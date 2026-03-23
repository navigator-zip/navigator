import Foundation
@testable import Networking
@testable import Vendors
import XCTest

final class NetworkingClientTests: XCTestCase {
	func testLiveClientMapsEveryOperation() async throws {
		let now = Date(timeIntervalSince1970: 1_741_430_800)
		let browserClient = try NavigatorAPIClient(
			configuration: NavigatorAPITransportConfiguration(
				baseURL: XCTUnwrap(URL(string: "https://navigator.example/api")),
				apiVersion: "1",
				authorizationBearerToken: "bearer-token",
				cookieHeader: "token=session-token",
				csrfToken: "csrf-token",
				additionalHeaders: [:]
			)
		) { request in
			let method = request.httpMethod ?? ""
			let path = request.url?.path ?? ""
			switch (method, path) {
			case ("GET", "/api/health"), ("GET", "/api/health/live"):
				return try Self.envelope(HealthStatus(status: "ok"), request: request)
			case ("GET", "/api/health/ready"):
				return try Self.envelope(
					HealthReady(checks: HealthReadinessChecks(database: true, websocketHub: true, workerQueue: true), status: "ready"),
					request: request
				)
			case ("POST", "/api/auth/authenticate"), ("POST", "/api/auth/resend"):
				return try Self.envelope(
					AuthChallengeData(expiresAt: now.addingTimeInterval(300), resendCode: "resend-1", resendValidFrom: now),
					request: request
				)
			case ("POST", "/api/auth/verify"):
				return try Self.envelope(
					AuthVerifyData(account: AuthAccount(
						session: SessionRecord(
							createdAt: now,
							id: "session-1",
							name: "MacBook",
							token: "token-1",
							updatedAt: now,
							userID: "user-1"
						),
						user: UserRecord(
							createdAt: now,
							deletedAt: nil,
							email: "user@example.com",
							id: "user-1",
							name: "Navigator",
							phone: nil,
							purgeAfter: nil,
							roles: [.user],
							stripeCustomerID: "cus_1",
							updatedAt: now
						)
					)),
					request: request
				)
			case ("GET", "/api/auth/me"):
				return try Self.envelope(
					UserProfile(
						createdAt: now,
						deletedAt: nil,
						email: "user@example.com",
						id: "user-1",
						name: "Navigator",
						phone: nil,
						roles: [.user]
					),
					request: request
				)
			case ("POST", "/api/auth/logout"):
				return try Self.envelope(LogoutResponseData(loggedOut: true), request: request)
			case ("POST", "/api/auth/logout-all"):
				return try Self.envelope(LogoutAllResponseData(loggedOutAll: true), request: request)
			case ("GET", "/api/billing/subscription"):
				return try Self.envelope(
					PremiumSubscriptionRecord(
						billingCycleAnchor: now,
						cancelAt: nil,
						cancelAtPeriodEnd: false,
						canceledAt: nil,
						createdAt: now,
						currentPeriodEnd: now.addingTimeInterval(3600),
						currentPeriodStart: now,
						defaultPaymentMethod: nil,
						items: [
							PremiumSubscriptionItemRecord(
								createdAt: now,
								currentPeriodEnd: now.addingTimeInterval(3600),
								currentPeriodStart: now,
								metadata: [:],
								priceID: "price-1",
								providerSubscriptionItemID: "item-1",
								quantity: 1,
								subscriptionID: "sub-1",
								updatedAt: now
							),
						],
						livemode: false,
						metadata: [:],
						provider: .stripe,
						providerSubscriptionID: "sub-1",
						quantity: 1,
						startDate: now,
						status: .active,
						updatedAt: now,
						userID: "user-1"
					),
					request: request
				)
			case ("POST", "/api/billing/checkout-session"), ("POST", "/api/billing/portal-session"):
				return try Self.envelope(UrlResponseData(url: "https://billing.example/session"), request: request)
			case ("GET", "/api/billing/invoices"):
				return try Self.envelope(
					OrderConnection(
						edges: [
							OrderEdge(cursor: "cursor-1", node: OrderRecord(
								createdAt: now,
								id: "order-1",
								status: "paid",
								stripeCheckoutSessionID: "cs_1",
								stripeCustomerID: "cus_1",
								updatedAt: now
							)),
						],
						pageInfo: CursorPageInfo(endCursor: "cursor-1", hasNextPage: false),
						totalCount: 1
					),
					request: request
				)
			case ("POST", "/api/billing/webhooks/stripe"):
				return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
			case ("GET", "/api/sync/bootstrap"):
				return try Self.envelope(
					SyncBootstrapData(
						deviceEnvelopes: [
							SyncDeviceEnvelopeRecord(
								ciphertext: "cipher",
								createdAt: now,
								id: "envelope-1",
								keyID: "key-1",
								kind: .accountMasterKey,
								recipientDeviceID: "device-1",
								recipientKeyFingerprint: "fingerprint-1",
								senderDeviceID: "device-2",
								suite: "suite-1",
								updatedAt: now,
								userID: "user-1",
								version: 1
							),
						],
						devices: [
							SyncDeviceRecord(
								agreementKeyFingerprint: "agreement-1",
								agreementPublicKey: "agreement-public",
								approvalState: .approved,
								createdAt: now,
								displayName: "MacBook",
								id: "device-1",
								lastSeenAt: now,
								revokedAt: nil,
								signingKeyFingerprint: "signing-1",
								signingPublicKey: "signing-public",
								updatedAt: now,
								userID: "user-1"
							),
						],
						latestCursor: "9",
						recoveryEnvelope: SyncRecoveryEnvelopeRecord(
							ciphertext: "recovery",
							createdAt: now,
							id: "recovery-1",
							isActive: true,
							kdfParams: nil,
							scheme: .generatedMnemonic,
							updatedAt: now,
							userID: "user-1",
							version: 1
						),
						snapshot: SyncSnapshotRecord(
							aad: ["kind": .string("full")],
							ciphertext: "snapshot",
							createdAt: now,
							cursor: "9",
							id: "snapshot-1",
							keyID: "key-1",
							nonce: "nonce-1",
							snapshotKind: .full,
							suite: "suite-1",
							updatedAt: now,
							userID: "user-1",
							version: 1
						),
						user: SyncBootstrapUser(id: "user-1")
					),
					request: request
				)
			case ("GET", "/api/sync/events"):
				return try Self.envelope(
					SyncEventsData(
						events: [
							SyncEventRecord(
								aad: ["cursor": .string("10")],
								ciphertext: "event-cipher",
								clientMutationID: "mutation-1",
								collectionID: "collection-1",
								createdAt: now,
								cursor: "10",
								entityID: "bookmark-1",
								entityKind: .bookmark,
								id: "event-1",
								keyID: "key-1",
								nonce: "nonce-1",
								objectID: "bookmark-1",
								objectVersion: "2",
								suite: "suite-1",
								updatedAt: now,
								userID: "user-1",
								version: 1
							),
						],
						latestCursor: "10",
						nextCursor: "10"
					),
					request: request
				)
			case ("POST", "/api/sync/events"):
				return try Self.envelope(
					SyncEventCommitData(
						cursor: "10",
						eventID: "event-1",
						objectID: "bookmark-1",
						objectVersion: "2",
						occurredAt: now,
						replayed: false
					),
					request: request
				)
			case ("POST", "/api/sync/snapshots"):
				return try Self.envelope(
					SyncSnapshotRecord(
						aad: ["kind": .string("full")],
						ciphertext: "snapshot",
						createdAt: now,
						cursor: "10",
						id: "snapshot-1",
						keyID: "key-1",
						nonce: "nonce-1",
						snapshotKind: .full,
						suite: "suite-1",
						updatedAt: now,
						userID: "user-1",
						version: 1
					),
					request: request
				)
			case ("GET", "/api/sync/devices"):
				return try Self.envelope(
					SyncDeviceListData(devices: [
						SyncDeviceRecord(
							agreementKeyFingerprint: "agreement-1",
							agreementPublicKey: "agreement-public",
							approvalState: .approved,
							createdAt: now,
							displayName: "MacBook",
							id: "device-1",
							lastSeenAt: now,
							revokedAt: nil,
							signingKeyFingerprint: "signing-1",
							signingPublicKey: "signing-public",
							updatedAt: now,
							userID: "user-1"
						),
					]),
					request: request
				)
			case ("POST", "/api/sync/devices/pending"), ("POST", "/api/sync/devices/device-1/approve"), (
				"POST",
				"/api/sync/devices/device-1/revoke"
			):
				return try Self.envelope(
					SyncDeviceMutationData(device: SyncDeviceRecord(
						agreementKeyFingerprint: "agreement-1",
						agreementPublicKey: "agreement-public",
						approvalState: .approved,
						createdAt: now,
						displayName: "MacBook",
						id: "device-1",
						lastSeenAt: now,
						revokedAt: nil,
						signingKeyFingerprint: "signing-1",
						signingPublicKey: "signing-public",
						updatedAt: now,
						userID: "user-1"
					)),
					request: request
				)
			case ("GET", "/api/sync/recovery-envelope"):
				return try Self.envelope(
					SyncRecoveryEnvelopeData(recoveryEnvelope: SyncRecoveryEnvelopeRecord(
						ciphertext: "recovery",
						createdAt: now,
						id: "recovery-1",
						isActive: true,
						kdfParams: nil,
						scheme: .generatedMnemonic,
						updatedAt: now,
						userID: "user-1",
						version: 1
					)),
					request: request
				)
			case ("PUT", "/api/sync/recovery-envelope"):
				return try Self.envelope(
					SyncRecoveryEnvelopeMutationData(recoveryEnvelope: SyncRecoveryEnvelopeRecord(
						ciphertext: "recovery",
						createdAt: now,
						id: "recovery-1",
						isActive: true,
						kdfParams: nil,
						scheme: .generatedMnemonic,
						updatedAt: now,
						userID: "user-1",
						version: 1
					)),
					request: request
				)
			case ("POST", "/api/account/deletion/request"):
				return try Self.envelope(
					AccountDeletionRequestResponseData(
						expiresAt: now.addingTimeInterval(300),
						resendCode: "delete-resend",
						resendValidFrom: now,
						scheduledPurgeAt: now.addingTimeInterval(2_592_000)
					),
					request: request
				)
			case ("POST", "/api/account/deletion/confirm"):
				return try Self.envelope(
					AccountDeletionConfirmResponseData(scheduledPurgeAt: now.addingTimeInterval(2_592_000), status: "confirmed"),
					request: request
				)
			case ("POST", "/api/account/deletion/cancel"):
				return try Self.envelope(AccountDeletionCancelResponseData(status: "canceled"), request: request)
			case ("GET", "/api/account/deletion/status"):
				return try Self.envelope(
					AccountDeletionRequestRecord(
						canceledAt: nil,
						confirmedAt: now,
						createdAt: now,
						id: "deletion-1",
						requestedAt: now,
						scheduledPurgeAt: now.addingTimeInterval(2_592_000),
						status: "confirmed",
						updatedAt: now,
						userID: "user-1"
					),
					request: request
				)
			case ("GET", "/api/account/audit/logs"):
				return try Self.envelope(
					AuditLogConnection(
						edges: [
							AuditLogEdge(cursor: "cursor-1", node: AuditLogRecord(
								action: "device.approved",
								actorUserID: "user-1",
								createdAt: now,
								entityID: "device-1",
								entityType: "syncDevice",
								id: "audit-1",
								ip: "127.0.0.1",
								metadata: [:],
								requestID: "request-1",
								updatedAt: now,
								userAgent: "NavigatorTests",
								userID: "user-1"
							)),
						],
						pageInfo: CursorPageInfo(endCursor: "cursor-1", hasNextPage: false)
					),
					request: request
				)
			default:
				XCTFail("Unhandled request: \(method) \(path)")
				return (Data(), HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!)
			}
		}

		let client = NetworkingClient.live(navigatorAPIClient: browserClient)
		let health = try await client.health()
		let healthLive = try await client.healthLive()
		let healthReady = try await client.healthReady()
		let authenticate = try await client.authenticate(AuthAuthenticateRequest(channel: .email, value: "user@example.com"))
		let verify = try await client.verify(AuthVerifyRequest(
			channel: .email,
			code: "123456",
			sessionName: "MacBook",
			value: "user@example.com"
		))
		let resend = try await client.resend(AuthResendRequest(
			channel: .email,
			resendCode: "resend-1",
			value: "user@example.com"
		))
		let me = try await client.me()
		let logout = try await client.logout()
		let logoutAll = try await client.logoutAll()
		let subscription = try await client.subscription()
		let checkout = try await client.checkoutSession(
			BillingCheckoutSessionRequest(couponCode: nil, priceID: "price-1"),
			"idem-1"
		)
		let portal = try await client.portalSession("idem-2")
		let invoices = try await client.invoices(NavigatorAPICursorPageRequest(first: 10, after: nil))
		_ = try await client.stripeWebhook(.object(["type": .string("checkout.session.completed")]))
		let bootstrap = try await client.bootstrap(nil)
		let syncEvents = try await client.syncEvents(SyncEventsRequest(afterCursor: nil, limit: 10))
		let appendEvent = try await client.appendSyncEvent(Self.appendRequest())
		let snapshot = try await client.snapshots(Self.snapshotRequest())
		let devices = try await client.syncDevices()
		let pendingDevice = try await client.createPendingSyncDevice(Self.pendingDeviceRequest())
		let approvedDevice = try await client.approveSyncDevice("device-1", Self.approveRequest())
		let revokedDevice = try await client.revokeSyncDevice("device-1", nil)
		let recoveryEnvelope = try await client.recoveryEnvelope()
		let updatedRecoveryEnvelope = try await client.putRecoveryEnvelope(Self.recoveryEnvelopeRequest())
		let deletionRequest = try await client.accountDeletionRequest()
		let deletionConfirm = try await client.accountDeletionConfirm(AccountDeletionConfirmRequest(code: "123456"))
		let deletionCancel = try await client.accountDeletionCancel()
		let deletionStatus = try await client.accountDeletionStatus()
		let auditLogs = try await client.accountAuditLogs(AccountAuditLogsRequest(
			action: nil,
			cursor: nil,
			entityID: nil,
			entityType: nil,
			from: nil,
			limit: nil,
			to: nil
		))

		XCTAssertEqual(health.status, "ok")
		XCTAssertEqual(healthLive.status, "ok")
		XCTAssertEqual(healthReady.status, "ready")
		XCTAssertEqual(authenticate.resendCode, "resend-1")
		XCTAssertEqual(verify.account.user.id, "user-1")
		XCTAssertEqual(resend.resendCode, "resend-1")
		XCTAssertEqual(me.id, "user-1")
		XCTAssertTrue(logout.loggedOut)
		XCTAssertTrue(logoutAll.loggedOutAll)
		XCTAssertEqual(subscription?.providerSubscriptionID, "sub-1")
		XCTAssertEqual(checkout.url, "https://billing.example/session")
		XCTAssertEqual(portal.url, "https://billing.example/session")
		XCTAssertEqual(invoices.edges.first?.node.id, "order-1")
		XCTAssertEqual(bootstrap.latestCursor, "9")
		XCTAssertEqual(syncEvents.latestCursor, "10")
		XCTAssertEqual(appendEvent.eventID, "event-1")
		XCTAssertEqual(snapshot.id, "snapshot-1")
		XCTAssertEqual(devices.devices.first?.id, "device-1")
		XCTAssertEqual(pendingDevice.device.id, "device-1")
		XCTAssertEqual(approvedDevice.device.id, "device-1")
		XCTAssertEqual(revokedDevice.device.id, "device-1")
		XCTAssertEqual(recoveryEnvelope.recoveryEnvelope?.id, "recovery-1")
		XCTAssertEqual(updatedRecoveryEnvelope.recoveryEnvelope.id, "recovery-1")
		XCTAssertEqual(deletionRequest.resendCode, "delete-resend")
		XCTAssertEqual(deletionConfirm.status, "confirmed")
		XCTAssertEqual(deletionCancel.status, "canceled")
		XCTAssertEqual(deletionStatus?.id, "deletion-1")
		XCTAssertEqual(auditLogs.edges.first?.node.id, "audit-1")
	}

