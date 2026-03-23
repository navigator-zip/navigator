import BrowserRuntime
@testable import BrowserView
import ModelKit
import XCTest

@MainActor
final class BrowserPermissionPromptRoutingTests: XCTestCase {
	func testRouteIgnoresMissingContainerAndMismatchedBrowser() {
		var resolved = [(BrowserPermissionSessionID, BrowserPermissionPromptDecision, BrowserPermissionPersistence)]()
		var cancelled = [BrowserPermissionSessionID]()
		var protections = [Bool]()
		let expectedBrowser = makeBrowserRef(0x111)
		let otherBrowser = makeBrowserRef(0x222)

		BrowserPermissionPromptRouting.route(
			session: makeSession(id: 51),
			expectedBrowser: expectedBrowser,
			container: nil,
			resolve: { resolved.append(($0, $1, $2)) },
			cancel: { cancelled.append($0) },
			setProtection: { protections.append($0) }
		)

		let runtime = BrowserRuntimeSpy()
		runtime.createBrowserResults = [otherBrowser]
		let container = BrowserContainerView(
			initialURL: "https://navigator.test",
			browserRuntime: runtime
		)
		let window = makeWindow(size: CGSize(width: 640, height: 480))
		host(container, in: window, size: CGSize(width: 640, height: 480))
		container.createBrowserIfNeeded()

		BrowserPermissionPromptRouting.route(
			session: makeSession(id: 52),
			expectedBrowser: expectedBrowser,
			container: container,
			resolve: { resolved.append(($0, $1, $2)) },
			cancel: { cancelled.append($0) },
			setProtection: { protections.append($0) }
		)

		BrowserPermissionPromptRouting.route(
			session: nil,
			expectedBrowser: expectedBrowser,
			container: container,
			resolve: { resolved.append(($0, $1, $2)) },
			cancel: { cancelled.append($0) },
			setProtection: { protections.append($0) }
		)

		XCTAssertTrue(resolved.isEmpty)
		XCTAssertTrue(cancelled.isEmpty)
		XCTAssertTrue(protections.isEmpty)
	}

	private func makeSession(id: BrowserPermissionSessionID) -> BrowserPermissionSession {
		BrowserPermissionSession(
			id: id,
			browserID: 2,
			promptID: 3,
			frameIdentifier: "frame-\(id)",
			source: .permissionPrompt,
			origin: BrowserPermissionOrigin(
				requestingOrigin: "https://request.example",
				topLevelOrigin: "https://top.example"
			),
			requestedKinds: .camera,
			promptKinds: .camera,
			state: .waitingForUserPrompt,
			siteDecision: nil,
			persistence: nil,
			osAuthorizationState: BrowserPermissionOSAuthorizationState(),
			createdAt: .distantPast,
			updatedAt: .distantPast
		)
	}
}
