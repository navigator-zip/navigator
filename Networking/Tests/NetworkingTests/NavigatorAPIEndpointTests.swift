import Foundation
@testable import Networking
import XCTest

final class NavigatorAPIEndpointTests: XCTestCase {
	private let configuration = NavigatorAPITransportConfiguration(
		baseURL: URL(string: "https://navigator.example/api")!,
		apiVersion: "1",
		authorizationBearerToken: "bearer-token",
		cookieHeader: "token=session-token",
		csrfToken: "csrf-token",
		additionalHeaders: ["X-Client": "NavigatorTests"]
	)

	func testHealthEndpointsBuildExpectedRequests() throws {
		try assertRequest(
			NavigatorAPI.Health.status,
			method: "GET",
			url: "https://navigator.example/api/health",
			body: nil,
			includesVersionHeader: false,
			includesCookie: false,
			includesCSRF: false
		)
		try assertRequest(
			NavigatorAPI.Health.live,
			method: "GET",
			url: "https://navigator.example/api/health/live",
			body: nil,
			includesVersionHeader: false,
			includesCookie: false,
			includesCSRF: false
		)
		try assertRequest(
			NavigatorAPI.Health.ready,
			method: "GET",
			url: "https://navigator.example/api/health/ready",
			body: nil,
			includesVersionHeader: false,
			includesCookie: false,
			includesCSRF: false
		)
	}

	func testAuthEndpointsBuildExpectedRequests() throws {
		try assertRequest(
			NavigatorAPI.Auth.authenticate(AuthAuthenticateRequest(channel: .email, value: "user@example.com")),
			method: "POST",
			url: "https://navigator.example/api/auth/authenticate",
			body: #"{"channel":"email","value":"user@example.com"}"#,
			includesVersionHeader: true,
			includesCookie: false,
			includesCSRF: false
		)
		try assertRequest(
			NavigatorAPI.Auth.verify(AuthVerifyRequest(
				channel: .email,
				code: "123456",
				sessionName: "MacBook",
				value: "user@example.com"
			)),
			method: "POST",
			url: "https://navigator.example/api/auth/verify",
			body: #"{"channel":"email","code":"123456","sessionName":"MacBook","value":"user@example.com"}"#,
			includesVersionHeader: true,
			includesCookie: false,
			includesCSRF: false
		)
		try assertRequest(
			NavigatorAPI.Auth.resend(AuthResendRequest(channel: .email, resendCode: "resend-1", value: "user@example.com")),
			method: "POST",
			url: "https://navigator.example/api/auth/resend",
			body: #"{"channel":"email","resendCode":"resend-1","value":"user@example.com"}"#,
			includesVersionHeader: true,
			includesCookie: false,
			includesCSRF: false
		)
		try assertRequest(
			NavigatorAPI.Auth.me,
			method: "GET",
			url: "https://navigator.example/api/auth/me",
			body: nil,
			includesVersionHeader: true,
			includesCookie: true,
			includesCSRF: false
		)
		try assertRequest(
			NavigatorAPI.Auth.logout,
			method: "POST",
			url: "https://navigator.example/api/auth/logout",
			body: nil,
			includesVersionHeader: true,
			includesCookie: true,
			includesCSRF: true
		)
		try assertRequest(
			NavigatorAPI.Auth.logoutAll,
			method: "POST",
			url: "https://navigator.example/api/auth/logout-all",
			body: nil,
			includesVersionHeader: true,
			includesCookie: true,
			includesCSRF: true
		)
	}

