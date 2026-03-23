import AppKit
import BrowserCameraKit
import CoreGraphics
import Foundation
import ModelKit
import Observation

public struct BrowserSidebarNavigationState: Equatable, Sendable {
	public let canGoBack: Bool
	public let canGoForward: Bool
	public let isLoading: Bool

	public init(
		canGoBack: Bool,
		canGoForward: Bool,
		isLoading: Bool
	) {
		self.canGoBack = canGoBack
		self.canGoForward = canGoForward
		self.isLoading = isLoading
	}

	public static let idle = BrowserSidebarNavigationState(
		canGoBack: false,
		canGoForward: false,
		isLoading: false
	)
}

public struct BrowserSidebarSpacePage: Equatable, Sendable {
	public let id: String
	public let title: String

	public init(id: String, title: String) {
		self.id = id
		self.title = title
	}
}

public struct BrowserSidebarActions {
	public let onGoBack: (BrowserTabID) -> Void
	public let onGoForward: (BrowserTabID) -> Void
	public let onReload: (BrowserTabID) -> Void
	public let onSubmitAddress: (BrowserTabID, String) -> Void
	public let navigationState: (BrowserTabID) -> BrowserSidebarNavigationState
	public let cameraControls: BrowserSidebarCameraControls

	public init(
		onGoBack: @escaping (BrowserTabID) -> Void,
		onGoForward: @escaping (BrowserTabID) -> Void,
		onReload: @escaping (BrowserTabID) -> Void,
		onSubmitAddress: @escaping (BrowserTabID, String) -> Void,
		navigationState: @escaping (BrowserTabID) -> BrowserSidebarNavigationState,
		cameraControls: BrowserSidebarCameraControls
	) {
		self.onGoBack = onGoBack
		self.onGoForward = onGoForward
		self.onReload = onReload
		self.onSubmitAddress = onSubmitAddress
		self.navigationState = navigationState
		self.cameraControls = cameraControls
	}

	public init(
		onGoBack: @escaping (BrowserTabID) -> Void,
		onGoForward: @escaping (BrowserTabID) -> Void,
		onReload: @escaping (BrowserTabID) -> Void,
		onSubmitAddress: @escaping (BrowserTabID, String) -> Void,
		navigationState: @escaping (BrowserTabID) -> BrowserSidebarNavigationState
	) {
		self.init(
			onGoBack: onGoBack,
			onGoForward: onGoForward,
			onReload: onReload,
			onSubmitAddress: onSubmitAddress,
			navigationState: navigationState,
			cameraControls: BrowserSidebarCameraControls()
		)
	}
}

@MainActor
@Observable
public final class BrowserSidebarViewModel {
	public enum NewTabInsertionBehavior: Sendable {
		case afterSelectedTab
		case append
	}

	public var addressText: String
	public private(set) var canGoBack = false
	public private(set) var canGoForward = false
	public private(set) var isLoading = false
	public private(set) var isFaviconLoadingSuspended = false
	public private(set) var tabs: [BrowserTabViewModel]
	public private(set) var selectedTabID: BrowserTabID?
	public private(set) var spacePages = [BrowserSidebarSpacePage]()
	public private(set) var selectedSpacePageID = ""
	public var selectedTabCurrentURL: String? {
		selectedTab?.currentURL
	}

	var displayedTabs: BrowserSidebarDisplayedTabs {
		tabCollection.displayedTabs()
	}

	var spacePageViewModels: [BrowserSidebarSpacePageViewModel] {
		spacePages.compactMap { spacePageViewModelsByID[$0.id] }
	}

	func allSpacePageTabIDs() -> Set<BrowserTabID> {
		Set(spacePageViewModels.flatMap { $0.tabs.map(\.id) })
	}

	public var onTabConfigurationChange: (() -> Void)? {
		get {
			legacyTabConfigurationChangeObserverID.flatMap { tabConfigurationChangeObservers[$0] }
		}
		set {
			if let existingObserverID = legacyTabConfigurationChangeObserverID {
				tabConfigurationChangeObservers.removeValue(forKey: existingObserverID)
			}

			guard let newValue else {
				legacyTabConfigurationChangeObserverID = nil
				return
			}

			let observerID = UUID()
			tabConfigurationChangeObservers[observerID] = newValue
			legacyTabConfigurationChangeObserverID = observerID
		}
	}

	private var tabConfigurationChangeObservers = [UUID: () -> Void]()
	private var viewStateChangeObservers = [UUID: () -> Void]()
	private var legacyTabConfigurationChangeObserverID: UUID?

