import AppKit
import BrowserCameraKit
@testable import BrowserSidebar
import CoreGraphics
import ModelKit
import XCTest

@MainActor
final class BrowserSidebarViewModelTests: XCTestCase {
	func testInitStartsWithSingleSelectedTab() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)

		XCTAssertEqual(model.tabs.count, 1)
		XCTAssertEqual(model.addressText, "https://navigator.zip")
		XCTAssertEqual(model.selectedTabID, model.tabs.first?.id)
		XCTAssertFalse(model.canGoBack)
		XCTAssertFalse(model.canGoForward)
	}

	func testCameraControlUpdatesNotifyViewStateObservers() throws {
		var snapshot = BrowserCameraSessionSnapshot(
			lifecycleState: .idle,
			healthState: .healthy,
			outputMode: .unavailable,
			routingSettings: .defaults,
			availableSources: [],
			activeConsumersByID: [:],
			performanceMetrics: .empty,
			lastErrorDescription: nil
		)
		var previewFrame: CGImage?
		let cameraControls = BrowserSidebarCameraControls(
			snapshot: { snapshot },
			routingConfiguration: { snapshot.routingConfiguration },
			previewFrame: { previewFrame },
			refreshAvailableDevices: {},
			setRoutingEnabled: { _ in },
			setPreferredSourceID: { _ in },
			setPreferredFilterPreset: { _ in },
			setPreviewEnabled: { _ in }
		)
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions(cameraControls: cameraControls)
		)
		var observerCallCount = 0
		_ = model.addViewStateChangeObserver {
			observerCallCount += 1
		}

		snapshot = BrowserCameraSessionSnapshot(
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
				BrowserCameraSource(id: "camera-main", name: "FaceTime HD", isDefault: true),
			],
			activeConsumersByID: [:],
			performanceMetrics: .empty,
			lastErrorDescription: nil
		)
		previewFrame = try XCTUnwrap(makePreviewFrame())
		model.refreshCameraState()

		XCTAssertEqual(observerCallCount, 1)
		XCTAssertTrue(model.showsCameraControls)
		XCTAssertTrue(model.cameraPreviewEnabled)
		XCTAssertEqual(model.cameraSelectedSourceID, "camera-main")
		XCTAssertEqual(model.cameraSelectedFilterPreset, .folia)
		XCTAssertEqual(model.cameraOutputMode, .processedNavigatorFeed)
		XCTAssertEqual(model.cameraDebugSummary.selectedSourceID, "camera-main")
		XCTAssertEqual(model.cameraDebugSummary.selectedSourceName, "FaceTime HD")
		XCTAssertNotNil(model.cameraPreviewImage)
	}

	func testCameraControlMutationsForwardToHandlersAndUpdateState() {
		var routingSelections = [Bool]()
		var previewSelections = [Bool]()
		var sourceSelections = [String?]()
		var presetSelections = [BrowserCameraFilterPreset]()
		var snapshot = BrowserCameraSessionSnapshot(
			lifecycleState: .idle,
			healthState: .healthy,
			outputMode: .unavailable,
			routingSettings: BrowserCameraRoutingSettings(
				routingEnabled: false,
				preferNavigatorCameraWhenPossible: true,
				preferredSourceID: nil,
				preferredFilterPreset: .none,
				previewEnabled: false
			),
			availableSources: [
				BrowserCameraSource(id: "camera-a", name: "FaceTime HD", isDefault: true),
				BrowserCameraSource(id: "camera-b", name: "Continuity Camera", isDefault: false),
			],
			activeConsumersByID: [:],
			performanceMetrics: .empty,
			lastErrorDescription: nil
		)
		let cameraControls = BrowserSidebarCameraControls(
			snapshot: { snapshot },
			routingConfiguration: { snapshot.routingConfiguration },
			previewFrame: { nil },
			refreshAvailableDevices: {},
			setRoutingEnabled: {
				routingSelections.append($0)
				var settings = snapshot.routingSettings
				settings.routingEnabled = $0
				snapshot = BrowserCameraSessionSnapshot(
					lifecycleState: snapshot.lifecycleState,
					healthState: snapshot.healthState,
					outputMode: snapshot.outputMode,
					routingSettings: settings,
					availableSources: snapshot.availableSources,
					activeConsumersByID: snapshot.activeConsumersByID,
					performanceMetrics: snapshot.performanceMetrics,
					lastErrorDescription: snapshot.lastErrorDescription
				)
			},
			setPreferredSourceID: {
				sourceSelections.append($0)
				var settings = snapshot.routingSettings
				settings.preferredSourceID = $0
				snapshot = BrowserCameraSessionSnapshot(
					lifecycleState: snapshot.lifecycleState,
					healthState: snapshot.healthState,
					outputMode: snapshot.outputMode,
					routingSettings: settings,
					availableSources: snapshot.availableSources,
					activeConsumersByID: snapshot.activeConsumersByID,
					performanceMetrics: snapshot.performanceMetrics,
					lastErrorDescription: snapshot.lastErrorDescription
				)
			},
			setPreferredFilterPreset: {
				presetSelections.append($0)
				var settings = snapshot.routingSettings
				settings.preferredFilterPreset = $0
				snapshot = BrowserCameraSessionSnapshot(
					lifecycleState: snapshot.lifecycleState,
					healthState: snapshot.healthState,
					outputMode: snapshot.outputMode,
					routingSettings: settings,
					availableSources: snapshot.availableSources,
					activeConsumersByID: snapshot.activeConsumersByID,
					performanceMetrics: snapshot.performanceMetrics,
					lastErrorDescription: snapshot.lastErrorDescription
				)
			},
			setPreviewEnabled: {
				previewSelections.append($0)
				var settings = snapshot.routingSettings
				settings.previewEnabled = $0
				snapshot = BrowserCameraSessionSnapshot(
					lifecycleState: snapshot.lifecycleState,
					healthState: snapshot.healthState,
					outputMode: snapshot.outputMode,
					routingSettings: settings,
					availableSources: snapshot.availableSources,
					activeConsumersByID: snapshot.activeConsumersByID,
					performanceMetrics: snapshot.performanceMetrics,
					lastErrorDescription: snapshot.lastErrorDescription
				)
			}
		)
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions(cameraControls: cameraControls)
		)

		model.setCameraRoutingEnabled(true)
		model.setCameraPreviewEnabled(true)
		model.selectCameraSource(id: "camera-b")
		model.selectCameraFilterPreset(.supergold)
		model.refreshCameraState()

		XCTAssertEqual(routingSelections, [true])
		XCTAssertEqual(previewSelections, [true])
		XCTAssertEqual(sourceSelections, ["camera-b"])
		XCTAssertEqual(presetSelections, [.supergold])
		XCTAssertTrue(model.cameraRoutingEnabled)
		XCTAssertTrue(model.cameraPreviewEnabled)
		XCTAssertEqual(model.cameraSelectedSourceID, "camera-b")
		XCTAssertEqual(model.cameraSelectedFilterPreset, .supergold)
	}

	func testCameraUsageStateTracksActiveTabTitlesAndSelectedTab() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		model.updateTabTitle("Camera Home", for: model.tabs[0].id)
		model.openNewTab(with: "https://camera.example/second", activate: true)
		model.updateTabTitle("Second Camera Tab", for: model.tabs[1].id)
		model.selectTab(id: model.tabs[0].id)

		model.updateActiveCameraTabIDs([
			model.tabs[0].id,
			model.tabs[1].id,
		])

		XCTAssertEqual(model.cameraUsageState.activeTabCount, 2)
		XCTAssertEqual(
			model.cameraUsageState.activeTabTitles,
			[
				"Camera Home",
				"Second Camera Tab",
			]
		)
		XCTAssertTrue(model.cameraUsageState.selectedTabIsActive)

		model.updateActiveCameraTabIDs([model.tabs[1].id])

		XCTAssertEqual(model.cameraUsageState.activeTabCount, 1)
		XCTAssertEqual(model.cameraUsageState.activeTabTitles, ["Second Camera Tab"])
		XCTAssertFalse(model.cameraUsageState.selectedTabIsActive)
	}

	func testRefreshAvailableCameraDevicesForwardsToHandlerAndNotifiesViewStateObservers() {
		var refreshCount = 0
		let cameraControls = BrowserSidebarCameraControls(
			snapshot: {
				BrowserCameraSessionSnapshot(
					lifecycleState: .idle,
					healthState: .healthy,
					outputMode: .unavailable,
					routingSettings: .defaults,
					availableSources: [],
					activeConsumersByID: [:],
					performanceMetrics: .empty,
					lastErrorDescription: nil
				)
			},
			routingConfiguration: {
				BrowserCameraRoutingConfiguration(settings: .defaults, outputMode: .unavailable)
			},
			previewFrame: { nil },
			refreshAvailableDevices: {
				refreshCount += 1
			},
			setRoutingEnabled: { _ in },
			setPreferredSourceID: { _ in },
			setPreferredFilterPreset: { _ in },
			setPreviewEnabled: { _ in }
		)
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions(cameraControls: cameraControls)
		)
		var observerCallCount = 0
		_ = model.addViewStateChangeObserver {
			observerCallCount += 1
		}

		model.refreshAvailableCameraDevices()

		XCTAssertEqual(refreshCount, 1)
		XCTAssertEqual(observerCallCount, 0)
	}

	func testSubmitAddressAddsHttpsWhenMissingAndTargetsSelectedTab() {
		var submittedTabID: BrowserTabID?
		var submittedAddress: String?
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: BrowserSidebarActions(
				onGoBack: { _ in },
				onGoForward: { _ in },
				onReload: { _ in },
				onSubmitAddress: { tabID, address in
					submittedTabID = tabID
					submittedAddress = address
				},
				navigationState: { _ in .idle }
			)
		)

		model.setAddressText("example.com")
		model.submitAddress()

		XCTAssertEqual(model.addressText, "https://example.com")
		XCTAssertEqual(model.tabs.first?.currentURL, "https://example.com")
		XCTAssertEqual(submittedTabID, model.tabs.first?.id)
		XCTAssertEqual(submittedAddress, "https://example.com")
	}

	func testSubmitAddressUsesHTTPForLocalhostWithoutScheme() {
		var submittedAddress: String?
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: BrowserSidebarActions(
				onGoBack: { _ in },
				onGoForward: { _ in },
				onReload: { _ in },
				onSubmitAddress: { _, address in
					submittedAddress = address
				},
				navigationState: { _ in .idle }
			)
		)

		model.setAddressText("localhost:3000")
		model.submitAddress()

		XCTAssertEqual(model.addressText, "http://localhost:3000")
		XCTAssertEqual(model.tabs.first?.currentURL, "http://localhost:3000")
		XCTAssertEqual(submittedAddress, "http://localhost:3000")
	}

	func testSubmitAddressNotifiesConfigurationObservers() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		var observerCount = 0
		var legacyCount = 0
		_ = model.addTabConfigurationChangeObserver {
			observerCount += 1
		}
		model.onTabConfigurationChange = {
			legacyCount += 1
		}

		model.setAddressText("swift.org")
		model.submitAddress()

		XCTAssertEqual(observerCount, 1)
		XCTAssertEqual(legacyCount, 1)
	}

	func testSelectTabUpdatesProjectedAddressAndNavigationState() throws {
		var navigationStates = [BrowserTabID: BrowserSidebarNavigationState]()
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: BrowserSidebarActions(
				onGoBack: { _ in },
				onGoForward: { _ in },
				onReload: { _ in },
				onSubmitAddress: { _, _ in },
				navigationState: { tabID in
					navigationStates[tabID] ?? .idle
				}
			)
		)
		let firstTabID = try XCTUnwrap(model.selectedTabID)
		model.addTab()
		let secondTabID = model.tabs[1].id
		navigationStates[firstTabID] = .idle
		navigationStates[secondTabID] = BrowserSidebarNavigationState(
			canGoBack: true,
			canGoForward: false,
			isLoading: true
		)
		model.updateTabURL("https://developer.apple.com/documentation", for: secondTabID)
		model.refreshSelectedNavigationState()

		XCTAssertEqual(model.selectedTabID, secondTabID)
		XCTAssertEqual(model.addressText, "https://developer.apple.com/documentation")
		XCTAssertTrue(model.canGoBack)
		XCTAssertFalse(model.canGoForward)
		XCTAssertTrue(model.isLoading)
	}

	func testAddTabSelectsNewTabAndRetainsExistingTabState() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		let originalTabID = model.selectedTabID
		model.setAddressText("https://existing.example")
		model.submitAddress()

		model.addTab()

		XCTAssertEqual(model.tabs.count, 2)
		XCTAssertNotEqual(model.selectedTabID, originalTabID)
		XCTAssertEqual(model.addressText, "https://navigator.zip")
		XCTAssertEqual(
			model.tabs.first(where: { $0.id == originalTabID })?.currentURL,
			"https://existing.example"
		)
	}

	func testAddTabInsertsImmediatelyAfterSelectedTab() throws {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://first.example",
			actions: makeActions()
		)
		let firstTabID = try XCTUnwrap(model.selectedTabID)

		model.openNewTab(with: "second.example")
		let secondTabID = try XCTUnwrap(model.selectedTabID)
		model.openNewTab(with: "third.example")
		let thirdTabID = try XCTUnwrap(model.selectedTabID)

		model.selectTab(id: firstTabID)
		model.addTab()

		let insertedTabID = try XCTUnwrap(model.selectedTabID)
		XCTAssertEqual(model.tabs.map(\.id), [firstTabID, insertedTabID, secondTabID, thirdTabID])
		XCTAssertEqual(model.tabs[1].currentURL, "https://first.example")
	}

	func testMoveTabsReordersRowsAndPreservesSelectedTab() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		let firstTabID = model.tabs[0].id
		model.addTab()
		model.addTab()
		let secondTabID = model.tabs[1].id
		let selectedTabID = model.tabs[2].id
		model.selectTab(id: selectedTabID)

		model.moveTabs(from: IndexSet(integer: 0), to: 3)

		XCTAssertEqual(model.tabs.map(\.id), [secondTabID, selectedTabID, firstTabID])
		XCTAssertEqual(model.selectedTabID, selectedTabID)
	}

	func testPinningMovesTabIntoPinnedSectionAndPreservesSelection() throws {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		model.openNewTab(with: "https://swift.org")
		model.openNewTab(with: "https://developer.apple.com")
		let selectedTabID = try XCTUnwrap(model.selectedTabID)
		let firstTabID = model.tabs[0].id
		let secondTabID = model.tabs[1].id

		model.pinTab(id: selectedTabID)

		XCTAssertEqual(model.tabs.map(\.id), [selectedTabID, firstTabID, secondTabID])
		XCTAssertEqual(model.tabs[0].isPinned, true)
		XCTAssertEqual(model.selectedTabID, selectedTabID)
	}

	func testUnpinningMovesTabToStartOfUnpinnedSection() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		model.openNewTab(with: "https://swift.org")
		model.openNewTab(with: "https://developer.apple.com")
		let firstTabID = model.tabs[0].id
		let secondTabID = model.tabs[1].id
		let thirdTabID = model.tabs[2].id

		model.pinTab(id: firstTabID)
		model.pinTab(id: thirdTabID)
		model.unpinTab(id: firstTabID)

		XCTAssertEqual(model.tabs.map(\.id), [thirdTabID, firstTabID, secondTabID])
		XCTAssertFalse(model.tabs[1].isPinned)
	}

	func testUnpinningToSpecificIndexPlacesTabAtTargetPosition() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		model.openNewTab(with: "https://swift.org")
		model.openNewTab(with: "https://developer.apple.com")
		model.openNewTab(with: "https://github.com")
		let firstTabID = model.tabs[0].id
		let secondTabID = model.tabs[1].id
		let thirdTabID = model.tabs[2].id
		let fourthTabID = model.tabs[3].id

		model.pinTab(id: firstTabID)

		// Unpin to index 2 within the unpinned section (between third and fourth).
		model.unpinTab(id: firstTabID, toUnpinnedIndex: 2)

		XCTAssertEqual(model.tabs.map(\.id), [secondTabID, thirdTabID, firstTabID, fourthTabID])
		XCTAssertFalse(model.tabs[2].isPinned)
	}

	func testUnpinningToIndexZeroPlacesTabAtStartOfUnpinnedSection() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		model.openNewTab(with: "https://swift.org")
		model.openNewTab(with: "https://developer.apple.com")
		let firstTabID = model.tabs[0].id
		let secondTabID = model.tabs[1].id
		let thirdTabID = model.tabs[2].id

		model.pinTab(id: firstTabID)
		model.unpinTab(id: firstTabID, toUnpinnedIndex: 0)

		XCTAssertEqual(model.tabs.map(\.id), [firstTabID, secondTabID, thirdTabID])
		XCTAssertFalse(model.tabs[0].isPinned)
	}

	func testUnpinningToLastIndexPlacesTabAtEndOfUnpinnedSection() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		model.openNewTab(with: "https://swift.org")
		model.openNewTab(with: "https://developer.apple.com")
		let firstTabID = model.tabs[0].id
		let secondTabID = model.tabs[1].id
		let thirdTabID = model.tabs[2].id

		model.pinTab(id: firstTabID)
		model.unpinTab(id: firstTabID, toUnpinnedIndex: 2)

		XCTAssertEqual(model.tabs.map(\.id), [secondTabID, thirdTabID, firstTabID])
		XCTAssertFalse(model.tabs[2].isPinned)
	}

	func testUnpinningWithoutIndexDefaultsToStartOfUnpinnedSection() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		model.openNewTab(with: "https://swift.org")
		model.openNewTab(with: "https://developer.apple.com")
		let firstTabID = model.tabs[0].id
		let secondTabID = model.tabs[1].id
		let thirdTabID = model.tabs[2].id

		model.pinTab(id: firstTabID)
		model.unpinTab(id: firstTabID)

		// Without an insertion index, tab goes to start (backward compat).
		XCTAssertEqual(model.tabs.map(\.id), [firstTabID, secondTabID, thirdTabID])
		XCTAssertFalse(model.tabs[0].isPinned)
	}

	func testUnpinningToOutOfBoundsIndexClampsToEnd() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		model.openNewTab(with: "https://swift.org")
		let firstTabID = model.tabs[0].id
		let secondTabID = model.tabs[1].id

		model.pinTab(id: firstTabID)
		model.unpinTab(id: firstTabID, toUnpinnedIndex: 999)

		XCTAssertEqual(model.tabs.map(\.id), [secondTabID, firstTabID])
		XCTAssertFalse(model.tabs[1].isPinned)
	}

	func testClosingSelectedPinnedTabUnpinsWithoutClosing() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		model.openNewTab(with: "https://swift.org")

		let pinnedTabID = model.tabs[0].id
		let secondTabID = model.tabs[1].id
		model.pinTab(id: pinnedTabID)
		model.selectTab(id: pinnedTabID)

		model.closeSelectedTab()

		XCTAssertEqual(model.tabs.map(\.id), [pinnedTabID, secondTabID])
		XCTAssertEqual(model.tabs.map(\.isPinned), [false, false])
		XCTAssertEqual(model.selectedTabID, pinnedTabID)
	}

	func testPinningTabCapturesCurrentURLAsPinnedURL() throws {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		let tabID = try XCTUnwrap(model.selectedTabID)
		model.updateTabURL("https://swift.org", for: tabID)

		model.pinTab(id: tabID)

		XCTAssertEqual(model.tabs.first?.initialURL, "https://swift.org")
		XCTAssertEqual(model.tabs.first?.currentURL, "https://swift.org")
	}

	func testReplacePinnedTabURLWithCurrentURLUpdatesPinnedOrigin() throws {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		let tabID = try XCTUnwrap(model.selectedTabID)
		model.pinTab(id: tabID)
		model.updateTabURL("https://swift.org", for: tabID)

		model.replacePinnedTabURLWithCurrentURL(id: tabID)

		XCTAssertEqual(model.tabs.first?.initialURL, "https://swift.org")
		XCTAssertEqual(model.tabs.first?.currentURL, "https://swift.org")
	}

	func testPinTabDoesNothingForMissingIdentifier() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		let originalIDs = model.tabs.map(\.id)
		var callbackCount = 0
		model.onTabConfigurationChange = {
			callbackCount += 1
		}

		model.pinTab(id: BrowserTabID())

		XCTAssertEqual(model.tabs.map(\.id), originalIDs)
		XCTAssertEqual(model.tabs.map(\.isPinned), [false])
		XCTAssertEqual(callbackCount, 0)
	}

	func testPinTabStillNotifiesWhenTabIsAlreadyPinned() throws {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		let tabID = try XCTUnwrap(model.selectedTabID)
		model.pinTab(id: tabID)
		let pinnedIDs = model.tabs.map(\.id)
		var callbackCount = 0
		model.onTabConfigurationChange = {
			callbackCount += 1
		}

		model.pinTab(id: tabID)

		XCTAssertEqual(model.tabs.map(\.id), pinnedIDs)
		XCTAssertEqual(model.tabs.map(\.isPinned), [true])
		XCTAssertEqual(callbackCount, 1)
	}

	func testPinTabStopsAtTwentyPinnedTabs() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)

		for index in 1..<21 {
			model.openNewTab(with: "https://example\(index).com")
		}
		let tabIDs = model.tabs.map(\.id)

		for tabID in tabIDs {
			model.pinTab(id: tabID)
		}

		XCTAssertEqual(model.tabs.filter(\.isPinned).count, 20)
		XCTAssertFalse(model.tabs.last?.isPinned ?? true)
	}

	func testUnpinTabDoesNothingForMissingIdentifier() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		let originalIDs = model.tabs.map(\.id)
		var callbackCount = 0
		model.onTabConfigurationChange = {
			callbackCount += 1
		}

		model.unpinTab(id: BrowserTabID())

		XCTAssertEqual(model.tabs.map(\.id), originalIDs)
		XCTAssertEqual(model.tabs.map(\.isPinned), [false])
		XCTAssertEqual(callbackCount, 0)
	}

	func testUnpinTabStillNotifiesWhenTabIsAlreadyUnpinned() throws {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		let tabID = try XCTUnwrap(model.selectedTabID)
		let originalIDs = model.tabs.map(\.id)
		var callbackCount = 0
		model.onTabConfigurationChange = {
			callbackCount += 1
		}

		model.unpinTab(id: tabID)

		XCTAssertEqual(model.tabs.map(\.id), originalIDs)
		XCTAssertEqual(model.tabs.map(\.isPinned), [false])
		XCTAssertEqual(callbackCount, 1)
	}

	func testToggleSelectedTabPinPinsThenUnpinsSelectedTab() throws {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		model.openNewTab(with: "https://swift.org")
		let originalFirstTabID = model.tabs[0].id
		let selectedTabID = try XCTUnwrap(model.selectedTabID)

		model.toggleSelectedTabPin()

		XCTAssertEqual(model.tabs.map(\.id), [selectedTabID, originalFirstTabID])
		XCTAssertTrue(model.tabs[0].isPinned)
		XCTAssertEqual(model.selectedTabID, selectedTabID)

		model.toggleSelectedTabPin()

		XCTAssertEqual(model.tabs.map(\.id), [selectedTabID, originalFirstTabID])
		XCTAssertFalse(model.tabs[0].isPinned)
		XCTAssertEqual(model.selectedTabID, selectedTabID)
	}

	func testMoveTabsDoesNotMovePinnedTabIntoUnpinnedSection() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		model.openNewTab(with: "https://swift.org")
		model.openNewTab(with: "https://developer.apple.com")
		let firstTabID = model.tabs[0].id
		let secondTabID = model.tabs[1].id
		let thirdTabID = model.tabs[2].id
		model.pinTab(id: firstTabID)

		model.moveTabs(from: IndexSet(integer: 0), to: 3)

		XCTAssertEqual(model.tabs.map(\.id), [firstTabID, secondTabID, thirdTabID])
	}

	func testMoveTabsReordersPinnedTabsWithinPinnedSection() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		model.openNewTab(with: "https://swift.org")
		model.openNewTab(with: "https://developer.apple.com")
		let firstTabID = model.tabs[0].id
		let secondTabID = model.tabs[1].id
		let thirdTabID = model.tabs[2].id
		model.pinTab(id: firstTabID)
		model.pinTab(id: thirdTabID)

		model.moveTabs(from: IndexSet(integer: 0), to: 2)

		XCTAssertEqual(model.tabs.map(\.id), [thirdTabID, firstTabID, secondTabID])
	}

	func testMoveTabsInUnpinnedSectionOffsetsPastPinnedTabs() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		model.openNewTab(with: "https://swift.org")
		model.openNewTab(with: "https://developer.apple.com")
		let pinnedTabID = model.tabs[0].id
		let firstUnpinnedTabID = model.tabs[1].id
		let secondUnpinnedTabID = model.tabs[2].id
		model.pinTab(id: pinnedTabID)

		model.moveTabs(in: .unpinned, from: IndexSet(integer: 0), to: 2)

		XCTAssertEqual(model.tabs.map(\.id), [pinnedTabID, secondUnpinnedTabID, firstUnpinnedTabID])
	}

	func testAppendTabsAddsBatchWithoutReplacingExistingSelectionByDefault() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		let originalSelectedTabID = model.selectedTabID

		model.appendTabs(
			with: [
				"https://developer.apple.com",
				"https://swift.org",
			]
		)

		XCTAssertEqual(
			model.tabs.map(\.currentURL),
			[
				"https://navigator.zip",
				"https://developer.apple.com",
				"https://swift.org",
			]
		)
		XCTAssertEqual(model.selectedTabID, originalSelectedTabID)
	}

	func testAppendTabsCanSelectAppendedTabAndClearTabsRemovesSelection() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)

		model.clearTabs()
		model.appendTabs(
			with: [
				"https://first.example",
				"https://selected.example",
			],
			selectedIndexInBatch: 1
		)

		XCTAssertEqual(
			model.tabs.map(\.currentURL),
			[
				"https://first.example",
				"https://selected.example",
			]
		)
		XCTAssertEqual(model.selectedTabCurrentURL, "https://selected.example")
	}

	func testAppendImportedTabsPreservesProvidedTitles() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)

		model.appendImportedTabs(
			[
				BrowserSidebarImportedTabSeed(
					url: "developer.apple.com",
					title: "Apple Developer"
				),
				BrowserSidebarImportedTabSeed(
					url: "swift.org",
					title: "Swift"
				),
			]
		)

		XCTAssertEqual(
			model.tabs.map(\.currentURL),
			[
				"https://navigator.zip",
				"https://developer.apple.com",
				"https://swift.org",
			]
		)
		XCTAssertEqual(
			model.tabs.map(\.pageTitle),
			[
				nil,
				"Apple Developer",
				"Swift",
			]
		)
	}

	func testAppendImportedTabsPlacesPinnedTabsBeforeUnpinnedTabs() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)

		model.appendImportedTabs(
			[
				BrowserSidebarImportedTabSeed(
					url: "https://unpinned.example",
					title: "Unpinned",
					isPinned: false
				),
				BrowserSidebarImportedTabSeed(
					url: "https://pinned.example",
					title: "Pinned",
					isPinned: true
				),
			]
		)

		XCTAssertEqual(
			model.tabs.map(\.currentURL),
			[
				"https://pinned.example",
				"https://navigator.zip",
				"https://unpinned.example",
			]
		)
		XCTAssertEqual(model.tabs.map(\.isPinned), [true, false, false])
	}

	func testAppendImportedTabsClampsPinnedTabsToTwenty() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)

		model.appendImportedTabs(
			(0..<21).map { index in
				BrowserSidebarImportedTabSeed(
					url: "https://example\(index).com",
					title: "Example \(index)",
					isPinned: true
				)
			}
		)

		XCTAssertEqual(model.tabs.filter(\.isPinned).count, 20)
		XCTAssertFalse(model.tabs.last?.isPinned ?? true)
	}

	func testAppendImportedTabsDefaultsPinnedStateToFalse() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)

		model.appendImportedTabs(
			[
				BrowserSidebarImportedTabSeed(
					url: "https://default.example",
					title: "Default"
				),
			]
		)

		XCTAssertEqual(model.tabs.map(\.isPinned), [false, false])
	}

	func testMoveTabsNotifiesObservers() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		model.addTab()
		var callbackCount = 0
		model.onTabConfigurationChange = {
			callbackCount += 1
		}

		model.moveTabs(from: IndexSet(integer: 0), to: 2)

		XCTAssertEqual(callbackCount, 1)
	}

	func testSharedTabCollectionKeepsTabListsInSyncAcrossViewModels() {
		let sharedTabs = BrowserSidebarTabCollection(initialAddress: "https://navigator.zip")
		let firstModel = BrowserSidebarViewModel(
			tabCollection: sharedTabs,
			defaultNewTabAddress: "https://navigator.zip",
			initialSelectedTabID: sharedTabs.tabs.first?.id,
			actions: makeActions()
		)
		let secondModel = BrowserSidebarViewModel(
			tabCollection: sharedTabs,
			defaultNewTabAddress: "https://navigator.zip",
			initialSelectedTabID: sharedTabs.tabs.first?.id,
			actions: makeActions()
		)

		firstModel.openNewTab(with: "swift.org")

		XCTAssertEqual(
			firstModel.tabs.map(\.currentURL),
			secondModel.tabs.map(\.currentURL)
		)
		XCTAssertEqual(secondModel.tabs.count, 2)
		XCTAssertEqual(secondModel.tabs[1].currentURL, "https://swift.org")
		XCTAssertEqual(secondModel.selectedTabCurrentURL, "https://navigator.zip")
		XCTAssertEqual(firstModel.selectedTabCurrentURL, "https://swift.org")
	}

	func testSharedTabCollectionKeepsSelectionWindowLocalWhenSelectedTabChanges() {
		let sharedTabs = BrowserSidebarTabCollection(initialAddress: "https://navigator.zip")
		let firstModel = BrowserSidebarViewModel(
			tabCollection: sharedTabs,
			defaultNewTabAddress: "https://navigator.zip",
			initialSelectedTabID: sharedTabs.tabs.first?.id,
			actions: makeActions()
		)
		firstModel.openNewTab(with: "swift.org")
		let secondModel = BrowserSidebarViewModel(
			tabCollection: sharedTabs,
			defaultNewTabAddress: "https://navigator.zip",
			initialSelectedTabID: sharedTabs.tabs.first?.id,
			actions: makeActions()
		)

		secondModel.selectTab(id: secondModel.tabs[0].id)

		XCTAssertEqual(firstModel.selectedTabCurrentURL, "https://swift.org")
		XCTAssertEqual(secondModel.selectedTabCurrentURL, "https://navigator.zip")

		firstModel.closeSelectedTab()

		XCTAssertEqual(firstModel.selectedTabCurrentURL, "https://navigator.zip")
		XCTAssertEqual(secondModel.selectedTabCurrentURL, "https://navigator.zip")
		XCTAssertEqual(firstModel.tabs.map(\.currentURL), ["https://navigator.zip"])
		XCTAssertEqual(secondModel.tabs.map(\.currentURL), ["https://navigator.zip"])
	}

	func testSharedTabCollectionSupportsThreeIndependentSelectionsDuringSharedCloseFallback() {
		let sharedTabs = BrowserSidebarTabCollection(initialAddress: "https://navigator.zip")
		let firstModel = BrowserSidebarViewModel(
			tabCollection: sharedTabs,
			defaultNewTabAddress: "https://navigator.zip",
			initialSelectedTabID: sharedTabs.tabs.first?.id,
			actions: makeActions()
		)
		firstModel.openNewTab(with: "swift.org")
		firstModel.openNewTab(with: "developer.apple.com")

		let secondModel = BrowserSidebarViewModel(
			tabCollection: sharedTabs,
			defaultNewTabAddress: "https://navigator.zip",
			initialSelectedTabID: firstModel.tabs[0].id,
			actions: makeActions()
		)
		let thirdModel = BrowserSidebarViewModel(
			tabCollection: sharedTabs,
			defaultNewTabAddress: "https://navigator.zip",
			initialSelectedTabID: firstModel.tabs[1].id,
			actions: makeActions()
		)

		secondModel.selectTab(id: secondModel.tabs[0].id)
		thirdModel.selectTab(id: thirdModel.tabs[1].id)

		firstModel.closeTab(id: firstModel.tabs[1].id)

		XCTAssertEqual(
			firstModel.tabs.map(\.currentURL),
			["https://navigator.zip", "https://developer.apple.com"]
		)
		XCTAssertEqual(
			secondModel.tabs.map(\.currentURL),
			firstModel.tabs.map(\.currentURL)
		)
		XCTAssertEqual(
			thirdModel.tabs.map(\.currentURL),
			firstModel.tabs.map(\.currentURL)
		)
		XCTAssertEqual(firstModel.selectedTabCurrentURL, "https://developer.apple.com")
		XCTAssertEqual(secondModel.selectedTabCurrentURL, "https://navigator.zip")
		XCTAssertEqual(thirdModel.selectedTabCurrentURL, "https://developer.apple.com")
	}

	func testSharedTabCollectionReopenRestoresTabsWithoutOverwritingOtherWindowSelections() {
		let sharedTabs = BrowserSidebarTabCollection(initialAddress: "https://navigator.zip")
		let firstModel = BrowserSidebarViewModel(
			tabCollection: sharedTabs,
			defaultNewTabAddress: "https://navigator.zip",
			initialSelectedTabID: sharedTabs.tabs.first?.id,
			actions: makeActions()
		)
		firstModel.openNewTab(with: "swift.org")
		firstModel.openNewTab(with: "developer.apple.com")
		let secondModel = BrowserSidebarViewModel(
			tabCollection: sharedTabs,
			defaultNewTabAddress: "https://navigator.zip",
			initialSelectedTabID: firstModel.tabs[0].id,
			actions: makeActions()
		)
		secondModel.selectTab(id: secondModel.tabs[0].id)

		firstModel.closeSelectedTab()
		firstModel.reopenLastClosedTab()

		XCTAssertEqual(
			firstModel.tabs.map(\.currentURL),
			["https://navigator.zip", "https://swift.org", "https://developer.apple.com"]
		)
		XCTAssertEqual(
			secondModel.tabs.map(\.currentURL),
			firstModel.tabs.map(\.currentURL)
		)
		XCTAssertEqual(firstModel.selectedTabCurrentURL, "https://developer.apple.com")
		XCTAssertEqual(secondModel.selectedTabCurrentURL, "https://navigator.zip")
	}

	func testSharedTabCollectionPropagatesTabUpdatesWithoutChangingOtherWindowSelection() {
		let sharedTabs = BrowserSidebarTabCollection(initialAddress: "https://navigator.zip")
		let firstModel = BrowserSidebarViewModel(
			tabCollection: sharedTabs,
			defaultNewTabAddress: "https://navigator.zip",
			initialSelectedTabID: sharedTabs.tabs.first?.id,
			actions: makeActions()
		)
		firstModel.openNewTab(with: "swift.org")
		let secondModel = BrowserSidebarViewModel(
			tabCollection: sharedTabs,
			defaultNewTabAddress: "https://navigator.zip",
			initialSelectedTabID: firstModel.tabs[0].id,
			actions: makeActions()
		)
		secondModel.selectTab(id: secondModel.tabs[0].id)

		let sharedUpdatedTabID = firstModel.tabs[1].id
		firstModel.updateTabTitle("Swift", for: sharedUpdatedTabID)
		firstModel.updateTabFaviconURL("https://swift.org/favicon.ico", for: sharedUpdatedTabID)
		firstModel.updateNavigationState(
			BrowserSidebarNavigationState(
				canGoBack: true,
				canGoForward: false,
				isLoading: true
			),
			for: sharedUpdatedTabID
		)

		XCTAssertEqual(secondModel.selectedTabCurrentURL, "https://navigator.zip")
		XCTAssertFalse(secondModel.canGoBack)
		XCTAssertEqual(secondModel.tabs[1].pageTitle, "Swift")
		XCTAssertEqual(secondModel.tabs[1].faviconURL, "https://swift.org/favicon.ico")
		XCTAssertTrue(secondModel.tabs[1].canGoBack)
		XCTAssertTrue(secondModel.tabs[1].isLoading)
	}

	func testCloseSelectedTabSelectsNeighborAndInvokesConfigurationCallback() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		model.addTab()
		let firstTabID = model.tabs[0].id
		let secondTabID = model.tabs[1].id
		var callbackCount = 0
		model.onTabConfigurationChange = {
			callbackCount += 1
		}

		model.closeSelectedTab()

		XCTAssertEqual(model.tabs.count, 1)
		XCTAssertEqual(model.selectedTabID, firstTabID)
		XCTAssertNil(model.tabs.first(where: { $0.id == secondTabID }))
		XCTAssertEqual(callbackCount, 1)
	}

	func testReopenLastClosedTabRestoresOriginalPositionAndTabState() throws {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		let firstTabID = try XCTUnwrap(model.selectedTabID)
		model.updateTabURL("https://swift.org", for: firstTabID)
		model.setAddressText("swift.org/search")
		model.updateTabTitle("Swift", for: firstTabID)
		model.updateTabFaviconURL("https://swift.org/favicon.ico", for: firstTabID)
		model.updateNavigationState(
			BrowserSidebarNavigationState(
				canGoBack: true,
				canGoForward: false,
				isLoading: true
			),
			for: firstTabID
		)
		model.addTab()
		let secondTabID = try XCTUnwrap(model.selectedTabID)

		model.closeTab(id: firstTabID)
		model.reopenLastClosedTab()

		XCTAssertEqual(model.tabs.map(\.id), [firstTabID, secondTabID])
		XCTAssertEqual(model.selectedTabID, firstTabID)
		let reopenedTab = try XCTUnwrap(model.tabs.first)
		XCTAssertEqual(reopenedTab.currentURL, "https://swift.org")
		XCTAssertEqual(reopenedTab.addressText, "swift.org/search")
		XCTAssertEqual(reopenedTab.pageTitle, "Swift")
		XCTAssertEqual(reopenedTab.faviconURL, "https://swift.org/favicon.ico")
		XCTAssertTrue(reopenedTab.canGoBack)
		XCTAssertFalse(reopenedTab.canGoForward)
		XCTAssertTrue(reopenedTab.isLoading)
	}

	func testReopenLastClosedTabUsesLastClosedOrder() throws {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		let firstTabID = try XCTUnwrap(model.selectedTabID)
		model.addTab()
		let secondTabID = try XCTUnwrap(model.selectedTabID)

		model.closeTab(id: firstTabID)
		model.closeTab(id: secondTabID)
		model.reopenLastClosedTab()

		XCTAssertEqual(model.tabs.map(\.id), [secondTabID])
		XCTAssertEqual(model.selectedTabID, secondTabID)
	}

	func testCloseTabByIdentifierRemovesMatchingTabAndPreservesSelectionWhenClosingDifferentRow() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		let firstTabID = model.tabs[0].id
		model.addTab()
		let secondTabID = model.tabs[1].id
		var callbackCount = 0
		model.onTabConfigurationChange = {
			callbackCount += 1
		}
		model.selectTab(id: firstTabID)

		model.closeTab(id: secondTabID)

		XCTAssertEqual(model.tabs.count, 1)
		XCTAssertEqual(model.selectedTabID, firstTabID)
		XCTAssertNil(model.tabs.first(where: { $0.id == secondTabID }))
		XCTAssertEqual(callbackCount, 2)
	}

	func testSelectTabInvokesConfigurationCallback() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		model.addTab()
		let firstTabID = model.tabs[0].id
		var callbackCount = 0
		model.onTabConfigurationChange = {
			callbackCount += 1
		}

		model.selectTab(id: firstTabID)

		XCTAssertEqual(model.selectedTabID, firstTabID)
		XCTAssertEqual(callbackCount, 1)
	}

	func testUpdateNavigationStateRefreshesSelectedStateWithoutConfigurationCallback() throws {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		let selectedTabID = try XCTUnwrap(model.selectedTabID)
		var callbackCount = 0
		var viewStateChangeCount = 0
		let observerID = model.addViewStateChangeObserver {
			viewStateChangeCount += 1
		}
		model.onTabConfigurationChange = {
			callbackCount += 1
		}

		model.updateNavigationState(
			BrowserSidebarNavigationState(
				canGoBack: true,
				canGoForward: true,
				isLoading: true
			),
			for: selectedTabID
		)

		XCTAssertEqual(callbackCount, 0)
		XCTAssertEqual(viewStateChangeCount, 1)
		XCTAssertTrue(model.canGoBack)
		XCTAssertTrue(model.canGoForward)
		XCTAssertTrue(model.isLoading)

		model.removeViewStateChangeObserver(observerID)
	}

	func testSelectNextTabCyclesForwardAndWraps() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		model.addTab()
		model.addTab()
		let firstTabID = model.tabs[0].id
		let secondTabID = model.tabs[1].id
		let thirdTabID = model.tabs[2].id
		model.selectTab(id: firstTabID)

		model.selectNextTab()
		XCTAssertEqual(model.selectedTabID, secondTabID)
		model.selectNextTab()
		XCTAssertEqual(model.selectedTabID, thirdTabID)
		model.selectNextTab()
		XCTAssertEqual(model.selectedTabID, firstTabID)
	}

	func testSelectTabAtIndexTargetsMatchingTab() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		model.addTab()
		model.addTab()

		model.selectTab(at: 1)

		XCTAssertEqual(model.selectedTabID, model.tabs[1].id)
	}

	func testSelectPreviousTabCyclesBackwardAndWraps() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		model.addTab()
		model.addTab()
		let firstTabID = model.tabs[0].id
		let secondTabID = model.tabs[1].id
		let thirdTabID = model.tabs[2].id
		model.selectTab(id: secondTabID)

		model.selectPreviousTab()
		XCTAssertEqual(model.selectedTabID, firstTabID)
		model.selectPreviousTab()
		XCTAssertEqual(model.selectedTabID, thirdTabID)
		model.selectPreviousTab()
		XCTAssertEqual(model.selectedTabID, secondTabID)
	}

	func testMultipleConfigurationObserversCanCoexist() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		var observerCount = 0
		var legacyCount = 0
		let observerID = model.addTabConfigurationChangeObserver {
			observerCount += 1
		}
		model.onTabConfigurationChange = {
			legacyCount += 1
		}

		model.addTab()
		XCTAssertEqual(observerCount, 1)
		XCTAssertEqual(legacyCount, 1)

		model.removeTabConfigurationChangeObserver(observerID)
		model.selectTab(id: model.tabs[0].id)
		XCTAssertEqual(observerCount, 1)
		XCTAssertEqual(legacyCount, 2)
	}

	func testCloseLastTabLeavesNoTabs() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		let originalTabID = model.selectedTabID

		model.closeSelectedTab()

		XCTAssertEqual(model.tabs.count, 0)
		XCTAssertNil(model.selectedTabID)
		if let originalTabID {
			XCTAssertNil(model.tabs.first(where: { $0.id == originalTabID }))
		}
		XCTAssertEqual(model.addressText, "")
	}

	func testGoBackAndReloadUseSelectedTabIdentifier() throws {
		var goBackTabIDs = [BrowserTabID]()
		var reloadTabIDs = [BrowserTabID]()
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: BrowserSidebarActions(
				onGoBack: { tabID in
					goBackTabIDs.append(tabID)
				},
				onGoForward: { _ in },
				onReload: { tabID in
					reloadTabIDs.append(tabID)
				},
				onSubmitAddress: { _, _ in },
				navigationState: { _ in .idle }
			)
		)
		model.addTab()
		let selectedTabID = try XCTUnwrap(model.selectedTabID)

		model.goBack()
		model.reload()

		XCTAssertEqual(goBackTabIDs, [selectedTabID])
		XCTAssertEqual(reloadTabIDs, [selectedTabID])
	}

	func testNavigateSelectedTabSubmitsResolvedAddressForCurrentSelection() {
		var submittedAddresses = [String]()
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: BrowserSidebarActions(
				onGoBack: { _ in },
				onGoForward: { _ in },
				onReload: { _ in },
				onSubmitAddress: { _, address in
					submittedAddresses.append(address)
				},
				navigationState: { _ in .idle }
			)
		)

		model.navigateSelectedTab(to: "swift.org")

		XCTAssertEqual(model.addressText, "https://swift.org")
		XCTAssertEqual(model.selectedTabCurrentURL, "https://swift.org")
		XCTAssertEqual(submittedAddresses, ["https://swift.org"])
	}

	func testOpenNewTabCreatesSelectedTabAndNavigatesToSubmittedAddress() {
		var submittedTabIDs = [BrowserTabID]()
		var submittedAddresses = [String]()
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: BrowserSidebarActions(
				onGoBack: { _ in },
				onGoForward: { _ in },
				onReload: { _ in },
				onSubmitAddress: { tabID, address in
					submittedTabIDs.append(tabID)
					submittedAddresses.append(address)
				},
				navigationState: { _ in .idle }
			)
		)

		model.openNewTab(with: "developer.apple.com")

		XCTAssertEqual(model.tabs.count, 2)
		XCTAssertEqual(model.selectedTabCurrentURL, "https://developer.apple.com")
		XCTAssertEqual(submittedAddresses, ["https://developer.apple.com"])
		XCTAssertEqual(submittedTabIDs, [model.selectedTabID].compactMap { $0 })
	}

	func testReplaceTabsReplacesExistingTabsAndSelectsRequestedIndex() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		model.openNewTab(with: "swift.org")

		model.replaceTabs(
			with: [
				"navigator.example/imported",
				"https://developer.apple.com/imported",
			],
			selectedIndex: 1
		)

		XCTAssertEqual(model.tabs.count, 2)
		XCTAssertEqual(model.tabs[0].currentURL, "https://navigator.example/imported")
		XCTAssertEqual(model.tabs[1].currentURL, "https://developer.apple.com/imported")
		XCTAssertEqual(model.selectedTabCurrentURL, "https://developer.apple.com/imported")
	}

	func testReplaceTabsPreservesProvidedTitles() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)

		model.replaceTabs(
			withImportedTabs: [
				BrowserSidebarImportedTabSeed(
					url: "navigator.example/imported",
					title: "Imported One"
				),
				BrowserSidebarImportedTabSeed(
					url: "developer.apple.com/imported",
					title: "Imported Two"
				),
			],
			selectedIndex: 1
		)

		XCTAssertEqual(model.tabs.map(\.pageTitle), ["Imported One", "Imported Two"])
		XCTAssertEqual(model.selectedTabCurrentURL, "https://developer.apple.com/imported")
	}

	func testReplaceTabsClearsSelectionWhenImportContainsNoTabs() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)

		model.replaceTabs(with: [])

		XCTAssertTrue(model.tabs.isEmpty)
		XCTAssertNil(model.selectedTabID)
		XCTAssertEqual(model.addressText, "")
	}

	func testRestoreTabsPreservesPinnedStateAndSelectedTab() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		let pinnedTabID = BrowserTabID()
		let unpinnedTabID = BrowserTabID()

		model.restoreTabs(
			[
				StoredBrowserTab(
					id: pinnedTabID,
					objectVersion: 1,
					orderKey: "00000000",
					isPinned: true,
					url: "https://pinned.example",
					title: "Pinned"
				),
				StoredBrowserTab(
					id: unpinnedTabID,
					objectVersion: 1,
					orderKey: "00000001",
					isPinned: false,
					url: "https://unpinned.example",
					title: "Unpinned"
				),
			],
			selectedTabID: unpinnedTabID
		)

		XCTAssertEqual(model.tabs.map(\.id), [pinnedTabID, unpinnedTabID])
		XCTAssertEqual(model.tabs.map(\.isPinned), [true, false])
		XCTAssertEqual(model.selectedTabID, unpinnedTabID)
	}

	func testRestoreTabsFallsBackToFirstTabWhenSelectedIdentifierIsMissing() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		let pinnedTabID = BrowserTabID()
		let unpinnedTabID = BrowserTabID()

		model.restoreTabs(
			[
				StoredBrowserTab(
					id: pinnedTabID,
					objectVersion: 1,
					orderKey: "00000000",
					isPinned: true,
					url: "https://pinned.example",
					title: "Pinned"
				),
				StoredBrowserTab(
					id: unpinnedTabID,
					objectVersion: 1,
					orderKey: "00000001",
					isPinned: false,
					url: "https://unpinned.example",
					title: "Unpinned"
				),
			],
			selectedTabID: BrowserTabID()
		)

		XCTAssertEqual(model.selectedTabID, pinnedTabID)
		XCTAssertTrue(model.tabs[0].isPinned)
	}

	func testRestoreTabsUnpinsTabsBeyondPinnedLimit() {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		let storedTabs = (0..<22).map { index in
			StoredBrowserTab(
				id: BrowserTabID(),
				objectVersion: 1,
				orderKey: String(format: "%08d", index),
				isPinned: true,
				url: "https://example\(index).com",
				title: "Tab \(index)"
			)
		}

		model.restoreTabs(storedTabs, selectedTabID: storedTabs[0].id)

		XCTAssertEqual(model.tabs.filter(\.isPinned).count, 20)
		XCTAssertEqual(model.tabs.prefix(20).filter(\.isPinned).count, 20)
		XCTAssertTrue(model.tabs.suffix(2).allSatisfy { !$0.isPinned })
	}

	func testUpdateTabFaviconURLStoresValueOnMatchingTab() throws {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		let tabID = try XCTUnwrap(model.selectedTabID)

		model.updateTabFaviconURL("https://navigator.zip/favicon.ico", for: tabID)

		XCTAssertEqual(model.tabs.first?.faviconURL, "https://navigator.zip/favicon.ico")
	}

	func testUpdateTabTitleStoresValueOnMatchingTab() throws {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		let tabID = try XCTUnwrap(model.selectedTabID)

		model.updateTabTitle("Navigator Docs", for: tabID)

		XCTAssertEqual(model.tabs.first?.pageTitle, "Navigator Docs")
	}

	func testUpdatingTabURLAcrossHostsClearsExistingFavicon() throws {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		let tabID = try XCTUnwrap(model.selectedTabID)
		model.updateTabFaviconURL("https://navigator.zip/favicon.ico", for: tabID)

		model.updateTabURL("https://developer.apple.com", for: tabID)

		XCTAssertNil(model.tabs.first?.faviconURL)
	}

	func testUpdatingTabURLWithinSameHostRetainsExistingFavicon() throws {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		let tabID = try XCTUnwrap(model.selectedTabID)
		model.updateTabFaviconURL("https://navigator.zip/favicon.ico", for: tabID)

		model.updateTabURL("https://navigator.zip/docs", for: tabID)

		XCTAssertEqual(model.tabs.first?.faviconURL, "https://navigator.zip/favicon.ico")
	}

	func testTabPresentationUpdatesNotifyConfigurationObservers() throws {
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: makeActions()
		)
		let tabID = try XCTUnwrap(model.selectedTabID)
		var observerCallCount = 0
		model.onTabConfigurationChange = {
			observerCallCount += 1
		}

		model.updateTabTitle("Navigator Docs", for: tabID)
		model.updateTabURL("https://swift.org/documentation", for: tabID)
		model.updateTabFaviconURL("https://swift.org/favicon.ico", for: tabID)

		XCTAssertEqual(observerCallCount, 3)
	}

	private func makeActions(
		navigationStates: [BrowserTabID: BrowserSidebarNavigationState] = [:],
		cameraControls: BrowserSidebarCameraControls = BrowserSidebarCameraControls()
	) -> BrowserSidebarActions {
		BrowserSidebarActions(
			onGoBack: { _ in },
			onGoForward: { _ in },
			onReload: { _ in },
			onSubmitAddress: { _, _ in },
			navigationState: { tabID in
				navigationStates[tabID] ?? .idle
			},
			cameraControls: cameraControls
		)
	}

	private func makeCameraControls(
		snapshot: BrowserCameraSessionSnapshot
	) -> BrowserSidebarCameraControls {
		BrowserSidebarCameraControls(
			snapshot: { snapshot },
			routingConfiguration: { snapshot.routingConfiguration },
			previewFrame: { nil },
			refreshAvailableDevices: {},
			setRoutingEnabled: { _ in },
			setPreferredSourceID: { _ in },
			setPreferredFilterPreset: { _ in },
			setPreviewEnabled: { _ in }
		)
	}

	private func makePreviewFrame() -> CGImage? {
		let image = NSImage(size: NSSize(width: 8, height: 8))
		image.lockFocus()
		NSColor.systemBlue.setFill()
		NSBezierPath(rect: NSRect(x: 0, y: 0, width: 8, height: 8)).fill()
		image.unlockFocus()
		return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
	}
}

@MainActor
final class BrowserSidebarPresentationTests: XCTestCase {
	func testPresentationStartsHiddenAndCanBePresented() {
		let presentation = BrowserSidebarPresentation()

		XCTAssertFalse(presentation.isPresented)

		presentation.isPresented = true
		XCTAssertTrue(presentation.isPresented)
	}
}