	func testBillingEndpointsBuildExpectedRequests() throws {
		try assertRequest(
			NavigatorAPI.Billing.subscription,
			method: "GET",
			url: "https://navigator.example/api/billing/subscription",
			body: nil,
			includesVersionHeader: true,
			includesCookie: true,
			includesCSRF: false
		)
		try assertRequest(
			NavigatorAPI.Billing.checkoutSession(
				BillingCheckoutSessionRequest(couponCode: "PROMO", priceID: "price-1"),
				idempotencyKey: "idem-1"
			),
			method: "POST",
			url: "https://navigator.example/api/billing/checkout-session",
			body: #"{"couponCode":"PROMO","priceID":"price-1"}"#,
			includesVersionHeader: true,
			includesCookie: true,
			includesCSRF: true,
			extraHeaders: ["Idempotency-Key": "idem-1"]
		)
		try assertRequest(
			NavigatorAPI.Billing.portalSession(idempotencyKey: "idem-2"),
			method: "POST",
			url: "https://navigator.example/api/billing/portal-session",
			body: nil,
			includesVersionHeader: true,
			includesCookie: true,
			includesCSRF: true,
			extraHeaders: ["Idempotency-Key": "idem-2"]
		)
		try assertRequest(
			NavigatorAPI.Billing.invoices(NavigatorAPICursorPageRequest(first: 20, after: "cursor-1")),
			method: "GET",
			url: "https://navigator.example/api/billing/invoices?first=20&after=cursor-1",
			body: nil,
			includesVersionHeader: true,
			includesCookie: true,
			includesCSRF: false
		)
		try assertRequest(
			NavigatorAPI.Billing.stripeWebhook(.object(["type": .string("checkout.session.completed")])),
			method: "POST",
			url: "https://navigator.example/api/billing/webhooks/stripe",
			body: #"{"type":"checkout.session.completed"}"#,
			includesVersionHeader: false,
			includesCookie: false,
			includesCSRF: false
		)
	}

