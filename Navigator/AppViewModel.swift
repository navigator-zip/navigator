import BrowserActionBar
import BrowserSidebar
import BrowserView
import Foundation
import ModelKit
import Observation
import OverlayView
import Vendors

enum AppViewModelSessionPersistence {
	case sharedRestorable
	case sharedWindowSelection

	var restoresPersistedTabs: Bool {
		switch self {
		case .sharedRestorable:
			true
		case .sharedWindowSelection:
			false
		}
	}

	var persistsSelectedTab: Bool {
		switch self {
		case .sharedRestorable:
			true
		case .sharedWindowSelection:
			false
		}
	}
}

@MainActor
@Observable
final class AppViewModel {
	@ObservationIgnored @Dependency(\.date.now) private var now
	@ObservationIgnored @Shared(.navigatorStoredBrowserTabs) private var storedBrowserTabs: StoredBrowserTabCollection
	@ObservationIgnored @Shared(
		.navigatorStoredBrowserTabSelection
	) private var storedBrowserTabSelection: StoredBrowserTabSelection
	@ObservationIgnored @Shared(
		.navigatorImportedBrowserLibrary
	) private var importedBrowserLibrary: ImportedBrowserLibrary

	let sidebarWidth: Double
	let sidebarViewModel: BrowserSidebarViewModel
	let sidebarPresentation: BrowserSidebarPresentation
	let browserActionBarViewModel: BrowserActionBarViewModel
	let sidebarChromeViewModel: BrowserChromeViewModel
	let sharedTabCollection: BrowserSidebarTabCollection
	var toast: OverlayViewModel?
	var toastTitle: LocalizedStringResource = .navigatorToastCopyCurrentTabURLTitle
	var toastBody: String?
	private let sessionPersistence: AppViewModelSessionPersistence
	private let defaultInitialAddress: String
	private var streamingImportState: StreamingImportState?
	private var isStreamingImportSideEffectsSuspended = false
	private var hasPendingTabPersistence = false
	private var activeToastID: UUID?
	private(set) var activeSpaceID = StoredBrowserTabCollection.defaultSpaceID
	private static let globalPinnedSpaceID = "global-pinned-tabs"

	private enum StreamingImportStyle {
		static let applyBatchSize = 40
	}

	private enum ToastStyle {
		static let duration: Duration = .seconds(4)
	}

	init(
		initialAddress: String = "https://navigator.zip",
		sidebarWidth: Double = NavigatorSidebarWidth.default,
		sessionPersistence: AppViewModelSessionPersistence = .sharedRestorable,
		sharedTabCollection: BrowserSidebarTabCollection? = nil,
		initialSelectedTabID: BrowserTabID? = nil
	) {
		self.sessionPersistence = sessionPersistence
		defaultInitialAddress = initialAddress
		let sharedTabCollection = sharedTabCollection ?? BrowserSidebarTabCollection(initialAddress: initialAddress)
		self.sharedTabCollection = sharedTabCollection
		let sidebarViewModel = BrowserSidebarViewModel(
			tabCollection: sharedTabCollection,
			defaultNewTabAddress: initialAddress,
			initialSelectedTabID: initialSelectedTabID ?? sharedTabCollection.tabs.first?.id,
			newTabInsertionBehavior: sessionPersistence == .sharedWindowSelection ? .append : .afterSelectedTab,
			actions: Self.noopSidebarActions()
		)
		self.sidebarViewModel = sidebarViewModel
		self.sidebarPresentation = BrowserSidebarPresentation()
		self.sidebarWidth = sidebarWidth
		self.sidebarChromeViewModel = BrowserChromeViewModel(
			geometry: .init(sidebarWidth: CGFloat(sidebarWidth)),
			workItemScheduler: BrowserChromeViewModel.defaultWorkItemScheduler,
			sidebarPresentation: self.sidebarPresentation
		)
		self.browserActionBarViewModel = BrowserActionBarViewModel(
			onOpenCurrentTab: { url in
				sidebarViewModel.navigateSelectedTab(to: url)
			},
			onOpenNewTab: { url in
				sidebarViewModel.openNewTab(with: url)
			}
		)
		if sessionPersistence.restoresPersistedTabs {
			let restoredStoredTabs = hydrateStoredTabsIfNeeded()
			if !restoredStoredTabs {
				hydrateImportedTabsIfNeeded()
			}
		}
		syncSidebarSpacePages()
		observeSidebarTabState()
		if sessionPersistence.restoresPersistedTabs {
			persistCurrentTabs()
		}
	}

	deinit {}

	private static func noopSidebarActions() -> BrowserSidebarActions {
		BrowserSidebarActions(
			onGoBack: { _ in },
			onGoForward: { _ in },
			onReload: { _ in },
			onSubmitAddress: { _, _ in },
			navigationState: { _ in .idle }
		)
	}

	var browserActionBarCommandActions: BrowserActionBarCommandActions {
		BrowserActionBarCommandActions(
			openLocationBar: { [weak self] in
				self?.presentLocationActionBar()
			},
			openNewTabBar: { [weak self] in
				self?.presentNewTabActionBar()
			}
		)
	}

	func presentLocationActionBar() {
		let currentURL = sidebarViewModel.selectedTabCurrentURL ?? sidebarViewModel.addressText
		browserActionBarViewModel.presentCurrentTab(url: currentURL)
	}

	func presentNewTabActionBar() {
		browserActionBarViewModel.presentNewTab()
	}

