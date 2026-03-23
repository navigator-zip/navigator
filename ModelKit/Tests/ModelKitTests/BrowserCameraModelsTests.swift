import ModelKit
import XCTest

final class BrowserCameraModelsTests: XCTestCase {
	func testFilterPresetCasesMatchExpectedOrder() {
		XCTAssertEqual(
			BrowserCameraFilterPreset.allCases,
			[
				.none,
				.monochrome,
				.dither,
				.folia,
				.supergold,
				.tonachrome,
				.bubblegum,
				.darkroom,
				.glowInTheDark,
				.habenero,
			]
		)
	}

	func testConsumerKindFlagsDistinguishLiveFrameAndPreviewConsumers() {
		XCTAssertTrue(BrowserCameraConsumerKind.browserTabCapture.requiresLiveFrames)
		XCTAssertFalse(BrowserCameraConsumerKind.browserTabCapture.isPreviewConsumer)
		XCTAssertFalse(BrowserCameraConsumerKind.browserPreview.requiresLiveFrames)
		XCTAssertTrue(BrowserCameraConsumerKind.browserPreview.isPreviewConsumer)
		XCTAssertFalse(BrowserCameraConsumerKind.menuBarPreview.requiresLiveFrames)
		XCTAssertTrue(BrowserCameraConsumerKind.menuBarPreview.isPreviewConsumer)
	}

	func testSourceStoresIdentityNameAndDefaultFlag() {
		let source = BrowserCameraSource(
			id: "camera-main",
			name: "FaceTime HD Camera",
			isDefault: true
		)
		let legacyDevice: BrowserCameraDevice = source

		XCTAssertEqual(source.id, "camera-main")
		XCTAssertEqual(source.name, "FaceTime HD Camera")
		XCTAssertTrue(source.isDefault)
		XCTAssertEqual(legacyDevice, source)
	}

	func testRoutingSettingsDefaultAndLegacyInitializersStayAligned() {
		var settings = BrowserCameraRoutingSettings()
		let legacySettings: BrowserCameraPreferences = .init(
			routingEnabled: false,
			preferredDeviceID: "camera-secondary",
			preferNavigatorCameraWhenPossible: false
		)

		XCTAssertEqual(settings, .defaults)
		XCTAssertTrue(settings.routingEnabled)
		XCTAssertTrue(settings.preferNavigatorCameraWhenPossible)
		XCTAssertNil(settings.preferredSourceID)
		XCTAssertEqual(settings.preferredFilterPreset, .none)
		XCTAssertFalse(settings.prefersHorizontalFlip)
		XCTAssertFalse(settings.previewEnabled)

		settings.preferredDeviceID = "camera-main"

		XCTAssertEqual(settings.preferredSourceID, "camera-main")
		XCTAssertEqual(settings.preferredDeviceID, "camera-main")
		XCTAssertFalse(legacySettings.routingEnabled)
		XCTAssertFalse(legacySettings.preferNavigatorCameraWhenPossible)
		XCTAssertEqual(legacySettings.preferredSourceID, "camera-secondary")
		XCTAssertEqual(legacySettings.preferredFilterPreset, .none)
		XCTAssertFalse(legacySettings.previewEnabled)
	}

	func testRoutingSettingsCustomInitializerStoresAllFields() {
		let settings = BrowserCameraRoutingSettings(
			routingEnabled: true,
			preferNavigatorCameraWhenPossible: false,
			preferredSourceID: "camera-main",
			preferredFilterPreset: .folia,
			previewEnabled: true
		)

		XCTAssertTrue(settings.routingEnabled)
		XCTAssertFalse(settings.preferNavigatorCameraWhenPossible)
		XCTAssertEqual(settings.preferredSourceID, "camera-main")
		XCTAssertEqual(settings.preferredDeviceID, "camera-main")
		XCTAssertEqual(settings.preferredFilterPreset, .folia)
		XCTAssertFalse(settings.prefersHorizontalFlip)
		XCTAssertTrue(settings.previewEnabled)
	}

