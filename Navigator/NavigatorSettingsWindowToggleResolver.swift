import Foundation

enum NavigatorSettingsWindowToggleAction: Equatable {
	case open
	case close
}

enum NavigatorSettingsWindowToggleResolver {
	static func resolveAction(
		hasSettingsWindow: Bool,
		isVisible: Bool,
		isMiniaturized: Bool
	) -> NavigatorSettingsWindowToggleAction {
		guard hasSettingsWindow else {
			return .open
		}

		if isVisible || isMiniaturized {
			return .close
		}

		return .open
	}
}
