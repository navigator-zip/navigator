@testable import BrowserView
import ModelKit
import XCTest

final class BrowserCameraRoutingJavaScriptTests: XCTestCase {
	func testInstallScriptEmbedsRoutingConfigurationAndShimMetadata() {
		let snapshot = BrowserCameraSessionSnapshot(
			lifecycleState: .running,
			healthState: .healthy,
			outputMode: .directPhysicalCapture,
			routingSettings: BrowserCameraRoutingSettings(
				routingEnabled: true,
				preferNavigatorCameraWhenPossible: true,
				preferredSourceID: "camera-a",
				preferredFilterPreset: .folia,
				prefersHorizontalFlip: true,
				previewEnabled: false
			),
			availableSources: [
				BrowserCameraSource(
					id: "camera-a",
					name: "FaceTime HD",
					isDefault: true
				),
			],
			activeConsumersByID: [
				"tab-1": BrowserCameraConsumer(
					id: "tab-1",
					kind: .browserTabCapture,
					requiresLiveFrames: true
				),
			],
			performanceMetrics: .empty,
			lastErrorDescription: nil,
			publisherStatus: BrowserCameraVirtualPublisherStatus(
				state: .idle,
				configuration: BrowserCameraVirtualPublisherConfiguration(
					sourceDeviceID: "camera-a",
					filterPreset: .folia,
					frameWidth: 1280,
					frameHeight: 720,
					nominalFramesPerSecond: 30,
					pixelFormat: .bgra8888,
					backpressurePolicy: .dropOldest,
					transportMode: .inProcess
				),
				lastPublishedFrame: nil,
				lastErrorDescription: nil
			)
		)

		let script = BrowserCameraRoutingJavaScript.makeInstallScript(from: snapshot)

		XCTAssertTrue(script.contains(BrowserCameraRoutingScriptConstants.shimKey))
		XCTAssertTrue(script.contains("\"failClosedOnManagedVideoRequest\":false"))
		XCTAssertTrue(script.contains("\"genericVideoUsesManagedOutput\":false"))
		XCTAssertTrue(script.contains("\"managedRoutingAvailability\":\"directPhysicalCapture\""))
		XCTAssertTrue(script.contains("\"preferNavigatorCameraWhenPossible\":true"))
		XCTAssertTrue(script.contains("\"preferredSourceID\":\"camera-a\""))
		XCTAssertTrue(script.contains("\"preferredFilterPreset\":\"folia\""))
		XCTAssertTrue(script.contains("\"prefersHorizontalFlip\":true"))
		XCTAssertTrue(script.contains("\"routingEnabled\":true"))
		XCTAssertTrue(script.contains("\"publisherState\":\"idle\""))
		XCTAssertTrue(script.contains("\"publisherTransportMode\":\"inProcess\""))
		XCTAssertTrue(script.contains("\"exposesManagedDeviceIdentity\":false"))
		XCTAssertTrue(script.contains("requiresManagedVideoRouting(constraints, config)"))
		XCTAssertTrue(script.contains("requestsManagedDevice(videoConstraints, config)"))
		XCTAssertTrue(script.contains("explicitBypassedDeviceIDs(constraints, config)"))
		XCTAssertTrue(script.contains("normalizedDeviceConstraintValues(deviceConstraint)"))
		XCTAssertTrue(script.contains(BrowserCameraRoutingScriptConstants.routingChangeEventName))
		XCTAssertTrue(
			script.contains(
				"const cameraRoutingEventPromptMessage = \"\(BrowserCameraRoutingScriptConstants.cameraRoutingEventPromptMessage)\";"
			)
		)
		XCTAssertTrue(script.contains("window.dispatchEvent(new CustomEvent"))
		XCTAssertTrue(script.contains("dispatchDeviceChangeIfNeeded(previousConfig, nextConfig)"))
		XCTAssertTrue(script.contains("mediaDevices.dispatchEvent(new Event(\"devicechange\"))"))
		XCTAssertTrue(script.contains("activeManagedConfig(fallbackConfig)"))
		XCTAssertTrue(script.contains("function emitCameraRoutingEvent(eventName, state, config, overrides)"))
		XCTAssertTrue(
			script.contains(
				"const nativeCameraRoutingEventBridgeKey = \"\(BrowserCameraRoutingScriptConstants.nativeEventBridgeKey)\";"
			)
		)
		XCTAssertTrue(script.contains("const nativeBridge = window[nativeCameraRoutingEventBridgeKey];"))
		XCTAssertTrue(script.contains("if (nativeBridge(payloadJSON) !== false)"))
		XCTAssertTrue(script.contains("window.prompt(cameraRoutingEventPromptMessage, payloadJSON);"))
		XCTAssertTrue(script.contains("function routingErrorDescription(error)"))
		XCTAssertTrue(script.contains("applyConfig: function(updatedConfig)"))
		XCTAssertTrue(script.contains("assignManagedRoutingMetadata(target, metadata)"))
		XCTAssertTrue(script.contains("makeManagedRoutingMetadata(config, overrides)"))
		XCTAssertTrue(script.contains("nextManagedIdentity(state, sequenceKey, prefix)"))
		XCTAssertTrue(script.contains("getConfig: function()"))
		XCTAssertTrue(script.contains("managedFrameStateKey"))
		XCTAssertTrue(script.contains("ensureManagedFrameState()"))
		XCTAssertTrue(script.contains("activeManagedTrackCount: 0"))
		XCTAssertTrue(script.contains("nextManagedTrackSequence: 0"))
		XCTAssertTrue(script.contains("nextManagedStreamSequence: 0"))
		XCTAssertTrue(script.contains("receiveFrame: function(frame)"))
		XCTAssertTrue(script.contains("clearFrame: function()"))
		XCTAssertTrue(script.contains("getManagedStream: function(constraints)"))
		XCTAssertTrue(script.contains("captureStream(30)"))
		XCTAssertTrue(script.contains("new MediaStream()"))
		XCTAssertTrue(script.contains("mediaDevices.enumerateDevices = function()"))
		XCTAssertTrue(script.contains("annotateEnumeratedVideoDevice(device, activeConfig)"))
		XCTAssertTrue(script.contains("makeManagedDeviceEnumerationEntry(activeConfig)"))
		XCTAssertTrue(script.contains("decorateManagedVideoTrack(track, config)"))
		XCTAssertTrue(script.contains("decorateManagedStream(stream, config)"))
		XCTAssertTrue(script.contains("makeManagedTrackConstraintError()"))
		XCTAssertTrue(script.contains("managedPermissionProbeConstraints(constraints, config)"))
		XCTAssertTrue(script.contains("stopStreamTracks(stream, trackKind)"))
		XCTAssertTrue(script.contains("kind: \"track\""))
		XCTAssertTrue(script.contains("kind: \"stream\""))
		XCTAssertTrue(script.contains("managedTrackID: managedTrackID"))
		XCTAssertTrue(script.contains("managedStreamID: managedStreamID"))
		XCTAssertTrue(script.contains("track.clone = function()"))
		XCTAssertTrue(script.contains("track.stop = function()"))
		XCTAssertTrue(script.contains("function markManagedTrackStopped(eventName)"))
		XCTAssertTrue(script.contains("emitCameraRoutingEvent("))
		XCTAssertTrue(script.contains("\"track-started\""))
		XCTAssertTrue(script.contains("\"explicit-device-bypassed\""))
		XCTAssertTrue(script.contains("\"managed-track-device-switch-rejected\""))
		XCTAssertTrue(script.contains("markManagedTrackStopped(\"track-stopped\");"))
		XCTAssertTrue(script.contains("track.addEventListener(\"ended\", function()"))
		XCTAssertTrue(script.contains("markManagedTrackStopped(\"track-ended\");"))
		XCTAssertTrue(script.contains("stream.getVideoTracks = function()"))
		XCTAssertTrue(script.contains("stream.getTracks = function()"))
		XCTAssertTrue(script.contains("stream.clone = function()"))
		XCTAssertTrue(script.contains("track.__navigatorCameraRoutingTrackStopped"))
		XCTAssertTrue(script.contains("state.activeManagedTrackCount = Math.max(0"))
		XCTAssertTrue(script.contains("managedDeviceID: config.managedDeviceID || \"\""))
		XCTAssertTrue(script.contains("managedRoutingAvailability: config.managedRoutingAvailability"))
		XCTAssertTrue(script.contains("publisherState: config.publisherState"))
		XCTAssertTrue(script.contains("publisherTransportMode: config.publisherTransportMode || null"))
		XCTAssertTrue(script.contains("requestedDeviceIDs: null"))
		XCTAssertTrue(script.contains("track.getSettings = function()"))
		XCTAssertTrue(script.contains("track.getConstraints = function()"))
		XCTAssertTrue(script.contains("track.applyConstraints = function(nextConstraints)"))
		XCTAssertTrue(script.contains("const resolvedConfig = activeManagedConfig(config);"))
		XCTAssertTrue(script.contains("requestedDeviceIDs: requestedDeviceIDs"))
		XCTAssertTrue(script.contains("return decorateManagedVideoTrack("))
		XCTAssertTrue(script.contains("return decorateManagedStream("))
		XCTAssertTrue(script.contains("const constraintError = makeManagedTrackConstraintError();"))
		XCTAssertTrue(script.contains("return Promise.reject(constraintError)"))
		XCTAssertTrue(script.contains("delete forwardedConstraints.deviceId;"))
		XCTAssertTrue(script.contains("return \"installed\";"))
		XCTAssertTrue(script.contains("return \"updated\";"))
		XCTAssertTrue(script.contains("return \"unsupported\";"))
	}

