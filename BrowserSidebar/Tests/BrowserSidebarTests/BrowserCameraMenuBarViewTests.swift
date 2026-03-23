import AppKit
import BrowserCameraKit
@testable import BrowserSidebar
import ModelKit
import XCTest

@MainActor
final class BrowserCameraMenuBarViewTests: XCTestCase {
	func testViewShowsDisabledPreviewPlaceholderUntilPreviewIsEnabled() {
		let coordinator = BrowserCameraMenuBarCoordinatorSpy()
		let viewModel = BrowserCameraMenuBarViewModel(
			browserCameraSessionCoordinator: coordinator
		)
		let view = BrowserCameraMenuBarView(viewModel: viewModel)

		XCTAssertEqual(view.previewPlaceholderLabelForTesting().stringValue, "Preview is off")
		XCTAssertTrue(view.previewImageViewForTesting().isHidden)
		viewModel.invalidate()
		_ = view
	}

	func testViewActionsMutateCoordinatorSelectionState() {
		let coordinator = BrowserCameraMenuBarCoordinatorSpy()
		let viewModel = BrowserCameraMenuBarViewModel(
			browserCameraSessionCoordinator: coordinator
		)
		let view = BrowserCameraMenuBarView(viewModel: viewModel)

		view.routingToggleButtonForTesting().state = .off
		_ = view.routingToggleButtonForTesting().target?.perform(
			view.routingToggleButtonForTesting().action,
			with: view.routingToggleButtonForTesting()
		)

		view.previewToggleButtonForTesting().state = .on
		_ = view.previewToggleButtonForTesting().target?.perform(
			view.previewToggleButtonForTesting().action,
			with: view.previewToggleButtonForTesting()
		)

		view.sourcePopUpButtonForTesting().selectItem(at: 2)
		_ = view.sourcePopUpButtonForTesting().target?.perform(
			view.sourcePopUpButtonForTesting().action,
			with: view.sourcePopUpButtonForTesting()
		)

		view.presetPopUpButtonForTesting().selectItem(withTitle: "Folia")
		_ = view.presetPopUpButtonForTesting().target?.perform(
			view.presetPopUpButtonForTesting().action,
			with: view.presetPopUpButtonForTesting()
		)

		view.grainPopUpButtonForTesting().selectItem(withTitle: "High")
		_ = view.grainPopUpButtonForTesting().target?.perform(
			view.grainPopUpButtonForTesting().action,
			with: view.grainPopUpButtonForTesting()
		)

		view.horizontalFlipToggleButtonForTesting().state = .on
		_ = view.horizontalFlipToggleButtonForTesting().target?.perform(
			view.horizontalFlipToggleButtonForTesting().action,
			with: view.horizontalFlipToggleButtonForTesting()
		)

		view.refreshSourcesButtonForTesting().performClick(nil)

		XCTAssertEqual(coordinator.routingEnabledValues, [false])
		XCTAssertEqual(coordinator.previewEnabledValues, [true])
		XCTAssertEqual(coordinator.selectedSourceIDs, ["camera-2"])
		XCTAssertEqual(coordinator.selectedFilterPresets, [.folia])
		XCTAssertEqual(coordinator.selectedGrainPresences, [.high])
		XCTAssertEqual(coordinator.selectedHorizontalFlipValues, [true])
		XCTAssertEqual(coordinator.refreshAvailableDevicesCount, 1)
		viewModel.invalidate()
		_ = view
	}

	func testRefreshingWithSamePresetMenuKeepsExistingMenuItems() throws {
		let coordinator = BrowserCameraMenuBarCoordinatorSpy()
		let viewModel = BrowserCameraMenuBarViewModel(
			browserCameraSessionCoordinator: coordinator
		)
		let view = BrowserCameraMenuBarView(
			viewModel: viewModel,
			presentation: .settings
		)
		let originalItem = try XCTUnwrap(view.presetPopUpButtonForTesting().item(at: 1))

		coordinator.emitSnapshot()

		let refreshedItem = try XCTUnwrap(view.presetPopUpButtonForTesting().item(at: 1))
		XCTAssertTrue(originalItem === refreshedItem)
		XCTAssertEqual(refreshedItem.title, "Mononoke")
		viewModel.invalidate()
		_ = view
	}

