import BrowserRuntime
@testable import BrowserView
import XCTest

final class BrowserTabLifecycleTests: XCTestCase {
	func testTransientAndCreatedAtPropertiesReturnFalseAndNilForNonMatchingStates() {
		var record = BrowserTabLifecycleRecord()

		XCTAssertFalse(record.isTransient)
		XCTAssertNil(record.browserCreatedAt)

		record.intentState = .transientSelected(sessionID: 3)
		record.browserState = .live(createdAt: 42)

		XCTAssertTrue(record.isTransient)
		XCTAssertEqual(record.browserCreatedAt, 42)
	}
}
