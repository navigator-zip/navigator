import ApplicationServices
import Foundation

struct PermissionStateSnapshot: Equatable, Sendable {
	let accessibilityTrusted: Bool
	let inputMonitoringTrusted: Bool

	var publicStatus: TrackpadGesturePermissionStatus {
		TrackpadGesturePermissionStatus(
			accessibilityTrusted: accessibilityTrusted,
			inputMonitoringTrusted: inputMonitoringTrusted
		)
	}
}

protocol PermissionStateProviding: Sendable {
	func snapshot() -> PermissionStateSnapshot
}

struct PermissionTrustClient: Sendable {
	let isAccessibilityTrusted: @Sendable () -> Bool
	let isInputMonitoringTrusted: @Sendable () -> Bool

	static func resolveInputMonitoringTrust(
		isPreflightSupported: Bool,
		preflightCheck: @Sendable () -> Bool
	) -> Bool {
		guard isPreflightSupported else {
			return true
		}
		return preflightCheck()
	}

	static let live = PermissionTrustClient(
		isAccessibilityTrusted: {
			AXIsProcessTrusted()
		},
		isInputMonitoringTrusted: {
			return resolveInputMonitoringTrust(
				isPreflightSupported: true,
				preflightCheck: { CGPreflightListenEventAccess() }
			)
		}
	)
}

struct SystemPermissionStateProvider: PermissionStateProviding {
	let trustClient: PermissionTrustClient

	init(trustClient: PermissionTrustClient = .live) {
		self.trustClient = trustClient
	}

	func snapshot() -> PermissionStateSnapshot {
		PermissionStateSnapshot(
			accessibilityTrusted: trustClient.isAccessibilityTrusted(),
			inputMonitoringTrusted: trustClient.isInputMonitoringTrusted()
		)
	}
}
