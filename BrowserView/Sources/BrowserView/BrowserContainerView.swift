import AppKit
import BrowserRuntime
import BrowserSidebar
import ModelKit
import Vendors

private enum BrowserContentClippingFeatureFlag {
	static let environmentKey = "NAVIGATOR_DISABLE_BROWSER_CONTENT_CLIPPING"

	static func isDisabled(environment: [String: String]) -> Bool {
		guard let rawValue = environment[environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
		      rawValue.isEmpty == false
		else {
			return false
		}

		switch rawValue.lowercased() {
		case "0", "false", "no", "off", "disabled":
			return false
		default:
			return true
		}
	}
}

struct BrowserContainerState: Equatable {
	static let blankPageURL = "about:blank"

	let initialURL: String
	private(set) var pendingURL: String
	private(set) var hasReceivedNonBlankBrowserURL = false

	init(initialURL: String) {
		self.initialURL = initialURL
		self.pendingURL = initialURL
	}

	mutating func queueURL(_ url: String) {
		pendingURL = url
	}

	mutating func consumeBrowserURLChange(_ url: String) -> Bool {
		if url == Self.blankPageURL,
		   hasReceivedNonBlankBrowserURL == false,
		   pendingURL != Self.blankPageURL {
			return false
		}

		if url != Self.blankPageURL {
			hasReceivedNonBlankBrowserURL = true
		}
		queueURL(url)
		return true
	}

	var urlForNextBrowserCreation: String {
		pendingURL
	}
}

private struct BrowserTopLevelNativeContentPresentationState: Equatable {
	private(set) var activeContent: BrowserRuntimeTopLevelNativeContent?
	private(set) var forwardContent: BrowserRuntimeTopLevelNativeContent?

	var isPresentingContent: Bool {
		activeContent != nil
	}

	mutating func present(_ content: BrowserRuntimeTopLevelNativeContent) {
		activeContent = content
		forwardContent = nil
	}

	mutating func dismissActiveContent() -> Bool {
		guard let activeContent else { return false }
		forwardContent = activeContent
		self.activeContent = nil
		return true
	}

	mutating func restoreForwardContent() -> BrowserRuntimeTopLevelNativeContent? {
		guard let forwardContent else { return nil }
		activeContent = forwardContent
		self.forwardContent = nil
		return forwardContent
	}

	mutating func clear() {
		activeContent = nil
		forwardContent = nil
	}
}

public final class BrowserContainerView: NSView {
	private static let browserCornerRadius: CGFloat = 10
	@Dependency(\.browserRuntime) private var dependencyBrowserRuntime
	public private(set) var browser: CEFBridgeBrowserRef?
	public var onBrowserCreated: ((CEFBridgeBrowserRef) -> Void)?
	var onDisplayedTopLevelNativeContentChange: ((BrowserRuntimeTopLevelNativeContent?) -> Void)?
	private var pendingBrowserCreateWorkItem: DispatchWorkItem?
	private var lastPixelBounds: NSSize?
	private var isBrowserCreationEnabled = true
	private var state: BrowserContainerState
	private var topLevelNativeContentState = BrowserTopLevelNativeContentPresentationState()
	private let browserRuntimeOverride: (any BrowserRuntimeDriving)?
	private let scheduleCreateBrowserWorkItem: BrowserContainerCreationScheduler
	private let topLevelNativeContentViewFactory: BrowserTopLevelNativeContentViewFactory
	private let browserHostView = NSView()
	private let nativeContentHostView = NSView()
	private let permissionPromptHost = BrowserContainerPermissionPromptHost()
	private var topLevelNativeContentView: NSView?

	static let defaultCreateBrowserScheduler: BrowserContainerCreationScheduler = { action in
		var workItem: DispatchWorkItem!
		workItem = DispatchWorkItem {
			guard workItem.isCancelled == false else { return }
			action()
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(16), execute: workItem)
		return workItem
	}

	private var browserRuntime: any BrowserRuntimeDriving {
		browserRuntimeOverride ?? dependencyBrowserRuntime
	}

