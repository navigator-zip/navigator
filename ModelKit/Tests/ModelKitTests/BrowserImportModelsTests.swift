import ModelKit
import XCTest

final class BrowserImportModelsTests: XCTestCase {
	func testSnapshotPreviewAggregatesCountsAcrossProfilesAndFolders() {
		let snapshot = ImportedBrowserSnapshot(
			source: .chrome,
			profiles: [
				ImportedBrowserProfile(
					id: "profile-default",
					displayName: "Default",
					isDefault: true,
					windows: [
						ImportedBrowserWindow(
							id: "window-1",
							displayName: "Window 1",
							tabGroups: [
								ImportedTabGroup(
									id: "group-1",
									displayName: "Window 1",
									kind: .browserWindow,
									colorHex: nil,
									tabs: [
										ImportedTab(
											id: "tab-1",
											title: "Navigator",
											url: "https://navigator.example",
											isPinned: false,
											isFavorite: false,
											lastActiveAt: nil
										),
										ImportedTab(
											id: "tab-2",
											title: "Docs",
											url: "https://docs.example",
											isPinned: true,
											isFavorite: false,
											lastActiveAt: nil
										),
									]
								),
							],
							selectedTabID: "tab-2"
						),
					],
					bookmarkFolders: [
						ImportedBookmarkFolder(
							id: "folder-root",
							displayName: "Bookmarks Bar",
							childFolders: [
								ImportedBookmarkFolder(
									id: "folder-child",
									displayName: "Reference",
									childFolders: [],
									bookmarks: [
										ImportedBookmark(
											id: "bookmark-2",
											title: "Docs",
											url: "https://docs.example",
											addedAt: nil,
											isFavorite: false
										),
									]
								),
							],
							bookmarks: [
								ImportedBookmark(
									id: "bookmark-1",
									title: "Navigator",
									url: "https://navigator.example",
									addedAt: nil,
									isFavorite: true
								),
							]
						),
					],
					historyEntries: [
						ImportedHistoryEntry(
							id: "history-1",
							title: "Navigator",
							url: "https://navigator.example",
							visitedAt: .distantPast
						),
					]
				),
			]
		)

		XCTAssertEqual(
			snapshot.preview,
			BrowserImportPreview(
				workspaceCount: 1,
				tabGroupCount: 1,
				tabCount: 2,
				bookmarkFolderCount: 2,
				bookmarkCount: 2,
				historyEntryCount: 1
			)
		)
		XCTAssertFalse(snapshot.isEmpty)
	}

	func testEmptySnapshotReportsEmptyPreview() {
		let snapshot = ImportedBrowserSnapshot(source: .safari, profiles: [])

		XCTAssertEqual(snapshot.preview, .empty)
		XCTAssertTrue(snapshot.isEmpty)
	}

	func testLibraryReplacingRecordKeepsLatestSnapshotPerSource() {
		let chromeSnapshot = ImportedBrowserSnapshot(
			source: .chrome,
			profiles: []
		)
		let safariSnapshot = ImportedBrowserSnapshot(
			source: .safari,
			profiles: []
		)

		let library = ImportedBrowserLibrary.empty
			.replacingRecord(
				for: .chrome,
				with: chromeSnapshot,
				importedAt: .distantPast
			)
			.replacingRecord(
				for: .safari,
				with: safariSnapshot,
				importedAt: .distantFuture
			)

		XCTAssertEqual(library.records.count, 2)
		XCTAssertEqual(library.latestRecord?.snapshot.source, .safari)
	}

	func testBrowserImportEventEqualityTracksPayloads() {
		let profile = ImportedBrowserProfile(
			id: "Default",
			displayName: "Default",
			isDefault: true,
			windows: [],
			bookmarkFolders: [],
			historyEntries: []
		)
		let snapshot = ImportedBrowserSnapshot(
			source: .chrome,
			profiles: [profile]
		)

		XCTAssertEqual(
			BrowserImportEvent.profileImported(.chrome, profile),
			.profileImported(.chrome, profile)
		)
		XCTAssertEqual(BrowserImportEvent.finished(snapshot), .finished(snapshot))
		XCTAssertNotEqual(
			BrowserImportEvent.started(.chrome),
			BrowserImportEvent.started(.safari)
		)
	}
}
