import AppKit
@testable import BrowserActionBar
import Carbon.HIToolbox
import XCTest

@MainActor
final class BrowserActionBarViewTests: XCTestCase {
	func testAttachWhenAlreadyPresentedShowsPanel() async {
		let viewModel = makeViewModel()
		viewModel.presentCurrentTab(url: "https://example.test/presented")
		let parentWindow = makeParentWindow()
		let panel = BrowserActionBarView(viewModel: viewModel)

		panel.attach(to: parentWindow)
		await flushPresentationUpdates()

		XCTAssertTrue(panel.isVisible)
	}

	func testDismissHidesVisiblePanel() async {
		let viewModel = makeViewModel()
		let parentWindow = makeParentWindow()
		let panel = BrowserActionBarView(viewModel: viewModel)
		panel.attach(to: parentWindow)

		viewModel.presentCurrentTab(url: "https://example.test/visible")
		await flushPresentationUpdates()

		XCTAssertTrue(panel.isVisible)

		viewModel.dismiss()
		await flushPresentationUpdates()

		XCTAssertFalse(panel.isVisible)
	}

	func testRemoveFromWindowDetachesPanelFromParent() async {
		let viewModel = makeViewModel()
		let parentWindow = makeParentWindow()
		let panel = BrowserActionBarView(viewModel: viewModel)
		panel.attach(to: parentWindow)
		viewModel.presentCurrentTab(url: "https://example.test/remove")
		await flushPresentationUpdates()
		XCTAssertTrue(panel.isVisible)

		panel.removeFromWindow()

		XCTAssertFalse(panel.isVisible)
		XCTAssertFalse(parentWindow.childWindows?.contains(where: { $0 === panel }) == true)
	}

	func testAttachAndRepositionWithoutParentWindowNoOps() {
		let viewModel = makeViewModel()
		let panel = BrowserActionBarView(viewModel: viewModel)

		panel.attach(to: nil)
		panel.repositionForCurrentWindow(window: nil)

		XCTAssertFalse(panel.isVisible)
	}

	func testAttachToDifferentParentRebindsChildWindow() async {
		let viewModel = makeViewModel()
		let firstWindow = makeParentWindow()
		let secondWindow = makeParentWindow()
		let panel = BrowserActionBarView(viewModel: viewModel)
		viewModel.presentCurrentTab(url: "https://example.test/rebind")

		panel.attach(to: firstWindow)
		await flushPresentationUpdates()
		XCTAssertTrue(firstWindow.childWindows?.contains(where: { $0 === panel }) == true)

		panel.attach(to: secondWindow)
		await flushPresentationUpdates()

		XCTAssertFalse(firstWindow.childWindows?.contains(where: { $0 === panel }) == true)
		XCTAssertTrue(secondWindow.childWindows?.contains(where: { $0 === panel }) == true)
	}

	func testPresentAfterDismissShowsPanelAgain() async {
		let viewModel = makeViewModel()
		let parentWindow = makeParentWindow()
		let panel = BrowserActionBarView(viewModel: viewModel)
		panel.attach(to: parentWindow)

		viewModel.presentCurrentTab(url: "https://example.test/first")
		await flushPresentationUpdates()
		XCTAssertTrue(panel.isVisible)

		viewModel.dismiss()
		await flushPresentationUpdates()
		XCTAssertFalse(panel.isVisible)

		viewModel.presentCurrentTab(url: "https://example.test/second")
		await flushPresentationUpdates()

		XCTAssertTrue(panel.isVisible)
		XCTAssertEqual(panel.currentQueryTextForTesting, "https://example.test/second")
	}

	func testPresentWhileAlreadyVisibleTogglesPanelHidden() async {
		let viewModel = makeViewModel()
		let parentWindow = makeParentWindow()
		let panel = BrowserActionBarView(viewModel: viewModel)
		panel.attach(to: parentWindow)

		viewModel.presentCurrentTab(url: "https://example.test/first")
		await flushPresentationUpdates()
		XCTAssertTrue(panel.isVisible)

		viewModel.presentCurrentTab(url: "https://example.test/second")
		await flushPresentationUpdates()

		XCTAssertFalse(panel.isVisible)
		XCTAssertEqual(panel.currentQueryTextForTesting, "https://example.test/first")
	}

