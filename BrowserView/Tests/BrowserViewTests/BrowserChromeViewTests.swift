import AppKit
import BrowserRuntime
import BrowserSidebar
@testable import BrowserView
import ModelKit
import XCTest

@MainActor
final class BrowserChromeViewTests: XCTestCase {
	func testTabSyncAddsSelectsAndRemovesBrowserContainers() {
		let runtime = BrowserRuntimeSpy()
		let viewModel = makeBrowserSidebarViewModel()
		let presentation = BrowserSidebarPresentation()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0)
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		XCTAssertEqual(browserContainers(in: chromeView).count, 1)
		XCTAssertEqual(browserContainers(in: chromeView).filter(\.isHidden).count, 0)

		viewModel.addTab()

		XCTAssertEqual(browserContainers(in: chromeView).count, 2)
		XCTAssertEqual(browserContainers(in: chromeView).filter { !$0.isHidden }.count, 1)

		let firstTabID = viewModel.tabs[0].id
		viewModel.selectTab(id: firstTabID)
		XCTAssertEqual(browserContainers(in: chromeView).filter { !$0.isHidden }.count, 1)

		viewModel.closeTab(id: firstTabID)

		XCTAssertEqual(browserContainers(in: chromeView).count, 1)

		chromeView.removeFromSuperview()

