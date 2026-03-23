import SwiftUI

@MainActor
public extension Animation {
	static var springable: Animation {
		.spring(response: 0.35, dampingFraction: 0.82)
	}

	static var pushPopSpringable: Animation {
		.spring(response: 0.4, dampingFraction: 0.86)
	}
}
