import Foundation
@testable import TrackpadGestures
import XCTest

final class SwipeGestureGeometryTests: XCTestCase {
	func testPointSmoothingWithoutPreviousReturnsRawPoint() {
		let point = GesturePoint(x: 0.4, y: 0.6)

		XCTAssertEqual(point.applyingExponentialSmoothing(to: nil, alpha: 0.25), point)
	}

	func testBoundingBoxForEmptyContactsDefaultsToZeroSize() {
		let box = GestureBoundingBox.from(contacts: [])

		XCTAssertEqual(box.minX, 0)
		XCTAssertEqual(box.maxX, 0)
		XCTAssertEqual(box.minY, 0)
		XCTAssertEqual(box.maxY, 0)
		XCTAssertEqual(box.width, 0)
		XCTAssertEqual(box.height, 0)
	}

	func testBoundingBoxDimensionsMatchContactExtents() {
		let box = GestureBoundingBox.from(contacts: geometryContacts())

		XCTAssertEqual(box.width, 0.12, accuracy: 0.0001)
		XCTAssertEqual(box.height, 0.08, accuracy: 0.0001)
	}

	func testAveragePairwiseDistanceReturnsZeroForSingleContact() {
		let distance = SwipeGestureGeometry.averagePairwiseDistance(for: [geometryContacts()[0]])

		XCTAssertEqual(distance, 0)
	}

	func testFeatureExtractorDefaultsSpreadScaleToOneWhenBaselineDistanceIsZero() {
		let frame = TouchFrame(timestamp: 0.1, contacts: geometryContacts())
		let features = SwipeGestureFrameFeatureExtractor.features(
			for: frame,
			previousFilteredCentroid: GesturePoint(x: 0.2, y: 0.3),
			previousTimestamp: 0.0,
			baselineCentroid: GesturePoint(x: 0.2, y: 0.3),
			baselineAveragePairwiseDistance: 0,
			filterAlpha: 0.5,
			minimumFrameDeltaTime: 1.0 / 240.0
		)

		XCTAssertEqual(features.spreadScaleRelativeToBaseline, 1)
	}

	func testAngleFromHorizontalTreatsLeftwardAndRightwardMotionAsHorizontal() {
		XCTAssertEqual(
			SwipeGestureGeometry.angleFromHorizontalRadians(vx: 1, vy: 0.1),
			SwipeGestureGeometry.angleFromHorizontalRadians(vx: -1, vy: 0.1),
			accuracy: 0.0001
		)
		XCTAssertGreaterThan(
			SwipeGestureGeometry.angleFromHorizontalRadians(vx: 0.2, vy: 1),
			SwipeGestureGeometry.angleFromHorizontalRadians(vx: 1, vy: 0.2)
		)
	}

	private func geometryContacts() -> [TouchContact] {
		[
			TouchContact(
				identifier: 1,
				phase: .moved,
				normalizedX: 0.10,
				normalizedY: 0.20,
				majorAxis: 0.01,
				minorAxis: 0.01,
				pressure: 0.5,
				angle: 0
			),
			TouchContact(
				identifier: 2,
				phase: .moved,
				normalizedX: 0.18,
				normalizedY: 0.24,
				majorAxis: 0.01,
				minorAxis: 0.01,
				pressure: 0.5,
				angle: 0
			),
			TouchContact(
				identifier: 3,
				phase: .moved,
				normalizedX: 0.22,
				normalizedY: 0.28,
				majorAxis: 0.01,
				minorAxis: 0.01,
				pressure: 0.5,
				angle: 0
			),
		]
	}
}
