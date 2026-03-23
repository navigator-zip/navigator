import Foundation
import SwiftUI

private struct SizeKey: PreferenceKey {
	static var defaultValue: CGSize {
		.zero
	}

	static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
		value = nextValue()
	}
}

public extension View {
	func onSizeChange(
		_ onChange: @escaping @Sendable @MainActor (CGSize) -> Void
	) -> some View {
		overlay {
			GeometryReader { proxy in
				Color.clear.preference(
					key: SizeKey.self,
					value: proxy.size
				)
			}
			.onPreferenceChange(SizeKey.self) { size in
				onChange(size)
			}
			.allowsHitTesting(false)
		}
	}

	func onSizeChange(
		_ binding: Binding<CGSize>
	) -> some View {
		overlay {
			GeometryReader { proxy in
				Color.clear.preference(
					key: SizeKey.self,
					value: proxy.size
				)
			}
			.onPreferenceChange(SizeKey.self) { size in
				binding.wrappedValue = size
			}
			.allowsHitTesting(false)
		}
	}
}
