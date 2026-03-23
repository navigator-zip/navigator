import BrowserSidebar
import Foundation
import OSLog
import TrackpadGestures

protocol NavigatorTrackpadGestureLifecycle: AnyObject {
	func start()
	func stop()
	func diagnosticEvents() async -> AsyncStream<GestureDiagnosticEvent>
}

enum NavigatorTrackpadGestureDispatchAction: String, Equatable {
	case selectPreviousTab
	case selectNextTab
}

struct NavigatorRecognizedTrackpadGestureDispatch: Equatable {
	let action: NavigatorTrackpadGestureDispatchAction
	let logMessage: String
}

func navigatorRecognizedTrackpadGestureDispatch(
	for gesture: RecognizedGesture
) -> NavigatorRecognizedTrackpadGestureDispatch? {
	guard gesture.phase == .recognized else { return nil }

	let confidence = String(
		format: "%.2f",
		locale: Locale(identifier: "en_US_POSIX"),
		gesture.confidence
	)

	switch gesture.direction {
	case .left:
		return NavigatorRecognizedTrackpadGestureDispatch(
			action: .selectPreviousTab,
			logMessage: "Recognized three-finger swipe left; dispatching selectPreviousTab (confidence: \(confidence))"
		)
	case .right:
		return NavigatorRecognizedTrackpadGestureDispatch(
			action: .selectNextTab,
			logMessage: "Recognized three-finger swipe right; dispatching selectNextTab (confidence: \(confidence))"
		)
	}
}

enum NavigatorTrackpadGestureFeatureFlag {
	static func isEnabled() -> Bool {
		true
	}
}

@MainActor
final class NavigatorTrackpadGestureServiceLifecycle: NavigatorTrackpadGestureLifecycle {
	private let service: TrackpadGestureService
	private let resolveNavigatorAppViewModel: @MainActor () -> AppViewModel
	private var startupTask: Task<Void, Never>?
	private var gestureTask: Task<Void, Never>?

	static func makeIfEnabled(
		resolveNavigatorAppViewModel: @escaping @MainActor () -> AppViewModel
	) -> NavigatorTrackpadGestureServiceLifecycle? {
		guard NavigatorTrackpadGestureFeatureFlag.isEnabled() else {
			return nil
		}
		return NavigatorTrackpadGestureServiceLifecycle(
			resolveNavigatorAppViewModel: resolveNavigatorAppViewModel
		)
	}

	init(resolveNavigatorAppViewModel: @escaping @MainActor () -> AppViewModel) {
		self.resolveNavigatorAppViewModel = resolveNavigatorAppViewModel
		service = TrackpadGestureService(configuration: .v1())
	}

	func start() {
		ensureGestureObservation()
		guard startupTask == nil else { return }

		let service = service
		startupTask = Task { @MainActor [weak self, service] in
			defer {
				self?.startupTask = nil
			}
			do {
				_ = try await service.start()
			}
			catch TrackpadGestureError.alreadyRunning {}
			catch {
				navigatorTrackpadGestureLogger.error(
					"Failed to start trackpad gestures: \(String(describing: error), privacy: .public)"
				)
			}
		}
	}

	func stop() {
		startupTask?.cancel()
		startupTask = nil
		gestureTask?.cancel()
		gestureTask = nil

		let service = service
		Task {
			await service.stop()
		}
	}

	func diagnosticEvents() async -> AsyncStream<GestureDiagnosticEvent> {
		await service.diagnosticEvents()
	}

	private func ensureGestureObservation() {
		guard gestureTask == nil else { return }

		let service = service
		gestureTask = Task { @MainActor [weak self, service] in
			let gestures = await service.gestureEvents()
			for await gesture in gestures {
				self?.handleRecognizedGesture(gesture)
			}
		}
	}

	private func handleRecognizedGesture(_ gesture: RecognizedGesture) {
		guard let dispatch = navigatorRecognizedTrackpadGestureDispatch(for: gesture) else { return }
		navigatorTrackpadGestureLogger.info("\(dispatch.logMessage, privacy: .public)")
		let navigatorAppViewModel = resolveNavigatorAppViewModel()

		switch dispatch.action {
		case .selectPreviousTab:
			navigatorAppViewModel.sidebarViewModel.selectPreviousTab()
		case .selectNextTab:
			navigatorAppViewModel.sidebarViewModel.selectNextTab()
		}
	}
}
