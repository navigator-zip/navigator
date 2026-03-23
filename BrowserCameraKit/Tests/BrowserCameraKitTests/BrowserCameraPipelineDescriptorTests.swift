import AVFoundation
@testable import BrowserCameraKit
import XCTest

final class BrowserCameraPipelineDescriptorTests: XCTestCase {
	func testWarmupDescriptorsMatchApertureProfiles() {
		XCTAssertEqual(
			BrowserCameraPipelineDescriptorResolver
				.warmupDescriptors(for: .monochrome, grainPresence: .high)
				.map(\.warmupProfile),
			[
				.monochromatic,
				.monochromaticFront,
			]
		)
		XCTAssertEqual(
			BrowserCameraPipelineDescriptorResolver
				.warmupDescriptors(for: .vertichrome)
				.map(\.warmupProfile),
			[
				.chromaticTonachrome,
			]
		)
	}

	func testDescriptorResolverUsesFrontAndBackMononokeVariants() {
		let frontDescriptor = BrowserCameraPipelineDescriptorResolver.descriptor(
			for: .monochrome,
			devicePosition: .front,
			grainPresence: .high
		)
		let backDescriptor = BrowserCameraPipelineDescriptorResolver.descriptor(
			for: .monochrome,
			devicePosition: .back,
			grainPresence: .high
		)

		XCTAssertEqual(frontDescriptor.warmupProfile, .monochromaticFront)
		XCTAssertEqual(backDescriptor.warmupProfile, .monochromatic)
		XCTAssertEqual(frontDescriptor.grainPresence, .high)
		XCTAssertEqual(backDescriptor.grainPresence, .high)
		XCTAssertEqual(
			frontDescriptor.recipeKind,
			.monochrome(exposureAdjustment: 0.18)
		)
		XCTAssertEqual(
			backDescriptor.recipeKind,
			.monochrome(exposureAdjustment: 0.10)
		)
	}

	func testDescriptorResolverMapsChromaticProfilesToApertureNames() {
		let foliaDescriptor = BrowserCameraPipelineDescriptorResolver.descriptor(
			for: .folia,
			devicePosition: .unspecified,
			grainPresence: .normal
		)
		let supergoldDescriptor = BrowserCameraPipelineDescriptorResolver.descriptor(
			for: .supergold,
			devicePosition: .unspecified,
			grainPresence: .none
		)

		XCTAssertEqual(foliaDescriptor.warmupProfile, .chromaticFolia)
		XCTAssertEqual(supergoldDescriptor.warmupProfile, .chromaticSupergold)
		XCTAssertEqual(foliaDescriptor.grainPresence, .normal)
		XCTAssertEqual(supergoldDescriptor.grainPresence, .none)
		XCTAssertTrue(foliaDescriptor.requiredFilters.contains(.colorMatrix))
		XCTAssertTrue(supergoldDescriptor.requiredFilters.contains(.sepiaTone))
	}

	func testDescriptorResolverReturnsPassthroughForNone() {
		let descriptor = BrowserCameraPipelineDescriptorResolver.descriptor(
			for: .none,
			devicePosition: .unspecified
		)

		XCTAssertEqual(descriptor.warmupProfile, .passthrough)
		XCTAssertEqual(descriptor.recipeKind, .passthrough)
		XCTAssertEqual(descriptor.requiredFilters, [])
	}
}
