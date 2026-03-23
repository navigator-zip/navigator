import AppKit
import ModelKit

@MainActor
final class BrowserContainerPermissionPromptHost {
	private let overlayController: BrowserPermissionPromptOverlayController

	var hostView: NSView {
		overlayController.hostView
	}

	init(
		overlayController: BrowserPermissionPromptOverlayController = .init()
	) {
		self.overlayController = overlayController
	}

	func install(in containerView: NSView) {
		let hostView = overlayController.hostView
		containerView.addSubview(hostView)
		NSLayoutConstraint.activate([
			hostView.topAnchor.constraint(equalTo: containerView.topAnchor),
			hostView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
			hostView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
			hostView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
		])
	}

	func setPrompt(
		_ session: BrowserPermissionSession?,
		onDecision: ((BrowserPermissionPromptDecision, BrowserPermissionPersistence) -> Void)?,
		onCancel: (() -> Void)?
	) {
		overlayController.setPrompt(
			session,
			onDecision: onDecision,
			onCancel: onCancel
		)
	}

	#if DEBUG
		var isVisibleForTesting: Bool {
			overlayController.isVisibleForTesting
		}

		var textValuesForTesting: [String] {
			overlayController.textValuesForTesting
		}

		func setRememberForTesting(_ remember: Bool) {
			overlayController.setRememberForTesting(remember)
		}

		func performAllowForTesting() {
			overlayController.performAllowForTesting()
		}

		func performDenyForTesting() {
			overlayController.performDenyForTesting()
		}

		func performCancelForTesting() {
			overlayController.performCancelForTesting()
		}
	#endif
}
