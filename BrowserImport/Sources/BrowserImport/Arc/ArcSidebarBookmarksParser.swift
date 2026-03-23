import Foundation
import ModelKit
import OSLog

private let arcSidebarImportLogger = Logger(
	subsystem: "com.navigator.BrowserImport",
	category: "ArcSidebarImport"
)

private enum ArcSidebarConstants {
	static let sidebarFileName = "StorableSidebar.json"
	static let defaultPersonalSpaceID = "thebrowser.company.defaultPersonalSpaceID"
	static let pinnedContainerTag = "pinned"
	static let unpinnedContainerTag = "unpinned"
	static let spaceContainerType = 2
	static let folderContainerType = 1
	static let tabContainerType = 0
}

private enum ArcCurrentRootSelection {
	case window
	case bookmarks
}

private struct ArcSidebarContent {
	var folders: [ImportedBookmarkFolder] = []
	var bookmarks: [ImportedBookmark] = []

	var isEmpty: Bool {
		folders.isEmpty && bookmarks.isEmpty
	}

	mutating func append(_ other: Self) {
		folders.append(contentsOf: other.folders)
		bookmarks.append(contentsOf: other.bookmarks)
	}
}

private struct ArcPairedEntry {
	let id: String
	let value: JSONObject
}

private struct ArcSpaceContent {
	let id: String
	let displayName: String?
	let content: ArcSidebarContent
}

private struct ArcCurrentFormatSupplementalState {
	let orderedSpaceIDs: [String]
	let fallbackSpaceIDs: [String]
	let spaceModelsByID: [String: JSONObject]
	let itemsByID: [String: JSONObject]
	let topAppsContainerID: String?

	func makeStreamingState() -> ArcCurrentSidebarStreamingState {
		ArcCurrentSidebarStreamingState(
			didFinishSpaceModels: spaceModelsByID.isEmpty == false,
			didLogWaitingForTopApps: false,
			didLoadOrdering: orderedSpaceIDs.isEmpty == false || topAppsContainerID != nil,
			lastTopAppsResolutionLogSignature: nil,
			nextOrderedSpaceIndex: 0,
			orderedSpaceIDs: orderedSpaceIDs,
			fallbackSpaceIDs: fallbackSpaceIDs,
			supplementalItemIDs: Set(itemsByID.keys),
			spaceModelsByID: spaceModelsByID,
			itemsByID: itemsByID,
			topAppsContainerID: topAppsContainerID
		)
	}
}

enum ArcSidebarPinnedState: Equatable {
	case pinned
	case unpinned
	case notApplicable
}

enum ArcTopAppsContainerResolution: Equatable {
	case resolved(String)
	case missing
	case ambiguous

	var topAppsContainerID: String? {
		guard case .resolved(let identifier) = self else {
			return nil
		}
		return identifier
	}
}

struct ArcSidebarPinnedStateClassifier {
	let topAppsResolution: ArcTopAppsContainerResolution

	var topAppsContainerID: String? {
		topAppsResolution.topAppsContainerID
	}

	init(
		sidebarSyncState: JSONObject,
		itemsByID: [String: JSONObject]
	) {
		self.init(
			topAppsResolution: Self.resolveTopAppsContainerResolution(
				sidebarSyncState: sidebarSyncState,
				itemsByID: itemsByID
			)
		)
	}

	init(
		explicitTopAppsContainerID: String?,
		itemsByID: [String: JSONObject]
	) {
		self.init(
			topAppsResolution: Self.resolveTopAppsContainerResolution(
				explicitTopAppsContainerID: explicitTopAppsContainerID,
				itemsByID: itemsByID
			)
		)
	}

	init(topAppsResolution: ArcTopAppsContainerResolution) {
		self.topAppsResolution = topAppsResolution
	}

	static func resolveTopAppsContainerResolution(
		sidebarSyncState: JSONObject,
		itemsByID: [String: JSONObject]
	) -> ArcTopAppsContainerResolution {
		let containerValue = sidebarSyncState
			.dictionaryValue(for: "container")?
			.dictionaryValue(for: "value")
		return resolveTopAppsContainerResolution(
			explicitTopAppsContainerID: resolvedExplicitTopAppsContainerID(from: containerValue),
			itemsByID: itemsByID
		)
	}

	static func resolveTopAppsContainerResolution(
		explicitTopAppsContainerID: String?,
		itemsByID: [String: JSONObject]
	) -> ArcTopAppsContainerResolution {
		if let explicitTopAppsContainerID = normalizedIdentifier(explicitTopAppsContainerID) {
			return .resolved(explicitTopAppsContainerID)
		}

		let structuralMatches = Set(
			itemsByID.values.compactMap { item -> String? in
				guard
					item
					.dictionaryValue(for: "data")?
					.dictionaryValue(for: "itemContainer")?
					.dictionaryValue(for: "containerType")?
					.dictionaryValue(for: "topApps") != nil
				else {
					return nil
				}
				return normalizedIdentifier(item.stringValue(for: "id"))
			}
		)
		guard structuralMatches.isEmpty == false else {
			return .missing
		}
		guard structuralMatches.count == 1, let topAppsContainerID = structuralMatches.first else {
			return .ambiguous
		}
		return .resolved(topAppsContainerID)
	}

	func pinnedState(for item: JSONObject) -> ArcSidebarPinnedState {
		guard
			item.dictionaryValue(for: "data")?
			.dictionaryValue(for: "tab") != nil
		else {
			return .notApplicable
		}
		guard let topAppsContainerID else {
			return .unpinned
		}
		return item.stringValue(for: "parentID") == topAppsContainerID ? .pinned : .unpinned
	}

	private static func normalizedIdentifier(_ value: String?) -> String? {
		guard let value else {
			return nil
		}
		let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
		return normalized.isEmpty ? nil : normalized
	}

	static func resolvedExplicitTopAppsContainerID(from containerValue: JSONObject?) -> String? {
		guard let containerValue else {
			return nil
		}
		if let topAppsContainerID = normalizedIdentifier(containerValue.stringValue(for: "topAppsContainerID")) {
			return topAppsContainerID
		}
		return resolvedTopAppsContainerID(from: containerValue.anyArrayValue(for: "topAppsContainerIDs"))
	}

	private static func resolvedTopAppsContainerID(from values: [Any]) -> String? {
		guard values.isEmpty == false else {
			return nil
		}

		if let defaultTaggedID = taggedIdentifier(named: "default", in: values) {
			return defaultTaggedID
		}

		let identifiers = values.compactMap { normalizedIdentifier(identifierString(from: $0)) }
		let uniqueIdentifiers = Array(Set(identifiers))
		guard uniqueIdentifiers.count == 1 else {
			return identifiers.first
		}
		return uniqueIdentifiers[0]
	}

	private static func taggedIdentifier(named tag: String, in values: [Any]) -> String? {
		guard values.count >= 2 else {
			return nil
		}

		for index in stride(from: 0, through: values.count - 2, by: 2) {
			guard containsTag(tag, in: values[index]) else {
				continue
			}
			if let identifier = normalizedIdentifier(identifierString(from: values[index + 1])) {
				return identifier
			}
		}

		return nil
	}

	private static func containsTag(_ tag: String, in value: Any) -> Bool {
		if let object = value as? JSONObject {
			if object[tag] != nil {
				return true
			}
			return object.values.contains { containsTag(tag, in: $0) }
		}
		if let array = value as? [Any] {
			return array.contains { containsTag(tag, in: $0) }
		}
		return false
	}

	private static func identifierString(from value: Any) -> String? {
		if let string = value as? String {
			return string
		}
		if let object = value as? JSONObject {
			for objectValue in object.values {
				if let identifier = identifierString(from: objectValue) {
					return identifier
				}
			}
		}
		if let array = value as? [Any] {
			for arrayValue in array {
				if let identifier = identifierString(from: arrayValue) {
					return identifier
				}
			}
		}
		return nil
	}
}

struct ArcSidebarProfileChunk {
	let window: ImportedBrowserWindow?
	let bookmarkFolder: ImportedBookmarkFolder?
}

struct ArcSidebarBookmarksParser {
	func loadFolders(
		source: BrowserImportSource,
		profileURL: URL
	) throws -> [ImportedBookmarkFolder] {
		if let currentFormatChunks = try loadCurrentFormatProfileChunks(
			source: source,
			profileURL: profileURL
		) {
			return focusedCurrentFormatFolders(from: currentFormatChunks)
		}

		guard let sidebarSyncState = try loadSidebarSyncState(
			source: source,
			profileURL: profileURL
		) else {
			return []
		}

		if isCurrentFormatSidebarState(sidebarSyncState) {
			return currentFormatFolders(from: sidebarSyncState)
		}

		return legacyFormatFolders(from: sidebarSyncState)
	}

	func loadWindows(
		source: BrowserImportSource,
		profileURL: URL
	) throws -> [ImportedBrowserWindow] {
		if let currentFormatChunks = try loadCurrentFormatProfileChunks(
			source: source,
			profileURL: profileURL
		) {
			return currentFormatChunks.compactMap(\.window)
		}

		guard let sidebarSyncState = try loadSidebarSyncState(
			source: source,
			profileURL: profileURL
		) else {
			return []
		}

		if isCurrentFormatSidebarState(sidebarSyncState) {
			return currentFormatWindows(from: sidebarSyncState)
		}

		return legacyFormatWindows(from: sidebarSyncState)
	}

	func loadProfileChunks(
		source: BrowserImportSource,
		profileURL: URL
	) throws -> [ArcSidebarProfileChunk] {
		if let currentFormatChunks = try loadCurrentFormatProfileChunks(
			source: source,
			profileURL: profileURL
		) {
			return currentFormatChunks
		}

		guard let sidebarSyncState = try loadSidebarSyncState(
			source: source,
			profileURL: profileURL
		) else {
			return []
		}

		if isCurrentFormatSidebarState(sidebarSyncState) {
			return currentFormatProfileChunks(from: sidebarSyncState)
		}

		return legacyFormatProfileChunks(from: sidebarSyncState)
	}

	func loadProfileChunkStream(
		source: BrowserImportSource,
		profileURL: URL
	) -> AsyncThrowingStream<ArcSidebarProfileChunk, Error> {
		let sidebarURL = sidebarFileURL(for: profileURL)
		guard FileManager.default.fileExists(atPath: sidebarURL.path) else {
			return AsyncThrowingStream { continuation in
				continuation.finish()
			}
		}

		let parser = self
		return AsyncThrowingStream { continuation in
			let task = Task { @Sendable in
				do {
					var didYieldCurrentFormatChunk = false
					let didParseCurrentFormat = try parser.streamCurrentFormatProfileChunks(
						source: source,
						sidebarURL: sidebarURL,
						onChunk: { chunk in
							didYieldCurrentFormatChunk = true
							continuation.yield(chunk)
						}
					)
					if didParseCurrentFormat == false || didYieldCurrentFormatChunk == false {
						for chunk in try parser.loadProfileChunks(
							source: source,
							profileURL: profileURL
						) {
							continuation.yield(chunk)
						}
					}
					continuation.finish()
				}
				catch {
					continuation.finish(throwing: error)
				}
			}
			continuation.onTermination = { _ in
				task.cancel()
			}
		}
	}

