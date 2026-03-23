import AppKit
import BrowserCameraKit
import ModelKit
import Observation
import Vendors

public enum BrowserCameraControlsPresentation {
	case popover
	case settings
}

public final class BrowserCameraMenuBarView: NSView {
	private enum Layout {
		static let popoverPreviewHeight: CGFloat = 112
		static let settingsPreviewHeight: CGFloat = 88
		static let settingsMaxContentWidth: CGFloat = 360
		static let popoverPreviewCornerRadius: CGFloat = 10
		static let settingsPreviewCornerRadius: CGFloat = 8
		static let popoverHorizontalPadding: CGFloat = 14
		static let settingsHorizontalPadding: CGFloat = 0
	}

	private let viewModel: BrowserCameraMenuBarViewModel
	private let localizationBundle: Bundle
	private let presentation: BrowserCameraControlsPresentation
	private let titleLabel = NSTextField(labelWithString: "")
	private let routingToggle = NSButton(checkboxWithTitle: "", target: nil, action: nil)
	private let previewToggle = NSButton(checkboxWithTitle: "", target: nil, action: nil)
	private let horizontalFlipToggle = NSButton(checkboxWithTitle: "", target: nil, action: nil)
	private let refreshSourcesButton = NSButton(title: "", target: nil, action: nil)
	private let sourceLabel = NSTextField(labelWithString: "")
	private let sourcePopUpButton = NSPopUpButton()
	private let presetLabel = NSTextField(labelWithString: "")
	private let presetPopUpButton = NSPopUpButton()
	private let grainLabel = NSTextField(labelWithString: "")
	private let grainPopUpButton = NSPopUpButton()
	private let statusLabel = NSTextField(wrappingLabelWithString: "")
	private let diagnosticsLabel = NSTextField(wrappingLabelWithString: "")
	private let previewContainer = NSView()
	private let previewImageView = BrowserCameraPreviewView()
	private let previewPlaceholderLabel = NSTextField(wrappingLabelWithString: "")
	private var previewObservationRefreshTask: Task<Void, Never>?
	private var previewAspectRatioConstraint: NSLayoutConstraint?

	public init(viewModel: BrowserCameraMenuBarViewModel) {
		self.presentation = .popover
		self.localizationBundle = .module
		self.viewModel = viewModel
		super.init(frame: .zero)
		setupUI()
		viewModel.addChangeObserver { [weak self] in
			self?.refreshFromViewModel()
		}
		refreshFromViewModel()
		startObservingPreviewFrame()
	}

	public init(
		viewModel: BrowserCameraMenuBarViewModel,
		presentation: BrowserCameraControlsPresentation
	) {
		self.presentation = presentation
		self.localizationBundle = .module
		self.viewModel = viewModel
		super.init(frame: .zero)
		setupUI()
		viewModel.addChangeObserver { [weak self] in
			self?.refreshFromViewModel()
		}
		refreshFromViewModel()
		startObservingPreviewFrame()
	}

