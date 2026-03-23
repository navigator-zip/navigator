import Foundation
import ModelKit
import Observation

@MainActor
@Observable
final class BrowserSidebarSpacePageViewModel {
	let id: String
	private(set) var title: String
	private(set) var tabs: [BrowserTabViewModel]
	private(set) var selectedTabID: BrowserTabID?

	init(
		pageID: String,
		tabs: [BrowserTabViewModel],
		selectedTabID: BrowserTabID?
	) {
		id = pageID
		title = ""
		self.tabs = tabs
		self.selectedTabID = Self.resolvedSelectedTabID(
			selectedTabID,
			in: tabs
		)
	}

	init(
		page: BrowserSidebarSpacePage,
		tabs: [BrowserTabViewModel],
		selectedTabID: BrowserTabID?
	) {
		id = page.id
		title = page.title
		self.tabs = tabs
		self.selectedTabID = Self.resolvedSelectedTabID(
			selectedTabID,
			in: tabs
		)
	}

	func apply(
		page: BrowserSidebarSpacePage,
		tabs: [BrowserTabViewModel],
		selectedTabID: BrowserTabID?
	) {
		title = page.title
		self.tabs = tabs
		self.selectedTabID = Self.resolvedSelectedTabID(
			selectedTabID,
			in: tabs
		)
	}

	func updateTitle(_ title: String) {
		self.title = title
	}

	func applyActiveTabs(
		_ tabs: [BrowserTabViewModel],
		selectedTabID: BrowserTabID?
	) {
		self.tabs = tabs
		self.selectedTabID = Self.resolvedSelectedTabID(
			selectedTabID,
			in: tabs
		)
	}

	func applyStoredContent(_ content: BrowserSidebarSpacePageContent) {
		applyActiveTabs(
			content.tabs.map(BrowserTabViewModel.init(storedTab:)),
			selectedTabID: content.selectedTabID
		)
	}

	private static func resolvedSelectedTabID(
		_ selectedTabID: BrowserTabID?,
		in tabs: [BrowserTabViewModel]
	) -> BrowserTabID? {
		guard let selectedTabID else { return nil }
		return tabs.contains(where: { $0.id == selectedTabID }) ? selectedTabID : nil
	}
}

private extension BrowserTabViewModel {
	convenience init(storedTab: StoredBrowserTab) {
		self.init(
			id: storedTab.id,
			initialURL: storedTab.url,
			currentURL: storedTab.url,
			isPinned: storedTab.isPinned
		)
		setAddressText(storedTab.url)
		updatePageTitle(storedTab.title)
		updateFaviconURL(storedTab.faviconURL)
		restoreSessionHistory(
			entries: storedTab.resolvedHistoryEntries,
			currentIndex: storedTab.resolvedCurrentHistoryIndex
		)
	}
}
