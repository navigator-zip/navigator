import BrowserRuntime
@testable import BrowserView
import ModelKit
import XCTest

@MainActor
final class BrowserPermissionPromptBindingTests: XCTestCase {
	func testBindingRoutesMatchingLifecycleAndIgnoresStaleCallbacks() {
		let runtime = BrowserRuntimeSpy()
		let browser = makeBrowserRef(0x111)
		let container = BrowserContainerView(
			initialURL: "https://navigator.test",
			browserRuntime: runtime
		)
		let window = makeWindow(size: CGSize(width: 640, height: 480))
		host(container, in: window, size: CGSize(width: 640, height: 480))
		runtime.createBrowserResults = [browser]
		container.createBrowserIfNeeded()

		var lifecycleGeneration = 7
		var resolved = [(BrowserPermissionSessionID, BrowserPermissionPromptDecision, BrowserPermissionPersistence)]()
		var cancelled = [BrowserPermissionSessionID]()
		var protections = [Bool]()
		var sessions = [BrowserPermissionSession?]()

		BrowserPermissionPromptBinding.bind(
			browserRuntime: runtime,
			browser: browser,
			expectedLifecycleGeneration: 7,
			currentLifecycleGeneration: { lifecycleGeneration },
			container: { container },
			onSessionChange: { sessions.append($0) },
			resolve: { resolved.append(($0, $1, $2)) },
			cancel: { cancelled.append($0) },
			setProtection: { protections.append($0) }
		)

		runtime.firePermissionPrompt(
			makePermissionSession(
				id: 91,
				browserID: 2,
				requestedKinds: [.camera, .microphone]
			),
			for: browser
		)

		XCTAssertTrue(container.isPermissionPromptVisibleForTesting)
		XCTAssertEqual(protections, [true])

		container.performPermissionPromptAllowForTesting()

		XCTAssertEqual(resolved.count, 1)
		XCTAssertEqual(resolved[0].0, 91)
		XCTAssertEqual(resolved[0].1, .allow)
		XCTAssertEqual(resolved[0].2, .session)
		XCTAssertTrue(cancelled.isEmpty)

		runtime.firePermissionPrompt(nil, for: browser)

		XCTAssertFalse(container.isPermissionPromptVisibleForTesting)
		XCTAssertEqual(protections, [true, false])

		runtime.firePermissionPrompt(
			makePermissionSession(
				id: 92,
				browserID: 2,
				requestedKinds: .geolocation
			),
			for: browser
		)
		container.performPermissionPromptCancelForTesting()

		XCTAssertEqual(cancelled, [92])

		runtime.firePermissionPrompt(nil, for: browser)

		lifecycleGeneration = 8
		runtime.firePermissionPrompt(
			makePermissionSession(
				id: 93,
				browserID: 2,
				requestedKinds: .camera
			),
			for: browser
		)

		XCTAssertEqual(resolved.count, 1)
		XCTAssertEqual(cancelled, [92])
		XCTAssertEqual(protections, [true, false, true, false])
		XCTAssertEqual(sessions.compactMap { $0?.id }, [91, 92])
		XCTAssertEqual(sessions.filter { $0 == nil }.count, 2)
		XCTAssertFalse(container.isPermissionPromptVisibleForTesting)
	}
}
