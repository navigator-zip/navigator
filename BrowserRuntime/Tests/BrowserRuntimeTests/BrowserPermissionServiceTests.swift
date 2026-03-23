@testable import BrowserRuntime
import Foundation
import ModelKit
import XCTest

@MainActor
final class BrowserPermissionServiceTests: XCTestCase {
	private let now = Date(timeIntervalSince1970: 1234)

	func testUnsupportedRequestResolvesDenyImmediately() {
		let store = BrowserPermissionDecisionStoreSpy()
		let authorizer = BrowserPermissionAuthorizerSpy()
		var resolutions = [BrowserPermissionResolutionRecord]()
		let service = BrowserPermissionService(
			store: store,
			authorizer: authorizer,
			resolveNativeSession: { sessionID, resolution in
				resolutions.append(.init(sessionID: sessionID, resolution: resolution))
			}
		)

		service.handleRequest(
			makePermissionRequest(sessionID: 1, permissionFlags: BrowserPermissionKindSet(rawValue: 0)),
			now: now
		)

		XCTAssertEqual(resolutions, [.init(sessionID: 1, resolution: .deny)])
		XCTAssertEqual(service.activeSessionCount, 0)
		XCTAssertTrue(authorizer.requestedKinds.isEmpty)
	}

	func testStoredDenySkipsPromptAndDenies() {
		let store = BrowserPermissionDecisionStoreSpy()
		store.seedDecision(decision: .deny, for: makeDecisionKey(kind: .camera), at: now)
		let authorizer = BrowserPermissionAuthorizerSpy()
		var resolutions = [BrowserPermissionResolutionRecord]()
		var prompts = [BrowserPermissionSession?]()
		let service = BrowserPermissionService(
			store: store,
			authorizer: authorizer,
			resolveNativeSession: { sessionID, resolution in
				resolutions.append(.init(sessionID: sessionID, resolution: resolution))
			}
		)
		service.setPromptHandler(for: 1) { prompts.append($0) }

		service.handleRequest(
			makePermissionRequest(sessionID: 2, permissionFlags: .camera),
			now: now
		)

		XCTAssertEqual(resolutions, [.init(sessionID: 2, resolution: .deny)])
		XCTAssertNil(prompts.last ?? nil)
		XCTAssertEqual(service.activeSessionCount, 0)
	}

	func testStoredAllowAutoAllowsAfterOSAuthorization() {
		let store = BrowserPermissionDecisionStoreSpy()
		store.seedDecision(decision: .allow, for: makeDecisionKey(kind: .camera), at: now)
		let authorizer = BrowserPermissionAuthorizerSpy()
		authorizer.cachedAuthorizationState = BrowserPermissionOSAuthorizationState(
			camera: .authorized,
			microphone: .notDetermined,
			geolocation: .notDetermined
		)
		authorizer.queuedResponses = [
			BrowserPermissionOSAuthorizationState(
				camera: .authorized,
				microphone: .notDetermined,
				geolocation: .notDetermined
			),
		]
		var resolutions = [BrowserPermissionResolutionRecord]()
		var prompts = [BrowserPermissionSession?]()
		let service = BrowserPermissionService(
			store: store,
			authorizer: authorizer,
			resolveNativeSession: { sessionID, resolution in
				resolutions.append(.init(sessionID: sessionID, resolution: resolution))
			}
		)
		service.setPromptHandler(for: 1) { prompts.append($0) }

		service.handleRequest(
			makePermissionRequest(sessionID: 3, permissionFlags: .camera, source: .mediaAccess),
			now: now
		)

		XCTAssertEqual(authorizer.requestedKinds, [.camera])
		XCTAssertEqual(resolutions, [.init(sessionID: 3, resolution: .allow)])
		XCTAssertNil(prompts.last ?? nil)
		XCTAssertEqual(service.activeSessionCount, 0)
	}

