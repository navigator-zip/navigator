import Foundation
@testable import Networking
import XCTest

final class NavigatorAPIEdgeCaseTests: XCTestCase {
	private let configuration = NavigatorAPITransportConfiguration(
		baseURL: URL(string: "https://navigator.example/api")!,
		apiVersion: "1",
		authorizationBearerToken: nil,
		cookieHeader: nil,
		csrfToken: nil,
		additionalHeaders: [:]
	)

	func testOptionalQueriesAreOmittedWhenNil() throws {
		let invoices = try NavigatorAPI.Billing.invoices(NavigatorAPICursorPageRequest(first: nil, after: nil))
			.urlRequest(configuration: configuration)
		let bootstrap = try NavigatorAPI.Sync.bootstrap(deviceID: nil).urlRequest(configuration: configuration)
		let syncEvents = try NavigatorAPI.Sync.events(SyncEventsRequest(afterCursor: nil, limit: nil))
			.urlRequest(configuration: configuration)
		let auditLogs = try NavigatorAPI.Account.auditLogs(
			AccountAuditLogsRequest(
				action: nil,
				cursor: nil,
				entityID: nil,
				entityType: nil,
				from: nil,
				limit: nil,
				to: nil
			)
		).urlRequest(configuration: configuration)

		XCTAssertNil(invoices.url?.query)
		XCTAssertNil(bootstrap.url?.query)
		XCTAssertNil(syncEvents.url?.query)
		XCTAssertNil(auditLogs.url?.query)
	}

	func testDateQueriesUseFractionalISO8601() throws {
		let request = try NavigatorAPI.Account.auditLogs(
			AccountAuditLogsRequest(
				action: nil,
				cursor: nil,
				entityID: nil,
				entityType: nil,
				from: Date(timeIntervalSince1970: 0),
				limit: 10,
				to: Date(timeIntervalSince1970: 60)
			)
		).urlRequest(configuration: configuration)
		let query = try XCTUnwrap(request.url?.query)

		XCTAssertTrue(query.contains("from=1970-01-01T00:00:00.000Z"))
		XCTAssertTrue(query.contains("to=1970-01-01T00:01:00.000Z"))
	}

	func testBootstrapPreservesPercentEncodedBasePath() throws {
		let nestedConfiguration = try NavigatorAPITransportConfiguration(
			baseURL: XCTUnwrap(URL(string: "https://navigator.example/base%20path/api")),
			apiVersion: "1",
			authorizationBearerToken: nil,
			cookieHeader: nil,
			csrfToken: nil,
			additionalHeaders: [:]
		)
		let request = try NavigatorAPI.Sync.bootstrap(deviceID: "device 1").urlRequest(configuration: nestedConfiguration)

		XCTAssertEqual(
			request.url?.absoluteString,
			"https://navigator.example/base%20path/api/sync/bootstrap?deviceID=device%201"
		)
	}

	func testMessageValidationAndApiErrorResponsesDecodeDirectly() throws {
		let apiErrorJSON = """
		{"ok":false,"error":{"code":"RATE_LIMITED","message":"Slow down","details":{"retryAfter":10}},"meta":{"requestID":"request-1"}}
		"""
		let messageErrorJSON = #"{"message":"Unauthorized"}"#
		let validationErrorJSON = #"{"message":"Validation failed","errors":{"field":["required"]}}"#

		let apiError = try NavigatorAPICoding.decode(NavigatorAPIErrorEnvelope.self, from: Data(apiErrorJSON.utf8))
		let messageError = try NavigatorAPICoding.decode(
			NavigatorAPIMessageErrorResponse.self,
			from: Data(messageErrorJSON.utf8)
		)
		let validationError = try NavigatorAPICoding.decode(
			NavigatorAPIValidationErrorResponse.self,
			from: Data(validationErrorJSON.utf8)
		)

		XCTAssertEqual(apiError.error.code, .rateLimited)
		XCTAssertEqual(messageError.message, "Unauthorized")
		XCTAssertEqual(validationError.message, "Validation failed")
	}

	func testResponseMetaCursorDecodesWhenPresent() throws {
		let json = """
		{"ok":true,"data":{"loggedOut":true},"meta":{"requestID":"request-1","cursor":"10"}}
		"""

		let envelope = try NavigatorAPICoding.decode(NavigatorAPIEnvelope<LogoutResponseData>.self, from: Data(json.utf8))

		XCTAssertEqual(envelope.meta.requestID, "request-1")
		XCTAssertEqual(envelope.meta.cursor, "10")
	}
}
