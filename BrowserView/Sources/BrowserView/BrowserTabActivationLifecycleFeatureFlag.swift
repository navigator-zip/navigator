import Foundation

enum BrowserTabActivationLifecycleFeatureFlag {
	static let environmentKey = "NAVIGATOR_ENABLE_TAB_ACTIVATION_LIFECYCLE"
	static let enabledValue = "1"

	static func isEnabled(environment: [String: String]) -> Bool {
		guard let value = environment[environmentKey] else { return true }
		return value == enabledValue
	}
}
