import AppKit
import BrowserRuntime
import BrowserSidebar
@testable import BrowserView
import ModelKit
import XCTest

@MainActor
final class BrowserContainerViewTests: XCTestCase {
	func testPublicInitializerConfiguresLiveBackedContainerView() {
		let container = BrowserContainerView(initialURL: "https://navigator.zip")
		container.resolveBrowserRuntimeForTesting()

		XCTAssertEqual(container.initialURL, "https://navigator.zip")
		XCTAssertFalse(container.translatesAutoresizingMaskIntoConstraints)
		XCTAssertTrue(container.wantsLayer)
		XCTAssertEqual(container.layer?.cornerRadius, 10)
		XCTAssertEqual(container.layer?.masksToBounds, true)
	}

	func testLoadQueuesURLAndSchedulesBrowserCreationWithoutWindow() {
		let runtime = BrowserRuntimeSpy()
		let scheduler = BrowserContainerSchedulerSpy()
		let container = BrowserContainerView(
			initialURL: "https://navigator.zip",
			browserRuntime: runtime,
			scheduleCreateBrowserWorkItem: scheduler.schedule
		)

		container.load("https://swift.org")

		XCTAssertEqual(container.initialURL, "https://navigator.zip")
		XCTAssertEqual(container.pendingURL, "https://swift.org")
		XCTAssertEqual(scheduler.scheduleCount, 1)
		XCTAssertTrue(runtime.createBrowserRequests.isEmpty)
		XCTAssertNil(container.browserRef)
	}

	func testCreateBrowserIfNeededCreatesBrowserAndInvokesCreationCallback() {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x101)
		runtime.createBrowserResults = [browser]
		let container = BrowserContainerView(
			initialURL: "https://navigator.zip",
			browserRuntime: runtime
		)
		let window = makeWindow(size: CGSize(width: 640, height: 480))
		host(container, in: window, size: CGSize(width: 640, height: 480))
		var createdBrowser: CEFBridgeBrowserRef?
		container.onBrowserCreated = { createdBrowser = $0 }

		container.createBrowserIfNeeded()

