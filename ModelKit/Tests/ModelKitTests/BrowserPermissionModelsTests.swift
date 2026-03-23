import Foundation
@testable import ModelKit
import XCTest

final class BrowserPermissionModelsTests: XCTestCase {
	func testPermissionKindSetEnumeratesKindsInDeclarationOrder() {
		let kinds: BrowserPermissionKindSet = [.camera, .microphone, .geolocation]

		XCTAssertEqual(kinds.kinds, [.camera, .microphone, .geolocation])
		XCTAssertEqual(BrowserPermissionKindSet(kind: .camera), .camera)
		XCTAssertEqual(BrowserPermissionKind.camera.bridgeFlag, BrowserPermissionKindSet.camera.rawValue)
	}

	func testAuthorizationStateSubscriptReadsAndWritesByKind() {
		var state = BrowserPermissionOSAuthorizationState()

		state[.camera] = .authorized
		state[.microphone] = .denied
		state[.geolocation] = .restricted

		XCTAssertEqual(state[.camera], .authorized)
		XCTAssertEqual(state[.microphone], .denied)
		XCTAssertEqual(state[.geolocation], .restricted)
		XCTAssertEqual(
			state,
			.init(camera: .authorized, microphone: .denied, geolocation: .restricted)
		)
	}

	func testPermissionSessionRoundTripsThroughCodable() throws {
		let session = BrowserPermissionSession(
			id: 42,
			browserID: 99,
			promptID: 123,
			frameIdentifier: "frame-42",
			source: .permissionPrompt,
			origin: .init(
				requestingOrigin: "https://frame.example",
				topLevelOrigin: "https://top.example"
			),
			requestedKinds: [.camera, .microphone],
			promptKinds: .microphone,
			state: .waitingForUserPrompt,
			siteDecision: .allow,
			persistence: .remember,
			osAuthorizationState: .init(
				camera: .authorized,
				microphone: .notDetermined,
				geolocation: .denied
			),
			createdAt: Date(timeIntervalSince1970: 10),
			updatedAt: Date(timeIntervalSince1970: 11)
		)

		let data = try JSONEncoder().encode(session)
		let decodedSession = try JSONDecoder().decode(BrowserPermissionSession.self, from: data)

		XCTAssertEqual(decodedSession, session)
	}

	func testStoredDecisionStoreUsesDeterministicIdentifiersAndDefaults() {
		let key = BrowserStoredPermissionDecisionKey(
			requestingOrigin: "https://frame.example",
			topLevelOrigin: "https://top.example",
			kind: .camera
		)
		let decision = BrowserStoredPermissionDecision(
			key: key,
			decision: .allow,
			updatedAt: Date(timeIntervalSince1970: 20)
		)
		let store = BrowserStoredPermissionDecisionStore(decisions: [decision])

		XCTAssertEqual(decision.id, "https://frame.example|https://top.example|camera")
		XCTAssertEqual(store.storageVersion, BrowserStoredPermissionDecisionStore.currentVersion)
		XCTAssertEqual(BrowserStoredPermissionDecisionStore.empty.decisions, [])
	}
}
