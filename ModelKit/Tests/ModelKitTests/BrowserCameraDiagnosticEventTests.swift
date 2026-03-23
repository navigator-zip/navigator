import ModelKit
import XCTest

final class BrowserCameraDiagnosticEventTests: XCTestCase {
	func testDiagnosticEventRoundTripsThroughCodable() throws {
		let event = BrowserCameraDiagnosticEvent(
			kind: .captureStarted,
			detail: "deviceID=camera-a"
		)

		let decoded = try JSONDecoder().decode(
			BrowserCameraDiagnosticEvent.self,
			from: JSONEncoder().encode(event)
		)

		XCTAssertEqual(decoded, event)
	}

	func testDiagnosticEventKindsRemainStableForDiagnosticsFormatting() {
		XCTAssertEqual(
			BrowserCameraDiagnosticEventKind.allCases,
			[
				.deviceAvailabilityChanged,
				.consumerRegistered,
				.consumerUnregistered,
				.routingChanged,
				.preferredSourceChanged,
				.filterPresetChanged,
				.previewChanged,
				.captureStartRequested,
				.captureStarted,
				.captureStopped,
				.captureFailed,
				.sourceLost,
				.firstFrameProduced,
				.processingDegraded,
				.processingRecovered,
				.publisherStatusChanged,
				.managedTrackStarted,
				.managedTrackStopped,
				.managedTrackEnded,
				.permissionProbeFailed,
				.explicitDeviceBypassed,
				.managedTrackDeviceSwitchRejected,
				.browserProcessFallbackActivated,
			]
		)
	}
}