	func presentToast(title: LocalizedStringResource) {
		presentToast(title: title, body: String?.none)
	}

	func presentToast(title: LocalizedStringResource, body: LocalizedStringResource) {
		presentToast(title: title, body: String(localized: body))
	}

	func presentToast(title: LocalizedStringResource, body: String?) {
		let toastID = UUID()
		activeToastID = toastID
		toast = nil
		toastTitle = title
		toastBody = body
		toast = OverlayViewModel(
			style: .toast(duration: ToastStyle.duration)
		) { [weak self] in
			guard let self, self.activeToastID == toastID else { return }
			self.toast = nil
			self.toastBody = nil
		}
	}

	func openExternalURLs(_ urlStrings: [String]) {
		let resolvedURLStrings = urlStrings.filter { $0.isEmpty == false }
		guard let firstURLString = resolvedURLStrings.first else { return }

		sidebarViewModel.navigateSelectedTab(to: firstURLString)

		for urlString in resolvedURLStrings.dropFirst() {
			sidebarViewModel.openNewTab(with: urlString)
		}
	}

	func openIncomingURLsInNewTabs(_ urlStrings: [String]) {
		let resolvedURLStrings = urlStrings.filter { $0.isEmpty == false }
		guard resolvedURLStrings.isEmpty == false else { return }

		for urlString in resolvedURLStrings {
			sidebarViewModel.openNewTab(with: urlString)
		}
	}

	var spaces: [StoredBrowserSpace] {
		let storedTabs = $storedBrowserTabs.withLock { value in value }
		return storedTabs.spaces
			.filter { $0.id != Self.globalPinnedSpaceID }
			.sorted(by: { $0.orderKey < $1.orderKey })
	}

	@discardableResult
	func createSpace(name: String = "", initialURL: String? = nil) -> String {
		persistCurrentTabs()
		let createdSpaceID = UUID().uuidString
		let resolvedInitialURL = initialURL ?? defaultInitialAddress
		let createdTabID = UUID()
		activeSpaceID = createdSpaceID
		var collectionID = StoredBrowserTabCollection.defaultCollectionID
		$storedBrowserTabs.withLock { storedTabs in
			let existingSpaces = storedTabs.spaces.filter { $0.id != createdSpaceID }
			let nextSpaces = existingSpaces + [
				StoredBrowserSpace(
					id: createdSpaceID,
					name: name,
					orderKey: nextSpaceOrderKey(from: existingSpaces),
					selectedTabID: createdTabID
				),
			]
			let existingTabs = storedTabs.tabs.filter { $0.spaceID != createdSpaceID }
			let createdTab = StoredBrowserTab(
				id: createdTabID,
				objectVersion: 1,
				orderKey: Self.storedOrderKey(for: 0),
				spaceID: createdSpaceID,
				isPinned: false,
				url: resolvedInitialURL,
				title: nil,
				historyEntries: [
					StoredBrowserHistoryEntry(
						url: resolvedInitialURL,
						title: nil
					),
				],
				currentHistoryIndex: 0
			)
			storedTabs = StoredBrowserTabCollection(
				storageVersion: StoredBrowserTabCollection.currentVersion,
				collectionID: storedTabs.collectionID,
				hasStoredState: true,
				activeSpaceID: createdSpaceID,
				spaces: nextSpaces,
				tabs: orderedTabs(
					tabs: existingTabs + [createdTab],
					spaces: nextSpaces
				)
			)
			collectionID = storedTabs.collectionID
		}
		let tabsForNewSpace = $storedBrowserTabs.withLock { storedTabs in
			Self.visibleTabs(for: createdSpaceID, from: storedTabs.tabs)
		}
		sidebarViewModel.restoreTabs(
			tabsForNewSpace,
			selectedTabID: createdTabID,
			activeSpacePageID: createdSpaceID
		)
		updateStoredSelection(
			collectionID: collectionID,
			selectedSpaceID: createdSpaceID,
			selectedTabID: createdTabID
		)
		persistCurrentTabs()
		syncSidebarSpacePages()
		return createdSpaceID
	}

	func switchSpace(to spaceID: String) {
		persistCurrentTabs()
		let storedTabs = $storedBrowserTabs.withLock { value in value }
		guard storedTabs.spaces.contains(where: { $0.id == spaceID }) else { return }
		activeSpaceID = spaceID
		let tabsForSpace = Self.visibleTabs(for: spaceID, from: storedTabs.tabs)
		let spaceSelection = storedTabs.spaces.first(where: { $0.id == spaceID })?.selectedTabID
		let storedSelection = $storedBrowserTabSelection.withLock { value in value }
		let selectedTabID: UUID? = if storedSelection.collectionID == storedTabs.collectionID,
		                              storedSelection.selectedSpaceID == spaceID {
			storedSelection.selectedTabID
		}
		else {
			spaceSelection
		}
		sidebarViewModel.restoreTabs(
			tabsForSpace,
			selectedTabID: selectedTabID,
			activeSpacePageID: spaceID
		)
		persistCurrentTabs()
		syncSidebarSpacePages()
	}

