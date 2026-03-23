import SwiftUI

public extension View {
	var emboss: some View {
		ZStack {
			self
				.foregroundColor(.white)
				.offset(y: 1)

			self
		}
	}
}
