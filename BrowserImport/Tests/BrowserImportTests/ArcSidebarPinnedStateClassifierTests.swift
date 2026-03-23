@testable import BrowserImport
import Foundation
import ModelKit
import XCTest

final class ArcSidebarPinnedStateClassifierTests: XCTestCase {
	func testResolveTopAppsContainerPrefersCanonicalSyncStateID() {
		let itemsByID = [
			"top-apps": topAppsContainer(
				id: "top-apps",
				childrenIDs: ["top-direct"]
			),
			"top-direct": tabItem(
				id: "top-direct",
				parentID: "top-apps",
				title: "Top Direct",
				url: "https://top-direct.example"
			),
		]
		let sidebarSyncState = makeSidebarSyncState(
			itemsByID: itemsByID,
			spaceModelsByID: [
				"space-1": spaceModel(
					id: "space-1",
					pinnedContainerID: "space-pinned",
					unpinnedContainerID: "space-unpinned"
				),
			],
			orderedSpaceIDs: ["space-1"],
			topAppsContainerID: "top-apps"
		)

		let resolution = ArcSidebarPinnedStateClassifier.resolveTopAppsContainerResolution(
			sidebarSyncState: sidebarSyncState,
			itemsByID: itemsByID
		)

		XCTAssertEqual(resolution, .resolved("top-apps"))
	}

	func testResolveTopAppsContainerFallsBackToDefaultTaggedPluralIDs() {
		let itemsByID = [
			"top-apps": topAppsContainer(
				id: "top-apps",
				childrenIDs: ["top-direct"]
			),
			"top-direct": tabItem(
				id: "top-direct",
				parentID: "top-apps",
				title: "Top Direct",
				url: "https://top-direct.example"
			),
		]
		let sidebarSyncState = makeSidebarSyncState(
			itemsByID: itemsByID,
			spaceModelsByID: [:],
			orderedSpaceIDs: [],
			topAppsContainerIDs: [
				["default": true],
				"top-apps",
			]
		)

		let resolution = ArcSidebarPinnedStateClassifier.resolveTopAppsContainerResolution(
			sidebarSyncState: sidebarSyncState,
			itemsByID: itemsByID
		)

		XCTAssertEqual(resolution, .resolved("top-apps"))
	}

	func testLoadProfilePinsOnlyDirectTopAppsChildren() throws {
		let itemsByID = [
			"top-apps": topAppsContainer(
				id: "top-apps",
				childrenIDs: ["top-direct", "top-list"]
			),
			"top-direct": tabItem(
				id: "top-direct",
				parentID: "top-apps",
				title: "Top Direct",
				url: "https://top-direct.example"
			),
			"top-list": listItem(
				id: "top-list",
				parentID: "top-apps",
				title: "Nested List",
				childrenIDs: ["top-nested"]
			),
			"top-nested": tabItem(
				id: "top-nested",
				parentID: "top-list",
				title: "Top Nested",
				url: "https://top-nested.example"
			),
			"space-pinned": itemContainer(
				id: "space-pinned",
				childrenIDs: ["personal-pinned"],
				containerType: ["spaceItems": ["_0": "space-1"]]
			),
			"space-unpinned": itemContainer(
				id: "space-unpinned",
				childrenIDs: ["space-unpinned-tab"],
				containerType: ["spaceItems": ["_0": "space-1"]]
			),
			"personal-pinned": tabItem(
				id: "personal-pinned",
				parentID: "space-pinned",
				title: "Personal Pinned",
				url: "https://personal-pinned.example"
			),
			"space-unpinned-tab": tabItem(
				id: "space-unpinned-tab",
				parentID: "space-unpinned",
				title: "Space Unpinned",
				url: "https://space-unpinned.example"
			),
		]
		let tabs = try loadTabs(
			from: makeSidebarRoot(
				sidebarSyncState: makeSidebarSyncState(
					itemsByID: itemsByID,
					spaceModelsByID: [
						"space-1": spaceModel(
							id: "space-1",
							pinnedContainerID: "space-pinned",
							unpinnedContainerID: "space-unpinned"
						),
					],
					orderedSpaceIDs: ["space-1"],
					topAppsContainerID: "top-apps"
				)
			)
		)

		XCTAssertEqual(tabs.map(\.title), [
			"Top Direct",
			"Top Nested",
			"Personal Pinned",
			"Space Unpinned",
		])
		XCTAssertEqual(tabs.map(\.isPinned), [
			true,
			false,
			false,
			false,
		])
	}

	func testLoadProfileImportsTopAppsWhenContainerChildrenIDsAreEmptyButParentIDsMatch() throws {
		let itemsByID = [
			"top-apps": topAppsContainer(
				id: "top-apps",
				childrenIDs: []
			),
			"top-direct": tabItem(
				id: "top-direct",
				parentID: "top-apps",
				title: "Top Direct",
				url: "https://top-direct.example"
			),
			"space-pinned": itemContainer(
				id: "space-pinned",
				childrenIDs: [],
				containerType: ["spaceItems": ["_0": "thebrowser.company.defaultPersonalSpaceID"]]
			),
			"space-unpinned": itemContainer(
				id: "space-unpinned",
				childrenIDs: ["space-unpinned-tab"],
				containerType: ["spaceItems": ["_0": "thebrowser.company.defaultPersonalSpaceID"]]
			),
			"space-unpinned-tab": tabItem(
				id: "space-unpinned-tab",
				parentID: "space-unpinned",
				title: "Space Unpinned",
				url: "https://space-unpinned.example"
			),
		]
		let tabs = try loadTabs(
			from: makeSidebarRoot(
				sidebarSyncState: makeSidebarSyncState(
					itemsByID: itemsByID,
					spaceModelsByID: [
						"thebrowser.company.defaultPersonalSpaceID": spaceModel(
							id: "thebrowser.company.defaultPersonalSpaceID",
							pinnedContainerID: "space-pinned",
							unpinnedContainerID: "space-unpinned"
						),
					],
					orderedSpaceIDs: ["thebrowser.company.defaultPersonalSpaceID"],
					topAppsContainerID: "top-apps"
				)
			)
		)

		XCTAssertEqual(tabs.map(\.title), ["Top Direct", "Space Unpinned"])
		XCTAssertEqual(tabs.map(\.isPinned), [true, false])
	}

