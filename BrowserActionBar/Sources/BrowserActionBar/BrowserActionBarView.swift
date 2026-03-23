import Aesthetics
import AppKit
import Foundation
import Observation
import Vendors

public class BrowserActionBarWindow: NSWindow {
	override public var canBecomeKey: Bool {
		true
	}

	override public var canBecomeMain: Bool {
		true
	}
}

@MainActor
public final class BrowserActionBarView: BrowserActionBarWindow, NSTextFieldDelegate {
	private static let defaultWidth: CGFloat = 770
	private static let defaultHeight: CGFloat = 50
	private static let panelCornerRadius: CGFloat = 16
	private static let windowBorderWidth: CGFloat = 1
	private static let widthRatio: CGFloat = 0.7
	private static let verticalMargin: CGFloat = 120
	private static let queryFontScale: CGFloat = 1.2
	private static let iconLeadingInset: CGFloat = 20
	private static let iconTrailingSpacing: CGFloat = 8
	private static let iconSize: CGFloat = 16

	public var updateAnchorWindow: (() -> NSWindow?)?

	private let viewModel: BrowserActionBarViewModel
	private let contentContainerView = NSView()
	private let chromeView = NSView()
	private let leadingIconView = NSImageView()
	private let queryField = BrowserActionBarTextField()

	private var outsideMouseMonitors: [Any] = []
	private weak var lastParentWindow: NSWindow?
	private var isPanelVisible = false
	private var isSynchronizingFromViewModel = false
	private var lastAppliedPresentationSeed: UUID?
	private var lastAppliedMode: BrowserActionBarMode?
	private var shouldSelectQueryText = false
	private var currentLeadingIcon = BrowserActionBarLeadingIcon.search
	private var keyWindowProvider: () -> NSWindow? = { NSApp.keyWindow }
	private var isParentWindowKeyProvider: (NSWindow) -> Bool = { $0.isKeyWindow }
	private var makeParentWindowKeyHandler: (NSWindow) -> Void = { $0.makeKey() }
	private var localOutsideClickHandler: ((NSEvent) -> NSEvent)?
	private var globalOutsideClickHandler: ((NSPoint) -> Void)?
	private var localMonitorEventHandler: ((NSEvent) -> NSEvent?)?
	private var globalMonitorEventHandler: ((NSEvent) -> Void)?

	public init(viewModel: BrowserActionBarViewModel) {
		self.viewModel = viewModel

		super.init(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: Self.defaultWidth,
				height: Self.defaultHeight
			),
			styleMask: [.borderless, .titled, .fullSizeContentView],
			backing: .buffered,
			defer: false
		)

		contentContainerView.wantsLayer = true
		contentContainerView.layer?.backgroundColor = NSColor.clear.cgColor
		contentContainerView.layer?.cornerRadius = Self.panelCornerRadius
		contentContainerView.layer?.borderWidth = Self.windowBorderWidth
		contentContainerView.layer?.masksToBounds = false
		contentView = contentContainerView
		setupWindow()
		buildLayout()
		queryField.delegate = self
		orderOut(nil)

		viewModel.onStateChange = { [weak self] in
			self?.syncWithViewModelState()
		}

