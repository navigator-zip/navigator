import Foundation

public enum BrowserCameraRoutingEventKind: String, Codable, CaseIterable, Sendable {
	case trackStarted = "track-started"
	case trackStopped = "track-stopped"
	case trackEnded = "track-ended"
	case permissionProbeFailed = "permission-probe-failed"
	case explicitDeviceBypassed = "explicit-device-bypassed"
	case managedTrackDeviceSwitchRejected = "managed-track-device-switch-rejected"
}

public struct BrowserCameraRoutingEvent: Codable, Equatable, Sendable {
	public let event: BrowserCameraRoutingEventKind
	public let activeManagedTrackCount: Int
	public let managedTrackID: String?
	public let managedDeviceID: String?
	public let requestedDeviceIDs: [String]?
	public let preferredFilterPreset: BrowserCameraFilterPreset?
	public let errorDescription: String?

	public init(
		event: BrowserCameraRoutingEventKind,
		activeManagedTrackCount: Int,
		managedTrackID: String? = nil,
		managedDeviceID: String? = nil,
		requestedDeviceIDs: [String]? = nil,
		preferredFilterPreset: BrowserCameraFilterPreset? = nil,
		errorDescription: String? = nil
	) {
		self.event = event
		self.activeManagedTrackCount = activeManagedTrackCount
		self.managedTrackID = managedTrackID
		self.managedDeviceID = managedDeviceID
		self.requestedDeviceIDs = requestedDeviceIDs
		self.preferredFilterPreset = preferredFilterPreset
		self.errorDescription = errorDescription
	}
}