	private func loadCurrentFormatProfileChunks(
		source: BrowserImportSource,
		profileURL: URL
	) throws -> [ArcSidebarProfileChunk]? {
		let sidebarURL = sidebarFileURL(for: profileURL)
		guard FileManager.default.fileExists(atPath: sidebarURL.path) else {
			return []
		}

		var collectedChunks = [ArcSidebarProfileChunk]()
		let didParseCurrentFormat = try streamCurrentFormatProfileChunks(
			source: source,
			sidebarURL: sidebarURL
		) { chunk in
			collectedChunks.append(chunk)
		}
		guard didParseCurrentFormat else {
			return nil
		}
		if
			collectedChunks.isEmpty,
			let sidebarSyncState = try loadSidebarSyncState(
				source: source,
				profileURL: profileURL
			),
			isCurrentFormatSidebarState(sidebarSyncState) {
			return currentFormatProfileChunks(from: sidebarSyncState)
		}
		return collectedChunks
	}

	private func focusedCurrentFormatFolders(
		from chunks: [ArcSidebarProfileChunk]
	) -> [ImportedBookmarkFolder] {
		let folders = chunks.compactMap(\.bookmarkFolder)
		guard folders.count == 1 else {
			return folders
		}

		let firstFolder = folders[0]
		guard firstFolder.displayName == "Space", firstFolder.bookmarks.isEmpty else {
			return folders
		}
		return firstFolder.childFolders
	}

	private func loadSidebarSyncState(
		source: BrowserImportSource,
		profileURL: URL
	) throws -> JSONObject? {
		let sidebarURL = sidebarFileURL(for: profileURL)
		guard FileManager.default.fileExists(atPath: sidebarURL.path) else {
			return nil
		}

		let rootObject = try loadSidebarRootObject(
			source: source,
			sidebarURL: sidebarURL
		)
		return try resolvedSidebarSyncState(
			from: rootObject,
			source: source
		)
	}

	private func resolvedSidebarSyncState(
		from rootObject: Any,
		source: BrowserImportSource
	) throws -> JSONObject {
		if let root = rootObject as? JSONObject {
			let currentFormatStates = currentFormatSidebarStates(from: root)
			if let mergedCurrentFormatState = mergedCurrentFormatSidebarState(
				from: currentFormatStates
			) {
				return mergedCurrentFormatState
			}
		}

		if
			let root = rootObject as? JSONObject,
			let firebaseSyncState = root.dictionaryValue(for: "firebaseSyncState"),
			let syncData = firebaseSyncState.dictionaryValue(for: "syncData") {
			return syncData
		}

		if
			let root = rootObject as? JSONObject,
			let sidebarSyncState = root.dictionaryValue(for: "sidebarSyncState") {
			return sidebarSyncState
		}

		if
			let root = rootObject as? JSONObject,
			let sidebar = root.dictionaryValue(for: "sidebar") {
			let entries = sidebar.anyArrayValue(for: "containers")
			if let currentContainer = currentSidebarContainer(from: entries) {
				return currentContainer
			}
			if
				let globalEntry = entries.compactMap({ $0 as? JSONObject }).first(where: { $0["global"] != nil }),
				let globalState = globalEntry.dictionaryValue(for: "global"),
				let sidebarSyncState = globalState.dictionaryValue(for: "sidebarSyncState") {
				return sidebarSyncState
			}
		}

		if
			let entries = rootObject as? [JSONObject],
			let globalEntry = entries.first(where: { $0["global"] != nil }),
			let globalState = globalEntry.dictionaryValue(for: "global"),
			let sidebarSyncState = globalState.dictionaryValue(for: "sidebarSyncState") {
			return sidebarSyncState
		}

		throw BrowserImportError.parseFailed(
			source,
			reason: "Arc sidebar document is missing global sidebar state"
		)
	}

	private func loadSidebarRootObject(
		source: BrowserImportSource,
		sidebarURL: URL
	) throws -> Any {
		guard let stream = InputStream(url: sidebarURL) else {
			throw BrowserImportError.readFailed(sidebarURL)
		}

		let rootObject: Any
		stream.open()
		defer {
			stream.close()
		}
		do {
			rootObject = try JSONSerialization.jsonObject(with: stream)
		}
		catch {
			if stream.streamStatus == .error || stream.streamError != nil {
				throw BrowserImportError.readFailed(sidebarURL)
			}
			throw BrowserImportError.parseFailed(
				source,
				reason: "Invalid Arc sidebar document at \(sidebarURL.lastPathComponent)"
			)
		}
		return rootObject
	}

	private func legacyFormatFolders(from sidebarSyncState: JSONObject) -> [ImportedBookmarkFolder] {
		let containers = sidebarSyncState.arrayValue(for: "containers")
		let items = sidebarSyncState.arrayValue(for: "items")
		let itemsByID = Dictionary(
			uniqueKeysWithValues: items.compactMap { item in
				item.stringValue(for: "id").map { ($0, item) }
			}
		)
		let spaceTitlesByID = items.reduce(into: [String: String]()) { result, item in
			guard item.intValue(for: "containerType") == ArcSidebarConstants.spaceContainerType else {
				return
			}
			guard let itemID = item.stringValue(for: "id") else {
				return
			}
			result[itemID] = resolvedTitle(
				from: item,
				fallback: "Space"
			)
		}

		return containers.compactMap { container in
			guard container.intValue(for: "containerType") == ArcSidebarConstants.folderContainerType else {
				return nil
			}
			guard
				let spaceID = container.stringValue(for: "containerID"),
				let itemIDs = container.stringArrayValue(for: "spaceItems")
			else {
				return nil
			}

			return makeLegacyFolder(
				id: "space-\(spaceID)",
				displayName: spaceTitlesByID[spaceID] ?? "Space",
				itemIDs: itemIDs,
				itemsByID: itemsByID
			)
		}
	}

	private func currentFormatFolders(from sidebarSyncState: JSONObject) -> [ImportedBookmarkFolder] {
		let spaces = currentSpaces(from: sidebarSyncState)
		return rootFolders(from: spaces)
	}

	private func legacyFormatWindows(from sidebarSyncState: JSONObject) -> [ImportedBrowserWindow] {
		let containers = sidebarSyncState.arrayValue(for: "containers")
		let items = sidebarSyncState.arrayValue(for: "items")
		let itemsByID = Dictionary(
			uniqueKeysWithValues: items.compactMap { item in
				item.stringValue(for: "id").map { ($0, item) }
			}
		)
		let spaceTitlesByID = items.reduce(into: [String: String]()) { result, item in
			guard item.intValue(for: "containerType") == ArcSidebarConstants.spaceContainerType else {
				return
			}
			guard let itemID = item.stringValue(for: "id") else {
				return
			}
			result[itemID] = resolvedTitle(from: item, fallback: "Space")
		}

		return containers.compactMap { container in
			guard container.intValue(for: "containerType") == ArcSidebarConstants.folderContainerType else {
				return nil
			}
			guard
				let spaceID = container.stringValue(for: "containerID"),
				let itemIDs = container.stringArrayValue(for: "spaceItems")
			else {
				return nil
			}

			let tabs = legacyTabs(
				for: itemIDs,
				itemsByID: itemsByID
			)
			guard tabs.isEmpty == false else {
				return nil
			}

			let displayName = spaceTitlesByID[spaceID] ?? "Space"
			return window(
				id: "space-\(spaceID)",
				displayName: displayName,
				tabs: tabs
			)
		}
	}

	private func currentFormatWindows(from sidebarSyncState: JSONObject) -> [ImportedBrowserWindow] {
		currentFormatProfileChunks(from: sidebarSyncState).compactMap(\.window)
	}

	private func legacyFormatProfileChunks(from sidebarSyncState: JSONObject) -> [ArcSidebarProfileChunk] {
		let containers = sidebarSyncState.arrayValue(for: "containers")
		let items = sidebarSyncState.arrayValue(for: "items")
		let itemsByID = Dictionary(
			uniqueKeysWithValues: items.compactMap { item in
				item.stringValue(for: "id").map { ($0, item) }
			}
		)
		let spaceTitlesByID = items.reduce(into: [String: String]()) { result, item in
			guard item.intValue(for: "containerType") == ArcSidebarConstants.spaceContainerType else {
				return
			}
			guard let itemID = item.stringValue(for: "id") else {
				return
			}
			result[itemID] = resolvedTitle(from: item, fallback: "Space")
		}

		return containers.compactMap { container in
			guard container.intValue(for: "containerType") == ArcSidebarConstants.folderContainerType else {
				return nil
			}
			guard
				let spaceID = container.stringValue(for: "containerID"),
				let itemIDs = container.stringArrayValue(for: "spaceItems")
			else {
				return nil
			}

			let displayName = spaceTitlesByID[spaceID] ?? "Space"
			let tabs = legacyTabs(
				for: itemIDs,
				itemsByID: itemsByID
			)
			let bookmarkFolder = makeLegacyFolder(
				id: "space-\(spaceID)",
				displayName: displayName,
				itemIDs: itemIDs,
				itemsByID: itemsByID
			)
			let window = tabs.isEmpty
				? nil
				: window(
					id: "space-\(spaceID)",
					displayName: displayName,
					tabs: tabs
				)
			guard window != nil || bookmarkFolder != nil else {
				return nil
			}
			return ArcSidebarProfileChunk(
				window: window,
				bookmarkFolder: bookmarkFolder
			)
		}
	}

	private func currentFormatProfileChunks(from sidebarSyncState: JSONObject) -> [ArcSidebarProfileChunk] {
		let itemEntries = pairedEntries(from: sidebarSyncState.anyArrayValue(for: "items"))
		let itemsByID = Dictionary(
			uniqueKeysWithValues: itemEntries.map { ($0.id, $0.value) }
		)
		let pinnedStateClassifier = ArcSidebarPinnedStateClassifier(
			sidebarSyncState: sidebarSyncState,
			itemsByID: itemsByID
		)
		logTopAppsResolution(
			pinnedStateClassifier,
			itemsByID: itemsByID,
			context: "full-parse"
		)
		let spaceEntries = currentSpaceEntries(from: sidebarSyncState)
		let spacesByID = Dictionary(
			uniqueKeysWithValues: spaceEntries.map { ($0.id, $0.value) }
		)
		let orderedSpaceIDs = orderedSpaceIDs(
			from: sidebarSyncState,
			fallback: spaceEntries.map(\.id)
		)
		let topAppsRecipientSpaceID = topAppsRecipientSpaceID(
			spacesByID: spacesByID,
			orderedSpaceIDs: orderedSpaceIDs
		)

		return orderedSpaceIDs.enumerated().compactMap { index, spaceID in
			guard let spaceModel = spacesByID[spaceID] else {
				return nil
			}
			return currentFormatProfileChunk(
				spaceID: spaceID,
				spaceModel: spaceModel,
				itemsByID: itemsByID,
				pinnedStateClassifier: pinnedStateClassifier,
				orderedSpaceIDs: orderedSpaceIDs,
				index: index,
				topAppsRecipientSpaceID: topAppsRecipientSpaceID
			)
		}
	}

