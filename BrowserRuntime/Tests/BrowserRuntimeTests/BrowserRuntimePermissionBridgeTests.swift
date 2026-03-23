@testable import BrowserRuntime
import Foundation
import ModelKit
import XCTest

@MainActor
final class BrowserRuntimePermissionBridgeTests: XCTestCase {
	private let browser = UnsafeMutableRawPointer(bitPattern: 0xCAFE)!
	private let now = Date(timeIntervalSince1970: 7000)

	func testRegisterAndClearNativeHandlersForUnknownBrowserDoNotCrash() {
		let bridge = makeBridge()

		bridge.register(browser: browser)
		bridge.clearNativeHandlers(for: browser)
		bridge.unregister(browser: browser)

		XCTAssertTrue(true)
	}

	func testSetPromptHandlerIgnoresNilBrowserReference() {
		let bridge = makeBridge()
		var promptCount = 0

		bridge.setPromptHandler(for: nil) { _ in
			promptCount += 1
		}

		XCTAssertEqual(promptCount, 0)
	}

	func testRequestAndDismissCallbacksRouteThroughRegisteredBrowser() async throws {
		let store = BrowserPermissionDecisionStoreSpy()
		let authorizer = BrowserPermissionAuthorizerSpy()
		let bridge = makeBridge(store: store, authorizer: authorizer)
		bridge.registerBrowserForTesting(browser)
		var prompts = [BrowserPermissionSession?]()
		bridge.setPromptHandler(for: browser) { prompts.append($0) }

		withRawRequest(
			sessionID: 81,
			browserID: UInt64(UInt(bitPattern: browser)),
			promptID: 811,
			frameIdentifier: "frame-81",
			permissionFlags: .camera,
			source: BrowserPermissionRequestSource.mediaAccess.rawValue,
			requestingOrigin: "https://camera.example",
			topLevelOrigin: "https://top.example"
		) { requestPointer in
			BrowserRuntimePermissionBridge.invokeStoredPermissionRequestCallbackForTesting(
				userData: browser,
				requestPointer: requestPointer
			)
		}
		await drainMainActorTasks()

		let prompt = try XCTUnwrap(prompts.compactMap { $0 }.first)
		XCTAssertEqual(prompt.id, 81)
		XCTAssertEqual(prompt.browserID, UInt64(UInt(bitPattern: browser)))
		XCTAssertEqual(prompt.frameIdentifier, "frame-81")
		XCTAssertEqual(prompt.source, .mediaAccess)
		XCTAssertEqual(prompt.origin.requestingOrigin, "https://camera.example")
		XCTAssertEqual(prompt.origin.topLevelOrigin, "https://top.example")

		BrowserRuntimePermissionBridge.invokeStoredPermissionDismissedCallbackForTesting(
			userData: browser,
			sessionID: 81,
			reason: BrowserPermissionSessionDismissReason.browserClosed.rawValue
		)
		await drainMainActorTasks()

		XCTAssertNil(prompts.last ?? nil)
		bridge.unregisterBrowserForTesting(browser)
	}

	func testCallbacksIgnoreMissingPayloadAndMissingRegisteredBrowser() async {
		let bridge = makeBridge()
		var prompts = [BrowserPermissionSession?]()
		bridge.setPromptHandler(for: browser) { prompts.append($0) }

		BrowserRuntimePermissionBridge.invokePermissionRequestCallbackForTesting(
			userData: nil,
			requestPointer: nil
		)
		BrowserRuntimePermissionBridge.invokePermissionDismissedCallbackForTesting(
			userData: nil,
			sessionID: 1,
			reason: BrowserPermissionSessionDismissReason.promptDismissed.rawValue
		)

		withRawRequest(
			sessionID: 82,
			browserID: UInt64(UInt(bitPattern: browser)),
			promptID: 0,
			frameIdentifier: nil,
			permissionFlags: .camera,
			source: 999,
			requestingOrigin: "https://request.example",
			topLevelOrigin: "https://top.example"
		) { requestPointer in
			BrowserRuntimePermissionBridge.invokePermissionRequestCallbackForTesting(
				userData: browser,
				requestPointer: requestPointer
			)
		}
		BrowserRuntimePermissionBridge.invokePermissionDismissedCallbackForTesting(
			userData: browser,
			sessionID: 82,
			reason: 999
		)
		await drainMainActorTasks()

		XCTAssertTrue(prompts.compactMap { $0 }.isEmpty)
	}

	func testRequestCallbackNormalizesMissingOriginsToEmptyStrings() async throws {
		let bridge = makeBridge()
		bridge.registerBrowserForTesting(browser)
		var prompts = [BrowserPermissionSession?]()
		bridge.setPromptHandler(for: browser) { prompts.append($0) }

		withRawRequest(
			sessionID: 85,
			browserID: UInt64(UInt(bitPattern: browser)),
			promptID: 850,
			frameIdentifier: nil,
			permissionFlags: .camera,
			source: BrowserPermissionRequestSource.permissionPrompt.rawValue,
			requestingOrigin: nil,
			topLevelOrigin: nil
		) { requestPointer in
			BrowserRuntimePermissionBridge.invokeStoredPermissionRequestCallbackForTesting(
				userData: browser,
				requestPointer: requestPointer
			)
		}
		await drainMainActorTasks()

		let prompt = try XCTUnwrap(prompts.compactMap { $0 }.first)
		XCTAssertEqual(prompt.origin.requestingOrigin, "")
		XCTAssertEqual(prompt.origin.topLevelOrigin, "")
		bridge.unregisterBrowserForTesting(browser)
	}

