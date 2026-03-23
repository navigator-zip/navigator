import Dependencies
import Foundation

public enum SoundEffect: Sendable {
	case anvilAnimation
	case overlayPresented
	case overlayDismissed
	case segmentedControlOn
	case weightUnitFlip
	case horizontalDialTick(fileName: String)
}

public struct SoundEffectsClient: Sendable {
	public var play: @Sendable (SoundEffect) -> Void

	public init(play: @escaping @Sendable (SoundEffect) -> Void) {
		self.play = play
	}
}

extension SoundEffectsClient: DependencyKey {
	public static let liveValue = SoundEffectsClient { _ in }
	public static let testValue = SoundEffectsClient { _ in }
}

public extension DependencyValues {
	var soundEffects: SoundEffectsClient {
		get { self[SoundEffectsClient.self] }
		set { self[SoundEffectsClient.self] = newValue }
	}
}
