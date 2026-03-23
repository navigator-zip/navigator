import Foundation

public typealias BrowserPermissionSessionID = UInt64

public enum BrowserPermissionKind: String, Codable, CaseIterable, Sendable {
	case camera
	case microphone
	case geolocation

	public var bridgeFlag: UInt32 {
		switch self {
		case .camera:
			1 << 0
		case .microphone:
			1 << 1
		case .geolocation:
			1 << 2
		}
	}
}

public struct BrowserPermissionKindSet: OptionSet, Hashable, Sendable, Codable {
	public let rawValue: UInt32

	public init(rawValue: UInt32) {
		self.rawValue = rawValue
	}

	public static let camera = Self(rawValue: BrowserPermissionKind.camera.bridgeFlag)
	public static let microphone = Self(rawValue: BrowserPermissionKind.microphone.bridgeFlag)
	public static let geolocation = Self(rawValue: BrowserPermissionKind.geolocation.bridgeFlag)

	public static let all: Self = [.camera, .microphone, .geolocation]

	public var kinds: [BrowserPermissionKind] {
		BrowserPermissionKind.allCases.filter { contains(Self(kind: $0)) }
	}

	public init(kind: BrowserPermissionKind) {
		self.init(rawValue: kind.bridgeFlag)
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()
		rawValue = try container.decode(UInt32.self)
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		try container.encode(rawValue)
	}
}

public enum BrowserPermissionRequestSource: UInt32, Codable, Sendable {
	case mediaAccess = 0
	case permissionPrompt = 1
}

public enum BrowserPermissionResolution: UInt32, Codable, Sendable {
	case deny = 0
	case allow = 1
	case cancel = 2
}

public enum BrowserPermissionSessionDismissReason: UInt32, Codable, Sendable {
	case unknown = 0
	case browserClosed = 1
	case renderProcessTerminated = 2
	case mainFrameNavigation = 3
	case promptDismissed = 4
	case explicitCancel = 5
}

public enum BrowserPermissionPromptDecision: String, Codable, Sendable {
	case allow
	case deny
}

public enum BrowserPermissionPersistence: String, Codable, Sendable {
	case session
	case remember
}

public enum BrowserPermissionSessionLifecycleState: String, Codable, Sendable {
	case requestedBySite
	case checkingStoredPolicy
	case waitingForUserPrompt
	case waitingForOSAuthorization
	case resolvedAllow
	case resolvedDeny
	case cancelled
}

public enum BrowserPermissionOSAuthorizationStatus: String, Codable, Sendable {
	case notDetermined
	case denied
	case restricted
	case authorized
	case unsupported
}

public struct BrowserPermissionOSAuthorizationState: Codable, Equatable, Sendable {
	public var camera: BrowserPermissionOSAuthorizationStatus
	public var microphone: BrowserPermissionOSAuthorizationStatus
	public var geolocation: BrowserPermissionOSAuthorizationStatus

	public init(
		camera: BrowserPermissionOSAuthorizationStatus = .notDetermined,
		microphone: BrowserPermissionOSAuthorizationStatus = .notDetermined,
		geolocation: BrowserPermissionOSAuthorizationStatus = .notDetermined
	) {
		self.camera = camera
		self.microphone = microphone
		self.geolocation = geolocation
	}

	public subscript(kind: BrowserPermissionKind) -> BrowserPermissionOSAuthorizationStatus {
		get {
			switch kind {
			case .camera:
				camera
			case .microphone:
				microphone
			case .geolocation:
				geolocation
			}
		}
		set {
			switch kind {
			case .camera:
				camera = newValue
			case .microphone:
				microphone = newValue
			case .geolocation:
				geolocation = newValue
			}
		}
	}
}

public struct BrowserPermissionOrigin: Codable, Equatable, Sendable {
	public let requestingOrigin: String
	public let topLevelOrigin: String

	public init(requestingOrigin: String, topLevelOrigin: String) {
		self.requestingOrigin = requestingOrigin
		self.topLevelOrigin = topLevelOrigin
	}
}

public struct BrowserPermissionSession: Identifiable, Codable, Equatable, Sendable {
	public let id: BrowserPermissionSessionID
	public let browserID: UInt64
	public let promptID: UInt64
	public let frameIdentifier: String?
	public let source: BrowserPermissionRequestSource
	public let origin: BrowserPermissionOrigin
	public let requestedKinds: BrowserPermissionKindSet
	public let promptKinds: BrowserPermissionKindSet
	public let state: BrowserPermissionSessionLifecycleState
	public let siteDecision: BrowserPermissionPromptDecision?
	public let persistence: BrowserPermissionPersistence?
	public let osAuthorizationState: BrowserPermissionOSAuthorizationState
	public let createdAt: Date
	public let updatedAt: Date

	public init(
		id: BrowserPermissionSessionID,
		browserID: UInt64,
		promptID: UInt64,
		frameIdentifier: String?,
		source: BrowserPermissionRequestSource,
		origin: BrowserPermissionOrigin,
		requestedKinds: BrowserPermissionKindSet,
		promptKinds: BrowserPermissionKindSet,
		state: BrowserPermissionSessionLifecycleState,
		siteDecision: BrowserPermissionPromptDecision?,
		persistence: BrowserPermissionPersistence?,
		osAuthorizationState: BrowserPermissionOSAuthorizationState,
		createdAt: Date,
		updatedAt: Date
	) {
		self.id = id
		self.browserID = browserID
		self.promptID = promptID
		self.frameIdentifier = frameIdentifier
		self.source = source
		self.origin = origin
		self.requestedKinds = requestedKinds
		self.promptKinds = promptKinds
		self.state = state
		self.siteDecision = siteDecision
		self.persistence = persistence
		self.osAuthorizationState = osAuthorizationState
		self.createdAt = createdAt
		self.updatedAt = updatedAt
	}
}

public struct BrowserStoredPermissionDecisionKey: Codable, Equatable, Hashable, Sendable {
	public let requestingOrigin: String
	public let topLevelOrigin: String
	public let kind: BrowserPermissionKind

	public init(
		requestingOrigin: String,
		topLevelOrigin: String,
		kind: BrowserPermissionKind
	) {
		self.requestingOrigin = requestingOrigin
		self.topLevelOrigin = topLevelOrigin
		self.kind = kind
	}
}

public struct BrowserStoredPermissionDecision: Identifiable, Codable, Equatable, Sendable {
	public var id: String {
		"\(key.requestingOrigin)|\(key.topLevelOrigin)|\(key.kind.rawValue)"
	}

	public let key: BrowserStoredPermissionDecisionKey
	public let decision: BrowserPermissionPromptDecision
	public let updatedAt: Date

	public init(
		key: BrowserStoredPermissionDecisionKey,
		decision: BrowserPermissionPromptDecision,
		updatedAt: Date
	) {
		self.key = key
		self.decision = decision
		self.updatedAt = updatedAt
	}
}

public struct BrowserStoredPermissionDecisionStore: Codable, Equatable, Sendable {
	public static let currentVersion = 1

	public let storageVersion: Int
	public let decisions: [BrowserStoredPermissionDecision]

	public init(
		storageVersion: Int = Self.currentVersion,
		decisions: [BrowserStoredPermissionDecision]
	) {
		self.storageVersion = storageVersion
		self.decisions = decisions
	}

	public static let empty = Self(decisions: [])
}
