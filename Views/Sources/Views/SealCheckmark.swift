import Helpers
import SwiftUI

public struct SealCheckmark: View {
	private let dimension: CGFloat

	public init(dimension: CGFloat = 25) {
		self.dimension = dimension
	}

	public var body: some View {
		ZStack {
			Image(systemName: "seal.fill")
				.resizable()
				.frame(dimension: dimension)
				.foregroundColor(.green)
				.blendMode(.difference)
				.phaseAnimator([0.0, 360.0]) { view, angle in
					view.rotationEffect(.degrees(angle))
				} animation: { _ in
					.linear(duration: 12).repeatForever(autoreverses: false)
				}

			Image(systemName: "checkmark")
				.resizable()
				.font(.title.weight(.black))
				.frame(dimension: dimension * 0.4)
				.foregroundStyle(.secondary)
		}
		.drawingGroup()
	}
}