	func testViewShowsPreviewImageWhenPreviewFrameArrives() async throws {
		let coordinator = BrowserCameraMenuBarCoordinatorSpy()
		coordinator.setPreviewEnabledInSnapshot(true)
		let previewFrameUpdater = BrowserCameraPreviewFrameUpdater(mainQueue: .main)
		let viewModel = BrowserCameraMenuBarViewModel(
			browserCameraSessionCoordinator: coordinator,
			previewFrameUpdater: previewFrameUpdater
		)
		let view = BrowserCameraMenuBarView(viewModel: viewModel)

		previewFrameUpdater.publishImage(makePreviewFrame(width: 48, height: 32))
		try await Task.sleep(nanoseconds: 50_000_000)

		XCTAssertFalse(view.previewImageViewForTesting().isHidden)
		XCTAssertNotNil(view.previewImageViewForTesting().layer?.contents)
		XCTAssertNil(view.previewImageViewForTesting().image)
		XCTAssertTrue(view.previewPlaceholderLabelForTesting().isHidden)
		viewModel.invalidate()
		_ = view
	}

	func testPreviewContainerAdoptsIncomingFrameAspectRatio() async throws {
		let coordinator = BrowserCameraMenuBarCoordinatorSpy()
		coordinator.setPreviewEnabledInSnapshot(true)
		let previewFrameUpdater = BrowserCameraPreviewFrameUpdater(mainQueue: .main)
		let viewModel = BrowserCameraMenuBarViewModel(
			browserCameraSessionCoordinator: coordinator,
			previewFrameUpdater: previewFrameUpdater
		)
		let view = BrowserCameraMenuBarView(
			viewModel: viewModel,
			presentation: .settings
		)
		view.frame = NSRect(x: 0, y: 0, width: 360, height: 480)
		view.layoutSubtreeIfNeeded()

		previewFrameUpdater.publishImage(makePreviewFrame(width: 120, height: 90))
		try await Task.sleep(nanoseconds: 50_000_000)
		view.layoutSubtreeIfNeeded()

		let previewFrame = view.previewContainerForTesting().frame
		XCTAssertEqual(previewFrame.height / previewFrame.width, 0.75, accuracy: 0.02)
		viewModel.invalidate()
		_ = view
	}

	func testSettingsPresentationKeepsCameraControlsCompact() {
		let coordinator = BrowserCameraMenuBarCoordinatorSpy()
		coordinator.setPreviewEnabledInSnapshot(true)
		let viewModel = BrowserCameraMenuBarViewModel(
			browserCameraSessionCoordinator: coordinator
		)
		let view = BrowserCameraMenuBarView(
			viewModel: viewModel,
			presentation: .settings
		)
		view.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
		view.layoutSubtreeIfNeeded()

		XCTAssertLessThanOrEqual(view.fittingSize.width, 360)
		viewModel.invalidate()
		_ = view
	}

