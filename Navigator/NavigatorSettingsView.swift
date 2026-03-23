import Aesthetics
import AppKit
import BrowserSidebar
import Vendors

enum NavigatorSettingsInterfaceIdentifier {
	static let closeWindowButton = NSUserInterfaceItemIdentifier("navigator-settings-close-window-button")
	static let inactiveMiddleWindowButton = NSUserInterfaceItemIdentifier(
		"navigator-settings-inactive-middle-window-button"
	)
	static let inactiveTrailingWindowButton = NSUserInterfaceItemIdentifier(
		"navigator-settings-inactive-trailing-window-button"
	)
	static let defaultBrowserButton = NSUserInterfaceItemIdentifier("navigator-settings-default-browser-button")
	static let automaticUpdatesCheckbox = NSUserInterfaceItemIdentifier("navigator-settings-automatic-updates-checkbox")
	static let importChromeButton = NSUserInterfaceItemIdentifier("navigator-settings-import-chrome-button")
	static let importArcButton = NSUserInterfaceItemIdentifier("navigator-settings-import-arc-button")
	static let importSafariButton = NSUserInterfaceItemIdentifier("navigator-settings-import-safari-button")
	static let openImportedBookmarksButton = NSUserInterfaceItemIdentifier(
		"navigator-settings-open-imported-bookmarks-button"
	)
	static let openImportedHistoryButton = NSUserInterfaceItemIdentifier(
		"navigator-settings-open-imported-history-button"
	)
	static let importStatusIndicator = NSUserInterfaceItemIdentifier("navigator-settings-import-status-indicator")
}

final class NavigatorSettingsView: DoubleStrokePanelView {
	private enum Layout {
		static let contentInset: CGFloat = 16
		static let windowControlsSpacing: CGFloat = 8
		static let windowControlsBottomSpacing: CGFloat = 12
		static let headerHeight: CGFloat = 42
		static let sectionIconPointSize: CGFloat = 24
		static let sectionBodySpacing: CGFloat = 8
		static let importStatusIndicatorSize: CGFloat = 8
		static let importStatusIndicatorSpacing: CGFloat = 8
	}

	private let viewModel: NavigatorSettingsViewModel

	private let windowControlsStackView = NSStackView()
	private let sectionHeaderStackView = NSStackView()
	private let sectionDivider = separator()
	private let sectionContentView = NSView()
	private let closeWindowButton = BrowserSidebarWindowControlButton(baseColor: .systemRed)
	private let inactiveMiddleWindowButton = BrowserSidebarWindowControlButton(baseColor: .systemGray)
	private let inactiveTrailingWindowButton = BrowserSidebarWindowControlButton(baseColor: .systemGray)

