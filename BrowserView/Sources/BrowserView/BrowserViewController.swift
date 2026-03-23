import AppKit
import BrowserCameraKit
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

typealias BrowserTabActivationScheduler = (TimeInterval, @escaping () -> Void) -> () -> Void
typealias BrowserTabVisibilityHandoffScheduler = (TimeInterval, @escaping () -> Void) -> () -> Void

private enum BrowserTabVisibilityHandoff {
	static let delay: TimeInterval = 1.0 / 60.0
}

private func defaultTabLifecycleConfiguration() -> BrowserTabLifecycleConfiguration {
	BrowserTabActivationLifecycleFeatureFlag.isEnabled(environment: ProcessInfo.processInfo.environment)
		? .init()
		: .disabled
}

@MainActor
public final class BrowserViewController: NSViewController {
	private let windowID: UUID?
	private let sidebarViewModel: BrowserSidebarViewModel
	private let sidebarPresentation: BrowserSidebarPresentation
	private var currentSidebarWidth: CGFloat
	private let browserRuntimeOverride: (any BrowserRuntimeDriving)?
	private let browserChromeViewModel: BrowserChromeViewModel
	private let eventMonitoring: BrowserChromeEventMonitoring
	private let tabLifecycleConfiguration: BrowserTabLifecycleConfiguration
	private let activationScheduler: BrowserTabActivationScheduler
	private let visibilityHandoffScheduler: BrowserTabVisibilityHandoffScheduler
	private let browserContainerCreationScheduler: BrowserContainerCreationScheduler
	private let timeProvider: () -> TimeInterval
	@Dependency(\.browserRuntime) private var dependencyBrowserRuntime

	private var browserRuntime: any BrowserRuntimeDriving {
		browserRuntimeOverride ?? dependencyBrowserRuntime
	}

	private lazy var chromeView = BrowserChromeView(
		browserRuntime: browserRuntime,
		sidebarViewModel: sidebarViewModel,
		sidebarPresentation: sidebarPresentation,
		sidebarWidth: currentSidebarWidth,
		browserChromeViewModel: browserChromeViewModel,
		eventMonitoring: eventMonitoring,
		tabLifecycleConfiguration: tabLifecycleConfiguration,
		activationScheduler: activationScheduler,
		visibilityHandoffScheduler: visibilityHandoffScheduler,
		browserContainerCreationScheduler: browserContainerCreationScheduler,
		timeProvider: timeProvider
	)

	public convenience init(
		windowID: UUID?,
		sidebarViewModel: BrowserSidebarViewModel,
		sidebarPresentation: BrowserSidebarPresentation,
		sidebarWidth: CGFloat
	) {
		self.init(
			windowID: windowID,
			sidebarViewModel: sidebarViewModel,
			sidebarPresentation: sidebarPresentation,
			sidebarWidth: sidebarWidth,
			browserRuntime: nil,
			browserChromeViewModel: BrowserChromeViewModel(
				geometry: .init(sidebarWidth: sidebarWidth),
				workItemScheduler: BrowserChromeViewModel.defaultWorkItemScheduler,
				sidebarPresentation: sidebarPresentation
			),
			eventMonitoring: .live
		)
	}

	convenience init(
		windowID: UUID?,
		sidebarViewModel: BrowserSidebarViewModel,
		sidebarPresentation: BrowserSidebarPresentation,
		sidebarWidth: CGFloat,
		browserRuntime: any BrowserRuntimeDriving
	) {
		self.init(
			windowID: windowID,
			sidebarViewModel: sidebarViewModel,
			sidebarPresentation: sidebarPresentation,
			sidebarWidth: sidebarWidth,
			browserRuntime: browserRuntime,
			browserChromeViewModel: BrowserChromeViewModel(
				geometry: .init(sidebarWidth: sidebarWidth),
				workItemScheduler: BrowserChromeViewModel.defaultWorkItemScheduler,
				sidebarPresentation: sidebarPresentation
			),
			eventMonitoring: .live
		)
	}

	public convenience init(
		windowID: UUID?,
		sidebarViewModel: BrowserSidebarViewModel,
		sidebarPresentation: BrowserSidebarPresentation,
		sidebarWidth: CGFloat,
		browserRuntime: (any BrowserRuntimeDriving)?,
		browserChromeViewModel: BrowserChromeViewModel,
		eventMonitoring: BrowserChromeEventMonitoring
	) {
		self.init(
			windowID: windowID,
			sidebarViewModel: sidebarViewModel,
			sidebarPresentation: sidebarPresentation,
			sidebarWidth: sidebarWidth,
			browserRuntime: browserRuntime,
			browserChromeViewModel: browserChromeViewModel,
			eventMonitoring: eventMonitoring,
			tabLifecycleConfiguration: defaultTabLifecycleConfiguration(),
			activationScheduler: BrowserChromeView.defaultActivationScheduler,
			visibilityHandoffScheduler: BrowserChromeView.defaultVisibilityHandoffScheduler,
			browserContainerCreationScheduler: BrowserContainerView.defaultCreateBrowserScheduler,
			timeProvider: BrowserChromeView.defaultTimeProvider
		)
	}

	init(
		windowID: UUID?,
		sidebarViewModel: BrowserSidebarViewModel,
		sidebarPresentation: BrowserSidebarPresentation,
		sidebarWidth: CGFloat,
		browserRuntime: (any BrowserRuntimeDriving)?,
		browserChromeViewModel: BrowserChromeViewModel,
		eventMonitoring: BrowserChromeEventMonitoring,
		tabLifecycleConfiguration: BrowserTabLifecycleConfiguration,
		activationScheduler: @escaping BrowserTabActivationScheduler,
		visibilityHandoffScheduler: @escaping BrowserTabVisibilityHandoffScheduler = BrowserChromeView
			.defaultVisibilityHandoffScheduler,
		browserContainerCreationScheduler: @escaping BrowserContainerCreationScheduler = BrowserContainerView
			.defaultCreateBrowserScheduler,
		timeProvider: @escaping () -> TimeInterval
	) {
		self.windowID = windowID
		self.sidebarViewModel = sidebarViewModel
		self.sidebarPresentation = sidebarPresentation
		currentSidebarWidth = sidebarWidth
		self.browserRuntimeOverride = browserRuntime
		self.browserChromeViewModel = browserChromeViewModel
		self.eventMonitoring = eventMonitoring
		self.tabLifecycleConfiguration = tabLifecycleConfiguration
		self.activationScheduler = activationScheduler
		self.visibilityHandoffScheduler = visibilityHandoffScheduler
		self.browserContainerCreationScheduler = browserContainerCreationScheduler
		self.timeProvider = timeProvider
		self.browserChromeViewModel.updateSidebarWidth(sidebarWidth)
		super.init(nibName: nil, bundle: nil)
	}

	@available(*, unavailable)
	public required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override public func loadView() {
		view = BrowserViewControllerRootView(
			sidebarPresentation: sidebarPresentation,
			sidebarWidthProvider: { [weak self] in
				self?.currentSidebarWidth ?? 0
			}
		)
		view.frame = NSRect(x: 0, y: 0, width: 1100, height: 700)
		view.wantsLayer = true
		view.layer?.backgroundColor = NSColor.clear.cgColor
	}

	override public func viewDidLoad() {
		super.viewDidLoad()
		buildChromeUI()
	}

	public var hostedBrowser: CEFBridgeBrowserRef? {
		chromeView.hostedBrowser
	}

	public func updateSidebarWidth(_ width: CGFloat) {
		currentSidebarWidth = width
		browserChromeViewModel.updateSidebarWidth(width)
	}

	#if DEBUG
		func browserContainerForTesting(tabID: BrowserTabID) -> BrowserContainerView? {
			chromeView.browserContainerForTesting(tabID: tabID)
		}

		func protectionReasonsForTesting(tabID: BrowserTabID) -> Set<BrowserTabProtectionReason> {
			chromeView.protectionReasonsForTesting(tabID: tabID)
		}
	#endif

	override public func viewDidAppear() {
		super.viewDidAppear()
		chromeView.ensureSelectedBrowserIsReady()
		browserRuntime.noteBrowserActivity()
	}

	private func buildChromeUI() {
		view.addSubview(chromeView)
		chromeView.translatesAutoresizingMaskIntoConstraints = false

		NSLayoutConstraint.activate([
			chromeView.topAnchor.constraint(equalTo: view.topAnchor),
			chromeView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			chromeView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			chromeView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
		])
	}
}

final class BrowserChromeView: NSView {
	private static let browserContainerCornerRadius: CGFloat = 10
	static let defaultActivationScheduler: BrowserTabActivationScheduler = { delay, action in
		if delay <= 0 {
			action()
			return {}
		}
		let workItem = DispatchWorkItem(block: action)
		DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
		return {
			workItem.cancel()
		}
	}

	static let defaultVisibilityHandoffScheduler: BrowserTabVisibilityHandoffScheduler = { delay, action in
		if delay <= 0 {
			action()
			return {}
		}
		let workItem = DispatchWorkItem(block: action)
		DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
		return {
			workItem.cancel()
		}
	}

	static let defaultTimeProvider: () -> TimeInterval = {
		ProcessInfo.processInfo.systemUptime
	}

	private let browserRuntime: any BrowserRuntimeDriving
	private let browserChromeViewModel: BrowserChromeViewModel
	private let sidebarViewModel: BrowserSidebarViewModel
	private let sidebarPresentation: BrowserSidebarPresentation
	private let eventMonitoring: BrowserChromeEventMonitoring
	private let tabLifecycleConfiguration: BrowserTabLifecycleConfiguration
	private let activationScheduler: BrowserTabActivationScheduler
	private let visibilityHandoffScheduler: BrowserTabVisibilityHandoffScheduler
	private let browserContainerCreationScheduler: BrowserContainerCreationScheduler
	private let timeProvider: () -> TimeInterval
	private let browserCameraSessionCoordinator: any BrowserCameraSessionCoordinating
	private let restoredHistoryCoordinator = BrowserRestoredHistoryCoordinator()
	private let browserContainerHost = NSView()
	private let tabHostViewModel = BrowserTabHostViewModel()
	private var tabConfigurationChangeObserverID: UUID?
	private var browserContainersByTabID = [BrowserTabID: BrowserContainerView]()
	private var tabLifecycleRecords = [BrowserTabID: BrowserTabLifecycleRecord]()
	private var activationCancellationByTabID = [BrowserTabID: () -> Void]()
	private var visibilityHandoffCancellation: (() -> Void)?
	private var nextActivationSessionID = 0
	private var selectionGeneration = 0
	private var currentSelectedTabID: BrowserTabID?
	private var previousSelectedTabID: BrowserTabID?
	private var retainedVisibleTabID: BrowserTabID?
	private var mouseTrackingArea: NSTrackingArea?
	private var mouseMoveMonitor: Any?
	private var interactionMonitor: Any?
	private var windowNotificationObservers = [NSObjectProtocol]()
	private var memoryPressureSource: DispatchSourceMemoryPressure?
	private var lifecycleGeneration = 0
	private var pendingCameraPermissionSessionsByTabID = [BrowserTabID: BrowserPermissionSession]()
	private var activeManagedCameraTrackCountByTabID = [BrowserTabID: Int]()
	private var cameraSessionSnapshotObserverID: UUID?
	private var cameraPreviewFrameObserverID: UUID?
	private var activeManagedCameraFrameTabIDs = Set<BrowserTabID>()
	private var browserProcessCameraScriptFallbackTabIDs = Set<BrowserTabID>()
	private var rendererCameraRoutingTransportReadyTabIDs = Set<BrowserTabID>()
	private var rendererManagedFrameTransportReadyTabIDs = Set<BrowserTabID>()
	private var nextManagedCameraFrameSequence: UInt64 = 1
	private var lastManagedCameraFrameDeliveryTime: TimeInterval?

