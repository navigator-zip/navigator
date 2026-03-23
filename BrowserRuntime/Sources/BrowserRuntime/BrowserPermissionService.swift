import Foundation
import ModelKit

struct BrowserPermissionNativeRequest: Equatable, Sendable {
	let sessionID: BrowserPermissionSessionID
	let browserID: UInt64
	let promptID: UInt64
	let frameIdentifier: String?
	let permissionFlags: UInt32
	let source: BrowserPermissionRequestSource
	let requestingOrigin: String
	let topLevelOrigin: String
}

@MainActor
final class BrowserPermissionService {
	private struct SessionRecord: Equatable {
		var session: BrowserPermissionSession
		let requestedKinds: BrowserPermissionKindSet
		let promptKinds: BrowserPermissionKindSet
	}

	typealias BrowserKey = UInt64
	typealias PromptHandler = (BrowserPermissionSession?) -> Void

	private let store: BrowserPermissionDecisionStoring
	private let authorizer: BrowserPermissionAuthorizing
	private let resolveNativeSession: (BrowserPermissionSessionID, BrowserPermissionResolution) -> Void

	private var sessionsByID = [BrowserPermissionSessionID: SessionRecord]()
	private var sessionOrderByBrowser = [BrowserKey: [BrowserPermissionSessionID]]()
	private var sessionDecisionsByBrowser =
		[BrowserKey: [BrowserStoredPermissionDecisionKey: BrowserPermissionPromptDecision]]()
	private var promptHandlers = [BrowserKey: PromptHandler]()
	private var lastPublishedPromptIDByBrowser = [BrowserKey: BrowserPermissionSessionID?]()
	private var eventTrace = [String]()

	init(
		store: BrowserPermissionDecisionStoring,
		authorizer: BrowserPermissionAuthorizing,
		resolveNativeSession: @escaping (BrowserPermissionSessionID, BrowserPermissionResolution) -> Void
	) {
		self.store = store
		self.authorizer = authorizer
		self.resolveNativeSession = resolveNativeSession
	}

	func setPromptHandler(
		for browserKey: BrowserKey,
		handler: PromptHandler?
	) {
		if handler == nil {
			promptHandlers.removeValue(forKey: browserKey)
			lastPublishedPromptIDByBrowser.removeValue(forKey: browserKey)
			return
		}
		promptHandlers[browserKey] = handler
		publishPrompt(for: browserKey)
	}

	func handleRequest(_ request: BrowserPermissionNativeRequest, now: Date) {
		let requestedKinds = BrowserPermissionKindSet(rawValue: request.permissionFlags)
			.intersection(.all)
		guard requestedKinds.rawValue != 0 else {
			trace("request unsupported session=\(request.sessionID) browser=\(request.browserID)")
			resolveNativeSession(request.sessionID, .deny)
			return
		}

		let origin = BrowserPermissionOrigin(
			requestingOrigin: request.requestingOrigin,
			topLevelOrigin: request.topLevelOrigin
		)
		let storedDeniedKinds = matchingKinds(
			in: requestedKinds,
			where: { kind in
				store.decision(for: decisionKey(origin: origin, kind: kind)) == .deny
			}
		)
		let sessionDeniedKinds = matchingSessionKinds(
			in: requestedKinds,
			browserID: request.browserID,
			origin: origin,
			decision: .deny
		)
		let deniedKinds = storedDeniedKinds.union(sessionDeniedKinds)
		if deniedKinds.rawValue != 0 {
			trace("request auto-deny decision session=\(request.sessionID) browser=\(request.browserID)")
			resolveNativeSession(request.sessionID, .deny)
			return
		}

		let storedAllowedKinds = matchingKinds(
			in: requestedKinds,
			where: { kind in
				store.decision(for: decisionKey(origin: origin, kind: kind)) == .allow
			}
		)
		let sessionAllowedKinds = matchingSessionKinds(
			in: requestedKinds,
			browserID: request.browserID,
			origin: origin,
			decision: .allow
		)
		let promptKinds = requestedKinds.subtracting(storedAllowedKinds.union(sessionAllowedKinds))
		let session = BrowserPermissionSession(
			id: request.sessionID,
			browserID: request.browserID,
			promptID: request.promptID,
			frameIdentifier: request.frameIdentifier,
			source: request.source,
			origin: origin,
			requestedKinds: requestedKinds,
			promptKinds: promptKinds,
			state: promptKinds.rawValue == 0 ? .waitingForOSAuthorization : .waitingForUserPrompt,
			siteDecision: nil,
			persistence: nil,
			osAuthorizationState: authorizer.cachedState(),
			createdAt: now,
			updatedAt: now
		)
		sessionsByID[session.id] = SessionRecord(
			session: session,
			requestedKinds: requestedKinds,
			promptKinds: promptKinds
		)
		sessionOrderByBrowser[request.browserID, default: []].append(session.id)
		trace(
			"request queued session=\(session.id) browser=\(request.browserID) requested=\(requestedKinds.rawValue) prompt=\(promptKinds.rawValue)"
		)

		if promptKinds.rawValue == 0 {
			requestOSAuthorization(for: session.id, rememberDecision: false, now: now)
		}
		else {
			publishPrompt(for: request.browserID)
		}
	}

