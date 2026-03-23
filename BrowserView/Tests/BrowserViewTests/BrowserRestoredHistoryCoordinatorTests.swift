import BrowserSidebar
@testable import BrowserView
import ModelKit
import XCTest

@MainActor
final class BrowserRestoredHistoryCoordinatorTests: XCTestCase {
	func testBrowserCreatedWithSingleEntryUsesLiveHistory() {
		let coordinator = BrowserRestoredHistoryCoordinator()
		let tab = makeTab(url: "https://c.example", entries: ["https://c.example"], currentIndex: 0)

		coordinator.syncTabs([tab])
		coordinator.browserCreated(for: tab)

		XCTAssertEqual(coordinator.goBack(for: tab), .runtimeBack)
		XCTAssertEqual(coordinator.goForward(for: tab), .runtimeForward)
	}

	func testBrowserCreatedWithoutPriorSyncInitializesState() {
		let coordinator = BrowserRestoredHistoryCoordinator()
		let tab = makeTab(
			url: "https://b.example",
			entries: ["https://a.example", "https://b.example"],
			currentIndex: 1
		)

		coordinator.browserCreated(for: tab)

		XCTAssertEqual(coordinator.goBack(for: tab), .loadURL("https://a.example"))
	}

	func testUnsyncedTabFallsBackToRuntimeSemantics() {
		let coordinator = BrowserRestoredHistoryCoordinator()
		let tab = BrowserTabViewModel(initialURL: "https://saved.example")

		XCTAssertEqual(coordinator.goBack(for: tab), .runtimeBack)
		XCTAssertEqual(coordinator.goForward(for: tab), .runtimeForward)
		XCTAssertEqual(coordinator.reload(for: tab).action, .runtimeReload)
		XCTAssertEqual(
			coordinator.submitAddress("https://next.example", for: tab).action,
			.loadURL("https://next.example")
		)
		XCTAssertEqual(
			coordinator.navigationState(
				for: tab,
				browserState: BrowserSidebarNavigationState(
					canGoBack: true,
					canGoForward: true,
					isLoading: false
				)
			),
			BrowserSidebarNavigationState(
				canGoBack: true,
				canGoForward: true,
				isLoading: false
			)
		)
	}

	func testBrowserCreatedWithRestoredStackUsesSyntheticBackAndForward() {
		let coordinator = BrowserRestoredHistoryCoordinator()
		let tabID = UUID()
		let tab = makeTab(
			id: tabID,
			url: "https://c.example",
			entries: ["https://a.example", "https://b.example", "https://c.example"],
			currentIndex: 2
		)

		coordinator.syncTabs([tab])
		coordinator.browserCreated(for: tab)

		XCTAssertEqual(coordinator.goBack(for: tab), .loadURL("https://b.example"))
		let commit = coordinator.handleCommittedURL("https://b.example", for: tab)
		XCTAssertNotNil(commit)
		let updatedTab = makeTab(
			id: tabID,
			url: "https://b.example",
			entries: ["https://a.example", "https://b.example", "https://c.example"],
			currentIndex: 1
		)
		coordinator.syncTabs([updatedTab])
		XCTAssertEqual(coordinator.goForward(for: updatedTab), .loadURL("https://c.example"))
	}

	func testNavigatingSyntheticIgnoresRepeatedBackUntilCommit() {
		let coordinator = BrowserRestoredHistoryCoordinator()
		let tab = makeTab(
			url: "https://c.example",
			entries: ["https://a.example", "https://b.example", "https://c.example"],
			currentIndex: 2
		)

		coordinator.syncTabs([tab])
		coordinator.browserCreated(for: tab)

		XCTAssertEqual(coordinator.goBack(for: tab), .loadURL("https://b.example"))
		XCTAssertEqual(coordinator.goBack(for: tab), .none)
	}