	convenience init(
		browserRuntime: any BrowserRuntimeDriving,
		sidebarViewModel: BrowserSidebarViewModel,
		sidebarPresentation: BrowserSidebarPresentation,
		sidebarWidth: CGFloat,
		browserCameraSessionCoordinator: any BrowserCameraSessionCoordinating = BrowserCameraSessionCoordinator
			.shared
	) {
		self.init(
			browserRuntime: browserRuntime,
			sidebarViewModel: sidebarViewModel,
			sidebarPresentation: sidebarPresentation,
			sidebarWidth: sidebarWidth,
			browserChromeViewModel: BrowserChromeViewModel(
				geometry: .init(sidebarWidth: sidebarWidth),
				workItemScheduler: BrowserChromeViewModel.defaultWorkItemScheduler,
				sidebarPresentation: sidebarPresentation
			),
			eventMonitoring: .live,
			tabLifecycleConfiguration: defaultTabLifecycleConfiguration(),
			activationScheduler: BrowserChromeView.defaultActivationScheduler,
			visibilityHandoffScheduler: BrowserChromeView.defaultVisibilityHandoffScheduler,
			browserContainerCreationScheduler: BrowserContainerView.defaultCreateBrowserScheduler,
			timeProvider: BrowserChromeView.defaultTimeProvider,
			browserCameraSessionCoordinator: browserCameraSessionCoordinator
		)
	}

	convenience init(
		browserRuntime: any BrowserRuntimeDriving,
		sidebarViewModel: BrowserSidebarViewModel,
		sidebarPresentation: BrowserSidebarPresentation,
		sidebarWidth: CGFloat,
		browserChromeViewModel: BrowserChromeViewModel,
		eventMonitoring: BrowserChromeEventMonitoring,
		tabLifecycleConfiguration: BrowserTabLifecycleConfiguration = .init(),
		browserCameraSessionCoordinator: any BrowserCameraSessionCoordinating = BrowserCameraSessionCoordinator
			.shared
	) {
		self.init(
			browserRuntime: browserRuntime,
			sidebarViewModel: sidebarViewModel,
			sidebarPresentation: sidebarPresentation,
			sidebarWidth: sidebarWidth,
			browserChromeViewModel: browserChromeViewModel,
			eventMonitoring: eventMonitoring,
			tabLifecycleConfiguration: tabLifecycleConfiguration,
			activationScheduler: BrowserChromeView.defaultActivationScheduler,
			visibilityHandoffScheduler: BrowserChromeView.defaultVisibilityHandoffScheduler,
			browserContainerCreationScheduler: BrowserContainerView.defaultCreateBrowserScheduler,
			timeProvider: BrowserChromeView.defaultTimeProvider,
			browserCameraSessionCoordinator: browserCameraSessionCoordinator
		)
	}

	convenience init(
		browserRuntime: any BrowserRuntimeDriving,
		sidebarViewModel: BrowserSidebarViewModel,
		sidebarPresentation: BrowserSidebarPresentation,
		sidebarWidth: CGFloat,
		tabLifecycleConfiguration: BrowserTabLifecycleConfiguration,
		activationScheduler: @escaping BrowserTabActivationScheduler = BrowserChromeView.defaultActivationScheduler,
		visibilityHandoffScheduler: @escaping BrowserTabVisibilityHandoffScheduler = BrowserChromeView
			.defaultVisibilityHandoffScheduler,
		browserContainerCreationScheduler: @escaping BrowserContainerCreationScheduler = BrowserContainerView
			.defaultCreateBrowserScheduler,
		timeProvider: @escaping () -> TimeInterval = BrowserChromeView.defaultTimeProvider,
		browserCameraSessionCoordinator: any BrowserCameraSessionCoordinating = BrowserCameraSessionCoordinator
			.shared
	) {
		self.init(
			browserRuntime: browserRuntime,
			sidebarViewModel: sidebarViewModel,
			sidebarPresentation: sidebarPresentation,
			sidebarWidth: sidebarWidth,
			browserChromeViewModel: BrowserChromeViewModel(
				geometry: .init(sidebarWidth: sidebarWidth),
				workItemScheduler: BrowserChromeViewModel.defaultWorkItemScheduler,
				sidebarPresentation: sidebarPresentation
			),
			eventMonitoring: .live,
			tabLifecycleConfiguration: tabLifecycleConfiguration,
			activationScheduler: activationScheduler,
			visibilityHandoffScheduler: visibilityHandoffScheduler,
			browserContainerCreationScheduler: browserContainerCreationScheduler,
			timeProvider: timeProvider,
			browserCameraSessionCoordinator: browserCameraSessionCoordinator
		)
	}

	init(
		browserRuntime: any BrowserRuntimeDriving,
		sidebarViewModel: BrowserSidebarViewModel,
		sidebarPresentation: BrowserSidebarPresentation,
		sidebarWidth: CGFloat,
		browserChromeViewModel: BrowserChromeViewModel,
		eventMonitoring: BrowserChromeEventMonitoring,
		tabLifecycleConfiguration: BrowserTabLifecycleConfiguration,
		activationScheduler: @escaping BrowserTabActivationScheduler,
		visibilityHandoffScheduler: @escaping BrowserTabVisibilityHandoffScheduler = BrowserChromeView
			.defaultVisibilityHandoffScheduler,
		browserContainerCreationScheduler: @escaping BrowserContainerCreationScheduler = BrowserContainerView
			.defaultCreateBrowserScheduler,
		timeProvider: @escaping () -> TimeInterval,
		browserCameraSessionCoordinator: any BrowserCameraSessionCoordinating = BrowserCameraSessionCoordinator
			.shared
	) {
		self.browserCameraSessionCoordinator = browserCameraSessionCoordinator
		self.browserRuntime = browserRuntime
		self.browserChromeViewModel = browserChromeViewModel
		self.sidebarViewModel = sidebarViewModel
		self.sidebarPresentation = sidebarPresentation
		self.eventMonitoring = eventMonitoring
		self.tabLifecycleConfiguration = tabLifecycleConfiguration
		self.activationScheduler = activationScheduler
		self.visibilityHandoffScheduler = visibilityHandoffScheduler
		self.browserContainerCreationScheduler = browserContainerCreationScheduler
		self.timeProvider = timeProvider
		super.init(frame: .zero)
		translatesAutoresizingMaskIntoConstraints = false
		tabConfigurationChangeObserverID = sidebarViewModel.addTabConfigurationChangeObserver { [weak self] in
			self?.syncBrowserTabs()
		}
		bindSidebarActions()
		bindBrowserCameraSessionUpdates()
		addChromeSubviews()
		syncBrowserTabs()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	var hostedBrowser: CEFBridgeBrowserRef? {
		guard let selectedTabID = sidebarViewModel.selectedTabID else { return nil }
		return browserContainersByTabID[selectedTabID]?.browserRef
	}

	#if DEBUG
		func browserContainerForTesting(tabID: BrowserTabID) -> BrowserContainerView? {
			browserContainersByTabID[tabID]
		}

		func protectionReasonsForTesting(tabID: BrowserTabID) -> Set<BrowserTabProtectionReason> {
			tabLifecycleRecords[tabID]?.protectionReasons ?? []
		}
	#endif

	func setDevToolsProtection(_ isProtected: Bool, for tabID: BrowserTabID) {
		setProtection(isProtected, reason: .devTools, for: tabID)
	}

	func setAccessibilityProtection(_ isProtected: Bool, for tabID: BrowserTabID) {
		setProtection(isProtected, reason: .accessibilityFocus, for: tabID)
	}

	override func mouseMoved(with event: NSEvent) {
		super.mouseMoved(with: event)
		handleMouseMoveEvent(event)
	}

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		window?.acceptsMouseMovedEvents = true
		setupMouseMoveMonitor()
		if tabLifecycleConfiguration.isEnabled {
			setupInteractionMonitor()
			setupWindowLifecycleObservers()
			setupMemoryPressureMonitoring()
		}
	}

	override func viewWillMove(toWindow newWindow: NSWindow?) {
		super.viewWillMove(toWindow: newWindow)
		if newWindow == nil {
			cleanupMonitors()
		}
		else if newWindow !== window {
			teardownWindowLifecycleObservers()
		}
	}

	override func removeFromSuperview() {
		if let observerID = tabConfigurationChangeObserverID {
			sidebarViewModel.removeTabConfigurationChangeObserver(observerID)
			tabConfigurationChangeObserverID = nil
		}
		if let observerID = cameraSessionSnapshotObserverID {
			browserCameraSessionCoordinator.removeSnapshotObserver(id: observerID)
			cameraSessionSnapshotObserverID = nil
		}
		if let observerID = cameraPreviewFrameObserverID {
			browserCameraSessionCoordinator.removePreviewFrameObserver(id: observerID)
			cameraPreviewFrameObserverID = nil
		}
		clearAllCameraConsumers()
		cleanupMonitors()
		super.removeFromSuperview()
	}

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		if let mouseTrackingArea {
			removeTrackingArea(mouseTrackingArea)
		}