	func testConfigurationPayloadEncodesRoutingConfigurationForRendererMessageTransport() {
		let snapshot = BrowserCameraSessionSnapshot(
			lifecycleState: .running,
			healthState: .healthy,
			outputMode: .processedNavigatorFeed,
			routingSettings: BrowserCameraRoutingSettings(
				routingEnabled: true,
				preferNavigatorCameraWhenPossible: true,
				preferredSourceID: "camera-a",
				preferredFilterPreset: .supergold,
				prefersHorizontalFlip: true,
				previewEnabled: true
			),
			availableSources: [
				BrowserCameraSource(id: "camera-a", name: "FaceTime HD", isDefault: true),
			],
			activeConsumersByID: [:],
			performanceMetrics: .empty,
			lastErrorDescription: nil,
			publisherStatus: BrowserCameraVirtualPublisherStatus.notRequired
		)

		let payload = BrowserCameraRoutingJavaScript.makeConfigurationPayload(from: snapshot)

		XCTAssertTrue(payload.contains("\"routingEnabled\":true"))
		XCTAssertTrue(payload.contains("\"preferNavigatorCameraWhenPossible\":true"))
		XCTAssertTrue(payload.contains("\"preferredSourceID\":\"camera-a\""))
		XCTAssertTrue(payload.contains("\"preferredFilterPreset\":\"supergold\""))
		XCTAssertTrue(payload.contains("\"prefersHorizontalFlip\":true"))
		XCTAssertTrue(payload.contains("\"outputMode\":\"processedNavigatorFeed\""))
		XCTAssertTrue(payload.contains("\"healthState\":\"healthy\""))
		XCTAssertTrue(payload.contains("\"publisherState\":\"notRequired\""))
		XCTAssertTrue(payload.contains("\"genericVideoUsesManagedOutput\":true"))
	}