	func testExpireTimedOutSessionsCancelsExpiredPrompt() async {
		var resolutions = [BrowserPermissionResolutionRecord]()
		let bridge = BrowserRuntimePermissionBridge(
			permissionStoreFactory: { BrowserPermissionDecisionStoreSpy() },
			permissionAuthorizerFactory: { BrowserPermissionAuthorizerSpy() },
			resolveNativePermissionSession: { sessionID, resolution in
				resolutions.append(.init(sessionID: sessionID, resolution: resolution))
			},
			sessionTimeoutInterval: 300
		)
		bridge.configureNowProvider { self.now }
		bridge.registerBrowserForTesting(browser)
		var prompts = [BrowserPermissionSession?]()
		bridge.setPromptHandler(for: browser) { prompts.append($0) }

		bridge.handleRequest(
			makePermissionRequest(
				sessionID: 86,
				browserID: UInt64(UInt(bitPattern: browser)),
				permissionFlags: .camera
			),
			now: now
		)
		bridge.expireTimedOutSessions(now: now.addingTimeInterval(301))
		await drainMainActorTasks()

		XCTAssertEqual(resolutions, [.init(sessionID: 86, resolution: .cancel)])
		XCTAssertNil(prompts.last ?? nil)
		bridge.unregisterBrowserForTesting(browser)
	}

	func testRegisteredCallbacksIgnoreMissingNowProviderAndReleasedBridge() async {
		let missingNowBridge = BrowserRuntimePermissionBridge(
			permissionStoreFactory: { BrowserPermissionDecisionStoreSpy() },
			permissionAuthorizerFactory: { BrowserPermissionAuthorizerSpy() },
			resolveNativePermissionSession: { _, _ in }
		)
		var prompts = [BrowserPermissionSession?]()
		missingNowBridge.registerBrowserForTesting(browser)
		missingNowBridge.setPromptHandler(for: browser) { prompts.append($0) }

		withRawRequest(
			sessionID: 83,
			browserID: UInt64(UInt(bitPattern: browser)),
			promptID: 0,
			frameIdentifier: nil,
			permissionFlags: .camera,
			source: BrowserPermissionRequestSource.permissionPrompt.rawValue,
			requestingOrigin: "https://request.example",
			topLevelOrigin: "https://top.example"
		) { requestPointer in
			BrowserRuntimePermissionBridge.invokePermissionRequestCallbackForTesting(
				userData: browser,
				requestPointer: requestPointer
			)
		}
		await drainMainActorTasks()
		XCTAssertTrue(prompts.compactMap { $0 }.isEmpty)
		missingNowBridge.unregisterBrowserForTesting(browser)

		var releasedBridge: BrowserRuntimePermissionBridge? = makeBridge()
		releasedBridge?.registerBrowserForTesting(browser)
		releasedBridge = nil

		withRawRequest(
			sessionID: 84,
			browserID: UInt64(UInt(bitPattern: browser)),
			promptID: 0,
			frameIdentifier: nil,
			permissionFlags: .camera,
			source: BrowserPermissionRequestSource.permissionPrompt.rawValue,
			requestingOrigin: "https://request.example",
			topLevelOrigin: "https://top.example"
		) { requestPointer in
			BrowserRuntimePermissionBridge.invokePermissionRequestCallbackForTesting(
				userData: browser,
				requestPointer: requestPointer
			)
		}
		BrowserRuntimePermissionBridge.invokePermissionDismissedCallbackForTesting(
			userData: browser,
			sessionID: 84,
			reason: BrowserPermissionSessionDismissReason.browserClosed.rawValue
		)
		await drainMainActorTasks()
	}

	private func makeBridge(
		store: BrowserPermissionDecisionStoreSpy = BrowserPermissionDecisionStoreSpy(),
		authorizer: BrowserPermissionAuthorizerSpy = BrowserPermissionAuthorizerSpy()
	) -> BrowserRuntimePermissionBridge {
		let bridge = BrowserRuntimePermissionBridge(
			permissionStoreFactory: { store },
			permissionAuthorizerFactory: { authorizer },
			resolveNativePermissionSession: { _, _ in }
		)
		bridge.configureNowProvider { self.now }
		return bridge
	}

	private func drainMainActorTasks() async {
		await Task.yield()
		await Task.yield()
	}

	private func withRawRequest(
		sessionID: BrowserPermissionSessionID,
		browserID: UInt64,
		promptID: UInt64,
		frameIdentifier: String?,
		permissionFlags: BrowserPermissionKindSet,
		source: UInt32,
		requestingOrigin: String?,
		topLevelOrigin: String?,
		body: (UnsafeRawPointer) -> Void
	) {
		let framePointer = frameIdentifier.flatMap { strdup($0) }
		let requestingOriginPointer = requestingOrigin.flatMap { strdup($0) }
		let topLevelOriginPointer = topLevelOrigin.flatMap { strdup($0) }
		defer {
			if let framePointer {
				free(framePointer)
			}
			if let requestingOriginPointer {
				free(requestingOriginPointer)
			}
			if let topLevelOriginPointer {
				free(topLevelOriginPointer)
			}
		}

		var request = BrowserRuntimeCEFBridgePermissionRequest(
			session_id: sessionID,
			browser_id: browserID,
			prompt_id: promptID,
			frame_identifier: framePointer.map { UnsafePointer($0) },
			permission_flags: permissionFlags.rawValue,
			source: source,
			requesting_origin: requestingOriginPointer.map { UnsafePointer($0) },
			top_level_origin: topLevelOriginPointer.map { UnsafePointer($0) }
		)
		withUnsafePointer(to: &request) { pointer in
			body(UnsafeRawPointer(pointer))
		}
	}
}
