import BrowserRuntime
import BrowserSidebar
@testable import BrowserView
import ModelKit
import XCTest

@MainActor
final class BrowserViewControllerTests: XCTestCase {
	func testPublicInitializerCreatesControllerWithoutLoadingView() {
		let viewModel = makeBrowserSidebarViewModel()
		let presentation = BrowserSidebarPresentation()
		let controller = BrowserViewController(
			windowID: UUID(),
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 320
		)
		controller.loadViewIfNeeded()

		XCTAssertEqual(controller.view.subviews.count, 1)
	}

	func testViewControllerBuildsChromeViewAndEnsuresSelectedBrowserOnAppearance() {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x505)
		runtime.createBrowserResults = [browser]
		let viewModel = makeBrowserSidebarViewModel()
		let presentation = BrowserSidebarPresentation()
		let controller = BrowserViewController(
			windowID: UUID(),
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 320,
			browserRuntime: runtime,

			browserChromeViewModel: BrowserChromeViewModel(
				geometry: .init(sidebarWidth: 320),
				workItemScheduler: BrowserChromeViewModel.defaultWorkItemScheduler,
				sidebarPresentation: presentation
			),
			eventMonitoring: .live,
			tabLifecycleConfiguration: .init(activationDelay: 0),
			activationScheduler: BrowserChromeView.defaultActivationScheduler,
			timeProvider: BrowserChromeView.defaultTimeProvider
		)
		controller.loadViewIfNeeded()

		XCTAssertEqual(controller.view.subviews.count, 1)
		XCTAssertNil(controller.hostedBrowser)

		let window = makeWindow(size: CGSize(width: 900, height: 700))
		host(controller.view, in: window, size: CGSize(width: 900, height: 700))
		controller.view.layoutSubtreeIfNeeded()
		let initialActivityCount = runtime.noteBrowserActivityCount

		controller.viewDidAppear()

