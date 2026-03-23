import Foundation
@testable import TrackpadGestures
import XCTest

final class SwipeRightGestureRecognizerEdgeTests: XCTestCase {
	func testRecognizerReturnsToIdleAfterFingerLift() {
		let recognizer = SwipeRightGestureRecognizer(configuration: .v1)
		let sessionID = GestureSessionID()

		let frames = [
			TouchFrame(timestamp: 0.0, contacts: contacts(xOffset: 0.20, yOffset: 0.40)),
			TouchFrame(timestamp: 0.05, contacts: contacts(xOffset: 0.34, yOffset: 0.40)),
			TouchFrame(timestamp: 0.10, contacts: contacts(xOffset: 0.48, yOffset: 0.40)),
			TouchFrame(timestamp: 0.15, contacts: []),
		]

		let diagnostics = frames.flatMap { recognizer.process(frame: $0, sessionID: sessionID).diagnostics }

		XCTAssertTrue(diagnostics.contains(.recognizerTransition(from: "committedThreeFingerHorizontalSwipe", to: "idle")))
	}

	func testRecognizerRejectsDirectionReversalBeforeCommit() {
		let recognizer = makeRecognizer(minimumConfidence: 0.95)
		let sessionID = GestureSessionID()

		_ = recognizer.process(
			frame: TouchFrame(timestamp: 0.0, contacts: contacts(xOffset: 0.30, yOffset: 0.40)),
			sessionID: sessionID
		)
		_ = recognizer.process(
			frame: TouchFrame(timestamp: 0.05, contacts: contacts(xOffset: 0.36, yOffset: 0.40)),
			sessionID: sessionID
		)
		let result = recognizer.process(
			frame: TouchFrame(timestamp: 0.10, contacts: contacts(xOffset: 0.28, yOffset: 0.40)),
			sessionID: sessionID
		)

		XCTAssertTrue(result.diagnostics.contains(.gestureRejected(.reversedBeforeCommit)))
	}

	func testRecognizerAllowsLongThreeFingerHoldBeforeDirectionalMove() {
		let recognizer = makeRecognizer(minimumHorizontalTravel: 0.04, minimumConfidence: 0.0)
		let sessionID = GestureSessionID()

		_ = recognizer.process(
			frame: TouchFrame(timestamp: 0.0, contacts: contacts(xOffset: 0.20, yOffset: 0.40)),
			sessionID: sessionID
		)
		let result = recognizer.process(
			frame: TouchFrame(timestamp: 1.50, contacts: contacts(xOffset: 0.31, yOffset: 0.40)),
			sessionID: sessionID
		)

		XCTAssertEqual(result.recognizedGesture?.direction, .right)
	}

	func testRecognizerRejectsVerticalDriftExceeded() {
		let recognizer = makeRecognizer(maximumVerticalDrift: 0.02)
		let sessionID = GestureSessionID()

		_ = recognizer.process(
			frame: TouchFrame(timestamp: 0.0, contacts: contacts(xOffset: 0.20, yOffset: 0.40)),
			sessionID: sessionID
		)
		let result = recognizer.process(
			frame: TouchFrame(timestamp: 0.05, contacts: contacts(xOffset: 0.26, yOffset: 0.50)),
			sessionID: sessionID
		)

		XCTAssertTrue(result.diagnostics.contains(.gestureRejected(.verticalDriftExceeded)))
	}

	func testRecognizerDoesNotCommitDiagonalDragThatNeverBecomesHorizontalEnough() {
		let recognizer = makeRecognizer(minimumHorizontalTravel: 0.08, minimumConfidence: 0.0)
		let sessionID = GestureSessionID()

		let frames = [
			TouchFrame(timestamp: 0.0, contacts: contacts(xOffset: 0.20, yOffset: 0.40)),
			TouchFrame(timestamp: 0.05, contacts: contacts(xOffset: 0.24, yOffset: 0.47)),
			TouchFrame(timestamp: 0.10, contacts: contacts(xOffset: 0.29, yOffset: 0.55)),
		]

		let recognizedGestures = frames.compactMap { recognizer.process(frame: $0, sessionID: sessionID).recognizedGesture }

		XCTAssertTrue(recognizedGestures.isEmpty)
	}

	func testRecognizerWaitsForDirectionalMoveWhileThreeFingersRemainDown() {
		let recognizer = makeRecognizer(
			minimumHorizontalTravel: 0.04,
			minimumConfidence: 0.0
		)
		let sessionID = GestureSessionID()

		_ = recognizer.process(
			frame: TouchFrame(timestamp: 0.0, contacts: contacts(xOffset: 0.20, yOffset: 0.40)),
			sessionID: sessionID
		)
		let stationaryResult = recognizer.process(
			frame: TouchFrame(timestamp: 0.20, contacts: contacts(xOffset: 0.20, yOffset: 0.40)),
			sessionID: sessionID
		)
		let result = recognizer.process(
			frame: TouchFrame(timestamp: 0.21, contacts: contacts(xOffset: 0.31, yOffset: 0.40)),
			sessionID: sessionID
		)

		XCTAssertNil(stationaryResult.recognizedGesture)
		XCTAssertEqual(result.recognizedGesture?.direction, .right)
	}

