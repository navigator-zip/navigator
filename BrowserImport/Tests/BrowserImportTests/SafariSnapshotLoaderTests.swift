@testable import BrowserImport
import Foundation
import ModelKit
import XCTest

final class SafariSnapshotLoaderTests: XCTestCase {
	func testLoadProfileImportsBookmarksAndSkipsReadingList() throws {
		let profileURL = makeTemporaryProfileURL()
		try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
		try writeBookmarksPlist(
			to: profileURL.appendingPathComponent("Bookmarks.plist"),
			root: makeBookmarksRoot()
		)

		let loader = SafariSnapshotLoader()
		let profile = BrowserProfile(
			id: "Safari",
			displayName: "Safari",
			profileURL: profileURL,
			isDefault: true
		)

		let importedProfile = try loader.loadProfile(
			source: .safari,
			profile: profile,
			dataKinds: [.bookmarks]
		)

		XCTAssertEqual(importedProfile.windows, [])
		XCTAssertEqual(importedProfile.historyEntries, [])
		XCTAssertEqual(importedProfile.bookmarkFolders.count, 1)

		let rootFolder = try XCTUnwrap(importedProfile.bookmarkFolders.first)
		XCTAssertEqual(rootFolder.displayName, "Bookmarks")
		XCTAssertEqual(rootFolder.childFolders.map(\.displayName), ["Favorites"])
		XCTAssertEqual(rootFolder.bookmarks.map(\.title), ["OpenAI"])

		let favoritesFolder = try XCTUnwrap(rootFolder.childFolders.first)
		XCTAssertEqual(favoritesFolder.bookmarks.map(\.title), ["Swift"])
	}

	func testLoadProfileImportsHistoryEntriesFromDatabase() throws {
		let profileURL = makeTemporaryProfileURL()
		try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
		try createHistoryDatabase(at: profileURL.appendingPathComponent("History.db"))

		let loader = SafariSnapshotLoader()
		let profile = BrowserProfile(
			id: "Safari",
			displayName: "Safari",
			profileURL: profileURL,
			isDefault: true
		)

		let importedProfile = try loader.loadProfile(
			source: .safari,
			profile: profile,
			dataKinds: [.history]
		)

		XCTAssertEqual(importedProfile.bookmarkFolders, [])
		XCTAssertEqual(importedProfile.historyEntries.count, 2)
		XCTAssertEqual(importedProfile.historyEntries.map(\.title), ["Second Visit", "First Visit"])
		XCTAssertEqual(
			importedProfile.historyEntries.map(\.url),
			["https://second.example", "https://first.example"]
		)
		XCTAssertGreaterThan(
			importedProfile.historyEntries[0].visitedAt,
			importedProfile.historyEntries[1].visitedAt
		)
	}

	func testLoadProfileReturnsEmptyCollectionsWhenFilesAreMissing() throws {
		let profileURL = makeTemporaryProfileURL()
		try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)

		let loader = SafariSnapshotLoader()
		let profile = BrowserProfile(
			id: "Safari",
			displayName: "Safari",
			profileURL: profileURL,
			isDefault: true
		)

		let importedProfile = try loader.loadProfile(
			source: .safari,
			profile: profile,
			dataKinds: [.bookmarks, .history]
		)

		XCTAssertEqual(importedProfile.bookmarkFolders, [])
		XCTAssertEqual(importedProfile.historyEntries, [])
	}

	private func makeTemporaryProfileURL() -> URL {
		FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
	}

	private func writeBookmarksPlist(to url: URL, root: [String: Any]) throws {
		let data = try PropertyListSerialization.data(
			fromPropertyList: root,
			format: .binary,
			options: 0
		)
		try data.write(to: url)
	}

	private func makeBookmarksRoot() -> [String: Any] {
		[
			"WebBookmarkType": "WebBookmarkTypeList",
			"Title": "Bookmarks",
			"Children": [
				[
					"WebBookmarkType": "WebBookmarkTypeLeaf",
					"URLString": "https://openai.com",
					"URIDictionary": [
						"title": "OpenAI",
					],
				],
				[
					"WebBookmarkType": "WebBookmarkTypeList",
					"Title": "Favorites",
					"Children": [
						[
							"WebBookmarkType": "WebBookmarkTypeLeaf",
							"URLString": "https://swift.org",
							"URIDictionary": [
								"title": "Swift",
							],
						],
					],
				],
				[
					"WebBookmarkType": "WebBookmarkTypeList",
					"Title": "Reading List",
					"WebBookmarkIdentifier": "com.apple.ReadingList",
					"Children": [
						[
							"WebBookmarkType": "WebBookmarkTypeLeaf",
							"URLString": "https://ignored.example",
							"URIDictionary": [
								"title": "Ignored",
							],
						],
					],
				],
			],
		]
	}

	private func createHistoryDatabase(at url: URL) throws {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
		process.arguments = [url.path]
		let inputPipe = Pipe()
		let errorPipe = Pipe()
		process.standardInput = inputPipe
		process.standardError = errorPipe

		try process.run()

		let sql = """
		CREATE TABLE history_items (
			id INTEGER PRIMARY KEY,
			url TEXT NOT NULL,
			title TEXT
		);
		CREATE TABLE history_visits (
			id INTEGER PRIMARY KEY,
			history_item INTEGER NOT NULL,
			visit_time REAL NOT NULL
		);
		INSERT INTO history_items (id, url, title) VALUES
			(1, 'https://first.example', 'First Visit'),
			(2, 'https://second.example', 'Second Visit');
		INSERT INTO history_visits (id, history_item, visit_time) VALUES
			(1, 1, 10),
			(2, 2, 20);
		"""

		inputPipe.fileHandleForWriting.write(Data(sql.utf8))
		try inputPipe.fileHandleForWriting.close()
		process.waitUntilExit()

		let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
		guard process.terminationStatus == 0 else {
			let errorMessage = String(data: errorData, encoding: .utf8) ?? "sqlite error"
			XCTFail(errorMessage)
			return
		}
	}
}
