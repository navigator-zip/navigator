@testable import BrowserCameraKit
import CoreGraphics
import ModelKit
import XCTest

@MainActor
final class BrowserCameraSessionCoordinatorTests: XCTestCase {
	func testInitialSnapshotUsesPreferredStoredDeviceWhenAvailableAndPreservesSettings() {
		let coordinator = BrowserCameraSessionCoordinator(
			deviceProvider: StubDeviceProvider(
				devices: [
					BrowserCameraDevice(id: "camera-a", name: "FaceTime HD", isDefault: true),
					BrowserCameraDevice(id: "camera-b", name: "Continuity Camera", isDefault: false),
				]
			),
			preferencesStore: StubPreferencesStore(
				preferences: BrowserCameraPreferences(
					routingEnabled: true,
					preferNavigatorCameraWhenPossible: true,
					preferredSourceID: "camera-b",
					preferredFilterPreset: .folia,
					previewEnabled: true
				)
			),
			captureController: StubCaptureController()
		)

		let configuration = coordinator.currentRoutingConfiguration()

		XCTAssertTrue(configuration.isRoutingEnabled)
		XCTAssertEqual(configuration.preferredDeviceID, "camera-b")
		XCTAssertEqual(configuration.preferredFilterPreset, .folia)
		XCTAssertFalse(configuration.prefersHorizontalFlip)
		XCTAssertTrue(configuration.previewEnabled)
		XCTAssertEqual(configuration.outputMode, .processedNavigatorFeed)
	}

	func testRefreshClearsMissingPreferredDeviceAndFallsBackToAutomaticSelection() {
		let preferencesStore = StubPreferencesStore(
			preferences: BrowserCameraPreferences(
				routingEnabled: true,
				preferNavigatorCameraWhenPossible: true,
				preferredSourceID: "missing-camera",
				preferredFilterPreset: .none,
				previewEnabled: false
			)
		)
		let coordinator = BrowserCameraSessionCoordinator(
			deviceProvider: StubDeviceProvider(
				devices: [
					BrowserCameraDevice(id: "camera-a", name: "FaceTime HD", isDefault: true),
				]
			),
			preferencesStore: preferencesStore,
			captureController: StubCaptureController()
		)

		let configuration = coordinator.currentRoutingConfiguration()

		XCTAssertEqual(configuration.preferredDeviceID, "camera-a")
		XCTAssertNil(preferencesStore.savedPreferences?.preferredDeviceID)
	}

	func testAutomaticSelectionPrefersDisplayCameraOverDefaultFaceTimeAndContinuity() {
		let coordinator = BrowserCameraSessionCoordinator(
			deviceProvider: StubDeviceProvider(
				devices: [
					BrowserCameraDevice(id: "camera-face", name: "FaceTime HD Camera", isDefault: true),
					BrowserCameraDevice(id: "camera-display", name: "Studio Display Camera", isDefault: false),
					BrowserCameraDevice(id: "camera-phone", name: "Rehat's iPhone Camera", isDefault: false),
				]
			),
			preferencesStore: StubPreferencesStore(preferences: BrowserCameraPreferences()),
			captureController: StubCaptureController()
		)

		let configuration = coordinator.currentRoutingConfiguration()

		XCTAssertEqual(configuration.preferredDeviceID, "camera-display")
	}

	func testRegisteringLiveFrameConsumerMovesLifecycleToStartingAndRequestsCapture() {
		let captureController = StubCaptureController()
		let coordinator = BrowserCameraSessionCoordinator(
			deviceProvider: StubDeviceProvider(
				devices: [
					BrowserCameraDevice(id: "camera-a", name: "FaceTime HD", isDefault: true),
				]
			),
			preferencesStore: StubPreferencesStore(preferences: BrowserCameraPreferences()),
			captureController: captureController
		)

		coordinator.registerConsumer(
			BrowserCameraConsumer(
				id: "tab-1",
				kind: .browserTabCapture,
				requiresLiveFrames: true
			)
		)

		let snapshot = coordinator.currentSnapshot()
		XCTAssertEqual(snapshot.lifecycleState, .starting)
		XCTAssertEqual(snapshot.liveFrameConsumerCount, 1)
		XCTAssertEqual(snapshot.previewConsumerCount, 0)
		XCTAssertEqual(
			captureController.startConfigurations,
			[
				BrowserCameraCaptureConfiguration(
					deviceID: "camera-a",
					filterPreset: .none
				),
			]
		)
	}

	func testCaptureStartEventMovesLifecycleToRunning() {
		let captureController = StubCaptureController()
		let coordinator = makeCoordinator(captureController: captureController)

		coordinator.registerConsumer(makeLiveConsumer(id: "tab-1"))
		captureController.send(.didStartRunning(deviceID: "camera-a"))

		let snapshot = coordinator.currentSnapshot()
		XCTAssertEqual(snapshot.lifecycleState, .running)
		XCTAssertEqual(snapshot.healthState, .healthy)
		XCTAssertNil(snapshot.lastErrorDescription)
		XCTAssertEqual(snapshot.performanceMetrics, .empty)
	}

	func testMetricsUpdateFlowsIntoSnapshotAndDebugSummary() {
		let captureController = StubCaptureController()
		let coordinator = makeCoordinator(captureController: captureController)
		let pipelineRuntimeState = BrowserCameraPipelineRuntimeState(
			preset: .folia,
			implementation: .aperture,
			warmupProfile: .chromaticFolia,
			grainPresence: .normal,
			requiredFilterCount: 7
		)

		coordinator.registerConsumer(makeLiveConsumer(id: "tab-1"))
		captureController.send(.didStartRunning(deviceID: "camera-a"))
		captureController.send(.didUpdatePipelineRuntimeState(pipelineRuntimeState))
		captureController.send(
			.didUpdateMetrics(
				BrowserCameraPerformanceMetrics(
					processedFrameCount: 30,
					droppedFrameCount: 2,
					firstFrameLatencyMilliseconds: 91.0,
					averageProcessingLatencyMilliseconds: 11.5,
					lastProcessingLatencyMilliseconds: 12.25,
					realtimeBudgetExceeded: false
				)
			)
		)

		let snapshot = coordinator.currentSnapshot()
		let debugSummary = coordinator.currentDebugSummary()
		XCTAssertEqual(snapshot.performanceMetrics.processedFrameCount, 30)
		XCTAssertEqual(snapshot.performanceMetrics.droppedFrameCount, 2)
		XCTAssertEqual(snapshot.performanceMetrics.firstFrameLatencyMilliseconds, 91.0)
		XCTAssertEqual(snapshot.performanceMetrics.averageProcessingLatencyMilliseconds, 11.5)
		XCTAssertEqual(snapshot.performanceMetrics.lastProcessingLatencyMilliseconds, 12.25)
		XCTAssertFalse(snapshot.performanceMetrics.realtimeBudgetExceeded)
		XCTAssertEqual(debugSummary.performanceMetrics, snapshot.performanceMetrics)
		XCTAssertEqual(debugSummary.selectedSourceID, "camera-a")
		XCTAssertEqual(debugSummary.publisherStatus, .notRequired)
		XCTAssertEqual(snapshot.pipelineRuntimeState, pipelineRuntimeState)
		XCTAssertEqual(debugSummary.pipelineRuntimeState, pipelineRuntimeState)
	}

	func testCoordinatorRecordsRecentDiagnosticEventsForDemandAndCaptureLifecycle() {
		let captureController = StubCaptureController()
		let coordinator = makeCoordinator(captureController: captureController)
		let pipelineRuntimeState = BrowserCameraPipelineRuntimeState(
			preset: .folia,
			implementation: .aperture,
			warmupProfile: .chromaticFolia,
			grainPresence: .high,
			requiredFilterCount: 1
		)

		coordinator.registerConsumer(makeLiveConsumer(id: "tab-1"))
		captureController.send(.didStartRunning(deviceID: "camera-a"))
		captureController.send(.didUpdatePipelineRuntimeState(pipelineRuntimeState))
		captureController.send(
			.didUpdateMetrics(
				BrowserCameraPerformanceMetrics(
					processedFrameCount: 12,
					droppedFrameCount: 1,
					firstFrameLatencyMilliseconds: 78.5,
					averageProcessingLatencyMilliseconds: 11.0,
					lastProcessingLatencyMilliseconds: 11.0,
					realtimeBudgetExceeded: true
				)
			)
		)

		let recentEvents = coordinator.currentDebugSummary().recentDiagnosticEvents

		XCTAssertEqual(
			recentEvents.map(\.kind),
			[
				.deviceAvailabilityChanged,
				.consumerRegistered,
				.captureStartRequested,
				.captureStarted,
				.firstFrameProduced,
				.processingDegraded,
			]
		)
		XCTAssertEqual(
			recentEvents.last?.detail,
			"processed=12 dropped=1 averageLatencyMs=11.0 pipeline=aperture warmup=chromatic.folia grain=high filters=1"
		)
	}

