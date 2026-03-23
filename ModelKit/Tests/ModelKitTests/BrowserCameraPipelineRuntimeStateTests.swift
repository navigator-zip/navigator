import ModelKit
import XCTest

final class BrowserCameraPipelineRuntimeStateTests: XCTestCase {
	func testPipelineRuntimeStateNormalizesNegativeFilterCounts() {
		let state = BrowserCameraPipelineRuntimeState(
			preset: .mononoke,
			implementation: .navigatorFallback,
			warmupProfile: .monochromatic,
			grainPresence: .high,
			requiredFilterCount: -3
		)

		XCTAssertEqual(state.requiredFilterCount, 0)
		XCTAssertTrue(state.isFallbackActive)
	}

	func testPipelineRuntimeStateRoundTripsThroughCodable() throws {
		let state = BrowserCameraPipelineRuntimeState(
			preset: .supergold,
			implementation: .aperture,
			warmupProfile: .chromaticSupergold,
			grainPresence: .none,
			requiredFilterCount: 4
		)

		let decoded = try JSONDecoder().decode(
			BrowserCameraPipelineRuntimeState.self,
			from: JSONEncoder().encode(state)
		)

		XCTAssertEqual(decoded, state)
		XCTAssertFalse(decoded.isFallbackActive)
	}
}
