import AppIntents
import AppKit
import BrowserActionBar
import BrowserCameraKit
import BrowserImport
import BrowserRuntime
import BrowserSidebar
import Carbon.HIToolbox
import CoreServices
import ModelKit
@testable import Navigator
import OverlayView
import UniformTypeIdentifiers
import Vendors
import XCTest

final class NavigatorKeyboardShortcutTests: XCTestCase {
	func testResolverMapsPrimaryCommandShortcuts() {
		XCTAssertEqual(
			NavigatorKeyboardShortcutResolver.resolveAction(
				for: UInt16(kVK_ANSI_N),
				modifiers: [.command],
				normalizedCharacter: "n",
				rawCharacter: "n"
			),
			.openNewWindow
		)
		XCTAssertEqual(
			NavigatorKeyboardShortcutResolver.resolveAction(
				for: UInt16(kVK_ANSI_L),
				modifiers: [.command],
				normalizedCharacter: "l",
				rawCharacter: "l"
			),
			.openLocation
		)
		XCTAssertEqual(
			NavigatorKeyboardShortcutResolver.resolveAction(
				for: UInt16(kVK_ANSI_T),
				modifiers: [.command],
				normalizedCharacter: "t",
				rawCharacter: "t"
			),
			.openNewTab
		)
		XCTAssertEqual(
			NavigatorKeyboardShortcutResolver.resolveAction(
				for: UInt16(kVK_ANSI_T),
				modifiers: [.command, .shift],
				normalizedCharacter: "t",
				rawCharacter: "t"
			),
			.reopenLastClosedTab
		)
		XCTAssertEqual(
			NavigatorKeyboardShortcutResolver.resolveAction(
				for: UInt16(kVK_ANSI_C),
				modifiers: [.command, .shift],
				normalizedCharacter: "c",
				rawCharacter: "c"
			),
			.copyCurrentTabURL
		)
		XCTAssertEqual(
			NavigatorKeyboardShortcutResolver.resolveAction(
				for: UInt16(kVK_ANSI_W),
				modifiers: [.command],
				normalizedCharacter: "w",
				rawCharacter: "w"
			),
			.closeCurrentTab
		)
		XCTAssertEqual(
			NavigatorKeyboardShortcutResolver.resolveAction(
				for: UInt16(kVK_ANSI_P),
				modifiers: [.command],
				normalizedCharacter: "p",
				rawCharacter: "p"
			),
			.togglePinSelectedTab
		)
		XCTAssertEqual(
			NavigatorKeyboardShortcutResolver.resolveAction(
				for: UInt16(kVK_ANSI_R),
				modifiers: [.command],
				normalizedCharacter: "r",
				rawCharacter: "r"
			),
			.reload
		)
		XCTAssertEqual(
			NavigatorKeyboardShortcutResolver.resolveAction(
				for: UInt16(kVK_ANSI_1),
				modifiers: [.command],
				normalizedCharacter: "1",
				rawCharacter: "1"
			),
			.selectTab(index: 0)
		)
		XCTAssertEqual(
			NavigatorKeyboardShortcutResolver.resolveAction(
				for: UInt16(kVK_ANSI_9),
				modifiers: [.command],
				normalizedCharacter: "9",
				rawCharacter: "9"
			),
			.selectTab(index: 8)
		)
	}

	func testResolverMapsCommandBracketsToHistoryNavigation() {
		XCTAssertEqual(
			NavigatorKeyboardShortcutResolver.resolveAction(
				for: UInt16(kVK_ANSI_LeftBracket),
				modifiers: [.command],
				normalizedCharacter: "[",
				rawCharacter: "["
			),
			.goBack
		)
		XCTAssertEqual(
			NavigatorKeyboardShortcutResolver.resolveAction(
				for: UInt16(kVK_ANSI_RightBracket),
				modifiers: [.command],
				normalizedCharacter: "]",
				rawCharacter: "]"
			),
			.goForward
		)
	}

	func testResolverKeepsShiftedBracketsForTabSelection() {
		XCTAssertEqual(
			NavigatorKeyboardShortcutResolver.resolveAction(
				for: UInt16(kVK_ANSI_LeftBracket),
				modifiers: [.command, .shift],
				normalizedCharacter: "[",
				rawCharacter: "{"
			),
			.selectPreviousTab
		)
		XCTAssertEqual(
			NavigatorKeyboardShortcutResolver.resolveAction(
				for: UInt16(kVK_ANSI_RightBracket),
				modifiers: [.command, .shift],
				normalizedCharacter: "]",
				rawCharacter: "}"
			),
			.selectNextTab
		)
	}

	func testResolverFallsBackToBracketCharacters() {
		XCTAssertEqual(
			NavigatorKeyboardShortcutResolver.resolveAction(
				for: UInt16.max,
				modifiers: [.command],
				normalizedCharacter: nil,
				rawCharacter: "["
			),
			.goBack
		)
		XCTAssertEqual(
			NavigatorKeyboardShortcutResolver.resolveAction(
				for: UInt16.max,
				modifiers: [.command],
				normalizedCharacter: nil,
				rawCharacter: "]"
			),
			.goForward
		)
		XCTAssertEqual(
			NavigatorKeyboardShortcutResolver.resolveAction(
				for: UInt16.max,
				modifiers: [.command],
				normalizedCharacter: nil,
				rawCharacter: "1"
			),
			.selectTab(index: 0)
		)
	}

	func testResolverRejectsUnsupportedModifierCombinations() {
		XCTAssertNil(
			NavigatorKeyboardShortcutResolver.resolveAction(
				for: UInt16(kVK_ANSI_LeftBracket),
				modifiers: [.command, .option],
				normalizedCharacter: "[",
				rawCharacter: "["
			)
		)
		XCTAssertNil(
			NavigatorKeyboardShortcutResolver.resolveAction(
				for: UInt16(kVK_ANSI_RightBracket),
				modifiers: [.command, .control],
				normalizedCharacter: "]",
				rawCharacter: "]"
			)
		)
	}

	func testHandleShortcutEventTogglesPinForSelectedTab() throws {
		let (delegate, viewModel) = makeAppDelegate(
			hooks: NavigatorAppDelegateHooks(
				makePrimaryContentViewController: { _, navigatorAppViewModel in
					TestRootViewController(navigatorAppViewModel: navigatorAppViewModel)
				}
			)
		)
		addTeardownBlock {
			delegate.primaryWindow?.orderOut(nil)
		}
		delegate.createPrimaryWindowIfNeeded()
		viewModel.sidebarViewModel.openNewTab(with: "https://swift.org")

		let togglePinEvent = try XCTUnwrap(
			makeCoverageKeyDownEvent(
				keyCode: UInt16(kVK_ANSI_P),
				characters: "p",
				charactersIgnoringModifiers: "p",
				modifiers: [.command],
				timestamp: 30
			)
		)

		XCTAssertTrue(delegate.handleShortcutEvent(togglePinEvent))
		XCTAssertTrue(viewModel.sidebarViewModel.tabs[0].isPinned)
		XCTAssertEqual(viewModel.sidebarViewModel.selectedTabID, viewModel.sidebarViewModel.tabs[0].id)
		XCTAssertNotNil(viewModel.toast)
		XCTAssertEqual(
			String(localized: viewModel.toastTitle),
			String(localized: LocalizedStringResource.navigatorToastPinnedTabTitle)
		)

		let unpinEvent = try XCTUnwrap(
			makeCoverageKeyDownEvent(
				keyCode: UInt16(kVK_ANSI_P),
				characters: "p",
				charactersIgnoringModifiers: "p",
				modifiers: [.command],
				timestamp: 31
			)
		)

		XCTAssertTrue(delegate.handleShortcutEvent(unpinEvent))
		XCTAssertFalse(viewModel.sidebarViewModel.tabs[0].isPinned)
		XCTAssertEqual(viewModel.sidebarViewModel.selectedTabID, viewModel.sidebarViewModel.tabs[0].id)
		XCTAssertNotNil(viewModel.toast)
		XCTAssertEqual(
			String(localized: viewModel.toastTitle),
			String(localized: LocalizedStringResource.navigatorToastUnpinnedTabTitle)
		)
	}

	@MainActor
	func testHandlerPerformsEveryShortcutAction() {
		var performedActions = [NavigatorKeyboardShortcutAction]()
		let handler = NavigatorKeyboardShortcutHandler(
			openNewWindow: { performedActions.append(.openNewWindow) },
			openLocation: { performedActions.append(.openLocation) },
			openNewTab: { performedActions.append(.openNewTab) },
			reopenLastClosedTab: { performedActions.append(.reopenLastClosedTab) },
			closeCurrentTab: { performedActions.append(.closeCurrentTab) },
			togglePinSelectedTab: { performedActions.append(.togglePinSelectedTab) },
			copyCurrentTabURL: { performedActions.append(.copyCurrentTabURL) },
			reload: { performedActions.append(.reload) },
			goBack: { performedActions.append(.goBack) },
			goForward: { performedActions.append(.goForward) },
			selectNextTab: { performedActions.append(.selectNextTab) },
			selectPreviousTab: { performedActions.append(.selectPreviousTab) },
			selectTabAtIndex: { performedActions.append(.selectTab(index: $0)) }
		)

		let expectedActions: [NavigatorKeyboardShortcutAction] = [
			.openNewWindow,
			.openLocation,
			.openNewTab,
			.reopenLastClosedTab,
			.closeCurrentTab,
			.togglePinSelectedTab,
			.copyCurrentTabURL,
			.reload,
			.goBack,
			.goForward,
			.selectNextTab,
			.selectPreviousTab,
			.selectTab(index: 0),
			.selectTab(index: 8),
		]

		for action in expectedActions {
			handler.perform(action)
		}

		XCTAssertEqual(performedActions, expectedActions)
	}

	func testActivationDedupesRepeatedShortcutInsideWindow() {
		var activation = NavigatorKeyboardShortcutActivation()

		XCTAssertTrue(activation.shouldHandle(for: .goBack, at: 1.0))
		XCTAssertFalse(activation.shouldHandle(for: .goBack, at: 1.05))
	}

	func testActivationAllowsDifferentActionsAndLaterRepeats() {
		var activation = NavigatorKeyboardShortcutActivation()

		XCTAssertTrue(activation.shouldHandle(for: .goBack, at: 1.0))
		XCTAssertTrue(activation.shouldHandle(for: .goForward, at: 1.02))
		XCTAssertTrue(activation.shouldHandle(for: .goForward, at: 1.12))
	}

	func testActivationSuppressesRepeatedSameActionBurstWhileKeyRepeats() {
		var activation = NavigatorKeyboardShortcutActivation()

		XCTAssertTrue(activation.shouldHandle(for: .openLocation, at: 1.00))
		XCTAssertFalse(activation.shouldHandle(for: .openLocation, at: 1.05))
		XCTAssertFalse(activation.shouldHandle(for: .openLocation, at: 1.10))
		XCTAssertFalse(activation.shouldHandle(for: .openLocation, at: 1.15))
		XCTAssertTrue(activation.shouldHandle(for: .openLocation, at: 1.24))
	}

	func testActivationAllowsModeSwitchActionsBackToBack() {
		var activation = NavigatorKeyboardShortcutActivation()

		XCTAssertTrue(activation.shouldHandle(for: .openNewTab, at: 2.00))
		XCTAssertTrue(activation.shouldHandle(for: .openLocation, at: 2.04))
	}
}

final class NavigatorLaunchEnvironmentTests: XCTestCase {
	func testIsRunningTestsReturnsTrueWhenXCTestConfigurationIsPresent() {
		XCTAssertTrue(
			NavigatorLaunchEnvironment.isRunningTests(
				environment: ["XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"]
			)
		)
	}

	func testIsRunningTestsReturnsFalseWhenNoXCTestEnvironmentIsPresent() {
		XCTAssertFalse(
			NavigatorLaunchEnvironment.isRunningTests(
				environment: ["PATH": "/usr/bin"]
			)
		)
	}
}

final class NavigatorAppRuntimeCoverageTests: XCTestCase {
	func testRunExitsWhenArgumentVectorIsMissing() {
		var exitCode: Int32?

		NavigatorAppRuntime.run(
			hooks: NavigatorAppRuntimeHooks(
				arguments: ["Navigator"],
				unsafeArgv: nil,
				exitProcess: { code in exitCode = code }
			)
		)

		XCTAssertEqual(exitCode, 0)
	}

	func testRunExitsWithSubprocessCodeWhenCEFSubprocessReturnsSuccess() {
		var receivedPointer: UnsafeRawPointer?
		var exitCode: Int32?

		NavigatorAppRuntime.run(
			hooks: NavigatorAppRuntimeHooks(
				argc: 2,
				arguments: ["Navigator", "--type=renderer"],
				maybeRunSubprocess: { argc, argv in
					XCTAssertEqual(argc, 2)
					receivedPointer = argv
					return 7
				},
				exitProcess: { code in exitCode = code }
			)
		)

		XCTAssertNotNil(receivedPointer)
		XCTAssertEqual(exitCode, 7)
	}

	func testRunExitsZeroWhenCEFSubprocessRequestsFallback() {
		var exitCode: Int32?

		NavigatorAppRuntime.run(
			hooks: NavigatorAppRuntimeHooks(
				arguments: ["Navigator", "--type=gpu-process"],
				maybeRunSubprocess: { _, _ in -1 },
				exitProcess: { code in exitCode = code }
			)
		)

		XCTAssertEqual(exitCode, 0)
	}

	func testRunBootstrapsDelegateAndActivatesApplicationWhenNotRunningTests() {
		let expectedDelegate = CoverageTestApplicationDelegate()
		var capturedDelegate: NSApplicationDelegate?
		var didSetActivationPolicy = false
		var didActivate = false
		var didRunApplication = false
		var subprocessCallCount = 0

		NavigatorAppRuntime.run(
			hooks: NavigatorAppRuntimeHooks(
				arguments: ["Navigator"],
				maybeRunSubprocess: { _, _ in
					subprocessCallCount += 1
					return -1
				},
				makeDelegate: { expectedDelegate },
				setDelegate: { capturedDelegate = $0 },
				setActivationPolicyRegular: { didSetActivationPolicy = true },
				activateIgnoringOtherApps: { didActivate = true },
				runApplication: { didRunApplication = true },
				isRunningTests: { false }
			)
		)

		XCTAssertEqual(subprocessCallCount, 1)
		XCTAssertTrue(capturedDelegate === expectedDelegate)
		XCTAssertTrue(didSetActivationPolicy)
		XCTAssertTrue(didActivate)
		XCTAssertTrue(didRunApplication)
	}

	func testRunSkipsActivationWhenRunningTests() {
		var didSetActivationPolicy = false
		var didActivate = false
		var didRunApplication = false

		NavigatorAppRuntime.run(
			hooks: NavigatorAppRuntimeHooks(
				arguments: ["Navigator"],
				maybeRunSubprocess: { _, _ in -1 },
				setActivationPolicyRegular: { didSetActivationPolicy = true },
				activateIgnoringOtherApps: { didActivate = true },
				runApplication: { didRunApplication = true },
				isRunningTests: { true }
			)
		)

		XCTAssertFalse(didSetActivationPolicy)
		XCTAssertFalse(didActivate)
		XCTAssertTrue(didRunApplication)
	}

	func testNavigatorAppMainInvokesRuntimeRunner() {
		let originalRunner = NavigatorAppMain.runRuntime
		var didRunRuntime = false
		NavigatorAppMain.runRuntime = {
			didRunRuntime = true
		}
		defer {
			NavigatorAppMain.runRuntime = originalRunner
		}

		NavigatorApp.main()

		XCTAssertTrue(didRunRuntime)
	}
}

@MainActor
final class NavigatorAppDelegateCoverageTests: XCTestCase {
	override func setUp() {
		super.setUp()
		installCoverageTestApplicationDelegate()
	}

	override func tearDown() {
		closeAllCoverageTestWindows()
		super.tearDown()
		NSApp.mainMenu = nil
	}

	func testApplicationDidFinishLaunchingSkipsBootstrapDuringTests() {
		let delegate = NavigatorAppDelegate(
			navigatorAppViewModel: AppViewModel(),
			hooks: NavigatorAppDelegateHooks(
				isRunningTests: { true }
			)
		)

		delegate.applicationDidFinishLaunching(Notification(name: .init("NavigatorTests")))

		XCTAssertFalse(delegate.hasStartedBrowserRuntime)
		XCTAssertNil(delegate.primaryWindow)
	}

	func testApplicationDidFinishLaunchingBootstrapsAppAndCreatesPrimaryWindow() {
		var startCount = 0
		let localMonitor = NSObject()
		let globalMonitor = NSObject()
		let observer = NSObject()
		let existingWindow = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
			styleMask: [.titled, .closable],
			backing: .buffered,
			defer: false
		)
		existingWindow.contentViewController = NSViewController()
		existingWindow.orderFront(nil)

		let delegate = NavigatorAppDelegate(
			navigatorAppViewModel: AppViewModel(),
			hooks: NavigatorAppDelegateHooks(
				isRunningTests: { false },
				startBrowserRuntime: { startCount += 1 },
				makePrimaryContentViewController: { _, _ in NSViewController() },
				addLocalKeyDownMonitor: { _ in localMonitor },
				addGlobalKeyDownMonitor: { _ in globalMonitor },
				addSystemAppearanceObserver: { _ in observer }
			)
		)

		delegate.applicationDidFinishLaunching(Notification(name: .init("NavigatorTests")))

