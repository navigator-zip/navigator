import Foundation

public typealias JSONObject = [String: JSONValue]

public enum NavigatorAPICoding {
	public static let jsonEncoder: JSONEncoder = {
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .custom { date, encoder in
			var container = encoder.singleValueContainer()
			try container.encode(iso8601String(from: date))
		}
		encoder.outputFormatting = [.sortedKeys]
		return encoder
	}()

	public static let jsonDecoder: JSONDecoder = {
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .custom { decoder in
			let container = try decoder.singleValueContainer()
			let value = try container.decode(String.self)
			guard let date = navigatorAPIDate(from: value) else {
				throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format: \(value)")
			}
			return date
		}
		return decoder
	}()

	public static func encode(_ value: some Codable) throws -> Data {
		try jsonEncoder.encode(value)
	}

	public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
		try jsonDecoder.decode(type, from: data)
	}
}

private func iso8601String(from date: Date) -> String {
	let formatter = ISO8601DateFormatter()
	formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
	return formatter.string(from: date)
}

private func navigatorAPIDate(from value: String) -> Date? {
	let withFractions = ISO8601DateFormatter()
	withFractions.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
	if let parsed = withFractions.date(from: value) {
		return parsed
	}

	let withoutFractions = ISO8601DateFormatter()
	withoutFractions.formatOptions = [.withInternetDateTime]
	return withoutFractions.date(from: value)
}

public enum NavigatorAPIErrorCode: String, Codable, Sendable {
	case badRequestValidation = "BAD_REQUEST_VALIDATION"
	case unauthenticated = "AUTH_UNAUTHENTICATED"
	case forbidden = "AUTH_FORBIDDEN"
	case resourceNotFound = "RESOURCE_NOT_FOUND"
	case revisionConflict = "CONFLICT_REVISION_MISMATCH"
	case idempotencyReplay = "CONFLICT_IDEMPOTENCY_REPLAY"
	case preconditionFailed = "PRECONDITION_FAILED"
	case semanticValidation = "SEMANTIC_VALIDATION_FAILED"
	case rateLimited = "RATE_LIMITED"
	case internalError = "INTERNAL_ERROR"
	case dependencyUnavailable = "DEPENDENCY_UNAVAILABLE"
	case replayRequired = "REPLAY_REQUIRED"
	case entitlementRequired = "ENTITLEMENT_REQUIRED"
	case limitExceeded = "LIMIT_EXCEEDED"
	case apiVersionUnsupported = "API_VERSION_UNSUPPORTED"
}

public struct NavigatorAPIErrorDetails: Codable, Sendable {
	public let code: NavigatorAPIErrorCode
	public let message: String
	public let details: JSONObject?
}

public enum NavigatorAPIError: Error, LocalizedError, Sendable {
	case transport(Error)
	case invalidURL
	case invalidResponse
	case invalidPayload(underlying: Error)
	case apiError(NavigatorAPIErrorDetails)
	case validationError(message: String, errors: JSONObject)
	case messageError(message: String)
	case httpStatus(statusCode: Int)

	public var errorDescription: String? {
		switch self {
		case .transport(let error):
			return "Network transport failed: \(error.localizedDescription)"
		case .invalidURL:
			return "Request URL was invalid"
		case .invalidResponse:
			return "Server returned non-HTTP response"
		case .invalidPayload(let underlying):
			return "Response payload was malformed: \(underlying.localizedDescription)"
		case .apiError(let details):
			return "\(details.code.rawValue): \(details.message)"
		case .validationError(let message, _):
			return message
		case .messageError(let message):
			return message
		case .httpStatus(let statusCode):
			return "Server returned unexpected HTTP status: \(statusCode)"
		}
	}
}

public enum JSONValue: Codable, Sendable {
	case null
	case bool(Bool)
	case number(Double)
	case string(String)
	case array([JSONValue])
	case object(JSONObject)

