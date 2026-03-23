import Foundation
import ModelKit
import Observation

public struct BrowserSidebarImportedTabSeed: Equatable, Sendable {
	public let url: String
	public let title: String?
	public let isPinned: Bool

	public init(
		url: String,
		title: String? = nil,
		isPinned: Bool = false
	) {
		self.url = url
		self.title = title
		self.isPinned = isPinned
	}
}

@MainActor
public final class BrowserSidebarTabCollection {
	private static let maximumPinnedTabCount = 20
	private struct TabsChangeObserver {
		weak var owner: AnyObject?
		let handler: (Int?) -> Void
	}

	private static let closedTabHistoryLimit = 20

	public private(set) var tabs: [BrowserTabViewModel]

	private let defaultNewTabAddress: String
	private var recentlyClosedTabs = [BrowserSidebarClosedTabSnapshot]()
	private var tabsChangeObservers = [UUID: TabsChangeObserver]()

	public init(initialAddress: String) {
		let initialTab = BrowserTabViewModel(initialURL: initialAddress)
		self.tabs = [initialTab]
		self.defaultNewTabAddress = initialAddress
	}

	func addTabsChangeObserver(
		owner: AnyObject,
		_ observer: @escaping (Int?) -> Void
	) {
		tabsChangeObservers[UUID()] = TabsChangeObserver(
			owner: owner,
			handler: observer
		)
	}

	func addTab(after selectedTabID: BrowserTabID?) -> BrowserTabViewModel {
		let newTab = BrowserTabViewModel(initialURL: defaultNewTabAddress)
		tabs.insert(newTab, at: insertionIndex(after: selectedTabID))
		notifyTabsChanged()
		return newTab
	}

	func openNewTab(
		with url: String,
		after selectedTabID: BrowserTabID?
	) -> BrowserTabViewModel {
		let newTab = BrowserTabViewModel(initialURL: url)
		tabs.insert(newTab, at: insertionIndex(after: selectedTabID))
		notifyTabsChanged()
		return newTab
	}

	func reopenLastClosedTab() -> BrowserTabViewModel? {
		guard let snapshot = recentlyClosedTabs.popLast() else { return nil }
		let restoredTab = snapshot.restoredTab()
		let insertionIndex = normalizedInsertionIndex(
			for: restoredTab,
			originalIndex: snapshot.originalIndex
		)
		tabs.insert(restoredTab, at: insertionIndex)
		notifyTabsChanged()
		return restoredTab
	}

	func closeTab(id: BrowserTabID) -> Int? {
		guard let index = tabs.firstIndex(where: { $0.id == id }) else { return nil }
		recordClosedTabSnapshot(BrowserSidebarClosedTabSnapshot(tab: tabs[index], originalIndex: index))
		tabs.remove(at: index)
		let fallbackIndex = tabs.isEmpty ? nil : min(index, tabs.count - 1)
		notifyTabsChanged(fallbackSelectionIndex: fallbackIndex)
		return fallbackIndex
	}

	func moveTabs(from source: IndexSet, to destination: Int) {
		guard !source.isEmpty else { return }
		guard let firstSourceIndex = source.first, tabs.indices.contains(firstSourceIndex) else { return }
		let isPinnedMove = tabs[firstSourceIndex].isPinned
		guard source.allSatisfy({ tabs.indices.contains($0) && tabs[$0].isPinned == isPinnedMove }) else {
			return
		}

		let partitionRange = reorderableRange(forPinnedState: isPinnedMove)
		var reorderedTabs = tabs
		reorderedTabs.move(
			fromOffsets: source,
			toOffset: min(max(destination, partitionRange.lowerBound), partitionRange.upperBound)
		)
		tabs = reorderedTabs
		notifyTabsChanged()
	}

	func moveTabs(
		in section: BrowserSidebarTabSection,
		from source: IndexSet,
		to destination: Int
	) {
		let displayedTabs = displayedTabs()
		guard let translatedSource = displayedTabs.translatedSourceIndexes(for: section, from: source) else {
			return
		}
		let translatedDestination = displayedTabs.translatedDestinationIndex(
			for: section,
			destination: destination
		)
		moveTabs(from: translatedSource, to: translatedDestination)
	}

	func pinTab(id: BrowserTabID) {
		setPinned(true, for: id)
	}

	func unpinTab(id: BrowserTabID, toUnpinnedIndex: Int? = nil) {
		setPinned(false, for: id, unpinnedInsertionIndex: toUnpinnedIndex)
	}

	func replacePinnedTabURLWithCurrentURL(id: BrowserTabID) {
		guard let tab = tab(id: id), tab.isPinned, tab.currentURL != tab.initialURL else { return }
		tab.replacePinnedURLWithCurrentURL()
		notifyTabsChanged()
	}

