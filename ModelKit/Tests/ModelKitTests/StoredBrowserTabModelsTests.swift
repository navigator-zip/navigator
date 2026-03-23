import ModelKit
import XCTest

final class StoredBrowserTabModelsTests: XCTestCase {
	func testStoredBrowserTabDecodesMissingPinnedStateAsFalse() throws {
		let json = """
		{
		  "id": "8D8B28EA-BB88-44D8-83C3-B3041F9EAE4B",
		  "objectVersion": 1,
		  "orderKey": "00000000",
		  "parentObjectID": null,
		  "isArchived": false,
		  "url": "https://navigator.example",
		  "title": "Navigator",
		  "faviconURL": "https://navigator.example/favicon.ico"
		}
		"""

		let tab = try JSONDecoder().decode(StoredBrowserTab.self, from: Data(json.utf8))

		XCTAssertFalse(tab.isPinned)
	}

	func testStoredBrowserTabDecodesPinnedStateWhenPresent() throws {
		let json = """
		{
		  "id": "8D8B28EA-BB88-44D8-83C3-B3041F9EAE4B",
		  "objectVersion": 2,
		  "orderKey": "00000001",
		  "parentObjectID": null,
		  "isArchived": false,
		  "isPinned": true,
		  "url": "https://navigator.example",
		  "title": "Navigator",
		  "faviconURL": "https://navigator.example/favicon.ico"
		}
		"""

		let tab = try JSONDecoder().decode(StoredBrowserTab.self, from: Data(json.utf8))

		XCTAssertTrue(tab.isPinned)
	}

	func testStoredBrowserTabDecodesMissingSpaceIDAsDefaultSpace() throws {
		let json = """
		{
		  "id": "8D8B28EA-BB88-44D8-83C3-B3041F9EAE4B",
		  "objectVersion": 1,
		  "orderKey": "00000000",
		  "parentObjectID": null,
		  "isArchived": false,
		  "url": "https://navigator.example"
		}
		"""

		let tab = try JSONDecoder().decode(StoredBrowserTab.self, from: Data(json.utf8))

		XCTAssertEqual(tab.spaceID, StoredBrowserTabCollection.defaultSpaceID)
	}

	func testStoredBrowserTabCollectionDecodesWithoutSpacesAndDerivesDefaultSpace() throws {
		let json = """
		{
		  "storageVersion": 1,
		  "collectionID": "default-workspace",
		  "hasStoredState": true,
		  "tabs": [
		    {
		      "id": "8D8B28EA-BB88-44D8-83C3-B3041F9EAE4B",
		      "objectVersion": 1,
		      "orderKey": "00000000",
		      "isArchived": false,
		      "isPinned": false,
		      "url": "https://navigator.example"
		    }
		  ]
		}
		"""

		let collection = try JSONDecoder().decode(StoredBrowserTabCollection.self, from: Data(json.utf8))

		XCTAssertEqual(collection.activeSpaceID, StoredBrowserTabCollection.defaultSpaceID)
		XCTAssertEqual(collection.spaces.count, 1)
		XCTAssertEqual(collection.spaces[0].id, StoredBrowserTabCollection.defaultSpaceID)
	}

	func testStoredBrowserTabSelectionDecodesWithoutSpaceAsDefaultSpace() throws {
		let json = """
		{
		  "storageVersion": 1,
		  "collectionID": "default-workspace",
		  "selectedTabID": "8D8B28EA-BB88-44D8-83C3-B3041F9EAE4B"
		}
		"""

		let selection = try JSONDecoder().decode(StoredBrowserTabSelection.self, from: Data(json.utf8))

		XCTAssertEqual(selection.selectedSpaceID, StoredBrowserTabCollection.defaultSpaceID)
	}

	func testStoredBrowserTabCollectionRoundTripPreservesSpacesAndSelection() throws {
		let tabID = try XCTUnwrap(UUID(uuidString: "8D8B28EA-BB88-44D8-83C3-B3041F9EAE4B"))
		let collection = StoredBrowserTabCollection(
			storageVersion: StoredBrowserTabCollection.currentVersion,
			collectionID: "default-workspace",
			hasStoredState: true,
			activeSpaceID: "space-two",
			spaces: [
				StoredBrowserSpace(
					id: "space-one",
					name: "One",
					orderKey: "00000000",
					selectedTabID: nil
				),
				StoredBrowserSpace(
					id: "space-two",
					name: "Two",
					orderKey: "00000001",
					selectedTabID: tabID
				),
			],
			tabs: [
				StoredBrowserTab(
					id: tabID,
					objectVersion: 1,
					orderKey: "00000000",
					spaceID: "space-two",
					isArchived: false,
					isPinned: false,
					url: "https://navigator.example"
				),
			]
		)
		let data = try JSONEncoder().encode(collection)
		let decodedCollection = try JSONDecoder().decode(StoredBrowserTabCollection.self, from: data)

		XCTAssertEqual(decodedCollection.activeSpaceID, "space-two")
		XCTAssertEqual(decodedCollection.spaces.count, 2)
		XCTAssertEqual(decodedCollection.tabs.first?.spaceID, "space-two")
	}
}
