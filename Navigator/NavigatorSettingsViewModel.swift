import BrowserImport
import Foundation
import ModelKit
import Observation
import Vendors

enum NavigatorSettingsSection: Int, CaseIterable {
	case general
	case camera
	case account
	case colophon

	static let allCases: [NavigatorSettingsSection] = [
		.general,
		.account,
		.colophon,
	]
}

enum NavigatorDefaultBrowserStatus: Equatable {
	case readyToSet
	case currentDefault
	case updateFailed
}

enum NavigatorBrowserImportStatus: Equatable {
	case idle
	case importing(BrowserImportSource)
	case completed(BrowserImportSource, BrowserImportPreview)
	case failed(String)
}

enum NavigatorBrowserImportIndicatorState: Equatable {
	case importing
	case completed
}

@MainActor
@Observable
final class NavigatorSettingsViewModel {
	typealias ExecuteImport = (BrowserImportSelection) -> AsyncThrowingStream<BrowserImportEvent, Error>

	@ObservationIgnored @Dependency(\.date.now) private var now
	@ObservationIgnored @Shared(
		.navigatorImportedBrowserLibrary
	) private var importedBrowserLibrary: ImportedBrowserLibrary
	@ObservationIgnored @Shared(
		.navigatorAutomaticallyChecksForUpdates
	) private var storedAutomaticallyChecksForUpdates: Bool

	var selectedSection: NavigatorSettingsSection = .general {
		didSet {
			if NavigatorSettingsSection.allCases.contains(selectedSection) == false {
				selectedSection = .general
			}
		}
	}

	var automaticallyChecksForUpdates = true
	var defaultBrowserStatus: NavigatorDefaultBrowserStatus
	var browserImportStatus: NavigatorBrowserImportStatus = .idle
	var isSettingDefaultBrowser = false
	let versionDescription: String
	let bundleIdentifier: String
	private let bundle: Bundle
	private let defaultBrowserClient: NavigatorDefaultBrowserClient
	private let executeImport: ExecuteImport
	private let onImportEvent: (BrowserImportEvent) -> Void
	private let onImportFailure: (BrowserImportSource) -> Void
	private let onImportedSnapshot: (ImportedBrowserSnapshot) -> Void
	private let onOpenImportedBookmarks: () -> Void
	private let onOpenImportedHistory: () -> Void
	private var inFlightImportPreview = BrowserImportPreview.empty
	private var inFlightImportedProfileIDs = Set<String>()

	convenience init() {
		self.init(bundle: .main)
	}

	init(
		bundle: Bundle,
		defaultBrowserClient: NavigatorDefaultBrowserClient? = nil,
		browserImportCoordinator: BrowserImportCoordinator = .live(
			homeDirectory: FileManager.default.homeDirectoryForCurrentUser
		),
		executeImport: ExecuteImport? = nil,
		onImportEvent: @escaping (BrowserImportEvent) -> Void = { _ in },
		onImportFailure: @escaping (BrowserImportSource) -> Void = { _ in },
		onImportedSnapshot: @escaping (ImportedBrowserSnapshot) -> Void = { _ in },
		onOpenImportedBookmarks: @escaping () -> Void = {},
		onOpenImportedHistory: @escaping () -> Void = {}
	) {
		self.bundle = bundle
		let resolvedDefaultBrowserClient = defaultBrowserClient ?? .live
		self.defaultBrowserClient = resolvedDefaultBrowserClient
		self.onImportEvent = onImportEvent
		self.onImportFailure = onImportFailure
		self.onImportedSnapshot = onImportedSnapshot
		self.onOpenImportedBookmarks = onOpenImportedBookmarks
		self.onOpenImportedHistory = onOpenImportedHistory
		if let executeImport {
			self.executeImport = executeImport
		}
		else {
			self.executeImport = { selection in
				browserImportCoordinator.streamImport(for: selection)
			}
		}
		versionDescription = Self.versionDescription(bundle: bundle)
		bundleIdentifier = bundle.bundleIdentifier ?? Self.noneValue
		defaultBrowserStatus = Self.resolveDefaultBrowserStatus(
			bundleIdentifier: bundle.bundleIdentifier,
			defaultBrowserClient: resolvedDefaultBrowserClient
		)
		automaticallyChecksForUpdates = storedAutomaticallyChecksForUpdates
	}