	func testCoordinatorRecordsPerformanceDiagnosticWithoutAverageLatency() {
		let captureController = StubCaptureController()
		let coordinator = makeCoordinator(captureController: captureController)

		coordinator.registerConsumer(makeLiveConsumer(id: "tab-1"))
		captureController.send(.didStartRunning(deviceID: "camera-a"))
		captureController.send(
			.didUpdateMetrics(
				BrowserCameraPerformanceMetrics(
					processedFrameCount: 4,
					droppedFrameCount: 3,
					firstFrameLatencyMilliseconds: nil,
					averageProcessingLatencyMilliseconds: nil,
					lastProcessingLatencyMilliseconds: 22.0,
					realtimeBudgetExceeded: true
				)
			)
		)

		XCTAssertEqual(
			coordinator.currentDebugSummary().recentDiagnosticEvents.last?.detail,
			"processed=4 dropped=3 averageLatencyMs=none"
		)
	}

	func testCoordinatorCapsRecentDiagnosticEventsAtConfiguredLimit() {
		let coordinator = makeCoordinator()

		for index in 0..<25 {
			coordinator.setPreferredFilterPreset(index.isMultiple(of: 2) ? .folia : .vertichrome)
		}

		let recentEvents = coordinator.currentDebugSummary().recentDiagnosticEvents

		XCTAssertEqual(recentEvents.count, 20)
		XCTAssertEqual(recentEvents.first?.kind, .filterPresetChanged)
		XCTAssertEqual(recentEvents.first?.detail, "preset=tonachrome")
		XCTAssertEqual(recentEvents.last?.detail, "preset=folia")
	}

	func testCoordinatorRecordsBrowserRoutingAndFallbackDiagnosticEvents() {
		let coordinator = makeCoordinator()
		let startedEvent = BrowserCameraRoutingEvent(
			event: .trackStarted,
			activeManagedTrackCount: 1,
			managedTrackID: "track-7",
			managedDeviceID: BrowserCameraManagedOutputIdentity.deviceID,
			preferredFilterPreset: .folia
		)
		let stoppedEvent = BrowserCameraRoutingEvent(
			event: .trackStopped,
			activeManagedTrackCount: 0,
			managedTrackID: "track-7"
		)
		let endedEvent = BrowserCameraRoutingEvent(
			event: .trackEnded,
			activeManagedTrackCount: 0,
			managedTrackID: "track-7"
		)
		let permissionProbeFailedEvent = BrowserCameraRoutingEvent(
			event: .permissionProbeFailed,
			activeManagedTrackCount: 0,
			errorDescription: "Permission denied"
		)
		let explicitDeviceBypassedEvent = BrowserCameraRoutingEvent(
			event: .explicitDeviceBypassed,
			activeManagedTrackCount: 0,
			requestedDeviceIDs: ["camera-a", "camera-b"]
		)
		let managedTrackDeviceSwitchRejectedEvent = BrowserCameraRoutingEvent(
			event: .managedTrackDeviceSwitchRejected,
			activeManagedTrackCount: 1,
			managedTrackID: "track-9",
			managedDeviceID: BrowserCameraManagedOutputIdentity.deviceID,
			requestedDeviceIDs: ["camera-c"],
			errorDescription: "Navigator Camera Output cannot switch devices on an active managed track."
		)

		coordinator.noteBrowserRoutingEvent(tabID: "tab-7", event: startedEvent)
		coordinator.noteBrowserRoutingEvent(tabID: "tab-7", event: stoppedEvent)
		coordinator.noteBrowserRoutingEvent(tabID: "tab-7", event: endedEvent)
		coordinator.noteBrowserRoutingEvent(tabID: "tab-7", event: permissionProbeFailedEvent)
		coordinator.noteBrowserRoutingEvent(tabID: "tab-7", event: explicitDeviceBypassedEvent)
		coordinator.noteBrowserRoutingEvent(tabID: "tab-7", event: managedTrackDeviceSwitchRejectedEvent)
		coordinator.noteBrowserProcessFallback(tabID: "tab-7", reason: "rendererError=Renderer unavailable")

		let recentEvents = coordinator.currentDebugSummary().recentDiagnosticEvents
		XCTAssertEqual(
			recentEvents.suffix(7).map(\.kind),
			[
				.managedTrackStarted,
				.managedTrackStopped,
				.managedTrackEnded,
				.permissionProbeFailed,
				.explicitDeviceBypassed,
				.managedTrackDeviceSwitchRejected,
				.browserProcessFallbackActivated,
			]
		)
		XCTAssertEqual(
			recentEvents[recentEvents.count - 7].detail,
			"tabID=tab-7 activeManagedTrackCount=1 trackID=track-7 managedDeviceID=\(BrowserCameraManagedOutputIdentity.deviceID) requestedDeviceIDs=none preset=folia"
		)
		XCTAssertEqual(
			recentEvents[recentEvents.count - 6].detail,
			"tabID=tab-7 activeManagedTrackCount=0 trackID=track-7 managedDeviceID=none requestedDeviceIDs=none preset=none"
		)
		XCTAssertEqual(
			recentEvents[recentEvents.count - 5].detail,
			"tabID=tab-7 activeManagedTrackCount=0 trackID=track-7 managedDeviceID=none requestedDeviceIDs=none preset=none"
		)
		XCTAssertEqual(
			recentEvents[recentEvents.count - 4].detail,
			"tabID=tab-7 activeManagedTrackCount=0 trackID=none managedDeviceID=none requestedDeviceIDs=none preset=none error=Permission denied"
		)
		XCTAssertEqual(
			recentEvents[recentEvents.count - 3].detail,
			"tabID=tab-7 activeManagedTrackCount=0 trackID=none managedDeviceID=none requestedDeviceIDs=camera-a,camera-b preset=none"
		)
		XCTAssertEqual(
			recentEvents[recentEvents.count - 2].detail,
			"tabID=tab-7 activeManagedTrackCount=1 trackID=track-9 managedDeviceID=\(BrowserCameraManagedOutputIdentity.deviceID) requestedDeviceIDs=camera-c preset=none error=Navigator Camera Output cannot switch devices on an active managed track."
		)
		XCTAssertEqual(
			recentEvents.last?.detail,
			"tabID=tab-7 reason=rendererError=Renderer unavailable"
		)
	}

	func testCoordinatorStoresSortedBrowserTransportStatesInSnapshotAndDebugSummary() {
		let coordinator = makeCoordinator()

		coordinator.updateBrowserTransportState(
			BrowserCameraBrowserTransportState(
				tabID: "tab-b",
				routingTransportMode: .browserProcessJavaScriptFallback,
				frameTransportMode: .browserProcessJavaScriptFallback,
				activeManagedTrackCount: 0
			)
		)
		coordinator.updateBrowserTransportState(
			BrowserCameraBrowserTransportState(
				tabID: "tab-a",
				routingTransportMode: .rendererProcessMessages,
				frameTransportMode: .unavailable,
				activeManagedTrackCount: 1
			)
		)

		let snapshot = coordinator.currentSnapshot()
		let debugSummary = coordinator.currentDebugSummary()

		XCTAssertEqual(snapshot.browserTransportStates.map(\.tabID), ["tab-a", "tab-b"])
		XCTAssertEqual(debugSummary.browserTransportStates.map(\.tabID), ["tab-a", "tab-b"])
		XCTAssertEqual(
			snapshot.browserTransportStates.first?.routingTransportMode,
			.rendererProcessMessages
		)
		XCTAssertEqual(
			snapshot.browserTransportStates.last?.frameTransportMode,
			.browserProcessJavaScriptFallback
		)
	}

	func testCoordinatorClearsBrowserTransportStateByTabIdentifier() {
		let coordinator = makeCoordinator()

		coordinator.updateBrowserTransportState(
			BrowserCameraBrowserTransportState(
				tabID: "tab-1",
				routingTransportMode: .rendererProcessMessages,
				frameTransportMode: .rendererProcessMessages,
				activeManagedTrackCount: 1
			)
		)
		coordinator.clearBrowserTransportState(tabID: "tab-1")
		coordinator.clearBrowserTransportState(tabID: "tab-1")

		XCTAssertTrue(coordinator.currentSnapshot().browserTransportStates.isEmpty)
	}

	func testCoordinatorRecordsBrowserRoutingEventWithoutManagedTrackIdentity() {
		let coordinator = makeCoordinator()
		let startedEvent = BrowserCameraRoutingEvent(
			event: .trackStarted,
			activeManagedTrackCount: 1
		)

		coordinator.noteBrowserRoutingEvent(tabID: "tab-8", event: startedEvent)

		XCTAssertEqual(
			coordinator.currentDebugSummary().recentDiagnosticEvents.last?.detail,
			"tabID=tab-8 activeManagedTrackCount=1 trackID=none managedDeviceID=none requestedDeviceIDs=none preset=none"
		)
	}

