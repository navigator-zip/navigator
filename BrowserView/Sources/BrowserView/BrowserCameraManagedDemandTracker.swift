import ModelKit

struct BrowserCameraManagedDemandResolution: Equatable {
	let nextActiveManagedTrackCount: Int
	let shouldRegisterConsumer: Bool
	let shouldUnregisterConsumer: Bool
}

enum BrowserCameraManagedDemandTracker {
	static func resolve(
		currentActiveManagedTrackCount: Int?,
		event: BrowserCameraRoutingEvent
	) -> BrowserCameraManagedDemandResolution {
		let previousCount = max(0, currentActiveManagedTrackCount ?? 0)
		switch event.event {
		case .permissionProbeFailed:
			return BrowserCameraManagedDemandResolution(
				nextActiveManagedTrackCount: previousCount,
				shouldRegisterConsumer: false,
				shouldUnregisterConsumer: false
			)
		case .explicitDeviceBypassed, .managedTrackDeviceSwitchRejected:
			return BrowserCameraManagedDemandResolution(
				nextActiveManagedTrackCount: previousCount,
				shouldRegisterConsumer: false,
				shouldUnregisterConsumer: false
			)
		case .trackStarted, .trackStopped, .trackEnded:
			break
		}
		let nextCount = max(0, event.activeManagedTrackCount)
		return BrowserCameraManagedDemandResolution(
			nextActiveManagedTrackCount: nextCount,
			shouldRegisterConsumer: previousCount == 0 && nextCount > 0,
			shouldUnregisterConsumer: previousCount > 0 && nextCount == 0
		)
	}
}
