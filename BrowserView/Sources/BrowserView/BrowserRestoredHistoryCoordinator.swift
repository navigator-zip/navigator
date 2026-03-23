import BrowserSidebar
import Foundation
import ModelKit

@MainActor
final class BrowserRestoredHistoryCoordinator {
	enum NavigationAction: Equatable {
		case none
		case loadURL(String)
		case runtimeBack
		case runtimeForward
		case runtimeReload
	}

	private enum Mode: Equatable {
		case live
		case eligible
		case navigatingSynthetic(expectedURL: String, expectedIndex: Int)
		case diverged
	}

	private struct TabState: Equatable {
		var browserGeneration = 0
		var mode: Mode = .live
	}

	private enum Constants {
		static let aboutBlankURL = BrowserSessionHistoryDefaults.aboutBlankURL
	}

	private var states = [BrowserTabID: TabState]()

	func syncTabs(_ tabs: [BrowserTabViewModel]) {
		let activeIDs = Set(tabs.map(\.id))
		states = states.filter { activeIDs.contains($0.key) }
		for tab in tabs where states[tab.id] == nil {
			states[tab.id] = TabState()
		}
	}

	func browserCreated(for tab: BrowserTabViewModel) {
		var state = states[tab.id] ?? TabState()
		state.browserGeneration += 1
		if tab.historyEntries.count > 1 {
			state.mode = .eligible
		}
		else {
			state.mode = .live
		}
		states[tab.id] = state
	}

	func browserRemoved(for tabID: BrowserTabID) {
		states.removeValue(forKey: tabID)
	}

	func goBack(for tab: BrowserTabViewModel) -> NavigationAction {
		guard let state = states[tab.id] else { return .runtimeBack }
		switch state.mode {
		case .navigatingSynthetic:
			return .none
		case .eligible:
			guard tab.currentHistoryIndex > 0 else { return .runtimeBack }
			let expectedIndex = tab.currentHistoryIndex - 1
			let expectedURL = tab.historyEntries[expectedIndex].url
			states[tab.id]?.mode = .navigatingSynthetic(
				expectedURL: expectedURL,
				expectedIndex: expectedIndex
			)
			return .loadURL(expectedURL)
		case .live, .diverged:
			return .runtimeBack
		}
	}

	func goForward(for tab: BrowserTabViewModel) -> NavigationAction {
		guard let state = states[tab.id] else { return .runtimeForward }
		switch state.mode {
		case .navigatingSynthetic:
			return .none
		case .eligible:
			let expectedIndex = tab.currentHistoryIndex + 1
			guard tab.historyEntries.indices.contains(expectedIndex) else { return .runtimeForward }
			let expectedURL = tab.historyEntries[expectedIndex].url
			states[tab.id]?.mode = .navigatingSynthetic(
				expectedURL: expectedURL,
				expectedIndex: expectedIndex
			)
			return .loadURL(expectedURL)
		case .live, .diverged:
			return .runtimeForward
		}
	}

	func reload(for tab: BrowserTabViewModel) -> HistoryUpdate {
		forceDiverged(for: tab)
		return HistoryUpdate(
			entries: tab.historyEntries,
			currentIndex: tab.currentHistoryIndex,
			action: .runtimeReload
		)
	}

	func submitAddress(
		_ url: String,
		for tab: BrowserTabViewModel
	) -> HistoryUpdate {
		let trimmedURL = normalizedURL(url)
		guard trimmedURL.isEmpty == false else {
			return HistoryUpdate(
				entries: tab.historyEntries,
				currentIndex: tab.currentHistoryIndex,
				action: .none
			)
		}
		var nextEntries = tab.historyEntries
		var nextIndex = tab.currentHistoryIndex
		if nextEntries.isEmpty {
			nextEntries = [StoredBrowserHistoryEntry(url: trimmedURL, title: tab.pageTitle)]
			nextIndex = 0
		}
		else {
			nextEntries = Array(nextEntries.prefix(nextIndex + 1))
		}
		states[tab.id]?.mode = .diverged
		return HistoryUpdate(
			entries: nextEntries,
			currentIndex: nextIndex,
			action: .loadURL(trimmedURL)
		)
	}