	func testSetPreferredDeviceIDNilRecordsAutomaticSourceInDiagnosticEvents() {
		let preferencesStore = StubPreferencesStore(
			preferences: BrowserCameraPreferences(
				routingEnabled: true,
				preferNavigatorCameraWhenPossible: true,
				preferredSourceID: "camera-a",
				preferredFilterPreset: .none,
				previewEnabled: false
			)
		)
		let coordinator = BrowserCameraSessionCoordinator(
			deviceProvider: StubDeviceProvider(
				devices: [
					BrowserCameraDevice(id: "camera-a", name: "FaceTime HD", isDefault: true),
				]
			),
			preferencesStore: preferencesStore,
			captureController: StubCaptureController()
		)

		coordinator.setPreferredDeviceID(nil)

		XCTAssertEqual(
			coordinator.currentDebugSummary().recentDiagnosticEvents.last?.detail,
			"preferredSourceID=automatic"
		)
	}

	func testRefreshWhileStoppingAndWithoutDemandDoesNotRequestAdditionalStop() {
		let captureController = StubCaptureController()
		let coordinator = makeCoordinator(captureController: captureController)

		coordinator.registerConsumer(makeLiveConsumer(id: "tab-1"))
		coordinator.unregisterConsumer(id: "tab-1")
		XCTAssertEqual(coordinator.currentSnapshot().lifecycleState, .stopping)
		XCTAssertEqual(captureController.stopCount, 1)

		coordinator.refreshAvailableDevices()

		XCTAssertEqual(captureController.stopCount, 1)
		XCTAssertEqual(coordinator.currentSnapshot().lifecycleState, .stopping)
	}

	func testSystemVirtualPublicationStartsPublisherAndReportsPublisherUnavailability() {
		let captureController = StubCaptureController()
		let virtualPublisherController = StubVirtualPublisherController()
		let coordinator = makeCoordinator(
			captureController: captureController,
			virtualPublisherController: virtualPublisherController,
			preferredManagedOutputMode: .systemVirtualCameraPublication
		)

		coordinator.registerConsumer(makeLiveConsumer(id: "tab-1"))

		let snapshot = coordinator.currentSnapshot()
		XCTAssertEqual(snapshot.outputMode, .processedNavigatorFeed)
		XCTAssertEqual(snapshot.healthState, .healthy)
		XCTAssertNil(snapshot.lastErrorDescription)
		XCTAssertFalse(snapshot.publisherReachable)
		XCTAssertEqual(snapshot.publisherStatus.state, .installMissing)
		XCTAssertEqual(
			virtualPublisherController.startConfigurations,
			[
				BrowserCameraVirtualPublisherConfiguration(
					sourceDeviceID: "camera-a",
					filterPreset: .none,
					frameWidth: 1280,
					frameHeight: 720,
					nominalFramesPerSecond: 30,
					pixelFormat: .bgra8888,
					backpressurePolicy: .dropOldest,
					transportMode: .sharedMemory
				),
			]
		)
	}

	func testSystemVirtualPublicationDoesNotStartPublisherWithoutInAppConsumerDemand() {
		let captureController = StubCaptureController()
		let virtualPublisherController = StubVirtualPublisherController()
		let coordinator = makeCoordinator(
			captureController: captureController,
			virtualPublisherController: virtualPublisherController,
			preferredManagedOutputMode: .systemVirtualCameraPublication
		)

		let snapshot = coordinator.currentSnapshot()

		XCTAssertEqual(snapshot.lifecycleState, .idle)
		XCTAssertEqual(snapshot.outputMode, .processedNavigatorFeed)
		XCTAssertEqual(virtualPublisherController.startConfigurations, [])
		XCTAssertEqual(captureController.startConfigurations, [])
	}

	func testSystemVirtualPublicationDoesNotStartPublisherForPreviewOnlyDemand() {
		let captureController = StubCaptureController()
		let virtualPublisherController = StubVirtualPublisherController()
		let coordinator = makeCoordinator(
			captureController: captureController,
			virtualPublisherController: virtualPublisherController,
			preferredManagedOutputMode: .systemVirtualCameraPublication
		)

		coordinator.setPreviewEnabled(true)
		coordinator.registerConsumer(
			BrowserCameraConsumer(
				id: "preview-1",
				kind: .menuBarPreview,
				requiresLiveFrames: false
			)
		)

		let snapshot = coordinator.currentSnapshot()
		XCTAssertEqual(snapshot.outputMode, .processedNavigatorFeed)
		XCTAssertEqual(virtualPublisherController.startConfigurations, [])
		XCTAssertEqual(
			captureController.startConfigurations,
			[
				BrowserCameraCaptureConfiguration(
					deviceID: "camera-a",
					filterPreset: .none
				),
			]
		)
	}

	func testSystemVirtualPublicationBecomesHealthyWhenPublisherReportsReady() throws {
		let captureController = StubCaptureController()
		let virtualPublisherController = StubVirtualPublisherController()
		let coordinator = makeCoordinator(
			captureController: captureController,
			virtualPublisherController: virtualPublisherController,
			preferredManagedOutputMode: .systemVirtualCameraPublication
		)

		coordinator.registerConsumer(makeLiveConsumer(id: "tab-1"))
		try virtualPublisherController.sendStatus(
			BrowserCameraVirtualPublisherStatus(
				state: .ready,
				configuration: XCTUnwrap(virtualPublisherController.startConfigurations.last),
				lastPublishedFrame: BrowserCameraVirtualPublisherFrameDescriptor(
					width: 1280,
					height: 720,
					timing: BrowserCameraVirtualPublisherFrameTiming(
						sequence: 1,
						presentationTimestampMilliseconds: 33.0,
						durationMilliseconds: 33.0
					)
				),
				lastErrorDescription: nil
			)
		)

		let snapshot = coordinator.currentSnapshot()
		XCTAssertEqual(snapshot.outputMode, .systemVirtualCameraPublication)
		XCTAssertEqual(snapshot.healthState, .healthy)
		XCTAssertTrue(snapshot.publisherReachable)
		XCTAssertEqual(snapshot.publisherStatus.state, .ready)
		XCTAssertEqual(snapshot.debugSummary.publisherStatus.lastPublishedFrame?.timing.sequence, 1)
	}

	func testSystemVirtualPublicationReconfiguresPublisherWhenFilterChanges() {
		let captureController = StubCaptureController()
		let virtualPublisherController = StubVirtualPublisherController()
		let coordinator = makeCoordinator(
			captureController: captureController,
			virtualPublisherController: virtualPublisherController,
			preferredManagedOutputMode: .systemVirtualCameraPublication
		)

		coordinator.registerConsumer(makeLiveConsumer(id: "tab-1"))
		coordinator.setPreferredFilterPreset(.vertichrome)

		XCTAssertEqual(
			virtualPublisherController.startConfigurations,
			[
				BrowserCameraVirtualPublisherConfiguration(
					sourceDeviceID: "camera-a",
					filterPreset: .none,
					frameWidth: 1280,
					frameHeight: 720,
					nominalFramesPerSecond: 30,
					pixelFormat: .bgra8888,
					backpressurePolicy: .dropOldest,
					transportMode: .sharedMemory
				),
				BrowserCameraVirtualPublisherConfiguration(
					sourceDeviceID: "camera-a",
					filterPreset: .vertichrome,
					frameWidth: 1280,
					frameHeight: 720,
					nominalFramesPerSecond: 30,
					pixelFormat: .bgra8888,
					backpressurePolicy: .dropOldest,
					transportMode: .sharedMemory
				),
			]
		)
	}

	func testSystemVirtualPublicationStopsPublisherWhenInAppDemandEnds() {
		let captureController = StubCaptureController()
		let virtualPublisherController = StubVirtualPublisherController()
		let coordinator = makeCoordinator(
			captureController: captureController,
			virtualPublisherController: virtualPublisherController,
			preferredManagedOutputMode: .systemVirtualCameraPublication
		)

		coordinator.registerConsumer(makeLiveConsumer(id: "tab-1"))
		coordinator.unregisterConsumer(id: "tab-1")

		XCTAssertEqual(virtualPublisherController.stopCount, 1)
		XCTAssertEqual(captureController.stopCount, 1)
		XCTAssertEqual(
			virtualPublisherController.startConfigurations,
			[
				BrowserCameraVirtualPublisherConfiguration(
					sourceDeviceID: "camera-a",
					filterPreset: .none,
					frameWidth: 1280,
					frameHeight: 720,
					nominalFramesPerSecond: 30,
					pixelFormat: .bgra8888,
					backpressurePolicy: .dropOldest,
					transportMode: .sharedMemory
				),
			]
		)
		XCTAssertEqual(coordinator.currentSnapshot().publisherStatus.state, .notRequired)
		XCTAssertEqual(coordinator.currentSnapshot().lifecycleState, .stopping)
	}