	func testDependencyValuesRoundTrip() {
		let liveValue = NetworkingClient.liveValue
		let testValue = NetworkingClient.testValue
		let previewValue = NetworkingClient.previewValue

		var dependencyValues = DependencyValues()
		dependencyValues.networkingClient = liveValue
		_ = dependencyValues.networkingClient
		dependencyValues.networkingClient = testValue
		_ = dependencyValues.networkingClient
		dependencyValues.networkingClient = previewValue
		_ = dependencyValues.networkingClient
	}

	func testLiveClientRevokeDeviceUsesBodyVariantWhenProvided() async throws {
		let navigatorAPIClient = try NavigatorAPIClient(
			configuration: NavigatorAPITransportConfiguration(
				baseURL: XCTUnwrap(URL(string: "https://navigator.example/api")),
				apiVersion: "1",
				authorizationBearerToken: "bearer-token",
				cookieHeader: "token=session-token",
				csrfToken: "csrf-token",
				additionalHeaders: [:]
			)
		) { request in
			XCTAssertEqual(request.url?.path, "/api/sync/devices/device-1/revoke")
			let body = try XCTUnwrap(request.httpBody)
			let decoded = try NavigatorAPICoding.decode(SyncDeviceRevokeRequest.self, from: body)
			XCTAssertEqual(decoded.revokedByDeviceID, "device-2")
			return try Self.envelope(
				SyncDeviceMutationData(device: SyncDeviceRecord(
					agreementKeyFingerprint: "agreement-1",
					agreementPublicKey: "agreement-public",
					approvalState: .revoked,
					createdAt: Date(timeIntervalSince1970: 0),
					displayName: "MacBook",
					id: "device-1",
					lastSeenAt: nil,
					revokedAt: Date(timeIntervalSince1970: 1),
					signingKeyFingerprint: "signing-1",
					signingPublicKey: "signing-public",
					updatedAt: Date(timeIntervalSince1970: 1),
					userID: "user-1"
				)),
				request: request
			)
		}

		let client = NetworkingClient.live(navigatorAPIClient: navigatorAPIClient)
		let response = try await client.revokeSyncDevice("device-1", SyncDeviceRevokeRequest(revokedByDeviceID: "device-2"))

		XCTAssertEqual(response.device.approvalState, .revoked)
	}