	func testNavigatingSyntheticIgnoresForwardUntilCommit() {
		let coordinator = BrowserRestoredHistoryCoordinator()
		let tab = makeTab(
			url: "https://c.example",
			entries: ["https://a.example", "https://b.example", "https://c.example"],
			currentIndex: 2
		)

		coordinator.syncTabs([tab])
		coordinator.browserCreated(for: tab)
		_ = coordinator.goBack(for: tab)

		XCTAssertEqual(coordinator.goForward(for: tab), .none)
	}

	func testEligibleForwardWithoutSyntheticNextFallsBackToRuntime() {
		let coordinator = BrowserRestoredHistoryCoordinator()
		let tab = makeTab(
			url: "https://b.example",
			entries: ["https://a.example", "https://b.example"],
			currentIndex: 1
		)

		coordinator.syncTabs([tab])
		coordinator.browserCreated(for: tab)

		XCTAssertEqual(coordinator.goForward(for: tab), .runtimeForward)
	}

	func testEligibleBackAtFirstRestoredEntryFallsBackToRuntime() {
		let coordinator = BrowserRestoredHistoryCoordinator()
		let tab = makeTab(
			url: "https://a.example",
			entries: ["https://a.example", "https://b.example"],
			currentIndex: 0
		)

		coordinator.syncTabs([tab])
		coordinator.browserCreated(for: tab)

		XCTAssertEqual(coordinator.goBack(for: tab), .runtimeBack)
	}

	func testSyntheticCommitMovesCurrentIndexAndPreservesEligibility() throws {
		let coordinator = BrowserRestoredHistoryCoordinator()
		let tabID = UUID()
		let tab = makeTab(
			id: tabID,
			url: "https://c.example",
			entries: ["https://a.example", "https://b.example", "https://c.example"],
			currentIndex: 2
		)

		coordinator.syncTabs([tab])
		coordinator.browserCreated(for: tab)
		_ = coordinator.goBack(for: tab)

		let update = try XCTUnwrap(coordinator.handleCommittedURL("https://b.example", for: tab))
		XCTAssertEqual(update.currentIndex, 1)
		XCTAssertEqual(update.entries.map(\.url), ["https://a.example", "https://b.example", "https://c.example"])

		let updatedTab = makeTab(
			id: tabID,
			url: "https://b.example",
			entries: update.entries.map(\.url),
			currentIndex: update.currentIndex
		)
		coordinator.syncTabs([updatedTab])
		XCTAssertEqual(coordinator.goBack(for: updatedTab), .loadURL("https://a.example"))
	}

	func testUnexpectedCommitDuringEligibleHistoryForcesDivergenceAndTruncatesForwardHistory() throws {
		let coordinator = BrowserRestoredHistoryCoordinator()
		let tab = makeTab(
			url: "https://b.example",
			entries: ["https://a.example", "https://b.example", "https://c.example"],
			currentIndex: 1
		)

		coordinator.syncTabs([tab])
		coordinator.browserCreated(for: tab)

		let update = try XCTUnwrap(coordinator.handleCommittedURL("https://d.example", for: tab))
		XCTAssertEqual(update.currentIndex, 2)
		XCTAssertEqual(update.entries.map(\.url), ["https://a.example", "https://b.example", "https://d.example"])
		let divergedTab = makeTab(
			id: tab.id,
			url: "https://d.example",
			entries: update.entries.map(\.url),
			currentIndex: update.currentIndex
		)
		coordinator.syncTabs([divergedTab])
		XCTAssertEqual(coordinator.goForward(for: divergedTab), .runtimeForward)
	}

	func testReloadFromRestoredBackPositionForcesDivergenceAndDropsSyntheticForwardAffordance() {
		let coordinator = BrowserRestoredHistoryCoordinator()
		let tab = makeTab(
			url: "https://b.example",
			entries: ["https://a.example", "https://b.example", "https://c.example"],
			currentIndex: 1
		)

		coordinator.syncTabs([tab])
		coordinator.browserCreated(for: tab)

		let update = coordinator.reload(for: tab)

		XCTAssertEqual(update.action, .runtimeReload)
		XCTAssertEqual(update.entries.map(\.url), ["https://a.example", "https://b.example", "https://c.example"])
		let state = coordinator.navigationState(
			for: tab,
			browserState: BrowserSidebarNavigationState(canGoBack: false, canGoForward: false, isLoading: false)
		)
		XCTAssertFalse(state.canGoForward)
	}