	func testLoadProfileFallsBackToStructuralTopAppsContainer() throws {
		let itemsByID = [
			"top-apps": topAppsContainer(
				id: "top-apps",
				childrenIDs: ["top-direct"]
			),
			"top-direct": tabItem(
				id: "top-direct",
				parentID: "top-apps",
				title: "Top Direct",
				url: "https://top-direct.example"
			),
			"space-pinned": itemContainer(
				id: "space-pinned",
				childrenIDs: ["space-pinned-tab"],
				containerType: ["spaceItems": ["_0": "space-1"]]
			),
			"space-unpinned": itemContainer(
				id: "space-unpinned",
				childrenIDs: [],
				containerType: ["spaceItems": ["_0": "space-1"]]
			),
			"space-pinned-tab": tabItem(
				id: "space-pinned-tab",
				parentID: "space-pinned",
				title: "Space Pinned",
				url: "https://space-pinned.example"
			),
		]
		let tabs = try loadTabs(
			from: makeSidebarRoot(
				sidebarSyncState: makeSidebarSyncState(
					itemsByID: itemsByID,
					spaceModelsByID: [
						"space-1": spaceModel(
							id: "space-1",
							pinnedContainerID: "space-pinned",
							unpinnedContainerID: "space-unpinned"
						),
					],
					orderedSpaceIDs: ["space-1"]
				)
			)
		)

		XCTAssertEqual(tabs.map(\.title), ["Top Direct", "Space Pinned"])
		XCTAssertEqual(tabs.map(\.isPinned), [true, false])
	}

	func testLoadProfileRoutesTopAppsIntoDefaultPersonalSpaceWhenOrderedSpacesStartElsewhere() throws {
		let itemsByID = [
			"top-apps": topAppsContainer(
				id: "top-apps",
				childrenIDs: ["top-direct"]
			),
			"top-direct": tabItem(
				id: "top-direct",
				parentID: "top-apps",
				title: "Top Direct",
				url: "https://top-direct.example"
			),
			"bills-pinned": itemContainer(
				id: "bills-pinned",
				childrenIDs: [],
				containerType: ["spaceItems": ["_0": "bills-space"]]
			),
			"bills-unpinned": itemContainer(
				id: "bills-unpinned",
				childrenIDs: ["bills-tab"],
				containerType: ["spaceItems": ["_0": "bills-space"]]
			),
			"bills-tab": tabItem(
				id: "bills-tab",
				parentID: "bills-unpinned",
				title: "Bills Tab",
				url: "https://bills.example"
			),
			"home-pinned": itemContainer(
				id: "home-pinned",
				childrenIDs: [],
				containerType: ["spaceItems": ["_0": "thebrowser.company.defaultPersonalSpaceID"]]
			),
			"home-unpinned": itemContainer(
				id: "home-unpinned",
				childrenIDs: ["home-tab"],
				containerType: ["spaceItems": ["_0": "thebrowser.company.defaultPersonalSpaceID"]]
			),
			"home-tab": tabItem(
				id: "home-tab",
				parentID: "home-unpinned",
				title: "Home Tab",
				url: "https://home.example"
			),
		]
		let importedProfile = try loadProfile(
			from: makeSidebarRoot(
				sidebarSyncState: makeSidebarSyncState(
					itemsByID: itemsByID,
					spaceModelsByID: [
						"bills-space": spaceModel(
							id: "bills-space",
							pinnedContainerID: "bills-pinned",
							unpinnedContainerID: "bills-unpinned",
							isDefault: false
						),
						"thebrowser.company.defaultPersonalSpaceID": spaceModel(
							id: "thebrowser.company.defaultPersonalSpaceID",
							pinnedContainerID: "home-pinned",
							unpinnedContainerID: "home-unpinned",
							isDefault: false
						),
					],
					orderedSpaceIDs: ["bills-space", "thebrowser.company.defaultPersonalSpaceID"],
					topAppsContainerIDs: [
						["default": true],
						"top-apps",
					]
				)
			)
		)

		let billsWindow = try XCTUnwrap(importedProfile.windows.first(where: { $0.displayName == "Space 1" }))
		XCTAssertEqual(billsWindow.tabGroups.first?.tabs.map(\.title), ["Bills Tab"])
		XCTAssertEqual(billsWindow.tabGroups.first?.tabs.map(\.isPinned), [false])

		let homeWindow = try XCTUnwrap(importedProfile.windows.first(where: { $0.displayName == "Space 2" }))
		XCTAssertEqual(homeWindow.tabGroups.first?.tabs.map(\.title), ["Top Direct", "Home Tab"])
		XCTAssertEqual(homeWindow.tabGroups.first?.tabs.map(\.isPinned), [true, false])
	}

	func testLoadProfileMergesFirebaseSyncDataWithSidebarSyncStateTopApps() throws {
		let firebaseItemsByID = [
			"home-pinned": itemContainer(
				id: "home-pinned",
				childrenIDs: [],
				containerType: ["spaceItems": ["_0": "thebrowser.company.defaultPersonalSpaceID"]]
			),
			"home-unpinned": itemContainer(
				id: "home-unpinned",
				childrenIDs: ["home-tab"],
				containerType: ["spaceItems": ["_0": "thebrowser.company.defaultPersonalSpaceID"]]
			),
			"home-tab": tabItem(
				id: "home-tab",
				parentID: "home-unpinned",
				title: "Home Tab",
				url: "https://home.example"
			),
		]
		let sidebarItemsByID = firebaseItemsByID.merging(
			[
				"top-apps": topAppsContainer(
					id: "top-apps",
					childrenIDs: ["top-direct"]
				),
				"top-direct": tabItem(
					id: "top-direct",
					parentID: "top-apps",
					title: "Top Direct",
					url: "https://top-direct.example"
				),
			],
			uniquingKeysWith: { current, _ in current }
		)
		let importedProfile = try loadProfile(
			from: makeSidebarRoot(
				firebaseSyncState: makeSidebarSyncState(
					itemsByID: firebaseItemsByID,
					spaceModelsByID: [
						"thebrowser.company.defaultPersonalSpaceID": spaceModel(
							id: "thebrowser.company.defaultPersonalSpaceID",
							pinnedContainerID: "home-pinned",
							unpinnedContainerID: "home-unpinned"
						),
					],
					orderedSpaceIDs: ["thebrowser.company.defaultPersonalSpaceID"]
				),
				sidebarSyncState: makeSidebarSyncState(
					itemsByID: sidebarItemsByID,
					spaceModelsByID: [
						"thebrowser.company.defaultPersonalSpaceID": spaceModel(
							id: "thebrowser.company.defaultPersonalSpaceID",
							pinnedContainerID: "home-pinned",
							unpinnedContainerID: "home-unpinned"
						),
					],
					orderedSpaceIDs: ["thebrowser.company.defaultPersonalSpaceID"],
					topAppsContainerID: "top-apps"
				)
			)
		)

		let homeWindow = try XCTUnwrap(importedProfile.windows.first)
		XCTAssertEqual(homeWindow.tabGroups.first?.tabs.map(\.title), ["Top Direct", "Home Tab"])
		XCTAssertEqual(homeWindow.tabGroups.first?.tabs.map(\.isPinned), [true, false])
	}