	private var actions: BrowserSidebarActions
	private var onSelectSpacePage: ((String) -> Void)?
	public var onAddSpace: (() -> Void)?
	private var cameraControls = BrowserSidebarCameraControls.unavailable
	private var activeCameraTabIDs = Set<BrowserTabID>()
	private var spacePageContentsByID = [String: BrowserSidebarSpacePageContent]()
	private var spacePageViewModelsByID = [String: BrowserSidebarSpacePageViewModel]()
	private var activeSpacePageContentID = ""
	private let tabCollection: BrowserSidebarTabCollection
	private let defaultNewTabAddress: String
	private let newTabInsertionBehavior: NewTabInsertionBehavior

	public func addTabConfigurationChangeObserver(_ observer: @escaping () -> Void) -> UUID {
		let observerID = UUID()
		tabConfigurationChangeObservers[observerID] = observer
		return observerID
	}

	public func removeTabConfigurationChangeObserver(_ observerID: UUID) {
		tabConfigurationChangeObservers.removeValue(forKey: observerID)
		if legacyTabConfigurationChangeObserverID == observerID {
			legacyTabConfigurationChangeObserverID = nil
		}
	}

	func addViewStateChangeObserver(_ observer: @escaping () -> Void) -> UUID {
		let observerID = UUID()
		viewStateChangeObservers[observerID] = observer
		return observerID
	}

	func removeViewStateChangeObserver(_ observerID: UUID) {
		viewStateChangeObservers.removeValue(forKey: observerID)
	}

	public convenience init(initialAddress: String, actions: BrowserSidebarActions) {
		let tabCollection = BrowserSidebarTabCollection(initialAddress: initialAddress)
		self.init(
			tabCollection: tabCollection,
			defaultNewTabAddress: initialAddress,
			initialSelectedTabID: tabCollection.tabs.first?.id,
			actions: actions
		)
	}

	public init(
		tabCollection: BrowserSidebarTabCollection,
		defaultNewTabAddress: String,
		initialSelectedTabID: BrowserTabID?,
		newTabInsertionBehavior: NewTabInsertionBehavior = .afterSelectedTab,
		actions: BrowserSidebarActions
	) {
		self.addressText = ""
		self.tabs = tabCollection.tabs
		self.selectedTabID = initialSelectedTabID
		self.defaultNewTabAddress = defaultNewTabAddress
		self.newTabInsertionBehavior = newTabInsertionBehavior
		self.actions = actions
		self.tabCollection = tabCollection
		self.cameraControls = actions.cameraControls
		tabCollection.addTabsChangeObserver(owner: self) { [weak self] fallbackSelectionIndex in
			self?.applySharedTabCollectionChange(fallbackSelectionIndex: fallbackSelectionIndex)
		}
		let bootstrapSpacePageID = UUID().uuidString
		spacePages = [BrowserSidebarSpacePage(id: bootstrapSpacePageID, title: "1")]
		selectedSpacePageID = bootstrapSpacePageID
		activeSpacePageContentID = bootstrapSpacePageID
		spacePageViewModelsByID[bootstrapSpacePageID] = BrowserSidebarSpacePageViewModel(
			pageID: bootstrapSpacePageID,
			tabs: displayedTabs.unpinned,
			selectedTabID: selectedUnpinnedTabID()
		)
		syncSelectedTabProjection()
		refreshSelectedNavigationState()
	}

	public var showsCameraControls: Bool {
		cameraControls.isVisible
	}

	public var cameraRoutingEnabled: Bool {
		currentCameraSnapshot().routingSettings.routingEnabled
	}

	public var cameraPreviewEnabled: Bool {
		currentCameraSnapshot().routingSettings.previewEnabled
	}

	public var cameraAvailableSources: [BrowserCameraSource] {
		currentCameraSnapshot().availableSources
	}

	public var cameraSelectedSourceID: String? {
		currentCameraSnapshot().routingSettings.preferredSourceID
	}

	public var cameraAvailableFilterPresets: [BrowserCameraFilterPreset] {
		BrowserCameraFilterPreset.allCases
	}

	public var cameraSelectedFilterPreset: BrowserCameraFilterPreset {
		currentCameraSnapshot().routingSettings.preferredFilterPreset
	}

	public var cameraAvailableGrainPresences: [BrowserCameraPipelineGrainPresence] {
		BrowserCameraPipelineGrainPresence.allCases
	}