	func renameSpace(id: String, name: String) {
		$storedBrowserTabs.withLock { storedTabs in
			let updatedSpaces = storedTabs.spaces.map { space in
				space.id == id
					? StoredBrowserSpace(
						id: space.id,
						name: name,
						orderKey: space.orderKey,
						selectedTabID: space.selectedTabID
					)
					: space
			}
			storedTabs = StoredBrowserTabCollection(
				storageVersion: StoredBrowserTabCollection.currentVersion,
				collectionID: storedTabs.collectionID,
				hasStoredState: storedTabs.hasStoredState,
				activeSpaceID: storedTabs.activeSpaceID,
				spaces: updatedSpaces,
				tabs: storedTabs.tabs
			)
		}
		syncSidebarSpacePages()
	}

	func deleteSpace(id: String) {
		persistCurrentTabs()
		let storedTabs = $storedBrowserTabs.withLock { value in value }
		guard storedTabs.spaces.contains(where: { $0.id == id }) else { return }
		let remainingSpaces = storedTabs.spaces.filter { $0.id != id }
		let fallbackSpaceID = remainingSpaces.first?.id ?? StoredBrowserTabCollection.defaultSpaceID
		let nextSpaces = remainingSpaces.isEmpty
			? [
				StoredBrowserSpace(
					id: fallbackSpaceID,
					orderKey: "00000000"
				),
			]
			: remainingSpaces
		let nextTabs = storedTabs.tabs.filter { $0.spaceID != id }
		let nextActiveSpaceID = activeSpaceID == id ? fallbackSpaceID : activeSpaceID
		activeSpaceID = nextActiveSpaceID
		$storedBrowserTabs.withLock { storedTabs in
			storedTabs = StoredBrowserTabCollection(
				storageVersion: StoredBrowserTabCollection.currentVersion,
				collectionID: storedTabs.collectionID,
				hasStoredState: true,
				activeSpaceID: nextActiveSpaceID,
				spaces: nextSpaces,
				tabs: nextTabs
			)
		}
		let tabsForActiveSpace = Self.visibleTabs(
			for: nextActiveSpaceID,
			from: nextTabs
		)
		if tabsForActiveSpace.isEmpty {
			let selectedTabID = replaceActiveSpaceTabsWithSingleURL(defaultInitialAddress)
			updateStoredSelection(
				collectionID: storedTabs.collectionID,
				selectedSpaceID: nextActiveSpaceID,
				selectedTabID: selectedTabID
			)
		}
		else {
			sidebarViewModel.restoreTabs(
				tabsForActiveSpace,
				selectedTabID: nextSpaces.first(where: { $0.id == nextActiveSpaceID })?.selectedTabID,
				activeSpacePageID: nextActiveSpaceID
			)
		}
		persistCurrentTabs()
		syncSidebarSpacePages()
	}

	func importBrowserSnapshot(_ snapshot: ImportedBrowserSnapshot) {
		persistImportedBrowserSnapshot(snapshot)
		applyImportedTabs(from: snapshot)
	}

	func beginStreamingBrowserImport(from source: BrowserImportSource) {
		setStreamingImportSideEffectsSuspended(true)
		streamingImportState = StreamingImportState(
			source: source,
			hasFinishedLoadingSnapshot: false,
			isDrainingTabs: false,
			pendingImportedSpaces: [],
			nextPendingImportedTabIndex: 0
		)
	}

	func importBrowserProfileChunk(
		_ profile: ImportedBrowserProfile,
		from source: BrowserImportSource
	) {
		if streamingImportState?.source != source {
			beginStreamingBrowserImport(from: source)
		}
		enqueueImportedTabs(from: profile)
	}

	func finishStreamingBrowserImport(_ snapshot: ImportedBrowserSnapshot) {
		persistImportedBrowserSnapshot(snapshot)
		guard streamingImportState?.source == snapshot.source else {
			appendImportedTabs(from: snapshot, preservesSelection: true)
			setStreamingImportSideEffectsSuspended(false)
			return
		}
		streamingImportState?.hasFinishedLoadingSnapshot = true
		scheduleStreamingImportDrainIfNeeded()
		finalizeStreamingImportIfPossible()
	}

	func cancelStreamingBrowserImport(from source: BrowserImportSource) {
		guard var streamingImportState, streamingImportState.source == source else { return }
		if streamingImportState.hasPendingImportedSpaces {
			let pendingImportedSpaces = Array(
				streamingImportState.pendingImportedSpaces[
					streamingImportState.nextPendingImportedTabIndex...
				]
			)
			streamingImportState.pendingImportedSpaces.removeAll(keepingCapacity: true)
			streamingImportState.nextPendingImportedTabIndex = 0
			self.streamingImportState = streamingImportState
			for importedSpace in pendingImportedSpaces {
				appendImportedSpaceBatch(
					importedSpace,
					allowsSelectionUpdate: false
				)
			}
			syncSidebarSpacePages()
		}
		self.streamingImportState = nil
		setStreamingImportSideEffectsSuspended(false)
	}

	func openImportedBookmarks() {
		guard let latestSnapshot else { return }
		openExternalURLs(
			latestSnapshot.importedBookmarks.map(\.url)
		)
	}

	func openImportedHistory(limit: Int = 20) {
		guard let latestSnapshot else { return }
		let recentURLs = latestSnapshot.importedHistoryEntries
			.sorted(by: { $0.visitedAt > $1.visitedAt })
			.prefix(limit)
			.map(\.url)
		openExternalURLs(Array(recentURLs))
	}

	private var latestSnapshot: ImportedBrowserSnapshot? {
		$importedBrowserLibrary.withLock { library in
			library.latestRecord?.snapshot
		}
	}