		XCTAssertEqual(startCount, 1)
		XCTAssertTrue(delegate.hasStartedBrowserRuntime)
		XCTAssertTrue((delegate.localKeyboardShortcutMonitor as AnyObject?) === localMonitor)
		XCTAssertTrue((delegate.globalKeyboardShortcutMonitor as AnyObject?) === globalMonitor)
		XCTAssertTrue((delegate.systemAppearanceObserver as AnyObject?) === observer)
		XCTAssertNotNil(delegate.primaryWindow)
		XCTAssertEqual(NSApp.mainMenu?.items.count, 3)
		XCTAssertFalse(existingWindow.isRestorable)
	}

	func testInstallMainMenuBuildsStableEditSubmenuOwnership() throws {
		let delegate = NavigatorAppDelegate(
			navigatorAppViewModel: AppViewModel(),
			hooks: NavigatorAppDelegateHooks(isRunningTests: { false })
		)

		delegate.installMainMenu()

		let mainMenu = try XCTUnwrap(NSApp.mainMenu)
		let editMenuItem = try XCTUnwrap(mainMenu.item(withTitle: String(localized: .navigatorMenuEditTitle)))
		let editMenu = try XCTUnwrap(editMenuItem.submenu)
		let submenuTitles = [
			String(localized: .navigatorMenuEditFindTitle),
			String(localized: .navigatorMenuEditSpellingTitle),
			String(localized: .navigatorMenuEditSubstitutionsTitle),
			String(localized: .navigatorMenuEditTransformationsTitle),
			String(localized: .navigatorMenuEditSpeechTitle),
			String(localized: .navigatorMenuEditFontTitle),
			String(localized: .navigatorMenuEditWritingDirectionTitle),
			String(localized: .navigatorMenuEditLayoutOrientationTitle),
		]

		for submenuTitle in submenuTitles {
			let item = try XCTUnwrap(editMenu.item(withTitle: submenuTitle))
			let submenu = try XCTUnwrap(item.submenu)
			XCTAssertTrue(submenu.supermenu === editMenu)
		}

		let fontMenu = try XCTUnwrap(editMenu.item(withTitle: String(localized: .navigatorMenuEditFontTitle))?.submenu)
		XCTAssertNotNil(fontMenu.item(withTitle: String(localized: .navigatorMenuEditFontBold)))
		XCTAssertNotNil(fontMenu.item(withTitle: String(localized: .navigatorMenuEditFontItalic)))
	}

	func testInstallMainMenuOmitsCommandNumberTabItemsFromFileMenu() {
		let delegate = NavigatorAppDelegate(
			navigatorAppViewModel: AppViewModel(),
			hooks: NavigatorAppDelegateHooks(isRunningTests: { false })
		)

		delegate.installMainMenu()

		guard let mainMenu = NSApp.mainMenu else {
			return XCTFail("Expected main menu to be installed")
		}
		guard let fileMenu = mainMenu.item(withTitle: "File")?.submenu else {
			return XCTFail("Expected File menu to be installed")
		}
		guard let newWindowItem = fileMenu.item(withTitle: String(localized: .navigatorFileMenuNewWindow)) else {
			return XCTFail("Expected New Window item to remain in the File menu")
		}

		XCTAssertEqual(newWindowItem.keyEquivalent, "n")
		XCTAssertEqual(newWindowItem.keyEquivalentModifierMask, [.command])
		XCTAssertNil(fileMenu.item(withTitle: String(localized: .navigatorFileMenuSelectTab1)))
		XCTAssertNil(fileMenu.item(withTitle: String(localized: .navigatorFileMenuSelectTab9)))
	}

	func testRestoredWindowFrameUsesBestMatchingSavedScreenWhenWindowIsNotAttached() {
		let delegate = NavigatorAppDelegate(
			navigatorAppViewModel: AppViewModel(),
			hooks: NavigatorAppDelegateHooks(isRunningTests: { false })
		)
		let saved = NavigatorWindowFrame(
			origin: NSPoint(x: 1500, y: 120),
			size: NSSize(width: 900, height: 700)
		)
		let primaryScreen = NSRect(x: 0, y: 0, width: 1440, height: 900)
		let externalScreen = NSRect(x: 1440, y: 0, width: 1728, height: 1117)

		let restoredFrame = delegate.restoredWindowFrame(
			for: saved,
			attachedScreenVisibleFrame: nil,
			mainScreenVisibleFrame: primaryScreen,
			screenVisibleFrames: [primaryScreen, externalScreen],
			fallbackFrame: .zero
		)

		XCTAssertEqual(restoredFrame.origin.x, 1500)
		XCTAssertEqual(restoredFrame.origin.y, 120)
		XCTAssertEqual(restoredFrame.size.width, 900)
		XCTAssertEqual(restoredFrame.size.height, 700)
	}

	func testResolvedVisibleFramePrefersBestIntersectionBeforeMainScreen() {
		let preferredFrame = NSRect(x: 1500, y: 120, width: 900, height: 700)
		let primaryScreen = NSRect(x: 0, y: 0, width: 1440, height: 900)
		let externalScreen = NSRect(x: 1440, y: 0, width: 1728, height: 1117)

		let resolvedFrame = NavigatorAppDelegate.resolvedVisibleFrame(
			attachedScreenVisibleFrame: nil,
			mainScreenVisibleFrame: primaryScreen,
			screenVisibleFrames: [primaryScreen, externalScreen],
			preferredFrame: preferredFrame,
			fallbackFrame: .zero
		)

		XCTAssertEqual(resolvedFrame, externalScreen)
	}

	func testOpenNewWindowSharesTabsButKeepsSelectionPerWindow() throws {
		let primaryViewModel = AppViewModel()
		var createdViewModels = [AppViewModel]()
		let delegate = NavigatorAppDelegate(
			navigatorAppViewModel: primaryViewModel,
			hooks: NavigatorAppDelegateHooks(
				isRunningTests: { false },
				makePrimaryContentViewController: { _, navigatorAppViewModel in
					createdViewModels.append(navigatorAppViewModel)
					return TestRootViewController(navigatorAppViewModel: navigatorAppViewModel)
				}
			)
		)
		addTeardownBlock {
			NSApp.windows.forEach { $0.orderOut(nil) }
		}

		delegate.createPrimaryWindowIfNeeded()
		primaryViewModel.sidebarViewModel.openNewTab(with: "https://primary.example")
		primaryViewModel.sidebarViewModel.openNewTab(with: "https://secondary.example")
		primaryViewModel.sidebarViewModel.selectTab(id: primaryViewModel.sidebarViewModel.tabs[1].id)
		XCTAssertEqual(createdViewModels.count, 1)
		XCTAssertTrue(createdViewModels[0] === primaryViewModel)

		delegate.openNewWindow(nil)

		XCTAssertEqual(createdViewModels.count, 2)
		let secondaryViewModel = createdViewModels[1]
		XCTAssertFalse(secondaryViewModel === primaryViewModel)
		XCTAssertEqual(
			secondaryViewModel.sidebarViewModel.tabs.map(\.currentURL),
			primaryViewModel.sidebarViewModel.tabs.map(\.currentURL)
		)
		let secondaryWindow = try XCTUnwrap(
			NSApp.windows.first { window in
				guard
					let rootViewController = window.contentViewController as? TestRootViewController
				else {
					return false
				}
				return rootViewController.navigatorAppViewModel === secondaryViewModel
			}
		)
		secondaryWindow.makeKeyAndOrderFront(nil)
		let secondaryRootViewController = try XCTUnwrap(
			secondaryWindow.contentViewController as? TestRootViewController
		)
		XCTAssertTrue(secondaryRootViewController.navigatorAppViewModel === secondaryViewModel)
		XCTAssertEqual(
			secondaryViewModel.sidebarViewModel.selectedTabID,
			primaryViewModel.sidebarViewModel.selectedTabID
		)

		delegate.keyboardShortcutHandler.perform(.selectTab(index: 0))

		XCTAssertEqual(
			secondaryViewModel.sidebarViewModel.selectedTabCurrentURL,
			"https://navigator.zip"
		)
		XCTAssertEqual(
			primaryViewModel.sidebarViewModel.selectedTabCurrentURL,
			"https://primary.example"
		)
		XCTAssertEqual(
			secondaryViewModel.sidebarViewModel.tabs.map(\.currentURL),
			primaryViewModel.sidebarViewModel.tabs.map(\.currentURL)
		)
	}

	func testOpenNewWindowUsesActiveWindowSelectionForNewWindow() throws {
		let primaryViewModel = AppViewModel()
		var createdViewModels = [AppViewModel]()
		let delegate = NavigatorAppDelegate(
			navigatorAppViewModel: primaryViewModel,
			hooks: NavigatorAppDelegateHooks(
				isRunningTests: { false },
				makePrimaryContentViewController: { _, navigatorAppViewModel in
					createdViewModels.append(navigatorAppViewModel)
					return TestRootViewController(navigatorAppViewModel: navigatorAppViewModel)
				}
			)
		)
		addTeardownBlock {
			NSApp.windows.forEach { $0.orderOut(nil) }
		}

		delegate.createPrimaryWindowIfNeeded()
		primaryViewModel.sidebarViewModel.openNewTab(with: "https://swift.org")
		primaryViewModel.sidebarViewModel.openNewTab(with: "https://developer.apple.com")
		primaryViewModel.sidebarViewModel.selectTab(id: primaryViewModel.sidebarViewModel.tabs[0].id)

		delegate.openNewWindow(nil)
		let secondaryViewModel = try XCTUnwrap(createdViewModels.last)
		let secondaryWindow = try XCTUnwrap(
			NSApp.windows.first { window in
				(window.contentViewController as? TestRootViewController)?.navigatorAppViewModel === secondaryViewModel
			}
		)
		secondaryWindow.makeKeyAndOrderFront(nil)
		secondaryViewModel.sidebarViewModel.selectTab(id: secondaryViewModel.sidebarViewModel.tabs[2].id)

		delegate.openNewWindow(nil)

		XCTAssertEqual(createdViewModels.count, 3)
		let tertiaryViewModel = createdViewModels[2]
		XCTAssertEqual(
			tertiaryViewModel.sidebarViewModel.selectedTabCurrentURL,
			"https://developer.apple.com"
		)
		XCTAssertEqual(
			tertiaryViewModel.sidebarViewModel.tabs.map(\.currentURL),
			secondaryViewModel.sidebarViewModel.tabs.map(\.currentURL)
		)
		XCTAssertEqual(primaryViewModel.sidebarViewModel.selectedTabCurrentURL, "https://navigator.zip")
	}

	func testOpenNewTabShortcutTargetsKeyWindowActionBarOnly() throws {
		let primaryViewModel = AppViewModel()
		var createdViewModels = [AppViewModel]()
		let delegate = NavigatorAppDelegate(
			navigatorAppViewModel: primaryViewModel,
			hooks: NavigatorAppDelegateHooks(
				isRunningTests: { false },
				makePrimaryContentViewController: { _, navigatorAppViewModel in
					createdViewModels.append(navigatorAppViewModel)
					return TestRootViewController(navigatorAppViewModel: navigatorAppViewModel)
				}
			)
		)
		addTeardownBlock {
			NSApp.windows.forEach { $0.orderOut(nil) }
		}

		delegate.createPrimaryWindowIfNeeded()
		delegate.openNewWindow(nil)
		let secondaryViewModel = try XCTUnwrap(createdViewModels.last)
		let secondaryWindow = try XCTUnwrap(
			NSApp.windows.first { window in
				(window.contentViewController as? TestRootViewController)?.navigatorAppViewModel === secondaryViewModel
			}
		)
		secondaryWindow.makeKeyAndOrderFront(nil)

		delegate.keyboardShortcutHandler.perform(.openNewTab)

		XCTAssertEqual(secondaryViewModel.browserActionBarViewModel.mode, .newTab)
		XCTAssertTrue(secondaryViewModel.browserActionBarViewModel.isPresented)
		XCTAssertFalse(primaryViewModel.browserActionBarViewModel.isPresented)
	}

	func testWindowDelegatePersistsPrimaryWindowFrameOnMoveResizeAndClose() throws {
		let delegate = NavigatorAppDelegate(
			navigatorAppViewModel: AppViewModel(),
			hooks: NavigatorAppDelegateHooks(
				isRunningTests: { false },
				makePrimaryContentViewController: { _, _ in NSViewController() }
			)
		)
		addTeardownBlock {
			delegate.primaryWindow?.orderOut(nil)
		}
		delegate.createPrimaryWindowIfNeeded()
		let window = try XCTUnwrap(delegate.primaryWindow)
		window.setFrame(NSRect(x: 320, y: 180, width: 980, height: 760), display: false)
		let settledFrame = window.frame

		delegate.windowDidMove(Notification(name: NSWindow.didMoveNotification, object: window))
		delegate.windowDidResize(Notification(name: NSWindow.didResizeNotification, object: window))
		delegate.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))

		@Shared(.navigatorWindowSize) var navigatorWindowSize = NavigatorWindowFrame()
		let persisted = $navigatorWindowSize.withLock { $0 }
		XCTAssertEqual(persisted.origin.x, settledFrame.origin.x)
		XCTAssertEqual(persisted.origin.y, settledFrame.origin.y)
		XCTAssertEqual(persisted.size.width, settledFrame.size.width)
		XCTAssertEqual(persisted.size.height, settledFrame.size.height)
	}

	func testPrimaryWindowFramePersistsAcrossColdLaunches() throws {
		clearNavigatorWindowPersistenceState()
		let targetVisibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
		let targetFrame = NSRect(
			x: targetVisibleFrame.minX + 32,
			y: targetVisibleFrame.minY + 32,
			width: min(980, targetVisibleFrame.width - 64),
			height: min(760, targetVisibleFrame.height - 64)
		)
		try persistNavigatorWindowFrameState(targetFrame)

		let secondDelegate = NavigatorAppDelegate(
			navigatorAppViewModel: AppViewModel(),
			hooks: NavigatorAppDelegateHooks(
				isRunningTests: { false },
				makePrimaryContentViewController: { _, _ in NSViewController() }
			)
		)
		addTeardownBlock {
			secondDelegate.primaryWindow?.orderOut(nil)
		}
		secondDelegate.createPrimaryWindowIfNeeded()
		let restoredWindow = try XCTUnwrap(secondDelegate.primaryWindow)

		XCTAssertEqual(restoredWindow.frame.origin.x, targetFrame.origin.x)
		XCTAssertEqual(restoredWindow.frame.origin.y, targetFrame.origin.y)
		XCTAssertEqual(restoredWindow.frame.size.width, targetFrame.size.width)
		XCTAssertEqual(restoredWindow.frame.size.height, targetFrame.size.height)
	}

	func testTerminationLifecycleRemovesResourcesAndShutsDownRuntime() {
		var removedMonitors = [AnyObject]()
		var removedObserver: NSObjectProtocol?
		var shutdownCount = 0
		let localMonitor = NSObject()
		let globalMonitor = NSObject()
		let observer = NSObject()
		let delegate = NavigatorAppDelegate(
			navigatorAppViewModel: AppViewModel(),
			hooks: NavigatorAppDelegateHooks(
				isRunningTests: { false },
				startBrowserRuntime: {},
				shutdownBrowserRuntime: { shutdownCount += 1 },
				makePrimaryContentViewController: { _, _ in NSViewController() },
				addLocalKeyDownMonitor: { _ in localMonitor },
				addGlobalKeyDownMonitor: { _ in globalMonitor },
				removeEventMonitor: { removedMonitors.append($0 as AnyObject) },
				addSystemAppearanceObserver: { _ in observer },
				removeSystemAppearanceObserver: { removedObserver = $0 }
			)
		)

		delegate.applicationDidFinishLaunching(Notification(name: .init("NavigatorTests")))
		XCTAssertTrue(delegate.applicationSupportsSecureRestorableState(NSApp))
		XCTAssertFalse(delegate.application(NSApp, shouldSaveApplicationState: NSCoder()))
		XCTAssertFalse(delegate.application(NSApp, shouldRestoreApplicationState: NSCoder()))
		XCTAssertTrue(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApp))
		XCTAssertEqual(delegate.applicationShouldTerminate(NSApp), .terminateNow)
		XCTAssertEqual(shutdownCount, 1)

		delegate.applicationDidFinishLaunching(Notification(name: .init("NavigatorTests")))
		delegate.applicationWillTerminate(Notification(name: .init("NavigatorTests")))

		XCTAssertEqual(removedMonitors.count, 2)
		XCTAssertTrue(removedMonitors.contains { $0 === localMonitor })
		XCTAssertTrue(removedMonitors.contains { $0 === globalMonitor })
		XCTAssertTrue(removedObserver === observer)
		XCTAssertNil(delegate.localKeyboardShortcutMonitor)
		XCTAssertNil(delegate.globalKeyboardShortcutMonitor)
		XCTAssertNil(delegate.systemAppearanceObserver)
		XCTAssertEqual(shutdownCount, 2)
	}

	func testIncomingURLsActionsAndSettingsWindowUpdateState() throws {
		let viewModel = AppViewModel()
		let delegate = NavigatorAppDelegate(
			navigatorAppViewModel: viewModel,
			hooks: NavigatorAppDelegateHooks(
				isRunningTests: { false },
				makePrimaryContentViewController: { _, _ in NSViewController() }
			)
		)

		XCTAssertFalse(delegate.handleIncomingURLs([]))
		XCTAssertTrue(try delegate.handleIncomingURLs([XCTUnwrap(URL(string: "https://navigator.example"))]))
		XCTAssertEqual(viewModel.sidebarViewModel.selectedTabCurrentURL, "https://navigator.example")
		XCTAssertEqual(
			viewModel.sidebarViewModel.tabs.map(\.currentURL),
			["https://navigator.zip", "https://navigator.example"]
		)

		delegate.application(
			NSApp,
			openFiles: ["/tmp/navigator-coverage.html"]
		)
		XCTAssertEqual(
			viewModel.sidebarViewModel.tabs.last?.currentURL,
			URL(fileURLWithPath: "/tmp/navigator-coverage.html").absoluteString
		)
		XCTAssertEqual(viewModel.sidebarViewModel.tabs.count, 3)

		delegate.openLocationBar(nil)
		XCTAssertTrue(viewModel.browserActionBarViewModel.isPresented)
		viewModel.browserActionBarViewModel.dismiss()

		delegate.openNewTabBar(nil)
		XCTAssertTrue(viewModel.browserActionBarViewModel.isPresented)

		let previousTabCount = viewModel.sidebarViewModel.tabs.count
		delegate.closeCurrentTab(nil)
		XCTAssertEqual(viewModel.sidebarViewModel.tabs.count, previousTabCount - 1)
		delegate.reopenLastClosedTab(nil)
		XCTAssertEqual(viewModel.sidebarViewModel.tabs.count, previousTabCount)
		XCTAssertEqual(
			viewModel.sidebarViewModel.selectedTabCurrentURL,
			URL(fileURLWithPath: "/tmp/navigator-coverage.html").absoluteString
		)

		delegate.showSettingsWindow(nil)
		XCTAssertNotNil(delegate.settingsWindowController)
		delegate.toggleSettingsWindow()
		XCTAssertFalse(delegate.settingsWindowController?.window?.isVisible ?? true)
	}

	func testApplicationOpenEntryPointRoutesURLs() throws {
		let viewModel = AppViewModel()
		let delegate = NavigatorAppDelegate(
			navigatorAppViewModel: viewModel,
			hooks: NavigatorAppDelegateHooks(
				isRunningTests: { false },
				makePrimaryContentViewController: { _, _ in NSViewController() }
			)
		)

		try delegate.application(NSApp, open: [XCTUnwrap(URL(string: "https://open-entry.example"))])
		delegate.application(NSApp, openFiles: [])

		XCTAssertEqual(viewModel.sidebarViewModel.selectedTabCurrentURL, "https://open-entry.example")
		XCTAssertEqual(
			viewModel.sidebarViewModel.tabs.map(\.currentURL),
			["https://navigator.zip", "https://open-entry.example"]
		)
	}

	func testKeyboardShortcutHandlingAndWindowPersistenceHelpers() throws {
		let viewModel = AppViewModel()
		let delegate = NavigatorAppDelegate(
			navigatorAppViewModel: viewModel,
			hooks: NavigatorAppDelegateHooks(
				isRunningTests: { false },
				makePrimaryContentViewController: { _, _ in NSViewController() }
			)
		)

		delegate.createPrimaryWindowIfNeeded()
		let primaryWindow = try XCTUnwrap(delegate.primaryWindow)
		XCTAssertFalse(primaryWindow.isRestorable)
		XCTAssertEqual(primaryWindow.minSize.width, NavigatorBrowserWindowSizing.minimumFrameWidth)
		XCTAssertEqual(primaryWindow.minSize.height, NavigatorBrowserWindowSizing.minimumFrameHeight)

		let unsupportedEvent = try XCTUnwrap(
			makeCoverageKeyDownEvent(
				keyCode: UInt16(kVK_ANSI_X),
				characters: "x",
				charactersIgnoringModifiers: "x",
				modifiers: [.command]
			)
		)
		XCTAssertFalse(delegate.handleShortcutEvent(unsupportedEvent))

		let openLocationEvent = try XCTUnwrap(
			makeCoverageKeyDownEvent(
				keyCode: UInt16(kVK_ANSI_L),
				characters: "l",
				charactersIgnoringModifiers: "l",
				modifiers: [.command],
				timestamp: 10
			)
		)
		XCTAssertTrue(delegate.handleShortcutEvent(openLocationEvent))
		XCTAssertTrue(viewModel.browserActionBarViewModel.isPresented)
		XCTAssertTrue(delegate.handleShortcutEvent(openLocationEvent))

		delegate.showSettingsWindow(nil)
		delegate.settingsWindowController?.window?.makeKeyAndOrderFront(nil)
		let closeEvent = try XCTUnwrap(
			makeCoverageKeyDownEvent(
				keyCode: UInt16(kVK_ANSI_W),
				characters: "w",
				charactersIgnoringModifiers: "w",
				modifiers: [.command],
				timestamp: 20
			)
		)
		_ = delegate.handleShortcutEvent(closeEvent)

		viewModel.sidebarViewModel.openNewTab(with: "https://reopen.example")
		viewModel.sidebarViewModel.closeSelectedTab()
		let reopenEvent = try XCTUnwrap(
			makeCoverageKeyDownEvent(
				keyCode: UInt16(kVK_ANSI_T),
				characters: "t",
				charactersIgnoringModifiers: "t",
				modifiers: [.command, .shift],
				timestamp: 21
			)
		)
		XCTAssertTrue(delegate.handleShortcutEvent(reopenEvent))
		XCTAssertEqual(viewModel.sidebarViewModel.selectedTabCurrentURL, "https://reopen.example")
		let copyCurrentTabURLEvent = try XCTUnwrap(
			makeCoverageKeyDownEvent(
				keyCode: UInt16(kVK_ANSI_C),
				characters: "C",
				charactersIgnoringModifiers: "c",
				modifiers: [.command, .shift],
				timestamp: 22
			)
		)
		XCTAssertTrue(delegate.handleShortcutEvent(copyCurrentTabURLEvent))
		XCTAssertEqual(
			NSPasteboard.general.string(forType: .string),
			"https://reopen.example"
		)
		XCTAssertNotNil(viewModel.toast)
		XCTAssertEqual(
			String(localized: viewModel.toastTitle),
			String(localized: LocalizedStringResource.navigatorToastCopyCurrentTabURLTitle)
		)

		let backgroundAction = expectation(description: "background action invoked on main queue")
		DispatchQueue.global().async {
			delegate.invokeKeyboardShortcutAction {
				backgroundAction.fulfill()
			}
		}
		wait(for: [backgroundAction], timeout: 1)

		delegate.keyboardShortcutHandler.perform(.reload)
		delegate.keyboardShortcutHandler.perform(.goBack)
		delegate.keyboardShortcutHandler.perform(.goForward)
		delegate.keyboardShortcutHandler.perform(.selectNextTab)
		delegate.keyboardShortcutHandler.perform(.selectPreviousTab)
		delegate.keyboardShortcutHandler.perform(.selectTab(index: 0))
		delegate.keyboardShortcutHandler.perform(.reopenLastClosedTab)

		let frameWindow = NSWindow(
			contentRect: NSRect(x: -100, y: -50, width: 120, height: 100),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		delegate.saveWindowFrame(for: frameWindow)
		let restoreWindow = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		delegate.restoreWindowState(for: restoreWindow)
		XCTAssertGreaterThanOrEqual(restoreWindow.frame.width, NavigatorBrowserWindowSizing.minimumFrameWidth)
		XCTAssertGreaterThanOrEqual(restoreWindow.frame.height, NavigatorBrowserWindowSizing.minimumFrameHeight)
	}

	func testBrowserWindowSizingEnforcesMinimumWidthDuringSaveAndConfigure() {
		let delegate = NavigatorAppDelegate(
			navigatorAppViewModel: AppViewModel(),
			hooks: NavigatorAppDelegateHooks(
				isRunningTests: { false },
				makePrimaryContentViewController: { _, _ in NSViewController() }
			)
		)

		let smallWindow = NSWindow(
			contentRect: NSRect(x: 20, y: 30, width: 120, height: 80),
			styleMask: [.titled, .closable, .resizable],
			backing: .buffered,
			defer: false
		)
		delegate.saveWindowFrame(for: smallWindow)

		@Shared(.navigatorWindowSize) var navigatorWindowSize = NavigatorWindowFrame()
		let persisted = $navigatorWindowSize.withLock { $0 }
		XCTAssertEqual(persisted.size.width, NavigatorBrowserWindowSizing.minimumFrameWidth)
		XCTAssertEqual(persisted.size.height, NavigatorBrowserWindowSizing.minimumFrameHeight)

		let restoredWindow = NSWindow(
			contentRect: NSRect(x: -5000, y: -5000, width: 10, height: 10),
			styleMask: [.titled, .closable, .resizable],
			backing: .buffered,
			defer: false
		)
		delegate.configure(window: restoredWindow)

		XCTAssertFalse(restoredWindow.isRestorable)
		XCTAssertEqual(restoredWindow.minSize.width, NavigatorBrowserWindowSizing.minimumFrameWidth)
		XCTAssertEqual(restoredWindow.minSize.height, NavigatorBrowserWindowSizing.minimumFrameHeight)
		XCTAssertGreaterThanOrEqual(restoredWindow.frame.width, NavigatorBrowserWindowSizing.minimumFrameWidth)
		XCTAssertGreaterThanOrEqual(restoredWindow.frame.height, NavigatorBrowserWindowSizing.minimumFrameHeight)
	}

	@MainActor
	func testMonitorCallbacksExerciseShortcutObserversAndSettingsWindowBypass() throws {
		var localMonitor: ((NSEvent) -> NSEvent?)?
		var globalMonitor: ((NSEvent) -> Void)?
		var appearanceObserver: ((Notification) -> Void)?
		var isSettingsWindowFocused = false
		let viewModel = AppViewModel()
		let delegate = NavigatorAppDelegate(
			navigatorAppViewModel: viewModel,
			hooks: NavigatorAppDelegateHooks(
				isRunningTests: { false },
				isSettingsWindowFocused: { isSettingsWindowFocused },
				startBrowserRuntime: {},
				makePrimaryContentViewController: { _, _ in NSViewController() },
				addLocalKeyDownMonitor: { handler in
					localMonitor = handler
					return NSObject()
				},
				addGlobalKeyDownMonitor: { handler in
					globalMonitor = handler
					return NSObject()
				},
				addSystemAppearanceObserver: { handler in
					appearanceObserver = handler
					return NSObject()
				}
			)
		)

		delegate.applicationDidFinishLaunching(Notification(name: .init("NavigatorTests")))
		let unsupportedEvent = try XCTUnwrap(
			makeCoverageKeyDownEvent(
				keyCode: UInt16(kVK_ANSI_X),
				characters: "x",
				charactersIgnoringModifiers: "x",
				modifiers: [.command],
				timestamp: 30
			)
		)
		let supportedEvent = try XCTUnwrap(
			makeCoverageKeyDownEvent(
				keyCode: UInt16(kVK_ANSI_L),
				characters: "l",
				charactersIgnoringModifiers: "l",
				modifiers: [.command],
				timestamp: 31
			)
		)
		let openTabEvent = try XCTUnwrap(
			makeCoverageKeyDownEvent(
				keyCode: UInt16(kVK_ANSI_T),
				characters: "t",
				charactersIgnoringModifiers: "t",
				modifiers: [.command],
				timestamp: 32
			)
		)
		let closeEvent = try XCTUnwrap(
			makeCoverageKeyDownEvent(
				keyCode: UInt16(kVK_ANSI_W),
				characters: "w",
				charactersIgnoringModifiers: "w",
				modifiers: [.command],
				timestamp: 33
			)
		)

		let passthroughEvent = try XCTUnwrap(localMonitor?(unsupportedEvent))
		XCTAssertEqual(passthroughEvent.keyCode, unsupportedEvent.keyCode)

		XCTAssertNil(localMonitor?(supportedEvent))
		XCTAssertEqual(viewModel.browserActionBarViewModel.mode, .currentTab)

		globalMonitor?(openTabEvent)
		XCTAssertEqual(viewModel.browserActionBarViewModel.mode, .newTab)

		appearanceObserver?(Notification(name: .init("AppleInterfaceThemeChangedNotification")))

		isSettingsWindowFocused = true
		let settingsPassthroughEvent = try XCTUnwrap(localMonitor?(closeEvent))
		XCTAssertEqual(settingsPassthroughEvent.keyCode, closeEvent.keyCode)
		XCTAssertFalse(delegate.handleShortcutEvent(closeEvent))
	}

	@MainActor
	func testShortcutInstallersAndHandlerClosuresCoverNoOpPaths() throws {
		var localMonitor: ((NSEvent) -> NSEvent?)?
		var globalMonitor: ((NSEvent) -> Void)?
		var appearanceObserver: ((Notification) -> Void)?
		let viewModel = AppViewModel()
		let delegate = NavigatorAppDelegate(
			navigatorAppViewModel: viewModel,
			hooks: NavigatorAppDelegateHooks(
				isRunningTests: { false },
				makePrimaryContentViewController: { _, _ in NSViewController() },
				addLocalKeyDownMonitor: { handler in
					localMonitor = handler
					return NSObject()
				},
				addGlobalKeyDownMonitor: { handler in
					globalMonitor = handler
					return NSObject()
				},
				addSystemAppearanceObserver: { handler in
					appearanceObserver = handler
					return NSObject()
				}
			)
		)

		delegate.installSystemAppearanceObserver()
		delegate.installLocalShortcutMonitor()
		delegate.installGlobalShortcutMonitor()

		let unsupportedEvent = try XCTUnwrap(
			makeCoverageKeyDownEvent(
				keyCode: UInt16(kVK_ANSI_X),
				characters: "x",
				charactersIgnoringModifiers: "x",
				modifiers: [.command],
				timestamp: 40
			)
		)
		let passthroughEvent = try XCTUnwrap(localMonitor?(unsupportedEvent))
		XCTAssertEqual(passthroughEvent.keyCode, unsupportedEvent.keyCode)

		globalMonitor?(unsupportedEvent)
		appearanceObserver?(Notification(name: .init("AppleInterfaceThemeChangedNotification")))

		delegate.keyboardShortcutHandler.perform(.openNewTab)
		XCTAssertEqual(viewModel.browserActionBarViewModel.mode, .newTab)

		delegate.shutdownBrowserRuntimeIfNeeded()
		XCTAssertFalse(delegate.hasStartedBrowserRuntime)
	}

	@MainActor
	func testLocalShortcutMonitorReturnsNilForHandledEventsAndPassthroughWhenDelegateIsReleased() throws {
		var localMonitor: ((NSEvent) -> NSEvent?)?
		var delegate: NavigatorAppDelegate? = NavigatorAppDelegate(
			navigatorAppViewModel: AppViewModel(),
			hooks: NavigatorAppDelegateHooks(
				isRunningTests: { false },
				addLocalKeyDownMonitor: { handler in
					localMonitor = handler
					return NSObject()
				}
			)
		)
		delegate?.installLocalShortcutMonitor()

		let handledEvent = try XCTUnwrap(
			makeCoverageKeyDownEvent(
				keyCode: UInt16(kVK_ANSI_L),
				characters: "l",
				charactersIgnoringModifiers: "l",
				modifiers: [.command],
				timestamp: 41
			)
		)
		XCTAssertNil(localMonitor?(handledEvent))

		delegate = nil

		let orphanedEvent = try XCTUnwrap(
			makeCoverageKeyDownEvent(
				keyCode: UInt16(kVK_ANSI_L),
				characters: "l",
				charactersIgnoringModifiers: "l",
				modifiers: [.command],
				timestamp: 42
			)
		)
		let passthroughEvent = try XCTUnwrap(localMonitor?(orphanedEvent))
		XCTAssertEqual(passthroughEvent.keyCode, orphanedEvent.keyCode)
	}

	@MainActor
	func testHandleShortcutEventReturnsFalseWhenSettingsWindowOwnsCommandW() throws {
		let (delegate, _) = makeAppDelegate(
			hooks: NavigatorAppDelegateHooks(
				isRunningTests: { false },
				isSettingsWindowFocused: { true },
				makePrimaryContentViewController: { _, navigatorAppViewModel in
					TestRootViewController(navigatorAppViewModel: navigatorAppViewModel)
				}
			)
		)
		addTeardownBlock {
			delegate.settingsWindowController?.window?.orderOut(nil)
			delegate.primaryWindow?.orderOut(nil)
		}
		delegate.createPrimaryWindowIfNeeded()

		let closeEvent = try makeKeyDownEvent(
			keyCode: UInt16(kVK_ANSI_W),
			character: "w",
			timestamp: 43
		)

		XCTAssertFalse(delegate.handleShortcutEvent(closeEvent))
	}

	@MainActor
	func testCloseCurrentTabUnpinsSelectedPinnedTab() {
		let (delegate, viewModel) = makeAppDelegate(
			hooks: NavigatorAppDelegateHooks(
				isRunningTests: { false },
				makePrimaryContentViewController: { _, navigatorAppViewModel in
					TestRootViewController(navigatorAppViewModel: navigatorAppViewModel)
				}
			)
		)
		addTeardownBlock {
			delegate.primaryWindow?.orderOut(nil)
		}

		viewModel.sidebarViewModel.openNewTab(with: "https://swift.org")
		let pinnedTabID = viewModel.sidebarViewModel.tabs[0].id
		let secondTabID = viewModel.sidebarViewModel.tabs[1].id
		viewModel.sidebarViewModel.pinTab(id: pinnedTabID)
		viewModel.sidebarViewModel.selectTab(id: pinnedTabID)

		delegate.closeCurrentTab(nil)

		XCTAssertEqual(viewModel.sidebarViewModel.tabs.map(\.id), [pinnedTabID, secondTabID])
		XCTAssertEqual(viewModel.sidebarViewModel.tabs.map(\.isPinned), [false, false])
		XCTAssertEqual(viewModel.sidebarViewModel.selectedTabID, pinnedTabID)
	}

	@MainActor
	func testResolvedVisibleFrameFallsBackFromWindowScreenToMainScreenToWindowFrame() throws {
		let shownWindow = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		shownWindow.orderFront(nil)
		let shownScreenFrame = try XCTUnwrap(shownWindow.screen?.visibleFrame)

		XCTAssertEqual(
			NavigatorAppDelegate.resolvedVisibleFrame(
				attachedScreenVisibleFrame: shownScreenFrame,
				mainScreenVisibleFrame: .zero,
				screenVisibleFrames: [],
				preferredFrame: shownWindow.frame,
				fallbackFrame: shownWindow.frame
			),
			shownScreenFrame
		)

		let hiddenWindow = NSWindow(
			contentRect: NSRect(x: 40, y: 50, width: 220, height: 140),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		let mainScreenFrame = NSRect(x: 10, y: 20, width: 500, height: 400)

		XCTAssertEqual(
			NavigatorAppDelegate.resolvedVisibleFrame(
				attachedScreenVisibleFrame: nil,
				mainScreenVisibleFrame: mainScreenFrame,
				screenVisibleFrames: [],
				preferredFrame: hiddenWindow.frame,
				fallbackFrame: hiddenWindow.frame
			),
			mainScreenFrame
		)
		XCTAssertEqual(
			NavigatorAppDelegate.resolvedVisibleFrame(
				attachedScreenVisibleFrame: nil,
				mainScreenVisibleFrame: nil,
				screenVisibleFrames: [],
				preferredFrame: hiddenWindow.frame,
				fallbackFrame: hiddenWindow.frame
			),
			hiddenWindow.frame
		)
	}
}

final class NavigatorAppRuntimeAdditionalCoverage {
	func testRunExitsWhenArgumentVectorIsMissing() {
		var exitCode: Int32?

		NavigatorAppRuntime.run(
			hooks: NavigatorAppRuntimeHooks(
				arguments: ["Navigator"],
				unsafeArgv: nil,
				exitProcess: { code in exitCode = code }
			)
		)

		XCTAssertEqual(exitCode, 0)
	}

	func testRunExitsWithReportedSubprocessCode() {
		var subprocessCallCount = 0
		var exitCode: Int32?
		var ranApplication = false

		NavigatorAppRuntime.run(
			hooks: NavigatorAppRuntimeHooks(
				argc: 2,
				arguments: ["Navigator", "--type=renderer"],
				unsafeArgv: CommandLine.unsafeArgv,
				maybeRunSubprocess: { argc, argv in
					subprocessCallCount += 1
					XCTAssertEqual(argc, 2)
					XCTAssertNotNil(argv)
					return 42
				},
				makeDelegate: { TestApplicationDelegate2() },
				setDelegate: { _ in XCTFail("Subprocess launch should not install an app delegate") },
				setActivationPolicyRegular: { XCTFail("Subprocess launch should not change activation policy") },
				activateIgnoringOtherApps: { XCTFail("Subprocess launch should not activate the app") },
				runApplication: { ranApplication = true },
				isRunningTests: { false },
				exitProcess: { code in exitCode = code }
			)
		)

		XCTAssertEqual(subprocessCallCount, 1)
		XCTAssertEqual(exitCode, 42)
		XCTAssertFalse(ranApplication)
	}

	func testRunFallsBackToZeroExitWhenSubprocessDoesNotHandleRequest() {
		var exitCode: Int32?

		NavigatorAppRuntime.run(
			hooks: NavigatorAppRuntimeHooks(
				argc: 2,
				arguments: ["Navigator", "--type=gpu-process"],
				unsafeArgv: CommandLine.unsafeArgv,
				maybeRunSubprocess: { _, _ in -1 },
				makeDelegate: { TestApplicationDelegate2() },
				setDelegate: { _ in XCTFail("Subprocess launch should not install an app delegate") },
				setActivationPolicyRegular: { XCTFail("Subprocess launch should not change activation policy") },
				activateIgnoringOtherApps: { XCTFail("Subprocess launch should not activate the app") },
				runApplication: { XCTFail("Subprocess launch should not run the app") },
				isRunningTests: { false },
				exitProcess: { code in exitCode = code }
			)
		)

		XCTAssertEqual(exitCode, 0)
	}

	func testRunLaunchesApplicationWithoutActivationWhileRunningTests() {
		let delegate = TestApplicationDelegate2()
		var installedDelegate: NSApplicationDelegate?
		var activationPolicyChanges = 0
		var activationRequests = 0
		var subprocessCallCount = 0
		var runApplicationCount = 0

		NavigatorAppRuntime.run(
			hooks: NavigatorAppRuntimeHooks(
				argc: 1,
				arguments: ["Navigator"],
				unsafeArgv: CommandLine.unsafeArgv,
				maybeRunSubprocess: { _, _ in
					subprocessCallCount += 1
					return -1
				},
				makeDelegate: { delegate },
				setDelegate: { installedDelegate = $0 },
				setActivationPolicyRegular: { activationPolicyChanges += 1 },
				activateIgnoringOtherApps: { activationRequests += 1 },
				runApplication: { runApplicationCount += 1 },
				isRunningTests: { true },
				exitProcess: { _ in XCTFail("Normal launch should not exit the process") }
			)
		)

		XCTAssertEqual(subprocessCallCount, 1)
		XCTAssertTrue((installedDelegate as AnyObject?) === delegate)
		XCTAssertEqual(activationPolicyChanges, 0)
		XCTAssertEqual(activationRequests, 0)
		XCTAssertEqual(runApplicationCount, 1)
	}

	func testRunLaunchesApplicationAndActivatesOutsideTests() {
		var activationPolicyChanges = 0
		var activationRequests = 0

		NavigatorAppRuntime.run(
			hooks: NavigatorAppRuntimeHooks(
				argc: 1,
				arguments: ["Navigator"],
				unsafeArgv: CommandLine.unsafeArgv,
				maybeRunSubprocess: { _, _ in -1 },
				makeDelegate: { TestApplicationDelegate2() },
				setDelegate: { _ in },
				setActivationPolicyRegular: { activationPolicyChanges += 1 },
				activateIgnoringOtherApps: { activationRequests += 1 },
				runApplication: {},
				isRunningTests: { false },
				exitProcess: { _ in XCTFail("Normal launch should not exit the process") }
			)
		)

		XCTAssertEqual(activationPolicyChanges, 1)
		XCTAssertEqual(activationRequests, 1)
	}

	func testNavigatorAppMainInvokesRuntimeRunner() {
		let originalRunner = NavigatorAppMain.runRuntime
		var didRunRuntime = false
		NavigatorAppMain.runRuntime = {
			didRunRuntime = true
		}
		defer {
			NavigatorAppMain.runRuntime = originalRunner
		}

		NavigatorApp.main()

		XCTAssertTrue(didRunRuntime)
	}
}

#if false
	@MainActor
	final class NavigatorAppDelegateAdditionalCoverage: XCTestCase {
		func testApplicationDidFinishLaunchingSkipsBootstrapWhileRunningTests() {
			var startedBrowserRuntime = 0
			let (delegate, _) = makeAppDelegate(
				hooks: NavigatorAppDelegateHooks(
					isRunningTests: { true },
					startBrowserRuntime: { startedBrowserRuntime += 1 }
				)
			)

			delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

			XCTAssertEqual(startedBrowserRuntime, 0)
			XCTAssertFalse(delegate.hasStartedBrowserRuntime)
			XCTAssertNil(delegate.primaryWindow)
		}

		func testApplicationDidFinishLaunchingBootstrapsMenuMonitorsObserverAndWindow() throws {
			var startedBrowserRuntime = 0
			let localMonitorToken = NSObject()
			let globalMonitorToken = NSObject()
			let systemObserverToken = NSObject()
			var localMonitor: ((NSEvent) -> NSEvent?)?
			var globalMonitor: ((NSEvent) -> Void)?
			var systemAppearanceObserver: ((Notification) -> Void)?
			let existingWindow = NSWindow(
				contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
				styleMask: [.titled, .closable],
				backing: .buffered,
				defer: false
			)

			let (delegate, viewModel) = makeAppDelegate(
				hooks: NavigatorAppDelegateHooks(
					isRunningTests: { false },
					startBrowserRuntime: { startedBrowserRuntime += 1 },
					makePrimaryContentViewController: { _, navigatorAppViewModel in
						TestRootViewController(navigatorAppViewModel: navigatorAppViewModel)
					},
					addLocalKeyDownMonitor: { handler in
						localMonitor = handler
						return localMonitorToken
					},
					addGlobalKeyDownMonitor: { handler in
						globalMonitor = handler
						return globalMonitorToken
					},
					removeEventMonitor: { _ in },
					addSystemAppearanceObserver: { handler in
						systemAppearanceObserver = handler
						return systemObserverToken
					},
					removeSystemAppearanceObserver: { _ in }
				)
			)
			existingWindow.makeKeyAndOrderFront(nil)
			addTeardownBlock {
				existingWindow.orderOut(nil)
				delegate.settingsWindowController?.window?.orderOut(nil)
				delegate.primaryWindow?.orderOut(nil)
				NSApp.mainMenu = nil
			}

			delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

			XCTAssertEqual(startedBrowserRuntime, 1)
			XCTAssertTrue(delegate.hasStartedBrowserRuntime)
			XCTAssertTrue((delegate.localKeyboardShortcutMonitor as AnyObject?) === localMonitorToken)
			XCTAssertTrue((delegate.globalKeyboardShortcutMonitor as AnyObject?) === globalMonitorToken)
			XCTAssertTrue((delegate.systemAppearanceObserver as AnyObject?) === systemObserverToken)
			XCTAssertNotNil(delegate.primaryWindow)
			XCTAssertEqual(
				NSApp.mainMenu?.items.compactMap(\.title),
				["Navigator", "File", "Edit"]
			)

			viewModel.sidebarViewModel.navigateSelectedTab(to: "https://before-monitor.example")
			_ = try XCTUnwrap(localMonitor)(makeKeyDownEvent(keyCode: UInt16(kVK_ANSI_L), character: "l", timestamp: 10))
			XCTAssertEqual(viewModel.browserActionBarViewModel.mode, .currentTab)

			try globalMonitor?(makeKeyDownEvent(keyCode: UInt16(kVK_ANSI_T), character: "t", timestamp: 20))
			XCTAssertEqual(viewModel.browserActionBarViewModel.mode, .newTab)

			systemAppearanceObserver?(Notification(name: NSNotification.Name("AppleInterfaceThemeChangedNotification")))
		}

		func testTerminationLifecycleRemovesMonitorsAndShutsDownRuntime() {
			var shutdownBrowserRuntime = 0
			var removedMonitorCount = 0
			var removedObserverCount = 0
			let localMonitorToken = NSObject()
			let globalMonitorToken = NSObject()
			let systemObserverToken = NSObject()
			let (delegate, _) = makeAppDelegate(
				hooks: NavigatorAppDelegateHooks(
					isRunningTests: { false },
					startBrowserRuntime: {},
					shutdownBrowserRuntime: { shutdownBrowserRuntime += 1 },
					makePrimaryContentViewController: { _, navigatorAppViewModel in
						TestRootViewController(navigatorAppViewModel: navigatorAppViewModel)
					},
					addLocalKeyDownMonitor: { _ in localMonitorToken },
					addGlobalKeyDownMonitor: { _ in globalMonitorToken },
					removeEventMonitor: { _ in removedMonitorCount += 1 },
					addSystemAppearanceObserver: { _ in systemObserverToken },
					removeSystemAppearanceObserver: { _ in removedObserverCount += 1 }
				)
			)
			addTeardownBlock {
				delegate.settingsWindowController?.window?.orderOut(nil)
				delegate.primaryWindow?.orderOut(nil)
				NSApp.mainMenu = nil
			}

			delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

			XCTAssertEqual(delegate.applicationShouldTerminate(NSApp), .terminateNow)
			XCTAssertEqual(shutdownBrowserRuntime, 1)
			XCTAssertFalse(delegate.hasStartedBrowserRuntime)
			XCTAssertTrue(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApp))
			XCTAssertTrue(delegate.applicationSupportsSecureRestorableState(NSApp))
			XCTAssertFalse(delegate.application(NSApp, shouldSaveApplicationState: NSCoder()))
			XCTAssertFalse(delegate.application(NSApp, shouldRestoreApplicationState: NSCoder()))

			delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
			delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))

			XCTAssertEqual(shutdownBrowserRuntime, 2)
			XCTAssertEqual(removedMonitorCount, 2)
			XCTAssertEqual(removedObserverCount, 1)
			XCTAssertNil(delegate.localKeyboardShortcutMonitor)
			XCTAssertNil(delegate.globalKeyboardShortcutMonitor)
			XCTAssertNil(delegate.systemAppearanceObserver)
		}

		func testOpenRequestsAndWindowActionsRouteIntoViewModel() throws {
			let (delegate, viewModel) = makeAppDelegate(
				hooks: NavigatorAppDelegateHooks(
					isRunningTests: { false },
					makePrimaryContentViewController: { _, navigatorAppViewModel in
						TestRootViewController(navigatorAppViewModel: navigatorAppViewModel)
					}
				)
			)
			addTeardownBlock {
				delegate.settingsWindowController?.window?.orderOut(nil)
				delegate.primaryWindow?.orderOut(nil)
			}

			XCTAssertFalse(try delegate.handleIncomingURLs([
				XCTUnwrap(URL(string: "mailto:test@example.com")),
			]))

			XCTAssertTrue(try delegate.handleIncomingURLs([
				XCTUnwrap(URL(string: "https://swift.org")),
				URL(fileURLWithPath: "/tmp/example.html"),
			]))
			XCTAssertEqual(
				viewModel.sidebarViewModel.selectedTabCurrentURL,
				URL(fileURLWithPath: "/tmp/example.html").absoluteString
			)

			try delegate.application(NSApp, open: [XCTUnwrap(URL(string: "https://navigator.zip"))])
			XCTAssertEqual(viewModel.sidebarViewModel.selectedTabCurrentURL, "https://navigator.zip")

			delegate.application(NSApp, openFiles: ["/tmp/history.html"])
			XCTAssertEqual(
				viewModel.sidebarViewModel.selectedTabCurrentURL,
				URL(fileURLWithPath: "/tmp/history.html").absoluteString
			)

			delegate.openLocationBar(nil)
			XCTAssertEqual(viewModel.browserActionBarViewModel.mode, .currentTab)

			delegate.openNewTabBar(nil)
			XCTAssertEqual(viewModel.browserActionBarViewModel.mode, .newTab)

			delegate.closeCurrentTab(nil)

			delegate.showSettingsWindow(nil)
			XCTAssertNotNil(delegate.settingsWindowController?.window)

			delegate.showSettingsWindow(nil)
			XCTAssertFalse(delegate.settingsWindowController?.window?.isVisible ?? true)
		}

		func testKeyboardShortcutHandlingCoversResolvedDedupedAndRejectedPaths() throws {
			let (delegate, viewModel) = makeAppDelegate(
				hooks: NavigatorAppDelegateHooks(
					isRunningTests: { false },
					makePrimaryContentViewController: { _, navigatorAppViewModel in
						TestRootViewController(navigatorAppViewModel: navigatorAppViewModel)
					}
				)
			)
			addTeardownBlock {
				delegate.settingsWindowController?.window?.orderOut(nil)
				delegate.primaryWindow?.orderOut(nil)
			}
			delegate.createPrimaryWindowIfNeeded()

			XCTAssertFalse(
				try delegate.handleShortcutEvent(
					makeKeyDownEvent(keyCode: UInt16(kVK_ANSI_A), modifiers: [.option], character: "a", timestamp: 1)
				)
			)

			XCTAssertTrue(
				try delegate.handleShortcutEvent(
					makeKeyDownEvent(keyCode: UInt16(kVK_ANSI_L), character: "l", timestamp: 2)
				)
			)
			XCTAssertEqual(viewModel.browserActionBarViewModel.mode, .currentTab)

			viewModel.browserActionBarViewModel.dismiss()
			XCTAssertTrue(
				try delegate.handleShortcutEvent(
					makeKeyDownEvent(keyCode: UInt16(kVK_ANSI_L), character: "l", timestamp: 2.05)
				)
			)
			XCTAssertFalse(viewModel.browserActionBarViewModel.isPresented)
			XCTAssertEqual(viewModel.browserActionBarViewModel.mode, .currentTab)

			delegate.openSettingsWindow()
			delegate.settingsWindowController?.window?.makeKeyAndOrderFront(nil)
			XCTAssertTrue(
				try delegate.handleShortcutEvent(
					makeKeyDownEvent(keyCode: UInt16(kVK_ANSI_W), character: "w", timestamp: 3)
				)
			)
		}

		func testInvokeKeyboardShortcutActionRunsOnMainAndBackgroundThreads() {
			let (delegate, _) = makeAppDelegate()
			var mainThreadInvocations = 0
			delegate.invokeKeyboardShortcutAction {
				mainThreadInvocations += 1
				XCTAssertTrue(Thread.isMainThread)
			}
			XCTAssertEqual(mainThreadInvocations, 1)

			let expectation = expectation(description: "background action")
			DispatchQueue.global().async {
				delegate.invokeKeyboardShortcutAction {
					XCTAssertTrue(Thread.isMainThread)
					expectation.fulfill()
				}
			}

			wait(for: [expectation], timeout: 1)
		}

		func testKeyboardShortcutHandlerPerformsAllActions() {
			let (delegate, viewModel) = makeAppDelegate(
				hooks: NavigatorAppDelegateHooks(
					makePrimaryContentViewController: { _, navigatorAppViewModel in
						TestRootViewController(navigatorAppViewModel: navigatorAppViewModel)
					}
				)
			)
			addTeardownBlock {
				delegate.primaryWindow?.orderOut(nil)
			}
			delegate.createPrimaryWindowIfNeeded()

			let handler = delegate.keyboardShortcutHandler
			handler.perform(.openLocation)
			XCTAssertEqual(viewModel.browserActionBarViewModel.mode, .currentTab)

			handler.perform(.openNewTab)
			XCTAssertEqual(viewModel.browserActionBarViewModel.mode, .newTab)

			viewModel.sidebarViewModel.openNewTab(with: "https://reopen.example")
			handler.perform(.closeCurrentTab)
			handler.perform(.reopenLastClosedTab)
			XCTAssertEqual(viewModel.sidebarViewModel.selectedTabCurrentURL, "https://reopen.example")
			handler.perform(.copyCurrentTabURL)
			XCTAssertEqual(
				NSPasteboard.general.string(forType: .string),
				"https://reopen.example"
			)
			XCTAssertNotNil(viewModel.toast)
			XCTAssertEqual(
				String(localized: viewModel.toastTitle),
				String(localized: LocalizedStringResource.navigatorToastCopyCurrentTabURLTitle)
			)
			handler.perform(.togglePinSelectedTab)
			XCTAssertTrue(viewModel.sidebarViewModel.tabs[0].isPinned)
			XCTAssertEqual(viewModel.sidebarViewModel.selectedTabID, viewModel.sidebarViewModel.tabs[0].id)
			handler.perform(.togglePinSelectedTab)
			XCTAssertFalse(viewModel.sidebarViewModel.tabs[0].isPinned)
			handler.perform(.reload)
			handler.perform(.goBack)
			handler.perform(.goForward)
			handler.perform(.selectNextTab)
			handler.perform(.selectPreviousTab)
			handler.perform(.selectTab(index: 0))
			XCTAssertEqual(viewModel.sidebarViewModel.selectedTabID, viewModel.sidebarViewModel.tabs[0].id)
		}

		func testWindowStatePersistenceAndPrimaryWindowCreationAreStable() {
			let (delegate, _) = makeAppDelegate(
				hooks: NavigatorAppDelegateHooks(
					makePrimaryContentViewController: { _, navigatorAppViewModel in
						TestRootViewController(navigatorAppViewModel: navigatorAppViewModel)
					}
				)
			)
			addTeardownBlock {
				delegate.primaryWindow?.orderOut(nil)
			}

			let window = NSWindow(
				contentRect: NSRect(x: 20, y: 30, width: 120, height: 80),
				styleMask: [.titled, .closable, .resizable],
				backing: .buffered,
				defer: false
			)
			delegate.saveWindowFrame(for: window)

			@Shared(.navigatorWindowSize) var navigatorWindowSize = NavigatorWindowFrame()
			let persisted = $navigatorWindowSize.withLock { $0 }
			XCTAssertGreaterThanOrEqual(persisted.size.width, NavigatorBrowserWindowSizing.minimumFrameWidth)
			XCTAssertGreaterThanOrEqual(persisted.size.height, NavigatorBrowserWindowSizing.minimumFrameHeight)

			let restoredWindow = NSWindow(
				contentRect: NSRect(x: -5000, y: -5000, width: 10, height: 10),
				styleMask: [.titled, .closable, .resizable],
				backing: .buffered,
				defer: false
			)
			delegate.restoreWindowState(for: restoredWindow)
			XCTAssertGreaterThanOrEqual(restoredWindow.frame.width, NavigatorBrowserWindowSizing.minimumFrameWidth)
			XCTAssertGreaterThanOrEqual(restoredWindow.frame.height, NavigatorBrowserWindowSizing.minimumFrameHeight)

			delegate.configure(window: restoredWindow)
			XCTAssertFalse(restoredWindow.isRestorable)
			XCTAssertEqual(restoredWindow.minSize.width, NavigatorBrowserWindowSizing.minimumFrameWidth)
			XCTAssertEqual(restoredWindow.minSize.height, NavigatorBrowserWindowSizing.minimumFrameHeight)

			delegate.createPrimaryWindowIfNeeded()
			let firstPrimaryWindow = delegate.primaryWindow
			delegate.createPrimaryWindowIfNeeded()
			XCTAssertTrue(delegate.primaryWindow === firstPrimaryWindow)

			delegate.saveWindowState()
			delegate.shutdownBrowserRuntimeIfNeeded()
		}

		func testRestoredWindowFrameUsesBestMatchingSavedScreenWhenWindowIsNotAttached() {
			let (delegate, _) = makeAppDelegate()
			let saved = NavigatorWindowFrame(
				origin: NSPoint(x: 1500, y: 120),
				size: NSSize(width: 900, height: 700)
			)
			let primaryScreen = NSRect(x: 0, y: 0, width: 1440, height: 900)
			let externalScreen = NSRect(x: 1440, y: 0, width: 1728, height: 1117)

			let restoredFrame = delegate.restoredWindowFrame(
				for: saved,
				attachedScreenVisibleFrame: nil,
				mainScreenVisibleFrame: primaryScreen,
				screenVisibleFrames: [primaryScreen, externalScreen],
				fallbackFrame: .zero
			)

			XCTAssertEqual(restoredFrame.origin.x, 1500)
			XCTAssertEqual(restoredFrame.origin.y, 120)
			XCTAssertEqual(restoredFrame.size.width, 900)
			XCTAssertEqual(restoredFrame.size.height, 700)
		}

		func testRestoredWindowFrameClampsOversizedSavedFrameToVisibleScreenBounds() {
			let (delegate, _) = makeAppDelegate()
			let saved = NavigatorWindowFrame(
				origin: NSPoint(x: 100, y: 100),
				size: NSSize(width: 2200, height: 1600)
			)
			let visibleFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)

			let restoredFrame = delegate.restoredWindowFrame(
				for: saved,
				attachedScreenVisibleFrame: nil,
				mainScreenVisibleFrame: visibleFrame,
				screenVisibleFrames: [visibleFrame],
				fallbackFrame: .zero
			)

			XCTAssertEqual(restoredFrame.size.width, visibleFrame.width)
			XCTAssertEqual(restoredFrame.size.height, visibleFrame.height)
			XCTAssertEqual(restoredFrame.origin.x, visibleFrame.minX)
			XCTAssertEqual(restoredFrame.origin.y, visibleFrame.minY)
		}

		func testResolvedVisibleFrameFallsBackToBestIntersectionBeforeMainScreen() {
			let preferredFrame = NSRect(x: 1500, y: 120, width: 900, height: 700)
			let primaryScreen = NSRect(x: 0, y: 0, width: 1440, height: 900)
			let externalScreen = NSRect(x: 1440, y: 0, width: 1728, height: 1117)

			let resolvedFrame = NavigatorAppDelegate.resolvedVisibleFrame(
				attachedScreenVisibleFrame: nil,
				mainScreenVisibleFrame: primaryScreen,
				screenVisibleFrames: [primaryScreen, externalScreen],
				preferredFrame: preferredFrame,
				fallbackFrame: .zero
			)

			XCTAssertEqual(resolvedFrame, externalScreen)
		}
	}