	func testLoadFoldersIncludesTopAppsForDefaultPersonalSpace() throws {
		let itemsByID = [
			"top-apps": topAppsContainer(
				id: "top-apps",
				childrenIDs: ["top-direct"]
			),
			"top-direct": tabItem(
				id: "top-direct",
				parentID: "top-apps",
				title: "Top Direct",
				url: "https://top-direct.example"
			),
			"home-pinned": itemContainer(
				id: "home-pinned",
				childrenIDs: ["home-pinned-tab"],
				containerType: ["spaceItems": ["_0": "thebrowser.company.defaultPersonalSpaceID"]]
			),
			"home-pinned-tab": tabItem(
				id: "home-pinned-tab",
				parentID: "home-pinned",
				title: "Home Pinned",
				url: "https://home-pinned.example"
			),
			"home-unpinned": itemContainer(
				id: "home-unpinned",
				childrenIDs: [],
				containerType: ["spaceItems": ["_0": "thebrowser.company.defaultPersonalSpaceID"]]
			),
		]
		let folders = try loadFolders(
			from: makeSidebarRoot(
				sidebarSyncState: makeSidebarSyncState(
					itemsByID: itemsByID,
					spaceModelsByID: [
						"thebrowser.company.defaultPersonalSpaceID": spaceModel(
							id: "thebrowser.company.defaultPersonalSpaceID",
							pinnedContainerID: "home-pinned",
							unpinnedContainerID: "home-unpinned"
						),
					],
					orderedSpaceIDs: ["thebrowser.company.defaultPersonalSpaceID"],
					topAppsContainerID: "top-apps"
				)
			)
		)

		let homeFolder = try XCTUnwrap(folders.first)
		XCTAssertEqual(homeFolder.bookmarks.map(\.title), ["Top Direct", "Home Pinned"])
	}

	func testLoadProfileIncludesTopAppsInWindowAndBookmarkPaths() throws {
		let itemsByID = [
			"top-apps": topAppsContainer(
				id: "top-apps",
				childrenIDs: ["top-direct"]
			),
			"top-direct": tabItem(
				id: "top-direct",
				parentID: "top-apps",
				title: "Top Direct",
				url: "https://top-direct.example"
			),
			"home-pinned": itemContainer(
				id: "home-pinned",
				childrenIDs: ["home-pinned-tab"],
				containerType: ["spaceItems": ["_0": "thebrowser.company.defaultPersonalSpaceID"]]
			),
			"home-pinned-tab": tabItem(
				id: "home-pinned-tab",
				parentID: "home-pinned",
				title: "Home Pinned",
				url: "https://home-pinned.example"
			),
			"home-unpinned": itemContainer(
				id: "home-unpinned",
				childrenIDs: ["home-unpinned-tab"],
				containerType: ["spaceItems": ["_0": "thebrowser.company.defaultPersonalSpaceID"]]
			),
			"home-unpinned-tab": tabItem(
				id: "home-unpinned-tab",
				parentID: "home-unpinned",
				title: "Home Unpinned",
				url: "https://home-unpinned.example"
			),
		]
		let importedProfile = try loadProfile(
			from: makeSidebarRoot(
				sidebarSyncState: makeSidebarSyncState(
					itemsByID: itemsByID,
					spaceModelsByID: [
						"thebrowser.company.defaultPersonalSpaceID": spaceModel(
							id: "thebrowser.company.defaultPersonalSpaceID",
							pinnedContainerID: "home-pinned",
							unpinnedContainerID: "home-unpinned"
						),
					],
					orderedSpaceIDs: ["thebrowser.company.defaultPersonalSpaceID"],
					topAppsContainerID: "top-apps"
				)
			),
			dataKinds: [.tabs, .bookmarks]
		)

		let homeWindow = try XCTUnwrap(importedProfile.windows.first)
		XCTAssertEqual(
			homeWindow.tabGroups.first?.tabs.map(\.title),
			["Top Direct", "Home Pinned", "Home Unpinned"]
		)
		XCTAssertEqual(
			homeWindow.tabGroups.first?.tabs.map(\.isPinned),
			[true, false, false]
		)

		let homeFolder = try XCTUnwrap(importedProfile.bookmarkFolders.first)
		XCTAssertEqual(homeFolder.bookmarks.map(\.title), ["Top Direct", "Home Pinned"])
	}

