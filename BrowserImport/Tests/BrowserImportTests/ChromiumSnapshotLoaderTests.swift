@testable import BrowserImport
import Foundation
import ModelKit
import XCTest

final class ChromiumSnapshotLoaderTests: XCTestCase {
	func testLoadProfileParsesBookmarksFileIntoImportedFolders() throws {
		let profileURL = uniqueProfileURL()
		try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
		try writeBookmarksFixture(
			to: profileURL.appendingPathComponent("Bookmarks", isDirectory: false)
		)

		let importedProfile = try ChromiumSnapshotLoader().loadProfile(
			source: .chrome,
			profile: BrowserProfile(
				id: "Default",
				displayName: "Default",
				profileURL: profileURL,
				isDefault: true
			),
			dataKinds: [.bookmarks]
		)

		XCTAssertEqual(
			Set(importedProfile.bookmarkFolders.map(\.displayName)),
			Set(["Bookmarks Bar", "Other bookmarks"])
		)
		let bookmarksBarFolder = try XCTUnwrap(
			importedProfile.bookmarkFolders.first(where: { $0.displayName == "Bookmarks Bar" })
		)
		let otherBookmarksFolder = try XCTUnwrap(
			importedProfile.bookmarkFolders.first(where: { $0.displayName == "Other bookmarks" })
		)
		XCTAssertEqual(bookmarksBarFolder.bookmarks.map(\.title), ["Navigator"])
		XCTAssertEqual(bookmarksBarFolder.childFolders.first?.bookmarks.map(\.title), ["Docs"])
		XCTAssertEqual(otherBookmarksFolder.bookmarks.map(\.title), ["Archive"])
		XCTAssertEqual(importedProfile.historyEntries, [])
		XCTAssertEqual(importedProfile.windows, [])
		XCTAssertNotNil(bookmarksBarFolder.bookmarks.first?.addedAt)
	}

	func testLoadProfileParsesArcSidebarIntoImportedFolders() throws {
		let arcRootURL = uniqueProfileURL()
		let profileURL = arcRootURL.appendingPathComponent("User Data/Default", isDirectory: true)
		try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
		try writeLegacyArcSidebarFixture(
			to: arcRootURL.appendingPathComponent("StorableSidebar.json", isDirectory: false)
		)

		let importedProfile = try ChromiumSnapshotLoader().loadProfile(
			source: .arc,
			profile: BrowserProfile(
				id: "Default",
				displayName: "Default",
				profileURL: profileURL,
				isDefault: true
			),
			dataKinds: [.bookmarks]
		)

		XCTAssertEqual(importedProfile.bookmarkFolders.map(\.displayName), ["Work", "Research"])
		let workFolder = try XCTUnwrap(
			importedProfile.bookmarkFolders.first(where: { $0.displayName == "Work" })
		)
		let readingList = try XCTUnwrap(workFolder.childFolders.first)
		XCTAssertEqual(workFolder.bookmarks.map(\.title), ["Navigator"])
		XCTAssertEqual(readingList.displayName, "Reading List")
		XCTAssertEqual(readingList.bookmarks.map(\.title), ["Docs"])
		XCTAssertEqual(
			importedProfile.bookmarkFolders.last?.bookmarks.map(\.title),
			["developer.apple.com"]
		)
	}

	func testLoadProfileParsesCurrentArcSyncSidebarIntoImportedFolders() throws {
		let arcRootURL = uniqueProfileURL()
		let profileURL = arcRootURL.appendingPathComponent("User Data/Default", isDirectory: true)
		try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
		try writeCurrentArcSidebarFixture(
			to: arcRootURL.appendingPathComponent("StorableSidebar.json", isDirectory: false)
		)

		let importedProfile = try ChromiumSnapshotLoader().loadProfile(
			source: .arc,
			profile: BrowserProfile(
				id: "Default",
				displayName: "Default",
				profileURL: profileURL,
				isDefault: true
			),
			dataKinds: [.bookmarks]
		)

		XCTAssertEqual(importedProfile.bookmarkFolders.map(\.displayName), ["Arc Basics"])
		let arcBasics = try XCTUnwrap(importedProfile.bookmarkFolders.first)
		XCTAssertEqual(arcBasics.childFolders, [])
		XCTAssertEqual(arcBasics.bookmarks.map(\.title), [
			"Arc Resources",
			"Import Logins & Bookmarks",
			"Try Arc Max",
			"The Browser Company",
			"Keeping Tabs",
			"Arc",
		])
		XCTAssertEqual(arcBasics.bookmarks.map(\.url), [
			"https://resources.arc.net/",
			"https://resources.arc.net/hc/en-us/articles/19335089616791-Import-Bookmarks-Logins-History-Extensions-from-Your-Previous-Browser",
			"https://arc.net/max/tutorial",
			"https://www.youtube.com/@TheBrowserCompany/videos",
			"https://browsercompany.substack.com/archive",
			"https://twitter.com/arcinternet",
		])
	}