#endif

final class NavigatorIncomingOpenRequestResolverTests: XCTestCase {
	func testURLStringsKeepsSupportedWebAndFileURLs() throws {
		let fileURL = URL(fileURLWithPath: "/tmp/example.html")

		XCTAssertEqual(
			try NavigatorIncomingOpenRequestResolver.urlStrings(from: [
				XCTUnwrap(URL(string: "https://swift.org")),
				XCTUnwrap(URL(string: "http://example.com")),
				fileURL,
			]),
			[
				"https://swift.org",
				"http://example.com",
				fileURL.absoluteString,
			]
		)
	}

	func testURLStringsRejectsUnsupportedSchemes() throws {
		XCTAssertEqual(
			try NavigatorIncomingOpenRequestResolver.urlStrings(from: [
				XCTUnwrap(URL(string: "mailto:test@example.com")),
				XCTUnwrap(URL(string: "ftp://example.com/file.txt")),
			]),
			[]
		)
	}

	func testFileURLsCreatesFileURLsFromPaths() {
		XCTAssertEqual(
			NavigatorIncomingOpenRequestResolver.fileURLs(from: [
				"/tmp/example.html",
				"/tmp/other.xhtml",
			]),
			[
				URL(fileURLWithPath: "/tmp/example.html"),
				URL(fileURLWithPath: "/tmp/other.xhtml"),
			]
		)
	}
}

@MainActor
final class NavigatorCameraStatusItemCoverageTests: XCTestCase {
	func testLaunchingDoesNotInstallCameraStatusItemController() {
		var installCount = 0
		let delegate = NavigatorAppDelegate(
			navigatorAppViewModel: AppViewModel(),
			hooks: NavigatorAppDelegateHooks(
				isRunningTests: { false },
				makePrimaryContentViewController: { _, _ in NSViewController() },
				makeCameraStatusItemController: { _ in
					installCount += 1
					return NavigatorCameraStatusItemControllerSpy()
				}
			)
		)

		delegate.applicationDidFinishLaunching(Notification(name: .init("NavigatorTests")))

		XCTAssertEqual(installCount, 0)
		XCTAssertNil(delegate.cameraStatusItemController)
		XCTAssertTrue(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApp))
	}

	func testOpeningSettingsDoesNotInstallCameraStatusItemControllerAndStillAllowsTerminationAfterLastWindowClosed() {
		let delegate = NavigatorAppDelegate(
			navigatorAppViewModel: AppViewModel(),
			hooks: NavigatorAppDelegateHooks(
				isRunningTests: { false },
				makePrimaryContentViewController: { _, _ in NSViewController() },
				makeCameraStatusItemController: { _ in
					NavigatorCameraStatusItemControllerSpy()
				}
			)
		)

		delegate.applicationDidFinishLaunching(Notification(name: .init("NavigatorTests")))
		delegate.openSettingsWindow()

		XCTAssertNil(delegate.cameraStatusItemController)
		XCTAssertTrue(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApp))
	}

	func testClosingSettingsClearsWindowControllerWithoutCreatingCameraStatusItemController() throws {
		let delegate = NavigatorAppDelegate(
			navigatorAppViewModel: AppViewModel(),
			hooks: NavigatorAppDelegateHooks(
				isRunningTests: { false },
				makePrimaryContentViewController: { _, _ in NSViewController() },
				makeCameraStatusItemController: { _ in
					NavigatorCameraStatusItemControllerSpy()
				}
			)
		)

		delegate.applicationDidFinishLaunching(Notification(name: .init("NavigatorTests")))
		delegate.openSettingsWindow()
		let settingsWindow = try XCTUnwrap(delegate.settingsWindowController?.window)

		delegate.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: settingsWindow))

		XCTAssertNil(delegate.settingsWindowController)
		XCTAssertNil(delegate.cameraStatusItemController)
		XCTAssertTrue(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApp))
	}

	func testReopeningSettingsAfterCloseCreatesFreshController() throws {
		let delegate = NavigatorAppDelegate(
			navigatorAppViewModel: AppViewModel(),
			hooks: NavigatorAppDelegateHooks(
				isRunningTests: { false },
				makePrimaryContentViewController: { _, _ in NSViewController() },
				makeCameraStatusItemController: { _ in
					NavigatorCameraStatusItemControllerSpy()
				}
			)
		)

		delegate.applicationDidFinishLaunching(Notification(name: .init("NavigatorTests")))
		delegate.openSettingsWindow()
		let firstController = try XCTUnwrap(delegate.settingsWindowController)
		let firstWindow = try XCTUnwrap(firstController.window)

		delegate.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: firstWindow))
		delegate.openSettingsWindow()

		let secondController = try XCTUnwrap(delegate.settingsWindowController)
		XCTAssertFalse(firstController === secondController)
	}

	func testTerminationInvalidatesInstalledCameraStatusItemController() {
		let delegate = NavigatorAppDelegate(
			navigatorAppViewModel: AppViewModel(),
			hooks: NavigatorAppDelegateHooks(
				isRunningTests: { false },
				makePrimaryContentViewController: { _, _ in NSViewController() },
				makeCameraStatusItemController: { _ in
					NavigatorCameraStatusItemControllerSpy()
				}
			)
		)

		delegate.applicationDidFinishLaunching(Notification(name: .init("NavigatorTests")))
		delegate.openSettingsWindow()
		XCTAssertEqual(delegate.applicationShouldTerminate(NSApp), .terminateNow)

		XCTAssertNil(delegate.cameraStatusItemController)
	}
}

@MainActor
final class NavigatorCameraStatusItemControllerTests: XCTestCase {
	func testTintStyleErrorMapsToSystemRed() {
		XCTAssertTrue(
			NavigatorCameraStatusItemTintStyle.error.color.isEqual(NSColor.systemRed)
		)
	}

	func testAppearanceResolverTreatsPreviewOnlyCameraUsageAsActive() {
		let appearance = NavigatorCameraStatusItemAppearanceResolver.resolve(
			lifecycleState: .running,
			healthState: .healthy,
			debugSummary: makeNavigatorCameraStatusSnapshot(
				lifecycleState: .running,
				healthState: .healthy,
				activeConsumers: [
					BrowserCameraConsumer(
						id: "preview",
						kind: .menuBarPreview,
						requiresLiveFrames: false
					),
				]
			).debugSummary
		)

		XCTAssertEqual(
			appearance,
			NavigatorCameraStatusItemAppearance(
				symbolName: "video.fill",
				tintStyle: .accent
			)
		)
	}

	func testAppearanceResolverCoversWarningAndErrorBranches() {
		let degradedAppearance = NavigatorCameraStatusItemAppearanceResolver.resolve(
			lifecycleState: .running,
			healthState: .pipelineFallback,
			debugSummary: makeNavigatorCameraStatusSnapshot(
				lifecycleState: .running,
				healthState: .pipelineFallback
			).debugSummary
		)
		let publisherAppearance = NavigatorCameraStatusItemAppearanceResolver.resolve(
			lifecycleState: .running,
			healthState: .publisherUnavailable,
			debugSummary: makeNavigatorCameraStatusSnapshot(
				lifecycleState: .running,
				healthState: .publisherUnavailable
			).debugSummary
		)
		let failedAppearance = NavigatorCameraStatusItemAppearanceResolver.resolve(
			lifecycleState: .failed,
			healthState: .healthy,
			debugSummary: makeNavigatorCameraStatusSnapshot(
				lifecycleState: .failed,
				healthState: .healthy
			).debugSummary
		)

		XCTAssertEqual(
			degradedAppearance,
			NavigatorCameraStatusItemAppearance(
				symbolName: "video.badge.exclamationmark",
				tintStyle: .warning
			)
		)
		XCTAssertEqual(
			publisherAppearance,
			NavigatorCameraStatusItemAppearance(
				symbolName: "video.slash",
				tintStyle: .error
			)
		)
		XCTAssertEqual(
			failedAppearance,
			NavigatorCameraStatusItemAppearance(
				symbolName: "exclamationmark.triangle.fill",
				tintStyle: .error
			)
		)
	}

	func testControllerRefreshesAppearanceFromSnapshotUpdatesAndInvalidatesHost() {
		let coordinator = NavigatorCameraStatusItemCoordinatorSpy(
			snapshot: makeNavigatorCameraStatusSnapshot(
				lifecycleState: .idle,
				healthState: .healthy
			)
		)
		let viewModel = BrowserCameraMenuBarViewModel(
			browserCameraSessionCoordinator: coordinator
		)
		let button = NavigatorCameraStatusItemButtonSpy()
		let host = NavigatorCameraStatusItemHostSpy(button: button)
		let popover = NavigatorCameraStatusItemPopoverSpy()
		let controller = NavigatorCameraStatusItemController(
			viewModel: viewModel,
			statusItemHost: host,
			popover: popover,
			contentViewProvider: { _ in
				NSView(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
			}
		)

		XCTAssertTrue((button.target as AnyObject?) === controller)
		XCTAssertEqual(button.action, NSSelectorFromString("togglePopover:"))
		XCTAssertEqual(button.imagePosition, .imageOnly)
		XCTAssertEqual(
			controller.currentAppearanceForTesting(),
			NavigatorCameraStatusItemAppearance(
				symbolName: "video",
				tintStyle: .secondary
			)
		)
		XCTAssertEqual(controller.currentToolTipForTesting(), "Navigator Camera ready")
		XCTAssertEqual(popover.behavior, .transient)
		XCTAssertEqual(popover.contentSize, NSSize(width: 320, height: 360))
		XCTAssertNotNil(popover.contentViewController)

		coordinator.snapshot = makeNavigatorCameraStatusSnapshot(
			lifecycleState: .running,
			healthState: .healthy,
			activeConsumers: [
				BrowserCameraConsumer(
					id: "preview",
					kind: .menuBarPreview,
					requiresLiveFrames: false
				),
			],
			pipelineRuntimeState: BrowserCameraPipelineRuntimeState(
				preset: .mononoke,
				implementation: .aperture,
				warmupProfile: .monochromatic,
				grainPresence: .high,
				requiredFilterCount: 1
			),
			recentDiagnosticEvents: [
				BrowserCameraDiagnosticEvent(
					kind: .permissionProbeFailed,
					detail: "tabID=tab-1 error=Permission denied"
				),
			]
		)
		coordinator.emitSnapshot()

		XCTAssertEqual(
			controller.currentAppearanceForTesting(),
			NavigatorCameraStatusItemAppearance(
				symbolName: "video.fill",
				tintStyle: .accent
			)
		)
		XCTAssertEqual(
			controller.currentToolTipForTesting(),
			"""
			Navigator Camera active
			Pipeline: aperture • monochromatic • 1 filters
			Latest event: Permission probe failed: tabID=tab-1 error=Permission denied
			"""
		)
		XCTAssertNotNil(button.image)
		XCTAssertTrue(button.contentTintColor?.isEqual(NSColor.controlAccentColor) ?? false)

		controller.invalidate()

		XCTAssertEqual(host.invalidateCount, 1)
		XCTAssertNil(button.target)
		XCTAssertNil(button.action)
		XCTAssertEqual(coordinator.removedSnapshotObserverIDs, ["snapshot-observer"])
		XCTAssertEqual(coordinator.removedPreviewObserverIDs, ["preview-observer"])
	}

	func testControllerTogglePopoverShowsAndClosesUsingInjectedPopover() {
		let coordinator = NavigatorCameraStatusItemCoordinatorSpy(
			snapshot: makeNavigatorCameraStatusSnapshot(
				lifecycleState: .idle,
				healthState: .healthy
			)
		)
		let popover = NavigatorCameraStatusItemPopoverSpy()
		let controller = NavigatorCameraStatusItemController(
			viewModel: BrowserCameraMenuBarViewModel(
				browserCameraSessionCoordinator: coordinator
			),
			statusItemHost: NavigatorCameraStatusItemHostSpy(
				button: NavigatorCameraStatusItemButtonSpy()
			),
			popover: popover,
			contentViewProvider: { _ in
				NSView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
			}
		)

		controller.togglePopoverForTesting()
		XCTAssertEqual(popover.showRequestCount, 1)
		XCTAssertTrue(popover.isShown)

		controller.togglePopoverForTesting()
		XCTAssertEqual(popover.closeRequestCount, 1)
		XCTAssertFalse(popover.isShown)
		controller.invalidate()
	}

	func testControllerOnlyRegistersMenuBarPreviewConsumerWhilePopoverIsShown() {
		let snapshot = BrowserCameraSessionSnapshot(
			lifecycleState: .idle,
			healthState: .healthy,
			outputMode: .processedNavigatorFeed,
			routingSettings: BrowserCameraRoutingSettings(
				routingEnabled: true,
				preferNavigatorCameraWhenPossible: true,
				preferredSourceID: "camera-1",
				preferredFilterPreset: .none,
				previewEnabled: true
			),
			availableSources: [
				BrowserCameraSource(id: "camera-1", name: "FaceTime HD Camera", isDefault: true),
			],
			activeConsumersByID: [:],
			performanceMetrics: .empty,
			lastErrorDescription: nil
		)
		let coordinator = NavigatorCameraStatusItemCoordinatorSpy(snapshot: snapshot)
		let popover = NavigatorCameraStatusItemPopoverSpy()
		let controller = NavigatorCameraStatusItemController(
			viewModel: BrowserCameraMenuBarViewModel(
				browserCameraSessionCoordinator: coordinator
			),
			statusItemHost: NavigatorCameraStatusItemHostSpy(
				button: NavigatorCameraStatusItemButtonSpy()
			),
			popover: popover,
			contentViewProvider: { _ in
				NSView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
			}
		)

		XCTAssertTrue(coordinator.registeredConsumers.isEmpty)

		controller.togglePopoverForTesting()
		XCTAssertEqual(coordinator.registeredConsumers.last?.kind, .menuBarPreview)

		controller.togglePopoverForTesting()
		XCTAssertEqual(coordinator.unregisteredConsumerIDs.last, coordinator.registeredConsumers.last?.id)

		controller.invalidate()
	}

	func testControllerSafelyHandlesMissingStatusItemButton() {
		let coordinator = NavigatorCameraStatusItemCoordinatorSpy(
			snapshot: makeNavigatorCameraStatusSnapshot(
				lifecycleState: .idle,
				healthState: .healthy
			)
		)
		let popover = NavigatorCameraStatusItemPopoverSpy()
		let host = NavigatorCameraStatusItemHostSpy(button: nil)
		let controller = NavigatorCameraStatusItemController(
			viewModel: BrowserCameraMenuBarViewModel(
				browserCameraSessionCoordinator: coordinator
			),
			statusItemHost: host,
			popover: popover,
			contentViewProvider: { _ in
				NSView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
			}
		)

		XCTAssertNil(controller.currentAppearanceForTesting())

		coordinator.emitSnapshot()
		controller.togglePopoverForTesting()
		controller.invalidate()

		XCTAssertEqual(popover.showRequestCount, 0)
		XCTAssertEqual(popover.closeRequestCount, 1)
		XCTAssertEqual(host.invalidateCount, 1)
	}

	func testNSStatusBarButtonAdapterReturnsButtonView() throws {
		let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
		defer {
			NSStatusBar.system.removeStatusItem(statusItem)
		}
		let button = try XCTUnwrap(statusItem.button)
		let adapter: any NavigatorCameraStatusItemButtonControlling = button

		XCTAssertTrue(adapter.view === button)
	}

	func testLiveControllerCanInitializeAndInvalidate() {
		let coordinator = NavigatorCameraStatusItemCoordinatorSpy(
			snapshot: makeNavigatorCameraStatusSnapshot(
				lifecycleState: .running,
				healthState: .sourceLost
			)
		)
		let controller = NavigatorCameraStatusItemController(
			browserCameraSessionCoordinator: coordinator
		)

		XCTAssertNotNil(controller.currentAppearanceForTesting())
		controller.invalidate()
	}

	func testTooltipResolverIncludesLatestEventAndFallsBackToLastError() {
		let readySummary = makeNavigatorCameraStatusSnapshot(
			lifecycleState: .idle,
			healthState: .healthy
		).debugSummary

		XCTAssertEqual(
			NavigatorCameraStatusItemTooltipResolver.resolve(
				debugSummary: readySummary,
				localized: { $0.fallbackValue },
				localizedDiagnosticEvent: { $0.fallbackValue(localeIdentifier: nil) }
			),
			"Navigator Camera ready"
		)

		let activeSummary = makeNavigatorCameraStatusSnapshot(
			lifecycleState: .running,
			healthState: .healthy,
			activeConsumers: [
				BrowserCameraConsumer(
					id: "tab-1",
					kind: .browserTabCapture,
					requiresLiveFrames: true
				),
			],
			browserTransportStates: [
				BrowserCameraBrowserTransportState(
					tabID: "tab-1",
					routingTransportMode: .browserProcessJavaScriptFallback,
					frameTransportMode: .rendererProcessMessages,
					activeManagedTrackCount: 1
				),
			],
			pipelineRuntimeState: BrowserCameraPipelineRuntimeState(
				preset: .mononoke,
				implementation: .aperture,
				warmupProfile: .monochromatic,
				grainPresence: .high,
				requiredFilterCount: 1
			),
			lastErrorDescription: "Renderer unavailable",
			recentDiagnosticEvents: [
				BrowserCameraDiagnosticEvent(
					kind: .permissionProbeFailed,
					detail: "tabID=tab-1 error=Permission denied"
				),
			]
		).debugSummary

		XCTAssertEqual(
			NavigatorCameraStatusItemTooltipResolver.resolve(
				debugSummary: activeSummary,
				localized: { $0.fallbackValue },
				localizedDiagnosticEvent: { $0.fallbackValue(localeIdentifier: nil) }
			),
			"""
			Navigator Camera active
			Browser transport: tabs 1 • Tracks: 1 • Fallback: 1
			Pipeline: aperture • monochromatic • 1 filters
			Latest event: Permission probe failed: tabID=tab-1 error=Permission denied
			"""
		)

		let degradedSummary = makeNavigatorCameraStatusSnapshot(
			lifecycleState: .running,
			healthState: .degraded,
			recentDiagnosticEvents: [
				BrowserCameraDiagnosticEvent(
					kind: .processingDegraded,
					detail: nil
				),
			]
		).debugSummary

		XCTAssertEqual(
			NavigatorCameraStatusItemTooltipResolver.resolve(
				debugSummary: degradedSummary,
				localized: { $0.fallbackValue },
				localizedDiagnosticEvent: { $0.fallbackValue(localeIdentifier: nil) }
			),
			"""
			Navigator Camera degraded
			Latest event: Processing degraded
			"""
		)

		let failedSummary = makeNavigatorCameraStatusSnapshot(
			lifecycleState: .failed,
			healthState: .healthy,
			lastErrorDescription: "Capture unavailable"
		).debugSummary

		XCTAssertEqual(
			NavigatorCameraStatusItemTooltipResolver.resolve(
				debugSummary: failedSummary,
				localized: { $0.fallbackValue },
				localizedDiagnosticEvent: { $0.fallbackValue(localeIdentifier: nil) }
			),
			"""
			Navigator Camera unavailable
			Last error: Capture unavailable
			"""
		)

		let publisherSummary = makeNavigatorCameraStatusSnapshot(
			lifecycleState: .running,
			healthState: .publisherUnavailable,
			lastErrorDescription: "Publisher crashed"
		).debugSummary

		XCTAssertEqual(
			NavigatorCameraStatusItemTooltipResolver.resolve(
				debugSummary: publisherSummary,
				localized: { $0.fallbackValue },
				localizedDiagnosticEvent: { $0.fallbackValue(localeIdentifier: nil) }
			),
			"""
			Navigator Camera publisher unavailable
			Last error: Publisher crashed
			"""
		)
	}

	func testNavigatorCameraDiagnosticLocalizationKeysCoverAllEventKinds() {
		for kind in BrowserCameraDiagnosticEventKind.allCases {
			let key = NavigatorCameraDiagnosticLocalizationKey(kind: kind)
			XCTAssertFalse(key.fallbackValue(localeIdentifier: nil).isEmpty)
			XCTAssertFalse(key.fallbackValue(localeIdentifier: "ja").isEmpty)
		}
	}
}

final class NavigatorDefaultBrowserClientTests: XCTestCase {
	func testLiveClientRejectsEmptyBundleIdentifier() async throws {
		XCTAssertFalse(NavigatorDefaultBrowserClient.live.isDefaultBrowser(""))
		let bundle = try makeBundle(bundleIdentifier: nil, shortVersion: nil, buildNumber: nil)
		await XCTAssertThrowsErrorAsync(try await NavigatorDefaultBrowserClient.live.setAsDefaultBrowser(bundle)) { error in
			guard case .missingBundleIdentifier = error as? NavigatorDefaultBrowserClientError else {
				return XCTFail("Expected missingBundleIdentifier error")
			}
		}
	}

	func testCopyDefaultHandlerForInvalidSchemeReturnsNil() {
		XCTAssertNil(
			NavigatorDefaultBrowserClient.copyDefaultHandlerForURLScheme("navigator-tests-invalid-scheme")
		)
	}

	func testIsDefaultBrowserRejectsEmptyBundleIdentifier() {
		var requestedSchemes = [String]()

		XCTAssertFalse(
			NavigatorDefaultBrowserClient.isDefaultBrowser(
				bundleIdentifier: "",
				copyDefaultHandlerForURLScheme: { scheme in
					requestedSchemes.append(scheme)
					return "com.example.navigator"
				}
			)
		)
		XCTAssertTrue(requestedSchemes.isEmpty)
	}

	func testIsDefaultBrowserReturnsFalseWhenAnySchemeHandlerIsMissingOrMismatched() {
		var missingHandlerSchemes = [String]()
		XCTAssertFalse(
			NavigatorDefaultBrowserClient.isDefaultBrowser(
				bundleIdentifier: "com.example.navigator",
				copyDefaultHandlerForURLScheme: { scheme in
					missingHandlerSchemes.append(scheme)
					return nil
				}
			)
		)
		XCTAssertEqual(missingHandlerSchemes, ["http"])

		var mismatchedSchemes = [String]()
		XCTAssertFalse(
			NavigatorDefaultBrowserClient.isDefaultBrowser(
				bundleIdentifier: "com.example.navigator",
				copyDefaultHandlerForURLScheme: { scheme in
					mismatchedSchemes.append(scheme)
					return scheme == "http" ? "com.example.navigator" : "com.example.other"
				}
			)
		)
		XCTAssertEqual(mismatchedSchemes, ["http", "https"])
	}

	func testIsDefaultBrowserReturnsTrueWhenAllSchemeHandlersMatch() {
		var requestedSchemes = [String]()

		XCTAssertTrue(
			NavigatorDefaultBrowserClient.isDefaultBrowser(
				bundleIdentifier: "com.example.navigator",
				copyDefaultHandlerForURLScheme: { scheme in
					requestedSchemes.append(scheme)
					return "com.example.navigator"
				}
			)
		)
		XCTAssertEqual(requestedSchemes, ["http", "https"])
	}

	func testSetAsDefaultBrowserRejectsEmptyBundleIdentifier() async throws {
		var schemeUpdates = [(URL, String)]()
		var contentTypeUpdates = [(URL, String)]()
		let bundle = try makeBundle(bundleIdentifier: nil, shortVersion: nil, buildNumber: nil)

		await XCTAssertThrowsErrorAsync(
			try await NavigatorDefaultBrowserClient.setAsDefaultBrowser(
				bundle: bundle,
				setDefaultApplicationForURLScheme: { applicationURL, scheme, completion in
					schemeUpdates.append((applicationURL, scheme))
					completion(nil)
				},
				setDefaultApplicationForContentType: { applicationURL, contentType, completion in
					contentTypeUpdates.append((applicationURL, contentType.identifier))
					completion(nil)
				}
			)
		) { error in
			guard case .missingBundleIdentifier = error as? NavigatorDefaultBrowserClientError else {
				return XCTFail("Expected missingBundleIdentifier error")
			}
		}
		XCTAssertTrue(schemeUpdates.isEmpty)
		XCTAssertTrue(contentTypeUpdates.isEmpty)
	}

	func testSetAsDefaultBrowserStopsOnSchemeFailure() async throws {
		var schemeUpdates = [(URL, String)]()
		var contentTypeUpdates = [(URL, String)]()
		let bundle = try makeBundle(bundleIdentifier: "com.example.navigator", shortVersion: nil, buildNumber: nil)
		let expectedError = NSError(domain: "NavigatorDefaultBrowserClientTests", code: 50)

		await XCTAssertThrowsErrorAsync(
			try await NavigatorDefaultBrowserClient.setAsDefaultBrowser(
				bundle: bundle,
				setDefaultApplicationForURLScheme: { applicationURL, scheme, completion in
					schemeUpdates.append((applicationURL, scheme))
					completion(scheme == "http" ? expectedError : nil)
				},
				setDefaultApplicationForContentType: { applicationURL, contentType, completion in
					contentTypeUpdates.append((applicationURL, contentType.identifier))
					completion(nil)
				}
			)
		) { error in
			guard case let .updateFailed(target, underlyingError) = error as? NavigatorDefaultBrowserClientError else {
				return XCTFail("Expected updateFailed error")
			}
			let nsError = underlyingError as NSError
			XCTAssertEqual(target, "http")
			XCTAssertEqual(nsError.domain, expectedError.domain)
			XCTAssertEqual(nsError.code, expectedError.code)
		}
		XCTAssertEqual(schemeUpdates.map(\.1), ["http"])
		XCTAssertTrue(contentTypeUpdates.isEmpty)
	}

	func testSetAsDefaultBrowserStopsOnContentTypeFailure() async throws {
		var schemeUpdates = [(URL, String)]()
		var contentTypeUpdates = [(URL, String)]()
		let bundle = try makeBundle(bundleIdentifier: "com.example.navigator", shortVersion: nil, buildNumber: nil)
		let expectedError = NSError(domain: "NavigatorDefaultBrowserClientTests", code: 10814)

		await XCTAssertThrowsErrorAsync(
			try await NavigatorDefaultBrowserClient.setAsDefaultBrowser(
				bundle: bundle,
				setDefaultApplicationForURLScheme: { applicationURL, scheme, completion in
					schemeUpdates.append((applicationURL, scheme))
					completion(nil)
				},
				setDefaultApplicationForContentType: { applicationURL, contentType, completion in
					contentTypeUpdates.append((applicationURL, contentType.identifier))
					completion(contentType.identifier == "public.html" ? expectedError : nil)
				}
			)
		) { error in
			guard case let .updateFailed(target, underlyingError) = error as? NavigatorDefaultBrowserClientError else {
				return XCTFail("Expected updateFailed error")
			}
			let nsError = underlyingError as NSError
			XCTAssertEqual(target, "public.html")
			XCTAssertEqual(nsError.domain, expectedError.domain)
			XCTAssertEqual(nsError.code, expectedError.code)
		}
		XCTAssertEqual(schemeUpdates.map(\.1), ["http", "https"])
		XCTAssertEqual(contentTypeUpdates.map(\.1), ["public.html"])
	}

	func testSetAsDefaultBrowserUpdatesAllSupportedSchemesAndContentTypes() async throws {
		var schemeUpdates = [(URL, String)]()
		var contentTypeUpdates = [(URL, String)]()
		let bundle = try makeBundle(bundleIdentifier: "com.example.navigator", shortVersion: nil, buildNumber: nil)

		try await NavigatorDefaultBrowserClient.setAsDefaultBrowser(
			bundle: bundle,
			setDefaultApplicationForURLScheme: { applicationURL, scheme, completion in
				schemeUpdates.append((applicationURL, scheme))
				completion(nil)
			},
			setDefaultApplicationForContentType: { applicationURL, contentType, completion in
				contentTypeUpdates.append((applicationURL, contentType.identifier))
				completion(nil)
			}
		)

		XCTAssertEqual(schemeUpdates.map(\.1), ["http", "https"])
		XCTAssertEqual(contentTypeUpdates.map(\.1), ["public.html", "public.xhtml"])
		XCTAssertTrue(schemeUpdates.allSatisfy { $0.0 == bundle.bundleURL })
		XCTAssertTrue(contentTypeUpdates.allSatisfy { $0.0 == bundle.bundleURL })
	}

	func testLiveHelpersDelegateToWorkspaceWrappers() async throws {
		XCTAssertFalse(NavigatorDefaultBrowserClient.liveIsDefaultBrowser(""))
		let emptyBundle = try makeBundle(bundleIdentifier: nil, shortVersion: nil, buildNumber: nil)
		await XCTAssertThrowsErrorAsync(try await NavigatorDefaultBrowserClient.live
			.setAsDefaultBrowser(emptyBundle)) { error in
				guard case .missingBundleIdentifier = error as? NavigatorDefaultBrowserClientError else {
					return XCTFail("Expected missingBundleIdentifier error")
				}
			}

		var schemeUpdates = [(URL, String)]()
		var contentTypeUpdates = [(URL, String)]()
		let bundle = try makeBundle(bundleIdentifier: "com.example.navigator", shortVersion: nil, buildNumber: nil)
		try? await NavigatorDefaultBrowserClient.liveSetAsDefaultBrowser(
			bundle,
			setDefaultApplicationForURLScheme: { applicationURL, scheme, completion in
				schemeUpdates.append((applicationURL, scheme))
				completion(nil)
			},
			setDefaultApplicationForContentType: { applicationURL, contentType, completion in
				contentTypeUpdates.append((applicationURL, contentType.identifier))
				completion(nil)
			}
		)

		XCTAssertEqual(schemeUpdates.map(\.1), ["http", "https"])
		XCTAssertEqual(contentTypeUpdates.map(\.1), ["public.html", "public.xhtml"])
	}
}

@MainActor
final class NavigatorSettingsViewModelTests: XCTestCase {
	override func setUp() {
		super.setUp()
		installCoverageTestApplicationDelegate()
		clearImportedBrowserLibrary()
	}

	override func tearDown() {
		closeAllCoverageTestWindows()
		clearImportedBrowserLibrary()
		super.tearDown()
	}

	func testSelectedSectionDefaultsToGeneral() {
		let viewModel = NavigatorSettingsViewModel(bundle: .main)

		XCTAssertEqual(viewModel.selectedSection, .general)
	}

	func testConvenienceInitIsCallable() {
		let viewModel = NavigatorSettingsViewModel()

		XCTAssertEqual(viewModel.selectedSection, .general)
	}

	func testAutomaticUpdateChecksDefaultToEnabled() {
		withDependencies {
			$0.defaultFileStorage = .inMemory
		} operation: {
			let viewModel = NavigatorSettingsViewModel(bundle: .main)

			XCTAssertTrue(viewModel.automaticallyChecksForUpdates)
		}
	}

	func testAutomaticUpdateChecksPersistAcrossSettingsViewModels() {
		withDependencies {
			$0.defaultFileStorage = .inMemory
		} operation: {
			let firstViewModel = NavigatorSettingsViewModel(bundle: .main)
			firstViewModel.setAutomaticallyChecksForUpdates(false)

			let secondViewModel = NavigatorSettingsViewModel(bundle: .main)

			XCTAssertFalse(firstViewModel.automaticallyChecksForUpdates)
			XCTAssertFalse(secondViewModel.automaticallyChecksForUpdates)
		}
	}

	func testDefaultBrowserStatusStartsAsCurrentDefaultWhenClientMatchesBundleIdentifier() {
		let viewModel = NavigatorSettingsViewModel(
			bundle: .main,
			defaultBrowserClient: .init(
				isDefaultBrowser: { _ in true },
				setAsDefaultBrowser: { _ in }
			)
		)

		XCTAssertEqual(viewModel.defaultBrowserStatus, .currentDefault)
		XCTAssertFalse(viewModel.canSetAsDefaultBrowser)
	}