	public var cameraSelectedGrainPresence: BrowserCameraPipelineGrainPresence {
		currentCameraSnapshot().routingSettings.preferredGrainPresence
	}

	public var cameraPrefersHorizontalFlip: Bool {
		currentCameraSnapshot().routingSettings.prefersHorizontalFlip
	}

	public var cameraLifecycleState: BrowserCameraLifecycleState {
		currentCameraSnapshot().lifecycleState
	}

	public var cameraHealthState: BrowserCameraHealthState {
		currentCameraSnapshot().healthState
	}

	public var cameraOutputMode: BrowserCameraOutputMode {
		currentCameraSnapshot().outputMode
	}

	public var cameraLastErrorDescription: String? {
		currentCameraSnapshot().lastErrorDescription
	}

	public var cameraDebugSummary: BrowserCameraDebugSummary {
		currentCameraSnapshot().debugSummary
	}

	public var cameraPreviewImage: NSImage? {
		cameraControls.previewImage
	}

	public var cameraPreviewFrame: CGImage? {
		cameraControls.previewFrame()
	}

	public var cameraUsageState: BrowserSidebarCameraUsageState {
		let activeTabs = tabs.filter { activeCameraTabIDs.contains($0.id) }
		return BrowserSidebarCameraUsageState(
			activeTabCount: activeTabs.count,
			activeTabTitles: activeTabs.map(\.displayTitle),
			selectedTabIsActive: selectedTabID.map { activeCameraTabIDs.contains($0) } ?? false
		)
	}

	func isCameraActive(for tabID: BrowserTabID) -> Bool {
		activeCameraTabIDs.contains(tabID)
	}

	public func goBack() {
		guard let selectedTab else { return }
		actions.onGoBack(selectedTab.id)
		refreshSelectedNavigationState()
	}

	public func goForward() {
		guard let selectedTab else { return }
		actions.onGoForward(selectedTab.id)
		refreshSelectedNavigationState()
	}

	public func reload() {
		guard let selectedTab else { return }
		actions.onReload(selectedTab.id)
		refreshSelectedNavigationState()
	}

	public func setCameraRoutingEnabled(_ isEnabled: Bool) {
		cameraControls.setRoutingEnabled(isEnabled)
	}

	public func setCameraPreviewEnabled(_ isEnabled: Bool) {
		cameraControls.setPreviewEnabled(isEnabled)
	}

	public func selectCameraSource(id: String?) {
		cameraControls.setPreferredSourceID(id)
	}

	public func selectCameraFilterPreset(_ preset: BrowserCameraFilterPreset) {
		cameraControls.setPreferredFilterPreset(preset)
	}

	public func selectCameraGrainPresence(_ grainPresence: BrowserCameraPipelineGrainPresence) {
		cameraControls.setPreferredGrainPresence(grainPresence)
	}

	public func setCameraPrefersHorizontalFlip(_ prefersHorizontalFlip: Bool) {
		cameraControls.setPrefersHorizontalFlip(prefersHorizontalFlip)
	}

	public func submitAddress() {
		guard let selectedTab else { return }
		let resolvedAddress = resolvedAddress(from: addressText, fallbackAddress: selectedTab.initialURL)
		setAddressText(resolvedAddress)
		tabCollection.updateTabURL(resolvedAddress, for: selectedTab.id)
		notifyTabConfigurationChange()
		actions.onSubmitAddress(selectedTab.id, resolvedAddress)
		refreshSelectedNavigationState()
	}

	public func setAddressText(_ text: String) {
		addressText = text
		selectedTab?.setAddressText(text)
	}

	public func selectTab(id: BrowserTabID?) {
		guard let id else {
			print("[Navigator][BrowserSidebar] selectTab ignored: nil id")
			return
		}
		guard tabs.contains(where: { $0.id == id }) else {
			print("[Navigator][BrowserSidebar] selectTab ignored: missing tab id=\(id.uuidString)")
			return
		}
		guard selectedTabID != id else {
			print("[Navigator][BrowserSidebar] selectTab ignored: already selected id=\(id.uuidString)")
			return
		}
		print(
			"[Navigator][BrowserSidebar] selectTab start id=\(id.uuidString) previous=\(selectedTabID?.uuidString ?? "nil")"
		)
		setSelectedTabID(id, recordPreviousSelection: true)
		syncSelectedTabProjection()
		refreshSelectedNavigationState()
		notifyTabConfigurationChange()
		print(
			"[Navigator][BrowserSidebar] selectTab committed id=\(id.uuidString) address=\(addressText)"
		)
	}

