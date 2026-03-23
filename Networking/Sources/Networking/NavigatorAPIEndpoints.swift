import Foundation

public enum NavigatorAPIHTTPMethod: String, Sendable {
	case get = "GET"
	case post = "POST"
	case put = "PUT"
	case patch = "PATCH"
	case delete = "DELETE"
}

public struct NavigatorAPICursorPageRequest: Sendable {
	public let first: Int?
	public let after: String?

	public init(first: Int?, after: String?) {
		self.first = first
		self.after = after
	}
}

public struct SyncEventsRequest: Sendable {
	public let afterCursor: String?
	public let limit: Int?

	public init(afterCursor: String?, limit: Int?) {
		self.afterCursor = afterCursor
		self.limit = limit
	}
}

public struct AccountAuditLogsRequest: Sendable {
	public let action: String?
	public let cursor: String?
	public let entityID: String?
	public let entityType: String?
	public let from: Date?
	public let limit: Int?
	public let to: Date?

	public init(
		action: String?,
		cursor: String?,
		entityID: String?,
		entityType: String?,
		from: Date?,
		limit: Int?,
		to: Date?
	) {
		self.action = action
		self.cursor = cursor
		self.entityID = entityID
		self.entityType = entityType
		self.from = from
		self.limit = limit
		self.to = to
	}
}

public struct NavigatorAPITransportConfiguration: Sendable {
	public let baseURL: URL
	public let apiVersion: String
	public let authorizationBearerToken: String?
	public let cookieHeader: String?
	public let csrfToken: String?
	public let additionalHeaders: [String: String]

	public init(
		baseURL: URL,
		apiVersion: String,
		authorizationBearerToken: String?,
		cookieHeader: String?,
		csrfToken: String?,
		additionalHeaders: [String: String]
	) {
		self.baseURL = baseURL
		self.apiVersion = apiVersion
		self.authorizationBearerToken = authorizationBearerToken
		self.cookieHeader = cookieHeader
		self.csrfToken = csrfToken
		self.additionalHeaders = additionalHeaders
	}
}

public struct NavigatorAPIRequest<Response: Sendable>: Sendable {
	public let method: NavigatorAPIHTTPMethod
	public let path: String
	public let queryItems: [URLQueryItem]
	public let headers: [String: String]
	public let body: Data?
	public let requiresAuthentication: Bool
	public let requiresCSRFToken: Bool
	public let requiresAPIVersionHeader: Bool
	private let decodeSuccessClosure: @Sendable (Data, HTTPURLResponse) throws -> Response

	init(
		method: NavigatorAPIHTTPMethod,
		path: String,
		queryItems: [URLQueryItem],
		headers: [String: String],
		body: Data?,
		requiresAuthentication: Bool,
		requiresCSRFToken: Bool,
		requiresAPIVersionHeader: Bool,
		decodeSuccessClosure: @escaping @Sendable (Data, HTTPURLResponse) throws -> Response
	) {
		self.method = method
		self.path = path
		self.queryItems = queryItems
		self.headers = headers
		self.body = body
		self.requiresAuthentication = requiresAuthentication
		self.requiresCSRFToken = requiresCSRFToken
		self.requiresAPIVersionHeader = requiresAPIVersionHeader
		self.decodeSuccessClosure = decodeSuccessClosure
	}

	public func urlRequest(configuration: NavigatorAPITransportConfiguration) throws -> URLRequest {
		guard let scheme = configuration.baseURL.scheme,
		      scheme == "http" || scheme == "https",
		      configuration.baseURL.host != nil
		else {
			throw NavigatorAPIError.invalidURL
		}

		var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)!
		var basePath = components.percentEncodedPath
		if basePath == "/" {
			basePath = ""
		}

		let resolvedPath: String = if path.hasPrefix("/") {
			path
		}
		else {
			"/\(path)"
		}

		components.percentEncodedPath = "\(basePath)\(resolvedPath)"
		if !queryItems.isEmpty {
			components.queryItems = queryItems
		}

		let url = components.url!

		var request = URLRequest(url: url)
		request.httpMethod = method.rawValue
		request.httpBody = body

