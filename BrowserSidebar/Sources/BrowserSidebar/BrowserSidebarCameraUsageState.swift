import Foundation

public struct BrowserSidebarCameraUsageState: Equatable, Sendable {
	public let activeTabCount: Int
	public let activeTabTitles: [String]
	public let selectedTabIsActive: Bool

	public init(
		activeTabCount: Int,
		activeTabTitles: [String],
		selectedTabIsActive: Bool
	) {
		self.activeTabCount = activeTabCount
		self.activeTabTitles = activeTabTitles
		self.selectedTabIsActive = selectedTabIsActive
	}

	public static let inactive = Self(
		activeTabCount: 0,
		activeTabTitles: [],
		selectedTabIsActive: false
	)
}