	public func selectTab(at index: Int) {
		guard tabs.indices.contains(index) else {
			print("[Navigator][BrowserSidebar] selectTab ignored: missing index=\(index)")
			return
		}

		selectTab(id: tabs[index].id)
	}

	public func addTab() {
		let newTab = tabCollection.addTab(after: newTabInsertionAnchor())
		setSelectedTabID(newTab.id, recordPreviousSelection: true)
		syncSelectedTabProjection()
		refreshSelectedNavigationState()
		notifyTabConfigurationChange()
	}

	public func selectNextTab() {
		selectAdjacentTab(step: 1)
	}

	public func selectPreviousTab() {
		selectAdjacentTab(step: -1)
	}

	public func closeSelectedTab() {
		guard let selectedTabID else { return }
		closeTab(id: selectedTabID)
	}

	public func reopenLastClosedTab() {
		guard let restoredTab = tabCollection.reopenLastClosedTab() else { return }
		setSelectedTabID(restoredTab.id, recordPreviousSelection: true)
		syncSelectedTabProjection()
		notifyTabConfigurationChange()
	}

	public func closeTab(id: BrowserTabID) {
		guard let tab = tab(id: id) else { return }
		if tab.isPinned {
			tabCollection.unpinTab(id: id)
			syncSelectedTabProjection()
			refreshSelectedNavigationState()
			notifyTabConfigurationChange()
			return
		}
		let wasSelected = selectedTabID == id
		let fallbackIndex = tabCollection.closeTab(id: id)

		if wasSelected {
			applySelectionFallback(fallbackSelectionIndex: fallbackIndex)
		}

		syncSelectedTabProjection()
		refreshSelectedNavigationState()
		notifyTabConfigurationChange()
	}

	public func moveTabs(from source: IndexSet, to destination: Int) {
		guard !source.isEmpty else { return }
		tabCollection.moveTabs(from: source, to: destination)
		syncSelectedTabProjection()
		refreshSelectedNavigationState()
		notifyTabConfigurationChange()
	}

	func moveTabs(
		in section: BrowserSidebarTabSection,
		from source: IndexSet,
		to destination: Int
	) {
		guard !source.isEmpty else { return }
		tabCollection.moveTabs(in: section, from: source, to: destination)
		syncSelectedTabProjection()
		refreshSelectedNavigationState()
		notifyTabConfigurationChange()
	}

	public func pinTab(id: BrowserTabID) {
		guard tabs.contains(where: { $0.id == id }) else { return }
		tabCollection.pinTab(id: id)
		syncSelectedTabProjection()
		refreshSelectedNavigationState()
		notifyTabConfigurationChange()
	}

	public func unpinTab(id: BrowserTabID, toUnpinnedIndex: Int? = nil) {
		guard tabs.contains(where: { $0.id == id }) else { return }
		tabCollection.unpinTab(id: id, toUnpinnedIndex: toUnpinnedIndex)
		syncSelectedTabProjection()
		refreshSelectedNavigationState()
		notifyTabConfigurationChange()
	}

	public func replacePinnedTabURLWithCurrentURL(id: BrowserTabID) {
		guard tabs.contains(where: { $0.id == id }) else { return }
		tabCollection.replacePinnedTabURLWithCurrentURL(id: id)
		syncSelectedTabProjection()
		refreshSelectedNavigationState()
		notifyTabConfigurationChange()
	}

	public func toggleSelectedTabPin() {
		guard let selectedTab else { return }

		if selectedTab.isPinned {
			unpinTab(id: selectedTab.id)
		}
		else {
			pinTab(id: selectedTab.id)
		}
	}

	public func setActions(_ actions: BrowserSidebarActions) {
		self.actions = actions
		cameraControls = actions.cameraControls
		refreshSelectedNavigationState()
		notifyViewStateChange()
	}

	public func setCameraControls(_ cameraControls: BrowserSidebarCameraControls) {
		self.cameraControls = cameraControls
		notifyViewStateChange()
	}

	public func refreshCameraState() {
		notifyViewStateChange()
	}

	public func updateActiveCameraTabIDs(_ activeCameraTabIDs: Set<BrowserTabID>) {
		let visibleTabIDs = Set(tabs.map(\.id))
		let normalizedIDs = activeCameraTabIDs.intersection(visibleTabIDs)
		guard self.activeCameraTabIDs != normalizedIDs else { return }
		self.activeCameraTabIDs = normalizedIDs
		notifyViewStateChange()
	}