	func testPresentCurrentTabWhileNewTabIsVisibleRefreshesDisplayedAddress() async {
		let viewModel = makeViewModel()
		let parentWindow = makeParentWindow()
		let panel = BrowserActionBarView(viewModel: viewModel)
		panel.attach(to: parentWindow)

		viewModel.presentNewTab()
		panel.simulateQueryTextChangeForTesting("typed in new tab")
		await flushPresentationUpdates()

		viewModel.presentCurrentTab(url: "https://example.test/current")
		await flushPresentationUpdates()

		XCTAssertTrue(panel.isVisible)
		XCTAssertEqual(panel.currentQueryTextForTesting, "https://example.test/current")
		XCTAssertNil(panel.currentPlaceholderForTesting)
	}

	func testSwitchingBetweenModesRefreshesFocusedQueryWithCurrentURL() async {
		let viewModel = makeViewModel()
		let parentWindow = makeParentWindow()
		let panel = BrowserActionBarView(viewModel: viewModel)
		panel.attach(to: parentWindow)

		viewModel.presentCurrentTab(url: "https://example.test/current-initial")
		await flushPresentationUpdates()
		XCTAssertTrue(panel.isQueryFieldEditingForTesting)

		panel.simulateQueryTextChangeForTesting("typed current override")
		viewModel.presentNewTab()
		await flushPresentationUpdates()

		XCTAssertTrue(panel.isVisible)
		XCTAssertEqual(panel.currentEditorQueryTextForTesting, "")
		XCTAssertEqual(panel.currentQueryTextForTesting, "")

		panel.simulateQueryTextChangeForTesting("typed new tab query")
		viewModel.presentCurrentTab(url: "https://example.test/current-latest")
		await flushPresentationUpdates()

		XCTAssertTrue(panel.isVisible)
		XCTAssertEqual(panel.currentEditorQueryTextForTesting, "https://example.test/current-latest")
		XCTAssertEqual(panel.currentQueryTextForTesting, "https://example.test/current-latest")
		XCTAssertNil(panel.currentPlaceholderForTesting)
	}

	func testStaleEndEditingWhilePanelIsNotKeyDoesNotOverwriteCurrentTabQuery() async {
		let viewModel = makeViewModel()
		let parentWindow = makeParentWindow()
		let panel = BrowserActionBarView(viewModel: viewModel)
		panel.attach(to: parentWindow)

		viewModel.presentNewTab()
		await flushPresentationUpdates()
		panel.simulateQueryTextChangeForTesting("typed new tab query")

		viewModel.presentCurrentTab(url: "https://example.test/current-latest")
		await flushPresentationUpdates()
		XCTAssertEqual(viewModel.query, "https://example.test/current-latest")

		parentWindow.makeKeyAndOrderFront(nil)
		await flushPresentationUpdates()
		panel.simulateQueryTextDidEndEditingForTesting("typed new tab query")

		XCTAssertEqual(viewModel.query, "https://example.test/current-latest")
	}

	func testEndEditingWhilePanelIsKeyUpdatesQuery() {
		let viewModel = makeViewModel()
		let panel = BrowserActionBarView(viewModel: viewModel)
		panel.setKeyWindowForTesting(panel)

		panel.simulateQueryTextDidEndEditingForTesting("https://example.test/edited")

		XCTAssertEqual(viewModel.query, "https://example.test/edited")
	}

	func testResetKeyWindowProviderForTestingRestoresDefaultProvider() {
		let viewModel = makeViewModel()
		let panel = BrowserActionBarView(viewModel: viewModel)
		panel.setKeyWindowForTesting(panel)
		panel.resetKeyWindowProviderForTesting()
		panel.simulateQueryTextDidEndEditingForTesting("https://example.test/no-op")
		XCTAssertEqual(viewModel.query, "")
	}

