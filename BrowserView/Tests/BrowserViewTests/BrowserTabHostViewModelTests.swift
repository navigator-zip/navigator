import BrowserSidebar
@testable import BrowserView
import XCTest

@MainActor
final class BrowserTabHostViewModelTests: XCTestCase {
	func testInitialSyncAddsAllTabs() throws {
		let model = BrowserTabHostViewModel()
		let firstTab = try BrowserTabViewModel(
			id: XCTUnwrap(BrowserTabID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")),
			initialURL: "https://navigator.zip"
		)
		let secondTab = try BrowserTabViewModel(
			id: XCTUnwrap(BrowserTabID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")),
			initialURL: "https://developer.apple.com"
		)

		let result = model.sync(
			tabs: [firstTab, secondTab],
			selectedTabID: secondTab.id
		)

		XCTAssertEqual(result.tabsToAdd.map(\.id), [firstTab.id, secondTab.id])
		XCTAssertEqual(result.tabIDsToRemove, [])
		XCTAssertEqual(result.selectedTabID, secondTab.id)
	}

	func testSelectionChangeDoesNotRemoveOrReaddContainers() throws {
		let model = BrowserTabHostViewModel()
		let firstTab = try BrowserTabViewModel(
			id: XCTUnwrap(BrowserTabID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")),
			initialURL: "https://navigator.zip"
		)
		let secondTab = try BrowserTabViewModel(
			id: XCTUnwrap(BrowserTabID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")),
			initialURL: "https://developer.apple.com"
		)
		_ = model.sync(tabs: [firstTab, secondTab], selectedTabID: firstTab.id)

		let result = model.sync(
			tabs: [firstTab, secondTab],
			selectedTabID: secondTab.id
		)

		XCTAssertTrue(result.tabsToAdd.isEmpty)
		XCTAssertTrue(result.tabIDsToRemove.isEmpty)
		XCTAssertEqual(result.selectedTabID, secondTab.id)
	}

	func testRemovingTabOnlyReturnsRemovedIdentifier() throws {
		let model = BrowserTabHostViewModel()
		let firstTab = try BrowserTabViewModel(
			id: XCTUnwrap(BrowserTabID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")),
			initialURL: "https://navigator.zip"
		)
		let secondTab = try BrowserTabViewModel(
			id: XCTUnwrap(BrowserTabID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")),
			initialURL: "https://developer.apple.com"
		)
		_ = model.sync(tabs: [firstTab, secondTab], selectedTabID: firstTab.id)

		let result = model.sync(
			tabs: [firstTab],
			selectedTabID: firstTab.id
		)

		XCTAssertTrue(result.tabsToAdd.isEmpty)
		XCTAssertEqual(result.tabIDsToRemove, [secondTab.id])
		XCTAssertEqual(result.selectedTabID, firstTab.id)
	}

	func testUpdatingTabURLDoesNotRecreateHostedContainer() throws {
		let model = BrowserTabHostViewModel()
		let tabID = try XCTUnwrap(BrowserTabID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))
		let tab = BrowserTabViewModel(
			id: tabID,
			initialURL: "https://navigator.zip"
		)
		_ = model.sync(tabs: [tab], selectedTabID: tabID)
		let updatedTab = BrowserTabViewModel(
			id: tabID,
			initialURL: "https://navigator.zip",
			currentURL: "https://developer.apple.com/documentation"
		)

		let result = model.sync(
			tabs: [updatedTab],
			selectedTabID: tabID
		)

		XCTAssertTrue(result.tabsToAdd.isEmpty)
		XCTAssertTrue(result.tabIDsToRemove.isEmpty)
		XCTAssertEqual(result.selectedTabID, tabID)
	}

	func testRemovingMultipleTabsReturnsIdentifiersInUUIDOrder() throws {
		let model = BrowserTabHostViewModel()
		let aTab = try BrowserTabViewModel(
			id: XCTUnwrap(BrowserTabID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")),
			initialURL: "https://a.example"
		)
		let cTab = try BrowserTabViewModel(
			id: XCTUnwrap(BrowserTabID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")),
			initialURL: "https://c.example"
		)
		let bTab = try BrowserTabViewModel(
			id: XCTUnwrap(BrowserTabID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")),
			initialURL: "https://b.example"
		)
		_ = model.sync(tabs: [cTab, aTab, bTab], selectedTabID: aTab.id)

		let result = model.sync(
			tabs: [aTab],
			selectedTabID: aTab.id
		)

		XCTAssertEqual(result.tabIDsToRemove, [bTab.id, cTab.id])
	}
}