	func testSubmitAddressForcesDivergenceAndDropsSyntheticForwardEntries() {
		let coordinator = BrowserRestoredHistoryCoordinator()
		let tab = makeTab(
			url: "https://b.example",
			entries: ["https://a.example", "https://b.example", "https://c.example"],
			currentIndex: 1
		)

		coordinator.syncTabs([tab])
		coordinator.browserCreated(for: tab)

		let update = coordinator.submitAddress("https://d.example", for: tab)

		XCTAssertEqual(update.action, .loadURL("https://d.example"))
		XCTAssertEqual(update.entries.map(\.url), ["https://a.example", "https://b.example"])
		XCTAssertEqual(update.currentIndex, 1)
	}

	func testSubmitAddressReturnsNoneForEmptyInput() {
		let coordinator = BrowserRestoredHistoryCoordinator()
		let tab = makeTab(url: "https://saved.example", entries: ["https://saved.example"], currentIndex: 0)

		coordinator.syncTabs([tab])
		coordinator.browserCreated(for: tab)

		let update = coordinator.submitAddress("   ", for: tab)
		XCTAssertEqual(update.action, .none)
		XCTAssertEqual(update.entries.map(\.url), ["https://saved.example"])
	}

	func testHandleCommittedURLIgnoresInitialAboutBlank() {
		let coordinator = BrowserRestoredHistoryCoordinator()
		let tab = makeTab(url: "https://saved.example", entries: ["https://saved.example"], currentIndex: 0)

		coordinator.syncTabs([tab])
		coordinator.browserCreated(for: tab)

		XCTAssertNil(coordinator.handleCommittedURL("about:blank", for: tab))
	}

	func testHandleTitleChangeUpdatesCurrentHistoryEntryTitle() throws {
		let coordinator = BrowserRestoredHistoryCoordinator()
		let tab = makeTab(
			url: "https://saved.example",
			entries: ["https://saved.example"],
			currentIndex: 0,
			title: "Saved Page"
		)

		coordinator.syncTabs([tab])
		coordinator.browserCreated(for: tab)

		let update = try XCTUnwrap(coordinator.handleTitleChange("Saved Page", for: tab))
		XCTAssertEqual(update.entries.first?.title, "Saved Page")
	}

	func testNavigationStateUsesSyntheticAffordancesWhileEligible() {
		let coordinator = BrowserRestoredHistoryCoordinator()
		let tab = makeTab(
			url: "https://b.example",
			entries: ["https://a.example", "https://b.example", "https://c.example"],
			currentIndex: 1
		)

		coordinator.syncTabs([tab])
		coordinator.browserCreated(for: tab)

		let state = coordinator.navigationState(
			for: tab,
			browserState: BrowserSidebarNavigationState(canGoBack: false, canGoForward: false, isLoading: false)
		)

		XCTAssertTrue(state.canGoBack)
		XCTAssertTrue(state.canGoForward)
		XCTAssertFalse(state.isLoading)
	}

	func testEligibleNavigationStateFallsBackToRuntimeAffordancesAtSyntheticEdges() {
		let coordinator = BrowserRestoredHistoryCoordinator()
		let firstTab = makeTab(
			url: "https://a.example",
			entries: ["https://a.example", "https://b.example"],
			currentIndex: 0
		)
		coordinator.syncTabs([firstTab])
		coordinator.browserCreated(for: firstTab)
		let firstState = coordinator.navigationState(
			for: firstTab,
			browserState: BrowserSidebarNavigationState(
				canGoBack: true,
				canGoForward: false,
				isLoading: false
			)
		)
		XCTAssertTrue(firstState.canGoBack)

		let lastTab = makeTab(
			id: firstTab.id,
			url: "https://b.example",
			entries: ["https://a.example", "https://b.example"],
			currentIndex: 1
		)
		coordinator.syncTabs([lastTab])
		coordinator.browserCreated(for: lastTab)
		let lastState = coordinator.navigationState(
			for: lastTab,
			browserState: BrowserSidebarNavigationState(
				canGoBack: false,
				canGoForward: true,
				isLoading: false
			)
		)
		XCTAssertTrue(lastState.canGoForward)
	}