	private func hydrateImportedTabsIfNeeded() {
		guard let latestSnapshot else { return }
		applyImportedTabs(from: latestSnapshot)
	}

	private func hydrateStoredTabsIfNeeded() -> Bool {
		let storedTabs = $storedBrowserTabs.withLock { value in value }
		guard storedTabs.hasStoredState else { return false }
		let storedSelection = $storedBrowserTabSelection.withLock { value in value }
		let resolvedActiveSpaceID = resolvedActiveSpaceID(
			storedTabs: storedTabs,
			storedSelection: storedSelection
		)
		activeSpaceID = resolvedActiveSpaceID
		let tabsForActiveSpace = Self.visibleTabs(
			for: resolvedActiveSpaceID,
			from: storedTabs.tabs
		)
		let selectedTabID = resolvedSelectedTabID(
			storedTabs: storedTabs,
			storedSelection: storedSelection,
			activeSpaceID: resolvedActiveSpaceID
		)
		sidebarViewModel.restoreTabs(
			tabsForActiveSpace,
			selectedTabID: selectedTabID,
			activeSpacePageID: resolvedActiveSpaceID
		)
		return true
	}

	private func observeSidebarTabState() {
		_ = sidebarViewModel.addTabConfigurationChangeObserver { [weak self] in
			self?.handleSidebarTabConfigurationChange()
		}
	}

	private func handleSidebarTabConfigurationChange() {
		if isStreamingImportSideEffectsSuspended {
			hasPendingTabPersistence = true
			return
		}
		persistCurrentTabs()
	}

	private func persistCurrentTabs() {
		let storedTabsSnapshot = $storedBrowserTabs.withLock { value in value }
		let previousTabsByID = Dictionary(
			uniqueKeysWithValues: Self.visibleTabs(for: activeSpaceID, from: storedTabsSnapshot.tabs).map { tab in
				(tab.id, tab)
			}
		)
		var nextPinnedOrderIndex = 0
		var nextUnpinnedOrderIndex = 0
		let nextTabs = sidebarViewModel.tabs.enumerated().map { _, tab in
			let orderKey: String
			if tab.isPinned {
				orderKey = Self.storedOrderKey(for: nextPinnedOrderIndex)
				nextPinnedOrderIndex += 1
			}
			else {
				orderKey = Self.storedOrderKey(for: nextUnpinnedOrderIndex)
				nextUnpinnedOrderIndex += 1
			}
			let previousTab = previousTabsByID[tab.id]
			let persistedURL = persistedURL(for: tab)
			let persistedTitle = persistedTitle(for: tab)
			let persistedFaviconURL = persistedFaviconURL(for: tab)
			let persistedHistoryEntries = persistedHistoryEntries(for: tab)
			let persistedCurrentHistoryIndex = persistedCurrentHistoryIndex(for: tab)
			let isUnchanged = previousTab?.orderKey == orderKey
				&& previousTab?.url == persistedURL
				&& previousTab?.title == persistedTitle
				&& previousTab?.faviconURL == persistedFaviconURL
				&& previousTab?.historyEntries == persistedHistoryEntries
				&& previousTab?.currentHistoryIndex == persistedCurrentHistoryIndex
				&& previousTab?.isPinned == tab.isPinned
				&& previousTab?.isArchived == false
			let objectVersion: Int = if let previousTab {
				isUnchanged ? previousTab.objectVersion : previousTab.objectVersion + 1
			}
			else {
				1
			}

			return StoredBrowserTab(
				id: tab.id,
				objectVersion: objectVersion,
				orderKey: orderKey,
				spaceID: tab.isPinned ? Self.globalPinnedSpaceID : activeSpaceID,
				parentObjectID: previousTab?.parentObjectID,
				isArchived: false,
				isPinned: tab.isPinned,
				url: persistedURL,
				title: persistedTitle,
				faviconURL: persistedFaviconURL,
				historyEntries: persistedHistoryEntries,
				currentHistoryIndex: persistedCurrentHistoryIndex
			)
		}

		let collectionID = storedTabsSnapshot.collectionID
		let otherSpaceTabs = storedTabsSnapshot.tabs.filter {
			$0.spaceID != activeSpaceID && $0.spaceID != Self.globalPinnedSpaceID
		}
		let nextSelectedTabID = sidebarViewModel.selectedTabID
		let nextSpaces = updatedSpaces(
			from: storedTabsSnapshot,
			activeSpaceID: activeSpaceID,
			selectedTabID: nextSelectedTabID
		)
		let mergedTabs = orderedTabs(
			tabs: otherSpaceTabs + nextTabs,
			spaces: nextSpaces
		)
		$storedBrowserTabs.withLock { storedTabs in
			storedTabs = StoredBrowserTabCollection(
				storageVersion: StoredBrowserTabCollection.currentVersion,
				collectionID: collectionID,
				hasStoredState: true,
				activeSpaceID: activeSpaceID,
				spaces: nextSpaces,
				tabs: mergedTabs
			)
		}
		if sessionPersistence.persistsSelectedTab {
			updateStoredSelection(
				collectionID: collectionID,
				selectedSpaceID: activeSpaceID,
				selectedTabID: nextSelectedTabID
			)
			return
		}

		let hasStoredSelection = $storedBrowserTabSelection.withLock { storedSelection in
			storedSelection.collectionID == collectionID
				&& storedSelection.selectedSpaceID == activeSpaceID
				&& nextTabs.contains(where: { $0.id == storedSelection.selectedTabID })
		}
		guard !hasStoredSelection else { return }
		updateStoredSelection(
			collectionID: collectionID,
			selectedSpaceID: activeSpaceID,
			selectedTabID: nextSelectedTabID
		)
	}

