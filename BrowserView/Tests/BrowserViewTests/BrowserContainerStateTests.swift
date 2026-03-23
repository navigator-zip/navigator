import AppIntents
@testable import BrowserView
import XCTest

final class BrowserContainerStateTests: XCTestCase {
	func testQueueURLUpdatesPendingBrowserCreationURL() {
		var state = BrowserContainerState(initialURL: "https://navigator.zip")

		state.queueURL("https://developer.apple.com")

		XCTAssertEqual(state.pendingURL, "https://developer.apple.com")
		XCTAssertEqual(state.urlForNextBrowserCreation, "https://developer.apple.com")
	}

	func testLatestQueuedURLWinsBeforeBrowserCreation() {
		var state = BrowserContainerState(initialURL: "https://navigator.zip")

		state.queueURL("https://developer.apple.com")
		state.queueURL("https://swift.org")

		XCTAssertEqual(state.urlForNextBrowserCreation, "https://swift.org")
	}

	func testTransientInitialAboutBlankBrowserURLIsIgnoredWhenPendingURLIsRealPage() {
		var state = BrowserContainerState(initialURL: "https://navigator.zip")

		let shouldPropagate = state.consumeBrowserURLChange("about:blank")

		XCTAssertFalse(shouldPropagate)
		XCTAssertEqual(state.pendingURL, "https://navigator.zip")
	}

	func testInitialAboutBlankBrowserURLStillPropagatesForIntentionalBlankTab() {
		var state = BrowserContainerState(initialURL: "about:blank")

		let shouldPropagate = state.consumeBrowserURLChange("about:blank")

		XCTAssertTrue(shouldPropagate)
		XCTAssertEqual(state.pendingURL, "about:blank")
	}
}