	func testSetAsDefaultBrowserPromotesStatusAfterSuccessfulUpdate() async {
		var isDefaultBrowser = false
		let viewModel = NavigatorSettingsViewModel(
			bundle: .main,
			defaultBrowserClient: .init(
				isDefaultBrowser: { _ in isDefaultBrowser },
				setAsDefaultBrowser: { _ in
					isDefaultBrowser = true
				}
			)
		)

		XCTAssertEqual(viewModel.defaultBrowserStatus, .readyToSet)

		await viewModel.setAsDefaultBrowser()

		XCTAssertEqual(viewModel.defaultBrowserStatus, .currentDefault)
		XCTAssertFalse(viewModel.canSetAsDefaultBrowser)
	}

	func testSetAsDefaultBrowserShowsFailureWhenUpdateThrows() async {
		let viewModel = NavigatorSettingsViewModel(
			bundle: .main,
			defaultBrowserClient: .init(
				isDefaultBrowser: { _ in false },
				setAsDefaultBrowser: { _ in
					throw DefaultBrowserTestError.failed
				}
			)
		)

		await viewModel.setAsDefaultBrowser()

		XCTAssertEqual(viewModel.defaultBrowserStatus, .updateFailed)
		XCTAssertTrue(viewModel.canSetAsDefaultBrowser)
		XCTAssertFalse(viewModel.showsDefaultBrowserError)
		XCTAssertEqual(
			viewModel.defaultBrowserDescription,
			String(localized: .navigatorSettingsDefaultBrowserDescription)
		)
	}

	func testDefaultBrowserDescriptionsCoverEveryState() {
		let viewModel = NavigatorSettingsViewModel(
			bundle: .main,
			defaultBrowserClient: .init(
				isDefaultBrowser: { _ in false },
				setAsDefaultBrowser: { _ in }
			)
		)

		XCTAssertEqual(
			viewModel.defaultBrowserDescription,
			String(localized: .navigatorSettingsDefaultBrowserDescription)
		)

		viewModel.defaultBrowserStatus = .currentDefault
		XCTAssertEqual(
			viewModel.defaultBrowserDescription,
			String(localized: .navigatorSettingsDefaultBrowserEnabledDescription)
		)

		viewModel.defaultBrowserStatus = .updateFailed
		XCTAssertEqual(
			viewModel.defaultBrowserDescription,
			String(localized: .navigatorSettingsDefaultBrowserDescription)
		)
	}

	func testRefreshDefaultBrowserStatusReevaluatesBrowserState() {
		var isDefaultBrowser = false
		let viewModel = NavigatorSettingsViewModel(
			bundle: .main,
			defaultBrowserClient: .init(
				isDefaultBrowser: { _ in isDefaultBrowser },
				setAsDefaultBrowser: { _ in }
			)
		)

		isDefaultBrowser = true
		viewModel.refreshDefaultBrowserStatus()

		XCTAssertEqual(viewModel.defaultBrowserStatus, .currentDefault)
	}

	func testSetAsDefaultBrowserFailsWhenBundleIdentifierCannotBeNormalized() async throws {
		let viewModel = try NavigatorSettingsViewModel(
			bundle: makeBundle(bundleIdentifier: nil, shortVersion: nil, buildNumber: nil),
			defaultBrowserClient: .init(
				isDefaultBrowser: { _ in false },
				setAsDefaultBrowser: { _ in }
			)
		)

		await viewModel.setAsDefaultBrowser()

		XCTAssertEqual(viewModel.defaultBrowserStatus, .updateFailed)
		XCTAssertFalse(viewModel.canSetAsDefaultBrowser)
	}

	func testSetAsDefaultBrowserKeepsReadyStateWhenReadbackStillDoesNotMatch() async {
		let viewModel = NavigatorSettingsViewModel(
			bundle: .main,
			defaultBrowserClient: .init(
				isDefaultBrowser: { _ in false },
				setAsDefaultBrowser: { _ in }
			)
		)

		await viewModel.setAsDefaultBrowser()

		XCTAssertEqual(viewModel.defaultBrowserStatus, .readyToSet)
		XCTAssertTrue(viewModel.canSetAsDefaultBrowser)
		XCTAssertFalse(viewModel.showsDefaultBrowserError)
		XCTAssertEqual(
			viewModel.defaultBrowserDescription,
			String(localized: .navigatorSettingsDefaultBrowserDescription)
		)
	}

	func testVersionDescriptionHandlesSingleValuesAndMissingValues() throws {
		let shortOnlyViewModel = try NavigatorSettingsViewModel(
			bundle: makeBundle(
				bundleIdentifier: "com.example.navigator",
				shortVersion: "2.0",
				buildNumber: nil
			)
		)
		let buildOnlyViewModel = try NavigatorSettingsViewModel(
			bundle: makeBundle(
				bundleIdentifier: "com.example.navigator",
				shortVersion: nil,
				buildNumber: "42"
			)
		)
		let missingViewModel = try NavigatorSettingsViewModel(
			bundle: makeBundle(
				bundleIdentifier: "com.example.navigator",
				shortVersion: nil,
				buildNumber: nil
			)
		)

		XCTAssertEqual(shortOnlyViewModel.versionDescription, "2.0")
		XCTAssertEqual(buildOnlyViewModel.versionDescription, "42")
		XCTAssertEqual(missingViewModel.versionDescription, "-")
	}

	func testImportFromChromeLoadsSnapshotAndMarksCompleted() async {
		let snapshot = makeImportedBrowserSnapshot(
			source: .chrome,
			tabURLs: [
				"https://navigator.example",
				"https://developer.apple.com",
			],
			selectedTabIndex: 1,
			bookmarkURLs: ["https://bookmarks.example"],
			historyURLs: ["https://history.example"]
		)
		var importedSnapshot: ImportedBrowserSnapshot?
		await withDependencies {
			$0.date.now = Date(timeIntervalSince1970: 1234)
		} operation: {
			let viewModel = NavigatorSettingsViewModel(
				bundle: .main,
				executeImport: makeImmediateImportExecution(result: .success(snapshot)),
				onImportedSnapshot: { importedSnapshot = $0 }
			)

			viewModel.importFromChrome()
			await waitUntil { importedSnapshot == snapshot }

			XCTAssertEqual(importedSnapshot, snapshot)
			XCTAssertEqual(viewModel.browserImportStatus, .completed(.chrome, snapshot.preview))
			XCTAssertFalse(viewModel.importSummaryText.isEmpty)
			XCTAssertTrue(viewModel.importSummaryText.contains("2"))
		}
	}

	func testImportSummaryUpdatesWhileProfilesStreamIn() async {
		await withDependencies {
			$0.date.now = Date(timeIntervalSince1970: 1234)
		} operation: {
			let controlledImport = ControlledImportExecution()
			let firstProfile = ImportedBrowserProfile(
				id: "Default",
				displayName: "Default",
				isDefault: true,
				windows: [
					ImportedBrowserWindow(
						id: "window-1",
						displayName: "Window 1",
						tabGroups: [
							ImportedTabGroup(
								id: "group-1",
								displayName: "Window 1",
								kind: .browserWindow,
								colorHex: nil,
								tabs: [
									ImportedTab(
										id: "tab-1",
										title: "Navigator",
										url: "https://navigator.example",
										isPinned: false,
										isFavorite: false,
										lastActiveAt: nil
									),
								]
							),
						],
						selectedTabID: "tab-1"
					),
				],
				bookmarkFolders: [],
				historyEntries: []
			)
			let finalSnapshot = ImportedBrowserSnapshot(
				source: .chrome,
				profiles: [firstProfile]
			)
			let viewModel = NavigatorSettingsViewModel(
				bundle: .main,
				executeImport: { _ in controlledImport.stream }
			)

			viewModel.importFromChrome()
			await waitForImportExecution()

			controlledImport.yield(.started(.chrome))
			controlledImport.yield(.profileImported(.chrome, firstProfile))
			await waitUntil {
				viewModel.importSummaryText.contains(
					"\(String(localized: .navigatorSettingsImportSummaryProfiles)): 1"
				)
			}

			XCTAssertEqual(viewModel.browserImportStatus, .importing(.chrome))
			XCTAssertEqual(
				viewModel.importSummaryText,
				[
					"\(String(localized: .navigatorSettingsImportSummaryImporting)) Chrome",
					"\(String(localized: .navigatorSettingsImportSummaryProfiles)): 1",
					"\(String(localized: .navigatorSettingsImportSummaryTabs)): 1",
					"\(String(localized: .navigatorSettingsImportSummaryBookmarks)): 0",
					"\(String(localized: .navigatorSettingsImportSummaryHistory)): 0",
				].joined(separator: "\n")
			)

			controlledImport.yield(.finished(finalSnapshot))
			controlledImport.finish()
			await waitUntil {
				viewModel.browserImportStatus == .completed(.chrome, finalSnapshot.preview)
			}

			XCTAssertEqual(viewModel.browserImportStatus, .completed(.chrome, finalSnapshot.preview))
		}
	}

	func testImportSummaryMergesRepeatedProfileChunksWhileStreaming() async {
		let controlledImport = ControlledImportExecution()
		let firstChunk = ImportedBrowserProfile(
			id: "Default",
			displayName: "Default",
			isDefault: true,
			windows: [
				ImportedBrowserWindow(
					id: "space-1",
					displayName: "Space 1",
					tabGroups: [
						ImportedTabGroup(
							id: "space-1-group",
							displayName: "Space 1",
							kind: .space,
							colorHex: nil,
							tabs: [
								ImportedTab(
									id: "tab-1",
									title: "One",
									url: "https://one.example",
									isPinned: true,
									isFavorite: false,
									lastActiveAt: nil
								),
							]
						),
					],
					selectedTabID: nil
				),
			],
			bookmarkFolders: [],
			historyEntries: []
		)
		let secondChunk = ImportedBrowserProfile(
			id: "Default",
			displayName: "Default",
			isDefault: true,
			windows: [
				ImportedBrowserWindow(
					id: "space-2",
					displayName: "Space 2",
					tabGroups: [
						ImportedTabGroup(
							id: "space-2-group",
							displayName: "Space 2",
							kind: .space,
							colorHex: nil,
							tabs: [
								ImportedTab(
									id: "tab-2",
									title: "Two",
									url: "https://two.example",
									isPinned: true,
									isFavorite: false,
									lastActiveAt: nil
								),
							]
						),
					],
					selectedTabID: nil
				),
			],
			bookmarkFolders: [],
			historyEntries: []
		)
		let viewModel = NavigatorSettingsViewModel(
			bundle: .main,
			executeImport: { _ in controlledImport.stream }
		)

		viewModel.importFromArc()
		await waitForImportExecution()

		controlledImport.yield(.started(.arc))
		controlledImport.yield(.profileImported(.arc, firstChunk))
		controlledImport.yield(.profileImported(.arc, secondChunk))

		await waitUntil {
			viewModel.importSummaryText.contains(
				"\(String(localized: .navigatorSettingsImportSummaryProfiles)): 1"
			) &&
				viewModel.importSummaryText.contains(
					"\(String(localized: .navigatorSettingsImportSummaryTabs)): 2"
				)
		}

		XCTAssertEqual(
			viewModel.importSummaryText,
			[
				"\(String(localized: .navigatorSettingsImportSummaryImporting)) Arc",
				"\(String(localized: .navigatorSettingsImportSummaryProfiles)): 1",
				"\(String(localized: .navigatorSettingsImportSummaryTabs)): 2",
				"\(String(localized: .navigatorSettingsImportSummaryBookmarks)): 0",
				"\(String(localized: .navigatorSettingsImportSummaryHistory)): 0",
			].joined(separator: "\n")
		)
	}

	func testImportFromBrowserSurfacesCoordinatorFailures() async {
		var failedSource: BrowserImportSource?
		let viewModel = NavigatorSettingsViewModel(
			bundle: .main,
			executeImport: makeImmediateImportExecution(
				result: .failure(BrowserImportError.browserNotInstalled(.arc))
			),
			onImportFailure: { failedSource = $0 }
		)

		viewModel.importFromArc()
		await waitUntil { viewModel.showsImportError }

		XCTAssertEqual(
			viewModel.browserImportStatus,
			NavigatorBrowserImportStatus.failed(
				BrowserImportError.browserNotInstalled(.arc).localizedDescription
			)
		)
		XCTAssertEqual(failedSource, .arc)
		XCTAssertTrue(viewModel.showsImportError)
	}

	func testImportStoresSnapshotAndOpenActionsFollowAvailability() async {
		var openedBookmarks = 0
		var openedHistory = 0
		let snapshot = makeImportedBrowserSnapshot(
			source: .safari,
			tabURLs: ["https://navigator.example"],
			bookmarkURLs: ["https://bookmarks.example"],
			historyURLs: ["https://history.example"]
		)

		await withDependencies {
			$0.date.now = Date(timeIntervalSince1970: 1234)
		} operation: {
			let viewModel = NavigatorSettingsViewModel(
				bundle: .main,
				executeImport: makeImmediateImportExecution(result: .success(snapshot)),
				onOpenImportedBookmarks: { openedBookmarks += 1 },
				onOpenImportedHistory: { openedHistory += 1 }
			)

			viewModel.importFromSafari()
			await waitUntil {
				viewModel.canOpenImportedBookmarks && viewModel.canOpenImportedHistory
			}
			viewModel.openImportedBookmarks()
			viewModel.openImportedHistory()

			XCTAssertTrue(viewModel.canOpenImportedBookmarks)
			XCTAssertTrue(viewModel.canOpenImportedHistory)
			XCTAssertEqual(openedBookmarks, 1)
			XCTAssertEqual(openedHistory, 1)
			XCTAssertTrue(viewModel.importSummaryText.contains("Safari"))
		}
	}

	func testStreamingImportEventsUpdateAppTabsBeforeCompletion() async {
		await withDependencies {
			$0.date.now = Date(timeIntervalSince1970: 1234)
		} operation: {
			let controlledImport = ControlledImportExecution()
			let appViewModel = AppViewModel()
			let importActions = NavigatorSettingsWindowActions(appViewModel: appViewModel)
			let finalSnapshot = makeImportedBrowserSnapshot(
				source: .chrome,
				tabURLs: ["https://imported.example"],
				bookmarkURLs: ["https://bookmark.example"],
				historyURLs: ["https://history.example"]
			)
			let importedProfile = finalSnapshot.profiles[0]
			let settingsViewModel = NavigatorSettingsViewModel(
				bundle: .main,
				executeImport: { _ in controlledImport.stream },
				onImportEvent: importActions.handleImportEvent(_:)
			)
			retainNavigatorSettingsTestObject(importActions)
			retainNavigatorSettingsTestObject(settingsViewModel)

			settingsViewModel.importFromChrome()
			await waitForImportExecution()
			controlledImport.yield(.started(.chrome))
			controlledImport.yield(.profileImported(.chrome, importedProfile))
			await waitUntil {
				appViewModel.sidebarViewModel.tabs.map(\.currentURL) == [
					"https://navigator.zip",
					"https://imported.example",
				]
			}

			XCTAssertEqual(settingsViewModel.browserImportStatus, .importing(.chrome))
			XCTAssertEqual(
				appViewModel.sidebarViewModel.tabs.map(\.currentURL),
				[
					"https://navigator.zip",
					"https://imported.example",
				]
			)

			controlledImport.yield(.finished(finalSnapshot))
			controlledImport.finish()
			await waitUntil {
				settingsViewModel.browserImportStatus == .completed(.chrome, finalSnapshot.preview)
			}

			XCTAssertEqual(settingsViewModel.browserImportStatus, .completed(.chrome, finalSnapshot.preview))

			importActions.openImportedBookmarks()
			XCTAssertEqual(
				appViewModel.sidebarViewModel.tabs.map(\.currentURL),
				[
					"https://bookmark.example",
					"https://imported.example",
				]
			)

			importActions.openImportedHistory()
			XCTAssertEqual(
				appViewModel.sidebarViewModel.tabs.map(\.currentURL),
				[
					"https://history.example",
					"https://imported.example",
				]
			)
		}
	}

	func testBrowserImportCoordinatorStreamEmitsSnapshotLifecycleEvents() async throws {
		let snapshot = makeImportedBrowserSnapshot(
			source: .chrome,
			tabURLs: ["https://executor.example"],
			bookmarkURLs: ["https://executor-bookmark.example"]
		)
		let coordinator = makeImportCoordinator(snapshot: snapshot)
		let selection = BrowserImportSelection(
			source: .chrome,
			profileIDs: [],
			dataKinds: BrowserImportDataKind.allCases,
			conflictMode: .replaceCurrentData
		)

		var events = [BrowserImportEvent]()
		for try await event in coordinator.streamImport(for: selection) {
			events.append(event)
		}

		XCTAssertEqual(
			events,
			[
				.started(.chrome),
				.profileImported(.chrome, snapshot.profiles[0]),
				.finished(snapshot),
			]
		)
	}

	func testDefaultExecuteImportUsesCoordinatorWhenNoOverrideIsProvided() async {
		let snapshot = makeImportedBrowserSnapshot(
			source: .chrome,
			tabURLs: ["https://coordinator.example"]
		)
		await withDependencies {
			$0.date.now = Date(timeIntervalSince1970: 1234)
		} operation: {
			let viewModel = NavigatorSettingsViewModel(
				bundle: .main,
				browserImportCoordinator: makeImportCoordinator(snapshot: snapshot)
			)

			viewModel.importFromChrome()
			for _ in 0..<10 {
				await waitForImportExecution()
				if case .completed = viewModel.browserImportStatus {
					break
				}
			}

			XCTAssertEqual(viewModel.browserImportStatus, .completed(.chrome, snapshot.preview))
		}
	}

	func testBrowserImportRequestsMergeConflictModeAndSkipsHistoryByDefault() async {
		var receivedSelection: BrowserImportSelection?
		let viewModel = NavigatorSettingsViewModel(
			bundle: .main,
			executeImport: { selection in
				receivedSelection = selection
				return AsyncThrowingStream { continuation in
					continuation.finish()
				}
			}
		)

		viewModel.importFromArc()
		await waitForImportExecution()

		XCTAssertEqual(receivedSelection?.source, .arc)
		XCTAssertEqual(receivedSelection?.dataKinds, [.tabs, .bookmarks])
		XCTAssertEqual(receivedSelection?.conflictMode, .merge)
	}

	func testOpenImportedActionsAreNoOpsWithoutImportedData() {
		var openedBookmarks = 0
		var openedHistory = 0
		let viewModel = NavigatorSettingsViewModel(
			bundle: .main,
			onOpenImportedBookmarks: { openedBookmarks += 1 },
			onOpenImportedHistory: { openedHistory += 1 }
		)

		viewModel.openImportedBookmarks()
		viewModel.openImportedHistory()

		XCTAssertEqual(openedBookmarks, 0)
		XCTAssertEqual(openedHistory, 0)
	}

	func testWhitespaceMetadataFallsBackToDashValues() async throws {
		let viewModel = try NavigatorSettingsViewModel(
			bundle: makeBundle(
				bundleIdentifier: "  ",
				shortVersion: " \n ",
				buildNumber: "\t"
			)
		)

		XCTAssertEqual(viewModel.versionDescription, "-")
		await viewModel.setAsDefaultBrowser()
		XCTAssertEqual(viewModel.defaultBrowserStatus, .updateFailed)
	}

	func testImportFromBrowserIgnoresRequestsWhileAnotherImportIsInProgress() {
		var executeImportCallCount = 0
		let viewModel = NavigatorSettingsViewModel(
			bundle: .main,
			executeImport: { _ in
				executeImportCallCount += 1
				return AsyncThrowingStream { continuation in
					continuation.yield(.started(.safari))
				}
			}
		)
		viewModel.browserImportStatus = .importing(.chrome)

		viewModel.importFromSafari()

		XCTAssertEqual(executeImportCallCount, 0)
		XCTAssertEqual(viewModel.browserImportStatus, .importing(.chrome))
	}

	func testSettingsWindowShortcutResolverOnlyClosesForCommandW() {
		XCTAssertTrue(
			NavigatorSettingsWindowShortcutResolver.shouldClose(
				modifiers: [.command],
				normalizedCharacter: "w",
				rawCharacter: "w"
			)
		)
		XCTAssertFalse(
			NavigatorSettingsWindowShortcutResolver.shouldClose(
				modifiers: [.command, .shift],
				normalizedCharacter: "w",
				rawCharacter: "w"
			)
		)
		XCTAssertFalse(
			NavigatorSettingsWindowShortcutResolver.shouldClose(
				modifiers: [.command],
				normalizedCharacter: "q",
				rawCharacter: "q"
			)
		)
		XCTAssertTrue(
			NavigatorSettingsWindowShortcutResolver.shouldClose(
				modifiers: [.command],
				normalizedCharacter: nil,
				rawCharacter: "w"
			)
		)
	}
}

@MainActor
final class AppViewModelTests: XCTestCase {
	override func setUp() {
		super.setUp()
		installCoverageTestApplicationDelegate()
		clearStoredBrowserTabState()
		clearImportedBrowserLibrary()
	}

	override func tearDown() {
		closeAllCoverageTestWindows()
		clearStoredBrowserTabState()
		clearImportedBrowserLibrary()
		super.tearDown()
	}

	func testOpenExternalURLsReplacesSelectedTabWithFirstURL() {
		let viewModel = AppViewModel()

		viewModel.openExternalURLs(["https://swift.org"])

		XCTAssertEqual(viewModel.sidebarViewModel.selectedTabCurrentURL, "https://swift.org")
		XCTAssertEqual(viewModel.sidebarViewModel.tabs.count, 1)
	}

	func testOpenIncomingURLsInNewTabsPreservesCurrentTabAndSelectsOpenedURL() {
		let viewModel = AppViewModel()

		viewModel.openIncomingURLsInNewTabs(["https://swift.org"])

		XCTAssertEqual(
			viewModel.sidebarViewModel.tabs.map(\.currentURL),
			["https://navigator.zip", "https://swift.org"]
		)
		XCTAssertEqual(viewModel.sidebarViewModel.selectedTabCurrentURL, "https://swift.org")
	}

	func testOpenIncomingURLsInNewTabsAppendsMultipleURLsAndSelectsLastOpenedTab() {
		let viewModel = AppViewModel()

		viewModel.openIncomingURLsInNewTabs([
			"https://swift.org",
			"https://developer.apple.com",
			"file:///tmp/example.html",
		])

		XCTAssertEqual(viewModel.sidebarViewModel.tabs.map(\.currentURL), [
			"https://navigator.zip",
			"https://swift.org",
			"https://developer.apple.com",
			"file:///tmp/example.html",
		])
		XCTAssertEqual(viewModel.sidebarViewModel.selectedTabCurrentURL, "file:///tmp/example.html")
	}

	func testOpenIncomingURLsInNewTabsCreatesSelectionFromEmptySidebarState() {
		let viewModel = AppViewModel()
		viewModel.sidebarViewModel.clearTabs()

		viewModel.openIncomingURLsInNewTabs(["https://swift.org"])

		XCTAssertEqual(viewModel.sidebarViewModel.tabs.map(\.currentURL), ["https://swift.org"])
		XCTAssertEqual(viewModel.sidebarViewModel.selectedTabCurrentURL, "https://swift.org")
	}

	func testOpenExternalURLsOpensAdditionalURLsInNewTabs() {
		let viewModel = AppViewModel()

		viewModel.openExternalURLs([
			"https://swift.org",
			"https://developer.apple.com",
			"file:///tmp/example.html",
		])

		XCTAssertEqual(viewModel.sidebarViewModel.tabs.map(\.currentURL), [
			"https://swift.org",
			"https://developer.apple.com",
			"file:///tmp/example.html",
		])
		XCTAssertEqual(viewModel.sidebarViewModel.selectedTabCurrentURL, "file:///tmp/example.html")
	}

	func testBrowserActionBarCommandActionsPresentLocationAndNewTabModes() {
		let viewModel = AppViewModel()

		viewModel.browserActionBarCommandActions.openLocationBar()
		XCTAssertTrue(viewModel.browserActionBarViewModel.isPresented)
		XCTAssertEqual(viewModel.browserActionBarViewModel.mode, .currentTab)
		XCTAssertEqual(viewModel.browserActionBarViewModel.query, "https://navigator.zip")

		viewModel.browserActionBarCommandActions.openNewTabBar()
		XCTAssertTrue(viewModel.browserActionBarViewModel.isPresented)
		XCTAssertEqual(viewModel.browserActionBarViewModel.mode, .newTab)
		XCTAssertEqual(viewModel.browserActionBarViewModel.query, "")
	}

	func testPresentLocationActionBarFallsBackToAddressTextWithoutSelection() {
		let viewModel = AppViewModel()
		viewModel.sidebarViewModel.closeSelectedTab()
		viewModel.sidebarViewModel.addressText = "typed.example"

		viewModel.presentLocationActionBar()

		XCTAssertEqual(viewModel.browserActionBarViewModel.mode, .currentTab)
		XCTAssertEqual(viewModel.browserActionBarViewModel.query, "typed.example")
	}

	func testPresentNewTabActionBarPresentsNewTabMode() {
		let viewModel = AppViewModel()

		viewModel.presentNewTabActionBar()

		XCTAssertTrue(viewModel.browserActionBarViewModel.isPresented)
		XCTAssertEqual(viewModel.browserActionBarViewModel.mode, .newTab)
	}

	func testPresentToastStoresTitleAndBody() {
		let viewModel = AppViewModel()

		viewModel.presentToast(
			title: .navigatorToastCopyCurrentTabURLTitle,
			body: .navigatorToastCopyCurrentTabURLBody
		)

		XCTAssertNotNil(viewModel.toast)
		XCTAssertEqual(
			String(localized: viewModel.toastTitle),
			String(localized: LocalizedStringResource.navigatorToastCopyCurrentTabURLTitle)
		)
		XCTAssertEqual(
			viewModel.toastBody,
			String(localized: LocalizedStringResource.navigatorToastCopyCurrentTabURLBody)
		)
	}

	func testPresentToastWithTitleOnlyClearsBody() {
		let viewModel = AppViewModel()

		viewModel.presentToast(title: .navigatorToastCopyCurrentTabURLTitle)

		XCTAssertNotNil(viewModel.toast)
		XCTAssertNil(viewModel.toastBody)
	}

	func testToastDismissalClearsToastAndBody() async {
		let viewModel = AppViewModel()
		viewModel.presentToast(
			title: .navigatorToastCopyCurrentTabURLTitle,
			body: .navigatorToastCopyCurrentTabURLBody
		)
		let toast = try? XCTUnwrap(viewModel.toast)

		await toast?.didRequestDismissal()

		XCTAssertNil(viewModel.toast)
		XCTAssertNil(viewModel.toastBody)
	}

	func testSpacesReturnsStoredSpacesOrderedByOrderKey() {
		withInMemoryStoredBrowserTabState(
			StoredBrowserTabCollection(
				activeSpaceID: "space-two",
				spaces: [
					StoredBrowserSpace(id: "space-two", name: "Two", orderKey: "00000001"),
					StoredBrowserSpace(id: "space-one", name: "One", orderKey: "00000000"),
				],
				tabs: []
			)
		) {
			let viewModel = AppViewModel()

			XCTAssertEqual(viewModel.spaces.map(\.id), ["space-one", "space-two"])
		}
	}

	func testBrowserActionBarPrimaryActionsDriveSidebarNavigation() {
		let viewModel = AppViewModel()

		viewModel.presentLocationActionBar()
		viewModel.browserActionBarViewModel.performPrimaryAction(with: "swift.org")
		XCTAssertEqual(viewModel.sidebarViewModel.selectedTabCurrentURL, "https://swift.org")

		viewModel.presentNewTabActionBar()
		viewModel.browserActionBarViewModel.performPrimaryAction(with: "developer.apple.com")
		XCTAssertEqual(
			viewModel.sidebarViewModel.tabs.map(\.currentURL),
			["https://swift.org", "https://developer.apple.com"]
		)
	}

	func testSidebarNoopActionsAreCallable() {
		let viewModel = AppViewModel()

		viewModel.sidebarViewModel.goBack()
		viewModel.sidebarViewModel.goForward()
		viewModel.sidebarViewModel.reload()

		XCTAssertEqual(viewModel.sidebarViewModel.selectedTabCurrentURL, "https://navigator.zip")
	}

	func testOpenExternalURLsIgnoresEmptyInput() {
		let viewModel = AppViewModel()

		viewModel.openExternalURLs([])
		viewModel.openExternalURLs([""])

		XCTAssertEqual(viewModel.sidebarViewModel.tabs.map(\.currentURL), ["https://navigator.zip"])
	}

	func testImportBrowserSnapshotReplacesTabsAndPreservesSelectedImportedTab() {
		withDependencies {
			$0.date.now = Date(timeIntervalSince1970: 1234)
		} operation: {
			let viewModel = AppViewModel()
			let snapshot = makeImportedBrowserSnapshot(
				source: .chrome,
				tabURLs: [
					"https://first.example",
					"https://selected.example",
					"https://third.example",
				],
				selectedTabIndex: 1
			)

			viewModel.importBrowserSnapshot(snapshot)

			XCTAssertEqual(
				viewModel.sidebarViewModel.tabs.map(\.currentURL),
				[
					"https://first.example",
					"https://selected.example",
					"https://third.example",
				]
			)
			XCTAssertEqual(viewModel.sidebarViewModel.selectedTabCurrentURL, "https://selected.example")
		}
	}

	func testImportBrowserSnapshotCreatesSeparateSpacesPerImportedWindow() {
		withDependencies {
			$0.date.now = Date(timeIntervalSince1970: 1234)
		} operation: {
			let viewModel = AppViewModel()
			let snapshot = ImportedBrowserSnapshot(
				source: .chrome,
				profiles: [
					ImportedBrowserProfile(
						id: "Default",
						displayName: "Default",
						isDefault: true,
						windows: [
							ImportedBrowserWindow(
								id: "window-a",
								displayName: "Window A",
								tabGroups: [
									ImportedTabGroup(
										id: "group-a",
										displayName: "Group A",
										kind: .browserWindow,
										colorHex: nil,
										tabs: [
											ImportedTab(
												id: "tab-a1",
												title: "A1",
												url: "https://window-a.example",
												isPinned: false,
												isFavorite: false,
												lastActiveAt: nil
											),
										]
									),
								],
								selectedTabID: "tab-a1"
							),
							ImportedBrowserWindow(
								id: "window-b",
								displayName: "Window B",
								tabGroups: [
									ImportedTabGroup(
										id: "group-b",
										displayName: "Group B",
										kind: .browserWindow,
										colorHex: nil,
										tabs: [
											ImportedTab(
												id: "tab-b1",
												title: "B1",
												url: "https://window-b.example",
												isPinned: false,
												isFavorite: false,
												lastActiveAt: nil
											),
										]
									),
								],
								selectedTabID: nil
							),
						],
						bookmarkFolders: [],
						historyEntries: []
					),
				]
			)

			viewModel.importBrowserSnapshot(snapshot)

			@Shared(.navigatorStoredBrowserTabs) var storedTabs = .empty
			XCTAssertEqual(storedTabs.spaces.count, 2)
			XCTAssertEqual(Set(storedTabs.tabs.map(\.spaceID)).count, 2)
			XCTAssertEqual(viewModel.sidebarViewModel.tabs.map(\.currentURL), ["https://window-a.example"])
		}
	}

	func testImportBrowserSnapshotGlobalizesPinnedTabsAcrossSpaces() {
		withDependencies {
			$0.date.now = Date(timeIntervalSince1970: 1234)
		} operation: {
			let viewModel = AppViewModel()
			let snapshot = ImportedBrowserSnapshot(
				source: .arc,
				profiles: [
					ImportedBrowserProfile(
						id: "Default",
						displayName: "Default",
						isDefault: true,
						windows: [
							ImportedBrowserWindow(
								id: "window-a",
								displayName: "Window A",
								tabGroups: [
									ImportedTabGroup(
										id: "group-a",
										displayName: "Group A",
										kind: .space,
										colorHex: nil,
										tabs: [
											ImportedTab(
												id: "tab-a1",
												title: "Pinned A1",
												url: "https://window-a-pinned.example",
												isPinned: true,
												isFavorite: false,
												lastActiveAt: nil
											),
										]
									),
								],
								selectedTabID: "tab-a1"
							),
							ImportedBrowserWindow(
								id: "window-b",
								displayName: "Window B",
								tabGroups: [
									ImportedTabGroup(
										id: "group-b",
										displayName: "Group B",
										kind: .space,
										colorHex: nil,
										tabs: [
											ImportedTab(
												id: "tab-b1",
												title: "Pinned B1",
												url: "https://window-b-pinned.example",
												isPinned: true,
												isFavorite: false,
												lastActiveAt: nil
											),
										]
									),
								],
								selectedTabID: "tab-b1"
							),
						],
						bookmarkFolders: [],
						historyEntries: []
					),
				]
			)

			viewModel.importBrowserSnapshot(snapshot)

			XCTAssertEqual(viewModel.spaces.count, 2)
			XCTAssertEqual(
				viewModel.sidebarViewModel.tabs.map(\.currentURL),
				[
					"https://window-a-pinned.example",
					"https://window-b-pinned.example",
				]
			)
			viewModel.switchSpace(to: importedSpaceID(profileID: "Default", windowID: "window-b"))
			XCTAssertEqual(
				viewModel.sidebarViewModel.tabs.map(\.currentURL),
				[
					"https://window-a-pinned.example",
					"https://window-b-pinned.example",
				]
			)
		}
	}

	func testImportBrowserSnapshotUsesProfileNameWhenWindowNameIsEmpty() {
		withDependencies {
			$0.date.now = Date(timeIntervalSince1970: 1234)
		} operation: {
			let viewModel = AppViewModel()
			let snapshot = ImportedBrowserSnapshot(
				source: .arc,
				profiles: [
					ImportedBrowserProfile(
						id: "default",
						displayName: "Profile Name",
						isDefault: true,
						windows: [
							ImportedBrowserWindow(
								id: "window-empty-name",
								displayName: "",
								tabGroups: [
									ImportedTabGroup(
										id: "group",
										displayName: "Group",
										kind: .browserWindow,
										colorHex: nil,
										tabs: [
											ImportedTab(
												id: "tab",
												title: "Tab",
												url: "https://example.com",
												isPinned: false,
												isFavorite: false,
												lastActiveAt: nil
											),
										]
									),
								],
								selectedTabID: "tab"
							),
						],
						bookmarkFolders: [],
						historyEntries: []
					),
				]
			)

			viewModel.importBrowserSnapshot(snapshot)

			@Shared(.navigatorStoredBrowserTabs) var storedTabs = .empty
			XCTAssertEqual(storedTabs.spaces.first?.name, "Profile Name")
		}
	}

	func testImportBrowserSnapshotSeedsImportedTitlesIntoLiveSidebar() {
		withDependencies {
			$0.date.now = Date(timeIntervalSince1970: 1234)
		} operation: {
			let viewModel = AppViewModel()
			let snapshot = makeImportedBrowserSnapshot(
				source: .arc,
				tabURLs: [
					"https://resources.arc.net/",
					"https://arc.net/max/tutorial",
				],
				tabTitles: [
					"Arc Resources",
					"Try Arc Max",
				]
			)

			viewModel.importBrowserSnapshot(snapshot)

			XCTAssertEqual(
				viewModel.sidebarViewModel.tabs.map(\.pageTitle),
				[
					"Arc Resources",
					"Try Arc Max",
				]
			)
			XCTAssertEqual(
				viewModel.sidebarViewModel.tabs.map(\.displayTitle),
				[
					"Arc Resources",
					"Try Arc Max",
				]
			)
		}
	}

	func testInitHydratesImportedTabsFromPersistedLibraryOnColdStart() {
		withDependencies {
			$0.date.now = Date(timeIntervalSince1970: 1234)
		} operation: {
			let initialViewModel = AppViewModel()
			initialViewModel.importBrowserSnapshot(
				makeImportedBrowserSnapshot(
					source: .safari,
					tabURLs: [
						"https://persisted.example",
						"https://selected.example",
					],
					selectedTabIndex: 1
				)
			)

			let hydratedViewModel = AppViewModel()

			XCTAssertEqual(
				hydratedViewModel.sidebarViewModel.tabs.map(\.currentURL),
				[
					"https://persisted.example",
					"https://selected.example",
				]
			)
			XCTAssertEqual(hydratedViewModel.sidebarViewModel.selectedTabCurrentURL, "https://selected.example")
		}
	}