	func decide(
		sessionID: BrowserPermissionSessionID,
		decision: BrowserPermissionPromptDecision,
		persistence: BrowserPermissionPersistence,
		now: Date
	) {
		guard var record = sessionsByID[sessionID] else { return }
		guard record.session.state == .waitingForUserPrompt else { return }

		if decision == .deny {
			record.session = record.session.updating(
				state: .resolvedDeny,
				siteDecision: .deny,
				persistence: persistence,
				osAuthorizationState: authorizer.cachedState(),
				updatedAt: now
			)
			sessionsByID[sessionID] = record
			if persistence == .remember {
				persist(
					decision: .deny,
					origin: record.session.origin,
					kinds: record.promptKinds,
					at: now
				)
			}
			else {
				persistSessionDecision(
					decision: .deny,
					browserID: record.session.browserID,
					origin: record.session.origin,
					kinds: record.promptKinds
				)
			}
			trace("request denied session=\(sessionID) browser=\(record.session.browserID)")
			resolveNativeSession(sessionID, .deny)
			removeSession(sessionID)
			return
		}

		record.session = record.session.updating(
			state: .waitingForOSAuthorization,
			siteDecision: .allow,
			persistence: persistence,
			osAuthorizationState: authorizer.cachedState(),
			updatedAt: now
		)
		sessionsByID[sessionID] = record
		trace("request awaiting-os session=\(sessionID) browser=\(record.session.browserID)")
		publishPrompt(for: record.session.browserID)
		requestOSAuthorization(for: sessionID, rememberDecision: persistence == .remember, now: now)
	}

	func cancel(sessionID: BrowserPermissionSessionID, now: Date) {
		guard let session = sessionsByID[sessionID]?.session else { return }
		trace("request cancelled session=\(sessionID) browser=\(session.browserID)")
		sessionsByID[sessionID]?.session = session.updating(
			state: .cancelled,
			siteDecision: nil,
			persistence: nil,
			osAuthorizationState: authorizer.cachedState(),
			updatedAt: now
		)
		resolveNativeSession(sessionID, .cancel)
		removeSession(sessionID)
	}

	func dismissSession(
		sessionID: BrowserPermissionSessionID,
		reason: BrowserPermissionSessionDismissReason,
		now: Date
	) {
		guard let session = sessionsByID[sessionID]?.session else { return }
		trace("request dismissed session=\(sessionID) browser=\(session.browserID) reason=\(reason.rawValue)")
		sessionsByID[sessionID]?.session = session.updating(
			state: .cancelled,
			siteDecision: session.siteDecision,
			persistence: session.persistence,
			osAuthorizationState: authorizer.cachedState(),
			updatedAt: now
		)
		removeSession(sessionID)
	}

	func expireSessions(
		now: Date,
		timeoutInterval: TimeInterval
	) {
		guard timeoutInterval > 0 else { return }
		let expiredSessionIDs = sessionsByID.values.compactMap { record -> BrowserPermissionSessionID? in
			guard record.session.state == .waitingForUserPrompt else { return nil }
			guard now.timeIntervalSince(record.session.createdAt) >= timeoutInterval else { return nil }
			return record.session.id
		}
		for sessionID in expiredSessionIDs {
			trace("request timed-out session=\(sessionID)")
			cancel(sessionID: sessionID, now: now)
		}
	}

	func clearBrowser(_ browserKey: BrowserKey) {
		let sessionIDs = sessionOrderByBrowser[browserKey] ?? []
		for sessionID in sessionIDs {
			sessionsByID.removeValue(forKey: sessionID)
		}
		sessionOrderByBrowser.removeValue(forKey: browserKey)
		sessionDecisionsByBrowser.removeValue(forKey: browserKey)
		lastPublishedPromptIDByBrowser.removeValue(forKey: browserKey)
		promptHandlers[browserKey]?(nil)
	}

	func dumpState() -> String {
		let activeSessionLines = sessionOrderByBrowser
			.sorted { lhs, rhs in
				lhs.key < rhs.key
			}
			.flatMap { browserKey, sessionIDs -> [String] in
				return sessionIDs.compactMap { sessionID in
					guard let record = sessionsByID[sessionID] else { return nil }
					return "browser=\(browserKey) session=\(sessionID) state=\(record.session.state.rawValue) requested=\(record.requestedKinds.rawValue) prompt=\(record.promptKinds.rawValue) origin=\(record.session.origin.requestingOrigin)"
				}
			}

		let traceLines = eventTrace.suffix(32)
		return ([
			"activeSessions=\(sessionsByID.count)",
			"storedDecisions=\(store.snapshot().decisions.count)",
			"osState=\(authorizer.cachedState())",
		] + activeSessionLines + traceLines).joined(separator: "\n")
	}

