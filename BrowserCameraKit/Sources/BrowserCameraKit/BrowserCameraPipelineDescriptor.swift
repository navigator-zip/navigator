import AVFoundation
import Foundation
import ModelKit

enum BrowserCameraWarholTransformation: String, Equatable, Sendable {
	case bubblegum
	case darkroom
	case glowInTheDark
	case habenero
}

enum BrowserCameraPipelineFilterName: String, CaseIterable, Sendable {
	case colorControls = "CIColorControls"
	case colorInvert = "CIColorInvert"
	case colorMatrix = "CIColorMatrix"
	case colorMonochrome = "CIColorMonochrome"
	case exposureAdjust = "CIExposureAdjust"
	case multiplyBlendMode = "CIMultiplyBlendMode"
	case photoEffectMono = "CIPhotoEffectMono"
	case randomGenerator = "CIRandomGenerator"
	case sepiaTone = "CISepiaTone"
	case temperatureAndTint = "CITemperatureAndTint"
}

struct BrowserCameraColorVector: Equatable, Sendable {
	let x: Double
	let y: Double
	let z: Double
	let w: Double
}

enum BrowserCameraPipelineRecipeKind: Equatable, Sendable {
	case passthrough
	case monochrome(exposureAdjustment: Double)
	case dither
	case chromatic(
		neutralTemperature: Double,
		targetTemperature: Double,
		saturation: Double,
		contrast: Double,
		redVector: BrowserCameraColorVector
	)
	case supergold
	case warhol(BrowserCameraWarholTransformation)
}

struct BrowserCameraPipelineDescriptor: Equatable, Sendable {
	let warmupProfile: BrowserCameraPipelineWarmupProfile
	let recipeKind: BrowserCameraPipelineRecipeKind
	let grainPresence: BrowserCameraPipelineGrainPresence
	let requiredFilters: Set<BrowserCameraPipelineFilterName>
}

enum BrowserCameraPipelineDescriptorResolver {
	private static let noiseFilters: Set<BrowserCameraPipelineFilterName> = [
		.colorInvert,
		.colorMatrix,
		.colorMonochrome,
		.multiplyBlendMode,
		.randomGenerator,
	]

	static func warmupDescriptors(
		for preset: BrowserCameraFilterPreset,
		grainPresence: BrowserCameraPipelineGrainPresence
	) -> [BrowserCameraPipelineDescriptor] {
		switch preset {
		case .none:
			[descriptor(for: .none, devicePosition: .unspecified, grainPresence: grainPresence)]
		case .monochrome:
			[
				descriptor(for: .monochrome, devicePosition: .back, grainPresence: grainPresence),
				descriptor(for: .monochrome, devicePosition: .front, grainPresence: grainPresence),
			]
		case .dither:
			[descriptor(for: .dither, devicePosition: .unspecified, grainPresence: grainPresence)]
		case .folia:
			[descriptor(for: .folia, devicePosition: .unspecified, grainPresence: grainPresence)]
		case .supergold:
			[descriptor(for: .supergold, devicePosition: .unspecified, grainPresence: grainPresence)]
		case .tonachrome:
			[descriptor(for: .tonachrome, devicePosition: .unspecified, grainPresence: grainPresence)]
		case .bubblegum:
			[descriptor(for: .bubblegum, devicePosition: .unspecified, grainPresence: grainPresence)]
		case .darkroom:
			[descriptor(for: .darkroom, devicePosition: .unspecified, grainPresence: grainPresence)]
		case .glowInTheDark:
			[descriptor(for: .glowInTheDark, devicePosition: .unspecified, grainPresence: grainPresence)]
		case .habenero:
			[descriptor(for: .habenero, devicePosition: .unspecified, grainPresence: grainPresence)]
		}
	}

	static func warmupDescriptors(for preset: BrowserCameraFilterPreset) -> [BrowserCameraPipelineDescriptor] {
		warmupDescriptors(for: preset, grainPresence: .none)
	}