	func testControlCommandsTriggerExpectedActions() {
		var openedCurrentTab = ""
		let viewModel = makeViewModel(
			onOpenCurrentTab: { openedCurrentTab = $0 }
		)
		let panel = BrowserActionBarView(viewModel: viewModel)
		panel.setQueryFieldTextForTesting("swift.org")
		let textView = NSTextView()
		let control = NSTextField()

		XCTAssertTrue(
			panel.control(
				control,
				textView: textView,
				doCommandBy: #selector(NSResponder.insertNewline(_:))
			)
		)
		XCTAssertEqual(openedCurrentTab, "https://swift.org")

		viewModel.presentNewTab()
		XCTAssertTrue(
			panel.control(
				control,
				textView: textView,
				doCommandBy: #selector(NSResponder.cancelOperation(_:))
			)
		)
		XCTAssertFalse(viewModel.isPresented)

		XCTAssertFalse(
			panel.control(
				control,
				textView: textView,
				doCommandBy: #selector(NSResponder.moveDown(_:))
			)
		)
	}

	func testActionBarTextFieldIsVerticallyCentered() async {
		let expectedIconLeadingInset: CGFloat = 20
		let expectedIconSpacing: CGFloat = 8
		let viewModel = makeViewModel()
		let parentWindow = makeParentWindow()
		let panel = BrowserActionBarView(viewModel: viewModel)
		panel.attach(to: parentWindow)

		viewModel.presentCurrentTab(url: "https://example.test/fill")
		await flushPresentationUpdates()

		let panelBounds = panel.contentBoundsForTesting
		let fieldFrame = panel.queryFieldFrameForTesting
		let iconFrame = panel.leadingIconFrameForTesting

		XCTAssertEqual(iconFrame.minX, expectedIconLeadingInset, accuracy: 0.5)
		XCTAssertEqual(iconFrame.midY, panelBounds.midY, accuracy: 0.5)
		XCTAssertEqual(fieldFrame.minX, iconFrame.maxX + expectedIconSpacing, accuracy: 0.5)
		XCTAssertEqual(fieldFrame.midY, panelBounds.midY, accuracy: 0.5)
		XCTAssertLessThan(fieldFrame.height, panelBounds.height)
	}

	func testLeadingIconUpdatesForURLAndSearchInput() async {
		let viewModel = makeViewModel()
		let parentWindow = makeParentWindow()
		let panel = BrowserActionBarView(viewModel: viewModel)
		panel.attach(to: parentWindow)

		viewModel.presentNewTab()
		await flushPresentationUpdates()
		XCTAssertEqual(panel.leadingIconNameForTesting, "search")

		panel.simulateQueryTextChangeForTesting("swift.org")
		await flushPresentationUpdates()
		XCTAssertEqual(panel.leadingIconNameForTesting, "earth")

		panel.simulateQueryTextChangeForTesting("swift async await")
		await flushPresentationUpdates()
		XCTAssertEqual(panel.leadingIconNameForTesting, "search")
	}

	func testActionBarTextFieldUsesClearBackgroundAndLargerFont() {
		let viewModel = makeViewModel()
		let panel = BrowserActionBarView(viewModel: viewModel)
		let defaultFontSize = (NSTextField().font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)).pointSize
		let expectedFontScale: CGFloat = 1.2