	init(
		viewModel: BrowserCameraMenuBarViewModel,
		localizationBundle: Bundle,
		presentation: BrowserCameraControlsPresentation = .popover
	) {
		self.presentation = presentation
		self.localizationBundle = localizationBundle
		self.viewModel = viewModel
		super.init(frame: .zero)
		setupUI()
		viewModel.addChangeObserver { [weak self] in
			self?.refreshFromViewModel()
		}
		refreshFromViewModel()
		startObservingPreviewFrame()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	deinit {
		previewObservationRefreshTask?.cancel()
	}

	private func setupUI() {
		wantsLayer = true
		switch presentation {
		case .popover:
			layer?.cornerRadius = 12
			layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
		case .settings:
			layer?.cornerRadius = 0
			layer?.backgroundColor = NSColor.clear.cgColor
		}

		titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
		titleLabel.stringValue = localized(.cameraSectionTitle)

		configureCheckbox(
			routingToggle,
			title: localized(.cameraRoutingToggle),
			action: #selector(didToggleRouting(_:))
		)
		configureCheckbox(
			previewToggle,
			title: localized(.cameraPreviewToggle),
			action: #selector(didTogglePreview(_:))
		)
		configureCheckbox(
			horizontalFlipToggle,
			title: localized(.cameraHorizontalFlipToggle),
			action: #selector(didToggleHorizontalFlip(_:))
		)

		refreshSourcesButton.title = localized(.cameraRefreshSourcesAction)
		refreshSourcesButton.target = self
		refreshSourcesButton.action = #selector(didTapRefreshSources)
		refreshSourcesButton.identifier = InterfaceIdentifier.refreshSourcesButton

		sourceLabel.font = .preferredFont(forTextStyle: .subheadline)
		sourceLabel.stringValue = localized(.cameraSourceLabel)
		sourcePopUpButton.target = self
		sourcePopUpButton.action = #selector(didChangeSource(_:))
		sourcePopUpButton.identifier = InterfaceIdentifier.sourcePopUpButton

		presetLabel.font = .preferredFont(forTextStyle: .subheadline)
		presetLabel.stringValue = localized(.cameraPresetLabel)
		presetPopUpButton.target = self
		presetPopUpButton.action = #selector(didChangePreset(_:))
		presetPopUpButton.identifier = InterfaceIdentifier.presetPopUpButton

		grainLabel.font = .preferredFont(forTextStyle: .subheadline)
		grainLabel.stringValue = localized(.cameraGrainLabel)
		grainPopUpButton.target = self
		grainPopUpButton.action = #selector(didChangeGrain(_:))
		grainPopUpButton.identifier = InterfaceIdentifier.grainPopUpButton

		statusLabel.identifier = InterfaceIdentifier.statusLabel
		statusLabel.font = .preferredFont(forTextStyle: .caption1)
		statusLabel.maximumNumberOfLines = 0

		diagnosticsLabel.identifier = InterfaceIdentifier.diagnosticsLabel
		diagnosticsLabel.font = .preferredFont(forTextStyle: .caption1)
		diagnosticsLabel.maximumNumberOfLines = 0

		previewContainer.wantsLayer = true
		previewContainer.layer?.cornerRadius = previewCornerRadius
		previewContainer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.08).cgColor

		previewImageView.identifier = InterfaceIdentifier.previewImageView
		previewPlaceholderLabel.identifier = InterfaceIdentifier.previewPlaceholderLabel
		previewPlaceholderLabel.font = .preferredFont(forTextStyle: .caption1)
		previewPlaceholderLabel.alignment = .center
		previewPlaceholderLabel.maximumNumberOfLines = 0
		previewPlaceholderLabel.textColor = .secondaryLabelColor

		let sourceRow = NSStackView(views: [sourceLabel, NSView(), sourcePopUpButton])
		sourceRow.orientation = .horizontal
		sourceRow.alignment = .centerY
		sourceRow.spacing = 8

		let presetRow = NSStackView(views: [presetLabel, NSView(), presetPopUpButton])
		presetRow.orientation = .horizontal
		presetRow.alignment = .centerY
		presetRow.spacing = 8

		let grainRow = NSStackView(views: [grainLabel, NSView(), grainPopUpButton])
		grainRow.orientation = .horizontal
		grainRow.alignment = .centerY
		grainRow.spacing = 8

		let toggleRow = NSStackView(views: [
			routingToggle,
			previewToggle,
			horizontalFlipToggle,
			NSView(),
			refreshSourcesButton,
		])
		toggleRow.orientation = .horizontal
		toggleRow.alignment = .centerY
		toggleRow.spacing = 10

		let stackViews: [NSView] = switch presentation {
		case .popover:
			[titleLabel, toggleRow, sourceRow, presetRow, grainRow, statusLabel, diagnosticsLabel, previewContainer]
		case .settings:
			[toggleRow, sourceRow, presetRow, grainRow, statusLabel, diagnosticsLabel, previewContainer]
		}
		let contentStack = NSStackView(views: stackViews)
		contentStack.translatesAutoresizingMaskIntoConstraints = false
		contentStack.orientation = .vertical
		contentStack.alignment = .leading
		contentStack.spacing = 10

		addSubview(contentStack)
		previewContainer.translatesAutoresizingMaskIntoConstraints = false
		previewImageView.translatesAutoresizingMaskIntoConstraints = false
		previewPlaceholderLabel.translatesAutoresizingMaskIntoConstraints = false
		previewContainer.addSubview(previewImageView)
		previewContainer.addSubview(previewPlaceholderLabel)

		var constraints = [
			contentStack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
			contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
			sourcePopUpButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 144),
			presetPopUpButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 144),
			grainPopUpButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 144),
			previewContainer.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
			previewImageView.topAnchor.constraint(equalTo: previewContainer.topAnchor),
			previewImageView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
			previewImageView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
			previewImageView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),
			previewPlaceholderLabel.centerXAnchor.constraint(equalTo: previewContainer.centerXAnchor),
			previewPlaceholderLabel.centerYAnchor.constraint(equalTo: previewContainer.centerYAnchor),
			previewPlaceholderLabel.leadingAnchor.constraint(
				greaterThanOrEqualTo: previewContainer.leadingAnchor,
				constant: 12
			),
			previewPlaceholderLabel.trailingAnchor.constraint(
				lessThanOrEqualTo: previewContainer.trailingAnchor,
				constant: -12
			),
		]
		let previewAspectRatioConstraint = previewContainer.heightAnchor.constraint(
			equalTo: previewContainer.widthAnchor,
			multiplier: defaultPreviewAspectRatio
		)
		self.previewAspectRatioConstraint = previewAspectRatioConstraint
		constraints.append(previewAspectRatioConstraint)

		switch presentation {
		case .popover:
			constraints.append(contentsOf: [
				contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalPadding),
				contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalPadding),
			])
		case .settings:
			constraints.append(contentsOf: [
				contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: horizontalPadding),
				contentStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -horizontalPadding),
				contentStack.centerXAnchor.constraint(equalTo: centerXAnchor),
				contentStack.widthAnchor.constraint(lessThanOrEqualToConstant: Layout.settingsMaxContentWidth),
			])
		}

		NSLayoutConstraint.activate(constraints)

		routingToggle.translatesAutoresizingMaskIntoConstraints = false
		previewToggle.translatesAutoresizingMaskIntoConstraints = false
		horizontalFlipToggle.translatesAutoresizingMaskIntoConstraints = false
		refreshSourcesButton.translatesAutoresizingMaskIntoConstraints = false
		sourceLabel.translatesAutoresizingMaskIntoConstraints = false
		sourcePopUpButton.translatesAutoresizingMaskIntoConstraints = false
		presetLabel.translatesAutoresizingMaskIntoConstraints = false
		presetPopUpButton.translatesAutoresizingMaskIntoConstraints = false
		grainLabel.translatesAutoresizingMaskIntoConstraints = false
		grainPopUpButton.translatesAutoresizingMaskIntoConstraints = false
		statusLabel.translatesAutoresizingMaskIntoConstraints = false
		diagnosticsLabel.translatesAutoresizingMaskIntoConstraints = false
	}

	private var horizontalPadding: CGFloat {
		switch presentation {
		case .popover:
			Layout.popoverHorizontalPadding
		case .settings:
			Layout.settingsHorizontalPadding
		}
	}

	private var previewHeight: CGFloat {
		switch presentation {
		case .popover:
			Layout.popoverPreviewHeight
		case .settings:
			Layout.settingsPreviewHeight
		}
	}

	private var defaultPreviewAspectRatio: CGFloat {
		previewHeight / Layout.settingsMaxContentWidth
	}

	private var previewCornerRadius: CGFloat {
		switch presentation {
		case .popover:
			Layout.popoverPreviewCornerRadius
		case .settings:
			Layout.settingsPreviewCornerRadius
		}
	}

	private func configureCheckbox(
		_ button: NSButton,
		title: String,
		action: Selector
	) {
		button.title = title
		button.target = self
		button.action = action
		button.contentTintColor = .labelColor
	}

	private func refreshFromViewModel() {
		routingToggle.state = viewModel.routingEnabled ? .on : .off
		previewToggle.state = viewModel.previewEnabled ? .on : .off
		horizontalFlipToggle.state = viewModel.prefersHorizontalFlip ? .on : .off
		rebuildSourceMenu()
		rebuildPresetMenu()
		rebuildGrainMenu()
		statusLabel.stringValue = resolvedStatusText()
		diagnosticsLabel.stringValue = resolvedDiagnosticsText()
		previewPlaceholderLabel.stringValue = resolvedPreviewPlaceholderText()

		refreshPreviewImage()
		sourcePopUpButton.isEnabled = !viewModel.availableSources.isEmpty
	}

	private func refreshPreviewImage() {
		let previewFrame = viewModel.previewEnabled ? viewModel.previewFrameUpdater.previewFrame : nil
		updatePreviewAspectRatio(using: previewFrame)
		previewImageView.previewFrame = previewFrame
		previewImageView.isHidden = previewFrame == nil
		previewPlaceholderLabel.isHidden = previewFrame != nil
	}

	private func updatePreviewAspectRatio(using previewFrame: CGImage?) {
		let multiplier: CGFloat = if let previewFrame, previewFrame.width > 0 {
			CGFloat(previewFrame.height) / CGFloat(previewFrame.width)
		}
		else {
			defaultPreviewAspectRatio
		}

		guard previewAspectRatioConstraint?.multiplier != multiplier else { return }
		if let previewAspectRatioConstraint {
			NSLayoutConstraint.deactivate([previewAspectRatioConstraint])
		}
		let replacementConstraint = previewContainer.heightAnchor.constraint(
			equalTo: previewContainer.widthAnchor,
			multiplier: multiplier
		)
		previewAspectRatioConstraint = replacementConstraint
		NSLayoutConstraint.activate([replacementConstraint])
		needsLayout = true
	}

	private func startObservingPreviewFrame() {
		withObservationTracking {
			_ = viewModel.previewFrameUpdater.previewFrame
		} onChange: { [weak self] in
			Task { @MainActor [weak self] in
				guard let self else { return }
				self.previewObservationRefreshTask?.cancel()
				self.refreshPreviewImage()
				self.startObservingPreviewFrame()
			}
		}
	}

	private func rebuildSourceMenu() {
		let selectedSourceID = viewModel.selectedSourceID
		let entries = [CameraMenuEntry(title: localized(.cameraSourceAutomaticOption), representedObject: nil)]
			+ viewModel.availableSources.map { source in
				CameraMenuEntry(
					title: sourceDisplayTitle(source),
					representedObject: source.id as NSString
				)
			}
		synchronizeMenu(for: sourcePopUpButton, with: entries)
		selectMenuItem(
			for: sourcePopUpButton,
			matchingRepresentedObject: selectedSourceID.map { $0 as NSString }
		)
	}

	private func rebuildPresetMenu() {
		let entries = viewModel.availableFilterPresets.map { preset in
			CameraMenuEntry(
				title: localizedPresetTitle(for: preset),
				representedObject: preset.rawValue as NSString
			)
		}
		synchronizeMenu(for: presetPopUpButton, with: entries)
		selectMenuItem(
			for: presetPopUpButton,
			matchingRepresentedObject: viewModel.selectedFilterPreset.rawValue as NSString
		)
	}

	private func rebuildGrainMenu() {
		let entries = viewModel.availableGrainPresences.map { grainPresence in
			CameraMenuEntry(
				title: localizedGrainTitle(for: grainPresence),
				representedObject: grainPresence.rawValue as NSString
			)
		}
		synchronizeMenu(for: grainPopUpButton, with: entries)
		selectMenuItem(
			for: grainPopUpButton,
			matchingRepresentedObject: viewModel.selectedGrainPresence.rawValue as NSString
		)
	}

	private func synchronizeMenu(
		for button: NSPopUpButton,
		with entries: [CameraMenuEntry]
	) {
		let currentItems = button.itemArray
		for index in 0..<entries.count {
			let entry = entries[index]
			if index < currentItems.count {
				let item = currentItems[index]
				item.title = entry.title
				item.representedObject = entry.representedObject
			}
			else {
				button.addItem(withTitle: entry.title)
				button.lastItem?.representedObject = entry.representedObject
			}
		}

		while button.numberOfItems > entries.count {
			button.removeItem(at: button.numberOfItems - 1)
		}
	}

	private func selectMenuItem(
		for button: NSPopUpButton,
		matchingRepresentedObject representedObject: Any?
	) {
		guard let representedObject else {
			if button.numberOfItems > 0 {
				button.selectItem(at: 0)
			}
			return
		}

		if let representedObject = representedObject as? NSObject,
		   let matchingItem = button.itemArray.first(where: {
		   	($0.representedObject as? NSObject) == representedObject
		   }) {
			button.select(matchingItem)
			return
		}

		if button.numberOfItems > 0 {
			button.selectItem(at: 0)
		}
	}

	private func sourceDisplayTitle(_ source: BrowserCameraSource) -> String {
		source.isDefault
			? String(format: localized(.cameraSourceDefaultFormat), source.name)
			: source.name
	}

	private func resolvedStatusText() -> String {
		if let lastErrorDescription = viewModel.lastErrorDescription,
		   lastErrorDescription.isEmpty == false {
			return lastErrorDescription
		}

		switch viewModel.lifecycleState {
		case .idle:
			return localized(.cameraStatusIdle)
		case .preparing:
			return localized(.cameraStatusPreparing)
		case .starting:
			return localized(.cameraStatusStarting)
		case .running:
			return localized(.cameraStatusRunning)
		case .stopping:
			return localized(.cameraStatusStopping)
		case .failed:
			return localized(.cameraStatusFailed)
		}
	}

	private func resolvedPreviewPlaceholderText() -> String {
		guard viewModel.previewEnabled else {
			return localized(.cameraPreviewPlaceholderDisabled)
		}
		guard !viewModel.availableSources.isEmpty else {
			return localized(.cameraPreviewPlaceholderUnavailable)
		}
		return localized(.cameraPreviewPlaceholderWaiting)
	}

	private func resolvedDiagnosticsText() -> String {
		BrowserCameraDiagnosticsFormatter.text(
			from: viewModel.debugSummary,
			routingFormat: localized(.cameraDiagnosticsRoutingFormat),
			consumersFormat: localized(.cameraDiagnosticsConsumersFormat),
			framesFormat: localized(.cameraDiagnosticsFramesFormat),
			pipelineFormat: localized(.cameraDiagnosticsPipelineFormat),
			browserTransportFormat: localized(.cameraDiagnosticsBrowserTransportFormat),
			latestEventFormat: localized(.cameraDiagnosticsLatestEventFormat),
			publisherFormat: localized(.cameraDiagnosticsPublisherFormat),
			unknownTransport: localized(.cameraDiagnosticsPublisherTransportUnknown),
			localizeDiagnosticEvent: localized,
			localizedRoutingAvailability: localizedRoutingAvailability,
			localizedPublisherState: localizedPublisherState,
			localizedPublisherTransport: localizedPublisherTransport
		)
	}

	private func localizedRoutingAvailability(
		_ availability: BrowserCameraManagedRoutingAvailability
	) -> String {
		switch availability {
		case .available:
			localized(.cameraDiagnosticsRoutingAvailabilityAvailable)
		case .routingDisabled:
			localized(.cameraDiagnosticsRoutingAvailabilityRoutingDisabled)
		case .navigatorPreferenceDisabled:
			localized(.cameraDiagnosticsRoutingAvailabilityNavigatorPreferenceDisabled)
		case .noAvailableSource:
			localized(.cameraDiagnosticsRoutingAvailabilityNoAvailableSource)
		case .directPhysicalCapture:
			localized(.cameraDiagnosticsRoutingAvailabilityDirectPhysicalCapture)
		case .sourceLost:
			localized(.cameraDiagnosticsRoutingAvailabilitySourceLost)
		case .degraded:
			localized(.cameraDiagnosticsRoutingAvailabilityDegraded)
		case .pipelineFallback:
			localized(.cameraDiagnosticsRoutingAvailabilityPipelineFallback)
		case .publisherUnavailable:
			localized(.cameraDiagnosticsRoutingAvailabilityPublisherUnavailable)
		}
	}

	private func localizedPublisherState(_ state: BrowserCameraVirtualPublisherState) -> String {
		switch state {
		case .notRequired:
			localized(.cameraDiagnosticsPublisherStateNotRequired)
		case .idle:
			localized(.cameraDiagnosticsPublisherStateIdle)
		case .installMissing:
			localized(.cameraDiagnosticsPublisherStateUnavailable)
		case .activating:
			localized(.cameraDiagnosticsPublisherStateStarting)
		case .starting:
			localized(.cameraDiagnosticsPublisherStateStarting)
		case .ready:
			localized(.cameraDiagnosticsPublisherStateReady)
		case .degraded:
			localized(.cameraDiagnosticsPublisherStateFailed)
		case .timedOut:
			localized(.cameraDiagnosticsPublisherStateFailed)
		case .stopping:
			localized(.cameraDiagnosticsPublisherStateStarting)
		case .updateRequired:
			localized(.cameraDiagnosticsPublisherStateUnavailable)
		case .unavailable:
			localized(.cameraDiagnosticsPublisherStateUnavailable)
		case .failed:
			localized(.cameraDiagnosticsPublisherStateFailed)
		}
	}

	private func localizedPublisherTransport(
		_ transportMode: BrowserCameraVirtualPublisherTransportMode
	) -> String {
		switch transportMode {
		case .inProcess:
			localized(.cameraDiagnosticsPublisherTransportInProcess)
		case .sharedMemory:
			localized(.cameraDiagnosticsPublisherTransportSharedMemory)
		case .copiedFrames:
			localized(.cameraDiagnosticsPublisherTransportCopiedFrames)
		}
	}

	private func localizedPresetTitle(for preset: BrowserCameraFilterPreset) -> String {
		switch preset {
		case .none:
			return localized(.cameraPresetNone)
		case .monochrome:
			return localized(.cameraPresetMononoke)
		case .dither:
			return localized(.cameraPresetDither)
		case .folia:
			return localized(.cameraPresetFolia)
		case .supergold:
			return localized(.cameraPresetSupergold)
		case .tonachrome:
			return localized(.cameraPresetTonachrome)
		case .bubblegum:
			return localized(.cameraPresetBubblegum)
		case .darkroom:
			return localized(.cameraPresetDarkroom)
		case .glowInTheDark:
			return localized(.cameraPresetGlowInTheDark)
		case .habenero:
			return localized(.cameraPresetHabenero)
		}
	}

	private func localizedGrainTitle(
		for grainPresence: BrowserCameraPipelineGrainPresence
	) -> String {
		switch grainPresence {
		case .none:
			return localized(.cameraGrainNone)
		case .normal:
			return localized(.cameraGrainNormal)
		case .high:
			return localized(.cameraGrainHigh)
		}
	}

	private func localized(_ key: LocalizationKey) -> String {
		let localizedValue = localizationBundle.localizedString(
			forKey: key.rawValue,
			value: key.rawValue,
			table: nil
		)
		return localizedValue == key.rawValue ? key.fallbackValue : localizedValue
	}

	private func localized(_ key: BrowserCameraDiagnosticLocalizationKey) -> String {
		let localizedValue = localizationBundle.localizedString(
			forKey: key.rawValue,
			value: key.rawValue,
			table: nil
		)
		let localeIdentifier = localizationBundle.preferredLocalizations.first ?? Locale.preferredLanguages.first
		return localizedValue == key.rawValue ? key.fallbackValue(localeIdentifier: localeIdentifier) : localizedValue
	}

	@objc private func didToggleRouting(_ sender: NSButton) {
		viewModel.setRoutingEnabled(sender.state == .on)
	}

	@objc private func didTogglePreview(_ sender: NSButton) {
		viewModel.setPreviewEnabled(sender.state == .on)
	}

	@objc private func didToggleHorizontalFlip(_ sender: NSButton) {
		viewModel.setPrefersHorizontalFlip(sender.state == .on)
	}

	@objc private func didTapRefreshSources() {
		viewModel.refreshAvailableDevices()
	}

	@objc private func didChangeSource(_ sender: NSPopUpButton) {
		let selectedSourceID = sender.selectedItem?.representedObject as? String
		viewModel.selectSource(id: selectedSourceID)
	}

	@objc private func didChangePreset(_ sender: NSPopUpButton) {
		guard let rawValue = sender.selectedItem?.representedObject as? String,
		      let preset = BrowserCameraFilterPreset(rawValue: rawValue)
		else {
			return
		}
		viewModel.selectFilterPreset(preset)
	}

	@objc private func didChangeGrain(_ sender: NSPopUpButton) {
		guard let rawValue = sender.selectedItem?.representedObject as? String,
		      let grainPresence = BrowserCameraPipelineGrainPresence(rawValue: rawValue)
		else {
			return
		}
		viewModel.selectGrainPresence(grainPresence)
	}

	func routingToggleButtonForTesting() -> NSButton {
		routingToggle
	}

	func previewToggleButtonForTesting() -> NSButton {
		previewToggle
	}

	func horizontalFlipToggleButtonForTesting() -> NSButton {
		horizontalFlipToggle
	}

	func refreshSourcesButtonForTesting() -> NSButton {
		refreshSourcesButton
	}

	func sourcePopUpButtonForTesting() -> NSPopUpButton {
		sourcePopUpButton
	}

	func presetPopUpButtonForTesting() -> NSPopUpButton {
		presetPopUpButton
	}

	func grainPopUpButtonForTesting() -> NSPopUpButton {
		grainPopUpButton
	}

	func statusLabelForTesting() -> NSTextField {
		statusLabel
	}

	func diagnosticsLabelForTesting() -> NSTextField {
		diagnosticsLabel
	}

	func previewImageViewForTesting() -> BrowserCameraPreviewView {
		previewImageView
	}

	func previewContainerForTesting() -> NSView {
		previewContainer
	}

	func previewPlaceholderLabelForTesting() -> NSTextField {
		previewPlaceholderLabel
	}
}