	static func descriptor(
		for preset: BrowserCameraFilterPreset,
		devicePosition: AVCaptureDevice.Position,
		grainPresence: BrowserCameraPipelineGrainPresence
	) -> BrowserCameraPipelineDescriptor {
		switch preset {
		case .none:
			return BrowserCameraPipelineDescriptor(
				warmupProfile: .passthrough,
				recipeKind: .passthrough,
				grainPresence: .none,
				requiredFilters: []
			)
		case .monochrome:
			return BrowserCameraPipelineDescriptor(
				warmupProfile: devicePosition == .front ? .monochromaticFront : .monochromatic,
				recipeKind: .monochrome(exposureAdjustment: devicePosition == .front ? 0.18 : 0.10),
				grainPresence: grainPresence,
				requiredFilters: Set([
					BrowserCameraPipelineFilterName.colorControls,
					BrowserCameraPipelineFilterName.exposureAdjust,
					BrowserCameraPipelineFilterName.photoEffectMono,
					BrowserCameraPipelineFilterName.temperatureAndTint,
				]).union(noiseFilters)
			)
		case .dither:
			return BrowserCameraPipelineDescriptor(
				warmupProfile: .dither,
				recipeKind: .dither,
				grainPresence: grainPresence,
				requiredFilters: Set([
					BrowserCameraPipelineFilterName.photoEffectMono,
				]).union(noiseFilters)
			)
		case .folia:
			return BrowserCameraPipelineDescriptor(
				warmupProfile: .chromaticFolia,
				recipeKind: .chromatic(
					neutralTemperature: 6500,
					targetTemperature: 8600,
					saturation: 1.08,
					contrast: 1.02,
					redVector: BrowserCameraColorVector(x: 0.98, y: 1.05, z: 0.92, w: 0)
				),
				grainPresence: grainPresence,
				requiredFilters: Set([
					BrowserCameraPipelineFilterName.colorControls,
					BrowserCameraPipelineFilterName.colorMatrix,
					BrowserCameraPipelineFilterName.temperatureAndTint,
				]).union(noiseFilters)
			)
		case .supergold:
			return BrowserCameraPipelineDescriptor(
				warmupProfile: .chromaticSupergold,
				recipeKind: .supergold,
				grainPresence: grainPresence,
				requiredFilters: Set([
					BrowserCameraPipelineFilterName.colorControls,
					BrowserCameraPipelineFilterName.exposureAdjust,
					BrowserCameraPipelineFilterName.sepiaTone,
					BrowserCameraPipelineFilterName.temperatureAndTint,
				])
			)
		case .tonachrome:
			return BrowserCameraPipelineDescriptor(
				warmupProfile: .chromaticTonachrome,
				recipeKind: .chromatic(
					neutralTemperature: 6500,
					targetTemperature: 9500,
					saturation: 0.90,
					contrast: 1.08,
					redVector: BrowserCameraColorVector(x: 1.04, y: 0.98, z: 0.88, w: 0)
				),
				grainPresence: grainPresence,
				requiredFilters: Set([
					BrowserCameraPipelineFilterName.colorControls,
					BrowserCameraPipelineFilterName.colorMatrix,
					BrowserCameraPipelineFilterName.temperatureAndTint,
				]).union(noiseFilters)
			)
		case .bubblegum:
			return BrowserCameraPipelineDescriptor(
				warmupProfile: .warholBubblegum,
				recipeKind: .warhol(.bubblegum),
				grainPresence: grainPresence,
				requiredFilters: noiseFilters
			)
		case .darkroom:
			return BrowserCameraPipelineDescriptor(
				warmupProfile: .warholDarkroom,
				recipeKind: .warhol(.darkroom),
				grainPresence: grainPresence,
				requiredFilters: noiseFilters
			)
		case .glowInTheDark:
			return BrowserCameraPipelineDescriptor(
				warmupProfile: .warholGlowInTheDark,
				recipeKind: .warhol(.glowInTheDark),
				grainPresence: grainPresence,
				requiredFilters: noiseFilters
			)
		case .habenero:
			return BrowserCameraPipelineDescriptor(
				warmupProfile: .warholHabenero,
				recipeKind: .warhol(.habenero),
				grainPresence: grainPresence,
				requiredFilters: noiseFilters
			)
		}
	}

	static func descriptor(
		for preset: BrowserCameraFilterPreset,
		devicePosition: AVCaptureDevice.Position
	) -> BrowserCameraPipelineDescriptor {
		descriptor(for: preset, devicePosition: devicePosition, grainPresence: .none)
	}
}
