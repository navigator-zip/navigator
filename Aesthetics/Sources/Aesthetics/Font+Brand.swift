import SwiftUI

public extension Font {
	static func brandDisplay(
		_ textStyle: Font.TextStyle,
		weight: Font.Weight = .regular
	) -> Font {
		.system(
			size: pointSize(for: textStyle),
			weight: weight
		)
	}

	static func brandDisplay(
		size: CGFloat,
		weight: Font.Weight = .regular
	) -> Font {
		.system(size: size, weight: weight)
	}

	private static func pointSize(for textStyle: Font.TextStyle) -> CGFloat {
		switch textStyle {
		case .largeTitle:
			34
		case .title:
			28
		case .title2:
			22
		case .title3:
			20
		case .headline:
			17
		case .subheadline:
			15
		case .callout:
			16
		case .caption:
			12
		case .caption2:
			11
		case .footnote:
			13
		case .body:
			17
		@unknown default:
			17
		}
	}
}
