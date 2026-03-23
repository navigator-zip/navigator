import AppKit
import BrowserCameraKit
@testable import BrowserSidebar
import CoreGraphics
import ModelKit
import XCTest

@MainActor
final class BrowserCameraMenuBarViewModelTests: XCTestCase {
	func testPreviewPreferenceDoesNotRegisterMenuBarPreviewConsumerUntilPopoverIsPresented() {
		let coordinator = BrowserCameraMenuBarCoordinatorSpy()
		coordinator.setPreviewEnabledInSnapshot(true)

		let viewModel = BrowserCameraMenuBarViewModel(
			browserCameraSessionCoordinator: coordinator
		)

		XCTAssertTrue(coordinator.registeredConsumers.isEmpty)

		viewModel.setPopoverPresented(true)

		XCTAssertEqual(coordinator.registeredConsumers.last?.kind, .menuBarPreview)
		viewModel.invalidate()
	}

	func testSnapshotUpdateDisablesPreviewAndUnregistersConsumer() {
		let coordinator = BrowserCameraMenuBarCoordinatorSpy()
		coordinator.setPreviewEnabledInSnapshot(true)
		let viewModel = BrowserCameraMenuBarViewModel(
			browserCameraSessionCoordinator: coordinator
		)
		viewModel.setPopoverPresented(true)

		coordinator.setPreviewEnabledInSnapshot(false)
		coordinator.emitSnapshot()

		XCTAssertEqual(coordinator.unregisteredConsumerIDs.last, "menu-bar-preview")
		XCTAssertFalse(viewModel.previewEnabled)
		viewModel.invalidate()
	}

	func testClosingPopoverUnregistersPreviewConsumerWithoutChangingPreviewPreference() {
		let coordinator = BrowserCameraMenuBarCoordinatorSpy()
		coordinator.setPreviewEnabledInSnapshot(true)
		let viewModel = BrowserCameraMenuBarViewModel(
			browserCameraSessionCoordinator: coordinator
		)
		viewModel.setPopoverPresented(true)

		viewModel.setPopoverPresented(false)

		XCTAssertEqual(coordinator.unregisteredConsumerIDs.last, "menu-bar-preview")
		XCTAssertTrue(viewModel.previewEnabled)
		viewModel.invalidate()
	}

	func testActionsForwardToCoordinator() {
		let coordinator = BrowserCameraMenuBarCoordinatorSpy()
		let viewModel = BrowserCameraMenuBarViewModel(
			browserCameraSessionCoordinator: coordinator
		)

		viewModel.setRoutingEnabled(false)
		viewModel.setPreviewEnabled(true)
		viewModel.selectSource(id: "camera-2")
		viewModel.selectFilterPreset(.folia)
		viewModel.refreshAvailableDevices()

		XCTAssertEqual(coordinator.routingEnabledValues, [false])
		XCTAssertEqual(coordinator.previewEnabledValues, [true])
		XCTAssertEqual(coordinator.selectedSourceIDs, ["camera-2"])
		XCTAssertEqual(coordinator.selectedFilterPresets, [.folia])
		XCTAssertEqual(coordinator.refreshAvailableDevicesCount, 1)
		viewModel.invalidate()
	}

	func testPreviewFrameUpdatesPublishPreviewImage() async throws {
		let coordinator = BrowserCameraMenuBarCoordinatorSpy()
		let previewFrameUpdater = BrowserCameraPreviewFrameUpdater(mainQueue: .main)
		let viewModel = BrowserCameraMenuBarViewModel(
			browserCameraSessionCoordinator: coordinator,
			previewFrameUpdater: previewFrameUpdater
		)

		previewFrameUpdater.publishImage(makePreviewFrame(width: 32, height: 24))
		try await Task.sleep(nanoseconds: 50_000_000)

		XCTAssertEqual(viewModel.previewFrame?.width, 32)
		XCTAssertEqual(viewModel.previewFrame?.height, 24)
		viewModel.invalidate()
	}

	func testInvalidateRemovesObserversAndPreviewConsumer() {
		let coordinator = BrowserCameraMenuBarCoordinatorSpy()
		coordinator.setPreviewEnabledInSnapshot(true)
		let viewModel = BrowserCameraMenuBarViewModel(
			browserCameraSessionCoordinator: coordinator
		)
		viewModel.setPopoverPresented(true)

		viewModel.invalidate()

		XCTAssertTrue(coordinator.removedSnapshotObserverIDs.contains("snapshot-observer"))
		XCTAssertEqual(coordinator.unregisteredConsumerIDs.last, "menu-bar-preview")
	}

	func testRemovingChangeObserverStopsFurtherNotificationsAndPreviewCanClear() async throws {
		let coordinator = BrowserCameraMenuBarCoordinatorSpy()
		let previewFrameUpdater = BrowserCameraPreviewFrameUpdater(mainQueue: .main)
		let viewModel = BrowserCameraMenuBarViewModel(
			browserCameraSessionCoordinator: coordinator,
			previewFrameUpdater: previewFrameUpdater
		)
		var changeCount = 0
		let observerID = viewModel.addChangeObserver {
			changeCount += 1
		}

		XCTAssertEqual(changeCount, 1)

		previewFrameUpdater.publishImage(makePreviewFrame(width: 18, height: 12))
		try await Task.sleep(nanoseconds: 50_000_000)
		XCTAssertEqual(changeCount, 1)
		XCTAssertNotNil(viewModel.previewFrame)

		previewFrameUpdater.publishImage(nil)
		try await Task.sleep(nanoseconds: 50_000_000)
		XCTAssertEqual(changeCount, 1)
		XCTAssertNil(viewModel.previewFrame)

		viewModel.removeChangeObserver(id: observerID)
		coordinator.emitSnapshot()

		XCTAssertEqual(changeCount, 1)
		viewModel.invalidate()
	}
}
