import Foundation
import ModelKit

struct BrowserRuntimeCEFBridgePermissionRequest {
	var session_id: UInt64
	var browser_id: UInt64
	var prompt_id: UInt64
	var frame_identifier: UnsafePointer<CChar>?
	var permission_flags: UInt32
	var source: UInt32
	var requesting_origin: UnsafePointer<CChar>?
	var top_level_origin: UnsafePointer<CChar>?
}

private typealias CEFBridgePermissionRequestCallback = @convention(c) (
	UnsafeMutableRawPointer?,
	UnsafeRawPointer?
) -> Void

private typealias CEFBridgePermissionSessionDismissedCallback = @convention(c) (
	UnsafeMutableRawPointer?,
	UInt64,
	UInt32
) -> Void

@_silgen_name("CEFBridge_SetPermissionRequestHandler")
private func browserRuntimeCEFBridgeSetPermissionRequestHandler(
	_ browserRef: CEFBridgeBrowserRef?,
	_ callback: CEFBridgePermissionRequestCallback?,
	_ userData: UnsafeMutableRawPointer?
)

@_silgen_name("CEFBridge_SetPermissionSessionDismissedHandler")
private func browserRuntimeCEFBridgeSetPermissionSessionDismissedHandler(
	_ browserRef: CEFBridgeBrowserRef?,
	_ callback: CEFBridgePermissionSessionDismissedCallback?,
	_ userData: UnsafeMutableRawPointer?
)

@_silgen_name("CEFBridge_ResolvePermissionRequest")
func browserRuntimeCEFBridgeResolvePermissionRequest(
	_ sessionID: UInt64,
	_ resolution: UInt32
) -> Int32

final class BrowserRuntimePermissionBridge {
	static let defaultSessionTimeoutInterval: TimeInterval = 5 * 60

	private struct BrowserCallbacks {
		let handleRequest: @MainActor (BrowserPermissionNativeRequest) -> Void
		let handleDismissed: @MainActor (BrowserPermissionSessionID, BrowserPermissionSessionDismissReason) -> Void
	}

	typealias BrowserKey = UInt64
	typealias NowProvider = @MainActor () -> Date?

	@MainActor private static var callbacksByBrowserKey = [BrowserKey: BrowserCallbacks]()

	private let permissionStoreFactory: @MainActor () -> BrowserPermissionDecisionStoring
	private let permissionAuthorizerFactory: @MainActor () -> BrowserPermissionAuthorizing
	private let resolveNativePermissionSession: (BrowserPermissionSessionID, BrowserPermissionResolution) -> Void
	private let sessionTimeoutInterval: TimeInterval
	@MainActor private lazy var service = BrowserPermissionService(
		store: permissionStoreFactory(),
		authorizer: permissionAuthorizerFactory(),
		resolveNativeSession: resolveNativePermissionSession
	)
	private var nowProvider: NowProvider?

	init(
		permissionStoreFactory: @escaping @MainActor () -> BrowserPermissionDecisionStoring,
		permissionAuthorizerFactory: @escaping @MainActor () -> BrowserPermissionAuthorizing,
		resolveNativePermissionSession: @escaping (BrowserPermissionSessionID, BrowserPermissionResolution) -> Void,
		sessionTimeoutInterval: TimeInterval = BrowserRuntimePermissionBridge.defaultSessionTimeoutInterval
	) {
		self.permissionStoreFactory = permissionStoreFactory
		self.permissionAuthorizerFactory = permissionAuthorizerFactory
		self.resolveNativePermissionSession = resolveNativePermissionSession
		self.sessionTimeoutInterval = sessionTimeoutInterval
	}

	func configureNowProvider(_ provider: @escaping NowProvider) {
		nowProvider = provider
	}