	func testLoadProfileParsesCurrentArcSyncSidebarIntoImportedTabs() throws {
		let arcRootURL = uniqueProfileURL()
		let profileURL = arcRootURL.appendingPathComponent("User Data/Default", isDirectory: true)
		try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
		try writeCurrentArcSidebarFixture(
			to: arcRootURL.appendingPathComponent("StorableSidebar.json", isDirectory: false)
		)

		let importedProfile = try ChromiumSnapshotLoader().loadProfile(
			source: .arc,
			profile: BrowserProfile(
				id: "Default",
				displayName: "Default",
				profileURL: profileURL,
				isDefault: true
			),
			dataKinds: [.tabs]
		)

		XCTAssertEqual(importedProfile.windows.map(\.displayName), ["Space"])
		let spaceWindow = try XCTUnwrap(importedProfile.windows.first)
		XCTAssertEqual(spaceWindow.selectedTabID, nil)
		XCTAssertEqual(spaceWindow.tabGroups.map(\.kind), [.space])
		XCTAssertEqual(spaceWindow.tabGroups.first?.tabs.map(\.title), [
			"Arc Resources",
			"Import Logins & Bookmarks",
			"Try Arc Max",
			"The Browser Company",
			"Keeping Tabs",
			"Arc",
			"Loose Tab",
		])
		XCTAssertEqual(spaceWindow.tabGroups.first?.tabs.map(\.url), [
			"https://resources.arc.net/",
			"https://resources.arc.net/hc/en-us/articles/19335089616791-Import-Bookmarks-Logins-History-Extensions-from-Your-Previous-Browser",
			"https://arc.net/max/tutorial",
			"https://www.youtube.com/@TheBrowserCompany/videos",
			"https://browsercompany.substack.com/archive",
			"https://twitter.com/arcinternet",
			"https://example.com/loose",
		])
		XCTAssertEqual(spaceWindow.tabGroups.first?.tabs.map(\.isPinned), [
			false,
			false,
			false,
			false,
			false,
			false,
			false,
		])
	}

	func testLoadProfileParsesLiveArcSidebarIntoImportedFolders() throws {
		let arcRootURL = uniqueProfileURL()
		let profileURL = arcRootURL.appendingPathComponent("User Data/Default", isDirectory: true)
		try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
		try writeLiveArcSidebarFixture(
			to: arcRootURL.appendingPathComponent("StorableSidebar.json", isDirectory: false)
		)

		let importedProfile = try ChromiumSnapshotLoader().loadProfile(
			source: .arc,
			profile: BrowserProfile(
				id: "Default",
				displayName: "Default",
				profileURL: profileURL,
				isDefault: true
			),
			dataKinds: [.bookmarks]
		)

		XCTAssertEqual(importedProfile.bookmarkFolders.map(\.displayName), ["Arc Basics"])
		let arcBasics = try XCTUnwrap(importedProfile.bookmarkFolders.first)
		XCTAssertEqual(arcBasics.bookmarks.map(\.title), [
			"Arc Resources",
			"Import Logins & Bookmarks",
			"Try Arc Max",
			"The Browser Company",
			"Keeping Tabs",
			"Arc",
		])
	}

	func testLoadProfileParsesLiveArcSidebarIntoImportedTabs() throws {
		let arcRootURL = uniqueProfileURL()
		let profileURL = arcRootURL.appendingPathComponent("User Data/Default", isDirectory: true)
		try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
		try writeLiveArcSidebarFixture(
			to: arcRootURL.appendingPathComponent("StorableSidebar.json", isDirectory: false)
		)

		let importedProfile = try ChromiumSnapshotLoader().loadProfile(
			source: .arc,
			profile: BrowserProfile(
				id: "Default",
				displayName: "Default",
				profileURL: profileURL,
				isDefault: true
			),
			dataKinds: [.tabs]
		)

		XCTAssertEqual(importedProfile.windows.map(\.displayName), ["Space"])
		let spaceWindow = try XCTUnwrap(importedProfile.windows.first)
		XCTAssertEqual(spaceWindow.tabGroups.first?.tabs.map(\.title), [
			"Arc Resources",
			"Import Logins & Bookmarks",
			"Try Arc Max",
			"The Browser Company",
			"Keeping Tabs",
			"Arc",
			"Loose Tab",
		])
		XCTAssertEqual(spaceWindow.tabGroups.first?.tabs.map(\.isPinned), [
			false,
			false,
			false,
			false,
			false,
			false,
			false,
		])
	}

	func testLoadArcProfileChunksStreamsCurrentSidebarPerSpace() throws {
		let arcRootURL = uniqueProfileURL()
		let profileURL = arcRootURL.appendingPathComponent("User Data/Default", isDirectory: true)
		try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
		try writeCurrentArcSidebarFixture(
			to: arcRootURL.appendingPathComponent("StorableSidebar.json", isDirectory: false)
		)

		let chunks = try ChromiumSnapshotLoader().loadProfileChunks(
			source: .arc,
			profile: BrowserProfile(
				id: "Default",
				displayName: "Default",
				profileURL: profileURL,
				isDefault: true
			),
			dataKinds: [.tabs, .bookmarks]
		)

		XCTAssertEqual(chunks.count, 1)
		XCTAssertEqual(chunks[0].windows.map(\.displayName), ["Space"])
		XCTAssertEqual(chunks[0].bookmarkFolders.map(\.displayName), ["Space"])
		XCTAssertEqual(chunks[0].bookmarkFolders.first?.childFolders.map(\.displayName), ["Arc Basics"])
	}

	func testLoadArcProfileChunkStreamYieldsSidebarBeforeHistory() async throws {
		let arcRootURL = uniqueProfileURL()
		let profileURL = arcRootURL.appendingPathComponent("User Data/Default", isDirectory: true)
		try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
		try writeCurrentArcSidebarFixture(
			to: arcRootURL.appendingPathComponent("StorableSidebar.json", isDirectory: false)
		)
		try createHistoryDatabase(
			at: profileURL.appendingPathComponent("History", isDirectory: false)
		)

		let profile = BrowserProfile(
			id: "Default",
			displayName: "Default",
			profileURL: profileURL,
			isDefault: true
		)
		var chunks = [ImportedBrowserProfile]()
		for try await chunk in ChromiumSnapshotLoader().loadProfileChunkStream(
			source: .arc,
			profile: profile,
			dataKinds: [.tabs, .history]
		) {
			chunks.append(chunk)
		}

		XCTAssertEqual(chunks.count, 2)
		XCTAssertEqual(chunks[0].windows.map(\.displayName), ["Space"])
		XCTAssertEqual(chunks[0].historyEntries, [])
		XCTAssertEqual(chunks[1].windows, [])
		XCTAssertEqual(chunks[1].historyEntries.map(\.title), ["Navigator Docs", "Navigator"])
	}