		guard window != nil else { return }
		let trackingOptions: NSTrackingArea.Options = [
			.mouseMoved,
			.mouseEnteredAndExited,
			.activeInKeyWindow,
			.inVisibleRect,
		]
		let area = NSTrackingArea(
			rect: .zero,
			options: trackingOptions,
			owner: self,
			userInfo: nil
		)
		addTrackingArea(area)
		mouseTrackingArea = area
	}

	func ensureSelectedBrowserIsReady() {
		guard let selectedTabID = sidebarViewModel.selectedTabID else { return }
		layoutSubtreeIfNeeded()
		applySelectedTab(selectedTabID)
	}

	private func cleanupMonitors() {
		lifecycleGeneration += 1
		cancelAllActivations()
		cancelVisibilityHandoff(hideRetainedTab: true)
		teardownWindowLifecycleObservers()
		teardownMemoryPressureMonitoring()
		teardownMouseMoveMonitor()
		teardownInteractionMonitor()
		browserChromeViewModel.cancelPendingSidebarOpen()
	}

	private func setupMouseMoveMonitor() {
		guard mouseMoveMonitor == nil else { return }
		mouseMoveMonitor = eventMonitoring.addLocalMouseMovedMonitor { [weak self] event in
			guard let self else { return event }
			self.handleMouseMoveEvent(event)
			return event
		}
	}

	private func setupInteractionMonitor() {
		guard interactionMonitor == nil else { return }
		interactionMonitor = eventMonitoring.addLocalCommitInteractionMonitor { [weak self] event in
			guard let self else { return event }
			self.handleCommitInteractionEvent(event)
			return event
		}
	}

	private func handleMouseMoveEvent(_ event: NSEvent) {
		browserRuntime.noteBrowserActivity()
		guard let location = locationInSidebar(for: event) else { return }
		browserChromeViewModel.handleMouseMovement(at: location, in: bounds.size)
	}

	private func handleCommitInteractionEvent(_ event: NSEvent) {
		guard tabLifecycleConfiguration.isEnabled else { return }
		browserRuntime.noteBrowserActivity()
		guard let selectedTabID = sidebarViewModel.selectedTabID else { return }
		guard currentSelectedTabID == selectedTabID else { return }
		guard tabLifecycleRecords[selectedTabID]?.isTransient == true else { return }
		switch event.type {
		case .keyDown:
			recordCommitWorthyInteraction(for: selectedTabID)
		case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .scrollWheel:
			guard let location = locationInSidebar(for: event), bounds.contains(location) else { return }
			recordCommitWorthyInteraction(for: selectedTabID)
		default:
			break
		}
	}

	private func teardownMouseMoveMonitor() {
		if let monitor = mouseMoveMonitor {
			eventMonitoring.removeMonitor(monitor)
		}
		mouseMoveMonitor = nil
	}

	private func teardownInteractionMonitor() {
		if let monitor = interactionMonitor {
			eventMonitoring.removeMonitor(monitor)
		}
		interactionMonitor = nil
	}

	private func setupWindowLifecycleObservers() {
		guard let window, windowNotificationObservers.isEmpty else { return }
		let center = NotificationCenter.default
		windowNotificationObservers = [
			center.addObserver(
				forName: NSWindow.didMiniaturizeNotification,
				object: window,
				queue: .main
			) { [weak self] _ in
				Task { @MainActor [weak self] in
					self?.handleWindowVisibilityChange(isEffectivelyVisible: false)
				}
			},
			center.addObserver(
				forName: NSWindow.didDeminiaturizeNotification,
				object: window,
				queue: .main
			) { [weak self] _ in
				Task { @MainActor [weak self] in
					self?.handleWindowVisibilityChange(isEffectivelyVisible: true)
				}
			},
			center.addObserver(
				forName: NSWindow.didChangeOcclusionStateNotification,
				object: window,
				queue: .main
			) { [weak self, weak window] _ in
				Task { @MainActor [weak self, weak window] in
					guard let window else { return }
					let isVisible = window.occlusionState.contains(.visible) && !window.isMiniaturized
					self?.handleWindowVisibilityChange(isEffectivelyVisible: isVisible)
				}
			},
		]
	}

	private func teardownWindowLifecycleObservers() {
		let center = NotificationCenter.default
		for observer in windowNotificationObservers {
			center.removeObserver(observer)
		}
		windowNotificationObservers.removeAll()
	}

	private func setupMemoryPressureMonitoring() {
		guard memoryPressureSource == nil else { return }
		let source = DispatchSource.makeMemoryPressureSource(
			eventMask: [.warning, .critical],
			queue: .main
		)
		source.setEventHandler { [weak self] in
			Task { @MainActor [weak self] in
				self?.handleMemoryPressure()
			}
		}
		source.resume()
		memoryPressureSource = source
	}

	private func teardownMemoryPressureMonitoring() {
		memoryPressureSource?.cancel()
		memoryPressureSource = nil
	}

	private func addChromeSubviews() {
		wantsLayer = true

		addSubview(browserContainerHost)

		browserContainerHost.translatesAutoresizingMaskIntoConstraints = false
		browserContainerHost.wantsLayer = true
		if BrowserContentClippingFeatureFlag.isDisabled(environment: ProcessInfo.processInfo.environment) == false {
			browserContainerHost.layer?.cornerRadius = Self.browserContainerCornerRadius
			browserContainerHost.layer?.masksToBounds = true
		}
		else {
			browserContainerHost.layer?.cornerRadius = 0
			browserContainerHost.layer?.masksToBounds = false
		}

		NSLayoutConstraint.activate([
			browserContainerHost.topAnchor.constraint(equalTo: topAnchor),
			browserContainerHost.leadingAnchor.constraint(equalTo: leadingAnchor),
			browserContainerHost.trailingAnchor.constraint(equalTo: trailingAnchor),
			browserContainerHost.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}

	private func syncBrowserTabs() {
		restoredHistoryCoordinator.syncTabs(sidebarViewModel.tabs)
		let syncResult = tabHostViewModel.sync(
			tabs: sidebarViewModel.tabs,
			selectedTabID: sidebarViewModel.selectedTabID
		)

		for hostedTab in syncResult.tabsToAdd {
			addBrowserContainer(for: hostedTab)
		}
		for tabID in syncResult.tabIDsToRemove {
			removeBrowserContainer(for: tabID)
		}
		if let selectedTabID = syncResult.selectedTabID {
			applySelectedTab(selectedTabID)
		}
		else {
			if tabLifecycleConfiguration.isEnabled {
				cancelAllActivations()
			}
			cancelVisibilityHandoff(hideRetainedTab: true)
			currentSelectedTabID = nil
			previousSelectedTabID = nil
		}
	}

	private func bindBrowserCameraSessionUpdates() {
		cameraSessionSnapshotObserverID = browserCameraSessionCoordinator.addSnapshotObserver { [weak self] snapshot in
			self?.handleBrowserCameraSessionSnapshotChange(snapshot)
		}
		cameraPreviewFrameObserverID = browserCameraSessionCoordinator.addPreviewFrameObserver { [weak self] previewFrame in
			self?.handleBrowserCameraPreviewFrameChange(previewFrame)
		}
	}

	private func handleBrowserCameraSessionSnapshotChange(
		_ snapshot: BrowserCameraSessionSnapshot
	) {
		let previousManagedFrameTabIDs = activeManagedCameraFrameTabIDs
		let nextManagedFrameTabIDs = managedCameraFrameTabIDs(from: snapshot)
		let newlyManagedFrameTabIDs = nextManagedFrameTabIDs.subtracting(previousManagedFrameTabIDs)
		let removedManagedFrameTabIDs = previousManagedFrameTabIDs.subtracting(nextManagedFrameTabIDs)
		activeManagedCameraFrameTabIDs = nextManagedFrameTabIDs

		if !removedManagedFrameTabIDs.isEmpty {
			clearManagedCameraFrames(for: removedManagedFrameTabIDs)
			rendererManagedFrameTransportReadyTabIDs.subtract(removedManagedFrameTabIDs)
			for removedTabID in removedManagedFrameTabIDs {
				syncBrowserTransportState(for: removedTabID)
			}
		}
		sidebarViewModel.updateActiveCameraTabIDs(activeCameraTabIDs(from: snapshot))
		sidebarViewModel.refreshCameraState()
		for (tabID, container) in browserContainersByTabID {
			guard let browser = container.browserRef else { continue }
			syncBrowserCameraRouting(for: browser, tabID: tabID, snapshot: snapshot)
		}
		if !newlyManagedFrameTabIDs.isEmpty {
			deliverCurrentManagedCameraFrameIfAvailable(
				to: newlyManagedFrameTabIDs,
				ignoringThrottle: true
			)
		}
	}

	private func handleBrowserCameraPreviewFrameChange(_ previewFrame: CGImage?) {
		sidebarViewModel.refreshCameraState()
		guard !activeManagedCameraFrameTabIDs.isEmpty else { return }
		guard let previewFrame else {
			clearManagedCameraFrames(for: activeManagedCameraFrameTabIDs)
			return
		}

		deliverManagedCameraFrame(
			previewFrame,
			to: activeManagedCameraFrameTabIDs,
			ignoringThrottle: false
		)
	}

	private func activeCameraTabIDs(from snapshot: BrowserCameraSessionSnapshot) -> Set<BrowserTabID> {
		Set(
			snapshot.activeConsumers.compactMap { consumer in
				guard consumer.kind == .browserTabCapture else { return nil }
				return BrowserTabID(uuidString: consumer.id)
			}
		)
	}

	private func managedCameraFrameTabIDs(
		from snapshot: BrowserCameraSessionSnapshot
	) -> Set<BrowserTabID> {
		guard snapshot.routingSettings.routingEnabled else {
			return []
		}
		return activeCameraTabIDs(from: snapshot)
	}

	private func deliverCurrentManagedCameraFrameIfAvailable(
		to tabIDs: Set<BrowserTabID>,
		ignoringThrottle: Bool
	) {
		guard let previewFrame = browserCameraSessionCoordinator.currentPreviewFrame() else { return }
		deliverManagedCameraFrame(previewFrame, to: tabIDs, ignoringThrottle: ignoringThrottle)
	}

	private func deliverManagedCameraFrame(
		_ previewFrame: CGImage,
		to tabIDs: Set<BrowserTabID>,
		ignoringThrottle: Bool
	) {
		guard !tabIDs.isEmpty else { return }
		let currentTime = timeProvider()
		if !ignoringThrottle,
		   let lastManagedCameraFrameDeliveryTime,
		   currentTime - lastManagedCameraFrameDeliveryTime < BrowserCameraManagedFrameDelivery.minimumFrameInterval {
			return
		}
		guard let payload = BrowserCameraManagedFrameDelivery.payload(
			from: previewFrame,
			sequence: nextManagedCameraFrameSequence
		) else {
			return
		}

		nextManagedCameraFrameSequence += 1
		lastManagedCameraFrameDeliveryTime = currentTime
		deliverManagedCameraFramePayload(payload, to: tabIDs)
	}

	private func clearManagedCameraFrames(for tabIDs: Set<BrowserTabID>) {
		guard !tabIDs.isEmpty else { return }
		lastManagedCameraFrameDeliveryTime = nil
		for tabID in tabIDs {
			clearManagedCameraFrameState(for: tabID)
		}
	}

	private func syncBrowserCameraRouting(
		for browser: CEFBridgeBrowserRef,
		tabID: BrowserTabID,
		snapshot: BrowserCameraSessionSnapshot
	) {
		guard browserProcessCameraScriptFallbackTabIDs.contains(tabID) == false else {
			installBrowserCameraRoutingScript(for: browser, tabID: tabID, snapshot: snapshot)
			return
		}
		guard rendererCameraRoutingTransportReadyTabIDs.contains(tabID) else {
			installBrowserCameraRoutingScript(for: browser, tabID: tabID, snapshot: snapshot)
			return
		}
		sendBrowserCameraRoutingConfiguration(snapshot, for: browser, tabID: tabID)
	}

	private func browserTransportMode(
		for tabID: BrowserTabID,
		rendererReadyTabIDs: Set<BrowserTabID>
	) -> BrowserCameraBrowserTransportMode {
		if browserProcessCameraScriptFallbackTabIDs.contains(tabID) {
			return .browserProcessJavaScriptFallback
		}
		if rendererReadyTabIDs.contains(tabID) {
			return .rendererProcessMessages
		}
		return .unavailable
	}

	private func syncBrowserTransportState(for tabID: BrowserTabID) {
		guard browserContainersByTabID[tabID] != nil else {
			browserCameraSessionCoordinator.clearBrowserTransportState(tabID: tabID.uuidString)
			return
		}

		browserCameraSessionCoordinator.updateBrowserTransportState(
			BrowserCameraBrowserTransportState(
				tabID: tabID.uuidString,
				routingTransportMode: browserTransportMode(
					for: tabID,
					rendererReadyTabIDs: rendererCameraRoutingTransportReadyTabIDs
				),
				frameTransportMode: browserTransportMode(
					for: tabID,
					rendererReadyTabIDs: rendererManagedFrameTransportReadyTabIDs
				),
				activeManagedTrackCount: activeManagedCameraTrackCountByTabID[tabID] ?? 0
			)
		)
	}

	private func deliverManagedCameraFramePayload(
		_ payload: BrowserCameraManagedFramePayload,
		to tabIDs: Set<BrowserTabID>
	) {
		let script = BrowserCameraManagedFrameDelivery.makeFrameDeliveryScript(for: payload)
		let message = BrowserCameraManagedFrameDelivery.makeFrameDeliveryTransportMessage(for: payload)
		for tabID in tabIDs {
			guard let browser = browserContainersByTabID[tabID]?.browserRef else { continue }
			if browserProcessCameraScriptFallbackTabIDs.contains(tabID) {
				evaluateBrowserProcessCameraScript(script, for: browser)
				continue
			}
			if rendererManagedFrameTransportReadyTabIDs.contains(tabID) {
				sendManagedCameraRendererMessage(
					message,
					for: browser,
					tabID: tabID,
					fallbackScript: script
				)
				continue
			}
			evaluateBrowserCameraScript(script, for: browser, tabID: tabID) { [weak self] in
				self?.rendererManagedFrameTransportReadyTabIDs.insert(tabID)
				self?.syncBrowserTransportState(for: tabID)
			}
		}
	}

	private func clearManagedCameraFrameState(for tabID: BrowserTabID) {
		guard let browser = browserContainersByTabID[tabID]?.browserRef else { return }
		let script = BrowserCameraManagedFrameDelivery.makeClearFrameScript()
		if browserProcessCameraScriptFallbackTabIDs.contains(tabID) {
			evaluateBrowserProcessCameraScript(script, for: browser)
			return
		}
		if rendererManagedFrameTransportReadyTabIDs.contains(tabID) {
			sendManagedCameraRendererMessage(
				BrowserCameraManagedFrameDelivery.makeClearFrameTransportMessage(),
				for: browser,
				tabID: tabID,
				fallbackScript: script
			)
			return
		}
		evaluateBrowserCameraScript(script, for: browser, tabID: tabID)
	}

	private func sendManagedCameraRendererMessage(
		_ message: BrowserCameraRendererTransportMessage,
		for browser: CEFBridgeBrowserRef,
		tabID: BrowserTabID,
		fallbackScript: String
	) {
		browserRuntime.sendRendererProcessMessage(browser, message: message) { [weak self] _, error in
			guard let self else { return }
			guard let error, !error.isEmpty else { return }
			let fallbackInsertResult = self.browserProcessCameraScriptFallbackTabIDs.insert(tabID)
			self.rendererCameraRoutingTransportReadyTabIDs.remove(tabID)
			self.rendererManagedFrameTransportReadyTabIDs.remove(tabID)
			self.syncBrowserTransportState(for: tabID)
			if fallbackInsertResult.inserted {
				self.browserCameraSessionCoordinator.noteBrowserProcessFallback(
					tabID: tabID.uuidString,
					reason: "rendererError=\(error)"
				)
			}
			let installScript = BrowserCameraRoutingJavaScript.makeInstallScript(
				from: self.browserCameraSessionCoordinator.currentSnapshot()
			)
			self.evaluateBrowserProcessCameraScript(installScript, for: browser) { [weak self] in
				self?.evaluateBrowserProcessCameraScript(fallbackScript, for: browser)
			}
		}
	}

	private func sendBrowserCameraRoutingConfiguration(
		_ snapshot: BrowserCameraSessionSnapshot,
		for browser: CEFBridgeBrowserRef,
		tabID: BrowserTabID
	) {
		let installScript = BrowserCameraRoutingJavaScript.makeInstallScript(from: snapshot)
		let message = BrowserCameraRoutingJavaScript.makeConfigurationTransportMessage(from: snapshot)
		browserRuntime.sendRendererProcessMessage(browser, message: message) { [weak self] _, error in
			guard let self else { return }
			guard let error, !error.isEmpty else { return }
			let fallbackInsertResult = self.browserProcessCameraScriptFallbackTabIDs.insert(tabID)
			self.rendererCameraRoutingTransportReadyTabIDs.remove(tabID)
			self.rendererManagedFrameTransportReadyTabIDs.remove(tabID)
			self.syncBrowserTransportState(for: tabID)
			if fallbackInsertResult.inserted {
				self.browserCameraSessionCoordinator.noteBrowserProcessFallback(
					tabID: tabID.uuidString,
					reason: "rendererConfigError=\(error)"
				)
			}
			self.evaluateBrowserProcessCameraScript(installScript, for: browser)
		}
	}

	private func evaluateBrowserCameraScript(
		_ script: String,
		for browser: CEFBridgeBrowserRef,
		tabID: BrowserTabID,
		allowsRendererReinstallRetry: Bool = true,
		completion: (@MainActor () -> Void)? = nil
	) {
		if browserProcessCameraScriptFallbackTabIDs.contains(tabID) {
			evaluateBrowserProcessCameraScript(script, for: browser, completion: completion)
			return
		}

		browserRuntime.evaluateJavaScriptInRendererWithResult(browser, script: script) { [weak self] result, error in
			guard let self else { return }
			if allowsRendererReinstallRetry,
			   result == BrowserCameraRendererScriptStatus.missingShim.rawValue {
				let installScript = BrowserCameraRoutingJavaScript.makeInstallScript(
					from: self.browserCameraSessionCoordinator.currentSnapshot()
				)
				self.browserRuntime
					.evaluateJavaScriptInRendererWithResult(
						browser,
						script: installScript
					) { [weak self] installResult, installError in
						guard let self else { return }
						guard BrowserCameraRendererScriptEvaluation.requiresBrowserProcessFallback(
							result: installResult,
							error: installError
						) == false else {
							let fallbackInsertResult = self.browserProcessCameraScriptFallbackTabIDs.insert(tabID)
							self.rendererCameraRoutingTransportReadyTabIDs.remove(tabID)
							self.syncBrowserTransportState(for: tabID)
							if fallbackInsertResult.inserted {
								self.browserCameraSessionCoordinator.noteBrowserProcessFallback(
									tabID: tabID.uuidString,
									reason: BrowserCameraRendererScriptEvaluation.browserProcessFallbackReason(
										result: installResult,
										error: installError
									)
								)
							}
							self.evaluateBrowserProcessCameraScript(script, for: browser, completion: completion)
							return
						}
						self.evaluateBrowserCameraScript(
							script,
							for: browser,
							tabID: tabID,
							allowsRendererReinstallRetry: false,
							completion: completion
						)
					}
				return
			}
			guard BrowserCameraRendererScriptEvaluation.requiresBrowserProcessFallback(
				result: result,
				error: error
			) else {
				completion?()
				return
			}
			let fallbackInsertResult = self.browserProcessCameraScriptFallbackTabIDs.insert(tabID)
			self.rendererCameraRoutingTransportReadyTabIDs.remove(tabID)
			self.syncBrowserTransportState(for: tabID)
			if fallbackInsertResult.inserted {
				self.browserCameraSessionCoordinator.noteBrowserProcessFallback(
					tabID: tabID.uuidString,
					reason: BrowserCameraRendererScriptEvaluation.browserProcessFallbackReason(
						result: result,
						error: error
					)
				)
			}
			self.evaluateBrowserProcessCameraScript(script, for: browser, completion: completion)
		}
	}

	private func evaluateBrowserProcessCameraScript(
		_ script: String,
		for browser: CEFBridgeBrowserRef,
		completion: (@MainActor () -> Void)? = nil
	) {
		browserRuntime.evaluateJavaScriptWithResult(browser, script: script) { _, _ in
			completion?()
		}
	}

	private func completeBrowserCameraRoutingScriptInstall(
		for browser: CEFBridgeBrowserRef,
		tabID: BrowserTabID,
		lifecycleGeneration: Int
	) {
		guard self.lifecycleGeneration == lifecycleGeneration else { return }
		guard self.browserContainersByTabID[tabID]?.browserRef == browser else { return }
		if browserProcessCameraScriptFallbackTabIDs.contains(tabID) {
			rendererCameraRoutingTransportReadyTabIDs.remove(tabID)
		}
		else {
			rendererCameraRoutingTransportReadyTabIDs.insert(tabID)
		}
		rendererManagedFrameTransportReadyTabIDs.remove(tabID)
		syncBrowserTransportState(for: tabID)
		if self.activeManagedCameraFrameTabIDs.contains(tabID) {
			self.deliverCurrentManagedCameraFrameIfAvailable(
				to: [tabID],
				ignoringThrottle: true
			)
		}
	}

	private func addBrowserContainer(for hostedTab: BrowserTabHostViewModel.HostedTab) {
		guard browserContainersByTabID[hostedTab.id] == nil else { return }
		tabLifecycleRecords[hostedTab.id] = tabLifecycleRecords[hostedTab.id] ?? .init()
		let container = BrowserContainerView(
			initialURL: hostedTab.initialURL,
			browserRuntime: browserRuntime,
			scheduleCreateBrowserWorkItem: browserContainerCreationScheduler
		)
		container.setBrowserCreationEnabled(false)
		container.isHidden = true
		container.onBrowserCreated = { [weak self] browser in
			guard let self else { return }
			guard self.tabLifecycleRecords[hostedTab.id] != nil else {
				self.browserRuntime.close(browser)
				return
			}
			self.browserProcessCameraScriptFallbackTabIDs.remove(hostedTab.id)
			self.rendererCameraRoutingTransportReadyTabIDs.remove(hostedTab.id)
			self.rendererManagedFrameTransportReadyTabIDs.remove(hostedTab.id)
			self.syncBrowserTransportState(for: hostedTab.id)
			self.markBrowserCreated(for: hostedTab.id)
			if let tab = self.tabViewModel(for: hostedTab.id) {
				self.restoredHistoryCoordinator.browserCreated(for: tab)
			}
			self.bindAddressChangeHandler(for: browser, tabID: hostedTab.id)
			self.bindFaviconURLChangeHandler(for: browser, tabID: hostedTab.id)
			self.bindTitleChangeHandler(for: browser, tabID: hostedTab.id)
			self.bindRenderProcessTerminationHandler(for: browser, tabID: hostedTab.id)
			self.bindMainFrameNavigationHandler(for: browser, tabID: hostedTab.id)
			self.bindOpenURLInTabHandler(for: browser, tabID: hostedTab.id)
			self.bindCameraRoutingEventHandler(for: browser, tabID: hostedTab.id)
			self.bindPermissionPromptHandler(for: browser, tabID: hostedTab.id)
			self.installBrowserCameraRoutingScript(for: browser, tabID: hostedTab.id)
			self.syncNavigationState(for: hostedTab.id)
			self.browserRuntime.noteBrowserActivity()
		}
		container.onDisplayedTopLevelNativeContentChange = { [weak self, weak container] content in
			guard let self, let container else { return }
			guard self.tabLifecycleRecords[hostedTab.id] != nil else { return }
			if let content {
				self.sidebarViewModel.updateTabURL(content.url, for: hostedTab.id)
			}
			else {
				self.sidebarViewModel.updateTabURL(container.pendingURL, for: hostedTab.id)
			}
			self.syncNavigationState(for: hostedTab.id)
		}
		browserContainersByTabID[hostedTab.id] = container
		browserContainerHost.addSubview(container)
		container.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			container.topAnchor.constraint(equalTo: browserContainerHost.topAnchor),
			container.leadingAnchor.constraint(equalTo: browserContainerHost.leadingAnchor),
			container.trailingAnchor.constraint(equalTo: browserContainerHost.trailingAnchor),
			container.bottomAnchor.constraint(equalTo: browserContainerHost.bottomAnchor),
		])
	}

	private func removeBrowserContainer(for tabID: BrowserTabID) {
		restoredHistoryCoordinator.browserRemoved(for: tabID)
		cancelActivation(for: tabID)
		if retainedVisibleTabID == tabID {
			cancelVisibilityHandoff(hideRetainedTab: false)
		}
		tabLifecycleRecords.removeValue(forKey: tabID)
		if currentSelectedTabID == tabID {
			currentSelectedTabID = nil
		}
		if previousSelectedTabID == tabID {
			previousSelectedTabID = nil
		}
		guard let container = browserContainersByTabID.removeValue(forKey: tabID) else { return }
		browserProcessCameraScriptFallbackTabIDs.remove(tabID)
		rendererCameraRoutingTransportReadyTabIDs.remove(tabID)
		rendererManagedFrameTransportReadyTabIDs.remove(tabID)
		clearCameraConsumer(for: tabID)
		container.removeFromSuperview()
	}

	private func applySelectedTab(_ tabID: BrowserTabID) {
		let selectionChanged = currentSelectedTabID != tabID
		if tabLifecycleConfiguration.isEnabled {
			handleSelectionChange(to: tabID)
		}
		else {
			activateCommittedTab(tabID)
		}
		updateContainerVisibility(for: tabID, selectionChanged: selectionChanged)

		guard let selectedContainer = browserContainersByTabID[tabID] else { return }
		if tabLifecycleRecords[tabID]?.isCommitted == true {
			layoutSubtreeIfNeeded()
			if selectedContainer.browserRef == nil {
				beginProvisionalNavigationIfNeeded(for: tabID)
			}
			selectedContainer.setBrowserCreationEnabled(true)
			selectedContainer.createBrowserIfNeeded()
		}
		browserRuntime.noteBrowserActivity()
		if tabLifecycleConfiguration.isEnabled {
			evictHiddenBrowsersIfNeeded()
		}
		if let browser = selectedContainer.browserRef {
			installBrowserCameraRoutingScript(for: browser, tabID: tabID)
		}
		syncNavigationState(for: tabID)
	}

	private func updateContainerVisibility(for selectedTabID: BrowserTabID, selectionChanged: Bool) {
		cancelVisibilityHandoff(hideRetainedTab: true)

		let retainedTabID = retainedVisibilityHandoffTabID(for: selectedTabID, selectionChanged: selectionChanged)
		let visibleTabIDs = Set([selectedTabID, retainedTabID].compactMap { $0 })

		for (candidateTabID, container) in browserContainersByTabID {
			container.isHidden = visibleTabIDs.contains(candidateTabID) == false
			container.layer?.zPosition = candidateTabID == retainedTabID ? 1 : 0
			container.setBrowserCreationEnabled(
				candidateTabID == selectedTabID &&
					(tabLifecycleConfiguration.isEnabled == false || tabLifecycleRecords[candidateTabID]?.isCommitted == true)
			)
		}

		guard let retainedTabID else { return }
		retainedVisibleTabID = retainedTabID
		let lifecycleGeneration = self.lifecycleGeneration
		visibilityHandoffCancellation = visibilityHandoffScheduler(BrowserTabVisibilityHandoff.delay) { [weak self] in
			guard let self else { return }
			guard self.lifecycleGeneration == lifecycleGeneration else { return }
			self.finishVisibilityHandoff(selectedTabID: selectedTabID, retainedTabID: retainedTabID)
		}
	}

	private func retainedVisibilityHandoffTabID(for selectedTabID: BrowserTabID, selectionChanged: Bool) -> BrowserTabID? {
		guard selectionChanged else { return nil }
		guard let previousSelectedTabID, previousSelectedTabID != selectedTabID else { return nil }
		guard let selectedContainer = browserContainersByTabID[selectedTabID],
		      let previousContainer = browserContainersByTabID[previousSelectedTabID]
		else {
			return nil
		}
		guard selectedContainer.isReadyForSelectionHandoff, previousContainer.isReadyForSelectionHandoff else { return nil }
		return previousSelectedTabID
	}

	private func finishVisibilityHandoff(selectedTabID: BrowserTabID, retainedTabID: BrowserTabID) {
		guard currentSelectedTabID == selectedTabID else {
			cancelVisibilityHandoff(hideRetainedTab: true)
			return
		}
		browserContainersByTabID[retainedTabID]?.isHidden = true
		browserContainersByTabID[retainedTabID]?.layer?.zPosition = 0
		browserContainersByTabID[selectedTabID]?.layer?.zPosition = 0
		retainedVisibleTabID = nil
		visibilityHandoffCancellation = nil
	}

	private func cancelVisibilityHandoff(hideRetainedTab: Bool) {
		visibilityHandoffCancellation?()
		visibilityHandoffCancellation = nil
		if hideRetainedTab, let retainedVisibleTabID {
			browserContainersByTabID[retainedVisibleTabID]?.isHidden = true
			browserContainersByTabID[retainedVisibleTabID]?.layer?.zPosition = 0
		}
		retainedVisibleTabID = nil
	}

	private func handleSelectionChange(to tabID: BrowserTabID) {
		guard tabLifecycleConfiguration.isEnabled else { return }
		guard currentSelectedTabID != tabID else { return }
		let previousSelection = currentSelectedTabID
		selectionGeneration += 1
		if let previousSelection {
			handleDeselection(of: previousSelection)
			previousSelectedTabID = previousSelection
		}
		currentSelectedTabID = tabID
		guard let record = tabLifecycleRecords[tabID] else { return }
		switch record.intentState {
		case .committed:
			cancelActivation(for: tabID)
			activateCommittedTab(tabID)
		case .cold:
			startTransientSelection(for: tabID)
		case .transientSelected:
			startTransientSelection(for: tabID)
		}
	}

	private func handleDeselection(of tabID: BrowserTabID) {
		guard tabLifecycleConfiguration.isEnabled else { return }
		guard var record = tabLifecycleRecords[tabID] else { return }
		captureScrollStateIfNeeded(for: tabID)
		cancelActivation(for: tabID)
		if record.isCommitted {
			return
		}

		if browserContainersByTabID[tabID]?.browserRef != nil {
			logLifecycleEvent("transientSelectionDiscarded tabID=\(tabID) reason=abandoned")
			discardBrowser(for: tabID, stopLoad: true, preserveCommitment: false)
			return
		}

		record.intentState = .cold
		record.navigationState = .none
		record.browserState = .none
		tabLifecycleRecords[tabID] = record
		logLifecycleEvent("transientSelectionCanceled tabID=\(tabID) reason=deselectedBeforeCreation")
	}

	private func startTransientSelection(for tabID: BrowserTabID) {
		guard tabLifecycleConfiguration.isEnabled else { return }
		cancelActivation(for: tabID)
		nextActivationSessionID += 1
		let sessionID = nextActivationSessionID
		var record = tabLifecycleRecords[tabID] ?? .init()
		record.intentState = .transientSelected(sessionID: sessionID)
		record.lastSelectionGeneration = selectionGeneration
		tabLifecycleRecords[tabID] = record
		logLifecycleEvent("transientSelectionStarted tabID=\(tabID)")
		let lifecycleGeneration = self.lifecycleGeneration
		activationCancellationByTabID[tabID] = activationScheduler(tabLifecycleConfiguration.activationDelay) { [weak self] in
			guard let self else { return }
			guard self.lifecycleGeneration == lifecycleGeneration else { return }
			self.commitTransientSelection(for: tabID, sessionID: sessionID)
		}
	}

	private func commitTransientSelection(for tabID: BrowserTabID, sessionID: Int) {
		guard tabLifecycleConfiguration.isEnabled else { return }
		guard currentSelectedTabID == tabID else { return }
		guard var record = tabLifecycleRecords[tabID] else { return }
		guard case let .transientSelected(activeSessionID) = record.intentState, activeSessionID == sessionID else { return }
		activationCancellationByTabID.removeValue(forKey: tabID)
		record.intentState = .committed
		record.lastSelectionGeneration = selectionGeneration
		tabLifecycleRecords[tabID] = record
		logLifecycleEvent("transientSelectionCommitted tabID=\(tabID) sessionID=\(sessionID)")
		activateCommittedTab(tabID)
	}

	private func activateCommittedTab(_ tabID: BrowserTabID) {
		guard var record = tabLifecycleRecords[tabID] else { return }
		record.intentState = .committed
		record.lastSelectionGeneration = selectionGeneration
		tabLifecycleRecords[tabID] = record
		guard currentSelectedTabID == tabID else { return }
		guard let container = browserContainersByTabID[tabID] else { return }
		beginProvisionalNavigationIfNeeded(for: tabID)
		layoutSubtreeIfNeeded()
		container.setBrowserCreationEnabled(true)
		container.createBrowserIfNeeded()
		restoreScrollStateIfNeeded(for: tabID)
	}

	private func beginProvisionalNavigationIfNeeded(for tabID: BrowserTabID) {
		guard var record = tabLifecycleRecords[tabID] else { return }
		guard record.navigationState == .none || record.navigationState == .finished else { return }
		record.navigationState = .provisional
		if record.isDiscarded == false {
			record.capturedScrollState = nil
		}
		tabLifecycleRecords[tabID] = record
	}

	private func cancelActivation(for tabID: BrowserTabID) {
		activationCancellationByTabID.removeValue(forKey: tabID)?()
	}

	private func cancelAllActivations() {
		for cancellation in activationCancellationByTabID.values {
			cancellation()
		}
		activationCancellationByTabID.removeAll()
	}

	private func markBrowserCreated(for tabID: BrowserTabID) {
		guard var record = tabLifecycleRecords[tabID] else { return }
		record.browserState = .live(createdAt: timeProvider())
		tabLifecycleRecords[tabID] = record
		if currentSelectedTabID != tabID, record.isCommitted == false {
			discardBrowser(for: tabID, stopLoad: true, preserveCommitment: false)
			return
		}
		if tabLifecycleConfiguration.isEnabled {
			evictHiddenBrowsersIfNeeded()
		}
	}

	private func discardBrowser(for tabID: BrowserTabID, stopLoad: Bool, preserveCommitment: Bool) {
		guard var record = tabLifecycleRecords[tabID] else { return }
		clearCameraConsumer(for: tabID)
		browserContainersByTabID[tabID]?.setBrowserCreationEnabled(false)
		browserContainersByTabID[tabID]?.discardBrowser(stopLoad: stopLoad)
		record.browserState = preserveCommitment ? .discarded : .none
		record.navigationState = .none
		record.intentState = preserveCommitment ? .committed : .cold
		tabLifecycleRecords[tabID] = record
		logLifecycleEvent(
			"browserDiscarded tabID=\(tabID) stopLoad=\(stopLoad) preserveCommitment=\(preserveCommitment)"
		)
	}

	private func setProtection(
		_ isProtected: Bool,
		reason: BrowserTabProtectionReason,
		for tabID: BrowserTabID
	) {
		guard var record = tabLifecycleRecords[tabID] else { return }
		if isProtected {
			record.protectionReasons.insert(reason)
		}
		else {
			record.protectionReasons.remove(reason)
		}
		tabLifecycleRecords[tabID] = record
		if tabLifecycleConfiguration.isEnabled {
			evictHiddenBrowsersIfNeeded()
		}
	}

	private func protectedTabIDs() -> Set<BrowserTabID> {
		var protectedIDs = Set<BrowserTabID>()
		if let currentSelectedTabID {
			protectedIDs.insert(currentSelectedTabID)
		}
		if let previousSelectedTabID {
			protectedIDs.insert(previousSelectedTabID)
		}
		if let warmTabID = tabLifecycleRecords
			.filter({ $0.value.isCommitted && $0.value.hasLiveBrowser })
			.filter({ $0.key != currentSelectedTabID && $0.key != previousSelectedTabID })
			.max(by: { $0.value.lastSelectionGeneration < $1.value.lastSelectionGeneration })?
			.key {
			protectedIDs.insert(warmTabID)
		}
		for (tabID, record) in tabLifecycleRecords where record.isProtectedFromEviction {
			protectedIDs.insert(tabID)
		}
		return protectedIDs
	}

	private func evictHiddenBrowsersIfNeeded(force: Bool = false) {
		guard tabLifecycleConfiguration.isEnabled else { return }
		let protectedIDs = protectedTabIDs()
		let liveTabs = tabLifecycleRecords.filter { $0.value.hasLiveBrowser }
		guard liveTabs.count > tabLifecycleConfiguration.maxLiveBrowsers || force else { return }

		let now = timeProvider()
		let candidates = liveTabs
			.filter { protectedIDs.contains($0.key) == false }
			.sorted { lhs, rhs in
				lhs.value.lastSelectionGeneration < rhs.value.lastSelectionGeneration
			}

		for candidate in candidates {
			guard tabLifecycleRecords.filter({ $0.value.hasLiveBrowser }).count > tabLifecycleConfiguration
				.maxLiveBrowsers || force
			else {
				break
			}
			if force == false,
			   let createdAt = candidate.value.browserCreatedAt,
			   now - createdAt < tabLifecycleConfiguration.minimumLiveBrowserLifetime {
				logLifecycleEvent("rendererChurnProtectionSkip tabID=\(candidate.key)")
				continue
			}
			discardBrowser(for: candidate.key, stopLoad: false, preserveCommitment: candidate.value.isCommitted)
			logLifecycleEvent(
				"hiddenBrowserEvicted tabID=\(candidate.key) liveBrowserCount=\(tabLifecycleRecords.filter { $0.value.hasLiveBrowser }.count)"
			)
		}
	}

	private func bindAddressChangeHandler(for browser: CEFBridgeBrowserRef, tabID: BrowserTabID) {
		let lifecycleGeneration = self.lifecycleGeneration
		browserRuntime.setAddressChangeHandler(for: browser) { [weak self] url in
			guard let self else { return }
			guard self.lifecycleGeneration == lifecycleGeneration else { return }
			guard self.browserContainersByTabID[tabID]?.consumeBrowserURLChange(url) == true else {
				self.syncNavigationState(for: tabID)
				return
			}
			if var record = self.tabLifecycleRecords[tabID] {
				record.navigationState = .committed
				self.tabLifecycleRecords[tabID] = record
			}
			if self.isAuthSensitiveURL(url) == false {
				self.setProtection(false, reason: .authSensitive, for: tabID)
			}
			if let tab = self.tabViewModel(for: tabID),
			   let historyUpdate = self.restoredHistoryCoordinator.handleCommittedURL(url, for: tab) {
				self.sidebarViewModel.updateTabSessionHistory(
					entries: historyUpdate.entries,
					currentIndex: historyUpdate.currentIndex,
					for: tabID
				)
			}
			self.sidebarViewModel.updateTabURL(url, for: tabID)
			self.restoreScrollStateIfNeeded(for: tabID)
			self.syncNavigationState(for: tabID)
		}
	}

	private func bindFaviconURLChangeHandler(for browser: CEFBridgeBrowserRef, tabID: BrowserTabID) {
		let lifecycleGeneration = self.lifecycleGeneration
		browserRuntime.setFaviconURLChangeHandler(for: browser) { [weak self] faviconURL in
			guard let self else { return }
			guard self.lifecycleGeneration == lifecycleGeneration else { return }
			self.sidebarViewModel.updateTabFaviconURL(
				normalizedFaviconURL(from: faviconURL),
				for: tabID
			)
		}
	}

	private func bindTitleChangeHandler(for browser: CEFBridgeBrowserRef, tabID: BrowserTabID) {
		let lifecycleGeneration = self.lifecycleGeneration
		browserRuntime.setTitleChangeHandler(for: browser) { [weak self] title in
			guard let self else { return }
			guard self.lifecycleGeneration == lifecycleGeneration else { return }
			self.sidebarViewModel.updateTabTitle(title, for: tabID)
			if let tab = self.tabViewModel(for: tabID),
			   let historyUpdate = self.restoredHistoryCoordinator.handleTitleChange(title, for: tab) {
				self.sidebarViewModel.updateTabSessionHistory(
					entries: historyUpdate.entries,
					currentIndex: historyUpdate.currentIndex,
					for: tabID
				)
			}
		}
	}

	private func bindRenderProcessTerminationHandler(for browser: CEFBridgeBrowserRef, tabID: BrowserTabID) {
		let lifecycleGeneration = self.lifecycleGeneration
		browserRuntime.setRenderProcessTerminationHandler(for: browser) { [weak self] _ in
			guard let self else { return }
			guard self.lifecycleGeneration == lifecycleGeneration else { return }
			guard self.browserContainersByTabID[tabID]?.browserRef == browser else { return }
			self.rendererManagedFrameTransportReadyTabIDs.remove(tabID)
			self.clearCameraConsumer(for: tabID)
			self.logLifecycleEvent("renderProcessTermination tabID=\(tabID)")
			self.discardBrowser(for: tabID, stopLoad: false, preserveCommitment: true)
		}
	}

	private func bindMainFrameNavigationHandler(for browser: CEFBridgeBrowserRef, tabID: BrowserTabID) {
		let lifecycleGeneration = self.lifecycleGeneration
		browserRuntime.setMainFrameNavigationHandler(for: browser) { [weak self] event in
			guard let self else { return }
			guard self.lifecycleGeneration == lifecycleGeneration else { return }
			guard self.browserContainersByTabID[tabID]?.browserRef == browser else { return }
			self.rendererManagedFrameTransportReadyTabIDs.remove(tabID)
			self.clearCameraConsumer(for: tabID)
			if self.shouldProtectForAuthSensitiveFlow(event) {
				self.setProtection(true, reason: .authSensitive, for: tabID)
			}
			self.installBrowserCameraRoutingScript(for: browser, tabID: tabID)
		}
	}

	private func installBrowserCameraRoutingScript(
		for browser: CEFBridgeBrowserRef,
		tabID: BrowserTabID,
		snapshot: BrowserCameraSessionSnapshot? = nil
	) {
		let lifecycleGeneration = self.lifecycleGeneration
		let script = BrowserCameraRoutingJavaScript.makeInstallScript(
			from: snapshot ?? browserCameraSessionCoordinator.currentSnapshot()
		)
		evaluateBrowserCameraScript(
			script,
			for: browser,
			tabID: tabID,
			allowsRendererReinstallRetry: false
		) { [weak self] in
			self?.completeBrowserCameraRoutingScriptInstall(
				for: browser,
				tabID: tabID,
				lifecycleGeneration: lifecycleGeneration
			)
		}
	}

	private func bindOpenURLInTabHandler(for browser: CEFBridgeBrowserRef, tabID: BrowserTabID) {
		let lifecycleGeneration = self.lifecycleGeneration
		browserRuntime.setOpenURLInTabHandler(for: browser) { [weak self] event in
			guard let self else { return }
			guard self.lifecycleGeneration == lifecycleGeneration else { return }
			guard self.browserContainersByTabID[tabID]?.browserRef == browser else { return }
			self.sidebarViewModel.openNewTab(with: event.url, activate: event.activatesTab)
		}
	}

	private func bindCameraRoutingEventHandler(for browser: CEFBridgeBrowserRef, tabID: BrowserTabID) {
		let lifecycleGeneration = self.lifecycleGeneration
		browserRuntime.setCameraRoutingEventHandler(for: browser) { [weak self] event in
			guard let self else { return }
			guard self.lifecycleGeneration == lifecycleGeneration else { return }
			guard self.browserContainersByTabID[tabID]?.browserRef == browser else { return }
			self.handleCameraRoutingEvent(event, for: tabID)
		}
	}

	private func bindPermissionPromptHandler(for browser: CEFBridgeBrowserRef, tabID: BrowserTabID) {
		let lifecycleGeneration = self.lifecycleGeneration
		BrowserPermissionPromptBinding.bind(
			browserRuntime: browserRuntime,
			browser: browser,
			expectedLifecycleGeneration: lifecycleGeneration,
			currentLifecycleGeneration: { [weak self] in
				self?.lifecycleGeneration ?? .min
			},
			container: { [weak self] in
				self?.browserContainersByTabID[tabID]
			},
			onSessionChange: { [weak self] session in
				self?.handleCameraPermissionPromptSession(session, for: tabID)
			},
			resolve: { [weak self] sessionID, decision, persistence in
				guard let self else { return }
				self.handleCameraPermissionResolution(
					for: tabID,
					decision: decision
				)
				self.browserRuntime.resolvePermissionPrompt(
					sessionID: sessionID,
					decision: decision,
					persistence: persistence
				)
			},
			cancel: { [weak self] sessionID in
				guard let self else { return }
				self.clearCameraConsumer(for: tabID)
				self.browserRuntime.cancelPermissionPrompt(sessionID: sessionID)
			},
			setProtection: { [weak self] isProtected in
				guard let self else { return }
				self.setProtection(isProtected, reason: .permissionPrompt, for: tabID)
			}
		)
	}

	private func handleCameraPermissionPromptSession(
		_ session: BrowserPermissionSession?,
		for tabID: BrowserTabID
	) {
		guard let session else {
			pendingCameraPermissionSessionsByTabID.removeValue(forKey: tabID)
			return
		}
		guard session.requestedKinds.contains(.camera) || session.promptKinds.contains(.camera) else {
			pendingCameraPermissionSessionsByTabID.removeValue(forKey: tabID)
			return
		}
		pendingCameraPermissionSessionsByTabID[tabID] = session
	}

	private func handleCameraPermissionResolution(
		for tabID: BrowserTabID,
		decision: BrowserPermissionPromptDecision
	) {
		let hadCameraRequest = pendingCameraPermissionSessionsByTabID.removeValue(forKey: tabID) != nil
		guard hadCameraRequest else { return }
		switch decision {
		case .allow:
			break
		case .deny:
			guard (activeManagedCameraTrackCountByTabID[tabID] ?? 0) == 0 else { break }
			browserCameraSessionCoordinator.unregisterConsumer(id: tabID.uuidString)
		}
	}

	private func handleCameraRoutingEvent(
		_ event: BrowserCameraRoutingEvent,
		for tabID: BrowserTabID
	) {
		browserCameraSessionCoordinator.noteBrowserRoutingEvent(
			tabID: tabID.uuidString,
			event: event
		)
		let resolution = BrowserCameraManagedDemandTracker.resolve(
			currentActiveManagedTrackCount: activeManagedCameraTrackCountByTabID[tabID],
			event: event
		)
		if resolution.nextActiveManagedTrackCount == 0 {
			activeManagedCameraTrackCountByTabID.removeValue(forKey: tabID)
		}
		else {
			activeManagedCameraTrackCountByTabID[tabID] = resolution.nextActiveManagedTrackCount
		}

		if resolution.shouldRegisterConsumer {
			browserCameraSessionCoordinator.registerConsumer(
				BrowserCameraConsumer(
					id: tabID.uuidString,
					kind: .browserTabCapture,
					requiresLiveFrames: true
				)
			)
		}
		if resolution.shouldUnregisterConsumer {
			browserCameraSessionCoordinator.unregisterConsumer(id: tabID.uuidString)
		}
		syncBrowserTransportState(for: tabID)
	}

	private func clearCameraConsumer(for tabID: BrowserTabID) {
		pendingCameraPermissionSessionsByTabID.removeValue(forKey: tabID)
		activeManagedCameraTrackCountByTabID.removeValue(forKey: tabID)
		rendererCameraRoutingTransportReadyTabIDs.remove(tabID)
		rendererManagedFrameTransportReadyTabIDs.remove(tabID)
		syncBrowserTransportState(for: tabID)
		browserCameraSessionCoordinator.unregisterConsumer(id: tabID.uuidString)
	}

	private func clearAllCameraConsumers() {
		let trackedTabIDs = Set(browserContainersByTabID.keys).union(pendingCameraPermissionSessionsByTabID.keys)
		for tabID in trackedTabIDs {
			clearCameraConsumer(for: tabID)
		}
	}

	private func bindSidebarActions() {
		sidebarViewModel.setActions(
			BrowserSidebarActions(
				onGoBack: { [weak self] tabID in
					guard let self else { return }
					self.activateCommittedTab(tabID)
					self.beginProvisionalNavigationIfNeeded(for: tabID)
					self.browserRuntime.noteBrowserActivity()
					let container = self.browserContainersByTabID[tabID]
					if container?.goBackInPresentedTopLevelNativeContent() == true {
						self.browserRuntime.goBack(container?.browserRef)
						self.syncNavigationState(for: tabID)
						return
					}
					guard let tab = self.tabViewModel(for: tabID) else {
						self.browserRuntime.goBack(container?.browserRef)
						return
					}
					switch self.restoredHistoryCoordinator.goBack(for: tab) {
					case .loadURL(let url):
						container?.load(url)
						self.syncNavigationState(for: tabID)
					case .runtimeBack:
						self.browserRuntime.goBack(container?.browserRef)
					case .none, .runtimeForward, .runtimeReload:
						self.syncNavigationState(for: tabID)
					}
				},
				onGoForward: { [weak self] tabID in
					guard let self else { return }
					self.activateCommittedTab(tabID)
					self.beginProvisionalNavigationIfNeeded(for: tabID)
					self.browserRuntime.noteBrowserActivity()
					let container = self.browserContainersByTabID[tabID]
					if container?.goForwardInPresentedTopLevelNativeContent() == true {
						self.syncNavigationState(for: tabID)
						return
					}
					guard let tab = self.tabViewModel(for: tabID) else {
						self.browserRuntime.goForward(container?.browserRef)
						return
					}
					switch self.restoredHistoryCoordinator.goForward(for: tab) {
					case .loadURL(let url):
						container?.load(url)
						self.syncNavigationState(for: tabID)
					case .runtimeForward:
						self.browserRuntime.goForward(container?.browserRef)
					case .none, .runtimeBack, .runtimeReload:
						self.syncNavigationState(for: tabID)
					}
				},
				onReload: { [weak self] tabID in
					guard let self else { return }
					self.activateCommittedTab(tabID)
					self.beginProvisionalNavigationIfNeeded(for: tabID)
					self.browserRuntime.noteBrowserActivity()
					let container = self.browserContainersByTabID[tabID]
					if container?.reloadPresentedTopLevelNativeContent() == true {
						self.syncNavigationState(for: tabID)
						return
					}
					guard let tab = self.tabViewModel(for: tabID) else {
						self.browserRuntime.reload(container?.browserRef)
						return
					}
					let historyUpdate = self.restoredHistoryCoordinator.reload(for: tab)
					self.sidebarViewModel.updateTabSessionHistory(
						entries: historyUpdate.entries,
						currentIndex: historyUpdate.currentIndex,
						for: tabID
					)
					self.browserRuntime.reload(container?.browserRef)
				},
				onSubmitAddress: { [weak self] tabID, url in
					guard let self else { return }
					let container = self.browserContainersByTabID[tabID]
					self.activateCommittedTab(tabID)
					self.beginProvisionalNavigationIfNeeded(for: tabID)
					self.browserRuntime.noteBrowserActivity()
					if let tab = self.tabViewModel(for: tabID) {
						let historyUpdate = self.restoredHistoryCoordinator.submitAddress(url, for: tab)
						self.sidebarViewModel.updateTabSessionHistory(
							entries: historyUpdate.entries,
							currentIndex: historyUpdate.currentIndex,
							for: tabID
						)
						switch historyUpdate.action {
						case .loadURL(let resolvedURL):
							container?.load(resolvedURL)
						case .none:
							break
						case .runtimeBack, .runtimeForward, .runtimeReload:
							container?.load(url)
						}
					}
					else {
						container?.load(url)
					}
					self.syncNavigationState(for: tabID)
				},
				navigationState: { [weak self] tabID in
					self?.navigationState(for: tabID) ?? .idle
				},
				cameraControls: makeSidebarCameraControls()
			)
		)
		sidebarViewModel.refreshCameraState()
	}

	private func makeSidebarCameraControls() -> BrowserSidebarCameraControls {
		BrowserSidebarCameraControls(
			snapshot: { [weak self] in
				MainActor.assumeIsolated {
					self?.browserCameraSessionCoordinator.currentSnapshot() ?? Self.unavailableBrowserCameraSnapshot
				}
			},
			routingConfiguration: { [weak self] in
				MainActor.assumeIsolated {
					self?.browserCameraSessionCoordinator.currentRoutingConfiguration()
						?? Self.unavailableBrowserCameraRoutingConfiguration
				}
			},
			previewFrame: { [weak self] in
				MainActor.assumeIsolated {
					self?.browserCameraSessionCoordinator.currentPreviewFrame()
				}
			},
			refreshAvailableDevices: { [weak self] in
				MainActor.assumeIsolated {
					guard let self else { return }
					self.browserCameraSessionCoordinator.refreshAvailableDevices()
					self.sidebarViewModel.refreshCameraState()
				}
			},
			setRoutingEnabled: { [weak self] isEnabled in
				MainActor.assumeIsolated {
					guard let self else { return }
					self.browserCameraSessionCoordinator.setRoutingEnabled(isEnabled)
					self.sidebarViewModel.refreshCameraState()
				}
			},
			setPreferredSourceID: { [weak self] preferredSourceID in
				MainActor.assumeIsolated {
					guard let self else { return }
					self.browserCameraSessionCoordinator.setPreferredDeviceID(preferredSourceID)
					self.sidebarViewModel.refreshCameraState()
				}
			},
			setPreferredFilterPreset: { [weak self] preferredFilterPreset in
				MainActor.assumeIsolated {
					guard let self else { return }
					self.browserCameraSessionCoordinator.setPreferredFilterPreset(preferredFilterPreset)
					self.sidebarViewModel.refreshCameraState()
				}
			},
			setPreferredGrainPresence: { [weak self] preferredGrainPresence in
				MainActor.assumeIsolated {
					guard let self else { return }
					self.browserCameraSessionCoordinator.setPreferredGrainPresence(preferredGrainPresence)
					self.sidebarViewModel.refreshCameraState()
				}
			},
			setPrefersHorizontalFlip: { [weak self] prefersHorizontalFlip in
				MainActor.assumeIsolated {
					guard let self else { return }
					self.browserCameraSessionCoordinator.setPrefersHorizontalFlip(prefersHorizontalFlip)
					self.sidebarViewModel.refreshCameraState()
				}
			},
			setPreviewEnabled: { [weak self] isEnabled in
				MainActor.assumeIsolated {
					guard let self else { return }
					self.browserCameraSessionCoordinator.setPreviewEnabled(isEnabled)
					self.sidebarViewModel.refreshCameraState()
				}
			}
		)
	}

	private static let unavailableBrowserCameraRoutingConfiguration = BrowserCameraRoutingConfiguration(
		settings: .defaults,
		outputMode: .unavailable
	)

	private static let unavailableBrowserCameraSnapshot = BrowserCameraSessionSnapshot(
		lifecycleState: .idle,
		healthState: .healthy,
		outputMode: .unavailable,
		routingSettings: .defaults,
		availableSources: [],
		activeConsumersByID: [:],
		performanceMetrics: .empty,
		lastErrorDescription: nil
	)

	func handleWindowVisibilityChange(isEffectivelyVisible: Bool) {
		guard tabLifecycleConfiguration.isEnabled else { return }
		guard !isEffectivelyVisible else { return }
		logLifecycleEvent("windowVisibilityReclaim")
		evictHiddenBrowsersIfNeeded(force: true)
	}

	func handleMemoryPressure() {
		guard tabLifecycleConfiguration.isEnabled else { return }
		logLifecycleEvent("memoryPressureReclaim")
		evictHiddenBrowsersIfNeeded(force: true)
	}

	func recordCommitWorthyInteraction(for tabID: BrowserTabID) {
		guard tabLifecycleConfiguration.isEnabled else { return }
		guard let record = tabLifecycleRecords[tabID] else { return }
		guard case let .transientSelected(sessionID) = record.intentState else { return }
		commitTransientSelection(for: tabID, sessionID: sessionID)
	}

	private func syncNavigationState(for tabID: BrowserTabID) {
		let state = navigationState(for: tabID)
		sidebarViewModel.updateNavigationState(state, for: tabID)
		guard var record = tabLifecycleRecords[tabID] else { return }
		if state.isLoading {
			if record.navigationState == .none {
				record.navigationState = .provisional
			}
		}
		else if record.navigationState == .provisional || record.navigationState == .committed {
			record.navigationState = .finished
		}
		tabLifecycleRecords[tabID] = record
	}

	private func navigationState(for tabID: BrowserTabID) -> BrowserSidebarNavigationState {
		guard let container = browserContainersByTabID[tabID], let browser = container.browserRef else { return .idle }
		let browserState = BrowserSidebarNavigationState(
			canGoBack: browserRuntime.canGoBack(browser),
			canGoForward: browserRuntime.canGoForward(browser),
			isLoading: browserRuntime.isLoading(browser)
		)
		let containerState = container.navigationState(overriding: browserState)
		guard let tab = tabViewModel(for: tabID) else { return containerState }
		return restoredHistoryCoordinator.navigationState(
			for: tab,
			browserState: containerState
		)
	}

	private func tabViewModel(for tabID: BrowserTabID) -> BrowserTabViewModel? {
		sidebarViewModel.tabs.first(where: { $0.id == tabID })
	}

	private func captureScrollStateIfNeeded(for tabID: BrowserTabID) {
		guard tabLifecycleConfiguration.isEnabled else { return }
		guard let container = browserContainersByTabID[tabID], let browser = container.browserRef else { return }
		let currentURL = sidebarViewModel.tabs.first(where: { $0.id == tabID })?.currentURL ?? container.pendingURL
		guard currentURL.isEmpty == false else { return }
		let captureScript = "JSON.stringify({x: window.scrollX || 0, y: window.scrollY || 0})"
		browserRuntime.evaluateJavaScriptWithResult(browser, script: captureScript) { [weak self] result, _ in
			guard let self, var record = self.tabLifecycleRecords[tabID] else { return }
			guard let result, let position = self.scrollPosition(from: result) else { return }
			record.capturedScrollState = .init(url: currentURL, position: position)
			self.tabLifecycleRecords[tabID] = record
		}
	}

	private func restoreScrollStateIfNeeded(for tabID: BrowserTabID) {
		guard tabLifecycleConfiguration.isEnabled else { return }
		guard let record = tabLifecycleRecords[tabID], let capturedScrollState = record.capturedScrollState else { return }
		guard let container = browserContainersByTabID[tabID], let browser = container.browserRef else { return }
		let currentURL = sidebarViewModel.tabs.first(where: { $0.id == tabID })?.currentURL ?? container.pendingURL
		guard currentURL == capturedScrollState.url else { return }
		let x = capturedScrollState.position.x
		let y = capturedScrollState.position.y
		let restoreScript = """
		(function() {
		  const targetX = \(x);
		  const targetY = \(y);
		  let attempts = 8;
		  function apply() {
		    window.scrollTo(targetX, targetY);
		    attempts -= 1;
		    if (attempts > 0 && (Math.abs(window.scrollX - targetX) > 1 || Math.abs(window.scrollY - targetY) > 1)) {
		      window.requestAnimationFrame(apply);
		    }
		  }
		  apply();
		})();
		"""
		browserRuntime.evaluateJavaScriptWithResult(browser, script: restoreScript) { _, _ in }
	}

	private func scrollPosition(from json: String) -> BrowserRuntimeScrollPosition? {
		guard let data = json.data(using: .utf8) else { return nil }
		guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
		guard let x = payload["x"] as? Double, let y = payload["y"] as? Double else { return nil }
		return BrowserRuntimeScrollPosition(x: x, y: y)
	}

	private func shouldProtectForAuthSensitiveFlow(_ event: BrowserRuntimeMainFrameNavigationEvent) -> Bool {
		guard isAuthSensitiveURL(event.url) else { return false }
		return event.isRedirect || event.userGesture == false
	}

	private func isAuthSensitiveURL(_ url: String) -> Bool {
		guard let components = URLComponents(string: url.lowercased()) else { return false }
		let host = components.host ?? ""
		let path = components.path
		let query = components.percentEncodedQuery ?? ""
		let searchSpace = [host, path, query].joined(separator: " ")
		let authMarkers = [
			"oauth",
			"authorize",
			"login",
			"signin",
			"saml",
			"auth",
			"auth0",
			"accounts.google",
			"microsoftonline",
			"okta",
		]
		return authMarkers.contains(where: { searchSpace.contains($0) })
	}

	private func normalizedFaviconURL(from value: String) -> String? {
		let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmedValue.isEmpty ? nil : trimmedValue
	}

	private func logLifecycleEvent(_ message: String) {
		print("[Navigator][TabLifecycle] \(message)")
	}

	private func locationInSidebar(for event: NSEvent) -> NSPoint? {
		guard let window else { return nil }
		guard let eventWindow = event.window, eventWindow == window else { return nil }

		guard bounds.width > 0, bounds.height > 0 else { return nil }
		guard bounds.origin.x.isFinite, bounds.origin.y.isFinite else { return nil }
		guard bounds.size.width.isFinite, bounds.size.height.isFinite else { return nil }

		let localPoint = convert(event.locationInWindow, from: nil)
		guard localPoint.x.isFinite, localPoint.y.isFinite else { return nil }

		return localPoint
	}

	override func hitTest(_ point: NSPoint) -> NSView? {
		return super.hitTest(point)
	}
}

private final class BrowserViewControllerRootView: NSView {
	private static let sidebarHitTestPadding: CGFloat = 32
	private let sidebarPresentation: BrowserSidebarPresentation
	private let sidebarWidthProvider: () -> CGFloat

	init(sidebarPresentation: BrowserSidebarPresentation, sidebarWidthProvider: @escaping () -> CGFloat) {
		self.sidebarPresentation = sidebarPresentation
		self.sidebarWidthProvider = sidebarWidthProvider
		super.init(frame: .zero)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func hitTest(_ point: NSPoint) -> NSView? {
		if sidebarPresentation.isPresented,
		   point.x >= 0,
		   point.x <= sidebarWidthProvider() + Self.sidebarHitTestPadding {
			return nil
		}
		return super.hitTest(point)
	}
}
