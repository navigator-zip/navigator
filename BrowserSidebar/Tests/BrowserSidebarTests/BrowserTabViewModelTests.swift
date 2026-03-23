@testable import BrowserSidebar
import XCTest

@MainActor
final class BrowserTabViewModelTests: XCTestCase {
	func testDisplayTitleFallsBackToCurrentURLWhenPageTitleIsUnavailable() {
		let tabID = BrowserTabID()
		let tab = BrowserTabViewModel(
			id: tabID,
			initialURL: "https://navigator.zip",
			currentURL: "https://developer.apple.com/documentation/swiftui"
		)

		XCTAssertEqual(tab.id, tabID)
		XCTAssertEqual(tab.displayTitle, "https://developer.apple.com/documentation/swiftui")
	}

	func testDisplayTitleFallsBackToRawURLWhenHostIsUnavailable() {
		let tab = BrowserTabViewModel(
			id: BrowserTabID(),
			initialURL: "https://navigator.zip",
			currentURL: "not a url"
		)

		XCTAssertEqual(tab.displayTitle, "not a url")
	}

	func testFaviconLoadKeyTracksNormalizedFaviconURL() {
		let tab = BrowserTabViewModel(initialURL: "https://navigator.zip")

		XCTAssertEqual(tab.faviconLoadKey, "https://navigator.zip|")

		tab.updateFaviconURL("  https://navigator.zip/favicon.ico \n")
		XCTAssertEqual(tab.faviconURL, "https://navigator.zip/favicon.ico")
		XCTAssertEqual(
			tab.faviconLoadKey,
			"https://navigator.zip|https://navigator.zip/favicon.ico"
		)

		tab.updateFaviconURL("  \n ")
		XCTAssertNil(tab.faviconURL)
	}

	func testUpdateNavigationStateProjectsFlags() {
		let tab = BrowserTabViewModel(initialURL: "https://navigator.zip")

		tab.updateNavigationState(
			BrowserSidebarNavigationState(
				canGoBack: true,
				canGoForward: true,
				isLoading: true
			)
		)

		XCTAssertTrue(tab.canGoBack)
		XCTAssertTrue(tab.canGoForward)
		XCTAssertTrue(tab.isLoading)
	}

	func testDisplayTitlePrefersPageTitleWhenAvailable() {
		let tab = BrowserTabViewModel(
			id: BrowserTabID(),
			initialURL: "https://navigator.zip",
			currentURL: "https://developer.apple.com/documentation/swiftui"
		)

		tab.updatePageTitle("SwiftUI | Apple Developer Documentation")

		XCTAssertEqual(tab.displayTitle, "SwiftUI | Apple Developer Documentation")
	}

	func testUpdateCurrentURLClearsExistingPageTitle() {
		let tab = BrowserTabViewModel(initialURL: "https://navigator.zip")
		tab.updatePageTitle("Navigator")
		XCTAssertEqual(tab.displayTitle, "Navigator")

		tab.updateCurrentURL("https://swift.org")

		XCTAssertNil(tab.pageTitle)
		XCTAssertEqual(tab.displayTitle, "https://swift.org")
	}

	func testUpdatePageTitleTrimsWhitespaceAndClearsOnBlankInput() {
		let tab = BrowserTabViewModel(
			id: BrowserTabID(),
			initialURL: "https://navigator.zip",
			currentURL: "https://navigator.zip/docs"
		)

		tab.updatePageTitle("  Navigator Docs  \n")
		XCTAssertEqual(tab.pageTitle, "Navigator Docs")
		XCTAssertEqual(tab.displayTitle, "Navigator Docs")

		tab.updatePageTitle(" \n ")
		XCTAssertNil(tab.pageTitle)
		XCTAssertEqual(tab.displayTitle, "https://navigator.zip/docs")
	}

	func testUpdatingSameURLRetainsExistingPageTitle() {
		let tab = BrowserTabViewModel(
			id: BrowserTabID(),
			initialURL: "https://navigator.zip",
			currentURL: "https://navigator.zip/docs"
		)
		tab.updatePageTitle("Navigator Docs")

		tab.updateCurrentURL("https://navigator.zip/docs")

		XCTAssertEqual(tab.pageTitle, "Navigator Docs")
		XCTAssertEqual(tab.displayTitle, "Navigator Docs")
	}

	func testCaptureCurrentURLAsPinnedURLUpdatesInitialURL() {
		let tab = BrowserTabViewModel(initialURL: "https://navigator.zip")

		tab.updateCurrentURL("https://swift.org")
		tab.captureCurrentURLAsPinnedURL()

		XCTAssertEqual(tab.initialURL, "https://swift.org")
		XCTAssertEqual(tab.currentURL, "https://swift.org")
	}

	func testUpdateFaviconURLRetainsLastPinnedFaviconWhenUpdateIsBlank() {
		let tab = BrowserTabViewModel(initialURL: "https://navigator.zip", isPinned: true)

		tab.updateFaviconURL("https://navigator.zip/favicon.ico")
		tab.updateFaviconURL("   ")

		XCTAssertEqual(tab.faviconURL, "https://navigator.zip/favicon.ico")
	}

	func testUpdateFaviconURLClearsUnpinnedFaviconWhenUpdateIsBlank() {
		let tab = BrowserTabViewModel(initialURL: "https://navigator.zip")

		tab.updateFaviconURL("https://navigator.zip/favicon.ico")
		tab.updateFaviconURL("   ")

		XCTAssertNil(tab.faviconURL)
	}
}
