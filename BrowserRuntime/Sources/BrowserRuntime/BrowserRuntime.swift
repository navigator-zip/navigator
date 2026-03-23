import AppKit
import Darwin
import Foundation
import ModelKit
import Vendors

public typealias CEFBridgeBrowserRef = UnsafeMutableRawPointer
public typealias CEFBridgeMessageCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?)
	-> Void

@_silgen_name("CEFBridge_SetTopLevelNativeContentHandler")
private func browserRuntimeCEFBridgeSetTopLevelNativeContentHandler(
	_ browserRef: CEFBridgeBrowserRef?,
	_ callback: CEFBridgeMessageCallback?,
	_ userData: UnsafeMutableRawPointer?
)

@_silgen_name("CEFBridge_SetMainFrameNavigationHandler")
private func browserRuntimeCEFBridgeSetMainFrameNavigationHandler(
	_ browserRef: CEFBridgeBrowserRef?,
	_ callback: CEFBridgeMessageCallback?,
	_ userData: UnsafeMutableRawPointer?
)

@_silgen_name("CEFBridge_SetOpenURLInTabHandler")
private func browserRuntimeCEFBridgeSetOpenURLInTabHandler(
	_ browserRef: CEFBridgeBrowserRef?,
	_ callback: CEFBridgeMessageCallback?,
	_ userData: UnsafeMutableRawPointer?
)

@_silgen_name("CEFBridge_SetCameraRoutingEventHandler")
private func browserRuntimeCEFBridgeSetCameraRoutingEventHandler(
	_ browserRef: CEFBridgeBrowserRef?,
	_ callback: CEFBridgeMessageCallback?,
	_ userData: UnsafeMutableRawPointer?
)

public struct BrowserRuntimePictureInPictureState: Sendable, Equatable, Decodable {
	public struct ActiveVideo: Sendable, Equatable, Decodable {
		public let currentSourceURL: String?
		public let currentTimeSeconds: Double?
		public let durationSeconds: Double?
		public let playbackRate: Double?
		public let isPaused: Bool
		public let isEnded: Bool
		public let videoWidth: Int?
		public let videoHeight: Int?
	}

	public let sequenceNumber: Int
	public let event: String
	public let location: String?
	public let isCurrentWindowPictureInPicture: Bool
	public let isVideoPictureInPictureActive: Bool
	public let isVideoPictureInPictureSupported: Bool?
	public let isDocumentPictureInPictureSupported: Bool
	public let isDocumentPictureInPictureWindowOpen: Bool
	public let currentWindowInnerWidth: Int?
	public let currentWindowInnerHeight: Int?
	public let videoPictureInPictureWindowWidth: Int?
	public let videoPictureInPictureWindowHeight: Int?
	public let documentPictureInPictureWindowWidth: Int?
	public let documentPictureInPictureWindowHeight: Int?
	public let activeVideo: ActiveVideo?
	public let videoElementCount: Int?
	public let errorDescription: String?

	static func from(json: String) -> BrowserRuntimePictureInPictureState? {
		guard let data = json.data(using: .utf8) else { return nil }
		return try? JSONDecoder().decode(Self.self, from: data)
	}
}

public struct BrowserRuntimeRenderProcessTermination: Sendable, Equatable, Decodable {
	public let status: Int
	public let errorCode: Int
	public let errorDescription: String

	public init(status: Int, errorCode: Int, errorDescription: String) {
		self.status = status
		self.errorCode = errorCode
		self.errorDescription = errorDescription
	}

	static func from(json: String) -> BrowserRuntimeRenderProcessTermination? {
		guard let data = json.data(using: .utf8) else { return nil }
		return try? JSONDecoder().decode(Self.self, from: data)
	}
}

public struct BrowserRuntimeMainFrameNavigationEvent: Sendable, Equatable, Decodable {
	public let url: String
	public let userGesture: Bool
	public let isRedirect: Bool

	public init(url: String, userGesture: Bool, isRedirect: Bool) {
		self.url = url
		self.userGesture = userGesture
		self.isRedirect = isRedirect
	}

	static func from(json: String) -> BrowserRuntimeMainFrameNavigationEvent? {
		guard let data = json.data(using: .utf8) else { return nil }
		return try? JSONDecoder().decode(Self.self, from: data)
	}
}

public struct BrowserRuntimeOpenURLInTabEvent: Sendable, Equatable, Decodable {
	public let url: String
	public let activatesTab: Bool

	public init(url: String, activatesTab: Bool) {
		self.url = url
		self.activatesTab = activatesTab
	}

	static func from(json: String) -> BrowserRuntimeOpenURLInTabEvent? {
		guard let data = json.data(using: .utf8) else { return nil }
		return try? JSONDecoder().decode(Self.self, from: data)
	}
}

public struct BrowserRuntimeScrollPosition: Sendable, Equatable {
	public let x: Double
	public let y: Double

	public init(x: Double, y: Double) {
		self.x = x
		self.y = y
	}
}

public struct BrowserRuntimeDiagnostics: Sendable {
	public let isInitialized: Bool
	public let hasTrackedBrowser: Bool
	public let trackedBrowserCount: Int
	public let trackedBrowserIdentifier: String?
	public let currentURL: String?
	public let canGoBack: Bool?
	public let canGoForward: Bool?
	public let isLoading: Bool?
	public let resourcesPath: String
	public let localesPath: String
	public let cachePath: String
	public let subprocessPath: String
	public let resourcesPathExists: Bool
	public let localesPathExists: Bool
	public let cachePathExists: Bool
	public let subprocessPathExists: Bool
	public let lastUserActivityAgeSeconds: TimeInterval
	public let lastActivitySignalAgeSeconds: TimeInterval

	public init(
		isInitialized: Bool,
		hasTrackedBrowser: Bool,
		trackedBrowserCount: Int,
		trackedBrowserIdentifier: String?,
		currentURL: String?,
		canGoBack: Bool?,
		canGoForward: Bool?,
		isLoading: Bool?,
		resourcesPath: String,
		localesPath: String,
		cachePath: String,
		subprocessPath: String,
		resourcesPathExists: Bool,
		localesPathExists: Bool,
		cachePathExists: Bool,
		subprocessPathExists: Bool,
		lastUserActivityAgeSeconds: TimeInterval,
		lastActivitySignalAgeSeconds: TimeInterval
	) {
		self.isInitialized = isInitialized
		self.hasTrackedBrowser = hasTrackedBrowser
		self.trackedBrowserCount = trackedBrowserCount
		self.trackedBrowserIdentifier = trackedBrowserIdentifier
		self.currentURL = currentURL
		self.canGoBack = canGoBack
		self.canGoForward = canGoForward
		self.isLoading = isLoading
		self.resourcesPath = resourcesPath
		self.localesPath = localesPath
		self.cachePath = cachePath
		self.subprocessPath = subprocessPath
		self.resourcesPathExists = resourcesPathExists
		self.localesPathExists = localesPathExists
		self.cachePathExists = cachePathExists
		self.subprocessPathExists = subprocessPathExists
		self.lastUserActivityAgeSeconds = lastUserActivityAgeSeconds
		self.lastActivitySignalAgeSeconds = lastActivitySignalAgeSeconds
	}
}

private func withOptionalCString<Result>(
	_ value: String?,
	_ body: (UnsafePointer<CChar>?) -> Result
) -> Result {
	guard let value else { return body(nil) }
	return value.withCString(body)
}

@MainActor
private final class BrowserRuntimeJavaScriptResultBox {
	let completion: @MainActor (String?, String?) -> Void

	init(completion: @escaping @MainActor (String?, String?) -> Void) {
		self.completion = completion
	}
}

enum BrowserRuntimeBridgeMessageKind {
	case address
	case title
	case faviconURL
	case pictureInPictureState
	case topLevelNativeContent
	case renderProcessTermination
	case mainFrameNavigation
	case openURLInTab
	case cameraRoutingEvent
}

@MainActor
struct BrowserRuntimeBridgeMessageState {
	typealias BrowserKey = UInt64

	private var addressHandlers = [BrowserKey: (String) -> Void]()
	private var titleHandlers = [BrowserKey: (String) -> Void]()
	private var faviconURLHandlers = [BrowserKey: (String) -> Void]()
	private var pictureInPictureStateHandlers = [BrowserKey: (BrowserRuntimePictureInPictureState) -> Void]()
	private var topLevelNativeContentHandlers = [BrowserKey: (BrowserRuntimeTopLevelNativeContent) -> Void]()
	private var renderProcessTerminationHandlers = [BrowserKey: (BrowserRuntimeRenderProcessTermination) -> Void]()
	private var mainFrameNavigationHandlers = [BrowserKey: (BrowserRuntimeMainFrameNavigationEvent) -> Void]()
	private var openURLInTabHandlers = [BrowserKey: (BrowserRuntimeOpenURLInTabEvent) -> Void]()
	private var cameraRoutingEventHandlers = [BrowserKey: (BrowserCameraRoutingEvent) -> Void]()
	private var lastAddressByBrowser = [BrowserKey: String]()
	private var lastTitleByBrowser = [BrowserKey: String]()
	private var lastFaviconURLByBrowser = [BrowserKey: String]()
	private var lastPictureInPictureStateByBrowser = [BrowserKey: BrowserRuntimePictureInPictureState]()
	private var lastTopLevelNativeContentByBrowser = [BrowserKey: BrowserRuntimeTopLevelNativeContent]()
	private var lastRenderProcessTerminationByBrowser = [BrowserKey: BrowserRuntimeRenderProcessTermination]()

	mutating func setHandler(
		_ handler: ((String) -> Void)?,
		for browserKey: BrowserKey,
		kind: BrowserRuntimeBridgeMessageKind
	) {
		switch kind {
		case .address:
			addressHandlers[browserKey] = handler
			if handler == nil {
				lastAddressByBrowser.removeValue(forKey: browserKey)
			}
		case .title:
			titleHandlers[browserKey] = handler
			if handler == nil {
				lastTitleByBrowser.removeValue(forKey: browserKey)
			}
		case .faviconURL:
			faviconURLHandlers[browserKey] = handler
			if handler == nil {
				lastFaviconURLByBrowser.removeValue(forKey: browserKey)
			}
		case .pictureInPictureState:
			break
		case .topLevelNativeContent:
			break
		case .renderProcessTermination:
			break
		case .mainFrameNavigation:
			break
		case .openURLInTab:
			break
		case .cameraRoutingEvent:
			break
		}
	}

	mutating func setPictureInPictureStateHandler(
		_ handler: ((BrowserRuntimePictureInPictureState) -> Void)?,
		for browserKey: BrowserKey
	) {
		pictureInPictureStateHandlers[browserKey] = handler
		if handler == nil {
			lastPictureInPictureStateByBrowser.removeValue(forKey: browserKey)
		}
	}

	mutating func setTopLevelNativeContentHandler(
		_ handler: ((BrowserRuntimeTopLevelNativeContent) -> Void)?,
		for browserKey: BrowserKey
	) {
		topLevelNativeContentHandlers[browserKey] = handler
		if handler == nil {
			lastTopLevelNativeContentByBrowser.removeValue(forKey: browserKey)
		}
	}

