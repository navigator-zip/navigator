import SwiftUI
#if os(iOS) || os(tvOS) || os(visionOS)
	import UIKit
#elseif os(macOS)
	import AppKit
#endif

public enum BrandColors {
	public static let brandBlueHex: UInt = 0x0000FF
	public static let brandOrangeHex: UInt = 0xFFA503

	public static var accent: Color {
		dynamic(light: brandBlueHex, dark: brandOrangeHex)
	}

	public static var accentLight: Color {
		Color(hex: brandBlueHex)
	}

	public static var accentDark: Color {
		Color(hex: brandOrangeHex)
	}

	public static var blue: Color {
		Color(hex: brandBlueHex)
	}

	public static var orange: Color {
		Color(hex: brandOrangeHex)
	}

	public static let baseBackgroundLightHex: UInt = 0xFFFFFF
	public static let baseBackgroundDarkHex: UInt = 0x262626

	public static var baseBackground: Color {
		dynamic(light: baseBackgroundLightHex, dark: baseBackgroundDarkHex)
	}

	public static var baseBackgroundLight: Color {
		Color(hex: baseBackgroundLightHex)
	}

	public static var baseBackgroundDark: Color {
		Color(hex: baseBackgroundDarkHex)
	}

	public static let baseBackgroundAlternateLightHex: UInt = 0xE5E5E5
	public static let baseBackgroundAlternateDarkHex: UInt = 0x1A1A1A

	public static var baseBackgroundAlternate: Color {
		dynamic(light: baseBackgroundAlternateLightHex, dark: baseBackgroundAlternateDarkHex)
	}

	public static var baseBackgroundAlternateLight: Color {
		Color(hex: baseBackgroundAlternateLightHex)
	}

	public static var baseBackgroundAlternateDark: Color {
		Color(hex: baseBackgroundAlternateDarkHex)
	}

	public static let cardBackgroundLightHex: UInt = 0xFFFFFF
	public static let cardBackgroundDarkHex: UInt = 0x262626

	public static var cardBackground: Color {
		dynamic(light: cardBackgroundLightHex, dark: cardBackgroundDarkHex)
	}

	public static var cardBackgroundLight: Color {
		Color(hex: cardBackgroundLightHex)
	}

	public static var cardBackgroundDark: Color {
		Color(hex: cardBackgroundDarkHex)
	}

	public static let cardOverlayBackgroundLightHex: UInt = 0xDFDFDF
	public static let cardOverlayBackgroundDarkHex: UInt = 0x333333

	public static var cardOverlayBackground: Color {
		dynamic(light: cardOverlayBackgroundLightHex, dark: cardOverlayBackgroundDarkHex)
	}

	public static var cardOverlayBackgroundLight: Color {
		Color(hex: cardOverlayBackgroundLightHex)
	}

	public static var cardOverlayBackgroundDark: Color {
		Color(hex: cardOverlayBackgroundDarkHex)
	}

	public static let primaryButtonBackgroundLightHex: UInt = 0x262626
	public static let primaryButtonBackgroundDarkHex: UInt = 0xD9D9D9

	public static var primaryButtonBackground: Color {
		dynamic(light: primaryButtonBackgroundLightHex, dark: primaryButtonBackgroundDarkHex)
	}

	public static var primaryButtonBackgroundLight: Color {
		Color(hex: primaryButtonBackgroundLightHex)
	}

	public static var primaryButtonBackgroundDark: Color {
		Color(hex: primaryButtonBackgroundDarkHex)
	}

	public static let primaryButtonTextLightHex: UInt = 0xFEFEFE
	public static let primaryButtonTextDarkHex: UInt = 0x262626

	public static var primaryButtonText: Color {
		dynamic(light: primaryButtonTextLightHex, dark: primaryButtonTextDarkHex)
	}

	public static var primaryButtonTextLight: Color {
		Color(hex: primaryButtonTextLightHex)
	}

	public static var primaryButtonTextDark: Color {
		Color(hex: primaryButtonTextDarkHex)
	}

	public static let secondaryButtonBackgroundLightHex: UInt = 0xEEEEEE
	public static let secondaryButtonBackgroundDarkHex: UInt = 0x333333

	public static var secondaryButtonBackground: Color {
		dynamic(light: secondaryButtonBackgroundLightHex, dark: secondaryButtonBackgroundDarkHex)
	}

	public static var secondaryButtonBackgroundLight: Color {
		Color(hex: secondaryButtonBackgroundLightHex)
	}

