import Foundation
import ModelKit

struct SafariSnapshotLoader {
	private enum Constants {
		static let bookmarksFileName = "Bookmarks.plist"
		static let historyFileName = "History.db"
		static let sqliteBinaryPath = "/usr/bin/sqlite3"
		static let readingListIdentifier = "com.apple.ReadingList"
		static let syntheticRootFolderName = "Bookmarks"
		static let historyDateReference = Date(timeIntervalSinceReferenceDate: 0)
	}

	func loadProfile(
		source: BrowserImportSource,
		profile: BrowserProfile,
		dataKinds: [BrowserImportDataKind]
	) throws -> ImportedBrowserProfile {
		var bookmarkFolders = [ImportedBookmarkFolder]()
		var historyEntries = [ImportedHistoryEntry]()

		if dataKinds.contains(.bookmarks) {
			bookmarkFolders = try loadBookmarks(from: profile.profileURL, source: source)
		}

		if dataKinds.contains(.history) {
			historyEntries = try loadHistory(from: profile.profileURL, source: source)
		}

		return ImportedBrowserProfile(
			id: profile.id,
			displayName: profile.displayName,
			isDefault: profile.isDefault,
			windows: [],
			bookmarkFolders: bookmarkFolders,
			historyEntries: historyEntries
		)
	}

	private func loadBookmarks(
		from profileURL: URL,
		source: BrowserImportSource
	) throws -> [ImportedBookmarkFolder] {
		let bookmarksURL = profileURL.appendingPathComponent(Constants.bookmarksFileName)
		guard FileManager.default.fileExists(atPath: bookmarksURL.path) else {
			return []
		}

		let data: Data
		do {
			data = try Data(contentsOf: bookmarksURL)
		}
		catch {
			throw BrowserImportError.readFailed(bookmarksURL)
		}

		let rootObject: Any
		do {
			rootObject = try PropertyListSerialization.propertyList(from: data, format: nil)
		}
		catch {
			throw BrowserImportError.parseFailed(source, reason: "invalid Safari bookmarks plist")
		}

		guard let rootDictionary = rootObject as? [String: Any] else {
			throw BrowserImportError.parseFailed(source, reason: "unexpected Safari bookmarks root")
		}

		let parsedRoot = parseBookmarkNode(
			rootDictionary,
			pathComponents: [Constants.syntheticRootFolderName]
		)
		switch parsedRoot {
		case .folder(let folder):
			return [folder]
		case .bookmark:
			return []
		case .none:
			return []
		}
	}

	private func loadHistory(
		from profileURL: URL,
		source: BrowserImportSource
	) throws -> [ImportedHistoryEntry] {
		let historyURL = profileURL.appendingPathComponent(Constants.historyFileName)
		guard FileManager.default.fileExists(atPath: historyURL.path) else {
			return []
		}

		let copiedDatabaseURL = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString)
			.appendingPathComponent(Constants.historyFileName)

		do {
			try FileManager.default.createDirectory(
				at: copiedDatabaseURL.deletingLastPathComponent(),
				withIntermediateDirectories: true
			)
			try FileManager.default.copyItem(at: historyURL, to: copiedDatabaseURL)
		}
		catch {
			throw BrowserImportError.readFailed(historyURL)
		}

		defer {
			try? FileManager.default.removeItem(at: copiedDatabaseURL.deletingLastPathComponent())
		}

