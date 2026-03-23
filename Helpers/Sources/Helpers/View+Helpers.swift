import Foundation
import SwiftUI

public extension View {
	func frame(
		dimension: CGFloat?,
		alignment: Alignment = .center
	) -> some View {
		frame(
			width: dimension,
			height: dimension,
			alignment: alignment
		)
	}

	func frame(
		size: CGSize
	) -> some View {
		frame(
			width: size.width,
			height: size.height
		)
	}

	func expand(
		_ axes: Axis.Set = [.horizontal, .vertical],
		alignment: Alignment = .center
	) -> some View {
		frame(
			maxWidth: axes.contains(.horizontal) ? .infinity : nil,
			maxHeight: axes.contains(.vertical) ? .infinity : nil,
			alignment: alignment
		)
	}
}