	func testRecognizerDoesNotRejectStationaryThreeFingerContact() {
		let recognizer = makeRecognizer(minimumHorizontalTravel: 0.01, minimumConfidence: 0.0)
		let sessionID = GestureSessionID()

		_ = recognizer.process(
			frame: TouchFrame(timestamp: 0.0, contacts: contacts(xOffset: 0.20, yOffset: 0.40)),
			sessionID: sessionID
		)
		let result = recognizer.process(
			frame: TouchFrame(timestamp: 0.001, contacts: contacts(xOffset: 0.20, yOffset: 0.40)),
			sessionID: sessionID
		)

		XCTAssertNil(result.recognizedGesture)
		XCTAssertFalse(result.diagnostics.contains(.gestureRejected(.dominantLeftwardMotion)))
		XCTAssertFalse(result.diagnostics.contains(.gestureRejected(.fingerCountMismatch)))
	}

	func testRecognizerToleratesSingleTransientFingerCountGlitchBeforeCommit() {
		let recognizer = makeRecognizer(
			minimumHorizontalTravel: 0.10,
			minimumConfidence: 0.0
		)
		let sessionID = GestureSessionID()

		_ = recognizer.process(
			frame: TouchFrame(timestamp: 0.0, contacts: contacts(xOffset: 0.20, yOffset: 0.40)),
			sessionID: sessionID
		)
		_ = recognizer.process(
			frame: TouchFrame(timestamp: 0.05, contacts: contacts(xOffset: 0.26, yOffset: 0.40)),
			sessionID: sessionID
		)
		_ = recognizer.process(
			frame: TouchFrame(timestamp: 0.10, contacts: twoFingerContacts(xOffset: 0.28, yOffset: 0.40)),
			sessionID: sessionID
		)
		let result = recognizer.process(
			frame: TouchFrame(timestamp: 0.15, contacts: contacts(xOffset: 0.33, yOffset: 0.40)),
			sessionID: sessionID
		)

		XCTAssertEqual(result.recognizedGesture?.direction, .right)
	}

	func testRecognizerRejectsFingerCountMismatchAfterBudgetExceeded() {
		let recognizer = makeRecognizer(minimumHorizontalTravel: 0.10, minimumConfidence: 0.0)
		let sessionID = GestureSessionID()

		_ = recognizer.process(
			frame: TouchFrame(timestamp: 0.0, contacts: contacts(xOffset: 0.20, yOffset: 0.40)),
			sessionID: sessionID
		)
		_ = recognizer.process(
			frame: TouchFrame(timestamp: 0.05, contacts: contacts(xOffset: 0.20, yOffset: 0.40)),
			sessionID: sessionID
		)
		_ = recognizer.process(
			frame: TouchFrame(timestamp: 0.10, contacts: twoFingerContacts(xOffset: 0.22, yOffset: 0.40)),
			sessionID: sessionID
		)
		let result = recognizer.process(
			frame: TouchFrame(timestamp: 0.15, contacts: twoFingerContacts(xOffset: 0.24, yOffset: 0.40)),
			sessionID: sessionID
		)

		XCTAssertTrue(result.diagnostics.contains(.gestureRejected(.fingerCountMismatch)))
		XCTAssertTrue(
			result.diagnostics.contains { diagnostic in
				if case .recognizerMeasurement = diagnostic {
					return true
				}
				return false
			}
		)
	}

	func testRecognizerRemainsReadyDuringStationaryFrameAfterPriming() {
		let recognizer = makeRecognizer(minimumHorizontalTravel: 0.10, minimumConfidence: 0.0)
		let sessionID = GestureSessionID()

		_ = recognizer.process(
			frame: TouchFrame(timestamp: 0.0, contacts: contacts(xOffset: 0.20, yOffset: 0.40)),
			sessionID: sessionID
		)
		_ = recognizer.process(
			frame: TouchFrame(timestamp: 0.05, contacts: contacts(xOffset: 0.20, yOffset: 0.40)),
			sessionID: sessionID
		)
		let result = recognizer.process(
			frame: TouchFrame(timestamp: 0.10, contacts: contacts(xOffset: 0.20, yOffset: 0.40)),
			sessionID: sessionID
		)

		XCTAssertNil(result.recognizedGesture)
		XCTAssertFalse(result.diagnostics.contains(.recognizerTransition(
			from: "readyThreeFingerHorizontalSwipe",
			to: "readyThreeFingerHorizontalSwipe"
		)))
	}