	func testInitHydratesStoredTabsBeforeImportedLibraryFallback() throws {
		try withInMemoryStoredBrowserTabState(
			StoredBrowserTabCollection(
				tabs: [
					StoredBrowserTab(
						id: XCTUnwrap(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")),
						objectVersion: 2,
						orderKey: "00000000",
						url: "https://stored.example",
						title: "Stored",
						faviconURL: "https://stored.example/favicon.ico"
					),
					StoredBrowserTab(
						id: XCTUnwrap(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")),
						objectVersion: 1,
						orderKey: "00000001",
						url: "https://selected.example",
						title: "Selected"
					),
				]
			),
			selection: StoredBrowserTabSelection(
				selectedTabID: XCTUnwrap(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))
			),
			importedBrowserLibrary: ImportedBrowserLibrary(
				records: [
					ImportedBrowserLibraryRecord(
						snapshot: makeImportedBrowserSnapshot(
							source: .safari,
							tabURLs: ["https://imported.example"]
						),
						importedAt: Date(timeIntervalSince1970: 1234)
					),
				]
			)
		) {
			let viewModel = AppViewModel()

			XCTAssertEqual(
				viewModel.sidebarViewModel.tabs.map(\.id.uuidString),
				[
					"AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
					"BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
				]
			)
			XCTAssertEqual(
				viewModel.sidebarViewModel.tabs.map(\.currentURL),
				["https://stored.example", "https://selected.example"]
			)
			XCTAssertEqual(viewModel.sidebarViewModel.selectedTabCurrentURL, "https://selected.example")
			XCTAssertEqual(viewModel.sidebarViewModel.tabs[0].pageTitle, "Stored")
			XCTAssertEqual(
				viewModel.sidebarViewModel.tabs[0].faviconURL,
				"https://stored.example/favicon.ico"
			)
		}
	}

	func testInitHydratesSelectedSpaceFromStoredSelection() throws {
		try withInMemoryStoredBrowserTabState(
			StoredBrowserTabCollection(
				activeSpaceID: "space-one",
				spaces: [
					StoredBrowserSpace(
						id: "space-one",
						name: "One",
						orderKey: "00000000"
					),
					StoredBrowserSpace(
						id: "space-two",
						name: "Two",
						orderKey: "00000001"
					),
				],
				tabs: [
					StoredBrowserTab(
						id: XCTUnwrap(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")),
						objectVersion: 1,
						orderKey: "00000000",
						spaceID: "space-one",
						url: "https://space-one.example"
					),
					StoredBrowserTab(
						id: XCTUnwrap(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")),
						objectVersion: 1,
						orderKey: "00000000",
						spaceID: "space-two",
						url: "https://space-two.example"
					),
				]
			),
			selection: StoredBrowserTabSelection(
				selectedSpaceID: "space-two",
				selectedTabID: XCTUnwrap(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))
			)
		) {
			let viewModel = AppViewModel()

			XCTAssertEqual(viewModel.activeSpaceID, "space-two")
			XCTAssertEqual(viewModel.sidebarViewModel.tabs.map(\.currentURL), ["https://space-two.example"])
		}
	}

	func testInitUsesStoredActiveSpaceWhenSelectionCollectionDoesNotMatch() {
		withInMemoryStoredBrowserTabState(
			StoredBrowserTabCollection(
				activeSpaceID: "space-two",
				spaces: [
					StoredBrowserSpace(id: "space-one", name: "One", orderKey: "00000000"),
					StoredBrowserSpace(id: "space-two", name: "Two", orderKey: "00000001"),
				],
				tabs: [
					StoredBrowserTab(
						id: BrowserTabID(),
						objectVersion: 1,
						orderKey: "00000000",
						spaceID: "space-two",
						url: "https://space-two.example"
					),
				]
			),
			selection: StoredBrowserTabSelection(
				collectionID: "different-collection",
				selectedSpaceID: "space-one",
				selectedTabID: nil
			)
		) {
			let viewModel = AppViewModel()

			XCTAssertEqual(viewModel.activeSpaceID, "space-two")
			XCTAssertEqual(viewModel.sidebarViewModel.tabs.map(\.currentURL), ["https://space-two.example"])
		}
	}

	func testInitUsesSpaceMetadataSelectionWhenStoredSelectionIsForDifferentSpace() throws {
		try withInMemoryStoredBrowserTabState(
			StoredBrowserTabCollection(
				activeSpaceID: "space-two",
				spaces: [
					StoredBrowserSpace(id: "space-one", name: "One", orderKey: "00000000"),
					StoredBrowserSpace(
						id: "space-two",
						name: "Two",
						orderKey: "00000001",
						selectedTabID: XCTUnwrap(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))
					),
				],
				tabs: [
					StoredBrowserTab(
						id: XCTUnwrap(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")),
						objectVersion: 1,
						orderKey: "00000000",
						spaceID: "space-two",
						isPinned: true,
						url: "https://pinned.example"
					),
					StoredBrowserTab(
						id: XCTUnwrap(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")),
						objectVersion: 1,
						orderKey: "00000001",
						spaceID: "space-two",
						url: "https://selected.example"
					),
				]
			),
			selection: StoredBrowserTabSelection(
				collectionID: "different-collection",
				selectedSpaceID: "space-one",
				selectedTabID: nil
			)
		) {
			let viewModel = AppViewModel()

			XCTAssertEqual(viewModel.sidebarViewModel.selectedTabCurrentURL, "https://selected.example")
		}
	}

	func testInitFallsBackToFirstPinnedTabWhenSelectionIsMissing() throws {
		try withInMemoryStoredBrowserTabState(
			StoredBrowserTabCollection(
				activeSpaceID: "space-one",
				spaces: [
					StoredBrowserSpace(id: "space-one", name: "One", orderKey: "00000000"),
				],
				tabs: [
					StoredBrowserTab(
						id: XCTUnwrap(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")),
						objectVersion: 1,
						orderKey: "00000000",
						spaceID: "space-one",
						isPinned: true,
						url: "https://pinned.example"
					),
					StoredBrowserTab(
						id: XCTUnwrap(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")),
						objectVersion: 1,
						orderKey: "00000001",
						spaceID: "space-one",
						url: "https://second.example"
					),
				]
			),
			selection: StoredBrowserTabSelection(
				selectedSpaceID: "space-one",
				selectedTabID: BrowserTabID()
			)
		) {
			let viewModel = AppViewModel()

			XCTAssertEqual(viewModel.sidebarViewModel.selectedTabCurrentURL, "https://pinned.example")
		}
	}

	func testTabMutationsPersistStoredTabsAndDeviceLocalSelection() {
		withInMemoryStoredBrowserTabState(.empty) {
			let viewModel = AppViewModel()

			viewModel.openIncomingURLsInNewTabs([
				"https://swift.org",
				"https://developer.apple.com",
			])
			viewModel.sidebarViewModel.selectTab(id: viewModel.sidebarViewModel.tabs[0].id)

			@Shared(.navigatorStoredBrowserTabs) var storedTabs = .empty
			@Shared(.navigatorStoredBrowserTabSelection) var storedSelection = .empty

			XCTAssertTrue(storedTabs.hasStoredState)
			XCTAssertEqual(
				storedTabs.tabs.map(\.url),
				[
					"https://navigator.zip",
					"https://swift.org",
					"https://developer.apple.com",
				]
			)
			XCTAssertEqual(
				storedTabs.tabs.map(\.orderKey),
				["00000000", "00000001", "00000002"]
			)
			XCTAssertEqual(Set(storedTabs.tabs.map(\.spaceID)), [StoredBrowserTabCollection.defaultSpaceID])
			XCTAssertEqual(storedTabs.activeSpaceID, StoredBrowserTabCollection.defaultSpaceID)
			XCTAssertEqual(storedTabs.spaces.map(\.id), [StoredBrowserTabCollection.defaultSpaceID])
			XCTAssertEqual(storedSelection.selectedSpaceID, StoredBrowserTabCollection.defaultSpaceID)
			XCTAssertEqual(storedSelection.selectedTabID, viewModel.sidebarViewModel.tabs[0].id)
		}
	}

	func testCreateAndSwitchSpacePersistsTabsPerSpace() {
		withInMemoryStoredBrowserTabState(.empty) {
			let viewModel = AppViewModel()
			viewModel.sidebarViewModel.navigateSelectedTab(to: "https://space-one.example")

			let secondSpaceID = viewModel.createSpace(name: "Second", initialURL: "https://space-two.example")

			XCTAssertEqual(viewModel.activeSpaceID, secondSpaceID)
			XCTAssertEqual(viewModel.sidebarViewModel.tabs.map(\.currentURL), ["https://space-two.example"])

			viewModel.switchSpace(to: StoredBrowserTabCollection.defaultSpaceID)

			XCTAssertEqual(viewModel.sidebarViewModel.tabs.map(\.currentURL), ["https://space-one.example"])
			@Shared(.navigatorStoredBrowserTabs) var storedTabs = .empty
			XCTAssertEqual(Set(storedTabs.spaces.map(\.id)), [StoredBrowserTabCollection.defaultSpaceID, secondSpaceID])
			XCTAssertEqual(
				Set(storedTabs.tabs.map(\.spaceID)),
				[StoredBrowserTabCollection.defaultSpaceID, secondSpaceID]
			)
		}
	}

	func testPinnedTabsRemainVisibleAcrossAllSpaces() throws {
		try withInMemoryStoredBrowserTabState(.empty) {
			let viewModel = AppViewModel()
			let pinnedTabID = try XCTUnwrap(viewModel.sidebarViewModel.selectedTabID)
			viewModel.sidebarViewModel.pinTab(id: pinnedTabID)
			viewModel.sidebarViewModel.replacePinnedTabURLWithCurrentURL(id: pinnedTabID)

			let secondSpaceID = viewModel.createSpace(name: "Second", initialURL: "https://space-two.example")
			XCTAssertEqual(
				viewModel.sidebarViewModel.tabs.map(\.currentURL),
				[
					"https://navigator.zip",
					"https://space-two.example",
				]
			)

			viewModel.switchSpace(to: StoredBrowserTabCollection.defaultSpaceID)
			XCTAssertEqual(
				viewModel.sidebarViewModel.tabs.map(\.currentURL),
				[
					"https://navigator.zip",
				]
			)
			viewModel.switchSpace(to: secondSpaceID)
			XCTAssertEqual(
				viewModel.sidebarViewModel.tabs.map(\.currentURL),
				[
					"https://navigator.zip",
					"https://space-two.example",
				]
			)
		}
	}

	func testCreateSpaceUsesDefaultInitialAddressWhenNoInitialURLProvided() {
		withInMemoryStoredBrowserTabState(.empty) {
			let viewModel = AppViewModel()

			_ = viewModel.createSpace(name: "No URL")

			XCTAssertEqual(viewModel.sidebarViewModel.selectedTabCurrentURL, "https://navigator.zip")
		}
	}

	func testDeleteActiveSpaceFallsBackToRemainingSpace() {
		withInMemoryStoredBrowserTabState(.empty) {
			let viewModel = AppViewModel()
			viewModel.sidebarViewModel.navigateSelectedTab(to: "https://default-space.example")
			let secondSpaceID = viewModel.createSpace(name: "Second", initialURL: "https://second-space.example")

			viewModel.deleteSpace(id: secondSpaceID)

			XCTAssertEqual(viewModel.activeSpaceID, StoredBrowserTabCollection.defaultSpaceID)
			XCTAssertEqual(viewModel.sidebarViewModel.tabs.map(\.currentURL), ["https://default-space.example"])

			@Shared(.navigatorStoredBrowserTabs) var storedTabs = .empty
			XCTAssertEqual(storedTabs.spaces.map(\.id), [StoredBrowserTabCollection.defaultSpaceID])
			XCTAssertEqual(Set(storedTabs.tabs.map(\.spaceID)), [StoredBrowserTabCollection.defaultSpaceID])
		}
	}

	func testDeletingOnlySpaceRecreatesDefaultSpaceAndDefaultTab() {
		withInMemoryStoredBrowserTabState(.empty) {
			let viewModel = AppViewModel()
			viewModel.deleteSpace(id: StoredBrowserTabCollection.defaultSpaceID)

			XCTAssertEqual(viewModel.activeSpaceID, StoredBrowserTabCollection.defaultSpaceID)
			XCTAssertEqual(viewModel.sidebarViewModel.tabs.map(\.currentURL), ["https://navigator.zip"])

			@Shared(.navigatorStoredBrowserTabs) var storedTabs = .empty
			XCTAssertEqual(storedTabs.spaces.map(\.id), [StoredBrowserTabCollection.defaultSpaceID])
		}
	}

	func testRenameSpaceUpdatesStoredSpaceMetadata() {
		withInMemoryStoredBrowserTabState(.empty) {
			let viewModel = AppViewModel()
			let secondSpaceID = viewModel.createSpace(name: "Old Name", initialURL: "https://space-two.example")

			viewModel.renameSpace(id: secondSpaceID, name: "Renamed Space")

			@Shared(.navigatorStoredBrowserTabs) var storedTabs = .empty
			XCTAssertEqual(
				storedTabs.spaces.first(where: { $0.id == secondSpaceID })?.name,
				"Renamed Space"
			)
		}
	}

	func testSwitchAndDeleteSpaceIgnoreUnknownIdentifiers() {
		withInMemoryStoredBrowserTabState(.empty) {
			let viewModel = AppViewModel()
			let previousActiveSpaceID = viewModel.activeSpaceID
			let previousURLs = viewModel.sidebarViewModel.tabs.map(\.currentURL)

			viewModel.switchSpace(to: "missing-space")
			viewModel.deleteSpace(id: "missing-space")

			XCTAssertEqual(viewModel.activeSpaceID, previousActiveSpaceID)
			XCTAssertEqual(viewModel.sidebarViewModel.tabs.map(\.currentURL), previousURLs)
		}
	}

	func testPersistCurrentTabsRepairsMissingActiveSpaceAndSortsStableWhenOrderKeysMatch() throws {
		try withInMemoryStoredBrowserTabState(.empty) {
			let viewModel = AppViewModel()
			let activeSpaceID = viewModel.activeSpaceID
			let otherSpaceFirstID = try XCTUnwrap(UUID(uuidString: "99999999-9999-9999-9999-999999999999"))
			let otherSpaceSecondID = try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))

			@Shared(.navigatorStoredBrowserTabs) var storedTabs = .empty
			$storedTabs.withLock { value in
				value = StoredBrowserTabCollection(
					activeSpaceID: "other-space",
					spaces: [
						StoredBrowserSpace(
							id: "other-space",
							name: "Other",
							orderKey: "00000000"
						),
					],
					tabs: [
						StoredBrowserTab(
							id: otherSpaceFirstID,
							objectVersion: 1,
							orderKey: "00000000",
							spaceID: "other-space",
							url: "https://other-two.example"
						),
						StoredBrowserTab(
							id: otherSpaceSecondID,
							objectVersion: 1,
							orderKey: "00000000",
							spaceID: "other-space",
							url: "https://other-one.example"
						),
					]
				)
			}

			viewModel.openIncomingURLsInNewTabs(["https://active-space.example"])

			let repairedStoredTabs = $storedTabs.withLock { value in value }
			XCTAssertTrue(repairedStoredTabs.spaces.contains(where: { $0.id == activeSpaceID }))
			let repairedOtherSpaceTabs = repairedStoredTabs.tabs.filter { $0.spaceID == "other-space" }
			XCTAssertEqual(
				repairedOtherSpaceTabs.map(\.id),
				[otherSpaceSecondID, otherSpaceFirstID]
			)
		}
	}

	func testPersistCurrentTabsOrdersUnknownSpaceTabsAfterKnownSpaces() throws {
		try withInMemoryStoredBrowserTabState(.empty) {
			let viewModel = AppViewModel()
			let orphanTabID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-1111-1111-1111-AAAAAAAAAAAA"))

			@Shared(.navigatorStoredBrowserTabs) var storedTabs = .empty
			$storedTabs.withLock { value in
				value = StoredBrowserTabCollection(
					activeSpaceID: StoredBrowserTabCollection.defaultSpaceID,
					spaces: [
						StoredBrowserSpace(
							id: StoredBrowserTabCollection.defaultSpaceID,
							name: "Default",
							orderKey: "00000000"
						),
					],
					tabs: [
						StoredBrowserTab(
							id: orphanTabID,
							objectVersion: 1,
							orderKey: "00000000",
							spaceID: "orphan-space",
							url: "https://orphan.example"
						),
					]
				)
			}

			viewModel.openIncomingURLsInNewTabs(["https://known.example"])

			let persistedTabs = $storedTabs.withLock { value in value.tabs }
			XCTAssertEqual(persistedTabs.last?.spaceID, "orphan-space")
		}
	}

	func testSwitchSpaceUsesStoredSelectionForTargetSpace() throws {
		try withInMemoryStoredBrowserTabState(
			StoredBrowserTabCollection(
				activeSpaceID: "space-one",
				spaces: [
					StoredBrowserSpace(id: "space-one", name: "One", orderKey: "00000000"),
					StoredBrowserSpace(id: "space-two", name: "Two", orderKey: "00000001"),
				],
				tabs: [
					StoredBrowserTab(
						id: XCTUnwrap(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")),
						objectVersion: 1,
						orderKey: "00000000",
						spaceID: "space-one",
						url: "https://one.example"
					),
					StoredBrowserTab(
						id: XCTUnwrap(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")),
						objectVersion: 1,
						orderKey: "00000000",
						spaceID: "space-two",
						url: "https://two-first.example"
					),
					StoredBrowserTab(
						id: XCTUnwrap(UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")),
						objectVersion: 1,
						orderKey: "00000001",
						spaceID: "space-two",
						url: "https://two-selected.example"
					),
				]
			),
			selection: StoredBrowserTabSelection(
				selectedSpaceID: "space-two",
				selectedTabID: XCTUnwrap(UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"))
			)
		) {
			let viewModel = AppViewModel()
			viewModel.switchSpace(to: "space-two")

			XCTAssertEqual(viewModel.sidebarViewModel.selectedTabCurrentURL, "https://two-selected.example")
		}
	}

	func testSharedWindowSelectionPersistsTabsWithoutOverwritingStoredSelection() {
		withInMemoryStoredBrowserTabState(.empty) {
			let primaryViewModel = AppViewModel()
			primaryViewModel.openIncomingURLsInNewTabs([
				"https://swift.org",
				"https://developer.apple.com",
			])
			primaryViewModel.sidebarViewModel.selectTab(id: primaryViewModel.sidebarViewModel.tabs[1].id)

			let secondaryViewModel = AppViewModel(
				sessionPersistence: .sharedWindowSelection,
				sharedTabCollection: primaryViewModel.sharedTabCollection,
				initialSelectedTabID: primaryViewModel.sidebarViewModel.tabs[2].id
			)

			secondaryViewModel.sidebarViewModel.closeTab(id: secondaryViewModel.sidebarViewModel.tabs[0].id)

			@Shared(.navigatorStoredBrowserTabs) var storedTabs = .empty
			@Shared(.navigatorStoredBrowserTabSelection) var storedSelection = .empty

			XCTAssertEqual(
				storedTabs.tabs.map(\.url),
				[
					"https://swift.org",
					"https://developer.apple.com",
				]
			)
			XCTAssertEqual(
				storedSelection.selectedTabID,
				primaryViewModel.sidebarViewModel.tabs[0].id
			)
			XCTAssertEqual(
				secondaryViewModel.sidebarViewModel.selectedTabCurrentURL,
				"https://developer.apple.com"
			)
		}
	}

	func testSharedWindowSelectionChangesSelectionWithoutPersistingIt() {
		withInMemoryStoredBrowserTabState(.empty) {
			let primaryViewModel = AppViewModel()
			primaryViewModel.openIncomingURLsInNewTabs([
				"https://swift.org",
				"https://developer.apple.com",
			])
			primaryViewModel.sidebarViewModel.selectTab(id: primaryViewModel.sidebarViewModel.tabs[0].id)

			let secondaryViewModel = AppViewModel(
				sessionPersistence: .sharedWindowSelection,
				sharedTabCollection: primaryViewModel.sharedTabCollection,
				initialSelectedTabID: primaryViewModel.sidebarViewModel.tabs[2].id
			)

			secondaryViewModel.sidebarViewModel.selectTab(id: secondaryViewModel.sidebarViewModel.tabs[1].id)

			@Shared(.navigatorStoredBrowserTabSelection) var storedSelection = .empty

			XCTAssertEqual(
				storedSelection.selectedTabID,
				primaryViewModel.sidebarViewModel.tabs[0].id
			)
			XCTAssertEqual(
				secondaryViewModel.sidebarViewModel.selectedTabCurrentURL,
				"https://swift.org"
			)
			XCTAssertEqual(
				primaryViewModel.sidebarViewModel.selectedTabCurrentURL,
				"https://navigator.zip"
			)
		}
	}

	func testSharedWindowSelectionTracksSharedTabMutationsAcrossThreeViewModels() {
		withInMemoryStoredBrowserTabState(.empty) {
			let primaryViewModel = AppViewModel()
			primaryViewModel.openIncomingURLsInNewTabs([
				"https://swift.org",
				"https://developer.apple.com",
			])

			let secondaryViewModel = AppViewModel(
				sessionPersistence: .sharedWindowSelection,
				sharedTabCollection: primaryViewModel.sharedTabCollection,
				initialSelectedTabID: primaryViewModel.sidebarViewModel.tabs[1].id
			)
			let tertiaryViewModel = AppViewModel(
				sessionPersistence: .sharedWindowSelection,
				sharedTabCollection: primaryViewModel.sharedTabCollection,
				initialSelectedTabID: primaryViewModel.sidebarViewModel.tabs[2].id
			)

			secondaryViewModel.sidebarViewModel.openNewTab(with: "https://example.com")
			tertiaryViewModel.sidebarViewModel.selectTab(id: tertiaryViewModel.sidebarViewModel.tabs[0].id)

			XCTAssertEqual(
				primaryViewModel.sidebarViewModel.tabs.map(\.currentURL),
				[
					"https://navigator.zip",
					"https://swift.org",
					"https://developer.apple.com",
					"https://example.com",
				]
			)
			XCTAssertEqual(
				secondaryViewModel.sidebarViewModel.tabs.map(\.currentURL),
				primaryViewModel.sidebarViewModel.tabs.map(\.currentURL)
			)
			XCTAssertEqual(
				tertiaryViewModel.sidebarViewModel.tabs.map(\.currentURL),
				primaryViewModel.sidebarViewModel.tabs.map(\.currentURL)
			)
			XCTAssertEqual(primaryViewModel.sidebarViewModel.selectedTabCurrentURL, "https://developer.apple.com")
			XCTAssertEqual(secondaryViewModel.sidebarViewModel.selectedTabCurrentURL, "https://example.com")
			XCTAssertEqual(tertiaryViewModel.sidebarViewModel.selectedTabCurrentURL, "https://navigator.zip")
		}
	}

	func testSharedWindowSelectionUpdatesStoredSelectionWhenPrimarySelectionFallsBackAfterSharedClose() {
		withInMemoryStoredBrowserTabState(.empty) {
			let primaryViewModel = AppViewModel()
			primaryViewModel.openIncomingURLsInNewTabs([
				"https://swift.org",
				"https://developer.apple.com",
			])
			primaryViewModel.sidebarViewModel.selectTab(id: primaryViewModel.sidebarViewModel.tabs[1].id)

			let secondaryViewModel = AppViewModel(
				sessionPersistence: .sharedWindowSelection,
				sharedTabCollection: primaryViewModel.sharedTabCollection,
				initialSelectedTabID: primaryViewModel.sidebarViewModel.tabs[2].id
			)

			secondaryViewModel.sidebarViewModel.closeTab(id: secondaryViewModel.sidebarViewModel.tabs[1].id)

			@Shared(.navigatorStoredBrowserTabs) var storedTabs = .empty
			@Shared(.navigatorStoredBrowserTabSelection) var storedSelection = .empty

			XCTAssertEqual(
				storedTabs.tabs.map(\.url),
				[
					"https://navigator.zip",
					"https://developer.apple.com",
				]
			)
			XCTAssertEqual(
				storedSelection.selectedTabID,
				primaryViewModel.sidebarViewModel.tabs[1].id
			)
			XCTAssertEqual(
				primaryViewModel.sidebarViewModel.selectedTabCurrentURL,
				"https://developer.apple.com"
			)
			XCTAssertEqual(
				secondaryViewModel.sidebarViewModel.selectedTabCurrentURL,
				"https://developer.apple.com"
			)
		}
	}

	func testSubmitAddressPersistsUpdatedTabURLForRestore() {
		withInMemoryStoredBrowserTabState(.empty) {
			let viewModel = AppViewModel()

			viewModel.sidebarViewModel.setAddressText("swift.org")
			viewModel.sidebarViewModel.submitAddress()

			@Shared(.navigatorStoredBrowserTabs) var storedTabs = .empty
			XCTAssertEqual(storedTabs.tabs.map(\.url), ["https://swift.org"])

			let hydratedViewModel = AppViewModel()
			XCTAssertEqual(hydratedViewModel.sidebarViewModel.tabs.map(\.currentURL), ["https://swift.org"])
			XCTAssertEqual(hydratedViewModel.sidebarViewModel.selectedTabCurrentURL, "https://swift.org")
		}
	}

	func testPinnedTabsPersistPinnedOriginURLInsteadOfCurrentNavigatedURL() throws {
		try withInMemoryStoredBrowserTabState(.empty) {
			let viewModel = AppViewModel()
			let pinnedTabID = try XCTUnwrap(viewModel.sidebarViewModel.selectedTabID)

			viewModel.sidebarViewModel.pinTab(id: pinnedTabID)
			viewModel.sidebarViewModel.updateTabURL("https://swift.org", for: pinnedTabID)

			@Shared(.navigatorStoredBrowserTabs) var storedTabs = .empty
			XCTAssertEqual(storedTabs.tabs.map(\.url), ["https://navigator.zip"])

			let hydratedViewModel = AppViewModel()
			XCTAssertEqual(hydratedViewModel.sidebarViewModel.tabs.map(\.currentURL), ["https://navigator.zip"])
			XCTAssertTrue(hydratedViewModel.sidebarViewModel.tabs[0].isPinned)
		}
	}

	func testReplacingPinnedTabURLPersistsCurrentURLAsNewPinnedOrigin() throws {
		try withInMemoryStoredBrowserTabState(.empty) {
			let viewModel = AppViewModel()
			let pinnedTabID = try XCTUnwrap(viewModel.sidebarViewModel.selectedTabID)

			viewModel.sidebarViewModel.pinTab(id: pinnedTabID)
			viewModel.sidebarViewModel.updateTabURL("https://swift.org", for: pinnedTabID)
			viewModel.sidebarViewModel.replacePinnedTabURLWithCurrentURL(id: pinnedTabID)

			@Shared(.navigatorStoredBrowserTabs) var storedTabs = .empty
			XCTAssertEqual(storedTabs.tabs.map(\.url), ["https://swift.org"])

			let hydratedViewModel = AppViewModel()
			XCTAssertEqual(hydratedViewModel.sidebarViewModel.tabs.map(\.currentURL), ["https://swift.org"])
			XCTAssertTrue(hydratedViewModel.sidebarViewModel.tabs[0].isPinned)
		}
	}

	func testStreamingImportAppendsTabsAsProfilesArriveAndPersistsFinalSnapshot() async {
		await withDependencies {
			$0.date.now = Date(timeIntervalSince1970: 1234)
		} operation: {
			let viewModel = AppViewModel()
			let firstProfile = ImportedBrowserProfile(
				id: "Default",
				displayName: "Default",
				isDefault: true,
				windows: [
					ImportedBrowserWindow(
						id: "window-1",
						displayName: "Window 1",
						tabGroups: [
							ImportedTabGroup(
								id: "group-1",
								displayName: "Window 1",
								kind: .browserWindow,
								colorHex: nil,
								tabs: [
									ImportedTab(
										id: "tab-1",
										title: "First",
										url: "https://first.example",
										isPinned: false,
										isFavorite: false,
										lastActiveAt: nil
									),
								]
							),
						],
						selectedTabID: nil
					),
				],
				bookmarkFolders: [],
				historyEntries: []
			)
			let secondProfile = ImportedBrowserProfile(
				id: "Profile 1",
				displayName: "Profile 1",
				isDefault: false,
				windows: [
					ImportedBrowserWindow(
						id: "window-2",
						displayName: "Window 2",
						tabGroups: [
							ImportedTabGroup(
								id: "group-2",
								displayName: "Window 2",
								kind: .browserWindow,
								colorHex: nil,
								tabs: [
									ImportedTab(
										id: "tab-2",
										title: "Second",
										url: "https://second.example",
										isPinned: false,
										isFavorite: false,
										lastActiveAt: nil
									),
								]
							),
						],
						selectedTabID: "tab-2"
					),
				],
				bookmarkFolders: [],
				historyEntries: []
			)
			let finalSnapshot = ImportedBrowserSnapshot(
				source: .chrome,
				profiles: [firstProfile, secondProfile]
			)

			viewModel.beginStreamingBrowserImport(from: .chrome)
			viewModel.importBrowserProfileChunk(firstProfile, from: .chrome)
			await waitUntil {
				viewModel.spaces.count == 2
			}
			XCTAssertEqual(
				viewModel.sidebarViewModel.tabs.map(\.currentURL),
				[
					"https://navigator.zip",
				]
			)

			viewModel.importBrowserProfileChunk(secondProfile, from: .chrome)
			await waitUntil {
				viewModel.spaces.count == 3
			}
			XCTAssertEqual(
				viewModel.sidebarViewModel.tabs.map(\.currentURL),
				[
					"https://navigator.zip",
				]
			)
			XCTAssertEqual(viewModel.sidebarViewModel.selectedTabCurrentURL, "https://navigator.zip")

			viewModel.switchSpace(to: importedSpaceID(profileID: "Default", windowID: "window-1"))
			XCTAssertEqual(
				viewModel.sidebarViewModel.tabs.map(\.currentURL),
				["https://first.example"]
			)
			viewModel.switchSpace(to: importedSpaceID(profileID: "Profile 1", windowID: "window-2"))
			XCTAssertEqual(
				viewModel.sidebarViewModel.tabs.map(\.currentURL),
				["https://second.example"]
			)
			viewModel.switchSpace(to: StoredBrowserTabCollection.defaultSpaceID)

			viewModel.finishStreamingBrowserImport(finalSnapshot)
			await waitUntil {
				viewModel.spaces.count == 3
			}

			XCTAssertEqual(
				viewModel.sidebarViewModel.tabs.map(\.currentURL),
				[
					"https://navigator.zip",
				]
			)

			@Shared(.navigatorStoredBrowserTabs) var storedTabs = .empty
			await waitUntil {
				storedTabs.tabs.map(\.url) == [
					"https://navigator.zip",
					"https://first.example",
					"https://second.example",
				]
			}

			let hydratedViewModel = AppViewModel()
			XCTAssertEqual(
				hydratedViewModel.sidebarViewModel.tabs.map(\.currentURL),
				[
					"https://navigator.zip",
				]
			)
			XCTAssertEqual(hydratedViewModel.sidebarViewModel.selectedTabCurrentURL, "https://navigator.zip")
			hydratedViewModel.switchSpace(to: importedSpaceID(profileID: "Default", windowID: "window-1"))
			XCTAssertEqual(
				hydratedViewModel.sidebarViewModel.tabs.map(\.currentURL),
				["https://first.example"]
			)
			hydratedViewModel.switchSpace(to: importedSpaceID(profileID: "Profile 1", windowID: "window-2"))
			XCTAssertEqual(
				hydratedViewModel.sidebarViewModel.tabs.map(\.currentURL),
				["https://second.example"]
			)
		}
	}

	func testStreamingImportDefersStoredTabPersistenceUntilCompletion() async {
		await withDependencies {
			$0.date.now = Date(timeIntervalSince1970: 1234)
		} operation: {
			await withInMemoryStoredBrowserTabState(.empty) {
				let viewModel = AppViewModel()
				let importedProfile = ImportedBrowserProfile(
					id: "Default",
					displayName: "Default",
					isDefault: true,
					windows: [
						ImportedBrowserWindow(
							id: "window-1",
							displayName: "Window 1",
							tabGroups: [
								ImportedTabGroup(
									id: "group-1",
									displayName: "Window 1",
									kind: .browserWindow,
									colorHex: nil,
									tabs: [
										ImportedTab(
											id: "tab-1",
											title: "Imported",
											url: "https://imported.example",
											isPinned: false,
											isFavorite: false,
											lastActiveAt: nil
										),
									]
								),
							],
							selectedTabID: "tab-1"
						),
					],
					bookmarkFolders: [],
					historyEntries: []
				)
				let finalSnapshot = ImportedBrowserSnapshot(
					source: .arc,
					profiles: [importedProfile]
				)

				viewModel.beginStreamingBrowserImport(from: .arc)
				viewModel.importBrowserProfileChunk(importedProfile, from: .arc)

				@Shared(.navigatorStoredBrowserTabs) var storedTabs = .empty
				await waitUntil {
					storedTabs.spaces.count == 2
				}
				XCTAssertEqual(
					storedTabs.tabs.map(\.url),
					[
						"https://navigator.zip",
						"https://imported.example",
					]
				)

				viewModel.finishStreamingBrowserImport(finalSnapshot)
				await waitUntil {
					storedTabs.tabs.map(\.url) == [
						"https://navigator.zip",
						"https://imported.example",
					]
				}

				XCTAssertEqual(
					storedTabs.tabs.map(\.url),
					[
						"https://navigator.zip",
						"https://imported.example",
					]
				)
			}
		}
	}

	func testFinishStreamingImportFallsBackToSnapshotAppendWhenSourceDiffers() async {
		await withDependencies {
			$0.date.now = Date(timeIntervalSince1970: 1234)
		} operation: {
			let viewModel = AppViewModel()
			viewModel.beginStreamingBrowserImport(from: .chrome)

			let snapshot = makeImportedBrowserSnapshot(
				source: .arc,
				tabURLs: [
					"https://first.example",
					"https://second.example",
				]
			)
			viewModel.finishStreamingBrowserImport(snapshot)

			await waitUntil {
				viewModel.spaces.count == 2
			}
			XCTAssertEqual(viewModel.sidebarViewModel.tabs.map(\.currentURL), ["https://navigator.zip"])
			viewModel.switchSpace(to: importedSpaceID(profileID: "Default", windowID: "window-1"))
			XCTAssertEqual(
				viewModel.sidebarViewModel.tabs.map(\.currentURL),
				[
					"https://first.example",
					"https://second.example",
				]
			)
		}
	}

	func testInitHydratesImportedTabsWhenNoStoredTabStateExists() {
		withDependencies {
			$0.date.now = Date(timeIntervalSince1970: 1234)
		} operation: {
			withInMemoryStoredBrowserTabState(
				.empty,
				importedBrowserLibrary: ImportedBrowserLibrary(
					records: [
						ImportedBrowserLibraryRecord(
							snapshot: makeImportedBrowserSnapshot(
								source: .safari,
								tabURLs: [
									"https://imported-only.example",
								]
							),
							importedAt: Date(timeIntervalSince1970: 1234)
						),
					]
				)
			) {
				let viewModel = AppViewModel()
				XCTAssertEqual(viewModel.sidebarViewModel.tabs.map(\.currentURL), ["https://imported-only.example"])
			}
		}
	}

	func testStreamingImportPreservesExistingTabsWhileAppendingImportedTabs() async {
		await withDependencies {
			$0.date.now = Date(timeIntervalSince1970: 1234)
		} operation: {
			let viewModel = AppViewModel()
			viewModel.openIncomingURLsInNewTabs(["https://existing.example"])

			let importedProfile = ImportedBrowserProfile(
				id: "Default",
				displayName: "Default",
				isDefault: true,
				windows: [
					ImportedBrowserWindow(
						id: "window-1",
						displayName: "Window 1",
						tabGroups: [
							ImportedTabGroup(
								id: "group-1",
								displayName: "Window 1",
								kind: .browserWindow,
								colorHex: nil,
								tabs: [
									ImportedTab(
										id: "tab-1",
										title: "Imported",
										url: "https://imported.example",
										isPinned: false,
										isFavorite: false,
										lastActiveAt: nil
									),
								]
							),
						],
						selectedTabID: "tab-1"
					),
				],
				bookmarkFolders: [],
				historyEntries: []
			)
			let finalSnapshot = ImportedBrowserSnapshot(
				source: .arc,
				profiles: [importedProfile]
			)

			viewModel.beginStreamingBrowserImport(from: .arc)
			viewModel.importBrowserProfileChunk(importedProfile, from: .arc)
			viewModel.finishStreamingBrowserImport(finalSnapshot)
			await waitUntil {
				viewModel.sidebarViewModel.tabs.map(\.currentURL) == [
					"https://navigator.zip",
					"https://existing.example",
				]
			}

			XCTAssertEqual(
				viewModel.sidebarViewModel.tabs.map(\.currentURL),
				[
					"https://navigator.zip",
					"https://existing.example",
				]
			)
			XCTAssertEqual(
				viewModel.sidebarViewModel.tabs.map(\.pageTitle),
				[
					nil,
					nil,
				]
			)
			XCTAssertEqual(viewModel.sidebarViewModel.selectedTabCurrentURL, "https://existing.example")
			await waitUntil {
				viewModel.spaces.count == 2
			}
			viewModel.switchSpace(to: importedSpaceID(profileID: "Default", windowID: "window-1"))
			XCTAssertEqual(
				viewModel.sidebarViewModel.tabs.map(\.currentURL),
				["https://imported.example"]
			)
			XCTAssertEqual(
				viewModel.sidebarViewModel.tabs.map(\.pageTitle),
				["Imported"]
			)
		}
	}

	func testImportBrowserProfileChunkBeginsStreamingWhenSourceChanges() async {
		let viewModel = AppViewModel()
		let importedProfile = ImportedBrowserProfile(
			id: "Default",
			displayName: "Default",
			isDefault: true,
			windows: [
				ImportedBrowserWindow(
					id: "window-1",
					displayName: "Window 1",
					tabGroups: [
						ImportedTabGroup(
							id: "group-1",
							displayName: "Window 1",
							kind: .browserWindow,
							colorHex: nil,
							tabs: [
								ImportedTab(
									id: "tab-1",
									title: "Imported",
									url: "https://source-change.example",
									isPinned: false,
									isFavorite: false,
									lastActiveAt: nil
								),
							]
						),
					],
					selectedTabID: "tab-1"
				),
			],
			bookmarkFolders: [],
			historyEntries: []
		)

		viewModel.beginStreamingBrowserImport(from: .safari)
		viewModel.importBrowserProfileChunk(importedProfile, from: .chrome)
		await waitUntil {
			viewModel.spaces.count == 2
		}

		XCTAssertEqual(
			viewModel.sidebarViewModel.tabs.map(\.currentURL),
			[
				"https://navigator.zip",
			]
		)
		XCTAssertEqual(viewModel.sidebarViewModel.selectedTabCurrentURL, "https://navigator.zip")
		viewModel.switchSpace(to: importedSpaceID(profileID: "Default", windowID: "window-1"))
		XCTAssertEqual(
			viewModel.sidebarViewModel.tabs.map(\.currentURL),
			["https://source-change.example"]
		)
	}

	func testCancelStreamingBrowserImportRestoresDeferredPersistence() {
		withInMemoryStoredBrowserTabState(.empty) {
			let viewModel = AppViewModel()
			let importedProfile = ImportedBrowserProfile(
				id: "Default",
				displayName: "Default",
				isDefault: true,
				windows: [
					ImportedBrowserWindow(
						id: "window-1",
						displayName: "Window 1",
						tabGroups: [
							ImportedTabGroup(
								id: "group-1",
								displayName: "Window 1",
								kind: .browserWindow,
								colorHex: nil,
								tabs: [
									ImportedTab(
										id: "tab-1",
										title: "Imported",
										url: "https://cancelled.example",
										isPinned: false,
										isFavorite: false,
										lastActiveAt: nil
									),
								]
							),
						],
						selectedTabID: "tab-1"
					),
				],
				bookmarkFolders: [],
				historyEntries: []
			)

			viewModel.beginStreamingBrowserImport(from: .arc)
			viewModel.importBrowserProfileChunk(importedProfile, from: .arc)
			viewModel.cancelStreamingBrowserImport(from: .arc)

			@Shared(.navigatorStoredBrowserTabs) var storedTabs = .empty
			XCTAssertEqual(
				storedTabs.tabs.map(\.url),
				[
					"https://navigator.zip",
					"https://cancelled.example",
				]
			)
			XCTAssertEqual(
				storedTabs.tabs.map(\.title),
				[
					nil,
					"Imported",
				]
			)
		}
	}

	func testCancelStreamingBrowserImportWhileDrainTaskIsRunning() async {
		await withInMemoryStoredBrowserTabState(.empty) {
			let viewModel = AppViewModel()
			let importedProfile = makeImportedBrowserSnapshot(
				source: .arc,
				tabURLs: (0..<4000).map { "https://stream-\($0).example" }
			).profiles[0]

			viewModel.beginStreamingBrowserImport(from: .arc)
			viewModel.importBrowserProfileChunk(importedProfile, from: .arc)
			await waitUntil {
				viewModel.spaces.count > 1
			}

			viewModel.cancelStreamingBrowserImport(from: .arc)
			await Task.yield()
			await Task.yield()

			XCTAssertGreaterThanOrEqual(viewModel.spaces.count, 2)
		}
	}

	func testOpenImportedBookmarksOpensPersistedBookmarkURLs() {
		withDependencies {
			$0.date.now = Date(timeIntervalSince1970: 1234)
		} operation: {
			let viewModel = AppViewModel()
			viewModel.importBrowserSnapshot(
				makeImportedBrowserSnapshot(
					source: .arc,
					bookmarkURLs: [
						"https://bookmark-one.example",
						"https://bookmark-two.example",
					]
				)
			)

			viewModel.openImportedBookmarks()

			XCTAssertEqual(
				viewModel.sidebarViewModel.tabs.map(\.currentURL),
				[
					"https://bookmark-one.example",
					"https://bookmark-two.example",
				]
			)
		}
	}

	func testOpenImportedHistoryOpensMostRecentHistoryURLsFirst() {
		let now = Date(timeIntervalSince1970: 1000)
		withDependencies {
			$0.date.now = Date(timeIntervalSince1970: 1234)
		} operation: {
			let viewModel = AppViewModel()
			viewModel.importBrowserSnapshot(
				makeImportedBrowserSnapshot(
					source: .chrome,
					historyEntries: [
						ImportedHistoryEntry(
							id: "history-older",
							title: "Older",
							url: "https://older.example",
							visitedAt: now.addingTimeInterval(-100)
						),
						ImportedHistoryEntry(
							id: "history-newer",
							title: "Newer",
							url: "https://newer.example",
							visitedAt: now
						),
					]
				)
			)

			viewModel.openImportedHistory(limit: 2)

			XCTAssertEqual(
				viewModel.sidebarViewModel.tabs.map(\.currentURL),
				[
					"https://newer.example",
					"https://older.example",
				]
			)
		}
	}

	func testOpenImportedBookmarksAndHistoryDoNothingWithoutPersistedSnapshot() {
		let viewModel = AppViewModel()

		viewModel.openImportedBookmarks()
		viewModel.openImportedHistory(limit: 5)

		XCTAssertEqual(viewModel.sidebarViewModel.tabs.map(\.currentURL), ["https://navigator.zip"])
	}

	func testImportActionTitlesAndVersionDescriptionResolveLocalizedMetadata() throws {
		let viewModel = try NavigatorSettingsViewModel(
			bundle: makeBundle(
				bundleIdentifier: "com.example.navigator",
				shortVersion: "2.0",
				buildNumber: "42"
			)
		)

		XCTAssertEqual(viewModel.versionDescription, "2.0 (42)")
		XCTAssertEqual(viewModel.defaultBrowserTitle, String(localized: .navigatorSettingsDefaultBrowserTitle))
		XCTAssertEqual(viewModel.defaultBrowserActionTitle, String(localized: .navigatorSettingsDefaultBrowserAction))
		XCTAssertEqual(viewModel.browserImportTitle, String(localized: .navigatorSettingsImportTitle))
		XCTAssertEqual(viewModel.browserImportDescription, String(localized: .navigatorSettingsImportDescription))
		XCTAssertEqual(viewModel.importChromeActionTitle, String(localized: .navigatorSettingsImportChromeAction))
		XCTAssertEqual(viewModel.importArcActionTitle, String(localized: .navigatorSettingsImportArcAction))
		XCTAssertEqual(viewModel.importSafariActionTitle, String(localized: .navigatorSettingsImportSafariAction))
		XCTAssertEqual(
			viewModel.openImportedBookmarksActionTitle,
			String(localized: .navigatorSettingsImportOpenBookmarksAction)
		)
		XCTAssertEqual(
			viewModel.openImportedHistoryActionTitle,
			String(localized: .navigatorSettingsImportOpenHistoryAction)
		)
	}

	func testImportSummaryTextCoversIdleImportingCompletedAndFailedStates() {
		let viewModel = NavigatorSettingsViewModel(bundle: .main)

		XCTAssertEqual(
			viewModel.importSummaryText,
			String(localized: .navigatorSettingsImportSummaryNone)
		)

		viewModel.browserImportStatus = .importing(.arc)
		XCTAssertEqual(
			viewModel.importSummaryText,
			"\(String(localized: .navigatorSettingsImportSummaryImporting)) Arc"
		)

		let preview = BrowserImportPreview(
			workspaceCount: 1,
			tabGroupCount: 2,
			tabCount: 3,
			bookmarkFolderCount: 4,
			bookmarkCount: 5,
			historyEntryCount: 6
		)
		viewModel.browserImportStatus = .completed(.safari, preview)
		XCTAssertEqual(
			viewModel.importSummaryText,
			[
				"\(String(localized: .navigatorSettingsImportSummaryLatest)): Safari",
				"\(String(localized: .navigatorSettingsImportSummaryProfiles)): 1",
				"\(String(localized: .navigatorSettingsImportSummaryTabs)): 3",
				"\(String(localized: .navigatorSettingsImportSummaryBookmarks)): 5",
				"\(String(localized: .navigatorSettingsImportSummaryHistory)): 6",
			].joined(separator: "\n")
		)

		viewModel.browserImportStatus = NavigatorBrowserImportStatus.failed("Import failed")
		XCTAssertEqual(viewModel.importSummaryText, "Import failed")
		XCTAssertTrue(viewModel.showsImportError)
	}

	func testBrowserImportIndicatorStateTracksImportLifecycle() {
		let viewModel = NavigatorSettingsViewModel(bundle: .main)

		XCTAssertNil(viewModel.browserImportIndicatorState)

		viewModel.browserImportStatus = .importing(.arc)
		XCTAssertEqual(viewModel.browserImportIndicatorState, .importing)

		viewModel.browserImportStatus = .completed(.safari, .empty)
		XCTAssertEqual(viewModel.browserImportIndicatorState, .completed)

		viewModel.browserImportStatus = .failed("Import failed")
		XCTAssertNil(viewModel.browserImportIndicatorState)
	}

	func testRefreshImportStatusLeavesTransientStatesUntouchedAndPromotesLatestRecord() {
		let persistedSnapshot = makeImportedBrowserSnapshot(
			source: .safari,
			tabURLs: ["https://persisted.example"],
			bookmarkURLs: ["https://bookmark.example"],
			historyURLs: ["https://history.example"]
		)
		withInMemoryImportedBrowserLibrary(
			ImportedBrowserLibrary(
				records: [
					ImportedBrowserLibraryRecord(
						snapshot: persistedSnapshot,
						importedAt: Date(timeIntervalSince1970: 5)
					),
				]
			)
		) {
			let viewModel = NavigatorSettingsViewModel(
				bundle: .main,
				defaultBrowserClient: .init(
					isDefaultBrowser: { _ in false },
					setAsDefaultBrowser: { _ in }
				)
			)

			viewModel.browserImportStatus = .importing(.chrome)
			viewModel.refreshImportStatus()
			XCTAssertEqual(viewModel.browserImportStatus, .importing(.chrome))

			viewModel.browserImportStatus = NavigatorBrowserImportStatus.failed("Failed")
			viewModel.refreshImportStatus()
			XCTAssertEqual(viewModel.browserImportStatus, NavigatorBrowserImportStatus.failed("Failed"))

			viewModel.browserImportStatus = .idle
			viewModel.refreshImportStatus()
			XCTAssertEqual(viewModel.browserImportStatus, .completed(.safari, persistedSnapshot.preview))
		}

		withInMemoryImportedBrowserLibrary(.empty) {
			let emptyViewModel = NavigatorSettingsViewModel(
				bundle: .main,
				defaultBrowserClient: .init(
					isDefaultBrowser: { _ in false },
					setAsDefaultBrowser: { _ in }
				)
			)
			emptyViewModel.refreshImportStatus()
			XCTAssertEqual(emptyViewModel.browserImportStatus, .idle)
		}
	}

	func testDefaultNoopOpenCallbacksAreExecutableWhenImportedDataExists() {
		withInMemoryImportedBrowserLibrary(
			ImportedBrowserLibrary(
				records: [
					ImportedBrowserLibraryRecord(
						snapshot: makeImportedBrowserSnapshot(
							source: .chrome,
							bookmarkURLs: ["https://bookmark.example"],
							historyURLs: ["https://history.example"]
						),
						importedAt: Date(timeIntervalSince1970: 1)
					),
				]
			)
		) {
			let viewModel = NavigatorSettingsViewModel(
				bundle: .main,
				defaultBrowserClient: .init(
					isDefaultBrowser: { _ in false },
					setAsDefaultBrowser: { _ in }
				)
			)

			viewModel.openImportedBookmarks()
			viewModel.openImportedHistory()

			XCTAssertTrue(viewModel.canOpenImportedBookmarks)
			XCTAssertTrue(viewModel.canOpenImportedHistory)
		}
	}
}

func testIdleImportSummaryUsesLatestPersistedRecord() {
	let snapshot = makeImportedBrowserSnapshot(
		source: .chrome,
		tabURLs: ["https://navigator.example"],
		bookmarkURLs: ["https://bookmarks.example"],
		historyURLs: ["https://history.example"]
	)

	withInMemoryImportedBrowserLibrary(
		ImportedBrowserLibrary(
			records: [
				ImportedBrowserLibraryRecord(
					snapshot: snapshot,
					importedAt: Date(timeIntervalSince1970: 1234)
				),
			]
		)
	) {
		let viewModel = NavigatorSettingsViewModel(
			bundle: .main,
			defaultBrowserClient: .init(
				isDefaultBrowser: { _ in false },
				setAsDefaultBrowser: { _ in }
			)
		)

		XCTAssertEqual(
			viewModel.importSummaryText,
			[
				"\(String(localized: .navigatorSettingsImportSummaryLatest)): Chrome",
				"\(String(localized: .navigatorSettingsImportSummaryProfiles)): 1",
				"\(String(localized: .navigatorSettingsImportSummaryTabs)): 1",
				"\(String(localized: .navigatorSettingsImportSummaryBookmarks)): 1",
				"\(String(localized: .navigatorSettingsImportSummaryHistory)): 1",
			].joined(separator: "\n")
		)
	}
}

@MainActor
final class WindowChromeStylerTests: XCTestCase {
	override func setUp() {
		super.setUp()
		installCoverageTestApplicationDelegate()
	}

	override func tearDown() {
		closeAllCoverageTestWindows()
		super.tearDown()
	}

	func testSettingsWindowKeepsClearBackgroundDuringAppearanceRefresh() throws {
		let controller = NavigatorSettingsWindowController()
		retainNavigatorSettingsTestObject(controller)
		let window = try XCTUnwrap(controller.window)

		window.appearance = NSAppearance(named: .darkAqua)
		WindowChromeStyler.applyResolvedColors(to: window)

		XCTAssertEqual(window.backgroundColor.alphaComponent, 0)
	}

	func testStandardWindowUsesResolvedBackgroundColorDuringAppearanceRefresh() {
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
			styleMask: [.titled, .closable, .resizable],
			backing: .buffered,
			defer: false
		)
		window.appearance = NSAppearance(named: .darkAqua)

		WindowChromeStyler.applyResolvedColors(to: window)

		let expectedColor = WindowChromeStyler.resolvedBackgroundColor(
			for: window.contentView?.effectiveAppearance ?? window.effectiveAppearance
		)
		XCTAssertEqual(window.backgroundColor, expectedColor)
	}
}

@MainActor
final class NavigatorSettingsViewTests: XCTestCase {
	override func setUp() {
		super.setUp()
		installCoverageTestApplicationDelegate()
	}

	override func tearDown() {
		closeAllCoverageTestWindows()
		super.tearDown()
	}

	func testResolvedDrawingColorFallsBackWhenCGColorCannotBeResolved() {
		let sourceColor = NSColor.controlAccentColor

		XCTAssertEqual(
			NavigatorSettingsView.resolvedDrawingColor(from: sourceColor) { _ in nil },
			sourceColor
		)
	}

	func testResolvedDrawingColorUsesResolvedCGColorWhenAvailable() {
		let sourceColor = NSColor.controlAccentColor
		let resolvedColor = NSColor.systemGreen

		XCTAssertEqual(
			NavigatorSettingsView.resolvedDrawingColor(from: sourceColor) { _ in resolvedColor },
			resolvedColor
		)
	}

	func testSectionIconsFallBackToSystemSymbolsWhenAssetsAreMissing() {
		var requestedSymbols = [(NavigatorSettingsSection, String)]()

		for section in NavigatorSettingsSection.allCases {
			let requestedImage = section.iconImage(
				isSelected: true,
				pointSize: 18,
				imageNamed: { _ in nil },
				systemSymbolImage: { symbolName, _ in
					requestedSymbols.append((section, symbolName))
					return NSImage(size: NSSize(width: 10, height: 10))
				}
			)

			XCTAssertNotNil(requestedImage)
		}

		XCTAssertEqual(
			requestedSymbols.map(\.1),
			[
				"slider.horizontal.3",
				"person.crop.circle.fill",
				"book.closed.fill",
			]
		)
	}

	func testSectionFallbackSymbolNamesIncludeUnselectedAccountAndColophonVariants() {
		XCTAssertEqual(
			NavigatorSettingsSection.fallbackSymbolName(for: .account, isSelected: false),
			"person.crop.circle"
		)
		XCTAssertEqual(
			NavigatorSettingsSection.fallbackSymbolName(for: .colophon, isSelected: false),
			"book.closed"
		)
	}

	func testSectionHeaderDoesNotInstallGestureRecognizersThatInterceptClicks() throws {
		let (view, _) = makeSettingsView()

		let sectionHeaderStackView = try XCTUnwrap(sectionHeaderStackView(in: view))

		XCTAssertTrue(sectionHeaderStackView.gestureRecognizers.isEmpty)
	}

	func testSettingsViewAddsCloseButtonAndTwoInactiveGrayWindowControls() throws {
		let (view, _) = makeSettingsView()

		let closeButton = try XCTUnwrap(
			settingsWindowControlButton(in: view, identifier: NavigatorSettingsInterfaceIdentifier.closeWindowButton)
		)
		let middleButton = try XCTUnwrap(
			settingsWindowControlButton(
				in: view,
				identifier: NavigatorSettingsInterfaceIdentifier.inactiveMiddleWindowButton
			)
		)
		let trailingButton = try XCTUnwrap(
			settingsWindowControlButton(
				in: view,
				identifier: NavigatorSettingsInterfaceIdentifier.inactiveTrailingWindowButton
			)
		)

		XCTAssertEqual(closeButton.toolTip, "Close Window")
		XCTAssertTrue(closeButton.isEnabled)
		XCTAssertFalse(middleButton.isEnabled)
		XCTAssertFalse(trailingButton.isEnabled)
		XCTAssertEqual(closeButton.bounds.size, NSSize(width: 12, height: 12))
		XCTAssertEqual(middleButton.bounds.size, NSSize(width: 12, height: 12))
		XCTAssertEqual(trailingButton.bounds.size, NSSize(width: 12, height: 12))
	}

	func testSettingsCloseWindowButtonClosesHostingWindow() throws {
		let (view, _) = makeSettingsView()
		let window = NavigatorSettingsWindowActionTestWindow(
			contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
			styleMask: [.borderless, .closable],
			backing: .buffered,
			defer: false
		)
		window.contentView = view
		window.makeKeyAndOrderFront(nil)

		try XCTUnwrap(
			settingsWindowControlButton(in: view, identifier: NavigatorSettingsInterfaceIdentifier.closeWindowButton)
		).performClick(nil)

		XCTAssertTrue(window.didCloseWindow)
	}

	func testClickingSectionHeaderButtonUpdatesSelectedSection() throws {
		let (view, viewModel) = makeSettingsView()
		let sectionHeaderStackView = try XCTUnwrap(sectionHeaderStackView(in: view))
		let accountButton = try XCTUnwrap(sectionButton(for: .account, in: sectionHeaderStackView))
		let colophonButton = try XCTUnwrap(sectionButton(for: .colophon, in: sectionHeaderStackView))

		accountButton.performClick(nil)
		XCTAssertEqual(viewModel.selectedSection, .account)

		colophonButton.performClick(nil)
		XCTAssertEqual(viewModel.selectedSection, .colophon)
	}

	func testSectionHeaderDoesNotShowCameraSectionButton() throws {
		let (view, _) = makeSettingsView()
		let sectionHeaderStackView = try XCTUnwrap(sectionHeaderStackView(in: view))

		XCTAssertNil(sectionButton(for: .camera, in: sectionHeaderStackView))
	}

	func testDefaultBrowserButtonClickDisablesButtonAfterSuccessfulUpdate() async throws {
		var isDefaultBrowser = false
		let (view, viewModel) = makeSettingsView(
			defaultBrowserClient: .init(
				isDefaultBrowser: { _ in isDefaultBrowser },
				setAsDefaultBrowser: { _ in
					isDefaultBrowser = true
				}
			)
		)
		let button = try XCTUnwrap(defaultBrowserButton(in: view))

		XCTAssertTrue(button.isEnabled)

		button.performClick(nil)

		await waitUntil {
			viewModel.defaultBrowserStatus == .currentDefault && button.isEnabled == false
		}

		XCTAssertEqual(viewModel.defaultBrowserStatus, .currentDefault)
		XCTAssertFalse(button.isEnabled)
	}

	func testAutomaticUpdatesCheckboxTogglesViewModelState() throws {
		let (view, viewModel) = makeSettingsView()
		let checkbox = try XCTUnwrap(automaticUpdatesCheckbox(in: view))

		XCTAssertEqual(checkbox.state, .on)

		checkbox.performClick(nil)

		XCTAssertFalse(viewModel.automaticallyChecksForUpdates)
		XCTAssertEqual(checkbox.state, .off)
	}

	func testImportChromeButtonTriggersImportAndRefreshesSummary() async throws {
		let snapshot = makeImportedBrowserSnapshot(
			source: .chrome,
			tabURLs: ["https://navigator.example"],
			bookmarkURLs: ["https://bookmarks.example"],
			historyURLs: ["https://history.example"]
		)
		try await withDependencies {
			$0.date.now = Date(timeIntervalSince1970: 1234)
		} operation: {
			let (view, viewModel) = makeSettingsView(
				executeImport: makeImmediateImportExecution(result: .success(snapshot))
			)
			let button = try XCTUnwrap(importButton(
				in: view,
				identifier: NavigatorSettingsInterfaceIdentifier.importChromeButton
			))

			button.performClick(nil)
			await waitUntil {
				viewModel.browserImportStatus == .completed(.chrome, snapshot.preview)
			}
			view.refresh()

			XCTAssertEqual(viewModel.browserImportStatus, .completed(.chrome, snapshot.preview))
			XCTAssertFalse(viewModel.importSummaryText.isEmpty)
			XCTAssertTrue(button.isEnabled)
		}
	}

	func testImportArcButtonTriggersHandler() async throws {
		let arcSnapshot = makeImportedBrowserSnapshot(source: .arc, tabURLs: ["https://arc.example"])

		try await withDependencies {
			$0.defaultFileStorage = .inMemory
			$0.date.now = Date(timeIntervalSince1970: 1234)
		} operation: {
			let (arcView, arcViewModel) = makeSettingsView(
				executeImport: makeImmediateImportExecution(result: .success(arcSnapshot))
			)
			let button = try XCTUnwrap(
				importButton(in: arcView, identifier: NavigatorSettingsInterfaceIdentifier.importArcButton)
			)
			_ = arcView.perform(NSSelectorFromString("handleImportArcButtonPress:"), with: button)
			await waitUntil {
				arcViewModel.browserImportStatus == .completed(.arc, arcSnapshot.preview)
			}
			XCTAssertEqual(arcViewModel.browserImportStatus, .completed(.arc, arcSnapshot.preview))
		}
	}

	func testImportSafariButtonTriggersHandler() async throws {
		let safariSnapshot = makeImportedBrowserSnapshot(source: .safari, tabURLs: ["https://safari.example"])

		try await withDependencies {
			$0.defaultFileStorage = .inMemory
			$0.date.now = Date(timeIntervalSince1970: 1234)
		} operation: {
			let (safariView, safariViewModel) = makeSettingsView(
				executeImport: makeImmediateImportExecution(result: .success(safariSnapshot))
			)
			try XCTUnwrap(importButton(in: safariView, identifier: NavigatorSettingsInterfaceIdentifier.importSafariButton))
				.performClick(nil)
			await waitUntil {
				safariViewModel.browserImportStatus == .completed(.safari, safariSnapshot.preview)
			}
			XCTAssertEqual(safariViewModel.browserImportStatus, .completed(.safari, safariSnapshot.preview))
		}
	}

	func testErrorStatesRenderDescriptionLabelsInRed() async throws {
		let defaultBrowserClient = NavigatorDefaultBrowserClient(
			isDefaultBrowser: { _ in false },
			setAsDefaultBrowser: { _ in
				throw DefaultBrowserTestError.failed
			}
		)
		let importError = BrowserImportError.browserNotInstalled(.chrome)
		try await withDependencies {
			$0.date.now = Date(timeIntervalSince1970: 1234)
		} operation: {
			let (view, viewModel) = makeSettingsView(
				defaultBrowserClient: defaultBrowserClient,
				executeImport: makeImmediateImportExecution(result: .failure(importError))
			)

			try XCTUnwrap(defaultBrowserButton(in: view)).performClick(nil)
			try XCTUnwrap(
				importButton(in: view, identifier: NavigatorSettingsInterfaceIdentifier.importChromeButton)
			).performClick(nil)
			await waitUntil {
				viewModel.defaultBrowserStatus == .updateFailed && viewModel.showsImportError
			}
			view.refresh()

			let defaultBrowserDescriptionLabel = try XCTUnwrap(
				label(in: view, stringValue: viewModel.defaultBrowserDescription)
			)
			let importSummaryLabel = try XCTUnwrap(
				label(in: view, stringValue: importError.localizedDescription)
			)
			let expectedErrorColor = NavigatorSettingsView.resolvedDrawingColor(from: .systemRed)
			let expectedDefaultBrowserColor = NSColor.secondaryLabelColor

			XCTAssertEqual(defaultBrowserDescriptionLabel.textColor, expectedDefaultBrowserColor)
			XCTAssertEqual(importSummaryLabel.textColor, expectedErrorColor)
		}
	}

	func testImportStatusIndicatorTurnsAmberThenGreen() async throws {
		let controlledImport = ControlledImportExecution()
		let snapshot = makeImportedBrowserSnapshot(
			source: .chrome,
			tabURLs: ["https://navigator.example"]
		)

		try await withDependencies {
			$0.defaultFileStorage = .inMemory
			$0.date.now = Date(timeIntervalSince1970: 1234)
		} operation: {
			let (view, viewModel) = makeSettingsView(
				executeImport: { _ in controlledImport.stream }
			)
			let button = try XCTUnwrap(importButton(
				in: view,
				identifier: NavigatorSettingsInterfaceIdentifier.importChromeButton
			))
			let indicatorView = try XCTUnwrap(importStatusIndicatorView(in: view))

			XCTAssertTrue(indicatorView.isHidden)

			button.performClick(nil)
			await waitForImportExecution()

			controlledImport.yield(.started(.chrome))
			await waitUntil { viewModel.browserImportStatus == .importing(.chrome) }
			view.refresh()

			let importingColor = try XCTUnwrap(
				try NSColor(cgColor: XCTUnwrap(indicatorView.layer?.backgroundColor))
			)
			XCTAssertFalse(indicatorView.isHidden)
			XCTAssertEqual(importingColor, NavigatorSettingsView.resolvedDrawingColor(from: .systemOrange))

			controlledImport.yield(.finished(snapshot))
			controlledImport.finish()
			await waitUntil {
				viewModel.browserImportStatus == .completed(.chrome, snapshot.preview)
			}
			view.refresh()

			let completedColor = try XCTUnwrap(
				try NSColor(cgColor: XCTUnwrap(indicatorView.layer?.backgroundColor))
			)
			XCTAssertFalse(indicatorView.isHidden)
			XCTAssertEqual(completedColor, NavigatorSettingsView.resolvedDrawingColor(from: .systemGreen))
		}
	}

	func testIconImageUsesDefaultSystemSymbolFallbackAndResizingHelper() {
		let image = NavigatorSettingsSection.general.iconImage(
			isSelected: false,
			pointSize: 18,
			imageNamed: { _ in nil }
		)
		let resizedImage = NavigatorSettingsSection.resizedImage(
			from: NSImage(size: NSSize(width: 32, height: 32)),
			pointSize: 18
		)

		XCTAssertNotNil(image)
		XCTAssertEqual(resizedImage.size, NSSize(width: 18, height: 18))
		XCTAssertTrue(resizedImage.isTemplate)
	}

	func testImportedBookmarksAndHistoryButtonsInvokeCallbacks() throws {
		var openedBookmarks = 0
		var openedHistory = 0
		let library = ImportedBrowserLibrary(
			records: [
				ImportedBrowserLibraryRecord(
					snapshot: makeImportedBrowserSnapshot(
						source: .chrome,
						bookmarkURLs: ["https://bookmark.example"],
						historyURLs: ["https://history.example"]
					),
					importedAt: Date(timeIntervalSince1970: 1)
				),
			]
		)

		try withDependencies {
			$0.defaultFileStorage = .inMemory
		} operation: {
			@Shared(.navigatorImportedBrowserLibrary) var importedBrowserLibrary = .empty
			$importedBrowserLibrary.withLock { value in
				value = library
			}

			let viewModel = NavigatorSettingsViewModel(
				bundle: .main,
				onOpenImportedBookmarks: { openedBookmarks += 1 },
				onOpenImportedHistory: { openedHistory += 1 }
			)
			let view = NavigatorSettingsView(viewModel: viewModel)
			retainNavigatorSettingsTestObject(viewModel)
			retainNavigatorSettingsTestObject(view)
			view.layoutSubtreeIfNeeded()

			try XCTUnwrap(
				importButton(in: view, identifier: NavigatorSettingsInterfaceIdentifier.openImportedBookmarksButton)
			).performClick(nil)
			try XCTUnwrap(
				importButton(in: view, identifier: NavigatorSettingsInterfaceIdentifier.openImportedHistoryButton)
			).performClick(nil)
		}

		XCTAssertEqual(openedBookmarks, 1)
		XCTAssertEqual(openedHistory, 1)
	}

	func testSettingsViewControllerRefreshesAfterBackgroundImportCompletes() async throws {
		let snapshot = makeImportedBrowserSnapshot(
			source: .chrome,
			tabURLs: ["https://navigator.example"]
		)
		try await withDependencies {
			$0.date.now = Date(timeIntervalSince1970: 1234)
		} operation: {
			let viewModel = NavigatorSettingsViewModel(
				bundle: .main,
				executeImport: makeImmediateImportExecution(result: .success(snapshot))
			)
			let controller = NavigatorSettingsViewController(viewModel: viewModel)
			retainNavigatorSettingsTestObject(viewModel)
			retainNavigatorSettingsTestObject(controller)
			controller.loadViewIfNeeded()

			let button = try XCTUnwrap(importButton(
				in: controller.view,
				identifier: NavigatorSettingsInterfaceIdentifier.importChromeButton
			))

			button.performClick(nil)
			XCTAssertFalse(button.isEnabled)

			await waitUntil {
				viewModel.browserImportStatus == .completed(.chrome, snapshot.preview)
			}
			await waitForObservationRefresh()

			XCTAssertEqual(viewModel.browserImportStatus, .completed(.chrome, snapshot.preview))
			XCTAssertTrue(button.isEnabled)
		}
	}

	func testSelectingCurrentSectionAndInvalidSectionTagAreNoOps() throws {
		let (view, viewModel) = makeSettingsView()
		let header = try XCTUnwrap(sectionHeaderStackView(in: view))
		let generalButton = try XCTUnwrap(sectionButton(for: .general, in: header))

		generalButton.performClick(nil)
		XCTAssertEqual(viewModel.selectedSection, .general)

		let invalidButton = NSButton()
		invalidButton.tag = Int.max
		_ = view.perform(NSSelectorFromString("handleSectionSelection:"), with: invalidButton)
		XCTAssertEqual(viewModel.selectedSection, .general)
	}

	func testViewDidChangeEffectiveAppearanceRefreshesWithoutChangingButtonIdentity() throws {
		let (view, _) = makeSettingsView()
		let button = try XCTUnwrap(defaultBrowserButton(in: view))

		view.appearance = NSAppearance(named: .darkAqua)
		view.viewDidChangeEffectiveAppearance()

		XCTAssertEqual(defaultBrowserButton(in: view), button)
	}

	func testRefreshKeepsExistingSelectedSectionContentMounted() {
		let (view, viewModel) = makeSettingsView()
		viewModel.selectedSection = .account
		view.refresh()

		let beforeRefreshSubviews = view.subviews.count
		view.refresh()

		XCTAssertEqual(view.subviews.count, beforeRefreshSubviews)
	}

	func testSelectingCameraSectionNormalizesBackToGeneral() {
		let (view, viewModel) = makeSettingsView()
		viewModel.selectedSection = .camera
		view.refresh()

		XCTAssertEqual(viewModel.selectedSection, .general)
		XCTAssertNil(view.allDescendantSubviews.first { $0 is BrowserCameraMenuBarView })
	}

	private func makeSettingsView(
		defaultBrowserClient: NavigatorDefaultBrowserClient = .init(
			isDefaultBrowser: { _ in false },
			setAsDefaultBrowser: { _ in }
		),
		executeImport: NavigatorSettingsViewModel.ExecuteImport? = nil,
		browserImportCoordinator: BrowserImportCoordinator = BrowserImportCoordinator(
			discoverInstallations: { [] },
			loadProfileSnapshot: { _, _, _ in
				ImportedBrowserProfile(
					id: "Default",
					displayName: "Default",
					isDefault: true,
					windows: [],
					bookmarkFolders: [],
					historyEntries: []
				)
			},
			loadRunningWindows: { _ in [] }
		)
	) -> (NavigatorSettingsView, NavigatorSettingsViewModel) {
		withDependencies {
			$0.defaultFileStorage = .inMemory
		} operation: {
			let viewModel = NavigatorSettingsViewModel(
				bundle: .main,
				defaultBrowserClient: defaultBrowserClient,
				browserImportCoordinator: browserImportCoordinator,
				executeImport: executeImport
			)
			let view = NavigatorSettingsView(viewModel: viewModel)
			retainNavigatorSettingsTestObject(viewModel)
			retainNavigatorSettingsTestObject(view)
			view.layoutSubtreeIfNeeded()
			return (view, viewModel)
		}
	}

	private func sectionHeaderStackView(in view: NSView) -> NSStackView? {
		let expectedSectionTags = Set(NavigatorSettingsSection.allCases.map(\.rawValue))
		return view.allDescendantSubviews
			.compactMap { $0 as? NSStackView }
			.first { stackView in
				let arrangedButtons = stackView.arrangedSubviews.compactMap { $0 as? NSButton }
				return Set(arrangedButtons.map(\.tag)) == expectedSectionTags
			}
	}

	private func sectionButton(for section: NavigatorSettingsSection, in stackView: NSStackView) -> NSButton? {
		stackView.arrangedSubviews
			.compactMap { $0 as? NSButton }
			.first { $0.tag == section.rawValue }
	}

	private func defaultBrowserButton(in view: NSView) -> NSButton? {
		view.allDescendantSubviews
			.compactMap { $0 as? NSButton }
			.first { $0.identifier == NavigatorSettingsInterfaceIdentifier.defaultBrowserButton }
	}

	private func importButton(in view: NSView, identifier: NSUserInterfaceItemIdentifier) -> NSButton? {
		view.allDescendantSubviews
			.compactMap { $0 as? NSButton }
			.first { $0.identifier == identifier }
	}

	private func automaticUpdatesCheckbox(in view: NSView) -> NSButton? {
		view.allDescendantSubviews
			.compactMap { $0 as? NSButton }
			.first { $0.identifier == NavigatorSettingsInterfaceIdentifier.automaticUpdatesCheckbox }
	}

	private func settingsWindowControlButton(
		in view: NSView,
		identifier: NSUserInterfaceItemIdentifier
	) -> BrowserSidebarWindowControlButton? {
		view.allDescendantSubviews
			.compactMap { $0 as? BrowserSidebarWindowControlButton }
			.first { $0.identifier == identifier }
	}

	private func importStatusIndicatorView(in view: NSView) -> NSView? {
		view.allDescendantSubviews
			.first { $0.identifier == NavigatorSettingsInterfaceIdentifier.importStatusIndicator }
	}

	private func label(in view: NSView, stringValue: String) -> NSTextField? {
		view.allDescendantSubviews
			.compactMap { $0 as? NSTextField }
			.first { $0.stringValue == stringValue }
	}
}

@MainActor
private final class NavigatorSettingsCameraCoordinatorSpy: BrowserCameraSessionCoordinating {
	private let snapshot: BrowserCameraSessionSnapshot
	private let previewFrame: CGImage? = nil

	init(previewEnabled: Bool) {
		snapshot = BrowserCameraSessionSnapshot(
			lifecycleState: .running,
			healthState: .healthy,
			outputMode: .processedNavigatorFeed,
			routingSettings: BrowserCameraRoutingSettings(
				routingEnabled: true,
				preferNavigatorCameraWhenPossible: true,
				preferredSourceID: "camera-1",
				preferredFilterPreset: .none,
				previewEnabled: previewEnabled
			),
			availableSources: [
				BrowserCameraSource(id: "camera-1", name: "FaceTime HD Camera", isDefault: true),
			],
			activeConsumersByID: [:],
			performanceMetrics: .empty,
			lastErrorDescription: nil
		)
	}

	func currentSnapshot() -> BrowserCameraSessionSnapshot {
		snapshot
	}

	func currentDebugSummary() -> BrowserCameraDebugSummary {
		snapshot.debugSummary
	}

	func currentRoutingConfiguration() -> BrowserCameraRoutingConfiguration {
		snapshot.routingConfiguration
	}

	func currentPreviewFrame() -> CGImage? {
		previewFrame
	}

	func refreshAvailableDevices() {}

	func registerConsumer(_ consumer: BrowserCameraConsumer) {}

	func unregisterConsumer(id: String) {}

	func setRoutingEnabled(_ isEnabled: Bool) {}

	func setPreferredDeviceID(_ preferredDeviceID: String?) {}

	func setPreferredFilterPreset(_ preferredFilterPreset: BrowserCameraFilterPreset) {}

	func setPreferredGrainPresence(_ preferredGrainPresence: BrowserCameraPipelineGrainPresence) {}

	func setPrefersHorizontalFlip(_ prefersHorizontalFlip: Bool) {}

	func setPreviewEnabled(_ isEnabled: Bool) {}

	func noteBrowserRoutingEvent(tabID: String, event: BrowserCameraRoutingEvent) {}

	func noteBrowserProcessFallback(tabID: String, reason: String) {}

	func updateBrowserTransportState(_ state: BrowserCameraBrowserTransportState) {}

	func clearBrowserTransportState(tabID: String) {}

	func addSnapshotObserver(
		_ observer: @escaping @MainActor (BrowserCameraSessionSnapshot) -> Void
	) -> UUID {
		let observerID = UUID()
		observer(snapshot)
		return observerID
	}

	func removeSnapshotObserver(id: UUID) {}

	func addPreviewFrameObserver(
		_ observer: @escaping @MainActor (CGImage?) -> Void
	) -> UUID {
		let observerID = UUID()
		observer(previewFrame)
		return observerID
	}

	func removePreviewFrameObserver(id: UUID) {}
}

private final class NavigatorSettingsWindowActionTestWindow: NSWindow {
	private(set) var didCloseWindow = false

	override func close() {
		didCloseWindow = true
		super.close()
	}
}

final class NavigatorSettingsWindowPlacementResolverTests: XCTestCase {
	func testCentersSettingsWindowInsideParentFrame() {
		let frame = NavigatorSettingsWindowPlacementResolver.frame(
			windowSize: NSSize(width: 600, height: 400),
			centeredIn: NSRect(x: 100, y: 200, width: 1200, height: 900),
			visibleFrame: nil
		)

		XCTAssertEqual(frame.origin.x, 400)
		XCTAssertEqual(frame.origin.y, 450)
	}

	func testClampsCenteredFrameToVisibleFrameBounds() {
		let frame = NavigatorSettingsWindowPlacementResolver.frame(
			windowSize: NSSize(width: 600, height: 400),
			centeredIn: NSRect(x: 1800, y: 900, width: 800, height: 700),
			visibleFrame: NSRect(x: 0, y: 0, width: 1728, height: 1117)
		)

		XCTAssertEqual(frame.origin.x, 1128)
		XCTAssertEqual(frame.origin.y, 717)
	}
}

@MainActor
final class NavigatorSettingsWindowControllerTests: XCTestCase {
	override func setUp() {
		super.setUp()
		installCoverageTestApplicationDelegate()
	}

	override func tearDown() {
		closeAllCoverageTestWindows()
		super.tearDown()
	}

	func testShowWindowUsesDefaultAnchorResolver() throws {
		let controller = NavigatorSettingsWindowController(
			navigatorAppViewModel: AppViewModel()
		)
		retainNavigatorSettingsTestObject(controller)

		controller.showWindow(nil)

		XCTAssertNotNil(controller.window)
		XCTAssertTrue(try XCTUnwrap(controller.window).isVisible)
	}

	func testShowWindowPositionsRelativeToAnchorWindow() throws {
		let anchorWindow = NSWindow(
			contentRect: NSRect(x: 200, y: 300, width: 900, height: 700),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		anchorWindow.makeKeyAndOrderFront(nil)
		let controller = NavigatorSettingsWindowController(
			navigatorAppViewModel: AppViewModel(),
			resolveAnchorWindow: { anchorWindow }
		)
		retainNavigatorSettingsTestObject(controller)

		controller.showWindow(nil)

		let window = try XCTUnwrap(controller.window)
		let expectedFrame = NavigatorSettingsWindowPlacementResolver.frame(
			windowSize: window.frame.size,
			centeredIn: anchorWindow.frame,
			visibleFrame: NavigatorSettingsWindowController.resolvedVisibleFrame(
				attachedScreenVisibleFrame: anchorWindow.screen?.visibleFrame,
				mainScreenVisibleFrame: NSScreen.main?.visibleFrame
			)
		)
		XCTAssertEqual(window.frame.origin.x, expectedFrame.origin.x)
		XCTAssertEqual(window.frame.origin.y, expectedFrame.origin.y)
	}

	func testResolvedVisibleFrameFallsBackToMainScreenAndNil() {
		let hiddenWindow = NSWindow(
			contentRect: NSRect(x: 10, y: 20, width: 300, height: 200),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		let mainScreenFrame = NSRect(x: 50, y: 60, width: 500, height: 400)

		XCTAssertEqual(
			NavigatorSettingsWindowController.resolvedVisibleFrame(
				attachedScreenVisibleFrame: nil,
				mainScreenVisibleFrame: mainScreenFrame
			),
			mainScreenFrame
		)
		XCTAssertNil(
			NavigatorSettingsWindowController.resolvedVisibleFrame(
				attachedScreenVisibleFrame: nil,
				mainScreenVisibleFrame: nil
			)
		)
	}

	func testSettingsChromeWindowHandlesCommandWAndFallsBackForOtherKeys() throws {
		let controller = NavigatorSettingsWindowController(
			navigatorAppViewModel: AppViewModel()
		)
		retainNavigatorSettingsTestObject(controller)
		controller.showWindow(nil)
		let window = try XCTUnwrap(controller.window)

		let otherEvent = try makeKeyDownEvent(
			keyCode: UInt16(kVK_ANSI_Q),
			character: "q",
			timestamp: 1
		)
		XCTAssertFalse(window.performKeyEquivalent(with: otherEvent))

		let closeEvent = try makeKeyDownEvent(
			keyCode: UInt16(kVK_ANSI_W),
			character: "w",
			timestamp: 2
		)
		XCTAssertTrue(window.performKeyEquivalent(with: closeEvent))
		XCTAssertFalse(window.isVisible)
	}
}

@MainActor
private func makeAppDelegate(
	navigatorAppViewModel: AppViewModel? = nil,
	hooks: NavigatorAppDelegateHooks? = nil
) -> (NavigatorAppDelegate, AppViewModel) {
	withDependencies {
		$0.defaultFileStorage = .inMemory
	} operation: {
		let resolvedViewModel = navigatorAppViewModel ?? AppViewModel(initialAddress: "https://navigator.zip")
		let resolvedHooks = hooks ?? NavigatorAppDelegateHooks()
		return (
			NavigatorAppDelegate(
				navigatorAppViewModel: resolvedViewModel,
				hooks: resolvedHooks
			),
			resolvedViewModel
		)
	}
}

private func makeKeyDownEvent(
	keyCode: UInt16,
	modifiers: NSEvent.ModifierFlags = [.command],
	character: String,
	ignoringModifiersCharacter: String? = nil,
	timestamp: TimeInterval
) throws -> NSEvent {
	try XCTUnwrap(
		NSEvent.keyEvent(
			with: .keyDown,
			location: .zero,
			modifierFlags: modifiers,
			timestamp: timestamp,
			windowNumber: NSApp.keyWindow?.windowNumber ?? 0,
			context: nil,
			characters: character,
			charactersIgnoringModifiers: ignoringModifiersCharacter ?? character,
			isARepeat: false,
			keyCode: keyCode
		)
	)
}

private extension NSView {
	var allDescendantSubviews: [NSView] {
		subviews + subviews.flatMap(\.allDescendantSubviews)
	}
}

private final class CoverageTestApplicationDelegate: NSObject, NSApplicationDelegate {
	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
		false
	}
}

@MainActor
private let retainedCoverageTestApplicationDelegate = CoverageTestApplicationDelegate()

@MainActor
private var retainedNavigatorSettingsTestObjects = [AnyObject]()

@MainActor
private func retainNavigatorSettingsTestObject(_ object: AnyObject) {
	retainedNavigatorSettingsTestObjects.append(object)
}

@MainActor
private final class NavigatorCameraStatusItemControllerSpy: NSObject, NavigatorCameraStatusItemControlling {
	private(set) var invalidateCount = 0

	func invalidate() {
		invalidateCount += 1
	}
}

@MainActor
private final class NavigatorCameraStatusItemCoordinatorSpy: NSObject, BrowserCameraSessionCoordinating {
	var snapshot: BrowserCameraSessionSnapshot
	var previewFrame: CGImage?
	private var snapshotObservers = [UUID: @MainActor (BrowserCameraSessionSnapshot) -> Void]()
	private var previewObservers = [UUID: @MainActor (CGImage?) -> Void]()

	private(set) var removedSnapshotObserverIDs = [String]()
	private(set) var removedPreviewObserverIDs = [String]()
	private(set) var registeredConsumers = [BrowserCameraConsumer]()
	private(set) var unregisteredConsumerIDs = [String]()

	init(snapshot: BrowserCameraSessionSnapshot) {
		self.snapshot = snapshot
		super.init()
	}

	func currentSnapshot() -> BrowserCameraSessionSnapshot {
		snapshot
	}

	func currentDebugSummary() -> BrowserCameraDebugSummary {
		snapshot.debugSummary
	}

	func currentRoutingConfiguration() -> BrowserCameraRoutingConfiguration {
		snapshot.routingConfiguration
	}

	func currentPreviewFrame() -> CGImage? {
		previewFrame
	}

	func refreshAvailableDevices() {}
	func registerConsumer(_ consumer: BrowserCameraConsumer) {
		registeredConsumers.append(consumer)
	}

	func unregisterConsumer(id: String) {
		unregisteredConsumerIDs.append(id)
	}

	func setRoutingEnabled(_ isEnabled: Bool) {}
	func setPreferredDeviceID(_ preferredDeviceID: String?) {}
	func setPreferredFilterPreset(_ preferredFilterPreset: BrowserCameraFilterPreset) {}
	func setPreferredGrainPresence(_ preferredGrainPresence: BrowserCameraPipelineGrainPresence) {}

	func setPrefersHorizontalFlip(_ prefersHorizontalFlip: Bool) {}
	func setPreviewEnabled(_ isEnabled: Bool) {}
	func noteBrowserRoutingEvent(tabID: String, event: BrowserCameraRoutingEvent) {}
	func noteBrowserProcessFallback(tabID: String, reason: String) {}
	func updateBrowserTransportState(_ state: BrowserCameraBrowserTransportState) {}
	func clearBrowserTransportState(tabID: String) {}

	func addSnapshotObserver(
		_ observer: @escaping @MainActor (BrowserCameraSessionSnapshot) -> Void
	) -> UUID {
		let observerID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
		snapshotObservers[observerID] = observer
		observer(snapshot)
		return observerID
	}

	func removeSnapshotObserver(id: UUID) {
		snapshotObservers.removeValue(forKey: id)
		removedSnapshotObserverIDs.append("snapshot-observer")
	}

	func addPreviewFrameObserver(
		_ observer: @escaping @MainActor (CGImage?) -> Void
	) -> UUID {
		let observerID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
		previewObservers[observerID] = observer
		observer(previewFrame)
		return observerID
	}

	func removePreviewFrameObserver(id: UUID) {
		previewObservers.removeValue(forKey: id)
		removedPreviewObserverIDs.append("preview-observer")
	}

	func emitSnapshot() {
		for observer in snapshotObservers.values {
			observer(snapshot)
		}
	}
}

@MainActor
private final class NavigatorCameraStatusItemButtonSpy: NSView, NavigatorCameraStatusItemButtonControlling {
	var target: AnyObject?
	var action: Selector?
	var image: NSImage?
	var contentTintColor: NSColor?
	var imagePosition: NSControl.ImagePosition = .noImage
	var view: NSView {
		self
	}
}

@MainActor
private final class NavigatorCameraStatusItemHostSpy: NSObject, NavigatorCameraStatusItemHosting {
	let button: (any NavigatorCameraStatusItemButtonControlling)?
	private(set) var invalidateCount = 0

	init(button: (any NavigatorCameraStatusItemButtonControlling)?) {
		self.button = button
		super.init()
	}

	func invalidate() {
		invalidateCount += 1
	}
}

@MainActor
private final class NavigatorCameraStatusItemPopoverSpy: NSObject, NavigatorCameraStatusItemPopoverControlling {
	var isShown = false
	var behavior: NSPopover.Behavior = .applicationDefined
	var contentSize = NSSize.zero
	var contentViewController: NSViewController?
	var delegate: NSPopoverDelegate?
	private(set) var showRequestCount = 0
	private(set) var closeRequestCount = 0

	func performClose(_ sender: Any?) {
		isShown = false
		closeRequestCount += 1
		delegate?.popoverDidClose?(
			Notification(name: NSPopover.didCloseNotification, object: self)
		)
	}

	func show(relativeTo positioningRect: NSRect, of positioningView: NSView, preferredEdge: NSRectEdge) {
		isShown = true
		showRequestCount += 1
	}
}

private func makeNavigatorCameraStatusSnapshot(
	lifecycleState: BrowserCameraLifecycleState,
	healthState: BrowserCameraHealthState,
	activeConsumers: [BrowserCameraConsumer] = [],
	browserTransportStates: [BrowserCameraBrowserTransportState] = [],
	pipelineRuntimeState: BrowserCameraPipelineRuntimeState? = nil,
	lastErrorDescription: String? = nil,
	recentDiagnosticEvents: [BrowserCameraDiagnosticEvent] = []
) -> BrowserCameraSessionSnapshot {
	BrowserCameraSessionSnapshot(
		lifecycleState: lifecycleState,
		healthState: healthState,
		outputMode: healthState == .publisherUnavailable
			? .systemVirtualCameraPublication
			: .processedNavigatorFeed,
		routingSettings: BrowserCameraRoutingSettings(
			routingEnabled: true,
			preferNavigatorCameraWhenPossible: true,
			preferredSourceID: "camera-1",
			preferredFilterPreset: .none,
			previewEnabled: false
		),
		availableSources: [
			BrowserCameraSource(id: "camera-1", name: "FaceTime HD Camera", isDefault: true),
		],
		activeConsumersByID: activeConsumers.reduce(into: [:]) { partialResult, consumer in
			partialResult[consumer.id] = consumer
		},
		performanceMetrics: .empty,
		lastErrorDescription: lastErrorDescription,
		publisherStatus: healthState == .publisherUnavailable
			? BrowserCameraVirtualPublisherStatus(
				state: .unavailable,
				configuration: nil,
				lastPublishedFrame: nil,
				lastErrorDescription: lastErrorDescription
			)
			: .notRequired,
		pipelineRuntimeState: pipelineRuntimeState,
		browserTransportStates: browserTransportStates,
		recentDiagnosticEvents: recentDiagnosticEvents
	)
}

@MainActor
private func installCoverageTestApplicationDelegate() {
	clearNavigatorWindowPersistenceState()
	clearStoredBrowserTabState()
	NSApp.delegate = retainedCoverageTestApplicationDelegate
}

@MainActor
private func closeAllCoverageTestWindows() {
	for window in NSApplication.shared.windows {
		window.animationBehavior = .none
		window.orderOut(nil)
	}

	clearNavigatorWindowPersistenceState()
}

private func makeCoverageKeyDownEvent(
	keyCode: UInt16,
	characters: String,
	charactersIgnoringModifiers: String,
	modifiers: NSEvent.ModifierFlags,
	timestamp: TimeInterval = 1
) -> NSEvent? {
	NSEvent.keyEvent(
		with: .keyDown,
		location: .zero,
		modifierFlags: modifiers,
		timestamp: timestamp,
		windowNumber: 0,
		context: nil,
		characters: characters,
		charactersIgnoringModifiers: charactersIgnoringModifiers,
		isARepeat: false,
		keyCode: keyCode
	)
}

private func makeImportCoordinator(snapshot: ImportedBrowserSnapshot) -> BrowserImportCoordinator {
	BrowserImportCoordinator(
		discoverInstallations: {
			[
				BrowserInstallation(
					source: snapshot.source,
					displayName: snapshot.source.displayName,
					profileRootURL: URL(fileURLWithPath: "/tmp/\(snapshot.source.rawValue)"),
					profiles: [
						BrowserProfile(
							id: "Default",
							displayName: "Default",
							profileURL: URL(fileURLWithPath: "/tmp/\(snapshot.source.rawValue)/Default"),
							isDefault: true
						),
					]
				),
			]
		},
		loadProfileSnapshot: { _, _, _ in
			ImportedBrowserProfile(
				id: snapshot.profiles.first?.id ?? "Default",
				displayName: snapshot.profiles.first?.displayName ?? "Default",
				isDefault: true,
				windows: [],
				bookmarkFolders: snapshot.profiles.first?.bookmarkFolders ?? [],
				historyEntries: snapshot.profiles.first?.historyEntries ?? []
			)
		},
		loadRunningWindows: { _ in
			snapshot.profiles.first?.windows ?? []
		}
	)
}

private func makeImmediateImportExecution(
	result: Result<ImportedBrowserSnapshot, Error>
) -> NavigatorSettingsViewModel.ExecuteImport {
	{ selection in
		AsyncThrowingStream { continuation in
			continuation.yield(.started(selection.source))
			switch result {
			case .success(let snapshot):
				for profile in snapshot.profiles {
					continuation.yield(.profileImported(snapshot.source, profile))
				}
				continuation.yield(.finished(snapshot))
				continuation.finish()
			case .failure(let error):
				continuation.finish(throwing: error)
			}
		}
	}
}

@MainActor
private func waitForImportExecution() async {
	for _ in 0..<20 {
		await Task.yield()
	}
}

@MainActor
private func waitForObservationRefresh() async {
	for _ in 0..<10 {
		await Task.yield()
	}
}

@MainActor
private func waitUntil(
	maximumIterations: Int = 100,
	condition: @escaping @MainActor () -> Bool
) async {
	for _ in 0..<maximumIterations {
		if condition() {
			return
		}
		await Task.yield()
	}
}

private final class ControlledImportExecution {
	let stream: AsyncThrowingStream<BrowserImportEvent, Error>
	private let continuation: AsyncThrowingStream<BrowserImportEvent, Error>.Continuation

	init() {
		var resolvedContinuation: AsyncThrowingStream<BrowserImportEvent, Error>.Continuation?
		stream = AsyncThrowingStream { continuation in
			resolvedContinuation = continuation
		}
		continuation = resolvedContinuation!
	}

	func yield(_ event: BrowserImportEvent) {
		continuation.yield(event)
	}

	func finish() {
		continuation.finish()
	}

	func fail(_ error: Error) {
		continuation.finish(throwing: error)
	}
}

private func makeImportedBrowserSnapshot(
	source: BrowserImportSource = .chrome,
	tabURLs: [String] = [],
	tabTitles: [String]? = nil,
	selectedTabIndex: Int? = nil,
	bookmarkURLs: [String] = [],
	historyURLs: [String] = [],
	historyEntries: [ImportedHistoryEntry]? = nil
) -> ImportedBrowserSnapshot {
	let tabs = tabURLs.enumerated().map { index, url in
		let title = tabTitles.flatMap { titles in
			titles.indices.contains(index) ? titles[index] : nil
		} ?? "Tab \(index + 1)"
		return ImportedTab(
			id: "tab-\(index)",
			title: title,
			url: url,
			isPinned: false,
			isFavorite: false,
			lastActiveAt: nil
		)
	}
	let selectedTabID = selectedTabIndex.flatMap { index in
		tabs.indices.contains(index) ? tabs[index].id : nil
	}
	let bookmarkFolder = ImportedBookmarkFolder(
		id: "folder-1",
		displayName: "Imported",
		childFolders: [],
		bookmarks: bookmarkURLs.enumerated().map { index, url in
			ImportedBookmark(
				id: "bookmark-\(index)",
				title: "Bookmark \(index + 1)",
				url: url,
				addedAt: nil,
				isFavorite: false
			)
		}
	)
	let resolvedHistoryEntries = historyEntries ?? historyURLs.enumerated().map { index, url in
		ImportedHistoryEntry(
			id: "history-\(index)",
			title: "History \(index + 1)",
			url: url,
			visitedAt: Date(timeIntervalSince1970: TimeInterval(1000 + index))
		)
	}

	return ImportedBrowserSnapshot(
		source: source,
		profiles: [
			ImportedBrowserProfile(
				id: "Default",
				displayName: "Default",
				isDefault: true,
				windows: tabs.isEmpty ? [] : [
					ImportedBrowserWindow(
						id: "window-1",
						displayName: "Window 1",
						tabGroups: [
							ImportedTabGroup(
								id: "group-1",
								displayName: "Window 1",
								kind: .browserWindow,
								colorHex: nil,
								tabs: tabs
							),
						],
						selectedTabID: selectedTabID
					),
				],
				bookmarkFolders: bookmarkURLs.isEmpty ? [] : [bookmarkFolder],
				historyEntries: resolvedHistoryEntries
			),
		]
	)
}

private func makeImportedBrowserProfile() -> ImportedBrowserProfile {
	ImportedBrowserProfile(
		id: "Default",
		displayName: "Default",
		isDefault: true,
		windows: [],
		bookmarkFolders: [],
		historyEntries: []
	)
}

private func persistImportedBrowserLibrary(
	_ snapshot: ImportedBrowserSnapshot,
	importedAt: Date = Date(timeIntervalSince1970: 1234)
) throws {
	let library = ImportedBrowserLibrary(
		records: [
			ImportedBrowserLibraryRecord(
				snapshot: snapshot,
				importedAt: importedAt
			),
		]
	)
	let url = URL.navigatorImportedBrowserLibrary
	try FileManager.default.createDirectory(
		at: url.deletingLastPathComponent(),
		withIntermediateDirectories: true
	)
	try JSONEncoder().encode(library).write(to: url)
}

private func clearImportedBrowserLibrary() {
	try? FileManager.default.removeItem(at: .navigatorImportedBrowserLibrary)
}

private func clearNavigatorWindowPersistenceState() {
	try? FileManager.default.removeItem(at: .navigatorWindowSize)
	NSWindow.removeFrame(usingName: NavigatorWindowPersistenceKeys.primaryFrameAutosaveName)
}

private func persistNavigatorWindowFrameState(_ frame: NSRect) throws {
	let url = URL.navigatorWindowSize
	try FileManager.default.createDirectory(
		at: url.deletingLastPathComponent(),
		withIntermediateDirectories: true
	)
	let payload: [String: Double] = [
		"originX": frame.origin.x,
		"originY": frame.origin.y,
		"width": frame.size.width,
		"height": frame.size.height,
	]
	try JSONEncoder().encode(payload).write(to: url)
}

private func clearStoredBrowserTabState() {
	try? FileManager.default.removeItem(at: .navigatorStoredBrowserTabs)
	try? FileManager.default.removeItem(at: .navigatorStoredBrowserTabSelection)
}

@MainActor
private func withInMemoryImportedBrowserLibrary<Result>(
	_ library: ImportedBrowserLibrary,
	operation: () throws -> Result
) rethrows -> Result {
	try withDependencies {
		$0.defaultFileStorage = .inMemory
	} operation: {
		@Shared(.navigatorImportedBrowserLibrary) var importedBrowserLibrary = .empty
		$importedBrowserLibrary.withLock { value in
			value = library
		}
		return try operation()
	}
}

@MainActor
private func withInMemoryStoredBrowserTabState<Result>(
	_ tabs: StoredBrowserTabCollection,
	selection: StoredBrowserTabSelection = .empty,
	importedBrowserLibrary: ImportedBrowserLibrary = .empty,
	operation: () throws -> Result
) rethrows -> Result {
	try withDependencies {
		$0.defaultFileStorage = .inMemory
	} operation: {
		@Shared(.navigatorStoredBrowserTabs) var storedBrowserTabs = .empty
		@Shared(.navigatorStoredBrowserTabSelection) var storedBrowserTabSelection = .empty
		@Shared(.navigatorImportedBrowserLibrary) var storedImportedBrowserLibrary = .empty
		$storedBrowserTabs.withLock { value in
			value = tabs
		}
		$storedBrowserTabSelection.withLock { value in
			value = selection
		}
		$storedImportedBrowserLibrary.withLock { value in
			value = importedBrowserLibrary
		}
		return try operation()
	}
}

@MainActor
private func withInMemoryStoredBrowserTabState<Result>(
	_ tabs: StoredBrowserTabCollection,
	selection: StoredBrowserTabSelection = .empty,
	importedBrowserLibrary: ImportedBrowserLibrary = .empty,
	operation: () async throws -> Result
) async rethrows -> Result {
	try await withDependencies {
		$0.defaultFileStorage = .inMemory
	} operation: {
		@Shared(.navigatorStoredBrowserTabs) var storedBrowserTabs = .empty
		@Shared(.navigatorStoredBrowserTabSelection) var storedBrowserTabSelection = .empty
		@Shared(.navigatorImportedBrowserLibrary) var storedImportedBrowserLibrary = .empty
		$storedBrowserTabs.withLock { value in
			value = tabs
		}
		$storedBrowserTabSelection.withLock { value in
			value = selection
		}
		$storedImportedBrowserLibrary.withLock { value in
			value = importedBrowserLibrary
		}
		return try await operation()
	}
}

private func replaceImportedBrowserLibrary(_ library: ImportedBrowserLibrary) {
	let url = URL.navigatorImportedBrowserLibrary
	try? FileManager.default.removeItem(at: url)
	try? FileManager.default.createDirectory(
		at: url.deletingLastPathComponent(),
		withIntermediateDirectories: true
	)
	try? JSONEncoder().encode(library).write(to: url)
}

private func importedSpaceID(profileID: String, windowID: String) -> String {
	"imported-space-\(profileID)-\(windowID)"
}

private func makeBundle(
	bundleIdentifier: String?,
	shortVersion: String?,
	buildNumber: String?
) throws -> Bundle {
	let bundleURL = FileManager.default.temporaryDirectory
		.appendingPathComponent(UUID().uuidString)
		.appendingPathExtension("bundle")
	try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

	var infoDictionary: [String: Any] = [
		"CFBundlePackageType": "BNDL",
		"CFBundleName": "NavigatorTests",
	]
	if let bundleIdentifier {
		infoDictionary["CFBundleIdentifier"] = bundleIdentifier
	}
	if let shortVersion {
		infoDictionary["CFBundleShortVersionString"] = shortVersion
	}
	if let buildNumber {
		infoDictionary["CFBundleVersion"] = buildNumber
	}

	let infoPlistURL = bundleURL.appendingPathComponent("Info.plist")
	let wroteInfoPlist = NSDictionary(dictionary: infoDictionary).write(to: infoPlistURL, atomically: true)
	XCTAssertTrue(wroteInfoPlist)
	return try XCTUnwrap(Bundle(url: bundleURL))
}

private final class TestApplicationDelegate2: NSObject, NSApplicationDelegate {}

private func XCTAssertThrowsErrorAsync(
	_ expression: @autoclosure () async throws -> some Any,
	_ message: @autoclosure () -> String = "Expected error to be thrown",
	file: StaticString = #filePath,
	line: UInt = #line,
	_ errorHandler: (Error) -> Void = { _ in }
) async {
	do {
		_ = try await expression()
		XCTFail(message(), file: file, line: line)
	}
	catch {
		errorHandler(error)
	}
}

@MainActor
private final class TestRootViewController: NSViewController, NavigatorBrowserWindowContent {
	let navigatorAppViewModel: AppViewModel

	init(navigatorAppViewModel: AppViewModel) {
		self.navigatorAppViewModel = navigatorAppViewModel
		super.init(nibName: nil, bundle: nil)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func loadView() {
		view = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
	}
}

final class NavigatorSettingsWindowToggleResolverTests: XCTestCase {
	func testResolvesOpenWhenNoSettingsWindowExists() {
		let action = NavigatorSettingsWindowToggleResolver.resolveAction(
			hasSettingsWindow: false,
			isVisible: false,
			isMiniaturized: false
		)

		XCTAssertEqual(action, .open)
	}

	func testResolvesCloseWhenSettingsWindowIsVisible() {
		let action = NavigatorSettingsWindowToggleResolver.resolveAction(
			hasSettingsWindow: true,
			isVisible: true,
			isMiniaturized: false
		)

		XCTAssertEqual(action, .close)
	}

	func testResolvesCloseWhenSettingsWindowIsMiniaturized() {
		let action = NavigatorSettingsWindowToggleResolver.resolveAction(
			hasSettingsWindow: true,
			isVisible: false,
			isMiniaturized: true
		)

		XCTAssertEqual(action, .close)
	}

	func testResolvesOpenWhenSettingsWindowExistsButIsHidden() {
		let action = NavigatorSettingsWindowToggleResolver.resolveAction(
			hasSettingsWindow: true,
			isVisible: false,
			isMiniaturized: false
		)

		XCTAssertEqual(action, .open)
	}
}

private enum DefaultBrowserTestError: Error {
	case failed
}

final class CEFPackagerPrivacyPlistTests: XCTestCase {
	func testPackageModeNormalizesHelperPrivacyUsageDescriptions() throws {
		let fixture = try CEFPackagerTestFixture(includePackagingScript: true)
		addTeardownBlock {
			try? FileManager.default.removeItem(at: fixture.root)
		}

		let result = try CEFPackagerTestSupport.runPackager(
			arguments: [
				"--mode", "package",
				"--repo-root", fixture.root.path,
				"--app-bundle-path", fixture.appBundle.path,
				"--app-scheme", fixture.appExecutableName,
				"--no-sign",
				"--no-verbose",
			],
			workingDirectory: fixture.root
		)

		guard result.exitCode == 0 else {
			XCTFail(result.output)
			return
		}

		for role in CEFPackagerFixtureHelperRole.allCases {
			let plist = try fixture.readPackagedHelperInfoPlist(for: role)
			for (key, expectedValue) in CEFPackagerTestSupport.expectedPrivacyUsageDescriptions {
				XCTAssertEqual(plist[key] as? String, expectedValue, "\(role.bundleName) missing \(key)")
			}
		}
	}

	func testStageModeFailsWhenMissingPrivacyKeysCannotBeNormalized() throws {
		let fixture = try CEFPackagerTestFixture(includePackagingScript: false)
		addTeardownBlock {
			try? FileManager.default.removeItem(at: fixture.root)
		}

		let lockedContents = fixture.helperContentsDirectory(for: .base)
		try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: lockedContents.path)
		defer {
			try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lockedContents.path)
		}

		let result = try CEFPackagerTestSupport.runPackager(
			arguments: [
				"--mode", "stage",
				"--repo-root", fixture.root.path,
				"--skip-fetch",
				"--app-bundle-path", fixture.appBundle.path,
				"--app-scheme", fixture.appExecutableName,
				"--no-verbose",
			],
			workingDirectory: fixture.root
		)

		XCTAssertNotEqual(result.exitCode, 0, result.output)
		XCTAssertTrue(
			result.output.contains("Navigator Helper.app") || result.output.contains("Info.plist"),
			result.output
		)
	}
}

final class CEFProjectConfigurationTests: XCTestCase {
	func testNavigatorTargetDoesNotHardLinkChromiumEmbeddedFramework() throws {
		let project = try navigatorProjectContents()

		XCTAssertFalse(
			project.contains("\"Chromium\\\\ Embedded\\\\ Framework\""),
			"Navigator should load Chromium through the native dlopen path instead of a hard linker dependency."
		)
	}

	func testAttachPackagedRuntimePhaseTracksRealAppBundleOutputs() throws {
		let project = try navigatorProjectContents()

		XCTAssertTrue(
			project.contains("\"$(PROJECT_DIR)/Vendor/CEF/Release/ChromiumEmbeddedRuntime.framework\""),
			"The runtime attach phase should re-run when the packaged CEF runtime changes."
		)
		XCTAssertTrue(
			project.contains(
				"\"$(TARGET_BUILD_DIR)/$(FULL_PRODUCT_NAME)/Contents/Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework\""
			),
			"The runtime attach phase should declare the copied framework as an output."
		)
		XCTAssertTrue(
			project.contains("\"$(TARGET_BUILD_DIR)/$(FULL_PRODUCT_NAME)/Contents/Resources/runtime_layout.json\""),
			"The runtime attach phase should declare runtime metadata output inside the app bundle."
		)
		XCTAssertFalse(
			project.contains("\"$(DERIVED_FILE_DIR)/AttachCEFRuntime.stamp\""),
			"Stamp-only outputs let Xcode skip runtime attachment after the app bundle is recreated."
		)
	}
}

final class AttachCEFRuntimeScriptTests: XCTestCase {
	func testAttachScriptBundlesPackagedRuntimeIntoBuiltApp() throws {
		let fixture = try AttachCEFRuntimeTestFixture()
		addTeardownBlock {
			try? FileManager.default.removeItem(at: fixture.root)
		}

		let result = try runProcess(
			executableURL: URL(fileURLWithPath: "/bin/zsh"),
			arguments: [fixture.scriptURL.path],
			workingDirectory: fixture.root,
			environment: fixture.environment
		)

		guard result.exitCode == 0 else {
			XCTFail(result.output)
			return
		}

		let fileManager = FileManager.default
		XCTAssertTrue(
			fileManager.fileExists(atPath: fixture.attachedFrameworkBinary.path),
			fixture.attachedFrameworkBinary.path
		)
		XCTAssertTrue(fileManager.fileExists(atPath: fixture.attachedRuntimeLayout.path), fixture.attachedRuntimeLayout.path)
		XCTAssertTrue(fileManager.fileExists(atPath: fixture.attachedResource(named: "icudtl.dat").path))
		XCTAssertTrue(
			result.output.contains("Attached packaged CEF runtime from \(fixture.packagedRuntime.path)"),
			result.output
		)

		for role in CEFPackagerFixtureHelperRole.allCases {
			XCTAssertTrue(
				fileManager.fileExists(atPath: fixture.attachedHelperBundle(for: role).path),
				fixture.attachedHelperBundle(for: role).path
			)
		}
	}
}

private enum CEFPackagerFixtureHelperRole: CaseIterable {
	case base
	case renderer
	case gpu
	case plugin

	var bundleName: String {
		switch self {
		case .base:
			return "Navigator Helper.app"
		case .renderer:
			return "Navigator Helper (Renderer).app"
		case .gpu:
			return "Navigator Helper (GPU).app"
		case .plugin:
			return "Navigator Helper (Plugin).app"
		}
	}

	var executableName: String {
		bundleName.replacingOccurrences(of: ".app", with: "")
	}

	var bundleIdentifier: String {
		switch self {
		case .base:
			return "org.example.navigator.helper"
		case .renderer:
			return "org.example.navigator.helper.renderer"
		case .gpu:
			return "org.example.navigator.helper.gpu"
		case .plugin:
			return "org.example.navigator.helper.plugin"
		}
	}
}

private struct AttachCEFRuntimeTestFixture {
	let root: URL
	let buildProducts: URL
	let appBundle: URL
	let packagedRuntime: URL
	let scriptURL: URL
	let appExecutableName = "Navigator"

	init() throws {
		root = try makeTemporaryDirectory(prefix: "AttachCEFRuntimeScriptTests")
		buildProducts = root.appendingPathComponent("Build/Products/Debug")
		appBundle = buildProducts.appendingPathComponent("Navigator.app")
		packagedRuntime = root.appendingPathComponent("Vendor/CEF/Release/ChromiumEmbeddedRuntime.framework")
		scriptURL = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appendingPathComponent("Scripts/AttachCEFRuntime.sh")

		try createAppBundle()
		try createPackagedRuntime()
	}

	var environment: [String: String] {
		[
			"PROJECT_DIR": root.path,
			"TARGET_BUILD_DIR": buildProducts.path,
			"FULL_PRODUCT_NAME": "Navigator.app",
			"PRODUCT_NAME": appExecutableName,
			"CODE_SIGN_IDENTITY": "-",
		]
	}

	var attachedFrameworkBinary: URL {
		appBundle.appendingPathComponent(
			"Contents/Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework"
		)
	}

	var attachedRuntimeLayout: URL {
		appBundle.appendingPathComponent("Contents/Resources/runtime_layout.json")
	}

	func attachedHelperBundle(for role: CEFPackagerFixtureHelperRole) -> URL {
		appBundle.appendingPathComponent("Contents/Frameworks/\(role.bundleName)")
	}

	func attachedResource(named name: String) -> URL {
		appBundle.appendingPathComponent("Contents/Resources/\(name)")
	}

	private func createAppBundle() throws {
		let contentsURL = appBundle.appendingPathComponent("Contents")
		let macOSURL = contentsURL.appendingPathComponent("MacOS")
		try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)
		try copyExecutableStub(to: macOSURL.appendingPathComponent(appExecutableName))
		try writePlist(
			[
				"CFBundleExecutable": appExecutableName,
				"CFBundleIdentifier": "com.example.navigator",
				"CFBundleInfoDictionaryVersion": "6.0",
				"CFBundleName": appExecutableName,
				"CFBundlePackageType": "APPL",
				"CFBundleShortVersionString": "1.0",
				"CFBundleVersion": "1",
			],
			to: contentsURL.appendingPathComponent("Info.plist")
		)
	}

	private func createPackagedRuntime() throws {
		let frameworkURL = packagedRuntime
			.appendingPathComponent("Contents/Frameworks/Chromium Embedded Framework.framework")
		let versionAURL = frameworkURL.appendingPathComponent("Versions/A")
		let resourcesURL = versionAURL.appendingPathComponent("Resources")
		try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
		try copyExecutableStub(to: versionAURL.appendingPathComponent("Chromium Embedded Framework"))
		try writePlist(
			[
				"CFBundleExecutable": "Chromium Embedded Framework",
				"CFBundleIdentifier": "org.example.cef.framework",
				"CFBundleInfoDictionaryVersion": "6.0",
				"CFBundleName": "Chromium Embedded Framework",
				"CFBundlePackageType": "FMWK",
				"CFBundleShortVersionString": "1.0",
				"CFBundleVersion": "1",
			],
			to: resourcesURL.appendingPathComponent("Info.plist")
		)
		try Data("icu".utf8).write(to: resourcesURL.appendingPathComponent("icudtl.dat"), options: .atomic)
		try Data("pak".utf8).write(to: resourcesURL.appendingPathComponent("chrome_100_percent.pak"), options: .atomic)
		try Data("runtime".utf8).write(
			to: resourcesURL.appendingPathComponent("gpu_shader_cache.bin"),
			options: .atomic
		)
		try createFrameworkSymlink(named: "Current", target: "A", in: frameworkURL.appendingPathComponent("Versions"))
		try createFrameworkSymlink(
			named: "Chromium Embedded Framework",
			target: "Versions/Current/Chromium Embedded Framework",
			in: frameworkURL
		)
		try createFrameworkSymlink(named: "Resources", target: "Versions/Current/Resources", in: frameworkURL)

		let runtimeResourcesURL = packagedRuntime.appendingPathComponent("Contents/Resources")
		try FileManager.default.createDirectory(at: runtimeResourcesURL, withIntermediateDirectories: true)
		let runtimeLayout = """
		{
		  "expectedPaths": {
		    "resourcesRelativePath": "Contents/Resources",
		    "localesRelativePath": "Contents/Frameworks/Chromium Embedded Framework.framework/Versions/A/Resources/locales",
		    "helpersDirRelativePath": "Contents/Frameworks"
		  }
		}
		"""
		try runtimeLayout.write(
			to: runtimeResourcesURL.appendingPathComponent("runtime_layout.json"),
			atomically: true,
			encoding: .utf8
		)
		try Data("icu".utf8).write(to: runtimeResourcesURL.appendingPathComponent("icudtl.dat"), options: .atomic)

		for role in CEFPackagerFixtureHelperRole.allCases {
			try createHelperBundle(
				at: packagedRuntime.appendingPathComponent("Contents/Frameworks/\(role.bundleName)"),
				role: role
			)
		}
	}

	private func createHelperBundle(at bundleURL: URL, role: CEFPackagerFixtureHelperRole) throws {
		let contentsURL = bundleURL.appendingPathComponent("Contents")
		let macOSURL = contentsURL.appendingPathComponent("MacOS")
		try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)
		try copyExecutableStub(to: macOSURL.appendingPathComponent(role.executableName))
		try writePlist(
			[
				"CFBundleDevelopmentRegion": "en",
				"CFBundleDisplayName": role.executableName,
				"CFBundleExecutable": role.executableName,
				"CFBundleIdentifier": role.bundleIdentifier,
				"CFBundleInfoDictionaryVersion": "6.0",
				"CFBundleName": role.executableName,
				"CFBundlePackageType": "APPL",
				"CFBundleShortVersionString": "1.0",
				"CFBundleVersion": "1",
			],
			to: contentsURL.appendingPathComponent("Info.plist")
		)
	}

	private func copyExecutableStub(to destinationURL: URL) throws {
		try FileManager.default.createDirectory(
			at: destinationURL.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		if FileManager.default.fileExists(atPath: destinationURL.path) {
			try FileManager.default.removeItem(at: destinationURL)
		}
		try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: destinationURL)
	}

	private func createFrameworkSymlink(named name: String, target: String, in directoryURL: URL) throws {
		let symlinkURL = directoryURL.appendingPathComponent(name)
		if FileManager.default.fileExists(atPath: symlinkURL.path) {
			try FileManager.default.removeItem(at: symlinkURL)
		}
		try FileManager.default.createSymbolicLink(atPath: symlinkURL.path, withDestinationPath: target)
	}
}

private struct CEFPackagerTestFixture {
	let root: URL
	let appBundle: URL
	let releaseRoot: URL
	let packagedRuntime: URL
	let appExecutableName = "Navigator"

	init(includePackagingScript: Bool) throws {
		root = try makeTemporaryDirectory(prefix: "CEFPackagerPrivacyPlistTests")
		appBundle = root.appendingPathComponent("Navigator.app")
		releaseRoot = root.appendingPathComponent("Vendor/CEF/Release")
		packagedRuntime = releaseRoot.appendingPathComponent("ChromiumEmbeddedRuntime.framework")

		try createAppBundle()
		try createCEFHeaders()
		try createCEFFramework()
		try CEFPackagerFixtureHelperRole.allCases.forEach { role in
			try createHelperBundle(for: role)
		}
		if includePackagingScript {
			try createPackagingScript()
		}
	}

	func helperBundleURL(for role: CEFPackagerFixtureHelperRole, packaged: Bool = false) -> URL {
		let root = packaged ? packagedRuntime.appendingPathComponent("Contents/Frameworks") : releaseRoot
		return root.appendingPathComponent(role.bundleName)
	}

	func helperContentsDirectory(for role: CEFPackagerFixtureHelperRole) -> URL {
		helperBundleURL(for: role).appendingPathComponent("Contents")
	}

	func helperInfoPlistURL(for role: CEFPackagerFixtureHelperRole, packaged: Bool = false) -> URL {
		helperBundleURL(for: role, packaged: packaged).appendingPathComponent("Contents/Info.plist")
	}

	func readPackagedHelperInfoPlist(for role: CEFPackagerFixtureHelperRole) throws -> [String: Any] {
		try readPlist(at: helperInfoPlistURL(for: role, packaged: true))
	}

	private func createAppBundle() throws {
		let contentsURL = appBundle.appendingPathComponent("Contents")
		try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
		try writePlist(
			[
				"CFBundleExecutable": appExecutableName,
				"CFBundleIdentifier": "com.example.navigator",
				"CFBundleInfoDictionaryVersion": "6.0",
				"CFBundleName": appExecutableName,
				"CFBundlePackageType": "APPL",
				"CFBundleShortVersionString": "1.0",
				"CFBundleVersion": "1",
			],
			to: contentsURL.appendingPathComponent("Info.plist")
		)
	}

	private func createCEFHeaders() throws {
		let includeURL = root.appendingPathComponent("Vendor/CEF/include")
		try FileManager.default.createDirectory(at: includeURL, withIntermediateDirectories: true)
		try Data("hash".utf8).write(to: includeURL.appendingPathComponent("cef_api_hash.h"))
	}

	private func createCEFFramework() throws {
		let resourcesURL = releaseRoot
			.appendingPathComponent("Chromium Embedded Framework.framework/Versions/A/Resources")
		try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
		try Data("icu".utf8).write(to: resourcesURL.appendingPathComponent("icudtl.dat"))
		try Data("pak".utf8).write(to: resourcesURL.appendingPathComponent("chrome_100_percent.pak"))
	}

	private func createHelperBundle(for role: CEFPackagerFixtureHelperRole) throws {
		let contentsURL = helperBundleURL(for: role).appendingPathComponent("Contents")
		let macOSURL = contentsURL.appendingPathComponent("MacOS")
		try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)
		try Data("helper".utf8).write(to: macOSURL.appendingPathComponent(role.executableName))
		try writePlist(
			[
				"CFBundleDevelopmentRegion": "en",
				"CFBundleDisplayName": role.executableName,
				"CFBundleExecutable": role.executableName,
				"CFBundleIdentifier": role.bundleIdentifier,
				"CFBundleInfoDictionaryVersion": "6.0",
				"CFBundleName": role.executableName,
				"CFBundlePackageType": "APPL",
				"CFBundleShortVersionString": "1.0",
				"CFBundleVersion": "1",
			],
			to: contentsURL.appendingPathComponent("Info.plist")
		)
	}

	private func createPackagingScript() throws {
		let scriptURL = root.appendingPathComponent("BundleCEFRuntime.sh")
		let script = """
		#!/bin/zsh
		set -euo pipefail
		typeset -a helper_bundles
		helper_bundles=("${CEF_HELPERS_STAGING_DIR}"/*Helper*.app)
		/bin/mkdir -p "${CEF_RUNTIME_PACKAGE_DIR}/Contents/Frameworks"
		for helper in "${helper_bundles[@]}"; do
		  /usr/bin/ditto "${helper}" "${CEF_RUNTIME_PACKAGE_DIR}/Contents/Frameworks/$(basename "${helper}")"
		done
		"""
		try script.write(to: scriptURL, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
	}
}

private enum CEFPackagerTestSupport {
	static let expectedPrivacyUsageDescriptions: [String: String] = [
		"NSCameraUsageDescription": "Navigator uses your camera when a website requests video access.",
		"NSLocationWhenInUseUsageDescription": "Navigator uses your location when a website requests location access.",
		"NSMicrophoneUsageDescription": "Navigator uses your microphone when a website requests audio access.",
	]

	private static var cachedExecutableURL: URL?

	static func runPackager(
		arguments: [String],
		workingDirectory: URL
	) throws -> CEFPackagerCommandResult {
		try runProcess(
			executableURL: executableURL(),
			arguments: arguments,
			workingDirectory: workingDirectory
		)
	}

	private static func executableURL() throws -> URL {
		let environment = ProcessInfo.processInfo.environment
		if let executablePath = environment["CEFPACKAGER_EXECUTABLE_PATH"],
		   FileManager.default.isExecutableFile(atPath: executablePath) {
			return URL(fileURLWithPath: executablePath)
		}
		if let cachedExecutableURL,
		   FileManager.default.isExecutableFile(atPath: cachedExecutableURL.path) {
			return cachedExecutableURL
		}

		let derivedDataURL = try makeTemporaryDirectory(prefix: "CEFPackagerBuild")
		let repoRoot = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
		let projectURL = repoRoot.appendingPathComponent("Navigator.xcodeproj")
		let buildResult = try runProcess(
			executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
			arguments: [
				"xcodebuild",
				"-project", projectURL.path,
				"-scheme", "CEFPackager",
				"-configuration", "Debug",
				"-derivedDataPath", derivedDataURL.path,
				"CODE_SIGNING_ALLOWED=NO",
				"-quiet",
				"build",
			],
			workingDirectory: repoRoot
		)
		guard buildResult.exitCode == 0 else {
			throw CEFPackagerTestError.packagerBuildFailed(buildResult.output)
		}

		let executableURL = derivedDataURL.appendingPathComponent("Build/Products/Debug/CEFPackager")
		guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
			throw CEFPackagerTestError.packagerMissing(executableURL.path)
		}

		cachedExecutableURL = executableURL
		return executableURL
	}
}

private struct CEFPackagerCommandResult {
	let exitCode: Int32
	let output: String
}

private enum CEFPackagerTestError: Error, LocalizedError {
	case packagerBuildFailed(String)
	case packagerMissing(String)
	case invalidPlist(String)

	var errorDescription: String? {
		switch self {
		case .packagerBuildFailed(let output):
			return "Failed to build CEFPackager:\n\(output)"
		case .packagerMissing(let path):
			return "CEFPackager executable missing at \(path)"
		case .invalidPlist(let path):
			return "Invalid plist at \(path)"
		}
	}
}

private func runProcess(
	executableURL: URL,
	arguments: [String],
	workingDirectory: URL
) throws -> CEFPackagerCommandResult {
	try runProcess(
		executableURL: executableURL,
		arguments: arguments,
		workingDirectory: workingDirectory,
		environment: [:]
	)
}

private func runProcess(
	executableURL: URL,
	arguments: [String],
	workingDirectory: URL,
	environment: [String: String]
) throws -> CEFPackagerCommandResult {
	let process = Process()
	let outputPipe = Pipe()
	let outputLock = NSLock()
	var outputData = Data()

	process.executableURL = executableURL
	process.arguments = arguments
	process.currentDirectoryURL = workingDirectory
	process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, updated in updated }
	process.standardOutput = outputPipe
	process.standardError = outputPipe

	outputPipe.fileHandleForReading.readabilityHandler = { handle in
		let chunk = handle.availableData
		guard !chunk.isEmpty else { return }
		outputLock.lock()
		outputData.append(chunk)
		outputLock.unlock()
	}

	try process.run()
	process.waitUntilExit()
	outputPipe.fileHandleForReading.readabilityHandler = nil

	let trailingData = outputPipe.fileHandleForReading.readDataToEndOfFile()
	if !trailingData.isEmpty {
		outputLock.lock()
		outputData.append(trailingData)
		outputLock.unlock()
	}

	let output = String(data: outputData, encoding: .utf8) ?? ""
	return CEFPackagerCommandResult(
		exitCode: process.terminationStatus,
		output: output
	)
}

private func navigatorProjectContents() throws -> String {
	let repoRoot = URL(fileURLWithPath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()
	let projectURL = repoRoot.appendingPathComponent("Navigator.xcodeproj/project.pbxproj")
	return try String(contentsOf: projectURL, encoding: .utf8)
}

private func makeTemporaryDirectory(prefix: String) throws -> URL {
	let directoryURL = FileManager.default.temporaryDirectory
		.appendingPathComponent("\(prefix)-\(UUID().uuidString)")
	try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
	return directoryURL
}

private func writePlist(_ dictionary: [String: Any], to url: URL) throws {
	let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
	try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
	try data.write(to: url, options: .atomic)
}

private func readPlist(at url: URL) throws -> [String: Any] {
	let data = try Data(contentsOf: url)
	guard let dictionary = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
		throw CEFPackagerTestError.invalidPlist(url.path)
	}
	return dictionary
}

@MainActor
final class BrowserDiagnosticsViewModelCoverageTests: XCTestCase {
	func testReportBuilderIncludesCameraSectionAndRecentEvents() throws {
		let tempDirectory = try makeBrowserDiagnosticsTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: tempDirectory) }

		let crashReportURL = tempDirectory.appendingPathComponent("Navigator-Example.crash")
		try "example".write(to: crashReportURL, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes(
			[.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)],
			ofItemAtPath: crashReportURL.path
		)

		let runtimeSnapshot = makeBrowserDiagnosticsRuntimeSnapshot(
			hasTrackedBrowser: true,
			trackedBrowserCount: 2,
			trackedBrowserIdentifier: "browser-1",
			currentURL: "https://navigator.example/camera",
			canGoBack: true,
			canGoForward: false,
			isLoading: false,
			cachePath: tempDirectory.path,
			resourcesPathExists: true,
			localesPathExists: false,
			cachePathExists: true,
			subprocessPathExists: false,
			lastUserActivityAgeSeconds: 1.25,
			lastActivitySignalAgeSeconds: 2.5
		)
		let cameraSnapshot = makeBrowserDiagnosticsCameraSnapshot(
			lifecycleState: .running,
			healthState: .degraded,
			outputMode: .processedNavigatorFeed,
			selectedSourceID: "front-camera",
			selectedSourceName: "Front Camera",
			selectedPreset: .mononoke,
			activeLiveConsumerIDs: ["tab-1"],
			activePreviewConsumerIDs: ["browser-preview"],
			browserTransportStates: [
				BrowserCameraBrowserTransportState(
					tabID: "tab-1",
					routingTransportMode: .rendererProcessMessages,
					frameTransportMode: .rendererProcessMessages,
					activeManagedTrackCount: 1
				),
			],
			processedFrameCount: 42,
			droppedFrameCount: 3,
			firstFrameLatencyMilliseconds: 18.2,
			averageProcessingLatencyMilliseconds: 5.6,
			pipelineRuntimeState: BrowserCameraPipelineRuntimeState(
				preset: .mononoke,
				implementation: .aperture,
				warmupProfile: .monochromatic,
				grainPresence: .high,
				requiredFilterCount: 1
			),
			lastErrorDescription: "processing timeout",
			publisherStatus: BrowserCameraVirtualPublisherStatus(
				state: .ready,
				configuration: BrowserCameraVirtualPublisherConfiguration(
					sourceDeviceID: "front-camera",
					filterPreset: .mononoke,
					frameWidth: 1280,
					frameHeight: 720,
					nominalFramesPerSecond: 30,
					pixelFormat: .bgra8888,
					backpressurePolicy: .dropOldest,
					transportMode: .sharedMemory
				),
				lastPublishedFrame: nil,
				lastErrorDescription: nil
			),
			recentDiagnosticEvents: [
				BrowserCameraDiagnosticEvent(
					kind: .captureStarted,
					detail: "source=front-camera"
				),
				BrowserCameraDiagnosticEvent(
					kind: .firstFrameProduced,
					detail: "latency=18.2ms"
				),
			]
		)

		let report = BrowserDiagnosticsReportBuilder.makeReport(
			from: runtimeSnapshot,
			hostSnapshot: BrowserDiagnosticsHostSnapshot(
				bundleIdentifier: "com.example.Navigator",
				versionDescription: "1.2 (345)",
				bundlePath: "/Applications/Navigator.app",
				resourcePath: "/Applications/Navigator.app/Contents/Resources",
				windowCount: 2,
				visibleWindowCount: 1,
				keyWindowTitle: "Navigator"
			),
			cameraSnapshot: cameraSnapshot,
			crashReports: [crashReportURL],
			chromeDebugLogLines: [
				"[info] managed camera ready",
				"[debug] first processed frame delivered",
			],
			localize: { $0.fallbackEnglish },
			localizeCameraDiagnosticEvent: { $0.fallbackValue(localeIdentifier: nil) },
			formatTimestamp: { _ in "Nov 14, 2023 at 10:13:20 PM" }
		)
		XCTAssertTrue(report.contains("Camera"))
		XCTAssertTrue(report.contains("Camera lifecycle: running"))
		XCTAssertTrue(report.contains("Camera health: degraded"))
		XCTAssertTrue(report.contains("Camera output mode: processedNavigatorFeed"))
		XCTAssertTrue(report.contains("Selected source: Front Camera"))
		XCTAssertTrue(report.contains("Selected preset: mononoke"))
		XCTAssertTrue(report.contains("Routing enabled: yes"))
		XCTAssertTrue(report.contains("Prefer Navigator camera: yes"))
		XCTAssertTrue(report.contains("Preview enabled: yes"))
		XCTAssertTrue(report.contains("Managed routing availability: degraded"))
		XCTAssertTrue(report.contains("Generic video uses managed output: no"))
		XCTAssertTrue(report.contains("Fail closed when unavailable: yes"))
		XCTAssertTrue(report.contains("Managed device exposed: no"))
		XCTAssertTrue(report.contains("Live consumers: 1 [tab-1]"))
		XCTAssertTrue(report.contains("Preview consumers: 1 [browser-preview]"))
		XCTAssertTrue(
			report.contains(
				"Browser transport tabs: 1 [tab-1:routing=rendererProcessMessages frame=rendererProcessMessages tracks=1]"
			)
		)
		XCTAssertTrue(report.contains("Processed frames: 42"))
		XCTAssertTrue(report.contains("Dropped frames: 3"))
		XCTAssertTrue(report.contains("First frame latency: 18.200ms"))
		XCTAssertTrue(report.contains("Average processing latency: 5.600ms"))
		XCTAssertTrue(report.contains("Pipeline runtime: aperture • monochromatic • filters=1"))
		XCTAssertTrue(report.contains("Publisher state: ready"))
		XCTAssertTrue(report.contains("Publisher transport: sharedMemory"))
		XCTAssertTrue(report.contains("Camera last error: processing timeout"))
		XCTAssertTrue(report.contains("Recent camera events"))
		XCTAssertTrue(report.contains("- Capture started: source=front-camera"))
		XCTAssertTrue(report.contains("- First frame produced: latency=18.2ms"))
		XCTAssertTrue(report.contains("CEF paths"))
		XCTAssertTrue(report.contains("[missing]"))
		XCTAssertTrue(report.contains("Recent crash reports"))
		XCTAssertTrue(report.contains("Navigator-Example.crash (Nov 14, 2023 at 10:13:20 PM)"))
		XCTAssertTrue(report.contains("CEF log tail"))
		XCTAssertTrue(report.contains("- [info] managed camera ready"))
	}

