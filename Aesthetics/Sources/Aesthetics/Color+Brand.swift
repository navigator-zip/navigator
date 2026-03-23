// swiftlint:disable all
#if os(macOS)
	import AppKit
#elseif os(iOS) || os(tvOS) || os(watchOS)
	import UIKit
#endif

public typealias Color = ColorAsset.Color

public extension Color {
	static var brandAccent: Color {
		Asset.Colors.accent.color
	}

	static var brandAccentForeground: Color {
		Asset.Colors.accentForegroundColor.color
	}

	static var brandPrimarySeparator: Color {
		Asset.Colors.separatorPrimaryColor.color
	}

	static var brandSecondarySeparator: Color {
		Asset.Colors.separatorSecondaryColor.color
	}

	static var brandPrimaryText: Color {
		Asset.Colors.textPrimaryColor.color
	}

	static var brandUnmodifiedCodeBackground: Color {
		Asset.Colors.unmodifiedCodeBackgroundColor.color
	}

	static var brandBackground: Color {
		Asset.Colors.background.color
	}

	static var brandControlAccent: Color {
		Asset.Colors.controlAccentColor.color
	}

	static var navigatorChromeFill: Color {
		secondarySystemFill
	}
}