	func handleCommittedURL(
		_ url: String,
		for tab: BrowserTabViewModel
	) -> HistoryUpdate? {
		let normalizedCommittedURL = normalizedURL(url)
		guard shouldPersistCommittedURL(normalizedCommittedURL) else { return nil }

		let nextUpdate: HistoryUpdate
		switch states[tab.id]?.mode ?? .live {
		case let .navigatingSynthetic(expectedURL, expectedIndex):
			if committedURLMatchesExpected(
				normalizedCommittedURL,
				expectedURL: expectedURL,
				entry: tab.historyEntries[safe: expectedIndex]
			), tab.historyEntries.indices.contains(expectedIndex) {
				var entries = tab.historyEntries
				entries[expectedIndex] = updatedEntry(
					entries[expectedIndex],
					url: normalizedCommittedURL,
					title: tab.pageTitle
				)
				states[tab.id]?.mode = .eligible
				nextUpdate = HistoryUpdate(
					entries: entries,
					currentIndex: expectedIndex,
					action: .none
				)
			}
			else {
				states[tab.id]?.mode = .diverged
				nextUpdate = integratedLiveCommit(
					normalizedCommittedURL,
					for: tab,
					title: tab.pageTitle
				)
			}
		case .eligible:
			if currentEntryURL(for: tab) == normalizedCommittedURL {
				nextUpdate = HistoryUpdate(
					entries: updatingCurrentEntryTitle(for: tab, url: normalizedCommittedURL),
					currentIndex: tab.currentHistoryIndex,
					action: .none
				)
			}
			else {
				states[tab.id]?.mode = .diverged
				nextUpdate = integratedLiveCommit(
					normalizedCommittedURL,
					for: tab,
					title: tab.pageTitle
				)
			}
		case .live, .diverged:
			nextUpdate = integratedLiveCommit(
				normalizedCommittedURL,
				for: tab,
				title: tab.pageTitle
			)
		}

		return nextUpdate
	}

	func handleTitleChange(
		_ title: String?,
		for tab: BrowserTabViewModel
	) -> HistoryUpdate? {
		guard tab.historyEntries.indices.contains(tab.currentHistoryIndex) else { return nil }
		var entries = tab.historyEntries
		entries[tab.currentHistoryIndex] = updatedEntry(
			entries[tab.currentHistoryIndex],
			url: entries[tab.currentHistoryIndex].url,
			title: title
		)
		return HistoryUpdate(
			entries: entries,
			currentIndex: tab.currentHistoryIndex,
			action: .none
		)
	}

	func navigationState(
		for tab: BrowserTabViewModel,
		browserState: BrowserSidebarNavigationState
	) -> BrowserSidebarNavigationState {
		switch states[tab.id]?.mode ?? .live {
		case .live, .diverged:
			return browserState
		case .eligible:
			return BrowserSidebarNavigationState(
				canGoBack: tab.currentHistoryIndex > 0 || browserState.canGoBack,
				canGoForward: tab.currentHistoryIndex < tab.historyEntries.count - 1 || browserState.canGoForward,
				isLoading: browserState.isLoading
			)
		case .navigatingSynthetic:
			return BrowserSidebarNavigationState(
				canGoBack: false,
				canGoForward: false,
				isLoading: true
			)
		}
	}

	private func forceDiverged(for tab: BrowserTabViewModel) {
		states[tab.id]?.mode = .diverged
	}

	private func shouldPersistCommittedURL(_ url: String) -> Bool {
		url.isEmpty == false && url != Constants.aboutBlankURL
	}

