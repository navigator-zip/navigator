import Foundation

public enum BrowserImportSource: String, CaseIterable, Codable, Sendable {
	case arc
	case chrome
	case safari

	public var displayName: String {
		switch self {
		case .arc:
			"Arc"
		case .chrome:
			"Chrome"
		case .safari:
			"Safari"
		}
	}
}

public enum BrowserImportDataKind: String, CaseIterable, Codable, Sendable {
	case tabs
	case bookmarks
	case history
}

public enum BrowserImportConflictMode: String, CaseIterable, Codable, Sendable {
	case merge
	case replaceCurrentData
}

public struct BrowserProfile: Codable, Equatable, Hashable, Sendable {
	public let id: String
	public let displayName: String
	public let profileURL: URL
	public let isDefault: Bool

	public init(
		id: String,
		displayName: String,
		profileURL: URL,
		isDefault: Bool
	) {
		self.id = id
		self.displayName = displayName
		self.profileURL = profileURL
		self.isDefault = isDefault
	}
}

public struct BrowserInstallation: Codable, Equatable, Hashable, Sendable {
	public let source: BrowserImportSource
	public let displayName: String
	public let profileRootURL: URL
	public let profiles: [BrowserProfile]

	public init(
		source: BrowserImportSource,
		displayName: String,
		profileRootURL: URL,
		profiles: [BrowserProfile]
	) {
		self.source = source
		self.displayName = displayName
		self.profileRootURL = profileRootURL
		self.profiles = profiles
	}
}

public struct BrowserImportSelection: Codable, Equatable, Sendable {
	public let source: BrowserImportSource
	public let profileIDs: [String]
	public let dataKinds: [BrowserImportDataKind]
	public let conflictMode: BrowserImportConflictMode

	public init(
		source: BrowserImportSource,
		profileIDs: [String],
		dataKinds: [BrowserImportDataKind],
		conflictMode: BrowserImportConflictMode
	) {
		self.source = source
		self.profileIDs = profileIDs
		self.dataKinds = dataKinds
		self.conflictMode = conflictMode
	}
}

public enum ImportedTabGroupKind: String, CaseIterable, Codable, Sendable {
	case browserWindow
	case savedGroup
	case space
}

public struct ImportedBrowserSnapshot: Codable, Equatable, Sendable {
	public let source: BrowserImportSource
	public let profiles: [ImportedBrowserProfile]

	public init(source: BrowserImportSource, profiles: [ImportedBrowserProfile]) {
		self.source = source
		self.profiles = profiles
	}

	public var isEmpty: Bool {
		preview == .empty
	}

	public var preview: BrowserImportPreview {
		let workspaceCount = profiles.count
		let tabGroupCount = profiles.reduce(0) { partialResult, profile in
			partialResult + profile.windows.reduce(0) { $0 + $1.tabGroups.count }
		}
		let tabCount = profiles.reduce(0) { partialResult, profile in
			partialResult + profile.windows.reduce(0) { windowResult, window in
				windowResult + window.tabGroups.reduce(0) { $0 + $1.tabs.count }
			}
		}
		let bookmarkFolderCount = profiles.reduce(0) { partialResult, profile in
			partialResult + profile.bookmarkFolders.reduce(0) { $0 + $1.recursiveFolderCount }
		}
		let bookmarkCount = profiles.reduce(0) { partialResult, profile in
			partialResult + profile.bookmarkFolders.reduce(0) { $0 + $1.recursiveBookmarkCount }
		}
		let historyEntryCount = profiles.reduce(0) { $0 + $1.historyEntries.count }

		return BrowserImportPreview(
			workspaceCount: workspaceCount,
			tabGroupCount: tabGroupCount,
			tabCount: tabCount,
			bookmarkFolderCount: bookmarkFolderCount,
			bookmarkCount: bookmarkCount,
			historyEntryCount: historyEntryCount
		)
	}

	public var importedTabs: [ImportedTab] {
		profiles.flatMap(\.importedTabs)
	}

	public var importedBookmarks: [ImportedBookmark] {
		profiles.flatMap(\.importedBookmarks)
	}

	public var importedHistoryEntries: [ImportedHistoryEntry] {
		profiles.flatMap(\.historyEntries)
	}
}

public struct ImportedBrowserProfile: Codable, Equatable, Sendable {
	public let id: String
	public let displayName: String
	public let isDefault: Bool
	public let windows: [ImportedBrowserWindow]
	public let bookmarkFolders: [ImportedBookmarkFolder]
	public let historyEntries: [ImportedHistoryEntry]

	public init(
		id: String,
		displayName: String,
		isDefault: Bool,
		windows: [ImportedBrowserWindow],
		bookmarkFolders: [ImportedBookmarkFolder],
		historyEntries: [ImportedHistoryEntry]
	) {
		self.id = id
		self.displayName = displayName
		self.isDefault = isDefault
		self.windows = windows
		self.bookmarkFolders = bookmarkFolders
		self.historyEntries = historyEntries
	}

	public var importedTabs: [ImportedTab] {
		windows.flatMap { window in
			window.tabGroups.flatMap(\.tabs)
		}
	}

	public var importedBookmarks: [ImportedBookmark] {
		bookmarkFolders.flatMap(\.recursiveBookmarks)
	}
}

public struct ImportedBrowserWindow: Codable, Equatable, Sendable {
	public let id: String
	public let displayName: String
	public let tabGroups: [ImportedTabGroup]
	public let selectedTabID: String?

