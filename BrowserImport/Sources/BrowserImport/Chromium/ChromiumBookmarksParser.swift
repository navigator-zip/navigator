import Foundation
import ModelKit

private enum ChromiumBookmarksConstants {
	static let bookmarksFileName = "Bookmarks"
	static let bookmarkBarRootKey = "bookmark_bar"
	static let otherBookmarksRootKey = "other"
	static let syncedBookmarksRootKey = "synced"

	static let emptyFolderNames = Set([
		"",
		"Bookmarks",
	])

	static let fallbackRootDisplayNames = [
		bookmarkBarRootKey: "Bookmarks Bar",
		otherBookmarksRootKey: "Other Bookmarks",
		syncedBookmarksRootKey: "Synced Bookmarks",
	]
}

struct ChromiumBookmarksParser {
	func loadFolders(
		source: BrowserImportSource,
		profileURL: URL
	) throws -> [ImportedBookmarkFolder] {
		let bookmarksURL = profileURL.appendingPathComponent(
			ChromiumBookmarksConstants.bookmarksFileName,
			isDirectory: false
		)
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

		let document: ChromiumBookmarksDocument
		do {
			document = try JSONDecoder().decode(ChromiumBookmarksDocument.self, from: data)
		}
		catch {
			throw BrowserImportError.parseFailed(
				source,
				reason: "Invalid Chromium bookmarks document at \(bookmarksURL.lastPathComponent)"
			)
		}

		return document.roots.compactMap { rootKey, rootNode in
			makeImportedFolder(
				from: rootNode,
				rootKey: rootKey
			)
		}
	}

	private func makeImportedFolder(
		from node: ChromiumBookmarkNode,
		rootKey: String
	) -> ImportedBookmarkFolder? {
		let displayName = resolvedFolderDisplayName(
			rootKey: rootKey,
			nodeName: node.name
		)
		let childFolders = node.children.compactMap { child in
			makeImportedFolder(from: child, rootKey: rootKey)
		}
		let bookmarks = node.children.compactMap(makeImportedBookmark(from:))
		guard childFolders.isEmpty == false || bookmarks.isEmpty == false else {
			return nil
		}
		return ImportedBookmarkFolder(
			id: node.id ?? rootKey,
			displayName: displayName,
			childFolders: childFolders,
			bookmarks: bookmarks
		)
	}

	private func makeImportedBookmark(from node: ChromiumBookmarkNode) -> ImportedBookmark? {
		guard node.type == .url else {
			return nil
		}
		let normalizedURL = node.url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		guard normalizedURL.isEmpty == false else {
			return nil
		}

		let fallbackTitle = URL(string: normalizedURL)?.host() ?? normalizedURL
		let title = normalizedDisplayName(
			node.name,
			fallback: fallbackTitle
		)
		return ImportedBookmark(
			id: node.id ?? normalizedURL,
			title: title,
			url: normalizedURL,
			addedAt: Self.chromiumDate(from: node.dateAdded),
			isFavorite: false
		)
	}

	private func resolvedFolderDisplayName(
		rootKey: String,
		nodeName: String?
	) -> String {
		if let normalizedName = normalizedNonEmptyValue(nodeName),
		   ChromiumBookmarksConstants.emptyFolderNames.contains(normalizedName) == false {
			return normalizedName
		}

		if let fallback = ChromiumBookmarksConstants.fallbackRootDisplayNames[rootKey] {
			return fallback
		}

		return rootKey.replacingOccurrences(of: "_", with: " ").capitalized
	}

	private func normalizedDisplayName(_ value: String?, fallback: String) -> String {
		normalizedNonEmptyValue(value) ?? fallback
	}

	private func normalizedNonEmptyValue(_ value: String?) -> String? {
		guard let value else { return nil }
		let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
		return normalizedValue.isEmpty ? nil : normalizedValue
	}

	static func chromiumDate(from value: String?) -> Date? {
		guard let value, let rawValue = Int64(value) else {
			return nil
		}
		return ChromiumTimestampConverter.date(fromWebKitMicroseconds: rawValue)
	}
}

private struct ChromiumBookmarksDocument: Decodable {
	let roots: [String: ChromiumBookmarkNode]
}

private struct ChromiumBookmarkNode: Decodable {
	enum NodeType: String, Decodable {
		case folder
		case url
	}

	let type: NodeType?
	let id: String?
	let name: String?
	let url: String?
	let dateAdded: String?
	let children: [ChromiumBookmarkNode]

	private enum CodingKeys: String, CodingKey {
		case type
		case id
		case name
		case url
		case dateAdded = "date_added"
		case children
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		type = try container.decodeIfPresent(NodeType.self, forKey: .type)
		id = try container.decodeIfPresent(String.self, forKey: .id)
		name = try container.decodeIfPresent(String.self, forKey: .name)
		url = try container.decodeIfPresent(String.self, forKey: .url)
		dateAdded = try container.decodeIfPresent(String.self, forKey: .dateAdded)
		children = try container.decodeIfPresent([ChromiumBookmarkNode].self, forKey: .children) ?? []
	}
}