	func testReportBuilderUsesCameraFallbacksWhenPublisherTransportAndEventsAreUnavailable() {
		let report = BrowserDiagnosticsReportBuilder.makeReport(
			from: makeBrowserDiagnosticsRuntimeSnapshot(
				hasTrackedBrowser: false,
				trackedBrowserCount: 0,
				trackedBrowserIdentifier: nil,
				currentURL: nil,
				canGoBack: nil,
				canGoForward: nil,
				isLoading: nil,
				cachePath: "/tmp/navigator-cache",
				resourcesPathExists: false,
				localesPathExists: false,
				cachePathExists: false,
				subprocessPathExists: false,
				lastUserActivityAgeSeconds: 0,
				lastActivitySignalAgeSeconds: 0
			),
			hostSnapshot: BrowserDiagnosticsHostSnapshot(
				bundleIdentifier: nil,
				versionDescription: "none",
				bundlePath: "/Applications/Navigator.app",
				resourcePath: nil,
				windowCount: 0,
				visibleWindowCount: 0,
				keyWindowTitle: nil
			),
			cameraSnapshot: makeBrowserDiagnosticsCameraSnapshot(
				lifecycleState: .idle,
				healthState: .healthy,
				outputMode: .unavailable,
				routingEnabled: false,
				preferNavigatorCameraWhenPossible: false,
				selectedSourceID: nil,
				selectedSourceName: nil,
				selectedPreset: .none,
				previewEnabled: false,
				activeLiveConsumerIDs: [],
				activePreviewConsumerIDs: [],
				processedFrameCount: 0,
				droppedFrameCount: 0,
				firstFrameLatencyMilliseconds: nil,
				averageProcessingLatencyMilliseconds: nil,
				lastErrorDescription: nil,
				publisherStatus: .notRequired,
				recentDiagnosticEvents: []
			),
			crashReports: [],
			chromeDebugLogLines: [],
			localize: { $0.fallbackEnglish },
			localizeCameraDiagnosticEvent: { $0.fallbackValue(localeIdentifier: nil) },
			additionalLocalizationLookup: { $0 },
			formatTimestamp: { _ in "unused" }
		)

		XCTAssertTrue(report.contains("Routing enabled: no"))
		XCTAssertTrue(report.contains("Prefer Navigator camera: no"))
		XCTAssertTrue(report.contains("Preview enabled: no"))
		XCTAssertTrue(report.contains("Managed routing availability: navigatorPreferenceDisabled"))
		XCTAssertTrue(report.contains("Generic video uses managed output: no"))
		XCTAssertTrue(report.contains("Fail closed when unavailable: no"))
		XCTAssertTrue(report.contains("Managed device exposed: no"))
		XCTAssertTrue(report.contains("Browser transport tabs: 0"))
		XCTAssertTrue(report.contains("Publisher transport: none"))
		XCTAssertTrue(report.contains("First frame latency: none"))
		XCTAssertTrue(report.contains("Average processing latency: none"))
		XCTAssertTrue(report.contains("Pipeline runtime: none"))
		XCTAssertTrue(report.contains("Selected source: none"))
		XCTAssertTrue(report.contains("Camera last error: none"))
		XCTAssertTrue(report.contains("- No recent camera events recorded"))
		XCTAssertTrue(report.contains("- No recent crash reports found"))
		XCTAssertTrue(report.contains("- No `chrome_debug.log` output available yet."))
	}

