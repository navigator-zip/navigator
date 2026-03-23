import SwiftUI

public extension View {
	var titleStyling: some View {
		self
			.foregroundStyle(.primary)
			.multilineTextAlignment(.leading)
			.font(.brandDisplay(.headline, weight: .bold))
	}

	var subtitleStyling: some View {
		self
			.foregroundStyle(.secondary)
			.multilineTextAlignment(.leading)
			.font(.brandDisplay(.subheadline, weight: .bold))
	}
}