	mutating func setRenderProcessTerminationHandler(
		_ handler: ((BrowserRuntimeRenderProcessTermination) -> Void)?,
		for browserKey: BrowserKey
	) {
		renderProcessTerminationHandlers[browserKey] = handler
		if handler == nil {
			lastRenderProcessTerminationByBrowser.removeValue(forKey: browserKey)
		}
	}

	mutating func setMainFrameNavigationHandler(
		_ handler: ((BrowserRuntimeMainFrameNavigationEvent) -> Void)?,
		for browserKey: BrowserKey
	) {
		mainFrameNavigationHandlers[browserKey] = handler
	}

	mutating func setOpenURLInTabHandler(
		_ handler: ((BrowserRuntimeOpenURLInTabEvent) -> Void)?,
		for browserKey: BrowserKey
	) {
		openURLInTabHandlers[browserKey] = handler
	}

	mutating func setCameraRoutingEventHandler(
		_ handler: ((BrowserCameraRoutingEvent) -> Void)?,
		for browserKey: BrowserKey
	) {
		cameraRoutingEventHandlers[browserKey] = handler
	}

	mutating func consumeMessage(
		_ message: String,
		for browserKey: BrowserKey,
		kind: BrowserRuntimeBridgeMessageKind
	) -> ((String) -> Void)? {
		switch kind {
		case .address:
			guard let handler = addressHandlers[browserKey] else { return nil }
			guard lastAddressByBrowser[browserKey] != message else { return nil }
			lastAddressByBrowser[browserKey] = message
			return handler
		case .title:
			guard let handler = titleHandlers[browserKey] else { return nil }
			guard lastTitleByBrowser[browserKey] != message else { return nil }
			lastTitleByBrowser[browserKey] = message
			return handler
		case .faviconURL:
			guard let handler = faviconURLHandlers[browserKey] else { return nil }
			guard lastFaviconURLByBrowser[browserKey] != message else { return nil }
			lastFaviconURLByBrowser[browserKey] = message
			return handler
		case .pictureInPictureState:
			return nil
		case .topLevelNativeContent:
			return nil
		case .renderProcessTermination:
			return nil
		case .mainFrameNavigation:
			return nil
		case .openURLInTab:
			return nil
		case .cameraRoutingEvent:
			return nil
		}
	}

	func hasHandler(
		for browserKey: BrowserKey,
		kind: BrowserRuntimeBridgeMessageKind
	) -> Bool {
		switch kind {
		case .address:
			addressHandlers[browserKey] != nil
		case .title:
			titleHandlers[browserKey] != nil
		case .faviconURL:
			faviconURLHandlers[browserKey] != nil
		case .pictureInPictureState:
			pictureInPictureStateHandlers[browserKey] != nil
		case .topLevelNativeContent:
			topLevelNativeContentHandlers[browserKey] != nil
		case .renderProcessTermination:
			renderProcessTerminationHandlers[browserKey] != nil
		case .mainFrameNavigation:
			mainFrameNavigationHandlers[browserKey] != nil
		case .openURLInTab:
			openURLInTabHandlers[browserKey] != nil
		case .cameraRoutingEvent:
			cameraRoutingEventHandlers[browserKey] != nil
		}
	}

	mutating func consumePictureInPictureState(
		_ state: BrowserRuntimePictureInPictureState,
		for browserKey: BrowserKey
	) -> ((BrowserRuntimePictureInPictureState) -> Void)? {
		guard let handler = pictureInPictureStateHandlers[browserKey] else { return nil }
		guard lastPictureInPictureStateByBrowser[browserKey] != state else { return nil }
		lastPictureInPictureStateByBrowser[browserKey] = state
		return handler
	}

	mutating func consumeTopLevelNativeContent(
		_ content: BrowserRuntimeTopLevelNativeContent,
		for browserKey: BrowserKey
	) -> ((BrowserRuntimeTopLevelNativeContent) -> Void)? {
		guard let handler = topLevelNativeContentHandlers[browserKey] else { return nil }
		guard lastTopLevelNativeContentByBrowser[browserKey] != content else { return nil }
		lastTopLevelNativeContentByBrowser[browserKey] = content
		return handler
	}

	mutating func consumeRenderProcessTermination(
		_ termination: BrowserRuntimeRenderProcessTermination,
		for browserKey: BrowserKey
	) -> ((BrowserRuntimeRenderProcessTermination) -> Void)? {
		guard let handler = renderProcessTerminationHandlers[browserKey] else { return nil }
		guard lastRenderProcessTerminationByBrowser[browserKey] != termination else { return nil }
		lastRenderProcessTerminationByBrowser[browserKey] = termination
		return handler
	}

	mutating func consumeMainFrameNavigationEvent(
		_ event: BrowserRuntimeMainFrameNavigationEvent,
		for browserKey: BrowserKey
	) -> ((BrowserRuntimeMainFrameNavigationEvent) -> Void)? {
		guard let handler = mainFrameNavigationHandlers[browserKey] else { return nil }
		return handler
	}

	mutating func consumeOpenURLInTabEvent(
		_ event: BrowserRuntimeOpenURLInTabEvent,
		for browserKey: BrowserKey
	) -> ((BrowserRuntimeOpenURLInTabEvent) -> Void)? {
		guard let handler = openURLInTabHandlers[browserKey] else { return nil }
		return handler
	}

	mutating func consumeCameraRoutingEvent(
		_ event: BrowserCameraRoutingEvent,
		for browserKey: BrowserKey
	) -> ((BrowserCameraRoutingEvent) -> Void)? {
		guard let handler = cameraRoutingEventHandlers[browserKey] else { return nil }
		return handler
	}

	func lastMessage(
		for browserKey: BrowserKey,
		kind: BrowserRuntimeBridgeMessageKind
	) -> String? {
		switch kind {
		case .address:
			lastAddressByBrowser[browserKey]
		case .title:
			lastTitleByBrowser[browserKey]
		case .faviconURL:
			lastFaviconURLByBrowser[browserKey]
		case .pictureInPictureState:
			nil
		case .topLevelNativeContent:
			nil
		case .renderProcessTermination:
			nil
		case .mainFrameNavigation:
			nil
		case .openURLInTab:
			nil
		case .cameraRoutingEvent:
			nil
		}
	}

	func lastPictureInPictureState(for browserKey: BrowserKey) -> BrowserRuntimePictureInPictureState? {
		lastPictureInPictureStateByBrowser[browserKey]
	}

	func lastTopLevelNativeContent(for browserKey: BrowserKey) -> BrowserRuntimeTopLevelNativeContent? {
		lastTopLevelNativeContentByBrowser[browserKey]
	}

	func lastRenderProcessTermination(for browserKey: BrowserKey) -> BrowserRuntimeRenderProcessTermination? {
		lastRenderProcessTerminationByBrowser[browserKey]
	}

	mutating func clear(for browserKey: BrowserKey) {
		addressHandlers.removeValue(forKey: browserKey)
		titleHandlers.removeValue(forKey: browserKey)
		faviconURLHandlers.removeValue(forKey: browserKey)
		pictureInPictureStateHandlers.removeValue(forKey: browserKey)
		topLevelNativeContentHandlers.removeValue(forKey: browserKey)
		renderProcessTerminationHandlers.removeValue(forKey: browserKey)
		mainFrameNavigationHandlers.removeValue(forKey: browserKey)
		openURLInTabHandlers.removeValue(forKey: browserKey)
		cameraRoutingEventHandlers.removeValue(forKey: browserKey)
		lastAddressByBrowser.removeValue(forKey: browserKey)
		lastTitleByBrowser.removeValue(forKey: browserKey)
		lastFaviconURLByBrowser.removeValue(forKey: browserKey)
		lastPictureInPictureStateByBrowser.removeValue(forKey: browserKey)
		lastTopLevelNativeContentByBrowser.removeValue(forKey: browserKey)
		lastRenderProcessTerminationByBrowser.removeValue(forKey: browserKey)
	}
}

public final class BrowserRuntime: @unchecked Sendable {
	private typealias BrowserKey = UInt64

	private struct RuntimeLayoutConfiguration {
		let resourcesRelativePath: String?
		let localesRelativePath: String?
		let helpersDirectoryRelativePath: String?
	}

	private struct RuntimePaths {
		let metadataPath: String
		let runtimeRootPath: String
		let resourcesPath: String
		let localesPath: String?
		let helpersDirectoryPath: String?
	}

	@MainActor private(set) var isInitialized = false
	@MainActor private static var bridgeMessageState = BrowserRuntimeBridgeMessageState()

	@Dependency(\.date.now) private var now

	@MainActor private var messageLoopTimer: DispatchSourceTimer?
	@MainActor private var trackedBrowsers = [BrowserKey: CEFBridgeBrowserRef]()
	@MainActor private var browserSelectionOrder = [BrowserKey]()
	@MainActor private var lastUserActivityUptime = ProcessInfo.processInfo.systemUptime
	@MainActor private var lastActivitySignalUptime = ProcessInfo.processInfo.systemUptime
	private let permissionBridge: BrowserRuntimePermissionBridge

	private enum MessageLoop {
		static let activeInterval: TimeInterval = 1.0 / 60.0
		static let idleInterval: TimeInterval = 1.0 / 24.0
		static let activityWindow: TimeInterval = 0.8
		static let externalPumpFallbackWindow: TimeInterval = 3.0
		static let leeway: DispatchTimeInterval = .milliseconds(1)
		static let activitySignalInterval: TimeInterval = 1.0 / 120.0
	}

	private enum ExternalMessagePumpFeatureFlag {
		static let environmentKey = "MIUM_CEF_ENABLE_EXTERNAL_MESSAGE_PUMP"

		static func isEnabled(environment: [String: String]) -> Bool {
			guard let rawValue = environment[environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
			      rawValue.isEmpty == false
			else {
				return true
			}

			switch rawValue.lowercased() {
			case "0", "false", "no", "off", "disabled":
				return false
			default:
				return true
			}
		}
	}

	private let cacheDirectoryName = "NavigatorCEFCache"
	private let cacheCompatibilityMarkerFileName = ".navigator-cef-cache-stamp"
	private let cacheCompatibilitySchemaVersion = 1
	private let processPathBufferSize = 4 * Int(MAXPATHLEN)

	private nonisolated static func debugLog(_ message: @autoclosure () -> String) {
		#if DEBUG
			print(message())
		#endif
	}

	public init() {
		permissionBridge = BrowserRuntimePermissionBridge(
			permissionStoreFactory: { BrowserPermissionDecisionStore() },
			permissionAuthorizerFactory: { BrowserPermissionAuthorizationController() },
			resolveNativePermissionSession: { sessionID, resolution in
				_ = browserRuntimeCEFBridgeResolvePermissionRequest(sessionID, resolution.rawValue)
			}
		)
		permissionBridge.configureNowProvider { [weak self] in
			self?.now
		}
	}