	private func resolvedHistoryEntries(for tab: BrowserTabViewModel) -> [StoredBrowserHistoryEntry] {
		let filteredEntries = tab.historyEntries.filter { entry in
			entry.url.isEmpty == false && entry.url != BrowserSessionHistoryDefaults.aboutBlankURL
		}
		if filteredEntries.isEmpty == false {
			return filteredEntries
		}
		return [
			StoredBrowserHistoryEntry(
				url: tab.currentURL,
				title: tab.pageTitle
			),
		]
	}

	private func resolvedCurrentHistoryIndex(for tab: BrowserTabViewModel) -> Int {
		let entries = resolvedHistoryEntries(for: tab)
		return min(max(0, tab.currentHistoryIndex), entries.count - 1)
	}

	private func persistedURL(for tab: BrowserTabViewModel) -> String {
		tab.isPinned ? tab.initialURL : tab.currentURL
	}

	private func persistedTitle(for tab: BrowserTabViewModel) -> String? {
		guard tab.isPinned else { return tab.pageTitle }
		return tab.currentURL == tab.initialURL ? tab.pageTitle : nil
	}

	private func persistedFaviconURL(for tab: BrowserTabViewModel) -> String? {
		guard tab.isPinned else { return tab.faviconURL }
		return tab.currentURL == tab.initialURL ? tab.faviconURL : nil
	}

	private func persistedHistoryEntries(for tab: BrowserTabViewModel) -> [StoredBrowserHistoryEntry] {
		guard tab.isPinned else { return resolvedHistoryEntries(for: tab) }
		return [
			StoredBrowserHistoryEntry(
				url: tab.initialURL,
				title: persistedTitle(for: tab)
			),
		]
	}

	private func persistedCurrentHistoryIndex(for tab: BrowserTabViewModel) -> Int {
		tab.isPinned ? 0 : resolvedCurrentHistoryIndex(for: tab)
	}

	private func persistImportedBrowserSnapshot(_ snapshot: ImportedBrowserSnapshot) {
		let importedAt = now
		$importedBrowserLibrary.withLock { library in
			library = library.replacingRecord(
				for: snapshot.source,
				with: snapshot,
				importedAt: importedAt
			)
		}
	}

	private func applyImportedTabs(from snapshot: ImportedBrowserSnapshot) {
		let importedSpaces = importedSpaceBatches(from: snapshot.profiles)
		guard importedSpaces.isEmpty == false else { return }
		var selectedTabIDBySpaceID = [String: UUID]()
		let importedSpaceMetadatas = importedSpaces.enumerated().map { index, importedSpace in
			StoredBrowserSpace(
				id: importedSpace.spaceID,
				name: importedSpace.name,
				orderKey: Self.storedOrderKey(for: index),
				selectedTabID: nil
			)
		}
		var flattenedTabs = [StoredBrowserTab]()
		var nextOrderBySpaceID = [String: Int]()
		for importedSpace in importedSpaces {
			for (index, tabSeed) in importedSpace.tabs.enumerated() {
				let tabID = UUID()
				if importedSpace.selectedIndex == index {
					selectedTabIDBySpaceID[importedSpace.spaceID] = tabID
				}
				let tabSpaceID = tabSeed.isPinned ? Self.globalPinnedSpaceID : importedSpace.spaceID
				let nextOrderIndex = nextOrderBySpaceID[tabSpaceID, default: 0]
				nextOrderBySpaceID[tabSpaceID] = nextOrderIndex + 1
				flattenedTabs.append(
					StoredBrowserTab(
						id: tabID,
						objectVersion: 1,
						orderKey: Self.storedOrderKey(for: nextOrderIndex),
						spaceID: tabSpaceID,
						isPinned: tabSeed.isPinned,
						url: tabSeed.url,
						title: tabSeed.title,
						historyEntries: [
							StoredBrowserHistoryEntry(
								url: tabSeed.url,
								title: tabSeed.title
							),
						],
						currentHistoryIndex: 0
					)
				)
			}
		}
		let hydratedSpaceMetadatas = importedSpaceMetadatas.map { space in
			StoredBrowserSpace(
				id: space.id,
				name: space.name,
				orderKey: space.orderKey,
				selectedTabID: selectedTabIDBySpaceID[space.id]
			)
		}
		let activeImportedSpace = importedSpaces.first(where: { $0.containsSelectedTab }) ?? importedSpaces[0]
		activeSpaceID = activeImportedSpace.spaceID
		let collectionID = $storedBrowserTabs.withLock { storedTabs in
			storedTabs.collectionID
		}
		let nextStoredTabs = StoredBrowserTabCollection(
			storageVersion: StoredBrowserTabCollection.currentVersion,
			collectionID: collectionID,
			hasStoredState: true,
			activeSpaceID: activeSpaceID,
			spaces: hydratedSpaceMetadatas,
			tabs: orderedTabs(
				tabs: flattenedTabs,
				spaces: hydratedSpaceMetadatas
			)
		)
		$storedBrowserTabs.withLock { storedTabs in
			storedTabs = nextStoredTabs
		}
		updateStoredSelection(
			collectionID: collectionID,
			selectedSpaceID: activeSpaceID,
			selectedTabID: selectedTabIDBySpaceID[activeSpaceID]
		)
		let tabsForActiveSpace = Self.visibleTabs(
			for: activeSpaceID,
			from: nextStoredTabs.tabs
		)
		sidebarViewModel.restoreTabs(
			tabsForActiveSpace,
			selectedTabID: selectedTabIDBySpaceID[activeSpaceID],
			activeSpacePageID: activeSpaceID
		)
		syncSidebarSpacePages()
	}