	#if DEBUG
		func resolveBrowserRuntimeForTesting() {
			_ = browserRuntime
		}
	#endif

	public init(initialURL: String) {
		state = BrowserContainerState(initialURL: initialURL)
		browserRuntimeOverride = nil
		scheduleCreateBrowserWorkItem = Self.defaultCreateBrowserScheduler
		topLevelNativeContentViewFactory = .live
		super.init(frame: .zero)
		translatesAutoresizingMaskIntoConstraints = false
		configureLayer()
		configureHostViews()
	}

	convenience init(
		initialURL: String,
		browserRuntime: any BrowserRuntimeDriving
	) {
		self.init(
			initialURL: initialURL,
			browserRuntime: browserRuntime,
			scheduleCreateBrowserWorkItem: Self.defaultCreateBrowserScheduler,
			topLevelNativeContentViewFactory: .live
		)
	}

	init(
		initialURL: String,
		browserRuntime: any BrowserRuntimeDriving,
		scheduleCreateBrowserWorkItem: @escaping BrowserContainerCreationScheduler,
		topLevelNativeContentViewFactory: BrowserTopLevelNativeContentViewFactory = .live
	) {
		state = BrowserContainerState(initialURL: initialURL)
		browserRuntimeOverride = browserRuntime
		self.scheduleCreateBrowserWorkItem = scheduleCreateBrowserWorkItem
		self.topLevelNativeContentViewFactory = topLevelNativeContentViewFactory
		super.init(frame: .zero)
		translatesAutoresizingMaskIntoConstraints = false
		configureLayer()
		configureHostViews()
	}

	@available(*, unavailable)
	public required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override public func layout() {
		super.layout()
		if browser == nil {
			guard isBrowserCreationEnabled else { return }
			scheduleCreateBrowserIfNeeded()
			return
		}
		let pixelBounds = convertToBacking(bounds)
		let normalizedPixelBounds = NSSize(width: Int(pixelBounds.width), height: Int(pixelBounds.height))
		guard normalizedPixelBounds != lastPixelBounds else { return }
		lastPixelBounds = normalizedPixelBounds
		browserRuntime.resizeBrowser(browser, in: browserHostView)
	}

	public var initialURL: String {
		state.initialURL
	}

	var pendingURL: String {
		state.pendingURL
	}

	var isPresentingTopLevelNativeContent: Bool {
		topLevelNativeContentState.isPresentingContent
	}

	var isReadyForSelectionHandoff: Bool {
		browser != nil || topLevelNativeContentState.isPresentingContent
	}

	func queueURL(_ url: String) {
		state.queueURL(url)
	}

	func consumeBrowserURLChange(_ url: String) -> Bool {
		state.consumeBrowserURLChange(url)
	}

	func setBrowserCreationEnabled(_ isEnabled: Bool) {
		guard isBrowserCreationEnabled != isEnabled else { return }
		isBrowserCreationEnabled = isEnabled
		if isEnabled {
			scheduleCreateBrowserIfNeeded()
		}
		else {
			pendingBrowserCreateWorkItem?.cancel()
			pendingBrowserCreateWorkItem = nil
		}
	}

	func discardBrowser(stopLoad: Bool) {
		pendingBrowserCreateWorkItem?.cancel()
		pendingBrowserCreateWorkItem = nil
		setPermissionPrompt(nil, onDecision: nil, onCancel: nil)
		guard let browser else { return }
		// Native close can synchronously fan back into discard paths; clear the ref first so teardown stays idempotent.
		self.browser = nil
		lastPixelBounds = nil
		clearPresentedTopLevelNativeContent()
		browserRuntime.setTopLevelNativeContentHandler(for: browser, supportedKinds: [], handler: nil)
		if stopLoad {
			browserRuntime.stopLoad(browser)
		}
		browserRuntime.close(browser)
	}