	func testReportBuilderFormatsConsumerListsAndNoneFallbacks() {
		let report = BrowserDiagnosticsReportBuilder.makeReport(
			from: makeBrowserDiagnosticsRuntimeSnapshot(
				hasTrackedBrowser: true,
				trackedBrowserCount: 1,
				trackedBrowserIdentifier: "browser-old",
				currentURL: "https://navigator.example/old",
				canGoBack: false,
				canGoForward: false,
				isLoading: false,
				cachePath: "/tmp/cache-old",
				resourcesPathExists: true,
				localesPathExists: true,
				cachePathExists: true,
				subprocessPathExists: true,
				lastUserActivityAgeSeconds: 0.5,
				lastActivitySignalAgeSeconds: 0.75
			),
			hostSnapshot: BrowserDiagnosticsHostSnapshot(
				bundleIdentifier: "com.example.Navigator",
				versionDescription: "1.0",
				bundlePath: "/Applications/Navigator.app",
				resourcePath: "/Applications/Navigator.app/Contents/Resources",
				windowCount: 1,
				visibleWindowCount: 1,
				keyWindowTitle: "Navigator"
			),
			cameraSnapshot: makeBrowserDiagnosticsCameraSnapshot(
				activeLiveConsumerIDs: ["tab-1", "tab-2"],
				activePreviewConsumerIDs: ["preview-1"],
				lastErrorDescription: nil
			),
			crashReports: [],
			chromeDebugLogLines: [],
			localize: { $0.fallbackEnglish },
			localizeCameraDiagnosticEvent: { $0.fallbackValue(localeIdentifier: nil) },
			formatTimestamp: { _ in "unused" }
		)

		XCTAssertTrue(report.contains("Live consumers: 2 [tab-1, tab-2]"))
		XCTAssertTrue(report.contains("Preview consumers: 1 [preview-1]"))
		XCTAssertTrue(report.contains("Camera last error: none"))
	}