	func testOSDenyRemovesStoredAllowAndDenies() {
		let store = BrowserPermissionDecisionStoreSpy()
		store.seedDecision(decision: .allow, for: makeDecisionKey(kind: .camera), at: now)
		let authorizer = BrowserPermissionAuthorizerSpy()
		authorizer.queuedResponses = [
			BrowserPermissionOSAuthorizationState(
				camera: .denied,
				microphone: .notDetermined,
				geolocation: .notDetermined
			),
		]
		var resolutions = [BrowserPermissionResolutionRecord]()
		let service = BrowserPermissionService(
			store: store,
			authorizer: authorizer,
			resolveNativeSession: { sessionID, resolution in
				resolutions.append(.init(sessionID: sessionID, resolution: resolution))
			}
		)

		service.handleRequest(
			makePermissionRequest(sessionID: 4, permissionFlags: .camera),
			now: now
		)

		XCTAssertEqual(resolutions, [.init(sessionID: 4, resolution: .deny)])
		XCTAssertEqual(store.decision(for: makeDecisionKey(kind: .camera)), nil)
		XCTAssertEqual(store.removals, [makeDecisionKey(kind: .camera)])
	}

	func testAllowRememberPersistsOnlyPromptedKindsAfterOSAuthorization() throws {
		let store = BrowserPermissionDecisionStoreSpy()
		store.seedDecision(decision: .allow, for: makeDecisionKey(kind: .camera), at: now)
		let authorizer = BrowserPermissionAuthorizerSpy()
		authorizer.cachedAuthorizationState = BrowserPermissionOSAuthorizationState(
			camera: .authorized,
			microphone: .notDetermined,
			geolocation: .notDetermined
		)
		authorizer.queuedResponses = [
			BrowserPermissionOSAuthorizationState(
				camera: .authorized,
				microphone: .authorized,
				geolocation: .notDetermined
			),
		]
		var resolutions = [BrowserPermissionResolutionRecord]()
		var prompts = [BrowserPermissionSession?]()
		let service = BrowserPermissionService(
			store: store,
			authorizer: authorizer,
			resolveNativeSession: { sessionID, resolution in
				resolutions.append(.init(sessionID: sessionID, resolution: resolution))
			}
		)
		service.setPromptHandler(for: 9) { prompts.append($0) }

		service.handleRequest(
			makePermissionRequest(
				sessionID: 5,
				browserID: 9,
				permissionFlags: [.camera, .microphone]
			),
			now: now
		)

		let prompt = try XCTUnwrap(prompts.compactMap { $0 }.first)
		XCTAssertEqual(prompt.requestedKinds, [.camera, .microphone])
		XCTAssertEqual(prompt.promptKinds, .microphone)
		XCTAssertEqual(prompt.state, .waitingForUserPrompt)

		service.decide(
			sessionID: 5,
			decision: .allow,
			persistence: .remember,
			now: now.addingTimeInterval(1)
		)

		XCTAssertEqual(resolutions, [.init(sessionID: 5, resolution: .allow)])
		XCTAssertEqual(store.decision(for: makeDecisionKey(kind: .camera)), .allow)
		XCTAssertEqual(store.decision(for: makeDecisionKey(kind: .microphone)), .allow)
		XCTAssertEqual(store.upserts.map(\.key.kind), [.microphone])
		XCTAssertTrue(prompts.contains(where: { $0?.id == 5 }))
		XCTAssertNil(prompts.last ?? nil)
	}