	public init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()
		if container.decodeNil() {
			self = .null
		}
		else if let value = try? container.decode(Bool.self) {
			self = .bool(value)
		}
		else if let value = try? container.decode(Double.self) {
			self = .number(value)
		}
		else if let value = try? container.decode(String.self) {
			self = .string(value)
		}
		else if let value = try? container.decode([JSONValue].self) {
			self = .array(value)
		}
		else if let value = try? container.decode(JSONObject.self) {
			self = .object(value)
		}
		else {
			throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid JSON value")
		}
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		switch self {
		case .null:
			try container.encodeNil()
		case .bool(let value):
			try container.encode(value)
		case .number(let value):
			try container.encode(value)
		case .string(let value):
			try container.encode(value)
		case .array(let value):
			try container.encode(value)
		case .object(let value):
			try container.encode(value)
		}
	}
}

public struct NavigatorAPIEnvelope<T: Codable & Sendable>: Codable, Sendable {
	public let ok: Bool
	public let data: T
	public let meta: NavigatorAPIMeta
}

public struct NavigatorAPIMeta: Codable, Sendable {
	public let requestID: String
	public let cursor: String?
}

public struct NavigatorAPIErrorEnvelope: Codable, Sendable {
	public let ok: Bool
	public let error: NavigatorAPIErrorDetails
	public let meta: NavigatorAPIMeta
}

public struct NavigatorAPIMessageErrorResponse: Codable, Sendable {
	public let message: String
}

public struct NavigatorAPIValidationErrorResponse: Codable, Sendable {
	public let message: String
	public let errors: JSONObject
}

public struct EmptyPayload: Codable, Sendable {}

public enum NavigatorAPINonNegativeIntegerLike: Codable, Sendable, Equatable {
	case integer(Int)
	case string(String)

	public init(integer: Int) {
		self = .integer(integer)
	}

	public init(string: String) {
		self = .string(string)
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()
		if let value = try? container.decode(Int.self) {
			self = .integer(value)
			return
		}
		self = try .string(container.decode(String.self))
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		switch self {
		case .integer(let value):
			try container.encode(value)
		case .string(let value):
			try container.encode(value)
		}
	}
}

public enum NavigatorAPIPositiveIntegerLike: Codable, Sendable, Equatable {
	case integer(Int)
	case string(String)

	public init(integer: Int) {
		self = .integer(integer)
	}

	public init(string: String) {
		self = .string(string)
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()
		if let value = try? container.decode(Int.self) {
			self = .integer(value)
			return
		}
		self = try .string(container.decode(String.self))
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		switch self {
		case .integer(let value):
			try container.encode(value)
		case .string(let value):
			try container.encode(value)
		}
	}
}

public enum AuthChannel: String, Codable, Sendable {
	case email
}

public enum Role: String, Codable, Sendable {
	case admin
	case user
}

public enum PremiumProvider: String, Codable, Sendable {
	case apple
	case stripe
}

public enum SubscriptionStatus: String, Codable, Sendable {
	case active
	case canceled
	case incomplete
	case incompleteExpired = "incomplete_expired"
	case pastDue = "past_due"
	case paused
	case trialing
	case unpaid
}

public enum SyncDeviceApprovalState: String, Codable, Sendable {
	case approved
	case pending
	case revoked
}

public enum SyncDeviceEnvelopeKind: String, Codable, Sendable {
	case accountMasterKey
	case collectionKey
}

public enum SyncEntityKind: String, Codable, Sendable {
	case bookmark
	case bookmarkFolder
	case bookmarkTag
	case tab
	case tabGroup
	case workspace
}

public enum SyncObjectKind: String, Codable, Sendable {
	case bookmark
	case bookmarkFolder
	case bookmarkTag
	case tab
	case tabGroup
	case workspace
}

public enum SyncRecoveryScheme: String, Codable, Sendable {
	case generatedMnemonic
	case passphraseDerived
}

public enum SyncSnapshotKind: String, Codable, Sendable {
	case full
}