	@MainActor
	func register(browser: CEFBridgeBrowserRef) {
		let browserKey = Self.browserKey(for: browser)
		Self.callbacksByBrowserKey[browserKey] = makeBrowserCallbacks()
		browserRuntimeCEFBridgeSetPermissionRequestHandler(browser, Self.permissionRequestCallback, browser)
		browserRuntimeCEFBridgeSetPermissionSessionDismissedHandler(
			browser,
			Self.permissionSessionDismissedCallback,
			browser
		)
	}

	@MainActor
	func unregister(browser: CEFBridgeBrowserRef) {
		let browserKey = Self.browserKey(for: browser)
		Self.callbacksByBrowserKey.removeValue(forKey: browserKey)
		service.clearBrowser(browserKey)
	}

	@MainActor
	func clearNativeHandlers(for browser: CEFBridgeBrowserRef) {
		browserRuntimeCEFBridgeSetPermissionRequestHandler(browser, nil, nil)
		browserRuntimeCEFBridgeSetPermissionSessionDismissedHandler(browser, nil, nil)
	}

	@MainActor
	func setPromptHandler(
		for browser: CEFBridgeBrowserRef?,
		handler: ((BrowserPermissionSession?) -> Void)?
	) {
		guard let browser else { return }
		service.setPromptHandler(
			for: Self.browserKey(for: browser),
			handler: handler
		)
	}

	@MainActor
	func handleRequest(_ request: BrowserPermissionNativeRequest, now: Date) {
		service.handleRequest(request, now: now)
	}

	@MainActor
	func resolvePrompt(
		sessionID: BrowserPermissionSessionID,
		decision: BrowserPermissionPromptDecision,
		persistence: BrowserPermissionPersistence,
		now: Date
	) {
		service.decide(
			sessionID: sessionID,
			decision: decision,
			persistence: persistence,
			now: now
		)
	}

	@MainActor
	func cancelPrompt(sessionID: BrowserPermissionSessionID, now: Date) {
		service.cancel(sessionID: sessionID, now: now)
	}

	@MainActor
	func dismissSession(
		sessionID: BrowserPermissionSessionID,
		reason: BrowserPermissionSessionDismissReason,
		now: Date
	) {
		service.dismissSession(
			sessionID: sessionID,
			reason: reason,
			now: now
		)
	}

	@MainActor
	func dumpState() -> String {
		service.dumpState()
	}

	@MainActor
	func expireTimedOutSessions(now: Date) {
		service.expireSessions(now: now, timeoutInterval: sessionTimeoutInterval)
	}

	@MainActor
	private func makeBrowserCallbacks() -> BrowserCallbacks {
		BrowserCallbacks(
			handleRequest: { [weak self] request in
				guard let self, let now = self.nowProvider?() else { return }
				self.service.handleRequest(request, now: now)
			},
			handleDismissed: { [weak self] sessionID, reason in
				guard let self, let now = self.nowProvider?() else { return }
				self.service.dismissSession(
					sessionID: sessionID,
					reason: reason,
					now: now
				)
			}
		)
	}

	private static func browserKey(for browser: CEFBridgeBrowserRef) -> BrowserKey {
		UInt64(UInt(bitPattern: browser))
	}

	private nonisolated static let permissionRequestCallback: CEFBridgePermissionRequestCallback = {
		userData,
			requestPointer in
		handlePermissionRequestCallback(userData: userData, requestPointer: requestPointer)
	}

	private nonisolated static let permissionSessionDismissedCallback:
		CEFBridgePermissionSessionDismissedCallback = { userData, sessionID, reason in
			handlePermissionDismissedCallback(
				userData: userData,
				sessionID: sessionID,
				reason: reason
			)
		}

