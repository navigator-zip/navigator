import AVFoundation
@testable import BrowserRuntime
import CoreLocation
import Foundation
import ModelKit

struct BrowserPermissionResolutionRecord: Equatable {
	let sessionID: BrowserPermissionSessionID
	let resolution: BrowserPermissionResolution
}

@MainActor
final class BrowserPermissionDecisionStoreSpy: BrowserPermissionDecisionStoring {
	private(set) var decisions = [BrowserStoredPermissionDecisionKey: BrowserStoredPermissionDecision]()
	private(set) var upserts = [(
		key: BrowserStoredPermissionDecisionKey,
		decision: BrowserPermissionPromptDecision,
		timestamp: Date
	)]()
	private(set) var removals = [BrowserStoredPermissionDecisionKey]()

	func decision(for key: BrowserStoredPermissionDecisionKey) -> BrowserPermissionPromptDecision? {
		decisions[key]?.decision
	}

	func upsert(
		decision: BrowserPermissionPromptDecision,
		for key: BrowserStoredPermissionDecisionKey,
		at timestamp: Date
	) {
		upserts.append((key, decision, timestamp))
		decisions[key] = BrowserStoredPermissionDecision(
			key: key,
			decision: decision,
			updatedAt: timestamp
		)
	}

	func removeDecision(for key: BrowserStoredPermissionDecisionKey) {
		removals.append(key)
		decisions.removeValue(forKey: key)
	}

	func snapshot() -> BrowserStoredPermissionDecisionStore {
		BrowserStoredPermissionDecisionStore(
			decisions: decisions.values.sorted { lhs, rhs in
				lhs.id < rhs.id
			}
		)
	}

	func seedDecision(
		decision: BrowserPermissionPromptDecision,
		for key: BrowserStoredPermissionDecisionKey,
		at timestamp: Date
	) {
		decisions[key] = BrowserStoredPermissionDecision(
			key: key,
			decision: decision,
			updatedAt: timestamp
		)
	}
}

@MainActor
final class BrowserPermissionAuthorizerSpy: BrowserPermissionAuthorizing {
	var cachedAuthorizationState = BrowserPermissionOSAuthorizationState()
	var requestedKinds = [BrowserPermissionKindSet]()
	var queuedResponses = [BrowserPermissionOSAuthorizationState]()

	func cachedState() -> BrowserPermissionOSAuthorizationState {
		cachedAuthorizationState
	}

	func requestAuthorization(
		for kinds: BrowserPermissionKindSet,
		completion: @escaping @MainActor (BrowserPermissionOSAuthorizationState) -> Void
	) {
		requestedKinds.append(kinds)
		let response = queuedResponses.isEmpty ? cachedAuthorizationState : queuedResponses.removeFirst()
		cachedAuthorizationState = response
		completion(response)
	}
}

@MainActor
final class AsyncBrowserPermissionAuthorizerSpy: BrowserPermissionAuthorizing {
	var cachedAuthorizationState = BrowserPermissionOSAuthorizationState()
	var requestedKinds = [BrowserPermissionKindSet]()
	private var pendingCompletions = [@MainActor (BrowserPermissionOSAuthorizationState) -> Void]()

	func cachedState() -> BrowserPermissionOSAuthorizationState {
		cachedAuthorizationState
	}

	func requestAuthorization(
		for kinds: BrowserPermissionKindSet,
		completion: @escaping @MainActor (BrowserPermissionOSAuthorizationState) -> Void
	) {
		requestedKinds.append(kinds)
		pendingCompletions.append(completion)
	}

	var hasPendingCompletion: Bool {
		pendingCompletions.isEmpty == false
	}

	func finishNext(with state: BrowserPermissionOSAuthorizationState) {
		guard pendingCompletions.isEmpty == false else { return }
		cachedAuthorizationState = state
		let completion = pendingCompletions.removeFirst()
		completion(state)
	}
}

@MainActor
final class BrowserPermissionLocationAuthorizerSpy: BrowserPermissionLocationAuthorizing {
	var currentStatusValue: BrowserPermissionOSAuthorizationStatus
	private(set) var requestCount = 0
	private var pendingCompletion: (@MainActor (BrowserPermissionOSAuthorizationStatus) -> Void)?

	init(currentStatusValue: BrowserPermissionOSAuthorizationStatus) {
		self.currentStatusValue = currentStatusValue
	}

	func currentStatus() -> BrowserPermissionOSAuthorizationStatus {
		currentStatusValue
	}

	func requestAuthorization(
		completion: @escaping @MainActor (BrowserPermissionOSAuthorizationStatus) -> Void
	) {
		requestCount += 1
		pendingCompletion = completion
	}

	func finish(with status: BrowserPermissionOSAuthorizationStatus) {
		currentStatusValue = status
		pendingCompletion?(status)
		pendingCompletion = nil
	}
}

final class FakeCoreLocationManager: CLLocationManager {
	var fakeAuthorizationStatus: CLAuthorizationStatus = .notDetermined
	private(set) var requestWhenInUseAuthorizationCount = 0

	override var authorizationStatus: CLAuthorizationStatus {
		fakeAuthorizationStatus
	}

	override func requestWhenInUseAuthorization() {
		requestWhenInUseAuthorizationCount += 1
	}
}

func makePermissionRequest(
	sessionID: BrowserPermissionSessionID,
	browserID: UInt64 = 1,
	promptID: UInt64 = 0,
	frameIdentifier: String? = "frame-1",
	permissionFlags: BrowserPermissionKindSet,
	source: BrowserPermissionRequestSource = .permissionPrompt,
	requestingOrigin: String = "https://request.example",
	topLevelOrigin: String = "https://top.example"
) -> BrowserPermissionNativeRequest {
	BrowserPermissionNativeRequest(
		sessionID: sessionID,
		browserID: browserID,
		promptID: promptID,
		frameIdentifier: frameIdentifier,
		permissionFlags: permissionFlags.rawValue,
		source: source,
		requestingOrigin: requestingOrigin,
		topLevelOrigin: topLevelOrigin
	)
}

func makeDecisionKey(
	requestingOrigin: String = "https://request.example",
	topLevelOrigin: String = "https://top.example",
	kind: BrowserPermissionKind
) -> BrowserStoredPermissionDecisionKey {
	BrowserStoredPermissionDecisionKey(
		requestingOrigin: requestingOrigin,
		topLevelOrigin: topLevelOrigin,
		kind: kind
	)
}
