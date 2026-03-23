@testable import BrowserImport
import Foundation
import ModelKit
import XCTest

final class BrowserSourceDiscovererTests: XCTestCase {
	func testDiscoverInstallationsFindsChromiumProfilesAndSafariData() throws {
		let homeDirectory = uniqueTestHomeDirectory()
		let fileManager = FileManager.default
		try fileManager.createDirectory(
			at: chromeRootURL(homeDirectory).appendingPathComponent("Default"),
			withIntermediateDirectories: true
		)
		try fileManager.createDirectory(
			at: chromeRootURL(homeDirectory).appendingPathComponent("Profile 2"),
			withIntermediateDirectories: true
		)
		try fileManager.createDirectory(
			at: safariRootURL(homeDirectory),
			withIntermediateDirectories: true
		)
		fileManager.createFile(
			atPath: safariRootURL(homeDirectory).appendingPathComponent("Bookmarks.plist").path,
			contents: Data()
		)

		let discoverer = BrowserSourceDiscoverer.testInstance(
			homeDirectory: homeDirectory,
			fileManager: fileManager
		)

		let installations = discoverer.discoverInstallations()

		XCTAssertEqual(installations.map(\.source), [.chrome, .safari])
		XCTAssertEqual(installations.first?.profiles.map(\.id), ["Default", "Profile 2"])
		XCTAssertEqual(installations.last?.profiles.map(\.displayName), ["Safari"])
	}

	func testCoordinatorBuildsPreviewFromSelectedProfiles() throws {
		let coordinator = BrowserImportCoordinator(
			discoverInstallations: {
				[
					BrowserInstallation(
						source: .chrome,
						displayName: "Chrome",
						profileRootURL: URL(fileURLWithPath: "/tmp/chrome"),
						profiles: [
							BrowserProfile(
								id: "Default",
								displayName: "Default",
								profileURL: URL(fileURLWithPath: "/tmp/chrome/Default"),
								isDefault: true
							),
						]
					),
				]
			},
			loadProfileSnapshot: { _, profile, dataKinds in
				XCTAssertEqual(profile.id, "Default")
				XCTAssertEqual(dataKinds, [.tabs, .bookmarks])
				return ImportedBrowserProfile(
					id: profile.id,
					displayName: profile.displayName,
					isDefault: profile.isDefault,
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
									]
								),
							],
							selectedTabID: "tab-1"
						),
					],
					bookmarkFolders: [
						ImportedBookmarkFolder(
							id: "folder-1",
							displayName: "Bookmarks Bar",
							childFolders: [],
							bookmarks: [
								ImportedBookmark(
									id: "bookmark-1",
									title: "Navigator",
									url: "https://navigator.example",
									addedAt: nil,
									isFavorite: false
								),
							]
						),
					],
					historyEntries: []
				)
			},
			loadRunningWindows: { _ in
				[]
			}
		)

		let preview = try coordinator.previewImport(
			for: BrowserImportSelection(
				source: .chrome,
				profileIDs: ["Default"],
				dataKinds: [.tabs, .bookmarks],
				conflictMode: .replaceCurrentData
			)
		)

		XCTAssertEqual(
			preview,
			BrowserImportPreview(
				workspaceCount: 1,
				tabGroupCount: 1,
				tabCount: 1,
				bookmarkFolderCount: 1,
				bookmarkCount: 1,
				historyEntryCount: 0
			)
		)
	}

	private func uniqueTestHomeDirectory() -> URL {
		FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
	}

	private func chromeRootURL(_ homeDirectory: URL) -> URL {
		homeDirectory
			.appendingPathComponent("Library", isDirectory: true)
			.appendingPathComponent("Application Support", isDirectory: true)
			.appendingPathComponent("Google", isDirectory: true)
			.appendingPathComponent("Chrome", isDirectory: true)
	}

	private func safariRootURL(_ homeDirectory: URL) -> URL {
		homeDirectory
			.appendingPathComponent("Library", isDirectory: true)
			.appendingPathComponent("Safari", isDirectory: true)
	}
}

private extension BrowserSourceDiscoverer {
	static func testInstance(
		homeDirectory: URL,
		fileManager: FileManager
	) -> BrowserSourceDiscoverer {
		BrowserSourceDiscoverer(homeDirectory: homeDirectory, fileManager: fileManager)
	}
}
