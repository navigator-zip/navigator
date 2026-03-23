import AppKit

@MainActor
final class ReorderableListPlaceholderCoordinator {
	private let placeholderView: ReorderableListDragPlaceholderView
	private var currentFrame: CGRect?

	init(placeholderView: ReorderableListDragPlaceholderView) {
		self.placeholderView = placeholderView
	}

	func show(frame: CGRect) {
		currentFrame = frame
		placeholderView.show(frame: frame)
	}

	func hide() {
		currentFrame = nil
		placeholderView.hide()
	}

	func frameIfVisible() -> CGRect? {
		guard placeholderView.isHidden == false else { return nil }
		return currentFrame
	}
}