		var mergedHeaders = configuration.additionalHeaders
		mergedHeaders["Accept"] = "application/json"
		if body != nil {
			mergedHeaders["Content-Type"] = "application/json"
		}
		if requiresAPIVersionHeader {
			mergedHeaders["API-Version"] = configuration.apiVersion
		}
		if requiresAuthentication {
			if let token = configuration.authorizationBearerToken {
				mergedHeaders["Authorization"] = "Bearer \(token)"
			}
			if let cookie = configuration.cookieHeader {
				mergedHeaders["Cookie"] = cookie
			}
		}
		if requiresCSRFToken, let csrfToken = configuration.csrfToken {
			mergedHeaders["X-CSRF-Token"] = csrfToken
		}
		for (key, value) in headers {
			mergedHeaders[key] = value
		}
		for (key, value) in mergedHeaders {
			request.setValue(value, forHTTPHeaderField: key)
		}

		return request
	}

	func decodeSuccess(from data: Data, response: HTTPURLResponse) throws -> Response {
		try decodeSuccessClosure(data, response)
	}
}

public struct NavigatorAPIClient: Sendable {
	public typealias FetchResponse = @Sendable (URLRequest) async throws -> (Data, URLResponse)

	public let configuration: NavigatorAPITransportConfiguration
	private let fetchResponse: FetchResponse

	public init(configuration: NavigatorAPITransportConfiguration, fetchResponse: @escaping FetchResponse) {
		self.configuration = configuration
		self.fetchResponse = fetchResponse
	}

	public func send<Response>(_ request: NavigatorAPIRequest<Response>) async throws -> Response {
		let urlRequest = try request.urlRequest(configuration: configuration)

		let data: Data
		let response: URLResponse
		do {
			(data, response) = try await fetchResponse(urlRequest)
		}
		catch {
			throw NavigatorAPIError.transport(error)
		}

		guard let httpResponse = response as? HTTPURLResponse else {
			throw NavigatorAPIError.invalidResponse
		}

		guard (200..<300).contains(httpResponse.statusCode) else {
			if let errorEnvelope = try? NavigatorAPICoding.decode(NavigatorAPIErrorEnvelope.self, from: data) {
				throw NavigatorAPIError.apiError(errorEnvelope.error)
			}
			if let validationError = try? NavigatorAPICoding.decode(NavigatorAPIValidationErrorResponse.self, from: data) {
				throw NavigatorAPIError.validationError(message: validationError.message, errors: validationError.errors)
			}
			if let messageError = try? NavigatorAPICoding.decode(NavigatorAPIMessageErrorResponse.self, from: data) {
				throw NavigatorAPIError.messageError(message: messageError.message)
			}
			throw NavigatorAPIError.httpStatus(statusCode: httpResponse.statusCode)
		}

		do {
			return try request.decodeSuccess(from: data, response: httpResponse)
		}
		catch {
			throw NavigatorAPIError.invalidPayload(underlying: error)
		}
	}
}

public enum NavigatorAPI {
	public enum Health {
		public static let status = NavigatorAPI.envelopeRequest(
			method: .get,
			path: "/health",
			requiresAuthentication: false,
			requiresCSRFToken: false,
			requiresAPIVersionHeader: false,
			response: HealthStatus.self
		)

		public static let live = NavigatorAPI.envelopeRequest(
			method: .get,
			path: "/health/live",
			requiresAuthentication: false,
			requiresCSRFToken: false,
			requiresAPIVersionHeader: false,
			response: HealthStatus.self
		)

		public static let ready = NavigatorAPI.envelopeRequest(
			method: .get,
			path: "/health/ready",
			requiresAuthentication: false,
			requiresCSRFToken: false,
			requiresAPIVersionHeader: false,
			response: HealthReady.self
		)
	}

	public enum Auth {
		public static func authenticate(_ request: AuthAuthenticateRequest) throws
			-> NavigatorAPIRequest<NavigatorAPIEnvelope<AuthChallengeData>> {
			try NavigatorAPI.envelopeRequest(
				method: .post,
				path: "/auth/authenticate",
				body: request,
				requiresAuthentication: false,
				requiresCSRFToken: false,
				requiresAPIVersionHeader: true,
				response: AuthChallengeData.self
			)
		}

