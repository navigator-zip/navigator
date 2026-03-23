import Foundation
import ModelKit

public struct BrowserImportCoordinator: Sendable {
	public typealias DiscoverInstallations = @Sendable () throws -> [BrowserInstallation]
	public typealias LoadProfileSnapshot = @Sendable (
		BrowserImportSource,
		BrowserProfile,
		[BrowserImportDataKind]
	) throws -> ImportedBrowserProfile
	public typealias LoadProfileChunks = @Sendable (
		BrowserImportSource,
		BrowserProfile,
		[BrowserImportDataKind]
	) throws -> [ImportedBrowserProfile]
	public typealias LoadProfileChunkStream = @Sendable (
		BrowserImportSource,
		BrowserProfile,
		[BrowserImportDataKind]
	) -> AsyncThrowingStream<ImportedBrowserProfile, Error>
	public typealias LoadRunningWindows = @Sendable (BrowserImportSource) throws -> [ImportedBrowserWindow]

	private let discoverInstallationsClosure: DiscoverInstallations
	private let loadProfileSnapshotClosure: LoadProfileSnapshot
	private let loadProfileChunkStreamClosure: LoadProfileChunkStream?
	private let loadRunningWindowsClosure: LoadRunningWindows

	public init(
		discoverInstallations: @escaping DiscoverInstallations,
		loadProfileSnapshot: @escaping LoadProfileSnapshot,
		loadRunningWindows: @escaping LoadRunningWindows
	) {
		discoverInstallationsClosure = discoverInstallations
		loadProfileSnapshotClosure = loadProfileSnapshot
		loadProfileChunkStreamClosure = nil
		loadRunningWindowsClosure = loadRunningWindows
	}

	public init(
		discoverInstallations: @escaping DiscoverInstallations,
		loadProfileSnapshot: @escaping LoadProfileSnapshot,
		loadProfileChunks: @escaping LoadProfileChunks,
		loadRunningWindows: @escaping LoadRunningWindows
	) {
		discoverInstallationsClosure = discoverInstallations
		loadProfileSnapshotClosure = loadProfileSnapshot
		loadProfileChunkStreamClosure = Self.streamLoader(from: loadProfileChunks)
		loadRunningWindowsClosure = loadRunningWindows
	}

	public init(
		discoverInstallations: @escaping DiscoverInstallations,
		loadProfileSnapshot: @escaping LoadProfileSnapshot,
		loadProfileChunkStream: @escaping LoadProfileChunkStream,
		loadRunningWindows: @escaping LoadRunningWindows
	) {
		discoverInstallationsClosure = discoverInstallations
		loadProfileSnapshotClosure = loadProfileSnapshot
		loadProfileChunkStreamClosure = loadProfileChunkStream
		loadRunningWindowsClosure = loadRunningWindows
	}

	public static func live(homeDirectory: URL) -> Self {
		return Self(
			discoverInstallations: {
				BrowserSourceDiscoverer(homeDirectory: homeDirectory).discoverInstallations()
			},
			loadProfileSnapshot: { source, profile, dataKinds in
				switch source {
				case .arc, .chrome:
					return try ChromiumSnapshotLoader().loadProfile(
						source: source,
						profile: profile,
						dataKinds: dataKinds
					)
				case .safari:
					return try SafariSnapshotLoader().loadProfile(
						source: source,
						profile: profile,
						dataKinds: dataKinds
					)
				}
			},
			loadProfileChunkStream: { source, profile, dataKinds in
				ChromiumSnapshotLoader().loadProfileChunkStream(
					source: source,
					profile: profile,
					dataKinds: dataKinds
				)
			},
			loadRunningWindows: { source in
				switch source {
				case .arc:
					[]
				case .chrome, .safari:
					try RunningBrowserTabsLoader().loadWindows(for: source)
				}
			}
		)
	}

	public func discoverInstallations() throws -> [BrowserInstallation] {
		try discoverInstallationsClosure()
	}

	public func previewImport(for selection: BrowserImportSelection) throws -> BrowserImportPreview {
		try loadSnapshot(for: selection).preview
	}

	public func streamImport(
		for selection: BrowserImportSelection
	) -> AsyncThrowingStream<BrowserImportEvent, Error> {
		AsyncThrowingStream { continuation in
			let coordinator = self
			Task {
				do {
					let installation = try coordinator.resolveInstallation(for: selection.source)
					let profiles = try coordinator.resolveProfiles(
						from: installation,
						selectedProfileIDs: selection.profileIDs
					)
					let runningWindows = try coordinator.resolveRunningWindows(for: selection)
					let targetProfileID = profiles.first(where: \.isDefault)?.id ?? profiles.first?.id

					continuation.yield(.started(selection.source))

					var importedProfiles = [ImportedBrowserProfile]()
					for profile in profiles {
						let shouldMergeRunningWindows = runningWindows.isEmpty == false && profile.id == targetProfileID
						if
							let profileChunkStream = coordinator.resolveProfileChunkStream(
								source: selection.source,
								profile: profile,
								dataKinds: selection.dataKinds
							) {
							var mergedProfile = coordinator.emptyProfile(for: profile)
							var didEmitChunk = false
							for try await chunk in profileChunkStream {
								didEmitChunk = true
								mergedProfile = coordinator.mergedProfile(
									mergedProfile,
									with: chunk
								)
								continuation.yield(.profileImported(selection.source, chunk))
							}
							if shouldMergeRunningWindows {
								let runningWindowsChunk = coordinator.emptyProfile(
									for: profile,
									windows: runningWindows
								)
								didEmitChunk = true
								mergedProfile = coordinator.mergedProfile(
									mergedProfile,
									with: runningWindowsChunk
								)
								continuation.yield(.profileImported(selection.source, runningWindowsChunk))
							}
							if didEmitChunk == false {
								let emptyProfile = coordinator.emptyProfile(for: profile)
								mergedProfile = emptyProfile
								continuation.yield(.profileImported(selection.source, emptyProfile))
							}
							importedProfiles.append(mergedProfile)
							continue
						}

						var importedProfile = try coordinator.loadProfileSnapshotClosure(
							selection.source,
							profile,
							selection.dataKinds
						)
						if shouldMergeRunningWindows {
							importedProfile = coordinator.profile(
								byMergingRunningWindows: runningWindows,
								into: importedProfile
							)
						}
						importedProfiles.append(importedProfile)
						continuation.yield(.profileImported(selection.source, importedProfile))
					}

					let snapshot = ImportedBrowserSnapshot(
						source: selection.source,
						profiles: importedProfiles
					)
					continuation.yield(.finished(snapshot))
					continuation.finish()
				}
				catch {
					continuation.finish(throwing: error)
				}
			}
		}
	}