	func testSystemVirtualPublicationForwardsProcessedFramesIntoPublisher() async {
		let captureController = StubCaptureController()
		let virtualPublisherController = StubVirtualPublisherController()
		let coordinator = makeCoordinator(
			captureController: captureController,
			virtualPublisherController: virtualPublisherController,
			preferredManagedOutputMode: .systemVirtualCameraPublication
		)
		let frame = BrowserCameraVirtualOutputFrame(
			data: Data([0x01, 0x02, 0x03, 0x04]),
			width: 2,
			height: 1,
			bytesPerRow: 8,
			pixelFormat: .bgra8888,
			timestampHostTime: 44,
			durationHostTime: 33
		)

		coordinator.registerConsumer(makeLiveConsumer(id: "tab-1"))
		captureController.sendVirtualPublisherFrame(frame)
		await Task.yield()

		XCTAssertEqual(virtualPublisherController.publishedFrames.count, 1)
		XCTAssertEqual(virtualPublisherController.publishedFrames.first?.payloadByteCount, frame.payloadByteCount)
		XCTAssertEqual(virtualPublisherController.publishedFrames.first?.width, frame.width)
		XCTAssertEqual(virtualPublisherController.publishedFrames.first?.height, frame.height)
		XCTAssertEqual(virtualPublisherController.publishedFrames.first?.bytesPerRow, frame.bytesPerRow)
		XCTAssertEqual(virtualPublisherController.publishedFrames.first?.pixelFormat, frame.pixelFormat)
		XCTAssertEqual(
			virtualPublisherController.publishedFrames.first?.timestampHostTime,
			frame.timestampHostTime
		)
		XCTAssertEqual(
			virtualPublisherController.publishedFrames.first?.durationHostTime,
			frame.durationHostTime
		)
		XCTAssertEqual(virtualPublisherController.publishedFrames.first?.data, frame.data)
	}

	func testProcessedRoutingDoesNotForwardFramesIntoVirtualPublisher() async {
		let captureController = StubCaptureController()
		let virtualPublisherController = StubVirtualPublisherController()
		let coordinator = makeCoordinator(
			captureController: captureController,
			virtualPublisherController: virtualPublisherController,
			preferredManagedOutputMode: .processedNavigatorFeed
		)
		let frame = BrowserCameraVirtualOutputFrame(
			data: Data([0x05, 0x06]),
			width: 1,
			height: 1,
			bytesPerRow: 4,
			pixelFormat: .bgra8888,
			timestampHostTime: 12,
			durationHostTime: 6
		)

		coordinator.registerConsumer(makeLiveConsumer(id: "tab-1"))
		captureController.sendVirtualPublisherFrame(frame)
		await Task.yield()

		XCTAssertEqual(virtualPublisherController.publishedFrames, [])
	}

	func testRealtimeBudgetExceededMetricsDegradeHealthUntilMetricsRecover() {
		let captureController = StubCaptureController()
		let coordinator = makeCoordinator(captureController: captureController)

		coordinator.registerConsumer(makeLiveConsumer(id: "tab-1"))
		captureController.send(.didStartRunning(deviceID: "camera-a"))
		captureController.send(
			.didUpdateMetrics(
				BrowserCameraPerformanceMetrics(
					processedFrameCount: 18,
					droppedFrameCount: 1,
					firstFrameLatencyMilliseconds: 66.0,
					averageProcessingLatencyMilliseconds: 48.5,
					lastProcessingLatencyMilliseconds: 51.2,
					realtimeBudgetExceeded: true
				)
			)
		)

		var snapshot = coordinator.currentSnapshot()
		XCTAssertEqual(snapshot.healthState, .degraded)
		XCTAssertEqual(
			snapshot.lastErrorDescription,
			"Navigator Camera processing is currently exceeding the realtime budget."
		)

		captureController.send(
			.didUpdateMetrics(
				BrowserCameraPerformanceMetrics(
					processedFrameCount: 30,
					droppedFrameCount: 1,
					firstFrameLatencyMilliseconds: 66.0,
					averageProcessingLatencyMilliseconds: 14.0,
					lastProcessingLatencyMilliseconds: 15.0,
					realtimeBudgetExceeded: false
				)
			)
		)

		snapshot = coordinator.currentSnapshot()
		XCTAssertEqual(snapshot.healthState, .healthy)
		XCTAssertNil(snapshot.lastErrorDescription)
	}

	func testPreviewOnlyConsumerLeavesLifecycleIdleAndDoesNotRequestCapture() {
		let captureController = StubCaptureController()
		let coordinator = makeCoordinator(captureController: captureController)

		coordinator.registerConsumer(
			BrowserCameraConsumer(
				id: "preview-1",
				kind: .browserPreview,
				requiresLiveFrames: false
			)
		)

		let snapshot = coordinator.currentSnapshot()
		XCTAssertEqual(snapshot.lifecycleState, .idle)
		XCTAssertEqual(snapshot.liveFrameConsumerCount, 0)
		XCTAssertEqual(snapshot.previewConsumerCount, 1)
		XCTAssertTrue(captureController.startConfigurations.isEmpty)
	}

	func testPreviewEnabledPreviewConsumerStartsManagedCaptureWithoutLiveFrameDemand() {
		let captureController = StubCaptureController()
		let coordinator = BrowserCameraSessionCoordinator(
			deviceProvider: StubDeviceProvider(
				devices: [BrowserCameraDevice(id: "camera-a", name: "FaceTime HD", isDefault: true)]
			),
			preferencesStore: StubPreferencesStore(
				preferences: BrowserCameraPreferences(
					routingEnabled: false,
					preferNavigatorCameraWhenPossible: false,
					preferredSourceID: nil,
					preferredFilterPreset: .none,
					previewEnabled: true
				)
			),
			captureController: captureController
		)

		coordinator.registerConsumer(
			BrowserCameraConsumer(
				id: "preview-1",
				kind: .browserPreview,
				requiresLiveFrames: false
			)
		)

		let snapshot = coordinator.currentSnapshot()
		XCTAssertEqual(snapshot.lifecycleState, .starting)
		XCTAssertEqual(snapshot.outputMode, .processedNavigatorFeed)
		XCTAssertEqual(snapshot.liveFrameConsumerCount, 0)
		XCTAssertEqual(snapshot.previewConsumerCount, 1)
		XCTAssertEqual(
			captureController.startConfigurations,
			[
				BrowserCameraCaptureConfiguration(deviceID: "camera-a", filterPreset: .none),
			]
		)
	}

	func testSnapshotPreservesExplicitLiveFrameRequirementForPreviewConsumer() {
		let captureController = StubCaptureController()
		let coordinator = makeCoordinator(captureController: captureController)

		coordinator.registerConsumer(
			BrowserCameraConsumer(
				id: "preview-live-1",
				kind: .browserPreview,
				requiresLiveFrames: true
			)
		)

		let snapshot = coordinator.currentSnapshot()
		XCTAssertEqual(snapshot.activeLiveFrameConsumerIDs, ["preview-live-1"])
		XCTAssertEqual(snapshot.activePreviewConsumerIDs, [])
		XCTAssertEqual(snapshot.liveFrameConsumerCount, 1)
		XCTAssertEqual(snapshot.previewConsumerCount, 0)
		XCTAssertEqual(
			captureController.startConfigurations,
			[
				BrowserCameraCaptureConfiguration(
					deviceID: "camera-a",
					filterPreset: .none
				),
			]
		)
	}

	func testCurrentSnapshotSortsConsumersByKindThenIdentifier() {
		let coordinator = makeCoordinator()

		coordinator.registerConsumer(
			BrowserCameraConsumer(
				id: "preview-b",
				kind: .browserPreview,
				requiresLiveFrames: false
			)
		)
		coordinator.registerConsumer(
			BrowserCameraConsumer(
				id: "capture-a",
				kind: .browserTabCapture,
				requiresLiveFrames: true
			)
		)
		coordinator.registerConsumer(
			BrowserCameraConsumer(
				id: "preview-a",
				kind: .browserPreview,
				requiresLiveFrames: false
			)
		)

		XCTAssertEqual(
			coordinator.currentSnapshot().activeConsumers.map(\.id),
			["capture-a", "preview-a", "preview-b"]
		)
	}

	func testUnregisteringLastLiveConsumerMovesLifecycleToStoppingThenIdleAfterStopEvent() {
		let captureController = StubCaptureController()
		let coordinator = makeCoordinator(captureController: captureController)

		coordinator.registerConsumer(makeLiveConsumer(id: "tab-1"))
		captureController.send(.didStartRunning(deviceID: "camera-a"))
		coordinator.unregisterConsumer(id: "tab-1")

		XCTAssertEqual(coordinator.currentSnapshot().lifecycleState, .stopping)
		XCTAssertEqual(captureController.stopCount, 1)

		captureController.send(.didStop(deviceID: "camera-a"))

		let snapshot = coordinator.currentSnapshot()
		XCTAssertEqual(snapshot.lifecycleState, .idle)
		XCTAssertTrue(snapshot.activeConsumers.isEmpty)
	}

	func testUnexpectedStopWhileDemandRemainsRestartsCapture() {
		let captureController = StubCaptureController()
		let coordinator = makeCoordinator(captureController: captureController)

		coordinator.registerConsumer(makeLiveConsumer(id: "tab-1"))
		captureController.send(.didStartRunning(deviceID: "camera-a"))
		captureController.send(.didStop(deviceID: "camera-a"))

		XCTAssertEqual(
			captureController.startConfigurations,
			[
				BrowserCameraCaptureConfiguration(deviceID: "camera-a", filterPreset: .none),
				BrowserCameraCaptureConfiguration(deviceID: "camera-a", filterPreset: .none),
			]
		)
		XCTAssertEqual(coordinator.currentSnapshot().lifecycleState, .starting)
		XCTAssertEqual(coordinator.currentSnapshot().performanceMetrics, .empty)
	}