	func testLoadProfileChunkStreamMergesFirebaseSyncDataWithSidebarSyncStateTopApps() async throws {
		let firebaseItemsByID = [
			"home-pinned": itemContainer(
				id: "home-pinned",
				childrenIDs: [],
				containerType: ["spaceItems": ["_0": "thebrowser.company.defaultPersonalSpaceID"]]
			),
			"home-unpinned": itemContainer(
				id: "home-unpinned",
				childrenIDs: ["home-tab"],
				containerType: ["spaceItems": ["_0": "thebrowser.company.defaultPersonalSpaceID"]]
			),
			"home-tab": tabItem(
				id: "home-tab",
				parentID: "home-unpinned",
				title: "Home Tab",
				url: "https://home.example"
			),
		]
		let sidebarItemsByID = firebaseItemsByID.merging(
			[
				"top-apps": topAppsContainer(
					id: "top-apps",
					childrenIDs: ["top-direct"]
				),
				"top-direct": tabItem(
					id: "top-direct",
					parentID: "top-apps",
					title: "Top Direct",
					url: "https://top-direct.example"
				),
			],
			uniquingKeysWith: { current, _ in current }
		)
		let rootObject = makeSidebarRoot(
			firebaseSyncState: makeSidebarSyncState(
				itemsByID: firebaseItemsByID,
				spaceModelsByID: [
					"thebrowser.company.defaultPersonalSpaceID": spaceModel(
						id: "thebrowser.company.defaultPersonalSpaceID",
						pinnedContainerID: "home-pinned",
						unpinnedContainerID: "home-unpinned"
					),
				],
				orderedSpaceIDs: ["thebrowser.company.defaultPersonalSpaceID"]
			),
			sidebarSyncState: makeSidebarSyncState(
				itemsByID: sidebarItemsByID,
				spaceModelsByID: [
					"thebrowser.company.defaultPersonalSpaceID": spaceModel(
						id: "thebrowser.company.defaultPersonalSpaceID",
						pinnedContainerID: "home-pinned",
						unpinnedContainerID: "home-unpinned"
					),
				],
				orderedSpaceIDs: ["thebrowser.company.defaultPersonalSpaceID"],
				topAppsContainerID: "top-apps"
			)
		)
		let profileURL = try writeSidebarProfile(rootObject)

		var chunks = [ArcSidebarProfileChunk]()
		for try await chunk in ArcSidebarBookmarksParser().loadProfileChunkStream(
			source: .arc,
			profileURL: profileURL
		) {
			chunks.append(chunk)
		}

		let homeWindow = try XCTUnwrap(chunks.compactMap(\.window).first)
		XCTAssertEqual(homeWindow.tabGroups.first?.tabs.map(\.title), ["Top Direct", "Home Tab"])
		XCTAssertEqual(homeWindow.tabGroups.first?.tabs.map(\.isPinned), [true, false])
	}

	func testLoadProfileChunkStreamPreservesRicherTopAppsContainerAcrossDuplicateItems() async throws {
		let firebaseItemsByID = [
			"home-pinned": itemContainer(
				id: "home-pinned",
				childrenIDs: [],
				containerType: ["spaceItems": ["_0": "thebrowser.company.defaultPersonalSpaceID"]]
			),
			"home-unpinned": itemContainer(
				id: "home-unpinned",
				childrenIDs: ["home-tab"],
				containerType: ["spaceItems": ["_0": "thebrowser.company.defaultPersonalSpaceID"]]
			),
			"home-tab": tabItem(
				id: "home-tab",
				parentID: "home-unpinned",
				title: "Home Tab",
				url: "https://home.example"
			),
			"top-apps": topAppsContainer(
				id: "top-apps",
				childrenIDs: []
			),
		]
		let sidebarItemsByID = firebaseItemsByID.merging(
			[
				"top-apps": topAppsContainer(
					id: "top-apps",
					childrenIDs: ["top-direct"]
				),
				"top-direct": tabItem(
					id: "top-direct",
					parentID: "top-apps",
					title: "Top Direct",
					url: "https://top-direct.example"
				),
			],
			uniquingKeysWith: { _, supplemental in supplemental }
		)
		let rootObject = makeSidebarRoot(
			firebaseSyncState: makeSidebarSyncState(
				itemsByID: firebaseItemsByID,
				spaceModelsByID: [
					"thebrowser.company.defaultPersonalSpaceID": spaceModel(
						id: "thebrowser.company.defaultPersonalSpaceID",
						pinnedContainerID: "home-pinned",
						unpinnedContainerID: "home-unpinned"
					),
				],
				orderedSpaceIDs: ["thebrowser.company.defaultPersonalSpaceID"],
				topAppsContainerID: "top-apps"
			),
			sidebarSyncState: makeSidebarSyncState(
				itemsByID: sidebarItemsByID,
				spaceModelsByID: [
					"thebrowser.company.defaultPersonalSpaceID": spaceModel(
						id: "thebrowser.company.defaultPersonalSpaceID",
						pinnedContainerID: "home-pinned",
						unpinnedContainerID: "home-unpinned"
					),
				],
				orderedSpaceIDs: ["thebrowser.company.defaultPersonalSpaceID"],
				topAppsContainerID: "top-apps"
			)
		)
		let profileURL = try writeSidebarProfile(rootObject)

		var chunks = [ArcSidebarProfileChunk]()
		for try await chunk in ArcSidebarBookmarksParser().loadProfileChunkStream(
			source: .arc,
			profileURL: profileURL
		) {
			chunks.append(chunk)
		}

		let homeWindow = try XCTUnwrap(chunks.compactMap(\.window).first)
		let homeFolder = try XCTUnwrap(chunks.compactMap(\.bookmarkFolder).first)
		XCTAssertEqual(homeWindow.tabGroups.first?.tabs.map(\.title), ["Top Direct", "Home Tab"])
		XCTAssertEqual(homeWindow.tabGroups.first?.tabs.map(\.isPinned), [true, false])
		XCTAssertEqual(homeFolder.bookmarks.map(\.title), ["Top Direct"])
	}