		let rows = try queryHistoryRows(databaseURL: copiedDatabaseURL, source: source)
		return rows.map { row in
			ImportedHistoryEntry(
				id: "history-\(row.visitID)",
				title: normalize(row.title),
				url: row.url,
				visitedAt: Date(
					timeInterval: row.visitTime,
					since: Constants.historyDateReference
				)
			)
		}
	}

	private func queryHistoryRows(
		databaseURL: URL,
		source: BrowserImportSource
	) throws -> [SafariHistoryRow] {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: Constants.sqliteBinaryPath)
		process.arguments = [
			"-readonly",
			"-json",
			databaseURL.path,
			Self.historyQuery,
		]

		let outputPipe = Pipe()
		let errorPipe = Pipe()
		process.standardOutput = outputPipe
		process.standardError = errorPipe

		do {
			try process.run()
		}
		catch {
			throw BrowserImportError.readFailed(databaseURL)
		}

		process.waitUntilExit()

		let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
		let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

		guard process.terminationStatus == 0 else {
			let errorMessage = String(data: errorData, encoding: .utf8)?
				.trimmingCharacters(in: .whitespacesAndNewlines)
			throw BrowserImportError.parseFailed(
				source,
				reason: errorMessage?.isEmpty == false ? errorMessage! : "sqlite history query failed"
			)
		}

		if outputData.isEmpty {
			return []
		}

		do {
			return try JSONDecoder().decode([SafariHistoryRow].self, from: outputData)
		}
		catch {
			throw BrowserImportError.parseFailed(source, reason: "invalid Safari history query output")
		}
	}

	private func parseBookmarkNode(
		_ node: [String: Any],
		pathComponents: [String]
	) -> ParsedBookmarkNode? {
		if isReadingList(node) {
			return nil
		}

		let bookmarkType = node["WebBookmarkType"] as? String
		switch bookmarkType {
		case "WebBookmarkTypeList":
			return parseFolderNode(node, pathComponents: pathComponents)
		case "WebBookmarkTypeLeaf":
			return parseLeafNode(node, pathComponents: pathComponents)
		default:
			return parseFolderNode(node, pathComponents: pathComponents)
		}
	}

	private func parseFolderNode(
		_ node: [String: Any],
		pathComponents: [String]
	) -> ParsedBookmarkNode? {
		let title = bookmarkTitle(for: node) ?? pathComponents.last ?? Constants.syntheticRootFolderName
		let nextPathComponents = appendPathComponent(title, to: pathComponents)
		let children = (node["Children"] as? [[String: Any]]) ?? []

		var childFolders = [ImportedBookmarkFolder]()
		var bookmarks = [ImportedBookmark]()

		for child in children {
			switch parseBookmarkNode(child, pathComponents: nextPathComponents) {
			case .folder(let folder):
				childFolders.append(folder)
			case .bookmark(let bookmark):
				bookmarks.append(bookmark)
			case .none:
				continue
			}
		}

		if childFolders.isEmpty, bookmarks.isEmpty, node["Children"] != nil {
			return nil
		}

		return .folder(
			ImportedBookmarkFolder(
				id: folderIdentifier(from: nextPathComponents),
				displayName: title,
				childFolders: childFolders,
				bookmarks: bookmarks
			)
		)
	}

	private func parseLeafNode(
		_ node: [String: Any],
		pathComponents: [String]
	) -> ParsedBookmarkNode? {
		guard
			let urlString = normalize(node["URLString"] as? String),
			URL(string: urlString) != nil
		else {
			return nil
		}

		let title = bookmarkTitle(for: node) ?? urlString
		let identifierPath = appendPathComponent(title, to: pathComponents)
		return .bookmark(
			ImportedBookmark(
				id: bookmarkIdentifier(from: identifierPath),
				title: title,
				url: urlString,
				addedAt: nil,
				isFavorite: false
			)
		)
	}

	private func bookmarkTitle(for node: [String: Any]) -> String? {
		if let uriDictionary = node["URIDictionary"] as? [String: Any],
		   let title = normalize(uriDictionary["title"] as? String) {
			return title
		}

		if let title = normalize(node["Title"] as? String) {
			return title
		}

		return nil
	}

	private func isReadingList(_ node: [String: Any]) -> Bool {
		if let identifier = normalize(node["WebBookmarkIdentifier"] as? String),
		   identifier == Constants.readingListIdentifier {
			return true
		}

		if let title = bookmarkTitle(for: node), title == "Reading List" {
			return true
		}

		return false
	}

	private func appendPathComponent(_ component: String, to pathComponents: [String]) -> [String] {
		let normalizedComponent = normalize(component) ?? component
		return pathComponents + [normalizedComponent]
	}

	private func folderIdentifier(from pathComponents: [String]) -> String {
		"folder:\(pathComponents.joined(separator: "/"))"
	}

	private func bookmarkIdentifier(from pathComponents: [String]) -> String {
		"bookmark:\(pathComponents.joined(separator: "/"))"
	}

	private func normalize(_ value: String?) -> String? {
		guard let value else { return nil }
		let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmedValue.isEmpty ? nil : trimmedValue
	}

	private static let historyQuery = """
	SELECT
		history_visits.id AS visitID,
		history_items.url AS url,
		history_items.title AS title,
		history_visits.visit_time AS visitTime
	FROM history_visits
	INNER JOIN history_items
		ON history_items.id = history_visits.history_item
	ORDER BY history_visits.visit_time DESC;
	"""
}

private enum ParsedBookmarkNode {
	case folder(ImportedBookmarkFolder)
	case bookmark(ImportedBookmark)
}

private struct SafariHistoryRow: Decodable {
	let visitID: Int
	let url: String
	let title: String?
	let visitTime: TimeInterval
}
