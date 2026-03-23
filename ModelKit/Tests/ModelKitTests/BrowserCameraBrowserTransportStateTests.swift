import ModelKit
import XCTest

final class BrowserCameraBrowserTransportStateTests: XCTestCase {
	func testBrowserTransportModesRemainStableForDiagnosticsContracts() {
		XCTAssertEqual(
			BrowserCameraBrowserTransportMode.allCases,
			[
				.unavailable,
				.rendererProcessMessages,
				.browserProcessJavaScriptFallback,
			]
		)
	}

	func testBrowserTransportStateClampsNegativeManagedTrackCounts() {
		let state = BrowserCameraBrowserTransportState(
			tabID: "tab-1",
			routingTransportMode: .rendererProcessMessages,
			frameTransportMode: .browserProcessJavaScriptFallback,
			activeManagedTrackCount: -4
		)

		XCTAssertEqual(state.activeManagedTrackCount, 0)
		XCTAssertTrue(state.isUsingBrowserProcessFallback)
	}

	func testBrowserTransportStateRoundTripsThroughCodable() throws {
		let state = BrowserCameraBrowserTransportState(
			tabID: "tab-1",
			routingTransportMode: .rendererProcessMessages,
			frameTransportMode: .rendererProcessMessages,
			activeManagedTrackCount: 2
		)

		let decoded = try JSONDecoder().decode(
			BrowserCameraBrowserTransportState.self,
			from: JSONEncoder().encode(state)
		)

		XCTAssertEqual(decoded, state)
		XCTAssertFalse(decoded.isUsingBrowserProcessFallback)
	}
}