	func testLegacyConsumerRetainsExplicitLiveFrameRequirement() {
		let consumer = BrowserCameraConsumer(
			id: "preview-1",
			kind: .browserPreview,
			requiresLiveFrames: true
		)

		XCTAssertEqual(consumer.id, "preview-1")
		XCTAssertEqual(consumer.kind, .browserPreview)
		XCTAssertTrue(consumer.requiresLiveFrames)
	}

	func testManagedFramePayloadStoresIdentityGeometryAndDataURL() throws {
		let payload = BrowserCameraManagedFramePayload(
			sequence: 7,
			width: 1280,
			height: 720,
			imageDataURL: "data:image/jpeg;base64,Zm9v"
		)
		let decoded = try JSONDecoder().decode(
			BrowserCameraManagedFramePayload.self,
			from: JSONEncoder().encode(payload)
		)

		XCTAssertEqual(payload.sequence, 7)
		XCTAssertEqual(payload.width, 1280)
		XCTAssertEqual(payload.height, 720)
		XCTAssertEqual(payload.imageDataURL, "data:image/jpeg;base64,Zm9v")
		XCTAssertEqual(decoded, payload)
	}

	func testRoutingConfigurationCapturesLegacyAndSettingsBackedInputs() {
		let settings = BrowserCameraRoutingSettings(
			routingEnabled: true,
			preferNavigatorCameraWhenPossible: true,
			preferredSourceID: "camera-main",
			preferredFilterPreset: .supergold,
			previewEnabled: true
		)

		let fullConfiguration = BrowserCameraRoutingConfiguration(
			isRoutingEnabled: false,
			preferredDeviceID: "camera-secondary",
			preferNavigatorCameraWhenPossible: false,
			preferredFilterPreset: .vertichrome,
			previewEnabled: true,
			outputMode: .systemVirtualCameraPublication
		)
		let legacyConfiguration = BrowserCameraRoutingConfiguration(
			isRoutingEnabled: true,
			preferredDeviceID: "camera-main",
			preferNavigatorCameraWhenPossible: true,
			outputMode: .directPhysicalCapture
		)
		let settingsBackedConfiguration = BrowserCameraRoutingConfiguration(
			settings: settings,
			outputMode: .processedNavigatorFeed
		)

		XCTAssertFalse(fullConfiguration.isRoutingEnabled)
		XCTAssertEqual(fullConfiguration.preferredDeviceID, "camera-secondary")
		XCTAssertFalse(fullConfiguration.preferNavigatorCameraWhenPossible)
		XCTAssertEqual(fullConfiguration.preferredFilterPreset, .vertichrome)
		XCTAssertTrue(fullConfiguration.previewEnabled)
		XCTAssertEqual(fullConfiguration.outputMode, .systemVirtualCameraPublication)

		XCTAssertTrue(legacyConfiguration.isRoutingEnabled)
		XCTAssertEqual(legacyConfiguration.preferredFilterPreset, .none)
		XCTAssertFalse(legacyConfiguration.previewEnabled)
		XCTAssertEqual(legacyConfiguration.outputMode, .directPhysicalCapture)

		XCTAssertEqual(settingsBackedConfiguration.settings, settings)
		XCTAssertEqual(settingsBackedConfiguration.outputMode, .processedNavigatorFeed)
	}

	func testPerformanceMetricsStoresLatencyAndFrameCounts() {
		let metrics = BrowserCameraPerformanceMetrics(
			processedFrameCount: 42,
			droppedFrameCount: 3,
			firstFrameLatencyMilliseconds: 84.5,
			averageProcessingLatencyMilliseconds: 18.5,
			lastProcessingLatencyMilliseconds: 21.25,
			realtimeBudgetExceeded: true
		)

		XCTAssertEqual(metrics.processedFrameCount, 42)
		XCTAssertEqual(metrics.droppedFrameCount, 3)
		XCTAssertEqual(metrics.firstFrameLatencyMilliseconds, 84.5)
		XCTAssertEqual(metrics.averageProcessingLatencyMilliseconds, 18.5)
		XCTAssertEqual(metrics.lastProcessingLatencyMilliseconds, 21.25)
		XCTAssertTrue(metrics.realtimeBudgetExceeded)
	}

