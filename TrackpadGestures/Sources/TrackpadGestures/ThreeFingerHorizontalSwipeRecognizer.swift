import Foundation

struct ThreeFingerHorizontalSwipeRecognizerResult {
	let diagnostics: [GestureDiagnosticEvent.Kind]
	let recognizedGesture: RecognizedGesture?
}

final class ThreeFingerHorizontalSwipeRecognizer {
	private enum State: Equatable {
		case idle
		case priming(Candidate)
		case ready(Candidate)
		case tracking(Candidate)
		case committed(Candidate)

		var name: String {
			switch self {
			case .idle:
				"idle"
			case .priming:
				"primingThreeFingerHorizontalSwipe"
			case .ready:
				"readyThreeFingerHorizontalSwipe"
			case .tracking:
				"trackingThreeFingerHorizontalSwipe"
			case .committed:
				"committedThreeFingerHorizontalSwipe"
			}
		}
	}

	private struct RecentMotionSample: Equatable {
		let horizontalVelocity: Double
		let horizontalDominance: Double
		let angleFromHorizontalRadians: Double
	}

	private struct Candidate: Equatable {
		let startTimestamp: TimeInterval
		let lastTimestamp: TimeInterval
		let lastMotionTimestamp: TimeInterval
		let baselineCentroid: GesturePoint
		let baselineBoundingBox: GestureBoundingBox
		let baselineAveragePairwiseDistance: Double
		let filteredCentroid: GesturePoint
		let previousFilteredCentroid: GesturePoint
		let latestRawCentroid: GesturePoint
		let directionLock: GestureDirection?
		let reverseTravelAfterLock: Double
		let badContactFrameCount: Int
		let stablePrimingFrameCount: Int
		let consecutiveGoodTrackingFrames: Int
		let consecutiveCommitEligibleFrames: Int
		let motionHistory: [RecentMotionSample]

		static func initial(from frame: TouchFrame) -> Candidate {
			let features = SwipeGestureFrameFeatureExtractor.initialFeatures(frame: frame)
			return Candidate(
				startTimestamp: frame.timestamp,
				lastTimestamp: frame.timestamp,
				lastMotionTimestamp: frame.timestamp,
				baselineCentroid: features.rawCentroid,
				baselineBoundingBox: features.boundingBox,
				baselineAveragePairwiseDistance: features.averagePairwiseDistance,
				filteredCentroid: features.filteredCentroid,
				previousFilteredCentroid: features.filteredCentroid,
				latestRawCentroid: features.rawCentroid,
				directionLock: nil,
				reverseTravelAfterLock: 0,
				badContactFrameCount: 0,
				stablePrimingFrameCount: 1,
				consecutiveGoodTrackingFrames: 0,
				consecutiveCommitEligibleFrames: 0,
				motionHistory: []
			)
		}

		func updated(
			with features: SwipeGestureFrameFeatures,
			directionLock: GestureDirection?,
			reverseTravelAfterLock: Double,
			stablePrimingFrameCount: Int,
			consecutiveGoodTrackingFrames: Int,
			consecutiveCommitEligibleFrames: Int,
			motionHistoryLimit: Int
		) -> Candidate {
			let movedDistance = abs(features.frameDx) + abs(features.frameDy)
			let nextMotionHistory = appendedMotionSample(
				for: features,
				limit: motionHistoryLimit
			)
			return Candidate(
				startTimestamp: startTimestamp,
				lastTimestamp: features.timestamp,
				lastMotionTimestamp: movedDistance > 0.002 ? features.timestamp : lastMotionTimestamp,
				baselineCentroid: baselineCentroid,
				baselineBoundingBox: baselineBoundingBox,
				baselineAveragePairwiseDistance: baselineAveragePairwiseDistance,
				filteredCentroid: features.filteredCentroid,
				previousFilteredCentroid: filteredCentroid,
				latestRawCentroid: features.rawCentroid,
				directionLock: directionLock,
				reverseTravelAfterLock: reverseTravelAfterLock,
				badContactFrameCount: 0,
				stablePrimingFrameCount: stablePrimingFrameCount,
				consecutiveGoodTrackingFrames: consecutiveGoodTrackingFrames,
				consecutiveCommitEligibleFrames: consecutiveCommitEligibleFrames,
				motionHistory: nextMotionHistory
			)
		}