	func testConfigurationTransportMessageUsesRoutingConfigurationChannel() {
		let snapshot = BrowserCameraSessionSnapshot(
			lifecycleState: .running,
			healthState: .healthy,
			outputMode: .processedNavigatorFeed,
			routingSettings: BrowserCameraRoutingSettings(
				routingEnabled: true,
				preferNavigatorCameraWhenPossible: true,
				preferredSourceID: "camera-a",
				preferredFilterPreset: .supergold,
				prefersHorizontalFlip: true,
				previewEnabled: true
			),
			availableSources: [
				BrowserCameraSource(id: "camera-a", name: "FaceTime HD", isDefault: true),
			],
			activeConsumersByID: [:],
			performanceMetrics: .empty,
			lastErrorDescription: nil,
			publisherStatus: .notRequired
		)

		let message = BrowserCameraRoutingJavaScript.makeConfigurationTransportMessage(from: snapshot)

		XCTAssertEqual(
			message.channel.rawValue,
			BrowserCameraRoutingScriptConstants.cameraRoutingConfigUpdateChannel
		)
		XCTAssertTrue(message.jsonPayload.contains("\"routingEnabled\":true"))
		XCTAssertTrue(message.jsonPayload.contains("\"preferredFilterPreset\":\"supergold\""))
		XCTAssertTrue(message.jsonPayload.contains("\"prefersHorizontalFlip\":true"))
	}