	private func appendImportedTabs(
		from snapshot: ImportedBrowserSnapshot,
		preservesSelection: Bool
	) {
		let importedSpaces = importedSpaceBatches(from: snapshot.profiles)
		guard importedSpaces.isEmpty == false else { return }
		for importedSpace in importedSpaces {
			appendImportedSpaceBatch(
				importedSpace,
				allowsSelectionUpdate: !preservesSelection
			)
		}
		syncSidebarSpacePages()
	}

	private func importedSpaceBatches(
		from profiles: [ImportedBrowserProfile]
	) -> [ImportedSpaceBatch] {
		var importedSpaces = [ImportedSpaceBatch]()
		for profile in profiles {
			for window in profile.windows {
				var windowTabs = [BrowserSidebarImportedTabSeed]()
				var selectedIndex: Int?
				for tabGroup in window.tabGroups {
					for tab in tabGroup.tabs {
						if window.selectedTabID == tab.id {
							selectedIndex = windowTabs.count
						}
						windowTabs.append(
							BrowserSidebarImportedTabSeed(
								url: tab.url,
								title: tab.title,
								isPinned: tab.isPinned
							)
						)
					}
				}
				guard windowTabs.isEmpty == false else { continue }
				let resolvedName = if window.displayName.isEmpty {
					profile.displayName
				}
				else {
					window.displayName
				}
				importedSpaces.append(
					ImportedSpaceBatch(
						spaceID: "\(snapshotScopedImportedSpacePrefix)-\(profile.id)-\(window.id)",
						name: resolvedName,
						tabs: windowTabs,
						selectedIndex: selectedIndex
					)
				)
			}
		}
		return importedSpaces
	}

	private func resolvedActiveSpaceID(
		storedTabs: StoredBrowserTabCollection,
		storedSelection: StoredBrowserTabSelection
	) -> String {
		let preferredSelectionSpaceID = if storedSelection.collectionID == storedTabs.collectionID {
			storedSelection.selectedSpaceID
		}
		else {
			storedTabs.activeSpaceID
		}
		if storedTabs.spaces.contains(where: { $0.id == preferredSelectionSpaceID }) {
			return preferredSelectionSpaceID
		}
		return storedTabs.activeSpaceID
	}

	private func resolvedSelectedTabID(
		storedTabs: StoredBrowserTabCollection,
		storedSelection: StoredBrowserTabSelection,
		activeSpaceID: String
	) -> UUID? {
		let tabsForSpace = Self.visibleTabs(for: activeSpaceID, from: storedTabs.tabs)
		let selectedFromStore: UUID? = if storedSelection.collectionID == storedTabs.collectionID,
		                                  storedSelection.selectedSpaceID == activeSpaceID {
			storedSelection.selectedTabID
		}
		else {
			storedTabs.spaces.first(where: { $0.id == activeSpaceID })?.selectedTabID
		}
		if let selectedFromStore, tabsForSpace.contains(where: { $0.id == selectedFromStore }) {
			return selectedFromStore
		}
		if let firstPinnedTabID = tabsForSpace.first(where: \.isPinned)?.id {
			return firstPinnedTabID
		}
		return tabsForSpace.first?.id
	}

	private static func tabs(
		for spaceID: String,
		from tabs: [StoredBrowserTab]
	) -> [StoredBrowserTab] {
		tabs
			.filter { $0.spaceID == spaceID }
			.sorted(by: { $0.orderKey < $1.orderKey })
	}

	private static func visibleTabs(
		for spaceID: String,
		from allTabs: [StoredBrowserTab]
	) -> [StoredBrowserTab] {
		let pinnedTabs = Self.tabs(
			for: globalPinnedSpaceID,
			from: allTabs
		)
		let spaceTabs = Self.tabs(
			for: spaceID,
			from: allTabs
		)
		return pinnedTabs + spaceTabs
	}

	private func updatedSpaces(
		from collection: StoredBrowserTabCollection,
		activeSpaceID: String,
		selectedTabID: UUID?
	) -> [StoredBrowserSpace] {
		var spaces = collection.spaces
		if let existingIndex = spaces.firstIndex(where: { $0.id == activeSpaceID }) {
			let existing = spaces[existingIndex]
			spaces[existingIndex] = StoredBrowserSpace(
				id: existing.id,
				name: existing.name,
				orderKey: existing.orderKey,
				selectedTabID: selectedTabID
			)
		}
		else {
			spaces.append(
				StoredBrowserSpace(
					id: activeSpaceID,
					orderKey: nextSpaceOrderKey(
						from: spaces
					),
					selectedTabID: selectedTabID
				)
			)
		}
		return spaces.sorted(by: { $0.orderKey < $1.orderKey })
	}