	init(
		permissionStoreFactory: @escaping @MainActor () -> BrowserPermissionDecisionStoring,
		permissionAuthorizerFactory: @escaping @MainActor () -> BrowserPermissionAuthorizing,
		resolveNativePermissionSession: @escaping (BrowserPermissionSessionID, BrowserPermissionResolution) -> Void
	) {
		permissionBridge = BrowserRuntimePermissionBridge(
			permissionStoreFactory: permissionStoreFactory,
			permissionAuthorizerFactory: permissionAuthorizerFactory,
			resolveNativePermissionSession: resolveNativePermissionSession
		)
		permissionBridge.configureNowProvider { [weak self] in
			self?.now
		}
	}

	@MainActor
	public func noteBrowserActivity() {
		recordBrowserActivity(for: nil, shouldThrottle: true)
	}

	private nonisolated static let addressChangeMessageCallback: CEFBridgeMessageCallback = { userData, message in
		guard let userData else {
			debugLog("[Navigator] addressChangeCallback dropped: missing userData")
			return
		}
		let browserKey = UInt64(UInt(bitPattern: userData))
		let currentMessage = message.map(String.init(cString:)) ?? ""
		debugLog("[Navigator] addressChangeCallback browserKey=\(browserKey) url=\(currentMessage)")

		Task { @MainActor [browserKey, currentMessage] in
			BrowserRuntime.handleBridgeMessage(
				browserKey: browserKey,
				currentMessage: currentMessage,
				kind: .address
			)
		}
	}

	private nonisolated static let titleChangeMessageCallback: CEFBridgeMessageCallback = { userData, message in
		guard let userData else {
			debugLog("[Navigator] titleChangeCallback dropped: missing userData")
			return
		}
		let browserKey = UInt64(UInt(bitPattern: userData))
		let currentMessage = message.map(String.init(cString:)) ?? ""
		debugLog("[Navigator] titleChangeCallback browserKey=\(browserKey) title=\(currentMessage)")

		Task { @MainActor [browserKey, currentMessage] in
			BrowserRuntime.handleBridgeMessage(
				browserKey: browserKey,
				currentMessage: currentMessage,
				kind: .title
			)
		}
	}

	private nonisolated static let faviconURLChangeMessageCallback: CEFBridgeMessageCallback = { userData, message in
		guard let userData else {
			debugLog("[Navigator] faviconURLChangeCallback dropped: missing userData")
			return
		}
		let browserKey = UInt64(UInt(bitPattern: userData))
		let currentMessage = message.map(String.init(cString:)) ?? ""
		debugLog("[Navigator] faviconURLChangeCallback browserKey=\(browserKey) url=\(currentMessage)")

		Task { @MainActor [browserKey, currentMessage] in
			BrowserRuntime.handleBridgeMessage(
				browserKey: browserKey,
				currentMessage: currentMessage,
				kind: .faviconURL
			)
		}
	}

	private nonisolated static let pictureInPictureStateChangeMessageCallback: CEFBridgeMessageCallback = {
		userData,
			message in
		guard let userData else {
			debugLog("[Navigator] pictureInPictureStateChangeCallback dropped: missing userData")
			return
		}
		let browserKey = UInt64(UInt(bitPattern: userData))
		let currentMessage = message.map(String.init(cString:)) ?? ""
		debugLog("[Navigator] pictureInPictureStateChangeCallback browserKey=\(browserKey) payload=\(currentMessage)")

		Task { @MainActor [browserKey, currentMessage] in
			BrowserRuntime.handlePictureInPictureStateMessage(
				browserKey: browserKey,
				currentMessage: currentMessage
			)
		}
	}

	private nonisolated static let topLevelNativeContentMessageCallback: CEFBridgeMessageCallback = {
		userData,
			message in
		guard let userData else {
			debugLog("[Navigator] topLevelNativeContentCallback dropped: missing userData")
			return
		}
		let browserKey = UInt64(UInt(bitPattern: userData))
		let currentMessage = message.map(String.init(cString:)) ?? ""
		debugLog("[Navigator] topLevelNativeContentCallback browserKey=\(browserKey) payload=\(currentMessage)")

		Task { @MainActor [browserKey, currentMessage] in
			BrowserRuntime.handleTopLevelNativeContentMessage(
				browserKey: browserKey,
				currentMessage: currentMessage
			)
		}
	}

	private nonisolated static let renderProcessTerminationMessageCallback: CEFBridgeMessageCallback = {
		userData,
			message in
		guard let userData else {
			debugLog("[Navigator] renderProcessTerminationCallback dropped: missing userData")
			return
		}
		let browserKey = UInt64(UInt(bitPattern: userData))
		let currentMessage = message.map(String.init(cString:)) ?? ""
		debugLog("[Navigator] renderProcessTerminationCallback browserKey=\(browserKey) payload=\(currentMessage)")

		Task { @MainActor [browserKey, currentMessage] in
			BrowserRuntime.handleRenderProcessTerminationMessage(
				browserKey: browserKey,
				currentMessage: currentMessage
			)
		}
	}

	private nonisolated static let mainFrameNavigationMessageCallback: CEFBridgeMessageCallback = {
		userData,
			message in
		guard let userData else {
			debugLog("[Navigator] mainFrameNavigationCallback dropped: missing userData")
			return
		}
		let browserKey = UInt64(UInt(bitPattern: userData))
		let currentMessage = message.map(String.init(cString:)) ?? ""
		debugLog("[Navigator] mainFrameNavigationCallback browserKey=\(browserKey) payload=\(currentMessage)")

		Task { @MainActor [browserKey, currentMessage] in
			BrowserRuntime.handleMainFrameNavigationMessage(
				browserKey: browserKey,
				currentMessage: currentMessage
			)
		}
	}

	private nonisolated static let openURLInTabMessageCallback: CEFBridgeMessageCallback = {
		userData,
			message in
		guard let userData else {
			debugLog("[Navigator] openURLInTabCallback dropped: missing userData")
			return
		}
		let browserKey = UInt64(UInt(bitPattern: userData))
		let currentMessage = message.map(String.init(cString:)) ?? ""
		debugLog("[Navigator] openURLInTabCallback browserKey=\(browserKey) payload=\(currentMessage)")

		Task { @MainActor [browserKey, currentMessage] in
			BrowserRuntime.handleOpenURLInTabMessage(
				browserKey: browserKey,
				currentMessage: currentMessage
			)
		}
	}

	private nonisolated static let cameraRoutingEventMessageCallback: CEFBridgeMessageCallback = {
		userData,
			message in
		guard let userData else {
			debugLog("[Navigator] cameraRoutingEventCallback dropped: missing userData")
			return
		}
		let browserKey = UInt64(UInt(bitPattern: userData))
		let currentMessage = message.map(String.init(cString:)) ?? ""
		debugLog("[Navigator] cameraRoutingEventCallback browserKey=\(browserKey) payload=\(currentMessage)")

		Task { @MainActor [browserKey, currentMessage] in
			BrowserRuntime.handleCameraRoutingEventMessage(
				browserKey: browserKey,
				currentMessage: currentMessage
			)
		}
	}

	@MainActor
	private static func handleBridgeMessage(
		browserKey: BrowserKey,
		currentMessage: String,
		kind: BrowserRuntimeBridgeMessageKind
	) {
		let hasHandler = bridgeMessageState.hasHandler(for: browserKey, kind: kind)
		guard let callback = bridgeMessageState.consumeMessage(
			currentMessage,
			for: browserKey,
			kind: kind
		) else {
			if !hasHandler {
				let callbackName = switch kind {
				case .address:
					"addressChangeCallback"
				case .title:
					"titleChangeCallback"
				case .faviconURL:
					"faviconURLChangeCallback"
				case .pictureInPictureState:
					"pictureInPictureStateChangeCallback"
				case .topLevelNativeContent:
					"topLevelNativeContentCallback"
				case .renderProcessTermination:
					"renderProcessTerminationCallback"
				case .mainFrameNavigation:
					"mainFrameNavigationCallback"
				case .openURLInTab:
					"openURLInTabCallback"
				case .cameraRoutingEvent:
					"cameraRoutingEventCallback"
				}
				debugLog("[Navigator] \(callbackName) dropped for browserKey=\(browserKey) message=\(currentMessage)")
			}
			return
		}
		callback(currentMessage)
	}

	@MainActor
	private static func handlePictureInPictureStateMessage(
		browserKey: BrowserKey,
		currentMessage: String
	) {
		guard let state = BrowserRuntimePictureInPictureState.from(json: currentMessage) else {
			debugLog(
				"[Navigator] pictureInPictureStateChangeCallback dropped invalid payload for browserKey=\(browserKey) payload=\(currentMessage)"
			)
			return
		}

		guard let callback = bridgeMessageState.consumePictureInPictureState(
			state,
			for: browserKey
		) else {
			return
		}
		callback(state)
	}

	@MainActor
	private static func handleTopLevelNativeContentMessage(
		browserKey: BrowserKey,
		currentMessage: String
	) {
		guard let content = BrowserRuntimeTopLevelNativeContent.from(json: currentMessage) else {
			debugLog(
				"[Navigator] topLevelNativeContentCallback dropped invalid payload for browserKey=\(browserKey) payload=\(currentMessage)"
			)
			return
		}

		guard let callback = bridgeMessageState.consumeTopLevelNativeContent(content, for: browserKey) else {
			return
		}
		callback(content)
	}

	@MainActor
	private static func handleRenderProcessTerminationMessage(
		browserKey: BrowserKey,
		currentMessage: String
	) {
		guard let termination = BrowserRuntimeRenderProcessTermination.from(json: currentMessage) else {
			debugLog(
				"[Navigator] renderProcessTerminationCallback dropped invalid payload for browserKey=\(browserKey) payload=\(currentMessage)"
			)
			return
		}

		guard let callback = bridgeMessageState.consumeRenderProcessTermination(termination, for: browserKey) else {
			return
		}
		callback(termination)
	}

	@MainActor
	private static func handleMainFrameNavigationMessage(
		browserKey: BrowserKey,
		currentMessage: String
	) {
		guard let event = BrowserRuntimeMainFrameNavigationEvent.from(json: currentMessage) else {
			debugLog(
				"[Navigator] mainFrameNavigationCallback dropped invalid payload for browserKey=\(browserKey) payload=\(currentMessage)"
			)
			return
		}

		guard let callback = bridgeMessageState.consumeMainFrameNavigationEvent(event, for: browserKey) else {
			return
		}
		callback(event)
	}

	@MainActor
	private static func handleOpenURLInTabMessage(
		browserKey: BrowserKey,
		currentMessage: String
	) {
		guard let event = BrowserRuntimeOpenURLInTabEvent.from(json: currentMessage) else {
			debugLog(
				"[Navigator] openURLInTabCallback dropped invalid payload for browserKey=\(browserKey) payload=\(currentMessage)"
			)
			return
		}

		guard let callback = bridgeMessageState.consumeOpenURLInTabEvent(event, for: browserKey) else {
			return
		}
		callback(event)
	}