	func testReportBuilderFallsBackToSourceIdentifierAndCrashFileNameOnly() {
		let missingCrashReportURL = URL(fileURLWithPath: "/tmp/Navigator-Missing.crash")
		let report = BrowserDiagnosticsReportBuilder.makeReport(
			from: makeBrowserDiagnosticsRuntimeSnapshot(),
			hostSnapshot: BrowserDiagnosticsHostSnapshot(
				bundleIdentifier: "com.example.Navigator",
				versionDescription: "1.0",
				bundlePath: "/Applications/Navigator.app",
				resourcePath: "/Applications/Navigator.app/Contents/Resources",
				windowCount: 1,
				visibleWindowCount: 1,
				keyWindowTitle: "Navigator"
			),
			cameraSnapshot: makeBrowserDiagnosticsCameraSnapshot(
				selectedSourceID: "camera-id-only",
				selectedSourceName: nil,
				recentDiagnosticEvents: [
					BrowserCameraDiagnosticEvent(
						kind: .processingDegraded,
						detail: nil
					),
				]
			),
			crashReports: [missingCrashReportURL],
			chromeDebugLogLines: [],
			localize: { $0.fallbackEnglish },
			localizeCameraDiagnosticEvent: { $0.fallbackValue(localeIdentifier: nil) },
			formatTimestamp: { _ in "unused" }
		)

		XCTAssertTrue(report.contains("Selected source: camera-id-only"))
		XCTAssertTrue(report.contains("- Processing degraded"))
		XCTAssertTrue(report.contains("- Navigator-Missing.crash"))
	}

	private func makeBrowserDiagnosticsTemporaryDirectory() throws -> URL {
		let directoryURL = FileManager.default.temporaryDirectory
			.appendingPathComponent("BrowserDiagnosticsViewModelTests-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
		return directoryURL
	}

	private func makeBrowserDiagnosticsRuntimeSnapshot(
		hasTrackedBrowser: Bool = true,
		trackedBrowserCount: Int = 1,
		trackedBrowserIdentifier: String? = "browser-1",
		currentURL: String? = "https://navigator.example",
		canGoBack: Bool? = false,
		canGoForward: Bool? = false,
		isLoading: Bool? = false,
		cachePath: String = "/tmp/navigator-cache",
		resourcesPathExists: Bool = true,
		localesPathExists: Bool = true,
		cachePathExists: Bool = true,
		subprocessPathExists: Bool = true,
		lastUserActivityAgeSeconds: TimeInterval = 0.5,
		lastActivitySignalAgeSeconds: TimeInterval = 1.0
	) -> BrowserRuntimeDiagnostics {
		BrowserRuntimeDiagnostics(
			isInitialized: true,
			hasTrackedBrowser: hasTrackedBrowser,
			trackedBrowserCount: trackedBrowserCount,
			trackedBrowserIdentifier: trackedBrowserIdentifier,
			currentURL: currentURL,
			canGoBack: canGoBack,
			canGoForward: canGoForward,
			isLoading: isLoading,
			resourcesPath: "/Applications/Navigator.app/Contents/Frameworks/CEF.framework/Resources",
			localesPath: "/Applications/Navigator.app/Contents/Frameworks/CEF.framework/Resources/locales",
			cachePath: cachePath,
			subprocessPath: "/Applications/Navigator.app/Contents/Frameworks/Navigator Helper.app",
			resourcesPathExists: resourcesPathExists,
			localesPathExists: localesPathExists,
			cachePathExists: cachePathExists,
			subprocessPathExists: subprocessPathExists,
			lastUserActivityAgeSeconds: lastUserActivityAgeSeconds,
			lastActivitySignalAgeSeconds: lastActivitySignalAgeSeconds
		)
	}

	private func makeBrowserDiagnosticsCameraSnapshot(
		lifecycleState: BrowserCameraLifecycleState = .running,
		healthState: BrowserCameraHealthState = .healthy,
		outputMode: BrowserCameraOutputMode = .processedNavigatorFeed,
		routingEnabled: Bool = true,
		preferNavigatorCameraWhenPossible: Bool = true,
		selectedSourceID: String? = "front-camera",
		selectedSourceName: String? = "Front Camera",
		selectedPreset: BrowserCameraFilterPreset = .none,
		previewEnabled: Bool? = nil,
		activeLiveConsumerIDs: [String] = [],
		activePreviewConsumerIDs: [String] = [],
		browserTransportStates: [BrowserCameraBrowserTransportState] = [],
		processedFrameCount: Int = 0,
		droppedFrameCount: Int = 0,
		firstFrameLatencyMilliseconds: Double? = nil,
		averageProcessingLatencyMilliseconds: Double? = nil,
		pipelineRuntimeState: BrowserCameraPipelineRuntimeState? = nil,
		lastErrorDescription: String? = nil,
		publisherStatus: BrowserCameraVirtualPublisherStatus = .notRequired,
		recentDiagnosticEvents: [BrowserCameraDiagnosticEvent] = []
	) -> BrowserCameraSessionSnapshot {
		var activeConsumersByID = [String: BrowserCameraConsumer]()
		for consumerID in activeLiveConsumerIDs {
			activeConsumersByID[consumerID] = BrowserCameraConsumer(
				id: consumerID,
				kind: .browserTabCapture,
				requiresLiveFrames: true
			)
		}
		for consumerID in activePreviewConsumerIDs {
			activeConsumersByID[consumerID] = BrowserCameraConsumer(
				id: consumerID,
				kind: .browserPreview,
				requiresLiveFrames: false
			)
		}

		return BrowserCameraSessionSnapshot(
			lifecycleState: lifecycleState,
			healthState: healthState,
			outputMode: outputMode,
			routingSettings: BrowserCameraRoutingSettings(
				routingEnabled: routingEnabled,
				preferNavigatorCameraWhenPossible: preferNavigatorCameraWhenPossible,
				preferredSourceID: selectedSourceID,
				preferredFilterPreset: selectedPreset,
				previewEnabled: previewEnabled ?? !activePreviewConsumerIDs.isEmpty
			),
			availableSources: selectedSourceID.map {
				[
					BrowserCameraSource(
						id: $0,
						name: selectedSourceName ?? $0,
						isDefault: true
					),
				]
			} ?? [],
			activeConsumersByID: activeConsumersByID,
			performanceMetrics: BrowserCameraPerformanceMetrics(
				processedFrameCount: processedFrameCount,
				droppedFrameCount: droppedFrameCount,
				firstFrameLatencyMilliseconds: firstFrameLatencyMilliseconds,
				averageProcessingLatencyMilliseconds: averageProcessingLatencyMilliseconds,
				lastProcessingLatencyMilliseconds: averageProcessingLatencyMilliseconds,
				realtimeBudgetExceeded: healthState == .degraded
			),
			lastErrorDescription: lastErrorDescription,
			publisherStatus: publisherStatus,
			pipelineRuntimeState: pipelineRuntimeState,
			browserTransportStates: browserTransportStates,
			recentDiagnosticEvents: recentDiagnosticEvents
		)
	}
}