	func testNavigationStateShowsLoadingWhileSyntheticNavigationIsPending() {
		let coordinator = BrowserRestoredHistoryCoordinator()
		let tab = makeTab(
			url: "https://c.example",
			entries: ["https://a.example", "https://b.example", "https://c.example"],
			currentIndex: 2
		)

		coordinator.syncTabs([tab])
		coordinator.browserCreated(for: tab)
		_ = coordinator.goBack(for: tab)

		let state = coordinator.navigationState(
			for: tab,
			browserState: BrowserSidebarNavigationState(canGoBack: true, canGoForward: false, isLoading: false)
		)

		XCTAssertFalse(state.canGoBack)
		XCTAssertFalse(state.canGoForward)
		XCTAssertTrue(state.isLoading)
	}

	func testBrowserRemovedClearsStateAndFallsBackToRuntimeSemantics() {
		let coordinator = BrowserRestoredHistoryCoordinator()
		let tab = makeTab(
			url: "https://saved.example",
			entries: ["https://a.example", "https://saved.example"],
			currentIndex: 1
		)

		coordinator.syncTabs([tab])
		coordinator.browserCreated(for: tab)
		coordinator.browserRemoved(for: tab.id)

		XCTAssertEqual(coordinator.goBack(for: tab), .runtimeBack)
	}

	func testEligibleCommitForCurrentEntryUpdatesTitleWithoutDiverging() throws {
		let coordinator = BrowserRestoredHistoryCoordinator()
		let tab = makeTab(
			url: "https://b.example",
			entries: ["https://a.example", "https://b.example", "https://c.example"],
			currentIndex: 1,
			title: "Page B"
		)

		coordinator.syncTabs([tab])
		coordinator.browserCreated(for: tab)

		let update = try XCTUnwrap(coordinator.handleCommittedURL("https://b.example", for: tab))
		XCTAssertEqual(update.currentIndex, 1)
		XCTAssertEqual(update.entries[1].title, "Page B")
		XCTAssertEqual(coordinator.goBack(for: tab), .loadURL("https://a.example"))
	}

	func testSyntheticMismatchCommitFallsBackToIntegratedLiveCommit() throws {
		let coordinator = BrowserRestoredHistoryCoordinator()
		let tab = makeTab(
			url: "https://c.example",
			entries: ["https://a.example", "https://b.example", "https://c.example"],
			currentIndex: 2
		)

		coordinator.syncTabs([tab])
		coordinator.browserCreated(for: tab)
		_ = coordinator.goBack(for: tab)

		let update = try XCTUnwrap(coordinator.handleCommittedURL("https://unexpected.example", for: tab))
		XCTAssertEqual(
			update.entries.map(\.url),
			["https://a.example", "https://b.example", "https://c.example", "https://unexpected.example"]
		)
		XCTAssertEqual(update.currentIndex, 3)
	}

	func testSyntheticCommitAcceptsOriginalOrDisplayURLEquivalentRedirect() throws {
		let coordinator = BrowserRestoredHistoryCoordinator()
		let tab = makeTab(
			url: "https://c.example",
			entries: [
				"https://a.example",
				"https://b.example",
				"https://c.example",
			],
			currentIndex: 2,
			customEntries: [
				StoredBrowserHistoryEntry(url: "https://a.example"),
				StoredBrowserHistoryEntry(
					url: "https://b.example",
					title: "Page B",
					originalURL: "https://short.example/b",
					displayURL: "https://display.example/b"
				),
				StoredBrowserHistoryEntry(url: "https://c.example"),
			]
		)

		coordinator.syncTabs([tab])
		coordinator.browserCreated(for: tab)
		_ = coordinator.goBack(for: tab)

		let update = try XCTUnwrap(coordinator.handleCommittedURL("https://display.example/b", for: tab))
		XCTAssertEqual(update.currentIndex, 1)
	}

