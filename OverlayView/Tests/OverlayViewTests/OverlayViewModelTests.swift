@testable import OverlayView
import XCTest

@MainActor
final class OverlayViewModelTests: XCTestCase {
	func testManualDismissRunsCompletionOnce() async {
		var dismissalCount = 0
		let model = OverlayViewModel(
			style: .toast(duration: nil),
			sleep: { _ in }
		) {
			dismissalCount += 1
		}

		await model.didRequestDismissal()
		await model.didRequestDismissal()

		XCTAssertFalse(model.isActive)
		XCTAssertEqual(dismissalCount, 1)
	}

	func testAutoDismissTransitionsToInactive() async {
		let dismissal = expectation(description: "toast dismissed")
		let model = OverlayViewModel(
			style: .toast(duration: .milliseconds(1)),
			sleep: { _ in }
		) {
			dismissal.fulfill()
		}

		_ = model
		await fulfillment(of: [dismissal], timeout: 1)
		XCTAssertFalse(model.isActive)
	}
}