	func testViewRendersCameraStatusAndDiagnosticsText() {
		let coordinator = BrowserCameraMenuBarCoordinatorSpy()
		coordinator.snapshot = BrowserCameraSessionSnapshot(
			lifecycleState: .running,
			healthState: .degraded,
			outputMode: .processedNavigatorFeed,
			routingSettings: coordinator.snapshot.routingSettings,
			availableSources: coordinator.snapshot.availableSources,
			activeConsumersByID: [
				"tab": BrowserCameraConsumer(id: "tab", kind: .browserTabCapture, requiresLiveFrames: true),
				"preview": BrowserCameraConsumer(id: "preview", kind: .menuBarPreview, requiresLiveFrames: false),
			],
			performanceMetrics: BrowserCameraPerformanceMetrics(
				processedFrameCount: 120,
				droppedFrameCount: 3,
				firstFrameLatencyMilliseconds: 18,
				averageProcessingLatencyMilliseconds: 12.4,
				lastProcessingLatencyMilliseconds: 13,
				realtimeBudgetExceeded: false
			),
			lastErrorDescription: nil,
			publisherStatus: .notRequired,
			browserTransportStates: [
				BrowserCameraBrowserTransportState(
					tabID: "tab-2",
					routingTransportMode: .browserProcessJavaScriptFallback,
					frameTransportMode: .rendererProcessMessages,
					activeManagedTrackCount: 1
				),
			],
			recentDiagnosticEvents: [
				BrowserCameraDiagnosticEvent(
					kind: .permissionProbeFailed,
					detail: "tabID=tab-2 error=Permission denied"
				),
			]
		)
		let viewModel = BrowserCameraMenuBarViewModel(
			browserCameraSessionCoordinator: coordinator
		)
		let view = BrowserCameraMenuBarView(viewModel: viewModel)

		XCTAssertEqual(view.statusLabelForTesting().stringValue, "Camera is running")
		XCTAssertEqual(
			view.diagnosticsLabelForTesting().stringValue,
			"""
			Routing: Degraded (fail closed)
			Live consumers: 1 • Preview consumers: 1
			Frames: 120 • Dropped: 3 • Avg latency: 12.4 ms
			Browser transport: tabs 1 • Tracks: 1 • Fallback: 1
			Latest event: Permission probe failed: tabID=tab-2 error=Permission denied
			"""
		)
		viewModel.invalidate()
		_ = view
	}