	func testSessionSnapshotRetainsRecentDiagnosticEventsInDebugSummaryAndRoundTrip() throws {
		let recentEvents = [
			BrowserCameraDiagnosticEvent(
				kind: .routingChanged,
				detail: "routingEnabled=true"
			),
			BrowserCameraDiagnosticEvent(
				kind: .captureStarted,
				detail: "deviceID=camera-main"
			),
		]
		let browserTransportStates = [
			BrowserCameraBrowserTransportState(
				tabID: "tab-b",
				routingTransportMode: .browserProcessJavaScriptFallback,
				frameTransportMode: .browserProcessJavaScriptFallback,
				activeManagedTrackCount: 0
			),
			BrowserCameraBrowserTransportState(
				tabID: "tab-a",
				routingTransportMode: .rendererProcessMessages,
				frameTransportMode: .rendererProcessMessages,
				activeManagedTrackCount: 1
			),
		]
		let pipelineRuntimeState = BrowserCameraPipelineRuntimeState(
			preset: .folia,
			implementation: .aperture,
			warmupProfile: .chromaticFolia,
			grainPresence: .normal,
			requiredFilterCount: 7
		)
		let snapshot = BrowserCameraSessionSnapshot(
			lifecycleState: .running,
			healthState: .healthy,
			outputMode: .processedNavigatorFeed,
			routingSettings: BrowserCameraRoutingSettings(
				routingEnabled: true,
				preferNavigatorCameraWhenPossible: true,
				preferredSourceID: "camera-main",
				preferredFilterPreset: .folia,
				previewEnabled: true
			),
			availableSources: [
				BrowserCameraSource(id: "camera-main", name: "FaceTime HD Camera", isDefault: true),
			],
			activeConsumersByID: [
				"tab-1": BrowserCameraConsumer(
					id: "tab-1",
					kind: .browserTabCapture,
					requiresLiveFrames: true
				),
			],
			performanceMetrics: BrowserCameraPerformanceMetrics(
				processedFrameCount: 12,
				droppedFrameCount: 1,
				firstFrameLatencyMilliseconds: 82.0,
				averageProcessingLatencyMilliseconds: 10.5,
				lastProcessingLatencyMilliseconds: 10.0,
				realtimeBudgetExceeded: false
			),
			lastErrorDescription: nil,
			publisherStatus: .notRequired,
			pipelineRuntimeState: pipelineRuntimeState,
			browserTransportStates: browserTransportStates,
			recentDiagnosticEvents: recentEvents
		)

		let decoded = try JSONDecoder().decode(
			BrowserCameraSessionSnapshot.self,
			from: JSONEncoder().encode(snapshot)
		)

		XCTAssertEqual(snapshot.recentDiagnosticEvents, recentEvents)
		XCTAssertEqual(snapshot.debugSummary.recentDiagnosticEvents, recentEvents)
		XCTAssertEqual(snapshot.pipelineRuntimeState, pipelineRuntimeState)
		XCTAssertEqual(snapshot.debugSummary.pipelineRuntimeState, pipelineRuntimeState)
		XCTAssertEqual(snapshot.browserTransportStates.map(\.tabID), ["tab-a", "tab-b"])
		XCTAssertEqual(snapshot.debugSummary.browserTransportStates.map(\.tabID), ["tab-a", "tab-b"])
		XCTAssertEqual(decoded.recentDiagnosticEvents, recentEvents)
		XCTAssertEqual(decoded.pipelineRuntimeState, pipelineRuntimeState)
		XCTAssertEqual(decoded.browserTransportStates.map(\.tabID), ["tab-a", "tab-b"])
		XCTAssertEqual(decoded.debugSummary.recentDiagnosticEvents, recentEvents)
		XCTAssertEqual(decoded.debugSummary.pipelineRuntimeState, pipelineRuntimeState)
	}

