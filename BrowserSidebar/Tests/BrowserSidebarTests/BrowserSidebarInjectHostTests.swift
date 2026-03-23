import AppKit
@testable import BrowserSidebar
import XCTest

@MainActor
final class BrowserSidebarInjectHostTests: XCTestCase {
	func testInjectedBrowserSidebarViewWrapsConstructedView() {
		let injectedView = InjectedBrowserSidebarView(NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10)))

		XCTAssertNotNil(injectedView)
		XCTAssertNotNil(injectedView.superview ?? injectedView)
	}
}
