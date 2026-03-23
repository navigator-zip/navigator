import AppKit
import Carbon.HIToolbox
import Foundation

enum NavigatorKeyboardShortcutAction: Equatable {
	case openNewWindow
	case openLocation
	case openNewTab
	case reopenLastClosedTab
	case closeCurrentTab
	case togglePinSelectedTab
	case copyCurrentTabURL
	case reload
	case goBack
	case goForward
	case selectNextTab
	case selectPreviousTab
	case selectTab(index: Int)
}

enum NavigatorKeyboardShortcutResolver {
	static func resolveAction(
		for keyCode: UInt16,
		modifiers: NSEvent.ModifierFlags,
		normalizedCharacter: String?,
		rawCharacter: String?
	) -> NavigatorKeyboardShortcutAction? {
		let supportedModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
		guard hasSupportedCommandModifiers(supportedModifiers) else { return nil }

		let usesShift = supportedModifiers.contains(.shift)

		switch (keyCode, usesShift) {
		case (commandNShortcut, false):
			return .openNewWindow
		case (commandLShortcut, false):
			return .openLocation
		case (commandTShortcut, false):
			return .openNewTab
		case (commandTShortcut, true):
			return .reopenLastClosedTab
		case (commandPShortcut, false):
			return .togglePinSelectedTab
		case (commandWShortcut, false):
			return .closeCurrentTab
		case (commandCShortcut, true):
			return .copyCurrentTabURL
		case (commandRShortcut, false):
			return .reload
		case (commandRightBracketShortcut, false):
			return .goForward
		case (commandLeftBracketShortcut, false):
			return .goBack
		case (commandRightBracketShortcut, true):
			return .selectNextTab
		case (commandLeftBracketShortcut, true):
			return .selectPreviousTab
		default:
			break
		}

		if let tabIndex = tabSelectionIndex(for: keyCode, usesShift: usesShift) {
			return .selectTab(index: tabIndex)
		}

		if usesShift {
			switch rawCharacter {
			case "}":
				return .selectNextTab
			case "{":
				return .selectPreviousTab
			case "t":
				return .reopenLastClosedTab
			case "c":
				return .copyCurrentTabURL
			default:
				return nil
			}
		}

		if let tabIndex = tabSelectionIndex(for: normalizedCharacter ?? rawCharacter) {
			return .selectTab(index: tabIndex)
		}

		switch normalizedCharacter ?? rawCharacter {
		case "n":
			return .openNewWindow
		case "l":
			return .openLocation
		case "t":
			return .openNewTab
		case "p":
			return .togglePinSelectedTab
		case "w":
			return .closeCurrentTab
		case "r":
			return .reload
		case "]":
			return .goForward
		case "[":
			return .goBack
		default:
			return nil
		}
	}

	private static func hasSupportedCommandModifiers(_ modifiers: NSEvent.ModifierFlags) -> Bool {
		modifiers.contains(.command) && modifiers.intersection([.control, .option]).isEmpty
	}

	private static let commandNShortcut: UInt16 = .init(kVK_ANSI_N)
	private static let commandLShortcut: UInt16 = .init(kVK_ANSI_L)
	private static let commandTShortcut: UInt16 = .init(kVK_ANSI_T)
	private static let commandPShortcut: UInt16 = .init(kVK_ANSI_P)
	private static let commandCShortcut: UInt16 = .init(kVK_ANSI_C)
	private static let commandWShortcut: UInt16 = .init(kVK_ANSI_W)
	private static let commandRShortcut: UInt16 = .init(kVK_ANSI_R)
	private static let commandLeftBracketShortcut: UInt16 = .init(kVK_ANSI_LeftBracket)
	private static let commandRightBracketShortcut: UInt16 = .init(kVK_ANSI_RightBracket)

	private static func tabSelectionIndex(for keyCode: UInt16, usesShift: Bool) -> Int? {
		guard usesShift == false else { return nil }

		return switch keyCode {
		case .init(kVK_ANSI_1): 0
		case .init(kVK_ANSI_2): 1
		case .init(kVK_ANSI_3): 2
		case .init(kVK_ANSI_4): 3
		case .init(kVK_ANSI_5): 4
		case .init(kVK_ANSI_6): 5
		case .init(kVK_ANSI_7): 6
		case .init(kVK_ANSI_8): 7
		case .init(kVK_ANSI_9): 8
		default: nil
		}
	}

	private static func tabSelectionIndex(for character: String?) -> Int? {
		guard
			let character,
			let number = Int(character),
			(1...9).contains(number)
		else {
			return nil
		}

		return number - 1
	}
}

@MainActor
struct NavigatorKeyboardShortcutHandler {
	var openNewWindow: () -> Void
	var openLocation: () -> Void
	var openNewTab: () -> Void
	var reopenLastClosedTab: () -> Void
	var closeCurrentTab: () -> Void
	var togglePinSelectedTab: () -> Void
	var copyCurrentTabURL: () -> Void
	var reload: () -> Void
	var goBack: () -> Void
	var goForward: () -> Void
	var selectNextTab: () -> Void
	var selectPreviousTab: () -> Void
	var selectTabAtIndex: (Int) -> Void

	func perform(_ action: NavigatorKeyboardShortcutAction) {
		switch action {
		case .openNewWindow:
			openNewWindow()
		case .openLocation:
			openLocation()
		case .openNewTab:
			openNewTab()
		case .reopenLastClosedTab:
			reopenLastClosedTab()
		case .closeCurrentTab:
			closeCurrentTab()
		case .togglePinSelectedTab:
			togglePinSelectedTab()
		case .copyCurrentTabURL:
			copyCurrentTabURL()
		case .reload:
			reload()
		case .goBack:
			goBack()
		case .goForward:
			goForward()
		case .selectNextTab:
			selectNextTab()
		case .selectPreviousTab:
			selectPreviousTab()
		case let .selectTab(index):
			selectTabAtIndex(index)
		}
	}
}

struct NavigatorKeyboardShortcutActivation {
	private static let dedupeWindow: TimeInterval = 0.08
	private var lastAction: NavigatorKeyboardShortcutAction?
	private var lastTimestamp: TimeInterval?

	mutating func shouldHandle(for action: NavigatorKeyboardShortcutAction, at timestamp: TimeInterval) -> Bool {
		guard let lastAction,
		      let lastTimestamp else {
			update(action: action, timestamp: timestamp)
			return true
		}

		if lastAction == action, abs(lastTimestamp - timestamp) < Self.dedupeWindow {
			// Keep extending the suppression window while duplicate keydown events arrive.
			update(action: action, timestamp: timestamp)
			return false
		}

		update(action: action, timestamp: timestamp)
		return true
	}

	private mutating func update(action: NavigatorKeyboardShortcutAction, timestamp: TimeInterval) {
		lastAction = action
		lastTimestamp = timestamp
	}
}
