@testable import TrackpadGestures
import XCTest

final class PermissionStateProviderTests: XCTestCase {
	func testSystemPermissionStateProviderReturnsInjectedTrustSnapshot() {
		let provider = SystemPermissionStateProvider(
			trustClient: PermissionTrustClient(
				isAccessibilityTrusted: { false },
				isInputMonitoringTrusted: { true }
			)
		)

		XCTAssertEqual(
			provider.snapshot(),
			PermissionStateSnapshot(accessibilityTrusted: false, inputMonitoringTrusted: true)
		)
	}

	func testResolveInputMonitoringTrustReturnsTrueWhenPreflightIsUnavailable() {
		let trust = PermissionTrustClient.resolveInputMonitoringTrust(
			isPreflightSupported: false,
			preflightCheck: { false }
		)

		XCTAssertTrue(trust)
	}

	func testResolveInputMonitoringTrustUsesPreflightWhenSupported() {
		let trust = PermissionTrustClient.resolveInputMonitoringTrust(
			isPreflightSupported: true,
			preflightCheck: { false }
		)

		XCTAssertFalse(trust)
	}
}