	func testDenyRememberPersistsPromptKindsAndResolvesDeny() {
		let store = BrowserPermissionDecisionStoreSpy()
		let authorizer = BrowserPermissionAuthorizerSpy()
		var resolutions = [BrowserPermissionResolutionRecord]()
		let service = BrowserPermissionService(
			store: store,
			authorizer: authorizer,
			resolveNativeSession: { sessionID, resolution in
				resolutions.append(.init(sessionID: sessionID, resolution: resolution))
			}
		)

		service.handleRequest(
			makePermissionRequest(sessionID: 6, permissionFlags: [.camera, .microphone]),
			now: now
		)
		service.decide(
			sessionID: 6,
			decision: .deny,
			persistence: .remember,
			now: now.addingTimeInterval(1)
		)

		XCTAssertEqual(resolutions, [.init(sessionID: 6, resolution: .deny)])
		XCTAssertEqual(store.decision(for: makeDecisionKey(kind: .camera)), .deny)
		XCTAssertEqual(store.decision(for: makeDecisionKey(kind: .microphone)), .deny)
		XCTAssertTrue(authorizer.requestedKinds.isEmpty)
	}

	func testSessionScopedAllowSkipsRepeatPromptInSameBrowser() {
		let store = BrowserPermissionDecisionStoreSpy()
		let authorizer = BrowserPermissionAuthorizerSpy()
		authorizer.queuedResponses = [
			BrowserPermissionOSAuthorizationState(
				camera: .authorized,
				microphone: .notDetermined,
				geolocation: .notDetermined
			),
			BrowserPermissionOSAuthorizationState(
				camera: .authorized,
				microphone: .notDetermined,
				geolocation: .notDetermined
			),
		]
		var resolutions = [BrowserPermissionResolutionRecord]()
		var prompts = [BrowserPermissionSession?]()
		let service = BrowserPermissionService(
			store: store,
			authorizer: authorizer,
			resolveNativeSession: { sessionID, resolution in
				resolutions.append(.init(sessionID: sessionID, resolution: resolution))
			}
		)
		service.setPromptHandler(for: 31) { prompts.append($0) }

		service.handleRequest(
			makePermissionRequest(sessionID: 61, browserID: 31, permissionFlags: .camera),
			now: now
		)

		service.decide(
			sessionID: 61,
			decision: .allow,
			persistence: .session,
			now: now.addingTimeInterval(1)
		)
		service.handleRequest(
			makePermissionRequest(sessionID: 62, browserID: 31, permissionFlags: .camera),
			now: now.addingTimeInterval(2)
		)

		XCTAssertEqual(
			resolutions,
			[
				.init(sessionID: 61, resolution: .allow),
				.init(sessionID: 62, resolution: .allow),
			]
		)
		XCTAssertEqual(prompts.compactMap { $0 }.map(\.id), [61])
		XCTAssertEqual(authorizer.requestedKinds, [.camera, .camera])
		XCTAssertTrue(store.snapshot().decisions.isEmpty)
	}

	func testSessionScopedDenySkipsRepeatPromptInSameBrowser() {
		let store = BrowserPermissionDecisionStoreSpy()
		var resolutions = [BrowserPermissionResolutionRecord]()
		var prompts = [BrowserPermissionSession?]()
		let service = BrowserPermissionService(
			store: store,
			authorizer: BrowserPermissionAuthorizerSpy(),
			resolveNativeSession: { sessionID, resolution in
				resolutions.append(.init(sessionID: sessionID, resolution: resolution))
			}
		)
		service.setPromptHandler(for: 32) { prompts.append($0) }

		service.handleRequest(
			makePermissionRequest(sessionID: 63, browserID: 32, permissionFlags: .microphone),
			now: now
		)

		service.decide(
			sessionID: 63,
			decision: .deny,
			persistence: .session,
			now: now.addingTimeInterval(1)
		)
		service.handleRequest(
			makePermissionRequest(sessionID: 64, browserID: 32, permissionFlags: .microphone),
			now: now.addingTimeInterval(2)
		)

		XCTAssertEqual(
			resolutions,
			[
				.init(sessionID: 63, resolution: .deny),
				.init(sessionID: 64, resolution: .deny),
			]
		)
		XCTAssertEqual(prompts.compactMap { $0 }.map(\.id), [63])
		XCTAssertTrue(store.snapshot().decisions.isEmpty)
	}