	func testInstallScriptDisablesRoutingWhenCoordinatorConfigurationIsUnavailable() {
		let snapshot = BrowserCameraSessionSnapshot(
			lifecycleState: .failed,
			healthState: .sourceLost,
			outputMode: .unavailable,
			routingSettings: BrowserCameraRoutingSettings(
				routingEnabled: false,
				preferNavigatorCameraWhenPossible: true,
				preferredSourceID: nil,
				preferredFilterPreset: .none,
				previewEnabled: false
			),
			availableSources: [],
			activeConsumersByID: [:],
			performanceMetrics: .empty,
			lastErrorDescription: "No available video capture devices.",
			publisherStatus: BrowserCameraVirtualPublisherStatus.notRequired
		)

		let script = BrowserCameraRoutingJavaScript.makeInstallScript(from: snapshot)

		XCTAssertTrue(script.contains("\"failClosedOnManagedVideoRequest\":false"))
		XCTAssertTrue(script.contains("\"genericVideoUsesManagedOutput\":false"))
		XCTAssertTrue(script.contains("\"managedRoutingAvailability\":\"noAvailableSource\""))
		XCTAssertTrue(script.contains("\"routingEnabled\":false"))
		XCTAssertFalse(script.contains("\"preferredSourceID\":\""))
		XCTAssertTrue(script.contains("\"outputMode\":\"unavailable\""))
		XCTAssertTrue(script.contains("\"healthState\":\"sourceLost\""))
		XCTAssertTrue(script.contains("\"publisherState\":\"notRequired\""))
		XCTAssertFalse(script.contains("\"publisherTransportMode\":"))
		XCTAssertTrue(script.contains("unsupported: true"))
		XCTAssertTrue(script.contains("dispatchRoutingChange(nextConfig)"))
	}

	func testInstallScriptFailsClosedForGenericVideoWhenManagedRoutingIsEnabledButUnhealthy() {
		let snapshot = BrowserCameraSessionSnapshot(
			lifecycleState: .failed,
			healthState: .pipelineFallback,
			outputMode: .processedNavigatorFeed,
			routingSettings: BrowserCameraRoutingSettings(
				routingEnabled: true,
				preferNavigatorCameraWhenPossible: true,
				preferredSourceID: "camera-a",
				preferredFilterPreset: .supergold,
				previewEnabled: false
			),
			availableSources: [
				BrowserCameraSource(
					id: "camera-a",
					name: "FaceTime HD",
					isDefault: true
				),
			],
			activeConsumersByID: [:],
			performanceMetrics: .empty,
			lastErrorDescription: "Pipeline unavailable.",
			publisherStatus: BrowserCameraVirtualPublisherStatus.notRequired
		)

		let script = BrowserCameraRoutingJavaScript.makeInstallScript(from: snapshot)

		XCTAssertTrue(script.contains("\"failClosedOnManagedVideoRequest\":true"))
		XCTAssertTrue(script.contains("\"managedRoutingAvailability\":\"pipelineFallback\""))
		XCTAssertTrue(script.contains("Promise.reject(makeRoutingUnavailableError())"))
		XCTAssertTrue(script.contains("NotReadableError"))
	}