	public init(
		id: String,
		displayName: String,
		tabGroups: [ImportedTabGroup],
		selectedTabID: String?
	) {
		self.id = id
		self.displayName = displayName
		self.tabGroups = tabGroups
		self.selectedTabID = selectedTabID
	}
}

public struct ImportedTabGroup: Codable, Equatable, Sendable {
	public let id: String
	public let displayName: String
	public let kind: ImportedTabGroupKind
	public let colorHex: String?
	public let tabs: [ImportedTab]

	public init(
		id: String,
		displayName: String,
		kind: ImportedTabGroupKind,
		colorHex: String?,
		tabs: [ImportedTab]
	) {
		self.id = id
		self.displayName = displayName
		self.kind = kind
		self.colorHex = colorHex
		self.tabs = tabs
	}
}

public struct ImportedTab: Codable, Equatable, Sendable {
	public let id: String
	public let title: String
	public let url: String
	public let isPinned: Bool
	public let isFavorite: Bool
	public let lastActiveAt: Date?

	public init(
		id: String,
		title: String,
		url: String,
		isPinned: Bool,
		isFavorite: Bool,
		lastActiveAt: Date?
	) {
		self.id = id
		self.title = title
		self.url = url
		self.isPinned = isPinned
		self.isFavorite = isFavorite
		self.lastActiveAt = lastActiveAt
	}
}

public struct ImportedBookmarkFolder: Codable, Equatable, Sendable {
	public let id: String
	public let displayName: String
	public let childFolders: [ImportedBookmarkFolder]
	public let bookmarks: [ImportedBookmark]

	public init(
		id: String,
		displayName: String,
		childFolders: [ImportedBookmarkFolder],
		bookmarks: [ImportedBookmark]
	) {
		self.id = id
		self.displayName = displayName
		self.childFolders = childFolders
		self.bookmarks = bookmarks
	}

	public var recursiveFolderCount: Int {
		1 + childFolders.reduce(0) { $0 + $1.recursiveFolderCount }
	}

	public var recursiveBookmarkCount: Int {
		bookmarks.count + childFolders.reduce(0) { $0 + $1.recursiveBookmarkCount }
	}

	public var recursiveBookmarks: [ImportedBookmark] {
		bookmarks + childFolders.flatMap(\.recursiveBookmarks)
	}
}

public struct ImportedBookmark: Codable, Equatable, Sendable {
	public let id: String
	public let title: String
	public let url: String
	public let addedAt: Date?
	public let isFavorite: Bool

	public init(
		id: String,
		title: String,
		url: String,
		addedAt: Date?,
		isFavorite: Bool
	) {
		self.id = id
		self.title = title
		self.url = url
		self.addedAt = addedAt
		self.isFavorite = isFavorite
	}
}

public struct ImportedHistoryEntry: Codable, Equatable, Sendable {
	public let id: String
	public let title: String?
	public let url: String
	public let visitedAt: Date

	public init(
		id: String,
		title: String?,
		url: String,
		visitedAt: Date
	) {
		self.id = id
		self.title = title
		self.url = url
		self.visitedAt = visitedAt
	}
}

public struct BrowserImportPreview: Codable, Equatable, Sendable {
	public let workspaceCount: Int
	public let tabGroupCount: Int
	public let tabCount: Int
	public let bookmarkFolderCount: Int
	public let bookmarkCount: Int
	public let historyEntryCount: Int

	public init(
		workspaceCount: Int,
		tabGroupCount: Int,
		tabCount: Int,
		bookmarkFolderCount: Int,
		bookmarkCount: Int,
		historyEntryCount: Int
	) {
		self.workspaceCount = workspaceCount
		self.tabGroupCount = tabGroupCount
		self.tabCount = tabCount
		self.bookmarkFolderCount = bookmarkFolderCount
		self.bookmarkCount = bookmarkCount
		self.historyEntryCount = historyEntryCount
	}

	public static let empty = Self(
		workspaceCount: 0,
		tabGroupCount: 0,
		tabCount: 0,
		bookmarkFolderCount: 0,
		bookmarkCount: 0,
		historyEntryCount: 0
	)
}

public struct ImportedBrowserLibraryRecord: Codable, Equatable, Sendable {
	public let snapshot: ImportedBrowserSnapshot
	public let importedAt: Date

	public init(
		snapshot: ImportedBrowserSnapshot,
		importedAt: Date
	) {
		self.snapshot = snapshot
		self.importedAt = importedAt
	}
}

public struct ImportedBrowserLibrary: Codable, Equatable, Sendable {
	public let records: [ImportedBrowserLibraryRecord]

	public init(records: [ImportedBrowserLibraryRecord]) {
		self.records = records
	}

	public var latestRecord: ImportedBrowserLibraryRecord? {
		records.max(by: { $0.importedAt < $1.importedAt })
	}

	public func replacingRecord(
		for source: BrowserImportSource,
		with snapshot: ImportedBrowserSnapshot,
		importedAt: Date
	) -> Self {
		let filteredRecords = records.filter { $0.snapshot.source != source }
		return Self(
			records: filteredRecords + [
				ImportedBrowserLibraryRecord(
					snapshot: snapshot,
					importedAt: importedAt
				),
			]
		)
	}

	public static let empty = Self(records: [])
}