	private func currentSpaces(from sidebarSyncState: JSONObject) -> [ArcSpaceContent] {
		let itemEntries = pairedEntries(from: sidebarSyncState.anyArrayValue(for: "items"))
		let itemsByID = Dictionary(
			uniqueKeysWithValues: itemEntries.map { ($0.id, $0.value) }
		)
		let pinnedStateClassifier = ArcSidebarPinnedStateClassifier(
			sidebarSyncState: sidebarSyncState,
			itemsByID: itemsByID
		)
		let spaceEntries = currentSpaceEntries(from: sidebarSyncState)
		let spacesByID = Dictionary(
			uniqueKeysWithValues: spaceEntries.map { ($0.id, $0.value) }
		)
		let orderedSpaceIDs = orderedSpaceIDs(
			from: sidebarSyncState,
			fallback: spaceEntries.map(\.id)
		)
		let topAppsRecipientSpaceID = topAppsRecipientSpaceID(
			spacesByID: spacesByID,
			orderedSpaceIDs: orderedSpaceIDs
		)

		return orderedSpaceIDs.compactMap { spaceID in
			guard let spaceModel = spacesByID[spaceID] else {
				return nil
			}
			return currentSpaceContent(
				spaceID: spaceID,
				spaceModel: spaceModel,
				itemsByID: itemsByID,
				pinnedStateClassifier: pinnedStateClassifier,
				topAppsRecipientSpaceID: topAppsRecipientSpaceID
			)
		}
	}

	private func currentSpaceContent(
		spaceID: String,
		spaceModel: JSONObject,
		itemsByID: [String: JSONObject],
		pinnedStateClassifier: ArcSidebarPinnedStateClassifier,
		topAppsRecipientSpaceID: String?
	) -> ArcSpaceContent? {
		let rootItemIDs = currentRootItemIDs(
			for: spaceModel,
			itemsByID: itemsByID,
			pinnedStateClassifier: pinnedStateClassifier,
			includeTopApps: spaceID == topAppsRecipientSpaceID,
			selection: .bookmarks
		)
		let content = currentContent(
			for: rootItemIDs,
			itemsByID: itemsByID
		)
		guard content.isEmpty == false else {
			return nil
		}

		return ArcSpaceContent(
			id: spaceID,
			displayName: currentResolvedTitle(
				from: spaceModel,
				fallback: nil
			) ?? currentResolvedTitle(
				from: itemsByID[spaceID],
				fallback: nil
			),
			content: content
		)
	}

	private func currentContainerItemIDs(
		for spaceModel: JSONObject,
		tag: String,
		itemsByID: [String: JSONObject]
	) -> [String] {
		let containerID: String? = switch tag {
		case ArcSidebarConstants.pinnedContainerTag:
			pinnedContainerID(from: spaceModel)
		case ArcSidebarConstants.unpinnedContainerTag:
			unpinnedContainerID(from: spaceModel)
		default:
			nil
		}
		guard let containerID, let container = itemsByID[containerID] else {
			return []
		}
		return container.stringArrayValue(for: "childrenIds") ?? []
	}

	private func rootFolders(from spaces: [ArcSpaceContent]) -> [ImportedBookmarkFolder] {
		guard spaces.isEmpty == false else {
			return []
		}

		var folders = [ImportedBookmarkFolder]()
		let hasMultipleSpaces = spaces.count > 1

		for (index, space) in spaces.enumerated() {
			if let displayName = space.displayName {
				folders.append(
					wrappedFolder(
						id: "space-\(space.id)",
						displayName: displayName,
						content: space.content
					)
				)
				continue
			}

			if hasMultipleSpaces || space.content.bookmarks.isEmpty == false {
				let fallbackName = hasMultipleSpaces ? "Space \(index + 1)" : "Space"
				folders.append(
					wrappedFolder(
						id: "space-\(space.id)",
						displayName: fallbackName,
						content: space.content
					)
				)
				continue
			}

			folders.append(contentsOf: space.content.folders)
		}

		return folders
	}

	private func currentContent(
		for itemIDs: [String],
		itemsByID: [String: JSONObject]
	) -> ArcSidebarContent {
		var content = ArcSidebarContent()
		for itemID in itemIDs {
			guard let item = itemsByID[itemID] else {
				continue
			}
			content.append(
				currentContent(
					from: item,
					fallbackID: itemID,
					itemsByID: itemsByID
				)
			)
		}
		return content
	}

	private func legacyTabs(
		for itemIDs: [String],
		itemsByID: [String: JSONObject]
	) -> [ImportedTab] {
		itemIDs.flatMap { itemID -> [ImportedTab] in
			guard let item = itemsByID[itemID] else {
				return []
			}
			return legacyTabs(
				from: item,
				fallbackID: itemID,
				itemsByID: itemsByID
			)
		}
	}

	private func legacyTabs(
		from item: JSONObject,
		fallbackID: String,
		itemsByID: [String: JSONObject]
	) -> [ImportedTab] {
		if let tab = makeTab(
			from: item,
			fallbackID: fallbackID,
			requiresPinnedFlag: true,
			pinnedState: .pinned
		) {
			return [tab]
		}

		let childIDs = item.stringArrayValue(for: "childrenIds") ?? []
		guard childIDs.isEmpty == false else {
			return []
		}

		return legacyTabs(for: childIDs, itemsByID: itemsByID)
	}

	private func currentTabs(
		for itemIDs: [String],
		itemsByID: [String: JSONObject],
		pinnedStateClassifier: ArcSidebarPinnedStateClassifier
	) -> [ImportedTab] {
		itemIDs.flatMap { itemID -> [ImportedTab] in
			guard let item = itemsByID[itemID] else {
				return []
			}
			return currentTabs(
				from: item,
				fallbackID: itemID,
				itemsByID: itemsByID,
				pinnedStateClassifier: pinnedStateClassifier
			)
		}
	}

	private func currentTabs(
		from item: JSONObject,
		fallbackID: String,
		itemsByID: [String: JSONObject],
		pinnedStateClassifier: ArcSidebarPinnedStateClassifier
	) -> [ImportedTab] {
		if let tab = makeTab(
			from: item,
			fallbackID: fallbackID,
			requiresPinnedFlag: false,
			pinnedState: pinnedStateClassifier.pinnedState(for: item)
		) {
			return [tab]
		}

		let childIDs = item.stringArrayValue(for: "childrenIds") ?? []
		guard childIDs.isEmpty == false else {
			return []
		}

		return currentTabs(
			for: childIDs,
			itemsByID: itemsByID,
			pinnedStateClassifier: pinnedStateClassifier
		)
	}

	private func currentContent(
		from item: JSONObject,
		fallbackID: String,
		itemsByID: [String: JSONObject]
	) -> ArcSidebarContent {
		if let bookmark = makeBookmark(
			from: item,
			fallbackID: fallbackID,
			requiresPinnedFlag: false
		) {
			return ArcSidebarContent(bookmarks: [bookmark])
		}

		let childIDs = item.stringArrayValue(for: "childrenIds") ?? []
		guard childIDs.isEmpty == false else {
			return ArcSidebarContent()
		}

		let childContent = currentContent(for: childIDs, itemsByID: itemsByID)
		guard childContent.isEmpty == false else {
			return ArcSidebarContent()
		}

		guard let displayName = currentResolvedTitle(from: item, fallback: nil) else {
			return childContent
		}

		return ArcSidebarContent(
			folders: [
				wrappedFolder(
					id: fallbackID,
					displayName: displayName,
					content: childContent
				),
			]
		)
	}

	private func makeLegacyFolder(
		id: String,
		displayName: String,
		itemIDs: [String],
		itemsByID: [String: JSONObject]
	) -> ImportedBookmarkFolder? {
		var childFolders = [ImportedBookmarkFolder]()
		var bookmarks = [ImportedBookmark]()

		for itemID in itemIDs {
			guard let item = itemsByID[itemID] else { continue }
			switch item.intValue(for: "containerType") {
			case ArcSidebarConstants.folderContainerType:
				guard let childIDs = item.stringArrayValue(for: "childrenIds") else {
					continue
				}
				if let childFolder = makeLegacyFolder(
					id: itemID,
					displayName: resolvedTitle(from: item, fallback: "Folder"),
					itemIDs: childIDs,
					itemsByID: itemsByID
				) {
					childFolders.append(childFolder)
				}
			case ArcSidebarConstants.tabContainerType:
				if let bookmark = makeBookmark(
					from: item,
					fallbackID: itemID,
					requiresPinnedFlag: true
				) {
					bookmarks.append(bookmark)
				}
			default:
				continue
			}
		}

		guard childFolders.isEmpty == false || bookmarks.isEmpty == false else {
			return nil
		}

		return ImportedBookmarkFolder(
			id: id,
			displayName: displayName,
			childFolders: childFolders,
			bookmarks: bookmarks
		)
	}

	private func makeBookmark(
		from item: JSONObject,
		fallbackID: String,
		requiresPinnedFlag: Bool
	) -> ImportedBookmark? {
		if requiresPinnedFlag, item.boolValue(for: "isPinned") != true {
			return nil
		}
		guard
			let tabData = item.dictionaryValue(for: "data")?.dictionaryValue(for: "tab"),
			let url = normalizedNonEmptyValue(tabData.stringValue(for: "savedURL"))
		else {
			return nil
		}

		let fallbackTitle = URL(string: url)?.host() ?? url
		let title = normalizedNonEmptyValue(item.stringValue(for: "title"))
			?? normalizedNonEmptyValue(tabData.stringValue(for: "savedTitle"))
			?? fallbackTitle
		return ImportedBookmark(
			id: fallbackID,
			title: title,
			url: url,
			addedAt: nil,
			isFavorite: false
		)
	}