		public static func verify(_ request: AuthVerifyRequest) throws
			-> NavigatorAPIRequest<NavigatorAPIEnvelope<AuthVerifyData>> {
			try NavigatorAPI.envelopeRequest(
				method: .post,
				path: "/auth/verify",
				body: request,
				requiresAuthentication: false,
				requiresCSRFToken: false,
				requiresAPIVersionHeader: true,
				response: AuthVerifyData.self
			)
		}

		public static func resend(_ request: AuthResendRequest) throws
			-> NavigatorAPIRequest<NavigatorAPIEnvelope<AuthChallengeData>> {
			try NavigatorAPI.envelopeRequest(
				method: .post,
				path: "/auth/resend",
				body: request,
				requiresAuthentication: false,
				requiresCSRFToken: false,
				requiresAPIVersionHeader: true,
				response: AuthChallengeData.self
			)
		}

		public static let me = NavigatorAPI.envelopeRequest(
			method: .get,
			path: "/auth/me",
			requiresAuthentication: true,
			requiresCSRFToken: false,
			requiresAPIVersionHeader: true,
			response: UserProfile.self
		)

		public static let logout = NavigatorAPI.envelopeRequest(
			method: .post,
			path: "/auth/logout",
			requiresAuthentication: true,
			requiresCSRFToken: true,
			requiresAPIVersionHeader: true,
			response: LogoutResponseData.self
		)

		public static let logoutAll = NavigatorAPI.envelopeRequest(
			method: .post,
			path: "/auth/logout-all",
			requiresAuthentication: true,
			requiresCSRFToken: true,
			requiresAPIVersionHeader: true,
			response: LogoutAllResponseData.self
		)
	}

	public enum Billing {
		public static let subscription = NavigatorAPI.envelopeRequest(
			method: .get,
			path: "/billing/subscription",
			requiresAuthentication: true,
			requiresCSRFToken: false,
			requiresAPIVersionHeader: true,
			response: PremiumSubscriptionRecord?.self
		)

		public static func checkoutSession(
			_ request: BillingCheckoutSessionRequest,
			idempotencyKey: String
		) throws -> NavigatorAPIRequest<NavigatorAPIEnvelope<UrlResponseData>> {
			try NavigatorAPI.envelopeRequest(
				method: .post,
				path: "/billing/checkout-session",
				headers: ["Idempotency-Key": idempotencyKey],
				body: request,
				requiresAuthentication: true,
				requiresCSRFToken: true,
				requiresAPIVersionHeader: true,
				response: UrlResponseData.self
			)
		}

		public static func portalSession(idempotencyKey: String)
			-> NavigatorAPIRequest<NavigatorAPIEnvelope<UrlResponseData>> {
			NavigatorAPI.envelopeRequest(
				method: .post,
				path: "/billing/portal-session",
				headers: ["Idempotency-Key": idempotencyKey],
				requiresAuthentication: true,
				requiresCSRFToken: true,
				requiresAPIVersionHeader: true,
				response: UrlResponseData.self
			)
		}

		public static func invoices(_ request: NavigatorAPICursorPageRequest)
			-> NavigatorAPIRequest<NavigatorAPIEnvelope<OrderConnection>> {
			NavigatorAPI.envelopeRequest(
				method: .get,
				path: "/billing/invoices",
				queryItems: NavigatorAPI.cursorQueryItems(from: request),
				requiresAuthentication: true,
				requiresCSRFToken: false,
				requiresAPIVersionHeader: true,
				response: OrderConnection.self
			)
		}

		public static func stripeWebhook(_ payload: JSONValue) throws -> NavigatorAPIRequest<EmptyPayload> {
			try NavigatorAPI.emptyRequest(
				method: .post,
				path: "/billing/webhooks/stripe",
				body: payload,
				requiresAuthentication: false,
				requiresCSRFToken: false,
				requiresAPIVersionHeader: false
			)
		}
	}

	public enum Sync {
		public static func bootstrap() -> NavigatorAPIRequest<NavigatorAPIEnvelope<SyncBootstrapData>> {
			bootstrap(deviceID: nil)
		}