	public func currentCameraSnapshot() -> BrowserCameraSessionSnapshot {
		cameraControls.snapshot()
	}

	public func currentCameraRoutingConfiguration() -> BrowserCameraRoutingConfiguration {
		cameraControls.routingConfiguration()
	}

	public func currentCameraPreviewFrame() -> CGImage? {
		cameraControls.previewFrame()
	}

	public func refreshAvailableCameraDevices() {
		cameraControls.refreshAvailableDevices()
	}

	public func configureSpacePages(
		_ pages: [BrowserSidebarSpacePage],
		selectedPageID: String
	) {
		configureSpacePages(
			pages,
			selectedPageID: selectedPageID,
			pageContents: [],
			onSelectSpacePage: nil
		)
	}

	public func configureSpacePages(
		_ pages: [BrowserSidebarSpacePage],
		selectedPageID: String,
		pageContents: [BrowserSidebarSpacePageContent],
		onSelectSpacePage: ((String) -> Void)?
	) {
		let resolvedPages = pages.isEmpty
			? [BrowserSidebarSpacePage(id: selectedPageID, title: "1")]
			: pages
		let resolvedSelectedPageID = resolvedPages.contains(where: { $0.id == selectedPageID })
			? selectedPageID
			: resolvedPages[0].id
		let resolvedContentsByID = Dictionary(
			uniqueKeysWithValues: pageContents.map { ($0.pageID, $0) }
		)
		spacePages = resolvedPages
		selectedSpacePageID = resolvedSelectedPageID
		spacePageContentsByID = resolvedContentsByID
		self.onSelectSpacePage = onSelectSpacePage
		syncSpacePageViewModels()
		notifyViewStateChange()
	}

	public func configureSpacePages(
		_ pages: [BrowserSidebarSpacePage],
		selectedPageID: String,
		onSelectSpacePage: ((String) -> Void)?
	) {
		configureSpacePages(
			pages,
			selectedPageID: selectedPageID,
			pageContents: [],
			onSelectSpacePage: onSelectSpacePage
		)
	}

	public func selectSpacePage(id: String) {
		guard spacePages.contains(where: { $0.id == id }) else { return }
		guard selectedSpacePageID != id else { return }
		selectedSpacePageID = id
		syncSpacePageViewModels()
		notifyViewStateChange()
		onSelectSpacePage?(id)
	}

	public func selectAdjacentSpacePage(step: Int) {
		guard !spacePages.isEmpty, step != 0 else { return }
		guard let currentIndex = spacePages.firstIndex(where: { $0.id == selectedSpacePageID }) else { return }
		let destinationIndex = currentIndex + step
		guard spacePages.indices.contains(destinationIndex) else { return }
		selectSpacePage(id: spacePages[destinationIndex].id)
	}

	public func setCameraPreferredSourceID(_ preferredSourceID: String?) {
		cameraControls.setPreferredSourceID(preferredSourceID)
	}

	public func setCameraPreferredFilterPreset(_ preferredFilterPreset: BrowserCameraFilterPreset) {
		cameraControls.setPreferredFilterPreset(preferredFilterPreset)
	}

	public func setFaviconLoadingSuspended(_ isSuspended: Bool) {
		guard isFaviconLoadingSuspended != isSuspended else { return }
		isFaviconLoadingSuspended = isSuspended
		notifyViewStateChange()
	}

	public func updateTabURL(_ url: String, for tabID: BrowserTabID) {
		guard tab(id: tabID) != nil else { return }
		tabCollection.updateTabURL(url, for: tabID)
		if selectedTabID == tabID {
			syncSelectedTabProjection()
		}
		notifyTabConfigurationChange()
	}

	public func updateTabTitle(_ title: String?, for tabID: BrowserTabID) {
		guard tab(id: tabID) != nil else { return }
		tabCollection.updateTabTitle(title, for: tabID)
		notifyTabConfigurationChange()
	}

	public func updateNavigationState(_ state: BrowserSidebarNavigationState, for tabID: BrowserTabID) {
		guard tab(id: tabID) != nil else { return }
		tabCollection.updateNavigationState(state, for: tabID)
		if selectedTabID == tabID {
			syncSelectedTabProjection()
		}
	}