	func testViewRendersPublisherDiagnosticsWhenSystemPublicationIsActive() {
		let coordinator = BrowserCameraMenuBarCoordinatorSpy()
		coordinator.snapshot = BrowserCameraSessionSnapshot(
			lifecycleState: .running,
			healthState: .healthy,
			outputMode: .systemVirtualCameraPublication,
			routingSettings: coordinator.snapshot.routingSettings,
			availableSources: coordinator.snapshot.availableSources,
			activeConsumersByID: [:],
			performanceMetrics: BrowserCameraPerformanceMetrics(
				processedFrameCount: 12,
				droppedFrameCount: 0,
				firstFrameLatencyMilliseconds: 18,
				averageProcessingLatencyMilliseconds: 9.5,
				lastProcessingLatencyMilliseconds: 10,
				realtimeBudgetExceeded: false
			),
			lastErrorDescription: nil,
			publisherStatus: BrowserCameraVirtualPublisherStatus(
				state: .ready,
				configuration: BrowserCameraVirtualPublisherConfiguration(
					sourceDeviceID: "camera-1",
					filterPreset: .none,
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
		)
		let viewModel = BrowserCameraMenuBarViewModel(
			browserCameraSessionCoordinator: coordinator
		)
		let view = BrowserCameraMenuBarView(viewModel: viewModel)

		XCTAssertEqual(
			view.diagnosticsLabelForTesting().stringValue,
			"Routing: Managed output available\nLive consumers: 0 • Preview consumers: 0\nFrames: 12 • Dropped: 0 • Avg latency: 9.5 ms\nPublisher: Ready • Transport: Shared memory"
		)
		viewModel.invalidate()
		_ = view
	}

	func testViewUsesFallbackLocalizationForAdditionalStatusesAndPlaceholders() {
		let fallbackBundle = Bundle(for: Self.self)
		let statusCases: [(BrowserCameraLifecycleState, String)] = [
			(.preparing, "Preparing camera"),
			(.starting, "Starting camera"),
			(.stopping, "Stopping camera"),
			(.failed, "Camera failed"),
		]

		for (lifecycleState, expectedStatus) in statusCases {
			let coordinator = BrowserCameraMenuBarCoordinatorSpy()
			coordinator.snapshot = BrowserCameraSessionSnapshot(
				lifecycleState: lifecycleState,
				healthState: .healthy,
				outputMode: .processedNavigatorFeed,
				routingSettings: BrowserCameraRoutingSettings(
					routingEnabled: true,
					preferNavigatorCameraWhenPossible: true,
					preferredSourceID: "missing-camera",
					preferredFilterPreset: .vertichrome,
					previewEnabled: true
				),
				availableSources: coordinator.snapshot.availableSources,
				activeConsumersByID: [:],
				performanceMetrics: BrowserCameraPerformanceMetrics(
					processedFrameCount: 1,
					droppedFrameCount: 0,
					firstFrameLatencyMilliseconds: nil,
					averageProcessingLatencyMilliseconds: nil,
					lastProcessingLatencyMilliseconds: nil,
					realtimeBudgetExceeded: false
				),
				lastErrorDescription: nil
			)
			let viewModel = BrowserCameraMenuBarViewModel(
				browserCameraSessionCoordinator: coordinator
			)
			let view = BrowserCameraMenuBarView(
				viewModel: viewModel,
				localizationBundle: fallbackBundle
			)

			XCTAssertEqual(view.statusLabelForTesting().stringValue, expectedStatus)
			XCTAssertEqual(view.previewPlaceholderLabelForTesting().stringValue, "Waiting for preview")
			XCTAssertEqual(view.sourcePopUpButtonForTesting().titleOfSelectedItem, "Automatic")
			XCTAssertEqual(
				view.diagnosticsLabelForTesting().stringValue,
				"Routing: Managed output available\nLive consumers: 0 • Preview consumers: 0\nFrames: 1 • Dropped: 0 • Avg latency: -- ms"
			)
			XCTAssertEqual(
				view.presetPopUpButtonForTesting().itemTitles,
				[
					"None",
					"Mononoke",
					"Dither",
					"Folia",
					"Supergold",
					"Tonachrome",
					"Bubblegum",
					"Darkroom",
					"Glow in the Dark",
					"Habenero",
				]
			)
			XCTAssertEqual(
				view.sourcePopUpButtonForTesting().itemTitles,
				["Automatic", "FaceTime HD Camera (Default)", "Studio Display Camera"]
			)

			viewModel.invalidate()
			_ = view
		}
	}

	func testViewShowsUnavailablePlaceholderAndLastErrorUsingFallbackLocalization() {
		let coordinator = BrowserCameraMenuBarCoordinatorSpy()
		coordinator.snapshot = BrowserCameraSessionSnapshot(
			lifecycleState: .running,
			healthState: .sourceLost,
			outputMode: .unavailable,
			routingSettings: BrowserCameraRoutingSettings(
				routingEnabled: true,
				preferNavigatorCameraWhenPossible: true,
				preferredSourceID: nil,
				preferredFilterPreset: .none,
				previewEnabled: true
			),
			availableSources: [],
			activeConsumersByID: [:],
			performanceMetrics: .empty,
			lastErrorDescription: "Source disconnected"
		)
		let viewModel = BrowserCameraMenuBarViewModel(
			browserCameraSessionCoordinator: coordinator
		)
		let view = BrowserCameraMenuBarView(
			viewModel: viewModel,
			localizationBundle: Bundle(for: Self.self)
		)

		XCTAssertEqual(view.statusLabelForTesting().stringValue, "Source disconnected")
		XCTAssertEqual(view.previewPlaceholderLabelForTesting().stringValue, "No camera available")
		XCTAssertFalse(view.sourcePopUpButtonForTesting().isEnabled)
		XCTAssertEqual(view.sourcePopUpButtonForTesting().itemTitles, ["Automatic"])
		viewModel.invalidate()
		_ = view
	}

	func testInvalidPresetSelectionDoesNotMutateCoordinator() {
		let coordinator = BrowserCameraMenuBarCoordinatorSpy()
		let viewModel = BrowserCameraMenuBarViewModel(
			browserCameraSessionCoordinator: coordinator
		)
		let view = BrowserCameraMenuBarView(viewModel: viewModel)
		let invalidMenuItem = NSMenuItem(title: "Invalid", action: nil, keyEquivalent: "")
		invalidMenuItem.representedObject = "definitely-not-a-preset"

		view.presetPopUpButtonForTesting().menu?.addItem(invalidMenuItem)
		view.presetPopUpButtonForTesting().select(invalidMenuItem)
		_ = view.presetPopUpButtonForTesting().target?.perform(
			view.presetPopUpButtonForTesting().action,
			with: view.presetPopUpButtonForTesting()
		)

		XCTAssertTrue(coordinator.selectedFilterPresets.isEmpty)
		viewModel.invalidate()
		_ = view
	}
}
