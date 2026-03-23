import Foundation
@testable import TrackpadGestures
import XCTest

final class TrackpadGestureRecognizerTests: XCTestCase {
	func testReplayFixturesProduceExpectedRecognitionCounts() throws {
		for fixtureName in [
			"three-finger-swipe-right",
			"left-swipe",
			"diagonal-swipe",
			"two-finger-scroll",
			"four-finger-gesture",
			"finger-count-change",
			"jittery-near-threshold",
		] {
			let fixture = try loadFixture(named: fixtureName)
			let recognizer = SwipeRightGestureRecognizer(configuration: .v1)
			let sessionID = GestureSessionID()
			var recognizedGestures = [RecognizedGesture]()
			for frame in fixture.frames {
				let result = recognizer.process(frame: frame, sessionID: sessionID)
				if let recognizedGesture = result.recognizedGesture {
					recognizedGestures.append(recognizedGesture)
				}
			}
			if fixtureName == "left-swipe", let firstGesture = recognizedGestures.first {
				XCTAssertEqual(firstGesture.direction, .left)
			}
			XCTAssertEqual(
				recognizedGestures.count,
				fixture.metadata.expectedRecognizedCount,
				fixtureName
			)
		}
	}

	func testRecognizerRejectsOutOfOrderAndDuplicateFrames() {
		let recognizer = SwipeRightGestureRecognizer(configuration: .v1)
		let sessionID = GestureSessionID()
		let initialFrame = TouchFrame(timestamp: 1, contacts: fixtureContacts(xOffset: 0.20, yOffset: 0.40))
		let duplicateFrame = TouchFrame(timestamp: 1, contacts: fixtureContacts(xOffset: 0.22, yOffset: 0.40))
		let staleFrame = TouchFrame(timestamp: 0.9, contacts: fixtureContacts(xOffset: 0.24, yOffset: 0.40))

		_ = recognizer.process(frame: initialFrame, sessionID: sessionID)
		let duplicateResult = recognizer.process(frame: duplicateFrame, sessionID: sessionID)
		let staleResult = recognizer.process(frame: staleFrame, sessionID: sessionID)

		XCTAssertEqual(duplicateResult.diagnostics, [.frameDropped(.duplicateFrame)])
		XCTAssertEqual(staleResult.diagnostics, [.frameDropped(.staleFrame)])
	}

	func testRecognizerOnlyFiresOnceUntilFingersLift() {
		let recognizer = SwipeRightGestureRecognizer(configuration: .v1)
		let sessionID = GestureSessionID()
		let frames = [
			TouchFrame(timestamp: 0.0, contacts: fixtureContacts(xOffset: 0.20, yOffset: 0.40)),
			TouchFrame(timestamp: 0.05, contacts: fixtureContacts(xOffset: 0.32, yOffset: 0.40)),
			TouchFrame(timestamp: 0.10, contacts: fixtureContacts(xOffset: 0.44, yOffset: 0.40)),
			TouchFrame(timestamp: 0.15, contacts: fixtureContacts(xOffset: 0.48, yOffset: 0.40)),
			TouchFrame(timestamp: 0.18, contacts: []),
			TouchFrame(timestamp: 0.20, contacts: fixtureContacts(xOffset: 0.50, yOffset: 0.40)),
		]

		let recognizedGestures = frames.compactMap { recognizer.process(frame: $0, sessionID: sessionID).recognizedGesture }
		XCTAssertEqual(recognizedGestures.count, 1)
	}

	private func fixtureContacts(xOffset: Double, yOffset: Double) -> [TouchContact] {
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

	private func loadFixture(named name: String) throws -> TouchFrameFixture {
		let bundle = Bundle.module
		let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json"))
		let data = try Data(contentsOf: url)
		return try JSONDecoder().decode(TouchFrameFixture.self, from: data)
	}
}

private struct TouchFrameFixture: Decodable {
	struct Metadata: Decodable {
		let name: String
		let device: String
		let osVersion: String
		let expectedRecognizedCount: Int
	}

	let metadata: Metadata
	let frames: [TouchFrame]
}