	func testArcSidebarParserYieldsFirstChunkBeforeTrailingParseFailure() async throws {
		let arcRootURL = uniqueProfileURL()
		let profileURL = arcRootURL.appendingPathComponent("User Data/Default", isDirectory: true)
		try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
		try writePartiallyMalformedCurrentArcSidebarFixture(
			to: arcRootURL.appendingPathComponent("StorableSidebar.json", isDirectory: false)
		)

		var chunks = [ArcSidebarProfileChunk]()
		do {
			for try await chunk in ArcSidebarBookmarksParser().loadProfileChunkStream(
				source: .arc,
				profileURL: profileURL
			) {
				chunks.append(chunk)
			}
			XCTFail("Expected trailing parse failure")
		}
		catch {
			let window = try XCTUnwrap(chunks.first?.window)
			XCTAssertEqual(chunks.count, 1)
			XCTAssertEqual(window.displayName, "Space 1")
			XCTAssertEqual(window.tabGroups.first?.tabs.map(\.title), ["One"])
		}
	}

	func testLoadProfileSkipsArcGlobalTabsForNonDefaultProfiles() throws {
		let arcRootURL = uniqueProfileURL()
		let profileURL = arcRootURL.appendingPathComponent("User Data/Profile 2", isDirectory: true)
		try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
		try writeCurrentArcSidebarFixture(
			to: arcRootURL.appendingPathComponent("StorableSidebar.json", isDirectory: false)
		)

		let importedProfile = try ChromiumSnapshotLoader().loadProfile(
			source: .arc,
			profile: BrowserProfile(
				id: "Profile 2",
				displayName: "Profile 2",
				profileURL: profileURL,
				isDefault: false
			),
			dataKinds: [.tabs]
		)

		XCTAssertEqual(importedProfile.windows, [])
	}

	func testLoadProfileSkipsArcGlobalBookmarksForNonDefaultProfiles() throws {
		let arcRootURL = uniqueProfileURL()
		let profileURL = arcRootURL.appendingPathComponent("User Data/Profile 2", isDirectory: true)
		try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
		try writeLegacyArcSidebarFixture(
			to: arcRootURL.appendingPathComponent("StorableSidebar.json", isDirectory: false)
		)

		let importedProfile = try ChromiumSnapshotLoader().loadProfile(
			source: .arc,
			profile: BrowserProfile(
				id: "Profile 2",
				displayName: "Profile 2",
				profileURL: profileURL,
				isDefault: false
			),
			dataKinds: [.bookmarks]
		)

		XCTAssertEqual(importedProfile.bookmarkFolders, [])
	}

	func testLoadProfileParsesHistoryDatabaseIntoImportedEntries() throws {
		let profileURL = uniqueProfileURL()
		try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
		try createHistoryDatabase(
			at: profileURL.appendingPathComponent("History", isDirectory: false)
		)

		let importedProfile = try ChromiumSnapshotLoader().loadProfile(
			source: .arc,
			profile: BrowserProfile(
				id: "Profile 2",
				displayName: "Profile 2",
				profileURL: profileURL,
				isDefault: false
			),
			dataKinds: [.history]
		)

		XCTAssertEqual(importedProfile.bookmarkFolders, [])
		XCTAssertEqual(importedProfile.historyEntries.map(\.title), ["Navigator Docs", "Navigator"])
		XCTAssertEqual(importedProfile.historyEntries.map(\.url), [
			"https://docs.navigator.example",
			"https://navigator.example",
		])
		XCTAssertGreaterThan(
			importedProfile.historyEntries[0].visitedAt,
			importedProfile.historyEntries[1].visitedAt
		)
	}

	func testLoadProfileReturnsEmptyCollectionsWhenChromiumArtifactsAreMissing() throws {
		let profileURL = uniqueProfileURL()
		try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)

		let importedProfile = try ChromiumSnapshotLoader().loadProfile(
			source: .chrome,
			profile: BrowserProfile(
				id: "Default",
				displayName: "Default",
				profileURL: profileURL,
				isDefault: true
			),
			dataKinds: [.bookmarks, .history]
		)