	private func makeTab(
		from item: JSONObject,
		fallbackID: String,
		requiresPinnedFlag: Bool,
		pinnedState: ArcSidebarPinnedState
	) -> ImportedTab? {
		if requiresPinnedFlag, item.boolValue(for: "isPinned") != true {
			return nil
		}
		guard
			let tabData = item.dictionaryValue(for: "data")?.dictionaryValue(for: "tab"),
			let url = normalizedNonEmptyValue(tabData.stringValue(for: "savedURL"))
		else {
			return nil
		}

		let fallbackTitle = URL(string: url)?.host() ?? url
		let title = normalizedNonEmptyValue(item.stringValue(for: "title"))
			?? normalizedNonEmptyValue(tabData.stringValue(for: "savedTitle"))
			?? fallbackTitle
		return ImportedTab(
			id: fallbackID,
			title: title,
			url: url,
			isPinned: pinnedState == .pinned,
			isFavorite: false,
			lastActiveAt: nil
		)
	}

	private func resolvedTitle(from item: JSONObject, fallback: String) -> String {
		currentResolvedTitle(from: item, fallback: fallback) ?? fallback
	}

	private func currentResolvedTitle(
		from item: JSONObject?,
		fallback: String?
	) -> String? {
		guard let item else {
			return fallback
		}

		let savedTitle = item
			.dictionaryValue(for: "data")?
			.dictionaryValue(for: "tab")?
			.stringValue(for: "savedTitle")
		return normalizedNonEmptyValue(item.stringValue(for: "title"))
			?? normalizedNonEmptyValue(savedTitle)
			?? fallback
	}

	private func normalizedNonEmptyValue(_ value: String?) -> String? {
		guard let value else { return nil }
		let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
		return normalized.isEmpty ? nil : normalized
	}

	private func orderedSpaceIDs(
		from sidebarSyncState: JSONObject,
		fallback: [String]
	) -> [String] {
		currentOrderedSpaceIDs(from: sidebarSyncState)
			?? sidebarSyncState
			.dictionaryValue(for: "container")?
			.dictionaryValue(for: "value")?
			.stringArrayValue(for: "orderedSpaceIDs")
			?? fallback
	}

	private func currentOrderedSpaceIDs(from object: JSONObject) -> [String]? {
		if let wrappedValue = object.dictionaryValue(for: "orderedSpaceIDs")?.stringArrayValue(for: "value") {
			return wrappedValue
		}
		if let directValue = object.stringArrayValue(for: "orderedSpaceIDs") {
			return directValue
		}
		return nil
	}

	private func pinnedContainerID(from spaceModel: JSONObject) -> String? {
		taggedID(
			named: ArcSidebarConstants.pinnedContainerTag,
			in: spaceModel.anyArrayValue(for: "containerIDs")
		) ?? taggedID(
			named: ArcSidebarConstants.pinnedContainerTag,
			in: spaceModel.anyArrayValue(for: "newContainerIDs")
		)
	}

	private func unpinnedContainerID(from spaceModel: JSONObject) -> String? {
		taggedID(
			named: ArcSidebarConstants.unpinnedContainerTag,
			in: spaceModel.anyArrayValue(for: "containerIDs")
		) ?? taggedID(
			named: ArcSidebarConstants.unpinnedContainerTag,
			in: spaceModel.anyArrayValue(for: "newContainerIDs")
		)
	}

	private func taggedID(
		named tag: String,
		in values: [Any]
	) -> String? {
		guard values.count >= 2 else {
			return nil
		}

		for index in stride(from: 0, through: values.count - 2, by: 2) {
			guard matchesTag(values[index], tag: tag) else {
				continue
			}
			guard let identifier = normalizedNonEmptyValue(values[index + 1] as? String) else {
				continue
			}
			return identifier
		}

		return nil
	}

	private func matchesTag(
		_ value: Any,
		tag: String
	) -> Bool {
		if let string = value as? String {
			return string == tag
		}

		if let object = value as? JSONObject {
			return object[tag] != nil
		}

		return false
	}

	private func currentRootItemIDs(
		for spaceModel: JSONObject,
		itemsByID: [String: JSONObject],
		pinnedStateClassifier: ArcSidebarPinnedStateClassifier,
		includeTopApps: Bool,
		selection: ArcCurrentRootSelection
	) -> [String] {
		var rootItemIDs = [String]()
		if includeTopApps {
			rootItemIDs.append(
				contentsOf: topAppsRootItemIDs(
					itemsByID: itemsByID,
					pinnedStateClassifier: pinnedStateClassifier
				)
			)
		}

		switch selection {
		case .window:
			rootItemIDs.append(
				contentsOf: currentContainerItemIDs(
					for: spaceModel,
					tag: ArcSidebarConstants.pinnedContainerTag,
					itemsByID: itemsByID
				)
			)
			rootItemIDs.append(
				contentsOf: currentContainerItemIDs(
					for: spaceModel,
					tag: ArcSidebarConstants.unpinnedContainerTag,
					itemsByID: itemsByID
				)
			)

		case .bookmarks:
			// Arc stores saved sidebar content under the pinned-area container even though
			// current pinning semantics only apply to direct Top Apps children.
			rootItemIDs.append(
				contentsOf: currentContainerItemIDs(
					for: spaceModel,
					tag: ArcSidebarConstants.pinnedContainerTag,
					itemsByID: itemsByID
				)
			)
		}

		return uniqueItemIDsPreservingOrder(rootItemIDs)
	}

	private func topAppsRootItemIDs(
		itemsByID: [String: JSONObject],
		pinnedStateClassifier: ArcSidebarPinnedStateClassifier
	) -> [String] {
		guard let topAppsContainerID = pinnedStateClassifier.topAppsContainerID else {
			return []
		}
		let directParentRootIDs = itemsByID.keys.sorted().filter { itemID in
			itemsByID[itemID]?.stringValue(for: "parentID") == topAppsContainerID
		}
		guard let topAppsContainer = itemsByID[topAppsContainerID] else {
			arcSidebarImportLogger.warning(
				"Arc import Top Apps container item missing for id=\(topAppsContainerID, privacy: .public); falling back to direct-parent scan roots=\(directParentRootIDs.joined(separator: ","), privacy: .public)"
			)
			return directParentRootIDs
		}

		let childRootIDs = topAppsContainer.stringArrayValue(for: "childrenIds") ?? []
		let mergedRootIDs = uniqueItemIDsPreservingOrder(childRootIDs + directParentRootIDs)
		if mergedRootIDs != childRootIDs {
			arcSidebarImportLogger.warning(
				"Arc import Top Apps container id=\(topAppsContainerID, privacy: .public) had incomplete child roots childIDs=\(childRootIDs.joined(separator: ","), privacy: .public) directParentRoots=\(directParentRootIDs.joined(separator: ","), privacy: .public)"
			)
		}
		return mergedRootIDs
	}

	private func orderedWindowTabs(from discoveredTabs: [ImportedTab]) -> [ImportedTab] {
		let pinnedTabs = discoveredTabs.filter(\.isPinned)
		let unpinnedTabs = discoveredTabs.filter { $0.isPinned == false }
		return pinnedTabs + unpinnedTabs
	}

	private func topAppsRecipientSpaceID(
		spacesByID: [String: JSONObject],
		orderedSpaceIDs: [String]
	) -> String? {
		if orderedSpaceIDs.contains(ArcSidebarConstants.defaultPersonalSpaceID) {
			return ArcSidebarConstants.defaultPersonalSpaceID
		}
		if let defaultSpaceID = orderedSpaceIDs.first(where: { isDefaultSpaceModel(spacesByID[$0]) }) {
			return defaultSpaceID
		}
		return orderedSpaceIDs.first
	}

	private func isDefaultSpaceModel(_ spaceModel: JSONObject?) -> Bool {
		spaceModel?
			.dictionaryValue(for: "profile")?
			.boolValue(for: "default") == true
	}

	private func uniqueItemIDsPreservingOrder(_ itemIDs: [String]) -> [String] {
		var seenItemIDs = Set<String>()
		return itemIDs.filter { seenItemIDs.insert($0).inserted }
	}

	private func logTopAppsResolution(
		_ pinnedStateClassifier: ArcSidebarPinnedStateClassifier,
		itemsByID: [String: JSONObject],
		context: String
	) {
		switch pinnedStateClassifier.topAppsResolution {
		case .resolved(let topAppsContainerID):
			let childIDs = itemsByID[topAppsContainerID]?.stringArrayValue(for: "childrenIds") ?? []
			arcSidebarImportLogger.notice(
				"Arc import [\(context, privacy: .public)] resolved Top Apps id=\(topAppsContainerID, privacy: .public) containerExists=\(itemsByID[topAppsContainerID] != nil, privacy: .public) childCount=\(childIDs.count, privacy: .public) childIDs=\(childIDs.joined(separator: ","), privacy: .public)"
			)
		case .missing:
			arcSidebarImportLogger.warning(
				"Arc import [\(context, privacy: .public)] missing Top Apps container; all discovered tabs will be unpinned"
			)
		case .ambiguous:
			let candidateIDs = structuralTopAppsContainerIDs(itemsByID: itemsByID)
			arcSidebarImportLogger.warning(
				"Arc import [\(context, privacy: .public)] ambiguous Top Apps containers ids=\(candidateIDs.joined(separator: ","), privacy: .public); all discovered tabs will be unpinned"
			)
		}
	}

	private func topAppsResolutionLogSignature(
		_ pinnedStateClassifier: ArcSidebarPinnedStateClassifier,
		itemsByID: [String: JSONObject]
	) -> String {
		switch pinnedStateClassifier.topAppsResolution {
		case .resolved(let topAppsContainerID):
			let childCount = itemsByID[topAppsContainerID]?.stringArrayValue(for: "childrenIds")?.count ?? 0
			let containerExists = itemsByID[topAppsContainerID] != nil
			return "resolved:\(topAppsContainerID):\(containerExists):\(childCount)"
		case .missing:
			return "missing"
		case .ambiguous:
			return "ambiguous:\(structuralTopAppsContainerIDs(itemsByID: itemsByID).joined(separator: ","))"
		}
	}

	private func logCurrentFormatWindowDiscovery(
		spaceID: String,
		displayName: String,
		topAppsRecipientSpaceID: String?,
		bookmarkItemIDs: [String],
		topAppsRootIDs: [String],
		windowRootItemIDs: [String],
		discoveredTabs: [ImportedTab]
	) {
		let discoveredTabSummary = discoveredTabs.map { tab in
			"\(tab.id):\(tab.isPinned ? "pinned" : "unpinned"):\(tab.title)"
		}.joined(separator: ",")
		arcSidebarImportLogger.notice(
			"Arc import space=\(spaceID, privacy: .public) displayName=\(displayName, privacy: .public) isTopAppsRecipient=\(spaceID == topAppsRecipientSpaceID, privacy: .public) bookmarkRoots=\(bookmarkItemIDs.joined(separator: ","), privacy: .public) topAppsRoots=\(topAppsRootIDs.joined(separator: ","), privacy: .public) windowRoots=\(windowRootItemIDs.joined(separator: ","), privacy: .public) discoveredTabs=\(discoveredTabSummary, privacy: .public)"
		)
	}