	var activeSessionCount: Int {
		sessionsByID.count
	}

	var storedDecisionCount: Int {
		store.snapshot().decisions.count
	}

	private func requestOSAuthorization(
		for sessionID: BrowserPermissionSessionID,
		rememberDecision: Bool,
		now: Date
	) {
		guard let record = sessionsByID[sessionID] else { return }
		let requestedKinds = record.requestedKinds
		authorizer.requestAuthorization(for: requestedKinds) { [weak self] authorizationState in
			guard let self else { return }
			guard var currentRecord = self.sessionsByID[sessionID] else { return }
			currentRecord.session = currentRecord.session.updating(
				state: currentRecord.session.state,
				siteDecision: currentRecord.session.siteDecision,
				persistence: currentRecord.session.persistence,
				osAuthorizationState: authorizationState,
				updatedAt: now
			)
			self.sessionsByID[sessionID] = currentRecord

			let hasDeniedOSAuthorization = currentRecord.requestedKinds.kinds.contains { kind in
				authorizationState[kind] != .authorized
			}
			if hasDeniedOSAuthorization {
				self.trace("request os-denied session=\(sessionID) browser=\(currentRecord.session.browserID)")
				if currentRecord.session.siteDecision == .allow || currentRecord.promptKinds.rawValue == 0 {
					self.removeStoredAllowDecisions(
						origin: currentRecord.session.origin,
						kinds: currentRecord.requestedKinds
					)
					self.removeSessionAllowDecisions(
						browserID: currentRecord.session.browserID,
						origin: currentRecord.session.origin,
						kinds: currentRecord.requestedKinds
					)
				}
				self.resolveNativeSession(sessionID, .deny)
				self.removeSession(sessionID)
				return
			}

			if rememberDecision {
				self.persist(
					decision: .allow,
					origin: currentRecord.session.origin,
					kinds: currentRecord.promptKinds,
					at: now
				)
			}
			else if currentRecord.session.siteDecision == .allow,
			        currentRecord.session.persistence == .session {
				self.persistSessionDecision(
					decision: .allow,
					browserID: currentRecord.session.browserID,
					origin: currentRecord.session.origin,
					kinds: currentRecord.promptKinds
				)
			}
			self.trace("request allowed session=\(sessionID) browser=\(currentRecord.session.browserID)")
			self.resolveNativeSession(sessionID, .allow)
			self.removeSession(sessionID)
		}
	}

	private func matchingKinds(
		in kinds: BrowserPermissionKindSet,
		where predicate: (BrowserPermissionKind) -> Bool
	) -> BrowserPermissionKindSet {
		kinds.kinds.reduce(into: BrowserPermissionKindSet()) { partialResult, kind in
			if predicate(kind) {
				partialResult.insert(BrowserPermissionKindSet(kind: kind))
			}
		}
	}

	private func matchingSessionKinds(
		in kinds: BrowserPermissionKindSet,
		browserID: BrowserKey,
		origin: BrowserPermissionOrigin,
		decision: BrowserPermissionPromptDecision
	) -> BrowserPermissionKindSet {
		matchingKinds(
			in: kinds,
			where: { kind in
				sessionDecisionsByBrowser[browserID]?[decisionKey(origin: origin, kind: kind)] == decision
			}
		)
	}

	private func persist(
		decision: BrowserPermissionPromptDecision,
		origin: BrowserPermissionOrigin,
		kinds: BrowserPermissionKindSet,
		at timestamp: Date
	) {
		for kind in kinds.kinds {
			store.upsert(
				decision: decision,
				for: decisionKey(origin: origin, kind: kind),
				at: timestamp
			)
		}
	}

	private func persistSessionDecision(
		decision: BrowserPermissionPromptDecision,
		browserID: BrowserKey,
		origin: BrowserPermissionOrigin,
		kinds: BrowserPermissionKindSet
	) {
		var sessionDecisions = sessionDecisionsByBrowser[browserID] ?? [:]
		for kind in kinds.kinds {
			sessionDecisions[decisionKey(origin: origin, kind: kind)] = decision
		}
		sessionDecisionsByBrowser[browserID] = sessionDecisions
	}

	private func removeStoredAllowDecisions(
		origin: BrowserPermissionOrigin,
		kinds: BrowserPermissionKindSet
	) {
		for kind in kinds.kinds {
			let key = decisionKey(origin: origin, kind: kind)
			guard store.decision(for: key) == .allow else { continue }
			store.removeDecision(for: key)
		}
	}