	func testLiveCommitRecognizesPreviousAndNextEntries() throws {
		let coordinator = BrowserRestoredHistoryCoordinator()
		let previousTab = makeTab(
			url: "https://b.example",
			entries: ["https://a.example", "https://b.example", "https://c.example"],
			currentIndex: 1
		)

		coordinator.syncTabs([previousTab])

		let previousUpdate = try XCTUnwrap(coordinator.handleCommittedURL("https://a.example", for: previousTab))
		XCTAssertEqual(previousUpdate.currentIndex, 0)

		let nextTab = makeTab(
			id: previousTab.id,
			url: "https://b.example",
			entries: ["https://a.example", "https://b.example", "https://c.example"],
			currentIndex: 1
		)
		coordinator.syncTabs([nextTab])
		let nextUpdate = try XCTUnwrap(coordinator.handleCommittedURL("https://c.example", for: nextTab))
		XCTAssertEqual(nextUpdate.currentIndex, 2)
	}

	func testHandleTitleChangeReturnsNilWhenNoCurrentEntryExists() {
		let coordinator = BrowserRestoredHistoryCoordinator()
		let tab = BrowserTabViewModel(initialURL: "https://saved.example")

		coordinator.syncTabs([tab])
		XCTAssertNil(coordinator.handleTitleChange("Title", for: tab))
	}

	func testLiveCommitSeedsHistoryWhenEntriesAreEmpty() throws {
		let coordinator = BrowserRestoredHistoryCoordinator()
		let tab = BrowserTabViewModel(initialURL: "https://saved.example")

		coordinator.syncTabs([tab])

		let update = try XCTUnwrap(coordinator.handleCommittedURL("https://seeded.example", for: tab))
		XCTAssertEqual(update.entries.map(\.url), ["https://seeded.example"])
		XCTAssertEqual(update.currentIndex, 0)
	}

	func testHandleCommittedURLFallsBackToLiveModeWhenTabWasNeverSynced() throws {
		let coordinator = BrowserRestoredHistoryCoordinator()
		let tab = BrowserTabViewModel(initialURL: "https://saved.example")

		let update = try XCTUnwrap(coordinator.handleCommittedURL("https://unsynced.example", for: tab))
		XCTAssertEqual(update.entries.map(\.url), ["https://unsynced.example"])
	}

	func testLiveCommitUpdatesExistingCurrentEntryWithoutAppending() throws {
		let coordinator = BrowserRestoredHistoryCoordinator()
		let tab = makeTab(
			url: "https://saved.example",
			entries: ["https://saved.example"],
			currentIndex: 0,
			title: "Saved"
		)

		coordinator.syncTabs([tab])

		let update = try XCTUnwrap(coordinator.handleCommittedURL("https://saved.example", for: tab))
		XCTAssertEqual(update.entries.map(\.url), ["https://saved.example"])
		XCTAssertEqual(update.currentIndex, 0)
	}

	private func makeTab(
		id: UUID = UUID(),
		url: String,
		entries: [String],
		currentIndex: Int,
		title: String? = nil,
		customEntries: [StoredBrowserHistoryEntry]? = nil
	) -> BrowserTabViewModel {
		let viewModel = BrowserSidebarViewModel(
			initialAddress: url,
			actions: BrowserSidebarActions(
				onGoBack: { _ in },
				onGoForward: { _ in },
				onReload: { _ in },
				onSubmitAddress: { _, _ in },
				navigationState: { _ in .idle }
			)
		)
		viewModel.restoreTabs(
			[
				StoredBrowserTab(
					id: id,
					objectVersion: 1,
					orderKey: "a",
					url: url,
					title: title,
					historyEntries: customEntries ?? entries.map { StoredBrowserHistoryEntry(url: $0) },
					currentHistoryIndex: currentIndex
				),
			],
			selectedTabID: id
		)
		return viewModel.tabs[0]
	}
}