	func testSyncEndpointsBuildExpectedRequests() throws {
		try assertRequest(
			NavigatorAPI.Sync.bootstrap(),
			method: "GET",
			url: "https://navigator.example/api/sync/bootstrap",
			body: nil,
			includesVersionHeader: true,
			includesCookie: true,
			includesCSRF: false
		)
		try assertRequest(
			NavigatorAPI.Sync.bootstrap(deviceID: "device-1"),
			method: "GET",
			url: "https://navigator.example/api/sync/bootstrap?deviceID=device-1",
			body: nil,
			includesVersionHeader: true,
			includesCookie: true,
			includesCSRF: false
		)
		try assertRequest(
			NavigatorAPI.Sync.events(SyncEventsRequest(afterCursor: "9", limit: 25)),
			method: "GET",
			url: "https://navigator.example/api/sync/events?afterCursor=9&limit=25",
			body: nil,
			includesVersionHeader: true,
			includesCookie: true,
			includesCSRF: false
		)

		let event = SyncEnvelope(
			aad: ["cursor": .string("9")],
			ciphertext: "cipher",
			keyID: "key-1",
			nonce: "nonce-1",
			suite: "suite-1",
			version: 1
		)
		let object = SyncObjectEnvelope(
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
		try assertRequest(
			NavigatorAPI.Sync.appendEvent(
				SyncEventAppendRequest(
					clientMutationID: "mutation-1",
					entityID: "bookmark-1",
					entityKind: .bookmark,
					event: event,
					expectedCursor: .string("9"),
					expectedObjectVersion: .integer(2),
					object: object
				)
			),
			method: "POST",
			url: "https://navigator.example/api/sync/events",
			bodyContains: "\"entityKind\":\"bookmark\"",
			includesVersionHeader: true,
			includesCookie: true,
			includesCSRF: true
		)
		try assertRequest(
			NavigatorAPI.Sync.snapshots(
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
			),
			method: "POST",
			url: "https://navigator.example/api/sync/snapshots",
			bodyContains: "\"snapshotKind\":\"full\"",
			includesVersionHeader: true,
			includesCookie: true,
			includesCSRF: true
		)
		try assertRequest(
			NavigatorAPI.Sync.devices,
			method: "GET",
			url: "https://navigator.example/api/sync/devices",
			body: nil,
			includesVersionHeader: true,
			includesCookie: true,
			includesCSRF: false
		)
		try assertRequest(
			NavigatorAPI.Sync.pendingDevice(
				SyncDevicePendingRequest(
					agreementKeyFingerprint: "agreement-1",
					agreementPublicKey: "agreement-public",
					challenge: "challenge-1",
					deviceID: "device-1",
					displayName: "MacBook",
					signingKeyFingerprint: "signing-1",
					signingPublicKey: "signing-public"
				)
			),
			method: "POST",
			url: "https://navigator.example/api/sync/devices/pending",
			bodyContains: "\"deviceID\":\"device-1\"",
			includesVersionHeader: true,
			includesCookie: true,
			includesCSRF: true
		)
		try assertRequest(
			NavigatorAPI.Sync.approveDevice(
				deviceID: "device/1",
				request: SyncDeviceApproveRequest(
					approvalPayload: ["challenge": .string("challenge-1")],
					approverDeviceID: "approver-1",
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
			),
			method: "POST",
			url: "https://navigator.example/api/sync/devices/device%2F1/approve",
			bodyContains: "\"approverDeviceID\":\"approver-1\"",
			includesVersionHeader: true,
			includesCookie: true,
			includesCSRF: true
		)
		try assertRequest(
			NavigatorAPI.Sync.revokeDevice(deviceID: "device-1"),
			method: "POST",
			url: "https://navigator.example/api/sync/devices/device-1/revoke",
			body: nil,
			includesVersionHeader: true,
			includesCookie: true,
			includesCSRF: true
		)
		try assertRequest(
			NavigatorAPI.Sync.revokeDevice(
				deviceID: "device-1",
				request: SyncDeviceRevokeRequest(revokedByDeviceID: "device-2")
			),
			method: "POST",
			url: "https://navigator.example/api/sync/devices/device-1/revoke",
			body: #"{"revokedByDeviceID":"device-2"}"#,
			includesVersionHeader: true,
			includesCookie: true,
			includesCSRF: true
		)
		try assertRequest(
			NavigatorAPI.Sync.recoveryEnvelope,
			method: "GET",
			url: "https://navigator.example/api/sync/recovery-envelope",
			body: nil,
			includesVersionHeader: true,
			includesCookie: true,
			includesCSRF: false
		)
		try assertRequest(
			NavigatorAPI.Sync.putRecoveryEnvelope(
				SyncRecoveryEnvelopePutRequest(
					ciphertext: "cipher",
					kdfParams: ["memory": .number(64)],
					scheme: .generatedMnemonic,
					version: 1
				)
			),
			method: "PUT",
			url: "https://navigator.example/api/sync/recovery-envelope",
			bodyContains: "\"scheme\":\"generatedMnemonic\"",
			includesVersionHeader: true,
			includesCookie: true,
			includesCSRF: true
		)
	}

	func testAccountEndpointsBuildExpectedRequests() throws {
		try assertRequest(
			NavigatorAPI.Account.requestDeletion,
			method: "POST",
			url: "https://navigator.example/api/account/deletion/request",
			body: nil,
			includesVersionHeader: true,
			includesCookie: true,
			includesCSRF: true
		)
		try assertRequest(
			NavigatorAPI.Account.confirmDeletion(AccountDeletionConfirmRequest(code: "123456")),
			method: "POST",
			url: "https://navigator.example/api/account/deletion/confirm",
			body: #"{"code":"123456"}"#,
			includesVersionHeader: true,
			includesCookie: true,
			includesCSRF: true
		)
		try assertRequest(
			NavigatorAPI.Account.cancelDeletion,
			method: "POST",
			url: "https://navigator.example/api/account/deletion/cancel",
			body: nil,
			includesVersionHeader: true,
			includesCookie: true,
			includesCSRF: true
		)
		try assertRequest(
			NavigatorAPI.Account.deletionStatus,
			method: "GET",
			url: "https://navigator.example/api/account/deletion/status",
			body: nil,
			includesVersionHeader: true,
			includesCookie: true,
			includesCSRF: false
		)
		try assertRequest(
			NavigatorAPI.Account.auditLogs(
				AccountAuditLogsRequest(
					action: "device.approved",
					cursor: "cursor-1",
					entityID: "device-1",
					entityType: "syncDevice",
					from: Date(timeIntervalSince1970: 0),
					limit: 50,
					to: Date(timeIntervalSince1970: 60)
				)
			),
			method: "GET",
			urlContains: "/account/audit/logs?",
			body: nil,
			includesVersionHeader: true,
			includesCookie: true,
			includesCSRF: false
		)
	}

	func testNavigatorAPIClientDecodesSuccessAndErrors() async throws {
		let successClient = NavigatorAPIClient(configuration: configuration) { request in
			let payload = """
			{"ok":true,"data":{"status":"ok"},"meta":{"requestID":"request-1"}}
			"""
			return (
				Data(payload.utf8),
				HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
			)
		}
		let health = try await successClient.send(NavigatorAPI.Health.status)
		XCTAssertEqual(health.data.status, "ok")

		let invalidResponseClient = NavigatorAPIClient(configuration: configuration) { _ in
			(Data(), URLResponse())
		}
		await XCTAssertThrowsErrorAsync(try await invalidResponseClient.send(NavigatorAPI.Health.status)) { error in
			XCTAssertEqual(error as? NavigatorAPIError, .invalidResponse)
		}

		let apiErrorClient = NavigatorAPIClient(configuration: configuration) { request in
			let payload = """
			{"ok":false,"error":{"code":"AUTH_FORBIDDEN","message":"Blocked","details":{"reason":"csrf"}},"meta":{"requestID":"request-2"}}
			"""
			return (
				Data(payload.utf8),
				HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!
			)
		}
		await XCTAssertThrowsErrorAsync(try await apiErrorClient.send(NavigatorAPI.Auth.me)) { error in
			guard case .apiError(let details) = error as? NavigatorAPIError else {
				return XCTFail("Expected API error")
			}
			XCTAssertEqual(details.code, .forbidden)
		}

		let validationClient = NavigatorAPIClient(configuration: configuration) { request in
			let payload = """
			{"message":"Validation failed","errors":{"field":["required"]}}
			"""
			return (
				Data(payload.utf8),
				HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
			)
		}
		await XCTAssertThrowsErrorAsync(try await validationClient.send(NavigatorAPI.Auth.me)) { error in
			guard case .validationError(let message, let errors) = error as? NavigatorAPIError else {
				return XCTFail("Expected validation error")
			}
			XCTAssertEqual(message, "Validation failed")
			XCTAssertNotNil(errors["field"])
		}

		let messageClient = NavigatorAPIClient(configuration: configuration) { request in
			let payload = """
			{"message":"Unauthorized"}
			"""
			return (
				Data(payload.utf8),
				HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
			)
		}
		await XCTAssertThrowsErrorAsync(try await messageClient.send(NavigatorAPI.Auth.me)) { error in
			guard case .messageError(let message) = error as? NavigatorAPIError else {
				return XCTFail("Expected message error")
			}
			XCTAssertEqual(message, "Unauthorized")
		}

		let invalidPayloadClient = NavigatorAPIClient(configuration: configuration) { request in
			(Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
		}
		await XCTAssertThrowsErrorAsync(try await invalidPayloadClient.send(NavigatorAPI.Health.status)) { error in
			guard case .invalidPayload = error as? NavigatorAPIError else {
				return XCTFail("Expected invalid payload")
			}
		}

		let transportClient = NavigatorAPIClient(configuration: configuration) { _ in
			throw TestError.transport
		}
		await XCTAssertThrowsErrorAsync(try await transportClient.send(NavigatorAPI.Health.status)) { error in
			guard case .transport = error as? NavigatorAPIError else {
				return XCTFail("Expected transport error")
			}
		}

		let httpStatusClient = NavigatorAPIClient(configuration: configuration) { request in
			(Data("oops".utf8), HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!)
		}
		await XCTAssertThrowsErrorAsync(try await httpStatusClient.send(NavigatorAPI.Health.ready)) { error in
			guard case .httpStatus(let code) = error as? NavigatorAPIError else {
				return XCTFail("Expected HTTP status error")
			}
			XCTAssertEqual(code, 503)
		}
	}

	func testURLRequestRejectsInvalidBaseURL() throws {
		let request = NavigatorAPIRequest<NavigatorAPIEnvelope<HealthStatus>>(
			method: .get,
			path: "/health",
			queryItems: [],
			headers: [:],
			body: nil,
			requiresAuthentication: false,
			requiresCSRFToken: false,
			requiresAPIVersionHeader: false,
			decodeSuccessClosure: { _, _ in
				NavigatorAPIEnvelope(
					ok: true,
					data: HealthStatus(status: "ok"),
					meta: NavigatorAPIMeta(requestID: "request-1", cursor: nil)
				)
			}
		)
		let badConfiguration = try NavigatorAPITransportConfiguration(
			baseURL: XCTUnwrap(URL(string: "file:///tmp/example")),
			apiVersion: "1",
			authorizationBearerToken: nil,
			cookieHeader: nil,
			csrfToken: nil,
			additionalHeaders: [:]
		)

		XCTAssertThrowsError(try request.urlRequest(configuration: badConfiguration))
	}

	func testURLRequestHandlesRootBaseURLAndRelativePath() throws {
		let request = NavigatorAPIRequest<NavigatorAPIEnvelope<HealthStatus>>(
			method: .get,
			path: "health",
			queryItems: [],
			headers: [:],
			body: nil,
			requiresAuthentication: false,
			requiresCSRFToken: false,
			requiresAPIVersionHeader: false,
			decodeSuccessClosure: { _, _ in
				NavigatorAPIEnvelope(
					ok: true,
					data: HealthStatus(status: "ok"),
					meta: NavigatorAPIMeta(requestID: "request-1", cursor: nil)
				)
			}
		)
		let rootConfiguration = try NavigatorAPITransportConfiguration(
			baseURL: XCTUnwrap(URL(string: "https://navigator.example/")),
			apiVersion: "1",
			authorizationBearerToken: nil,
			cookieHeader: nil,
			csrfToken: nil,
			additionalHeaders: [:]
		)

		let urlRequest = try request.urlRequest(configuration: rootConfiguration)

		XCTAssertEqual(urlRequest.url?.absoluteString, "https://navigator.example/health")
	}

	private func assertRequest(
		_ request: NavigatorAPIRequest<some Any>,
		method: String,
		url: String? = nil,
		urlContains: String? = nil,
		body: String? = nil,
		bodyContains: String? = nil,
		includesVersionHeader: Bool,
		includesCookie: Bool,
		includesCSRF: Bool,
		extraHeaders: [String: String] = [:]
	) throws {
		let urlRequest = try request.urlRequest(configuration: configuration)

		XCTAssertEqual(urlRequest.httpMethod, method)
		if let url {
			XCTAssertEqual(urlRequest.url?.absoluteString, url)
		}
		if let urlContains {
			XCTAssertTrue(urlRequest.url?.absoluteString.contains(urlContains) == true)
		}
		if let body {
			XCTAssertEqual(try String(data: XCTUnwrap(urlRequest.httpBody), encoding: .utf8), body)
		}
		else if let bodyContains {
			let text = try XCTUnwrap(try String(data: XCTUnwrap(urlRequest.httpBody), encoding: .utf8))
			XCTAssertTrue(text.contains(bodyContains))
		}
		else {
			XCTAssertNil(urlRequest.httpBody)
		}

		XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "API-Version"), includesVersionHeader ? "1" : nil)
		XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Cookie"), includesCookie ? "token=session-token" : nil)
		XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "X-CSRF-Token"), includesCSRF ? "csrf-token" : nil)
		XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "X-Client"), "NavigatorTests")
		for (key, value) in extraHeaders {
			XCTAssertEqual(urlRequest.value(forHTTPHeaderField: key), value)
		}
	}
}

private enum TestError: Error {
	case transport
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

extension NavigatorAPIError: Equatable {
	public static func ==(lhs: NavigatorAPIError, rhs: NavigatorAPIError) -> Bool {
		switch (lhs, rhs) {
		case (.invalidURL, .invalidURL), (.invalidResponse, .invalidResponse):
			return true
		case (.httpStatus(let lhsCode), .httpStatus(let rhsCode)):
			return lhsCode == rhsCode
		default:
			return false
		}
	}
}
