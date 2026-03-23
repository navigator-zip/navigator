import AppKit
import BrowserCameraKit
import BrowserRuntime
import BrowserSidebar
@testable import BrowserView
import CoreGraphics
import ModelKit

@MainActor
final class BrowserRuntimeSpy: BrowserRuntimeDriving {
	private(set) var noteBrowserActivityCount = 0
	private(set) var createBrowserRequests = [(parentView: NSView, initialURL: String)]()
	private(set) var resizeBrowserRequests = [(browser: CEFBridgeBrowserRef?, view: NSView)]()
	private(set) var loadRequests = [(browser: CEFBridgeBrowserRef?, url: String)]()
	private(set) var stopLoadRequests = [CEFBridgeBrowserRef?]()
	private(set) var closeRequests = [CEFBridgeBrowserRef?]()
	private(set) var goBackRequests = [CEFBridgeBrowserRef?]()
	private(set) var goForwardRequests = [CEFBridgeBrowserRef?]()
	private(set) var reloadRequests = [CEFBridgeBrowserRef?]()
	private(set) var evaluateJavaScriptRequests = [(browser: CEFBridgeBrowserRef?, script: String)]()
	private(set) var evaluateJavaScriptInRendererRequests = [(browser: CEFBridgeBrowserRef?, script: String)]()
	private(set) var sendRendererProcessMessageRequests = [(
		browser: CEFBridgeBrowserRef?,
		channel: String,
		jsonPayload: String
	)]()
	private(set) var resolvedPermissionPrompts = [(
		sessionID: BrowserPermissionSessionID,
		decision: BrowserPermissionPromptDecision,
		persistence: BrowserPermissionPersistence
	)]()
	private(set) var cancelledPermissionPromptSessionIDs = [BrowserPermissionSessionID]()

	var createBrowserResults = [CEFBridgeBrowserRef?]()
	var hasPendingNativeBrowserCloseResults = [Bool]()
	var hasPendingNativeBrowserCloseValue = false
	var evaluateJavaScriptResults = [(result: String?, error: String?)]()
	var evaluateJavaScriptInRendererResults = [(result: String?, error: String?)]()
	var sendRendererProcessMessageResults = [(result: String?, error: String?)]()
	var browserCameraRoutingJavaScriptResults = [(result: String?, error: String?)]()
	var onClose: ((CEFBridgeBrowserRef?) -> Void)?

	private var addressHandlers = [UInt: (String) -> Void]()
	private var faviconHandlers = [UInt: (String) -> Void]()
	private var titleHandlers = [UInt: (String) -> Void]()
	private var topLevelNativeContentHandlers = [UInt: (BrowserRuntimeTopLevelNativeContent) -> Void]()
	private var renderProcessTerminationHandlers = [UInt: (BrowserRuntimeRenderProcessTermination) -> Void]()
	private var mainFrameNavigationHandlers = [UInt: (BrowserRuntimeMainFrameNavigationEvent) -> Void]()
	private var openURLInTabHandlers = [UInt: (BrowserRuntimeOpenURLInTabEvent) -> Void]()
	private var cameraRoutingEventHandlers = [UInt: (BrowserCameraRoutingEvent) -> Void]()
	private var permissionPromptHandlers = [UInt: (BrowserPermissionSession?) -> Void]()
	private var navigationStates = [UInt: BrowserSidebarNavigationState]()

	func noteBrowserActivity() {
		noteBrowserActivityCount += 1
	}

	func hasPendingNativeBrowserClose() -> Bool {
		if !hasPendingNativeBrowserCloseResults.isEmpty {
			return hasPendingNativeBrowserCloseResults.removeFirst()
		}
		return hasPendingNativeBrowserCloseValue
	}

	func createBrowser(in parentView: NSView, initialURL: String) -> CEFBridgeBrowserRef? {
		createBrowserRequests.append((parentView, initialURL))
		guard !createBrowserResults.isEmpty else { return nil }
		return createBrowserResults.removeFirst()
	}

