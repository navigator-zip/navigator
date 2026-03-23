import Foundation
@preconcurrency import Vendors

public typealias NetworkingHTTPMethod = NavigatorAPIHTTPMethod
public typealias NetworkingTransportConfiguration = NavigatorAPITransportConfiguration

public struct NetworkingClient: Sendable {
	public var health: @Sendable () async throws -> HealthStatus
	public var healthLive: @Sendable () async throws -> HealthStatus
	public var healthReady: @Sendable () async throws -> HealthReady

	public var authenticate: @Sendable (_ request: AuthAuthenticateRequest) async throws -> AuthChallengeData
	public var verify: @Sendable (_ request: AuthVerifyRequest) async throws -> AuthVerifyData
	public var resend: @Sendable (_ request: AuthResendRequest) async throws -> AuthChallengeData
	public var me: @Sendable () async throws -> UserProfile
	public var logout: @Sendable () async throws -> LogoutResponseData
	public var logoutAll: @Sendable () async throws -> LogoutAllResponseData

	public var subscription: @Sendable () async throws -> PremiumSubscriptionRecord?
	public var checkoutSession: @Sendable (_ request: BillingCheckoutSessionRequest, _ idempotencyKey: String) async throws
		-> UrlResponseData
	public var portalSession: @Sendable (_ idempotencyKey: String) async throws -> UrlResponseData
	public var invoices: @Sendable (_ request: NavigatorAPICursorPageRequest) async throws -> OrderConnection
	public var stripeWebhook: @Sendable (_ payload: JSONValue) async throws -> EmptyPayload

	public var bootstrap: @Sendable (_ deviceID: String?) async throws -> SyncBootstrapData
	public var syncEvents: @Sendable (_ request: SyncEventsRequest) async throws -> SyncEventsData
	public var appendSyncEvent: @Sendable (_ request: SyncEventAppendRequest) async throws -> SyncEventCommitData
	public var snapshots: @Sendable (_ request: SyncSnapshotMutationRequest) async throws -> SyncSnapshotRecord
	public var syncDevices: @Sendable () async throws -> SyncDeviceListData
	public var createPendingSyncDevice: @Sendable (_ request: SyncDevicePendingRequest) async throws
		-> SyncDeviceMutationData
	public var approveSyncDevice: @Sendable (_ deviceID: String, _ request: SyncDeviceApproveRequest) async throws
		-> SyncDeviceMutationData
	public var revokeSyncDevice: @Sendable (_ deviceID: String, _ request: SyncDeviceRevokeRequest?) async throws
		-> SyncDeviceMutationData
	public var recoveryEnvelope: @Sendable () async throws -> SyncRecoveryEnvelopeData
	public var putRecoveryEnvelope: @Sendable (_ request: SyncRecoveryEnvelopePutRequest) async throws
		-> SyncRecoveryEnvelopeMutationData

	public var accountDeletionRequest: @Sendable () async throws -> AccountDeletionRequestResponseData
	public var accountDeletionConfirm: @Sendable (_ request: AccountDeletionConfirmRequest) async throws
		-> AccountDeletionConfirmResponseData
	public var accountDeletionCancel: @Sendable () async throws -> AccountDeletionCancelResponseData
	public var accountDeletionStatus: @Sendable () async throws -> AccountDeletionRequestRecord?
	public var accountAuditLogs: @Sendable (_ request: AccountAuditLogsRequest) async throws -> AuditLogConnection