	func testLoadProfileMergesLiveSidebarCurrentContainerTopApps() throws {
		let firebaseItemsByID = [
			"home-pinned": itemContainer(
				id: "home-pinned",
				childrenIDs: ["home-pinned-tab"],
				containerType: ["spaceItems": ["_0": "thebrowser.company.defaultPersonalSpaceID"]]
			),
			"home-pinned-tab": tabItem(
				id: "home-pinned-tab",
				parentID: "home-pinned",
				title: "Home Pinned",
				url: "https://home-pinned.example"
			),
			"home-unpinned": itemContainer(
				id: "home-unpinned",
				childrenIDs: ["home-unpinned-tab"],
				containerType: ["spaceItems": ["_0": "thebrowser.company.defaultPersonalSpaceID"]]
			),
			"home-unpinned-tab": tabItem(
				id: "home-unpinned-tab",
				parentID: "home-unpinned",
				title: "Home Unpinned",
				url: "https://home-unpinned.example"
			),
		]
		let sparseSidebarItemsByID = firebaseItemsByID.merging(
			[
				"top-apps": topAppsContainer(
					id: "top-apps",
					childrenIDs: []
				),
			],
			uniquingKeysWith: { current, _ in current }
		)
		let liveCurrentItemsByID = sparseSidebarItemsByID.merging(
			[
				"top-apps": topAppsContainer(
					id: "top-apps",
					childrenIDs: ["top-direct"]
				),
				"top-direct": tabItem(
					id: "top-direct",
					parentID: "top-apps",
					title: "Top Direct",
					url: "https://top-direct.example"
				),
			],
			uniquingKeysWith: { _, live in live }
		)
		let importedProfile = try loadProfile(
			from: makeSidebarRoot(
				firebaseSyncState: makeSidebarSyncState(
					itemsByID: firebaseItemsByID,
					spaceModelsByID: [
						"thebrowser.company.defaultPersonalSpaceID": spaceModel(
							id: "thebrowser.company.defaultPersonalSpaceID",
							pinnedContainerID: "home-pinned",
							unpinnedContainerID: "home-unpinned"
						),
					],
					orderedSpaceIDs: ["thebrowser.company.defaultPersonalSpaceID"]
				),
				sidebarSyncState: makeSidebarSyncState(
					itemsByID: sparseSidebarItemsByID,
					spaceModelsByID: [
						"thebrowser.company.defaultPersonalSpaceID": spaceModel(
							id: "thebrowser.company.defaultPersonalSpaceID",
							pinnedContainerID: "home-pinned",
							unpinnedContainerID: "home-unpinned"
						),
					],
					orderedSpaceIDs: ["thebrowser.company.defaultPersonalSpaceID"],
					topAppsContainerID: "top-apps"
				),
				liveCurrentContainer: makeLiveCurrentContainer(
					itemsByID: liveCurrentItemsByID,
					spaceModelsByID: [
						"thebrowser.company.defaultPersonalSpaceID": spaceModel(
							id: "thebrowser.company.defaultPersonalSpaceID",
							pinnedContainerID: "home-pinned",
							unpinnedContainerID: "home-unpinned"
						),
					],
					topAppsContainerID: "top-apps"
				)
			),
			dataKinds: [.tabs, .bookmarks]
		)

		let homeWindow = try XCTUnwrap(importedProfile.windows.first)
		XCTAssertEqual(
			homeWindow.tabGroups.first?.tabs.map(\.title),
			["Top Direct", "Home Pinned", "Home Unpinned"]
		)
		XCTAssertEqual(
			homeWindow.tabGroups.first?.tabs.map(\.isPinned),
			[true, false, false]
		)

		let homeFolder = try XCTUnwrap(importedProfile.bookmarkFolders.first)
		XCTAssertEqual(homeFolder.bookmarks.map(\.title), ["Top Direct", "Home Pinned"])
	}

	func testLoadProfileChunkStreamMergesLiveSidebarCurrentContainerTopApps() async throws {
		let firebaseItemsByID = [
			"home-pinned": itemContainer(
				id: "home-pinned",
				childrenIDs: [],
				containerType: ["spaceItems": ["_0": "thebrowser.company.defaultPersonalSpaceID"]]
			),
			"home-unpinned": itemContainer(
				id: "home-unpinned",
				childrenIDs: ["home-tab"],
				containerType: ["spaceItems": ["_0": "thebrowser.company.defaultPersonalSpaceID"]]
			),
			"home-tab": tabItem(
				id: "home-tab",
				parentID: "home-unpinned",
				title: "Home Tab",
				url: "https://home.example"
			),
		]
		let sparseSidebarItemsByID = firebaseItemsByID.merging(
			[
				"top-apps": topAppsContainer(
					id: "top-apps",
					childrenIDs: []
				),
			],
			uniquingKeysWith: { current, _ in current }
		)
		let liveCurrentItemsByID = sparseSidebarItemsByID.merging(
			[
				"top-apps": topAppsContainer(
					id: "top-apps",
					childrenIDs: ["top-direct"]
				),
				"top-direct": tabItem(
					id: "top-direct",
					parentID: "top-apps",
					title: "Top Direct",
					url: "https://top-direct.example"
				),
			],
			uniquingKeysWith: { _, live in live }
		)
		let rootObject = makeSidebarRoot(
			firebaseSyncState: makeSidebarSyncState(
				itemsByID: firebaseItemsByID,
				spaceModelsByID: [
					"thebrowser.company.defaultPersonalSpaceID": spaceModel(
						id: "thebrowser.company.defaultPersonalSpaceID",
						pinnedContainerID: "home-pinned",
						unpinnedContainerID: "home-unpinned"
					),
				],
				orderedSpaceIDs: ["thebrowser.company.defaultPersonalSpaceID"]
			),
			sidebarSyncState: makeSidebarSyncState(
				itemsByID: sparseSidebarItemsByID,
				spaceModelsByID: [
					"thebrowser.company.defaultPersonalSpaceID": spaceModel(
						id: "thebrowser.company.defaultPersonalSpaceID",
						pinnedContainerID: "home-pinned",
						unpinnedContainerID: "home-unpinned"
					),
				],
				orderedSpaceIDs: ["thebrowser.company.defaultPersonalSpaceID"],
				topAppsContainerID: "top-apps"
			),
			liveCurrentContainer: makeLiveCurrentContainer(
				itemsByID: liveCurrentItemsByID,
				spaceModelsByID: [
					"thebrowser.company.defaultPersonalSpaceID": spaceModel(
						id: "thebrowser.company.defaultPersonalSpaceID",
						pinnedContainerID: "home-pinned",
						unpinnedContainerID: "home-unpinned"
					),
				],
				topAppsContainerID: "top-apps"
			)
		)
		let profileURL = try writeSidebarProfile(rootObject)

		var chunks = [ArcSidebarProfileChunk]()
		for try await chunk in ArcSidebarBookmarksParser().loadProfileChunkStream(
			source: .arc,
			profileURL: profileURL
		) {
			chunks.append(chunk)
		}

		let homeWindow = try XCTUnwrap(chunks.compactMap(\.window).first)
		let homeFolder = try XCTUnwrap(chunks.compactMap(\.bookmarkFolder).first)
		XCTAssertEqual(homeWindow.tabGroups.first?.tabs.map(\.title), ["Top Direct", "Home Tab"])
		XCTAssertEqual(homeWindow.tabGroups.first?.tabs.map(\.isPinned), [true, false])
		XCTAssertEqual(homeFolder.bookmarks.map(\.title), ["Top Direct"])
	}