	func resizeBrowser(_ browser: CEFBridgeBrowserRef?, in view: NSView) {
		resizeBrowserRequests.append((browser, view))
	}

	func load(_ browser: CEFBridgeBrowserRef?, url: String) {
		loadRequests.append((browser, url))
	}

	func stopLoad(_ browser: CEFBridgeBrowserRef?) {
		stopLoadRequests.append(browser)
	}

	func close(_ browser: CEFBridgeBrowserRef?) {
		closeRequests.append(browser)
		onClose?(browser)
	}

	func setAddressChangeHandler(
		for browser: CEFBridgeBrowserRef?,
		handler: ((String) -> Void)?
	) {
		setHandler(handler, for: browser, in: &addressHandlers)
	}

	func setFaviconURLChangeHandler(
		for browser: CEFBridgeBrowserRef?,
		handler: ((String) -> Void)?
	) {
		setHandler(handler, for: browser, in: &faviconHandlers)
	}

	func setTitleChangeHandler(
		for browser: CEFBridgeBrowserRef?,
		handler: ((String) -> Void)?
	) {
		setHandler(handler, for: browser, in: &titleHandlers)
	}

	func setTopLevelNativeContentHandler(
		for browser: CEFBridgeBrowserRef?,
		supportedKinds _: Set<BrowserRuntimeTopLevelNativeContentKind>,
		handler: ((BrowserRuntimeTopLevelNativeContent) -> Void)?
	) {
		setHandler(handler, for: browser, in: &topLevelNativeContentHandlers)
	}

	func setRenderProcessTerminationHandler(
		for browser: CEFBridgeBrowserRef?,
		handler: ((BrowserRuntimeRenderProcessTermination) -> Void)?
	) {
		setHandler(handler, for: browser, in: &renderProcessTerminationHandlers)
	}

	func setMainFrameNavigationHandler(
		for browser: CEFBridgeBrowserRef?,
		handler: ((BrowserRuntimeMainFrameNavigationEvent) -> Void)?
	) {
		setHandler(handler, for: browser, in: &mainFrameNavigationHandlers)
	}

	func setOpenURLInTabHandler(
		for browser: CEFBridgeBrowserRef?,
		handler: ((BrowserRuntimeOpenURLInTabEvent) -> Void)?
	) {
		setHandler(handler, for: browser, in: &openURLInTabHandlers)
	}

	func setCameraRoutingEventHandler(
		for browser: CEFBridgeBrowserRef?,
		handler: ((BrowserCameraRoutingEvent) -> Void)?
	) {
		setHandler(handler, for: browser, in: &cameraRoutingEventHandlers)
	}

	func setPermissionPromptHandler(
		for browser: CEFBridgeBrowserRef?,
		handler: ((BrowserPermissionSession?) -> Void)?
	) {
		setHandler(handler, for: browser, in: &permissionPromptHandlers)
	}

	func resolvePermissionPrompt(
		sessionID: BrowserPermissionSessionID,
		decision: BrowserPermissionPromptDecision,
		persistence: BrowserPermissionPersistence
	) {
		resolvedPermissionPrompts.append((sessionID, decision, persistence))
	}

	func cancelPermissionPrompt(sessionID: BrowserPermissionSessionID) {
		cancelledPermissionPromptSessionIDs.append(sessionID)
	}

	func evaluateJavaScriptWithResult(
		_ browser: CEFBridgeBrowserRef?,
		script: String,
		completion: @escaping @MainActor (String?, String?) -> Void
	) {
		evaluateJavaScriptRequests.append((browser, script))
		let nextResult: (result: String?, error: String?) = if script.contains("__navigatorCameraRoutingShim") {
			browserCameraRoutingJavaScriptResults.isEmpty
				? ("installed", nil)
				: browserCameraRoutingJavaScriptResults.removeFirst()
		}
		else {
			evaluateJavaScriptResults.isEmpty ? (nil, nil) : evaluateJavaScriptResults.removeFirst()
		}
		completion(nextResult.0, nextResult.1)
	}