	func testSessionSnapshotComputesIdentityTrackedConsumersAndCompatibilityViews() throws {
		let settings = BrowserCameraRoutingSettings(
			routingEnabled: true,
			preferNavigatorCameraWhenPossible: true,
			preferredSourceID: "camera-main",
			preferredFilterPreset: .mononoke,
			previewEnabled: true
		)
		let sources = [
			BrowserCameraSource(id: "camera-main", name: "FaceTime HD Camera", isDefault: true),
			BrowserCameraSource(id: "camera-external", name: "Continuity Camera", isDefault: false),
		]
		let snapshot = BrowserCameraSessionSnapshot(
			lifecycleState: .running,
			healthState: .healthy,
			outputMode: .processedNavigatorFeed,
			routingSettings: settings,
			availableSources: sources,
			activeConsumersByID: [
				"browser-tab-2": BrowserCameraConsumer(
					id: "browser-tab-2",
					kind: .browserTabCapture,
					requiresLiveFrames: true
				),
				"menu-bar-1": BrowserCameraConsumer(
					id: "menu-bar-1",
					kind: .menuBarPreview,
					requiresLiveFrames: false
				),
				"browser-preview-1": BrowserCameraConsumer(
					id: "browser-preview-1",
					kind: .browserPreview,
					requiresLiveFrames: true
				),
			],
			lastErrorDescription: "pipeline fallback"
		)
		let roundTrippedSnapshot = try JSONDecoder().decode(
			BrowserCameraSessionSnapshot.self,
			from: JSONEncoder().encode(snapshot)
		)

		XCTAssertEqual(snapshot.lifecycleState, .running)
		XCTAssertEqual(snapshot.healthState, .healthy)
		XCTAssertEqual(snapshot.outputMode, .processedNavigatorFeed)
		XCTAssertEqual(snapshot.routingSettings, settings)
		XCTAssertEqual(snapshot.availableSources, sources)
		XCTAssertEqual(snapshot.availableDevices, sources)
		XCTAssertEqual(
			snapshot.routingConfiguration,
			BrowserCameraRoutingConfiguration(
				settings: settings,
				outputMode: .processedNavigatorFeed
			)
		)
		XCTAssertEqual(snapshot.activeLiveFrameConsumerIDs, ["browser-preview-1", "browser-tab-2"])
		XCTAssertEqual(
			snapshot.activePreviewConsumerIDs,
			["menu-bar-1"]
		)
		XCTAssertEqual(snapshot.liveFrameConsumerCount, 2)
		XCTAssertEqual(snapshot.previewConsumerCount, 1)
		XCTAssertTrue(snapshot.hasActiveConsumers)
		XCTAssertEqual(snapshot.performanceMetrics, .empty)
		XCTAssertEqual(
			snapshot.activeConsumers,
			[
				BrowserCameraConsumer(
					id: "browser-preview-1",
					kind: .browserPreview,
					requiresLiveFrames: true
				),
				BrowserCameraConsumer(
					id: "browser-tab-2",
					kind: .browserTabCapture,
					requiresLiveFrames: true
				),
				BrowserCameraConsumer(
					id: "menu-bar-1",
					kind: .menuBarPreview,
					requiresLiveFrames: false
				),
			]
		)
		XCTAssertEqual(snapshot.lastErrorDescription, "pipeline fallback")
		XCTAssertEqual(snapshot.debugSummary.selectedSourceID, "camera-main")
		XCTAssertEqual(snapshot.debugSummary.selectedSourceName, "FaceTime HD Camera")
		XCTAssertEqual(snapshot.debugSummary.selectedFilterPreset, .mononoke)
		XCTAssertEqual(snapshot.debugSummary.activeLiveFrameConsumerIDs, ["browser-preview-1", "browser-tab-2"])
		XCTAssertEqual(snapshot.debugSummary.activePreviewConsumerIDs, ["menu-bar-1"])
		XCTAssertEqual(snapshot.debugSummary.performanceMetrics, .empty)
		XCTAssertEqual(snapshot.debugSummary.lastErrorDescription, "pipeline fallback")
		XCTAssertEqual(snapshot.debugSummary.publisherStatus, .notRequired)
		XCTAssertFalse(snapshot.debugSummary.publisherReachable)
		XCTAssertTrue(snapshot.debugSummary.browserTransportStates.isEmpty)
		XCTAssertEqual(snapshot.publisherStatus, .notRequired)
		XCTAssertEqual(roundTrippedSnapshot, snapshot)
	}