	@MainActor
	private static func handleCameraRoutingEventMessage(
		browserKey: BrowserKey,
		currentMessage: String
	) {
		guard let data = currentMessage.data(using: .utf8),
		      let event = try? JSONDecoder().decode(BrowserCameraRoutingEvent.self, from: data)
		else {
			debugLog(
				"[Navigator] cameraRoutingEventCallback dropped invalid payload for browserKey=\(browserKey) payload=\(currentMessage)"
			)
			return
		}

		guard let callback = bridgeMessageState.consumeCameraRoutingEvent(event, for: browserKey) else {
			return
		}
		callback(event)
	}

	@MainActor
	private static func setAddressChangeHandler(_ browser: CEFBridgeBrowserRef, handler: ((String) -> Void)?) {
		let key = browserKey(for: browser)
		bridgeMessageState.setHandler(handler, for: key, kind: .address)
	}

	@MainActor
	private static func setTitleChangeHandler(_ browser: CEFBridgeBrowserRef, handler: ((String) -> Void)?) {
		let key = browserKey(for: browser)
		bridgeMessageState.setHandler(handler, for: key, kind: .title)
	}

	@MainActor
	private static func setFaviconURLChangeHandler(_ browser: CEFBridgeBrowserRef, handler: ((String) -> Void)?) {
		let key = browserKey(for: browser)
		bridgeMessageState.setHandler(handler, for: key, kind: .faviconURL)
	}

	@MainActor
	private static func setPictureInPictureStateChangeHandler(
		_ browser: CEFBridgeBrowserRef,
		handler: ((BrowserRuntimePictureInPictureState) -> Void)?
	) {
		let key = browserKey(for: browser)
		bridgeMessageState.setPictureInPictureStateHandler(handler, for: key)
	}

	@MainActor
	private static func setTopLevelNativeContentHandler(
		_ browser: CEFBridgeBrowserRef,
		handler: ((BrowserRuntimeTopLevelNativeContent) -> Void)?
	) {
		let key = browserKey(for: browser)
		bridgeMessageState.setTopLevelNativeContentHandler(handler, for: key)
	}

	@MainActor
	private static func setRenderProcessTerminationHandler(
		_ browser: CEFBridgeBrowserRef,
		handler: ((BrowserRuntimeRenderProcessTermination) -> Void)?
	) {
		let key = browserKey(for: browser)
		bridgeMessageState.setRenderProcessTerminationHandler(handler, for: key)
	}

	@MainActor
	private static func setMainFrameNavigationHandler(
		_ browser: CEFBridgeBrowserRef,
		handler: ((BrowserRuntimeMainFrameNavigationEvent) -> Void)?
	) {
		let key = browserKey(for: browser)
		bridgeMessageState.setMainFrameNavigationHandler(handler, for: key)
	}

	@MainActor
	private static func setOpenURLInTabHandler(
		_ browser: CEFBridgeBrowserRef,
		handler: ((BrowserRuntimeOpenURLInTabEvent) -> Void)?
	) {
		let key = browserKey(for: browser)
		bridgeMessageState.setOpenURLInTabHandler(handler, for: key)
	}

	@MainActor
	private static func setCameraRoutingEventHandler(
		_ browser: CEFBridgeBrowserRef,
		handler: ((BrowserCameraRoutingEvent) -> Void)?
	) {
		let key = browserKey(for: browser)
		bridgeMessageState.setCameraRoutingEventHandler(handler, for: key)
	}

	@MainActor
	private static func clearBridgeMessageState(for browserKey: BrowserKey) {
		bridgeMessageState.clear(for: browserKey)
	}

	private nonisolated static func browserKey(for browser: CEFBridgeBrowserRef) -> BrowserKey {
		UInt64(UInt(bitPattern: browser))
	}

	public static func maybeRunSubprocess(_ argc: Int32, _ argv: UnsafeRawPointer) -> Int32 {
		return CEFBridge_MaybeRunSubprocess(argc, argv)
	}

	@MainActor
	public func start() {
		if isInitialized { return }

		guard let runtimePaths = resolvedRuntimePaths() else {
			Self.debugLog("[Navigator] BrowserRuntime.start missing valid CEF runtime metadata")
			return
		}

		let metadataPath = runtimePaths.metadataPath
		let localesPath = runtimePaths.localesPath
		let cachePath = preparedCachePath()
		let helperPath = validatedExecutablePath(subprocessPath())

		var ok = false
		metadataPath.withCString { metadataPtr in
			withOptionalCString(localesPath) { localesPtr in
				cachePath.withCString { cachePtr in
					withOptionalCString(helperPath) { helperPtr in
						ok = CEFBridge_Initialize(metadataPtr, localesPtr, cachePtr, helperPtr) == 1
					}
				}
			}
		}

		guard ok else {
			Self.debugLog("[Navigator] BrowserRuntime.start failed to initialize CEF")
			return
		}

		if ExternalMessagePumpFeatureFlag.isEnabled(environment: ProcessInfo.processInfo.environment) {
			Self.debugLog("[Navigator] BrowserRuntime.start using CEF external message pump")
		}

		let uptime = ProcessInfo.processInfo.systemUptime
		isInitialized = true
		lastUserActivityUptime = uptime
		lastActivitySignalUptime = uptime
	}

	@MainActor
	public func shutdown() {
		guard isInitialized else { return }

		let browsers = Array(trackedBrowsers.values)
		for browser in browsers {
			Self.setAddressChangeHandler(browser, handler: nil)
			Self.setTitleChangeHandler(browser, handler: nil)
			Self.setFaviconURLChangeHandler(browser, handler: nil)
			Self.setPictureInPictureStateChangeHandler(browser, handler: nil)
			Self.setTopLevelNativeContentHandler(browser, handler: nil)
			Self.setRenderProcessTerminationHandler(browser, handler: nil)
			Self.setMainFrameNavigationHandler(browser, handler: nil)
			Self.setOpenURLInTabHandler(browser, handler: nil)
			Self.setCameraRoutingEventHandler(browser, handler: nil)
			CEFBridge_SetMessageHandler(browser, nil, nil)
			CEFBridge_SetTitleChangeHandler(browser, nil, nil)
			CEFBridge_SetFaviconURLChangeHandler(browser, nil, nil)
			CEFBridge_SetPictureInPictureStateChangeHandler(browser, nil, nil)
			browserRuntimeCEFBridgeSetTopLevelNativeContentHandler(browser, nil, nil)
			CEFBridge_SetRenderProcessTerminationHandler(browser, nil, nil)
			browserRuntimeCEFBridgeSetMainFrameNavigationHandler(browser, nil, nil)
			browserRuntimeCEFBridgeSetOpenURLInTabHandler(browser, nil, nil)
			browserRuntimeCEFBridgeSetCameraRoutingEventHandler(browser, nil, nil)
		}

		trackedBrowsers.removeAll()
		browserSelectionOrder.removeAll()
		stopMessageLoop()
		CEFBridge_Shutdown()
		isInitialized = false
	}

	@MainActor
	public func createBrowser(in parentView: NSView, initialURL: String) -> CEFBridgeBrowserRef? {
		start()
		guard isInitialized else { return nil }
		guard !hasPendingNativeBrowserClose() else {
			Self.debugLog("[Navigator] BrowserRuntime.createBrowser deferred: native close still pending")
			return nil
		}

		let backingScale = parentView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
		let pixelBounds = parentView.convertToBacking(parentView.bounds)
		let width = max(1, Int(pixelBounds.width))
		let height = max(1, Int(pixelBounds.height))
		Self
			.debugLog("[Navigator] BrowserRuntime.createBrowser parent=\(parentView) size=\(width)x\(height) url=\(initialURL)")

		let parentViewPointer = Unmanaged.passUnretained(parentView).toOpaque()
		var created: CEFBridgeBrowserRef?

		initialURL.withCString { cstr in
			created = CEFBridge_CreateBrowser(parentViewPointer, cstr, Int32(width), Int32(height), Double(backingScale))
		}

		guard let created else { return nil }
		track(browser: created)
		let browserKey = Self.browserKey(for: created)
		Task { @MainActor [weak self, browser = created, browserKey, initialURL] in
			guard let self, self.trackedBrowsers[browserKey] != nil else { return }
			self.load(browser, url: initialURL)
		}
		recordBrowserActivity(for: created, shouldThrottle: false)
		return created
	}

	@MainActor
	public func resizeBrowser(_ browser: CEFBridgeBrowserRef?, in view: NSView) {
		guard let browser else { return }
		let pixelBounds = view.convertToBacking(view.bounds)
		let width = max(1, Int(pixelBounds.width))
		let height = max(1, Int(pixelBounds.height))
		CEFBridge_ResizeBrowser(browser, Int32(width), Int32(height), Double(view.window?.backingScaleFactor ?? 1))
	}

	@MainActor
	public func load(_ browser: CEFBridgeBrowserRef?, url: String) {
		guard let browser else { return }
		setActiveBrowser(browser)
		url.withCString { cstr in
			CEFBridge_LoadUrl(browser, cstr)
		}
	}

	@MainActor
	public func stopLoad(_ browser: CEFBridgeBrowserRef?) {
		guard let browser else { return }
		setActiveBrowser(browser)
		CEFBridge_StopLoad(browser)
	}

	@MainActor
	public func goBack(_ browser: CEFBridgeBrowserRef?) {
		guard let browser else { return }
		setActiveBrowser(browser)
		CEFBridge_GoBack(browser)
	}

	@MainActor
	public func goForward(_ browser: CEFBridgeBrowserRef?) {
		guard let browser else { return }
		setActiveBrowser(browser)
		CEFBridge_GoForward(browser)
	}

	@MainActor
	public func reload(_ browser: CEFBridgeBrowserRef?) {
		guard let browser else { return }
		setActiveBrowser(browser)
		CEFBridge_Reload(browser)
	}

	@MainActor
	public func close(_ browser: CEFBridgeBrowserRef?) {
		guard let browser else { return }
		untrack(browser: browser)
		Self.setAddressChangeHandler(browser, handler: nil)
		Self.setTitleChangeHandler(browser, handler: nil)
		Self.setFaviconURLChangeHandler(browser, handler: nil)
		Self.setPictureInPictureStateChangeHandler(browser, handler: nil)
		Self.setTopLevelNativeContentHandler(browser, handler: nil)
		Self.setRenderProcessTerminationHandler(browser, handler: nil)
		Self.setMainFrameNavigationHandler(browser, handler: nil)
		Self.setOpenURLInTabHandler(browser, handler: nil)
		Self.setCameraRoutingEventHandler(browser, handler: nil)
		permissionBridge.setPromptHandler(for: browser, handler: nil)
		CEFBridge_SetMessageHandler(browser, nil, nil)
		CEFBridge_SetTitleChangeHandler(browser, nil, nil)
		CEFBridge_SetFaviconURLChangeHandler(browser, nil, nil)
		CEFBridge_SetPictureInPictureStateChangeHandler(browser, nil, nil)
		browserRuntimeCEFBridgeSetTopLevelNativeContentHandler(browser, nil, nil)
		CEFBridge_SetRenderProcessTerminationHandler(browser, nil, nil)
		browserRuntimeCEFBridgeSetMainFrameNavigationHandler(browser, nil, nil)
		browserRuntimeCEFBridgeSetOpenURLInTabHandler(browser, nil, nil)
		browserRuntimeCEFBridgeSetCameraRoutingEventHandler(browser, nil, nil)
		permissionBridge.clearNativeHandlers(for: browser)
		CEFBridge_CloseBrowser(browser)
		ensureMessageLoop()
	}