	private func integratedLiveCommit(
		_ url: String,
		for tab: BrowserTabViewModel,
		title: String?
	) -> HistoryUpdate {
		var entries = tab.historyEntries
		if entries.isEmpty {
			entries = [StoredBrowserHistoryEntry(url: url, title: title)]
			return HistoryUpdate(entries: entries, currentIndex: 0, action: .none)
		}

		let currentIndex = boundedCurrentIndex(for: tab)
		let currentEntry = entries[currentIndex]
		if currentEntry.url == url {
			entries[currentIndex] = updatedEntry(currentEntry, url: url, title: title)
			return HistoryUpdate(entries: entries, currentIndex: currentIndex, action: .none)
		}

		let previousIndex = currentIndex - 1
		if entries.indices.contains(previousIndex), entries[previousIndex].url == url {
			entries[previousIndex] = updatedEntry(entries[previousIndex], url: url, title: title)
			return HistoryUpdate(entries: entries, currentIndex: previousIndex, action: .none)
		}

		let nextIndex = currentIndex + 1
		if entries.indices.contains(nextIndex), entries[nextIndex].url == url {
			entries[nextIndex] = updatedEntry(entries[nextIndex], url: url, title: title)
			return HistoryUpdate(entries: entries, currentIndex: nextIndex, action: .none)
		}

		entries = Array(entries.prefix(currentIndex + 1))
		entries.append(
			StoredBrowserHistoryEntry(
				url: url,
				title: title
			)
		)
		return HistoryUpdate(entries: entries, currentIndex: entries.count - 1, action: .none)
	}

	private func updatingCurrentEntryTitle(
		for tab: BrowserTabViewModel,
		url: String
	) -> [StoredBrowserHistoryEntry] {
		guard tab.historyEntries.indices.contains(tab.currentHistoryIndex) else { return tab.historyEntries }
		var entries = tab.historyEntries
		entries[tab.currentHistoryIndex] = updatedEntry(
			entries[tab.currentHistoryIndex],
			url: url,
			title: tab.pageTitle
		)
		return entries
	}

	private func currentEntryURL(for tab: BrowserTabViewModel) -> String? {
		guard tab.historyEntries.indices.contains(tab.currentHistoryIndex) else { return nil }
		return tab.historyEntries[tab.currentHistoryIndex].url
	}

	private func boundedCurrentIndex(for tab: BrowserTabViewModel) -> Int {
		guard tab.historyEntries.isEmpty == false else { return 0 }
		return min(max(0, tab.currentHistoryIndex), tab.historyEntries.count - 1)
	}

	private func committedURLMatchesExpected(
		_ committedURL: String,
		expectedURL: String,
		entry: StoredBrowserHistoryEntry?
	) -> Bool {
		if committedURL == expectedURL {
			return true
		}
		guard let entry else { return false }
		return [
			entry.url,
			entry.originalURL,
			entry.displayURL,
		]
		.compactMap { $0 }
		.contains(committedURL)
	}

	private func updatedEntry(
		_ entry: StoredBrowserHistoryEntry,
		url: String,
		title: String?
	) -> StoredBrowserHistoryEntry {
		StoredBrowserHistoryEntry(
			url: url,
			title: title ?? entry.title,
			originalURL: entry.originalURL,
			displayURL: entry.displayURL,
			transitionType: entry.transitionType,
			isTopLevelNativeContent: entry.isTopLevelNativeContent,
			nativeContentKind: entry.nativeContentKind
		)
	}

	private func normalizedURL(_ url: String) -> String {
		url.trimmingCharacters(in: .whitespacesAndNewlines)
	}
}

struct HistoryUpdate: Equatable {
	let entries: [StoredBrowserHistoryEntry]
	let currentIndex: Int
	let action: BrowserRestoredHistoryCoordinator.NavigationAction
}

private extension Array {
	subscript(safe index: Int) -> Element? {
		indices.contains(index) ? self[index] : nil
	}
}