	private let accountPlaceholderLabel = NSTextField(
		wrappingLabelWithString: String(localized: .navigatorSettingsAccountPlaceholder)
	)
	private let defaultBrowserTitleLabel = NSTextField(labelWithString: "")
	private let defaultBrowserDescriptionLabel = NSTextField(wrappingLabelWithString: "")
	private let updatesTitleLabel = NSTextField(labelWithString: "")
	private let updatesDescriptionLabel = NSTextField(wrappingLabelWithString: "")
	private let browserImportTitleLabel = NSTextField(labelWithString: "")
	private let browserImportDescriptionLabel = NSTextField(wrappingLabelWithString: "")
	private let importSummaryLabel = NSTextField(wrappingLabelWithString: "")
	private let importStatusIndicatorView = NSView()
	private lazy var defaultBrowserButton: NSButton = {
		let button = NSButton(title: "", target: self, action: #selector(handleDefaultBrowserButtonPress(_:)))
		button.translatesAutoresizingMaskIntoConstraints = false
		button.identifier = NavigatorSettingsInterfaceIdentifier.defaultBrowserButton
		button.bezelStyle = .rounded
		button.setButtonType(.momentaryPushIn)
		return button
	}()

	private lazy var automaticUpdatesCheckbox: NSButton = {
		let button = NSButton(
			checkboxWithTitle: "",
			target: self,
			action: #selector(handleAutomaticUpdatesCheckboxToggle(_:))
		)
		button.translatesAutoresizingMaskIntoConstraints = false
		button.identifier = NavigatorSettingsInterfaceIdentifier.automaticUpdatesCheckbox
		button.allowsMixedState = false
		return button
	}()

	private lazy var importChromeButton: NSButton = makeActionButton(
		identifier: NavigatorSettingsInterfaceIdentifier.importChromeButton,
		action: #selector(handleImportChromeButtonPress(_:))
	)

	private lazy var importArcButton: NSButton = makeActionButton(
		identifier: NavigatorSettingsInterfaceIdentifier.importArcButton,
		action: #selector(handleImportArcButtonPress(_:))
	)

	private lazy var importSafariButton: NSButton = makeActionButton(
		identifier: NavigatorSettingsInterfaceIdentifier.importSafariButton,
		action: #selector(handleImportSafariButtonPress(_:))
	)

	private lazy var openImportedBookmarksButton: NSButton = makeActionButton(
		identifier: NavigatorSettingsInterfaceIdentifier.openImportedBookmarksButton,
		action: #selector(handleOpenImportedBookmarksButtonPress(_:))
	)

	private lazy var openImportedHistoryButton: NSButton = makeActionButton(
		identifier: NavigatorSettingsInterfaceIdentifier.openImportedHistoryButton,
		action: #selector(handleOpenImportedHistoryButtonPress(_:))
	)

	private let versionValueLabel = NSTextField(labelWithString: "")
	private let bundleIdentifierValueLabel = NSTextField(labelWithString: "")

	private var sectionButtons = [NavigatorSettingsSection: NSButton]()
	private var sectionContentBySection = [NavigatorSettingsSection: NSView]()
	private weak var activeSectionContent: NSView?
	private var importStatusIndicatorWidthConstraint: NSLayoutConstraint?
	private var importSummaryLeadingConstraint: NSLayoutConstraint?

	init(viewModel: NavigatorSettingsViewModel, cornerRadius: CGFloat = 8) {
		self.viewModel = viewModel
		super.init(
			frame: NSRect(origin: .zero, size: NavigatorSettingsWindow.contentSize),
			fillColor: Asset.Colors.background.color,
			cornerRadius: cornerRadius
		)
		setupUI()
		refresh()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	private func setupUI() {
		configureLabels()
		configureWindowControls()
		configureSectionHeader()
		configureSectionContentViews()
		configureLayout()
		applyResolvedColors()
	}

	override func viewDidChangeEffectiveAppearance() {
		super.viewDidChangeEffectiveAppearance()
		closeWindowButton.refreshAppearance()
		inactiveMiddleWindowButton.refreshAppearance()
		inactiveTrailingWindowButton.refreshAppearance()
		applyResolvedColors()
	}

	func refresh() {
		versionValueLabel.stringValue = viewModel.versionDescription
		bundleIdentifierValueLabel.stringValue = viewModel.bundleIdentifier
		refreshGeneralSection()
		applySelectedSection()
		applyResolvedColors()
	}

	private func applyResolvedColors() {
		layer?.backgroundColor = resolvedFillColor.cgColor
		accountPlaceholderLabel.textColor = NSColor.secondaryLabelColor
		defaultBrowserDescriptionLabel.textColor = NSColor.secondaryLabelColor
		browserImportDescriptionLabel.textColor = NSColor.secondaryLabelColor
		importSummaryLabel.textColor = viewModel.showsImportError
			? resolvedColor(.systemRed)
			: NSColor.secondaryLabelColor
		refreshSectionButtonStyle()
	}

	private func configureLabels() {
		accountPlaceholderLabel.font = .systemFont(ofSize: 13, weight: .regular)
		accountPlaceholderLabel.maximumNumberOfLines = 0
		accountPlaceholderLabel.lineBreakMode = .byWordWrapping

		defaultBrowserTitleLabel.font = .systemFont(ofSize: 13, weight: .medium)
		defaultBrowserTitleLabel.lineBreakMode = .byTruncatingTail

		defaultBrowserDescriptionLabel.font = .systemFont(ofSize: 13, weight: .regular)
		defaultBrowserDescriptionLabel.maximumNumberOfLines = 0
		defaultBrowserDescriptionLabel.lineBreakMode = .byWordWrapping

		updatesTitleLabel.font = .systemFont(ofSize: 13, weight: .medium)
		updatesTitleLabel.lineBreakMode = .byTruncatingTail

		updatesDescriptionLabel.font = .systemFont(ofSize: 13, weight: .regular)
		updatesDescriptionLabel.maximumNumberOfLines = 0
		updatesDescriptionLabel.lineBreakMode = .byWordWrapping

		browserImportTitleLabel.font = .systemFont(ofSize: 13, weight: .medium)
		browserImportTitleLabel.lineBreakMode = .byTruncatingTail

		browserImportDescriptionLabel.font = .systemFont(ofSize: 13, weight: .regular)
		browserImportDescriptionLabel.maximumNumberOfLines = 0
		browserImportDescriptionLabel.lineBreakMode = .byWordWrapping

		importSummaryLabel.font = .systemFont(ofSize: 13, weight: .regular)
		importSummaryLabel.translatesAutoresizingMaskIntoConstraints = false
		importSummaryLabel.maximumNumberOfLines = 0
		importSummaryLabel.lineBreakMode = .byWordWrapping
		importStatusIndicatorView.translatesAutoresizingMaskIntoConstraints = false
		importStatusIndicatorView.identifier = NavigatorSettingsInterfaceIdentifier.importStatusIndicator
		importStatusIndicatorView.wantsLayer = true
		importStatusIndicatorView.layer?.cornerRadius = Layout.importStatusIndicatorSize / 2

		versionValueLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
		versionValueLabel.alignment = .right
		versionValueLabel.lineBreakMode = .byTruncatingMiddle

		bundleIdentifierValueLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
		bundleIdentifierValueLabel.alignment = .right
		bundleIdentifierValueLabel.lineBreakMode = .byTruncatingMiddle
	}

	private func configureSectionHeader() {
		sectionHeaderStackView.translatesAutoresizingMaskIntoConstraints = false
		sectionHeaderStackView.orientation = .horizontal
		sectionHeaderStackView.alignment = .centerY
		sectionHeaderStackView.distribution = .fillEqually
		sectionHeaderStackView.spacing = 8

		for section in NavigatorSettingsSection.allCases {
			let button = NSButton(title: section.title, target: self, action: #selector(handleSectionSelection(_:)))
			button.translatesAutoresizingMaskIntoConstraints = false
			button.tag = section.rawValue
			button.setButtonType(.momentaryChange)
			button.image = section.iconImage(
				isSelected: section == viewModel.selectedSection,
				pointSize: Layout.sectionIconPointSize
			)
			button.imagePosition = .imageAbove
			button.bezelStyle = .regularSquare
			button.isBordered = false
			button.focusRingType = .none
			button.contentTintColor = sectionButtonColor(isSelected: section == viewModel.selectedSection)
			button.font = .systemFont(ofSize: 13, weight: .medium)
			if let cell = button.cell as? NSButtonCell {
				cell.highlightsBy = []
				cell.showsStateBy = []
			}
			sectionButtons[section] = button
			sectionHeaderStackView.addArrangedSubview(button)
		}

		sectionDivider.translatesAutoresizingMaskIntoConstraints = false
	}

	private func configureWindowControls() {
		windowControlsStackView.translatesAutoresizingMaskIntoConstraints = false
		windowControlsStackView.orientation = .horizontal
		windowControlsStackView.alignment = .centerY
		windowControlsStackView.spacing = Layout.windowControlsSpacing

		configureWindowControlButton(
			closeWindowButton,
			identifier: NavigatorSettingsInterfaceIdentifier.closeWindowButton,
			accessibilityLabel: String(
				localized: "navigator.settings.window.closeAction",
				defaultValue: "Close Window",
				comment: "Accessibility label and help text for the settings window close control."
			),
			action: #selector(handleCloseWindowButtonPress(_:))
		)
		configureWindowControlButton(
			inactiveMiddleWindowButton,
			identifier: NavigatorSettingsInterfaceIdentifier.inactiveMiddleWindowButton
		)
		configureWindowControlButton(
			inactiveTrailingWindowButton,
			identifier: NavigatorSettingsInterfaceIdentifier.inactiveTrailingWindowButton
		)

		[
			closeWindowButton,
			inactiveMiddleWindowButton,
			inactiveTrailingWindowButton,
		].forEach(windowControlsStackView.addArrangedSubview(_:))
	}

	private func configureSectionContentViews() {
		sectionContentBySection[.general] = makeGeneralSectionView()
		sectionContentBySection[.account] = makeAccountSectionView()
		sectionContentBySection[.colophon] = makeColophonSectionView()
	}

	private func configureLayout() {
		sectionContentView.translatesAutoresizingMaskIntoConstraints = false

		for subview in [windowControlsStackView, sectionHeaderStackView, sectionDivider, sectionContentView] {
			subview.translatesAutoresizingMaskIntoConstraints = false
			addSubview(subview)
		}

		NSLayoutConstraint.activate([
			windowControlsStackView.topAnchor.constraint(equalTo: topAnchor, constant: Layout.contentInset),
			windowControlsStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.contentInset),
			windowControlsStackView.heightAnchor.constraint(
				equalToConstant: BrowserSidebarWindowControlButton.controlDiameter
			),

			sectionHeaderStackView.topAnchor.constraint(
				equalTo: windowControlsStackView.bottomAnchor,
				constant: Layout.windowControlsBottomSpacing
			),
			sectionHeaderStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.contentInset),
			sectionHeaderStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.contentInset),
			sectionHeaderStackView.heightAnchor.constraint(equalToConstant: Layout.headerHeight),

			sectionDivider.topAnchor.constraint(equalTo: sectionHeaderStackView.bottomAnchor, constant: 12),
			sectionDivider.leadingAnchor.constraint(equalTo: leadingAnchor),
			sectionDivider.trailingAnchor.constraint(equalTo: trailingAnchor),

			sectionContentView.topAnchor.constraint(equalTo: sectionDivider.bottomAnchor, constant: 12),
			sectionContentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.contentInset),
			sectionContentView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.contentInset),
			sectionContentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Layout.contentInset),
		])
	}

	private func configureWindowControlButton(
		_ button: BrowserSidebarWindowControlButton,
		identifier: NSUserInterfaceItemIdentifier,
		accessibilityLabel: String? = nil,
		action: Selector? = nil
	) {
		button.identifier = identifier
		button.translatesAutoresizingMaskIntoConstraints = false
		button.title = ""
		button.image = nil
		button.target = action == nil ? nil : self
		button.action = action
		button.toolTip = accessibilityLabel
		button.isEnabled = action != nil
		if let accessibilityLabel {
			button.setAccessibilityLabel(accessibilityLabel)
		}

		NSLayoutConstraint.activate([
			button.widthAnchor.constraint(equalToConstant: BrowserSidebarWindowControlButton.controlDiameter),
			button.heightAnchor.constraint(equalToConstant: BrowserSidebarWindowControlButton.controlDiameter),
		])
	}

	private func makeGeneralSectionView() -> NSView {
		let importButtonsStack = NSStackView(views: [importChromeButton, importArcButton, importSafariButton])
		importButtonsStack.translatesAutoresizingMaskIntoConstraints = false
		importButtonsStack.orientation = .horizontal
		importButtonsStack.alignment = .centerY
		importButtonsStack.spacing = 8

		let importActionsStack = NSStackView(views: [openImportedBookmarksButton, openImportedHistoryButton])
		importActionsStack.translatesAutoresizingMaskIntoConstraints = false
		importActionsStack.orientation = .horizontal
		importActionsStack.alignment = .centerY
		importActionsStack.spacing = 8

		let importSummaryContainer = NSView()
		importSummaryContainer.translatesAutoresizingMaskIntoConstraints = false
		importSummaryContainer.addSubview(importStatusIndicatorView)
		importSummaryContainer.addSubview(importSummaryLabel)

		let importSummaryLeadingConstraint = importSummaryLabel.leadingAnchor.constraint(
			equalTo: importStatusIndicatorView.trailingAnchor,
			constant: Layout.importStatusIndicatorSpacing
		)
		NSLayoutConstraint.activate([
			importStatusIndicatorView.leadingAnchor.constraint(equalTo: importSummaryContainer.leadingAnchor),
			importStatusIndicatorView.topAnchor.constraint(
				equalTo: importSummaryContainer.topAnchor,
				constant: 4
			),
			importStatusIndicatorView.heightAnchor.constraint(equalToConstant: Layout.importStatusIndicatorSize),
			importSummaryLabel.topAnchor.constraint(equalTo: importSummaryContainer.topAnchor),
			importSummaryLeadingConstraint,
			importSummaryLabel.trailingAnchor.constraint(equalTo: importSummaryContainer.trailingAnchor),
			importSummaryLabel.bottomAnchor.constraint(equalTo: importSummaryContainer.bottomAnchor),
		])
		let importStatusIndicatorWidthConstraint = importStatusIndicatorView.widthAnchor.constraint(
			equalToConstant: Layout.importStatusIndicatorSize
		)
		importStatusIndicatorWidthConstraint.isActive = true
		self.importStatusIndicatorWidthConstraint = importStatusIndicatorWidthConstraint
		self.importSummaryLeadingConstraint = importSummaryLeadingConstraint

		let stack = NSStackView()
		stack.translatesAutoresizingMaskIntoConstraints = false
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = Layout.sectionBodySpacing
		stack.addArrangedSubview(defaultBrowserTitleLabel)
		stack.addArrangedSubview(defaultBrowserDescriptionLabel)
		stack.addArrangedSubview(defaultBrowserButton)
		stack.setCustomSpacing(18, after: defaultBrowserButton)
		stack.addArrangedSubview(updatesTitleLabel)
		stack.addArrangedSubview(updatesDescriptionLabel)
		stack.addArrangedSubview(automaticUpdatesCheckbox)
		stack.setCustomSpacing(18, after: automaticUpdatesCheckbox)
		stack.addArrangedSubview(browserImportTitleLabel)
		stack.addArrangedSubview(browserImportDescriptionLabel)
		stack.addArrangedSubview(importButtonsStack)
		stack.addArrangedSubview(importSummaryContainer)
		stack.addArrangedSubview(importActionsStack)

		let container = NSView()
		container.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(stack)

		NSLayoutConstraint.activate([
			stack.topAnchor.constraint(equalTo: container.topAnchor),
			stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
		])

		return container
	}

	private func makeActionButton(
		identifier: NSUserInterfaceItemIdentifier,
		action: Selector
	) -> NSButton {
		let button = NSButton(title: "", target: self, action: action)
		button.translatesAutoresizingMaskIntoConstraints = false
		button.identifier = identifier
		button.bezelStyle = .rounded
		button.setButtonType(.momentaryPushIn)
		return button
	}

	private func makeAccountSectionView() -> NSView {
		accountPlaceholderLabel.translatesAutoresizingMaskIntoConstraints = false

		let container = NSView()
		container.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(accountPlaceholderLabel)

		NSLayoutConstraint.activate([
			accountPlaceholderLabel.topAnchor.constraint(equalTo: container.topAnchor),
			accountPlaceholderLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			accountPlaceholderLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			accountPlaceholderLabel.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
		])

		return container
	}

	private func makeColophonSectionView() -> NSView {
		let versionRow = makeMetadataRow(
			title: String(localized: .navigatorSettingsAboutVersionTitle),
			valueLabel: versionValueLabel
		)
		let bundleIdentifierRow = makeMetadataRow(
			title: String(localized: .navigatorSettingsAboutBundleIdentifierTitle),
			valueLabel: bundleIdentifierValueLabel
		)

		let stack = NSStackView()
		stack.translatesAutoresizingMaskIntoConstraints = false
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = 10
		stack.addArrangedSubview(versionRow)
		stack.addArrangedSubview(bundleIdentifierRow)

		let container = NSView()
		container.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(stack)

		NSLayoutConstraint.activate([
			stack.topAnchor.constraint(equalTo: container.topAnchor),
			stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
		])

		return container
	}

	private func makeMetadataRow(title: String, valueLabel: NSTextField) -> NSView {
		let titleLabel = NSTextField(labelWithString: title)
		titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
		titleLabel.lineBreakMode = .byTruncatingTail

		let row = NSStackView()
		row.translatesAutoresizingMaskIntoConstraints = false
		row.orientation = .horizontal
		row.alignment = .firstBaseline
		row.distribution = .fill
		row.spacing = 12
		row.addArrangedSubview(titleLabel)
		row.addArrangedSubview(valueLabel)

		valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

		return row
	}

	private func applySelectedSection() {
		refreshSectionButtonStyle()
		let selectedView = sectionContentBySection[viewModel.selectedSection]!
		guard activeSectionContent !== selectedView else {
			return
		}

		activeSectionContent?.removeFromSuperview()
		selectedView.translatesAutoresizingMaskIntoConstraints = false
		sectionContentView.addSubview(selectedView)
		NSLayoutConstraint.activate([
			selectedView.topAnchor.constraint(equalTo: sectionContentView.topAnchor),
			selectedView.leadingAnchor.constraint(equalTo: sectionContentView.leadingAnchor),
			selectedView.trailingAnchor.constraint(equalTo: sectionContentView.trailingAnchor),
			selectedView.bottomAnchor.constraint(equalTo: sectionContentView.bottomAnchor),
		])
		activeSectionContent = selectedView
	}

	private func refreshSectionButtonStyle() {
		for (section, button) in sectionButtons {
			let isSelected = section == viewModel.selectedSection
			let baseColor = sectionButtonColor(isSelected: isSelected)
			button.state = isSelected ? .on : .off
			button.image = section.iconImage(isSelected: isSelected, pointSize: Layout.sectionIconPointSize)
			button.contentTintColor = baseColor
			button.attributedTitle = NSAttributedString(
				string: section.title,
				attributes: [
					.font: NSFont.systemFont(ofSize: 13, weight: .medium),
					.foregroundColor: baseColor,
				]
			)
		}
	}

	private func refreshGeneralSection() {
		defaultBrowserTitleLabel.stringValue = viewModel.defaultBrowserTitle
		defaultBrowserDescriptionLabel.stringValue = viewModel.defaultBrowserDescription
		defaultBrowserButton.title = viewModel.defaultBrowserActionTitle
		defaultBrowserButton.isEnabled = viewModel.canSetAsDefaultBrowser
		updatesTitleLabel.stringValue = viewModel.updatesTitle
		updatesDescriptionLabel.stringValue = viewModel.updatesDescription
		automaticUpdatesCheckbox.title = viewModel.automaticallyCheckForUpdatesTitle
		automaticUpdatesCheckbox.state = viewModel.automaticallyChecksForUpdates ? .on : .off
		browserImportTitleLabel.stringValue = viewModel.browserImportTitle
		browserImportDescriptionLabel.stringValue = viewModel.browserImportDescription
		importChromeButton.title = viewModel.importChromeActionTitle
		importChromeButton.isEnabled = viewModel.isImporting == false
		importArcButton.title = viewModel.importArcActionTitle
		importArcButton.isEnabled = viewModel.isImporting == false
		importSafariButton.title = viewModel.importSafariActionTitle
		importSafariButton.isEnabled = viewModel.isImporting == false
		importSummaryLabel.stringValue = viewModel.importSummaryText
		applyImportStatusIndicator()
		openImportedBookmarksButton.title = viewModel.openImportedBookmarksActionTitle
		openImportedBookmarksButton.isEnabled = viewModel.canOpenImportedBookmarks
		openImportedHistoryButton.title = viewModel.openImportedHistoryActionTitle
		openImportedHistoryButton.isEnabled = viewModel.canOpenImportedHistory
	}

	private func applyImportStatusIndicator() {
		guard let indicatorState = viewModel.browserImportIndicatorState else {
			importStatusIndicatorView.isHidden = true
			importStatusIndicatorWidthConstraint?.constant = 0
			importSummaryLeadingConstraint?.constant = 0
			importStatusIndicatorView.layer?.backgroundColor = nil
			return
		}

		importStatusIndicatorView.isHidden = false
		importStatusIndicatorWidthConstraint?.constant = Layout.importStatusIndicatorSize
		importSummaryLeadingConstraint?.constant = Layout.importStatusIndicatorSpacing
		let indicatorColor: NSColor = switch indicatorState {
		case .importing:
			resolvedColor(.systemOrange)
		case .completed:
			resolvedColor(.systemGreen)
		}
		importStatusIndicatorView.layer?.backgroundColor = indicatorColor.cgColor
	}

	private func sectionButtonColor(isSelected: Bool) -> NSColor {
		let color = isSelected
			? Asset.Colors.accent.color
			: Asset.Colors.textPrimaryColor.color
		return resolvedColor(color)
	}

	@objc private func handleSectionSelection(_ sender: NSButton) {
		guard let section = NavigatorSettingsSection(rawValue: sender.tag) else {
			return
		}
		selectSection(section)
	}

	private func selectSection(_ section: NavigatorSettingsSection) {
		guard viewModel.selectedSection != section else {
			return
		}
		viewModel.selectedSection = section
		applySelectedSection()
	}

	@objc private func handleDefaultBrowserButtonPress(_: NSButton) {
		Task { @MainActor in
			await viewModel.setAsDefaultBrowser()
			refresh()
		}
	}

	@objc private func handleAutomaticUpdatesCheckboxToggle(_ sender: NSButton) {
		viewModel.setAutomaticallyChecksForUpdates(sender.state == .on)
		refresh()
	}

	@objc private func handleCloseWindowButtonPress(_: NSButton) {
		window?.close()
	}

	@objc private func handleImportChromeButtonPress(_: NSButton) {
		viewModel.importFromChrome()
		refresh()
	}

	@objc private func handleImportArcButtonPress(_: NSButton) {
		viewModel.importFromArc()
		refresh()
	}

	@objc private func handleImportSafariButtonPress(_: NSButton) {
		viewModel.importFromSafari()
		refresh()
	}

	@objc private func handleOpenImportedBookmarksButtonPress(_: NSButton) {
		viewModel.openImportedBookmarks()
		refresh()
	}

	@objc private func handleOpenImportedHistoryButtonPress(_: NSButton) {
		viewModel.openImportedHistory()
		refresh()
	}

	private func resolvedColor(_ color: NSColor) -> NSColor {
		var outputColor = color
		effectiveAppearance.performAsCurrentDrawingAppearance {
			outputColor = Self.resolvedDrawingColor(from: color)
		}
		return outputColor
	}

	static func resolvedDrawingColor(
		from color: NSColor,
		resolveCGColor: (NSColor) -> NSColor? = { candidate in
			NSColor(cgColor: candidate.cgColor)
		}
	) -> NSColor {
		resolveCGColor(color) ?? color
	}
}