	func evaluateJavaScriptInRendererWithResult(
		_ browser: CEFBridgeBrowserRef?,
		script: String,
		completion: @escaping @MainActor (String?, String?) -> Void
	) {
		evaluateJavaScriptInRendererRequests.append((browser, script))
		let nextResult = evaluateJavaScriptInRendererResults.isEmpty
			? ("{\"acknowledged\":true}", "")
			: evaluateJavaScriptInRendererResults.removeFirst()
		completion(nextResult.0, nextResult.1)
	}

	func sendRendererProcessMessage(
		_ browser: CEFBridgeBrowserRef?,
		channel: String,
		jsonPayload: String,
		completion: @escaping @MainActor (String?, String?) -> Void
	) {
		sendRendererProcessMessageRequests.append((browser, channel, jsonPayload))
		let nextResult = sendRendererProcessMessageResults.isEmpty
			? ("{\"acknowledged\":true}", nil)
			: sendRendererProcessMessageResults.removeFirst()
		completion(nextResult.0, nextResult.1)
	}

	func goBack(_ browser: CEFBridgeBrowserRef?) {
		goBackRequests.append(browser)
	}

	func goForward(_ browser: CEFBridgeBrowserRef?) {
		goForwardRequests.append(browser)
	}

	func reload(_ browser: CEFBridgeBrowserRef?) {
		reloadRequests.append(browser)
	}

	func canGoBack(_ browser: CEFBridgeBrowserRef?) -> Bool {
		state(for: browser).canGoBack
	}

	func canGoForward(_ browser: CEFBridgeBrowserRef?) -> Bool {
		state(for: browser).canGoForward
	}

	func isLoading(_ browser: CEFBridgeBrowserRef?) -> Bool {
		state(for: browser).isLoading
	}

	func setNavigationState(_ state: BrowserSidebarNavigationState, for browser: CEFBridgeBrowserRef?) {
		navigationStates[key(for: browser)] = state
	}

	func fireAddressChange(_ url: String, for browser: CEFBridgeBrowserRef?) {
		addressHandlers[key(for: browser)]?(url)
	}

	func fireFaviconURLChange(_ url: String, for browser: CEFBridgeBrowserRef?) {
		faviconHandlers[key(for: browser)]?(url)
	}

	func fireTitleChange(_ title: String, for browser: CEFBridgeBrowserRef?) {
		titleHandlers[key(for: browser)]?(title)
	}

	func fireTopLevelNativeContent(_ content: BrowserRuntimeTopLevelNativeContent, for browser: CEFBridgeBrowserRef?) {
		topLevelNativeContentHandlers[key(for: browser)]?(content)
	}

	func fireRenderProcessTermination(
		_ termination: BrowserRuntimeRenderProcessTermination,
		for browser: CEFBridgeBrowserRef?
	) {
		renderProcessTerminationHandlers[key(for: browser)]?(termination)
	}

	func fireMainFrameNavigationEvent(
		_ event: BrowserRuntimeMainFrameNavigationEvent,
		for browser: CEFBridgeBrowserRef?
	) {
		mainFrameNavigationHandlers[key(for: browser)]?(event)
	}

	func fireOpenURLInTabEvent(
		_ event: BrowserRuntimeOpenURLInTabEvent,
		for browser: CEFBridgeBrowserRef?
	) {
		openURLInTabHandlers[key(for: browser)]?(event)
	}

	func fireCameraRoutingEvent(
		_ event: BrowserCameraRoutingEvent,
		for browser: CEFBridgeBrowserRef?
	) {
		cameraRoutingEventHandlers[key(for: browser)]?(event)
	}

	func firePermissionPrompt(_ session: BrowserPermissionSession?, for browser: CEFBridgeBrowserRef?) {
		permissionPromptHandlers[key(for: browser)]?(session)
	}

	private func state(for browser: CEFBridgeBrowserRef?) -> BrowserSidebarNavigationState {
		navigationStates[key(for: browser)] ?? .idle
	}

	private func key(for browser: CEFBridgeBrowserRef?) -> UInt {
		UInt(bitPattern: browser)
	}