	private func orderedTabs(
		tabs: [StoredBrowserTab],
		spaces: [StoredBrowserSpace]
	) -> [StoredBrowserTab] {
		let orderBySpaceID = Dictionary(
			uniqueKeysWithValues: spaces.enumerated().map { index, space in
				(space.id, index)
			}
		)
		return tabs.sorted { lhs, rhs in
			let lhsSpaceOrder = if lhs.spaceID == Self.globalPinnedSpaceID {
				-1
			}
			else {
				orderBySpaceID[lhs.spaceID] ?? Int.max
			}
			let rhsSpaceOrder = if rhs.spaceID == Self.globalPinnedSpaceID {
				-1
			}
			else {
				orderBySpaceID[rhs.spaceID] ?? Int.max
			}
			if lhsSpaceOrder != rhsSpaceOrder {
				return lhsSpaceOrder < rhsSpaceOrder
			}
			if lhs.orderKey != rhs.orderKey {
				return lhs.orderKey < rhs.orderKey
			}
			return lhs.id.uuidString < rhs.id.uuidString
		}
	}

	private func updateStoredSelection(
		collectionID: String,
		selectedSpaceID: String,
		selectedTabID: UUID?
	) {
		$storedBrowserTabSelection.withLock { storedSelection in
			storedSelection = StoredBrowserTabSelection(
				storageVersion: StoredBrowserTabSelection.currentVersion,
				collectionID: collectionID,
				selectedSpaceID: selectedSpaceID,
				selectedTabID: selectedTabID
			)
		}
	}

	private func replaceActiveSpaceTabsWithSingleURL(_ url: String) -> UUID? {
		sidebarViewModel.replaceTabs(
			with: [url],
			selectedIndex: 0,
			activeSpacePageID: activeSpaceID
		)
		return sidebarViewModel.selectedTabID
	}

	private func nextSpaceOrderKey(from spaces: [StoredBrowserSpace]) -> String {
		Self.storedOrderKey(for: spaces.count)
	}

	private static func storedOrderKey(for index: Int) -> String {
		String(format: "%08d", index)
	}

	private var snapshotScopedImportedSpacePrefix: String {
		"imported-space"
	}

	private func syncSidebarSpacePages() {
		let storedTabs = $storedBrowserTabs.withLock { value in value }
		let pageContents = spaces.map { space in
			BrowserSidebarSpacePageContent(
				pageID: space.id,
				tabs: Self.tabs(
					for: space.id,
					from: storedTabs.tabs
				),
				selectedTabID: space.selectedTabID
			)
		}
		sidebarViewModel.configureSpacePages(
			spaces.map { space in
				BrowserSidebarSpacePage(
					id: space.id,
					title: space.name
				)
			},
			selectedPageID: activeSpaceID,
			pageContents: pageContents,
			onSelectSpacePage: { [weak self] spaceID in
				self?.switchSpace(to: spaceID)
			}
		)
	}

	private func setStreamingImportSideEffectsSuspended(_ isSuspended: Bool) {
		guard isStreamingImportSideEffectsSuspended != isSuspended else { return }
		isStreamingImportSideEffectsSuspended = isSuspended
		sidebarViewModel.setFaviconLoadingSuspended(isSuspended)
		if !isSuspended {
			flushPendingTabPersistenceIfNeeded()
		}
	}

	private func flushPendingTabPersistenceIfNeeded() {
		guard hasPendingTabPersistence else { return }
		hasPendingTabPersistence = false
		persistCurrentTabs()
	}

	private func enqueueImportedTabs(from profile: ImportedBrowserProfile) {
		let importedSpaces = importedSpaceBatches(from: [profile])
		guard importedSpaces.isEmpty == false else { return }
		streamingImportState?.pendingImportedSpaces.append(contentsOf: importedSpaces)
		scheduleStreamingImportDrainIfNeeded()
	}

	private func scheduleStreamingImportDrainIfNeeded() {
		guard var streamingImportState else { return }
		guard streamingImportState.isDrainingTabs == false else { return }
		guard streamingImportState.hasPendingImportedSpaces else { return }
		streamingImportState.isDrainingTabs = true
		self.streamingImportState = streamingImportState
		Task { @MainActor [weak self] in
			await self?.drainPendingStreamingImportTabs()
		}
	}

	private func drainPendingStreamingImportTabs() async {
		while var streamingImportState = self.streamingImportState {
			guard streamingImportState.hasPendingImportedSpaces else {
				streamingImportState.isDrainingTabs = false
				self.streamingImportState = streamingImportState
				finalizeStreamingImportIfPossible()
				return
			}

			let startIndex = streamingImportState.nextPendingImportedTabIndex
			let endIndex = min(
				startIndex + StreamingImportStyle.applyBatchSize,
				streamingImportState.pendingImportedSpaces.count
			)
			let batchSpaces = Array(
				streamingImportState.pendingImportedSpaces[startIndex..<endIndex]
			)
			streamingImportState.nextPendingImportedTabIndex = endIndex
			if streamingImportState.hasPendingImportedSpaces == false {
				streamingImportState.pendingImportedSpaces.removeAll(keepingCapacity: true)
				streamingImportState.nextPendingImportedTabIndex = 0
			}
			self.streamingImportState = streamingImportState

			for importedSpace in batchSpaces {
				appendImportedSpaceBatch(
					importedSpace,
					allowsSelectionUpdate: false
				)
			}
			syncSidebarSpacePages()
			await Task.yield()
		}
	}