	func updateTabURL(_ url: String, for tabID: BrowserTabID) {
		guard let tab = tab(id: tabID) else { return }
		tab.updateCurrentURL(url)
		notifyTabsChanged()
	}

	func updateTabTitle(_ title: String?, for tabID: BrowserTabID) {
		guard let tab = tab(id: tabID) else { return }
		tab.updatePageTitle(title)
		notifyTabsChanged()
	}

	func updateNavigationState(_ state: BrowserSidebarNavigationState, for tabID: BrowserTabID) {
		guard let tab = tab(id: tabID) else { return }
		tab.updateNavigationState(state)
		notifyTabsChanged()
	}

	func updateTabFaviconURL(_ faviconURL: String?, for tabID: BrowserTabID) {
		guard let tab = tab(id: tabID) else { return }
		tab.updateFaviconURL(faviconURL)
		notifyTabsChanged()
	}

	func clearTabs() {
		tabs = []
		notifyTabsChanged()
	}

	func appendTabs(with seeds: [BrowserSidebarImportedTabSeed]) -> [BrowserTabViewModel] {
		let newTabs = seeds.map { seed in
			let tab = BrowserTabViewModel(
				initialURL: seed.url,
				isPinned: seed.isPinned
			)
			tab.updatePageTitle(seed.title)
			return tab
		}
		guard newTabs.isEmpty == false else { return [] }
		clampNewPinnedTabs(newTabs)
		let pinnedTabs = newTabs.filter(\.isPinned)
		let unpinnedTabs = newTabs.filter { !$0.isPinned }
		tabs.insert(contentsOf: pinnedTabs, at: pinnedTabsCount)
		tabs.append(contentsOf: unpinnedTabs)
		notifyTabsChanged()
		return pinnedTabs + unpinnedTabs
	}

	func replaceTabs(with seeds: [BrowserSidebarImportedTabSeed]) -> [BrowserTabViewModel] {
		tabs = normalizedTabs(
			seeds.map { seed in
				let tab = BrowserTabViewModel(
					initialURL: seed.url,
					isPinned: seed.isPinned
				)
				tab.updatePageTitle(seed.title)
				return tab
			}
		)
		notifyTabsChanged()
		return tabs
	}

	func restoreTabs(_ storedTabs: [StoredBrowserTab]) {
		tabs = normalizedTabs(
			storedTabs.map { storedTab in
				let restoredTab = BrowserTabViewModel(
					id: storedTab.id,
					initialURL: storedTab.url,
					currentURL: storedTab.url,
					isPinned: storedTab.isPinned
				)
				restoredTab.setAddressText(storedTab.url)
				restoredTab.updatePageTitle(storedTab.title)
				restoredTab.updateFaviconURL(storedTab.faviconURL)
				restoredTab.restoreSessionHistory(
					entries: storedTab.resolvedHistoryEntries,
					currentIndex: storedTab.resolvedCurrentHistoryIndex
				)
				return restoredTab
			}
		)
		notifyTabsChanged()
	}

	func updateTabSessionHistory(
		entries: [StoredBrowserHistoryEntry],
		currentIndex: Int,
		for tabID: BrowserTabID
	) {
		guard let tab = tab(id: tabID) else { return }
		tab.updateSessionHistory(entries: entries, currentIndex: currentIndex)
		notifyTabsChanged()
	}

	func displayedTabs() -> BrowserSidebarDisplayedTabs {
		let pinnedTabs = Array(tabs.prefix(while: \.isPinned))
		let unpinnedTabs = Array(tabs.dropFirst(pinnedTabs.count))
		return BrowserSidebarDisplayedTabs(
			pinned: Array(pinnedTabs.prefix(Self.maximumPinnedTabCount)),
			unpinned: unpinnedTabs
		)
	}

	private func setPinned(_ isPinned: Bool, for id: BrowserTabID, unpinnedInsertionIndex: Int? = nil) {
		guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
		let tab = tabs[index]
		guard tab.isPinned != isPinned else { return }
		if isPinned, pinnedTabsCount >= Self.maximumPinnedTabCount {
			return
		}
		tabs.remove(at: index)
		if isPinned {
			tab.captureCurrentURLAsPinnedURL()
		}
		tab.updatePinned(isPinned)
		let baseIndex = pinnedTabsCount
		let insertionIndex: Int
		if !isPinned, let targetUnpinnedIndex = unpinnedInsertionIndex {
			insertionIndex = min(baseIndex + targetUnpinnedIndex, tabs.count)
		} else {
			insertionIndex = baseIndex
		}
		tabs.insert(tab, at: insertionIndex)
		notifyTabsChanged()
	}