		XCTAssertEqual(runtime.createBrowserRequests.count, 1)
		XCTAssertEqual(runtime.createBrowserRequests.first?.initialURL, "https://navigator.zip")
		XCTAssertEqual(container.browserRef, browser)
		XCTAssertEqual(createdBrowser, browser)
	}

	func testCreateBrowserIfNeededDefersForZeroSizedBoundsAndPendingClose() {
		let runtime = BrowserRuntimeSpy()
		let scheduler = BrowserContainerSchedulerSpy()
		let zeroSizedContainer = BrowserContainerView(
			initialURL: "https://navigator.zip",
			browserRuntime: runtime,
			scheduleCreateBrowserWorkItem: scheduler.schedule
		)
		let zeroSizedWindow = makeWindow(size: CGSize(width: 640, height: 480))
		host(zeroSizedContainer, in: zeroSizedWindow, size: CGSize(width: 640, height: 480))
		zeroSizedContainer.frame = .zero
		let initialZeroSizeScheduleCount = scheduler.scheduleCount
		let initialZeroSizeCreateCount = runtime.createBrowserRequests.count

		zeroSizedContainer.createBrowserIfNeeded()

		XCTAssertEqual(scheduler.scheduleCount, initialZeroSizeScheduleCount + 1)
		XCTAssertEqual(runtime.createBrowserRequests.count, initialZeroSizeCreateCount)

		let pendingCloseContainer = BrowserContainerView(
			initialURL: "https://navigator.zip",
			browserRuntime: runtime,
			scheduleCreateBrowserWorkItem: scheduler.schedule
		)
		let pendingCloseWindow = makeWindow(size: CGSize(width: 640, height: 480))
		host(pendingCloseContainer, in: pendingCloseWindow, size: CGSize(width: 640, height: 480))
		runtime.hasPendingNativeBrowserCloseValue = true
		let initialPendingCloseScheduleCount = scheduler.scheduleCount
		let initialPendingCloseCreateCount = runtime.createBrowserRequests.count

		pendingCloseContainer.createBrowserIfNeeded()

		XCTAssertEqual(scheduler.scheduleCount, initialPendingCloseScheduleCount + 1)
		XCTAssertEqual(runtime.createBrowserRequests.count, initialPendingCloseCreateCount)
	}

	func testCreateBrowserIfNeededRetriesWhenNativeCloseIsStillPendingAfterFailedCreation() {
		let runtime = BrowserRuntimeSpy()
		runtime.createBrowserResults = [nil]
		runtime.hasPendingNativeBrowserCloseResults = [false, true]
		let scheduler = BrowserContainerSchedulerSpy()
		let container = BrowserContainerView(
			initialURL: "https://navigator.zip",
			browserRuntime: runtime,
			scheduleCreateBrowserWorkItem: scheduler.schedule
		)
		let window = makeWindow(size: CGSize(width: 640, height: 480))
		host(container, in: window, size: CGSize(width: 640, height: 480))
		let initialCreateCount = runtime.createBrowserRequests.count
		let initialScheduleCount = scheduler.scheduleCount

		container.createBrowserIfNeeded()

		XCTAssertEqual(runtime.createBrowserRequests.count, initialCreateCount + 1)
		XCTAssertEqual(scheduler.scheduleCount, initialScheduleCount + 1)
		XCTAssertNil(container.browserRef)
	}

	func testCreateBrowserIfNeededLeavesBrowserNilWhenCreationFailsWithoutPendingClose() {
		let runtime = BrowserRuntimeSpy()
		runtime.createBrowserResults = [nil]
		runtime.hasPendingNativeBrowserCloseResults = [false, false]
		let scheduler = BrowserContainerSchedulerSpy()
		let container = BrowserContainerView(
			initialURL: "https://navigator.zip",
			browserRuntime: runtime,
			scheduleCreateBrowserWorkItem: scheduler.schedule
		)
		let window = makeWindow(size: CGSize(width: 640, height: 480))
		host(container, in: window, size: CGSize(width: 640, height: 480))
		let initialCreateCount = runtime.createBrowserRequests.count
		let initialScheduleCount = scheduler.scheduleCount

		container.createBrowserIfNeeded()

		XCTAssertEqual(runtime.createBrowserRequests.count, initialCreateCount + 1)
		XCTAssertEqual(scheduler.scheduleCount, initialScheduleCount)
		XCTAssertNil(container.browserRef)
	}

	func testLayoutSchedulesBeforeCreationAndResizesOnlyWhenPixelBoundsChange() {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x202)
		runtime.createBrowserResults = [browser]
		let scheduler = BrowserContainerSchedulerSpy()
		let container = BrowserContainerView(
			initialURL: "https://navigator.zip",
			browserRuntime: runtime,
			scheduleCreateBrowserWorkItem: scheduler.schedule
		)
		let window = makeWindow(size: CGSize(width: 640, height: 480))
		host(container, in: window, size: CGSize(width: 640, height: 480))

		container.layout()
		XCTAssertEqual(scheduler.scheduleCount, 1)

		container.createBrowserIfNeeded()
		container.layout()
		container.layout()
		XCTAssertEqual(runtime.resizeBrowserRequests.count, 1)

		container.frame.size.width = 641
		container.layout()

		XCTAssertEqual(runtime.resizeBrowserRequests.count, 2)
		XCTAssertEqual(runtime.resizeBrowserRequests.first?.browser, browser)
	}

	func testScheduledCreationWorkInvokesDeferredCreateAttempt() {
		let runtime = BrowserRuntimeSpy()
		let scheduler = BrowserContainerSchedulerSpy()
		let container = BrowserContainerView(
			initialURL: "https://navigator.zip",
			browserRuntime: runtime,
			scheduleCreateBrowserWorkItem: scheduler.schedule
		)

		container.createBrowserIfNeeded()
		scheduler.runLastScheduledWork()

		XCTAssertEqual(scheduler.scheduleCount, 1)
		XCTAssertTrue(runtime.createBrowserRequests.isEmpty)
	}

	func testViewWillMoveToSuperviewNilCancelsPendingWorkAndClosesExistingBrowser() throws {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x303)
		runtime.createBrowserResults = [browser]
		let scheduler = BrowserContainerSchedulerSpy()
		let pendingContainer = BrowserContainerView(
			initialURL: "https://navigator.zip",
			browserRuntime: runtime,
			scheduleCreateBrowserWorkItem: scheduler.schedule
		)

		pendingContainer.createBrowserIfNeeded()
		let pendingWorkItem = try XCTUnwrap(scheduler.lastWorkItem)

		pendingContainer.viewWillMove(toSuperview: nil)

		XCTAssertTrue(pendingWorkItem.isCancelled)

		let liveContainer = BrowserContainerView(
			initialURL: "https://navigator.zip",
			browserRuntime: runtime,
			scheduleCreateBrowserWorkItem: scheduler.schedule
		)
		let window = makeWindow(size: CGSize(width: 640, height: 480))
		host(liveContainer, in: window, size: CGSize(width: 640, height: 480))
		liveContainer.createBrowserIfNeeded()

		liveContainer.viewWillMove(toSuperview: nil)

		XCTAssertEqual(runtime.closeRequests.last ?? nil, browser)
		XCTAssertNil(liveContainer.browserRef)
	}

	func testDiscardBrowserCanStopLoadBeforeClosing() {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x304)
		runtime.createBrowserResults = [browser]
		let container = BrowserContainerView(
			initialURL: "https://navigator.zip",
			browserRuntime: runtime
		)
		let window = makeWindow(size: CGSize(width: 640, height: 480))
		host(container, in: window, size: CGSize(width: 640, height: 480))
		container.createBrowserIfNeeded()

		container.discardBrowser(stopLoad: true)

		XCTAssertEqual(runtime.stopLoadRequests, [browser])
		XCTAssertEqual(runtime.closeRequests, [browser])
		XCTAssertNil(container.browserRef)
	}

	func testDiscardBrowserClearsBrowserBeforeRuntimeCloseReentersDiscard() {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x305)
		runtime.createBrowserResults = [browser]
		let container = BrowserContainerView(
			initialURL: "https://navigator.zip",
			browserRuntime: runtime
		)
		let window = makeWindow(size: CGSize(width: 640, height: 480))
		host(container, in: window, size: CGSize(width: 640, height: 480))
		container.createBrowserIfNeeded()
		runtime.onClose = { _ in
			container.discardBrowser(stopLoad: false)
		}

		container.discardBrowser(stopLoad: false)

		XCTAssertEqual(runtime.closeRequests, [browser])
		XCTAssertNil(container.browserRef)
	}

	func testPermissionPromptRendersTextAndAllowsRememberedDecision() {
		let container = BrowserContainerView(
			initialURL: "https://navigator.zip",
			browserRuntime: BrowserRuntimeSpy()
		)
		let session = makePermissionSession(
			id: 31,
			source: .permissionPrompt,
			requestingOrigin: "https://navigator.test",
			topLevelOrigin: "https://navigator.test",
			promptKinds: [.camera, .microphone]
		)
		var decisions = [(BrowserPermissionPromptDecision, BrowserPermissionPersistence)]()

		container.setPermissionPrompt(
			session,
			onDecision: { decisions.append(($0, $1)) },
			onCancel: {}
		)

		XCTAssertTrue(container.isPermissionPromptVisibleForTesting)

		container.setPermissionPromptRememberForTesting(true)
		container.performPermissionPromptAllowForTesting()

		XCTAssertEqual(decisions.count, 1)
		XCTAssertEqual(decisions.first?.0, .allow)
		XCTAssertEqual(decisions.first?.1, .remember)
	}

	func testPermissionPromptSupportsDenyCancelAndCrossOriginCopy() {
		let container = BrowserContainerView(
			initialURL: "https://navigator.zip",
			browserRuntime: BrowserRuntimeSpy()
		)
		let session = makePermissionSession(
			id: 32,
			source: .mediaAccess,
			requestingOrigin: "https://frame.example",
			topLevelOrigin: "https://app.example",
			promptKinds: [.geolocation]
		)
		var decisions = [(BrowserPermissionPromptDecision, BrowserPermissionPersistence)]()
		var cancelCount = 0

		container.setPermissionPrompt(
			session,
			onDecision: { decisions.append(($0, $1)) },
			onCancel: { cancelCount += 1 }
		)

		container.performPermissionPromptDenyForTesting()
		container.performPermissionPromptCancelForTesting()

		XCTAssertEqual(decisions.count, 1)
		XCTAssertEqual(decisions.first?.0, .deny)
		XCTAssertEqual(decisions.first?.1, .session)
		XCTAssertEqual(cancelCount, 1)
	}

	func testDiscardBrowserClearsPermissionPromptOverlay() {
		let container = BrowserContainerView(
			initialURL: "https://navigator.zip",
			browserRuntime: BrowserRuntimeSpy()
		)
		container.setPermissionPrompt(
			makePermissionSession(id: 33, promptKinds: [.camera]),
			onDecision: { _, _ in },
			onCancel: {}
		)

		container.discardBrowser(stopLoad: false)

		XCTAssertFalse(container.isPermissionPromptVisibleForTesting)
	}

	func testTopLevelNativeContentPresentationOverridesNavigationAndSupportsSyntheticBackForward() {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x404)
		runtime.createBrowserResults = [browser]
		runtime.setNavigationState(
			BrowserSidebarNavigationState(canGoBack: false, canGoForward: false, isLoading: false),
			for: browser
		)
		let container = BrowserContainerView(
			initialURL: "https://navigator.zip",
			browserRuntime: runtime
		)
		let window = makeWindow(size: CGSize(width: 640, height: 480))
		host(container, in: window, size: CGSize(width: 640, height: 480))
		container.createBrowserIfNeeded()
		let content = BrowserRuntimeTopLevelNativeContent(
			kind: .image,
			url: "https://navigator.test/image.png",
			pathExtension: "png",
			uniformTypeIdentifier: "public.png"
		)
		var displayedContent = [BrowserRuntimeTopLevelNativeContent?]()
		container.onDisplayedTopLevelNativeContentChange = { displayedContent.append($0) }

		runtime.fireTopLevelNativeContent(content, for: browser)

		XCTAssertTrue(container.isPresentingTopLevelNativeContent)
		XCTAssertEqual(
			container.navigationState(overriding: .idle),
			BrowserSidebarNavigationState(canGoBack: true, canGoForward: false, isLoading: false)
		)
		XCTAssertEqual(displayedContent.last ?? nil, content)

		XCTAssertTrue(container.goBackInPresentedTopLevelNativeContent())
		XCTAssertFalse(container.isPresentingTopLevelNativeContent)
		XCTAssertEqual(displayedContent.last ?? content, nil)
		XCTAssertTrue(container.navigationState(overriding: .idle).canGoForward)

		XCTAssertTrue(container.goForwardInPresentedTopLevelNativeContent())
		XCTAssertTrue(container.isPresentingTopLevelNativeContent)
		XCTAssertEqual(displayedContent.last ?? nil, content)
	}

	func testLoadClearsPresentedTopLevelNativeContentBeforeForwardingURLToRuntime() {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x505)
		runtime.createBrowserResults = [browser]
		let container = BrowserContainerView(
			initialURL: "https://navigator.zip",
			browserRuntime: runtime
		)
		let window = makeWindow(size: CGSize(width: 640, height: 480))
		host(container, in: window, size: CGSize(width: 640, height: 480))
		container.createBrowserIfNeeded()
		let content = BrowserRuntimeTopLevelNativeContent(
			kind: .image,
			url: "https://navigator.test/image.png",
			pathExtension: "png",
			uniformTypeIdentifier: "public.png"
		)

		runtime.fireTopLevelNativeContent(content, for: browser)
		container.load("https://swift.org")

		XCTAssertFalse(container.isPresentingTopLevelNativeContent)
		XCTAssertEqual(runtime.loadRequests.last?.url, "https://swift.org")
	}

	private func makePermissionSession(
		id: BrowserPermissionSessionID,
		source: BrowserPermissionRequestSource = .permissionPrompt,
		requestingOrigin: String = "https://navigator.test",
		topLevelOrigin: String = "https://navigator.test",
		promptKinds: BrowserPermissionKindSet
	) -> BrowserPermissionSession {
		BrowserPermissionSession(
			id: id,
			browserID: 1,
			promptID: id + 100,
			frameIdentifier: "frame-\(id)",
			source: source,
			origin: BrowserPermissionOrigin(
				requestingOrigin: requestingOrigin,
				topLevelOrigin: topLevelOrigin
			),
			requestedKinds: promptKinds,
			promptKinds: promptKinds,
			state: .waitingForUserPrompt,
			siteDecision: nil,
			persistence: nil,
			osAuthorizationState: BrowserPermissionOSAuthorizationState(),
			createdAt: .distantPast,
			updatedAt: .distantPast
		)
	}
}