	func testInstallScriptRoutesGenericManagedRequestsThroughManagedNavigatorStream() {
		let snapshot = BrowserCameraSessionSnapshot(
			lifecycleState: .running,
			healthState: .healthy,
			outputMode: .processedNavigatorFeed,
			routingSettings: BrowserCameraRoutingSettings(
				routingEnabled: true,
				preferNavigatorCameraWhenPossible: true,
				preferredSourceID: "camera-a",
				preferredFilterPreset: .mononoke,
				previewEnabled: false
			),
			availableSources: [],
			activeConsumersByID: [:],
			performanceMetrics: .empty,
			lastErrorDescription: nil,
			publisherStatus: BrowserCameraVirtualPublisherStatus.notRequired
		)

		let script = BrowserCameraRoutingJavaScript.makeInstallScript(from: snapshot)

		XCTAssertTrue(script.contains("\"genericVideoUsesManagedOutput\":true"))
		XCTAssertTrue(script.contains("\"managedRoutingAvailability\":\"available\""))
		XCTAssertTrue(script.contains("const shouldUseManagedNavigatorRouting = activeConfig.genericVideoUsesManagedOutput"))
		XCTAssertTrue(script.contains("const bypassedDeviceIDs = explicitBypassedDeviceIDs(constraints, activeConfig);"))
		XCTAssertTrue(script.contains("return window[shimKey].getManagedStream(constraints);"))
		XCTAssertTrue(script.contains("managed: true"))
		XCTAssertTrue(script
			.contains("const permissionProbeConstraints = managedPermissionProbeConstraints(constraints, activeConfig);"))
		XCTAssertTrue(script
			.contains("return originalGetUserMedia(permissionProbeConstraints).then(function(permissionProbeStream) {"))
		XCTAssertTrue(script.contains("stopStreamTracks(permissionProbeStream, \"video\");"))
		XCTAssertTrue(script.contains("stopStreamTracks(permissionProbeStream, \"audio\");"))
		XCTAssertTrue(script.contains("\"permission-probe-failed\""))
		XCTAssertTrue(script.contains("errorDescription: routingErrorDescription(error)"))
		XCTAssertTrue(script.contains("\"exposesManagedDeviceIdentity\":true"))
		XCTAssertTrue(script.contains("\"managedDeviceID\":\"navigator-camera-managed-output\""))
		XCTAssertTrue(script.contains("\"managedDeviceLabel\":"))
		XCTAssertTrue(script.contains("label: config.managedDeviceLabel || \"\""))
		XCTAssertTrue(script.contains("return value === config.managedDeviceID;"))
		XCTAssertTrue(script.contains("const activeConfig = window[shimKey]?.config ?? nextConfig;"))
		XCTAssertTrue(script.contains("? decorateManagedVideoTrack(videoTracks[0], activeConfig)"))
		XCTAssertTrue(script.contains("stopStreamTracks(permissionProbeStream);"))
		XCTAssertTrue(script.contains("return decorateManagedStream(managedStream, activeConfig);"))
		XCTAssertTrue(script.contains("return decorateManagedStream(stream, activeConfig);"))
	}

	func testInstallScriptDoesNotRouteGenericManagedRequestsWhenNavigatorPreferenceIsDisabled() {
		let snapshot = BrowserCameraSessionSnapshot(
			lifecycleState: .idle,
			healthState: .healthy,
			outputMode: .unavailable,
			routingSettings: BrowserCameraRoutingSettings(
				routingEnabled: true,
				preferNavigatorCameraWhenPossible: false,
				preferredSourceID: "camera-a",
				preferredFilterPreset: .none,
				previewEnabled: false
			),
			availableSources: [
				BrowserCameraSource(id: "camera-a", name: "FaceTime HD", isDefault: true),
			],
			activeConsumersByID: [:],
			performanceMetrics: .empty,
			lastErrorDescription: nil,
			publisherStatus: .notRequired
		)

		let script = BrowserCameraRoutingJavaScript.makeInstallScript(from: snapshot)

		XCTAssertTrue(script.contains("\"preferNavigatorCameraWhenPossible\":false"))
		XCTAssertTrue(script.contains("\"genericVideoUsesManagedOutput\":false"))
		XCTAssertTrue(script.contains("\"managedRoutingAvailability\":\"navigatorPreferenceDisabled\""))
		XCTAssertTrue(
			script.contains(
				"if (!config.routingEnabled || !config.preferNavigatorCameraWhenPossible || !config.preferredSourceID)"
			)
		)
	}