	public static var secondaryButtonBackgroundDark: Color {
		Color(hex: secondaryButtonBackgroundDarkHex)
	}

	public static let secondaryButtonTextLightHex: UInt = 0x262626
	public static let secondaryButtonTextDarkHex: UInt = 0xD8D8D8

	public static var secondaryButtonText: Color {
		dynamic(light: secondaryButtonTextLightHex, dark: secondaryButtonTextDarkHex)
	}

	public static var secondaryButtonTextLight: Color {
		Color(hex: secondaryButtonTextLightHex)
	}

	public static var secondaryButtonTextDark: Color {
		Color(hex: secondaryButtonTextDarkHex)
	}

	public static let paneBackgroundLightHex: UInt = 0xF3F3F3
	public static let paneBackgroundDarkHex: UInt = 0x25292D

	public static var paneBackground: Color {
		dynamic(light: paneBackgroundLightHex, dark: paneBackgroundDarkHex)
	}

	public static var paneBackgroundLight: Color {
		Color(hex: paneBackgroundLightHex)
	}

	public static var paneBackgroundDark: Color {
		Color(hex: paneBackgroundDarkHex)
	}

	public static let segmentedControlBackgroundLightHex: UInt = 0xFDFEFE
	public static let segmentedControlBackgroundDarkHex: UInt = 0x262626

	public static var segmentedControlBackground: Color {
		dynamic(light: segmentedControlBackgroundLightHex, dark: segmentedControlBackgroundDarkHex)
	}

	public static var segmentedControlBackgroundLight: Color {
		Color(hex: segmentedControlBackgroundLightHex)
	}

	public static var segmentedControlBackgroundDark: Color {
		Color(hex: segmentedControlBackgroundDarkHex)
	}

	public static let segmentedControlBackgroundIconLightHex: UInt = 0x666666
	public static let segmentedControlBackgroundIconDarkHex: UInt = 0x8C8C8C

	public static var segmentedControlBackgroundIcon: Color {
		dynamic(
			light: segmentedControlBackgroundIconLightHex,
			dark: segmentedControlBackgroundIconDarkHex
		)
	}

	public static var segmentedControlBackgroundIconLight: Color {
		Color(hex: segmentedControlBackgroundIconLightHex)
	}

	public static var segmentedControlBackgroundIconDark: Color {
		Color(hex: segmentedControlBackgroundIconDarkHex)
	}

	public static let segmentedControlPillBackgroundLightHex: UInt = 0xF1F1F1
	public static let segmentedControlPillBackgroundDarkHex: UInt = 0x333333

	public static var segmentedControlPillBackground: Color {
		dynamic(light: segmentedControlPillBackgroundLightHex, dark: segmentedControlPillBackgroundDarkHex)
	}

	public static var segmentedControlPillBackgroundLight: Color {
		Color(hex: segmentedControlPillBackgroundLightHex)
	}

	public static var segmentedControlPillBackgroundDark: Color {
		Color(hex: segmentedControlPillBackgroundDarkHex)
	}

	public static let segmentedControlPillPrimaryForegroundLightHex: UInt = 0x2A2A2A
	public static let segmentedControlPillPrimaryForegroundDarkHex: UInt = 0xDADADA

	public static var segmentedControlPillPrimaryForeground: Color {
		dynamic(
			light: segmentedControlPillPrimaryForegroundLightHex,
			dark: segmentedControlPillPrimaryForegroundDarkHex
		)
	}

	public static var segmentedControlPillPrimaryForegroundLight: Color {
		Color(hex: segmentedControlPillPrimaryForegroundLightHex)
	}

	public static var segmentedControlPillPrimaryForegroundDark: Color {
		Color(hex: segmentedControlPillPrimaryForegroundDarkHex)
	}

	public static let segmentedControlPillSecondaryForegroundLightHex: UInt = 0x5E5E5E
	public static let segmentedControlPillSecondaryForegroundDarkHex: UInt = 0x8D8D8D

	public static var segmentedControlPillSecondaryForeground: Color {
		dynamic(
			light: segmentedControlPillSecondaryForegroundLightHex,
			dark: segmentedControlPillSecondaryForegroundDarkHex
		)
	}

	public static var segmentedControlPillSecondaryForegroundLight: Color {
		Color(hex: segmentedControlPillSecondaryForegroundLightHex)
	}

	public static var segmentedControlPillSecondaryForegroundDark: Color {
		Color(hex: segmentedControlPillSecondaryForegroundDarkHex)
	}