	public func loadSnapshot(for selection: BrowserImportSelection) throws -> ImportedBrowserSnapshot {
		let installation = try resolveInstallation(for: selection.source)
		let profiles = try resolveProfiles(
			from: installation,
			selectedProfileIDs: selection.profileIDs
		)
		let importedProfiles = try profiles.map { profile in
			try loadProfileSnapshotClosure(
				selection.source,
				profile,
				selection.dataKinds
			)
		}
		let mergedProfiles: [ImportedBrowserProfile]
		let runningWindows = try resolveRunningWindows(for: selection)
		if runningWindows.isEmpty == false {
			mergedProfiles = mergeRunningWindows(runningWindows, into: importedProfiles)
		}
		else {
			mergedProfiles = importedProfiles
		}
		return ImportedBrowserSnapshot(
			source: selection.source,
			profiles: mergedProfiles
		)
	}

	private func resolveInstallation(for source: BrowserImportSource) throws -> BrowserInstallation {
		let installations = try discoverInstallationsClosure()
		guard let installation = installations.first(where: { $0.source == source }) else {
			throw BrowserImportError.browserNotInstalled(source)
		}
		return installation
	}

	private func resolveProfiles(
		from installation: BrowserInstallation,
		selectedProfileIDs: [String]
	) throws -> [BrowserProfile] {
		guard installation.profiles.isEmpty == false else {
			throw BrowserImportError.noProfilesFound(installation.source)
		}

		if selectedProfileIDs.isEmpty {
			return installation.profiles
		}

		let profilesByID = Dictionary(
			uniqueKeysWithValues: installation.profiles.map { ($0.id, $0) }
		)
		return try selectedProfileIDs.map { profileID in
			guard let profile = profilesByID[profileID] else {
				throw BrowserImportError.profileNotFound(
					installation.source,
					profileID: profileID
				)
			}
			return profile
		}
	}

	private func resolveRunningWindows(
		for selection: BrowserImportSelection
	) throws -> [ImportedBrowserWindow] {
		guard selection.dataKinds.contains(.tabs) else { return [] }
		return try loadRunningWindowsClosure(selection.source)
	}

	private func resolveProfileChunkStream(
		source: BrowserImportSource,
		profile: BrowserProfile,
		dataKinds: [BrowserImportDataKind]
	) -> AsyncThrowingStream<ImportedBrowserProfile, Error>? {
		guard source == .arc, let loadProfileChunkStreamClosure else {
			return nil
		}
		return loadProfileChunkStreamClosure(
			source,
			profile,
			dataKinds
		)
	}

	private func mergeRunningWindows(
		_ runningWindows: [ImportedBrowserWindow],
		into profiles: [ImportedBrowserProfile]
	) -> [ImportedBrowserProfile] {
		guard runningWindows.isEmpty == false else { return profiles }
		guard profiles.isEmpty == false else { return profiles }

		let targetIndex = profiles.firstIndex(where: \.isDefault) ?? 0
		var mergedProfiles = profiles
		let targetProfile = mergedProfiles[targetIndex]
		mergedProfiles[targetIndex] = profile(
			byMergingRunningWindows: runningWindows,
			into: targetProfile
		)
		return mergedProfiles
	}

	private func profile(
		byMergingRunningWindows runningWindows: [ImportedBrowserWindow],
		into profile: ImportedBrowserProfile
	) -> ImportedBrowserProfile {
		ImportedBrowserProfile(
			id: profile.id,
			displayName: profile.displayName,
			isDefault: profile.isDefault,
			windows: runningWindows,
			bookmarkFolders: profile.bookmarkFolders,
			historyEntries: profile.historyEntries
		)
	}

	private func mergedProfile(
		_ profile: ImportedBrowserProfile,
		with chunk: ImportedBrowserProfile
	) -> ImportedBrowserProfile {
		ImportedBrowserProfile(
			id: profile.id,
			displayName: profile.displayName,
			isDefault: profile.isDefault,
			windows: profile.windows + chunk.windows,
			bookmarkFolders: profile.bookmarkFolders + chunk.bookmarkFolders,
			historyEntries: profile.historyEntries + chunk.historyEntries
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

	private static func streamLoader(
		from loadProfileChunks: @escaping LoadProfileChunks
	) -> LoadProfileChunkStream {
		{ source, profile, dataKinds in
			AsyncThrowingStream { continuation in
				do {
					for chunk in try loadProfileChunks(source, profile, dataKinds) {
						continuation.yield(chunk)
					}
					continuation.finish()
				}
				catch {
					continuation.finish(throwing: error)
				}
			}
		}
	}
}