	func testQueuedSessionsPublishOnePromptAtATime() {
		let service = BrowserPermissionService(
			store: BrowserPermissionDecisionStoreSpy(),
			authorizer: BrowserPermissionAuthorizerSpy(),
			resolveNativeSession: { _, _ in }
		)
		var prompts = [BrowserPermissionSession?]()
		service.setPromptHandler(for: 12) { prompts.append($0) }

		service.handleRequest(
			makePermissionRequest(sessionID: 7, browserID: 12, permissionFlags: .camera),
			now: now
		)
		service.handleRequest(
			makePermissionRequest(sessionID: 8, browserID: 12, permissionFlags: .microphone),
			now: now.addingTimeInterval(1)
		)

		XCTAssertEqual(prompts.compactMap { $0?.id }.first, 7)

		service.decide(
			sessionID: 7,
			decision: .deny,
			persistence: .session,
			now: now.addingTimeInterval(2)
		)

		XCTAssertEqual(prompts.compactMap { $0?.id }.last, 8)
		XCTAssertEqual(service.activeSessionCount, 1)
	}

	func testDecideIgnoresMissingAndNonPromptSessions() {
		let store = BrowserPermissionDecisionStoreSpy()
		store.seedDecision(decision: .allow, for: makeDecisionKey(kind: .camera), at: now)
		let authorizer = AsyncBrowserPermissionAuthorizerSpy()
		var resolutions = [BrowserPermissionResolutionRecord]()
		let service = BrowserPermissionService(
			store: store,
			authorizer: authorizer,
			resolveNativeSession: { sessionID, resolution in
				resolutions.append(.init(sessionID: sessionID, resolution: resolution))
			}
		)

		service.decide(
			sessionID: 404,
			decision: .deny,
			persistence: .remember,
			now: now
		)

		service.handleRequest(
			makePermissionRequest(sessionID: 16, permissionFlags: .camera),
			now: now
		)
		XCTAssertTrue(authorizer.hasPendingCompletion)

		service.decide(
			sessionID: 16,
			decision: .deny,
			persistence: .remember,
			now: now.addingTimeInterval(1)
		)

		authorizer.finishNext(
			with: BrowserPermissionOSAuthorizationState(
				camera: .authorized,
				microphone: .notDetermined,
				geolocation: .notDetermined
			)
		)

		XCTAssertEqual(resolutions, [.init(sessionID: 16, resolution: .allow)])
	}

	func testCancelResolvesCancelWithoutPersisting() {
		let store = BrowserPermissionDecisionStoreSpy()
		var resolutions = [BrowserPermissionResolutionRecord]()
		let service = BrowserPermissionService(
			store: store,
			authorizer: BrowserPermissionAuthorizerSpy(),
			resolveNativeSession: { sessionID, resolution in
				resolutions.append(.init(sessionID: sessionID, resolution: resolution))
			}
		)

		service.handleRequest(
			makePermissionRequest(sessionID: 10, permissionFlags: .geolocation),
			now: now
		)
		service.cancel(sessionID: 10, now: now.addingTimeInterval(1))

		XCTAssertEqual(resolutions, [.init(sessionID: 10, resolution: .cancel)])
		XCTAssertEqual(store.snapshot().decisions, [])
		XCTAssertEqual(service.activeSessionCount, 0)
	}

	func testExpireSessionsCancelsOnlyExpiredSessionsWithoutPersisting() {
		let store = BrowserPermissionDecisionStoreSpy()
		var resolutions = [BrowserPermissionResolutionRecord]()
		let service = BrowserPermissionService(
			store: store,
			authorizer: BrowserPermissionAuthorizerSpy(),
			resolveNativeSession: { sessionID, resolution in
				resolutions.append(.init(sessionID: sessionID, resolution: resolution))
			}
		)

		service.handleRequest(
			makePermissionRequest(sessionID: 610, browserID: 60, permissionFlags: .camera),
			now: now
		)
		service.handleRequest(
			makePermissionRequest(sessionID: 611, browserID: 60, permissionFlags: .microphone),
			now: now.addingTimeInterval(250)
		)

		service.expireSessionsForTesting(
			now: now.addingTimeInterval(301),
			timeoutInterval: 300
		)

		XCTAssertEqual(resolutions, [.init(sessionID: 610, resolution: .cancel)])
		XCTAssertEqual(service.activeSessionCount, 1)
		XCTAssertEqual(store.snapshot().decisions, [])
	}