	private func removeSessionAllowDecisions(
		browserID: BrowserKey,
		origin: BrowserPermissionOrigin,
		kinds: BrowserPermissionKindSet
	) {
		guard var sessionDecisions = sessionDecisionsByBrowser[browserID] else { return }
		for kind in kinds.kinds {
			let key = decisionKey(origin: origin, kind: kind)
			guard sessionDecisions[key] == .allow else { continue }
			sessionDecisions.removeValue(forKey: key)
		}
		sessionDecisionsByBrowser[browserID] = sessionDecisions.isEmpty ? nil : sessionDecisions
	}

	private func decisionKey(
		origin: BrowserPermissionOrigin,
		kind: BrowserPermissionKind
	) -> BrowserStoredPermissionDecisionKey {
		BrowserStoredPermissionDecisionKey(
			requestingOrigin: origin.requestingOrigin,
			topLevelOrigin: origin.topLevelOrigin,
			kind: kind
		)
	}

	private func removeSession(_ sessionID: BrowserPermissionSessionID) {
		guard let record = sessionsByID.removeValue(forKey: sessionID) else { return }
		var order = sessionOrderByBrowser[record.session.browserID] ?? []
		order.removeAll { $0 == sessionID }
		sessionOrderByBrowser[record.session.browserID] = order.isEmpty ? nil : order
		publishPrompt(for: record.session.browserID)
	}

	private func publishPrompt(for browserKey: BrowserKey) {
		guard let handler = promptHandlers[browserKey] else { return }
		let nextSession = (sessionOrderByBrowser[browserKey] ?? [])
			.compactMap { sessionsByID[$0]?.session }
			.first(where: { $0.state == .waitingForUserPrompt })
		let nextSessionID = nextSession?.id
		if lastPublishedPromptIDByBrowser[browserKey] == nextSessionID {
			return
		}
		lastPublishedPromptIDByBrowser[browserKey] = nextSessionID
		handler(nextSession)
	}

	private func trace(_ entry: String) {
		eventTrace.append(entry)
		if eventTrace.count > 128 {
			eventTrace.removeFirst(eventTrace.count - 128)
		}
	}
}

private extension BrowserPermissionSession {
	func updating(
		state: BrowserPermissionSessionLifecycleState,
		siteDecision: BrowserPermissionPromptDecision?,
		persistence: BrowserPermissionPersistence?,
		osAuthorizationState: BrowserPermissionOSAuthorizationState,
		updatedAt: Date
	) -> BrowserPermissionSession {
		BrowserPermissionSession(
			id: id,
			browserID: browserID,
			promptID: promptID,
			frameIdentifier: frameIdentifier,
			source: source,
			origin: origin,
			requestedKinds: requestedKinds,
			promptKinds: promptKinds,
			state: state,
			siteDecision: siteDecision,
			persistence: persistence,
			osAuthorizationState: osAuthorizationState,
			createdAt: createdAt,
			updatedAt: updatedAt
		)
	}
}

#if DEBUG
	extension BrowserPermissionService {
		func injectSessionRecordForTesting(
			_ session: BrowserPermissionSession,
			requestedKinds: BrowserPermissionKindSet,
			promptKinds: BrowserPermissionKindSet
		) {
			injectSessionRecordForTesting(
				session,
				requestedKinds: requestedKinds,
				promptKinds: promptKinds,
				trackInBrowserOrder: true
			)
		}

		func injectSessionRecordForTesting(
			_ session: BrowserPermissionSession,
			requestedKinds: BrowserPermissionKindSet,
			promptKinds: BrowserPermissionKindSet,
			trackInBrowserOrder: Bool
		) {
			sessionsByID[session.id] = SessionRecord(
				session: session,
				requestedKinds: requestedKinds,
				promptKinds: promptKinds
			)
			if trackInBrowserOrder {
				sessionOrderByBrowser[session.browserID, default: []].append(session.id)
			}
		}

		func appendStaleSessionIDForTesting(
			_ sessionID: BrowserPermissionSessionID,
			browserKey: BrowserKey
		) {
			sessionOrderByBrowser[browserKey, default: []].append(sessionID)
		}

		func requestOSAuthorizationForTesting(
			sessionID: BrowserPermissionSessionID,
			rememberDecision: Bool,
			now: Date
		) {
			requestOSAuthorization(for: sessionID, rememberDecision: rememberDecision, now: now)
		}

		func expireSessionsForTesting(
			now: Date,
			timeoutInterval: TimeInterval
		) {
			expireSessions(now: now, timeoutInterval: timeoutInterval)
		}

		func removeSessionForTesting(_ sessionID: BrowserPermissionSessionID) {
			removeSession(sessionID)
		}
	}
#endif
