import Foundation

public enum BrowserCameraBrowserTransportMode: String, Codable, CaseIterable, Sendable {
	case unavailable
	case rendererProcessMessages
	case browserProcessJavaScriptFallback
}

public struct BrowserCameraBrowserTransportState: Codable, Equatable, Hashable, Sendable {
	public let tabID: String
	public let routingTransportMode: BrowserCameraBrowserTransportMode
	public let frameTransportMode: BrowserCameraBrowserTransportMode
	public let activeManagedTrackCount: Int

	public var isUsingBrowserProcessFallback: Bool {
		routingTransportMode == .browserProcessJavaScriptFallback
			|| frameTransportMode == .browserProcessJavaScriptFallback
	}

	public init(
		tabID: String,
		routingTransportMode: BrowserCameraBrowserTransportMode,
		frameTransportMode: BrowserCameraBrowserTransportMode,
		activeManagedTrackCount: Int
	) {
		self.tabID = tabID
		self.routingTransportMode = routingTransportMode
		self.frameTransportMode = frameTransportMode
		self.activeManagedTrackCount = max(0, activeManagedTrackCount)
	}
}