	public init(
		health: @Sendable @escaping () async throws -> HealthStatus,
		healthLive: @Sendable @escaping () async throws -> HealthStatus,
		healthReady: @Sendable @escaping () async throws -> HealthReady,
		authenticate: @Sendable @escaping (_ request: AuthAuthenticateRequest) async throws -> AuthChallengeData,
		verify: @Sendable @escaping (_ request: AuthVerifyRequest) async throws -> AuthVerifyData,
		resend: @Sendable @escaping (_ request: AuthResendRequest) async throws -> AuthChallengeData,
		me: @Sendable @escaping () async throws -> UserProfile,
		logout: @Sendable @escaping () async throws -> LogoutResponseData,
		logoutAll: @Sendable @escaping () async throws -> LogoutAllResponseData,
		subscription: @Sendable @escaping () async throws -> PremiumSubscriptionRecord?,
		checkoutSession: @Sendable @escaping (
			_ request: BillingCheckoutSessionRequest,
			_ idempotencyKey: String
		) async throws -> UrlResponseData,
		portalSession: @Sendable @escaping (_ idempotencyKey: String) async throws -> UrlResponseData,
		invoices: @Sendable @escaping (_ request: NavigatorAPICursorPageRequest) async throws -> OrderConnection,
		stripeWebhook: @Sendable @escaping (_ payload: JSONValue) async throws -> EmptyPayload,
		bootstrap: @Sendable @escaping (_ deviceID: String?) async throws -> SyncBootstrapData,
		syncEvents: @Sendable @escaping (_ request: SyncEventsRequest) async throws -> SyncEventsData,
		appendSyncEvent: @Sendable @escaping (_ request: SyncEventAppendRequest) async throws -> SyncEventCommitData,
		snapshots: @Sendable @escaping (_ request: SyncSnapshotMutationRequest) async throws -> SyncSnapshotRecord,
		syncDevices: @Sendable @escaping () async throws -> SyncDeviceListData,
		createPendingSyncDevice: @Sendable @escaping (_ request: SyncDevicePendingRequest) async throws
			-> SyncDeviceMutationData,
		approveSyncDevice: @Sendable @escaping (
			_ deviceID: String,
			_ request: SyncDeviceApproveRequest
		) async throws -> SyncDeviceMutationData,
		revokeSyncDevice: @Sendable @escaping (
			_ deviceID: String,
			_ request: SyncDeviceRevokeRequest?
		) async throws -> SyncDeviceMutationData,
		recoveryEnvelope: @Sendable @escaping () async throws -> SyncRecoveryEnvelopeData,
		putRecoveryEnvelope: @Sendable @escaping (
			_ request: SyncRecoveryEnvelopePutRequest
		) async throws -> SyncRecoveryEnvelopeMutationData,
		accountDeletionRequest: @Sendable @escaping () async throws -> AccountDeletionRequestResponseData,
		accountDeletionConfirm: @Sendable @escaping (
			_ request: AccountDeletionConfirmRequest
		) async throws -> AccountDeletionConfirmResponseData,
		accountDeletionCancel: @Sendable @escaping () async throws -> AccountDeletionCancelResponseData,
		accountDeletionStatus: @Sendable @escaping () async throws -> AccountDeletionRequestRecord?,
		accountAuditLogs: @Sendable @escaping (_ request: AccountAuditLogsRequest) async throws -> AuditLogConnection
	) {
		self.health = health
		self.healthLive = healthLive
		self.healthReady = healthReady
		self.authenticate = authenticate
		self.verify = verify
		self.resend = resend
		self.me = me
		self.logout = logout
		self.logoutAll = logoutAll
		self.subscription = subscription
		self.checkoutSession = checkoutSession
		self.portalSession = portalSession
		self.invoices = invoices
		self.stripeWebhook = stripeWebhook
		self.bootstrap = bootstrap
		self.syncEvents = syncEvents
		self.appendSyncEvent = appendSyncEvent
		self.snapshots = snapshots
		self.syncDevices = syncDevices
		self.createPendingSyncDevice = createPendingSyncDevice
		self.approveSyncDevice = approveSyncDevice
		self.revokeSyncDevice = revokeSyncDevice
		self.recoveryEnvelope = recoveryEnvelope
		self.putRecoveryEnvelope = putRecoveryEnvelope
		self.accountDeletionRequest = accountDeletionRequest
		self.accountDeletionConfirm = accountDeletionConfirm
		self.accountDeletionCancel = accountDeletionCancel
		self.accountDeletionStatus = accountDeletionStatus
		self.accountAuditLogs = accountAuditLogs
	}
}

