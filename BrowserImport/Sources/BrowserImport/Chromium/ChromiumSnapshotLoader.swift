import Foundation
import ModelKit

struct ChromiumSnapshotLoader {
	func loadProfileChunkStream(
		source: BrowserImportSource,
		profile: BrowserProfile,
		dataKinds: [BrowserImportDataKind]
	) -> AsyncThrowingStream<ImportedBrowserProfile, Error> {
		let requestedKinds = Set(dataKinds)

		switch source {
		case .arc:
			return loadArcProfileChunkStream(
				profile: profile,
				requestedKinds: requestedKinds
			)
		case .chrome, .safari:
			return AsyncThrowingStream { continuation in
				do {
					try continuation.yield(
						loadProfile(
							source: source,
							profile: profile,
							dataKinds: dataKinds
						)
					)
					continuation.finish()
				}
				catch {
					continuation.finish(throwing: error)
				}
			}
		}
	}

	func loadProfileChunks(
		source: BrowserImportSource,
		profile: BrowserProfile,
		dataKinds: [BrowserImportDataKind]
	) throws -> [ImportedBrowserProfile] {
		let requestedKinds = Set(dataKinds)

		switch source {
		case .arc:
			return try loadArcProfileChunks(
				profile: profile,
				requestedKinds: requestedKinds
			)
		case .chrome, .safari:
			return try [
				loadProfile(
					source: source,
					profile: profile,
					dataKinds: dataKinds
				),
			]
		}
	}

	func loadProfile(
		source: BrowserImportSource,
		profile: BrowserProfile,
		dataKinds: [BrowserImportDataKind]
	) throws -> ImportedBrowserProfile {
		let requestedKinds = Set(dataKinds)
		let windows: [ImportedBrowserWindow] = if requestedKinds.contains(.tabs) {
			switch source {
			case .arc:
				profile.isDefault
					? try ArcSidebarBookmarksParser().loadWindows(
						source: source,
						profileURL: profile.profileURL
					)
					: []
			case .chrome, .safari:
				[]
			}
		}
		else {
			[]
		}
		let bookmarkFolders: [ImportedBookmarkFolder] = if requestedKinds.contains(.bookmarks) {
			switch source {
			case .arc:
				// Arc stores sidebar bookmarks globally, so attach them once from the default profile.
				profile.isDefault
					? try ArcSidebarBookmarksParser().loadFolders(
						source: source,
						profileURL: profile.profileURL
					)
					: []
			case .chrome:
				try ChromiumBookmarksParser().loadFolders(
					source: source,
					profileURL: profile.profileURL
				)
			case .safari:
				[]
			}
		}
		else {
			[]
		}
		let historyEntries = requestedKinds.contains(.history)
			? try ChromiumHistoryReader().loadHistoryEntries(
				source: source,
				profileURL: profile.profileURL
			)
			: []

		return ImportedBrowserProfile(
			id: profile.id,
			displayName: profile.displayName,
			isDefault: profile.isDefault,
			windows: windows,
			bookmarkFolders: bookmarkFolders,
			historyEntries: historyEntries
		)
	}

	private func loadArcProfileChunks(
		profile: BrowserProfile,
		requestedKinds: Set<BrowserImportDataKind>
	) throws -> [ImportedBrowserProfile] {
		var chunks = try loadArcSidebarProfileChunks(
			profile: profile,
			requestedKinds: requestedKinds
		)
		if let historyChunk = try loadArcHistoryProfileChunk(
			profile: profile,
			requestedKinds: requestedKinds,
			hasSidebarChunks: chunks.isEmpty == false
		) {
			chunks.append(historyChunk)
		}
		if chunks.isEmpty {
			chunks.append(emptyProfile(for: profile))
		}
		return chunks
	}

	private func loadArcProfileChunkStream(
		profile: BrowserProfile,
		requestedKinds: Set<BrowserImportDataKind>
	) -> AsyncThrowingStream<ImportedBrowserProfile, Error> {
		AsyncThrowingStream { continuation in
			let task = Task { @Sendable in
				do {
					var didYieldChunk = false
					if profile.isDefault {
						let parser = ArcSidebarBookmarksParser()
						for try await sidebarChunk in parser.loadProfileChunkStream(
							source: .arc,
							profileURL: profile.profileURL
						) {
							let windows = requestedKinds.contains(.tabs)
								? [sidebarChunk.window].compactMap { $0 }
								: []
							let bookmarkFolders = requestedKinds.contains(.bookmarks)
								? [sidebarChunk.bookmarkFolder].compactMap { $0 }
								: []
							guard windows.isEmpty == false || bookmarkFolders.isEmpty == false else {
								continue
							}
							didYieldChunk = true
							continuation.yield(
								emptyProfile(
									for: profile,
									windows: windows,
									bookmarkFolders: bookmarkFolders
								)
							)
						}
					}
					if let historyChunk = try loadArcHistoryProfileChunk(
						profile: profile,
						requestedKinds: requestedKinds,
						hasSidebarChunks: didYieldChunk
					) {
						didYieldChunk = true
						continuation.yield(historyChunk)
					}
					if didYieldChunk == false {
						continuation.yield(emptyProfile(for: profile))
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

	private func loadArcSidebarProfileChunks(
		profile: BrowserProfile,
		requestedKinds: Set<BrowserImportDataKind>
	) throws -> [ImportedBrowserProfile] {
		guard profile.isDefault else {
			return []
		}
		let sidebarChunks = try ArcSidebarBookmarksParser().loadProfileChunks(
			source: .arc,
			profileURL: profile.profileURL
		)
		return sidebarChunks.compactMap { sidebarChunk in
			let windows = requestedKinds.contains(.tabs)
				? [sidebarChunk.window].compactMap { $0 }
				: []
			let bookmarkFolders = requestedKinds.contains(.bookmarks)
				? [sidebarChunk.bookmarkFolder].compactMap { $0 }
				: []
			guard windows.isEmpty == false || bookmarkFolders.isEmpty == false else {
				return nil
			}
			return emptyProfile(
				for: profile,
				windows: windows,
				bookmarkFolders: bookmarkFolders
			)
		}
	}

	private func loadArcHistoryProfileChunk(
		profile: BrowserProfile,
		requestedKinds: Set<BrowserImportDataKind>,
		hasSidebarChunks: Bool
	) throws -> ImportedBrowserProfile? {
		guard requestedKinds.contains(.history) else {
			return nil
		}
		let historyEntries = try ChromiumHistoryReader().loadHistoryEntries(
			source: .arc,
			profileURL: profile.profileURL
		)
		guard historyEntries.isEmpty == false || hasSidebarChunks == false else {
			return nil
		}
		return emptyProfile(
			for: profile,
			historyEntries: historyEntries
		)
	}

	private func emptyProfile(
		for profile: BrowserProfile,
		windows: [ImportedBrowserWindow] = [],
		bookmarkFolders: [ImportedBookmarkFolder] = [],
		historyEntries: [ImportedHistoryEntry] = []
	) -> ImportedBrowserProfile {
		ImportedBrowserProfile(
			id: profile.id,
			displayName: profile.displayName,
			isDefault: profile.isDefault,
			windows: windows,
			bookmarkFolders: bookmarkFolders,
			historyEntries: historyEntries
		)
	}
}
