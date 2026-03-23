import BrowserRuntime
import ModelKit

@MainActor
enum BrowserPermissionPromptRouting {
	static func route(
		session: BrowserPermissionSession?,
		expectedBrowser: CEFBridgeBrowserRef,
		container: BrowserContainerView?,
		resolve: @escaping (BrowserPermissionSessionID, BrowserPermissionPromptDecision, BrowserPermissionPersistence)
			-> Void,
		cancel: @escaping (BrowserPermissionSessionID) -> Void,
		setProtection: (Bool) -> Void
	) {
		guard let container else { return }

		if let session {
			guard container.browserRef == expectedBrowser else { return }
			container.setPermissionPrompt(
				session,
				onDecision: { decision, persistence in
					resolve(session.id, decision, persistence)
				},
				onCancel: {
					cancel(session.id)
				}
			)
			setProtection(true)
			return
		}

		guard container.browserRef == expectedBrowser || container.browserRef == nil else { return }
		container.setPermissionPrompt(nil, onDecision: nil, onCancel: nil)
		setProtection(false)
	}
}
