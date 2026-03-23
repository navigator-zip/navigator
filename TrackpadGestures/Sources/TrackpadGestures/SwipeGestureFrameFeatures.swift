import Foundation

struct SwipeGestureFrameFeatures: Equatable, Sendable {
	let timestamp: TimeInterval
	let contactCount: Int
	let rawCentroid: GesturePoint
	let filteredCentroid: GesturePoint
	let boundingBox: GestureBoundingBox
	let averagePairwiseDistance: Double
	let rawDxFromBaseline: Double
	let rawDyFromBaseline: Double
	let filteredDxFromBaseline: Double
	let filteredDyFromBaseline: Double
	let frameDx: Double
	let frameDy: Double
	let dt: TimeInterval
	let vx: Double
	let vy: Double
	let speed: Double
	let angleRadians: Double
	let angleFromHorizontalRadians: Double
	let horizontalDominance: Double
	let spreadScaleRelativeToBaseline: Double
}

enum SwipeGestureFrameFeatureExtractor {
	static func initialFeatures(frame: TouchFrame) -> SwipeGestureFrameFeatures {
		let rawCentroid = GesturePoint(frame: frame)
		let boundingBox = GestureBoundingBox.from(contacts: frame.contacts)
		let averagePairwiseDistance = SwipeGestureGeometry.averagePairwiseDistance(for: frame.contacts)
		return SwipeGestureFrameFeatures(
			timestamp: frame.timestamp,
			contactCount: frame.contacts.count,
			rawCentroid: rawCentroid,
			filteredCentroid: rawCentroid,
			boundingBox: boundingBox,
			averagePairwiseDistance: averagePairwiseDistance,
			rawDxFromBaseline: 0,
			rawDyFromBaseline: 0,
			filteredDxFromBaseline: 0,
			filteredDyFromBaseline: 0,
			frameDx: 0,
			frameDy: 0,
			dt: 0,
			vx: 0,
			vy: 0,
			speed: 0,
			angleRadians: 0,
			angleFromHorizontalRadians: 0,
			horizontalDominance: 0,
			spreadScaleRelativeToBaseline: 1
		)
	}

	static func features(
		for frame: TouchFrame,
		previousFilteredCentroid: GesturePoint,
		previousTimestamp: TimeInterval,
		baselineCentroid: GesturePoint,
		baselineAveragePairwiseDistance: Double,
		filterAlpha: Double,
		minimumFrameDeltaTime: TimeInterval
	) -> SwipeGestureFrameFeatures {
		let rawCentroid = GesturePoint(frame: frame)
		let filteredCentroid = rawCentroid.applyingExponentialSmoothing(
			to: previousFilteredCentroid,
			alpha: filterAlpha
		)
		let boundingBox = GestureBoundingBox.from(contacts: frame.contacts)
		let averagePairwiseDistance = SwipeGestureGeometry.averagePairwiseDistance(for: frame.contacts)
		let frameDx = filteredCentroid.x - previousFilteredCentroid.x
		let frameDy = filteredCentroid.y - previousFilteredCentroid.y
		let dt = max(frame.timestamp - previousTimestamp, minimumFrameDeltaTime)
		let vx = frameDx / dt
		let vy = frameDy / dt
		let speed = hypot(vx, vy)
		let velocityMagnitude = abs(vx) + abs(vy)
		let horizontalDominance = velocityMagnitude > 0 ? abs(vx) / velocityMagnitude : 0
		let angleFromHorizontalRadians = SwipeGestureGeometry.angleFromHorizontalRadians(vx: vx, vy: vy)
		let spreadScaleRelativeToBaseline = baselineAveragePairwiseDistance > 0
			? averagePairwiseDistance / baselineAveragePairwiseDistance
			: 1

		return SwipeGestureFrameFeatures(
			timestamp: frame.timestamp,
			contactCount: frame.contacts.count,
			rawCentroid: rawCentroid,
			filteredCentroid: filteredCentroid,
			boundingBox: boundingBox,
			averagePairwiseDistance: averagePairwiseDistance,
			rawDxFromBaseline: rawCentroid.x - baselineCentroid.x,
			rawDyFromBaseline: rawCentroid.y - baselineCentroid.y,
			filteredDxFromBaseline: filteredCentroid.x - baselineCentroid.x,
			filteredDyFromBaseline: filteredCentroid.y - baselineCentroid.y,
			frameDx: frameDx,
			frameDy: frameDy,
			dt: dt,
			vx: vx,
			vy: vy,
			speed: speed,
			angleRadians: atan2(vy, vx),
			angleFromHorizontalRadians: angleFromHorizontalRadians,
			horizontalDominance: horizontalDominance,
			spreadScaleRelativeToBaseline: spreadScaleRelativeToBaseline
		)
	}
}

extension SwipeRightRecognizerConfiguration {
	var requiredFingerCount: Int {
		3
	}

	var gestureFilterAlpha: Double {
		guard smoothingWindow > 1 else { return 1.0 }
		return 2.0 / (Double(smoothingWindow) + 1.0)
	}

	var primingMaximumMotion: Double {
		max(directionLockDistance * 1.25, 0.02)
	}

	var directionLockDistance: Double {
		max(minimumHorizontalTravel * 0.2, 0.01)
	}

	var minimumFrameDeltaTime: TimeInterval {
		1.0 / 240.0
	}

	var maximumBadContactFrames: Int {
		1
	}

	var maximumSpreadScaleDeviation: Double {
		0.35
	}

	var minimumHorizontalDominance: Double {
		0.6
	}

	var minimumConsecutiveTrackingFrames: Int {
		1
	}

	var minimumConsecutiveCommitEligibleFrames: Int {
		1
	}

	var motionHistoryLimit: Int {
		4
	}

	var minimumHorizontalVelocityForOnset: Double {
		max(directionLockDistance / 0.18, 0.12)
	}

	var minimumHorizontalVelocityForCommit: Double {
		max(minimumHorizontalTravel / 0.55, 0.12)
	}

	var maximumAngleFromHorizontalRadians: Double {
		.pi / 6
	}

	var fastSwipeCommitTravelMultiplier: Double {
		1.35
	}
}