		func updatedForMismatch(timestamp: TimeInterval) -> Candidate {
			Candidate(
				startTimestamp: startTimestamp,
				lastTimestamp: timestamp,
				lastMotionTimestamp: lastMotionTimestamp,
				baselineCentroid: baselineCentroid,
				baselineBoundingBox: baselineBoundingBox,
				baselineAveragePairwiseDistance: baselineAveragePairwiseDistance,
				filteredCentroid: filteredCentroid,
				previousFilteredCentroid: previousFilteredCentroid,
				latestRawCentroid: latestRawCentroid,
				directionLock: directionLock,
				reverseTravelAfterLock: reverseTravelAfterLock,
				badContactFrameCount: badContactFrameCount + 1,
				stablePrimingFrameCount: stablePrimingFrameCount,
				consecutiveGoodTrackingFrames: consecutiveGoodTrackingFrames,
				consecutiveCommitEligibleFrames: consecutiveCommitEligibleFrames,
				motionHistory: motionHistory
			)
		}

		var averageHorizontalDominance: Double {
			averageMotionValue(\.horizontalDominance)
		}

		var averageHorizontalVelocity: Double {
			averageMotionValue(\.horizontalVelocity)
		}

		var averageAngleFromHorizontalRadians: Double {
			averageMotionValue(\.angleFromHorizontalRadians)
		}

		private func appendedMotionSample(
			for features: SwipeGestureFrameFeatures,
			limit: Int
		) -> [RecentMotionSample] {
			Array(
				(motionHistory + [
					RecentMotionSample(
						horizontalVelocity: abs(features.vx),
						horizontalDominance: features.horizontalDominance,
						angleFromHorizontalRadians: features.angleFromHorizontalRadians
					),
				]).suffix(limit)
			)
		}

		private func averageMotionValue(_ keyPath: KeyPath<RecentMotionSample, Double>) -> Double {
			motionHistory.map { $0[keyPath: keyPath] }.reduce(0, +) / Double(max(motionHistory.count, 1))
		}
	}

	private let configuration: SwipeRightRecognizerConfiguration
	private var state: State = .idle
	private var lastFrameTimestamp: TimeInterval?

	init(configuration: SwipeRightRecognizerConfiguration) {
		self.configuration = configuration
	}

	func process(
		frame: TouchFrame,
		sessionID: GestureSessionID
	) -> ThreeFingerHorizontalSwipeRecognizerResult {
		var diagnostics = [GestureDiagnosticEvent.Kind]()

		if let lastFrameTimestamp {
			if frame.timestamp < lastFrameTimestamp {
				diagnostics.append(.frameDropped(.staleFrame))
				return .init(diagnostics: diagnostics, recognizedGesture: nil)
			}
			if frame.timestamp == lastFrameTimestamp {
				diagnostics.append(.frameDropped(.duplicateFrame))
				return .init(diagnostics: diagnostics, recognizedGesture: nil)
			}
		}
		lastFrameTimestamp = frame.timestamp

		switch state {
		case .idle:
			guard frame.contacts.count == configuration.requiredFingerCount else {
				return .init(diagnostics: diagnostics, recognizedGesture: nil)
			}
			state = .priming(Candidate.initial(from: frame))
			diagnostics.append(.recognizerTransition(from: State.idle.name, to: state.name))
			return .init(diagnostics: diagnostics, recognizedGesture: nil)
		case let .priming(candidate), let .ready(candidate), let .tracking(candidate):
			return continueTracking(frame: frame, sessionID: sessionID, candidate: candidate, diagnostics: diagnostics)
		case let .committed(candidate):
			if frame.contacts.count == configuration.requiredFingerCount {
				return .init(diagnostics: diagnostics, recognizedGesture: nil)
			}
			let previousState = State.committed(candidate)
			state = .idle
			diagnostics.append(.recognizerTransition(from: previousState.name, to: state.name))
			return .init(diagnostics: diagnostics, recognizedGesture: nil)
		}
	}