	@MainActor
	public func setAddressChangeHandler(
		for browser: CEFBridgeBrowserRef?,
		handler: ((String) -> Void)?
	) {
		guard let browser else { return }
		setActiveBrowser(browser)
		Self.debugLog("[Navigator] setAddressChangeHandler for browser=\(browser) enabled=\(handler != nil)")
		if let handler {
			Self.setAddressChangeHandler(browser, handler: handler)
			CEFBridge_SetMessageHandler(browser, Self.addressChangeMessageCallback, browser)
			return
		}

		Self.setAddressChangeHandler(browser, handler: nil)
		CEFBridge_SetMessageHandler(browser, nil, nil)
	}

	@MainActor
	public func setTitleChangeHandler(
		for browser: CEFBridgeBrowserRef?,
		handler: ((String) -> Void)?
	) {
		guard let browser else { return }
		setActiveBrowser(browser)
		Self.debugLog("[Navigator] setTitleChangeHandler for browser=\(browser) enabled=\(handler != nil)")
		if let handler {
			Self.setTitleChangeHandler(browser, handler: handler)
			CEFBridge_SetTitleChangeHandler(browser, Self.titleChangeMessageCallback, browser)
			return
		}

		Self.setTitleChangeHandler(browser, handler: nil)
		CEFBridge_SetTitleChangeHandler(browser, nil, nil)
	}

	@MainActor
	public func setFaviconURLChangeHandler(
		for browser: CEFBridgeBrowserRef?,
		handler: ((String) -> Void)?
	) {
		guard let browser else { return }
		setActiveBrowser(browser)
		Self.debugLog("[Navigator] setFaviconURLChangeHandler for browser=\(browser) enabled=\(handler != nil)")
		if let handler {
			Self.setFaviconURLChangeHandler(browser, handler: handler)
			CEFBridge_SetFaviconURLChangeHandler(browser, Self.faviconURLChangeMessageCallback, browser)
			return
		}

		Self.setFaviconURLChangeHandler(browser, handler: nil)
		CEFBridge_SetFaviconURLChangeHandler(browser, nil, nil)
	}

	@MainActor
	public func setPictureInPictureStateChangeHandler(
		for browser: CEFBridgeBrowserRef?,
		handler: ((BrowserRuntimePictureInPictureState) -> Void)?
	) {
		guard let browser else { return }
		setActiveBrowser(browser)
		Self.debugLog("[Navigator] setPictureInPictureStateChangeHandler for browser=\(browser) enabled=\(handler != nil)")
		if let handler {
			Self.setPictureInPictureStateChangeHandler(browser, handler: handler)
			CEFBridge_SetPictureInPictureStateChangeHandler(browser, Self.pictureInPictureStateChangeMessageCallback, browser)
			return
		}

		Self.setPictureInPictureStateChangeHandler(browser, handler: nil)
		CEFBridge_SetPictureInPictureStateChangeHandler(browser, nil, nil)
	}

	@MainActor
	public func setTopLevelNativeContentHandler(
		for browser: CEFBridgeBrowserRef?,
		supportedKinds: Set<BrowserRuntimeTopLevelNativeContentKind>,
		handler: ((BrowserRuntimeTopLevelNativeContent) -> Void)?
	) {
		guard let browser else { return }
		setActiveBrowser(browser)
		Self.debugLog(
			"[Navigator] setTopLevelNativeContentHandler for browser=\(browser) enabled=\(handler != nil)"
		)
		if let handler {
			let filteredHandler: (BrowserRuntimeTopLevelNativeContent) -> Void = { content in
				guard supportedKinds.contains(content.kind) else { return }
				handler(content)
			}
			Self.setTopLevelNativeContentHandler(browser, handler: filteredHandler)
			browserRuntimeCEFBridgeSetTopLevelNativeContentHandler(
				browser,
				Self.topLevelNativeContentMessageCallback,
				browser
			)
			return
		}

		Self.setTopLevelNativeContentHandler(browser, handler: nil)
		browserRuntimeCEFBridgeSetTopLevelNativeContentHandler(browser, nil, nil)
	}

	@MainActor
	public func setRenderProcessTerminationHandler(
		for browser: CEFBridgeBrowserRef?,
		handler: ((BrowserRuntimeRenderProcessTermination) -> Void)?
	) {
		guard let browser else { return }
		setActiveBrowser(browser)
		Self.debugLog("[Navigator] setRenderProcessTerminationHandler for browser=\(browser) enabled=\(handler != nil)")
		if let handler {
			Self.setRenderProcessTerminationHandler(browser, handler: handler)
			CEFBridge_SetRenderProcessTerminationHandler(
				browser,
				Self.renderProcessTerminationMessageCallback,
				browser
			)
			return
		}

		Self.setRenderProcessTerminationHandler(browser, handler: nil)
		CEFBridge_SetRenderProcessTerminationHandler(browser, nil, nil)
	}

	@MainActor
	public func setMainFrameNavigationHandler(
		for browser: CEFBridgeBrowserRef?,
		handler: ((BrowserRuntimeMainFrameNavigationEvent) -> Void)?
	) {
		guard let browser else { return }
		setActiveBrowser(browser)
		Self.debugLog("[Navigator] setMainFrameNavigationHandler for browser=\(browser) enabled=\(handler != nil)")
		if let handler {
			Self.setMainFrameNavigationHandler(browser, handler: handler)
			browserRuntimeCEFBridgeSetMainFrameNavigationHandler(
				browser,
				Self.mainFrameNavigationMessageCallback,
				browser
			)
			return
		}

		Self.setMainFrameNavigationHandler(browser, handler: nil)
		browserRuntimeCEFBridgeSetMainFrameNavigationHandler(browser, nil, nil)
	}

	@MainActor
	public func setOpenURLInTabHandler(
		for browser: CEFBridgeBrowserRef?,
		handler: ((BrowserRuntimeOpenURLInTabEvent) -> Void)?
	) {
		guard let browser else { return }
		setActiveBrowser(browser)
		Self.debugLog("[Navigator] setOpenURLInTabHandler for browser=\(browser) enabled=\(handler != nil)")
		if let handler {
			Self.setOpenURLInTabHandler(browser, handler: handler)
			browserRuntimeCEFBridgeSetOpenURLInTabHandler(
				browser,
				Self.openURLInTabMessageCallback,
				browser
			)
			return
		}

		Self.setOpenURLInTabHandler(browser, handler: nil)
		browserRuntimeCEFBridgeSetOpenURLInTabHandler(browser, nil, nil)
	}

	@MainActor
	public func setCameraRoutingEventHandler(
		for browser: CEFBridgeBrowserRef?,
		handler: ((BrowserCameraRoutingEvent) -> Void)?
	) {
		guard let browser else { return }
		setActiveBrowser(browser)
		Self.debugLog("[Navigator] setCameraRoutingEventHandler for browser=\(browser) enabled=\(handler != nil)")
		if let handler {
			Self.setCameraRoutingEventHandler(browser, handler: handler)
			browserRuntimeCEFBridgeSetCameraRoutingEventHandler(
				browser,
				Self.cameraRoutingEventMessageCallback,
				browser
			)
			return
		}

		Self.setCameraRoutingEventHandler(browser, handler: nil)
		browserRuntimeCEFBridgeSetCameraRoutingEventHandler(browser, nil, nil)
	}

	@MainActor
	public func setPermissionPromptHandler(
		for browser: CEFBridgeBrowserRef?,
		handler: ((BrowserPermissionSession?) -> Void)?
	) {
		guard let browser else { return }
		setActiveBrowser(browser)
		permissionBridge.setPromptHandler(for: browser, handler: handler)
	}

	@MainActor
	public func resolvePermissionPrompt(
		sessionID: BrowserPermissionSessionID,
		decision: BrowserPermissionPromptDecision,
		persistence: BrowserPermissionPersistence
	) {
		permissionBridge.resolvePrompt(
			sessionID: sessionID,
			decision: decision,
			persistence: persistence,
			now: now
		)
	}

	@MainActor
	public func cancelPermissionPrompt(sessionID: BrowserPermissionSessionID) {
		permissionBridge.cancelPrompt(sessionID: sessionID, now: now)
	}

	@MainActor
	public func dumpPermissionState() -> String {
		permissionBridge.dumpState()
	}

	#if DEBUG
		@MainActor
		func handlePermissionRequestForTesting(
			_ request: BrowserPermissionNativeRequest,
			now: Date
		) {
			permissionBridge.handleRequest(request, now: now)
		}

		@MainActor
		func resolvePermissionPromptForTesting(
			sessionID: BrowserPermissionSessionID,
			decision: BrowserPermissionPromptDecision,
			persistence: BrowserPermissionPersistence,
			now: Date
		) {
			permissionBridge.resolvePrompt(
				sessionID: sessionID,
				decision: decision,
				persistence: persistence,
				now: now
			)
		}

		@MainActor
		func cancelPermissionPromptForTesting(
			sessionID: BrowserPermissionSessionID,
			now: Date
		) {
			permissionBridge.cancelPrompt(sessionID: sessionID, now: now)
		}

		@MainActor
		func handlePermissionDismissedForTesting(
			sessionID: BrowserPermissionSessionID,
			reason: BrowserPermissionSessionDismissReason,
			now: Date
		) {
			permissionBridge.dismissSession(
				sessionID: sessionID,
				reason: reason,
				now: now
			)
		}

		@MainActor
		func expireTimedOutPermissionPromptsForTesting(now: Date) {
			permissionBridge.expireTimedOutSessions(now: now)
		}
	#endif

	@MainActor
	public func evaluateJavaScriptWithResult(
		_ browser: CEFBridgeBrowserRef?,
		script: String,
		completion: @escaping @MainActor (String?, String?) -> Void
	) {
		guard let browser else {
			completion(nil, "Missing browser")
			return
		}
		setActiveBrowser(browser)
		let callbackBox = BrowserRuntimeJavaScriptResultBox(completion: completion)
		let retained = Unmanaged.passRetained(callbackBox)
		script.withCString { cString in
			CEFBridge_ExecuteJavaScriptWithResult(
				browser,
				cString,
				browserRuntimeJavaScriptResultCallback,
				retained.toOpaque()
			)
		}
	}