	func testLoadProfileChunkStreamPreservesRicherSupplementalDuplicateItemValues() async throws {
		let firebaseItemsByID = [
			"home-pinned": itemContainer(
				id: "home-pinned",
				childrenIDs: [],
				containerType: ["spaceItems": ["_0": "thebrowser.company.defaultPersonalSpaceID"]]
			),
			"home-unpinned": itemContainer(
				id: "home-unpinned",
				childrenIDs: ["home-tab"],
				containerType: ["spaceItems": ["_0": "thebrowser.company.defaultPersonalSpaceID"]]
			),
			"home-tab": tabItem(
				id: "home-tab",
				parentID: "home-unpinned",
				title: "Home Tab",
				url: "https://home.example"
			),
			"top-apps": topAppsContainer(
				id: "top-apps",
				childrenIDs: ["top-direct"]
			),
			"top-direct": tabItem(
				id: "top-direct",
				parentID: "wrong-parent",
				title: "Top Direct",
				url: "https://top-direct.example"
			),
		]
		let sidebarItemsByID = firebaseItemsByID.merging(
			[
				"top-direct": tabItem(
					id: "top-direct",
					parentID: "top-apps",
					title: "Top Direct",
					url: "https://top-direct.example"
				),
			],
			uniquingKeysWith: { _, supplemental in supplemental }
		)
		let rootObject = makeSidebarRoot(
			firebaseSyncState: makeSidebarSyncState(
				itemsByID: firebaseItemsByID,
				spaceModelsByID: [
					"thebrowser.company.defaultPersonalSpaceID": spaceModel(
						id: "thebrowser.company.defaultPersonalSpaceID",
						pinnedContainerID: "home-pinned",
						unpinnedContainerID: "home-unpinned"
					),
				],
				orderedSpaceIDs: ["thebrowser.company.defaultPersonalSpaceID"],
				topAppsContainerID: "top-apps"
			),
			sidebarSyncState: makeSidebarSyncState(
				itemsByID: sidebarItemsByID,
				spaceModelsByID: [
					"thebrowser.company.defaultPersonalSpaceID": spaceModel(
						id: "thebrowser.company.defaultPersonalSpaceID",
						pinnedContainerID: "home-pinned",
						unpinnedContainerID: "home-unpinned"
					),
				],
				orderedSpaceIDs: ["thebrowser.company.defaultPersonalSpaceID"],
				topAppsContainerID: "top-apps"
			)
		)
		let profileURL = try writeSidebarProfile(rootObject)

		var chunks = [ArcSidebarProfileChunk]()
		for try await chunk in ArcSidebarBookmarksParser().loadProfileChunkStream(
			source: .arc,
			profileURL: profileURL
		) {
			chunks.append(chunk)
		}

		let homeWindow = try XCTUnwrap(chunks.compactMap(\.window).first)
		XCTAssertEqual(homeWindow.tabGroups.first?.tabs.map(\.title), ["Top Direct", "Home Tab"])
		XCTAssertEqual(homeWindow.tabGroups.first?.tabs.map(\.isPinned), [true, false])
	}

	func testLoadProfileChunkStreamPrefersIncomingDuplicateParentIDForTopAppsFallbackRoots() async throws {
		let firebaseItemsByID = [
			"home-pinned": itemContainer(
				id: "home-pinned",
				childrenIDs: [],
				containerType: ["spaceItems": ["_0": "thebrowser.company.defaultPersonalSpaceID"]]
			),
			"home-unpinned": itemContainer(
				id: "home-unpinned",
				childrenIDs: ["home-tab"],
				containerType: ["spaceItems": ["_0": "thebrowser.company.defaultPersonalSpaceID"]]
			),
			"home-tab": tabItem(
				id: "home-tab",
				parentID: "home-unpinned",
				title: "Home Tab",
				url: "https://home.example"
			),
			"top-apps": topAppsContainer(
				id: "top-apps",
				childrenIDs: []
			),
			"top-direct": tabItem(
				id: "top-direct",
				parentID: "wrong-parent",
				title: "Top Direct",
				url: "https://top-direct.example"
			),
		]
		let sidebarItemsByID = firebaseItemsByID.merging(
			[
				"top-direct": tabItem(
					id: "top-direct",
					parentID: "top-apps",
					title: "Top Direct",
					url: "https://top-direct.example"
				),
			],
			uniquingKeysWith: { _, supplemental in supplemental }
		)
		let rootObject = makeSidebarRoot(
			firebaseSyncState: makeSidebarSyncState(
				itemsByID: firebaseItemsByID,
				spaceModelsByID: [
					"thebrowser.company.defaultPersonalSpaceID": spaceModel(
						id: "thebrowser.company.defaultPersonalSpaceID",
						pinnedContainerID: "home-pinned",
						unpinnedContainerID: "home-unpinned"
					),
				],
				orderedSpaceIDs: ["thebrowser.company.defaultPersonalSpaceID"],
				topAppsContainerID: "top-apps"
			),
			sidebarSyncState: makeSidebarSyncState(
				itemsByID: sidebarItemsByID,
				spaceModelsByID: [
					"thebrowser.company.defaultPersonalSpaceID": spaceModel(
						id: "thebrowser.company.defaultPersonalSpaceID",
						pinnedContainerID: "home-pinned",
						unpinnedContainerID: "home-unpinned"
					),
				],
				orderedSpaceIDs: ["thebrowser.company.defaultPersonalSpaceID"],
				topAppsContainerID: "top-apps"
			)
		)
		let profileURL = try writeSidebarProfile(rootObject)

		var chunks = [ArcSidebarProfileChunk]()
		for try await chunk in ArcSidebarBookmarksParser().loadProfileChunkStream(
			source: .arc,
			profileURL: profileURL
		) {
			chunks.append(chunk)
		}

		let homeWindow = try XCTUnwrap(chunks.compactMap(\.window).first)
		let homeFolder = try XCTUnwrap(chunks.compactMap(\.bookmarkFolder).first)
		XCTAssertEqual(homeWindow.tabGroups.first?.tabs.map(\.title), ["Top Direct", "Home Tab"])
		XCTAssertEqual(homeWindow.tabGroups.first?.tabs.map(\.isPinned), [true, false])
		XCTAssertEqual(homeFolder.bookmarks.map(\.title), ["Top Direct"])
	}