		public static func bootstrap(deviceID: String?) -> NavigatorAPIRequest<NavigatorAPIEnvelope<SyncBootstrapData>> {
			NavigatorAPI.envelopeRequest(
				method: .get,
				path: "/sync/bootstrap",
				queryItems: NavigatorAPI.bootstrapQueryItems(deviceID: deviceID),
				requiresAuthentication: true,
				requiresCSRFToken: false,
				requiresAPIVersionHeader: true,
				response: SyncBootstrapData.self
			)
		}

		public static func events(_ request: SyncEventsRequest) -> NavigatorAPIRequest<NavigatorAPIEnvelope<SyncEventsData>> {
			NavigatorAPI.envelopeRequest(
				method: .get,
				path: "/sync/events",
				queryItems: NavigatorAPI.syncEventsQueryItems(from: request),
				requiresAuthentication: true,
				requiresCSRFToken: false,
				requiresAPIVersionHeader: true,
				response: SyncEventsData.self
			)
		}

		public static func appendEvent(_ request: SyncEventAppendRequest) throws
			-> NavigatorAPIRequest<NavigatorAPIEnvelope<SyncEventCommitData>> {
			try NavigatorAPI.envelopeRequest(
				method: .post,
				path: "/sync/events",
				body: request,
				requiresAuthentication: true,
				requiresCSRFToken: true,
				requiresAPIVersionHeader: true,
				response: SyncEventCommitData.self
			)
		}

		public static func snapshots(_ request: SyncSnapshotMutationRequest) throws
			-> NavigatorAPIRequest<NavigatorAPIEnvelope<SyncSnapshotRecord>> {
			try NavigatorAPI.envelopeRequest(
				method: .post,
				path: "/sync/snapshots",
				body: request,
				requiresAuthentication: true,
				requiresCSRFToken: true,
				requiresAPIVersionHeader: true,
				response: SyncSnapshotRecord.self
			)
		}

		public static let devices = NavigatorAPI.envelopeRequest(
			method: .get,
			path: "/sync/devices",
			requiresAuthentication: true,
			requiresCSRFToken: false,
			requiresAPIVersionHeader: true,
			response: SyncDeviceListData.self
		)

		public static func pendingDevice(_ request: SyncDevicePendingRequest) throws
			-> NavigatorAPIRequest<NavigatorAPIEnvelope<SyncDeviceMutationData>> {
			try NavigatorAPI.envelopeRequest(
				method: .post,
				path: "/sync/devices/pending",
				body: request,
				requiresAuthentication: true,
				requiresCSRFToken: true,
				requiresAPIVersionHeader: true,
				response: SyncDeviceMutationData.self
			)
		}

		public static func approveDevice(
			deviceID: String,
			request: SyncDeviceApproveRequest
		) throws -> NavigatorAPIRequest<NavigatorAPIEnvelope<SyncDeviceMutationData>> {
			try NavigatorAPI.envelopeRequest(
				method: .post,
				path: "/sync/devices/\(NavigatorAPI.escapedPathComponent(deviceID))/approve",
				body: request,
				requiresAuthentication: true,
				requiresCSRFToken: true,
				requiresAPIVersionHeader: true,
				response: SyncDeviceMutationData.self
			)
		}

		public static func revokeDevice(deviceID: String)
			-> NavigatorAPIRequest<NavigatorAPIEnvelope<SyncDeviceMutationData>> {
			NavigatorAPI.envelopeRequest(
				method: .post,
				path: "/sync/devices/\(NavigatorAPI.escapedPathComponent(deviceID))/revoke",
				requiresAuthentication: true,
				requiresCSRFToken: true,
				requiresAPIVersionHeader: true,
				response: SyncDeviceMutationData.self
			)
		}

		public static func revokeDevice(
			deviceID: String,
			request: SyncDeviceRevokeRequest
		) throws -> NavigatorAPIRequest<NavigatorAPIEnvelope<SyncDeviceMutationData>> {
			try NavigatorAPI.envelopeRequest(
				method: .post,
				path: "/sync/devices/\(NavigatorAPI.escapedPathComponent(deviceID))/revoke",
				body: request,
				requiresAuthentication: true,
				requiresCSRFToken: true,
				requiresAPIVersionHeader: true,
				response: SyncDeviceMutationData.self
			)
		}

