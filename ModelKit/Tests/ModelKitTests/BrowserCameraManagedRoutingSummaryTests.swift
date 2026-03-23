import ModelKit
import XCTest

final class BrowserCameraManagedRoutingSummaryTests: XCTestCase {
	func testSnapshotManagedRoutingSummaryReflectsNavigatorPreferenceDisabled() {
		let summary = makeSnapshot(
			routingSettings: BrowserCameraRoutingSettings(
				routingEnabled: true,
				preferNavigatorCameraWhenPossible: false,
				preferredSourceID: "camera-main",
				preferredFilterPreset: .none,
				previewEnabled: false
			)
		).managedRoutingSummary

		XCTAssertEqual(summary.availability, .navigatorPreferenceDisabled)
		XCTAssertFalse(summary.genericVideoUsesManagedOutput)
		XCTAssertFalse(summary.failClosedOnManagedVideoRequest)
		XCTAssertFalse(summary.exposesManagedDeviceIdentity)
		XCTAssertNil(summary.managedDeviceID)
	}

	func testSnapshotManagedRoutingSummaryReflectsNoAvailableSource() {
		let summary = makeSnapshot(
			outputMode: .unavailable,
			routingSettings: BrowserCameraRoutingSettings(
				routingEnabled: false,
				preferNavigatorCameraWhenPossible: true,
				preferredSourceID: nil,
				preferredFilterPreset: .none,
				previewEnabled: false
			),
			availableSources: []
		).managedRoutingSummary

		XCTAssertEqual(summary.availability, .noAvailableSource)
		XCTAssertFalse(summary.genericVideoUsesManagedOutput)
		XCTAssertFalse(summary.failClosedOnManagedVideoRequest)
		XCTAssertFalse(summary.exposesManagedDeviceIdentity)
	}

	func testSnapshotManagedRoutingSummaryReflectsRoutingDisabled() {
		let summary = makeSnapshot(
			routingSettings: BrowserCameraRoutingSettings(
				routingEnabled: false,
				preferNavigatorCameraWhenPossible: true,
				preferredSourceID: "camera-main",
				preferredFilterPreset: .none,
				previewEnabled: false
			)
		).managedRoutingSummary

		XCTAssertEqual(summary.availability, .routingDisabled)
		XCTAssertFalse(summary.genericVideoUsesManagedOutput)
		XCTAssertFalse(summary.failClosedOnManagedVideoRequest)
	}

	func testSnapshotManagedRoutingSummaryReflectsDirectPhysicalCapture() {
		let summary = makeSnapshot(outputMode: .directPhysicalCapture).managedRoutingSummary

		XCTAssertEqual(summary.availability, .directPhysicalCapture)
		XCTAssertFalse(summary.genericVideoUsesManagedOutput)
		XCTAssertFalse(summary.failClosedOnManagedVideoRequest)
		XCTAssertFalse(summary.exposesManagedDeviceIdentity)
	}

	func testSnapshotManagedRoutingSummaryReflectsHealthyProcessedOutput() {
		let summary = makeSnapshot(
			healthState: .healthy,
			outputMode: .processedNavigatorFeed
		).managedRoutingSummary

		XCTAssertEqual(summary.availability, .available)
		XCTAssertTrue(summary.genericVideoUsesManagedOutput)
		XCTAssertFalse(summary.failClosedOnManagedVideoRequest)
		XCTAssertTrue(summary.exposesManagedDeviceIdentity)
		XCTAssertEqual(summary.managedDeviceID, BrowserCameraManagedOutputIdentity.deviceID)
	}

	func testSnapshotManagedRoutingSummaryReflectsHealthySystemPublication() {
		let summary = makeSnapshot(
			healthState: .healthy,
			outputMode: .systemVirtualCameraPublication
		).managedRoutingSummary

		XCTAssertEqual(summary.availability, .available)
		XCTAssertTrue(summary.genericVideoUsesManagedOutput)
		XCTAssertFalse(summary.failClosedOnManagedVideoRequest)
		XCTAssertFalse(summary.exposesManagedDeviceIdentity)
	}

	func testSnapshotManagedRoutingSummaryReflectsSourceLost() {
		let summary = makeSnapshot(healthState: .sourceLost).managedRoutingSummary

		XCTAssertEqual(summary.availability, .sourceLost)
		XCTAssertFalse(summary.genericVideoUsesManagedOutput)
		XCTAssertTrue(summary.failClosedOnManagedVideoRequest)
	}

