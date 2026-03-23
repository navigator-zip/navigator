import Foundation

public struct StoredBrowserHistoryEntry: Codable, Equatable, Sendable {
	public let url: String
	public let title: String?
	public let originalURL: String?
	public let displayURL: String?
	public let transitionType: String?
	public let isTopLevelNativeContent: Bool
	public let nativeContentKind: String?

	public init(
		url: String,
		title: String? = nil,
		originalURL: String? = nil,
		displayURL: String? = nil,
		transitionType: String? = nil,
		isTopLevelNativeContent: Bool = false,
		nativeContentKind: String? = nil
	) {
		self.url = url
		self.title = title
		self.originalURL = originalURL
		self.displayURL = displayURL
		self.transitionType = transitionType
		self.isTopLevelNativeContent = isTopLevelNativeContent
		self.nativeContentKind = nativeContentKind
	}
}

public struct StoredBrowserTab: Codable, Equatable, Identifiable, Sendable {
	public let id: UUID
	public let objectVersion: Int
	public let orderKey: String
	public let spaceID: String
	public let parentObjectID: String?
	public let isArchived: Bool
	public let isPinned: Bool
	public let url: String
	public let title: String?
	public let faviconURL: String?
	public let historyEntries: [StoredBrowserHistoryEntry]?
	public let currentHistoryIndex: Int?

	private enum CodingKeys: String, CodingKey {
		case id
		case objectVersion
		case orderKey
		case spaceID
		case parentObjectID
		case isArchived
		case isPinned
		case url
		case title
		case faviconURL
		case historyEntries
		case currentHistoryIndex
	}

	public init(
		id: UUID,
		objectVersion: Int,
		orderKey: String,
		spaceID: String = StoredBrowserTabCollection.defaultSpaceID,
		parentObjectID: String? = nil,
		isArchived: Bool = false,
		isPinned: Bool = false,
		url: String,
		title: String? = nil,
		faviconURL: String? = nil,
		historyEntries: [StoredBrowserHistoryEntry]? = nil,
		currentHistoryIndex: Int? = nil
	) {
		self.id = id
		self.objectVersion = max(objectVersion, 1)
		self.orderKey = orderKey
		self.spaceID = spaceID
		self.parentObjectID = parentObjectID
		self.isArchived = isArchived
		self.isPinned = isPinned
		self.url = url
		self.title = title
		self.faviconURL = faviconURL
		self.historyEntries = historyEntries
		self.currentHistoryIndex = currentHistoryIndex
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		id = try container.decode(UUID.self, forKey: .id)
		objectVersion = try max(container.decode(Int.self, forKey: .objectVersion), 1)
		orderKey = try container.decode(String.self, forKey: .orderKey)
		spaceID = try container.decodeIfPresent(String.self, forKey: .spaceID)
			?? container.decodeIfPresent(String.self, forKey: .parentObjectID)
			?? StoredBrowserTabCollection.defaultSpaceID
		parentObjectID = try container.decodeIfPresent(String.self, forKey: .parentObjectID)
		isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
		isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
		url = try container.decode(String.self, forKey: .url)
		title = try container.decodeIfPresent(String.self, forKey: .title)
		faviconURL = try container.decodeIfPresent(String.self, forKey: .faviconURL)
		historyEntries = try container.decodeIfPresent([StoredBrowserHistoryEntry].self, forKey: .historyEntries)
		currentHistoryIndex = try container.decodeIfPresent(Int.self, forKey: .currentHistoryIndex)
	}

	public var resolvedHistoryEntries: [StoredBrowserHistoryEntry] {
		let filteredEntries = historyEntries?.filter { entry in
			entry.url.isEmpty == false && entry.url != BrowserSessionHistoryDefaults.aboutBlankURL
		}
		if let filteredEntries, filteredEntries.isEmpty == false {
			return filteredEntries
		}
		return [
			StoredBrowserHistoryEntry(
				url: url,
				title: title
			),
		]
	}

	public var resolvedCurrentHistoryIndex: Int {
		let entries = resolvedHistoryEntries
		guard let currentHistoryIndex else { return max(0, entries.count - 1) }
		return min(max(0, currentHistoryIndex), entries.count - 1)
	}
}

public enum BrowserSessionHistoryDefaults {
	public static let aboutBlankURL = "about:blank"
}

public struct StoredBrowserSpace: Codable, Equatable, Identifiable, Sendable {
	public let id: String
	public let name: String
	public let orderKey: String
	public let selectedTabID: UUID?

	public init(
		id: String,
		name: String = "",
		orderKey: String,
		selectedTabID: UUID? = nil
	) {
		self.id = id
		self.name = name
		self.orderKey = orderKey
		self.selectedTabID = selectedTabID
	}
}

public struct StoredBrowserTabCollection: Codable, Equatable, Sendable {
	public static let currentVersion = 2
	public static let defaultCollectionID = "default-workspace"
	public static let defaultSpaceID = "default-space"

	public let storageVersion: Int
	public let collectionID: String
	public let hasStoredState: Bool
	public let activeSpaceID: String
	public let spaces: [StoredBrowserSpace]
	public let tabs: [StoredBrowserTab]

	private enum CodingKeys: String, CodingKey {
		case storageVersion
		case collectionID
		case hasStoredState
		case activeSpaceID
		case spaces
		case tabs
	}

