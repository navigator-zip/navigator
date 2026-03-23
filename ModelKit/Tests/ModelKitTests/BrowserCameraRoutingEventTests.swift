import ModelKit
import XCTest

final class BrowserCameraRoutingEventTests: XCTestCase {
	func testRoundTripsThroughJSON() throws {
		let event = BrowserCameraRoutingEvent(
			event: .managedTrackDeviceSwitchRejected,
			activeManagedTrackCount: 2,
			managedTrackID: "track-7",
			managedDeviceID: BrowserCameraManagedOutputIdentity.deviceID,
			requestedDeviceIDs: ["camera-a", "camera-b"],
			preferredFilterPreset: .supergold,
			errorDescription: "permission denied"
		)

		let data = try JSONEncoder().encode(event)
		let decoded = try JSONDecoder().decode(BrowserCameraRoutingEvent.self, from: data)

		XCTAssertEqual(decoded, event)
	}

	func testDecodesWithoutOptionalFields() throws {
		let payload = #"{"activeManagedTrackCount":0,"event":"track-stopped"}"#

		let decoded = try JSONDecoder().decode(
			BrowserCameraRoutingEvent.self,
			from: XCTUnwrap(payload.data(using: .utf8))
		)

		XCTAssertEqual(decoded.event, .trackStopped)
		XCTAssertEqual(decoded.activeManagedTrackCount, 0)
		XCTAssertNil(decoded.managedTrackID)
		XCTAssertNil(decoded.managedDeviceID)
		XCTAssertNil(decoded.requestedDeviceIDs)
		XCTAssertNil(decoded.preferredFilterPreset)
		XCTAssertNil(decoded.errorDescription)
	}

	func testDecodesExplicitDeviceBypassEventWithRequestedDeviceIDs() throws {
		let payload =
			#"{"activeManagedTrackCount":1,"event":"explicit-device-bypassed","requestedDeviceIDs":["camera-a","camera-b"]}"#

		let decoded = try JSONDecoder().decode(
			BrowserCameraRoutingEvent.self,
			from: XCTUnwrap(payload.data(using: .utf8))
		)

		XCTAssertEqual(decoded.event, .explicitDeviceBypassed)
		XCTAssertEqual(decoded.requestedDeviceIDs, ["camera-a", "camera-b"])
	}

	func testRejectsUnknownEventKind() {
		let payload = #"{"activeManagedTrackCount":1,"event":"unknown"}"#

		XCTAssertThrowsError(
			try JSONDecoder().decode(
				BrowserCameraRoutingEvent.self,
				from: XCTUnwrap(payload.data(using: .utf8))
			)
		)
	}

	func testManagedOutputIdentityUsesStableManagedDeviceID() {
		XCTAssertEqual(
			BrowserCameraManagedOutputIdentity.deviceID,
			"navigator-camera-managed-output"
		)
	}
}