	func navigationState(overriding browserState: BrowserSidebarNavigationState) -> BrowserSidebarNavigationState {
		if topLevelNativeContentState.isPresentingContent {
			return BrowserSidebarNavigationState(
				canGoBack: true,
				canGoForward: false,
				isLoading: false
			)
		}

		return BrowserSidebarNavigationState(
			canGoBack: browserState.canGoBack,
			canGoForward: browserState.canGoForward || topLevelNativeContentState.forwardContent != nil,
			isLoading: browserState.isLoading
		)
	}

	@discardableResult
	func goBackInPresentedTopLevelNativeContent() -> Bool {
		guard topLevelNativeContentState.dismissActiveContent() else { return false }
		setPresentedTopLevelNativeContentView(nil)
		onDisplayedTopLevelNativeContentChange?(nil)
		return true
	}

	@discardableResult
	func goForwardInPresentedTopLevelNativeContent() -> Bool {
		guard let restoredContent = topLevelNativeContentState.restoreForwardContent() else { return false }
		presentTopLevelNativeContent(restoredContent)
		return true
	}

	@discardableResult
	func reloadPresentedTopLevelNativeContent() -> Bool {
		guard let activeContent = topLevelNativeContentState.activeContent else { return false }
		presentTopLevelNativeContent(activeContent)
		return true
	}

	public func load(_ url: String) {
		queueURL(url)
		clearPresentedTopLevelNativeContent()
		guard let browser else {
			createBrowserIfNeeded()
			return
		}
		browserRuntime.load(browser, url: url)
	}

	public func createBrowserIfNeeded() {
		pendingBrowserCreateWorkItem?.cancel()
		pendingBrowserCreateWorkItem = nil
		guard browser == nil else { return }
		guard isBrowserCreationEnabled else { return }
		let pixelBounds = convertToBacking(bounds)
		guard window != nil else {
			scheduleCreateBrowserIfNeeded()
			return
		}
		guard pixelBounds.width >= 1, pixelBounds.height >= 1 else {
			scheduleCreateBrowserIfNeeded()
			return
		}
		guard !browserRuntime.hasPendingNativeBrowserClose() else {
			scheduleCreateBrowserIfNeeded()
			return
		}
		browser = browserRuntime.createBrowser(in: browserHostView, initialURL: state.urlForNextBrowserCreation)
		if let browserRef {
			browserRuntime.setTopLevelNativeContentHandler(
				for: browserRef,
				supportedKinds: topLevelNativeContentViewFactory.supportedKinds
			) { [weak self] content in
				self?.presentTopLevelNativeContent(content)
			}
			onBrowserCreated?(browserRef)
		}
		else {
			if browserRuntime.hasPendingNativeBrowserClose() {
				scheduleCreateBrowserIfNeeded()
				return
			}
			print("[Navigator] BrowserContainerView.createBrowserIfNeeded failed to create browser ref")
		}
	}

	private func scheduleCreateBrowserIfNeeded() {
		guard pendingBrowserCreateWorkItem == nil else { return }
		let workItem = scheduleCreateBrowserWorkItem { [weak self] in
			self?.createBrowserIfNeeded()
		}
		pendingBrowserCreateWorkItem = workItem
	}

	override public func viewWillMove(toSuperview newSuperview: NSView?) {
		if newSuperview == nil {
			discardBrowser(stopLoad: false)
		}
		super.viewWillMove(toSuperview: newSuperview)
	}

	public var browserRef: CEFBridgeBrowserRef? {
		browser
	}

	func setPermissionPrompt(
		_ session: BrowserPermissionSession?,
		onDecision: ((BrowserPermissionPromptDecision, BrowserPermissionPersistence) -> Void)?,
		onCancel: (() -> Void)?
	) {
		permissionPromptHost.setPrompt(
			session,
			onDecision: onDecision,
			onCancel: onCancel
		)
	}

	override public func viewDidChangeEffectiveAppearance() {
		super.viewDidChangeEffectiveAppearance()
		applyResolvedColors()
	}

