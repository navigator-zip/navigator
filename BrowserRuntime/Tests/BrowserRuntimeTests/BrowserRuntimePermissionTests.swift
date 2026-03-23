@testable import BrowserRuntime
import ModelKit
import XCTest

@MainActor
final class BrowserRuntimePermissionTests: XCTestCase {
	private let browser = UnsafeMutableRawPointer(bitPattern: 0xBEEF)!
	private let now = Date(timeIntervalSince1970: 5000)

	func testRuntimePublishesPromptsAndResolvesAllow() throws {
		let store = BrowserPermissionDecisionStoreSpy()
		let authorizer = BrowserPermissionAuthorizerSpy()
		authorizer.queuedResponses = [
			BrowserPermissionOSAuthorizationState(
				camera: .authorized,
				microphone: .notDetermined,
				geolocation: .notDetermined
			),
		]
		var resolvedSessions = [BrowserPermissionResolutionRecord]()
		let runtime = BrowserRuntime(
			permissionStoreFactory: { store },
			permissionAuthorizerFactory: { authorizer },
			resolveNativePermissionSession: { sessionID, resolution in
				resolvedSessions.append(.init(sessionID: sessionID, resolution: resolution))
			}
		)
		var prompts = [BrowserPermissionSession?]()

		runtime.setPermissionPromptHandler(for: browser) { prompts.append($0) }
		runtime.handlePermissionRequestForTesting(
			makePermissionRequest(
				sessionID: 21,
				browserID: UInt64(UInt(bitPattern: browser)),
				permissionFlags: .camera
			),
			now: now
		)

		let prompt = try XCTUnwrap(prompts.compactMap { $0 }.first)
		XCTAssertEqual(prompt.id, 21)
		XCTAssertEqual(prompt.browserID, UInt64(UInt(bitPattern: browser)))
		XCTAssertEqual(prompt.state, .waitingForUserPrompt)

		runtime.resolvePermissionPromptForTesting(
			sessionID: 21,
			decision: .allow,
			persistence: .remember,
			now: now.addingTimeInterval(1)
		)

		XCTAssertEqual(resolvedSessions, [.init(sessionID: 21, resolution: .allow)])
		XCTAssertNil(prompts.last ?? nil)
		XCTAssertEqual(store.decision(for: makeDecisionKey(kind: .camera)), .allow)
	}

	func testRuntimeCancelsPromptAndExposesStateDump() {
		let runtime = BrowserRuntime(
			permissionStoreFactory: { BrowserPermissionDecisionStoreSpy() },
			permissionAuthorizerFactory: { BrowserPermissionAuthorizerSpy() },
			resolveNativePermissionSession: { _, _ in }
		)
		var prompts = [BrowserPermissionSession?]()

		runtime.setPermissionPromptHandler(for: browser) { prompts.append($0) }
		runtime.handlePermissionRequestForTesting(
			makePermissionRequest(
				sessionID: 22,
				browserID: UInt64(UInt(bitPattern: browser)),
				permissionFlags: .microphone
			),
			now: now
		)

		XCTAssertTrue(runtime.dumpPermissionState().contains("activeSessions=1"))

		runtime.cancelPermissionPromptForTesting(sessionID: 22, now: now.addingTimeInterval(1))

		XCTAssertNil(prompts.last ?? nil)
		XCTAssertTrue(runtime.dumpPermissionState().contains("activeSessions=0"))
	}

	func testRuntimeDismissedCallbackClearsPromptWithoutNativeResolution() {
		var resolvedSessions = [BrowserPermissionResolutionRecord]()
		let runtime = BrowserRuntime(
			permissionStoreFactory: { BrowserPermissionDecisionStoreSpy() },
			permissionAuthorizerFactory: { BrowserPermissionAuthorizerSpy() },
			resolveNativePermissionSession: { sessionID, resolution in
				resolvedSessions.append(.init(sessionID: sessionID, resolution: resolution))
			}
		)
		var prompts = [BrowserPermissionSession?]()

		runtime.setPermissionPromptHandler(for: browser) { prompts.append($0) }
		runtime.handlePermissionRequestForTesting(
			makePermissionRequest(
				sessionID: 23,
				browserID: UInt64(UInt(bitPattern: browser)),
				permissionFlags: .geolocation
			),
			now: now
		)
		runtime.handlePermissionDismissedForTesting(
			sessionID: 23,
			reason: .browserClosed,
			now: now.addingTimeInterval(1)
		)

		XCTAssertNil(prompts.last ?? nil)
		XCTAssertTrue(resolvedSessions.isEmpty)
	}

	func testRuntimeExpiresTimedOutPermissionPrompts() {
		var resolvedSessions = [BrowserPermissionResolutionRecord]()
		let runtime = BrowserRuntime(
			permissionStoreFactory: { BrowserPermissionDecisionStoreSpy() },
			permissionAuthorizerFactory: { BrowserPermissionAuthorizerSpy() },
			resolveNativePermissionSession: { sessionID, resolution in
				resolvedSessions.append(.init(sessionID: sessionID, resolution: resolution))
			}
		)
		var prompts = [BrowserPermissionSession?]()

		runtime.setPermissionPromptHandler(for: browser) { prompts.append($0) }
		runtime.handlePermissionRequestForTesting(
			makePermissionRequest(
				sessionID: 24,
				browserID: UInt64(UInt(bitPattern: browser)),
				permissionFlags: .camera
			),
			now: now
		)

		runtime.expireTimedOutPermissionPromptsForTesting(now: now.addingTimeInterval(301))

		XCTAssertEqual(resolvedSessions, [.init(sessionID: 24, resolution: .cancel)])
		XCTAssertNil(prompts.last ?? nil)
	}
}