	func testExpireSessionsIgnoresNonPositiveTimeoutIntervals() {
		var resolutions = [BrowserPermissionResolutionRecord]()
		let service = BrowserPermissionService(
			store: BrowserPermissionDecisionStoreSpy(),
			authorizer: BrowserPermissionAuthorizerSpy(),
			resolveNativeSession: { sessionID, resolution in
				resolutions.append(.init(sessionID: sessionID, resolution: resolution))
			}
		)

		service.handleRequest(
			makePermissionRequest(sessionID: 612, browserID: 60, permissionFlags: .camera),
			now: now
		)
		service.expireSessionsForTesting(now: now.addingTimeInterval(10), timeoutInterval: 0)

		XCTAssertTrue(resolutions.isEmpty)
		XCTAssertEqual(service.activeSessionCount, 1)
	}

	func testExpireSessionsKeepsRequestsWaitingForOSAuthorization() {
		let authorizer = AsyncBrowserPermissionAuthorizerSpy()
		var resolutions = [BrowserPermissionResolutionRecord]()
		let service = BrowserPermissionService(
			store: BrowserPermissionDecisionStoreSpy(),
			authorizer: authorizer,
			resolveNativeSession: { sessionID, resolution in
				resolutions.append(.init(sessionID: sessionID, resolution: resolution))
			}
		)
		var prompts = [BrowserPermissionSession?]()
		service.setPromptHandler(for: 61) { prompts.append($0) }

		service.handleRequest(
			makePermissionRequest(sessionID: 613, browserID: 61, permissionFlags: .camera),
			now: now
		)
		service.decide(
			sessionID: 613,
			decision: .allow,
			persistence: .session,
			now: now.addingTimeInterval(1)
		)

		XCTAssertTrue(authorizer.hasPendingCompletion)
		XCTAssertNil(prompts.last ?? nil)

		service.expireSessionsForTesting(
			now: now.addingTimeInterval(301),
			timeoutInterval: 300
		)

		XCTAssertTrue(resolutions.isEmpty)
		XCTAssertEqual(service.activeSessionCount, 1)

		authorizer.finishNext(
			with: BrowserPermissionOSAuthorizationState(
				camera: .authorized,
				microphone: .notDetermined,
				geolocation: .notDetermined
			)
		)

		XCTAssertEqual(resolutions, [.init(sessionID: 613, resolution: .allow)])
		XCTAssertEqual(service.activeSessionCount, 0)
	}

	func testCancelAndDismissIgnoreMissingSessions() {
		let service = BrowserPermissionService(
			store: BrowserPermissionDecisionStoreSpy(),
			authorizer: BrowserPermissionAuthorizerSpy(),
			resolveNativeSession: { _, _ in
				XCTFail("Unexpected resolution")
			}
		)

		service.cancel(sessionID: 808, now: now)
		service.dismissSession(
			sessionID: 909,
			reason: .promptDismissed,
			now: now.addingTimeInterval(1)
		)

		XCTAssertEqual(service.activeSessionCount, 0)
	}

