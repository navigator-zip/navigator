import Foundation

public enum BrowserCameraManagedRoutingAvailability: String, Codable, CaseIterable, Sendable {
	case available
	case routingDisabled
	case navigatorPreferenceDisabled
	case noAvailableSource
	case directPhysicalCapture
	case sourceLost
	case degraded
	case pipelineFallback
	case publisherUnavailable
}

public struct BrowserCameraManagedRoutingSummary: Codable, Equatable, Hashable, Sendable {
	public let availability: BrowserCameraManagedRoutingAvailability
	public let genericVideoUsesManagedOutput: Bool
	public let failClosedOnManagedVideoRequest: Bool
	public let exposesManagedDeviceIdentity: Bool

	public var managedDeviceID: String? {
		exposesManagedDeviceIdentity ? BrowserCameraManagedOutputIdentity.deviceID : nil
	}

	public init(
		availability: BrowserCameraManagedRoutingAvailability,
		genericVideoUsesManagedOutput: Bool,
		failClosedOnManagedVideoRequest: Bool,
		exposesManagedDeviceIdentity: Bool
	) {
		self.availability = availability
		self.genericVideoUsesManagedOutput = genericVideoUsesManagedOutput
		self.failClosedOnManagedVideoRequest = failClosedOnManagedVideoRequest
		self.exposesManagedDeviceIdentity = exposesManagedDeviceIdentity
	}
}

public extension BrowserCameraSessionSnapshot {
	var managedRoutingSummary: BrowserCameraManagedRoutingSummary {
		BrowserCameraManagedRoutingSummaryResolver.resolve(from: self)
	}
}

private enum BrowserCameraManagedRoutingSummaryResolver {
	static func resolve(
		from snapshot: BrowserCameraSessionSnapshot
	) -> BrowserCameraManagedRoutingSummary {
		guard snapshot.routingSettings.preferNavigatorCameraWhenPossible else {
			return BrowserCameraManagedRoutingSummary(
				availability: .navigatorPreferenceDisabled,
				genericVideoUsesManagedOutput: false,
				failClosedOnManagedVideoRequest: false,
				exposesManagedDeviceIdentity: false
			)
		}

		guard hasAvailableSource(in: snapshot) else {
			return BrowserCameraManagedRoutingSummary(
				availability: .noAvailableSource,
				genericVideoUsesManagedOutput: false,
				failClosedOnManagedVideoRequest: false,
				exposesManagedDeviceIdentity: false
			)
		}

		guard snapshot.routingSettings.routingEnabled else {
			return BrowserCameraManagedRoutingSummary(
				availability: .routingDisabled,
				genericVideoUsesManagedOutput: false,
				failClosedOnManagedVideoRequest: false,
				exposesManagedDeviceIdentity: false
			)
		}

		guard snapshot.outputMode != .directPhysicalCapture else {
			return BrowserCameraManagedRoutingSummary(
				availability: .directPhysicalCapture,
				genericVideoUsesManagedOutput: false,
				failClosedOnManagedVideoRequest: false,
				exposesManagedDeviceIdentity: false
			)
		}

		switch snapshot.healthState {
		case .healthy:
			return BrowserCameraManagedRoutingSummary(
				availability: .available,
				genericVideoUsesManagedOutput: true,
				failClosedOnManagedVideoRequest: false,
				exposesManagedDeviceIdentity: true
			)
		case .sourceLost:
			return unavailableSummary(.sourceLost)
		case .degraded:
			return unavailableSummary(.degraded)
		case .pipelineFallback:
			return unavailableSummary(.pipelineFallback)
		}
	}

	private static func hasAvailableSource(
		in snapshot: BrowserCameraSessionSnapshot
	) -> Bool {
		snapshot.routingSettings.preferredSourceID != nil || !snapshot.availableSources.isEmpty
	}

	private static func unavailableSummary(
		_ availability: BrowserCameraManagedRoutingAvailability
	) -> BrowserCameraManagedRoutingSummary {
		BrowserCameraManagedRoutingSummary(
			availability: availability,
			genericVideoUsesManagedOutput: false,
			failClosedOnManagedVideoRequest: true,
			exposesManagedDeviceIdentity: false
		)
	}
}
