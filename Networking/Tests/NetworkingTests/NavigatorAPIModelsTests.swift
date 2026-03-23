import Foundation
@testable import Networking
import XCTest

final class NavigatorAPIModelsTests: XCTestCase {
	func testJSONValueRoundTripsAllCases() throws {
		let value = JSONValue.object([
			"array": .array([.bool(true), .number(2), .string("three")]),
			"bool": .bool(false),
			"null": .null,
			"number": .number(4),
			"object": .object(["nested": .string("value")]),
			"string": .string("hello"),
		])

		let data = try NavigatorAPICoding.encode(value)
		let decoded = try NavigatorAPICoding.decode(JSONValue.self, from: data)

		XCTAssertEqual(decoded, value)
	}

	func testJSONValueRejectsInvalidPayload() {
		XCTAssertThrowsError(try NavigatorAPICoding.decode(JSONValue.self, from: Data("true false".utf8)))
	}

	func testJSONValueRejectsUnsupportedScalarPayload() {
		XCTAssertThrowsError(try NavigatorAPICoding.decode(JSONValue.self, from: Data("1e999".utf8)))
	}

	func testIntegerLikeRoundTrips() throws {
		let nonNegative = NavigatorAPINonNegativeIntegerLike.integer(4)
		let positive = NavigatorAPIPositiveIntegerLike.string("7")

		let encodedNonNegative = try NavigatorAPICoding.encode(nonNegative)
		let encodedPositive = try NavigatorAPICoding.encode(positive)

		XCTAssertEqual(
			try NavigatorAPICoding.decode(NavigatorAPINonNegativeIntegerLike.self, from: encodedNonNegative),
			nonNegative
		)
		XCTAssertEqual(try NavigatorAPICoding.decode(NavigatorAPIPositiveIntegerLike.self, from: encodedPositive), positive)
	}

