import AppIntents
@testable import BrowserSidebar
import ModelKit
import XCTest

@MainActor
final class BrowserSidebarViewModelCoverageTests: XCTestCase {
	func testGoForwardUsesSelectedTabIdentifier() throws {
		let recorder = SidebarActionRecorder()
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: recorder.actions()
		)
		model.addTab()
		let selectedTabID = try XCTUnwrap(model.selectedTabID)

		model.goForward()

		XCTAssertEqual(recorder.goForwardTabIDs, [selectedTabID])
	}

	func testSelectionDependentActionsBecomeNoopsWithoutSelection() {
		let recorder = SidebarActionRecorder()
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: recorder.actions()
		)
		model.clearSelectionForTesting()

		model.goBack()
		model.goForward()
		model.reload()
		model.submitAddress()
		model.navigateSelectedTab(to: "swift.org")
		model.closeSelectedTab()
		model.selectNextTab()
		model.selectPreviousTab()
		model.refreshSelectedNavigationState()

		XCTAssertTrue(recorder.goBackTabIDs.isEmpty)
		XCTAssertTrue(recorder.goForwardTabIDs.isEmpty)
		XCTAssertTrue(recorder.reloadTabIDs.isEmpty)
		XCTAssertTrue(recorder.submittedAddresses.isEmpty)
		XCTAssertEqual(model.addressText, "")
		XCTAssertFalse(model.canGoBack)
		XCTAssertFalse(model.canGoForward)
		XCTAssertFalse(model.isLoading)
		XCTAssertNil(model.selectedTabCurrentURL)
	}

	func testAddTabWithoutSelectionAppendsAtEnd() throws {
		let recorder = SidebarActionRecorder()
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: recorder.actions()
		)
		let firstTabID = try XCTUnwrap(model.selectedTabID)
		model.openNewTab(with: "swift.org")
		let secondTabID = try XCTUnwrap(model.selectedTabID)
		model.clearSelectionForTesting()

		model.addTab()

		let appendedTabID = try XCTUnwrap(model.selectedTabID)
		XCTAssertEqual(model.tabs.map(\.id), [firstTabID, secondTabID, appendedTabID])
	}

	func testSubmitAddressUsesFallbackForBlankInputAndPreservesExplicitScheme() {
		let recorder = SidebarActionRecorder()
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: recorder.actions()
		)

		model.setAddressText("   ")
		model.submitAddress()
		model.setAddressText("http://example.com/path")
		model.submitAddress()

		XCTAssertEqual(
			recorder.submittedAddresses,
			["https://navigator.zip", "http://example.com/path"]
		)
		XCTAssertEqual(model.selectedTabCurrentURL, "http://example.com/path")
	}

	func testSelectionAndUnknownIdentifiersAreIgnored() throws {
		let recorder = SidebarActionRecorder()
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: recorder.actions()
		)
		let originalTabID = try XCTUnwrap(model.selectedTabID)
		var callbackCount = 0
		model.onTabConfigurationChange = {
			callbackCount += 1
		}

		model.selectTab(id: nil)
		model.selectTab(id: originalTabID)
		model.selectTab(id: BrowserTabID())
		model.selectTab(at: -1)
		model.selectTab(at: 1)
		model.closeTab(id: BrowserTabID())
		model.updateTabURL("https://developer.apple.com", for: BrowserTabID())
		model.updateNavigationState(
			BrowserSidebarNavigationState(
				canGoBack: true,
				canGoForward: true,
				isLoading: true
			),
			for: BrowserTabID()
		)
		model.updateTabTitle("Ignored", for: BrowserTabID())
		model.updateTabFaviconURL("https://developer.apple.com/favicon.ico", for: BrowserTabID())

		XCTAssertEqual(model.tabs.count, 1)
		XCTAssertEqual(model.selectedTabID, originalTabID)
		XCTAssertEqual(callbackCount, 0)
	}

	func testSetActionsAndSelectedNavigationUpdatesProjection() throws {
		let recorder = SidebarActionRecorder()
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: recorder.actions()
		)
		let selectedTabID = try XCTUnwrap(model.selectedTabID)

		model.setActions(
			BrowserSidebarActions(
				onGoBack: { _ in },
				onGoForward: { _ in },
				onReload: { _ in },
				onSubmitAddress: { _, _ in },
				navigationState: { tabID in
					guard tabID == selectedTabID else { return .idle }
					return BrowserSidebarNavigationState(
						canGoBack: true,
						canGoForward: true,
						isLoading: true
					)
				}
			)
		)

		XCTAssertTrue(model.canGoBack)
		XCTAssertTrue(model.canGoForward)
		XCTAssertTrue(model.isLoading)
		XCTAssertTrue(model.isSelectedTab(selectedTabID))

		model.updateNavigationState(.idle, for: selectedTabID)

		XCTAssertFalse(model.canGoBack)
		XCTAssertFalse(model.canGoForward)
		XCTAssertFalse(model.isLoading)
	}

	func testSelectTabLogsNilPreviousSelectionBranch() throws {
		let recorder = SidebarActionRecorder()
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: recorder.actions()
		)
		let initialTabID = try XCTUnwrap(model.selectedTabID)

		model.clearSelectionForTesting()
		model.selectTab(id: initialTabID)

		XCTAssertEqual(model.selectedTabID, initialTabID)
	}

	func testMoveTabsIgnoresEmptySource() {
		let recorder = SidebarActionRecorder()
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: recorder.actions()
		)
		let originalIDs = model.tabs.map(\.id)

		model.moveTabs(from: IndexSet(), to: 1)

		XCTAssertEqual(model.tabs.map(\.id), originalIDs)
	}

	func testConfigureSpacePagesPublishesSelectionAndInvokesSelectionHandler() {
		let recorder = SidebarActionRecorder()
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: recorder.actions()
		)
		var selectedSpaceIDs = [String]()
		model.configureSpacePages(
			[
				BrowserSidebarSpacePage(id: "space-1", title: "Space 1"),
				BrowserSidebarSpacePage(id: "space-2", title: "Space 2"),
			],
			selectedPageID: "space-1",
			onSelectSpacePage: { selectedSpaceIDs.append($0) }
		)

		model.selectSpacePage(id: "space-2")

		XCTAssertEqual(model.spacePages.map(\.id), ["space-1", "space-2"])
		XCTAssertEqual(model.selectedSpacePageID, "space-2")
		XCTAssertEqual(selectedSpaceIDs, ["space-2"])
	}

	func testSelectAdjacentSpacePageStopsAtBounds() {
		let recorder = SidebarActionRecorder()
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: recorder.actions()
		)
		model.configureSpacePages(
			[
				BrowserSidebarSpacePage(id: "space-1", title: "Space 1"),
				BrowserSidebarSpacePage(id: "space-2", title: "Space 2"),
			],
			selectedPageID: "space-1"
		)

		model.selectAdjacentSpacePage(step: -1)
		XCTAssertEqual(model.selectedSpacePageID, "space-1")

		model.selectAdjacentSpacePage(step: 1)
		XCTAssertEqual(model.selectedSpacePageID, "space-2")

		model.selectAdjacentSpacePage(step: 1)
		XCTAssertEqual(model.selectedSpacePageID, "space-2")
	}

	func testConfigureSpacePagesKeepsLiveTabsOnActivePageAndStoredTabsOnInactivePages() {
		let recorder = SidebarActionRecorder()
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: recorder.actions()
		)
		let spaceTwoSelectedTabID = UUID()
		model.configureSpacePages(
			[
				BrowserSidebarSpacePage(id: "space-1", title: "Space 1"),
				BrowserSidebarSpacePage(id: "space-2", title: "Space 2"),
			],
			selectedPageID: "space-1",
			pageContents: [
				BrowserSidebarSpacePageContent(
					pageID: "space-1",
					tabs: [
						storedTab(
							id: UUID(),
							orderKey: "00000000",
							spaceID: "space-1",
							url: "https://stale-space-one.example"
						),
					],
					selectedTabID: nil
				),
				BrowserSidebarSpacePageContent(
					pageID: "space-2",
					tabs: [
						storedTab(
							id: spaceTwoSelectedTabID,
							orderKey: "00000000",
							spaceID: "space-2",
							url: "https://space-two.example"
						),
					],
					selectedTabID: spaceTwoSelectedTabID
				),
			],
			onSelectSpacePage: nil
		)

		XCTAssertEqual(model.spacePageViewModel(at: 0)?.tabs.map(\.currentURL), ["https://navigator.zip"])
		XCTAssertEqual(model.spacePageViewModel(at: 0)?.selectedTabID, model.selectedTabID)
		XCTAssertEqual(model.spacePageViewModel(at: 1)?.tabs.map(\.currentURL), ["https://space-two.example"])
		XCTAssertEqual(model.spacePageViewModel(at: 1)?.selectedTabID, spaceTwoSelectedTabID)
	}

	func testActiveSpacePageViewModelTracksLiveTabChangesWithoutReplacingInactiveSnapshots() {
		let recorder = SidebarActionRecorder()
		let model = BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: recorder.actions()
		)
		model.configureSpacePages(
			[
				BrowserSidebarSpacePage(id: "space-1", title: "Space 1"),
				BrowserSidebarSpacePage(id: "space-2", title: "Space 2"),
			],
			selectedPageID: "space-1",
			pageContents: [
				BrowserSidebarSpacePageContent(
					pageID: "space-2",
					tabs: [
						storedTab(
							id: UUID(),
							orderKey: "00000000",
							spaceID: "space-2",
							url: "https://space-two.example"
						),
					],
					selectedTabID: nil
				),
			],
			onSelectSpacePage: nil
		)

		model.openNewTab(with: "https://second.example", activate: false)

		XCTAssertEqual(
			model.spacePageViewModel(at: 0)?.tabs.map(\.currentURL),
			["https://navigator.zip", "https://second.example"]
		)
		XCTAssertEqual(model.spacePageViewModel(at: 1)?.tabs.map(\.currentURL), ["https://space-two.example"])
	}
}

@MainActor
private final class SidebarActionRecorder {
	private(set) var goBackTabIDs = [BrowserTabID]()
	private(set) var goForwardTabIDs = [BrowserTabID]()
	private(set) var reloadTabIDs = [BrowserTabID]()
	private(set) var submittedAddresses = [String]()

	func actions() -> BrowserSidebarActions {
		BrowserSidebarActions(
			onGoBack: { [weak self] tabID in
				self?.goBackTabIDs.append(tabID)
			},
			onGoForward: { [weak self] tabID in
				self?.goForwardTabIDs.append(tabID)
			},
			onReload: { [weak self] tabID in
				self?.reloadTabIDs.append(tabID)
			},
			onSubmitAddress: { [weak self] _, address in
				self?.submittedAddresses.append(address)
			},
			navigationState: { _ in .idle }
		)
	}
}

private func storedTab(
	id: UUID,
	orderKey: String,
	spaceID: String,
	url: String
) -> StoredBrowserTab {
	StoredBrowserTab(
		id: id,
		objectVersion: 1,
		orderKey: orderKey,
		spaceID: spaceID,
		url: url
	)
}
