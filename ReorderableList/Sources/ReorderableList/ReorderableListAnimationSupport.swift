import AppKit

final class ReorderableListAnimationLayer: CALayer {
	override func action(forKey event: String) -> CAAction? {
		NSNull()
	}
}

final class ReorderableListAnimationShapeLayer: CAShapeLayer {
	override func action(forKey event: String) -> CAAction? {
		NSNull()
	}
}

func reorderableListPerformOnMain(_ action: @escaping @MainActor () -> Void) {
	if Thread.isMainThread {
		MainActor.assumeIsolated {
			action()
		}
	}
	else {
		DispatchQueue.main.sync {
			MainActor.assumeIsolated {
				action()
			}
		}
	}
}
