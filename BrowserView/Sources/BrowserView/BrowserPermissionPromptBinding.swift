import BrowserRuntime
import ModelKit

@MainActor
enum BrowserPermissionPromptBinding {
	static func bind(
		browserRuntime: any BrowserRuntimeDriving,
		browser: CEFBridgeBrowserRef,
		expectedLifecycleGeneration: Int,
		currentLifecycleGeneration: @escaping () -> Int,
		container: @escaping () -> BrowserContainerView?,
		onSessionChange: @escaping (BrowserPermissionSession?) -> Void,
		resolve: @escaping (
			BrowserPermissionSessionID,
			BrowserPermissionPromptDecision,
			BrowserPermissionPersistence
		) -> Void,
		cancel: @escaping (BrowserPermissionSessionID) -> Void,
		setProtection: @escaping (Bool) -> Void
	) {
		browserRuntime.setPermissionPromptHandler(for: browser) { session in
			guard currentLifecycleGeneration() == expectedLifecycleGeneration else { return }
			onSessionChange(session)
			BrowserPermissionPromptRouting.route(
				session: session,
				expectedBrowser: browser,
				container: container(),
				resolve: resolve,
				cancel: cancel,
				setProtection: setProtection
			)
		}
	}
}