	private func continueTracking(
		frame: TouchFrame,
		sessionID: GestureSessionID,
		candidate: Candidate,
		diagnostics: [GestureDiagnosticEvent.Kind]
	) -> ThreeFingerHorizontalSwipeRecognizerResult {
		var diagnostics = diagnostics
		let previousState = state

		guard frame.contacts.count == configuration.requiredFingerCount else {
			let mismatchCandidate = candidate.updatedForMismatch(timestamp: frame.timestamp)
			if mismatchCandidate.badContactFrameCount <= configuration.maximumBadContactFrames {
				state = statePreservingActiveGesturePhase(previousState, candidate: mismatchCandidate)
				return .init(diagnostics: diagnostics, recognizedGesture: nil)
			}
			state = .idle
			diagnostics.append(
				recognizerMeasurement(
					state: previousState.name,
					contactCount: frame.contacts.count,
					candidate: candidate,
					direction: candidate.directionLock,
					confidence: nil,
					timestamp: frame.timestamp
				)
			)
			diagnostics.append(.gestureRejected(.fingerCountMismatch))
			diagnostics.append(.recognizerTransition(from: previousState.name, to: State.idle.name))
			return .init(diagnostics: diagnostics, recognizedGesture: nil)
		}

		let features = SwipeGestureFrameFeatureExtractor.features(
			for: frame,
			previousFilteredCentroid: candidate.filteredCentroid,
			previousTimestamp: candidate.lastTimestamp,
			baselineCentroid: candidate.baselineCentroid,
			baselineAveragePairwiseDistance: candidate.baselineAveragePairwiseDistance,
			filterAlpha: configuration.gestureFilterAlpha,
			minimumFrameDeltaTime: configuration.minimumFrameDeltaTime
		)
		let lockedDirection = resolvedDirectionLock(for: features, previousDirection: candidate.directionLock)
		let reverseTravelAfterLock = accumulatedReverseTravel(
			for: features,
			direction: lockedDirection,
			candidate: candidate
		)
		let shapeDeviation = abs(features.spreadScaleRelativeToBaseline - 1)
		let trackingFrameIsGood = shapeDeviation <= configuration.maximumSpreadScaleDeviation
			&& features.angleFromHorizontalRadians <= configuration.maximumAngleFromHorizontalRadians
		let onsetReached = abs(features.filteredDxFromBaseline) >= configuration.directionLockDistance
			|| (
				candidate.directionLock == nil
					&& abs(features.vx) >= configuration.minimumHorizontalVelocityForOnset
					&& trackingFrameIsGood
			)

		if case .priming = previousState {
			let isStablePrimingFrame = abs(features.rawDxFromBaseline) <= configuration.primingMaximumMotion
				&& abs(features.filteredDyFromBaseline) <= configuration.maximumVerticalDrift
				&& shapeDeviation <= configuration.maximumSpreadScaleDeviation
			if isStablePrimingFrame {
				let primingCandidate = candidate.updated(
					with: features,
					directionLock: nil,
					reverseTravelAfterLock: 0,
					stablePrimingFrameCount: candidate.stablePrimingFrameCount + 1,
					consecutiveGoodTrackingFrames: 0,
					consecutiveCommitEligibleFrames: 0,
					motionHistoryLimit: configuration.motionHistoryLimit
				)
				state = .ready(primingCandidate)
				if previousState.name != state.name {
					diagnostics.append(.recognizerTransition(from: previousState.name, to: state.name))
				}
				return .init(diagnostics: diagnostics, recognizedGesture: nil)
			}
		}

		if candidate.directionLock != nil, reverseTravelAfterLock > configuration.reversalTolerance {
			state = .idle
			diagnostics.append(
				recognizerMeasurement(
					state: previousState.name,
					contactCount: frame.contacts.count,
					features: features,
					startTimestamp: candidate.startTimestamp,
					direction: lockedDirection,
					confidence: nil,
					idleDuration: frame.timestamp - candidate.lastMotionTimestamp
				)
			)
			diagnostics.append(.gestureRejected(.reversedBeforeCommit))
			diagnostics.append(.recognizerTransition(from: previousState.name, to: State.idle.name))
			return .init(diagnostics: diagnostics, recognizedGesture: nil)
		}

		if abs(features.filteredDyFromBaseline) > configuration.maximumVerticalDrift {
			state = .idle
			diagnostics.append(
				recognizerMeasurement(
					state: previousState.name,
					contactCount: frame.contacts.count,
					features: features,
					startTimestamp: candidate.startTimestamp,
					direction: lockedDirection,
					confidence: nil,
					idleDuration: frame.timestamp - candidate.lastMotionTimestamp
				)
			)
			diagnostics.append(.gestureRejected(.verticalDriftExceeded))
			diagnostics.append(.recognizerTransition(from: previousState.name, to: State.idle.name))
			return .init(diagnostics: diagnostics, recognizedGesture: nil)
		}

		let recentHistoryCandidate = candidate.updated(
			with: features,
			directionLock: lockedDirection,
			reverseTravelAfterLock: reverseTravelAfterLock,
			stablePrimingFrameCount: 0,
			consecutiveGoodTrackingFrames: 0,
			consecutiveCommitEligibleFrames: 0,
			motionHistoryLimit: configuration.motionHistoryLimit
		)
		let trackingDominance = max(
			features.horizontalDominance,
			recentHistoryCandidate.averageHorizontalDominance
		)
		let trackingAngle = max(
			features.angleFromHorizontalRadians,
			recentHistoryCandidate.averageAngleFromHorizontalRadians
		)
		let trackingFrameQualifies = trackingFrameIsGood
			&& trackingDominance >= configuration.minimumHorizontalDominance
			&& trackingAngle <= configuration.maximumAngleFromHorizontalRadians
		let consecutiveGoodTrackingFrames = trackingFrameQualifies
			? candidate.consecutiveGoodTrackingFrames + 1
			: 0
		let trackingEstablished = consecutiveGoodTrackingFrames >= configuration.minimumConsecutiveTrackingFrames
			|| (onsetReached && previousState == .tracking(candidate))
		let commitFrameEligible = trackingEstablished
			&& lockedDirection != nil
			&& abs(features.rawDxFromBaseline) >= configuration.minimumHorizontalTravel
			&& (
				recentHistoryCandidate.averageHorizontalVelocity >= configuration.minimumHorizontalVelocityForCommit
					|| abs(features.rawDxFromBaseline)
					>= configuration.minimumHorizontalTravel * configuration.fastSwipeCommitTravelMultiplier
			)
		let consecutiveCommitEligibleFrames = commitFrameEligible
			? candidate.consecutiveCommitEligibleFrames + 1
			: 0
		let nextCandidate = candidate.updated(
			with: features,
			directionLock: lockedDirection,
			reverseTravelAfterLock: reverseTravelAfterLock,
			stablePrimingFrameCount: 0,
			consecutiveGoodTrackingFrames: consecutiveGoodTrackingFrames,
			consecutiveCommitEligibleFrames: consecutiveCommitEligibleFrames,
			motionHistoryLimit: configuration.motionHistoryLimit
		)
		let confidence = gestureConfidence(features: features)

		guard let direction = lockedDirection else {
			state = onsetReached ? .tracking(nextCandidate) : .ready(nextCandidate)
			if previousState.name != state.name {
				diagnostics.append(.recognizerTransition(from: previousState.name, to: state.name))
			}
			return .init(diagnostics: diagnostics, recognizedGesture: nil)
		}

		if consecutiveCommitEligibleFrames >= configuration.minimumConsecutiveCommitEligibleFrames,
		   confidence >= configuration.minimumConfidence {
			state = .committed(nextCandidate)
			diagnostics.append(.recognizerTransition(from: previousState.name, to: state.name))
			diagnostics.append(
				recognizerMeasurement(
					state: previousState.name,
					contactCount: frame.contacts.count,
					features: features,
					startTimestamp: candidate.startTimestamp,
					direction: direction,
					confidence: confidence,
					idleDuration: frame.timestamp - candidate.lastMotionTimestamp
				)
			)
			diagnostics.append(.gestureAccepted(direction: direction, confidence: confidence))
			return .init(
				diagnostics: diagnostics,
				recognizedGesture: RecognizedGesture(
					sessionID: sessionID,
					direction: direction,
					phase: .recognized,
					timestamp: frame.timestamp,
					confidence: confidence
				)
			)
		}

		state = onsetReached
			? .tracking(nextCandidate)
			: .ready(nextCandidate)
		if previousState.name != state.name {
			diagnostics.append(.recognizerTransition(from: previousState.name, to: state.name))
		}
		return .init(diagnostics: diagnostics, recognizedGesture: nil)
	}