	private func setHandler(
		_ handler: ((String) -> Void)?,
		for browser: CEFBridgeBrowserRef?,
		in storage: inout [UInt: (String) -> Void]
	) {
		let browserKey = key(for: browser)
		if let handler {
			storage[browserKey] = handler
		}
		else {
			storage.removeValue(forKey: browserKey)
		}
	}

	private func setHandler(
		_ handler: ((BrowserRuntimeTopLevelNativeContent) -> Void)?,
		for browser: CEFBridgeBrowserRef?,
		in storage: inout [UInt: (BrowserRuntimeTopLevelNativeContent) -> Void]
	) {
		let browserKey = key(for: browser)
		if let handler {
			storage[browserKey] = handler
		}
		else {
			storage.removeValue(forKey: browserKey)
		}
	}

	private func setHandler(
		_ handler: ((BrowserRuntimeRenderProcessTermination) -> Void)?,
		for browser: CEFBridgeBrowserRef?,
		in storage: inout [UInt: (BrowserRuntimeRenderProcessTermination) -> Void]
	) {
		let browserKey = key(for: browser)
		if let handler {
			storage[browserKey] = handler
		}
		else {
			storage.removeValue(forKey: browserKey)
		}
	}

	private func setHandler(
		_ handler: ((BrowserRuntimeMainFrameNavigationEvent) -> Void)?,
		for browser: CEFBridgeBrowserRef?,
		in storage: inout [UInt: (BrowserRuntimeMainFrameNavigationEvent) -> Void]
	) {
		let browserKey = key(for: browser)
		if let handler {
			storage[browserKey] = handler
		}
		else {
			storage.removeValue(forKey: browserKey)
		}
	}

	private func setHandler(
		_ handler: ((BrowserRuntimeOpenURLInTabEvent) -> Void)?,
		for browser: CEFBridgeBrowserRef?,
		in storage: inout [UInt: (BrowserRuntimeOpenURLInTabEvent) -> Void]
	) {
		let browserKey = key(for: browser)
		if let handler {
			storage[browserKey] = handler
		}
		else {
			storage.removeValue(forKey: browserKey)
		}
	}

	private func setHandler(
		_ handler: ((BrowserCameraRoutingEvent) -> Void)?,
		for browser: CEFBridgeBrowserRef?,
		in storage: inout [UInt: (BrowserCameraRoutingEvent) -> Void]
	) {
		let browserKey = key(for: browser)
		if let handler {
			storage[browserKey] = handler
		}
		else {
			storage.removeValue(forKey: browserKey)
		}
	}

	private func setHandler(
		_ handler: ((BrowserPermissionSession?) -> Void)?,
		for browser: CEFBridgeBrowserRef?,
		in storage: inout [UInt: (BrowserPermissionSession?) -> Void]
	) {
		let browserKey = key(for: browser)
		if let handler {
			storage[browserKey] = handler
		}
		else {
			storage.removeValue(forKey: browserKey)
		}
	}
}

@MainActor
final class BrowserCameraSessionCoordinatorSpy: BrowserCameraSessionCoordinating {
	var lifecycleState: BrowserCameraLifecycleState = .idle
	var healthState: BrowserCameraHealthState = .healthy
	var outputMode: BrowserCameraOutputMode = .processedNavigatorFeed
	var routingSettings = BrowserCameraRoutingSettings.defaults
	var availableSources = [
		BrowserCameraSource(
			id: "camera-a",
			name: "FaceTime HD",
			isDefault: true
		),
	]
	var lastErrorDescription: String?
	private(set) var refreshAvailableDevicesCount = 0
	private(set) var registeredConsumers = [BrowserCameraConsumer]()
	private(set) var unregisteredConsumerIDs = [String]()
	private(set) var notedRoutingEvents = [(tabID: String, event: BrowserCameraRoutingEvent)]()
	private(set) var notedFallbacks = [(tabID: String, reason: String)]()
	private(set) var removedSnapshotObserverIDs = [UUID]()
	private(set) var removedPreviewObserverIDs = [UUID]()
	private var activeConsumersByID = [String: BrowserCameraConsumer]()
	private(set) var browserTransportStatesByTabID = [String: BrowserCameraBrowserTransportState]()
	private var snapshotObservers = [UUID: @MainActor (BrowserCameraSessionSnapshot) -> Void]()
	private var previewObservers = [UUID: @MainActor (CGImage?) -> Void]()
	var performanceMetrics = BrowserCameraPerformanceMetrics.empty
	var previewFrame: CGImage?