	private func structuralTopAppsContainerIDs(itemsByID: [String: JSONObject]) -> [String] {
		itemsByID.keys.sorted().filter { itemID in
			itemsByID[itemID]?
				.dictionaryValue(for: "data")?
				.dictionaryValue(for: "itemContainer")?
				.dictionaryValue(for: "containerType")?
				.dictionaryValue(for: "topApps") != nil
		}
	}

	private func isCurrentFormatSidebarState(_ sidebarSyncState: JSONObject) -> Bool {
		sidebarSyncState.dictionaryValue(for: "container") != nil
			|| sidebarSyncState.anyArrayValue(for: "spaceModels").isEmpty == false
			|| sidebarSyncState.anyArrayValue(for: "spaces").isEmpty == false
	}

	private func currentSidebarContainer(from values: [Any]) -> JSONObject? {
		values
			.compactMap { $0 as? JSONObject }
			.first(where: isCurrentFormatSidebarState)
	}

	private func currentFormatSupplementalState(
		from sidebarSyncState: JSONObject
	) -> ArcCurrentFormatSupplementalState? {
		guard isCurrentFormatSidebarState(sidebarSyncState) else {
			return nil
		}

		let itemEntries = pairedEntries(from: sidebarSyncState.anyArrayValue(for: "items"))
		let allItemsByID = Dictionary(
			uniqueKeysWithValues: itemEntries.map { ($0.id, $0.value) }
		)
		let topAppsContainerID = ArcSidebarPinnedStateClassifier
			.resolvedExplicitTopAppsContainerID(
				from: sidebarSyncState
					.dictionaryValue(for: "container")?
					.dictionaryValue(for: "value")
			)
			?? ArcSidebarPinnedStateClassifier(
				sidebarSyncState: sidebarSyncState,
				itemsByID: allItemsByID
			).topAppsContainerID
		let topAppsItemsByID = topAppsSupplementalItems(
			itemsByID: allItemsByID,
			topAppsContainerID: topAppsContainerID
		)

		return ArcCurrentFormatSupplementalState(
			orderedSpaceIDs: [],
			fallbackSpaceIDs: [],
			spaceModelsByID: [:],
			itemsByID: topAppsItemsByID,
			topAppsContainerID: topAppsContainerID
		)
	}

	private func currentFormatSidebarStates(from root: JSONObject) -> [JSONObject] {
		let firebaseSyncState = root.dictionaryValue(for: "firebaseSyncState")?
			.dictionaryValue(for: "syncData")
		let sidebarSyncState = root.dictionaryValue(for: "sidebarSyncState")
		let liveCurrentContainer = root.dictionaryValue(for: "sidebar")
			.flatMap { currentSidebarContainer(from: $0.anyArrayValue(for: "containers")) }
		return [
			firebaseSyncState,
			sidebarSyncState,
			liveCurrentContainer,
		].compactMap { state in
			guard let state, isCurrentFormatSidebarState(state) else {
				return nil
			}
			return state
		}
	}

	private func supplementalCurrentFormatStates(from root: JSONObject) -> [JSONObject] {
		let sidebarSyncState = root.dictionaryValue(for: "sidebarSyncState")
		let liveCurrentContainer = root.dictionaryValue(for: "sidebar")
			.flatMap { currentSidebarContainer(from: $0.anyArrayValue(for: "containers")) }
		return [
			sidebarSyncState,
			liveCurrentContainer,
		].compactMap { state in
			guard let state, isCurrentFormatSidebarState(state) else {
				return nil
			}
			return state
		}
	}

	private func topAppsSupplementalItems(
		itemsByID: [String: JSONObject],
		topAppsContainerID: String?
	) -> [String: JSONObject] {
		guard let topAppsContainerID else {
			return [:]
		}

		var relevantItemIDs = Set<String>()
		if itemsByID[topAppsContainerID] != nil {
			collectCurrentSubtreeItemIDs(
				startingAt: topAppsContainerID,
				itemsByID: itemsByID,
				relevantItemIDs: &relevantItemIDs
			)
		}
		for itemID in itemsByID.keys.sorted() {
			guard itemsByID[itemID]?.stringValue(for: "parentID") == topAppsContainerID else {
				continue
			}
			collectCurrentSubtreeItemIDs(
				startingAt: itemID,
				itemsByID: itemsByID,
				relevantItemIDs: &relevantItemIDs
			)
		}
		return itemsByID.filter { relevantItemIDs.contains($0.key) }
	}

	private func collectCurrentSubtreeItemIDs(
		startingAt itemID: String,
		itemsByID: [String: JSONObject],
		relevantItemIDs: inout Set<String>
	) {
		guard relevantItemIDs.insert(itemID).inserted else {
			return
		}
		guard let item = itemsByID[itemID] else {
			return
		}
		for childID in item.stringArrayValue(for: "childrenIds") ?? [] {
			collectCurrentSubtreeItemIDs(
				startingAt: childID,
				itemsByID: itemsByID,
				relevantItemIDs: &relevantItemIDs
			)
		}
	}

	private func mergedCurrentFormatSidebarState(
		primary: JSONObject,
		supplemental: JSONObject
	) -> JSONObject {
		var merged = primary
		let primaryItems = pairedEntries(from: primary.anyArrayValue(for: "items"))
		let supplementalItems = pairedEntries(from: supplemental.anyArrayValue(for: "items"))
		let primarySpaceEntries = currentSpaceEntries(from: primary)
		let supplementalSpaceEntries = currentSpaceEntries(from: supplemental)

		let mergedItems = mergedPairedEntries(
			primary: primaryItems,
			supplemental: supplementalItems
		)
		if mergedItems.isEmpty == false {
			merged["items"] = wrappedPairedEntries(mergedItems)
		}

		let mergedSpaceEntries = mergedPairedEntries(
			primary: primarySpaceEntries,
			supplemental: supplementalSpaceEntries
		)
		if mergedSpaceEntries.isEmpty == false {
			merged["spaceModels"] = wrappedPairedEntries(mergedSpaceEntries)
		}

		let mergedContainer = mergedCurrentFormatContainer(
			primary: primary.dictionaryValue(for: "container"),
			supplemental: supplemental.dictionaryValue(for: "container")
		)
		if let mergedContainer {
			merged["container"] = mergedContainer
		}

		return merged
	}

	private func mergedPairedEntries(
		primary: [ArcPairedEntry],
		supplemental: [ArcPairedEntry]
	) -> [ArcPairedEntry] {
		guard primary.isEmpty == false || supplemental.isEmpty == false else {
			return []
		}

		var entriesByID = Dictionary(
			uniqueKeysWithValues: primary.map { ($0.id, $0) }
		)
		for entry in supplemental {
			if let existingEntry = entriesByID[entry.id] {
				entriesByID[entry.id] = ArcPairedEntry(
					id: entry.id,
					value: mergedCurrentItemPreferringIncoming(
						existing: existingEntry.value,
						incoming: entry.value
					)
				)
			}
			else {
				entriesByID[entry.id] = entry
			}
		}

		var mergedEntries = [ArcPairedEntry]()
		var seenIDs = Set<String>()
		for entry in primary where seenIDs.insert(entry.id).inserted {
			if let mergedEntry = entriesByID[entry.id] {
				mergedEntries.append(mergedEntry)
			}
		}
		for entry in supplemental where seenIDs.insert(entry.id).inserted {
			if let mergedEntry = entriesByID[entry.id] {
				mergedEntries.append(mergedEntry)
			}
		}
		return mergedEntries
	}

	private func wrappedPairedEntries(_ entries: [ArcPairedEntry]) -> [Any] {
		entries.flatMap { entry -> [Any] in
			[
				entry.id,
				["value": entry.value],
			]
		}
	}

	private func mergedCurrentFormatContainer(
		primary: JSONObject?,
		supplemental: JSONObject?
	) -> JSONObject? {
		guard primary != nil || supplemental != nil else {
			return nil
		}

		var mergedContainer = primary ?? supplemental ?? [:]
		let primaryValue = primary?.dictionaryValue(for: "value") ?? [:]
		let supplementalValue = supplemental?.dictionaryValue(for: "value") ?? [:]
		var mergedValue = primaryValue
		for (key, value) in supplementalValue where mergedValue[key] == nil {
			mergedValue[key] = value
		}
		if mergedValue.isEmpty == false {
			mergedContainer["value"] = mergedValue
		}
		return mergedContainer
	}

	private func mergedCurrentFormatSidebarState(
		from states: [JSONObject]
	) -> JSONObject? {
		guard let firstState = states.first else {
			return nil
		}
		return states.dropFirst().reduce(firstState) { partialState, nextState in
			mergedCurrentFormatSidebarState(
				primary: partialState,
				supplemental: nextState
			)
		}
	}

	private func currentSpaceEntries(from sidebarSyncState: JSONObject) -> [ArcPairedEntry] {
		let wrappedSpaceEntries = pairedEntries(from: sidebarSyncState.anyArrayValue(for: "spaceModels"))
		if wrappedSpaceEntries.isEmpty == false {
			return wrappedSpaceEntries
		}
		return pairedEntries(from: sidebarSyncState.anyArrayValue(for: "spaces"))
	}

	private func pairedEntries(from values: [Any]) -> [ArcPairedEntry] {
		guard values.count >= 2 else {
			return []
		}

		var entries = [ArcPairedEntry]()
		for index in stride(from: 0, through: values.count - 2, by: 2) {
			guard let identifier = normalizedNonEmptyValue(values[index] as? String) else {
				continue
			}
			guard let wrapper = values[index + 1] as? JSONObject else {
				continue
			}
			let value = wrapper.dictionaryValue(for: "value")
				?? wrapper.dictionaryValue(for: "item")
				?? wrapper
			entries.append(
				ArcPairedEntry(
					id: identifier,
					value: value
				)
			)
		}
		return entries
	}

	private func wrappedFolder(
		id: String,
		displayName: String,
		content: ArcSidebarContent
	) -> ImportedBookmarkFolder {
		ImportedBookmarkFolder(
			id: id,
			displayName: displayName,
			childFolders: content.folders,
			bookmarks: content.bookmarks
		)
	}

	private func window(
		id: String,
		displayName: String,
		tabs: [ImportedTab]
	) -> ImportedBrowserWindow {
		ImportedBrowserWindow(
			id: id,
			displayName: displayName,
			tabGroups: [
				ImportedTabGroup(
					id: "\(id)-group",
					displayName: displayName,
					kind: .space,
					colorHex: nil,
					tabs: tabs
				),
			],
			selectedTabID: nil
		)
	}

	private func sidebarFileURL(for profileURL: URL) -> URL {
		profileURL
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appendingPathComponent(ArcSidebarConstants.sidebarFileName, isDirectory: false)
	}
}

