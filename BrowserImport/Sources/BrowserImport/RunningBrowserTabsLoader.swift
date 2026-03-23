import AppKit
import Foundation
import ModelKit

struct RunningBrowserTabsLoader {
	typealias ScriptRunner = (_ script: String, _ source: BrowserImportSource) throws -> String
	typealias IsApplicationRunning = (_ source: BrowserImportSource) -> Bool

	private let runScript: ScriptRunner
	private let isApplicationRunning: IsApplicationRunning

	init(
		runScript: @escaping ScriptRunner = Self.liveRunScript,
		isApplicationRunning: @escaping IsApplicationRunning = Self.liveIsApplicationRunning
	) {
		self.runScript = runScript
		self.isApplicationRunning = isApplicationRunning
	}

	func loadWindows(for source: BrowserImportSource) throws -> [ImportedBrowserWindow] {
		guard isApplicationRunning(source) else { return [] }
		let output = try loadOutput(for: source)
		let rows = output
			.split(separator: "\n", omittingEmptySubsequences: true)
			.compactMap { Self.parseRow(String($0)) }
		guard rows.isEmpty == false else { return [] }

		let rowsByWindow = Dictionary(grouping: rows, by: \.windowIndex)
		return rowsByWindow.keys.sorted().map { windowIndex in
			let rowsForWindow = rowsByWindow[windowIndex, default: []].sorted {
				$0.tabIndex < $1.tabIndex
			}
			let selectedTabID = rowsForWindow.first(where: { $0.tabIndex == $0.activeTabIndex })?.tabID
			return ImportedBrowserWindow(
				id: "window-\(windowIndex)",
				displayName: "Window \(windowIndex)",
				tabGroups: [
					ImportedTabGroup(
						id: "window-\(windowIndex)-group",
						displayName: "Window \(windowIndex)",
						kind: .browserWindow,
						colorHex: nil,
						tabs: rowsForWindow.map { row in
							ImportedTab(
								id: row.tabID,
								title: row.title,
								url: row.url,
								isPinned: false,
								isFavorite: false,
								lastActiveAt: nil
							)
						}
					),
				],
				selectedTabID: selectedTabID
			)
		}
	}

	static func appleScript(for source: BrowserImportSource) -> String {
		appleScripts(for: source).first ?? ""
	}

	private func loadOutput(for source: BrowserImportSource) throws -> String {
		var lastError: Error?
		for script in Self.appleScripts(for: source) {
			do {
				return try runScript(script, source)
			}
			catch {
				lastError = error
			}
		}

		throw lastError ?? BrowserImportError.parseFailed(
			source,
			reason: "browser script did not produce any output"
		)
	}

	private static func appleScripts(for source: BrowserImportSource) -> [String] {
		switch source {
		case .arc:
			return [
				arcAppleScript(),
				arcFallbackAppleScript(),
			]
		case .chrome:
			return [chromiumAppleScript(applicationName: "Google Chrome")]
		case .safari:
			return [safariAppleScript()]
		}
	}

	private static func arcAppleScript() -> String {
		"""
		tell application "Arc"
			set outputLines to {}
			repeat with windowIndex from 1 to count of windows
				set currentWindow to window windowIndex
				set activeIndex to 0
				set activeTab to missing value
				try
					set activeTab to active tab of currentWindow
				end try
				repeat with tabIndex from 1 to count of tabs of currentWindow
					set currentTab to tab tabIndex of currentWindow
					if activeIndex is 0 then
						try
							if currentTab is activeTab then
								set activeIndex to tabIndex
							end if
						end try
					end if
					set tabURL to URL of currentTab
					if tabURL is not missing value and tabURL is not "" then
						set end of outputLines to (windowIndex as string) & tab & (activeIndex as string) & tab & (tabIndex as string) & tab & (title of currentTab) & tab & tabURL
					end if
				end repeat
			end repeat
			set AppleScript's text item delimiters to linefeed
			return outputLines as string
		end tell
		"""
	}

