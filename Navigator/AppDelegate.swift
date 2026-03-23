import AppKit
import BrowserActionBar
import BrowserCameraKit
import BrowserRuntime
import BrowserSidebar
import Foundation
import Inject
import TrackpadGestures
import Vendors

@MainActor
@objc final class NavigatorAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
	@Dependency(\.browserRuntime) private var browserRuntime
	private let navigatorAppViewModel: AppViewModel
	private let hooks: NavigatorAppDelegateHooks
	private var trackpadGestureLifecycle: (any NavigatorTrackpadGestureLifecycle)?
	private var trackpadGestureDiagnosticTask: Task<Void, Never>?
	private var hasStartedTrackpadGestures = false
	private var startBrowserRuntimeAction: () -> Void = {}
	private var shutdownBrowserRuntimeAction: () -> Void = {}
	private(set) var hasStartedBrowserRuntime = false
	private(set) var localKeyboardShortcutMonitor: Any?
	private(set) var globalKeyboardShortcutMonitor: Any?
	private(set) var systemAppearanceObserver: NSObjectProtocol?
	private(set) var lastShortcutActivation = NavigatorKeyboardShortcutActivation()
	private(set) var cameraStatusItemController: (any NavigatorCameraStatusItemControlling)?
	@ObservationIgnored @Shared(.navigatorWindowSize) private var navigatorWindowSize: NavigatorWindowFrame
	private(set) var primaryWindow: NSWindow?
	private(set) var settingsWindowController: NavigatorSettingsWindowController?

	override init() {
		navigatorAppViewModel = appViewModel
		hooks = .init()
		super.init()
		configureRuntimeActions()
	}

	init(
		navigatorAppViewModel: AppViewModel,
		hooks: NavigatorAppDelegateHooks
	) {
		self.navigatorAppViewModel = navigatorAppViewModel
		self.hooks = hooks
		super.init()
		configureRuntimeActions()
	}

	func applicationDidFinishLaunching(_ notification: Notification) {
		NSWindow.allowsAutomaticWindowTabbing = false
		guard hooks.isRunningTests() == false else { return }
		NSApplication.shared.setActivationPolicy(.regular)
		NSApplication.shared.activate(ignoringOtherApps: true)
		startBrowserRuntimeAction()
		hasStartedBrowserRuntime = true
		navigatorAppViewModel.browserActionBarViewModel.dismiss()
		installMainMenu()
		installKeyboardShortcuts()
		installSystemAppearanceObserver()
		NSApplication.shared.windows.forEach { configure(window: $0) }
		createPrimaryWindowIfNeeded()
		refreshAppearanceForAllWindows()
		startTrackpadGesturesIfNeeded()
	}

	func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
		saveWindowState()
		invalidateCameraStatusItemIfNeeded()
		shutdownBrowserRuntimeIfNeeded()
		stopTrackpadGesturesIfNeeded()
		return .terminateNow
	}

	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
		cameraStatusItemController == nil
	}

	func applicationWillTerminate(_ notification: Notification) {
		if let localKeyboardShortcutMonitor {
			hooks.removeEventMonitor(localKeyboardShortcutMonitor)
			self.localKeyboardShortcutMonitor = nil
		}
		if let globalKeyboardShortcutMonitor {
			hooks.removeEventMonitor(globalKeyboardShortcutMonitor)
			self.globalKeyboardShortcutMonitor = nil
		}
		if let systemAppearanceObserver {
			hooks.removeSystemAppearanceObserver(systemAppearanceObserver)
			self.systemAppearanceObserver = nil
		}
		saveWindowState()
		invalidateCameraStatusItemIfNeeded()
		shutdownBrowserRuntimeIfNeeded()
		stopTrackpadGesturesIfNeeded()
	}

	func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
		true
	}

	func application(_ app: NSApplication, shouldSaveApplicationState coder: NSCoder) -> Bool {
		false
	}

	func application(_ app: NSApplication, shouldRestoreApplicationState coder: NSCoder) -> Bool {
		false
	}

	func application(_ application: NSApplication, open urls: [URL]) {
		_ = handleIncomingURLs(urls)
	}

	func application(_ sender: NSApplication, openFiles filenames: [String]) {
		let fileURLs = NavigatorIncomingOpenRequestResolver.fileURLs(from: filenames)
		let didHandleAnyURL = handleIncomingURLs(fileURLs)
		sender.reply(toOpenOrPrint: didHandleAnyURL ? .success : .failure)
	}

	@objc func openLocationBar(_ sender: Any?) {
		ensureBrowserWindowActive()
		activeNavigatorAppViewModel().presentLocationActionBar()
	}

	@objc func openNewWindow(_ sender: Any?) {
		let sourceViewModel = activeNavigatorAppViewModel()
		_ = createBrowserWindow(
			navigatorAppViewModel: AppViewModel(
				sessionPersistence: .sharedWindowSelection,
				sharedTabCollection: sourceViewModel.sharedTabCollection,
				initialSelectedTabID: sourceViewModel.sidebarViewModel.selectedTabID
			),
			isPrimaryWindow: false
		)
	}

	@objc func openNewTabBar(_ sender: Any?) {
		ensureBrowserWindowActive()
		activeNavigatorAppViewModel().presentNewTabActionBar()
	}

	@objc func closeCurrentTab(_ sender: Any?) {
		activeNavigatorAppViewModel().sidebarViewModel.closeSelectedTab()
	}

	@objc func reopenLastClosedTab(_ sender: Any?) {
		ensureBrowserWindowActive()
		activeNavigatorAppViewModel().sidebarViewModel.reopenLastClosedTab()
	}

	@objc func copyCurrentTabURL(_ sender: Any?) {
		copySelectedTabURLToPasteboard()
	}

	@objc func showSettingsWindow(_ sender: Any?) {
		toggleSettingsWindow()
	}

	func toggleSettingsWindow() {
		let settingsWindow = settingsWindowController?.window
		let action = NavigatorSettingsWindowToggleResolver.resolveAction(
			hasSettingsWindow: settingsWindow != nil,
			isVisible: settingsWindow?.isVisible ?? false,
			isMiniaturized: settingsWindow?.isMiniaturized ?? false
		)
		switch action {
		case .open:
			openSettingsWindow()
		case .close:
			settingsWindow?.orderOut(nil)
		}
	}

	func openSettingsWindow() {
		let controller = settingsWindowController ?? makeSettingsWindowController()
		settingsWindowController = controller
		controller.window?.delegate = self
		NSApp.activate(ignoringOtherApps: true)
		controller.showWindow(nil)
		controller.window?.makeKeyAndOrderFront(nil)
	}

	func handleIncomingURLs(_ urls: [URL]) -> Bool {
		let navigableURLs = NavigatorIncomingOpenRequestResolver.urlStrings(from: urls)
		guard navigableURLs.isEmpty == false else { return false }

		createPrimaryWindowIfNeeded()
		ensureBrowserWindowActive()
		activeNavigatorAppViewModel().openIncomingURLsInNewTabs(navigableURLs)
		return true
	}

	func makeSettingsWindowController() -> NavigatorSettingsWindowController {
		NavigatorSettingsWindowController(
			navigatorAppViewModel: navigatorAppViewModel,
			resolveAnchorWindow: { [weak self] in
				self?.preferredBrowserWindow()
			}
		)
	}

	func installMainMenu() {
		let mainMenu = NSMenu()

		let appMenu = NSMenu(title: "Navigator")
		let settingsMenuItem = NSMenuItem(
			title: String(localized: .navigatorSettingsMenuTitle),
			action: #selector(showSettingsWindow(_:)),
			keyEquivalent: ","
		)
		settingsMenuItem.target = self
		settingsMenuItem.keyEquivalentModifierMask = [.command]
		appMenu.addItem(settingsMenuItem)
		appMenu.addItem(.separator())
		appMenu.addItem(withTitle: "Quit Navigator", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
		addSubmenu(appMenu, titled: "Navigator", to: mainMenu)

		let fileMenu = NSMenu(title: "File")
		let openNewWindowMenuItem = NSMenuItem(
			title: String(localized: .navigatorFileMenuNewWindow),
			action: #selector(openNewWindow(_:)),
			keyEquivalent: "n"
		)
		openNewWindowMenuItem.target = self
		openNewWindowMenuItem.keyEquivalentModifierMask = [.command]
		fileMenu.addItem(openNewWindowMenuItem)

		let openNewTabMenuItem = NSMenuItem(
			title: "New Tab",
			action: #selector(openNewTabBar(_:)),
			keyEquivalent: "t"
		)
		openNewTabMenuItem.target = self
		openNewTabMenuItem.keyEquivalentModifierMask = [.command]
		fileMenu.addItem(openNewTabMenuItem)

		let closeCurrentTabMenuItem = NSMenuItem(
			title: "Close Tab",
			action: #selector(closeCurrentTab(_:)),
			keyEquivalent: "w"
		)
		closeCurrentTabMenuItem.target = self
		closeCurrentTabMenuItem.keyEquivalentModifierMask = [.command]
		fileMenu.addItem(closeCurrentTabMenuItem)

		let reopenLastClosedTabMenuItem = NSMenuItem(
			title: String(localized: LocalizedStringResource.navigatorFileMenuReopenClosedTab),
			action: #selector(reopenLastClosedTab(_:)),
			keyEquivalent: "t"
		)
		reopenLastClosedTabMenuItem.target = self
		reopenLastClosedTabMenuItem.keyEquivalentModifierMask = NSEvent.ModifierFlags(
			rawValue: NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue
		)
		fileMenu.addItem(reopenLastClosedTabMenuItem)

		let openLocationMenuItem = NSMenuItem(
			title: "Open Location",
			action: #selector(openLocationBar(_:)),
			keyEquivalent: "l"
		)
		openLocationMenuItem.target = self
		openLocationMenuItem.keyEquivalentModifierMask = [.command]
		fileMenu.addItem(openLocationMenuItem)
		addSubmenu(fileMenu, titled: "File", to: mainMenu)
		addSubmenu(makeEditMenu(), titled: String(localized: .navigatorMenuEditTitle), to: mainMenu)

		NSApp.mainMenu = mainMenu
	}

	private func addSubmenu(_ submenu: NSMenu, titled title: String, to menu: NSMenu) {
		let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
		menu.addItem(item)
		menu.setSubmenu(submenu, for: item)
	}

	private func makeEditMenu() -> NSMenu {
		let editMenu = NSMenu(title: String(localized: .navigatorMenuEditTitle))
		editMenu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditUndo),
			action: Selector(("undo:")),
			keyEquivalent: "z",
			modifiers: [.command]
		))
		editMenu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditRedo),
			action: Selector(("redo:")),
			keyEquivalent: "Z",
			modifiers: [.command, .shift]
		))
		editMenu.addItem(.separator())
		editMenu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditCut),
			action: #selector(NSText.cut(_:)),
			keyEquivalent: "x",
			modifiers: [.command]
		))
		editMenu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditCopy),
			action: #selector(NSText.copy(_:)),
			keyEquivalent: "c",
			modifiers: [.command]
		))
		editMenu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditPaste),
			action: #selector(NSText.paste(_:)),
			keyEquivalent: "v",
			modifiers: [.command]
		))
		editMenu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditPasteAndMatchStyle),
			action: #selector(NSTextView.pasteAsPlainText(_:)),
			keyEquivalent: "V",
			modifiers: [.command, .option, .shift]
		))
		editMenu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditDelete),
			action: #selector(NSText.delete(_:)),
			keyEquivalent: ""
		))
		editMenu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditSelectAll),
			action: #selector(NSResponder.selectAll(_:)),
			keyEquivalent: "a",
			modifiers: [.command]
		))
		editMenu.addItem(.separator())
		addSubmenu(makeFindMenu(), titled: String(localized: .navigatorMenuEditFindTitle), to: editMenu)
		addSubmenu(makeSpellingAndGrammarMenu(), titled: String(localized: .navigatorMenuEditSpellingTitle), to: editMenu)
		addSubmenu(makeSubstitutionsMenu(), titled: String(localized: .navigatorMenuEditSubstitutionsTitle), to: editMenu)
		addSubmenu(makeTransformationsMenu(), titled: String(localized: .navigatorMenuEditTransformationsTitle), to: editMenu)
		addSubmenu(makeSpeechMenu(), titled: String(localized: .navigatorMenuEditSpeechTitle), to: editMenu)
		editMenu.addItem(.separator())
		addSubmenu(makeFontMenu(), titled: String(localized: .navigatorMenuEditFontTitle), to: editMenu)
		addSubmenu(
			makeWritingDirectionMenu(),
			titled: String(localized: .navigatorMenuEditWritingDirectionTitle),
			to: editMenu
		)
		addSubmenu(
			makeLayoutOrientationMenu(),
			titled: String(localized: .navigatorMenuEditLayoutOrientationTitle),
			to: editMenu
		)
		return editMenu
	}

	private func makeFindMenu() -> NSMenu {
		let findMenu = NSMenu(title: String(localized: .navigatorMenuEditFindTitle))
		findMenu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditFind),
			action: #selector(NSTextView.performFindPanelAction(_:)),
			keyEquivalent: "f",
			modifiers: [.command],
			tag: NSTextFinder.Action.showFindInterface.rawValue
		))
		findMenu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditFindAndReplace),
			action: #selector(NSTextView.performFindPanelAction(_:)),
			keyEquivalent: "f",
			modifiers: [.command, .option],
			tag: NSTextFinder.Action.showReplaceInterface.rawValue
		))
		findMenu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditFindNext),
			action: #selector(NSTextView.performFindPanelAction(_:)),
			keyEquivalent: "g",
			modifiers: [.command],
			tag: NSTextFinder.Action.nextMatch.rawValue
		))
		findMenu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditFindPrevious),
			action: #selector(NSTextView.performFindPanelAction(_:)),
			keyEquivalent: "G",
			modifiers: [.command, .shift],
			tag: NSTextFinder.Action.previousMatch.rawValue
		))
		findMenu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditFindUseSelection),
			action: #selector(NSTextView.performFindPanelAction(_:)),
			keyEquivalent: "e",
			modifiers: [.command],
			tag: NSTextFinder.Action.setSearchString.rawValue
		))
		return findMenu
	}

	private func makeSpellingAndGrammarMenu() -> NSMenu {
		let menu = NSMenu(title: String(localized: .navigatorMenuEditSpellingTitle))
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditSpellingShow),
			action: #selector(NSText.showGuessPanel(_:)),
			keyEquivalent: ":",
			modifiers: [.command]
		))
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditSpellingCheckNow),
			action: #selector(NSText.checkSpelling(_:)),
			keyEquivalent: ";",
			modifiers: [.command]
		))
		menu.addItem(.separator())
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditSpellingCheckWhileTyping),
			action: #selector(NSTextView.toggleContinuousSpellChecking(_:)),
			keyEquivalent: ""
		))
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditSpellingCheckGrammar),
			action: #selector(NSTextView.toggleGrammarChecking(_:)),
			keyEquivalent: ""
		))
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditSpellingCorrectAutomatically),
			action: #selector(NSTextView.toggleAutomaticSpellingCorrection(_:)),
			keyEquivalent: ""
		))
		return menu
	}

	private func makeSubstitutionsMenu() -> NSMenu {
		let menu = NSMenu(title: String(localized: .navigatorMenuEditSubstitutionsTitle))
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditSubstitutionsReplaceQuotes),
			action: #selector(NSTextView.toggleAutomaticQuoteSubstitution(_:)),
			keyEquivalent: ""
		))
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditSubstitutionsReplaceDashes),
			action: #selector(NSTextView.toggleAutomaticDashSubstitution(_:)),
			keyEquivalent: ""
		))
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditSubstitutionsAddLinks),
			action: #selector(NSTextView.toggleAutomaticLinkDetection(_:)),
			keyEquivalent: ""
		))
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditSubstitutionsReplaceText),
			action: #selector(NSTextView.toggleAutomaticTextReplacement(_:)),
			keyEquivalent: ""
		))
		menu.addItem(.separator())
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditSubstitutionsShow),
			action: #selector(NSTextView.orderFrontSubstitutionsPanel(_:)),
			keyEquivalent: ""
		))
		menu.addItem(.separator())
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditSubstitutionsSmartCopyPaste),
			action: #selector(NSTextView.toggleSmartInsertDelete(_:)),
			keyEquivalent: ""
		))
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditSubstitutionsSmartQuotes),
			action: #selector(NSTextView.toggleAutomaticQuoteSubstitution(_:)),
			keyEquivalent: ""
		))
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditSubstitutionsSmartDashes),
			action: #selector(NSTextView.toggleAutomaticDashSubstitution(_:)),
			keyEquivalent: ""
		))
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditSubstitutionsSmartLinks),
			action: #selector(NSTextView.toggleAutomaticLinkDetection(_:)),
			keyEquivalent: ""
		))
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditSubstitutionsDataDetectors),
			action: #selector(NSTextView.toggleAutomaticDataDetection(_:)),
			keyEquivalent: ""
		))
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditSubstitutionsTextReplacement),
			action: #selector(NSTextView.toggleAutomaticTextReplacement(_:)),
			keyEquivalent: ""
		))
		return menu
	}

	private func makeTransformationsMenu() -> NSMenu {
		let menu = NSMenu(title: String(localized: .navigatorMenuEditTransformationsTitle))
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditTransformationsUppercase),
			action: #selector(NSResponder.uppercaseWord(_:)),
			keyEquivalent: ""
		))
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditTransformationsLowercase),
			action: #selector(NSStandardKeyBindingResponding.lowercaseWord(_:)),
			keyEquivalent: ""
		))
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditTransformationsCapitalize),
			action: #selector(NSStandardKeyBindingResponding.capitalizeWord(_:)),
			keyEquivalent: ""
		))
		return menu
	}

	private func makeSpeechMenu() -> NSMenu {
		let menu = NSMenu(title: String(localized: .navigatorMenuEditSpeechTitle))
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditSpeechStart),
			action: #selector(NSTextView.startSpeaking(_:)),
			keyEquivalent: ""
		))
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditSpeechStop),
			action: #selector(NSTextView.stopSpeaking(_:)),
			keyEquivalent: ""
		))
		return menu
	}

	private func makeFontMenu() -> NSMenu {
		let menu = NSMenu(title: String(localized: .navigatorMenuEditFontTitle))
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditFontShow),
			action: #selector(NSFontManager.orderFrontFontPanel(_:)),
			keyEquivalent: "t",
			modifiers: [.command]
		))
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditFontBold),
			action: #selector(NSFontManager.addFontTrait(_:)),
			keyEquivalent: "b",
			modifiers: [.command],
			tag: Int(NSFontTraitMask.boldFontMask.rawValue)
		))
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditFontItalic),
			action: #selector(NSFontManager.addFontTrait(_:)),
			keyEquivalent: "i",
			modifiers: [.command],
			tag: Int(NSFontTraitMask.italicFontMask.rawValue)
		))
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditFontUnderline),
			action: #selector(NSText.underline(_:)),
			keyEquivalent: "u",
			modifiers: [.command]
		))
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditFontOutline),
			action: #selector(NSTextView.outline(_:)),
			keyEquivalent: ""
		))
		if #available(macOS 15.0, *) {
			menu.addItem(makeMenuItem(
				title: String(localized: .navigatorMenuEditFontHighlight),
				action: #selector(NSTextView.highlight(_:)),
				keyEquivalent: ""
			))
		}
		else {
			menu.addItem(makeMenuItem(
				title: String(localized: .navigatorMenuEditFontHighlight),
				action: #selector(NSTextView.changeDocumentBackgroundColor(_:)),
				keyEquivalent: ""
			))
		}
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditFontStyles),
			action: #selector(NSFontManager.orderFrontStylesPanel(_:)),
			keyEquivalent: ""
		))
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditFontShowColors),
			action: #selector(NSApplication.orderFrontColorPanel(_:)),
			keyEquivalent: ""
		))
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditFontFormat),
			action: #selector(NSFontManager.orderFrontStylesPanel(_:)),
			keyEquivalent: ""
		))
		return menu
	}

	private func makeWritingDirectionMenu() -> NSMenu {
		let menu = NSMenu(title: String(localized: .navigatorMenuEditWritingDirectionTitle))
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditWritingDirectionParagraph),
			action: nil,
			keyEquivalent: ""
		))
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditWritingDirectionParagraphDefault),
			action: #selector(NSResponder.makeBaseWritingDirectionNatural(_:)),
			keyEquivalent: "",
			indentationLevel: 1
		))
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditWritingDirectionParagraphLeftToRight),
			action: #selector(NSResponder.makeBaseWritingDirectionLeftToRight(_:)),
			keyEquivalent: "\u{2192}",
			modifiers: [.control, .command],
			indentationLevel: 1
		))
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditWritingDirectionParagraphRightToLeft),
			action: #selector(NSResponder.makeBaseWritingDirectionRightToLeft(_:)),
			keyEquivalent: "\u{2190}",
			modifiers: [.control, .command],
			indentationLevel: 1
		))
		menu.addItem(.separator())
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditWritingDirectionSelection),
			action: nil,
			keyEquivalent: ""
		))
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditWritingDirectionSelectionDefault),
			action: #selector(NSResponder.makeBaseWritingDirectionNatural(_:)),
			keyEquivalent: "\u{2193}",
			modifiers: [.control, .option, .command],
			indentationLevel: 1
		))
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditWritingDirectionSelectionLeftToRight),
			action: #selector(NSResponder.makeBaseWritingDirectionLeftToRight(_:)),
			keyEquivalent: "\u{2192}",
			modifiers: [.control, .option, .command],
			indentationLevel: 1
		))
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditWritingDirectionSelectionRightToLeft),
			action: #selector(NSResponder.makeBaseWritingDirectionRightToLeft(_:)),
			keyEquivalent: "\u{2190}",
			modifiers: [.control, .option, .command],
			indentationLevel: 1
		))
		return menu
	}

	private func makeLayoutOrientationMenu() -> NSMenu {
		let menu = NSMenu(title: String(localized: .navigatorMenuEditLayoutOrientationTitle))
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditLayoutOrientationHorizontal),
			action: #selector(NSTextView.changeLayoutOrientation(_:)),
			keyEquivalent: "",
			tag: NSLayoutManager.TextLayoutOrientation.horizontal.rawValue
		))
		menu.addItem(makeMenuItem(
			title: String(localized: .navigatorMenuEditLayoutOrientationVertical),
			action: #selector(NSTextView.changeLayoutOrientation(_:)),
			keyEquivalent: "",
			tag: NSLayoutManager.TextLayoutOrientation.vertical.rawValue
		))
		return menu
	}

	private func makeMenuItem(
		title: String,
		action: Selector?,
		keyEquivalent: String,
		modifiers: NSEvent.ModifierFlags = [],
		tag: Int = 0,
		indentationLevel: Int = 0
	) -> NSMenuItem {
		let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
		item.keyEquivalentModifierMask = modifiers
		item.tag = tag
		item.indentationLevel = indentationLevel
		return item
	}

	func installKeyboardShortcuts() {
		installLocalShortcutMonitor()
		installGlobalShortcutMonitor()
	}

	func installSystemAppearanceObserver() {
		systemAppearanceObserver = hooks.addSystemAppearanceObserver { [weak self] _ in
			self?.refreshAppearanceForAllWindows()
		}
	}

	func refreshAppearanceForAllWindows() {
		for window in NSApplication.shared.windows {
			WindowChromeStyler.applyResolvedColors(to: window)
			(window.contentViewController as? BrowserRootViewController)?.refreshAppearance()
		}
	}

	func installLocalShortcutMonitor() {
		localKeyboardShortcutMonitor = hooks.addLocalKeyDownMonitor { [weak self] event in
			guard let self else { return event }
			if self.handleShortcutEvent(event) {
				return nil
			}
			return event
		}
	}

	func installGlobalShortcutMonitor() {
		globalKeyboardShortcutMonitor = hooks.addGlobalKeyDownMonitor { [weak self] event in
			_ = self?.handleShortcutEvent(event)
		}
	}

	func handleShortcutEvent(_ event: NSEvent) -> Bool {
		let modifiers = event.modifierFlags
		let normalizedCharacter = event.charactersIgnoringModifiers?.lowercased()
		let rawCharacter = event.characters?.lowercased()
		let keyCode = event.keyCode

		guard
			let action = NavigatorKeyboardShortcutResolver.resolveAction(
				for: keyCode,
				modifiers: modifiers,
				normalizedCharacter: normalizedCharacter,
				rawCharacter: rawCharacter
			)
		else {
			return false
		}

		if action == .closeCurrentTab,
		   hooks.isSettingsWindowFocused() {
			return false
		}

		let now = event.timestamp
		guard lastShortcutActivation.shouldHandle(for: action, at: now) else {
			return true
		}

		invokeKeyboardShortcutAction { [weak self] in
			self?.keyboardShortcutHandler.perform(action)
		}
		return true
	}

	func invokeKeyboardShortcutAction(_ action: @escaping () -> Void) {
		if Thread.isMainThread {
			action()
		}
		else {
			DispatchQueue.main.async {
				action()
			}
		}
	}

	@MainActor
	var keyboardShortcutHandler: NavigatorKeyboardShortcutHandler {
		NavigatorKeyboardShortcutHandler(
			openNewWindow: { [weak self] in
				self?.openNewWindow(nil)
			},
			openLocation: { [weak self] in
				self?.openLocationBar(nil)
			},
			openNewTab: { [weak self] in
				self?.openNewTabBar(nil)
			},
			reopenLastClosedTab: { [weak self] in
				self?.reopenLastClosedTab(nil)
			},
			closeCurrentTab: { [weak self] in
				self?.activeNavigatorAppViewModel().sidebarViewModel.closeSelectedTab()
			},
			togglePinSelectedTab: { [weak self] in
				self?.toggleSelectedTabPin()
			},
			copyCurrentTabURL: { [weak self] in
				self?.copySelectedTabURLToPasteboard()
			},
			reload: { [weak self] in
				self?.activeNavigatorAppViewModel().sidebarViewModel.reload()
			},
			goBack: { [weak self] in
				self?.activeNavigatorAppViewModel().sidebarViewModel.goBack()
			},
			goForward: { [weak self] in
				self?.activeNavigatorAppViewModel().sidebarViewModel.goForward()
			},
			selectNextTab: { [weak self] in
				self?.activeNavigatorAppViewModel().sidebarViewModel.selectNextTab()
			},
			selectPreviousTab: { [weak self] in
				self?.activeNavigatorAppViewModel().sidebarViewModel.selectPreviousTab()
			},
			selectTabAtIndex: { [weak self] index in
				self?.activeNavigatorAppViewModel().sidebarViewModel.selectTab(at: index)
			}
		)
	}

	private func copySelectedTabURLToPasteboard() {
		guard
			let selectedTabURL = activeNavigatorAppViewModel().sidebarViewModel.selectedTabCurrentURL,
			selectedTabURL.isEmpty == false
		else {
			print("[Navigator] CMD+Shift+C acknowledged but no current tab URL available")
			return
		}

		let pasteboard = NSPasteboard.general
		pasteboard.clearContents()
		pasteboard.setString(selectedTabURL, forType: .string)
		activeNavigatorAppViewModel().presentToast(
			title: .navigatorToastCopyCurrentTabURLTitle,
			body: .navigatorToastCopyCurrentTabURLBody
		)
		print("[Navigator] CMD+Shift+C acknowledged: copied current tab URL")
	}

	private func toggleSelectedTabPin() {
		let appViewModel = activeNavigatorAppViewModel()
		guard let selectedTabID = appViewModel.sidebarViewModel.selectedTabID,
		      let selectedTab = appViewModel.sidebarViewModel.tabs.first(where: { $0.id == selectedTabID }) else {
			return
		}

		let wasPinned = selectedTab.isPinned
		appViewModel.sidebarViewModel.toggleSelectedTabPin()
		let toastTitle: LocalizedStringResource = wasPinned
			? .navigatorToastUnpinnedTabTitle
			: .navigatorToastPinnedTabTitle
		appViewModel.presentToast(title: toastTitle)
	}

	func createPrimaryWindowIfNeeded() {
		if primaryWindow != nil { return }
		primaryWindow = createBrowserWindow(
			navigatorAppViewModel: navigatorAppViewModel,
			isPrimaryWindow: true
		)
	}

	func configure(window: NSWindow, shouldRestoreWindowState: Bool = true) {
		window.isRestorable = false
		window.delegate = self
		window.minSize = NavigatorBrowserWindowSizing.minimumFrameSize
		WindowChromeStyler.apply(to: window)
		if shouldRestoreWindowState {
			restoreWindowState(for: window)
		}
	}

	func saveWindowState() {
		guard let window = primaryWindow else { return }
		saveWindowFrame(for: window)
	}

	func windowDidMove(_ notification: Notification) {
		savePrimaryWindowFrameIfNeeded(notification)
	}

	func windowDidResize(_ notification: Notification) {
		savePrimaryWindowFrameIfNeeded(notification)
	}

	func windowWillClose(_ notification: Notification) {
		savePrimaryWindowFrameIfNeeded(notification)
		guard let window = notification.object as? NSWindow else { return }
		if window === primaryWindow {
			primaryWindow = nextBrowserWindow(excluding: window)
		}
		if window === settingsWindowController?.window {
			settingsWindowController?.invalidate()
			settingsWindowController = nil
			invalidateCameraStatusItemIfNeeded()
		}
	}

	func shutdownBrowserRuntimeIfNeeded() {
		guard hasStartedBrowserRuntime else { return }
		shutdownBrowserRuntimeAction()
		hasStartedBrowserRuntime = false
	}

	private func startTrackpadGesturesIfNeeded() {
		guard hasStartedTrackpadGestures == false else { return }
		if trackpadGestureLifecycle == nil {
			let fallbackNavigatorAppViewModel = navigatorAppViewModel
			trackpadGestureLifecycle = hooks.makeTrackpadGestureLifecycle { [weak self, fallbackNavigatorAppViewModel] in
				self?.activeNavigatorAppViewModel() ?? fallbackNavigatorAppViewModel
			}
		}
		guard let trackpadGestureLifecycle else { return }
		hasStartedTrackpadGestures = true
		if trackpadGestureDiagnosticTask == nil {
			trackpadGestureDiagnosticTask = Task { @MainActor [weak self] in
				guard let self, let trackpadGestureLifecycle = self.trackpadGestureLifecycle else { return }
				let diagnostics = await trackpadGestureLifecycle.diagnosticEvents()
				for await diagnosticEvent in diagnostics {
					self.hooks.logTrackpadGestureDiagnosticEvent(diagnosticEvent)
				}
			}
		}
		trackpadGestureLifecycle.start()
	}

	private func stopTrackpadGesturesIfNeeded() {
		guard hasStartedTrackpadGestures else { return }
		hasStartedTrackpadGestures = false
		trackpadGestureLifecycle?.stop()
		trackpadGestureDiagnosticTask?.cancel()
		trackpadGestureDiagnosticTask = nil
	}

	private func configureRuntimeActions() {
		if let startBrowserRuntime = hooks.startBrowserRuntime {
			startBrowserRuntimeAction = startBrowserRuntime
		}
		else {
			let browserRuntime = self.browserRuntime
			startBrowserRuntimeAction = {
				browserRuntime.start()
			}
		}

		if let shutdownBrowserRuntime = hooks.shutdownBrowserRuntime {
			shutdownBrowserRuntimeAction = shutdownBrowserRuntime
		}
		else {
			let browserRuntime = self.browserRuntime
			shutdownBrowserRuntimeAction = {
				browserRuntime.shutdown()
			}
		}
	}

	private func createBrowserWindow(
		navigatorAppViewModel: AppViewModel,
		isPrimaryWindow: Bool
	) -> NSWindow {
		let persistedFrame = loadPersistedNavigatorWindowFrame()
		let window = NSWindow(
			contentRect: NSRect(origin: .zero, size: NavigatorBrowserWindowSizing.defaultFrameSize),
			styleMask: [
				.titled,
				.closable,
				.resizable,
				.miniaturizable,
			],
			backing: .buffered,
			defer: false
		)
		window.contentViewController = hooks.makePrimaryContentViewController(
			UUID(),
			navigatorAppViewModel
		)
		let fallbackFrame = NSRect(origin: .zero, size: NavigatorBrowserWindowSizing.defaultFrameSize)
		let startupFrame = isPrimaryWindow
			? primaryWindowStartupFrame(for: window, persistedFrame: persistedFrame)
			: restoredWindowFrame(
				for: persistedFrame,
				attachedScreenVisibleFrame: nil,
				mainScreenVisibleFrame: NSScreen.main?.visibleFrame,
				screenVisibleFrames: NSScreen.screens.map(\.visibleFrame),
				fallbackFrame: fallbackFrame
			)
		configure(window: window, shouldRestoreWindowState: false)
		window.setFrame(startupFrame, display: false)
		NSApp.activate(ignoringOtherApps: true)
		window.makeKeyAndOrderFront(nil)
		return window
	}

	private func browserWindowContent(for window: NSWindow?) -> (NSViewController & NavigatorBrowserWindowContent)? {
		window?.contentViewController as? (NSViewController & NavigatorBrowserWindowContent)
	}

	private func preferredBrowserWindow() -> NSWindow? {
		for candidate in [NSApp.keyWindow, NSApp.mainWindow] {
			if let candidate, browserWindowContent(for: candidate) != nil {
				return candidate
			}
		}
		if let orderedBrowserWindow = NSApp.orderedWindows.first(where: { browserWindowContent(for: $0) != nil }) {
			return orderedBrowserWindow
		}
		if let primaryWindow, browserWindowContent(for: primaryWindow) != nil {
			return primaryWindow
		}
		return nextBrowserWindow(excluding: nil)
	}

	private func nextBrowserWindow(excluding excludedWindow: NSWindow?) -> NSWindow? {
		NSApp.windows.first { window in
			window !== excludedWindow && browserWindowContent(for: window) != nil
		}
	}

	@discardableResult
	private func ensureBrowserWindowActive() -> NSWindow? {
		createPrimaryWindowIfNeeded()
		guard let window = preferredBrowserWindow() else { return nil }
		NSApp.activate(ignoringOtherApps: true)
		if window.isMiniaturized {
			window.deminiaturize(nil)
		}
		window.makeKeyAndOrderFront(nil)
		return window
	}

	private func activeNavigatorAppViewModel() -> AppViewModel {
		if let navigatorAppViewModel = browserWindowContent(for: preferredBrowserWindow())?.navigatorAppViewModel {
			return navigatorAppViewModel
		}
		return navigatorAppViewModel
	}

	func saveWindowFrame(for window: NSWindow) {
		let frame = window.frame
		let persistedFrame = NavigatorWindowFrame(
			origin: frame.origin,
			size: NSSize(
				width: max(frame.size.width, NavigatorBrowserWindowSizing.minimumFrameWidth),
				height: max(frame.size.height, NavigatorBrowserWindowSizing.minimumFrameHeight)
			)
		)
		$navigatorWindowSize.withLock { persisted in
			persisted = persistedFrame
		}
		try? persistNavigatorWindowFrame(persistedFrame)
		if window === primaryWindow {
			window.saveFrame(usingName: NavigatorWindowPersistenceKeys.primaryFrameAutosaveName)
		}
	}

	func restoreWindowState(for window: NSWindow) {
		let saved = loadPersistedNavigatorWindowFrame()
		window.setFrame(
			restoredWindowFrame(
				for: saved,
				attachedScreenVisibleFrame: window.screen?.visibleFrame,
				mainScreenVisibleFrame: NSScreen.main?.visibleFrame,
				screenVisibleFrames: NSScreen.screens.map(\.visibleFrame),
				fallbackFrame: window.frame
			),
			display: false
		)
	}

	func primaryWindowStartupFrame(
		for window: NSWindow,
		persistedFrame: NavigatorWindowFrame
	) -> NSRect {
		let fallbackFrame = NSRect(origin: .zero, size: NavigatorBrowserWindowSizing.defaultFrameSize)
		let hasPersistedFrame = persistedFrame != NavigatorWindowFrame()
		let startupFrameSource: NavigatorWindowFrame
		if hasPersistedFrame {
			startupFrameSource = persistedFrame
		}
		else if window.setFrameUsingName(NavigatorWindowPersistenceKeys.primaryFrameAutosaveName, force: false) {
			let autosavedFrame = window.frame
			startupFrameSource = NavigatorWindowFrame(
				origin: autosavedFrame.origin,
				size: autosavedFrame.size
			)
		}
		else {
			startupFrameSource = persistedFrame
		}

		return restoredWindowFrame(
			for: startupFrameSource,
			attachedScreenVisibleFrame: nil,
			mainScreenVisibleFrame: NSScreen.main?.visibleFrame,
			screenVisibleFrames: NSScreen.screens.map(\.visibleFrame),
			fallbackFrame: fallbackFrame
		)
	}

	func restoredWindowFrame(
		for saved: NavigatorWindowFrame,
		attachedScreenVisibleFrame: NSRect?,
		mainScreenVisibleFrame: NSRect?,
		screenVisibleFrames: [NSRect],
		fallbackFrame: NSRect
	) -> NSRect {
		let savedFrame = NSRect(origin: saved.origin, size: saved.size)
		let screenFrame = Self.resolvedVisibleFrame(
			attachedScreenVisibleFrame: attachedScreenVisibleFrame,
			mainScreenVisibleFrame: mainScreenVisibleFrame,
			screenVisibleFrames: screenVisibleFrames,
			preferredFrame: savedFrame,
			fallbackFrame: fallbackFrame
		)
		let clampedWidth = min(
			max(saved.size.width, NavigatorBrowserWindowSizing.minimumFrameWidth),
			screenFrame.width
		)
		let clampedHeight = min(
			max(saved.size.height, NavigatorBrowserWindowSizing.minimumFrameHeight),
			screenFrame.height
		)
		let clampedSize = NSSize(width: clampedWidth, height: clampedHeight)
		let maximumX = max(screenFrame.minX, screenFrame.maxX - clampedSize.width)
		let maximumY = max(screenFrame.minY, screenFrame.maxY - clampedSize.height)
		let clampedX = min(max(saved.origin.x, screenFrame.minX), maximumX)
		let clampedY = min(max(saved.origin.y, screenFrame.minY), maximumY)
		return NSRect(origin: NSPoint(x: clampedX, y: clampedY), size: clampedSize)
	}

	static func resolvedVisibleFrame(
		attachedScreenVisibleFrame: NSRect?,
		mainScreenVisibleFrame: NSRect?,
		screenVisibleFrames: [NSRect],
		preferredFrame: NSRect,
		fallbackFrame: NSRect
	) -> NSRect {
		if let attachedScreenVisibleFrame {
			return attachedScreenVisibleFrame
		}
		if let matchingScreenFrame = bestMatchingVisibleFrame(
			for: preferredFrame,
			screenVisibleFrames: screenVisibleFrames
		) {
			return matchingScreenFrame
		}
		if let mainScreenVisibleFrame {
			return mainScreenVisibleFrame
		}
		return fallbackFrame
	}

	static func bestMatchingVisibleFrame(
		for preferredFrame: NSRect,
		screenVisibleFrames: [NSRect]
	) -> NSRect? {
		screenVisibleFrames
			.map { screenFrame in
				(screenFrame, screenFrame.intersection(preferredFrame).area)
			}
			.filter { _, intersectionArea in
				intersectionArea > 0
			}
			.max { lhs, rhs in
				lhs.1 < rhs.1
			}?
			.0
			?? screenVisibleFrames.first(where: { $0.contains(preferredFrame.origin) })
	}

	private func savePrimaryWindowFrameIfNeeded(_ notification: Notification) {
		guard
			let window = notification.object as? NSWindow,
			window === primaryWindow
		else { return }
		saveWindowFrame(for: window)
	}

	private func invalidateCameraStatusItemIfNeeded() {
		cameraStatusItemController?.invalidate()
		cameraStatusItemController = nil
	}
}

private extension NSRect {
	var area: CGFloat {
		guard isNull == false else { return 0 }
		return width * height
	}
}