	func testLoadProfileChunkStreamWaitsForTopAppsTreeBeforeEmittingRecipientSpace() async throws {
		let rootObject: JSONObject = [
			"sidebarSyncState": [
				"container": [
					"value": [
						"orderedSpaceIDs": ["thebrowser.company.defaultPersonalSpaceID"],
						"topAppsContainerID": "top-apps",
						"version": 6,
					],
				],
				"spaceModels": orderedPairedEntries([
					(
						"thebrowser.company.defaultPersonalSpaceID",
						spaceModel(
							id: "thebrowser.company.defaultPersonalSpaceID",
							pinnedContainerID: "home-pinned",
							unpinnedContainerID: "home-unpinned"
						)
					),
				]),
				"items": orderedPairedEntries([
					(
						"home-pinned",
						itemContainer(
							id: "home-pinned",
							childrenIDs: [],
							containerType: ["spaceItems": ["_0": "thebrowser.company.defaultPersonalSpaceID"]]
						)
					),
					(
						"home-unpinned",
						itemContainer(
							id: "home-unpinned",
							childrenIDs: ["home-tab"],
							containerType: ["spaceItems": ["_0": "thebrowser.company.defaultPersonalSpaceID"]]
						)
					),
					(
						"home-tab",
						tabItem(
							id: "home-tab",
							parentID: "home-unpinned",
							title: "Home Tab",
							url: "https://home.example"
						)
					),
					(
						"top-apps",
						topAppsContainer(
							id: "top-apps",
							childrenIDs: ["top-direct"]
						)
					),
					(
						"top-direct",
						tabItem(
							id: "top-direct",
							parentID: "top-apps",
							title: "Top Direct",
							url: "https://top-direct.example"
						)
					),
				]),
			],
		]
		let profileURL = try writeSidebarProfile(rootObject)

		var chunks = [ArcSidebarProfileChunk]()
		for try await chunk in ArcSidebarBookmarksParser().loadProfileChunkStream(
			source: .arc,
			profileURL: profileURL
		) {
			chunks.append(chunk)
		}

		let homeWindow = try XCTUnwrap(chunks.compactMap(\.window).first)
		XCTAssertEqual(chunks.compactMap(\.window).count, 1)
		XCTAssertEqual(homeWindow.tabGroups.first?.tabs.map(\.title), ["Top Direct", "Home Tab"])
		XCTAssertEqual(homeWindow.tabGroups.first?.tabs.map(\.isPinned), [true, false])
	}

	func testLoadProfileMarksAllDiscoveredTabsUnpinnedWhenTopAppsCannotBeResolved() throws {
		let itemsByID = [
			"space-pinned": itemContainer(
				id: "space-pinned",
				childrenIDs: ["space-pinned-tab"],
				containerType: ["spaceItems": ["_0": "space-1"]]
			),
			"space-unpinned": itemContainer(
				id: "space-unpinned",
				childrenIDs: ["space-unpinned-tab"],
				containerType: ["spaceItems": ["_0": "space-1"]]
			),
			"space-pinned-tab": tabItem(
				id: "space-pinned-tab",
				parentID: "space-pinned",
				title: "Space Pinned",
				url: "https://space-pinned.example"
			),
			"space-unpinned-tab": tabItem(
				id: "space-unpinned-tab",
				parentID: "space-unpinned",
				title: "Space Unpinned",
				url: "https://space-unpinned.example"
			),
		]
		let tabs = try loadTabs(
			from: makeSidebarRoot(
				sidebarSyncState: makeSidebarSyncState(
					itemsByID: itemsByID,
					spaceModelsByID: [
						"space-1": spaceModel(
							id: "space-1",
							pinnedContainerID: "space-pinned",
							unpinnedContainerID: "space-unpinned"
						),
					],
					orderedSpaceIDs: ["space-1"]
				)
			)
		)

		XCTAssertEqual(tabs.map(\.isPinned), [false, false])
	}

	func testResolveTopAppsContainerTreatsMultipleStructuralCandidatesAsAmbiguous() {
		let itemsByID = [
			"top-apps-1": topAppsContainer(
				id: "top-apps-1",
				childrenIDs: ["top-direct-1"]
			),
			"top-apps-2": topAppsContainer(
				id: "top-apps-2",
				childrenIDs: ["top-direct-2"]
			),
			"top-direct-1": tabItem(
				id: "top-direct-1",
				parentID: "top-apps-1",
				title: "Top Direct 1",
				url: "https://top-direct-1.example"
			),
			"top-direct-2": tabItem(
				id: "top-direct-2",
				parentID: "top-apps-2",
				title: "Top Direct 2",
				url: "https://top-direct-2.example"
			),
		]

		let resolution = ArcSidebarPinnedStateClassifier.resolveTopAppsContainerResolution(
			sidebarSyncState: makeSidebarSyncState(
				itemsByID: itemsByID,
				spaceModelsByID: [:],
				orderedSpaceIDs: []
			),
			itemsByID: itemsByID
		)

		XCTAssertEqual(resolution, .ambiguous)
	}

	func testPinnedStateClassifierTreatsOrphanedTabsAsUnpinned() {
		let classifier = ArcSidebarPinnedStateClassifier(
			topAppsResolution: .resolved("top-apps")
		)

		XCTAssertEqual(
			classifier.pinnedState(
				for: tabItem(
					id: "orphaned",
					parentID: "missing-parent",
					title: "Orphaned",
					url: "https://orphaned.example"
				)
			),
			.unpinned
		)
	}
}