	func testSessionSnapshotCarriesPerformanceMetricsThroughCoding() throws {
		let snapshot = BrowserCameraSessionSnapshot(
			lifecycleState: .running,
			healthState: .healthy,
			outputMode: .systemVirtualCameraPublication,
			routingSettings: BrowserCameraRoutingSettings(
				routingEnabled: true,
				preferNavigatorCameraWhenPossible: true,
				preferredSourceID: "camera-main",
				preferredFilterPreset: .vertichrome,
				previewEnabled: false
			),
			availableSources: [
				BrowserCameraSource(id: "camera-main", name: "FaceTime HD Camera", isDefault: true),
			],
			activeConsumersByID: [:],
			performanceMetrics: BrowserCameraPerformanceMetrics(
				processedFrameCount: 120,
				droppedFrameCount: 5,
				firstFrameLatencyMilliseconds: 88.75,
				averageProcessingLatencyMilliseconds: 14.2,
				lastProcessingLatencyMilliseconds: 13.4,
				realtimeBudgetExceeded: false
			),
			lastErrorDescription: nil
		)
		let decoded = try JSONDecoder().decode(
			BrowserCameraSessionSnapshot.self,
			from: JSONEncoder().encode(snapshot)
		)

		XCTAssertEqual(decoded.performanceMetrics.processedFrameCount, 120)
		XCTAssertEqual(decoded.performanceMetrics.droppedFrameCount, 5)
		XCTAssertEqual(decoded.performanceMetrics.firstFrameLatencyMilliseconds, 88.75)
		XCTAssertEqual(decoded.performanceMetrics.averageProcessingLatencyMilliseconds, 14.2)
		XCTAssertEqual(decoded.performanceMetrics.lastProcessingLatencyMilliseconds, 13.4)
		XCTAssertFalse(decoded.performanceMetrics.realtimeBudgetExceeded)
		XCTAssertEqual(decoded.publisherStatus.state, .ready)
		XCTAssertTrue(decoded.debugSummary.publisherReachable)
	}

	func testPerformanceMetricsLegacyDecodingDefaultsOptionalValuesAndBudgetFlag() throws {
		let legacyJSON = """
		{
		  "processedFrameCount" : 4,
		  "droppedFrameCount" : 1
		}
		"""

		let metrics = try JSONDecoder().decode(
			BrowserCameraPerformanceMetrics.self,
			from: XCTUnwrap(legacyJSON.data(using: .utf8))
		)

		XCTAssertEqual(metrics.processedFrameCount, 4)
		XCTAssertEqual(metrics.droppedFrameCount, 1)
		XCTAssertNil(metrics.firstFrameLatencyMilliseconds)
		XCTAssertNil(metrics.averageProcessingLatencyMilliseconds)
		XCTAssertNil(metrics.lastProcessingLatencyMilliseconds)
		XCTAssertFalse(metrics.realtimeBudgetExceeded)
	}

	func testPerformanceMetricsDecodingEmptyPayloadDefaultsCountsToZero() throws {
		let metrics = try JSONDecoder().decode(
			BrowserCameraPerformanceMetrics.self,
			from: XCTUnwrap("{}".data(using: .utf8))
		)

		XCTAssertEqual(metrics.processedFrameCount, 0)
		XCTAssertEqual(metrics.droppedFrameCount, 0)
	}