		syncWithViewModelState()
	}

	public func attach(to window: NSWindow?) {
		guard let parentWindow = resolvedParentWindow(explicitWindow: window) else { return }
		rebindToParentWindow(parentWindow)
		repositionForCurrentWindow(window: parentWindow)

		if viewModel.isPresented {
			showPanel()
		}
		else {
			hidePanel()
		}
	}

	public func removeFromWindow() {
		stopOutsideMouseMonitoring()

		if let parentWindow = lastParentWindow,
		   parentWindow.childWindows?.contains(where: { $0 === self }) == true {
			parentWindow.removeChildWindow(self)
		}

		lastParentWindow = nil
		isPanelVisible = false
		orderOut(nil)
	}

	public func repositionForCurrentWindow(window: NSWindow?) {
		guard let parentWindow = resolvedParentWindow(explicitWindow: window) else { return }

		let targetFrame = parentWindow.frame
		let width = max(320, targetFrame.width * Self.widthRatio)
		let height = Self.defaultHeight
		let x = targetFrame.midX - (width / 2)
		let y = targetFrame.maxY - Self.verticalMargin - height
		let clampedY = max(targetFrame.minY + 12, y)
		let panelFrame = NSRect(x: x, y: clampedY, width: width, height: height)

		if !frame.equalTo(panelFrame) {
			setFrame(panelFrame, display: true)
		}
	}

	private func setupWindow() {
		isOpaque = false
		hasShadow = true
		level = .floating
		backgroundColor = .clear
		titlebarAppearsTransparent = true
		titleVisibility = .hidden
		hidesOnDeactivate = false
		isMovableByWindowBackground = false
		animationBehavior = .none
		isReleasedWhenClosed = false
		collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]

		standardWindowButton(.closeButton)?.isHidden = true
		standardWindowButton(.miniaturizeButton)?.isHidden = true
		standardWindowButton(.zoomButton)?.isHidden = true

		styleMask.remove(.resizable)
	}

	private func buildLayout() {
		queryField.translatesAutoresizingMaskIntoConstraints = false
		queryField.isEditable = true
		queryField.isSelectable = true
		queryField.focusRingType = .none
		queryField.alignment = .left
		queryField.drawsBackground = false
		queryField.backgroundColor = .clear
		queryField.isBordered = false
		queryField.isBezeled = false
		queryField.isAutomaticTextCompletionEnabled = false
		queryField.lineBreakMode = .byTruncatingHead
		queryField.placeholderString = viewModel.placeholder
		let defaultFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
		queryField.font = NSFont.systemFont(
			ofSize: defaultFont.pointSize * Self.queryFontScale
		)

		chromeView.translatesAutoresizingMaskIntoConstraints = false
		chromeView.wantsLayer = true
		chromeView.layer?.cornerRadius = Self.panelCornerRadius
		chromeView.layer?.masksToBounds = true
		leadingIconView.translatesAutoresizingMaskIntoConstraints = false
		leadingIconView.imageScaling = .scaleProportionallyDown
		contentContainerView.addSubview(chromeView)
		chromeView.addSubview(leadingIconView)
		chromeView.addSubview(queryField)

		NSLayoutConstraint.activate([
			contentContainerView.heightAnchor.constraint(equalToConstant: Self.defaultHeight),
			chromeView.centerYAnchor.constraint(equalTo: contentContainerView.centerYAnchor),
			chromeView.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
			chromeView.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
			chromeView.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
			chromeView.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor),
			leadingIconView.centerYAnchor.constraint(equalTo: chromeView.centerYAnchor),
			leadingIconView.leadingAnchor.constraint(
				equalTo: chromeView.leadingAnchor,
				constant: Self.iconLeadingInset
			),
			leadingIconView.widthAnchor.constraint(equalToConstant: Self.iconSize),
			leadingIconView.heightAnchor.constraint(equalToConstant: Self.iconSize),
			queryField.centerYAnchor.constraint(equalTo: chromeView.centerYAnchor),
			queryField.leadingAnchor.constraint(
				equalTo: leadingIconView.trailingAnchor,
				constant: Self.iconTrailingSpacing
			),
			queryField.trailingAnchor.constraint(equalTo: chromeView.trailingAnchor),
			queryField.topAnchor.constraint(greaterThanOrEqualTo: chromeView.topAnchor),
			queryField.bottomAnchor.constraint(lessThanOrEqualTo: chromeView.bottomAnchor),
		])

		applyResolvedColors()
	}

	private func syncWithViewModelState() {
		queryField.placeholderString = viewModel.placeholder
		let modeDidChange = lastAppliedMode != viewModel.mode
		lastAppliedMode = viewModel.mode

		if lastAppliedPresentationSeed != viewModel.presentationSeed {
			lastAppliedPresentationSeed = viewModel.presentationSeed
			syncQueryFieldText(force: true)
			shouldSelectQueryText = true
		}
		else if modeDidChange {
			syncQueryFieldText(force: true)
		}
		else if queryField.currentEditor() == nil {
			syncQueryFieldText(force: false)
		}

		applyResolvedColors()

		if viewModel.isPresented {
			if let parentWindow = resolvedParentWindow(explicitWindow: nil) {
				rebindToParentWindow(parentWindow)
				repositionForCurrentWindow(window: parentWindow)
			}
			showPanel()
		}
		else {
			hidePanel()
		}
	}

	private func resolvedParentWindow(explicitWindow: NSWindow?) -> NSWindow? {
		explicitWindow ?? lastParentWindow ?? updateAnchorWindow?()
	}

	private func rebindToParentWindow(_ window: NSWindow) {
		if let currentParent = lastParentWindow, currentParent !== window {
			if currentParent.childWindows?.contains(where: { $0 === self }) == true {
				currentParent.removeChildWindow(self)
			}
		}

		lastParentWindow = window

		if window.childWindows?.contains(where: { $0 === self }) != true {
			window.addChildWindow(self, ordered: .above)
		}
	}

	private func showPanel() {
		guard let parentWindow = resolvedParentWindow(explicitWindow: nil) else { return }

		rebindToParentWindow(parentWindow)
		repositionForCurrentWindow(window: parentWindow)

		let wasVisible = isPanelVisible
		isPanelVisible = true

		applyResolvedColors()
		makeKeyAndOrderFront(nil)
		orderFrontRegardless()

		if !wasVisible || shouldSelectQueryText || queryField.currentEditor() == nil {
			makeFirstResponder(queryField)
			syncQueryFieldText(force: true)
		}

		if !wasVisible || shouldSelectQueryText {
			queryField.selectText(nil)
			shouldSelectQueryText = false
		}
		startOutsideMouseMonitoring()
	}

	private func hidePanel() {
		stopOutsideMouseMonitoring()

		let parentWindow = lastParentWindow
		let panelWasKey = keyWindowProvider() === self

		if let parentWindow,
		   parentWindow.childWindows?.contains(where: { $0 === self }) == true {
			parentWindow.removeChildWindow(self)
		}

		isPanelVisible = false
		orderOut(nil)

		if let parentWindow,
		   parentWindow.isVisible,
		   panelWasKey,
		   !isParentWindowKeyProvider(parentWindow) {
			makeParentWindowKeyHandler(parentWindow)
		}
	}

	private func startOutsideMouseMonitoring() {
		guard outsideMouseMonitors.isEmpty else { return }

		let clickEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

		localOutsideClickHandler = { [unowned self] event in
			return handleLocalOutsideClick(event)
		}
		globalOutsideClickHandler = { [unowned self] screenPoint in
			handleGlobalOutsideClick(screenPoint)
		}

		localMonitorEventHandler = { [unowned self] event in
			handleLocalOutsideClick(event)
		}
		globalMonitorEventHandler = { [unowned self] _ in
			handleGlobalOutsideClick(NSEvent.mouseLocation)
		}

		let localMonitor = NSEvent.addLocalMonitorForEvents(
			matching: clickEvents,
			handler: localMonitorEventHandler!
		)

		let globalMonitor = NSEvent.addGlobalMonitorForEvents(
			matching: clickEvents,
			handler: globalMonitorEventHandler!
		)

		outsideMouseMonitors = [localMonitor, globalMonitor].compactMap { $0 }
	}

	private func stopOutsideMouseMonitoring() {
		for monitor in outsideMouseMonitors {
			NSEvent.removeMonitor(monitor)
		}
		outsideMouseMonitors.removeAll()
		localOutsideClickHandler = nil
		globalOutsideClickHandler = nil
		localMonitorEventHandler = nil
		globalMonitorEventHandler = nil
	}

	private func handleLocalOutsideClick(_ event: NSEvent) -> NSEvent {
		guard isPanelVisible else { return event }
		guard let eventWindow = event.window else {
			viewModel.dismiss()
			return event
		}

		let screenPoint = eventWindow
			.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero))
			.origin

		let clickInsidePanel = frame.contains(screenPoint)
		if !clickInsidePanel {
			viewModel.dismiss()
		}

		return event
	}

	private func handleGlobalOutsideClick(_ screenPoint: NSPoint) {
		guard isPanelVisible else { return }
		let clickInsidePanel = frame.contains(screenPoint)
		if !clickInsidePanel {
			viewModel.dismiss()
		}
	}

	private func performPrimaryAction() {
		viewModel.performPrimaryAction(with: queryField.stringValue)
	}

	private func syncQueryFieldText(force: Bool) {
		guard force || queryField.currentEditor() == nil else { return }
		let currentText = currentQueryText()
		guard currentText != viewModel.query else { return }
		isSynchronizingFromViewModel = true
		queryField.stringValue = viewModel.query
		queryField.currentEditor()?.string = viewModel.query
		isSynchronizingFromViewModel = false
	}

	public func controlTextDidChange(_ notification: Notification) {
		guard let field = notification.object as? NSTextField, field === queryField else { return }
		guard !isSynchronizingFromViewModel else { return }
		viewModel.updateQuery(currentQueryText())
	}

	public func controlTextDidEndEditing(_ notification: Notification) {
		guard let field = notification.object as? NSTextField, field === queryField else { return }
		guard !isSynchronizingFromViewModel else { return }
		guard keyWindowProvider() === self else { return }
		viewModel.updateQuery(currentQueryText())
	}

	override public func update() {
		super.update()
		applyResolvedColors()
	}

	private func applyResolvedColors() {
		updateLeadingIcon()
		chromeView.layer?.backgroundColor = Asset.Colors.background.color.cgColor
		leadingIconView.contentTintColor = Asset.Colors.textPrimaryColor.color
		queryField.textColor = Asset.Colors.textPrimaryColor.color
		contentContainerView.layer?.borderColor = Asset.Colors.separatorPrimaryColor.color.cgColor
	}

	private func updateLeadingIcon() {
		let nextIcon: BrowserActionBarLeadingIcon = switch viewModel.queryIntent {
		case .url:
			.earth
		case .empty, .search:
			.search
		}

		guard currentLeadingIcon != nextIcon || leadingIconView.image == nil else { return }
		currentLeadingIcon = nextIcon
		leadingIconView.image = nextIcon.imageAsset.image
		leadingIconView.image?.isTemplate = true
	}

	override public func performKeyEquivalent(with event: NSEvent) -> Bool {
		let normalizedCharacter = event.charactersIgnoringModifiers?.lowercased()
		let rawCharacter = event.characters?.lowercased()
		if BrowserActionBarShortcutForwardingResolver.shouldForwardToMainMenu(
			modifiers: event.modifierFlags,
			normalizedCharacter: normalizedCharacter,
			rawCharacter: rawCharacter
		), NSApp.mainMenu?.performKeyEquivalent(with: event) == true {
			return true
		}

		return super.performKeyEquivalent(with: event)
	}

	public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
		switch commandSelector {
		case #selector(NSResponder.insertNewline(_:)),
		     #selector(NSResponder.insertLineBreak(_:)),
		     #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
			performPrimaryAction()
			return true
		case #selector(NSResponder.cancelOperation(_:)):
			viewModel.dismiss()
			return true
		default:
			return false
		}
	}

	var currentQueryTextForTesting: String {
		queryField.stringValue
	}

	var currentEditorQueryTextForTesting: String? {
		queryField.currentEditor()?.string
	}

	var isQueryFieldEditingForTesting: Bool {
		queryField.currentEditor() != nil
	}

	var currentPlaceholderForTesting: String? {
		queryField.placeholderString
	}

	var queryFieldDrawsBackgroundForTesting: Bool {
		queryField.drawsBackground
	}

	var queryFieldBackgroundColorForTesting: NSColor {
		queryField.backgroundColor!
	}

	var queryFieldFontSizeForTesting: CGFloat {
		queryField.font!.pointSize
	}

	var windowBorderWidthForTesting: CGFloat {
		contentContainerView.layer!.borderWidth
	}

	var queryFieldFrameForTesting: NSRect {
		contentView?.layoutSubtreeIfNeeded()
		return queryField.frame
	}

	var leadingIconFrameForTesting: NSRect {
		contentView?.layoutSubtreeIfNeeded()
		return leadingIconView.frame
	}

	var leadingIconNameForTesting: String {
		currentLeadingIcon.rawValue
	}

	var contentBoundsForTesting: NSRect {
		contentView?.layoutSubtreeIfNeeded()
		return contentView!.bounds
	}

	var isHostedInWindowForTesting: Bool {
		true
	}

	func simulateQueryTextChangeForTesting(_ text: String) {
		makeFirstResponder(queryField)
		queryField.currentEditor()?.string = text
		controlTextDidChange(
			Notification(
				name: NSControl.textDidChangeNotification,
				object: queryField
			)
		)
	}

	func simulateQueryTextDidEndEditingForTesting(_ text: String) {
		queryField.stringValue = text
		controlTextDidEndEditing(
			Notification(
				name: NSControl.textDidEndEditingNotification,
				object: queryField
			)
		)
	}

	func setKeyWindowForTesting(_ window: NSWindow?) {
		keyWindowProvider = { window }
	}

	func resetKeyWindowProviderForTesting() {
		keyWindowProvider = { NSApp.keyWindow }
	}

	func setIsParentWindowKeyForTesting(_ provider: @escaping (NSWindow) -> Bool) {
		isParentWindowKeyProvider = provider
	}

	func setMakeParentWindowKeyHandlerForTesting(_ handler: @escaping (NSWindow) -> Void) {
		makeParentWindowKeyHandler = handler
	}

	func setIsSynchronizingFromViewModelForTesting(_ value: Bool) {
		isSynchronizingFromViewModel = value
	}

	func setLastAppliedModeForTesting(_ mode: BrowserActionBarMode?) {
		lastAppliedMode = mode
	}

	func setLastAppliedPresentationSeedForTesting(_ seed: UUID?) {
		lastAppliedPresentationSeed = seed
	}

	func simulateLocalOutsideClickForTesting(_ event: NSEvent) -> NSEvent? {
		localOutsideClickHandler?(event)
	}

	func simulateLocalMonitorEventForTesting(_ event: NSEvent) -> NSEvent? {
		localMonitorEventHandler?(event)
	}

	func simulateGlobalOutsideClickForTesting(screenPoint: NSPoint) {
		globalOutsideClickHandler?(screenPoint)
	}

	func simulateGlobalMonitorEventForTesting(_ event: NSEvent) {
		globalMonitorEventHandler?(event)
	}

	func captureLocalOutsideClickHandlerForTesting() -> ((NSEvent) -> NSEvent)? {
		localOutsideClickHandler
	}

	func captureGlobalOutsideClickHandlerForTesting() -> ((NSPoint) -> Void)? {
		globalOutsideClickHandler
	}

	func captureLocalMonitorEventHandlerForTesting() -> ((NSEvent) -> NSEvent?)? {
		localMonitorEventHandler
	}

	func captureGlobalMonitorEventHandlerForTesting() -> ((NSEvent) -> Void)? {
		globalMonitorEventHandler
	}

	func simulateSyncQueryFieldTextForTesting(force: Bool) {
		syncQueryFieldText(force: force)
	}

	func simulateControlTextDidChangeForTesting(object: Any?) {
		controlTextDidChange(
			Notification(name: NSControl.textDidChangeNotification, object: object)
		)
	}

	func simulateControlTextDidEndEditingForTesting(object: Any?) {
		controlTextDidEndEditing(
			Notification(name: NSControl.textDidEndEditingNotification, object: object)
		)
	}

	func setQueryFieldTextForTesting(_ text: String) {
		queryField.stringValue = text
	}

	private func currentQueryText() -> String {
		queryField.currentEditor()?.string ?? queryField.stringValue
	}
}

private enum BrowserActionBarLeadingIcon: String {
	case earth
	case search

	var imageAsset: ImageAsset {
		switch self {
		case .earth:
			Asset.Iconography.earth
		case .search:
			Asset.Iconography.search
		}
	}
}

private final class BrowserActionBarTextField: NSTextField {
	override var alignmentRectInsets: NSEdgeInsets {
		NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
	}
}

enum BrowserActionBarShortcutForwardingResolver {
	static func shouldForwardToMainMenu(
		modifiers: NSEvent.ModifierFlags,
		normalizedCharacter: String?,
		rawCharacter: String?
	) -> Bool {
		let supportedModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
		guard supportedModifiers.contains(.command),
		      supportedModifiers.intersection([.control, .option]).isEmpty else { return false }

		switch normalizedCharacter ?? rawCharacter {
		case "1", "2", "3", "4", "5", "6", "7", "8", "9", "l", "t", "r", "[", "]", "{", "}":
			return true
		default:
			return false
		}
	}
}
