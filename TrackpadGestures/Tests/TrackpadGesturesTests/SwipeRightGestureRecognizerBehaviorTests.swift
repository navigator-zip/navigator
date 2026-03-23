import Foundation
@testable import TrackpadGestures
import XCTest

final class SwipeRightGestureRecognizerBehaviorTests: XCTestCase {
	func testRecognizerUsesSmoothingWindowToDampenVerticalJitter() {
		let recognizer = SwipeRightGestureRecognizer(
			configuration: SwipeRightRecognizerConfiguration(
				minimumHorizontalTravel: 0.18,
				maximumVerticalDrift: 0.04,
				smoothingWindow: 3,
				reversalTolerance: 0.03,
				minimumConfidence: 0.15
			)
		)
		let sessionID = GestureSessionID()
		let frames = [
			TouchFrame(timestamp: 0.00, contacts: contacts(xOffset: 0.20, yOffset: 0.40)),
			TouchFrame(timestamp: 0.05, contacts: contacts(xOffset: 0.30, yOffset: 0.46)),
			TouchFrame(timestamp: 0.10, contacts: contacts(xOffset: 0.40, yOffset: 0.44)),
		]

		let recognizedGestures = frames.compactMap { recognizer.process(frame: $0, sessionID: sessionID).recognizedGesture }
		XCTAssertEqual(recognizedGestures.count, 1)
	}

	func testRecognizerV1AcceptsMeasuredLeftSwipeProfile() {
		let recognizer = SwipeRightGestureRecognizer(configuration: .v1)
		let sessionID = GestureSessionID()
		let frames = [
			TouchFrame(timestamp: 0.00, contacts: contacts(xOffset: 0.30, yOffset: 0.40)),
			TouchFrame(timestamp: 0.16, contacts: contacts(xOffset: 0.25, yOffset: 0.42)),
			TouchFrame(timestamp: 0.30, contacts: contacts(xOffset: 0.219, yOffset: 0.4298)),
		]

		let recognizedGestures = frames.compactMap { recognizer.process(frame: $0, sessionID: sessionID).recognizedGesture }

		XCTAssertEqual(recognizedGestures.count, 1)
		XCTAssertEqual(recognizedGestures.first?.direction, .left)
	}

	func testRecognizerV1AllowsBriefPauseBeforeFinalLeftwardPush() {
		let recognizer = SwipeRightGestureRecognizer(configuration: .v1)
		let sessionID = GestureSessionID()
		let frames = [
			TouchFrame(timestamp: 0.00, contacts: contacts(xOffset: 0.30, yOffset: 0.40)),
			TouchFrame(timestamp: 0.10, contacts: contacts(xOffset: 0.26, yOffset: 0.41)),
			TouchFrame(timestamp: 0.24, contacts: contacts(xOffset: 0.26, yOffset: 0.41)),
			TouchFrame(timestamp: 0.29, contacts: contacts(xOffset: 0.22, yOffset: 0.42)),
		]

		let recognizedGestures = frames.compactMap { recognizer.process(frame: $0, sessionID: sessionID).recognizedGesture }

		XCTAssertEqual(recognizedGestures.count, 1)
		XCTAssertEqual(recognizedGestures.first?.direction, .left)
	}

	func testRecognizerV1AcceptsMeasuredRightSwipeAcrossSeveralModestFrames() {
		let recognizer = SwipeRightGestureRecognizer(configuration: .v1)
		let sessionID = GestureSessionID()
		let frames = [
			TouchFrame(timestamp: 0.00, contacts: contacts(xOffset: 0.20, yOffset: 0.40)),
			TouchFrame(timestamp: 0.05, contacts: contacts(xOffset: 0.232, yOffset: 0.405)),
			TouchFrame(timestamp: 0.10, contacts: contacts(xOffset: 0.258, yOffset: 0.409)),
			TouchFrame(timestamp: 0.15, contacts: contacts(xOffset: 0.286, yOffset: 0.412)),
		]

		let recognizedGestures = frames.compactMap { recognizer.process(frame: $0, sessionID: sessionID).recognizedGesture }

		XCTAssertEqual(recognizedGestures.count, 1)
		XCTAssertEqual(recognizedGestures.first?.direction, .right)
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