	private static func arcFallbackAppleScript() -> String {
		"""
		tell application "Arc"
			set outputLines to {}
			repeat with windowIndex from 1 to count of windows
				set currentWindow to window windowIndex
				set activeIndex to 0
				set activeTabID to ""
				try
					set activeTabID to id of active tab of currentWindow
				end try
				repeat with tabIndex from 1 to count of tabs of currentWindow
					set currentTab to tab tabIndex of currentWindow
					if activeIndex is 0 then
						try
							if (id of currentTab) is activeTabID then
								set activeIndex to tabIndex
							end if
						end try
					end if
					set tabURL to URL of currentTab
					if tabURL is not missing value and tabURL is not "" then
						set end of outputLines to (windowIndex as string) & tab & (activeIndex as string) & tab & (tabIndex as string) & tab & (title of currentTab) & tab & tabURL
					end if
				end repeat
			end repeat
			set AppleScript's text item delimiters to linefeed
			return outputLines as string
		end tell
		"""
	}

	private static func chromiumAppleScript(applicationName: String) -> String {
		"""
		tell application "\(applicationName)"
			set outputLines to {}
			repeat with windowIndex from 1 to count of windows
				set currentWindow to window windowIndex
				set activeIndex to active tab index of currentWindow
				repeat with tabIndex from 1 to count of tabs of currentWindow
					set currentTab to tab tabIndex of currentWindow
					set tabURL to URL of currentTab
					if tabURL is not missing value and tabURL is not "" then
						set end of outputLines to (windowIndex as string) & tab & (activeIndex as string) & tab & (tabIndex as string) & tab & (title of currentTab) & tab & tabURL
					end if
				end repeat
			end repeat
			set AppleScript's text item delimiters to linefeed
			return outputLines as string
		end tell
		"""
	}

	private static func safariAppleScript() -> String {
		"""
		tell application "Safari"
			set outputLines to {}
			repeat with windowIndex from 1 to count of windows
				set currentWindow to window windowIndex
				set activeIndex to index of current tab of currentWindow
				repeat with tabIndex from 1 to count of tabs of currentWindow
					set currentTab to tab tabIndex of currentWindow
					set tabURL to URL of currentTab
					if tabURL is not missing value and tabURL is not "" then
						set end of outputLines to (windowIndex as string) & tab & (activeIndex as string) & tab & (tabIndex as string) & tab & (name of currentTab) & tab & tabURL
					end if
				end repeat
			end repeat
			set AppleScript's text item delimiters to linefeed
			return outputLines as string
		end tell
		"""
	}

	private static func parseRow(_ row: String) -> TabRow? {
		let components = row.components(separatedBy: "\t")
		guard components.count >= 5 else { return nil }
		guard
			let windowIndex = Int(components[0]),
			let activeTabIndex = Int(components[1]),
			let tabIndex = Int(components[2])
		else {
			return nil
		}

		let title = components[3].trimmingCharacters(in: .whitespacesAndNewlines)
		let url = components[4].trimmingCharacters(in: .whitespacesAndNewlines)
		guard url.isEmpty == false else { return nil }

		return TabRow(
			windowIndex: windowIndex,
			activeTabIndex: activeTabIndex,
			tabIndex: tabIndex,
			tabID: "window-\(windowIndex)-tab-\(tabIndex)",
			title: title.isEmpty ? url : title,
			url: url
		)
	}

	private static func liveRunScript(
		_ script: String,
		_ source: BrowserImportSource
	) throws -> String {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
		process.arguments = ["-e", script]
		let stdout = Pipe()
		let stderr = Pipe()
		process.standardOutput = stdout
		process.standardError = stderr
		try process.run()
		process.waitUntilExit()

		let output = String(
			data: stdout.fileHandleForReading.readDataToEndOfFile(),
			encoding: .utf8
		) ?? ""
		let errorOutput = String(
			data: stderr.fileHandleForReading.readDataToEndOfFile(),
			encoding: .utf8
		) ?? ""
		if process.terminationStatus != 0 {
			throw BrowserImportError.parseFailed(
				source,
				reason: errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
			)
		}
		return output
	}

	private static func liveIsApplicationRunning(_ source: BrowserImportSource) -> Bool {
		let bundleIdentifier = switch source {
		case .arc:
			"company.thebrowser.Browser"
		case .chrome:
			"com.google.Chrome"
		case .safari:
			"com.apple.Safari"
		}
		return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty == false
	}

	private struct TabRow {
		let windowIndex: Int
		let activeTabIndex: Int
		let tabIndex: Int
		let tabID: String
		let title: String
		let url: String
	}
}