private extension ArcSidebarBookmarksParser {
	func streamCurrentFormatProfileChunks(
		source: BrowserImportSource,
		sidebarURL: URL,
		onChunk: (ArcSidebarProfileChunk) -> Void
	) throws -> Bool {
		let supplementalCurrentFormatState = try? loadCurrentFormatSupplementalState(
			source: source,
			sidebarURL: sidebarURL
		)
		if try streamFocusedCurrentFormatProfileChunks(
			source: source,
			sidebarURL: sidebarURL,
			keyPath: ArcSidebarStreamingConstants.firebaseSyncDataKeyPath,
			supplementalState: supplementalCurrentFormatState,
			onChunk: onChunk
		) {
			return true
		}

		if try streamFocusedCurrentFormatProfileChunks(
			source: source,
			sidebarURL: sidebarURL,
			keyPath: ArcSidebarStreamingConstants.sidebarSyncStateKeyPath,
			supplementalState: nil,
			onChunk: onChunk
		) {
			return true
		}

		return try streamLiveSidebarProfileChunks(
			source: source,
			sidebarURL: sidebarURL,
			onChunk: onChunk
		)
	}

	func streamFocusedCurrentFormatProfileChunks(
		source: BrowserImportSource,
		sidebarURL: URL,
		keyPath: [String],
		supplementalState: ArcCurrentFormatSupplementalState?,
		onChunk: (ArcSidebarProfileChunk) -> Void
	) throws -> Bool {
		guard let inputStream = InputStream(url: sidebarURL) else {
			throw BrowserImportError.readFailed(sidebarURL)
		}

		inputStream.open()
		defer {
			inputStream.close()
		}

		let reader = ArcJSONByteStreamReader(
			stream: inputStream,
			source: source,
			fileURL: sidebarURL
		)
		guard try reader.peekNonWhitespaceByte() == .openBrace else {
			return false
		}

		for key in keyPath {
			guard try reader.scanForJSONStringToken(key) else {
				return false
			}
			try reader.expect(.colon)
		}
		return try streamSidebarSyncState(
			from: reader,
			source: source,
			supplementalState: supplementalState,
			onChunk: onChunk
		)
	}

	func streamSidebarSyncState(
		from reader: ArcJSONByteStreamReader,
		source: BrowserImportSource,
		supplementalState: ArcCurrentFormatSupplementalState?,
		onChunk: (ArcSidebarProfileChunk) -> Void
	) throws -> Bool {
		try reader.expect(.openBrace)
		var state = supplementalState?.makeStreamingState() ?? ArcCurrentSidebarStreamingState()
		var sawCurrentFormatKey = false

		while true {
			try checkCancellation()
			guard let nextByte = try reader.peekNonWhitespaceByte() else {
				throw reader.parseError("Unexpected end of Arc sidebarSyncState")
			}
			if nextByte == .closeBrace {
				_ = try reader.readNonWhitespaceByte()
				break
			}

			let key = try reader.readString()
			try reader.expect(.colon)
			switch key {
			case ArcSidebarStreamingConstants.spaceModelsKey:
				sawCurrentFormatKey = true
				try parseCurrentSpaceModels(
					from: reader,
					source: source,
					state: &state
				)
			case ArcSidebarStreamingConstants.containerKey:
				sawCurrentFormatKey = true
				try parseCurrentContainer(
					from: reader,
					source: source,
					state: &state
				)
			case ArcSidebarStreamingConstants.orderedSpaceIDsKey:
				sawCurrentFormatKey = true
				try parseCurrentOrderedSpaceIDs(
					from: reader,
					source: source,
					state: &state
				)
			case ArcSidebarStreamingConstants.itemsKey:
				sawCurrentFormatKey = true
				try parseCurrentItems(
					from: reader,
					source: source,
					state: &state,
					onChunk: onChunk
				)
			default:
				try reader.skipValue()
			}

			guard try reader.consumeCommaOrEnd(closing: .closeBrace) else {
				break
			}
		}

		guard sawCurrentFormatKey else {
			return false
		}

		try drainReadyCurrentSpaces(
			state: &state,
			onChunk: onChunk,
			isFinalPass: true
		)
		return true
	}

	func loadCurrentFormatSupplementalState(
		source: BrowserImportSource,
		sidebarURL: URL
	) throws -> ArcCurrentFormatSupplementalState? {
		guard
			let rootObject = try loadSidebarRootObject(
				source: source,
				sidebarURL: sidebarURL
			) as? JSONObject,
			let mergedSupplementalState = mergedCurrentFormatSidebarState(
				from: supplementalCurrentFormatStates(from: rootObject)
			)
		else {
			return nil
		}
		return currentFormatSupplementalState(from: mergedSupplementalState)
	}

	func loadFocusedCurrentFormatSupplementalState(
		source: BrowserImportSource,
		sidebarURL: URL,
		keyPath: [String]
	) throws -> ArcCurrentFormatSupplementalState? {
		guard let sidebarSyncState = try loadFocusedCurrentFormatState(
			source: source,
			sidebarURL: sidebarURL,
			keyPath: keyPath
		) else {
			return nil
		}
		return currentFormatSupplementalState(from: sidebarSyncState)
	}

	func loadFocusedCurrentFormatState(
		source: BrowserImportSource,
		sidebarURL: URL,
		keyPath: [String]
	) throws -> JSONObject? {
		guard let inputStream = InputStream(url: sidebarURL) else {
			throw BrowserImportError.readFailed(sidebarURL)
		}

		inputStream.open()
		defer {
			inputStream.close()
		}

		let reader = ArcJSONByteStreamReader(
			stream: inputStream,
			source: source,
			fileURL: sidebarURL
		)
		guard try reader.peekNonWhitespaceByte() == .openBrace else {
			return nil
		}

		for key in keyPath {
			guard try reader.scanForJSONStringToken(key) else {
				return nil
			}
			try reader.expect(.colon)
		}

		let valueData = try reader.readRawValueData()
		guard
			let sidebarSyncState = try decodeJSONObject(
				from: valueData,
				source: source,
				reason: "Invalid Arc \(keyPath.joined(separator: ".")) entry"
			)
		else {
			return nil
		}
		return sidebarSyncState
	}

	func parseCurrentSpaceModels(
		from reader: ArcJSONByteStreamReader,
		source: BrowserImportSource,
		state: inout ArcCurrentSidebarStreamingState
	) throws {
		try reader.expect(.openBracket)
		state.didFinishSpaceModels = false

		while true {
			try checkCancellation()
			guard let nextByte = try reader.peekNonWhitespaceByte() else {
				throw reader.parseError("Unexpected end of Arc spaceModels array")
			}
			if nextByte == .closeBracket {
				_ = try reader.readNonWhitespaceByte()
				state.didFinishSpaceModels = true
				return
			}

			let identifier = try reader.readString()
			try reader.expect(.comma)
			let wrapperData = try reader.readRawValueData()
			if
				let normalizedIdentifier = normalizedNonEmptyValue(identifier),
				let value = try decodeWrappedJSONObject(
					from: wrapperData,
					source: source,
					reason: "Invalid Arc space model entry"
				) {
				state.spaceModelsByID[normalizedIdentifier] = value
				if state.fallbackSpaceIDs.contains(normalizedIdentifier) == false {
					state.fallbackSpaceIDs.append(normalizedIdentifier)
				}
			}

			guard try reader.consumeCommaOrEnd(closing: .closeBracket) else {
				state.didFinishSpaceModels = true
				return
			}
		}
	}

	func parseCurrentContainer(
		from reader: ArcJSONByteStreamReader,
		source: BrowserImportSource,
		state: inout ArcCurrentSidebarStreamingState
	) throws {
		let containerData = try reader.readRawValueData()
		guard
			let containerObject = try decodeJSONObject(
				from: containerData,
				source: source,
				reason: "Invalid Arc container entry"
			)
		else {
			return
		}

		state.orderedSpaceIDs = containerObject
			.dictionaryValue(for: "value")
			.flatMap(currentOrderedSpaceIDs(from:))
			?? []
		let containerValue = containerObject.dictionaryValue(for: "value")
		state.topAppsContainerID = ArcSidebarPinnedStateClassifier
			.resolvedExplicitTopAppsContainerID(from: containerValue)
		state.didLoadOrdering = true
	}

	func parseCurrentOrderedSpaceIDs(
		from reader: ArcJSONByteStreamReader,
		source: BrowserImportSource,
		state: inout ArcCurrentSidebarStreamingState
	) throws {
		let orderedSpaceIDsData = try reader.readRawValueData()
		let orderedSpaceIDsValue = try decodeJSONValue(
			from: orderedSpaceIDsData,
			source: source,
			reason: "Invalid Arc orderedSpaceIDs entry"
		)
		if let object = orderedSpaceIDsValue as? JSONObject {
			state.orderedSpaceIDs = currentOrderedSpaceIDs(from: object) ?? []
		}
		else if let orderedSpaceIDs = orderedSpaceIDsValue as? [String] {
			state.orderedSpaceIDs = orderedSpaceIDs
		}
		else {
			state.orderedSpaceIDs = []
		}
		state.didLoadOrdering = true
	}

	func parseCurrentItems(
		from reader: ArcJSONByteStreamReader,
		source: BrowserImportSource,
		state: inout ArcCurrentSidebarStreamingState,
		onChunk: (ArcSidebarProfileChunk) -> Void
	) throws {
		try reader.expect(.openBracket)

		while true {
			try checkCancellation()
			guard let nextByte = try reader.peekNonWhitespaceByte() else {
				throw reader.parseError("Unexpected end of Arc items array")
			}
			if nextByte == .closeBracket {
				_ = try reader.readNonWhitespaceByte()
				return
			}

			let identifier = try reader.readString()
			try reader.expect(.comma)
			let wrapperData = try reader.readRawValueData()
			if
				let normalizedIdentifier = normalizedNonEmptyValue(identifier),
				let value = try decodeWrappedJSONObject(
					from: wrapperData,
					source: source,
					reason: "Invalid Arc item entry"
				) {
				if let existingValue = state.itemsByID[normalizedIdentifier] {
					if state.supplementalItemIDs.contains(normalizedIdentifier) {
						state.itemsByID[normalizedIdentifier] = mergedCurrentItemPreferringIncoming(
							existing: value,
							incoming: existingValue
						)
						state.supplementalItemIDs.remove(normalizedIdentifier)
					}
					else {
						state.itemsByID[normalizedIdentifier] = mergedCurrentItemPreferringIncoming(
							existing: existingValue,
							incoming: value
						)
					}
				}
				else {
					state.itemsByID[normalizedIdentifier] = value
				}
				try drainReadyCurrentSpaces(
					state: &state,
					onChunk: onChunk,
					isFinalPass: false
				)
			}

			guard try reader.consumeCommaOrEnd(closing: .closeBracket) else {
				return
			}
		}
	}