		public static let recoveryEnvelope = NavigatorAPI.envelopeRequest(
			method: .get,
			path: "/sync/recovery-envelope",
			requiresAuthentication: true,
			requiresCSRFToken: false,
			requiresAPIVersionHeader: true,
			response: SyncRecoveryEnvelopeData.self
		)

		public static func putRecoveryEnvelope(_ request: SyncRecoveryEnvelopePutRequest) throws
			-> NavigatorAPIRequest<NavigatorAPIEnvelope<SyncRecoveryEnvelopeMutationData>> {
			try NavigatorAPI.envelopeRequest(
				method: .put,
				path: "/sync/recovery-envelope",
				body: request,
				requiresAuthentication: true,
				requiresCSRFToken: true,
				requiresAPIVersionHeader: true,
				response: SyncRecoveryEnvelopeMutationData.self
			)
		}
	}

	public enum Account {
		public static let requestDeletion = NavigatorAPI.envelopeRequest(
			method: .post,
			path: "/account/deletion/request",
			requiresAuthentication: true,
			requiresCSRFToken: true,
			requiresAPIVersionHeader: true,
			response: AccountDeletionRequestResponseData.self
		)

		public static func confirmDeletion(_ request: AccountDeletionConfirmRequest) throws
			-> NavigatorAPIRequest<NavigatorAPIEnvelope<AccountDeletionConfirmResponseData>> {
			try NavigatorAPI.envelopeRequest(
				method: .post,
				path: "/account/deletion/confirm",
				body: request,
				requiresAuthentication: true,
				requiresCSRFToken: true,
				requiresAPIVersionHeader: true,
				response: AccountDeletionConfirmResponseData.self
			)
		}

		public static let cancelDeletion = NavigatorAPI.envelopeRequest(
			method: .post,
			path: "/account/deletion/cancel",
			requiresAuthentication: true,
			requiresCSRFToken: true,
			requiresAPIVersionHeader: true,
			response: AccountDeletionCancelResponseData.self
		)

		public static let deletionStatus = NavigatorAPI.envelopeRequest(
			method: .get,
			path: "/account/deletion/status",
			requiresAuthentication: true,
			requiresCSRFToken: false,
			requiresAPIVersionHeader: true,
			response: AccountDeletionRequestRecord?.self
		)

		public static func auditLogs(_ request: AccountAuditLogsRequest)
			-> NavigatorAPIRequest<NavigatorAPIEnvelope<AuditLogConnection>> {
			NavigatorAPI.envelopeRequest(
				method: .get,
				path: "/account/audit/logs",
				queryItems: NavigatorAPI.auditLogQueryItems(from: request),
				requiresAuthentication: true,
				requiresCSRFToken: false,
				requiresAPIVersionHeader: true,
				response: AuditLogConnection.self
			)
		}
	}
}

private extension NavigatorAPI {
	static func envelopeRequest<Response: Codable & Sendable>(
		method: NavigatorAPIHTTPMethod,
		path: String,
		queryItems: [URLQueryItem] = [],
		headers: [String: String] = [:],
		requiresAuthentication: Bool,
		requiresCSRFToken: Bool,
		requiresAPIVersionHeader: Bool,
		response: Response.Type
	) -> NavigatorAPIRequest<NavigatorAPIEnvelope<Response>> {
		NavigatorAPIRequest(
			method: method,
			path: path,
			queryItems: queryItems,
			headers: headers,
			body: nil,
			requiresAuthentication: requiresAuthentication,
			requiresCSRFToken: requiresCSRFToken,
			requiresAPIVersionHeader: requiresAPIVersionHeader,
			decodeSuccessClosure: decodeEnvelope(response)
		)
	}

