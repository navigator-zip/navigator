import Foundation
import ModelKit

public struct BrowserSidebarSpacePageContent: Equatable, Sendable {
	public let pageID: String
	public let tabs: [StoredBrowserTab]
	public let selectedTabID: BrowserTabID?

	public init(
		pageID: String,
		tabs: [StoredBrowserTab],
		selectedTabID: BrowserTabID?
	) {
		self.pageID = pageID
		self.tabs = tabs
		self.selectedTabID = selectedTabID
	}
}