	func testUnregisteringConsumerIsIdempotent() {
		let captureController = StubCaptureController()
		let coordinator = makeCoordinator(captureController: captureController)

		coordinator.registerConsumer(makeLiveConsumer(id: "tab-1"))
		coordinator.unregisterConsumer(id: "tab-1")
		coordinator.unregisterConsumer(id: "tab-1")

		XCTAssertEqual(captureController.stopCount, 1)
		XCTAssertEqual(coordinator.currentSnapshot().lifecycleState, .stopping)
	}

	func testLiveConsumerWithRoutingDisabledDoesNotStartManagedCapture() {
		let captureController = StubCaptureController()
		let coordinator = BrowserCameraSessionCoordinator(
			deviceProvider: StubDeviceProvider(
				devices: [BrowserCameraDevice(id: "camera-a", name: "FaceTime HD", isDefault: true)]
			),
			preferencesStore: StubPreferencesStore(
				preferences: BrowserCameraPreferences(
					routingEnabled: false,
					preferNavigatorCameraWhenPossible: true,
					preferredSourceID: nil,
					preferredFilterPreset: .none,
					previewEnabled: false
				)
			),
			captureController: captureController
		)

		coordinator.registerConsumer(makeLiveConsumer(id: "tab-1"))

		let configuration = coordinator.currentRoutingConfiguration()
		XCTAssertFalse(configuration.isRoutingEnabled)
		XCTAssertEqual(configuration.outputMode, .unavailable)
		XCTAssertEqual(coordinator.currentSnapshot().lifecycleState, .idle)
		XCTAssertTrue(captureController.startConfigurations.isEmpty)
	}

	func testSetRoutingEnabledFalsePersistsDisabledPreferenceAndStopsRunningCapture() {
		let preferencesStore = StubPreferencesStore(preferences: BrowserCameraPreferences())
		let captureController = StubCaptureController()
		let coordinator = BrowserCameraSessionCoordinator(
			deviceProvider: StubDeviceProvider(
				devices: [BrowserCameraDevice(id: "camera-a", name: "FaceTime HD", isDefault: true)]
			),
			preferencesStore: preferencesStore,
			captureController: captureController
		)

		coordinator.registerConsumer(makeLiveConsumer(id: "tab-1"))
		captureController.send(.didStartRunning(deviceID: "camera-a"))
		coordinator.setRoutingEnabled(false)

		let configuration = coordinator.currentRoutingConfiguration()
		XCTAssertFalse(configuration.isRoutingEnabled)
		XCTAssertEqual(configuration.outputMode, .unavailable)
		XCTAssertEqual(coordinator.currentSnapshot().lifecycleState, .stopping)
		XCTAssertEqual(preferencesStore.savedPreferences?.routingEnabled, false)
		XCTAssertEqual(captureController.stopCount, 1)
	}

	func testSetRoutingEnabledNoOpDoesNotPersistWhenValueIsUnchanged() {
		let preferencesStore = StubPreferencesStore(
			preferences: BrowserCameraPreferences(
				routingEnabled: true,
				preferNavigatorCameraWhenPossible: true,
				preferredSourceID: "camera-a",
				preferredFilterPreset: .none,
				previewEnabled: false
			)
		)
		let coordinator = BrowserCameraSessionCoordinator(
			deviceProvider: StubDeviceProvider(
				devices: [BrowserCameraDevice(id: "camera-a", name: "FaceTime HD", isDefault: true)]
			),
			preferencesStore: preferencesStore,
			captureController: StubCaptureController()
		)

		coordinator.setRoutingEnabled(true)

		XCTAssertNil(preferencesStore.savedPreferences)
	}

	func testSetPreferredDeviceIDPersistsSelectionAndRestartsManagedCapture() {
		let preferencesStore = StubPreferencesStore(preferences: BrowserCameraPreferences())
		let captureController = StubCaptureController()
		let coordinator = BrowserCameraSessionCoordinator(
			deviceProvider: StubDeviceProvider(
				devices: [
					BrowserCameraDevice(id: "camera-a", name: "FaceTime HD", isDefault: true),
					BrowserCameraDevice(id: "camera-b", name: "Continuity Camera", isDefault: false),
				]
			),
			preferencesStore: preferencesStore,
			captureController: captureController
		)

		coordinator.registerConsumer(makeLiveConsumer(id: "tab-1"))
		captureController.send(.didStartRunning(deviceID: "camera-a"))
		coordinator.setPreferredDeviceID("camera-b")

		let configuration = coordinator.currentRoutingConfiguration()
		XCTAssertEqual(configuration.preferredDeviceID, "camera-b")
		XCTAssertEqual(preferencesStore.savedPreferences?.preferredDeviceID, "camera-b")
		XCTAssertEqual(
			captureController.startConfigurations,
			[
				BrowserCameraCaptureConfiguration(deviceID: "camera-a", filterPreset: .none),
				BrowserCameraCaptureConfiguration(deviceID: "camera-b", filterPreset: .none),
			]
		)
		XCTAssertEqual(coordinator.currentSnapshot().lifecycleState, .starting)
	}

	func testSetPreferredDeviceIDNoOpDoesNotPersistWhenValueIsUnchanged() {
		let preferencesStore = StubPreferencesStore(
			preferences: BrowserCameraPreferences(
				routingEnabled: true,
				preferNavigatorCameraWhenPossible: true,
				preferredSourceID: "camera-a",
				preferredFilterPreset: .none,
				previewEnabled: false
			)
		)
		let coordinator = BrowserCameraSessionCoordinator(
			deviceProvider: StubDeviceProvider(
				devices: [BrowserCameraDevice(id: "camera-a", name: "FaceTime HD", isDefault: true)]
			),
			preferencesStore: preferencesStore,
			captureController: StubCaptureController()
		)

		coordinator.setPreferredDeviceID("camera-a")

		XCTAssertNil(preferencesStore.savedPreferences)
	}

	func testSetPreferredFilterPresetPersistsAndReconfiguresManagedCapture() {
		let preferencesStore = StubPreferencesStore(preferences: BrowserCameraPreferences())
		let captureController = StubCaptureController()
		let coordinator = BrowserCameraSessionCoordinator(
			deviceProvider: StubDeviceProvider(
				devices: [BrowserCameraDevice(id: "camera-a", name: "FaceTime HD", isDefault: true)]
			),
			preferencesStore: preferencesStore,
			captureController: captureController
		)

		coordinator.registerConsumer(makeLiveConsumer(id: "tab-1"))
		captureController.send(.didStartRunning(deviceID: "camera-a"))
		coordinator.setPreferredFilterPreset(.folia)

		XCTAssertEqual(preferencesStore.savedPreferences?.preferredFilterPreset, .folia)
		XCTAssertEqual(
			captureController.startConfigurations,
			[BrowserCameraCaptureConfiguration(deviceID: "camera-a", filterPreset: .none)]
		)
		XCTAssertEqual(
			captureController.updatedConfigurations,
			[BrowserCameraCaptureConfiguration(deviceID: "camera-a", filterPreset: .folia)]
		)
		XCTAssertEqual(coordinator.currentRoutingConfiguration().preferredFilterPreset, .folia)
	}

	func testSetPreferredFilterPresetNoOpDoesNotPersistWhenValueIsUnchanged() {
		let preferencesStore = StubPreferencesStore(
			preferences: BrowserCameraPreferences(
				routingEnabled: true,
				preferNavigatorCameraWhenPossible: true,
				preferredSourceID: nil,
				preferredFilterPreset: .folia,
				previewEnabled: false
			)
		)
		let captureController = StubCaptureController()
		let coordinator = BrowserCameraSessionCoordinator(
			deviceProvider: StubDeviceProvider(
				devices: [BrowserCameraDevice(id: "camera-a", name: "FaceTime HD", isDefault: true)]
			),
			preferencesStore: preferencesStore,
			captureController: captureController
		)
		preferencesStore.resetSavedPreferences()

		coordinator.setPreferredFilterPreset(.folia)

		XCTAssertNil(preferencesStore.savedPreferences)
		XCTAssertTrue(captureController.startConfigurations.isEmpty)
	}