	static func envelopeRequest<Response: Codable & Sendable>(
		method: NavigatorAPIHTTPMethod,
		path: String,
		queryItems: [URLQueryItem] = [],
		headers: [String: String] = [:],
		body: some Codable & Sendable,
		requiresAuthentication: Bool,
		requiresCSRFToken: Bool,
		requiresAPIVersionHeader: Bool,
		response: Response.Type
	) throws -> NavigatorAPIRequest<NavigatorAPIEnvelope<Response>> {
		try NavigatorAPIRequest(
			method: method,
			path: path,
			queryItems: queryItems,
			headers: headers,
			body: NavigatorAPICoding.encode(body),
			requiresAuthentication: requiresAuthentication,
			requiresCSRFToken: requiresCSRFToken,
			requiresAPIVersionHeader: requiresAPIVersionHeader,
			decodeSuccessClosure: decodeEnvelope(response)
		)
	}

	static func emptyRequest(
		method: NavigatorAPIHTTPMethod,
		path: String,
		queryItems: [URLQueryItem] = [],
		headers: [String: String] = [:],
		body: some Codable & Sendable,
		requiresAuthentication: Bool,
		requiresCSRFToken: Bool,
		requiresAPIVersionHeader: Bool
	) throws -> NavigatorAPIRequest<EmptyPayload> {
		try NavigatorAPIRequest(
			method: method,
			path: path,
			queryItems: queryItems,
			headers: headers,
			body: NavigatorAPICoding.encode(body),
			requiresAuthentication: requiresAuthentication,
			requiresCSRFToken: requiresCSRFToken,
			requiresAPIVersionHeader: requiresAPIVersionHeader,
			decodeSuccessClosure: decodeEmptyPayload()
		)
	}

	static func cursorQueryItems(from request: NavigatorAPICursorPageRequest) -> [URLQueryItem] {
		queryItems(
			queryItem(name: "first", value: request.first),
			queryItem(name: "after", value: request.after)
		)
	}

	static func bootstrapQueryItems(deviceID: String?) -> [URLQueryItem] {
		queryItems(queryItem(name: "deviceID", value: deviceID))
	}

	static func syncEventsQueryItems(from request: SyncEventsRequest) -> [URLQueryItem] {
		queryItems(
			queryItem(name: "afterCursor", value: request.afterCursor),
			queryItem(name: "limit", value: request.limit)
		)
	}

	static func auditLogQueryItems(from request: AccountAuditLogsRequest) -> [URLQueryItem] {
		queryItems(
			queryItem(name: "action", value: request.action),
			queryItem(name: "cursor", value: request.cursor),
			queryItem(name: "entityID", value: request.entityID),
			queryItem(name: "entityType", value: request.entityType),
			queryItem(name: "from", value: request.from),
			queryItem(name: "limit", value: request.limit),
			queryItem(name: "to", value: request.to)
		)
	}

	static func escapedPathComponent(_ value: String) -> String {
		value.addingPercentEncoding(withAllowedCharacters: pathAllowedCharacterSet)!
	}

	static func queryItems(_ items: URLQueryItem?...) -> [URLQueryItem] {
		items.compactMap { $0 }
	}

	static func queryItem(name: String, value: String?) -> URLQueryItem? {
		guard let value else {
			return nil
		}
		return URLQueryItem(name: name, value: value)
	}

	static func queryItem(name: String, value: Int?) -> URLQueryItem? {
		guard let value else {
			return nil
		}
		return URLQueryItem(name: name, value: String(value))
	}

	static func queryItem(name: String, value: Date?) -> URLQueryItem? {
		guard let value else {
			return nil
		}
		return URLQueryItem(name: name, value: navigatorAPIQueryDateString(from: value))
	}

	static let pathAllowedCharacterSet: CharacterSet = {
		var characters = CharacterSet.urlPathAllowed
		characters.remove(charactersIn: "/")
		return characters
	}()
}

private func navigatorAPIQueryDateString(from date: Date) -> String {
	let formatter = ISO8601DateFormatter()
	formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
	return formatter.string(from: date)
}

private func decodeEnvelope<Response: Codable & Sendable>(
	_ type: Response.Type
) -> @Sendable (Data, HTTPURLResponse) throws -> NavigatorAPIEnvelope<Response> {
	{ data, _ in
		try NavigatorAPICoding.decode(NavigatorAPIEnvelope<Response>.self, from: data)
	}
}

private func decodeEmptyPayload() -> @Sendable (Data, HTTPURLResponse) throws -> EmptyPayload {
	{ _, _ in
		EmptyPayload()
	}
}