		XCTAssertNil(viewModel.onTabConfigurationChange)
	}

	func testEnsureSelectedBrowserBindsHandlersAndSidebarActions() {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x404)
		runtime.createBrowserResults = [browser]
		runtime.setNavigationState(
			BrowserSidebarNavigationState(
				canGoBack: true,
				canGoForward: false,
				isLoading: true
			),
			for: browser
		)
		let viewModel = makeBrowserSidebarViewModel()
		let presentation = BrowserSidebarPresentation()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0)
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()

		XCTAssertEqual(chromeView.hostedBrowser, browser)
		XCTAssertTrue(viewModel.canGoBack)
		XCTAssertFalse(viewModel.canGoForward)
		XCTAssertTrue(viewModel.isLoading)

		runtime.fireAddressChange("https://developer.apple.com", for: browser)
		XCTAssertEqual(viewModel.selectedTabCurrentURL, "https://developer.apple.com")

		runtime.fireTitleChange("  Apple Developer  ", for: browser)
		XCTAssertEqual(viewModel.tabs[0].pageTitle, "Apple Developer")
		XCTAssertEqual(viewModel.tabs[0].displayTitle, "Apple Developer")

		runtime.fireFaviconURLChange("   ", for: browser)
		XCTAssertNil(viewModel.tabs[0].faviconURL)

		runtime.fireFaviconURLChange(" https://developer.apple.com/favicon.ico \n", for: browser)
		XCTAssertEqual(viewModel.tabs[0].faviconURL, "https://developer.apple.com/favicon.ico")

		viewModel.goBack()
		viewModel.goForward()
		viewModel.reload()
		viewModel.navigateSelectedTab(to: "swift.org")

		XCTAssertEqual(runtime.goBackRequests, [browser])
		XCTAssertEqual(runtime.goForwardRequests, [browser])
		XCTAssertEqual(runtime.reloadRequests, [browser])
		XCTAssertEqual(runtime.loadRequests.last?.url, "https://swift.org")
		XCTAssertGreaterThan(runtime.noteBrowserActivityCount, 0)
	}

	func testBrowserCreationInstallsCameraRoutingScriptAndNavigationReinstallsIt() throws {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x440)
		runtime.createBrowserResults = [browser]
		let cameraCoordinator = BrowserCameraSessionCoordinatorSpy()
		cameraCoordinator.routingSettings = BrowserCameraRoutingSettings(
			routingEnabled: true,
			preferNavigatorCameraWhenPossible: true,
			preferredSourceID: "camera-a",
			preferredFilterPreset: .folia,
			previewEnabled: false
		)
		let viewModel = makeBrowserSidebarViewModel()
		let presentation = BrowserSidebarPresentation()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0),
			browserCameraSessionCoordinator: cameraCoordinator
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()
		let browserTransportState = try XCTUnwrap(
			cameraCoordinator.currentSnapshot().browserTransportStates.first
		)

		XCTAssertFalse(runtime.evaluateJavaScriptInRendererRequests.isEmpty)
		XCTAssertTrue(
			runtime.evaluateJavaScriptInRendererRequests.contains { request in
				request.browser == browser && request.script.contains("__navigatorCameraRoutingShim")
			}
		)
		XCTAssertEqual(browserTransportState.tabID, viewModel.tabs[0].id.uuidString)
		XCTAssertEqual(browserTransportState.routingTransportMode, .rendererProcessMessages)
		XCTAssertEqual(browserTransportState.frameTransportMode, .unavailable)
		XCTAssertEqual(browserTransportState.activeManagedTrackCount, 0)
		let initialInstallCount = runtime.evaluateJavaScriptInRendererRequests.count

		runtime.fireMainFrameNavigationEvent(
			.init(
				url: "https://developer.apple.com/videos",
				userGesture: true,
				isRedirect: false
			),
			for: browser
		)

		XCTAssertEqual(runtime.evaluateJavaScriptInRendererRequests.count, initialInstallCount + 1)
	}

	func testBrowserCreationFallsBackToBrowserProcessCameraRoutingInstallWhenRendererTransportFails() throws {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x4401)
		runtime.createBrowserResults = [browser]
		runtime.evaluateJavaScriptInRendererResults = [(nil, "Renderer unavailable")]
		let cameraCoordinator = BrowserCameraSessionCoordinatorSpy()
		cameraCoordinator.routingSettings = BrowserCameraRoutingSettings(
			routingEnabled: true,
			preferNavigatorCameraWhenPossible: true,
			preferredSourceID: "camera-a",
			preferredFilterPreset: .folia,
			previewEnabled: false
		)
		let viewModel = makeBrowserSidebarViewModel()
		let presentation = BrowserSidebarPresentation()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0),
			browserCameraSessionCoordinator: cameraCoordinator
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()

		XCTAssertTrue(
			runtime.evaluateJavaScriptInRendererRequests.contains { request in
				request.browser == browser && request.script.contains("__navigatorCameraRoutingShim")
			}
		)
		XCTAssertTrue(
			runtime.evaluateJavaScriptRequests.contains { request in
				request.browser == browser && request.script.contains("__navigatorCameraRoutingShim")
			}
		)
		let browserTransportState = try XCTUnwrap(
			cameraCoordinator.currentSnapshot().browserTransportStates.first
		)
		XCTAssertEqual(browserTransportState.routingTransportMode, .browserProcessJavaScriptFallback)
		XCTAssertEqual(browserTransportState.frameTransportMode, .browserProcessJavaScriptFallback)
	}

	func testBrowserCreationFallsBackToBrowserProcessCameraRoutingInstallWhenRendererReportsMissingShim() {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x4402)
		runtime.createBrowserResults = [browser]
		runtime.evaluateJavaScriptInRendererResults = [(
			BrowserCameraRendererScriptStatus.missingShim.rawValue,
			""
		)]
		let cameraCoordinator = BrowserCameraSessionCoordinatorSpy()
		cameraCoordinator.routingSettings = BrowserCameraRoutingSettings(
			routingEnabled: true,
			preferNavigatorCameraWhenPossible: true,
			preferredSourceID: "camera-a",
			preferredFilterPreset: .folia,
			previewEnabled: false
		)
		let viewModel = makeBrowserSidebarViewModel()
		let presentation = BrowserSidebarPresentation()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0),
			browserCameraSessionCoordinator: cameraCoordinator
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()

		XCTAssertTrue(
			runtime.evaluateJavaScriptInRendererRequests.contains { request in
				request.browser == browser && request.script.contains("__navigatorCameraRoutingShim")
			}
		)
		XCTAssertTrue(
			runtime.evaluateJavaScriptRequests.contains { request in
				request.browser == browser && request.script.contains("__navigatorCameraRoutingShim")
			}
		)
	}

	func testBrowserCreationFallsBackToBrowserProcessCameraRoutingInstallWhenRendererTimesOut() {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x4403)
		runtime.createBrowserResults = [browser]
		runtime.evaluateJavaScriptInRendererResults = [(nil, "Renderer JavaScript timed out")]
		let cameraCoordinator = BrowserCameraSessionCoordinatorSpy()
		cameraCoordinator.routingSettings = BrowserCameraRoutingSettings(
			routingEnabled: true,
			preferNavigatorCameraWhenPossible: true,
			preferredSourceID: "camera-a",
			preferredFilterPreset: .folia,
			previewEnabled: false
		)
		let viewModel = makeBrowserSidebarViewModel()
		let presentation = BrowserSidebarPresentation()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0),
			browserCameraSessionCoordinator: cameraCoordinator
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()

		XCTAssertTrue(
			runtime.evaluateJavaScriptInRendererRequests.contains { request in
				request.browser == browser && request.script.contains("__navigatorCameraRoutingShim")
			}
		)
		XCTAssertTrue(
			runtime.evaluateJavaScriptRequests.contains { request in
				request.browser == browser && request.script.contains("__navigatorCameraRoutingShim")
			}
		)
		XCTAssertEqual(cameraCoordinator.notedFallbacks.count, 1)
		XCTAssertEqual(cameraCoordinator.notedFallbacks.first?.tabID, viewModel.tabs[0].id.uuidString)
		XCTAssertEqual(
			cameraCoordinator.notedFallbacks.first?.reason,
			"rendererError=Renderer JavaScript timed out"
		)
	}

	func testCameraSnapshotUpdatesUseRendererConfigMessageForExistingBrowser() {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x444)
		runtime.createBrowserResults = [browser]
		let cameraCoordinator = BrowserCameraSessionCoordinatorSpy()
		cameraCoordinator.routingSettings = BrowserCameraRoutingSettings(
			routingEnabled: true,
			preferNavigatorCameraWhenPossible: true,
			preferredSourceID: "camera-a",
			preferredFilterPreset: .folia,
			previewEnabled: false
		)
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://camera.example")
		let presentation = BrowserSidebarPresentation()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0),
			browserCameraSessionCoordinator: cameraCoordinator
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()
		let initialInstallCount = runtime.evaluateJavaScriptInRendererRequests.count
		XCTAssertTrue(runtime.sendRendererProcessMessageRequests.isEmpty)

		cameraCoordinator.routingSettings = BrowserCameraRoutingSettings(
			routingEnabled: true,
			preferNavigatorCameraWhenPossible: true,
			preferredSourceID: "camera-a",
			preferredFilterPreset: .supergold,
			previewEnabled: true
		)
		cameraCoordinator.registerConsumer(
			BrowserCameraConsumer(
				id: viewModel.tabs[0].id.uuidString,
				kind: .browserTabCapture,
				requiresLiveFrames: true
			)
		)
		cameraCoordinator.emitSnapshotChange()

		XCTAssertEqual(runtime.evaluateJavaScriptInRendererRequests.count, initialInstallCount)
		XCTAssertEqual(runtime.sendRendererProcessMessageRequests.count, 1)
		XCTAssertEqual(
			runtime.sendRendererProcessMessageRequests.last?.channel,
			BrowserCameraRoutingScriptConstants.cameraRoutingConfigUpdateChannel
		)
		XCTAssertTrue(
			runtime.sendRendererProcessMessageRequests.last?.jsonPayload.contains("\"preferredFilterPreset\":\"supergold\"")
				== true
		)
		XCTAssertEqual(viewModel.cameraUsageState.activeTabCount, 1)
		XCTAssertTrue(viewModel.cameraUsageState.selectedTabIsActive)
	}

	func testCameraSnapshotUpdateFallsBackToBrowserProcessInstallWhenRendererConfigMessageFails() throws {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x4441)
		runtime.createBrowserResults = [browser]
		runtime.sendRendererProcessMessageResults = [(nil, "Renderer config unavailable")]
		let cameraCoordinator = BrowserCameraSessionCoordinatorSpy()
		cameraCoordinator.routingSettings = BrowserCameraRoutingSettings(
			routingEnabled: true,
			preferNavigatorCameraWhenPossible: true,
			preferredSourceID: "camera-a",
			preferredFilterPreset: .folia,
			previewEnabled: false
		)
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://camera.example")
		let presentation = BrowserSidebarPresentation()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0),
			browserCameraSessionCoordinator: cameraCoordinator
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()

		cameraCoordinator.routingSettings.preferredFilterPreset = .vertichrome
		cameraCoordinator.emitSnapshotChange()

		XCTAssertEqual(runtime.sendRendererProcessMessageRequests.count, 1)
		XCTAssertEqual(
			runtime.sendRendererProcessMessageRequests.last?.channel,
			BrowserCameraRoutingScriptConstants.cameraRoutingConfigUpdateChannel
		)
		XCTAssertTrue(
			runtime.evaluateJavaScriptRequests.contains { request in
				request.browser == browser && request.script.contains("\"preferredFilterPreset\":\"vertichrome\"")
			}
		)
		XCTAssertEqual(
			cameraCoordinator.notedFallbacks.last?.reason,
			"rendererConfigError=Renderer config unavailable"
		)
		let browserTransportState = try XCTUnwrap(
			cameraCoordinator.currentSnapshot().browserTransportStates.first
		)
		XCTAssertEqual(browserTransportState.routingTransportMode, .browserProcessJavaScriptFallback)
		XCTAssertEqual(browserTransportState.frameTransportMode, .browserProcessJavaScriptFallback)
	}

	func testRemovingChromeViewUnsubscribesFromCameraSnapshotUpdates() {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x445)
		runtime.createBrowserResults = [browser]
		let cameraCoordinator = BrowserCameraSessionCoordinatorSpy()
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://camera.example")
		let presentation = BrowserSidebarPresentation()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0),
			browserCameraSessionCoordinator: cameraCoordinator
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()
		chromeView.removeFromSuperview()
		let installCountAfterRemoval = runtime.evaluateJavaScriptInRendererRequests.count

		cameraCoordinator.routingSettings.preferredFilterPreset = .vertichrome
		cameraCoordinator.emitSnapshotChange()

		XCTAssertEqual(cameraCoordinator.removedSnapshotObserverIDs.count, 1)
		XCTAssertEqual(runtime.evaluateJavaScriptInRendererRequests.count, installCountAfterRemoval)
	}

	func testSidebarCameraControlsProjectCameraStateAndMutateCoordinator() {
		let runtime = BrowserRuntimeSpy()
		let cameraCoordinator = BrowserCameraSessionCoordinatorSpy()
		cameraCoordinator.lifecycleState = .running
		cameraCoordinator.healthState = .degraded
		cameraCoordinator.outputMode = .processedNavigatorFeed
		cameraCoordinator.lastErrorDescription = "Pipeline fallback active"
		cameraCoordinator.availableSources = [
			BrowserCameraSource(id: "camera-a", name: "FaceTime HD", isDefault: true),
			BrowserCameraSource(id: "camera-b", name: "External Camera", isDefault: false),
		]
		cameraCoordinator.routingSettings = BrowserCameraRoutingSettings(
			routingEnabled: true,
			preferNavigatorCameraWhenPossible: true,
			preferredSourceID: "camera-a",
			preferredFilterPreset: .folia,
			previewEnabled: false
		)
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://camera.example")
		let presentation = BrowserSidebarPresentation()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0),
			browserCameraSessionCoordinator: cameraCoordinator
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		XCTAssertTrue(viewModel.showsCameraControls)
		XCTAssertEqual(viewModel.cameraLifecycleState, .running)
		XCTAssertEqual(viewModel.cameraHealthState, .degraded)
		XCTAssertEqual(viewModel.cameraOutputMode, .processedNavigatorFeed)
		XCTAssertEqual(viewModel.cameraLastErrorDescription, "Pipeline fallback active")
		XCTAssertEqual(viewModel.cameraSelectedSourceID, "camera-a")
		XCTAssertEqual(viewModel.cameraSelectedFilterPreset, .folia)
		XCTAssertEqual(viewModel.cameraAvailableSources.map(\.id), ["camera-a", "camera-b"])
		XCTAssertEqual(viewModel.cameraDebugSummary.selectedSourceID, "camera-a")
		XCTAssertEqual(viewModel.cameraDebugSummary.selectedSourceName, "FaceTime HD")

		viewModel.setCameraRoutingEnabled(false)
		XCTAssertFalse(cameraCoordinator.routingSettings.routingEnabled)

		viewModel.refreshAvailableCameraDevices()
		XCTAssertEqual(cameraCoordinator.refreshAvailableDevicesCount, 1)

		viewModel.selectCameraSource(id: "camera-b")
		XCTAssertEqual(cameraCoordinator.routingSettings.preferredSourceID, "camera-b")

		viewModel.selectCameraFilterPreset(.vertichrome)
		XCTAssertEqual(cameraCoordinator.routingSettings.preferredFilterPreset, .vertichrome)

		viewModel.setCameraPreviewEnabled(true)
		XCTAssertTrue(cameraCoordinator.routingSettings.previewEnabled)
		XCTAssertEqual(cameraCoordinator.currentSnapshot().previewConsumerCount, 0)

		viewModel.setCameraPreviewEnabled(false)
		XCTAssertFalse(cameraCoordinator.routingSettings.previewEnabled)
		XCTAssertEqual(cameraCoordinator.currentSnapshot().previewConsumerCount, 0)
		XCTAssertTrue(cameraCoordinator.unregisteredConsumerIDs.isEmpty)
	}

	func testPreviewUpdatesRefreshSidebarModelAndRemovalCleansUpPreviewObserver() throws {
		let runtime = BrowserRuntimeSpy()
		let cameraCoordinator = BrowserCameraSessionCoordinatorSpy()
		cameraCoordinator.routingSettings = BrowserCameraRoutingSettings(
			routingEnabled: true,
			preferNavigatorCameraWhenPossible: true,
			preferredSourceID: "camera-a",
			preferredFilterPreset: .mononoke,
			previewEnabled: true
		)
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://camera.example")
		let presentation = BrowserSidebarPresentation()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0),
			browserCameraSessionCoordinator: cameraCoordinator
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		XCTAssertEqual(cameraCoordinator.currentSnapshot().previewConsumerCount, 0)
		XCTAssertNil(viewModel.cameraPreviewImage)

		cameraCoordinator.previewFrame = makeBrowserCameraPreviewFrame()
		cameraCoordinator.emitPreviewFrameChange()

		_ = try XCTUnwrap(viewModel.cameraPreviewImage)

		chromeView.removeFromSuperview()

		XCTAssertEqual(cameraCoordinator.removedPreviewObserverIDs.count, 1)
		XCTAssertEqual(cameraCoordinator.currentSnapshot().previewConsumerCount, 0)
	}

	func testActiveCameraTabPreviewFramesAreDeliveredIntoManagedRoutingShim() throws {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x446)
		runtime.createBrowserResults = [browser]
		let cameraCoordinator = BrowserCameraSessionCoordinatorSpy()
		cameraCoordinator.routingSettings = BrowserCameraRoutingSettings(
			routingEnabled: true,
			preferNavigatorCameraWhenPossible: true,
			preferredSourceID: "camera-a",
			preferredFilterPreset: .folia,
			previewEnabled: false
		)
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://camera.example")
		let tabID = try XCTUnwrap(viewModel.selectedTabID)
		cameraCoordinator.registerConsumer(
			BrowserCameraConsumer(
				id: tabID.uuidString,
				kind: .browserTabCapture,
				requiresLiveFrames: true
			)
		)
		let presentation = BrowserSidebarPresentation()
		var currentTime: TimeInterval = 10
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0),
			timeProvider: { currentTime },
			browserCameraSessionCoordinator: cameraCoordinator
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()

		cameraCoordinator.previewFrame = makeBrowserCameraPreviewFrame()
		cameraCoordinator.emitPreviewFrameChange()
		currentTime += BrowserCameraManagedFrameDelivery.minimumFrameInterval
		cameraCoordinator.emitPreviewFrameChange()

		let rendererValidationRequests = runtime.evaluateJavaScriptInRendererRequests
		XCTAssertTrue(
			rendererValidationRequests.contains { request in
				request.browser == browser
					&& request.script.contains("shim.receiveFrame(")
					&& request.script.contains("data:image")
			}
		)
		XCTAssertTrue(
			runtime.sendRendererProcessMessageRequests.contains { request in
				request.browser == browser
					&& request.channel == BrowserCameraRoutingScriptConstants.cameraFrameDeliveryChannel
					&& request.jsonPayload.contains("\"imageDataURL\":")
					&& request.jsonPayload.contains("data:image")
			}
		)
	}

	func testManagedCameraFrameDeliveryIsThrottledAcrossRapidPreviewUpdates() throws {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x447)
		runtime.createBrowserResults = [browser]
		let cameraCoordinator = BrowserCameraSessionCoordinatorSpy()
		cameraCoordinator.routingSettings = BrowserCameraRoutingSettings(
			routingEnabled: true,
			preferNavigatorCameraWhenPossible: true,
			preferredSourceID: "camera-a",
			preferredFilterPreset: .supergold,
			previewEnabled: false
		)
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://camera.example")
		let tabID = try XCTUnwrap(viewModel.selectedTabID)
		cameraCoordinator.registerConsumer(
			BrowserCameraConsumer(
				id: tabID.uuidString,
				kind: .browserTabCapture,
				requiresLiveFrames: true
			)
		)
		var currentTime: TimeInterval = 10
		let presentation = BrowserSidebarPresentation()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0),
			timeProvider: { currentTime },
			browserCameraSessionCoordinator: cameraCoordinator
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()
		cameraCoordinator.previewFrame = makeBrowserCameraPreviewFrame()
		cameraCoordinator.emitPreviewFrameChange()
		let rendererRequestsAfterFirstFrame = runtime.evaluateJavaScriptInRendererRequests.filter {
			$0.script.contains("shim.receiveFrame(")
		}
		let rendererMessagesAfterFirstFrame = runtime.sendRendererProcessMessageRequests.filter {
			$0.channel == BrowserCameraRoutingScriptConstants.cameraFrameDeliveryChannel
		}

		cameraCoordinator.emitPreviewFrameChange()
		let rendererRequestsAfterSecondFrame = runtime.evaluateJavaScriptInRendererRequests.filter {
			$0.script.contains("shim.receiveFrame(")
		}
		let rendererMessagesAfterSecondFrame = runtime.sendRendererProcessMessageRequests.filter {
			$0.channel == BrowserCameraRoutingScriptConstants.cameraFrameDeliveryChannel
		}

		currentTime += BrowserCameraManagedFrameDelivery.minimumFrameInterval
		cameraCoordinator.emitPreviewFrameChange()
		let rendererRequestsAfterThirdFrame = runtime.evaluateJavaScriptInRendererRequests.filter {
			$0.script.contains("shim.receiveFrame(")
		}
		let rendererMessagesAfterThirdFrame = runtime.sendRendererProcessMessageRequests.filter {
			$0.channel == BrowserCameraRoutingScriptConstants.cameraFrameDeliveryChannel
		}

		XCTAssertEqual(rendererRequestsAfterFirstFrame.count, 1)
		XCTAssertEqual(rendererMessagesAfterFirstFrame.count, 0)
		XCTAssertEqual(rendererRequestsAfterSecondFrame.count, 1)
		XCTAssertEqual(rendererMessagesAfterSecondFrame.count, 0)
		XCTAssertEqual(rendererRequestsAfterThirdFrame.count, 1)
		XCTAssertEqual(rendererMessagesAfterThirdFrame.count, 1)
	}

	func testManagedCameraFrameDeliveryContinuesWhileCameraHealthIsDegraded() throws {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x4471)
		runtime.createBrowserResults = [browser]
		let cameraCoordinator = BrowserCameraSessionCoordinatorSpy()
		cameraCoordinator.healthState = .degraded
		cameraCoordinator.routingSettings = BrowserCameraRoutingSettings(
			routingEnabled: true,
			preferNavigatorCameraWhenPossible: true,
			preferredSourceID: "camera-a",
			preferredFilterPreset: .supergold,
			previewEnabled: false
		)
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://camera.example")
		let tabID = try XCTUnwrap(viewModel.selectedTabID)
		cameraCoordinator.registerConsumer(
			BrowserCameraConsumer(
				id: tabID.uuidString,
				kind: .browserTabCapture,
				requiresLiveFrames: true
			)
		)
		let presentation = BrowserSidebarPresentation()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0),
			browserCameraSessionCoordinator: cameraCoordinator
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()
		cameraCoordinator.previewFrame = makeBrowserCameraPreviewFrame()
		cameraCoordinator.emitPreviewFrameChange()

		XCTAssertTrue(
			runtime.evaluateJavaScriptInRendererRequests.contains { request in
				request.browser == browser && request.script.contains("shim.receiveFrame(")
			}
		)
	}

	func testRemovingManagedCameraTabClearsBrowserShimFrameState() throws {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x448)
		runtime.createBrowserResults = [browser]
		let cameraCoordinator = BrowserCameraSessionCoordinatorSpy()
		cameraCoordinator.routingSettings = BrowserCameraRoutingSettings(
			routingEnabled: true,
			preferNavigatorCameraWhenPossible: true,
			preferredSourceID: "camera-a",
			preferredFilterPreset: .vertichrome,
			previewEnabled: false
		)
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://camera.example")
		let tabID = try XCTUnwrap(viewModel.selectedTabID)
		cameraCoordinator.registerConsumer(
			BrowserCameraConsumer(
				id: tabID.uuidString,
				kind: .browserTabCapture,
				requiresLiveFrames: true
			)
		)
		let presentation = BrowserSidebarPresentation()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0),
			browserCameraSessionCoordinator: cameraCoordinator
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()
		cameraCoordinator.previewFrame = makeBrowserCameraPreviewFrame()
		cameraCoordinator.emitPreviewFrameChange()
		let messageCountAfterFrame = runtime.sendRendererProcessMessageRequests.count

		cameraCoordinator.unregisterConsumer(id: tabID.uuidString)
		cameraCoordinator.emitSnapshotChange()

		let clearRequests = runtime.sendRendererProcessMessageRequests.dropFirst(messageCountAfterFrame)
		XCTAssertTrue(
			clearRequests.contains { request in
				request.browser == browser
					&& request.channel == BrowserCameraRoutingScriptConstants.cameraFrameClearChannel
					&& request.jsonPayload == "{}"
			}
		)
	}

	func testManagedCameraFrameDeliveryUsesBrowserProcessFallbackAfterRendererCameraScriptTransportFailure() throws {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x449)
		runtime.createBrowserResults = [browser]
		runtime.evaluateJavaScriptInRendererResults = [(nil, "Renderer unavailable")]
		let cameraCoordinator = BrowserCameraSessionCoordinatorSpy()
		cameraCoordinator.routingSettings = BrowserCameraRoutingSettings(
			routingEnabled: true,
			preferNavigatorCameraWhenPossible: true,
			preferredSourceID: "camera-a",
			preferredFilterPreset: .folia,
			previewEnabled: false
		)
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://camera.example")
		let tabID = try XCTUnwrap(viewModel.selectedTabID)
		cameraCoordinator.registerConsumer(
			BrowserCameraConsumer(
				id: tabID.uuidString,
				kind: .browserTabCapture,
				requiresLiveFrames: true
			)
		)
		let presentation = BrowserSidebarPresentation()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0),
			browserCameraSessionCoordinator: cameraCoordinator
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()
		cameraCoordinator.previewFrame = makeBrowserCameraPreviewFrame()
		cameraCoordinator.emitPreviewFrameChange()

		XCTAssertTrue(
			runtime.evaluateJavaScriptInRendererRequests.contains { request in
				request.browser == browser && request.script.contains("__navigatorCameraRoutingShim")
			}
		)
		XCTAssertFalse(
			runtime.evaluateJavaScriptInRendererRequests.contains { request in
				request.browser == browser && request.script.contains("shim.receiveFrame(")
			}
		)
		XCTAssertTrue(
			runtime.evaluateJavaScriptRequests.contains { request in
				request.browser == browser && request.script.contains("shim.receiveFrame(")
			}
		)
		XCTAssertEqual(cameraCoordinator.notedFallbacks.count, 1)
		XCTAssertEqual(cameraCoordinator.notedFallbacks.first?.tabID, tabID.uuidString)
		XCTAssertEqual(cameraCoordinator.notedFallbacks.first?.reason, "rendererError=Renderer unavailable")
	}

	func testReadyManagedCameraFrameDeliveryFallsBackToBrowserProcessWhenRendererMessageTransportFails() throws {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x44B)
		runtime.createBrowserResults = [browser]
		runtime.sendRendererProcessMessageResults = [(nil, "Renderer transport unavailable")]
		let cameraCoordinator = BrowserCameraSessionCoordinatorSpy()
		cameraCoordinator.routingSettings = BrowserCameraRoutingSettings(
			routingEnabled: true,
			preferNavigatorCameraWhenPossible: true,
			preferredSourceID: "camera-a",
			preferredFilterPreset: .folia,
			previewEnabled: false
		)
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://camera.example")
		let tabID = try XCTUnwrap(viewModel.selectedTabID)
		cameraCoordinator.registerConsumer(
			BrowserCameraConsumer(
				id: tabID.uuidString,
				kind: .browserTabCapture,
				requiresLiveFrames: true
			)
		)
		var currentTime: TimeInterval = 10
		let presentation = BrowserSidebarPresentation()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0),
			timeProvider: { currentTime },
			browserCameraSessionCoordinator: cameraCoordinator
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()
		cameraCoordinator.previewFrame = makeBrowserCameraPreviewFrame()
		cameraCoordinator.emitPreviewFrameChange()
		currentTime += BrowserCameraManagedFrameDelivery.minimumFrameInterval
		cameraCoordinator.emitPreviewFrameChange()

		XCTAssertTrue(
			runtime.sendRendererProcessMessageRequests.contains { request in
				request.browser == browser
					&& request.channel == BrowserCameraRoutingScriptConstants.cameraFrameDeliveryChannel
			}
		)
		XCTAssertTrue(
			runtime.evaluateJavaScriptRequests.contains { request in
				request.browser == browser && request.script.contains("__navigatorCameraRoutingShim")
			}
		)
		XCTAssertTrue(
			runtime.evaluateJavaScriptRequests.contains { request in
				request.browser == browser && request.script.contains("shim.receiveFrame(")
			}
		)
		XCTAssertEqual(cameraCoordinator.notedFallbacks.count, 1)
		XCTAssertEqual(cameraCoordinator.notedFallbacks.first?.tabID, tabID.uuidString)
		XCTAssertEqual(
			cameraCoordinator.notedFallbacks.first?.reason,
			"rendererError=Renderer transport unavailable"
		)
	}

	func testManagedCameraFrameDeliveryReinstallsRendererShimBeforeFallingBack() throws {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x44A)
		runtime.createBrowserResults = [browser]
		runtime.evaluateJavaScriptInRendererResults = [
			(BrowserCameraRendererScriptStatus.installed.rawValue, ""),
			(BrowserCameraRendererScriptStatus.installed.rawValue, ""),
			(BrowserCameraRendererScriptStatus.missingShim.rawValue, ""),
			(BrowserCameraRendererScriptStatus.updated.rawValue, ""),
			(BrowserCameraRendererScriptStatus.delivered.rawValue, ""),
		]
		let cameraCoordinator = BrowserCameraSessionCoordinatorSpy()
		cameraCoordinator.routingSettings = BrowserCameraRoutingSettings(
			routingEnabled: true,
			preferNavigatorCameraWhenPossible: true,
			preferredSourceID: "camera-a",
			preferredFilterPreset: .folia,
			previewEnabled: false
		)
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://camera.example")
		let tabID = try XCTUnwrap(viewModel.selectedTabID)
		cameraCoordinator.registerConsumer(
			BrowserCameraConsumer(
				id: tabID.uuidString,
				kind: .browserTabCapture,
				requiresLiveFrames: true
			)
		)
		let presentation = BrowserSidebarPresentation()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0),
			browserCameraSessionCoordinator: cameraCoordinator
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()
		let rendererRequestCountBeforeFrame = runtime.evaluateJavaScriptInRendererRequests.count
		let browserProcessFrameRequestCountBeforeFrame = runtime.evaluateJavaScriptRequests.filter { request in
			request.browser == browser && request.script.contains("shim.receiveFrame(")
		}.count
		cameraCoordinator.previewFrame = makeBrowserCameraPreviewFrame()
		cameraCoordinator.emitPreviewFrameChange()

		let rendererRequestsAfterFrame = runtime.evaluateJavaScriptInRendererRequests.dropFirst(
			rendererRequestCountBeforeFrame
		)
		let installRequests = rendererRequestsAfterFrame.filter { request in
			request.browser == browser && request.script.contains("__navigatorCameraRoutingShim")
		}
		let frameRequests = rendererRequestsAfterFrame.filter { request in
			request.browser == browser && request.script.contains("shim.receiveFrame(")
		}
		let browserProcessFrameRequestCountAfterFrame = runtime.evaluateJavaScriptRequests.filter { request in
			request.browser == browser && request.script.contains("shim.receiveFrame(")
		}.count

		XCTAssertGreaterThanOrEqual(installRequests.count, 1)
		XCTAssertEqual(frameRequests.count, 2)
		XCTAssertFalse(
			browserProcessFrameRequestCountAfterFrame > browserProcessFrameRequestCountBeforeFrame
		)
		XCTAssertTrue(cameraCoordinator.notedFallbacks.isEmpty)
	}

	func testAllowingCameraPromptWaitsForManagedCameraDemandBeforeRegisteringConsumer() throws {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x441)
		runtime.createBrowserResults = [browser]
		let cameraCoordinator = BrowserCameraSessionCoordinatorSpy()
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://camera.example")
		let tabID = try XCTUnwrap(viewModel.selectedTabID)
		let presentation = BrowserSidebarPresentation()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0),
			browserCameraSessionCoordinator: cameraCoordinator
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()
		let container = try XCTUnwrap(chromeView.browserContainerForTesting(tabID: tabID))

		runtime.firePermissionPrompt(
			makePermissionSession(
				id: 500,
				browserID: UInt64(UInt(bitPattern: browser)),
				requestedKinds: .camera,
				promptKinds: .camera
			),
			for: browser
		)
		container.performPermissionPromptAllowForTesting()

		XCTAssertTrue(cameraCoordinator.registeredConsumers.isEmpty)
		XCTAssertEqual(cameraCoordinator.currentSnapshot().liveFrameConsumerCount, 0)

		runtime.fireCameraRoutingEvent(
			BrowserCameraRoutingEvent(
				event: .trackStarted,
				activeManagedTrackCount: 1,
				managedTrackID: "track-1"
			),
			for: browser
		)

		XCTAssertEqual(cameraCoordinator.registeredConsumers.last?.id, tabID.uuidString)
		XCTAssertEqual(cameraCoordinator.currentSnapshot().liveFrameConsumerCount, 1)
		XCTAssertEqual(cameraCoordinator.notedRoutingEvents.last?.tabID, tabID.uuidString)
		XCTAssertEqual(cameraCoordinator.notedRoutingEvents.last?.event.managedTrackID, "track-1")

		runtime.fireMainFrameNavigationEvent(
			.init(
				url: "https://camera.example/next",
				userGesture: true,
				isRedirect: false
			),
			for: browser
		)

		XCTAssertTrue(cameraCoordinator.unregisteredConsumerIDs.contains(tabID.uuidString))
		XCTAssertEqual(cameraCoordinator.currentSnapshot().liveFrameConsumerCount, 0)
	}

	func testManagedCameraRoutingEventsRegisterOnceAndUnregisterWhenTracksReachZero() throws {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x44B)
		runtime.createBrowserResults = [browser]
		let cameraCoordinator = BrowserCameraSessionCoordinatorSpy()
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://camera.example")
		let tabID = try XCTUnwrap(viewModel.selectedTabID)
		let presentation = BrowserSidebarPresentation()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0),
			browserCameraSessionCoordinator: cameraCoordinator
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()

		runtime.fireCameraRoutingEvent(
			BrowserCameraRoutingEvent(
				event: .trackStarted,
				activeManagedTrackCount: 1,
				managedTrackID: "track-1"
			),
			for: browser
		)
		runtime.fireCameraRoutingEvent(
			BrowserCameraRoutingEvent(
				event: .trackStarted,
				activeManagedTrackCount: 2,
				managedTrackID: "track-2"
			),
			for: browser
		)

		XCTAssertEqual(cameraCoordinator.registeredConsumers.map(\.id), [tabID.uuidString])
		XCTAssertEqual(cameraCoordinator.currentSnapshot().liveFrameConsumerCount, 1)
		XCTAssertEqual(
			cameraCoordinator.currentSnapshot().browserTransportStates.first?.activeManagedTrackCount,
			2
		)

		runtime.fireCameraRoutingEvent(
			BrowserCameraRoutingEvent(
				event: .trackStopped,
				activeManagedTrackCount: 0,
				managedTrackID: "track-2"
			),
			for: browser
		)

		XCTAssertEqual(cameraCoordinator.unregisteredConsumerIDs, [tabID.uuidString])
		XCTAssertEqual(cameraCoordinator.currentSnapshot().liveFrameConsumerCount, 0)
		XCTAssertEqual(
			cameraCoordinator.currentSnapshot().browserTransportStates.first?.activeManagedTrackCount,
			0
		)
		XCTAssertEqual(cameraCoordinator.notedRoutingEvents.map(\.event.event), [.trackStarted, .trackStarted, .trackStopped])
		XCTAssertEqual(
			cameraCoordinator.notedRoutingEvents.map(\.tabID),
			[tabID.uuidString, tabID.uuidString, tabID.uuidString]
		)
	}

	func testDenyingCameraPromptUnregistersTrackedConsumerWithoutRegistering() throws {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x442)
		runtime.createBrowserResults = [browser]
		let cameraCoordinator = BrowserCameraSessionCoordinatorSpy()
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://camera.example")
		let tabID = try XCTUnwrap(viewModel.selectedTabID)
		let presentation = BrowserSidebarPresentation()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0),
			browserCameraSessionCoordinator: cameraCoordinator
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()
		let container = try XCTUnwrap(chromeView.browserContainerForTesting(tabID: tabID))

		runtime.firePermissionPrompt(
			makePermissionSession(
				id: 501,
				browserID: UInt64(UInt(bitPattern: browser)),
				requestedKinds: .camera,
				promptKinds: .camera
			),
			for: browser
		)
		container.performPermissionPromptDenyForTesting()

		XCTAssertTrue(cameraCoordinator.registeredConsumers.isEmpty)
		XCTAssertEqual(cameraCoordinator.unregisteredConsumerIDs, [tabID.uuidString])
		XCTAssertEqual(cameraCoordinator.currentSnapshot().liveFrameConsumerCount, 0)
	}

	func testDenyingLaterCameraPromptDoesNotUnregisterActiveManagedConsumer() throws {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x4421)
		runtime.createBrowserResults = [browser]
		let cameraCoordinator = BrowserCameraSessionCoordinatorSpy()
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://camera.example")
		let tabID = try XCTUnwrap(viewModel.selectedTabID)
		let presentation = BrowserSidebarPresentation()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0),
			browserCameraSessionCoordinator: cameraCoordinator
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()
		let container = try XCTUnwrap(chromeView.browserContainerForTesting(tabID: tabID))

		runtime.fireCameraRoutingEvent(
			BrowserCameraRoutingEvent(
				event: .trackStarted,
				activeManagedTrackCount: 1,
				managedTrackID: "track-1"
			),
			for: browser
		)
		runtime.firePermissionPrompt(
			makePermissionSession(
				id: 503,
				browserID: UInt64(UInt(bitPattern: browser)),
				requestedKinds: .camera,
				promptKinds: .camera
			),
			for: browser
		)
		container.performPermissionPromptDenyForTesting()

		XCTAssertEqual(cameraCoordinator.registeredConsumers.map(\.id), [tabID.uuidString])
		XCTAssertTrue(cameraCoordinator.unregisteredConsumerIDs.isEmpty)
		XCTAssertEqual(cameraCoordinator.currentSnapshot().liveFrameConsumerCount, 1)
		XCTAssertEqual(
			cameraCoordinator.currentSnapshot().browserTransportStates.first?.activeManagedTrackCount,
			1
		)
	}

	func testNonCameraPromptResolutionDoesNotMutateCameraConsumers() throws {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x443)
		runtime.createBrowserResults = [browser]
		let cameraCoordinator = BrowserCameraSessionCoordinatorSpy()
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://maps.example")
		let tabID = try XCTUnwrap(viewModel.selectedTabID)
		let presentation = BrowserSidebarPresentation()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0),
			browserCameraSessionCoordinator: cameraCoordinator
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()
		let container = try XCTUnwrap(chromeView.browserContainerForTesting(tabID: tabID))

		runtime.firePermissionPrompt(
			makePermissionSession(
				id: 502,
				browserID: UInt64(UInt(bitPattern: browser)),
				requestedKinds: .geolocation,
				promptKinds: .geolocation
			),
			for: browser
		)
		container.performPermissionPromptAllowForTesting()
		container.performPermissionPromptDenyForTesting()

		XCTAssertTrue(cameraCoordinator.registeredConsumers.isEmpty)
		XCTAssertTrue(cameraCoordinator.unregisteredConsumerIDs.isEmpty)
		XCTAssertEqual(cameraCoordinator.currentSnapshot().liveFrameConsumerCount, 0)
	}

	func testClosingBrowserTabClearsTrackedBrowserTransportState() throws {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x44C)
		runtime.createBrowserResults = [browser]
		let cameraCoordinator = BrowserCameraSessionCoordinatorSpy()
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://camera.example")
		let tabID = try XCTUnwrap(viewModel.selectedTabID)
		let presentation = BrowserSidebarPresentation()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0),
			browserCameraSessionCoordinator: cameraCoordinator
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()

		XCTAssertEqual(cameraCoordinator.currentSnapshot().browserTransportStates.map(\.tabID), [tabID.uuidString])

		viewModel.closeTab(id: tabID)

		XCTAssertTrue(cameraCoordinator.currentSnapshot().browserTransportStates.isEmpty)
	}

	func testTitleEventsTrimClearAndResetAcrossNavigationChanges() {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x405)
		runtime.createBrowserResults = [browser]
		let viewModel = makeBrowserSidebarViewModel()
		let presentation = BrowserSidebarPresentation()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0)
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))
		chromeView.ensureSelectedBrowserIsReady()

		runtime.fireAddressChange("https://developer.apple.com/documentation", for: browser)
		runtime.fireTitleChange("  Apple Developer  ", for: browser)
		XCTAssertEqual(viewModel.tabs[0].pageTitle, "Apple Developer")
		XCTAssertEqual(viewModel.tabs[0].displayTitle, "Apple Developer")

		runtime.fireTitleChange(" \n ", for: browser)
		XCTAssertNil(viewModel.tabs[0].pageTitle)
		XCTAssertEqual(
			viewModel.tabs[0].displayTitle,
			"https://developer.apple.com/documentation"
		)

		runtime.fireTitleChange("Swift Documentation", for: browser)
		runtime.fireAddressChange("https://swift.org/documentation", for: browser)
		XCTAssertNil(viewModel.tabs[0].pageTitle)
		XCTAssertEqual(viewModel.tabs[0].displayTitle, "https://swift.org/documentation")
	}

	func testSelectingTabsSwitchesVisibleBrowserContainer() throws {
		let runtime = BrowserRuntimeSpy()
		let viewModel = makeBrowserSidebarViewModel()
		let presentation = BrowserSidebarPresentation()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		let firstVisibleContainer = try XCTUnwrap(
			browserContainers(in: chromeView).first(where: { !$0.isHidden })
		)

		viewModel.addTab()
		let secondVisibleContainer = try XCTUnwrap(
			browserContainers(in: chromeView).first(where: { !$0.isHidden })
		)
		XCTAssertFalse(secondVisibleContainer === firstVisibleContainer)

		let firstTabID = try XCTUnwrap(viewModel.tabs.first?.id)
		viewModel.selectTab(id: firstTabID)
		let reselectedVisibleContainer = try XCTUnwrap(
			browserContainers(in: chromeView).first(where: { !$0.isHidden })
		)
		XCTAssertTrue(reselectedVisibleContainer === firstVisibleContainer)
		XCTAssertEqual(browserContainers(in: chromeView).filter { !$0.isHidden }.count, 1)
	}

	func testLoadedTabSwitchKeepsPreviousContainerVisibleUntilVisibilityHandoffCompletes() throws {
		let runtime = BrowserRuntimeSpy()
		let firstBrowser = makeBrowserRef(0x510)
		let secondBrowser = makeBrowserRef(0x511)
		runtime.createBrowserResults = [firstBrowser, secondBrowser]
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://first.example")
		let presentation = BrowserSidebarPresentation()
		let handoffScheduler = BrowserChromeScheduledWorkSpy()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0),
			visibilityHandoffScheduler: handoffScheduler.schedule
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()
		let firstTabID = try XCTUnwrap(viewModel.selectedTabID)
		let firstContainer = try XCTUnwrap(chromeView.browserContainerForTesting(tabID: firstTabID))

		viewModel.addTab()

		let secondTabID = try XCTUnwrap(viewModel.selectedTabID)
		let secondContainer = try XCTUnwrap(chromeView.browserContainerForTesting(tabID: secondTabID))
		XCTAssertFalse(firstContainer.isHidden)
		XCTAssertFalse(secondContainer.isHidden)
		XCTAssertEqual(browserContainers(in: chromeView).filter { !$0.isHidden }.count, 2)

		handoffScheduler.runScheduledWork()

		XCTAssertTrue(firstContainer.isHidden)
		XCTAssertFalse(secondContainer.isHidden)
		XCTAssertEqual(browserContainers(in: chromeView).filter { !$0.isHidden }.count, 1)
	}

	func testSelectedTabMetadataUpdateDoesNotReopenPreviousVisibilityHandoff() throws {
		let runtime = BrowserRuntimeSpy()
		let firstBrowser = makeBrowserRef(0x512)
		let secondBrowser = makeBrowserRef(0x513)
		runtime.createBrowserResults = [firstBrowser, secondBrowser]
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://first.example")
		let presentation = BrowserSidebarPresentation()
		let handoffScheduler = BrowserChromeScheduledWorkSpy()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0),
			visibilityHandoffScheduler: handoffScheduler.schedule
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()
		let firstTabID = try XCTUnwrap(viewModel.selectedTabID)
		let firstContainer = try XCTUnwrap(chromeView.browserContainerForTesting(tabID: firstTabID))

		viewModel.addTab()

		let secondTabID = try XCTUnwrap(viewModel.selectedTabID)
		let secondContainer = try XCTUnwrap(chromeView.browserContainerForTesting(tabID: secondTabID))
		XCTAssertFalse(firstContainer.isHidden)
		XCTAssertFalse(secondContainer.isHidden)

		viewModel.updateTabURL("https://second-loaded.example", for: secondTabID)

		XCTAssertTrue(firstContainer.isHidden)
		XCTAssertFalse(secondContainer.isHidden)
		XCTAssertEqual(browserContainers(in: chromeView).filter { !$0.isHidden }.count, 1)
		XCTAssertEqual(handoffScheduler.scheduleCount, 1)
	}

	func testMouseMonitoringUpdatesSidebarPresentationAndCleansUp() {
		let runtime = BrowserRuntimeSpy()
		let viewModel = makeBrowserSidebarViewModel()
		let presentation = BrowserSidebarPresentation()
		let scheduledWork = BrowserChromeScheduledWorkSpy()
		let browserChromeViewModel = BrowserChromeViewModel(
			geometry: .init(sidebarWidth: 320),
			workItemScheduler: scheduledWork.schedule,
			sidebarPresentation: presentation
		)
		let monitor = BrowserChromeEventMonitorSpy()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 320,
			browserChromeViewModel: browserChromeViewModel,
			eventMonitoring: monitor.monitoring
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.viewDidMoveToWindow()
		chromeView.updateTrackingAreas()
		chromeView.updateTrackingAreas()
		XCTAssertEqual(monitor.addCount, 1)
		XCTAssertEqual(monitor.interactionAddCount, 1)
		XCTAssertEqual(chromeView.trackingAreas.count, 1)

		let initialActivityCount = runtime.noteBrowserActivityCount
		let openEvent = makeMouseMovedEvent(window: window, location: CGPoint(x: 1, y: 50))
		let returnedEvent = monitor.send(openEvent)

		XCTAssertTrue(returnedEvent === openEvent)
		XCTAssertGreaterThan(runtime.noteBrowserActivityCount, initialActivityCount)
		XCTAssertEqual(scheduledWork.scheduleCount, 1)

		scheduledWork.runScheduledWork()
		XCTAssertTrue(presentation.isPresented)

		_ = chromeView.hitTest(NSPoint(x: 1, y: 1))

		let closeEvent = makeMouseMovedEvent(window: window, location: CGPoint(x: 500, y: 50))
		_ = monitor.send(closeEvent)
		XCTAssertFalse(presentation.isPresented)

		chromeView.viewWillMove(toWindow: nil)
		XCTAssertEqual(monitor.removeCount, 2)
	}

	func testUpdateTrackingAreasReturnsEarlyWithoutWindow() {
		let runtime = BrowserRuntimeSpy()
		let viewModel = makeBrowserSidebarViewModel()
		let presentation = BrowserSidebarPresentation()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300
		)

		chromeView.updateTrackingAreas()

		XCTAssertTrue(chromeView.trackingAreas.isEmpty)
	}

	func testSidebarActionsFallBackWhenChromeViewHasDeallocated() {
		let runtime = BrowserRuntimeSpy()
		let viewModel = makeBrowserSidebarViewModel()
		let presentation = BrowserSidebarPresentation()
		weak var weakChromeView: BrowserChromeView?

		autoreleasepool {
			var chromeView: BrowserChromeView? = BrowserChromeView(
				browserRuntime: runtime,
				sidebarViewModel: viewModel,
				sidebarPresentation: presentation,
				sidebarWidth: 300
			)
			weakChromeView = chromeView
			chromeView?.removeFromSuperview()
			chromeView = nil
		}

		XCTAssertNil(weakChromeView)

		viewModel.goBack()
		viewModel.goForward()
		viewModel.reload()
		viewModel.navigateSelectedTab(to: "swift.org")

		XCTAssertTrue(runtime.goBackRequests.isEmpty)
		XCTAssertTrue(runtime.goForwardRequests.isEmpty)
		XCTAssertTrue(runtime.reloadRequests.isEmpty)
		XCTAssertTrue(runtime.loadRequests.isEmpty)
		XCTAssertEqual(viewModel.canGoBack, false)
		XCTAssertEqual(viewModel.canGoForward, false)
		XCTAssertEqual(viewModel.isLoading, false)
	}

	func testSelectedColdTabCreatesBrowserAfterActivationDelay() {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x501)
		runtime.createBrowserResults = [browser]
		let viewModel = makeBrowserSidebarViewModel()
		let presentation = BrowserSidebarPresentation()
		let scheduledWork = BrowserChromeScheduledWorkSpy()
		let timeProvider = BrowserLifecycleTimeProvider()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0.2),
			activationScheduler: scheduledWork.schedule,
			timeProvider: { timeProvider.now }
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()

		XCTAssertNil(
			chromeView.hostedBrowser,
			"createRequests=\(runtime.createBrowserRequests.count) closeRequests=\(runtime.closeRequests)"
		)
		XCTAssertTrue(runtime.createBrowserRequests.isEmpty)

		scheduledWork.runScheduledWork()

		XCTAssertEqual(chromeView.hostedBrowser, browser)
		XCTAssertEqual(runtime.createBrowserRequests.map(\.initialURL), ["https://navigator.zip"])
	}

	func testDefaultLifecycleConfigurationCommitsSelectedColdTabImmediately() {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x5011)
		runtime.createBrowserResults = [browser]
		let viewModel = makeBrowserSidebarViewModel()
		let presentation = BrowserSidebarPresentation()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init()
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()

		XCTAssertEqual(chromeView.hostedBrowser, browser)
		XCTAssertEqual(runtime.createBrowserRequests.map(\.initialURL), ["https://navigator.zip"])
	}

	func testChangingSelectionInvalidatesStaleActivationTimer() throws {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x502)
		runtime.createBrowserResults = [browser]
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://first.example")
		viewModel.addTab()
		let secondTabID = try XCTUnwrap(viewModel.selectedTabID)
		viewModel.updateTabURL("https://second.example", for: secondTabID)
		let firstTabID = viewModel.tabs[0].id
		let presentation = BrowserSidebarPresentation()
		let scheduledWork = BrowserChromeScheduledWorkSpy()
		let timeProvider = BrowserLifecycleTimeProvider()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0.2),
			activationScheduler: scheduledWork.schedule,
			timeProvider: { timeProvider.now }
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()
		viewModel.selectTab(id: firstTabID)
		scheduledWork.runAllScheduledWork()

		XCTAssertEqual(chromeView.hostedBrowser, browser)
		XCTAssertEqual(runtime.createBrowserRequests.map(\.initialURL), ["https://first.example"])
	}

	func testExplicitNavigationCommitsImmediatelyAndDoesNotStopLoadOnDeselect() {
		let runtime = BrowserRuntimeSpy()
		let firstBrowser = makeBrowserRef(0x503)
		runtime.createBrowserResults = [firstBrowser]
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://first.example")
		let presentation = BrowserSidebarPresentation()
		let scheduledWork = BrowserChromeScheduledWorkSpy()
		let timeProvider = BrowserLifecycleTimeProvider()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0.2),
			activationScheduler: scheduledWork.schedule,
			timeProvider: { timeProvider.now }
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()
		viewModel.navigateSelectedTab(to: "https://swift.org")

		XCTAssertEqual(chromeView.hostedBrowser, firstBrowser)
		XCTAssertEqual(runtime.loadRequests.last?.url, "https://swift.org")

		viewModel.addTab()

		XCTAssertFalse(runtime.stopLoadRequests.contains(where: { $0 == firstBrowser }))
		XCTAssertFalse(runtime.closeRequests.contains(where: { $0 == firstBrowser }))
	}

	func testRendererCrashDiscardsCommittedTabUntilReselection() throws {
		let runtime = BrowserRuntimeSpy()
		let containerScheduler = BrowserContainerSchedulerSpy()
		let firstBrowser = makeBrowserRef(0x505)
		let secondBrowser = makeBrowserRef(0x506)
		let recreatedFirstBrowser = makeBrowserRef(0x507)
		runtime.createBrowserResults = [firstBrowser, secondBrowser, recreatedFirstBrowser]
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://first.example")
		let firstTabID = try XCTUnwrap(viewModel.selectedTabID)
		let presentation = BrowserSidebarPresentation()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0.2),
			activationScheduler: BrowserChromeView.defaultActivationScheduler,
			browserContainerCreationScheduler: containerScheduler.schedule,
			timeProvider: BrowserChromeView.defaultTimeProvider
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()
		viewModel.navigateSelectedTab(to: "https://first.example")

		runtime.fireRenderProcessTermination(
			.init(status: 2, errorCode: 9, errorDescription: "Renderer crashed"),
			for: firstBrowser
		)

		XCTAssertNil(chromeView.hostedBrowser)
		XCTAssertTrue(runtime.closeRequests.contains(where: { $0 == firstBrowser }))

		viewModel.addTab()
		viewModel.navigateSelectedTab(to: "https://second.example")
		viewModel.selectTab(id: firstTabID)

		XCTAssertEqual(chromeView.hostedBrowser, recreatedFirstBrowser)
	}

	func testCommittedDiscardCapturesAndRestoresScrollPosition() throws {
		let runtime = BrowserRuntimeSpy()
		let containerScheduler = BrowserContainerSchedulerSpy()
		let firstBrowser = makeBrowserRef(0x508)
		let secondBrowser = makeBrowserRef(0x509)
		let thirdBrowser = makeBrowserRef(0x50A)
		let fourthBrowser = makeBrowserRef(0x50B)
		let recreatedFirstBrowser = makeBrowserRef(0x50C)
		runtime.createBrowserResults = [firstBrowser, secondBrowser, thirdBrowser, fourthBrowser, recreatedFirstBrowser]
		runtime.evaluateJavaScriptResults = [("{\"x\":12.5,\"y\":240.0}", nil), (nil, nil)]
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://first.example")
		let firstTabID = try XCTUnwrap(viewModel.selectedTabID)
		let presentation = BrowserSidebarPresentation()
		let scheduledWork = BrowserChromeScheduledWorkSpy()
		let timeProvider = BrowserLifecycleTimeProvider(now: 10)
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0.2, minimumLiveBrowserLifetime: 2, maxLiveBrowsers: 1),
			activationScheduler: scheduledWork.schedule,
			browserContainerCreationScheduler: containerScheduler.schedule,
			timeProvider: { timeProvider.now }
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()
		viewModel.navigateSelectedTab(to: "https://first.example")
		timeProvider.advance(by: 3)

		viewModel.addTab()
		viewModel.navigateSelectedTab(to: "https://second.example")
		timeProvider.advance(by: 3)
		viewModel.addTab()
		viewModel.navigateSelectedTab(to: "https://third.example")
		timeProvider.advance(by: 3)
		viewModel.addTab()
		viewModel.navigateSelectedTab(to: "https://fourth.example")
		timeProvider.advance(by: 3)

		XCTAssertTrue(runtime.closeRequests.contains(where: { $0 == firstBrowser }))
		XCTAssertTrue(runtime.evaluateJavaScriptRequests.contains(where: {
			$0.browser == firstBrowser && $0.script.contains("window.scrollX")
		}))

		viewModel.selectTab(id: firstTabID)
		runtime.fireAddressChange("https://first.example", for: recreatedFirstBrowser)

		XCTAssertTrue(
			runtime.evaluateJavaScriptRequests.contains(where: {
				$0.browser == recreatedFirstBrowser && $0.script.contains("window.scrollTo")
			})
		)
	}

	func testExplicitInteractionCommitsTransientSelectionImmediately() {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x504)
		runtime.createBrowserResults = [browser]
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://first.example")
		let presentation = BrowserSidebarPresentation()
		let scheduledWork = BrowserChromeScheduledWorkSpy()
		let monitor = BrowserChromeEventMonitorSpy()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			browserChromeViewModel: BrowserChromeViewModel(
				geometry: .init(sidebarWidth: 300),
				workItemScheduler: BrowserChromeViewModel.defaultWorkItemScheduler,
				sidebarPresentation: presentation
			),
			eventMonitoring: monitor.monitoring,
			tabLifecycleConfiguration: .init(activationDelay: 0.2),
			activationScheduler: scheduledWork.schedule,
			timeProvider: BrowserChromeView.defaultTimeProvider
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()

		XCTAssertNil(chromeView.hostedBrowser)

		_ = monitor.sendInteraction(makeKeyDownEvent(window: window))

		XCTAssertEqual(chromeView.hostedBrowser, browser)
		XCTAssertEqual(runtime.createBrowserRequests.map(\.initialURL), ["https://first.example"])
	}

	func testCommittedHiddenBrowserEvictsOldestUnprotectedAndReselectionRecreatesImmediately() throws {
		let runtime = BrowserRuntimeSpy()
		let firstBrowser = makeBrowserRef(0x510)
		let secondBrowser = makeBrowserRef(0x511)
		let thirdBrowser = makeBrowserRef(0x512)
		let fourthBrowser = makeBrowserRef(0x513)
		let recreatedFirstBrowser = makeBrowserRef(0x514)
		runtime.createBrowserResults = [firstBrowser, secondBrowser, thirdBrowser, fourthBrowser, recreatedFirstBrowser]
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://first.example")
		let firstTabID = try XCTUnwrap(viewModel.selectedTabID)
		let presentation = BrowserSidebarPresentation()
		let scheduledWork = BrowserChromeScheduledWorkSpy()
		let timeProvider = BrowserLifecycleTimeProvider()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0.2, minimumLiveBrowserLifetime: 2, maxLiveBrowsers: 3),
			activationScheduler: scheduledWork.schedule,
			timeProvider: { timeProvider.now }
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()
		viewModel.navigateSelectedTab(to: "https://first.example")
		timeProvider.advance(by: 3)

		viewModel.addTab()
		viewModel.navigateSelectedTab(to: "https://second.example")
		let secondTabID = try XCTUnwrap(viewModel.selectedTabID)
		timeProvider.advance(by: 3)

		viewModel.addTab()
		viewModel.navigateSelectedTab(to: "https://third.example")
		let thirdTabID = try XCTUnwrap(viewModel.selectedTabID)
		timeProvider.advance(by: 3)

		viewModel.addTab()
		viewModel.navigateSelectedTab(to: "https://fourth.example")

		XCTAssertTrue(runtime.closeRequests.contains(where: { $0 == firstBrowser }))
		XCTAssertEqual(chromeView.hostedBrowser, fourthBrowser)

		viewModel.selectTab(id: firstTabID)

		XCTAssertEqual(chromeView.hostedBrowser, recreatedFirstBrowser)
		XCTAssertEqual(viewModel.selectedTabID, firstTabID)
		XCTAssertFalse(runtime.stopLoadRequests.contains(where: { $0 == firstBrowser }))
		_ = secondTabID
		_ = thirdTabID
	}

	func testDefaultLifecycleConfigurationDoesNotEvictFourthCommittedHiddenBrowser() {
		let runtime = BrowserRuntimeSpy()
		let firstBrowser = makeBrowserRef(0x5101)
		let secondBrowser = makeBrowserRef(0x5102)
		let thirdBrowser = makeBrowserRef(0x5103)
		let fourthBrowser = makeBrowserRef(0x5104)
		runtime.createBrowserResults = [firstBrowser, secondBrowser, thirdBrowser, fourthBrowser]
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://first.example")
		let presentation = BrowserSidebarPresentation()
		let scheduledWork = BrowserChromeScheduledWorkSpy()
		let timeProvider = BrowserLifecycleTimeProvider()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(),
			activationScheduler: scheduledWork.schedule,
			timeProvider: { timeProvider.now }
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()
		viewModel.navigateSelectedTab(to: "https://first.example")
		timeProvider.advance(by: 3)

		viewModel.addTab()
		viewModel.navigateSelectedTab(to: "https://second.example")
		timeProvider.advance(by: 3)

		viewModel.addTab()
		viewModel.navigateSelectedTab(to: "https://third.example")
		timeProvider.advance(by: 3)

		viewModel.addTab()
		viewModel.navigateSelectedTab(to: "https://fourth.example")

		XCTAssertTrue(runtime.closeRequests.isEmpty)
		XCTAssertEqual(chromeView.hostedBrowser, fourthBrowser)
	}

	func testClosingTransientTabCancelsPendingActivationWork() throws {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x515)
		runtime.createBrowserResults = [browser]
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://first.example")
		viewModel.addTab()
		let selectedTabID = try XCTUnwrap(viewModel.selectedTabID)
		let presentation = BrowserSidebarPresentation()
		let scheduledWork = BrowserChromeScheduledWorkSpy()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0.2),
			activationScheduler: scheduledWork.schedule,
			timeProvider: BrowserChromeView.defaultTimeProvider
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()
		viewModel.closeTab(id: selectedTabID)
		scheduledWork.runAllScheduledWork()

		XCTAssertFalse(runtime.createBrowserRequests.map(\.initialURL).contains("https://navigator.zip"))
	}

	func testMemoryPressureForceDiscardsHiddenCommittedBrowsers() {
		let runtime = BrowserRuntimeSpy()
		let firstBrowser = makeBrowserRef(0x520)
		let secondBrowser = makeBrowserRef(0x521)
		let thirdBrowser = makeBrowserRef(0x522)
		let fourthBrowser = makeBrowserRef(0x523)
		runtime.createBrowserResults = [firstBrowser, secondBrowser, thirdBrowser, fourthBrowser]
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://first.example")
		let firstTabID = viewModel.tabs[0].id
		let presentation = BrowserSidebarPresentation()
		let scheduledWork = BrowserChromeScheduledWorkSpy()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0.2, minimumLiveBrowserLifetime: 10, maxLiveBrowsers: 4),
			activationScheduler: scheduledWork.schedule,
			timeProvider: BrowserChromeView.defaultTimeProvider
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()
		viewModel.navigateSelectedTab(to: "https://first.example")
		viewModel.addTab()
		viewModel.navigateSelectedTab(to: "https://second.example")
		viewModel.addTab()
		viewModel.navigateSelectedTab(to: "https://third.example")
		viewModel.addTab()
		viewModel.navigateSelectedTab(to: "https://fourth.example")

		XCTAssertTrue(runtime.closeRequests.isEmpty)

		chromeView.handleMemoryPressure()

		XCTAssertTrue(runtime.closeRequests.contains(where: { $0 == firstBrowser }))
		XCTAssertEqual(viewModel.tabs.first(where: { $0.id == firstTabID })?.currentURL, "https://first.example")
	}

	func testAuthSensitiveHiddenTabIsProtectedFromEviction() {
		let runtime = BrowserRuntimeSpy()
		let firstBrowser = makeBrowserRef(0x524)
		let secondBrowser = makeBrowserRef(0x525)
		let thirdBrowser = makeBrowserRef(0x526)
		let fourthBrowser = makeBrowserRef(0x527)
		runtime.createBrowserResults = [firstBrowser, secondBrowser, thirdBrowser, fourthBrowser]
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://first.example")
		let firstTabID = viewModel.tabs[0].id
		let presentation = BrowserSidebarPresentation()
		let scheduledWork = BrowserChromeScheduledWorkSpy()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0.2, minimumLiveBrowserLifetime: 0, maxLiveBrowsers: 3),
			activationScheduler: scheduledWork.schedule,
			timeProvider: BrowserChromeView.defaultTimeProvider
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()
		viewModel.navigateSelectedTab(to: "https://first.example")
		runtime.fireMainFrameNavigationEvent(
			.init(url: "https://accounts.google.com/o/oauth2/v2/auth", userGesture: false, isRedirect: true),
			for: firstBrowser
		)
		viewModel.addTab()
		viewModel.navigateSelectedTab(to: "https://second.example")
		viewModel.addTab()
		viewModel.navigateSelectedTab(to: "https://third.example")
		viewModel.addTab()
		viewModel.navigateSelectedTab(to: "https://fourth.example")

		XCTAssertFalse(runtime.closeRequests.contains(where: { $0 == firstBrowser }))
		XCTAssertEqual(viewModel.selectedTabID, viewModel.tabs.last?.id)
		_ = firstTabID
	}

	func testDevToolsProtectedHiddenTabIsProtectedFromEviction() {
		let runtime = BrowserRuntimeSpy()
		let firstBrowser = makeBrowserRef(0x528)
		let secondBrowser = makeBrowserRef(0x529)
		let thirdBrowser = makeBrowserRef(0x52A)
		let fourthBrowser = makeBrowserRef(0x52B)
		runtime.createBrowserResults = [firstBrowser, secondBrowser, thirdBrowser, fourthBrowser]
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://first.example")
		let firstTabID = viewModel.tabs[0].id
		let presentation = BrowserSidebarPresentation()
		let scheduledWork = BrowserChromeScheduledWorkSpy()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0.2, minimumLiveBrowserLifetime: 0, maxLiveBrowsers: 3),
			activationScheduler: scheduledWork.schedule,
			timeProvider: BrowserChromeView.defaultTimeProvider
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()
		viewModel.navigateSelectedTab(to: "https://first.example")
		chromeView.setDevToolsProtection(true, for: firstTabID)
		viewModel.addTab()
		viewModel.navigateSelectedTab(to: "https://second.example")
		viewModel.addTab()
		viewModel.navigateSelectedTab(to: "https://third.example")
		viewModel.addTab()
		viewModel.navigateSelectedTab(to: "https://fourth.example")

		XCTAssertFalse(runtime.closeRequests.contains(where: { $0 == firstBrowser }))
	}

	func testAccessibilityProtectedHiddenTabIsProtectedFromEviction() {
		let runtime = BrowserRuntimeSpy()
		let firstBrowser = makeBrowserRef(0x52C)
		let secondBrowser = makeBrowserRef(0x52D)
		let thirdBrowser = makeBrowserRef(0x52E)
		let fourthBrowser = makeBrowserRef(0x52F)
		runtime.createBrowserResults = [firstBrowser, secondBrowser, thirdBrowser, fourthBrowser]
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://first.example")
		let firstTabID = viewModel.tabs[0].id
		let presentation = BrowserSidebarPresentation()
		let scheduledWork = BrowserChromeScheduledWorkSpy()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0.2, minimumLiveBrowserLifetime: 0, maxLiveBrowsers: 3),
			activationScheduler: scheduledWork.schedule,
			timeProvider: BrowserChromeView.defaultTimeProvider
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()
		viewModel.navigateSelectedTab(to: "https://first.example")
		chromeView.setAccessibilityProtection(true, for: firstTabID)
		viewModel.addTab()
		viewModel.navigateSelectedTab(to: "https://second.example")
		viewModel.addTab()
		viewModel.navigateSelectedTab(to: "https://third.example")
		viewModel.addTab()
		viewModel.navigateSelectedTab(to: "https://fourth.example")

		XCTAssertFalse(runtime.closeRequests.contains(where: { $0 == firstBrowser }))
	}

	func testPermissionPromptProtectedHiddenTabIsProtectedFromEviction() {
		let runtime = BrowserRuntimeSpy()
		let firstBrowser = makeBrowserRef(0x530)
		let secondBrowser = makeBrowserRef(0x531)
		let thirdBrowser = makeBrowserRef(0x532)
		let fourthBrowser = makeBrowserRef(0x533)
		runtime.createBrowserResults = [firstBrowser, secondBrowser, thirdBrowser, fourthBrowser]
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://first.example")
		let firstTabID = viewModel.tabs[0].id
		let presentation = BrowserSidebarPresentation()
		let scheduledWork = BrowserChromeScheduledWorkSpy()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0.2, minimumLiveBrowserLifetime: 0, maxLiveBrowsers: 3),
			activationScheduler: scheduledWork.schedule,
			timeProvider: BrowserChromeView.defaultTimeProvider
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()
		viewModel.navigateSelectedTab(to: "https://first.example")
		runtime.firePermissionPrompt(
			makePermissionSession(
				id: 300,
				browserID: UInt64(UInt(bitPattern: firstBrowser)),
				requestedKinds: .camera,
				promptKinds: .camera
			),
			for: firstBrowser
		)
		XCTAssertTrue(chromeView.protectionReasonsForTesting(tabID: firstTabID).contains(.permissionPrompt))

		viewModel.addTab()
		viewModel.navigateSelectedTab(to: "https://second.example")
		viewModel.addTab()
		viewModel.navigateSelectedTab(to: "https://third.example")
		viewModel.addTab()
		viewModel.navigateSelectedTab(to: "https://fourth.example")

		XCTAssertFalse(runtime.closeRequests.contains(where: { $0 == firstBrowser }))
	}

	func testWindowOcclusionForceDiscardsHiddenCommittedBrowsers() {
		let runtime = BrowserRuntimeSpy()
		let firstBrowser = makeBrowserRef(0x534)
		let secondBrowser = makeBrowserRef(0x535)
		let thirdBrowser = makeBrowserRef(0x536)
		let fourthBrowser = makeBrowserRef(0x537)
		runtime.createBrowserResults = [firstBrowser, secondBrowser, thirdBrowser, fourthBrowser]
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://first.example")
		let presentation = BrowserSidebarPresentation()
		let scheduledWork = BrowserChromeScheduledWorkSpy()
		let chromeView = BrowserChromeView(
			browserRuntime: runtime,
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 300,
			tabLifecycleConfiguration: .init(activationDelay: 0.2, minimumLiveBrowserLifetime: 10, maxLiveBrowsers: 4),
			activationScheduler: scheduledWork.schedule,
			timeProvider: BrowserChromeView.defaultTimeProvider
		)
		let window = makeWindow(size: CGSize(width: 700, height: 500))
		host(chromeView, in: window, size: CGSize(width: 700, height: 500))

		chromeView.ensureSelectedBrowserIsReady()
		viewModel.navigateSelectedTab(to: "https://first.example")
		viewModel.addTab()
		viewModel.navigateSelectedTab(to: "https://second.example")
		viewModel.addTab()
		viewModel.navigateSelectedTab(to: "https://third.example")
		viewModel.addTab()
		viewModel.navigateSelectedTab(to: "https://fourth.example")

		chromeView.handleWindowVisibilityChange(isEffectivelyVisible: false)

		XCTAssertTrue(runtime.closeRequests.contains(where: { $0 == firstBrowser }))
	}

	private func browserContainers(in chromeView: BrowserChromeView) -> [BrowserContainerView] {
		chromeView.subviews
			.flatMap(\.subviews)
			.compactMap { $0 as? BrowserContainerView }
	}

	private func makeBrowserCameraPreviewFrame() -> CGImage {
		let image = NSImage(size: NSSize(width: 8, height: 8))
		image.lockFocus()
		NSColor.systemBlue.setFill()
		NSBezierPath(rect: NSRect(x: 0, y: 0, width: 8, height: 8)).fill()
		image.unlockFocus()
		return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
	}
}