	@MainActor
	public func canGoBack(_ browser: CEFBridgeBrowserRef?) -> Bool {
		guard let browser else { return false }
		setActiveBrowser(browser)
		return CEFBridge_CanGoBack(browser) == 1
	}

	@MainActor
	public func canGoForward(_ browser: CEFBridgeBrowserRef?) -> Bool {
		guard let browser else { return false }
		setActiveBrowser(browser)
		return CEFBridge_CanGoForward(browser) == 1
	}

	@MainActor
	public func isLoading(_ browser: CEFBridgeBrowserRef?) -> Bool {
		guard let browser else { return false }
		setActiveBrowser(browser)
		return CEFBridge_IsLoading(browser) == 1
	}

	@MainActor
	public func diagnosticsSnapshot() -> BrowserRuntimeDiagnostics {
		let selectedBrowser = resolveSelectedTrackedBrowser()
		let browserKey = selectedBrowser?.key
		let trackedBrowser = selectedBrowser?.browser
		let runtimePaths = resolvedRuntimePaths()
		let resolvedResourcesPath = runtimePaths?.resourcesPath
		let resolvedLocalesPath = runtimePaths?.localesPath
		let resolvedCachePath = resolvedCachePath()
		let resolvedSubprocessPath = subprocessPath()
		let fileManager = FileManager.default
		let uptime = ProcessInfo.processInfo.systemUptime

		return BrowserRuntimeDiagnostics(
			isInitialized: isInitialized,
			hasTrackedBrowser: !trackedBrowsers.isEmpty,
			trackedBrowserCount: trackedBrowsers.count,
			trackedBrowserIdentifier: browserKey.map { String(format: "0x%llx", $0) },
			currentURL: browserKey.flatMap { Self.bridgeMessageState.lastMessage(for: $0, kind: .address) },
			canGoBack: trackedBrowser.map { self.canGoBack($0) },
			canGoForward: trackedBrowser.map { self.canGoForward($0) },
			isLoading: trackedBrowser.map { self.isLoading($0) },
			resourcesPath: resolvedResourcesPath ?? "",
			localesPath: resolvedLocalesPath ?? "",
			cachePath: resolvedCachePath,
			subprocessPath: resolvedSubprocessPath ?? "",
			resourcesPathExists: resolvedResourcesPath.map { fileManager.fileExists(atPath: $0) } ?? false,
			localesPathExists: resolvedLocalesPath.map { fileManager.fileExists(atPath: $0) } ?? false,
			cachePathExists: fileManager.fileExists(atPath: resolvedCachePath),
			subprocessPathExists: resolvedSubprocessPath.map { fileManager.fileExists(atPath: $0) } ?? false,
			lastUserActivityAgeSeconds: max(0, uptime - lastUserActivityUptime),
			lastActivitySignalAgeSeconds: max(0, uptime - lastActivitySignalUptime)
		)
	}

	@MainActor
	public func reloadTrackedBrowser() -> Bool {
		guard let trackedBrowser = resolveSelectedTrackedBrowser()?.browser else { return false }
		reload(trackedBrowser)
		recordBrowserActivity(for: trackedBrowser, shouldThrottle: false)
		return true
	}

	@MainActor
	public func hasPendingNativeBrowserClose() -> Bool {
		CEFBridge_HasPendingBrowserClose() == 1
	}

	@MainActor
	private func track(browser: CEFBridgeBrowserRef) {
		let browserKey = Self.browserKey(for: browser)
		trackedBrowsers[browserKey] = browser
		Self.clearBridgeMessageState(for: browserKey)
		markBrowserActive(browserKey)
		CEFBridge_SetPictureInPictureStateChangeHandler(browser, Self.pictureInPictureStateChangeMessageCallback, browser)
		permissionBridge.register(browser: browser)
		browserRuntimeCEFBridgeSetTopLevelNativeContentHandler(browser, nil, nil)
	}

	@MainActor
	private func untrack(browser: CEFBridgeBrowserRef) {
		let browserKey = Self.browserKey(for: browser)
		trackedBrowsers.removeValue(forKey: browserKey)
		browserSelectionOrder.removeAll { $0 == browserKey }
		Self.clearBridgeMessageState(for: browserKey)
		permissionBridge.unregister(browser: browser)
	}

	@MainActor
	func setActiveBrowser(_ browser: CEFBridgeBrowserRef) {
		let browserKey = Self.browserKey(for: browser)
		guard trackedBrowsers[browserKey] != nil else { return }
		markBrowserActive(browserKey)
	}

	@MainActor
	private func markBrowserActive(_ browserKey: BrowserKey) {
		browserSelectionOrder.removeAll { $0 == browserKey }
		browserSelectionOrder.append(browserKey)
	}

	@MainActor
	private func resolveSelectedTrackedBrowser() -> (key: BrowserKey, browser: CEFBridgeBrowserRef)? {
		for browserKey in browserSelectionOrder.reversed() {
			if let browser = trackedBrowsers[browserKey] {
				return (browserKey, browser)
			}
		}
		return trackedBrowsers.first.map { ($0.key, $0.value) }
	}

	@MainActor
	private func recordBrowserActivity(for browser: CEFBridgeBrowserRef?, shouldThrottle: Bool) {
		if let browser {
			setActiveBrowser(browser)
		}
		guard isInitialized, !trackedBrowsers.isEmpty else { return }

		let uptime = ProcessInfo.processInfo.systemUptime
		if shouldThrottle, uptime - lastActivitySignalUptime < MessageLoop.activitySignalInterval {
			return
		}

		lastActivitySignalUptime = uptime
		lastUserActivityUptime = uptime
		ensureMessageLoop()
	}

	@MainActor
	private func ensureMessageLoop() {
		guard shouldRunMessageLoop() else {
			stopMessageLoop()
			return
		}
		if let existingTimer = messageLoopTimer {
			scheduleMessageLoop(for: existingTimer)
			return
		}

		let timer = DispatchSource.makeTimerSource(queue: .main)
		timer.setEventHandler { [weak self] in
			Task { @MainActor [weak self] in
				self?.handleMessageLoopTick()
			}
		}
		timer.resume()
		messageLoopTimer = timer
		scheduleMessageLoop(for: timer)
	}

	@MainActor
	private func handleMessageLoopTick() {
		guard shouldRunMessageLoop() else {
			stopMessageLoop()
			return
		}
		permissionBridge.expireTimedOutSessions(now: now)
		CEFBridge_DoMessageLoopWork()
		scheduleMessageLoop()
	}

	@MainActor
	private func scheduleMessageLoop() {
		guard let timer = messageLoopTimer else { return }
		scheduleMessageLoop(for: timer)
	}

	@MainActor
	private func scheduleMessageLoop(for timer: DispatchSourceTimer) {
		guard shouldRunMessageLoop() else {
			stopMessageLoop()
			return
		}
		timer.schedule(
			deadline: .now() + interval(),
			repeating: .never,
			leeway: MessageLoop.leeway
		)
	}

	@MainActor
	private func interval() -> DispatchTimeInterval {
		if ExternalMessagePumpFeatureFlag.isEnabled(environment: ProcessInfo.processInfo.environment) {
			let nanos = Int(MessageLoop.activeInterval * 1_000_000_000)
			return .nanoseconds(max(1_000_000, nanos))
		}

		let uptime = ProcessInfo.processInfo.systemUptime
		let isActive = (uptime - lastUserActivityUptime) <= MessageLoop.activityWindow
		let value = isActive ? MessageLoop.activeInterval : MessageLoop.idleInterval
		let nanos = Int(value * 1_000_000_000)
		return .nanoseconds(max(1_000_000, nanos))
	}

	@MainActor
	private func shouldRunMessageLoop() -> Bool {
		guard isInitialized else { return false }
		if hasPendingNativeBrowserClose() { return true }
		guard !trackedBrowsers.isEmpty else { return false }
		if ExternalMessagePumpFeatureFlag.isEnabled(environment: ProcessInfo.processInfo.environment) == false {
			return true
		}

		let uptime = ProcessInfo.processInfo.systemUptime
		return (uptime - lastUserActivityUptime) <= MessageLoop.externalPumpFallbackWindow
	}

	@MainActor
	private func stopMessageLoop() {
		messageLoopTimer?.cancel()
		messageLoopTimer = nil
	}

	@MainActor
	private func resolvedRuntimePaths() -> RuntimePaths? {
		guard let metadataPath = runtimeMetadataPath() else { return nil }
		let runtimeRootPath = runtimeRootPath(forMetadataPath: metadataPath)
		let layout = runtimeLayoutConfiguration(metadataPath: metadataPath)
		let resourcesPath = standardizedAbsolutePath(
			fromRelative: layout?.resourcesRelativePath,
			runtimeRootPath: runtimeRootPath
		) ?? metadataPath
		let localesPath = standardizedAbsolutePath(
			fromRelative: layout?.localesRelativePath,
			runtimeRootPath: runtimeRootPath
		) ?? defaultLocalesPath(runtimeRootPath: runtimeRootPath, resourcesPath: resourcesPath)
		let helpersDirectoryPath = standardizedAbsolutePath(
			fromRelative: layout?.helpersDirectoryRelativePath,
			runtimeRootPath: runtimeRootPath
		) ?? defaultHelpersDirectoryPath(runtimeRootPath: runtimeRootPath)

		return RuntimePaths(
			metadataPath: metadataPath,
			runtimeRootPath: runtimeRootPath,
			resourcesPath: resourcesPath,
			localesPath: localesPath,
			helpersDirectoryPath: helpersDirectoryPath
		)
	}

	@MainActor
	private func runtimeMetadataPath() -> String? {
		let bundleFallback = (Bundle.main.bundlePath as NSString).appendingPathComponent("Contents/Resources")
		let repoVendorRuntimeResources = (FileManager.default.currentDirectoryPath as NSString)
			.appendingPathComponent("Vendor/CEF/Release/ChromiumEmbeddedRuntime.framework/Contents/Resources")
		let toolsVendorRuntimeResources = (FileManager.default.currentDirectoryPath as NSString)
			.appendingPathComponent("Tools/Vendor/CEF/Release/ChromiumEmbeddedRuntime.framework/Contents/Resources")

		let candidates = [
			Bundle.main.resourcePath,
			bundleFallback,
			repoVendorRuntimeResources,
			toolsVendorRuntimeResources,
		]
		.compactMap { $0 }
		.map { ($0 as NSString).standardizingPath }

		return firstExistingDirectoryPath(
			in: candidates,
			where: { self.isValidRuntimeMetadataDirectory(at: $0) }
		)
	}

	@MainActor
	private func runtimeRootPath(forMetadataPath metadataPath: String) -> String {
		let standardizedMetadataPath = (metadataPath as NSString).standardizingPath
		let contentsResourcesSuffix = "/Contents/Resources"
		if standardizedMetadataPath.hasSuffix(contentsResourcesSuffix) {
			let contentsPath = (standardizedMetadataPath as NSString).deletingLastPathComponent
			return ((contentsPath as NSString).deletingLastPathComponent as NSString).standardizingPath
		}
		return standardizedMetadataPath
	}