	func currentSnapshot() -> BrowserCameraSessionSnapshot {
		BrowserCameraSessionSnapshot(
			lifecycleState: lifecycleState,
			healthState: healthState,
			outputMode: outputMode,
			routingSettings: routingSettings,
			availableSources: availableSources,
			activeConsumersByID: activeConsumersByID,
			performanceMetrics: performanceMetrics,
			lastErrorDescription: lastErrorDescription,
			publisherStatus: .notRequired,
			browserTransportStates: browserTransportStatesByTabID.values.sorted { lhs, rhs in
				lhs.tabID.localizedStandardCompare(rhs.tabID) == .orderedAscending
			},
			recentDiagnosticEvents: []
		)
	}

	func currentDebugSummary() -> BrowserCameraDebugSummary {
		currentSnapshot().debugSummary
	}

	func currentRoutingConfiguration() -> BrowserCameraRoutingConfiguration {
		currentSnapshot().routingConfiguration
	}

	func currentPreviewFrame() -> CGImage? {
		previewFrame
	}

	func refreshAvailableDevices() {
		refreshAvailableDevicesCount += 1
	}

	func registerConsumer(_ consumer: BrowserCameraConsumer) {
		registeredConsumers.append(consumer)
		activeConsumersByID[consumer.id] = consumer
	}

	func unregisterConsumer(id: String) {
		unregisteredConsumerIDs.append(id)
		activeConsumersByID.removeValue(forKey: id)
	}

	func setRoutingEnabled(_ isEnabled: Bool) {
		routingSettings.routingEnabled = isEnabled
	}

	func setPreferredDeviceID(_ preferredDeviceID: String?) {
		routingSettings.preferredSourceID = preferredDeviceID
	}

	func setPreferredFilterPreset(_ preferredFilterPreset: BrowserCameraFilterPreset) {
		routingSettings.preferredFilterPreset = preferredFilterPreset
	}

	func setPreferredGrainPresence(_ preferredGrainPresence: BrowserCameraPipelineGrainPresence) {
		routingSettings.preferredGrainPresence = preferredGrainPresence
	}

	func setPrefersHorizontalFlip(_ prefersHorizontalFlip: Bool) {
		routingSettings.prefersHorizontalFlip = prefersHorizontalFlip
	}

	func setPreviewEnabled(_ isEnabled: Bool) {
		routingSettings.previewEnabled = isEnabled
	}

	func noteBrowserRoutingEvent(tabID: String, event: BrowserCameraRoutingEvent) {
		notedRoutingEvents.append((tabID: tabID, event: event))
	}

	func noteBrowserProcessFallback(tabID: String, reason: String) {
		notedFallbacks.append((tabID: tabID, reason: reason))
	}

	func updateBrowserTransportState(_ state: BrowserCameraBrowserTransportState) {
		browserTransportStatesByTabID[state.tabID] = state
	}

	func clearBrowserTransportState(tabID: String) {
		browserTransportStatesByTabID.removeValue(forKey: tabID)
	}

	func addSnapshotObserver(
		_ observer: @escaping @MainActor (BrowserCameraSessionSnapshot) -> Void
	) -> UUID {
		let observerID = UUID()
		snapshotObservers[observerID] = observer
		observer(currentSnapshot())
		return observerID
	}

	func removeSnapshotObserver(id: UUID) {
		removedSnapshotObserverIDs.append(id)
		snapshotObservers.removeValue(forKey: id)
	}

	func addPreviewFrameObserver(
		_ observer: @escaping @MainActor (CGImage?) -> Void
	) -> UUID {
		let observerID = UUID()
		previewObservers[observerID] = observer
		observer(previewFrame)
		return observerID
	}