	func testInstallScriptAddsSyntheticManagedDeviceToEnumeratedDevicesWhenManagedRoutingIsHealthy() {
		let snapshot = BrowserCameraSessionSnapshot(
			lifecycleState: .running,
			healthState: .healthy,
			outputMode: .processedNavigatorFeed,
			routingSettings: BrowserCameraRoutingSettings(
				routingEnabled: true,
				preferNavigatorCameraWhenPossible: true,
				preferredSourceID: "camera-a",
				preferredFilterPreset: .supergold,
				previewEnabled: false
			),
			availableSources: [
				BrowserCameraSource(id: "camera-a", name: "FaceTime HD", isDefault: true),
			],
			activeConsumersByID: [
				"tab-1": BrowserCameraConsumer(
					id: "tab-1",
					kind: .browserTabCapture,
					requiresLiveFrames: true
				),
			],
			performanceMetrics: .empty,
			lastErrorDescription: nil,
			publisherStatus: BrowserCameraVirtualPublisherStatus.notRequired
		)

		let script = BrowserCameraRoutingJavaScript.makeInstallScript(from: snapshot)

		XCTAssertTrue(script.contains("const managedDevice = makeManagedDeviceEnumerationEntry(activeConfig);"))
		XCTAssertTrue(script.contains("const hasManagedDevice = annotatedDevices.some(function(device) {"))
		XCTAssertTrue(script.contains("return annotatedDevices.concat([managedDevice]);"))
	}

	func testInstallScriptDoesNotExposeSyntheticManagedDeviceWhenManagedRoutingIsUnhealthy() {
		let snapshot = BrowserCameraSessionSnapshot(
			lifecycleState: .failed,
			healthState: .degraded,
			outputMode: .processedNavigatorFeed,
			routingSettings: BrowserCameraRoutingSettings(
				routingEnabled: true,
				preferNavigatorCameraWhenPossible: true,
				preferredSourceID: "camera-a",
				preferredFilterPreset: .none,
				previewEnabled: false
			),
			availableSources: [
				BrowserCameraSource(id: "camera-a", name: "FaceTime HD", isDefault: true),
			],
			activeConsumersByID: [:],
			performanceMetrics: .empty,
			lastErrorDescription: "Camera session is degraded.",
			publisherStatus: BrowserCameraVirtualPublisherStatus.notRequired
		)

		let script = BrowserCameraRoutingJavaScript.makeInstallScript(from: snapshot)

		XCTAssertTrue(script.contains("\"exposesManagedDeviceIdentity\":false"))
		XCTAssertTrue(script.contains("\"managedRoutingAvailability\":\"degraded\""))
		XCTAssertFalse(script.contains("\"managedDeviceID\":\"navigator-camera-managed-output\""))
		XCTAssertFalse(script.contains("\"managedDeviceLabel\":"))
	}

	func testInstallScriptEmbedsNullPublisherTransportWhenPublisherConfigurationIsMissing() {
		let snapshot = BrowserCameraSessionSnapshot(
			lifecycleState: .failed,
			healthState: .publisherUnavailable,
			outputMode: .systemVirtualCameraPublication,
			routingSettings: BrowserCameraRoutingSettings(
				routingEnabled: true,
				preferNavigatorCameraWhenPossible: true,
				preferredSourceID: "camera-a",
				preferredFilterPreset: .none,
				previewEnabled: false
			),
			availableSources: [],
			activeConsumersByID: [:],
			performanceMetrics: .empty,
			lastErrorDescription: "Publisher unavailable",
			publisherStatus: BrowserCameraVirtualPublisherStatus(
				state: .unavailable,
				configuration: nil,
				lastPublishedFrame: nil,
				lastErrorDescription: "Publisher unavailable"
			)
		)

		let script = BrowserCameraRoutingJavaScript.makeInstallScript(from: snapshot)

		XCTAssertTrue(script.contains("\"publisherState\":\"unavailable\""))
		XCTAssertTrue(script.contains("\"managedRoutingAvailability\":\"publisherUnavailable\""))
		XCTAssertFalse(script.contains("\"publisherTransportMode\":"))
	}
}