	func testDependencyFallbackClientExecutesFetchClosure() async {
		await XCTAssertThrowsErrorAsync(try await NetworkingClient.liveValue.health()) { error in
			guard case .transport(let underlying) = error as? NavigatorAPIError else {
				return XCTFail("Expected fallback transport error")
			}
			XCTAssertEqual(underlying as? NavigatorAPIError, .invalidURL)
		}
	}

	private static func envelope(
		_ data: some Codable & Sendable,
		request: URLRequest
	) throws -> (Data, URLResponse) {
		let payload = NavigatorAPIEnvelope(
			ok: true,
			data: data,
			meta: NavigatorAPIMeta(requestID: "request-1", cursor: nil)
		)
		return try (
			NavigatorAPICoding.encode(payload),
			HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
		)
	}

	private static func appendRequest() -> SyncEventAppendRequest {
		SyncEventAppendRequest(
			clientMutationID: "mutation-1",
			entityID: "bookmark-1",
			entityKind: .bookmark,
			event: SyncEnvelope(
				aad: ["cursor": .string("9")],
				ciphertext: "cipher",
				keyID: "key-1",
				nonce: "nonce-1",
				suite: "suite-1",
				version: 1
			),
			expectedCursor: .string("9"),
			expectedObjectVersion: .integer(2),
			object: SyncObjectEnvelope(
				aad: ["objectID": .string("bookmark-1")],
				ciphertext: "object-cipher",
				collectionID: "collection-1",
				isDeleted: false,
				keyID: "key-1",
				nonce: "nonce-2",
				objectID: "bookmark-1",
				objectKind: .bookmark,
				objectVersion: .string("2"),
				orderKey: "a",
				parentObjectID: nil,
				suite: "suite-1",
				version: 1
			)
		)
	}

