import Foundation
@testable import TrackpadGestures
import XCTest

final class TrackpadGestureModelTests: XCTestCase {
	func testTouchFrameComputesCentroidAndRoundTripsCodable() throws {
		let frame = TouchFrame(
			timestamp: 12.5,
			contacts: [
				TouchContact(
					identifier: 1,
					phase: .began,
					normalizedX: 0.2,
					normalizedY: 0.3,
					majorAxis: 1.0,
					minorAxis: 0.5,
					pressure: 0.8,
					angle: 0.1
				),
				TouchContact(
					identifier: 2,
					phase: .moved,
					normalizedX: 0.4,
					normalizedY: 0.7,
					majorAxis: 1.1,
					minorAxis: 0.6,
					pressure: 0.9,
					angle: 0.2
				),
			]
		)

		XCTAssertEqual(frame.centroidX, 0.3, accuracy: 0.0001)
		XCTAssertEqual(frame.centroidY, 0.5, accuracy: 0.0001)

		let data = try JSONEncoder().encode(frame)
		let decoded = try JSONDecoder().decode(TouchFrame.self, from: data)
		XCTAssertEqual(decoded, frame)
		XCTAssertEqual(decoded.centroidX, 0.3, accuracy: 0.0001)
		XCTAssertEqual(decoded.centroidY, 0.5, accuracy: 0.0001)
	}

	func testEmptyTouchFrameCentroidDefaultsToZero() {
		let frame = TouchFrame(timestamp: 1, contacts: [])
		XCTAssertEqual(frame.centroidX, 0)
		XCTAssertEqual(frame.centroidY, 0)
	}

	func testGestureDiagnosticDescriptionIncludesSessionTimestampAndKind() throws {
		let sessionID = try GestureSessionID(rawValue: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000123")))
		let event = GestureDiagnosticEvent(
			sessionID: sessionID,
			timestamp: 42,
			kind: .gestureAccepted(direction: .right, confidence: 0.9)
		)

		let description = event.description
		XCTAssertTrue(description.contains(sessionID.rawValue.uuidString))
		XCTAssertTrue(description.contains("42.0"))
		XCTAssertTrue(description.contains("gestureAccepted"))
	}

	func testSwipeRightRecognizerConfigurationV1MatchesExpectedDefaults() {
		XCTAssertEqual(
			SwipeRightRecognizerConfiguration.v1,
			SwipeRightRecognizerConfiguration(
				minimumHorizontalTravel: 0.08,
				maximumVerticalDrift: 0.12,
				smoothingWindow: 3,
				reversalTolerance: 0.03,
				minimumConfidence: 0.55
			)
		)
	}

	func testRecognizedGestureExposesHorizontalSwipeKind() {
		let gesture = RecognizedGesture(
			sessionID: GestureSessionID(),
			direction: .left,
			phase: .recognized,
			timestamp: 2,
			confidence: 0.8
		)

		XCTAssertEqual(
			gesture.kind,
			.threeFingerHorizontalSwipe(direction: .left)
		)
	}

	func testPermissionStatusFindsMissingPermissions() {
		let status = TrackpadGesturePermissionStatus(
			accessibilityTrusted: false,
			inputMonitoringTrusted: true
		)

		XCTAssertEqual(
			status.missingPermissions(in: [.accessibility, .inputMonitoring]),
			[.accessibility]
		)
	}
}