public struct AuthAuthenticateRequest: Codable, Sendable {
	public let channel: AuthChannel
	public let value: String

	public init(channel: AuthChannel, value: String) {
		self.channel = channel
		self.value = value
	}
}

public struct AuthResendRequest: Codable, Sendable {
	public let channel: AuthChannel
	public let resendCode: String
	public let value: String

	public init(channel: AuthChannel, resendCode: String, value: String) {
		self.channel = channel
		self.resendCode = resendCode
		self.value = value
	}
}

public struct AuthVerifyRequest: Codable, Sendable {
	public let channel: AuthChannel
	public let code: String
	public let sessionName: String
	public let value: String

	public init(channel: AuthChannel, code: String, sessionName: String, value: String) {
		self.channel = channel
		self.code = code
		self.sessionName = sessionName
		self.value = value
	}
}

public struct BillingCheckoutSessionRequest: Codable, Sendable {
	public let couponCode: String?
	public let priceID: String

	public init(couponCode: String?, priceID: String) {
		self.couponCode = couponCode
		self.priceID = priceID
	}
}

public struct SyncEventAppendRequest: Codable, Sendable {
	public let clientMutationID: String?
	public let entityID: String?
	public let entityKind: SyncEntityKind
	public let event: SyncEnvelope
	public let expectedCursor: NavigatorAPINonNegativeIntegerLike
	public let expectedObjectVersion: NavigatorAPINonNegativeIntegerLike
	public let object: SyncObjectEnvelope

	public init(
		clientMutationID: String?,
		entityID: String?,
		entityKind: SyncEntityKind,
		event: SyncEnvelope,
		expectedCursor: NavigatorAPINonNegativeIntegerLike,
		expectedObjectVersion: NavigatorAPINonNegativeIntegerLike,
		object: SyncObjectEnvelope
	) {
		self.clientMutationID = clientMutationID
		self.entityID = entityID
		self.entityKind = entityKind
		self.event = event
		self.expectedCursor = expectedCursor
		self.expectedObjectVersion = expectedObjectVersion
		self.object = object
	}
}

public struct SyncSnapshotMutationRequest: Codable, Sendable {
	public let aad: JSONObject
	public let ciphertext: String
	public let cursor: NavigatorAPINonNegativeIntegerLike
	public let keyID: String
	public let nonce: String
	public let snapshotKind: SyncSnapshotKind
	public let suite: String
	public let version: Int

	public init(
		aad: JSONObject,
		ciphertext: String,
		cursor: NavigatorAPINonNegativeIntegerLike,
		keyID: String,
		nonce: String,
		snapshotKind: SyncSnapshotKind,
		suite: String,
		version: Int
	) {
		self.aad = aad
		self.ciphertext = ciphertext
		self.cursor = cursor
		self.keyID = keyID
		self.nonce = nonce
		self.snapshotKind = snapshotKind
		self.suite = suite
		self.version = version
	}
}

public struct SyncDevicePendingRequest: Codable, Sendable {
	public let agreementKeyFingerprint: String
	public let agreementPublicKey: String
	public let challenge: String
	public let deviceID: String
	public let displayName: String
	public let signingKeyFingerprint: String
	public let signingPublicKey: String

	public init(
		agreementKeyFingerprint: String,
		agreementPublicKey: String,
		challenge: String,
		deviceID: String,
		displayName: String,
		signingKeyFingerprint: String,
		signingPublicKey: String
	) {
		self.agreementKeyFingerprint = agreementKeyFingerprint
		self.agreementPublicKey = agreementPublicKey
		self.challenge = challenge
		self.deviceID = deviceID
		self.displayName = displayName
		self.signingKeyFingerprint = signingKeyFingerprint
		self.signingPublicKey = signingPublicKey
	}
}

public struct SyncDeviceApproveEnvelopeRequest: Codable, Sendable {
	public let ciphertext: String
	public let keyID: String
	public let kind: SyncDeviceEnvelopeKind
	public let recipientKeyFingerprint: String
	public let suite: String
	public let version: Int