	func testSetPreferredGrainPresencePersistsAndUpdatesManagedCaptureInline() {
		let preferencesStore = StubPreferencesStore(preferences: BrowserCameraPreferences())
		let captureController = StubCaptureController()
		let coordinator = BrowserCameraSessionCoordinator(
			deviceProvider: StubDeviceProvider(
				devices: [BrowserCameraDevice(id: "camera-a", name: "FaceTime HD", isDefault: true)]
			),
			preferencesStore: preferencesStore,
			captureController: captureController
		)

		coordinator.registerConsumer(makeLiveConsumer(id: "tab-1"))
		captureController.send(.didStartRunning(deviceID: "camera-a"))
		coordinator.setPreferredGrainPresence(.high)

		XCTAssertEqual(preferencesStore.savedPreferences?.preferredGrainPresence, .high)
		XCTAssertEqual(
			captureController.startConfigurations,
			[BrowserCameraCaptureConfiguration(deviceID: "camera-a", filterPreset: .none)]
		)
		XCTAssertEqual(
			captureController.updatedConfigurations,
			[
				BrowserCameraCaptureConfiguration(
					deviceID: "camera-a",
					filterPreset: .none,
					grainPresence: .high,
					prefersHorizontalFlip: false
				),
			]
		)
	}

	func testSetPrefersHorizontalFlipPersistsAndReconfiguresManagedCapture() {
		let preferencesStore = StubPreferencesStore(preferences: BrowserCameraPreferences())
		let captureController = StubCaptureController()
		let coordinator = BrowserCameraSessionCoordinator(
			deviceProvider: StubDeviceProvider(
				devices: [BrowserCameraDevice(id: "camera-a", name: "FaceTime HD", isDefault: true)]
			),
			preferencesStore: preferencesStore,
			captureController: captureController
		)

		coordinator.registerConsumer(makeLiveConsumer(id: "tab-1"))
		captureController.send(.didStartRunning(deviceID: "camera-a"))
		coordinator.setPrefersHorizontalFlip(true)

		XCTAssertEqual(preferencesStore.savedPreferences?.prefersHorizontalFlip, true)
		XCTAssertEqual(
			captureController.startConfigurations,
			[BrowserCameraCaptureConfiguration(deviceID: "camera-a", filterPreset: .none)]
		)
		XCTAssertEqual(
			captureController.updatedConfigurations,
			[
				BrowserCameraCaptureConfiguration(
					deviceID: "camera-a",
					filterPreset: .none,
					grainPresence: .none,
					prefersHorizontalFlip: true
				),
			]
		)
		XCTAssertTrue(coordinator.currentRoutingConfiguration().prefersHorizontalFlip)
	}

	func testSetPreferredFilterPresetWithoutDemandPersistsWithoutStartingCapture() {
		let preferencesStore = StubPreferencesStore(preferences: BrowserCameraPreferences())
		let captureController = StubCaptureController()
		let coordinator = BrowserCameraSessionCoordinator(
			deviceProvider: StubDeviceProvider(
				devices: [BrowserCameraDevice(id: "camera-a", name: "FaceTime HD", isDefault: true)]
			),
			preferencesStore: preferencesStore,
			captureController: captureController
		)

		coordinator.setPreferredFilterPreset(.supergold)

		XCTAssertEqual(preferencesStore.savedPreferences?.preferredFilterPreset, .supergold)
		XCTAssertTrue(captureController.startConfigurations.isEmpty)
	}

	func testSetPreviewEnabledPersistsPreferenceWithoutStartingCapture() {
		let preferencesStore = StubPreferencesStore(preferences: BrowserCameraPreferences())
		let captureController = StubCaptureController()
		let coordinator = BrowserCameraSessionCoordinator(
			deviceProvider: StubDeviceProvider(
				devices: [BrowserCameraDevice(id: "camera-a", name: "FaceTime HD", isDefault: true)]
			),
			preferencesStore: preferencesStore,
			captureController: captureController
		)

		coordinator.setPreviewEnabled(true)

		XCTAssertTrue(coordinator.currentRoutingConfiguration().previewEnabled)
		XCTAssertEqual(preferencesStore.savedPreferences?.previewEnabled, true)
		XCTAssertTrue(captureController.startConfigurations.isEmpty)
	}

	func testSetPreviewEnabledWithRegisteredPreviewConsumerStartsManagedCapture() {
		let preferencesStore = StubPreferencesStore(preferences: BrowserCameraPreferences())
		let captureController = StubCaptureController()
		let coordinator = BrowserCameraSessionCoordinator(
			deviceProvider: StubDeviceProvider(
				devices: [BrowserCameraDevice(id: "camera-a", name: "FaceTime HD", isDefault: true)]
			),
			preferencesStore: preferencesStore,
			captureController: captureController
		)

		coordinator.registerConsumer(
			BrowserCameraConsumer(
				id: "preview-1",
				kind: .browserPreview,
				requiresLiveFrames: false
			)
		)
		coordinator.setPreviewEnabled(true)

		XCTAssertEqual(coordinator.currentSnapshot().lifecycleState, .starting)
		XCTAssertEqual(
			captureController.startConfigurations,
			[
				BrowserCameraCaptureConfiguration(deviceID: "camera-a", filterPreset: .none),
			]
		)
	}

	func testSetPreviewEnabledNoOpDoesNotPersistWhenValueIsUnchanged() {
		let preferencesStore = StubPreferencesStore(
			preferences: BrowserCameraPreferences(
				routingEnabled: true,
				preferNavigatorCameraWhenPossible: true,
				preferredSourceID: nil,
				preferredFilterPreset: .none,
				previewEnabled: true
			)
		)
		let coordinator = BrowserCameraSessionCoordinator(
			deviceProvider: StubDeviceProvider(
				devices: [BrowserCameraDevice(id: "camera-a", name: "FaceTime HD", isDefault: true)]
			),
			preferencesStore: preferencesStore,
			captureController: StubCaptureController()
		)
		preferencesStore.resetSavedPreferences()

		coordinator.setPreviewEnabled(true)

		XCTAssertNil(preferencesStore.savedPreferences)
	}

	func testNoAvailableDevicesMarksSourceLostAndUnavailableOutput() {
		let coordinator = BrowserCameraSessionCoordinator(
			deviceProvider: StubDeviceProvider(devices: []),
			preferencesStore: StubPreferencesStore(preferences: BrowserCameraPreferences()),
			captureController: StubCaptureController()
		)

		let snapshot = coordinator.currentSnapshot()
		let configuration = coordinator.currentRoutingConfiguration()

		XCTAssertEqual(snapshot.healthState, .sourceLost)
		XCTAssertEqual(snapshot.outputMode, .unavailable)
		XCTAssertEqual(snapshot.lastErrorDescription, "No available video capture devices.")
		XCTAssertFalse(configuration.isRoutingEnabled)
	}

	func testLiveFrameConsumerWithoutAvailableDeviceMovesLifecycleToFailed() {
		let captureController = StubCaptureController()
		let coordinator = BrowserCameraSessionCoordinator(
			deviceProvider: StubDeviceProvider(devices: []),
			preferencesStore: StubPreferencesStore(preferences: BrowserCameraPreferences()),
			captureController: captureController
		)

		coordinator.registerConsumer(makeLiveConsumer(id: "tab-1"))

		let snapshot = coordinator.currentSnapshot()
		XCTAssertEqual(snapshot.lifecycleState, .failed)
		XCTAssertEqual(snapshot.healthState, .sourceLost)
		XCTAssertTrue(captureController.startConfigurations.isEmpty)
	}

	func testCaptureFailureMarksSessionDegradedAndReportsError() {
		let captureController = StubCaptureController()
		let coordinator = makeCoordinator(captureController: captureController)

		coordinator.registerConsumer(makeLiveConsumer(id: "tab-1"))
		captureController.send(.didFail(.authorizationDenied))

		let snapshot = coordinator.currentSnapshot()
		XCTAssertEqual(snapshot.lifecycleState, .failed)
		XCTAssertEqual(snapshot.healthState, .degraded)
		XCTAssertEqual(snapshot.lastErrorDescription, "Navigator does not have permission to access the camera.")
	}

	func testSourceUnavailableFailureMarksSessionSourceLostAndUsesDeviceDescription() {
		let captureController = StubCaptureController()
		let coordinator = makeCoordinator(captureController: captureController)

		coordinator.registerConsumer(makeLiveConsumer(id: "tab-1"))
		captureController.send(.didFail(.sourceUnavailable(deviceID: "camera-a")))

		let snapshot = coordinator.currentSnapshot()
		XCTAssertEqual(snapshot.healthState, .sourceLost)
		XCTAssertEqual(snapshot.lastErrorDescription, "Camera source camera-a is unavailable.")
	}

	func testRuntimeFailureUsesUnderlyingDescription() {
		let captureController = StubCaptureController()
		let coordinator = makeCoordinator(captureController: captureController)

		coordinator.registerConsumer(makeLiveConsumer(id: "tab-1"))
		captureController.send(.didFail(.runtimeFailure(description: "Synthetic runtime failure.")))

		let snapshot = coordinator.currentSnapshot()
		XCTAssertEqual(snapshot.healthState, .degraded)
		XCTAssertEqual(snapshot.lastErrorDescription, "Synthetic runtime failure.")
	}

	func testSessionConfigurationFailureUsesUnderlyingDescription() {
		let captureController = StubCaptureController()
		let coordinator = makeCoordinator(captureController: captureController)

		coordinator.registerConsumer(makeLiveConsumer(id: "tab-1"))
		captureController.send(
			.didFail(
				.sessionConfigurationFailed(description: "Unable to configure managed camera capture.")
			)
		)

		let snapshot = coordinator.currentSnapshot()
		XCTAssertEqual(snapshot.healthState, .degraded)
		XCTAssertEqual(
			snapshot.lastErrorDescription,
			"Unable to configure managed camera capture."
		)
	}

