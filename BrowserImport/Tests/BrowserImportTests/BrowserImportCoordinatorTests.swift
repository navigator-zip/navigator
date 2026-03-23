@testable import BrowserImport
import Foundation
import ModelKit
import XCTest

final class BrowserImportCoordinatorTests: XCTestCase {
	func testStreamImportEmitsStartedProfileAndFinishedEventsInOrder() async throws {
		let expectedProfile = ImportedBrowserProfile(
			id: "Default",
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
							]
						),
					],
					selectedTabID: "tab-1"
				),
			],
			bookmarkFolders: [],
			historyEntries: []
		)
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
			loadProfileSnapshot: { _, _, _ in expectedProfile },
			loadRunningWindows: { _ in [] }
		)

		let selection = BrowserImportSelection(
			source: .chrome,
			profileIDs: [],
			dataKinds: BrowserImportDataKind.allCases,
			conflictMode: .replaceCurrentData
		)

		var receivedEvents = [BrowserImportEvent]()
		for try await event in coordinator.streamImport(for: selection) {
			receivedEvents.append(event)
		}

		XCTAssertEqual(
			receivedEvents,
			[
				.started(.chrome),
				.profileImported(.chrome, expectedProfile),
				.finished(
					ImportedBrowserSnapshot(
						source: .chrome,
						profiles: [expectedProfile]
					)
				),
			]
		)
	}

	func testStreamImportMergesRunningWindowsIntoDefaultProfileBeforeYielding() async throws {
		let defaultProfile = BrowserProfile(
			id: "Default",
			displayName: "Default",
			profileURL: URL(fileURLWithPath: "/tmp/chrome/Default"),
			isDefault: true
		)
		let secondaryProfile = BrowserProfile(
			id: "Profile 1",
			displayName: "Profile 1",
			profileURL: URL(fileURLWithPath: "/tmp/chrome/Profile 1"),
			isDefault: false
		)
		let runningWindows = [
			ImportedBrowserWindow(
				id: "window-live",
				displayName: "Window Live",
				tabGroups: [
					ImportedTabGroup(
						id: "group-live",
						displayName: "Window Live",
						kind: .browserWindow,
						colorHex: nil,
						tabs: [
							ImportedTab(
								id: "tab-live",
								title: "Live Tab",
								url: "https://live.example",
								isPinned: false,
								isFavorite: false,
								lastActiveAt: nil
							),
						]
					),
				],
				selectedTabID: "tab-live"
			),
		]
		let coordinator = BrowserImportCoordinator(
			discoverInstallations: {
				[
					BrowserInstallation(
						source: .arc,
						displayName: "Arc",
						profileRootURL: URL(fileURLWithPath: "/tmp/arc"),
						profiles: [defaultProfile, secondaryProfile]
					),
				]
			},
			loadProfileSnapshot: { _, profile, _ in
				ImportedBrowserProfile(
					id: profile.id,
					displayName: profile.displayName,
					isDefault: profile.isDefault,
					windows: [],
					bookmarkFolders: [],
					historyEntries: []
				)
			},
			loadRunningWindows: { _ in runningWindows }
		)

		let selection = BrowserImportSelection(
			source: .arc,
			profileIDs: [],
			dataKinds: [.tabs],
			conflictMode: .replaceCurrentData
		)

		var events = [BrowserImportEvent]()
		for try await event in coordinator.streamImport(for: selection) {
			events.append(event)
		}
		let yieldedDefaultProfile = try XCTUnwrap(
			events.compactMap { event -> ImportedBrowserProfile? in
				guard case .profileImported(_, let profile) = event else { return nil }
				return profile.id == defaultProfile.id ? profile : nil
			}.first
		)

		XCTAssertEqual(yieldedDefaultProfile.windows, runningWindows)
		let yieldedSecondaryProfile = try XCTUnwrap(
			events.compactMap { event -> ImportedBrowserProfile? in
				guard case .profileImported(_, let profile) = event else { return nil }
				return profile.id == secondaryProfile.id ? profile : nil
			}.first
		)
		XCTAssertEqual(yieldedSecondaryProfile.windows, [])
	}

	func testStreamImportMergesChunkedProfilesIntoSingleFinishedSnapshot() async throws {
		let defaultProfile = BrowserProfile(
			id: "Default",
			displayName: "Default",
			profileURL: URL(fileURLWithPath: "/tmp/arc/Default"),
			isDefault: true
		)
		let firstChunk = ImportedBrowserProfile(
			id: "Default",
			displayName: "Default",
			isDefault: true,
			windows: [
				ImportedBrowserWindow(
					id: "space-1",
					displayName: "Space 1",
					tabGroups: [
						ImportedTabGroup(
							id: "space-1-group",
							displayName: "Space 1",
							kind: .space,
							colorHex: nil,
							tabs: [
								ImportedTab(
									id: "tab-1",
									title: "One",
									url: "https://one.example",
									isPinned: true,
									isFavorite: false,
									lastActiveAt: nil
								),
							]
						),
					],
					selectedTabID: nil
				),
			],
			bookmarkFolders: [],
			historyEntries: []
		)
		let secondChunk = ImportedBrowserProfile(
			id: "Default",
			displayName: "Default",
			isDefault: true,
			windows: [
				ImportedBrowserWindow(
					id: "space-2",
					displayName: "Space 2",
					tabGroups: [
						ImportedTabGroup(
							id: "space-2-group",
							displayName: "Space 2",
							kind: .space,
							colorHex: nil,
							tabs: [
								ImportedTab(
									id: "tab-2",
									title: "Two",
									url: "https://two.example",
									isPinned: true,
									isFavorite: false,
									lastActiveAt: nil
								),
							]
						),
					],
					selectedTabID: nil
				),
			],
			bookmarkFolders: [],
			historyEntries: []
		)
		let coordinator = BrowserImportCoordinator(
			discoverInstallations: {
				[
					BrowserInstallation(
						source: .arc,
						displayName: "Arc",
						profileRootURL: URL(fileURLWithPath: "/tmp/arc"),
						profiles: [defaultProfile]
					),
				]
			},
			loadProfileSnapshot: { _, _, _ in
				XCTFail("stream import should use chunk loader")
				return firstChunk
			},
			loadProfileChunkStream: { _, _, _ in
				AsyncThrowingStream { continuation in
					continuation.yield(firstChunk)
					continuation.yield(secondChunk)
					continuation.finish()
				}
			},
			loadRunningWindows: { _ in [] }
		)

		var events = [BrowserImportEvent]()
		for try await event in coordinator.streamImport(
			for: BrowserImportSelection(
				source: .arc,
				profileIDs: [],
				dataKinds: [.tabs],
				conflictMode: .replaceCurrentData
			)
		) {
			events.append(event)
		}

		XCTAssertEqual(
			events,
			[
				.started(.arc),
				.profileImported(.arc, firstChunk),
				.profileImported(.arc, secondChunk),
				.finished(
					ImportedBrowserSnapshot(
						source: .arc,
						profiles: [
							ImportedBrowserProfile(
								id: "Default",
								displayName: "Default",
								isDefault: true,
								windows: firstChunk.windows + secondChunk.windows,
								bookmarkFolders: [],
								historyEntries: []
							),
						]
					)
				),
			]
		)
	}
}
