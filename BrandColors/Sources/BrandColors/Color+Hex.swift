import SwiftUI

public extension Color {
	init(hex: UInt, alpha: Double = 1) {
		self = Color(
			.sRGB,
			red: Double((hex >> 16) & 0xFF) / 255,
			green: Double((hex >> 8) & 0xFF) / 255,
			blue: Double((hex >> 0) & 0xFF) / 255,
			opacity: alpha
		)
	}
}