	func drainReadyCurrentSpaces(
		state: inout ArcCurrentSidebarStreamingState,
		onChunk: (ArcSidebarProfileChunk) -> Void,
		isFinalPass: Bool
	) throws {
		guard state.didFinishSpaceModels else {
			return
		}
		if state.didLoadOrdering == false, isFinalPass == false {
			return
		}

		let orderedSpaceIDs = state.orderedSpaceIDs.isEmpty
			? state.fallbackSpaceIDs
			: state.orderedSpaceIDs
		let pinnedStateClassifier = ArcSidebarPinnedStateClassifier(
			explicitTopAppsContainerID: state.topAppsContainerID,
			itemsByID: state.itemsByID
		)
		let topAppsResolutionLogSignature = topAppsResolutionLogSignature(
			pinnedStateClassifier,
			itemsByID: state.itemsByID
		)
		if state.lastTopAppsResolutionLogSignature != topAppsResolutionLogSignature {
			logTopAppsResolution(
				pinnedStateClassifier,
				itemsByID: state.itemsByID,
				context: "stream"
			)
			state.lastTopAppsResolutionLogSignature = topAppsResolutionLogSignature
		}
		let topAppsRecipientSpaceID = topAppsRecipientSpaceID(
			spacesByID: state.spaceModelsByID,
			orderedSpaceIDs: orderedSpaceIDs
		)
		while state.nextOrderedSpaceIndex < orderedSpaceIDs.count {
			try checkCancellation()
			let nextSpaceIndex = state.nextOrderedSpaceIndex
			let spaceID = orderedSpaceIDs[nextSpaceIndex]
			guard let spaceModel = state.spaceModelsByID[spaceID] else {
				if isFinalPass {
					state.nextOrderedSpaceIndex += 1
					continue
				}
				return
			}
			if
				isFinalPass == false,
				spaceID == topAppsRecipientSpaceID,
				pinnedStateClassifier.topAppsContainerID != nil,
				isTopAppsTreeReady(
					itemsByID: state.itemsByID,
					pinnedStateClassifier: pinnedStateClassifier
				) == false {
				if state.didLogWaitingForTopApps == false {
					arcSidebarImportLogger.notice(
						"Arc import [stream] waiting for Top Apps tree before emitting space=\(spaceID, privacy: .public)"
					)
					state.didLogWaitingForTopApps = true
				}
				return
			}
			guard isCurrentSpaceReady(
				spaceModel: spaceModel,
				itemsByID: state.itemsByID,
				pinnedStateClassifier: pinnedStateClassifier,
				requiresTopAppsTree: spaceID == topAppsRecipientSpaceID
			) else {
				if isFinalPass {
					state.nextOrderedSpaceIndex += 1
					continue
				}
				return
			}
			guard let chunk = currentFormatProfileChunk(
				spaceID: spaceID,
				spaceModel: spaceModel,
				itemsByID: state.itemsByID,
				pinnedStateClassifier: pinnedStateClassifier,
				orderedSpaceIDs: orderedSpaceIDs,
				index: nextSpaceIndex,
				topAppsRecipientSpaceID: topAppsRecipientSpaceID
			) else {
				state.nextOrderedSpaceIndex += 1
				continue
			}
			onChunk(chunk)
			state.nextOrderedSpaceIndex += 1
		}
	}

	func isTopAppsTreeReady(
		itemsByID: [String: JSONObject],
		pinnedStateClassifier: ArcSidebarPinnedStateClassifier
	) -> Bool {
		guard let topAppsContainerID = pinnedStateClassifier.topAppsContainerID else {
			return false
		}
		var visitedContainerItemIDs = Set<String>()
		return isCurrentItemTreeReady(
			itemID: topAppsContainerID,
			itemsByID: itemsByID,
			visitedItemIDs: &visitedContainerItemIDs
		)
	}

	func currentFormatProfileChunk(
		spaceID: String,
		spaceModel: JSONObject,
		itemsByID: [String: JSONObject],
		pinnedStateClassifier: ArcSidebarPinnedStateClassifier,
		orderedSpaceIDs: [String],
		index: Int,
		topAppsRecipientSpaceID: String?
	) -> ArcSidebarProfileChunk? {
		let bookmarkItemIDs = currentRootItemIDs(
			for: spaceModel,
			itemsByID: itemsByID,
			pinnedStateClassifier: pinnedStateClassifier,
			includeTopApps: spaceID == topAppsRecipientSpaceID,
			selection: .bookmarks
		)
		let windowRootItemIDs = currentRootItemIDs(
			for: spaceModel,
			itemsByID: itemsByID,
			pinnedStateClassifier: pinnedStateClassifier,
			includeTopApps: spaceID == topAppsRecipientSpaceID,
			selection: .window
		)
		let bookmarkContent = currentContent(
			for: bookmarkItemIDs,
			itemsByID: itemsByID
		)
		let discoveredTabs = currentTabs(
			for: windowRootItemIDs,
			itemsByID: itemsByID,
			pinnedStateClassifier: pinnedStateClassifier
		)
		let windowTabs = orderedWindowTabs(from: discoveredTabs)
		let displayName = currentResolvedTitle(
			from: spaceModel,
			fallback: nil
		) ?? currentResolvedTitle(
			from: itemsByID[spaceID],
			fallback: nil
		) ?? (
			orderedSpaceIDs.count > 1 ? "Space \(index + 1)" : "Space"
		)
		let topAppsRootIDs = spaceID == topAppsRecipientSpaceID
			? topAppsRootItemIDs(
				itemsByID: itemsByID,
				pinnedStateClassifier: pinnedStateClassifier
			)
			: []
		logCurrentFormatWindowDiscovery(
			spaceID: spaceID,
			displayName: displayName,
			topAppsRecipientSpaceID: topAppsRecipientSpaceID,
			bookmarkItemIDs: bookmarkItemIDs,
			topAppsRootIDs: topAppsRootIDs,
			windowRootItemIDs: windowRootItemIDs,
			discoveredTabs: windowTabs
		)
		guard bookmarkContent.isEmpty == false || windowTabs.isEmpty == false else {
			return nil
		}
		let bookmarkFolder: ImportedBookmarkFolder? = if
			bookmarkContent.bookmarks.isEmpty == false || bookmarkContent.folders.isEmpty == false {
			wrappedFolder(
				id: "space-\(spaceID)",
				displayName: displayName,
				content: bookmarkContent
			)
		}
		else {
			nil
		}
		let window = windowTabs.isEmpty
			? nil
			: window(
				id: "space-\(spaceID)",
				displayName: displayName,
				tabs: windowTabs
			)
		guard window != nil || bookmarkFolder != nil else {
			return nil
		}
		return ArcSidebarProfileChunk(
			window: window,
			bookmarkFolder: bookmarkFolder
		)
	}

	func isCurrentSpaceReady(
		spaceModel: JSONObject,
		itemsByID: [String: JSONObject],
		pinnedStateClassifier: ArcSidebarPinnedStateClassifier,
		requiresTopAppsTree: Bool
	) -> Bool {
		let requiresResolvedTopAppsTree = requiresTopAppsTree && pinnedStateClassifier.topAppsContainerID != nil
		if requiresResolvedTopAppsTree,
		   isTopAppsTreeReady(
		   	itemsByID: itemsByID,
		   	pinnedStateClassifier: pinnedStateClassifier
		   ) == false {
			return false
		}
		let candidateContainerIDs = [
			pinnedContainerID(from: spaceModel),
			unpinnedContainerID(from: spaceModel),
		].compactMap { $0 }
		var itemTreeRootIDs = candidateContainerIDs
		if requiresResolvedTopAppsTree {
			let topAppsRootIDs = topAppsRootItemIDs(
				itemsByID: itemsByID,
				pinnedStateClassifier: pinnedStateClassifier
			)
			guard topAppsRootIDs.isEmpty == false else {
				return false
			}
			itemTreeRootIDs.append(contentsOf: topAppsRootIDs)
		}
		guard itemTreeRootIDs.isEmpty == false else {
			return false
		}
		for containerID in uniqueItemIDsPreservingOrder(itemTreeRootIDs) {
			var visitedItemIDs = Set<String>()
			guard isCurrentItemTreeReady(
				itemID: containerID,
				itemsByID: itemsByID,
				visitedItemIDs: &visitedItemIDs
			) else {
				return false
			}
		}
		return true
	}

	private func mergedCurrentItemPreferringIncoming(
		existing: JSONObject,
		incoming: JSONObject
	) -> JSONObject {
		mergedJSONObjectPreferringIncoming(
			existing: existing,
			incoming: incoming
		)
	}

	private func mergedJSONObjectPreferringIncoming(
		existing: JSONObject,
		incoming: JSONObject
	) -> JSONObject {
		var merged = existing
		for (key, incomingValue) in incoming {
			guard let existingValue = merged[key] else {
				merged[key] = incomingValue
				continue
			}

			if
				let existingObject = existingValue as? JSONObject,
				let incomingObject = incomingValue as? JSONObject {
				merged[key] = mergedJSONObjectPreferringIncoming(
					existing: existingObject,
					incoming: incomingObject
				)
				continue
			}

			if
				let existingChildren = existingValue as? [String],
				let incomingChildren = incomingValue as? [String],
				key == "childrenIds" {
				merged[key] = uniqueItemIDsPreservingOrder(existingChildren + incomingChildren)
				continue
			}

			if isJSONObjectValueEmpty(incomingValue) == false {
				merged[key] = incomingValue
			}
		}
		return merged
	}

	private func isJSONObjectValueEmpty(_ value: Any) -> Bool {
		switch value {
		case let string as String:
			return normalizedNonEmptyValue(string) == nil
		case let dictionary as JSONObject:
			return dictionary.isEmpty
		case let array as [Any]:
			return array.isEmpty
		case is NSNull:
			return true
		default:
			return false
		}
	}

	func isCurrentItemTreeReady(
		itemID: String,
		itemsByID: [String: JSONObject],
		visitedItemIDs: inout Set<String>
	) -> Bool {
		guard visitedItemIDs.insert(itemID).inserted else {
			return true
		}
		guard let item = itemsByID[itemID] else {
			return false
		}
		for childID in item.stringArrayValue(for: "childrenIds") ?? [] {
			guard isCurrentItemTreeReady(
				itemID: childID,
				itemsByID: itemsByID,
				visitedItemIDs: &visitedItemIDs
			) else {
				return false
			}
		}
		return true
	}

	func decodeWrappedJSONObject(
		from data: Data,
		source: BrowserImportSource,
		reason: String
	) throws -> JSONObject? {
		guard
			let wrapperObject = try decodeJSONObject(
				from: data,
				source: source,
				reason: reason
			)
		else {
			return nil
		}
		return wrapperObject.dictionaryValue(for: "value") ?? wrapperObject.dictionaryValue(for: "item") ?? wrapperObject
	}