	private func resolvedDirectionLock(
		for features: SwipeGestureFrameFeatures,
		previousDirection: GestureDirection?
	) -> GestureDirection? {
		if let previousDirection {
			return previousDirection
		}
		guard abs(features.filteredDxFromBaseline) >= configuration.directionLockDistance else {
			return nil
		}
		return features.filteredDxFromBaseline >= 0 ? .right : .left
	}

	private func accumulatedReverseTravel(
		for features: SwipeGestureFrameFeatures,
		direction: GestureDirection?,
		candidate: Candidate
	) -> Double {
		guard let direction else { return 0 }
		switch direction {
		case .right:
			return candidate.reverseTravelAfterLock + max(0, -features.frameDx)
		case .left:
			return candidate.reverseTravelAfterLock + max(0, features.frameDx)
		}
	}

	private func recognizerMeasurement(
		state: String,
		contactCount: Int,
		candidate: Candidate,
		direction: GestureDirection?,
		confidence: Double?,
		timestamp: TimeInterval
	) -> GestureDiagnosticEvent.Kind {
		let horizontalTravel = candidate.latestRawCentroid.x - candidate.baselineCentroid.x
		let verticalDrift = candidate.latestRawCentroid.y - candidate.baselineCentroid.y
		return .recognizerMeasurement(
			state: state,
			contactCount: contactCount,
			direction: direction,
			horizontalTravel: horizontalTravel,
			verticalDrift: verticalDrift,
			duration: timestamp - candidate.startTimestamp,
			idleDuration: timestamp - candidate.lastMotionTimestamp,
			confidence: confidence,
			minimumHorizontalTravel: configuration.minimumHorizontalTravel,
			maximumVerticalDrift: configuration.maximumVerticalDrift,
			minimumConfidence: configuration.minimumConfidence
		)
	}