	func testInterruptedFailureUsesUnderlyingDescription() {
		let captureController = StubCaptureController()
		let coordinator = makeCoordinator(captureController: captureController)

		coordinator.registerConsumer(makeLiveConsumer(id: "tab-1"))
		captureController.send(
			.didFail(
				.interrupted(description: "The active camera session was interrupted.")
			)
		)

		let snapshot = coordinator.currentSnapshot()
		XCTAssertEqual(snapshot.healthState, .degraded)
		XCTAssertEqual(
			snapshot.lastErrorDescription,
			"The active camera session was interrupted."
		)
	}

	func testPipelineUnavailableFailureMarksSessionPipelineFallback() {
		let captureController = StubCaptureController()
		let coordinator = makeCoordinator(captureController: captureController)

		coordinator.registerConsumer(makeLiveConsumer(id: "tab-1"))
		captureController.send(
			.didFail(
				.pipelineUnavailable(description: "The selected filter pipeline is unavailable.")
			)
		)

		let snapshot = coordinator.currentSnapshot()
		XCTAssertEqual(snapshot.healthState, .pipelineFallback)
		XCTAssertEqual(
			snapshot.lastErrorDescription,
			"The selected filter pipeline is unavailable."
		)
	}

	func testSourceLostRefreshesAvailableDevicesAndRestartsOnFallbackDevice() {
		let deviceProvider = SequencedDeviceProvider(
			sequences: [
				[
					BrowserCameraDevice(id: "camera-a", name: "FaceTime HD", isDefault: true),
				],
				[
					BrowserCameraDevice(id: "camera-b", name: "Continuity Camera", isDefault: true),
				],
			]
		)
		let captureController = StubCaptureController()
		let coordinator = BrowserCameraSessionCoordinator(
			deviceProvider: deviceProvider,
			preferencesStore: StubPreferencesStore(preferences: BrowserCameraPreferences()),
			captureController: captureController
		)

		coordinator.registerConsumer(makeLiveConsumer(id: "tab-1"))
		captureController.send(.didStartRunning(deviceID: "camera-a"))
		captureController.send(.sourceWasLost(deviceID: "camera-a"))

		let snapshot = coordinator.currentSnapshot()
		XCTAssertEqual(deviceProvider.availableDevicesCallCount, 2)
		XCTAssertEqual(snapshot.lifecycleState, .starting)
		XCTAssertEqual(snapshot.availableDevices.map(\.id), ["camera-b"])
		XCTAssertEqual(snapshot.routingConfiguration.preferredDeviceID, "camera-b")
		XCTAssertEqual(snapshot.performanceMetrics, .empty)
		XCTAssertEqual(
			captureController.startConfigurations.last,
			BrowserCameraCaptureConfiguration(deviceID: "camera-b", filterPreset: .none)
		)
	}

	func testRefreshingWhileRunningAndLosingAllDevicesRequestsStop() {
		let deviceProvider = SequencedDeviceProvider(
			sequences: [
				[
					BrowserCameraDevice(id: "camera-a", name: "FaceTime HD", isDefault: true),
				],
				[],
			]
		)
		let captureController = StubCaptureController()
		let coordinator = BrowserCameraSessionCoordinator(
			deviceProvider: deviceProvider,
			preferencesStore: StubPreferencesStore(preferences: BrowserCameraPreferences()),
			captureController: captureController
		)

		coordinator.registerConsumer(makeLiveConsumer(id: "tab-1"))
		captureController.send(.didStartRunning(deviceID: "camera-a"))
		coordinator.refreshAvailableDevices()

		let snapshot = coordinator.currentSnapshot()
		XCTAssertEqual(captureController.stopCount, 1)
		XCTAssertEqual(snapshot.lifecycleState, .failed)
		XCTAssertEqual(snapshot.healthState, .sourceLost)
	}

	func testSnapshotObserversReceiveDistinctUpdatesAndStopAfterRemoval() {
		let coordinator = makeCoordinator()
		var receivedSnapshots = [BrowserCameraSessionSnapshot]()

		let observerID = coordinator.addSnapshotObserver { snapshot in
			receivedSnapshots.append(snapshot)
		}

		coordinator.registerConsumer(
			BrowserCameraConsumer(
				id: "preview-1",
				kind: .browserPreview,
				requiresLiveFrames: false
			)
		)
		coordinator.registerConsumer(
			BrowserCameraConsumer(
				id: "preview-1",
				kind: .browserPreview,
				requiresLiveFrames: false
			)
		)
		coordinator.removeSnapshotObserver(id: observerID)
		coordinator.registerConsumer(makeLiveConsumer(id: "tab-1"))

		XCTAssertEqual(receivedSnapshots.map(\.previewConsumerCount), [0, 1])
		XCTAssertEqual(receivedSnapshots.map(\.liveFrameConsumerCount), [0, 0])
		XCTAssertEqual(receivedSnapshots.map(\.lifecycleState), [.idle, .idle])
	}

	func testPreviewFrameObserversReceivePreviewUpdatesAndClearEvents() async {
		let captureController = StubCaptureController()
		let previewFrameUpdater = BrowserCameraPreviewFrameUpdater(mainQueue: .main)
		let coordinator = makeCoordinator(
			captureController: captureController,
			previewFrameUpdater: previewFrameUpdater
		)
		let previewImage = makePreviewImage()
		let previewImageExpectation = expectation(description: "preview image")
		let previewClearExpectation = expectation(description: "preview clears")
		var sawPreviewImage = false
		var didFulfillClearExpectation = false
		var receivedEvents = 0

		let observerID = coordinator.addPreviewFrameObserver { previewFrame in
			receivedEvents += 1
			if previewFrame != nil, sawPreviewImage == false {
				sawPreviewImage = true
				previewImageExpectation.fulfill()
			}
			if sawPreviewImage, previewFrame == nil, didFulfillClearExpectation == false {
				didFulfillClearExpectation = true
				previewClearExpectation.fulfill()
			}
		}

		previewFrameUpdater.publish(BrowserCameraPreviewFrame(image: previewImage))
		await fulfillment(of: [previewImageExpectation], timeout: 1)
		previewFrameUpdater.publish(nil)
		captureController.send(.didStop(deviceID: "camera-a"))
		await fulfillment(of: [previewClearExpectation], timeout: 1)
		let receivedEventsBeforeRemoval = receivedEvents
		coordinator.removePreviewFrameObserver(id: observerID)
		previewFrameUpdater.publish(BrowserCameraPreviewFrame(image: previewImage))
		try? await Task.sleep(nanoseconds: 50_000_000)

		XCTAssertGreaterThanOrEqual(receivedEvents, 2)
		XCTAssertEqual(receivedEvents, receivedEventsBeforeRemoval)
		XCTAssertNil(coordinator.currentPreviewFrame())
	}

	func testUserDefaultsPreferencesStoreRoundTripsSavedPreferences() throws {
		let suiteName = "BrowserCameraSessionCoordinatorTests.\(UUID().uuidString)"
		let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
		let store = UserDefaultsBrowserCameraPreferencesStore(defaults: defaults)
		let preferences = BrowserCameraPreferences(
			routingEnabled: false,
			preferNavigatorCameraWhenPossible: false,
			preferredSourceID: "camera-b",
			preferredFilterPreset: .folia,
			previewEnabled: true
		)

		store.savePreferences(preferences)

		let restored = store.loadPreferences()
		XCTAssertEqual(restored.routingEnabled, false)
		XCTAssertEqual(restored.preferredDeviceID, "camera-b")
		XCTAssertFalse(restored.preferNavigatorCameraWhenPossible)
		XCTAssertEqual(restored.preferredFilterPreset, .folia)
		XCTAssertTrue(restored.previewEnabled)

		UserDefaultsBrowserCameraPreferencesStore.allKeys.forEach(defaults.removeObject(forKey:))
		defaults.removePersistentDomain(forName: suiteName)
	}

	func testLiveBrowserCameraDeviceProviderSmokeEnumeratesWithoutCrashing() {
		let devices = LiveBrowserCameraDeviceProvider().availableDevices()

		XCTAssertTrue(devices.allSatisfy { !$0.id.isEmpty && !$0.name.isEmpty })
	}

	func testConvenienceInitializerProducesSnapshotUsingLiveDependencies() {
		let defaults = UserDefaults.standard
		UserDefaultsBrowserCameraPreferencesStore.allKeys.forEach(defaults.removeObject(forKey:))

		let coordinator = BrowserCameraSessionCoordinator()
		let snapshot = coordinator.currentSnapshot()

		XCTAssertEqual(snapshot.routingSettings.preferredFilterPreset, .none)
		XCTAssertNotNil(snapshot.healthState)

		UserDefaultsBrowserCameraPreferencesStore.allKeys.forEach(defaults.removeObject(forKey:))
	}