	public init(
		ciphertext: String,
		keyID: String,
		kind: SyncDeviceEnvelopeKind,
		recipientKeyFingerprint: String,
		suite: String,
		version: Int
	) {
		self.ciphertext = ciphertext
		self.keyID = keyID
		self.kind = kind
		self.recipientKeyFingerprint = recipientKeyFingerprint
		self.suite = suite
		self.version = version
	}
}

public struct SyncDeviceApproveRequest: Codable, Sendable {
	public let approvalPayload: JSONObject
	public let approverDeviceID: String
	public let envelopes: [SyncDeviceApproveEnvelopeRequest]

	public init(
		approvalPayload: JSONObject,
		approverDeviceID: String,
		envelopes: [SyncDeviceApproveEnvelopeRequest]
	) {
		self.approvalPayload = approvalPayload
		self.approverDeviceID = approverDeviceID
		self.envelopes = envelopes
	}
}

public struct SyncDeviceRevokeRequest: Codable, Sendable {
	public let revokedByDeviceID: String?

	public init(revokedByDeviceID: String?) {
		self.revokedByDeviceID = revokedByDeviceID
	}
}

public struct SyncRecoveryEnvelopePutRequest: Codable, Sendable {
	public let ciphertext: String
	public let kdfParams: JSONObject?
	public let scheme: SyncRecoveryScheme
	public let version: Int

	public init(ciphertext: String, kdfParams: JSONObject?, scheme: SyncRecoveryScheme, version: Int) {
		self.ciphertext = ciphertext
		self.kdfParams = kdfParams
		self.scheme = scheme
		self.version = version
	}
}

public struct AccountDeletionConfirmRequest: Codable, Sendable {
	public let code: String

	public init(code: String) {
		self.code = code
	}
}

public struct HealthStatus: Codable, Sendable {
	public let status: String
}

public struct HealthReadinessChecks: Codable, Sendable {
	public let database: Bool
	public let websocketHub: Bool
	public let workerQueue: Bool
}

public struct HealthReady: Codable, Sendable {
	public let checks: HealthReadinessChecks
	public let status: String
}

public struct AuthChallengeData: Codable, Sendable {
	public let expiresAt: Date
	public let resendCode: String
	public let resendValidFrom: Date
}

public struct SessionRecord: Codable, Sendable {
	public let createdAt: Date
	public let id: String
	public let name: String
	public let token: String
	public let updatedAt: Date
	public let userID: String
}

public struct UserProfile: Codable, Sendable {
	public let createdAt: Date
	public let deletedAt: Date?
	public let email: String?
	public let id: String
	public let name: String?
	public let phone: String?
	public let roles: [Role]
}

public struct UserRecord: Codable, Sendable {
	public let createdAt: Date
	public let deletedAt: Date?
	public let email: String?
	public let id: String
	public let name: String?
	public let phone: String?
	public let purgeAfter: Date?
	public let roles: [Role]
	public let stripeCustomerID: String?
	public let updatedAt: Date
}

public struct AuthAccount: Codable, Sendable {
	public let session: SessionRecord
	public let user: UserRecord
}

public struct AuthVerifyData: Codable, Sendable {
	public let account: AuthAccount
}

public struct LogoutResponseData: Codable, Sendable {
	public let loggedOut: Bool
}

public struct LogoutAllResponseData: Codable, Sendable {
	public let loggedOutAll: Bool
}

public struct UrlResponseData: Codable, Sendable {
	public let url: String
}

public struct PremiumSubscriptionItemRecord: Codable, Sendable {
	public let createdAt: Date
	public let currentPeriodEnd: Date
	public let currentPeriodStart: Date
	public let metadata: JSONObject
	public let priceID: String
	public let providerSubscriptionItemID: String
	public let quantity: Int
	public let subscriptionID: String
	public let updatedAt: Date
}

