@testable import TrackpadGestures
import XCTest

final class TrackpadGesturePermissionsLiveTests: XCTestCase {
	func testSystemPermissionStateProviderLiveSnapshotIsCallable() {
		let snapshot = SystemPermissionStateProvider().snapshot()
		_ = snapshot.accessibilityTrusted
		_ = snapshot.inputMonitoringTrusted
	}
}