	func testIntegerLikeConvenienceInitializersAndDecodeBranches() throws {
		let nonNegative = NavigatorAPINonNegativeIntegerLike(integer: 8)
		let nonNegativeString = NavigatorAPINonNegativeIntegerLike(string: "9")
		let positive = NavigatorAPIPositiveIntegerLike(integer: 2)
		let positiveString = NavigatorAPIPositiveIntegerLike(string: "3")

		XCTAssertEqual(nonNegative, .integer(8))
		XCTAssertEqual(nonNegativeString, .string("9"))
		XCTAssertEqual(positive, .integer(2))
		XCTAssertEqual(positiveString, .string("3"))

		XCTAssertEqual(
			try NavigatorAPICoding.decode(NavigatorAPINonNegativeIntegerLike.self, from: Data("12".utf8)),
			.integer(12)
		)
		XCTAssertEqual(
			try NavigatorAPICoding.decode(NavigatorAPINonNegativeIntegerLike.self, from: Data(#""15""#.utf8)),
			.string("15")
		)
		XCTAssertEqual(
			try NavigatorAPICoding.decode(NavigatorAPIPositiveIntegerLike.self, from: Data("6".utf8)),
			.integer(6)
		)
	}

	func testDateCodingSupportsFractionalAndNonFractionalISO8601() throws {
		let json = """
		{
		  "createdAt": "2026-03-08T12:00:00.123Z",
		  "deletedAt": "2026-03-08T12:05:00Z",
		  "email": "user@example.com",
		  "id": "user-1",
		  "name": "Navigator",
		  "phone": null,
		  "roles": ["admin", "user"]
		}
		"""

		let profile = try NavigatorAPICoding.decode(UserProfile.self, from: Data(json.utf8))

		XCTAssertEqual(profile.id, "user-1")
		XCTAssertEqual(profile.roles, [.admin, .user])
		XCTAssertNotNil(profile.deletedAt)
	}

	func testDateCodingRejectsInvalidISO8601() {
		let json = """
		{
		  "createdAt": "not-a-date",
		  "deletedAt": null,
		  "email": "user@example.com",
		  "id": "user-1",
		  "name": "Navigator",
		  "phone": null,
		  "roles": ["user"]
		}
		"""

		XCTAssertThrowsError(try NavigatorAPICoding.decode(UserProfile.self, from: Data(json.utf8)))
	}

	func testRequestModelsEncodeExpectedFields() throws {
		let event = SyncEnvelope(
			aad: ["userID": .string("user-1")],
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
			objectVersion: .integer(2),
			orderKey: "a",
			parentObjectID: nil,
			suite: "suite-1",
			version: 1
		)
		let appendRequest = SyncEventAppendRequest(
			clientMutationID: "mutation-1",
			entityID: "bookmark-1",
			entityKind: .bookmark,
			event: event,
			expectedCursor: .string("9"),
			expectedObjectVersion: .integer(2),
			object: object
		)
		let approveRequest = SyncDeviceApproveRequest(
			approvalPayload: ["challenge": .string("code-1")],
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
		let recoveryRequest = SyncRecoveryEnvelopePutRequest(
			ciphertext: "recovery-cipher",
			kdfParams: ["memory": .number(64)],
			scheme: .generatedMnemonic,
			version: 1
		)

		let appendData = try NavigatorAPICoding.encode(appendRequest)
		let approveData = try NavigatorAPICoding.encode(approveRequest)
		let recoveryData = try NavigatorAPICoding.encode(recoveryRequest)

		let appendJSON = try XCTUnwrap(String(data: appendData, encoding: .utf8))
		let approveJSON = try XCTUnwrap(String(data: approveData, encoding: .utf8))
		let recoveryJSON = try XCTUnwrap(String(data: recoveryData, encoding: .utf8))

		XCTAssertTrue(appendJSON.contains("\"expectedCursor\":\"9\""))
		XCTAssertTrue(appendJSON.contains("\"entityKind\":\"bookmark\""))
		XCTAssertTrue(approveJSON.contains("\"approverDeviceID\":\"device-1\""))
		XCTAssertTrue(recoveryJSON.contains("\"scheme\":\"generatedMnemonic\""))
	}

	func testRepresentativeResponseModelsDecode() throws {
		let json = """
		{
		  "ok": true,
		  "data": {
		    "deviceEnvelopes": [
		      {
		        "ciphertext": "cipher",
		        "createdAt": "2026-03-08T12:00:00Z",
		        "id": "envelope-1",
		        "keyID": "key-1",
		        "kind": "accountMasterKey",
		        "recipientDeviceID": "device-1",
		        "recipientKeyFingerprint": "fingerprint-1",
		        "senderDeviceID": "device-2",
		        "suite": "suite-1",
		        "updatedAt": "2026-03-08T12:00:01Z",
		        "userID": "user-1",
		        "version": 1
		      }
		    ],
		    "devices": [
		      {
		        "agreementKeyFingerprint": "agreement-1",
		        "agreementPublicKey": "agreement-public",
		        "approvalState": "approved",
		        "createdAt": "2026-03-08T12:00:00Z",
		        "displayName": "MacBook",
		        "id": "device-1",
		        "lastSeenAt": "2026-03-08T12:01:00Z",
		        "revokedAt": null,
		        "signingKeyFingerprint": "signing-1",
		        "signingPublicKey": "signing-public",
		        "updatedAt": "2026-03-08T12:02:00Z",
		        "userID": "user-1"
		      }
		    ],
		    "latestCursor": "9",
		    "recoveryEnvelope": {
		      "ciphertext": "recovery",
		      "createdAt": "2026-03-08T12:00:00Z",
		      "id": "recovery-1",
		      "isActive": true,
		      "kdfParams": null,
		      "scheme": "generatedMnemonic",
		      "updatedAt": "2026-03-08T12:03:00Z",
		      "userID": "user-1",
		      "version": 1
		    },
		    "snapshot": {
		      "aad": {"kind": "full"},
		      "ciphertext": "snapshot",
		      "createdAt": "2026-03-08T12:00:00Z",
		      "cursor": "9",
		      "id": "snapshot-1",
		      "keyID": "key-1",
		      "nonce": "nonce-1",
		      "snapshotKind": "full",
		      "suite": "suite-1",
		      "updatedAt": "2026-03-08T12:04:00Z",
		      "userID": "user-1",
		      "version": 1
		    },
		    "user": {"id": "user-1"}
		  },
		  "meta": {"requestID": "request-1"}
		}
		"""

		let envelope = try NavigatorAPICoding.decode(NavigatorAPIEnvelope<SyncBootstrapData>.self, from: Data(json.utf8))

		XCTAssertTrue(envelope.ok)
		XCTAssertEqual(envelope.data.latestCursor, "9")
		XCTAssertEqual(envelope.data.devices.first?.approvalState, .approved)
		XCTAssertEqual(envelope.data.snapshot?.snapshotKind, .full)
	}

	func testErrorDescriptionsCoverAllCases() {
		let apiError = NavigatorAPIError.apiError(
			NavigatorAPIErrorDetails(code: .forbidden, message: "blocked", details: nil)
		)

		XCTAssertEqual(apiError.errorDescription, "AUTH_FORBIDDEN: blocked")
		XCTAssertEqual(NavigatorAPIError.invalidURL.errorDescription, "Request URL was invalid")
		XCTAssertEqual(NavigatorAPIError.invalidResponse.errorDescription, "Server returned non-HTTP response")
		XCTAssertTrue(
			NavigatorAPIError.invalidPayload(underlying: TestError.example).errorDescription?
				.contains("Response payload was malformed:") == true
		)
		XCTAssertEqual(
			NavigatorAPIError.validationError(message: "Validation failed", errors: [:]).errorDescription,
			"Validation failed"
		)
		XCTAssertEqual(NavigatorAPIError.messageError(message: "Unauthorized").errorDescription, "Unauthorized")
		XCTAssertEqual(
			NavigatorAPIError.httpStatus(statusCode: 418).errorDescription,
			"Server returned unexpected HTTP status: 418"
		)
	}

	func testTransportErrorDescriptionIncludesUnderlyingError() {
		let description = NavigatorAPIError.transport(TestError.example).errorDescription
		XCTAssertTrue(description?.contains("Network transport failed") == true)
	}
}

private enum TestError: Error {
	case example
}

extension JSONValue: Equatable {
	public static func ==(lhs: JSONValue, rhs: JSONValue) -> Bool {
		switch (lhs, rhs) {
		case (.null, .null):
			return true
		case (.bool(let lhsValue), .bool(let rhsValue)):
			return lhsValue == rhsValue
		case (.number(let lhsValue), .number(let rhsValue)):
			return lhsValue == rhsValue
		case (.string(let lhsValue), .string(let rhsValue)):
			return lhsValue == rhsValue
		case (.array(let lhsValue), .array(let rhsValue)):
			return lhsValue == rhsValue
		case (.object(let lhsValue), .object(let rhsValue)):
			return lhsValue == rhsValue
		default:
			return false
		}
	}
}