	func testRecognizerTransitionsFromPrimingToReadyOnSmallUnstableMotion() {
		let recognizer = makeRecognizer(minimumHorizontalTravel: 0.08, minimumConfidence: 0.0)
		let sessionID = GestureSessionID()

		_ = recognizer.process(
			frame: TouchFrame(timestamp: 0.0, contacts: contacts(xOffset: 0.20, yOffset: 0.40)),
			sessionID: sessionID
		)
		let result = recognizer.process(
			frame: TouchFrame(timestamp: 0.05, contacts: contacts(xOffset: 0.2155, yOffset: 0.40)),
			sessionID: sessionID
		)

		XCTAssertNil(result.recognizedGesture)
		XCTAssertTrue(result.diagnostics.contains(.recognizerTransition(
			from: "primingThreeFingerHorizontalSwipe",
			to: "readyThreeFingerHorizontalSwipe"
		)))
	}

	func testRecognizerReturnsToReadyWhenLockedTravelFallsBackBelowDirectionThreshold() {
		let recognizer = makeRecognizer(minimumHorizontalTravel: 0.50, minimumConfidence: 0.0)
		let sessionID = GestureSessionID()

		_ = recognizer.process(
			frame: TouchFrame(timestamp: 0.0, contacts: contacts(xOffset: 0.20, yOffset: 0.40)),
			sessionID: sessionID
		)
		_ = recognizer.process(
			frame: TouchFrame(timestamp: 0.05, contacts: contacts(xOffset: 0.20, yOffset: 0.40)),
			sessionID: sessionID
		)
		let trackingResult = recognizer.process(
			frame: TouchFrame(timestamp: 0.10, contacts: contacts(xOffset: 0.31, yOffset: 0.40)),
			sessionID: sessionID
		)
		let readyResult = recognizer.process(
			frame: TouchFrame(timestamp: 0.15, contacts: contacts(xOffset: 0.28, yOffset: 0.40)),
			sessionID: sessionID
		)

		XCTAssertTrue(trackingResult.diagnostics.contains(.recognizerTransition(
			from: "readyThreeFingerHorizontalSwipe",
			to: "trackingThreeFingerHorizontalSwipe"
		)))
		XCTAssertTrue(readyResult.diagnostics.contains(.recognizerTransition(
			from: "trackingThreeFingerHorizontalSwipe",
			to: "readyThreeFingerHorizontalSwipe"
		)))
	}

	func testRecognizerToleratesSingleTransientFingerCountGlitchWhileTracking() {
		let recognizer = makeRecognizer(minimumHorizontalTravel: 0.50, minimumConfidence: 0.0)
		let sessionID = GestureSessionID()

		_ = recognizer.process(
			frame: TouchFrame(timestamp: 0.0, contacts: contacts(xOffset: 0.20, yOffset: 0.40)),
			sessionID: sessionID
		)
		_ = recognizer.process(
			frame: TouchFrame(timestamp: 0.05, contacts: contacts(xOffset: 0.20, yOffset: 0.40)),
			sessionID: sessionID
		)
		_ = recognizer.process(
			frame: TouchFrame(timestamp: 0.10, contacts: contacts(xOffset: 0.31, yOffset: 0.40)),
			sessionID: sessionID
		)
		let mismatchResult = recognizer.process(
			frame: TouchFrame(timestamp: 0.15, contacts: twoFingerContacts(xOffset: 0.29, yOffset: 0.40)),
			sessionID: sessionID
		)

		XCTAssertNil(mismatchResult.recognizedGesture)
		XCTAssertFalse(mismatchResult.diagnostics.contains(.gestureRejected(.fingerCountMismatch)))
	}

	private func makeRecognizer(
		minimumHorizontalTravel: Double = 0.08,
		maximumVerticalDrift: Double = 0.12,
		minimumConfidence: Double = 0.55
	) -> SwipeRightGestureRecognizer {
		SwipeRightGestureRecognizer(
			configuration: SwipeRightRecognizerConfiguration(
				minimumHorizontalTravel: minimumHorizontalTravel,
				maximumVerticalDrift: maximumVerticalDrift,
				smoothingWindow: 1,
				reversalTolerance: 0.03,
				minimumConfidence: minimumConfidence
			)
		)
	}
}

private func contacts(xOffset: Double, yOffset: Double) -> [TouchContact] {
	[
		TouchContact(
			identifier: 1,
			phase: .moved,
			normalizedX: xOffset,
			normalizedY: yOffset,
			majorAxis: 0.01,
			minorAxis: 0.01,
			pressure: 0.5,
			angle: 0
		),
		TouchContact(
			identifier: 2,
			phase: .moved,
			normalizedX: xOffset + 0.04,
			normalizedY: yOffset + 0.06,
			majorAxis: 0.01,
			minorAxis: 0.01,
			pressure: 0.5,
			angle: 0
		),
		TouchContact(
			identifier: 3,
			phase: .moved,
			normalizedX: xOffset + 0.02,
			normalizedY: yOffset + 0.12,
			majorAxis: 0.01,
			minorAxis: 0.01,
			pressure: 0.5,
			angle: 0
		),
	]
}

private func twoFingerContacts(xOffset: Double, yOffset: Double) -> [TouchContact] {
	Array(contacts(xOffset: xOffset, yOffset: yOffset).prefix(2))
}