extension NavigatorSettingsSection {
	var title: String {
		switch self {
		case .general:
			return String(localized: .navigatorSettingsSectionGeneral)
		case .camera:
			return String(localized: "navigator.settings.section.camera")
		case .account:
			return String(localized: .navigatorSettingsSectionAccount)
		case .colophon:
			return String(localized: .navigatorSettingsSectionColophon)
		}
	}

	func iconImage(
		isSelected: Bool,
		pointSize: CGFloat,
		imageNamed: (String) -> NSImage? = { assetName in
			NSImage(named: NSImage.Name(assetName))
		},
		systemSymbolImage: (String, String) -> NSImage? = { symbolName, accessibilityDescription in
			NSImage(
				systemSymbolName: symbolName,
				accessibilityDescription: accessibilityDescription
			)
		}
	) -> NSImage? {
		if isSelected, let filledIconAssetName, let filledCandidate = imageNamed(filledIconAssetName) {
			return resizedImage(from: filledCandidate, pointSize: pointSize)
		}

		if let regularCandidate = imageNamed(regularIconAssetName) {
			return resizedImage(from: regularCandidate, pointSize: pointSize)
		}

		let image = systemSymbolImage(fallbackSymbolName(isSelected: isSelected), title)
		return image?.withSymbolConfiguration(.init(pointSize: pointSize, weight: .medium))
	}