		XCTAssertEqual(controller.hostedBrowser, browser)
		XCTAssertGreaterThan(runtime.noteBrowserActivityCount, initialActivityCount)
	}

	func testUpdatingSidebarWidthRefreshesRootHitTestRange() {
		let viewModel = makeBrowserSidebarViewModel()
		let presentation = BrowserSidebarPresentation(isPresented: true)
		let controller = BrowserViewController(
			windowID: UUID(),
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 320
		)
		controller.loadViewIfNeeded()

		XCTAssertNil(controller.view.hitTest(NSPoint(x: 340, y: 100)))

		controller.updateSidebarWidth(420)
		XCTAssertNil(controller.view.hitTest(NSPoint(x: 430, y: 100)))

		controller.updateSidebarWidth(240)
		XCTAssertNotNil(controller.view.hitTest(NSPoint(x: 290, y: 100)))
	}

	func testViewControllerOnlyCreatesBrowsersForSelectedTabs() throws {
		let runtime = BrowserRuntimeSpy()
		let initiallySelectedBrowser = makeBrowserRef(0x601)
		let newlySelectedBrowser = makeBrowserRef(0x602)
		runtime.createBrowserResults = [initiallySelectedBrowser, newlySelectedBrowser]
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://first.example")
		let firstTabID = try XCTUnwrap(viewModel.selectedTabID)
		viewModel.addTab()
		let secondTabID = try XCTUnwrap(viewModel.selectedTabID)
		viewModel.updateTabURL("https://second.example", for: secondTabID)
		viewModel.addTab()
		let thirdTabID = try XCTUnwrap(viewModel.selectedTabID)
		viewModel.updateTabURL("https://third.example", for: thirdTabID)
		let presentation = BrowserSidebarPresentation()
		let controller = BrowserViewController(
			windowID: UUID(),
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 320,
			browserRuntime: runtime,

			browserChromeViewModel: BrowserChromeViewModel(
				geometry: .init(sidebarWidth: 320),
				workItemScheduler: BrowserChromeViewModel.defaultWorkItemScheduler,
				sidebarPresentation: presentation
			),
			eventMonitoring: .live,
			tabLifecycleConfiguration: .init(activationDelay: 0),
			activationScheduler: BrowserChromeView.defaultActivationScheduler,
			timeProvider: BrowserChromeView.defaultTimeProvider
		)
		controller.loadViewIfNeeded()
		let window = makeWindow(size: CGSize(width: 900, height: 700))
		host(controller.view, in: window, size: CGSize(width: 900, height: 700))
		controller.view.layoutSubtreeIfNeeded()

		controller.viewDidAppear()

		XCTAssertEqual(runtime.createBrowserRequests.map(\.initialURL), ["https://third.example"])
		XCTAssertEqual(controller.hostedBrowser, initiallySelectedBrowser)

		viewModel.selectTab(id: firstTabID)

		XCTAssertEqual(
			runtime.createBrowserRequests.map(\.initialURL),
			["https://third.example", "https://first.example"]
		)
		XCTAssertEqual(controller.hostedBrowser, newlySelectedBrowser)
	}

	func testSelectingRestoredTabIgnoresTransientInitialAboutBlankAddressChange() throws {
		let runtime = BrowserRuntimeSpy()
		let firstBrowser = makeBrowserRef(0x701)
		let secondBrowser = makeBrowserRef(0x702)
		runtime.createBrowserResults = [firstBrowser, secondBrowser]

		let firstTabID = try XCTUnwrap(BrowserTabID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))
		let secondTabID = try XCTUnwrap(BrowserTabID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))
		let viewModel = makeBrowserSidebarViewModel()
		viewModel.restoreTabs(
			[
				StoredBrowserTab(
					id: firstTabID,
					objectVersion: 1,
					orderKey: "a",
					url: "https://first.example",
					title: "First Page"
				),
				StoredBrowserTab(
					id: secondTabID,
					objectVersion: 1,
					orderKey: "b",
					url: "https://second.example",
					title: "Saved Second Page"
				),
			],
			selectedTabID: firstTabID
		)
		let presentation = BrowserSidebarPresentation()
		let controller = BrowserViewController(
			windowID: UUID(),
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 320,
			browserRuntime: runtime,
			browserChromeViewModel: BrowserChromeViewModel(
				geometry: .init(sidebarWidth: 320),
				workItemScheduler: BrowserChromeViewModel.defaultWorkItemScheduler,
				sidebarPresentation: presentation
			),
			eventMonitoring: .live,
			tabLifecycleConfiguration: .init(activationDelay: 0),
			activationScheduler: BrowserChromeView.defaultActivationScheduler,
			timeProvider: BrowserChromeView.defaultTimeProvider
		)
		controller.loadViewIfNeeded()
		let window = makeWindow(size: CGSize(width: 900, height: 700))
		host(controller.view, in: window, size: CGSize(width: 900, height: 700))
		controller.view.layoutSubtreeIfNeeded()

		controller.viewDidAppear()
		viewModel.selectTab(id: secondTabID)
		runtime.fireAddressChange("about:blank", for: secondBrowser)

		let selectedTab = try XCTUnwrap(viewModel.tabs.first(where: { $0.id == secondTabID }))
		XCTAssertEqual(selectedTab.currentURL, "https://second.example")
		XCTAssertEqual(selectedTab.pageTitle, "Saved Second Page")
		XCTAssertEqual(selectedTab.displayTitle, "Saved Second Page")

		runtime.fireAddressChange("https://second.example", for: secondBrowser)

		XCTAssertEqual(selectedTab.currentURL, "https://second.example")
		XCTAssertEqual(selectedTab.pageTitle, "Saved Second Page")
	}

	func testGoBackUsesRestoredHistoryAfterBrowserRecreation() throws {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x7A1)
		runtime.createBrowserResults = [browser]
		runtime.setNavigationState(
			BrowserSidebarNavigationState(canGoBack: false, canGoForward: false, isLoading: false),
			for: browser
		)
		let tabID = try XCTUnwrap(BrowserTabID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"))
		let viewModel = makeBrowserSidebarViewModel()
		viewModel.restoreTabs(
			[
				StoredBrowserTab(
					id: tabID,
					objectVersion: 1,
					orderKey: "a",
					url: "https://c.example",
					title: "Page C",
					historyEntries: [
						StoredBrowserHistoryEntry(url: "https://a.example", title: "Page A"),
						StoredBrowserHistoryEntry(url: "https://b.example", title: "Page B"),
						StoredBrowserHistoryEntry(url: "https://c.example", title: "Page C"),
					],
					currentHistoryIndex: 2
				),
			],
			selectedTabID: tabID
		)
		let presentation = BrowserSidebarPresentation()
		let controller = BrowserViewController(
			windowID: UUID(),
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 320,
			browserRuntime: runtime,
			browserChromeViewModel: BrowserChromeViewModel(
				geometry: .init(sidebarWidth: 320),
				workItemScheduler: BrowserChromeViewModel.defaultWorkItemScheduler,
				sidebarPresentation: presentation
			),
			eventMonitoring: .live,
			tabLifecycleConfiguration: .init(activationDelay: 0),
			activationScheduler: BrowserChromeView.defaultActivationScheduler,
			timeProvider: BrowserChromeView.defaultTimeProvider
		)
		controller.loadViewIfNeeded()
		let window = makeWindow(size: CGSize(width: 900, height: 700))
		host(controller.view, in: window, size: CGSize(width: 900, height: 700))
		controller.view.layoutSubtreeIfNeeded()
		controller.viewDidAppear()

		viewModel.goBack()

		XCTAssertEqual(runtime.goBackRequests, [])
		XCTAssertEqual(runtime.loadRequests.map(\.url), ["https://b.example"])

		runtime.fireAddressChange("https://b.example", for: browser)
		let restoredTab = try XCTUnwrap(viewModel.tabs.first(where: { $0.id == tabID }))
		XCTAssertEqual(restoredTab.currentURL, "https://b.example")
		XCTAssertEqual(restoredTab.currentHistoryIndex, 1)
		XCTAssertEqual(restoredTab.historyEntries.map(\.url), [
			"https://a.example",
			"https://b.example",
			"https://c.example",
		])
	}

	func testSubmittingAddressAfterSyntheticBackDropsRestoredForwardHistory() throws {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x7A2)
		runtime.createBrowserResults = [browser]
		runtime.setNavigationState(
			BrowserSidebarNavigationState(canGoBack: false, canGoForward: false, isLoading: false),
			for: browser
		)
		let tabID = try XCTUnwrap(BrowserTabID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD"))
		let viewModel = makeBrowserSidebarViewModel()
		viewModel.restoreTabs(
			[
				StoredBrowserTab(
					id: tabID,
					objectVersion: 1,
					orderKey: "a",
					url: "https://c.example",
					title: "Page C",
					historyEntries: [
						StoredBrowserHistoryEntry(url: "https://a.example", title: "Page A"),
						StoredBrowserHistoryEntry(url: "https://b.example", title: "Page B"),
						StoredBrowserHistoryEntry(url: "https://c.example", title: "Page C"),
					],
					currentHistoryIndex: 2
				),
			],
			selectedTabID: tabID
		)
		let presentation = BrowserSidebarPresentation()
		let controller = BrowserViewController(
			windowID: UUID(),
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 320,
			browserRuntime: runtime,
			browserChromeViewModel: BrowserChromeViewModel(
				geometry: .init(sidebarWidth: 320),
				workItemScheduler: BrowserChromeViewModel.defaultWorkItemScheduler,
				sidebarPresentation: presentation
			),
			eventMonitoring: .live,
			tabLifecycleConfiguration: .init(activationDelay: 0),
			activationScheduler: BrowserChromeView.defaultActivationScheduler,
			timeProvider: BrowserChromeView.defaultTimeProvider
		)
		controller.loadViewIfNeeded()
		let window = makeWindow(size: CGSize(width: 900, height: 700))
		host(controller.view, in: window, size: CGSize(width: 900, height: 700))
		controller.view.layoutSubtreeIfNeeded()
		controller.viewDidAppear()

		viewModel.goBack()
		runtime.fireAddressChange("https://b.example", for: browser)
		viewModel.navigateSelectedTab(to: "https://d.example")

		let restoredTab = try XCTUnwrap(viewModel.tabs.first(where: { $0.id == tabID }))
		XCTAssertEqual(runtime.loadRequests.map(\.url), ["https://b.example", "https://d.example"])
		XCTAssertEqual(restoredTab.historyEntries.map(\.url), [
			"https://a.example",
			"https://b.example",
		])

		let state = viewModel.tabs.first(where: { $0.id == tabID }).map {
			BrowserSidebarNavigationState(
				canGoBack: $0.canGoBack,
				canGoForward: $0.canGoForward,
				isLoading: $0.isLoading
			)
		}
		XCTAssertEqual(state?.canGoForward, false)
	}

	func testGoBackFromPresentedTopLevelNativeContentAlsoNavigatesBrowserHistory() throws {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x703)
		runtime.createBrowserResults = [browser]
		runtime.setNavigationState(
			BrowserSidebarNavigationState(canGoBack: true, canGoForward: false, isLoading: false),
			for: browser
		)
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://first.example")
		let tabID = try XCTUnwrap(viewModel.selectedTabID)
		let presentation = BrowserSidebarPresentation()
		let controller = BrowserViewController(
			windowID: UUID(),
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 320,
			browserRuntime: runtime,
			browserChromeViewModel: BrowserChromeViewModel(
				geometry: .init(sidebarWidth: 320),
				workItemScheduler: BrowserChromeViewModel.defaultWorkItemScheduler,
				sidebarPresentation: presentation
			),
			eventMonitoring: .live,
			tabLifecycleConfiguration: .init(activationDelay: 0),
			activationScheduler: BrowserChromeView.defaultActivationScheduler,
			timeProvider: BrowserChromeView.defaultTimeProvider
		)
		controller.loadViewIfNeeded()
		let window = makeWindow(size: CGSize(width: 900, height: 700))
		host(controller.view, in: window, size: CGSize(width: 900, height: 700))
		controller.view.layoutSubtreeIfNeeded()
		controller.viewDidAppear()
		let container = try XCTUnwrap(controller.browserContainerForTesting(tabID: tabID))
		let content = BrowserRuntimeTopLevelNativeContent(
			kind: .image,
			url: "https://navigator.test/image.png",
			pathExtension: "png",
			uniformTypeIdentifier: "public.png"
		)

		runtime.fireAddressChange(content.url, for: browser)
		runtime.fireTopLevelNativeContent(content, for: browser)
		viewModel.goBack()

		XCTAssertFalse(container.isPresentingTopLevelNativeContent)
		XCTAssertEqual(runtime.goBackRequests, [browser])
	}

	func testPermissionPromptBindsToContainerAndRoutesResolutionThroughRuntime() throws {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x801)
		runtime.createBrowserResults = [browser]
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://first.example")
		let tabID = try XCTUnwrap(viewModel.selectedTabID)
		let presentation = BrowserSidebarPresentation()
		let controller = BrowserViewController(
			windowID: UUID(),
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 320,
			browserRuntime: runtime,
			browserChromeViewModel: BrowserChromeViewModel(
				geometry: .init(sidebarWidth: 320),
				workItemScheduler: BrowserChromeViewModel.defaultWorkItemScheduler,
				sidebarPresentation: presentation
			),
			eventMonitoring: .live,
			tabLifecycleConfiguration: .init(activationDelay: 0),
			activationScheduler: BrowserChromeView.defaultActivationScheduler,
			timeProvider: BrowserChromeView.defaultTimeProvider
		)
		controller.loadViewIfNeeded()
		let window = makeWindow(size: CGSize(width: 900, height: 700))
		host(controller.view, in: window, size: CGSize(width: 900, height: 700))
		controller.view.layoutSubtreeIfNeeded()
		controller.viewDidAppear()
		let container = try XCTUnwrap(controller.browserContainerForTesting(tabID: tabID))
		let session = makePermissionSession(
			id: 91,
			browserID: UInt64(UInt(bitPattern: browser)),
			requestingOrigin: "https://camera.example",
			topLevelOrigin: "https://camera.example",
			promptKinds: [.camera, .microphone]
		)

		runtime.firePermissionPrompt(session, for: browser)

		XCTAssertTrue(container.isPermissionPromptVisibleForTesting)
		XCTAssertTrue(controller.protectionReasonsForTesting(tabID: tabID).contains(.permissionPrompt))

		container.setPermissionPromptRememberForTesting(true)
		container.performPermissionPromptAllowForTesting()

		XCTAssertEqual(runtime.resolvedPermissionPrompts.count, 1)
		XCTAssertEqual(runtime.resolvedPermissionPrompts.first?.sessionID, 91)
		XCTAssertEqual(runtime.resolvedPermissionPrompts.first?.decision, .allow)
		XCTAssertEqual(runtime.resolvedPermissionPrompts.first?.persistence, .remember)

		runtime.firePermissionPrompt(nil, for: browser)

		XCTAssertFalse(container.isPermissionPromptVisibleForTesting)
		XCTAssertFalse(controller.protectionReasonsForTesting(tabID: tabID).contains(.permissionPrompt))
	}

	func testPermissionPromptCancelRoutesThroughRuntime() throws {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x804)
		runtime.createBrowserResults = [browser]
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://first.example")
		let tabID = try XCTUnwrap(viewModel.selectedTabID)
		let presentation = BrowserSidebarPresentation()
		let controller = BrowserViewController(
			windowID: UUID(),
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 320,
			browserRuntime: runtime,
			browserChromeViewModel: BrowserChromeViewModel(
				geometry: .init(sidebarWidth: 320),
				workItemScheduler: BrowserChromeViewModel.defaultWorkItemScheduler,
				sidebarPresentation: presentation
			),
			eventMonitoring: .live,
			tabLifecycleConfiguration: .init(activationDelay: 0),
			activationScheduler: BrowserChromeView.defaultActivationScheduler,
			timeProvider: BrowserChromeView.defaultTimeProvider
		)
		controller.loadViewIfNeeded()
		let window = makeWindow(size: CGSize(width: 900, height: 700))
		host(controller.view, in: window, size: CGSize(width: 900, height: 700))
		controller.view.layoutSubtreeIfNeeded()
		controller.viewDidAppear()
		let container = try XCTUnwrap(controller.browserContainerForTesting(tabID: tabID))

		runtime.firePermissionPrompt(
			makeScopedPermissionSession(
				id: 92,
				browserID: UInt64(UInt(bitPattern: browser)),
				promptKinds: .camera
			),
			for: browser
		)

		container.performPermissionPromptCancelForTesting()

		XCTAssertEqual(runtime.cancelledPermissionPromptSessionIDs, [92])
	}

	func testPermissionPromptDismissalAfterBrowserDiscardClearsProtection() throws {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x805)
		runtime.createBrowserResults = [browser]
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://first.example")
		let tabID = try XCTUnwrap(viewModel.selectedTabID)
		let presentation = BrowserSidebarPresentation()
		let controller = BrowserViewController(
			windowID: UUID(),
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 320,
			browserRuntime: runtime,
			browserChromeViewModel: BrowserChromeViewModel(
				geometry: .init(sidebarWidth: 320),
				workItemScheduler: BrowserChromeViewModel.defaultWorkItemScheduler,
				sidebarPresentation: presentation
			),
			eventMonitoring: .live,
			tabLifecycleConfiguration: .init(activationDelay: 0),
			activationScheduler: BrowserChromeView.defaultActivationScheduler,
			timeProvider: BrowserChromeView.defaultTimeProvider
		)
		controller.loadViewIfNeeded()
		let window = makeWindow(size: CGSize(width: 900, height: 700))
		host(controller.view, in: window, size: CGSize(width: 900, height: 700))
		controller.view.layoutSubtreeIfNeeded()
		controller.viewDidAppear()
		let container = try XCTUnwrap(controller.browserContainerForTesting(tabID: tabID))

		runtime.firePermissionPrompt(
			makeScopedPermissionSession(
				id: 93,
				browserID: UInt64(UInt(bitPattern: browser)),
				promptKinds: .camera
			),
			for: browser
		)
		XCTAssertTrue(controller.protectionReasonsForTesting(tabID: tabID).contains(.permissionPrompt))

		container.discardBrowser(stopLoad: false)
		XCTAssertNil(container.browserRef)

		runtime.firePermissionPrompt(nil, for: browser)

		XCTAssertFalse(container.isPermissionPromptVisibleForTesting)
		XCTAssertFalse(controller.protectionReasonsForTesting(tabID: tabID).contains(.permissionPrompt))
	}

	func testPermissionPromptIsScopedToRequestingBrowserContainer() throws {
		let runtime = BrowserRuntimeSpy()
		let secondBrowser = makeBrowserRef(0x802)
		let firstBrowser = makeBrowserRef(0x803)
		runtime.createBrowserResults = [secondBrowser, firstBrowser]
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://first.example")
		let firstTabID = try XCTUnwrap(viewModel.selectedTabID)
		viewModel.addTab()
		let secondTabID = try XCTUnwrap(viewModel.selectedTabID)
		viewModel.updateTabURL("https://second.example", for: secondTabID)
		let presentation = BrowserSidebarPresentation()
		let controller = BrowserViewController(
			windowID: UUID(),
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 320,
			browserRuntime: runtime,
			browserChromeViewModel: BrowserChromeViewModel(
				geometry: .init(sidebarWidth: 320),
				workItemScheduler: BrowserChromeViewModel.defaultWorkItemScheduler,
				sidebarPresentation: presentation
			),
			eventMonitoring: .live,
			tabLifecycleConfiguration: .init(activationDelay: 0),
			activationScheduler: BrowserChromeView.defaultActivationScheduler,
			timeProvider: BrowserChromeView.defaultTimeProvider
		)
		controller.loadViewIfNeeded()
		let window = makeWindow(size: CGSize(width: 900, height: 700))
		host(controller.view, in: window, size: CGSize(width: 900, height: 700))
		controller.view.layoutSubtreeIfNeeded()
		controller.viewDidAppear()
		viewModel.selectTab(id: firstTabID)
		let firstContainer = try XCTUnwrap(controller.browserContainerForTesting(tabID: firstTabID))
		let secondContainer = try XCTUnwrap(controller.browserContainerForTesting(tabID: secondTabID))
		let session = makeScopedPermissionSession(
			id: 92,
			browserID: UInt64(UInt(bitPattern: secondBrowser)),
			requestingOrigin: "https://frame.example",
			topLevelOrigin: "https://top.example",
			promptKinds: [.geolocation]
		)

		runtime.firePermissionPrompt(session, for: secondBrowser)

		XCTAssertFalse(firstContainer.isPermissionPromptVisibleForTesting)
		XCTAssertTrue(secondContainer.isPermissionPromptVisibleForTesting)
		XCTAssertTrue(controller.protectionReasonsForTesting(tabID: secondTabID).contains(.permissionPrompt))
		XCTAssertFalse(controller.protectionReasonsForTesting(tabID: firstTabID).contains(.permissionPrompt))
	}

	func testCommandClickOpensRequestedURLInNewBackgroundTab() throws {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x811)
		runtime.createBrowserResults = [browser]
		let viewModel = makeBrowserSidebarViewModel(initialAddress: "https://first.example")
		let initialTabID = try XCTUnwrap(viewModel.selectedTabID)
		let presentation = BrowserSidebarPresentation()
		let controller = BrowserViewController(
			windowID: UUID(),
			sidebarViewModel: viewModel,
			sidebarPresentation: presentation,
			sidebarWidth: 320,
			browserRuntime: runtime,
			browserChromeViewModel: BrowserChromeViewModel(
				geometry: .init(sidebarWidth: 320),
				workItemScheduler: BrowserChromeViewModel.defaultWorkItemScheduler,
				sidebarPresentation: presentation
			),
			eventMonitoring: .live,
			tabLifecycleConfiguration: .init(activationDelay: 0),
			activationScheduler: BrowserChromeView.defaultActivationScheduler,
			timeProvider: BrowserChromeView.defaultTimeProvider
		)
		controller.loadViewIfNeeded()
		let window = makeWindow(size: CGSize(width: 900, height: 700))
		host(controller.view, in: window, size: CGSize(width: 900, height: 700))
		controller.view.layoutSubtreeIfNeeded()
		controller.viewDidAppear()

		runtime.fireOpenURLInTabEvent(
			.init(url: "https://cmdclick.example", activatesTab: false),
			for: browser
		)

		XCTAssertEqual(viewModel.tabs.count, 2)
		XCTAssertEqual(viewModel.selectedTabID, initialTabID)
		XCTAssertEqual(viewModel.tabs[1].currentURL, "https://cmdclick.example")
	}

	private func makeScopedPermissionSession(
		id: BrowserPermissionSessionID,
		browserID: UInt64,
		requestingOrigin: String = "https://request.example",
		topLevelOrigin: String = "https://top.example",
		promptKinds: BrowserPermissionKindSet
	) -> BrowserPermissionSession {
		BrowserPermissionSession(
			id: id,
			browserID: browserID,
			promptID: id + 100,
			frameIdentifier: "frame-\(id)",
			source: .permissionPrompt,
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