	deinit {}

	var defaultBrowserTitle: String {
		String(localized: .navigatorSettingsDefaultBrowserTitle)
	}

	var defaultBrowserDescription: String {
		switch defaultBrowserStatus {
		case .readyToSet:
			return String(localized: .navigatorSettingsDefaultBrowserDescription)
		case .currentDefault:
			return String(localized: .navigatorSettingsDefaultBrowserEnabledDescription)
		case .updateFailed:
			return String(localized: .navigatorSettingsDefaultBrowserDescription)
		}
	}

	var defaultBrowserActionTitle: String {
		String(localized: .navigatorSettingsDefaultBrowserAction)
	}

	var updatesTitle: String {
		String(localized: "navigator.settings.updates.title")
	}

	var updatesDescription: String {
		String(localized: "navigator.settings.updates.description")
	}

	var automaticallyCheckForUpdatesTitle: String {
		String(localized: "navigator.settings.updates.automaticCheck.action")
	}

	var browserImportTitle: String {
		String(localized: .navigatorSettingsImportTitle)
	}

	var browserImportDescription: String {
		String(localized: .navigatorSettingsImportDescription)
	}

	var importChromeActionTitle: String {
		String(localized: .navigatorSettingsImportChromeAction)
	}

	var importArcActionTitle: String {
		String(localized: .navigatorSettingsImportArcAction)
	}

	var importSafariActionTitle: String {
		String(localized: .navigatorSettingsImportSafariAction)
	}

	var openImportedBookmarksActionTitle: String {
		String(localized: .navigatorSettingsImportOpenBookmarksAction)
	}

	var openImportedHistoryActionTitle: String {
		String(localized: .navigatorSettingsImportOpenHistoryAction)
	}

	var canOpenImportedBookmarks: Bool {
		latestImportRecord?.snapshot.importedBookmarks.isEmpty == false
	}

	var canOpenImportedHistory: Bool {
		latestImportRecord?.snapshot.importedHistoryEntries.isEmpty == false
	}

	var importSummaryText: String {
		switch browserImportStatus {
		case .idle:
			guard let latestImportRecord else {
				return String(localized: .navigatorSettingsImportSummaryNone)
			}
			return Self.importSummaryText(for: latestImportRecord)
		case .importing(let source):
			return Self.importingSummaryText(
				for: source,
				preview: inFlightImportPreview
			)
		case .completed(let source, let preview):
			return Self.importSummaryText(
				for: ImportedBrowserLibraryRecord(
					snapshot: ImportedBrowserSnapshot(source: source, profiles: []),
					importedAt: Date.distantPast
				),
				overridePreview: preview,
				overrideSourceDisplayName: source.displayName
			)
		case .failed(let message):
			return message
		}
	}

	var showsImportError: Bool {
		if case .failed = browserImportStatus {
			return true
		}
		return false
	}

	var isImporting: Bool {
		if case .importing = browserImportStatus {
			return true
		}
		return false
	}

	var browserImportIndicatorState: NavigatorBrowserImportIndicatorState? {
		switch browserImportStatus {
		case .importing:
			return .importing
		case .completed:
			return .completed
		case .idle, .failed:
			return nil
		}
	}

	var canSetAsDefaultBrowser: Bool {
		defaultBrowserStatus != .currentDefault && bundleIdentifier != Self.noneValue && isSettingDefaultBrowser == false
	}

	var showsDefaultBrowserError: Bool {
		false
	}

	func invalidate() {}

	func refreshDefaultBrowserStatus() {
		defaultBrowserStatus = Self.resolveDefaultBrowserStatus(
			bundleIdentifier: normalizedBundleIdentifier,
			defaultBrowserClient: defaultBrowserClient
		)
	}