	@MainActor
	private func runtimeLayoutConfiguration(metadataPath: String) -> RuntimeLayoutConfiguration? {
		let runtimeLayoutPath = (metadataPath as NSString).appendingPathComponent("runtime_layout.json")
		guard let layoutData = try? Data(contentsOf: URL(fileURLWithPath: runtimeLayoutPath)) else { return nil }
		guard let rawObject = try? JSONSerialization.jsonObject(with: layoutData) as? [String: Any] else { return nil }
		guard let expectedPaths = rawObject["expectedPaths"] as? [String: Any] else { return nil }

		return RuntimeLayoutConfiguration(
			resourcesRelativePath: sanitizedRelativePath(expectedPaths["resourcesRelativePath"] as? String),
			localesRelativePath: sanitizedRelativePath(expectedPaths["localesRelativePath"] as? String),
			helpersDirectoryRelativePath: sanitizedRelativePath(expectedPaths["helpersDirRelativePath"] as? String)
		)
	}

	@MainActor
	private func sanitizedRelativePath(_ value: String?) -> String? {
		guard let value else { return nil }
		let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmed.isEmpty ? nil : trimmed
	}

	@MainActor
	private func standardizedAbsolutePath(
		fromRelative relativePath: String?,
		runtimeRootPath: String
	) -> String? {
		guard let relativePath else { return nil }
		let nsRelativePath = relativePath as NSString
		if nsRelativePath.isAbsolutePath {
			return nsRelativePath.standardizingPath
		}
		return (runtimeRootPath as NSString).appendingPathComponent(relativePath)
	}

	@MainActor
	private func defaultLocalesPath(runtimeRootPath: String, resourcesPath: String) -> String? {
		let resourcesLocalesPath = (resourcesPath as NSString).appendingPathComponent("locales")
		if FileManager.default.fileExists(atPath: resourcesLocalesPath) {
			return (resourcesLocalesPath as NSString).standardizingPath
		}

		let candidates = [
			(runtimeRootPath as NSString).appendingPathComponent(
				"Contents/Frameworks/Chromium Embedded Framework.framework/Versions/A/Resources/locales"
			),
			(runtimeRootPath as NSString).appendingPathComponent(
				"Contents/Frameworks/Chromium Embedded Framework.framework/Resources/locales"
			),
			(runtimeRootPath as NSString).appendingPathComponent(
				"Contents/Frameworks/MiumRuntime/Chromium Embedded Framework.framework/Versions/A/Resources/locales"
			),
			(runtimeRootPath as NSString).appendingPathComponent(
				"Contents/Frameworks/MiumRuntime/Chromium Embedded Framework.framework/Resources/locales"
			),
		]
		.map { ($0 as NSString).standardizingPath }

		return firstExistingDirectoryPath(in: candidates)
	}

	@MainActor
	private func defaultHelpersDirectoryPath(runtimeRootPath: String) -> String {
		((runtimeRootPath as NSString).appendingPathComponent("Contents/Frameworks") as NSString).standardizingPath
	}

	@MainActor
	private func resolvedCachePath() -> String {
		cacheDirectoryBaseURL().path
	}

	@MainActor
	private func preparedCachePath() -> String {
		let baseURL = cacheDirectoryBaseURL()
		let manager = FileManager.default
		do {
			try manager.createDirectory(at: baseURL, withIntermediateDirectories: true)
		}
		catch {
			let fallback = FileManager.default.homeDirectoryForCurrentUser
				.appendingPathComponent("Library/Caches/Navigator", isDirectory: true)
			try? manager.createDirectory(at: fallback, withIntermediateDirectories: true)
			return preparedCacheDirectory(at: fallback).path
		}
		return preparedCacheDirectory(at: baseURL).path
	}

	@MainActor
	private func cacheDirectoryBaseURL() -> URL {
		let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
		let appSupport = supportDir?.appendingPathComponent("Navigator", isDirectory: true).appendingPathComponent(
			cacheDirectoryName,
			isDirectory: true
		)
		let fallback = FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent("Library/Caches/Navigator", isDirectory: true)
		return appSupport ?? fallback
	}

	@MainActor
	private func preparedCacheDirectory(at baseURL: URL) -> URL {
		let fileManager = FileManager.default
		let compatibilityMarkerURL = baseURL.appendingPathComponent(cacheCompatibilityMarkerFileName, isDirectory: false)
		let currentMarker = cacheCompatibilityMarker()
		let existingMarker = try? String(contentsOf: compatibilityMarkerURL, encoding: .utf8)
		let directoryContents = (try? fileManager.contentsOfDirectory(atPath: baseURL.path)) ?? []
		let shouldRotateCache = !directoryContents.isEmpty
			&& existingMarker?.trimmingCharacters(in: .whitespacesAndNewlines) != currentMarker

		if shouldRotateCache, fileManager.fileExists(atPath: baseURL.path) {
			rotateCacheDirectory(at: baseURL)
			try? fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
		}

		removeStaleSingletonArtifacts(at: baseURL)
		seedChromiumProfilePreferences(at: baseURL)
		try? currentMarker.write(to: compatibilityMarkerURL, atomically: true, encoding: .utf8)
		return baseURL
	}

	@MainActor
	private func seedChromiumProfilePreferences(at cacheDirectoryURL: URL) {
		let fileManager = FileManager.default
		let profileURL = cacheDirectoryURL.appendingPathComponent("Default", isDirectory: true)
		try? fileManager.createDirectory(at: profileURL, withIntermediateDirectories: true)

		let preferencesURL = profileURL.appendingPathComponent("Preferences", isDirectory: false)
		guard let preferences = chromiumPreferences(at: preferencesURL) else { return }
		let sanitizedPreferences = Self.sanitizedChromiumPreferences(preferences)
		guard JSONSerialization.isValidJSONObject(sanitizedPreferences),
		      let data = try? JSONSerialization.data(withJSONObject: sanitizedPreferences)
		else {
			return
		}

		try? data.write(to: preferencesURL, options: .atomic)
	}

	@MainActor
	private func chromiumPreferences(at preferencesURL: URL) -> [String: Any]? {
		guard let data = try? Data(contentsOf: preferencesURL) else { return nil }
		guard let rawObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
		return rawObject
	}

	static func sanitizedChromiumPreferences(_ preferences: [String: Any]) -> [String: Any] {
		var sanitizedPreferences = preferences
		for path in seededDisabledChromiumPreferencePaths {
			sanitizedPreferences = removingPreferenceValue(at: path, from: sanitizedPreferences).object
		}
		return sanitizedPreferences
	}

	private static let seededDisabledChromiumPreferencePaths = [
		["credentials_enable_service"],
		["credentials_enable_autosignin"],
		["profile", "password_manager_enabled"],
		["autofill", "profile_enabled"],
		["autofill", "credit_card_enabled"],
	]

	private static func removingPreferenceValue(
		at path: [String],
		from object: [String: Any]
	) -> (object: [String: Any], removed: Bool) {
		guard let key = path.first else { return (object, false) }
		guard path.count > 1 else {
			var updatedObject = object
			let removed = updatedObject.removeValue(forKey: key) != nil
			return (updatedObject, removed)
		}

		var updatedObject = object
		guard let nestedObject = updatedObject[key] as? [String: Any] else {
			return (updatedObject, false)
		}
		let result = removingPreferenceValue(at: Array(path.dropFirst()), from: nestedObject)
		if result.removed == false {
			return (updatedObject, false)
		}
		if result.object.isEmpty {
			updatedObject.removeValue(forKey: key)
		}
		else {
			updatedObject[key] = result.object
		}
		return (updatedObject, true)
	}

	@MainActor
	private func rotateCacheDirectory(at baseURL: URL) {
		let fileManager = FileManager.default
		let timestamp = ISO8601DateFormatter().string(from: now)
			.replacingOccurrences(of: ":", with: "-")
		let backupURL = baseURL.deletingLastPathComponent().appendingPathComponent(
			"\(baseURL.lastPathComponent).backup-\(timestamp)",
			isDirectory: true
		)
		try? fileManager.removeItem(at: backupURL)
		try? fileManager.moveItem(at: baseURL, to: backupURL)
	}

	@MainActor
	private func cacheCompatibilityMarker() -> String {
		let cefVersion = cefFrameworkVersion()
		return [
			"schema=\(cacheCompatibilitySchemaVersion)",
			cefVersion,
		].joined(separator: "|")
	}

	@MainActor
	private func cefFrameworkVersion() -> String {
		let frameworkPath = (Bundle.main.bundlePath as NSString)
			.appendingPathComponent("Contents/Frameworks/Chromium Embedded Framework.framework")
		let frameworkBundle = Bundle(path: frameworkPath)
		return frameworkBundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
	}

	@MainActor
	private func removeStaleSingletonArtifacts(at cacheDirectoryURL: URL) {
		let fileManager = FileManager.default
		let singletonNames = ["SingletonCookie", "SingletonLock", "SingletonSocket"]
		let artifactURLs = singletonNames.map { cacheDirectoryURL.appendingPathComponent($0, isDirectory: false) }
		let hasSingletonArtifacts = artifactURLs.contains { fileManager.fileExists(atPath: $0.path) }
		guard hasSingletonArtifacts else { return }

		let lockURL = cacheDirectoryURL.appendingPathComponent("SingletonLock", isDirectory: false)
		let lockDestination = try? fileManager.destinationOfSymbolicLink(atPath: lockURL.path)
		let ownerPID = singletonOwnerPID(from: lockDestination)
		let shouldRemoveArtifacts = lockDestination?.isEmpty != false
			|| ownerPID.map { !isLiveNavigatorProcess(pid: $0) } ?? true
		guard shouldRemoveArtifacts else { return }

		for artifactURL in artifactURLs where fileManager.fileExists(atPath: artifactURL.path) {
			try? fileManager.removeItem(at: artifactURL)
		}
	}

	@MainActor
	private func singletonOwnerPID(from lockDestination: String?) -> Int32? {
		guard let lockDestination, !lockDestination.isEmpty else { return nil }
		guard let separatorIndex = lockDestination.lastIndex(of: "-") else { return nil }
		let pidSubstring = lockDestination[lockDestination.index(after: separatorIndex)...]
		guard !pidSubstring.isEmpty else { return nil }
		guard let pid = Int32(pidSubstring), pid > 0 else { return nil }
		return pid
	}

	@MainActor
	private func isLiveNavigatorProcess(pid: Int32) -> Bool {
		guard pid > 0 else { return false }
		errno = 0
		if kill(pid, 0) != 0, errno != EPERM {
			return false
		}

		var processPathBuffer = [CChar](repeating: 0, count: processPathBufferSize)
		let resolvedLength = proc_pidpath(pid, &processPathBuffer, UInt32(processPathBuffer.count))
		guard resolvedLength > 0 else { return false }
		let processPathBytes = processPathBuffer
			.prefix(Int(resolvedLength))
			.prefix(while: { $0 != 0 })
			.map { UInt8(bitPattern: $0) }
		let processPath = String(decoding: processPathBytes, as: UTF8.self)

		let resolvedProcessName = URL(fileURLWithPath: processPath).lastPathComponent
		let expectedProcessName = Bundle.main.executableURL?.lastPathComponent ?? "Navigator"
		return resolvedProcessName == expectedProcessName
	}