	func decodeJSONObject(
		from data: Data,
		source: BrowserImportSource,
		reason: String
	) throws -> JSONObject? {
		try decodeJSONValue(
			from: data,
			source: source,
			reason: reason
		) as? JSONObject
	}

	func decodeJSONValue(
		from data: Data,
		source: BrowserImportSource,
		reason: String
	) throws -> Any {
		let rootObject: Any
		do {
			rootObject = try JSONSerialization.jsonObject(with: data)
		}
		catch {
			throw BrowserImportError.parseFailed(
				source,
				reason: reason
			)
		}
		return rootObject
	}

	func checkCancellation() throws {
		if Task.isCancelled {
			throw CancellationError()
		}
	}

	func streamLiveSidebarProfileChunks(
		source: BrowserImportSource,
		sidebarURL: URL,
		onChunk: (ArcSidebarProfileChunk) -> Void
	) throws -> Bool {
		guard let inputStream = InputStream(url: sidebarURL) else {
			throw BrowserImportError.readFailed(sidebarURL)
		}

		inputStream.open()
		defer {
			inputStream.close()
		}

		let reader = ArcJSONByteStreamReader(
			stream: inputStream,
			source: source,
			fileURL: sidebarURL
		)
		guard try reader.peekNonWhitespaceByte() == .openBrace else {
			return false
		}

		for key in ArcSidebarStreamingConstants.liveSidebarContainersKeyPath {
			guard try reader.scanForJSONStringToken(key) else {
				return false
			}
			try reader.expect(.colon)
		}

		let containersData = try reader.readRawValueData()
		let containers = try decodeJSONValue(
			from: containersData,
			source: source,
			reason: "Invalid Arc sidebar containers entry"
		) as? [Any] ?? []
		guard let currentContainer = currentSidebarContainer(from: containers) else {
			return false
		}

		for chunk in currentFormatProfileChunks(from: currentContainer) {
			onChunk(chunk)
		}
		return true
	}
}

private struct ArcCurrentSidebarStreamingState {
	var didFinishSpaceModels = false
	var didLogWaitingForTopApps = false
	var didLoadOrdering = false
	var lastTopAppsResolutionLogSignature: String?
	var nextOrderedSpaceIndex = 0
	var orderedSpaceIDs = [String]()
	var fallbackSpaceIDs = [String]()
	var supplementalItemIDs = Set<String>()
	var spaceModelsByID = [String: JSONObject]()
	var itemsByID = [String: JSONObject]()
	var topAppsContainerID: String?
}

private enum ArcSidebarStreamingConstants {
	static let containerKey = "container"
	static let containersKey = "containers"
	static let firebaseSyncStateKey = "firebaseSyncState"
	static let itemsKey = "items"
	static let orderedSpaceIDsKey = "orderedSpaceIDs"
	static let sidebarKey = "sidebar"
	static let sidebarSyncStateKey = "sidebarSyncState"
	static let spaceModelsKey = "spaceModels"
	static let syncDataKey = "syncData"

	static let firebaseSyncDataKeyPath = [firebaseSyncStateKey, syncDataKey]
	static let liveSidebarContainersKeyPath = [sidebarKey, containersKey]
	static let sidebarSyncStateKeyPath = [sidebarSyncStateKey]
}

private final class ArcJSONByteStreamReader {
	private let fileURL: URL
	private let source: BrowserImportSource
	private let stream: InputStream
	private var buffer = [UInt8](repeating: 0, count: 8192)
	private var bufferedCount = 0
	private var bufferedIndex = 0
	private var pushedBackByte: UInt8?

	init(
		stream: InputStream,
		source: BrowserImportSource,
		fileURL: URL
	) {
		self.stream = stream
		self.source = source
		self.fileURL = fileURL
	}

	func peekNonWhitespaceByte() throws -> UInt8? {
		guard let nextByte = try readNonWhitespaceByte() else {
			return nil
		}
		unread(nextByte)
		return nextByte
	}

	func readNonWhitespaceByte() throws -> UInt8? {
		while let nextByte = try readByte() {
			if nextByte.isJSONWhitespace == false {
				return nextByte
			}
		}
		return nil
	}

	func expect(_ expectedByte: UInt8) throws {
		guard let nextByte = try readNonWhitespaceByte() else {
			throw parseError("Unexpected end of Arc sidebar document")
		}
		guard nextByte == expectedByte else {
			throw parseError("Unexpected Arc JSON token")
		}
	}

	func readString() throws -> String {
		let data = try readRawStringData()
		let decodedValue: Any
		do {
			decodedValue = try JSONSerialization.jsonObject(
				with: data,
				options: [.fragmentsAllowed]
			)
		}
		catch {
			throw parseError("Invalid Arc JSON string")
		}
		guard let stringValue = decodedValue as? String else {
			throw parseError("Invalid Arc JSON string")
		}
		return stringValue
	}

	func skipValue() throws {
		_ = try readRawValueData()
	}

	func consumeCommaOrEnd(closing: UInt8) throws -> Bool {
		guard let nextByte = try readNonWhitespaceByte() else {
			throw parseError("Unexpected end of Arc sidebar document")
		}
		switch nextByte {
		case .comma:
			return true
		case closing:
			return false
		default:
			throw parseError("Unexpected Arc JSON delimiter")
		}
	}

	func readRawValueData() throws -> Data {
		guard let firstByte = try readNonWhitespaceByte() else {
			throw parseError("Unexpected end of Arc sidebar document")
		}

		switch firstByte {
		case .quote:
			return try readRawStringData(startingWith: firstByte)
		case .openBrace, .openBracket:
			return try readStructuredValueData(startingWith: firstByte)
		default:
			return try readPrimitiveValueData(startingWith: firstByte)
		}
	}

	func parseError(_ reason: String) -> BrowserImportError {
		.parseFailed(
			source,
			reason: "\(reason) at \(fileURL.lastPathComponent)"
		)
	}

	func scanForJSONStringToken(_ token: String) throws -> Bool {
		let pattern = Array("\"\(token)\"".utf8)
		guard pattern.isEmpty == false else {
			return false
		}

		var matchedCount = 0
		while let nextByte = try readByte() {
			if nextByte == pattern[matchedCount] {
				matchedCount += 1
				if matchedCount == pattern.count {
					return true
				}
				continue
			}

			matchedCount = nextByte == pattern[0] ? 1 : 0
		}

		return false
	}

	private func readRawStringData() throws -> Data {
		guard let firstByte = try readNonWhitespaceByte() else {
			throw parseError("Unexpected end of Arc JSON string")
		}
		guard firstByte == .quote else {
			throw parseError("Expected Arc JSON string")
		}
		return try readRawStringData(startingWith: firstByte)
	}

	private func readRawStringData(startingWith firstByte: UInt8) throws -> Data {
		var bytes = [firstByte]
		var isEscaping = false
		while let nextByte = try readByte() {
			bytes.append(nextByte)
			if isEscaping {
				isEscaping = false
				continue
			}
			if nextByte == .backslash {
				isEscaping = true
				continue
			}
			if nextByte == .quote {
				return Data(bytes)
			}
		}
		throw parseError("Unexpected end of Arc JSON string")
	}

	private func readStructuredValueData(startingWith firstByte: UInt8) throws -> Data {
		var bytes = [firstByte]
		var depth = 1
		var isInsideString = false
		var isEscaping = false

		while let nextByte = try readByte() {
			bytes.append(nextByte)
			if isInsideString {
				if isEscaping {
					isEscaping = false
				}
				else if nextByte == .backslash {
					isEscaping = true
				}
				else if nextByte == .quote {
					isInsideString = false
				}
				continue
			}

			switch nextByte {
			case .quote:
				isInsideString = true
			case .openBrace, .openBracket:
				depth += 1
			case .closeBrace, .closeBracket:
				depth -= 1
				if depth == 0 {
					return Data(bytes)
				}
			default:
				break
			}
		}

		throw parseError("Unexpected end of Arc JSON value")
	}

	private func readPrimitiveValueData(startingWith firstByte: UInt8) throws -> Data {
		var bytes = [firstByte]
		while let nextByte = try readByte() {
			if nextByte.isJSONValueTerminator {
				unread(nextByte)
				return Data(bytes)
			}
			bytes.append(nextByte)
		}
		return Data(bytes)
	}

	private func readByte() throws -> UInt8? {
		if let pushedBackByte {
			self.pushedBackByte = nil
			return pushedBackByte
		}

		if bufferedIndex < bufferedCount {
			let nextByte = buffer[bufferedIndex]
			bufferedIndex += 1
			return nextByte
		}

		bufferedIndex = 0
		bufferedCount = stream.read(&buffer, maxLength: buffer.count)
		if bufferedCount < 0 || stream.streamStatus == .error {
			throw BrowserImportError.readFailed(fileURL)
		}
		guard bufferedCount > 0 else {
			return nil
		}

		let nextByte = buffer[bufferedIndex]
		bufferedIndex += 1
		return nextByte
	}

	private func unread(_ byte: UInt8) {
		pushedBackByte = byte
	}
}

typealias JSONObject = [String: Any]

private extension UInt8 {
	static let backslash = UInt8(ascii: "\\")
	static let closeBrace = UInt8(ascii: "}")
	static let closeBracket = UInt8(ascii: "]")
	static let colon = UInt8(ascii: ":")
	static let comma = UInt8(ascii: ",")
	static let openBrace = UInt8(ascii: "{")
	static let openBracket = UInt8(ascii: "[")
	static let quote = UInt8(ascii: "\"")

	var isJSONValueTerminator: Bool {
		isJSONWhitespace || self == .comma || self == .closeBrace || self == .closeBracket
	}

	var isJSONWhitespace: Bool {
		self == 0x20 || self == 0x09 || self == 0x0A || self == 0x0D
	}
}

private extension [String: Any] {
	func arrayValue(for key: String) -> [JSONObject] {
		self[key] as? [JSONObject] ?? []
	}

	func anyArrayValue(for key: String) -> [Any] {
		self[key] as? [Any] ?? []
	}

	func boolValue(for key: String) -> Bool? {
		self[key] as? Bool
	}

	func dictionaryValue(for key: String) -> JSONObject? {
		self[key] as? JSONObject
	}

	func intValue(for key: String) -> Int? {
		if let intValue = self[key] as? Int {
			return intValue
		}
		if let numberValue = self[key] as? NSNumber {
			return numberValue.intValue
		}
		return nil
	}

	func stringArrayValue(for key: String) -> [String]? {
		self[key] as? [String]
	}

	func stringValue(for key: String) -> String? {
		self[key] as? String
	}
}
