import Foundation
import Observation

@MainActor
@Observable
public final class OverlayViewModel {
	public typealias Sleep = @Sendable (Duration) async throws -> Void

	public enum PresentationStyle: Equatable, Sendable {
		case toast(duration: Duration?)
	}

	public var isActive: Bool

	public let style: PresentationStyle
	private let sleep: Sleep?
	private let didFinishDismissalAnimation: @MainActor () -> Void
	private var autoDismissTask: Task<Void, Never>?

	private static let teardownDuration: Duration = .milliseconds(350)

	public init(
		style: PresentationStyle = .toast(duration: nil),
		sleep: Sleep? = nil,
		didFinishDismissalAnimation: @escaping @MainActor () -> Void
	) {
		self.isActive = true
		self.style = style
		self.sleep = sleep
		self.didFinishDismissalAnimation = didFinishDismissalAnimation

		if case .toast(let duration) = style, let duration {
			scheduleAutoDismiss(after: duration)
		}
	}

	public func didRequestDismissal() async {
		guard isActive else { return }
		isActive = false
		autoDismissTask?.cancel()
		try? await dismissEffect()
	}

	private func scheduleAutoDismiss(after duration: Duration) {
		autoDismissTask?.cancel()
		autoDismissTask = Task { @MainActor [weak self, sleep] in
			if let sleep {
				try? await sleep(duration)
			}
			else {
				try? await Task.sleep(for: duration)
			}
			guard Task.isCancelled == false else { return }
			await self?.didRequestDismissal()
		}
	}

	private func dismissEffect() async throws {
		if let sleep {
			try await sleep(Self.teardownDuration)
		}
		else {
			try await Task.sleep(for: Self.teardownDuration)
		}
		didFinishDismissalAnimation()
	}
}