public struct PremiumSubscriptionRecord: Codable, Sendable {
	public let billingCycleAnchor: Date?
	public let cancelAt: Date?
	public let cancelAtPeriodEnd: Bool
	public let canceledAt: Date?
	public let createdAt: Date
	public let currentPeriodEnd: Date
	public let currentPeriodStart: Date
	public let defaultPaymentMethod: String?
	public let items: [PremiumSubscriptionItemRecord]
	public let livemode: Bool
	public let metadata: JSONObject
	public let provider: PremiumProvider
	public let providerSubscriptionID: String
	public let quantity: Int?
	public let startDate: Date
	public let status: SubscriptionStatus
	public let updatedAt: Date
	public let userID: String
}

public struct CursorPageInfo: Codable, Sendable {
	public let endCursor: String?
	public let hasNextPage: Bool
}

public struct OrderRecord: Codable, Sendable {
	public let createdAt: Date
	public let id: String
	public let status: String
	public let stripeCheckoutSessionID: String
	public let stripeCustomerID: String?
	public let updatedAt: Date
}

public struct OrderEdge: Codable, Sendable {
	public let cursor: String
	public let node: OrderRecord
}

public struct OrderConnection: Codable, Sendable {
	public let edges: [OrderEdge]
	public let pageInfo: CursorPageInfo
	public let totalCount: Int
}

public struct AuditLogRecord: Codable, Sendable {
	public let action: String
	public let actorUserID: String?
	public let createdAt: Date
	public let entityID: String?
	public let entityType: String
	public let id: String
	public let ip: String?
	public let metadata: JSONObject?
	public let requestID: String?
	public let updatedAt: Date
	public let userAgent: String?
	public let userID: String?
}

public struct AuditLogEdge: Codable, Sendable {
	public let cursor: String
	public let node: AuditLogRecord
}

public struct AuditLogConnection: Codable, Sendable {
	public let edges: [AuditLogEdge]
	public let pageInfo: CursorPageInfo
}

public struct AccountDeletionRequestResponseData: Codable, Sendable {
	public let expiresAt: Date
	public let resendCode: String
	public let resendValidFrom: Date
	public let scheduledPurgeAt: Date
}

public struct AccountDeletionConfirmResponseData: Codable, Sendable {
	public let scheduledPurgeAt: Date
	public let status: String
}

public struct AccountDeletionCancelResponseData: Codable, Sendable {
	public let status: String
}

public struct AccountDeletionRequestRecord: Codable, Sendable {
	public let canceledAt: Date?
	public let confirmedAt: Date?
	public let createdAt: Date
	public let id: String
	public let requestedAt: Date
	public let scheduledPurgeAt: Date
	public let status: String
	public let updatedAt: Date
	public let userID: String
}

public struct SyncEnvelope: Codable, Sendable {
	public let aad: JSONObject
	public let ciphertext: String
	public let keyID: String
	public let nonce: String
	public let suite: String
	public let version: Int

	public init(aad: JSONObject, ciphertext: String, keyID: String, nonce: String, suite: String, version: Int) {
		self.aad = aad
		self.ciphertext = ciphertext
		self.keyID = keyID
		self.nonce = nonce
		self.suite = suite
		self.version = version
	}
}

public struct SyncObjectEnvelope: Codable, Sendable {
	public let aad: JSONObject
	public let ciphertext: String
	public let collectionID: String
	public let isDeleted: Bool?
	public let keyID: String
	public let nonce: String
	public let objectID: String
	public let objectKind: SyncObjectKind
	public let objectVersion: NavigatorAPIPositiveIntegerLike
	public let orderKey: String?
	public let parentObjectID: String?
	public let suite: String
	public let version: Int