	func removePreviewFrameObserver(id: UUID) {
		removedPreviewObserverIDs.append(id)
		previewObservers.removeValue(forKey: id)
	}

	func emitSnapshotChange() {
		let snapshot = currentSnapshot()
		for observer in snapshotObservers.values {
			observer(snapshot)
		}
	}

	func emitPreviewFrameChange() {
		for observer in previewObservers.values {
			observer(previewFrame)
		}
	}
}

@MainActor
final class BrowserContainerSchedulerSpy {
	private struct ScheduledWork {
		let workItem: DispatchWorkItem
		let action: () -> Void
	}

	private var scheduledWork = [ScheduledWork]()

	var scheduleCount: Int {
		scheduledWork.count
	}

	var lastWorkItem: DispatchWorkItem? {
		scheduledWork.last?.workItem
	}

	func schedule(_ action: @escaping () -> Void) -> DispatchWorkItem {
		let workItem = DispatchWorkItem(block: {})
		scheduledWork.append(ScheduledWork(workItem: workItem, action: action))
		return workItem
	}

	func runLastScheduledWork() {
		guard let scheduled = scheduledWork.popLast() else { return }
		guard !scheduled.workItem.isCancelled else { return }
		scheduled.action()
	}
}

@MainActor
final class BrowserChromeEventMonitorSpy {
	private let mouseMoveToken = NSObject()
	private let interactionToken = NSObject()
	private(set) var addCount = 0
	private(set) var removeCount = 0
	private(set) var interactionAddCount = 0
	private var mouseMoveHandler: ((NSEvent) -> NSEvent?)?
	private var interactionHandler: ((NSEvent) -> NSEvent?)?

	var monitoring: BrowserChromeEventMonitoring {
		BrowserChromeEventMonitoring(
			addLocalMouseMovedMonitor: { [weak self] handler in
				guard let self else { return nil }
				addCount += 1
				mouseMoveHandler = handler
				return mouseMoveToken
			},
			addLocalCommitInteractionMonitor: { [weak self] handler in
				guard let self else { return nil }
				interactionAddCount += 1
				interactionHandler = handler
				return interactionToken
			},
			removeMonitor: { [weak self] _ in
				self?.removeCount += 1
				self?.mouseMoveHandler = nil
				self?.interactionHandler = nil
			}
		)
	}

	func send(_ event: NSEvent) -> NSEvent? {
		mouseMoveHandler?(event)
	}

	func sendInteraction(_ event: NSEvent) -> NSEvent? {
		interactionHandler?(event)
	}
}

@MainActor
final class BrowserChromeScheduledWorkSpy {
	private var scheduledActions = [Int: () -> Void]()
	private var nextID = 0
	private(set) var scheduleCount = 0

	func schedule(delay _: TimeInterval, action: @escaping () -> Void) -> () -> Void {
		scheduleCount += 1
		nextID += 1
		let id = nextID
		scheduledActions[id] = action
		return { [weak self] in
			self?.scheduledActions.removeValue(forKey: id)
		}
	}

	func runScheduledWork() {
		let nextKey = scheduledActions.keys.sorted().first
		let action = nextKey.flatMap { scheduledActions.removeValue(forKey: $0) }
		action?()
	}

	func runAllScheduledWork() {
		while !scheduledActions.isEmpty {
			runScheduledWork()
		}
	}
}

@MainActor
final class BrowserLifecycleTimeProvider {
	private(set) var now: TimeInterval

	init(now: TimeInterval = 0) {
		self.now = now
	}

	func advance(by delta: TimeInterval) {
		now += delta
	}
}

@MainActor
func makeBrowserSidebarViewModel(
	initialAddress: String = "https://navigator.zip"
) -> BrowserSidebarViewModel {
	BrowserSidebarViewModel(
		initialAddress: initialAddress,
		actions: BrowserSidebarActions(
			onGoBack: { _ in },
			onGoForward: { _ in },
			onReload: { _ in },
			onSubmitAddress: { _, _ in },
			navigationState: { _ in .idle }
		)
	)
}