	@MainActor
	private func subprocessPath() -> String? {
		guard let runtimePaths = resolvedRuntimePaths() else { return nil }

		let executableName = Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String
		let baseHelperName = (executableName as NSString?)?.deletingPathExtension ?? "Navigator"
		let preferredHelperAppNames = [
			"\(baseHelperName) Helper.app",
			"Navigator Helper.app",
			"Chromium Helper.app",
			"Mium Helper.app",
		]

		let searchDirs = [
			runtimePaths.helpersDirectoryPath,
			(runtimePaths.runtimeRootPath as NSString).appendingPathComponent("Contents/Helpers"),
			(runtimePaths.runtimeRootPath as NSString).appendingPathComponent(
				"Contents/Frameworks/Chromium Embedded Framework.framework/Helpers"
			),
			(runtimePaths.runtimeRootPath as NSString).appendingPathComponent(
				"Contents/Frameworks/Chromium Embedded Framework.framework/Versions/A/Helpers"
			),
			(runtimePaths.runtimeRootPath as NSString).appendingPathComponent(
				"Contents/Frameworks/MiumRuntime/Chromium Embedded Framework.framework/Helpers"
			),
			(runtimePaths.runtimeRootPath as NSString).appendingPathComponent(
				"Contents/Frameworks/MiumRuntime/Chromium Embedded Framework.framework/Versions/A/Helpers"
			),
		]
		.compactMap { $0 }
		.map { ($0 as NSString).standardizingPath }

		let fileManager = FileManager.default
		for helperDir in searchDirs {
			for helperName in preferredHelperAppNames {
				let helperBundlePath = (helperDir as NSString).appendingPathComponent(helperName)
				let bundleExecutableName = (helperName as NSString).deletingPathExtension
				let helperBundle = Bundle(path: helperBundlePath)
				let helperExecutableName = helperBundle?.infoDictionary?["CFBundleExecutable"] as? String ?? bundleExecutableName
				let executablePath = (helperBundlePath as NSString)
					.appendingPathComponent("Contents/MacOS/\(helperExecutableName)")
				if fileManager.fileExists(atPath: executablePath) {
					Self.debugLog("[Navigator] using discovered subprocess path: \(executablePath)")
					return executablePath
				}
			}
		}

		Self.debugLog("[Navigator] no base Chromium helper app found; subprocess path left unset")
		return nil
	}

	@MainActor
	private func firstExistingDirectoryPath(
		in candidates: [String],
		where predicate: ((String) -> Bool)? = nil
	) -> String? {
		let fileManager = FileManager.default
		var seen = Set<String>()
		for candidate in candidates {
			let standardizedCandidate = (candidate as NSString).standardizingPath
			guard seen.insert(standardizedCandidate).inserted else { continue }

			var isDirectory: ObjCBool = false
			let exists = fileManager.fileExists(atPath: standardizedCandidate, isDirectory: &isDirectory)
			guard exists, isDirectory.boolValue else { continue }
			if let predicate, !predicate(standardizedCandidate) {
				continue
			}
			return standardizedCandidate
		}
		return nil
	}

	@MainActor
	private func isValidRuntimeMetadataDirectory(at path: String) -> Bool {
		var isDirectory: ObjCBool = false
		guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
			return false
		}
		return hasRuntimeLayout(at: path) || hasKnownCEFResources(at: path)
	}

	@MainActor
	private func hasRuntimeLayout(at metadataPath: String) -> Bool {
		let runtimeLayoutPath = (metadataPath as NSString).appendingPathComponent("runtime_layout.json")
		return FileManager.default.fileExists(atPath: runtimeLayoutPath)
	}

	@MainActor
	private func hasKnownCEFResources(at metadataPath: String) -> Bool {
		let fileManager = FileManager.default
		let icuDataPath = (metadataPath as NSString).appendingPathComponent("icudtl.dat")
		guard fileManager.fileExists(atPath: icuDataPath) else { return false }

		let directPakCandidates = [
			(metadataPath as NSString).appendingPathComponent("resources.pak"),
			(metadataPath as NSString).appendingPathComponent("chrome_100_percent.pak"),
			(metadataPath as NSString).appendingPathComponent("chrome_200_percent.pak"),
		]
		if directPakCandidates.contains(where: { fileManager.fileExists(atPath: $0) }) {
			return true
		}

		guard let enumerator = fileManager.enumerator(atPath: metadataPath) else { return false }
		for case let path as String in enumerator where path.hasSuffix(".pak") {
			return true
		}
		return false
	}

	@MainActor
	private func validatedExecutablePath(_ path: String?) -> String? {
		guard let path else { return nil }
		var isDirectory: ObjCBool = false
		let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
		guard exists, !isDirectory.boolValue else { return nil }
		return path
	}
}

private let browserRuntimeJavaScriptResultCallback: CEFBridgeJavaScriptResultCallback = { userData, result, error in
	guard let userData else { return }
	let callbackBox = Unmanaged<BrowserRuntimeJavaScriptResultBox>.fromOpaque(userData).takeRetainedValue()
	let resultString = result.map(String.init(cString:))
	let errorString = error.map(String.init(cString:))
	Task { @MainActor in
		callbackBox.completion(resultString, errorString)
	}
}

extension BrowserRuntime: DependencyKey {
	public static var liveValue: BrowserRuntime {
		BrowserRuntime()
	}

	public static var testValue: BrowserRuntime {
		BrowserRuntime()
	}

	public static var previewValue: BrowserRuntime {
		BrowserRuntime()
	}
}

public extension DependencyValues {
	var browserRuntime: BrowserRuntime {
		get { self[BrowserRuntime.self] }
		set { self[BrowserRuntime.self] = newValue }
	}
}

@_silgen_name("CEFBridge_Initialize")
private func CEFBridge_Initialize(
	_ resourcesPath: UnsafePointer<CChar>?,
	_ localesPath: UnsafePointer<CChar>?,
	_ cachePath: UnsafePointer<CChar>?,
	_ helperPath: UnsafePointer<CChar>?
) -> Int32

@_silgen_name("CEFBridge_Shutdown")
private func CEFBridge_Shutdown()

@_silgen_name("CEFBridge_DoMessageLoopWork")
private func CEFBridge_DoMessageLoopWork()

@_silgen_name("CEFBridge_HasPendingBrowserClose")
private func CEFBridge_HasPendingBrowserClose() -> Int32

@_silgen_name("CEFBridge_CreateBrowser")
private func CEFBridge_CreateBrowser(
	_ parentView: UnsafeMutableRawPointer,
	_ initialURL: UnsafePointer<CChar>?,
	_ width: Int32,
	_ height: Int32,
	_ backingScaleFactor: Double
) -> CEFBridgeBrowserRef?

@_silgen_name("CEFBridge_ResizeBrowser")
private func CEFBridge_ResizeBrowser(
	_ browserRef: CEFBridgeBrowserRef?,
	_ width: Int32,
	_ height: Int32,
	_ backingScaleFactor: Double
)

@_silgen_name("CEFBridge_LoadUrl")
private func CEFBridge_LoadUrl(_ browserRef: CEFBridgeBrowserRef?, _ initialURL: UnsafePointer<CChar>?)

@_silgen_name("CEFBridge_StopLoad")
private func CEFBridge_StopLoad(_ browserRef: CEFBridgeBrowserRef?)

@_silgen_name("CEFBridge_GoBack")
private func CEFBridge_GoBack(_ browserRef: CEFBridgeBrowserRef?)

@_silgen_name("CEFBridge_GoForward")
private func CEFBridge_GoForward(_ browserRef: CEFBridgeBrowserRef?)

@_silgen_name("CEFBridge_Reload")
private func CEFBridge_Reload(_ browserRef: CEFBridgeBrowserRef?)

@_silgen_name("CEFBridge_CloseBrowser")
private func CEFBridge_CloseBrowser(_ browserRef: CEFBridgeBrowserRef?)

@_silgen_name("CEFBridge_SetMessageHandler")
private func CEFBridge_SetMessageHandler(
	_ browserRef: CEFBridgeBrowserRef?,
	_ callback: CEFBridgeMessageCallback?,
	_ userData: UnsafeMutableRawPointer?
)

@_silgen_name("CEFBridge_SetTitleChangeHandler")
private func CEFBridge_SetTitleChangeHandler(
	_ browserRef: CEFBridgeBrowserRef?,
	_ callback: CEFBridgeMessageCallback?,
	_ userData: UnsafeMutableRawPointer?
)

@_silgen_name("CEFBridge_SetFaviconURLChangeHandler")
private func CEFBridge_SetFaviconURLChangeHandler(
	_ browserRef: CEFBridgeBrowserRef?,
	_ callback: CEFBridgeMessageCallback?,
	_ userData: UnsafeMutableRawPointer?
)

@_silgen_name("CEFBridge_SetPictureInPictureStateChangeHandler")
private func CEFBridge_SetPictureInPictureStateChangeHandler(
	_ browserRef: CEFBridgeBrowserRef?,
	_ callback: CEFBridgeMessageCallback?,
	_ userData: UnsafeMutableRawPointer?
)

@_silgen_name("CEFBridge_SetRenderProcessTerminationHandler")
private func CEFBridge_SetRenderProcessTerminationHandler(
	_ browserRef: CEFBridgeBrowserRef?,
	_ callback: CEFBridgeMessageCallback?,
	_ userData: UnsafeMutableRawPointer?
)

private typealias CEFBridgeJavaScriptResultCallback = @convention(c) (
	UnsafeMutableRawPointer?,
	UnsafePointer<CChar>?,
	UnsafePointer<CChar>?
) -> Void

@_silgen_name("CEFBridge_ExecuteJavaScriptWithResult")
private func CEFBridge_ExecuteJavaScriptWithResult(
	_ browserRef: CEFBridgeBrowserRef?,
	_ script: UnsafePointer<CChar>,
	_ callback: CEFBridgeJavaScriptResultCallback?,
	_ userData: UnsafeMutableRawPointer?
)

@_silgen_name("CEFBridge_CanGoBack")
private func CEFBridge_CanGoBack(_ browserRef: CEFBridgeBrowserRef?) -> Int32

@_silgen_name("CEFBridge_CanGoForward")
private func CEFBridge_CanGoForward(_ browserRef: CEFBridgeBrowserRef?) -> Int32

@_silgen_name("CEFBridge_IsLoading")
private func CEFBridge_IsLoading(_ browserRef: CEFBridgeBrowserRef?) -> Int32

@_silgen_name("CEFBridge_MaybeRunSubprocess")
private func CEFBridge_MaybeRunSubprocess(_ argc: Int32, _ argv: UnsafeRawPointer?) -> Int32