	private func configureLayer() {
		wantsLayer = true
		if BrowserContentClippingFeatureFlag.isDisabled(environment: ProcessInfo.processInfo.environment) == false {
			layer?.cornerRadius = Self.browserCornerRadius
			layer?.masksToBounds = true
		}
		else {
			layer?.cornerRadius = 0
			layer?.masksToBounds = false
		}
		applyResolvedColors()
	}

	private func configureHostViews() {
		browserHostView.translatesAutoresizingMaskIntoConstraints = false
		nativeContentHostView.translatesAutoresizingMaskIntoConstraints = false
		nativeContentHostView.isHidden = true

		addSubview(browserHostView)
		addSubview(nativeContentHostView)
		permissionPromptHost.install(in: self)

		NSLayoutConstraint.activate([
			browserHostView.topAnchor.constraint(equalTo: topAnchor),
			browserHostView.leadingAnchor.constraint(equalTo: leadingAnchor),
			browserHostView.trailingAnchor.constraint(equalTo: trailingAnchor),
			browserHostView.bottomAnchor.constraint(equalTo: bottomAnchor),
			nativeContentHostView.topAnchor.constraint(equalTo: topAnchor),
			nativeContentHostView.leadingAnchor.constraint(equalTo: leadingAnchor),
			nativeContentHostView.trailingAnchor.constraint(equalTo: trailingAnchor),
			nativeContentHostView.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}

	private func presentTopLevelNativeContent(_ content: BrowserRuntimeTopLevelNativeContent) {
		guard
			topLevelNativeContentViewFactory.supportedKinds.contains(content.kind),
			let contentView = topLevelNativeContentViewFactory.makeView(content)
		else {
			return
		}

		topLevelNativeContentState.present(content)
		setPresentedTopLevelNativeContentView(contentView)
		onDisplayedTopLevelNativeContentChange?(content)
	}

	private func clearPresentedTopLevelNativeContent() {
		let hadPresentedTopLevelNativeContent =
			topLevelNativeContentState.isPresentingContent || topLevelNativeContentView != nil
		topLevelNativeContentState.clear()
		setPresentedTopLevelNativeContentView(nil)
		guard hadPresentedTopLevelNativeContent else { return }
		onDisplayedTopLevelNativeContentChange?(nil)
	}

	private func setPresentedTopLevelNativeContentView(_ nextView: NSView?) {
		topLevelNativeContentView?.removeFromSuperview()
		topLevelNativeContentView = nextView

		guard let nextView else {
			nativeContentHostView.isHidden = true
			browserHostView.isHidden = false
			return
		}

		nextView.translatesAutoresizingMaskIntoConstraints = false
		nativeContentHostView.addSubview(nextView)
		NSLayoutConstraint.activate([
			nextView.topAnchor.constraint(equalTo: nativeContentHostView.topAnchor),
			nextView.leadingAnchor.constraint(equalTo: nativeContentHostView.leadingAnchor),
			nextView.trailingAnchor.constraint(equalTo: nativeContentHostView.trailingAnchor),
			nextView.bottomAnchor.constraint(equalTo: nativeContentHostView.bottomAnchor),
		])
		nativeContentHostView.isHidden = false
		browserHostView.isHidden = true
		topLevelNativeContentView = nextView
	}

	private func applyResolvedColors() {
		layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
	}

	#if DEBUG
		var isPermissionPromptVisibleForTesting: Bool {
			permissionPromptHost.isVisibleForTesting
		}

		var permissionPromptTextValuesForTesting: [String] {
			permissionPromptHost.textValuesForTesting
		}

		func setPermissionPromptRememberForTesting(_ remember: Bool) {
			permissionPromptHost.setRememberForTesting(remember)
		}

		func performPermissionPromptAllowForTesting() {
			permissionPromptHost.performAllowForTesting()
		}

		func performPermissionPromptDenyForTesting() {
			permissionPromptHost.performDenyForTesting()
		}

		func performPermissionPromptCancelForTesting() {
			permissionPromptHost.performCancelForTesting()
		}
	#endif
}
