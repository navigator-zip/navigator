import BrowserRuntime
import BrowserSidebar
import Foundation

struct BrowserTabLifecycleConfiguration: Equatable {
	var isEnabled: Bool = true
	var activationDelay: TimeInterval = 0
	var minimumLiveBrowserLifetime: TimeInterval = 2
	var maxLiveBrowsers: Int = 18

	init(
		isEnabled: Bool = true,
		activationDelay: TimeInterval = 0,
		minimumLiveBrowserLifetime: TimeInterval = 2,
		maxLiveBrowsers: Int = 18
	) {
		self.isEnabled = isEnabled
		self.activationDelay = activationDelay
		self.minimumLiveBrowserLifetime = minimumLiveBrowserLifetime
		self.maxLiveBrowsers = max(maxLiveBrowsers, 1)
	}

	static let disabled = Self(
		isEnabled: false,
		activationDelay: 0,
		minimumLiveBrowserLifetime: .greatestFiniteMagnitude,
		maxLiveBrowsers: .max
	)
}

enum BrowserTabIntentState: Equatable {
	case cold
	case transientSelected(sessionID: Int)
	case committed
}

enum BrowserTabNavigationState: Equatable {
	case none
	case provisional
	case committed
	case finished
}

enum BrowserTabBrowserState: Equatable {
	case none
	case live(createdAt: TimeInterval)
	case discarded
}

enum BrowserTabProtectionReason: Hashable {
	case devTools
	case accessibilityFocus
	case authSensitive
	case permissionPrompt
}

struct BrowserTabLifecycleRecord: Equatable {
	struct CapturedScrollState: Equatable {
		var url: String
		var position: BrowserRuntimeScrollPosition
	}

	var intentState: BrowserTabIntentState = .cold
	var navigationState: BrowserTabNavigationState = .none
	var browserState: BrowserTabBrowserState = .none
	var lastSelectionGeneration = 0
	var capturedScrollState: CapturedScrollState?
	var protectionReasons = Set<BrowserTabProtectionReason>()

	var isCommitted: Bool {
		if case .committed = intentState {
			return true
		}
		return false
	}

	var isTransient: Bool {
		if case .transientSelected = intentState {
			return true
		}
		return false
	}

	var hasLiveBrowser: Bool {
		if case .live = browserState {
			return true
		}
		return false
	}

	var browserCreatedAt: TimeInterval? {
		if case let .live(createdAt) = browserState {
			return createdAt
		}
		return nil
	}

	var isDiscarded: Bool {
		if case .discarded = browserState {
			return true
		}
		return false
	}

	var isProtectedFromEviction: Bool {
		protectionReasons.isEmpty == false
	}
}
