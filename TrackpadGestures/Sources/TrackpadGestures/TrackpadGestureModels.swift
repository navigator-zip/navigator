import Foundation

public enum TrackpadGestureAvailability: String, Sendable {
	case unsupportedOS
	case frameworkUnavailable
	case noTrackpadDetected
	case accessibilityDenied
	case inputMonitoringDenied
	case captureFailed
	case running
}

public enum TrackpadGestureRuntimeState: String, Sendable {
	case stopped
	case starting
	case running
	case degraded
	case stopping
	case failed
}

public struct GestureSessionID: Hashable, Codable, Sendable {
	public let rawValue: UUID

	public init(rawValue: UUID) {
		self.rawValue = rawValue
	}

	public init() {
		self.init(rawValue: UUID())
	}
}

public enum TouchContactPhase: String, Codable, Sendable {
	case began
	case moved
	case stationary
	case ended
	case cancelled
	case unknown
}

public struct TouchContact: Equatable, Codable, Sendable {
	public let identifier: Int
	public let phase: TouchContactPhase
	public let normalizedX: Double
	public let normalizedY: Double
	public let majorAxis: Double
	public let minorAxis: Double
	public let pressure: Double
	public let angle: Double

	public init(
		identifier: Int,
		phase: TouchContactPhase,
		normalizedX: Double,
		normalizedY: Double,
		majorAxis: Double,
		minorAxis: Double,
		pressure: Double,
		angle: Double
	) {
		self.identifier = identifier
		self.phase = phase
		self.normalizedX = normalizedX
		self.normalizedY = normalizedY
		self.majorAxis = majorAxis
		self.minorAxis = minorAxis
		self.pressure = pressure
		self.angle = angle
	}
}

public struct TouchFrame: Equatable, Codable, Sendable {
	public let timestamp: TimeInterval
	public let contacts: [TouchContact]
	public let centroidX: Double
	public let centroidY: Double

	public init(timestamp: TimeInterval, contacts: [TouchContact]) {
		self.timestamp = timestamp
		self.contacts = contacts
		if contacts.isEmpty {
			centroidX = 0
			centroidY = 0
		}
		else {
			centroidX = contacts.map(\.normalizedX).reduce(0, +) / Double(contacts.count)
			centroidY = contacts.map(\.normalizedY).reduce(0, +) / Double(contacts.count)
		}
	}

	private enum CodingKeys: String, CodingKey {
		case timestamp
		case contacts
	}

	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let timestamp = try container.decode(TimeInterval.self, forKey: .timestamp)
		let contacts = try container.decode([TouchContact].self, forKey: .contacts)
		self.init(timestamp: timestamp, contacts: contacts)
	}

	public func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(timestamp, forKey: .timestamp)
		try container.encode(contacts, forKey: .contacts)
	}
}

public enum GestureDirection: String, Codable, Sendable {
	case right
	case left
}

public enum GesturePhase: String, Codable, Sendable {
	case recognized
}

public struct RecognizedGesture: Equatable, Sendable {
	public let sessionID: GestureSessionID
	public let direction: GestureDirection
	public let phase: GesturePhase
	public let timestamp: TimeInterval
	public let confidence: Double

	public init(
		sessionID: GestureSessionID,
		direction: GestureDirection,
		phase: GesturePhase,
		timestamp: TimeInterval,
		confidence: Double
	) {
		self.sessionID = sessionID
		self.direction = direction
		self.phase = phase
		self.timestamp = timestamp
		self.confidence = confidence
	}

	public var kind: TrackpadGestureKind {
		.threeFingerHorizontalSwipe(direction: direction)
	}
}

public enum GestureRejectReason: String, Codable, Sendable {
	case fingerCountMismatch
	case verticalDriftExceeded
	case reversedBeforeCommit
	case dominantLeftwardMotion
	case insufficientConfidence
	case staleFrame
	case duplicateFrame
}

public struct GestureDiagnosticEvent: Equatable, Sendable, CustomStringConvertible {
	public enum Kind: Equatable, Sendable {
		case sessionStarted
		case sessionStopped
		case runtimeStateChanged(TrackpadGestureRuntimeState)
		case osVersion(String)
		case frameworkOpenAttempt(String)
		case frameworkLoaded(String)
		case frameworkOpened(String)
		case frameworkReady(String)
		case frameworkCloseAttempted(String)
		case frameworkCloseSkipped(String)
		case frameworkClosed(String)
		case frameworkLoadFailed(String)
		case symbolResolved(String)
		case symbolMissing(String)
		case deviceListCreationAttempt(path: String)
		case deviceListCreationResult(count: Int)
		case startupCompleted(deviceCount: Int)
		case startupFailed(String)
		case permissionSnapshot(accessibilityTrusted: Bool, inputMonitoringTrusted: Bool)
		case deviceSelectionStrategy(String)
		case frameworkSessionCreated(sessionID: UUID)
		case sessionCallbackRegistered(sessionID: UUID, device: String)
		case sessionDeviceStarted(sessionID: UUID, device: String)
		case sessionStateTransition(sessionID: UUID, state: MultitouchDeviceSessionState)
		case sessionShutdownRequested(sessionID: UUID, device: String)
		case callbackUnregistered(sessionID: UUID, device: String)
		case deviceStopped(sessionID: UUID, device: String)
		case deviceReleased(sessionID: UUID, device: String)
		case callbackIgnoredWhileStopping(sessionID: UUID, device: String)
		case callbackInFlightState(sessionID: UUID, device: String, inFlightCount: Int)
		case shutdownQuiescenceWaiting(sessionID: UUID, device: String)
		case shutdownQuiescenceComplete(sessionID: UUID, device: String)
		case deviceRegistered(String)
		case deviceUnregistered(String)
		case wakeRescanTriggered
		case frameDropped(GestureRejectReason)
		case recognizerMeasurement(
			state: String,
			contactCount: Int,
			direction: GestureDirection?,
			horizontalTravel: Double,
			verticalDrift: Double,
			duration: TimeInterval,
			idleDuration: TimeInterval,
			confidence: Double?,
			minimumHorizontalTravel: Double,
			maximumVerticalDrift: Double,
			minimumConfidence: Double
		)
		case recognizerTransition(from: String, to: String)
		case gestureAccepted(direction: GestureDirection, confidence: Double)
		case gestureRejected(GestureRejectReason)
		case actionDispatched(String)
		case killSwitchActivated(String)
	}