	func setAsDefaultBrowser() async {
		guard isSettingDefaultBrowser == false else { return }
		guard let normalizedBundleIdentifier else {
			defaultBrowserStatus = .updateFailed
			return
		}

		isSettingDefaultBrowser = true
		defer {
			isSettingDefaultBrowser = false
		}

		do {
			try await defaultBrowserClient.setAsDefaultBrowser(bundle)
			defaultBrowserStatus = Self.resolveDefaultBrowserStatus(
				bundleIdentifier: normalizedBundleIdentifier,
				defaultBrowserClient: defaultBrowserClient
			)
		}
		catch {
			defaultBrowserStatus = .updateFailed
		}
	}

	func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
		guard automaticallyChecksForUpdates != enabled else { return }
		automaticallyChecksForUpdates = enabled
		$storedAutomaticallyChecksForUpdates.withLock { value in
			value = enabled
		}
	}

	func importFromChrome() {
		importFromBrowser(.chrome)
	}

	func importFromArc() {
		importFromBrowser(.arc)
	}

	func importFromSafari() {
		importFromBrowser(.safari)
	}

	func openImportedBookmarks() {
		guard canOpenImportedBookmarks else { return }
		onOpenImportedBookmarks()
	}

	func openImportedHistory() {
		guard canOpenImportedHistory else { return }
		onOpenImportedHistory()
	}

	func refreshImportStatus() {
		if case .failed = browserImportStatus {
			return
		}
		if case .importing = browserImportStatus {
			return
		}
		if let latestImportRecord {
			browserImportStatus = .completed(
				latestImportRecord.snapshot.source,
				latestImportRecord.snapshot.preview
			)
		}
		else {
			browserImportStatus = .idle
		}
	}

	private static func versionDescription(bundle: Bundle) -> String {
		let shortVersion = normalized(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
		let buildNumber = normalized(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)

		switch (shortVersion, buildNumber) {
		case let (.some(shortVersion), .some(buildNumber)):
			return "\(shortVersion) (\(buildNumber))"
		case let (.some(shortVersion), nil):
			return shortVersion
		case let (nil, .some(buildNumber)):
			return buildNumber
		case (nil, nil):
			return noneValue
		}
	}

	private static func normalized(_ value: String?) -> String? {
		guard let value else { return nil }
		let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmedValue.isEmpty ? nil : trimmedValue
	}

	private static func resolveDefaultBrowserStatus(
		bundleIdentifier: String?,
		defaultBrowserClient: NavigatorDefaultBrowserClient,
		failedUpdateFallback: NavigatorDefaultBrowserStatus = .readyToSet
	) -> NavigatorDefaultBrowserStatus {
		guard let normalizedBundleIdentifier = normalized(bundleIdentifier) else {
			return failedUpdateFallback
		}

		return defaultBrowserClient.isDefaultBrowser(normalizedBundleIdentifier) ? .currentDefault : failedUpdateFallback
	}

	private var normalizedBundleIdentifier: String? {
		Self.normalized(bundleIdentifier == Self.noneValue ? nil : bundleIdentifier)
	}

	private var latestImportRecord: ImportedBrowserLibraryRecord? {
		$importedBrowserLibrary.withLock { library in
			library.latestRecord
		}
	}

	private static let defaultImportDataKinds: [BrowserImportDataKind] = [
		.tabs,
		.bookmarks,
	]

	private func importFromBrowser(_ source: BrowserImportSource) {
		guard isImporting == false else { return }
		browserImportStatus = .importing(source)
		resetInFlightImportPreview()
		let selection = BrowserImportSelection(
			source: source,
			profileIDs: [],
			dataKinds: Self.defaultImportDataKinds,
			conflictMode: .merge
		)
		let importEvents = executeImport(selection)
		Task { [weak self, importEvents, source] in
			do {
				for try await event in importEvents {
					await MainActor.run {
						self?.handleImportEvent(event)
					}
				}
			}
			catch {
				await MainActor.run {
					self?.finishImport(.failure(error), source: source)
				}
			}
		}
	}

	private func handleImportEvent(_ event: BrowserImportEvent) {
		onImportEvent(event)
		switch event {
		case .started:
			resetInFlightImportPreview()
		case .profileImported(_, let profile):
			mergeInFlightImportPreview(with: profile)
		case .finished(let snapshot):
			finishImport(.success(snapshot), source: snapshot.source)
		}
	}

	private func finishImport(
		_ result: Result<ImportedBrowserSnapshot, Error>,
		source: BrowserImportSource
	) {
		resetInFlightImportPreview()
		switch result {
		case .success(let snapshot):
			let importedAt = now
			$importedBrowserLibrary.withLock { library in
				library = library.replacingRecord(
					for: source,
					with: snapshot,
					importedAt: importedAt
				)
			}
			onImportedSnapshot(snapshot)
			browserImportStatus = .completed(source, snapshot.preview)
		case .failure(let error):
			onImportFailure(source)
			browserImportStatus = .failed(error.localizedDescription)
		}
	}

	private func mergeInFlightImportPreview(with profile: ImportedBrowserProfile) {
		let isNewProfile = inFlightImportedProfileIDs.insert(profile.id).inserted
		inFlightImportPreview = BrowserImportPreview(
			workspaceCount: inFlightImportPreview.workspaceCount + (isNewProfile ? 1 : 0),
			tabGroupCount: inFlightImportPreview.tabGroupCount + profile.windows.reduce(0) { $0 + $1.tabGroups.count },
			tabCount: inFlightImportPreview.tabCount + profile.importedTabs.count,
			bookmarkFolderCount: inFlightImportPreview.bookmarkFolderCount + profile.bookmarkFolders
				.reduce(0) { $0 + $1.recursiveFolderCount },
			bookmarkCount: inFlightImportPreview.bookmarkCount + profile.bookmarkFolders
				.reduce(0) { $0 + $1.recursiveBookmarkCount },
			historyEntryCount: inFlightImportPreview.historyEntryCount + profile.historyEntries.count
		)
	}

	private func resetInFlightImportPreview() {
		inFlightImportPreview = .empty
		inFlightImportedProfileIDs.removeAll(keepingCapacity: true)
	}

	private static func importSummaryText(
		for record: ImportedBrowserLibraryRecord,
		overridePreview: BrowserImportPreview? = nil,
		overrideSourceDisplayName: String? = nil
	) -> String {
		let preview = overridePreview ?? record.snapshot.preview
		let sourceDisplayName = overrideSourceDisplayName ?? record.snapshot.source.displayName
		return [
			"\(String(localized: .navigatorSettingsImportSummaryLatest)): \(sourceDisplayName)",
			"\(String(localized: .navigatorSettingsImportSummaryProfiles)): \(preview.workspaceCount)",
			"\(String(localized: .navigatorSettingsImportSummaryTabs)): \(preview.tabCount)",
			"\(String(localized: .navigatorSettingsImportSummaryBookmarks)): \(preview.bookmarkCount)",
			"\(String(localized: .navigatorSettingsImportSummaryHistory)): \(preview.historyEntryCount)",
		].joined(separator: "\n")
	}

	private static func importingSummaryText(
		for source: BrowserImportSource,
		preview: BrowserImportPreview
	) -> String {
		let importingTitle = "\(String(localized: .navigatorSettingsImportSummaryImporting)) \(source.displayName)"
		guard preview != .empty else { return importingTitle }
		return [
			importingTitle,
			"\(String(localized: .navigatorSettingsImportSummaryProfiles)): \(preview.workspaceCount)",
			"\(String(localized: .navigatorSettingsImportSummaryTabs)): \(preview.tabCount)",
			"\(String(localized: .navigatorSettingsImportSummaryBookmarks)): \(preview.bookmarkCount)",
			"\(String(localized: .navigatorSettingsImportSummaryHistory)): \(preview.historyEntryCount)",
		].joined(separator: "\n")
	}

	private static let noneValue = "-"
}