	func testDismissSessionRemovesPromptWithoutResolvingAgain() {
		var resolutions = [BrowserPermissionResolutionRecord]()
		let service = BrowserPermissionService(
			store: BrowserPermissionDecisionStoreSpy(),
			authorizer: BrowserPermissionAuthorizerSpy(),
			resolveNativeSession: { sessionID, resolution in
				resolutions.append(.init(sessionID: sessionID, resolution: resolution))
			}
		)
		var prompts = [BrowserPermissionSession?]()
		service.setPromptHandler(for: 1) { prompts.append($0) }

		service.handleRequest(
			makePermissionRequest(sessionID: 11, permissionFlags: .camera),
			now: now
		)
		service.dismissSession(
			sessionID: 11,
			reason: .promptDismissed,
			now: now.addingTimeInterval(1)
		)

		XCTAssertNil(prompts.last ?? nil)
		XCTAssertTrue(resolutions.isEmpty)
		XCTAssertEqual(service.activeSessionCount, 0)
	}

	func testClearBrowserDropsAllSessionsAndClearsPrompt() {
		let service = BrowserPermissionService(
			store: BrowserPermissionDecisionStoreSpy(),
			authorizer: BrowserPermissionAuthorizerSpy(),
			resolveNativeSession: { _, _ in }
		)
		var prompts = [BrowserPermissionSession?]()
		service.setPromptHandler(for: 17) { prompts.append($0) }

		service.handleRequest(
			makePermissionRequest(sessionID: 12, browserID: 17, permissionFlags: .camera),
			now: now
		)
		service.handleRequest(
			makePermissionRequest(sessionID: 13, browserID: 17, permissionFlags: .microphone),
			now: now.addingTimeInterval(1)
		)

		service.clearBrowser(17)

		XCTAssertNil(prompts.last ?? nil)
		XCTAssertEqual(service.activeSessionCount, 0)
	}

	func testClearBrowserWithoutSessionsStillClearsPromptSurface() {
		let service = BrowserPermissionService(
			store: BrowserPermissionDecisionStoreSpy(),
			authorizer: BrowserPermissionAuthorizerSpy(),
			resolveNativeSession: { _, _ in }
		)
		var prompts = [BrowserPermissionSession?]()
		service.setPromptHandler(for: 55) { prompts.append($0) }

		service.clearBrowser(55)

		XCTAssertNil(prompts.last ?? nil)
		XCTAssertEqual(service.activeSessionCount, 0)
	}

	func testRemovingPromptHandlerStopsFurtherPromptPublication() {
		let service = BrowserPermissionService(
			store: BrowserPermissionDecisionStoreSpy(),
			authorizer: BrowserPermissionAuthorizerSpy(),
			resolveNativeSession: { _, _ in }
		)
		var prompts = [BrowserPermissionSession?]()
		service.setPromptHandler(for: 41) { prompts.append($0) }
		service.setPromptHandler(for: 41, handler: nil)

		service.handleRequest(
			makePermissionRequest(sessionID: 15, browserID: 41, permissionFlags: .camera),
			now: now
		)

		XCTAssertFalse(prompts.contains(where: { $0?.id == 15 }))
		XCTAssertEqual(service.activeSessionCount, 1)
	}

	func testTracePrunesOldEntriesAfterCapacityLimit() {
		let service = BrowserPermissionService(
			store: BrowserPermissionDecisionStoreSpy(),
			authorizer: BrowserPermissionAuthorizerSpy(),
			resolveNativeSession: { _, _ in }
		)

		for sessionID in 1...140 {
			service.handleRequest(
				makePermissionRequest(
					sessionID: BrowserPermissionSessionID(sessionID),
					browserID: 77,
					permissionFlags: BrowserPermissionKindSet(rawValue: 0)
				),
				now: now.addingTimeInterval(TimeInterval(sessionID))
			)
		}

		let dump = service.dumpState()

		XCTAssertFalse(dump.contains("session=1 browser=77"))
		XCTAssertTrue(dump.contains("session=140 browser=77"))
	}

	func testDumpStateSkipsStaleSessionOrderEntries() {
		let service = BrowserPermissionService(
			store: BrowserPermissionDecisionStoreSpy(),
			authorizer: BrowserPermissionAuthorizerSpy(),
			resolveNativeSession: { _, _ in }
		)
		service.appendStaleSessionIDForTesting(123, browserKey: 42)

		let dump = service.dumpState()

		XCTAssertFalse(dump.contains("session=123"))
	}