	public let sessionID: GestureSessionID
	public let timestamp: TimeInterval
	public let kind: Kind

	public init(sessionID: GestureSessionID, timestamp: TimeInterval, kind: Kind) {
		self.sessionID = sessionID
		self.timestamp = timestamp
		self.kind = kind
	}

	public var description: String {
		"session=\(sessionID.rawValue.uuidString) time=\(timestamp) kind=\(kind)"
	}
}

public struct SwipeRightRecognizerConfiguration: Equatable, Codable, Sendable {
	public let minimumHorizontalTravel: Double
	public let maximumVerticalDrift: Double
	public let smoothingWindow: Int
	public let reversalTolerance: Double
	public let minimumConfidence: Double

	public init(
		minimumHorizontalTravel: Double,
		maximumVerticalDrift: Double,
		smoothingWindow: Int,
		reversalTolerance: Double,
		minimumConfidence: Double
	) {
		self.minimumHorizontalTravel = minimumHorizontalTravel
		self.maximumVerticalDrift = maximumVerticalDrift
		self.smoothingWindow = smoothingWindow
		self.reversalTolerance = reversalTolerance
		self.minimumConfidence = minimumConfidence
	}

	public static let v1 = SwipeRightRecognizerConfiguration(
		minimumHorizontalTravel: 0.08,
		maximumVerticalDrift: 0.12,
		smoothingWindow: 3,
		reversalTolerance: 0.03,
		minimumConfidence: 0.55
	)
}

public enum TrackpadGestureKind: Equatable, Codable, Sendable {
	case threeFingerHorizontalSwipe(direction: GestureDirection)
}

public enum TrackpadGesturePermissionKind: String, Codable, CaseIterable, Sendable {
	case accessibility
	case inputMonitoring
}

public struct TrackpadGesturePermissionStatus: Equatable, Codable, Sendable {
	public let accessibilityTrusted: Bool
	public let inputMonitoringTrusted: Bool

	public init(accessibilityTrusted: Bool, inputMonitoringTrusted: Bool) {
		self.accessibilityTrusted = accessibilityTrusted
		self.inputMonitoringTrusted = inputMonitoringTrusted
	}

	public func isTrusted(for kind: TrackpadGesturePermissionKind) -> Bool {
		switch kind {
		case .accessibility:
			accessibilityTrusted
		case .inputMonitoring:
			inputMonitoringTrusted
		}
	}

	public func missingPermissions(in requiredPermissions: [TrackpadGesturePermissionKind])
		-> [TrackpadGesturePermissionKind] {
		requiredPermissions.filter { isTrusted(for: $0) == false }
	}
}

public enum TrackpadGesturePermissionPolicy: Equatable, Sendable {
	case reportMissingAsDegraded([TrackpadGesturePermissionKind])
	case require([TrackpadGesturePermissionKind])

	public static let diagnosticOnly = TrackpadGesturePermissionPolicy.reportMissingAsDegraded(
		TrackpadGesturePermissionKind.allCases
	)

	public static let requireAll = TrackpadGesturePermissionPolicy.require(
		TrackpadGesturePermissionKind.allCases
	)

	var trackedPermissions: [TrackpadGesturePermissionKind] {
		switch self {
		case let .reportMissingAsDegraded(permissions), let .require(permissions):
			permissions
		}
	}
}

public enum TrackpadGestureCapabilityWarning: Equatable, Sendable {
	case permissionDenied(TrackpadGesturePermissionKind)
}

public enum TrackpadGestureBackendFailure: Error, Equatable, Sendable {
	case frameworkUnavailable(String)
	case noTrackpadsDetected
	case captureFailed(String)
}

public enum TrackpadGestureUnavailabilityReason: Error, Equatable, Sendable {
	case unsupportedOS
	case permissionDenied(TrackpadGesturePermissionKind)
	case backendFailure(TrackpadGestureBackendFailure)
	case disabled(String)
}

public struct TrackpadGestureCapabilityDetails: Equatable, Sendable {
	public let permissionStatus: TrackpadGesturePermissionStatus

	public init(permissionStatus: TrackpadGesturePermissionStatus) {
		self.permissionStatus = permissionStatus
	}
}

public enum TrackpadGestureCapability: Equatable, Sendable {
	case available(TrackpadGestureCapabilityDetails)
	case degraded(TrackpadGestureCapabilityDetails, warnings: [TrackpadGestureCapabilityWarning])
	case unavailable(TrackpadGestureUnavailabilityReason)
}

public enum TrackpadGestureError: Error, Equatable, Sendable {
	case alreadyRunning
	case capabilityUnavailable(TrackpadGestureUnavailabilityReason)
	case backendStartFailed(TrackpadGestureBackendFailure)
}

public enum TrackpadGestureServiceState: Equatable, Sendable {
	case idle
	case starting
	case running(GestureSessionID)
	case stopping(GestureSessionID)
	case failed(TrackpadGestureError)
	case disabled(TrackpadGestureUnavailabilityReason)
}
