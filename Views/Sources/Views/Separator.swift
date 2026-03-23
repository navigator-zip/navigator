import BrandColors
import Foundation
import Helpers
import SwiftUI

@MainActor
public var separator: some View {
	SkeumorphicSeparatorView()
}

@MainActor
public var verticalSeparator: some View {
	SkeumorphicVerticalSeparatorView()
}

private struct SkeumorphicSeparatorView: View {
	@Environment(\.colorScheme) private var colorScheme

	private var primaryFill: Color {
		if colorScheme == .dark {
			Color.black
		}
		else {
			BrandColors.baseBackgroundAlternate
		}
	}

	private var secondaryFill: Color {
		if colorScheme == .dark {
			Color.gray.opacity(0.5)
		}
		else {
			Color.white
		}
	}

	var body: some View {
		VStack(spacing: 0) {
			Rectangle()
				.fill(primaryFill)
				.frame(height: 2)
			Rectangle()
				.fill(secondaryFill)
				.frame(height: 1)
		}
	}
}

private struct SkeumorphicVerticalSeparatorView: View {
	@Environment(\.colorScheme) private var colorScheme

	private var primaryFill: Color {
		if colorScheme == .dark {
			Color.black
		}
		else {
			BrandColors.baseBackgroundAlternate
		}
	}

	private var secondaryFill: Color {
		Color.gray.opacity(0.5)
	}

	var body: some View {
		HStack(spacing: 0) {
			Rectangle()
				.fill(primaryFill)
				.frame(width: 2)
			Rectangle()
				.fill(secondaryFill)
				.frame(width: 1)
		}
		.expand(.vertical)
	}
}