	func testDumpStateIncludesActiveAndStoredDecisionCounts() {
		let store = BrowserPermissionDecisionStoreSpy()
		store.seedDecision(decision: .allow, for: makeDecisionKey(kind: .geolocation), at: now)
		let service = BrowserPermissionService(
			store: store,
			authorizer: BrowserPermissionAuthorizerSpy(),
			resolveNativeSession: { _, _ in }
		)
		service.handleRequest(
			makePermissionRequest(sessionID: 14, browserID: 22, permissionFlags: .camera),
			now: now
		)

		let dump = service.dumpState()

		XCTAssertTrue(dump.contains("activeSessions=1"))
		XCTAssertTrue(dump.contains("storedDecisions=1"))
		XCTAssertTrue(dump.contains("browser=22 session=14"))
		XCTAssertEqual(service.storedDecisionCount, 1)
	}

	func testDumpStateSortsActiveSessionsByBrowserKey() {
		let service = BrowserPermissionService(
			store: BrowserPermissionDecisionStoreSpy(),
			authorizer: BrowserPermissionAuthorizerSpy(),
			resolveNativeSession: { _, _ in }
		)
		service.handleRequest(
			makePermissionRequest(sessionID: 21, browserID: 90, permissionFlags: .camera),
			now: now
		)
		service.handleRequest(
			makePermissionRequest(sessionID: 22, browserID: 12, permissionFlags: .microphone),
			now: now.addingTimeInterval(1)
		)

		let dump = service.dumpState()
		let firstBrowserLine = try? XCTUnwrap(
			dump
				.split(separator: "\n")
				.first(where: { $0.hasPrefix("browser=") })
		)

		XCTAssertEqual(
			firstBrowserLine.map(String.init),
			"browser=12 session=22 state=waitingForUserPrompt requested=2 prompt=2 origin=https://request.example"
		)
	}

	func testRequestOSAuthorizationForTestingIgnoresMissingSessions() {
		let authorizer = AsyncBrowserPermissionAuthorizerSpy()
		let service = BrowserPermissionService(
			store: BrowserPermissionDecisionStoreSpy(),
			authorizer: authorizer,
			resolveNativeSession: { _, _ in }
		)

		service.requestOSAuthorizationForTesting(
			sessionID: 600,
			rememberDecision: false,
			now: now
		)

		XCTAssertTrue(authorizer.requestedKinds.isEmpty)
	}

	func testAuthorizerCallbackAfterServiceReleaseIsIgnored() {
		let store = BrowserPermissionDecisionStoreSpy()
		store.seedDecision(decision: .allow, for: makeDecisionKey(kind: .camera), at: now)
		let authorizer = AsyncBrowserPermissionAuthorizerSpy()
		var resolutions = [BrowserPermissionResolutionRecord]()
		var service: BrowserPermissionService? = BrowserPermissionService(
			store: store,
			authorizer: authorizer,
			resolveNativeSession: { sessionID, resolution in
				resolutions.append(.init(sessionID: sessionID, resolution: resolution))
			}
		)

		service?.handleRequest(
			makePermissionRequest(sessionID: 700, permissionFlags: .camera),
			now: now
		)
		XCTAssertTrue(authorizer.hasPendingCompletion)
		service = nil

		authorizer.finishNext(
			with: BrowserPermissionOSAuthorizationState(
				camera: .authorized,
				microphone: .notDetermined,
				geolocation: .notDetermined
			)
		)

		XCTAssertTrue(resolutions.isEmpty)
	}