public extension NetworkingClient {
	static func live(navigatorAPIClient: NavigatorAPIClient) -> Self {
		Self(
			health: { try await navigatorAPIClient.send(NavigatorAPI.Health.status).data },
			healthLive: { try await navigatorAPIClient.send(NavigatorAPI.Health.live).data },
			healthReady: { try await navigatorAPIClient.send(NavigatorAPI.Health.ready).data },
			authenticate: { try await navigatorAPIClient.send(NavigatorAPI.Auth.authenticate($0)).data },
			verify: { try await navigatorAPIClient.send(NavigatorAPI.Auth.verify($0)).data },
			resend: { try await navigatorAPIClient.send(NavigatorAPI.Auth.resend($0)).data },
			me: { try await navigatorAPIClient.send(NavigatorAPI.Auth.me).data },
			logout: { try await navigatorAPIClient.send(NavigatorAPI.Auth.logout).data },
			logoutAll: { try await navigatorAPIClient.send(NavigatorAPI.Auth.logoutAll).data },
			subscription: { try await navigatorAPIClient.send(NavigatorAPI.Billing.subscription).data },
			checkoutSession: {
				try await navigatorAPIClient.send(NavigatorAPI.Billing.checkoutSession($0, idempotencyKey: $1)).data
			},
			portalSession: { try await navigatorAPIClient.send(NavigatorAPI.Billing.portalSession(idempotencyKey: $0)).data },
			invoices: { try await navigatorAPIClient.send(NavigatorAPI.Billing.invoices($0)).data },
			stripeWebhook: { try await navigatorAPIClient.send(NavigatorAPI.Billing.stripeWebhook($0)) },
			bootstrap: { try await navigatorAPIClient.send(NavigatorAPI.Sync.bootstrap(deviceID: $0)).data },
			syncEvents: { try await navigatorAPIClient.send(NavigatorAPI.Sync.events($0)).data },
			appendSyncEvent: { try await navigatorAPIClient.send(NavigatorAPI.Sync.appendEvent($0)).data },
			snapshots: { try await navigatorAPIClient.send(NavigatorAPI.Sync.snapshots($0)).data },
			syncDevices: { try await navigatorAPIClient.send(NavigatorAPI.Sync.devices).data },
			createPendingSyncDevice: { try await navigatorAPIClient.send(NavigatorAPI.Sync.pendingDevice($0)).data },
			approveSyncDevice: {
				try await navigatorAPIClient.send(NavigatorAPI.Sync.approveDevice(deviceID: $0, request: $1)).data
			},
			revokeSyncDevice: {
				if let request = $1 {
					return try await navigatorAPIClient.send(
						NavigatorAPI.Sync.revokeDevice(deviceID: $0, request: request)
					).data
				}
				return try await navigatorAPIClient.send(NavigatorAPI.Sync.revokeDevice(deviceID: $0)).data
			},
			recoveryEnvelope: { try await navigatorAPIClient.send(NavigatorAPI.Sync.recoveryEnvelope).data },
			putRecoveryEnvelope: { try await navigatorAPIClient.send(NavigatorAPI.Sync.putRecoveryEnvelope($0)).data },
			accountDeletionRequest: { try await navigatorAPIClient.send(NavigatorAPI.Account.requestDeletion).data },
			accountDeletionConfirm: { try await navigatorAPIClient.send(NavigatorAPI.Account.confirmDeletion($0)).data },
			accountDeletionCancel: { try await navigatorAPIClient.send(NavigatorAPI.Account.cancelDeletion).data },
			accountDeletionStatus: { try await navigatorAPIClient.send(NavigatorAPI.Account.deletionStatus).data },
			accountAuditLogs: { try await navigatorAPIClient.send(NavigatorAPI.Account.auditLogs($0)).data }
		)
	}
}

extension NetworkingClient: DependencyKey {
	private static var dependencyFallbackNavigatorAPIClient: NavigatorAPIClient {
		NavigatorAPIClient(
			configuration: NavigatorAPITransportConfiguration(
				baseURL: URL(string: "https://api.navigator.zip")!,
				apiVersion: "1",
				authorizationBearerToken: nil,
				cookieHeader: nil,
				csrfToken: nil,
				additionalHeaders: [:]
			),
			fetchResponse: { _ in
				throw NavigatorAPIError.invalidURL
			}
		)
	}

	public static var liveValue: NetworkingClient {
		.live(navigatorAPIClient: dependencyFallbackNavigatorAPIClient)
	}

	public static var testValue: NetworkingClient {
		.live(navigatorAPIClient: dependencyFallbackNavigatorAPIClient)
	}

	public static var previewValue: NetworkingClient {
		.live(navigatorAPIClient: dependencyFallbackNavigatorAPIClient)
	}
}

public extension DependencyValues {
	var networkingClient: NetworkingClient {
		get { self[NetworkingClient.self] }
		set { self[NetworkingClient.self] = newValue }
	}
}