	public func updateTabFaviconURL(_ faviconURL: String?, for tabID: BrowserTabID) {
		guard tab(id: tabID) != nil else { return }
		tabCollection.updateTabFaviconURL(faviconURL, for: tabID)
		notifyTabConfigurationChange()
	}

	public func updateTabSessionHistory(
		entries: [StoredBrowserHistoryEntry],
		currentIndex: Int,
		for tabID: BrowserTabID
	) {
		guard tab(id: tabID) != nil else { return }
		tabCollection.updateTabSessionHistory(entries: entries, currentIndex: currentIndex, for: tabID)
		notifyTabConfigurationChange()
	}

	public func navigateSelectedTab(to text: String) {
		guard selectedTab != nil else { return }
		setAddressText(text)
		submitAddress()
	}

	public func openNewTab(with text: String, activate: Bool = true) {
		let resolvedAddress = resolvedAddress(from: text, fallbackAddress: defaultNewTabAddress)
		if activate {
			let newTab = tabCollection.openNewTab(
				with: resolvedAddress,
				after: newTabInsertionAnchor()
			)
			setSelectedTabID(newTab.id, recordPreviousSelection: true)
			syncSelectedTabProjection()
			refreshSelectedNavigationState()
			notifyTabConfigurationChange()
			actions.onSubmitAddress(newTab.id, resolvedAddress)
			return
		}

		let previousSelectedTabID = selectedTabID
		_ = tabCollection.openNewTab(
			with: resolvedAddress,
			after: newTabInsertionAnchor()
		)
		if previousSelectedTabID == nil {
			setSelectedTabID(tabs.first?.id)
		}
		syncSelectedTabProjection()
		refreshSelectedNavigationState()
		notifyTabConfigurationChange()
	}

	public func clearTabs() {
		tabCollection.clearTabs()
		setSelectedTabID(nil)
		syncSelectedTabProjection()
		refreshSelectedNavigationState()
		notifyTabConfigurationChange()
	}

	public func appendTabs(
		with urlStrings: [String],
		selectedIndexInBatch: Int? = nil
	) {
		let seeds = urlStrings.map {
			BrowserSidebarImportedTabSeed(url: $0)
		}
		appendImportedTabs(
			seeds,
			selectedIndexInBatch: selectedIndexInBatch
		)
	}

	public func appendImportedTabs(
		_ tabSeeds: [BrowserSidebarImportedTabSeed],
		selectedIndexInBatch: Int? = nil
	) {
		let resolvedSeeds = tabSeeds.map { seed in
			BrowserSidebarImportedTabSeed(
				url: resolvedAddress(from: seed.url, fallbackAddress: defaultNewTabAddress),
				title: seed.title,
				isPinned: seed.isPinned
			)
		}
		guard resolvedSeeds.isEmpty == false else { return }

		let newTabs = tabCollection.appendTabs(with: resolvedSeeds)
		if let selectedIndexInBatch, newTabs.indices.contains(selectedIndexInBatch) {
			setSelectedTabID(newTabs[selectedIndexInBatch].id, recordPreviousSelection: true)
		}
		else if selectedTabID == nil {
			setSelectedTabID(tabs.first?.id)
		}

		syncSelectedTabProjection()
		refreshSelectedNavigationState()
		notifyTabConfigurationChange()
	}

	public func replaceTabs(
		with urlStrings: [String],
		selectedIndex: Int? = nil
	) {
		replaceTabs(
			with: urlStrings,
			selectedIndex: selectedIndex,
			activeSpacePageID: nil
		)
	}

	public func replaceTabs(
		with urlStrings: [String],
		selectedIndex: Int?,
		activeSpacePageID: String?
	) {
		if let activeSpacePageID {
			activeSpacePageContentID = activeSpacePageID
		}
		let seeds = urlStrings.map {
			BrowserSidebarImportedTabSeed(url: $0)
		}
		replaceTabs(
			withImportedTabs: seeds,
			selectedIndex: selectedIndex,
			activeSpacePageID: activeSpacePageID
		)
	}

	public func replaceTabs(
		withImportedTabs tabSeeds: [BrowserSidebarImportedTabSeed],
		selectedIndex: Int? = nil
	) {
		replaceTabs(
			withImportedTabs: tabSeeds,
			selectedIndex: selectedIndex,
			activeSpacePageID: nil
		)
	}

