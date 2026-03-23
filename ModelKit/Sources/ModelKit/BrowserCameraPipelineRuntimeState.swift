import Foundation

public enum BrowserCameraPipelineWarmupProfile: String, Codable, CaseIterable, Sendable {
	case passthrough
	case chromaticFolia = "chromatic.folia"
	case chromaticSupergold = "chromatic.supergold"
	case chromaticTonachrome = "chromatic.tonachrome"
	case dither
	case monochromatic
	case monochromaticFront = "monochromatic.front"
	case warholBubblegum = "warhol.bubblegum"
	case warholDarkroom = "warhol.darkroom"
	case warholGlowInTheDark = "warhol.glowInTheDark"
	case warholHabenero = "warhol.habenero"
}

public enum BrowserCameraPipelineGrainPresence: String, Codable, CaseIterable, Sendable {
	case none
	case normal
	case high
}

public enum BrowserCameraPipelineImplementation: String, Codable, CaseIterable, Sendable {
	case passthrough
	case aperture
	case navigatorFallback
}

public struct BrowserCameraPipelineRuntimeState: Codable, Equatable, Hashable, Sendable {
	public let preset: BrowserCameraFilterPreset
	public let implementation: BrowserCameraPipelineImplementation
	public let warmupProfile: BrowserCameraPipelineWarmupProfile
	public let grainPresence: BrowserCameraPipelineGrainPresence
	public let requiredFilterCount: Int

	public var isFallbackActive: Bool {
		implementation == .navigatorFallback
	}

	public init(
		preset: BrowserCameraFilterPreset,
		implementation: BrowserCameraPipelineImplementation,
		warmupProfile: BrowserCameraPipelineWarmupProfile,
		grainPresence: BrowserCameraPipelineGrainPresence,
		requiredFilterCount: Int
	) {
		self.preset = preset
		self.implementation = implementation
		self.warmupProfile = warmupProfile
		self.grainPresence = grainPresence
		self.requiredFilterCount = max(0, requiredFilterCount)
	}
}