	public init(
		storageVersion: Int = Self.currentVersion,
		collectionID: String = Self.defaultCollectionID,
		hasStoredState: Bool = true,
		activeSpaceID: String = Self.defaultSpaceID,
		spaces: [StoredBrowserSpace] = [
			StoredBrowserSpace(
				id: Self.defaultSpaceID,
				orderKey: "00000000"
			),
		],
		tabs: [StoredBrowserTab]
	) {
		let normalizedSpaces = Self.normalizedSpaces(
			spaces: spaces,
			tabs: tabs
		)
		let resolvedActiveSpaceID = normalizedSpaces.contains(where: { $0.id == activeSpaceID })
			? activeSpaceID
			: normalizedSpaces.first?.id ?? Self.defaultSpaceID
		self.storageVersion = storageVersion
		self.collectionID = collectionID
		self.hasStoredState = hasStoredState
		self.activeSpaceID = resolvedActiveSpaceID
		self.spaces = normalizedSpaces
		self.tabs = tabs
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let decodedStorageVersion = try container.decodeIfPresent(Int.self, forKey: .storageVersion)
			?? Self.currentVersion
		let decodedCollectionID = try container.decodeIfPresent(String.self, forKey: .collectionID)
			?? Self.defaultCollectionID
		let decodedHasStoredState = try container.decodeIfPresent(Bool.self, forKey: .hasStoredState)
			?? false
		let decodedTabs = try container.decodeIfPresent([StoredBrowserTab].self, forKey: .tabs) ?? []
		let decodedSpaces = try container.decodeIfPresent([StoredBrowserSpace].self, forKey: .spaces) ?? []
		let normalizedSpaces = Self.normalizedSpaces(
			spaces: decodedSpaces,
			tabs: decodedTabs
		)
		let decodedActiveSpaceID = try container.decodeIfPresent(String.self, forKey: .activeSpaceID)
			?? normalizedSpaces.first?.id
			?? Self.defaultSpaceID
		let resolvedActiveSpaceID = normalizedSpaces.contains(where: { $0.id == decodedActiveSpaceID })
			? decodedActiveSpaceID
			: normalizedSpaces.first?.id ?? Self.defaultSpaceID

		storageVersion = decodedStorageVersion
		collectionID = decodedCollectionID
		hasStoredState = decodedHasStoredState
		activeSpaceID = resolvedActiveSpaceID
		spaces = normalizedSpaces
		tabs = decodedTabs
	}

	public static let empty = Self(
		storageVersion: Self.currentVersion,
		collectionID: Self.defaultCollectionID,
		hasStoredState: false,
		activeSpaceID: Self.defaultSpaceID,
		spaces: [
			StoredBrowserSpace(
				id: Self.defaultSpaceID,
				orderKey: "00000000"
			),
		],
		tabs: []
	)

	private static func normalizedSpaces(
		spaces: [StoredBrowserSpace],
		tabs: [StoredBrowserTab]
	) -> [StoredBrowserSpace] {
		var normalizedSpaces = spaces
		let knownSpaceIDs = Set(normalizedSpaces.map(\.id))
		let missingSpaceIDs = Set(tabs.map(\.spaceID)).subtracting(knownSpaceIDs)
		let nextOrderStart = normalizedSpaces.count
		for (offset, spaceID) in missingSpaceIDs.sorted().enumerated() {
			normalizedSpaces.append(
				StoredBrowserSpace(
					id: spaceID,
					orderKey: Self.storedOrderKey(for: nextOrderStart + offset)
				)
			)
		}
		if normalizedSpaces.isEmpty {
			normalizedSpaces = [
				StoredBrowserSpace(
					id: Self.defaultSpaceID,
					orderKey: "00000000"
				),
			]
		}
		return normalizedSpaces.sorted(by: { $0.orderKey < $1.orderKey })
	}

	private static func storedOrderKey(for index: Int) -> String {
		String(format: "%08d", index)
	}
}

public struct StoredBrowserTabSelection: Codable, Equatable, Sendable {
	public static let currentVersion = 2

	public let storageVersion: Int
	public let collectionID: String
	public let selectedSpaceID: String
	public let selectedTabID: UUID?

	private enum CodingKeys: String, CodingKey {
		case storageVersion
		case collectionID
		case selectedSpaceID
		case selectedTabID
	}

	public init(
		storageVersion: Int = Self.currentVersion,
		collectionID: String = StoredBrowserTabCollection.defaultCollectionID,
		selectedSpaceID: String = StoredBrowserTabCollection.defaultSpaceID,
		selectedTabID: UUID?
	) {
		self.storageVersion = storageVersion
		self.collectionID = collectionID
		self.selectedSpaceID = selectedSpaceID
		self.selectedTabID = selectedTabID
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		storageVersion = try container.decodeIfPresent(Int.self, forKey: .storageVersion) ?? Self.currentVersion
		collectionID = try container.decodeIfPresent(String.self, forKey: .collectionID)
			?? StoredBrowserTabCollection.defaultCollectionID
		selectedSpaceID = try container.decodeIfPresent(String.self, forKey: .selectedSpaceID)
			?? StoredBrowserTabCollection.defaultSpaceID
		selectedTabID = try container.decodeIfPresent(UUID.self, forKey: .selectedTabID)
	}

	public static let empty = Self(
		storageVersion: Self.currentVersion,
		collectionID: StoredBrowserTabCollection.defaultCollectionID,
		selectedSpaceID: StoredBrowserTabCollection.defaultSpaceID,
		selectedTabID: nil
	)
}