	private nonisolated static func handlePermissionRequestCallback(
		userData: UnsafeMutableRawPointer?,
		requestPointer: UnsafeRawPointer?
	) {
		guard let userData, let requestPointer else {
			debugLog("[Navigator] permissionRequestCallback dropped: missing payload")
			return
		}

		let browserKey = UInt64(UInt(bitPattern: userData))
		let rawRequest = requestPointer.assumingMemoryBound(
			to: BrowserRuntimeCEFBridgePermissionRequest.self
		).pointee
		let request = BrowserPermissionNativeRequest(
			sessionID: rawRequest.session_id,
			browserID: rawRequest.browser_id,
			promptID: rawRequest.prompt_id,
			frameIdentifier: rawRequest.frame_identifier.map(String.init(cString:)),
			permissionFlags: rawRequest.permission_flags,
			source: BrowserPermissionRequestSource(rawValue: rawRequest.source) ?? .permissionPrompt,
			requestingOrigin: rawRequest.requesting_origin.map(String.init(cString:)) ?? "",
			topLevelOrigin: rawRequest.top_level_origin.map(String.init(cString:)) ?? ""
		)
		debugLog(
			"[Navigator] permissionRequestCallback browserKey=\(browserKey) session=\(request.sessionID) flags=\(request.permissionFlags)"
		)

		Task { @MainActor [browserKey, request] in
			guard let callbacks = callbacksByBrowserKey[browserKey] else {
				debugLog("[Navigator] permissionRequestCallback dropped missing runtime for browserKey=\(browserKey)")
				return
			}
			callbacks.handleRequest(request)
		}
	}

	private nonisolated static func handlePermissionDismissedCallback(
		userData: UnsafeMutableRawPointer?,
		sessionID: BrowserPermissionSessionID,
		reason: UInt32
	) {
		guard let userData else {
			debugLog("[Navigator] permissionDismissedCallback dropped: missing userData")
			return
		}

		let browserKey = UInt64(UInt(bitPattern: userData))
		let dismissReason = BrowserPermissionSessionDismissReason(rawValue: reason) ?? .unknown
		debugLog(
			"[Navigator] permissionDismissedCallback browserKey=\(browserKey) session=\(sessionID) reason=\(reason)"
		)

		Task { @MainActor [browserKey, sessionID, dismissReason] in
			guard let callbacks = callbacksByBrowserKey[browserKey] else {
				debugLog(
					"[Navigator] permissionDismissedCallback dropped missing runtime for browserKey=\(browserKey)"
				)
				return
			}
			callbacks.handleDismissed(sessionID, dismissReason)
		}
	}

	private nonisolated static func debugLog(_ message: @autoclosure () -> String) {
		#if DEBUG
			print(message())
		#endif
	}

	#if DEBUG
		nonisolated static func invokeStoredPermissionRequestCallbackForTesting(
			userData: UnsafeMutableRawPointer?,
			requestPointer: UnsafeRawPointer?
		) {
			permissionRequestCallback(userData, requestPointer)
		}

		nonisolated static func invokeStoredPermissionDismissedCallbackForTesting(
			userData: UnsafeMutableRawPointer?,
			sessionID: BrowserPermissionSessionID,
			reason: UInt32
		) {
			permissionSessionDismissedCallback(userData, sessionID, reason)
		}

		@MainActor
		func registerBrowserForTesting(_ browser: CEFBridgeBrowserRef) {
			let browserKey = Self.browserKey(for: browser)
			Self.callbacksByBrowserKey[browserKey] = makeBrowserCallbacks()
		}

		@MainActor
		func unregisterBrowserForTesting(_ browser: CEFBridgeBrowserRef) {
			let browserKey = Self.browserKey(for: browser)
			Self.callbacksByBrowserKey.removeValue(forKey: browserKey)
		}

		nonisolated static func invokePermissionRequestCallbackForTesting(
			userData: UnsafeMutableRawPointer?,
			requestPointer: UnsafeRawPointer?
		) {
			handlePermissionRequestCallback(
				userData: userData,
				requestPointer: requestPointer
			)
		}

		nonisolated static func invokePermissionDismissedCallbackForTesting(
			userData: UnsafeMutableRawPointer?,
			sessionID: BrowserPermissionSessionID,
			reason: UInt32
		) {
			handlePermissionDismissedCallback(
				userData: userData,
				sessionID: sessionID,
				reason: reason
			)
		}
	#endif
}