	func testSnapshotManagedRoutingSummaryReflectsDegradedHealth() {
		let summary = makeSnapshot(healthState: .degraded).managedRoutingSummary

		XCTAssertEqual(summary.availability, .degraded)
		XCTAssertFalse(summary.genericVideoUsesManagedOutput)
		XCTAssertTrue(summary.failClosedOnManagedVideoRequest)
	}

	func testSnapshotManagedRoutingSummaryReflectsPipelineFallback() {
		let summary = makeSnapshot(healthState: .pipelineFallback).managedRoutingSummary

		XCTAssertEqual(summary.availability, .pipelineFallback)
		XCTAssertFalse(summary.genericVideoUsesManagedOutput)
		XCTAssertTrue(summary.failClosedOnManagedVideoRequest)
	}

	func testSnapshotManagedRoutingSummaryReflectsPublisherUnavailable() {
		let summary = makeSnapshot(
			healthState: .publisherUnavailable,
			outputMode: .systemVirtualCameraPublication
		).managedRoutingSummary

		XCTAssertEqual(summary.availability, .publisherUnavailable)
		XCTAssertFalse(summary.genericVideoUsesManagedOutput)
		XCTAssertTrue(summary.failClosedOnManagedVideoRequest)
		XCTAssertFalse(summary.exposesManagedDeviceIdentity)
	}

	func testDebugSummaryLegacyInitializerInfersManagedRoutingSummary() {
		let availableSummary = BrowserCameraDebugSummary(
			lifecycleState: .running,
			healthState: .healthy,
			outputMode: .processedNavigatorFeed,
			selectedSourceID: "camera-main",
			selectedSourceName: "FaceTime HD Camera",
			selectedFilterPreset: .folia,
			activeLiveFrameConsumerIDs: ["tab-1"],
			activePreviewConsumerIDs: [],
			performanceMetrics: .empty,
			lastErrorDescription: nil,
			publisherStatus: .notRequired
		)
		let unavailableSummary = BrowserCameraDebugSummary(
			lifecycleState: .failed,
			healthState: .pipelineFallback,
			outputMode: .processedNavigatorFeed,
			selectedSourceID: "camera-main",
			selectedSourceName: "FaceTime HD Camera",
			selectedFilterPreset: .folia,
			activeLiveFrameConsumerIDs: [],
			activePreviewConsumerIDs: [],
			performanceMetrics: .empty,
			lastErrorDescription: "Pipeline unavailable",
			publisherStatus: .notRequired
		)
		let directPhysicalSummary = BrowserCameraDebugSummary(
			lifecycleState: .running,
			healthState: .healthy,
			outputMode: .directPhysicalCapture,
			selectedSourceID: "camera-main",
			selectedSourceName: "FaceTime HD Camera",
			selectedFilterPreset: .none,
			activeLiveFrameConsumerIDs: [],
			activePreviewConsumerIDs: [],
			performanceMetrics: .empty,
			lastErrorDescription: nil,
			publisherStatus: .notRequired
		)

		XCTAssertEqual(availableSummary.managedRoutingSummary.availability, .available)
		XCTAssertTrue(availableSummary.managedRoutingSummary.exposesManagedDeviceIdentity)
		XCTAssertEqual(unavailableSummary.managedRoutingSummary.availability, .pipelineFallback)
		XCTAssertTrue(unavailableSummary.managedRoutingSummary.failClosedOnManagedVideoRequest)
		XCTAssertEqual(directPhysicalSummary.managedRoutingSummary.availability, .directPhysicalCapture)
	}

	private func makeSnapshot(
		healthState: BrowserCameraHealthState = .healthy,
		outputMode: BrowserCameraOutputMode = .processedNavigatorFeed,
		routingSettings: BrowserCameraRoutingSettings = BrowserCameraRoutingSettings(
			routingEnabled: true,
			preferNavigatorCameraWhenPossible: true,
			preferredSourceID: "camera-main",
			preferredFilterPreset: .folia,
			previewEnabled: false
		),
		availableSources: [BrowserCameraSource] = [
			BrowserCameraSource(id: "camera-main", name: "FaceTime HD Camera", isDefault: true),
		]
	) -> BrowserCameraSessionSnapshot {
		BrowserCameraSessionSnapshot(
			lifecycleState: healthState == .healthy ? .running : .failed,
			healthState: healthState,
			outputMode: outputMode,
			routingSettings: routingSettings,
			availableSources: availableSources,
			activeConsumersByID: [:],
			performanceMetrics: .empty,
			lastErrorDescription: nil,
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
					lastErrorDescription: nil
				)
				: .notRequired
		)
	}
}
