import ModelKit
@testable import Navigator
import TrackpadGestures
import XCTest

final class NavigatorAppDelegateHooksTests: XCTestCase {
	@MainActor
	private static var retainedVirtualCameraManagers = [NavigatorVirtualCameraExtensionManager]()

	@MainActor
	func testVirtualCameraRefreshPreservesApplicationsActivationFailure() {
		let manager = NavigatorVirtualCameraExtensionManager(
			environment: .init(
				mainBundleURL: { URL(fileURLWithPath: "/Applications/Navigator.app") },
				fileExistsAtPath: { _ in true },
				approvalStateProvider: { .notRequested },
				reachabilityStateProvider: { .unknown },
				compatibilityStateProvider: { .unknown },
				activationHandler: { .awaitingUserApproval }
			)
		)

		manager.refreshInstallLocation(appURL: URL(fileURLWithPath: "/Users/rk/Desktop/Navigator.app"))
		manager.noteActivationAttempt()
		XCTAssertEqual(
			manager.lastActivationError,
			"Navigator must be installed in /Applications before activating the camera extension."
		)

		manager.refresh()

		XCTAssertEqual(manager.installState, .failed)
		XCTAssertEqual(
			manager.lastActivationError,
			"Navigator must be installed in /Applications before activating the camera extension."
		)
		XCTAssertFalse(manager.canAttemptActivation)
		Self.retainedVirtualCameraManagers.append(manager)
	}

	func testTrackpadConsoleLoggingSkipsDeviceLifecycleChurn() {
		XCTAssertFalse(
			GestureDiagnosticEvent.Kind.deviceListCreationAttempt(path: "/tmp/framework")
				.shouldEmitNavigatorConsoleLog
		)
		XCTAssertFalse(
			GestureDiagnosticEvent.Kind.sessionStateTransition(
				sessionID: UUID(),
				state: .started
			).shouldEmitNavigatorConsoleLog
		)
		XCTAssertFalse(
			GestureDiagnosticEvent.Kind.deviceRegistered("123")
				.shouldEmitNavigatorConsoleLog
		)
	}

	func testTrackpadConsoleLoggingKeepsHighSignalEvents() {
		XCTAssertTrue(
			GestureDiagnosticEvent.Kind.runtimeStateChanged(.running)
				.shouldEmitNavigatorConsoleLog
		)
		XCTAssertTrue(
			GestureDiagnosticEvent.Kind.startupFailed("failed")
				.shouldEmitNavigatorConsoleLog
		)
		XCTAssertTrue(
			GestureDiagnosticEvent.Kind.gestureAccepted(direction: .right, confidence: 0.9)
				.shouldEmitNavigatorConsoleLog
		)
		XCTAssertTrue(
			GestureDiagnosticEvent.Kind.recognizerMeasurement(
				state: "trackingSwipeRight",
				contactCount: 3,
				direction: .left,
				horizontalTravel: -0.18,
				verticalDrift: 0.01,
				duration: 0.08,
				idleDuration: 0.01,
				confidence: 0.42,
				minimumHorizontalTravel: 0.22,
				maximumVerticalDrift: 0.12,
				minimumConfidence: 0.55
			).shouldEmitNavigatorConsoleLog
		)
	}

	func testRecognizedThreeFingerSwipeLeftBuildsPreviousTabDispatchLog() {
		let dispatch = navigatorRecognizedTrackpadGestureDispatch(
			for: RecognizedGesture(
				sessionID: GestureSessionID(),
				direction: .left,
				phase: .recognized,
				timestamp: 12.0,
				confidence: 0.912
			)
		)

		XCTAssertEqual(dispatch?.action, .selectPreviousTab)
		XCTAssertEqual(
			dispatch?.logMessage,
			"Recognized three-finger swipe left; dispatching selectPreviousTab (confidence: 0.91)"
		)
	}

	func testRecognizedThreeFingerSwipeRightBuildsNextTabDispatchLog() {
		let dispatch = navigatorRecognizedTrackpadGestureDispatch(
			for: RecognizedGesture(
				sessionID: GestureSessionID(),
				direction: .right,
				phase: .recognized,
				timestamp: 12.0,
				confidence: 0.9
			)
		)

		XCTAssertEqual(dispatch?.action, .selectNextTab)
		XCTAssertEqual(
			dispatch?.logMessage,
			"Recognized three-finger swipe right; dispatching selectNextTab (confidence: 0.90)"
		)
	}
}