	func testDebugSummaryMarksPublisherUnreachableWhenPublishedOutputIsUnavailable() {
		let snapshot = BrowserCameraSessionSnapshot(
			lifecycleState: .failed,
			healthState: .publisherUnavailable,
			outputMode: .systemVirtualCameraPublication,
			routingSettings: BrowserCameraRoutingSettings(
				routingEnabled: true,
				preferNavigatorCameraWhenPossible: true,
				preferredSourceID: "camera-main",
				preferredFilterPreset: .supergold,
				previewEnabled: false
			),
			availableSources: [
				BrowserCameraSource(id: "camera-main", name: "FaceTime HD Camera", isDefault: true),
			],
			activeConsumerKindsByID: [
				"tab-1": .browserTabCapture,
			],
			performanceMetrics: BrowserCameraPerformanceMetrics(
				processedFrameCount: 0,
				droppedFrameCount: 0,
				firstFrameLatencyMilliseconds: nil,
				averageProcessingLatencyMilliseconds: nil,
				lastProcessingLatencyMilliseconds: nil,
				realtimeBudgetExceeded: false
			),
			lastErrorDescription: "publisher unavailable"
		)

		XCTAssertFalse(snapshot.debugSummary.publisherReachable)
		XCTAssertEqual(snapshot.debugSummary.selectedSourceName, "FaceTime HD Camera")
		XCTAssertEqual(snapshot.publisherStatus.state, .unavailable)
		XCTAssertEqual(snapshot.publisherStatus.lastErrorDescription, "publisher unavailable")
	}

	func testSessionSnapshotDecodesLegacyConsumerKindsPayload() throws {
		let legacyJSON = """
		{
		  "activeConsumerKindsByID" : {
		    "browser-tab-1" : "browserTabCapture",
		    "preview-1" : "browserPreview"
		  },
		  "availableSources" : [
		    {
		      "id" : "camera-main",
		      "isDefault" : true,
		      "name" : "FaceTime HD Camera"
		    }
		  ],
		  "healthState" : "healthy",
		  "lastErrorDescription" : null,
		  "lifecycleState" : "running",
		  "outputMode" : "processedNavigatorFeed",
		  "routingSettings" : {
		    "preferNavigatorCameraWhenPossible" : true,
		    "preferredFilterPreset" : "folia",
		    "preferredSourceID" : "camera-main",
		    "previewEnabled" : true,
		    "routingEnabled" : true
		  }
		}
		"""
		let snapshot = try JSONDecoder().decode(
			BrowserCameraSessionSnapshot.self,
			from: XCTUnwrap(legacyJSON.data(using: .utf8))
		)

		XCTAssertEqual(
			snapshot.activeConsumers,
			[
				BrowserCameraConsumer(
					id: "browser-tab-1",
					kind: .browserTabCapture,
					requiresLiveFrames: true
				),
				BrowserCameraConsumer(
					id: "preview-1",
					kind: .browserPreview,
					requiresLiveFrames: false
				),
			]
		)
		XCTAssertEqual(snapshot.activeLiveFrameConsumerIDs, ["browser-tab-1"])
		XCTAssertEqual(snapshot.activePreviewConsumerIDs, ["preview-1"])
		XCTAssertEqual(snapshot.publisherStatus, .notRequired)
	}

	func testSessionSnapshotDecodesMissingLegacyConsumerKindsAsEmpty() throws {
		let json = """
		{
		  "availableSources" : [],
		  "healthState" : "healthy",
		  "lifecycleState" : "idle",
		  "outputMode" : "unavailable",
		  "routingSettings" : {
		    "preferNavigatorCameraWhenPossible" : true,
		    "preferredFilterPreset" : "none",
		    "preferredSourceID" : null,
		    "previewEnabled" : false,
		    "routingEnabled" : true
		  }
		}
		"""

		let snapshot = try JSONDecoder().decode(
			BrowserCameraSessionSnapshot.self,
			from: XCTUnwrap(json.data(using: .utf8))
		)

		XCTAssertTrue(snapshot.activeConsumers.isEmpty)
	}

