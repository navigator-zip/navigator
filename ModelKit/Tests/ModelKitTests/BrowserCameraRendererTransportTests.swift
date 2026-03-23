import ModelKit
import XCTest

final class BrowserCameraRendererTransportTests: XCTestCase {
	func testRendererTransportChannelRawValuesMatchBridgeContract() {
		XCTAssertEqual(
			BrowserCameraRendererTransportChannel.routingConfiguration.rawValue,
			"__cameraRoutingConfigUpdate__"
		)
		XCTAssertEqual(
			BrowserCameraRendererTransportChannel.frameDelivery.rawValue,
			"__cameraFrameDelivery__"
		)
		XCTAssertEqual(
			BrowserCameraRendererTransportChannel.frameClear.rawValue,
			"__cameraFrameClear__"
		)
	}

	func testRendererRoutingConfigurationPayloadTracksManagedRoutingIdentity() {
		let payload = BrowserCameraRendererRoutingConfigurationPayload(
			snapshot: makeSnapshot(
				healthState: .healthy,
				outputMode: .processedNavigatorFeed
			),
			managedDeviceLabel: "Navigator Camera Output"
		)

		XCTAssertTrue(payload.routingEnabled)
		XCTAssertTrue(payload.preferNavigatorCameraWhenPossible)
		XCTAssertTrue(payload.genericVideoUsesManagedOutput)
		XCTAssertFalse(payload.failClosedOnManagedVideoRequest)
		XCTAssertEqual(payload.managedRoutingAvailability, "available")
		XCTAssertEqual(payload.preferredSourceID, "camera-main")
		XCTAssertEqual(payload.preferredFilterPreset, "folia")
		XCTAssertEqual(payload.outputMode, "processedNavigatorFeed")
		XCTAssertEqual(payload.healthState, "healthy")
		XCTAssertEqual(payload.publisherState, "notRequired")
		XCTAssertTrue(payload.exposesManagedDeviceIdentity)
		XCTAssertEqual(payload.managedDeviceID, BrowserCameraManagedOutputIdentity.deviceID)
		XCTAssertEqual(payload.managedDeviceLabel, "Navigator Camera Output")
	}

	func testRendererRoutingConfigurationPayloadSuppressesManagedIdentityWhenUnavailable() {
		let payload = BrowserCameraRendererRoutingConfigurationPayload(
			snapshot: makeSnapshot(
				healthState: .publisherUnavailable,
				outputMode: .systemVirtualCameraPublication
			),
			managedDeviceLabel: "Navigator Camera Output"
		)

		XCTAssertFalse(payload.genericVideoUsesManagedOutput)
		XCTAssertTrue(payload.failClosedOnManagedVideoRequest)
		XCTAssertEqual(payload.managedRoutingAvailability, "publisherUnavailable")
		XCTAssertFalse(payload.exposesManagedDeviceIdentity)
		XCTAssertNil(payload.managedDeviceID)
		XCTAssertNil(payload.managedDeviceLabel)
		XCTAssertEqual(payload.publisherState, "unavailable")
		XCTAssertEqual(payload.publisherTransportMode, "sharedMemory")
	}

	func testRendererRoutingConfigurationTransportMessageUsesSortedJSON() {
		let payload = BrowserCameraRendererRoutingConfigurationPayload(
			snapshot: makeSnapshot(),
			managedDeviceLabel: "Navigator Camera Output"
		)

		let message = payload.transportMessage()

		XCTAssertEqual(message.channel, .routingConfiguration)
		XCTAssertTrue(message.jsonPayload.contains("\"routingEnabled\":true"))
		XCTAssertTrue(message.jsonPayload.contains("\"preferredFilterPreset\":\"folia\""))
		XCTAssertTrue(message.jsonPayload.contains("\"managedDeviceLabel\":\"Navigator Camera Output\""))
	}

	func testManagedFramePayloadBuildsRendererTransportMessage() {
		let payload = BrowserCameraManagedFramePayload(
			sequence: 12,
			width: 1280,
			height: 720,
			imageDataURL: "data:image/jpeg;base64,YmFy"
		)

		let message = payload.rendererTransportMessage()

		XCTAssertEqual(message.channel, .frameDelivery)
		XCTAssertTrue(message.jsonPayload.contains("\"sequence\":12"))
		XCTAssertTrue(message.jsonPayload.contains("\"width\":1280"))
		XCTAssertTrue(message.jsonPayload.contains("\"height\":720"))
		XCTAssertTrue(message.jsonPayload.contains("YmFy"))
	}

	func testFrameClearPayloadBuildsEmptyJSONObjectTransportMessage() {
		let message = BrowserCameraRendererFrameClearPayload().transportMessage()

		XCTAssertEqual(message.channel, .frameClear)
		XCTAssertEqual(message.jsonPayload, "{}")
	}

	private func makeSnapshot(
		healthState: BrowserCameraHealthState = .healthy,
		outputMode: BrowserCameraOutputMode = .processedNavigatorFeed
	) -> BrowserCameraSessionSnapshot {
		BrowserCameraSessionSnapshot(
			lifecycleState: healthState == .healthy ? .running : .failed,
			healthState: healthState,
			outputMode: outputMode,
			routingSettings: BrowserCameraRoutingSettings(
				routingEnabled: true,
				preferNavigatorCameraWhenPossible: true,
				preferredSourceID: "camera-main",
				preferredFilterPreset: .folia,
				previewEnabled: false
			),
			availableSources: [
				BrowserCameraSource(id: "camera-main", name: "FaceTime HD Camera", isDefault: true),
			],
			activeConsumersByID: [:],
			performanceMetrics: .empty,
			lastErrorDescription: healthState == .healthy ? nil : "publisher missing",
			publisherStatus: outputMode == .systemVirtualCameraPublication
				? BrowserCameraVirtualPublisherStatus(
					state: healthState == .healthy ? .ready : .unavailable,
					configuration: BrowserCameraVirtualPublisherConfiguration(
						sourceDeviceID: "camera-main",
						filterPreset: .folia,
						frameWidth: 1280,
						frameHeight: 720,
						nominalFramesPerSecond: 30,
						pixelFormat: .bgra8888,
						backpressurePolicy: .dropOldest,
						transportMode: .sharedMemory
					),
					lastPublishedFrame: nil,
					lastErrorDescription: healthState == .healthy ? nil : "publisher missing"
				)
				: .notRequired
		)
	}
}