	private func recognizerMeasurement(
		state: String,
		contactCount: Int,
		features: SwipeGestureFrameFeatures,
		startTimestamp: TimeInterval,
		direction: GestureDirection?,
		confidence: Double?,
		idleDuration: TimeInterval
	) -> GestureDiagnosticEvent.Kind {
		return .recognizerMeasurement(
			state: state,
			contactCount: contactCount,
			direction: direction,
			horizontalTravel: features.rawDxFromBaseline,
			verticalDrift: features.filteredDyFromBaseline,
			duration: features.timestamp - startTimestamp,
			idleDuration: idleDuration,
			confidence: confidence,
			minimumHorizontalTravel: configuration.minimumHorizontalTravel,
			maximumVerticalDrift: configuration.maximumVerticalDrift,
			minimumConfidence: configuration.minimumConfidence
		)
	}

	private func gestureConfidence(features: SwipeGestureFrameFeatures) -> Double {
		let horizontalProgressScore = min(
			max(abs(features.rawDxFromBaseline) / configuration.minimumHorizontalTravel, 0),
			1
		)
		let verticalScore = max(
			0,
			1 - min(abs(features.filteredDyFromBaseline) / configuration.maximumVerticalDrift, 1)
		)
		let shapeDeviation = abs(features.spreadScaleRelativeToBaseline - 1)
		let shapeStabilityScore = max(
			0,
			1 - min(shapeDeviation / configuration.maximumSpreadScaleDeviation, 1)
		)

		return (horizontalProgressScore * 0.45)
			+ (max(features.horizontalDominance, 1 - (features.angleFromHorizontalRadians / (.pi / 2))) * 0.25)
			+ (verticalScore * 0.15)
			+ (shapeStabilityScore * 0.15)
	}

	private func statePreservingActiveGesturePhase(_ state: State, candidate: Candidate) -> State {
		if case .priming = state {
			return .priming(candidate)
		}
		if case .ready = state {
			return .ready(candidate)
		}
		return .tracking(candidate)
	}
}

typealias SwipeRightGestureRecognizer = ThreeFingerHorizontalSwipeRecognizer
typealias SwipeRightGestureRecognizerResult = ThreeFingerHorizontalSwipeRecognizerResult