private extension ArcSidebarPinnedStateClassifierTests {
	func loadProfile(
		from rootObject: JSONObject,
		dataKinds: [BrowserImportDataKind] = [.tabs]
	) throws -> ImportedBrowserProfile {
		let profileURL = try writeSidebarProfile(rootObject)

		return try ChromiumSnapshotLoader().loadProfile(
			source: .arc,
			profile: BrowserProfile(
				id: "Default",
				displayName: "Default",
				profileURL: profileURL,
				isDefault: true
			),
			dataKinds: dataKinds
		)
	}

	func writeSidebarProfile(_ rootObject: JSONObject) throws -> URL {
		let rootURL = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		let profileURL = rootURL.appendingPathComponent("User Data/Default", isDirectory: true)
		try FileManager.default.createDirectory(
			at: profileURL,
			withIntermediateDirectories: true
		)
		let sidebarURL = rootURL.appendingPathComponent("StorableSidebar.json", isDirectory: false)
		let data = try JSONSerialization.data(withJSONObject: rootObject, options: [.prettyPrinted, .sortedKeys])
		try data.write(to: sidebarURL)
		return profileURL
	}

	func loadTabs(from rootObject: JSONObject) throws -> [ImportedTab] {
		let importedProfile = try loadProfile(from: rootObject)
		return importedProfile.windows.first?.tabGroups.first?.tabs ?? []
	}

	func loadFolders(from rootObject: JSONObject) throws -> [ImportedBookmarkFolder] {
		let profileURL = try writeSidebarProfile(rootObject)

		return try ArcSidebarBookmarksParser().loadFolders(
			source: .arc,
			profileURL: profileURL
		)
	}

	func makeSidebarRoot(sidebarSyncState: JSONObject) -> JSONObject {
		["sidebarSyncState": sidebarSyncState]
	}

	func makeSidebarRoot(
		firebaseSyncState: JSONObject,
		sidebarSyncState: JSONObject
	) -> JSONObject {
		[
			"firebaseSyncState": ["syncData": firebaseSyncState],
			"sidebarSyncState": sidebarSyncState,
		]
	}

	func makeSidebarRoot(
		firebaseSyncState: JSONObject,
		sidebarSyncState: JSONObject,
		liveCurrentContainer: JSONObject
	) -> JSONObject {
		[
			"firebaseSyncState": ["syncData": firebaseSyncState],
			"sidebarSyncState": sidebarSyncState,
			"sidebar": ["containers": [liveCurrentContainer]],
		]
	}

	func makeSidebarSyncState(
		itemsByID: [String: JSONObject],
		spaceModelsByID: [String: JSONObject],
		orderedSpaceIDs: [String],
		topAppsContainerID: String? = nil,
		topAppsContainerIDs: [Any]? = nil
	) -> JSONObject {
		var sidebarSyncState: JSONObject = [
			"items": pairedEntries(itemsByID),
			"spaceModels": pairedEntries(spaceModelsByID),
		]
		var containerValue: JSONObject = [
			"orderedSpaceIDs": orderedSpaceIDs,
			"version": 6,
		]
		if let topAppsContainerID {
			containerValue["topAppsContainerID"] = topAppsContainerID
		}
		if let topAppsContainerIDs {
			containerValue["topAppsContainerIDs"] = topAppsContainerIDs
		}
		else if let topAppsContainerID {
			containerValue["topAppsContainerIDs"] = [
				["default": true],
				topAppsContainerID,
			]
		}
		sidebarSyncState["container"] = ["value": containerValue]
		return sidebarSyncState
	}

	func pairedEntries(_ valuesByID: [String: JSONObject]) -> [Any] {
		valuesByID.keys.sorted().flatMap { identifier -> [Any] in
			[
				identifier,
				["value": valuesByID[identifier] ?? [:]],
			]
		}
	}

	func orderedPairedEntries(_ entries: [(String, JSONObject)]) -> [Any] {
		entries.flatMap { identifier, value -> [Any] in
			[
				identifier,
				["value": value],
			]
		}
	}

	func makeLiveCurrentContainer(
		itemsByID: [String: JSONObject],
		spaceModelsByID: [String: JSONObject],
		topAppsContainerID: String
	) -> JSONObject {
		[
			"topAppsContainerIDs": [
				["default": true],
				topAppsContainerID,
			],
			"spaces": pairedEntries(spaceModelsByID),
			"items": pairedEntries(itemsByID),
		]
	}

	func spaceModel(
		id: String,
		pinnedContainerID: String,
		unpinnedContainerID: String,
		isDefault: Bool = true
	) -> JSONObject {
		[
			"id": id,
			"containerIDs": [
				"pinned",
				pinnedContainerID,
				"unpinned",
				unpinnedContainerID,
			],
			"profile": ["default": isDefault],
		]
	}

	func topAppsContainer(
		id: String,
		childrenIDs: [String]
	) -> JSONObject {
		itemContainer(
			id: id,
			childrenIDs: childrenIDs,
			containerType: ["topApps": [:]]
		)
	}

	func itemContainer(
		id: String,
		childrenIDs: [String],
		containerType: JSONObject
	) -> JSONObject {
		var item: JSONObject = [
			"id": id,
			"childrenIds": childrenIDs,
			"data": [
				"itemContainer": [
					"containerType": containerType,
				],
			],
			"isUnread": false,
		]
		item["parentID"] = NSNull()
		return item
	}

	func listItem(
		id: String,
		parentID: String,
		title: String,
		childrenIDs: [String]
	) -> JSONObject {
		return [
			"id": id,
			"parentID": parentID,
			"childrenIds": childrenIDs,
			"title": title,
			"data": ["list": [:]],
			"isUnread": false,
		]
	}

	func tabItem(
		id: String,
		parentID: String,
		title: String,
		url: String
	) -> JSONObject {
		[
			"id": id,
			"parentID": parentID,
			"childrenIds": [],
			"title": title,
			"data": [
				"tab": [
					"savedTitle": title,
					"savedURL": url,
				],
			],
			"isUnread": false,
		]
	}
}