	public func replaceTabs(
		withImportedTabs tabSeeds: [BrowserSidebarImportedTabSeed],
		selectedIndex: Int?,
		activeSpacePageID: String?
	) {
		if let activeSpacePageID {
			activeSpacePageContentID = activeSpacePageID
		}
		let resolvedSeeds = tabSeeds.map { seed in
			BrowserSidebarImportedTabSeed(
				url: resolvedAddress(from: seed.url, fallbackAddress: defaultNewTabAddress),
				title: seed.title,
				isPinned: seed.isPinned
			)
		}

		let nextTabs = tabCollection.replaceTabs(with: resolvedSeeds)
		if let selectedIndex, nextTabs.indices.contains(selectedIndex) {
			setSelectedTabID(nextTabs[selectedIndex].id)
		}
		else {
			setSelectedTabID(nextTabs.first?.id)
		}

		syncSelectedTabProjection()
		refreshSelectedNavigationState()
		notifyTabConfigurationChange()
	}

	public func restoreTabs(
		_ storedTabs: [StoredBrowserTab],
		selectedTabID: BrowserTabID?
	) {
		restoreTabs(
			storedTabs,
			selectedTabID: selectedTabID,
			activeSpacePageID: nil
		)
	}

	public func restoreTabs(
		_ storedTabs: [StoredBrowserTab],
		selectedTabID: BrowserTabID?,
		activeSpacePageID: String?
	) {
		if let activeSpacePageID {
			activeSpacePageContentID = activeSpacePageID
		}
		else {
			activeSpacePageContentID = selectedSpacePageID
		}
		tabCollection.restoreTabs(storedTabs)

		if let selectedTabID, tabs.contains(where: { $0.id == selectedTabID }) {
			setSelectedTabID(selectedTabID)
		}
		else {
			setSelectedTabID(tabs.first?.id)
		}

		syncSelectedTabProjection()
		refreshSelectedNavigationState()
		notifyTabConfigurationChange()
	}

	public func refreshSelectedNavigationState() {
		guard let selectedTab else {
			applyNavigationState(.idle)
			return
		}
		let state = actions.navigationState(selectedTab.id)
		selectedTab.updateNavigationState(state)
		applyNavigationState(state)
	}

	public func isSelectedTab(_ tabID: BrowserTabID) -> Bool {
		selectedTabID == tabID
	}

	#if DEBUG
		func clearSelectionForTesting() {
			setSelectedTabID(nil)
			syncSelectedTabProjection()
		}
	#endif

	func spacePageViewModel(at index: Int) -> BrowserSidebarSpacePageViewModel? {
		guard spacePages.indices.contains(index) else { return nil }
		return spacePageViewModelsByID[spacePages[index].id]
	}

	private var selectedTab: BrowserTabViewModel? {
		guard let selectedTabID else { return nil }
		return tabs.first(where: { $0.id == selectedTabID })
	}

	private func tab(id: BrowserTabID) -> BrowserTabViewModel? {
		tabs.first(where: { $0.id == id })
	}

	private func applySharedTabCollectionChange(fallbackSelectionIndex: Int?) {
		tabs = tabCollection.tabs
		activeCameraTabIDs.formIntersection(Set(tabs.map(\.id)))
		applySelectionFallback(fallbackSelectionIndex: fallbackSelectionIndex)
		syncSelectedTabProjection()
		syncSpacePageViewModels()
		notifyViewStateChange()
	}

	private func applySelectionFallback(fallbackSelectionIndex: Int?) {
		guard tabs.isEmpty == false else {
			setSelectedTabID(nil)
			return
		}
		if let selectedTabID, tabs.contains(where: { $0.id == selectedTabID }) {
			return
		}
		if let fallbackSelectionIndex, tabs.indices.contains(fallbackSelectionIndex) {
			setSelectedTabID(tabs[fallbackSelectionIndex].id)
			return
		}
		setSelectedTabID(tabs.first?.id)
	}

	private func setSelectedTabID(
		_ selectedTabID: BrowserTabID?,
		recordPreviousSelection: Bool = false
	) {
		_ = recordPreviousSelection
		self.selectedTabID = selectedTabID
	}