private enum InterfaceIdentifier {
	static let refreshSourcesButton = NSUserInterfaceItemIdentifier(
		"browserCameraMenuBar.refreshSourcesButton"
	)
	static let sourcePopUpButton = NSUserInterfaceItemIdentifier(
		"browserCameraMenuBar.sourcePopUpButton"
	)
	static let presetPopUpButton = NSUserInterfaceItemIdentifier(
		"browserCameraMenuBar.presetPopUpButton"
	)
	static let grainPopUpButton = NSUserInterfaceItemIdentifier(
		"browserCameraMenuBar.grainPopUpButton"
	)
	static let statusLabel = NSUserInterfaceItemIdentifier(
		"browserCameraMenuBar.statusLabel"
	)
	static let diagnosticsLabel = NSUserInterfaceItemIdentifier(
		"browserCameraMenuBar.diagnosticsLabel"
	)
	static let previewImageView = NSUserInterfaceItemIdentifier(
		"browserCameraMenuBar.previewImageView"
	)
	static let previewPlaceholderLabel = NSUserInterfaceItemIdentifier(
		"browserCameraMenuBar.previewPlaceholderLabel"
	)
}

private struct CameraMenuEntry {
	let title: String
	let representedObject: Any?
}

private enum LocalizationKey: String {
	case cameraPreviewPlaceholderDisabled = "browser.sidebar.camera.preview.placeholder.disabled"
	case cameraPreviewPlaceholderUnavailable = "browser.sidebar.camera.preview.placeholder.unavailable"
	case cameraPreviewPlaceholderWaiting = "browser.sidebar.camera.preview.placeholder.waiting"
	case cameraPresetFolia = "browser.sidebar.camera.preset.folia"
	case cameraGrainHigh = "browser.sidebar.camera.grain.high"
	case cameraHorizontalFlipToggle = "browser.sidebar.camera.toggle.horizontalFlip"
	case cameraGrainLabel = "browser.sidebar.camera.label.grain"
	case cameraGrainNone = "browser.sidebar.camera.grain.none"
	case cameraGrainNormal = "browser.sidebar.camera.grain.normal"
	case cameraPresetBubblegum = "browser.sidebar.camera.preset.bubblegum"
	case cameraPresetDarkroom = "browser.sidebar.camera.preset.darkroom"
	case cameraPresetDither = "browser.sidebar.camera.preset.dither"
	case cameraPresetLabel = "browser.sidebar.camera.label.preset"
	case cameraPresetGlowInTheDark = "browser.sidebar.camera.preset.glowInTheDark"
	case cameraPresetHabenero = "browser.sidebar.camera.preset.habenero"
	case cameraPresetMononoke = "browser.sidebar.camera.preset.mononoke"
	case cameraPresetNone = "browser.sidebar.camera.preset.none"
	case cameraPresetSupergold = "browser.sidebar.camera.preset.supergold"
	case cameraPresetTonachrome = "browser.sidebar.camera.preset.tonachrome"
	case cameraPreviewToggle = "browser.sidebar.camera.toggle.preview"
	case cameraRefreshSourcesAction = "browser.sidebar.camera.action.refreshSources"
	case cameraDiagnosticsConsumersFormat = "browser.sidebar.camera.diagnostics.consumers.format"
	case cameraDiagnosticsFramesFormat = "browser.sidebar.camera.diagnostics.frames.format"
	case cameraDiagnosticsPipelineFormat = "browser.sidebar.camera.diagnostics.pipeline.format"
	case cameraDiagnosticsBrowserTransportFormat = "browser.sidebar.camera.diagnostics.browserTransport.format"
	case cameraDiagnosticsLatestEventFormat = "browser.sidebar.camera.diagnostics.latestEvent.format"
	case cameraDiagnosticsPublisherFormat = "browser.sidebar.camera.diagnostics.publisher.format"
	case cameraDiagnosticsRoutingFormat = "browser.sidebar.camera.diagnostics.routing.format"
	case cameraDiagnosticsRoutingAvailabilityAvailable = "browser.sidebar.camera.diagnostics.routing.availability.available"
	case cameraDiagnosticsRoutingAvailabilityRoutingDisabled = "browser.sidebar.camera.diagnostics.routing.availability.routingDisabled"
	case cameraDiagnosticsRoutingAvailabilityNavigatorPreferenceDisabled = "browser.sidebar.camera.diagnostics.routing.availability.navigatorPreferenceDisabled"
	case cameraDiagnosticsRoutingAvailabilityNoAvailableSource = "browser.sidebar.camera.diagnostics.routing.availability.noAvailableSource"
	case cameraDiagnosticsRoutingAvailabilityDirectPhysicalCapture = "browser.sidebar.camera.diagnostics.routing.availability.directPhysicalCapture"
	case cameraDiagnosticsRoutingAvailabilitySourceLost = "browser.sidebar.camera.diagnostics.routing.availability.sourceLost"
	case cameraDiagnosticsRoutingAvailabilityDegraded = "browser.sidebar.camera.diagnostics.routing.availability.degraded"
	case cameraDiagnosticsRoutingAvailabilityPipelineFallback = "browser.sidebar.camera.diagnostics.routing.availability.pipelineFallback"
	case cameraDiagnosticsRoutingAvailabilityPublisherUnavailable = "browser.sidebar.camera.diagnostics.routing.availability.publisherUnavailable"
	case cameraDiagnosticsPublisherStateFailed = "browser.sidebar.camera.diagnostics.publisher.state.failed"
	case cameraDiagnosticsPublisherStateIdle = "browser.sidebar.camera.diagnostics.publisher.state.idle"
	case cameraDiagnosticsPublisherStateNotRequired = "browser.sidebar.camera.diagnostics.publisher.state.notRequired"
	case cameraDiagnosticsPublisherStateReady = "browser.sidebar.camera.diagnostics.publisher.state.ready"
	case cameraDiagnosticsPublisherStateStarting = "browser.sidebar.camera.diagnostics.publisher.state.starting"
	case cameraDiagnosticsPublisherStateUnavailable = "browser.sidebar.camera.diagnostics.publisher.state.unavailable"
	case cameraDiagnosticsPublisherTransportCopiedFrames = "browser.sidebar.camera.diagnostics.publisher.transport.copiedFrames"
	case cameraDiagnosticsPublisherTransportInProcess = "browser.sidebar.camera.diagnostics.publisher.transport.inProcess"
	case cameraDiagnosticsPublisherTransportSharedMemory = "browser.sidebar.camera.diagnostics.publisher.transport.sharedMemory"
	case cameraDiagnosticsPublisherTransportUnknown = "browser.sidebar.camera.diagnostics.publisher.transport.unknown"
	case cameraRoutingToggle = "browser.sidebar.camera.toggle.routing"
	case cameraSectionTitle = "browser.sidebar.camera.title"
	case cameraSourceAutomaticOption = "browser.sidebar.camera.source.automatic"
	case cameraSourceDefaultFormat = "browser.sidebar.camera.source.defaultFormat"
	case cameraSourceLabel = "browser.sidebar.camera.label.source"
	case cameraStatusFailed = "browser.sidebar.camera.status.failed"
	case cameraStatusIdle = "browser.sidebar.camera.status.idle"
	case cameraStatusPreparing = "browser.sidebar.camera.status.preparing"
	case cameraStatusRunning = "browser.sidebar.camera.status.running"
	case cameraStatusStarting = "browser.sidebar.camera.status.starting"
	case cameraStatusStopping = "browser.sidebar.camera.status.stopping"