	func testSessionSnapshotDecodesMissingPublisherStatusUsingLegacyPublishedState() throws {
		let json = """
		{
		  "availableSources" : [],
		  "healthState" : "publisherUnavailable",
		  "lifecycleState" : "failed",
		  "outputMode" : "systemVirtualCameraPublication",
		  "routingSettings" : {
		    "preferNavigatorCameraWhenPossible" : true,
		    "preferredFilterPreset" : "none",
		    "preferredSourceID" : null,
		    "previewEnabled" : false,
		    "routingEnabled" : true
		  },
		  "lastErrorDescription" : "publisher missing"
		}
		"""

		let snapshot = try JSONDecoder().decode(
			BrowserCameraSessionSnapshot.self,
			from: XCTUnwrap(json.data(using: .utf8))
		)

		XCTAssertEqual(snapshot.publisherStatus.state, .unavailable)
		XCTAssertEqual(snapshot.publisherStatus.lastErrorDescription, "publisher missing")
		XCTAssertFalse(snapshot.publisherReachable)
	}

	func testLegacyConsumerKindsInitializerDefaultsPerformanceMetrics() {
		let snapshot = BrowserCameraSessionSnapshot(
			lifecycleState: .starting,
			healthState: .healthy,
			outputMode: .processedNavigatorFeed,
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
			activeConsumerKindsByID: [
				"tab-1": .browserTabCapture,
			],
			lastErrorDescription: nil
		)

		XCTAssertEqual(snapshot.performanceMetrics, .empty)
		XCTAssertEqual(snapshot.activeLiveFrameConsumerIDs, ["tab-1"])
	}

	func testLegacySessionSnapshotInitializerBridgesOlderConfigurationShapes() {
		let configuration = BrowserCameraRoutingConfiguration(
			isRoutingEnabled: true,
			preferredDeviceID: "camera-main",
			preferNavigatorCameraWhenPossible: true,
			outputMode: .directPhysicalCapture
		)
		let sources = [
			BrowserCameraSource(id: "camera-main", name: "FaceTime HD Camera", isDefault: true),
		]
		let snapshot = BrowserCameraSessionSnapshot(
			lifecycleState: .starting,
			healthState: .degraded,
			outputMode: .directPhysicalCapture,
			routingConfiguration: configuration,
			availableDevices: sources,
			activeConsumers: [
				BrowserCameraConsumer(
					id: "menu-bar-1",
					kind: .menuBarPreview,
					requiresLiveFrames: false
				),
				BrowserCameraConsumer(
					id: "browser-tab-1",
					kind: .browserTabCapture,
					requiresLiveFrames: true
				),
			],
			liveFrameConsumerCount: 99,
			previewConsumerCount: 42,
			lastErrorDescription: nil
		)
		let emptySnapshot = BrowserCameraSessionSnapshot(
			lifecycleState: .idle,
			healthState: .publisherUnavailable,
			outputMode: .unavailable,
			routingSettings: .defaults,
			availableSources: [],
			activeConsumersByID: [:],
			lastErrorDescription: "publisher missing"
		)

		XCTAssertEqual(snapshot.routingSettings, configuration.settings)
		XCTAssertEqual(snapshot.availableSources, sources)
		XCTAssertEqual(
			snapshot.activeConsumerKindsByID,
			[
				"browser-tab-1": .browserTabCapture,
				"menu-bar-1": .menuBarPreview,
			]
		)
		XCTAssertEqual(snapshot.liveFrameConsumerCount, 1)
		XCTAssertEqual(snapshot.previewConsumerCount, 1)
		XCTAssertEqual(snapshot.activeLiveFrameConsumerIDs, ["browser-tab-1"])
		XCTAssertEqual(snapshot.activePreviewConsumerIDs, ["menu-bar-1"])
		XCTAssertEqual(emptySnapshot.activeConsumers, [])
		XCTAssertFalse(emptySnapshot.hasActiveConsumers)
		XCTAssertEqual(emptySnapshot.liveFrameConsumerCount, 0)
		XCTAssertEqual(emptySnapshot.previewConsumerCount, 0)
		XCTAssertEqual(emptySnapshot.lastErrorDescription, "publisher missing")
	}
}
