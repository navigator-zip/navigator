import AppKit
@testable import BrowserView
import ModelKit
import XCTest

@MainActor
final class BrowserContainerPermissionPromptHostTests: XCTestCase {
	func testHostInstallsOverlayAndForwardsPromptActions() {
		let promptHost = BrowserContainerPermissionPromptHost()
		let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
		container.translatesAutoresizingMaskIntoConstraints = false
		var decisions = [(BrowserPermissionPromptDecision, BrowserPermissionPersistence)]()
		var cancelCount = 0

		promptHost.install(in: container)
		promptHost.setPrompt(
			makePermissionSession(
				id: 1,
				browserID: 2,
				requestingOrigin: "https://frame.example",
				topLevelOrigin: "https://top.example",
				requestedKinds: [.camera, .microphone]
			),
			onDecision: { decisions.append(($0, $1)) },
			onCancel: { cancelCount += 1 }
		)

		XCTAssertTrue(container.subviews.contains(promptHost.hostView))
		XCTAssertTrue(promptHost.isVisibleForTesting)
		XCTAssertFalse(promptHost.textValuesForTesting.isEmpty)

		promptHost.setRememberForTesting(true)
		promptHost.performAllowForTesting()

		XCTAssertEqual(decisions.count, 1)
		XCTAssertEqual(decisions[0].0, .allow)
		XCTAssertEqual(decisions[0].1, .remember)

		promptHost.setPrompt(
			makePermissionSession(
				id: 2,
				browserID: 2,
				requestedKinds: .geolocation
			),
			onDecision: { decisions.append(($0, $1)) },
			onCancel: { cancelCount += 1 }
		)
		promptHost.performDenyForTesting()
		promptHost.performCancelForTesting()

		XCTAssertEqual(decisions.count, 2)
		XCTAssertEqual(decisions[1].0, .deny)
		XCTAssertEqual(decisions[1].1, .session)
		XCTAssertEqual(cancelCount, 1)

		promptHost.setPrompt(nil, onDecision: nil, onCancel: nil)
		XCTAssertFalse(promptHost.isVisibleForTesting)
	}
}