	public static let splitPaneDividerLightHex: UInt = 0x242424
	public static let splitPaneDividerDarkHex: UInt = 0xFFFFFF

	public static var splitPaneDivider: Color {
		dynamic(light: splitPaneDividerLightHex, dark: splitPaneDividerDarkHex)
	}

	public static var splitPaneDividerLight: Color {
		Color(hex: splitPaneDividerLightHex)
	}

	public static var splitPaneDividerDark: Color {
		Color(hex: splitPaneDividerDarkHex)
	}

	public static let splitPaneStripLightHex: UInt = 0xFFFFFF
	public static let splitPaneStripDarkHex: UInt = 0x000000

	public static var splitPaneStrip: Color {
		dynamic(light: splitPaneStripLightHex, dark: splitPaneStripDarkHex)
	}

	public static var splitPaneStripLight: Color {
		Color(hex: splitPaneStripLightHex)
	}

	public static var splitPaneStripDark: Color {
		Color(hex: splitPaneStripDarkHex)
	}

	public static let splitPaneInnerStrokeHex: UInt = 0x4D4E50

	public static var splitPaneInnerStroke: Color {
		Color(hex: splitPaneInnerStrokeHex)
	}

	public static let splitPaneMiddleBackgroundLightHex: UInt = 0xE5E5E5
	public static let splitPaneMiddleBackgroundDarkHex: UInt = 0x1A1A1A

	public static var splitPaneMiddleBackground: Color {
		dynamic(
			light: splitPaneMiddleBackgroundLightHex,
			dark: splitPaneMiddleBackgroundDarkHex
		)
	}

	public static var splitPaneMiddleBackgroundLight: Color {
		Color(hex: splitPaneMiddleBackgroundLightHex)
	}

	public static var splitPaneMiddleBackgroundDark: Color {
		Color(hex: splitPaneMiddleBackgroundDarkHex)
	}

	public static let toggleBackgroundLightHex: UInt = 0x262626
	public static let toggleBackgroundDarkHex: UInt = 0xD9D9D9

	public static var toggleBackground: Color {
		dynamic(light: toggleBackgroundLightHex, dark: toggleBackgroundDarkHex)
	}

	public static var toggleBackgroundLight: Color {
		Color(hex: toggleBackgroundLightHex)
	}

	public static var toggleBackgroundDark: Color {
		Color(hex: toggleBackgroundDarkHex)
	}

	public static let togglePillLightHex: UInt = 0xFFFFFF
	public static let togglePillDarkHex: UInt = 0x242424

	public static var togglePill: Color {
		dynamic(light: togglePillLightHex, dark: togglePillDarkHex)
	}

	public static var togglePillLight: Color {
		Color(hex: togglePillLightHex)
	}

	public static var togglePillDark: Color {
		Color(hex: togglePillDarkHex)
	}

	public static let togglePillReversedLightHex: UInt = 0x242424
	public static let togglePillReversedDarkHex: UInt = 0xFFFFFF

	public static var togglePillReversed: Color {
		dynamic(light: togglePillReversedLightHex, dark: togglePillReversedDarkHex)
	}

	public static var togglePillReversedLight: Color {
		Color(hex: togglePillReversedLightHex)
	}

	public static var togglePillReversedDark: Color {
		Color(hex: togglePillReversedDarkHex)
	}

	public static let widgetBackgroundLightHex: UInt = 0xFFFFFF
	public static let widgetBackgroundDarkHex: UInt = 0x444444

	public static var widgetBackground: Color {
		dynamic(light: widgetBackgroundLightHex, dark: widgetBackgroundDarkHex)
	}

	public static var widgetBackgroundLight: Color {
		Color(hex: widgetBackgroundLightHex)
	}

	public static var widgetBackgroundDark: Color {
		Color(hex: widgetBackgroundDarkHex)
	}

	private static func dynamic(light: UInt, dark: UInt) -> Color {
		#if os(iOS) || os(tvOS) || os(visionOS)
			return Color(
				UIColor { traits in
					traits.userInterfaceStyle == .dark
						? UIColor(Color(hex: dark))
						: UIColor(Color(hex: light))
				}
			)
		#elseif os(macOS)
			return Color(
				NSColor(
					name: nil,
					dynamicProvider: { appearance in
						let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
						return NSColor(Color(hex: isDark ? dark : light))
					}
				)
			)
		#else
			return Color(hex: light)
		#endif
	}
}