	func testConvenienceInitializerDefaultsToSystemVirtualPublicationMode() {
		XCTAssertEqual(
			BrowserCameraSessionCoordinator.defaultPreferredManagedOutputMode,
			.systemVirtualCameraPublication
		)
	}

	func testSystemVirtualPublicationStaysIdleWithoutConsumersOnInitialization() {
		let captureController = StubCaptureController()
		let virtualPublisherController = StubVirtualPublisherController()
		let coordinator = BrowserCameraSessionCoordinator(
			deviceProvider: StubDeviceProvider(
				devices: [BrowserCameraDevice(id: "camera-a", name: "FaceTime HD", isDefault: true)]
			),
			preferencesStore: StubPreferencesStore(
				preferences: BrowserCameraPreferences(
					routingEnabled: true,
					preferNavigatorCameraWhenPossible: true,
					preferredSourceID: "camera-a",
					preferredFilterPreset: .none,
					previewEnabled: true
				)
			),
			captureController: captureController,
			virtualPublisherController: virtualPublisherController,
			preferredManagedOutputMode: .systemVirtualCameraPublication
		)

		let snapshot = coordinator.currentSnapshot()

		XCTAssertEqual(snapshot.lifecycleState, .idle)
		XCTAssertEqual(snapshot.outputMode, .processedNavigatorFeed)
		XCTAssertEqual(captureController.startConfigurations, [])
		XCTAssertEqual(virtualPublisherController.startConfigurations, [])
	}

	private func makeCoordinator(
		captureController: StubCaptureController = StubCaptureController(),
		virtualPublisherController: StubVirtualPublisherController = StubVirtualPublisherController(),
		previewFrameUpdater: BrowserCameraPreviewFrameUpdater = BrowserCameraPreviewFrameUpdater(mainQueue: .main),
		preferredManagedOutputMode: BrowserCameraOutputMode = .processedNavigatorFeed
	) -> BrowserCameraSessionCoordinator {
		BrowserCameraSessionCoordinator(
			deviceProvider: StubDeviceProvider(
				devices: [BrowserCameraDevice(id: "camera-a", name: "FaceTime HD", isDefault: true)]
			),
			preferencesStore: StubPreferencesStore(preferences: BrowserCameraPreferences()),
			captureController: captureController,
			virtualPublisherController: virtualPublisherController,
			previewFrameUpdater: previewFrameUpdater,
			preferredManagedOutputMode: preferredManagedOutputMode
		)
	}

	private func makeLiveConsumer(id: String) -> BrowserCameraConsumer {
		BrowserCameraConsumer(
			id: id,
			kind: .browserTabCapture,
			requiresLiveFrames: true
		)
	}
}

@MainActor
private struct StubDeviceProvider: BrowserCameraDeviceProviding {
	let devices: [BrowserCameraDevice]

	func availableDevices() -> [BrowserCameraDevice] {
		devices
	}
}

@MainActor
private final class SequencedDeviceProvider: BrowserCameraDeviceProviding {
	private let sequences: [[BrowserCameraDevice]]
	private(set) var availableDevicesCallCount = 0

	init(sequences: [[BrowserCameraDevice]]) {
		self.sequences = sequences
	}

	func availableDevices() -> [BrowserCameraDevice] {
		let index = min(availableDevicesCallCount, sequences.count - 1)
		availableDevicesCallCount += 1
		return sequences[index]
	}
}

@MainActor
private final class StubPreferencesStore: BrowserCameraPreferencesStoring {
	private(set) var preferences: BrowserCameraPreferences
	private(set) var savedPreferences: BrowserCameraPreferences?

	init(preferences: BrowserCameraPreferences) {
		self.preferences = preferences
	}

	func loadPreferences() -> BrowserCameraPreferences {
		preferences
	}

	func savePreferences(_ preferences: BrowserCameraPreferences) {
		savedPreferences = preferences
		self.preferences = preferences
	}

	func resetSavedPreferences() {
		savedPreferences = nil
	}
}

private final class StubCaptureController: BrowserCameraCaptureControlling {
	weak var delegate: (any BrowserCameraCaptureControllingDelegate)?

	private(set) var startConfigurations = [BrowserCameraCaptureConfiguration]()
	private(set) var updatedConfigurations = [BrowserCameraCaptureConfiguration]()
	private(set) var stopCount = 0

	func startCapture(with configuration: BrowserCameraCaptureConfiguration) {
		startConfigurations.append(configuration)
	}

	func updateCaptureConfiguration(_ configuration: BrowserCameraCaptureConfiguration) {
		updatedConfigurations.append(configuration)
	}

	func stopCapture() {
		stopCount += 1
	}

	@MainActor
	func send(_ event: BrowserCameraCaptureEvent) {
		delegate?.browserCameraCaptureControllerDidReceiveEvent(event)
	}

	@MainActor
	func sendVirtualPublisherFrame(_ frame: BrowserCameraVirtualOutputFrame) {
		delegate?.browserCameraCaptureControllerDidOutputVirtualPublisherFrame(
			data: frame.data,
			width: frame.width,
			height: frame.height,
			bytesPerRow: frame.bytesPerRow,
			pixelFormat: frame.pixelFormat,
			timestampHostTime: frame.timestampHostTime,
			durationHostTime: frame.durationHostTime
		)
	}
}

@MainActor
private final class StubVirtualPublisherController: BrowserCameraVirtualPublisherControlling {
	weak var delegate: (any BrowserCameraVirtualPublisherControllingDelegate)?

	private(set) var configureConfigurations = [BrowserCameraVirtualPublisherConfiguration]()
	private(set) var startConfigurations = [BrowserCameraVirtualPublisherConfiguration]()
	private(set) var publishedFrames = [BrowserCameraVirtualOutputFrame]()
	private(set) var stopCount = 0
	private var status = BrowserCameraVirtualPublisherStatus.notRequired
	private var configuredConfiguration: BrowserCameraVirtualPublisherConfiguration?

	func currentStatus() -> BrowserCameraVirtualPublisherStatus {
		status
	}

	func configurePublishing(with configuration: BrowserCameraVirtualPublisherConfiguration) {
		configuredConfiguration = configuration
		configureConfigurations.append(configuration)
		let nextStatus = BrowserCameraVirtualPublisherStatus(
			state: .idle,
			configuration: configuration,
			lastPublishedFrame: nil,
			lastErrorDescription: nil
		)
		guard status != nextStatus else { return }
		status = nextStatus
		delegate?.browserCameraVirtualPublisherControllerDidUpdateStatus(status)
	}

	func startPublishing() {
		guard let configuration = configuredConfiguration else { return }
		let nextStatus = BrowserCameraVirtualPublisherStatus(
			state: .installMissing,
			configuration: configuration,
			lastPublishedFrame: nil,
			lastErrorDescription: "System virtual camera publication is unavailable."
		)
		guard status != nextStatus else { return }
		startConfigurations.append(configuration)
		status = nextStatus
		delegate?.browserCameraVirtualPublisherControllerDidUpdateStatus(status)
	}

	func stopPublishing() {
		guard status != .notRequired else { return }
		stopCount += 1
		status = .notRequired
		delegate?.browserCameraVirtualPublisherControllerDidUpdateStatus(status)
	}

	func publishFrame(_ frame: BrowserCameraVirtualOutputFrame) async {
		publishedFrames.append(frame)
	}

	func publishFrame(
		data: Data,
		width: Int,
		height: Int,
		bytesPerRow: Int,
		pixelFormat: BrowserCameraVirtualPublisherPixelFormat,
		timestampHostTime: UInt64,
		durationHostTime: UInt64
	) async {
		await publishFrame(
			BrowserCameraVirtualOutputFrame(
				data: data,
				width: width,
				height: height,
				bytesPerRow: bytesPerRow,
				pixelFormat: pixelFormat,
				timestampHostTime: timestampHostTime,
				durationHostTime: durationHostTime
			)
		)
	}

	func sendStatus(_ status: BrowserCameraVirtualPublisherStatus) {
		self.status = status
		delegate?.browserCameraVirtualPublisherControllerDidUpdateStatus(status)
	}
}

private func makePreviewImage() -> CGImage {
	let colorSpace = CGColorSpaceCreateDeviceRGB()
	let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
	let bytesPerPixel = 4
	let width = 2
	let height = 2
	let bytesPerRow = width * bytesPerPixel
	let bytes: [UInt8] = [
		0x2A, 0x6A, 0xAA, 0xFF,
		0x2A, 0x6A, 0xAA, 0xFF,
		0x2A, 0x6A, 0xAA, 0xFF,
		0x2A, 0x6A, 0xAA, 0xFF,
	]
	let provider = CGDataProvider(data: Data(bytes) as CFData)!
	return CGImage(
		width: width,
		height: height,
		bitsPerComponent: 8,
		bitsPerPixel: 32,
		bytesPerRow: bytesPerRow,
		space: colorSpace,
		bitmapInfo: bitmapInfo,
		provider: provider,
		decode: nil,
		shouldInterpolate: false,
		intent: .defaultIntent
	)!
}
