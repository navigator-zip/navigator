@testable import BrowserView
import ModelKit
import XCTest

final class BrowserCameraManagedDemandTrackerTests: XCTestCase {
	func testResolveRegistersConsumerWhenManagedTracksTransitionFromIdleToActive() {
		let resolution = BrowserCameraManagedDemandTracker.resolve(
			currentActiveManagedTrackCount: nil,
			event: BrowserCameraRoutingEvent(
				event: .trackStarted,
				activeManagedTrackCount: 1
			)
		)

		XCTAssertEqual(
			resolution,
			BrowserCameraManagedDemandResolution(
				nextActiveManagedTrackCount: 1,
				shouldRegisterConsumer: true,
				shouldUnregisterConsumer: false
			)
		)
	}

	func testResolveDoesNotReRegisterConsumerWhileTracksRemainActive() {
		let resolution = BrowserCameraManagedDemandTracker.resolve(
			currentActiveManagedTrackCount: 1,
			event: BrowserCameraRoutingEvent(
				event: .trackStarted,
				activeManagedTrackCount: 2
			)
		)

		XCTAssertEqual(
			resolution,
			BrowserCameraManagedDemandResolution(
				nextActiveManagedTrackCount: 2,
				shouldRegisterConsumer: false,
				shouldUnregisterConsumer: false
			)
		)
	}

	func testResolveUnregistersConsumerWhenManagedTracksReachZero() {
		let resolution = BrowserCameraManagedDemandTracker.resolve(
			currentActiveManagedTrackCount: 2,
			event: BrowserCameraRoutingEvent(
				event: .trackStopped,
				activeManagedTrackCount: 0
			)
		)

		XCTAssertEqual(
			resolution,
			BrowserCameraManagedDemandResolution(
				nextActiveManagedTrackCount: 0,
				shouldRegisterConsumer: false,
				shouldUnregisterConsumer: true
			)
		)
	}

	func testResolveClampsNegativeTrackCountsToZero() {
		let resolution = BrowserCameraManagedDemandTracker.resolve(
			currentActiveManagedTrackCount: 0,
			event: BrowserCameraRoutingEvent(
				event: .trackEnded,
				activeManagedTrackCount: -3
			)
		)

		XCTAssertEqual(
			resolution,
			BrowserCameraManagedDemandResolution(
				nextActiveManagedTrackCount: 0,
				shouldRegisterConsumer: false,
				shouldUnregisterConsumer: false
			)
		)
	}

	func testResolveIgnoresPermissionProbeFailuresForDemandTracking() {
		let resolution = BrowserCameraManagedDemandTracker.resolve(
			currentActiveManagedTrackCount: 2,
			event: BrowserCameraRoutingEvent(
				event: .permissionProbeFailed,
				activeManagedTrackCount: 0,
				errorDescription: "Permission denied"
			)
		)

		XCTAssertEqual(
			resolution,
			BrowserCameraManagedDemandResolution(
				nextActiveManagedTrackCount: 2,
				shouldRegisterConsumer: false,
				shouldUnregisterConsumer: false
			)
		)
	}

	func testResolveIgnoresExplicitDeviceBypassForDemandTracking() {
		let resolution = BrowserCameraManagedDemandTracker.resolve(
			currentActiveManagedTrackCount: 2,
			event: BrowserCameraRoutingEvent(
				event: .explicitDeviceBypassed,
				activeManagedTrackCount: 0,
				requestedDeviceIDs: ["camera-a"]
			)
		)

		XCTAssertEqual(
			resolution,
			BrowserCameraManagedDemandResolution(
				nextActiveManagedTrackCount: 2,
				shouldRegisterConsumer: false,
				shouldUnregisterConsumer: false
			)
		)
	}

	func testResolveIgnoresManagedTrackDeviceSwitchRejectionForDemandTracking() {
		let resolution = BrowserCameraManagedDemandTracker.resolve(
			currentActiveManagedTrackCount: 1,
			event: BrowserCameraRoutingEvent(
				event: .managedTrackDeviceSwitchRejected,
				activeManagedTrackCount: 1,
				managedTrackID: "track-1",
				requestedDeviceIDs: ["camera-b"],
				errorDescription: "NotReadableError"
			)
		)

		XCTAssertEqual(
			resolution,
			BrowserCameraManagedDemandResolution(
				nextActiveManagedTrackCount: 1,
				shouldRegisterConsumer: false,
				shouldUnregisterConsumer: false
			)
		)
	}
}