		XCTAssertEqual(importedProfile.bookmarkFolders, [])
		XCTAssertEqual(importedProfile.historyEntries, [])
	}

	private func uniqueProfileURL() -> URL {
		FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
	}

	private func writeBookmarksFixture(to url: URL) throws {
		let fixture = """
		{
		  "roots": {
		    "bookmark_bar": {
		      "children": [
		        {
		          "date_added": "13380163200000000",
		          "id": "10",
		          "name": "Navigator",
		          "type": "url",
		          "url": "https://navigator.example"
		        },
		        {
		          "children": [
		            {
		              "date_added": "13380163300000000",
		              "id": "12",
		              "name": "Docs",
		              "type": "url",
		              "url": "https://docs.navigator.example"
		            }
		          ],
		          "date_added": "13380163250000000",
		          "id": "11",
		          "name": "Reference",
		          "type": "folder"
		        }
		      ],
		      "id": "1",
		      "name": "",
		      "type": "folder"
		    },
		    "other": {
		      "children": [
		        {
		          "date_added": "13380163400000000",
		          "id": "13",
		          "name": "Archive",
		          "type": "url",
		          "url": "https://archive.navigator.example"
		        }
		      ],
		      "id": "2",
		      "name": "Other bookmarks",
		      "type": "folder"
		    },
		    "synced": {
		      "children": [],
		      "id": "3",
		      "name": "Mobile bookmarks",
		      "type": "folder"
		    }
		  }
		}
		"""

		try fixture.data(using: .utf8).unwrap().write(to: url)
	}

	private func createHistoryDatabase(at databaseURL: URL) throws {
		let createCommand = """
		CREATE TABLE urls (
		  id INTEGER PRIMARY KEY,
		  url LONGVARCHAR,
		  title LONGVARCHAR,
		  last_visit_time INTEGER
		);
		INSERT INTO urls (id, url, title, last_visit_time) VALUES
		  (1, 'https://navigator.example', 'Navigator', 13380163200000000),
		  (2, 'https://docs.navigator.example', 'Navigator Docs', 13380163300000000);
		"""

		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
		process.arguments = [databaseURL.path, createCommand]
		try process.run()
		process.waitUntilExit()
		XCTAssertEqual(process.terminationStatus, 0)
	}

	private func writeLegacyArcSidebarFixture(to url: URL) throws {
		let fixture = """
		[
		  {
		    "global": {
		      "sidebarSyncState": {
		        "containers": [
		          {
		            "containerType": 1,
		            "containerID": "space-work",
		            "spaceItems": ["folder-reading", "tab-home", "tab-ignored"]
		          },
		          {
		            "containerType": 1,
		            "containerID": "space-research",
		            "spaceItems": ["tab-apple"]
		          }
		        ],
		        "items": [
		          {
		            "id": "space-work",
		            "containerType": 2,
		            "data": { "tab": { "savedTitle": "Work" } }
		          },
		          {
		            "id": "space-research",
		            "containerType": 2,
		            "data": { "tab": { "savedTitle": "Research" } }
		          },
		          {
		            "id": "folder-reading",
		            "containerType": 1,
		            "childrenIds": ["tab-docs"],
		            "data": { "tab": { "savedTitle": "Reading List" } }
		          },
		          {
		            "id": "tab-home",
		            "containerType": 0,
		            "isPinned": true,
		            "data": {
		              "tab": {
		                "savedTitle": "Navigator",
		                "savedURL": "https://navigator.example"
		              }
		            }
		          },
		          {
		            "id": "tab-docs",
		            "containerType": 0,
		            "isPinned": true,
		            "data": {
		              "tab": {
		                "savedTitle": "Docs",
		                "savedURL": "https://docs.navigator.example"
		              }
		            }
		          },
		          {
		            "id": "tab-apple",
		            "containerType": 0,
		            "isPinned": true,
		            "data": {
		              "tab": {
		                "savedTitle": "",
		                "savedURL": "https://developer.apple.com"
		              }
		            }
		          },
		          {
		            "id": "tab-ignored",
		            "containerType": 0,
		            "isPinned": false,
		            "data": {
		              "tab": {
		                "savedTitle": "Ignored",
		                "savedURL": "https://ignored.example"
		              }
		            }
		          }
		        ]
		      }
		    }
		  }
		]
		"""

		try fixture.data(using: .utf8).unwrap().write(to: url)
	}

	private func writeLiveArcSidebarFixture(to url: URL) throws {
		let fixture = """
		{
		  "sidebar": {
		    "containers": [
		      {
		        "global": {}
		      },
		      {
		        "items": [
		          "thebrowser.company.arcBasics.splitViewID",
		          {
		            "parentID": "thebrowser.company.arcBasicsFolderID",
		            "childrenIds": [
		              "browserCompanySubstack",
		              "arcTwitter"
		            ],
		            "id": "thebrowser.company.arcBasics.splitViewID",
		            "title": null,
		            "data": {
		              "splitView": {
		                "layoutOrientation": "horizontal"
		              }
		            },
		            "isUnread": false
		          },
		          "thebrowser.company.arcBasicsFolderID",
		          {
		            "parentID": "thebrowser.company.defaultPersonalSpacePinnedContainerID",
		            "childrenIds": [
		              "arcResources",
		              "importLoginsAndBookmarks",
		              "arcMaxTutorial",
		              "browserCompanyYouTube",
		              "thebrowser.company.arcBasics.splitViewID"
		            ],
		            "id": "thebrowser.company.arcBasicsFolderID",
		            "title": "Arc Basics",
		            "data": {
		              "list": {}
		            },
		            "isUnread": false
		          },
		          "thebrowser.company.defaultPersonalSpacePinnedContainerID",
		          {
		            "parentID": null,
		            "childrenIds": [
		              "thebrowser.company.arcBasicsFolderID"
		            ],
		            "id": "thebrowser.company.defaultPersonalSpacePinnedContainerID",
		            "title": null,
		            "data": {
		              "itemContainer": {
		                "containerType": {
		                  "spaceItems": {
		                    "_0": "thebrowser.company.defaultPersonalSpaceID"
		                  }
		                }
		              }
		            },
		            "isUnread": false
		          },
		          "thebrowser.company.defaultPersonalSpaceUnpinnedContainerID",
		          {
		            "parentID": null,
		            "childrenIds": [
		              "firebase-loose-tab"
		            ],
		            "id": "thebrowser.company.defaultPersonalSpaceUnpinnedContainerID",
		            "title": null,
		            "data": {
		              "itemContainer": {
		                "containerType": {
		                  "spaceItems": {
		                    "_0": "thebrowser.company.defaultPersonalSpaceID"
		                  }
		                }
		              }
		            },
		            "isUnread": false
		          },
		          "browserCompanyYouTube",
		          {
		            "parentID": "thebrowser.company.arcBasicsFolderID",
		            "childrenIds": [],
		            "id": "browserCompanyYouTube",
		            "title": "The Browser Company",
		            "isUnread": false,
		            "data": {
		              "tab": {
		                "savedMuteStatus": "allowAudio",
		                "savedTitle": "The Browser Company",
		                "savedURL": "https://www.youtube.com/@TheBrowserCompany/videos"
		              }
		            }
		          },
		          "arcMaxTutorial",
		          {
		            "parentID": "thebrowser.company.arcBasicsFolderID",
		            "childrenIds": [],
		            "id": "arcMaxTutorial",
		            "title": "Try Arc Max",
		            "isUnread": false,
		            "data": {
		              "tab": {
		                "savedURL": "https://arc.net/max/tutorial",
		                "savedMuteStatus": "allowAudio",
		                "savedTitle": "Try Arc Max"
		              }
		            }
		          },
		          "browserCompanySubstack",
		          {
		            "parentID": "thebrowser.company.arcBasics.splitViewID",
		            "childrenIds": [],
		            "id": "browserCompanySubstack",
		            "title": "Keeping Tabs",
		            "isUnread": false,
		            "data": {
		              "tab": {
		                "savedTitle": "Keeping Tabs",
		                "savedURL": "https://browsercompany.substack.com/archive",
		                "savedMuteStatus": "allowAudio"
		              }
		            }
		          },
		          "arcTwitter",
		          {
		            "parentID": "thebrowser.company.arcBasics.splitViewID",
		            "childrenIds": [],
		            "id": "arcTwitter",
		            "title": "Arc",
		            "isUnread": false,
		            "data": {
		              "tab": {
		                "savedURL": "https://twitter.com/arcinternet",
		                "savedTitle": "Arc",
		                "savedMuteStatus": "allowAudio"
		              }
		            }
		          },
		          "arcResources",
		          {
		            "id": "arcResources",
		            "parentID": "thebrowser.company.arcBasicsFolderID",
		            "childrenIds": [],
		            "title": "Arc Resources",
		            "isUnread": false,
		            "data": {
		              "tab": {
		                "savedTitle": "Arc Resources",
		                "savedURL": "https://resources.arc.net/",
		                "savedMuteStatus": "allowAudio"
		              }
		            }
		          },
		          "importLoginsAndBookmarks",
		          {
		            "id": "importLoginsAndBookmarks",
		            "parentID": "thebrowser.company.arcBasicsFolderID",
		            "childrenIds": [],
		            "title": "Import Logins & Bookmarks",
		            "isUnread": false,
		            "data": {
		              "tab": {
		                "savedURL": "https://resources.arc.net/hc/en-us/articles/19335089616791-Import-Bookmarks-Logins-History-Extensions-from-Your-Previous-Browser",
		                "savedTitle": "Import Logins & Bookmarks",
		                "savedMuteStatus": "allowAudio"
		              }
		            }
		          },
		          "firebase-loose-tab",
		          {
		            "id": "firebase-loose-tab",
		            "parentID": "thebrowser.company.defaultPersonalSpaceUnpinnedContainerID",
		            "childrenIds": [],
		            "title": null,
		            "isUnread": false,
		            "data": {
		              "tab": {
		                "savedURL": "https://example.com/loose",
		                "savedTitle": "Loose Tab",
		                "savedMuteStatus": "allowAudio"
		              }
		            }
		          }
		        ],
		        "spaces": [
		          "thebrowser.company.defaultPersonalSpaceID",
		          {
		            "id": "thebrowser.company.defaultPersonalSpaceID",
		            "title": null,
		            "containerIDs": [
		              "pinned",
		              "thebrowser.company.defaultPersonalSpacePinnedContainerID",
		              "unpinned",
		              "thebrowser.company.defaultPersonalSpaceUnpinnedContainerID"
		            ],
		            "newContainerIDs": [
		              {
		                "pinned": {}
		              },
		              "thebrowser.company.defaultPersonalSpacePinnedContainerID",
		              {
		                "unpinned": {
		                  "_0": {
		                    "shared": {}
		                  }
		                }
		              },
		              "thebrowser.company.defaultPersonalSpaceUnpinnedContainerID"
		            ],
		            "profile": {
		              "default": true
		            }
		          }
		        ]
		      }
		    ]
		  }
		}
		"""

		try fixture.data(using: .utf8).unwrap().write(to: url)
	}

	private func writeCurrentArcSidebarFixture(to url: URL) throws {
		let fixture = """
			{
			  "firebaseSyncState": {
			    "syncData": {
			      "dataEra": 1,
			      "orderedSpaceIDs": {
			        "value": [
			          "thebrowser.company.defaultPersonalSpaceID"
			        ],
			        "lastChangeDate": 794617260.0780001,
			        "lastChangedDevice": "4D4E5942-0E60-453B-96B8-699AC621BA5E"
			      },
			      "spaceModels": [
			        "thebrowser.company.defaultPersonalSpaceID",
			        {
			          "value": {
			            "id": "thebrowser.company.defaultPersonalSpaceID",
			            "title": null,
			            "containerIDs": [
			              "pinned",
			              "thebrowser.company.defaultPersonalSpacePinnedContainerID",
			              "unpinned",
			              "thebrowser.company.defaultPersonalSpaceUnpinnedContainerID"
			            ],
			            "newContainerIDs": [
			              {
			                "pinned": {}
			              },
			              "thebrowser.company.defaultPersonalSpacePinnedContainerID",
			              {
			                "unpinned": {
			                  "_0": {
			                    "shared": {}
			                  }
			                }
			              },
			              "thebrowser.company.defaultPersonalSpaceUnpinnedContainerID"
			            ],
			            "profile": {
			              "default": true
			            }
			          },
			          "lastChangeDate": 794617260.0780001,
			          "lastChangedDevice": "4D4E5942-0E60-453B-96B8-699AC621BA5E"
			        }
			      ],
			      "items": [
			        "thebrowser.company.arcBasics.splitViewID",
			        {
			          "value": {
			            "parentID": "thebrowser.company.arcBasicsFolderID",
			            "childrenIds": [
			              "browserCompanySubstack",
			              "arcTwitter"
			            ],
			            "id": "thebrowser.company.arcBasics.splitViewID",
			            "title": null,
			            "data": {
			              "splitView": {
			                "layoutOrientation": "horizontal",
			                "timeLastActiveAt": null,
			                "itemWidthFactors": [],
			                "focusItemID": null,
			                "customInfo": null
			              }
			            },
			            "isUnread": false
			          }
			        },
			        "thebrowser.company.arcBasicsFolderID",
			        {
			          "value": {
			            "parentID": "thebrowser.company.defaultPersonalSpacePinnedContainerID",
			            "childrenIds": [
			              "arcResources",
			              "importLoginsAndBookmarks",
			              "arcMaxTutorial",
			              "browserCompanyYouTube",
			              "thebrowser.company.arcBasics.splitViewID"
			            ],
			            "id": "thebrowser.company.arcBasicsFolderID",
			            "title": "Arc Basics",
			            "data": {
			              "list": {}
			            },
			            "isUnread": false
			          }
			        },
			        "thebrowser.company.defaultPersonalSpacePinnedContainerID",
			        {
			          "value": {
			            "parentID": null,
			            "childrenIds": [
			              "thebrowser.company.arcBasicsFolderID"
			            ],
			            "id": "thebrowser.company.defaultPersonalSpacePinnedContainerID",
			            "title": null,
			            "data": {
			              "itemContainer": {
			                "containerType": {
			                  "spaceItems": {
			                    "_0": "thebrowser.company.defaultPersonalSpaceID"
			                  }
			                }
			              }
			            },
			            "isUnread": false
			          }
			        },
			        "thebrowser.company.defaultPersonalSpaceUnpinnedContainerID",
			        {
			          "value": {
			            "parentID": null,
			            "childrenIds": [
			              "firebase-loose-tab"
			            ],
			            "id": "thebrowser.company.defaultPersonalSpaceUnpinnedContainerID",
			            "title": null,
			            "data": {
			              "itemContainer": {
			                "containerType": {
			                  "spaceItems": {
			                    "_0": "thebrowser.company.defaultPersonalSpaceID"
			                  }
			                }
			              }
			            },
			            "isUnread": false
			          }
			        },
			        "browserCompanyYouTube",
			        {
			          "value": {
			            "parentID": "thebrowser.company.arcBasicsFolderID",
			            "childrenIds": [],
			            "id": "browserCompanyYouTube",
			            "title": "The Browser Company",
			            "isUnread": false,
			            "data": {
			              "tab": {
			                "savedMuteStatus": "allowAudio",
			                "savedTitle": "The Browser Company",
			                "savedURL": "https://www.youtube.com/@TheBrowserCompany/videos"
			              }
			            }
			          }
			        },
			        "arcMaxTutorial",
			        {
			          "value": {
			            "parentID": "thebrowser.company.arcBasicsFolderID",
			            "childrenIds": [],
			            "id": "arcMaxTutorial",
			            "title": "Try Arc Max",
			            "isUnread": false,
			            "data": {
			              "tab": {
			                "savedURL": "https://arc.net/max/tutorial",
			                "savedMuteStatus": "allowAudio",
			                "savedTitle": "Try Arc Max"
			              }
			            }
			          }
			        },
			        "browserCompanySubstack",
			        {
			          "value": {
			            "parentID": "thebrowser.company.arcBasics.splitViewID",
			            "childrenIds": [],
			            "id": "browserCompanySubstack",
			            "title": "Keeping Tabs",
			            "isUnread": false,
			            "data": {
			              "tab": {
			                "savedTitle": "Keeping Tabs",
			                "savedURL": "https://browsercompany.substack.com/archive",
			                "savedMuteStatus": "allowAudio"
			              }
			            }
			          }
			        },
			        "arcTwitter",
			        {
			          "value": {
			            "parentID": "thebrowser.company.arcBasics.splitViewID",
			            "childrenIds": [],
			            "id": "arcTwitter",
			            "title": "Arc",
			            "isUnread": false,
			            "data": {
			              "tab": {
			                "savedURL": "https://twitter.com/arcinternet",
			                "savedTitle": "Arc",
			                "savedMuteStatus": "allowAudio"
			              }
			            }
			          }
			        },
			        "arcResources",
			        {
			          "value": {
			            "id": "arcResources",
			            "parentID": "thebrowser.company.arcBasicsFolderID",
			            "childrenIds": [],
			            "title": "Arc Resources",
			            "isUnread": false,
			            "data": {
			              "tab": {
			                "savedTitle": "Arc Resources",
			                "savedURL": "https://resources.arc.net/",
			                "savedMuteStatus": "allowAudio"
			              }
			            }
			          }
			        },
			        "importLoginsAndBookmarks",
			        {
			          "value": {
			            "id": "importLoginsAndBookmarks",
			            "parentID": "thebrowser.company.arcBasicsFolderID",
			            "childrenIds": [],
			            "title": "Import Logins & Bookmarks",
			            "isUnread": false,
			            "data": {
			              "tab": {
			                "savedURL": "https://resources.arc.net/hc/en-us/articles/19335089616791-Import-Bookmarks-Logins-History-Extensions-from-Your-Previous-Browser",
			                "savedTitle": "Import Logins & Bookmarks",
			                "savedMuteStatus": "allowAudio"
			              }
			            }
			          }
			        },
			        "firebase-loose-tab",
			        {
			          "value": {
			            "id": "firebase-loose-tab",
			            "parentID": "thebrowser.company.defaultPersonalSpaceUnpinnedContainerID",
			            "childrenIds": [],
			            "title": null,
			            "isUnread": false,
			            "data": {
			              "tab": {
			                "savedURL": "https://example.com/loose",
			                "savedTitle": "Loose Tab",
			                "savedMuteStatus": "allowAudio"
			              }
			            }
			          }
			        }
			      ]
			    }
			  },
		  "sidebarSyncState": {
		    "spaceModels": [
		      "thebrowser.company.defaultPersonalSpaceID",
		      {
		        "value": {
		          "customInfo": {
		            "iconType": {
		              "icon": "planet"
		            }
		          },
		          "newContainerIDs": [
		            {
		              "pinned": {}
		            },
		            "thebrowser.company.defaultPersonalSpacePinnedContainerID",
		            {
		              "unpinned": {
		                "_0": {
		                  "shared": {}
		                }
		              }
		            },
		            "thebrowser.company.defaultPersonalSpaceUnpinnedContainerID"
		          ],
		          "id": "thebrowser.company.defaultPersonalSpaceID",
		          "profile": {
		            "default": true
		          },
		          "containerIDs": [
		            "unpinned",
		            "thebrowser.company.defaultPersonalSpaceUnpinnedContainerID",
		            "pinned",
		            "thebrowser.company.defaultPersonalSpacePinnedContainerID"
		          ]
		        }
		      }
		    ],
		    "container": {
		      "lastChangeDate": 790468133.712405,
		      "value": {
		        "topAppsContainerIDs": [
		          {
		            "default": true
		          },
		          "F641F664-F6DA-40CB-B325-6B5A11A442D3"
		        ],
		        "topAppsContainerID": "F641F664-F6DA-40CB-B325-6B5A11A442D3",
		        "orderedSpaceIDs": [
		          "thebrowser.company.defaultPersonalSpaceID"
		        ],
		        "version": 6
		      }
		    },
		    "items": [
		      "thebrowser.company.arcBasics.splitViewID",
		      {
		        "value": {
		          "parentID": "thebrowser.company.arcBasicsFolderID",
		          "childrenIds": [
		            "browserCompanySubstack",
		            "arcTwitter"
		          ],
		          "id": "thebrowser.company.arcBasics.splitViewID",
		          "originatingDevice": "4D4E5942-0E60-453B-96B8-699AC621BA5E",
		          "title": null,
		          "isUnread": false,
		          "createdAt": 790468131.919036,
		          "data": {
		            "splitView": {
		              "customInfo": null,
		              "layoutOrientation": "horizontal",
		              "timeLastActiveAt": null,
		              "itemWidthFactors": [],
		              "focusItemID": null
		            }
		          }
		        }
		      },
		      "thebrowser.company.arcBasicsFolderID",
		      {
		        "value": {
		          "parentID": "thebrowser.company.defaultPersonalSpacePinnedContainerID",
		          "childrenIds": [
		            "thebrowser.company.arcGettingStarted",
		            "arcResources",
		            "importLoginsAndBookmarks",
		            "arcMaxTutorial",
		            "browserCompanyYouTube",
		            "thebrowser.company.arcBasics.splitViewID"
		          ],
		          "id": "thebrowser.company.arcBasicsFolderID",
		          "originatingDevice": "4D4E5942-0E60-453B-96B8-699AC621BA5E",
		          "title": "Arc Basics",
		          "isUnread": false,
		          "createdAt": 790468131.919035,
		          "data": {
		            "list": {}
		          }
		        }
		      },
		      "thebrowser.company.defaultPersonalSpacePinnedContainerID",
		      {
		        "value": {
		          "parentID": null,
		          "childrenIds": [
		            "thebrowser.company.arcBasicsFolderID"
		          ],
		          "id": "thebrowser.company.defaultPersonalSpacePinnedContainerID",
		          "originatingDevice": "4D4E5942-0E60-453B-96B8-699AC621BA5E",
		          "title": null,
		          "isUnread": false,
		          "data": {
		            "itemContainer": {
		              "containerType": {
		                "spaceItems": {
		                  "_0": "thebrowser.company.defaultPersonalSpaceID"
		                }
		              }
		            }
		          },
		          "createdAt": 790468131.918884
		        }
		      },
		      "browserCompanyYouTube",
		      {
		        "value": {
		          "parentID": "thebrowser.company.arcBasicsFolderID",
		          "childrenIds": [],
		          "id": "browserCompanyYouTube",
		          "originatingDevice": "4D4E5942-0E60-453B-96B8-699AC621BA5E",
		          "title": "The Browser Company",
		          "isUnread": false,
		          "createdAt": 790468131.919036,
		          "data": {
		            "tab": {
		              "savedMuteStatus": "allowAudio",
		              "savedTitle": "The Browser Company",
		              "savedURL": "https://www.youtube.com/@TheBrowserCompany/videos"
		            }
		          }
		        }
		      },
		      "arcMaxTutorial",
		      {
		        "value": {
		          "parentID": "thebrowser.company.arcBasicsFolderID",
		          "childrenIds": [],
		          "id": "arcMaxTutorial",
		          "originatingDevice": "4D4E5942-0E60-453B-96B8-699AC621BA5E",
		          "title": "Try Arc Max",
		          "isUnread": false,
		          "data": {
		            "tab": {
		              "savedURL": "https://arc.net/max/tutorial",
		              "savedMuteStatus": "allowAudio",
		              "savedTitle": "Try Arc Max"
		            }
		          },
		          "createdAt": 790468131.919036
		        }
		      },
		      "thebrowser.company.arcGettingStarted",
		      {
		        "value": {
		          "parentID": "thebrowser.company.arcBasicsFolderID",
		          "childrenIds": [],
		          "id": "thebrowser.company.arcGettingStarted",
		          "originatingDevice": "4D4E5942-0E60-453B-96B8-699AC621BA5E",
		          "title": "Getting Started",
		          "isUnread": false,
		          "data": {
		            "welcomeToArc": {
		              "timeLastActiveAt": null,
		              "tabType": "legacy"
		            }
		          },
		          "createdAt": 790468131.919036
		        }
		      },
		      "browserCompanySubstack",
		      {
		        "value": {
		          "parentID": "thebrowser.company.arcBasics.splitViewID",
		          "childrenIds": [],
		          "id": "browserCompanySubstack",
		          "originatingDevice": "4D4E5942-0E60-453B-96B8-699AC621BA5E",
		          "title": "Keeping Tabs",
		          "isUnread": false,
		          "data": {
		            "tab": {
		              "savedTitle": "Keeping Tabs",
		              "savedURL": "https://browsercompany.substack.com/archive",
		              "savedMuteStatus": "allowAudio"
		            }
		          },
		          "createdAt": 790468131.919036
		        }
		      },
		      "arcTwitter",
		      {
		        "value": {
		          "parentID": "thebrowser.company.arcBasics.splitViewID",
		          "childrenIds": [],
		          "id": "arcTwitter",
		          "originatingDevice": "4D4E5942-0E60-453B-96B8-699AC621BA5E",
		          "title": "Arc",
		          "isUnread": false,
		          "data": {
		            "tab": {
		              "savedURL": "https://twitter.com/arcinternet",
		              "savedTitle": "Arc",
		              "savedMuteStatus": "allowAudio"
		            }
		          },
		          "createdAt": 790468131.919036
		        }
		      },
		      "arcResources",
		      {
		        "value": {
		          "id": "arcResources",
		          "parentID": "thebrowser.company.arcBasicsFolderID",
		          "childrenIds": [],
		          "title": "Arc Resources",
		          "isUnread": false,
		          "createdAt": 790468131.919036,
		          "originatingDevice": "4D4E5942-0E60-453B-96B8-699AC621BA5E",
		          "data": {
		            "tab": {
		              "savedTitle": "Arc Resources",
		              "savedURL": "https://resources.arc.net/",
		              "savedMuteStatus": "allowAudio"
		            }
		          }
		        }
		      },
		      "importLoginsAndBookmarks",
		      {
		        "value": {
		          "id": "importLoginsAndBookmarks",
		          "parentID": "thebrowser.company.arcBasicsFolderID",
		          "childrenIds": [],
		          "title": "Import Logins & Bookmarks",
		          "isUnread": false,
		          "createdAt": 790468131.919036,
		          "originatingDevice": "4D4E5942-0E60-453B-96B8-699AC621BA5E",
		          "data": {
		            "tab": {
		              "savedURL": "https://resources.arc.net/hc/en-us/articles/19335089616791-Import-Bookmarks-Logins-History-Extensions-from-Your-Previous-Browser",
		              "savedTitle": "Import Logins & Bookmarks",
		              "savedMuteStatus": "allowAudio"
		            }
		          }
		        }
		      },
		      "thebrowser.company.defaultPersonalSpaceUnpinnedContainerID",
		      {
		        "value": {
		          "parentID": null,
		          "childrenIds": [],
		          "id": "thebrowser.company.defaultPersonalSpaceUnpinnedContainerID",
		          "originatingDevice": "4D4E5942-0E60-453B-96B8-699AC621BA5E",
		          "title": null,
		          "isUnread": false,
		          "data": {
		            "itemContainer": {
		              "containerType": {
		                "spaceItems": {
		                  "_0": "thebrowser.company.defaultPersonalSpaceID"
		                }
		              }
		            }
		          },
		          "createdAt": 790468131.918884
		        }
		      }
		    ]
		  }
		}
		"""

		try fixture.data(using: .utf8).unwrap().write(to: url)
	}

	private func writePartiallyMalformedCurrentArcSidebarFixture(to url: URL) throws {
		let fixture = """
		{
		  "sidebarSyncState": {
		    "spaceModels": [
		      "space-1",
		      {
		        "value": {
		          "id": "space-1",
		          "containerIDs": ["pinned", "pinned-1"]
		        }
		      },
		      "space-2",
		      {
		        "value": {
		          "id": "space-2",
		          "containerIDs": ["pinned", "pinned-2"]
		        }
		      }
		    ],
		    "container": {
		      "value": {
		        "orderedSpaceIDs": ["space-1", "space-2"],
		        "topAppsContainerID": "pinned-1"
		      }
		    },
		    "items": [
		      "pinned-1",
		      {
		        "value": {
		          "id": "pinned-1",
		          "childrenIds": ["folder-1"]
		        }
		      },
		      "folder-1",
		      {
		        "value": {
		          "id": "folder-1",
		          "title": "Folder 1",
		          "childrenIds": ["tab-1"],
		          "data": {
		            "list": {}
		          }
		        }
		      },
		      "tab-1",
		      {
		        "value": {
		          "id": "tab-1",
		          "title": "One",
		          "childrenIds": [],
		          "data": {
		            "tab": {
		              "savedTitle": "One",
		              "savedURL": "https://one.example"
		            }
		          }
		        }
		      },
		      "pinned-2",
		      {
		        "value": {
		          "id": "pinned-2",
		          "childrenIds": ["folder-2"]
		        }
		      },
		      "folder-2",
		      {
		        "value": {
		          "id": "folder-2",
		"""

		try fixture.data(using: .utf8).unwrap().write(to: url)
	}
}

private extension Optional {
	func unwrap(
		file: StaticString = #filePath,
		line: UInt = #line
	) throws -> Wrapped {
		guard let value = self else {
			throw XCTSkip("Expected fixture data", file: file, line: line)
		}
		return value
	}
}
