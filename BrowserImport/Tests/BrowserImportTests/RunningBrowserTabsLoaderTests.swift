@testable import BrowserImport
import ModelKit
import XCTest

final class RunningBrowserTabsLoaderTests: XCTestCase {
	func testLoadWindowsReturnsEmptyWhenApplicationIsNotRunning() throws {
		let loader = RunningBrowserTabsLoader(
			runScript: { _, _ in
				XCTFail("script runner should not execute")
				return ""
			},
			isApplicationRunning: { _ in false }
		)

		let windows = try loader.loadWindows(for: .chrome)

		XCTAssertTrue(windows.isEmpty)
	}

	func testLoadWindowsBuildsWindowGroupsAndSelectionFromScriptOutput() throws {
		let loader = RunningBrowserTabsLoader(
			runScript: { _, _ in
				[
					"1\t2\t1\tNavigator\thttps://navigator.example",
					"1\t2\t2\tDocs\thttps://docs.example",
					"2\t1\t1\tApple\thttps://apple.com",
				].joined(separator: "\n")
			},
			isApplicationRunning: { _ in true }
		)

		let windows = try loader.loadWindows(for: .chrome)

		XCTAssertEqual(windows.count, 2)
		XCTAssertEqual(windows[0].tabGroups.first?.tabs.count, 2)
		XCTAssertEqual(windows[0].selectedTabID, "window-1-tab-2")
		XCTAssertEqual(windows[1].tabGroups.first?.tabs.first?.url, "https://apple.com")
	}

	func testArcAppleScriptUsesNamedArcTerms() {
		let script = RunningBrowserTabsLoader.appleScript(for: .arc)

		XCTAssertTrue(script.contains("active tab of currentWindow"))
		XCTAssertTrue(script.contains("count of tabs of currentWindow"))
		XCTAssertTrue(script.contains("title of currentTab"))
		XCTAssertFalse(script.contains("«property acTa»"))
		XCTAssertFalse(script.contains("«class tAbB»"))
	}

	func testLoadWindowsRetriesArcWithFallbackScriptAfterParseFailure() throws {
		var scripts = [String]()
		let loader = RunningBrowserTabsLoader(
			runScript: { script, source in
				XCTAssertEqual(source, .arc)
				scripts.append(script)
				if scripts.count == 1 {
					throw BrowserImportError.parseFailed(
						.arc,
						reason: "Arc got an error: Can’t make tab id into type specifier. (-1700)"
					)
				}
				return "1\t1\t1\tNavigator\thttps://navigator.example"
			},
			isApplicationRunning: { _ in true }
		)

		let windows = try loader.loadWindows(for: .arc)

		XCTAssertEqual(scripts.count, 2)
		XCTAssertNotEqual(scripts[0], scripts[1])
		XCTAssertEqual(windows.count, 1)
		XCTAssertEqual(windows[0].selectedTabID, "window-1-tab-1")
	}

	func testCoordinatorMergesRunningWindowsIntoDefaultProfile() throws {
		let coordinator = BrowserImportCoordinator(
			discoverInstallations: {
				[
					BrowserInstallation(
						source: .safari,
						displayName: "Safari",
						profileRootURL: URL(fileURLWithPath: "/tmp/safari"),
						profiles: [
							BrowserProfile(
								id: "Safari",
								displayName: "Safari",
								profileURL: URL(fileURLWithPath: "/tmp/safari"),
								isDefault: true
							),
						]
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
			loadRunningWindows: { _ in
				[
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
				]
			}
		)

		let snapshot = try coordinator.loadSnapshot(
			for: BrowserImportSelection(
				source: .safari,
				profileIDs: [],
				dataKinds: [.tabs],
				conflictMode: .replaceCurrentData
			)
		)

		XCTAssertEqual(snapshot.profiles.first?.windows.count, 1)
		XCTAssertEqual(snapshot.profiles.first?.importedTabs.first?.url, "https://navigator.example")
	}
}