	private func syncSpacePageViewModels() {
		let activePageContentID = resolvedActiveSpacePageContentID()
		activeSpacePageContentID = activePageContentID

		var nextViewModelsByID = [String: BrowserSidebarSpacePageViewModel]()
		for page in spacePages {
			let spacePageViewModel = spacePageViewModelsByID[page.id] ?? BrowserSidebarSpacePageViewModel(
				pageID: page.id,
				tabs: [],
				selectedTabID: nil
			)
			spacePageViewModel.updateTitle(page.title)
			if page.id == activePageContentID {
				spacePageViewModel.applyActiveTabs(
					displayedTabs.unpinned,
					selectedTabID: selectedUnpinnedTabID()
				)
			}
			else if let content = spacePageContentsByID[page.id] {
				spacePageViewModel.applyStoredContent(content)
			}
			else {
				spacePageViewModel.applyActiveTabs([], selectedTabID: nil)
			}
			nextViewModelsByID[page.id] = spacePageViewModel
		}
		spacePageViewModelsByID = nextViewModelsByID
	}

	private func resolvedActiveSpacePageContentID() -> String {
		if spacePages.contains(where: { $0.id == activeSpacePageContentID }) {
			return activeSpacePageContentID
		}
		return selectedSpacePageID
	}

	private func selectedUnpinnedTabID() -> BrowserTabID? {
		guard let selectedTabID else { return nil }
		guard displayedTabs.unpinned.contains(where: { $0.id == selectedTabID }) else { return nil }
		return selectedTabID
	}

	private func syncSelectedTabProjection() {
		guard let selectedTab else {
			addressText = ""
			applyNavigationState(.idle)
			return
		}

		addressText = selectedTab.addressText
		applyNavigationState(
			BrowserSidebarNavigationState(
				canGoBack: selectedTab.canGoBack,
				canGoForward: selectedTab.canGoForward,
				isLoading: selectedTab.isLoading
			)
		)
	}

	private func applyNavigationState(_ state: BrowserSidebarNavigationState) {
		canGoBack = state.canGoBack
		canGoForward = state.canGoForward
		isLoading = state.isLoading
	}

	private func notifyTabConfigurationChange() {
		for observer in tabConfigurationChangeObservers.values {
			observer()
		}
		notifyViewStateChange()
	}

	private func notifyViewStateChange() {
		for observer in viewStateChangeObservers.values {
			observer()
		}
	}

	private func selectAdjacentTab(step: Int) {
		guard !tabs.isEmpty, let selectedTabID else { return }
		guard let currentIndex = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
		let tabsCount = tabs.count
		let nextIndex = (currentIndex + step + tabsCount) % tabsCount
		selectTab(id: tabs[nextIndex].id)
	}

	private func newTabInsertionAnchor() -> BrowserTabID? {
		switch newTabInsertionBehavior {
		case .afterSelectedTab:
			selectedTabID
		case .append:
			nil
		}
	}

	private func resolvedAddress(from input: String, fallbackAddress: String) -> String {
		let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return fallbackAddress }
		if let implicitWebAddress = implicitWebAddress(from: trimmed) {
			return implicitWebAddress
		}
		if hasExplicitScheme(trimmed) { return trimmed }
		return "https://\(trimmed)"
	}

	private func implicitWebAddress(from value: String) -> String? {
		guard !value.contains("://") else { return nil }
		guard !value.contains(where: { $0.isWhitespace }) else { return nil }
		let candidateAddress = "https://\(value)"
		guard var components = URLComponents(string: candidateAddress),
		      components.user == nil,
		      components.password == nil,
		      let host = components.host,
		      !host.isEmpty else { return nil }
		guard isIPAddress(host) || host.contains(".") || isLocalhostHost(host) else {
			return nil
		}
		components.scheme = isLocalhostHost(host) ? "http" : "https"
		return components.string
	}

	private func hasExplicitScheme(_ value: String) -> Bool {
		guard let separatorIndex = value.firstIndex(of: ":"),
		      separatorIndex > value.startIndex else {
			return false
		}

		let scheme = value[..<separatorIndex]
		guard let firstCharacter = scheme.first, firstCharacter.isLetter else { return false }
		return scheme.dropFirst().allSatisfy { character in
			character.isLetter || character.isNumber || character == "+" || character == "-" || character == "."
		}
	}

	private func isIPAddress(_ host: String) -> Bool {
		if host.contains(":") {
			return true
		}

		let components = host.split(separator: ".", omittingEmptySubsequences: false)
		guard components.count == 4 else { return false }
		return components.allSatisfy { component in
			guard let octet = Int(component), (0...255).contains(octet) else { return false }
			return String(octet) == component
		}
	}

	private func isLocalhostHost(_ host: String) -> Bool {
		let normalizedHost = host.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
		return normalizedHost == "localhost" || normalizedHost.hasSuffix(".localhost")
	}
}
