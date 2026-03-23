import Foundation

public enum BrowserCameraDiagnosticEventKind: String, Codable, CaseIterable, Sendable {
	case deviceAvailabilityChanged
	case consumerRegistered
	case consumerUnregistered
	case routingChanged
	case preferredSourceChanged
	case filterPresetChanged
	case previewChanged
	case captureStartRequested
	case captureStarted
	case captureStopped
	case captureFailed
	case sourceLost
	case firstFrameProduced
	case processingDegraded
	case processingRecovered
	case publisherStatusChanged
	case managedTrackStarted
	case managedTrackStopped
	case managedTrackEnded
	case permissionProbeFailed
	case explicitDeviceBypassed
	case managedTrackDeviceSwitchRejected
	case browserProcessFallbackActivated
}

public struct BrowserCameraDiagnosticEvent: Codable, Equatable, Hashable, Sendable {
	public let kind: BrowserCameraDiagnosticEventKind
	public let detail: String?

	public init(
		kind: BrowserCameraDiagnosticEventKind,
		detail: String?
	) {
		self.kind = kind
		self.detail = detail
	}
}