	static func fallbackSymbolName(for section: Self, isSelected: Bool) -> String {
		section.fallbackSymbolName(isSelected: isSelected)
	}

	static func resizedImage(from image: NSImage, pointSize: CGFloat) -> NSImage {
		sectionResizeImage(image, pointSize: pointSize)
	}

	private static func sectionResizeImage(_ image: NSImage, pointSize: CGFloat) -> NSImage {
		let resized = NSImage(size: NSSize(width: pointSize, height: pointSize))
		resized.lockFocus()
		image.draw(
			in: NSRect(origin: .zero, size: resized.size),
			from: NSRect(origin: .zero, size: image.size),
			operation: .copy,
			fraction: 1
		)
		resized.unlockFocus()
		resized.isTemplate = true
		return resized
	}

	private func resizedImage(from image: NSImage, pointSize: CGFloat) -> NSImage {
		Self.sectionResizeImage(image, pointSize: pointSize)
	}

	private func fallbackSymbolName(isSelected: Bool) -> String {
		switch self {
		case .general:
			return "slider.horizontal.3"
		case .camera:
			return isSelected ? "camera.fill" : "camera"
		case .account:
			return isSelected ? "person.crop.circle.fill" : "person.crop.circle"
		case .colophon:
			return isSelected ? "book.closed.fill" : "book.closed"
		}
	}
}

private extension NavigatorSettingsSection {
	var regularIconAssetName: String {
		switch self {
		case .general:
			return "navigator-settings-general"
		case .camera:
			return "navigator-settings-camera"
		case .account:
			return "navigator-settings-account"
		case .colophon:
			return "navigator-settings-colophon"
		}
	}

	private var filledIconAssetName: String? {
		switch self {
		case .general:
			return "navigator-settings-general-fill"
		case .camera:
			return "navigator-settings-camera-fill"
		case .account:
			return "navigator-settings-account-fill"
		case .colophon:
			return nil
		}
	}
}