	func testAuthorizerCallbackAfterSessionRemovalIsIgnored() {
		let store = BrowserPermissionDecisionStoreSpy()
		store.seedDecision(decision: .allow, for: makeDecisionKey(kind: .camera), at: now)
		let authorizer = AsyncBrowserPermissionAuthorizerSpy()
		var resolutions = [BrowserPermissionResolutionRecord]()
		let service = BrowserPermissionService(
			store: store,
			authorizer: authorizer,
			resolveNativeSession: { sessionID, resolution in
				resolutions.append(.init(sessionID: sessionID, resolution: resolution))
			}
		)

		service.handleRequest(
			makePermissionRequest(sessionID: 701, permissionFlags: .camera),
			now: now
		)
		XCTAssertTrue(authorizer.hasPendingCompletion)
		service.removeSessionForTesting(701)

		authorizer.finishNext(
			with: BrowserPermissionOSAuthorizationState(
				camera: .authorized,
				microphone: .notDetermined,
				geolocation: .notDetermined
			)
		)

		XCTAssertTrue(resolutions.isEmpty)
	}

	func testOSDenyRemovesOnlyStoredAllowDecisions() throws {
		let store = BrowserPermissionDecisionStoreSpy()
		store.seedDecision(decision: .allow, for: makeDecisionKey(kind: .camera), at: now)
		let authorizer = BrowserPermissionAuthorizerSpy()
		authorizer.cachedAuthorizationState = BrowserPermissionOSAuthorizationState(
			camera: .authorized,
			microphone: .notDetermined,
			geolocation: .notDetermined
		)
		authorizer.queuedResponses = [
			BrowserPermissionOSAuthorizationState(
				camera: .authorized,
				microphone: .denied,
				geolocation: .notDetermined
			),
		]
		let service = BrowserPermissionService(
			store: store,
			authorizer: authorizer,
			resolveNativeSession: { _, _ in }
		)
		var prompts = [BrowserPermissionSession?]()
		service.setPromptHandler(for: 81) { prompts.append($0) }

		service.handleRequest(
			makePermissionRequest(
				sessionID: 702,
				browserID: 81,
				permissionFlags: [.camera, .microphone]
			),
			now: now
		)

		let prompt = try XCTUnwrap(prompts.compactMap { $0 }.first)
		XCTAssertEqual(prompt.promptKinds, .microphone)

		service.decide(
			sessionID: 702,
			decision: .allow,
			persistence: .session,
			now: now.addingTimeInterval(1)
		)

		XCTAssertEqual(store.removals, [makeDecisionKey(kind: .camera)])
		XCTAssertNil(store.decision(for: makeDecisionKey(kind: .camera)))
	}

	func testRemoveSessionForTestingIgnoresMissingSessionsAndOrderlessSessions() {
		let service = BrowserPermissionService(
			store: BrowserPermissionDecisionStoreSpy(),
			authorizer: BrowserPermissionAuthorizerSpy(),
			resolveNativeSession: { _, _ in }
		)
		service.removeSessionForTesting(703)

		let session = BrowserPermissionSession(
			id: 704,
			browserID: 12,
			promptID: 0,
			frameIdentifier: "frame-1",
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
			createdAt: now,
			updatedAt: now
		)
		service.injectSessionRecordForTesting(
			session,
			requestedKinds: .camera,
			promptKinds: .camera,
			trackInBrowserOrder: false
		)

		service.removeSessionForTesting(704)

		XCTAssertEqual(service.activeSessionCount, 0)
	}

	func testInjectSessionRecordForTestingTracksBrowserOrderByDefault() {
		let service = BrowserPermissionService(
			store: BrowserPermissionDecisionStoreSpy(),
			authorizer: BrowserPermissionAuthorizerSpy(),
			resolveNativeSession: { _, _ in }
		)
		let session = BrowserPermissionSession(
			id: 705,
			browserID: 45,
			promptID: 0,
			frameIdentifier: "frame-705",
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
			createdAt: now,
			updatedAt: now
		)

		service.injectSessionRecordForTesting(
			session,
			requestedKinds: .camera,
			promptKinds: .camera
		)

		let dump = service.dumpState()
		XCTAssertTrue(dump.contains("browser=45 session=705"))
	}
}