	private func finalizeStreamingImportIfPossible() {
		guard let streamingImportState else { return }
		guard streamingImportState.hasFinishedLoadingSnapshot else { return }
		guard streamingImportState.hasPendingImportedSpaces == false else { return }
		guard streamingImportState.isDrainingTabs == false else { return }
		self.streamingImportState = nil
		setStreamingImportSideEffectsSuspended(false)
	}

	private func appendImportedSpaceBatch(
		_ importedSpace: ImportedSpaceBatch,
		allowsSelectionUpdate: Bool
	) {
		let appendedTabSeeds = importedSpace.tabs
		guard appendedTabSeeds.isEmpty == false else { return }
		var shouldSyncSpacePages = false
		var selectedTabIDForImportedSelection: UUID?
		var selectedIndexInBatch: Int?

		$storedBrowserTabs.withLock { storedTabs in
			var spaces = storedTabs.spaces.sorted(by: { $0.orderKey < $1.orderKey })
			let spaceIndex: Int
			if let existingIndex = spaces.firstIndex(where: { $0.id == importedSpace.spaceID }) {
				spaceIndex = existingIndex
			}
			else {
				spaceIndex = spaces.count
				spaces.append(
					StoredBrowserSpace(
						id: importedSpace.spaceID,
						name: importedSpace.name,
						orderKey: Self.storedOrderKey(for: spaceIndex)
					)
				)
				shouldSyncSpacePages = true
			}

			let existingSpaceTabs = Self.tabs(
				for: importedSpace.spaceID,
				from: storedTabs.tabs
			)
			let existingGlobalPinnedTabs = Self.tabs(
				for: Self.globalPinnedSpaceID,
				from: storedTabs.tabs
			)
			let nextUnpinnedTabOrderStart = existingSpaceTabs.count
			let nextPinnedTabOrderStart = existingGlobalPinnedTabs.count
			var nextStoredTabs = storedTabs.tabs
			var appendedTabIDs = [UUID]()
			appendedTabIDs.reserveCapacity(appendedTabSeeds.count)
			var appendedUnpinnedOffset = 0
			var appendedPinnedOffset = 0

			for (index, tabSeed) in appendedTabSeeds.enumerated() {
				let tabID = UUID()
				appendedTabIDs.append(tabID)
				let tabSpaceID = tabSeed.isPinned ? Self.globalPinnedSpaceID : importedSpace.spaceID
				let orderKey: String
				if tabSeed.isPinned {
					orderKey = Self.storedOrderKey(for: nextPinnedTabOrderStart + appendedPinnedOffset)
					appendedPinnedOffset += 1
				}
				else {
					orderKey = Self.storedOrderKey(for: nextUnpinnedTabOrderStart + appendedUnpinnedOffset)
					appendedUnpinnedOffset += 1
				}
				nextStoredTabs.append(
					StoredBrowserTab(
						id: tabID,
						objectVersion: 1,
						orderKey: orderKey,
						spaceID: tabSpaceID,
						isPinned: tabSeed.isPinned,
						url: tabSeed.url,
						title: tabSeed.title,
						historyEntries: [
							StoredBrowserHistoryEntry(
								url: tabSeed.url,
								title: tabSeed.title
							),
						],
						currentHistoryIndex: 0
					)
				)
			}

			if allowsSelectionUpdate,
			   let importedSelectedIndex = importedSpace.selectedIndex,
			   appendedTabIDs.indices.contains(importedSelectedIndex) {
				selectedTabIDForImportedSelection = appendedTabIDs[importedSelectedIndex]
				selectedIndexInBatch = importedSelectedIndex
				let existingSpace = spaces[spaceIndex]
				spaces[spaceIndex] = StoredBrowserSpace(
					id: existingSpace.id,
					name: existingSpace.name,
					orderKey: existingSpace.orderKey,
					selectedTabID: selectedTabIDForImportedSelection
				)
			}

			storedTabs = StoredBrowserTabCollection(
				storageVersion: StoredBrowserTabCollection.currentVersion,
				collectionID: storedTabs.collectionID,
				hasStoredState: true,
				activeSpaceID: storedTabs.activeSpaceID,
				spaces: spaces,
				tabs: orderedTabs(
					tabs: nextStoredTabs,
					spaces: spaces
				)
			)
		}

		if shouldSyncSpacePages {
			syncSidebarSpacePages()
		}
		if importedSpace.spaceID == activeSpaceID {
			sidebarViewModel.appendImportedTabs(
				appendedTabSeeds,
				selectedIndexInBatch: selectedIndexInBatch
			)
		}
		else if appendedTabSeeds.contains(where: \.isPinned) {
			sidebarViewModel.appendImportedTabs(
				appendedTabSeeds.filter(\.isPinned),
				selectedIndexInBatch: nil
			)
		}
	}
}

private struct StreamingImportState {
	let source: BrowserImportSource
	var hasFinishedLoadingSnapshot: Bool
	var isDrainingTabs: Bool
	var pendingImportedSpaces: [ImportedSpaceBatch]
	var nextPendingImportedTabIndex: Int

	var hasPendingImportedSpaces: Bool {
		nextPendingImportedTabIndex < pendingImportedSpaces.count
	}
}

private struct ImportedSpaceBatch {
	let spaceID: String
	let name: String
	let tabs: [BrowserSidebarImportedTabSeed]
	let selectedIndex: Int?

	var containsSelectedTab: Bool {
		selectedIndex != nil
	}
}