func makeBrowserRef(_ rawValue: Int) -> CEFBridgeBrowserRef {
	UnsafeMutableRawPointer(bitPattern: rawValue)!
}

@MainActor
func makeWindow(size: CGSize = CGSize(width: 800, height: 600)) -> NSWindow {
	let window = NSWindow(
		contentRect: NSRect(origin: .zero, size: size),
		styleMask: [.titled, .closable, .resizable],
		backing: .buffered,
		defer: false
	)
	window.orderFront(nil)
	return window
}

@MainActor
func host(
	_ view: NSView,
	in window: NSWindow,
	size: CGSize = CGSize(width: 800, height: 600)
) {
	let contentView = NSView(frame: NSRect(origin: .zero, size: size))
	window.contentView = contentView
	contentView.addSubview(view)
	NSLayoutConstraint.activate([
		view.topAnchor.constraint(equalTo: contentView.topAnchor),
		view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
		view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
		view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
	])
	contentView.layoutSubtreeIfNeeded()
}

@MainActor
func makeMouseMovedEvent(
	window: NSWindow,
	location: CGPoint
) -> NSEvent {
	guard let event = NSEvent.mouseEvent(
		with: .mouseMoved,
		location: location,
		modifierFlags: [],
		timestamp: 0,
		windowNumber: window.windowNumber,
		context: nil,
		eventNumber: 0,
		clickCount: 0,
		pressure: 0
	) else {
		fatalError("Failed to create mouse move event")
	}
	return event
}

@MainActor
func makeKeyDownEvent(window: NSWindow) -> NSEvent {
	guard let event = NSEvent.keyEvent(
		with: .keyDown,
		location: .zero,
		modifierFlags: [],
		timestamp: 0,
		windowNumber: window.windowNumber,
		context: nil,
		characters: "a",
		charactersIgnoringModifiers: "a",
		isARepeat: false,
		keyCode: 0
	) else {
		fatalError("Failed to create key down event")
	}
	return event
}

@MainActor
func recursiveSubviews(in view: NSView) -> [NSView] {
	view.subviews + view.subviews.flatMap { recursiveSubviews(in: $0) }
}

@MainActor
func findButton(in view: NSView, title: String) -> NSButton? {
	recursiveSubviews(in: view)
		.compactMap { $0 as? NSButton }
		.first(where: { $0.title == title })
}

@MainActor
func findTextField(in view: NSView, containing substring: String) -> NSTextField? {
	recursiveSubviews(in: view)
		.compactMap { $0 as? NSTextField }
		.first(where: { $0.stringValue.contains(substring) })
}

@MainActor
func browserContainers(in view: NSView) -> [BrowserContainerView] {
	recursiveSubviews(in: view)
		.compactMap { $0 as? BrowserContainerView }
}

func makePermissionSession(
	id: BrowserPermissionSessionID,
	browserID: UInt64,
	promptID: UInt64? = nil,
	source: BrowserPermissionRequestSource = .permissionPrompt,
	requestingOrigin: String = "https://request.example",
	topLevelOrigin: String = "https://top.example",
	requestedKinds: BrowserPermissionKindSet = .camera,
	promptKinds: BrowserPermissionKindSet? = nil,
	state: BrowserPermissionSessionLifecycleState = .waitingForUserPrompt
) -> BrowserPermissionSession {
	BrowserPermissionSession(
		id: id,
		browserID: browserID,
		promptID: promptID ?? id + 100,
		frameIdentifier: "frame-\(id)",
		source: source,
		origin: .init(
			requestingOrigin: requestingOrigin,
			topLevelOrigin: topLevelOrigin
		),
		requestedKinds: requestedKinds,
		promptKinds: promptKinds ?? requestedKinds,
		state: state,
		siteDecision: nil,
		persistence: nil,
		osAuthorizationState: .init(),
		createdAt: Date(timeIntervalSince1970: 0),
		updatedAt: Date(timeIntervalSince1970: 0)
	)
}