	private var pinnedTabsCount: Int {
		tabs.prefix(while: \.isPinned).count
	}

	private func reorderableRange(forPinnedState isPinned: Bool) -> Range<Int> {
		let pinnedCount = pinnedTabsCount
		if isPinned {
			return 0..<pinnedCount
		}
		return pinnedCount..<tabs.count
	}

	private func normalizedTabs(_ tabs: [BrowserTabViewModel]) -> [BrowserTabViewModel] {
		let normalizedTabs = clampedPinnedTabs(tabs)
		let pinnedTabs = normalizedTabs.filter(\.isPinned)
		let unpinnedTabs = normalizedTabs.filter { !$0.isPinned }
		return pinnedTabs + unpinnedTabs
	}

	private func clampedPinnedTabs(_ tabs: [BrowserTabViewModel]) -> [BrowserTabViewModel] {
		var pinnedCount = 0
		for tab in tabs {
			if tab.isPinned {
				if pinnedCount < Self.maximumPinnedTabCount {
					pinnedCount += 1
				}
				else {
					tab.updatePinned(false)
				}
			}
		}
		return tabs
	}

	private func clampNewPinnedTabs(_ tabs: [BrowserTabViewModel]) {
		var remainingPinnedSlots = max(0, Self.maximumPinnedTabCount - pinnedTabsCount)
		for tab in tabs where tab.isPinned {
			if remainingPinnedSlots > 0 {
				remainingPinnedSlots -= 1
			}
			else {
				tab.updatePinned(false)
			}
		}
	}

	private func normalizedInsertionIndex(
		for tab: BrowserTabViewModel,
		originalIndex: Int
	) -> Int {
		let boundedOriginalIndex = min(max(originalIndex, 0), tabs.count)
		let pinnedCount = pinnedTabsCount
		if tab.isPinned {
			return min(boundedOriginalIndex, pinnedCount)
		}
		return max(pinnedCount, boundedOriginalIndex)
	}

	private func tab(id: BrowserTabID) -> BrowserTabViewModel? {
		tabs.first(where: { $0.id == id })
	}

	private func insertionIndex(after selectedTabID: BrowserTabID?) -> Int {
		let pinnedCount = pinnedTabsCount
		guard let selectedTabID else { return tabs.count }
		guard let selectedIndex = tabs.firstIndex(where: { $0.id == selectedTabID }) else {
			return tabs.count
		}

		guard tabs[selectedIndex].isPinned == false else {
			return pinnedCount
		}
		return tabs.index(after: selectedIndex)
	}

	private func notifyTabsChanged(fallbackSelectionIndex: Int? = nil) {
		for (observerID, observer) in tabsChangeObservers {
			guard observer.owner != nil else {
				tabsChangeObservers.removeValue(forKey: observerID)
				continue
			}
			observer.handler(fallbackSelectionIndex)
		}
	}

	private func recordClosedTabSnapshot(_ snapshot: BrowserSidebarClosedTabSnapshot) {
		recentlyClosedTabs.append(snapshot)
		if recentlyClosedTabs.count > Self.closedTabHistoryLimit {
			recentlyClosedTabs.removeFirst(recentlyClosedTabs.count - Self.closedTabHistoryLimit)
		}
	}
}

@MainActor
struct BrowserSidebarClosedTabSnapshot {
	let id: BrowserTabID
	let initialURL: String
	let currentURL: String
	let addressText: String
	let isPinned: Bool
	let pageTitle: String?
	let faviconURL: String?
	let navigationState: BrowserSidebarNavigationState
	let originalIndex: Int

	init(tab: BrowserTabViewModel, originalIndex: Int) {
		id = tab.id
		initialURL = tab.initialURL
		currentURL = tab.currentURL
		addressText = tab.addressText
		isPinned = tab.isPinned
		pageTitle = tab.pageTitle
		faviconURL = tab.faviconURL
		navigationState = BrowserSidebarNavigationState(
			canGoBack: tab.canGoBack,
			canGoForward: tab.canGoForward,
			isLoading: tab.isLoading
		)
		self.originalIndex = originalIndex
	}

	func restoredTab() -> BrowserTabViewModel {
		let tab = BrowserTabViewModel(
			id: id,
			initialURL: initialURL,
			currentURL: currentURL,
			isPinned: isPinned
		)
		tab.setAddressText(addressText)
		tab.updatePageTitle(pageTitle)
		tab.updateFaviconURL(faviconURL)
		tab.updateNavigationState(navigationState)
		return tab
	}
}
