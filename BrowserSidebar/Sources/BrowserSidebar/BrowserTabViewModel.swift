import Foundation
import ModelKit
import Observation

public typealias BrowserTabID = UUID

@MainActor
@Observable
public final class BrowserTabViewModel: Identifiable {
	public let id: BrowserTabID
	public private(set) var initialURL: String
	public private(set) var currentURL: String
	public private(set) var addressText: String
	public private(set) var isPinned: Bool
	public private(set) var pageTitle: String?
	public private(set) var faviconURL: String?
	public private(set) var canGoBack = false
	public private(set) var canGoForward = false
	public private(set) var isLoading = false
	public private(set) var historyEntries = [StoredBrowserHistoryEntry]()
	public private(set) var currentHistoryIndex = 0

	public init(
		id: BrowserTabID,
		initialURL: String,
		currentURL: String,
		isPinned: Bool = false
	) {
		self.id = id
		self.initialURL = initialURL
		self.currentURL = currentURL
		self.addressText = currentURL
		self.isPinned = isPinned
	}

	public convenience init(id: BrowserTabID, initialURL: String) {
		self.init(id: id, initialURL: initialURL, currentURL: initialURL)
	}

	public convenience init(initialURL: String) {
		self.init(id: UUID(), initialURL: initialURL)
	}

	public convenience init(initialURL: String, isPinned: Bool) {
		self.init(id: UUID(), initialURL: initialURL, currentURL: initialURL, isPinned: isPinned)
	}

	public var displayTitle: String {
		if let pageTitle, !pageTitle.isEmpty {
			return pageTitle
		}
		return currentURL
	}

	var faviconLoadKey: String {
		"\(currentURL)|\(faviconURL ?? "")"
	}

	func setAddressText(_ text: String) {
		addressText = text
	}

	func updateCurrentURL(_ url: String) {
		let previousHost = host(for: currentURL)
		let nextHost = host(for: url)
		if currentURL != url {
			pageTitle = nil
		}
		currentURL = url
		addressText = url
		if previousHost != nextHost {
			faviconURL = nil
		}
	}

	func updatePageTitle(_ title: String?) {
		let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
		pageTitle = trimmedTitle?.isEmpty == false ? trimmedTitle : nil
	}

	func updateNavigationState(_ state: BrowserSidebarNavigationState) {
		canGoBack = state.canGoBack
		canGoForward = state.canGoForward
		isLoading = state.isLoading
	}

	func updatePinned(_ isPinned: Bool) {
		self.isPinned = isPinned
	}

	func captureCurrentURLAsPinnedURL() {
		initialURL = currentURL
	}

	func replacePinnedURLWithCurrentURL() {
		guard isPinned else { return }
		initialURL = currentURL
	}

	func updateFaviconURL(_ url: String?) {
		let trimmedURL = url?.trimmingCharacters(in: .whitespacesAndNewlines)
		guard trimmedURL?.isEmpty == false else {
			if isPinned {
				return
			}
			faviconURL = nil
			return
		}
		faviconURL = trimmedURL
	}

	func restoreSessionHistory(
		entries: [StoredBrowserHistoryEntry],
		currentIndex: Int
	) {
		guard entries.isEmpty == false else {
			historyEntries = []
			currentHistoryIndex = 0
			return
		}
		historyEntries = entries
		currentHistoryIndex = min(max(0, currentIndex), entries.count - 1)
	}

	func updateSessionHistory(
		entries: [StoredBrowserHistoryEntry],
		currentIndex: Int
	) {
		restoreSessionHistory(entries: entries, currentIndex: currentIndex)
	}

	private func host(for url: String) -> String? {
		URL(string: url)?.host()?.lowercased()
	}
}