		XCTAssertFalse(panel.queryFieldDrawsBackgroundForTesting)
		XCTAssertEqual(panel.queryFieldBackgroundColorForTesting, .clear)
		XCTAssertEqual(panel.queryFieldFontSizeForTesting, defaultFontSize * expectedFontScale, accuracy: 0.5)
	}

	func testActionBarUsesWindowHostInsteadOfPanel() {
		let viewModel = makeViewModel()
		let panel = BrowserActionBarView(viewModel: viewModel)

		XCTAssertTrue(panel.isHostedInWindowForTesting)
	}

	func testActionBarWindowHasOuterBorder() {
		let viewModel = makeViewModel()
		let panel = BrowserActionBarView(viewModel: viewModel)

		XCTAssertEqual(panel.windowBorderWidthForTesting, 1, accuracy: 0.1)
	}

	func testTypingWhileFocusedDoesNotClearQueryBetweenKeystrokes() async {
		let viewModel = makeViewModel()
		let parentWindow = makeParentWindow()
		let panel = BrowserActionBarView(viewModel: viewModel)
		panel.attach(to: parentWindow)

		viewModel.presentCurrentTab(url: "https://example.test/current")
		await flushPresentationUpdates()

		XCTAssertTrue(panel.isQueryFieldEditingForTesting)

		panel.simulateQueryTextChangeForTesting("h")
		await flushPresentationUpdates()

		XCTAssertEqual(viewModel.query, "h")
		XCTAssertEqual(panel.currentEditorQueryTextForTesting, "h")
		XCTAssertTrue(panel.isQueryFieldEditingForTesting)

		panel.simulateQueryTextChangeForTesting("he")
		await flushPresentationUpdates()

		XCTAssertEqual(viewModel.query, "he")
		XCTAssertEqual(panel.currentEditorQueryTextForTesting, "he")
		XCTAssertTrue(panel.isQueryFieldEditingForTesting)
	}

	func testShortcutForwardingResolverRoutesCommandBrowserShortcutsToMainMenu() {
		let supportedCharacters = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "l", "t", "r", "[", "]", "{", "}"]

		for character in supportedCharacters {
			XCTAssertTrue(
				BrowserActionBarShortcutForwardingResolver.shouldForwardToMainMenu(
					modifiers: [.command],
					normalizedCharacter: character,
					rawCharacter: character
				)
			)
		}
	}

	func testShortcutForwardingResolverRejectsUnsupportedCombinations() {
		XCTAssertFalse(
			BrowserActionBarShortcutForwardingResolver.shouldForwardToMainMenu(
				modifiers: [.command, .option],
				normalizedCharacter: "l",
				rawCharacter: "l"
			)
		)
		XCTAssertFalse(
			BrowserActionBarShortcutForwardingResolver.shouldForwardToMainMenu(
				modifiers: [],
				normalizedCharacter: "l",
				rawCharacter: "l"
			)
		)
		XCTAssertFalse(
			BrowserActionBarShortcutForwardingResolver.shouldForwardToMainMenu(
				modifiers: [.command],
				normalizedCharacter: "k",
				rawCharacter: "k"
			)
		)
	}

	func testShortcutForwardingResolverUsesRawCharacterFallback() {
		XCTAssertTrue(
			BrowserActionBarShortcutForwardingResolver.shouldForwardToMainMenu(
				modifiers: [.command],
				normalizedCharacter: nil,
				rawCharacter: "l"
			)
		)
	}

	func testPerformKeyEquivalentForwardsCommandLToMainMenuWhileEditing() async {
		let viewModel = makeViewModel()
		let parentWindow = makeParentWindow()
		let panel = BrowserActionBarView(viewModel: viewModel)
		panel.attach(to: parentWindow)
		viewModel.presentNewTab()
		await flushPresentationUpdates()
		XCTAssertTrue(panel.isQueryFieldEditingForTesting)

		let menuActionTarget = KeyEquivalentActionTarget()
		let mainMenu = NSMenu()
		let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
		let fileMenu = NSMenu(title: "File")
		let locationItem = NSMenuItem(
			title: "Open Location",
			action: #selector(KeyEquivalentActionTarget.openLocation(_:)),
			keyEquivalent: "l"
		)
		locationItem.target = menuActionTarget
		locationItem.keyEquivalentModifierMask = [.command]
		fileMenu.addItem(locationItem)
		fileMenuItem.submenu = fileMenu
		mainMenu.addItem(fileMenuItem)

		let previousMainMenu = NSApp.mainMenu
		NSApp.mainMenu = mainMenu
		defer {
			NSApp.mainMenu = previousMainMenu
		}

		let keyCode = UInt16(kVK_ANSI_L)
		guard let event = NSEvent.keyEvent(
			with: .keyDown,
			location: .zero,
			modifierFlags: [.command],
			timestamp: ProcessInfo.processInfo.systemUptime,
			windowNumber: panel.windowNumber,
			context: nil,
			characters: "l",
			charactersIgnoringModifiers: "l",
			isARepeat: false,
			keyCode: keyCode
		) else {
			XCTFail("Expected to construct a command+l event")
			return
		}

		XCTAssertTrue(panel.performKeyEquivalent(with: event))
		XCTAssertEqual(menuActionTarget.openLocationInvocationCount, 1)
	}

	func testPerformKeyEquivalentFallsBackToSuperForUnsupportedShortcut() {
		let viewModel = makeViewModel()
		let panel = BrowserActionBarView(viewModel: viewModel)
		let keyCode = UInt16(kVK_ANSI_K)

		guard let event = NSEvent.keyEvent(
			with: .keyDown,
			location: .zero,
			modifierFlags: [.command],
			timestamp: ProcessInfo.processInfo.systemUptime,
			windowNumber: panel.windowNumber,
			context: nil,
			characters: "k",
			charactersIgnoringModifiers: "k",
			isARepeat: false,
			keyCode: keyCode
		) else {
			return XCTFail("Expected to construct a command+k event")
		}

		XCTAssertFalse(panel.performKeyEquivalent(with: event))
	}

	func testOutsideClickHandlersDismissOutsideAndIgnoreInsideClicks() async {
		let viewModel = makeViewModel()
		let parentWindow = makeParentWindow()
		let panel = BrowserActionBarView(viewModel: viewModel)
		panel.attach(to: parentWindow)
		viewModel.presentCurrentTab(url: "https://example.test/outside")
		await flushPresentationUpdates()
		XCTAssertTrue(viewModel.isPresented)

		let insideScreenPoint = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
		panel.simulateGlobalOutsideClickForTesting(screenPoint: insideScreenPoint)
		XCTAssertTrue(viewModel.isPresented)

		let outsideScreenPoint = NSPoint(x: panel.frame.maxX + 100, y: panel.frame.maxY + 100)
		panel.simulateGlobalOutsideClickForTesting(screenPoint: outsideScreenPoint)
		XCTAssertFalse(viewModel.isPresented)

		viewModel.presentCurrentTab(url: "https://example.test/local-inside")
		await flushPresentationUpdates()
		guard let localInsideEvent = makeMouseDownEvent(in: parentWindow, screenPoint: insideScreenPoint) else {
			return XCTFail("Expected inside local mouse event")
		}
		_ = panel.simulateLocalOutsideClickForTesting(localInsideEvent)
		XCTAssertTrue(viewModel.isPresented)

		guard let localOutsideEvent = makeMouseDownEvent(in: parentWindow, screenPoint: outsideScreenPoint) else {
			return XCTFail("Expected outside local mouse event")
		}
		_ = panel.simulateLocalOutsideClickForTesting(localOutsideEvent)
		XCTAssertFalse(viewModel.isPresented)

		viewModel.presentCurrentTab(url: "https://example.test/local-nil-window")
		await flushPresentationUpdates()
		guard let nilWindowEvent = NSEvent.mouseEvent(
			with: .leftMouseDown,
			location: .zero,
			modifierFlags: [],
			timestamp: ProcessInfo.processInfo.systemUptime,
			windowNumber: 0,
			context: nil,
			eventNumber: 0,
			clickCount: 1,
			pressure: 1
		) else {
			return XCTFail("Expected nil-window mouse event")
		}
		_ = panel.simulateLocalOutsideClickForTesting(nilWindowEvent)
		XCTAssertFalse(viewModel.isPresented)
	}

	func testOutsideClickHandlersIgnoreWhenPanelNotVisible() async {
		let viewModel = makeViewModel()
		let parentWindow = makeParentWindow()
		let panel = BrowserActionBarView(viewModel: viewModel)
		panel.attach(to: parentWindow)
		viewModel.presentCurrentTab(url: "https://example.test/visible")
		await flushPresentationUpdates()
		guard let localHandler = panel.captureLocalOutsideClickHandlerForTesting(),
		      let globalHandler = panel.captureGlobalOutsideClickHandlerForTesting() else {
			return XCTFail("Expected outside-click handlers to be installed")
		}
		viewModel.dismiss()
		await flushPresentationUpdates()
		XCTAssertFalse(viewModel.isPresented)

		guard let insideEvent = makeMouseDownEvent(
			in: parentWindow,
			screenPoint: NSPoint(x: panel.frame.midX, y: panel.frame.midY)
		) else {
			return XCTFail("Expected inside local mouse event")
		}
		_ = localHandler(insideEvent)
		globalHandler(NSPoint(x: panel.frame.midX, y: panel.frame.midY))
		XCTAssertFalse(viewModel.isPresented)
	}

	func testOutsideMonitorClosuresDispatchEvents() async {
		let viewModel = makeViewModel()
		let parentWindow = makeParentWindow()
		var panel: BrowserActionBarView? = BrowserActionBarView(viewModel: viewModel)
		guard panel != nil else { return XCTFail("Expected panel") }
		panel?.attach(to: parentWindow)
		viewModel.presentCurrentTab(url: "https://example.test/released")
		await flushPresentationUpdates()

		guard let localOutsideHandler = panel?.captureLocalOutsideClickHandlerForTesting(),
		      let globalOutsideHandler = panel?.captureGlobalOutsideClickHandlerForTesting(),
		      let localMonitorHandler = panel?.captureLocalMonitorEventHandlerForTesting(),
		      let globalMonitorHandler = panel?.captureGlobalMonitorEventHandlerForTesting() else {
			return XCTFail("Expected monitor handlers to be installed")
		}

		let insidePoint = NSPoint(x: panel?.frame.midX ?? 0, y: panel?.frame.midY ?? 0)
		guard let insideEvent = makeMouseDownEvent(in: parentWindow, screenPoint: insidePoint) else {
			return XCTFail("Expected mouse events")
		}

		XCTAssertNotNil(localOutsideHandler(insideEvent))
		globalOutsideHandler(insidePoint)
		XCTAssertNotNil(localMonitorHandler(insideEvent))
		XCTAssertNotNil(panel?.simulateLocalMonitorEventForTesting(insideEvent))
		globalMonitorHandler(insideEvent)
		panel?.simulateGlobalMonitorEventForTesting(insideEvent)
		panel?.removeFromWindow()
		panel = nil
	}

	func testHidePanelInvokesMakeParentKeyWhenPanelWasKeyAndParentNotKey() async {
		let viewModel = makeViewModel()
		let parentWindow = makeParentWindow()
		let panel = BrowserActionBarView(viewModel: viewModel)
		var makeParentKeyInvocationCount = 0
		panel.attach(to: parentWindow)
		viewModel.presentCurrentTab(url: "https://example.test/key-window")
		await flushPresentationUpdates()
		panel.setKeyWindowForTesting(panel)
		panel.setIsParentWindowKeyForTesting { _ in false }
		panel.setMakeParentWindowKeyHandlerForTesting { _ in
			makeParentKeyInvocationCount += 1
		}

		viewModel.dismiss()
		await flushPresentationUpdates()

		XCTAssertEqual(makeParentKeyInvocationCount, 1)
	}

	func testControlTextNotificationsIgnoreNonQueryFieldAndSynchronization() {
		let viewModel = makeViewModel()
		let panel = BrowserActionBarView(viewModel: viewModel)
		let otherField = NSTextField()

		panel.simulateControlTextDidChangeForTesting(object: otherField)
		panel.setKeyWindowForTesting(panel)
		panel.setIsSynchronizingFromViewModelForTesting(true)
		panel.simulateQueryTextChangeForTesting("https://example.test/blocked-change")
		panel.simulateQueryTextDidEndEditingForTesting("https://example.test/blocked-end")
		panel.simulateControlTextDidEndEditingForTesting(object: otherField)

		XCTAssertEqual(viewModel.query, "")

		panel.setIsSynchronizingFromViewModelForTesting(false)
		panel.simulateQueryTextChangeForTesting("https://example.test/allowed-change")
		panel.simulateQueryTextDidEndEditingForTesting("https://example.test/allowed-end")

		XCTAssertEqual(viewModel.query, "https://example.test/allowed-end")
	}

	func testSyncQueryFieldTextSkipsWhenEditorActiveAndForceFalse() async {
		let viewModel = makeViewModel()
		let parentWindow = makeParentWindow()
		let panel = BrowserActionBarView(viewModel: viewModel)
		panel.attach(to: parentWindow)
		viewModel.presentCurrentTab(url: "https://example.test/start")
		await flushPresentationUpdates()
		panel.simulateQueryTextChangeForTesting("typed value")
		viewModel.updateQuery("https://example.test/model-update")

		panel.simulateSyncQueryFieldTextForTesting(force: false)

		XCTAssertEqual(panel.currentEditorQueryTextForTesting, "typed value")
	}

	func testSyncWithViewModelStateCoversModeAndNonEditingRefreshBranches() {
		let viewModel = makeViewModel()
		let panel = BrowserActionBarView(viewModel: viewModel)

		panel.setLastAppliedPresentationSeedForTesting(viewModel.presentationSeed)
		panel.setLastAppliedModeForTesting(.newTab)
		viewModel.updateQuery("https://example.test/mode-change")
		XCTAssertEqual(panel.currentQueryTextForTesting, "https://example.test/mode-change")

		panel.setLastAppliedPresentationSeedForTesting(viewModel.presentationSeed)
		panel.setLastAppliedModeForTesting(viewModel.mode)
		viewModel.updateQuery("https://example.test/non-editing")
		XCTAssertEqual(panel.currentQueryTextForTesting, "https://example.test/non-editing")
	}

	private func makeViewModel(
		onOpenCurrentTab: @escaping (String) -> Void = { _ in },
		onOpenNewTab: @escaping (String) -> Void = { _ in }
	) -> BrowserActionBarViewModel {
		BrowserActionBarViewModel(
			onOpenCurrentTab: onOpenCurrentTab,
			onOpenNewTab: onOpenNewTab
		)
	}

	private func makeParentWindow() -> NSWindow {
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
			styleMask: [.titled, .closable, .resizable],
			backing: .buffered,
			defer: false
		)
		window.makeKeyAndOrderFront(nil)
		addTeardownBlock {
			window.orderOut(nil)
		}
		return window
	}

	private func flushPresentationUpdates() async {
		await Task.yield()
		await Task.yield()
	}

	private func makeMouseDownEvent(in window: NSWindow, screenPoint: NSPoint) -> NSEvent? {
		let locationInWindow = window.convertFromScreen(NSRect(origin: screenPoint, size: .zero)).origin
		return NSEvent.mouseEvent(
			with: .leftMouseDown,
			location: locationInWindow,
			modifierFlags: [],
			timestamp: ProcessInfo.processInfo.systemUptime,
			windowNumber: window.windowNumber,
			context: nil,
			eventNumber: 0,
			clickCount: 1,
			pressure: 1
		)
	}
}

private final class KeyEquivalentActionTarget: NSObject {
	private(set) var openLocationInvocationCount = 0

	@objc func openLocation(_ sender: Any?) {
		openLocationInvocationCount += 1
	}
}