	private static func snapshotRequest() -> SyncSnapshotMutationRequest {
		SyncSnapshotMutationRequest(
			aad: ["kind": .string("full")],
			ciphertext: "snapshot",
			cursor: .string("9"),
			keyID: "key-1",
			nonce: "nonce-1",
			snapshotKind: .full,
			suite: "suite-1",
			version: 1
		)
	}

	private static func pendingDeviceRequest() -> SyncDevicePendingRequest {
		SyncDevicePendingRequest(
			agreementKeyFingerprint: "agreement-1",
			agreementPublicKey: "agreement-public",
			challenge: "challenge-1",
			deviceID: "device-1",
			displayName: "MacBook",
			signingKeyFingerprint: "signing-1",
			signingPublicKey: "signing-public"
		)
	}

	private static func approveRequest() -> SyncDeviceApproveRequest {
		SyncDeviceApproveRequest(
			approvalPayload: ["challenge": .string("challenge-1")],
			approverDeviceID: "device-1",
			envelopes: [
				SyncDeviceApproveEnvelopeRequest(
					ciphertext: "cipher",
					keyID: "key-1",
					kind: .accountMasterKey,
					recipientKeyFingerprint: "fingerprint-1",
					suite: "suite-1",
					version: 1
				),
			]
		)
	}

	private static func recoveryEnvelopeRequest() -> SyncRecoveryEnvelopePutRequest {
		SyncRecoveryEnvelopePutRequest(
			ciphertext: "recovery",
			kdfParams: nil,
			scheme: .generatedMnemonic,
			version: 1
		)
	}
}

private func XCTAssertThrowsErrorAsync(
	_ expression: @autoclosure () async throws -> some Any,
	_ verify: (Error) -> Void
) async {
	do {
		_ = try await expression()
		XCTFail("Expected error")
	}
	catch {
		verify(error)
	}
}