	var fallbackValue: String {
		switch self {
		case .cameraPreviewPlaceholderDisabled:
			"Preview is off"
		case .cameraPreviewPlaceholderUnavailable:
			"No camera available"
		case .cameraPreviewPlaceholderWaiting:
			"Waiting for preview"
		case .cameraPresetFolia:
			"Folia"
		case .cameraGrainHigh:
			"High"
		case .cameraHorizontalFlipToggle:
			"Flip Horizontally"
		case .cameraGrainLabel:
			"Grain"
		case .cameraGrainNone:
			"None"
		case .cameraGrainNormal:
			"Normal"
		case .cameraPresetBubblegum:
			"Bubblegum"
		case .cameraPresetDarkroom:
			"Darkroom"
		case .cameraPresetDither:
			"Dither"
		case .cameraPresetLabel:
			"Preset"
		case .cameraPresetGlowInTheDark:
			"Glow in the Dark"
		case .cameraPresetHabenero:
			"Habenero"
		case .cameraPresetMononoke:
			"Mononoke"
		case .cameraPresetNone:
			"None"
		case .cameraPresetSupergold:
			"Supergold"
		case .cameraPresetTonachrome:
			"Tonachrome"
		case .cameraPreviewToggle:
			"Show Preview"
		case .cameraRefreshSourcesAction:
			"Refresh Cameras"
		case .cameraDiagnosticsConsumersFormat:
			"Live consumers: %d • Preview consumers: %d"
		case .cameraDiagnosticsFramesFormat:
			"Frames: %d • Dropped: %d • Avg latency: %@ ms"
		case .cameraDiagnosticsPipelineFormat:
			"Pipeline: %@ • %@ • %d filters"
		case .cameraDiagnosticsBrowserTransportFormat:
			"Browser transport: tabs %d • Tracks: %d • Fallback: %d"
		case .cameraDiagnosticsLatestEventFormat:
			"Latest event: %@"
		case .cameraDiagnosticsPublisherFormat:
			"Publisher: %@ • Transport: %@"
		case .cameraDiagnosticsRoutingFormat:
			"Routing: %@"
		case .cameraDiagnosticsRoutingAvailabilityAvailable:
			"Managed output available"
		case .cameraDiagnosticsRoutingAvailabilityRoutingDisabled:
			"Routing disabled"
		case .cameraDiagnosticsRoutingAvailabilityNavigatorPreferenceDisabled:
			"Navigator preference off"
		case .cameraDiagnosticsRoutingAvailabilityNoAvailableSource:
			"No camera source"
		case .cameraDiagnosticsRoutingAvailabilityDirectPhysicalCapture:
			"Direct physical capture"
		case .cameraDiagnosticsRoutingAvailabilitySourceLost:
			"Source lost (fail closed)"
		case .cameraDiagnosticsRoutingAvailabilityDegraded:
			"Degraded (fail closed)"
		case .cameraDiagnosticsRoutingAvailabilityPipelineFallback:
			"Pipeline unavailable (fail closed)"
		case .cameraDiagnosticsRoutingAvailabilityPublisherUnavailable:
			"Publisher unavailable (fail closed)"
		case .cameraDiagnosticsPublisherStateFailed:
			"Failed"
		case .cameraDiagnosticsPublisherStateIdle:
			"Idle"
		case .cameraDiagnosticsPublisherStateNotRequired:
			"Not required"
		case .cameraDiagnosticsPublisherStateReady:
			"Ready"
		case .cameraDiagnosticsPublisherStateStarting:
			"Starting"
		case .cameraDiagnosticsPublisherStateUnavailable:
			"Unavailable"
		case .cameraDiagnosticsPublisherTransportCopiedFrames:
			"Copied frames"
		case .cameraDiagnosticsPublisherTransportInProcess:
			"In-process"
		case .cameraDiagnosticsPublisherTransportSharedMemory:
			"Shared memory"
		case .cameraDiagnosticsPublisherTransportUnknown:
			"Unknown"
		case .cameraRoutingToggle:
			"Use Navigator Camera"
		case .cameraSectionTitle:
			"Navigator Camera"
		case .cameraSourceAutomaticOption:
			"Automatic"
		case .cameraSourceDefaultFormat:
			"%@ (Default)"
		case .cameraSourceLabel:
			"Source"
		case .cameraStatusFailed:
			"Camera failed"
		case .cameraStatusIdle:
			"Camera is idle"
		case .cameraStatusPreparing:
			"Preparing camera"
		case .cameraStatusRunning:
			"Camera is running"
		case .cameraStatusStarting:
			"Starting camera"
		case .cameraStatusStopping:
			"Stopping camera"
		}
	}
}