	public init(
		aad: JSONObject,
		ciphertext: String,
		collectionID: String,
		isDeleted: Bool?,
		keyID: String,
		nonce: String,
		objectID: String,
		objectKind: SyncObjectKind,
		objectVersion: NavigatorAPIPositiveIntegerLike,
		orderKey: String?,
		parentObjectID: String?,
		suite: String,
		version: Int
	) {
		self.aad = aad
		self.ciphertext = ciphertext
		self.collectionID = collectionID
		self.isDeleted = isDeleted
		self.keyID = keyID
		self.nonce = nonce
		self.objectID = objectID
		self.objectKind = objectKind
		self.objectVersion = objectVersion
		self.orderKey = orderKey
		self.parentObjectID = parentObjectID
		self.suite = suite
		self.version = version
	}
}

public struct SyncDeviceRecord: Codable, Sendable {
	public let agreementKeyFingerprint: String
	public let agreementPublicKey: String
	public let approvalState: SyncDeviceApprovalState
	public let createdAt: Date
	public let displayName: String
	public let id: String
	public let lastSeenAt: Date?
	public let revokedAt: Date?
	public let signingKeyFingerprint: String
	public let signingPublicKey: String
	public let updatedAt: Date
	public let userID: String
}

public struct SyncDeviceEnvelopeRecord: Codable, Sendable {
	public let ciphertext: String
	public let createdAt: Date
	public let id: String
	public let keyID: String
	public let kind: SyncDeviceEnvelopeKind
	public let recipientDeviceID: String
	public let recipientKeyFingerprint: String
	public let senderDeviceID: String
	public let suite: String
	public let updatedAt: Date
	public let userID: String
	public let version: Int
}

public struct SyncEventRecord: Codable, Sendable {
	public let aad: JSONObject
	public let ciphertext: String
	public let clientMutationID: String?
	public let collectionID: String
	public let createdAt: Date
	public let cursor: String
	public let entityID: String?
	public let entityKind: SyncEntityKind
	public let id: String
	public let keyID: String
	public let nonce: String
	public let objectID: String
	public let objectVersion: String
	public let suite: String
	public let updatedAt: Date
	public let userID: String
	public let version: Int
}

public struct SyncSnapshotRecord: Codable, Sendable {
	public let aad: JSONObject
	public let ciphertext: String
	public let createdAt: Date
	public let cursor: String
	public let id: String
	public let keyID: String
	public let nonce: String
	public let snapshotKind: SyncSnapshotKind
	public let suite: String
	public let updatedAt: Date
	public let userID: String
	public let version: Int
}

public struct SyncRecoveryEnvelopeRecord: Codable, Sendable {
	public let ciphertext: String
	public let createdAt: Date
	public let id: String
	public let isActive: Bool
	public let kdfParams: JSONObject?
	public let scheme: SyncRecoveryScheme
	public let updatedAt: Date
	public let userID: String
	public let version: Int
}

public struct SyncBootstrapUser: Codable, Sendable {
	public let id: String
}

public struct SyncBootstrapData: Codable, Sendable {
	public let deviceEnvelopes: [SyncDeviceEnvelopeRecord]
	public let devices: [SyncDeviceRecord]
	public let latestCursor: String
	public let recoveryEnvelope: SyncRecoveryEnvelopeRecord?
	public let snapshot: SyncSnapshotRecord?
	public let user: SyncBootstrapUser
}

public struct SyncEventsData: Codable, Sendable {
	public let events: [SyncEventRecord]
	public let latestCursor: String
	public let nextCursor: String
}

public struct SyncEventCommitData: Codable, Sendable {
	public let cursor: String
	public let eventID: String
	public let objectID: String
	public let objectVersion: String
	public let occurredAt: Date
	public let replayed: Bool
}

public struct SyncDeviceListData: Codable, Sendable {
	public let devices: [SyncDeviceRecord]
}

public struct SyncDeviceMutationData: Codable, Sendable {
	public let device: SyncDeviceRecord
}

public struct SyncRecoveryEnvelopeData: Codable, Sendable {
	public let recoveryEnvelope: SyncRecoveryEnvelopeRecord?
}

public struct SyncRecoveryEnvelopeMutationData: Codable, Sendable {
	public let recoveryEnvelope: SyncRecoveryEnvelopeRecord
}
