import AppKit

@MainActor
final class ReorderableListOverlayCoordinator {
	private let dragVisualController: ReorderableListDragVisualController
	private weak var hostView: NSView?

	init(dragVisualController: ReorderableListDragVisualController) {
		self.dragVisualController = dragVisualController
	}

	var currentFrameInHost: CGRect? {
		dragVisualController.currentFrameInHost
	}

	var isActive: Bool {
		dragVisualController.isActive
	}

	var settleDuration: TimeInterval? {
		dragVisualController.settleDuration
	}

	func attach(to hostView: NSView) {
		self.hostView = hostView
		dragVisualController.attach(to: hostView)
	}

	func beginLift(
		snapshotImage: NSImage,
		frame: CGRect,
		backgroundColor: NSColor,
		appearance: ReorderDragAppearance,
		chromeGeometry: ReorderableListDragChromeGeometry? = nil
	) {
		dragVisualController.beginLift(
			snapshotImage: snapshotImage,
			frame: frame,
			backgroundColor: backgroundColor,
			appearance: appearance,
			chromeGeometry: chromeGeometry
		)
	}

	func move(_ frameInHost: CGRect) -> ReorderableListDragVisualUpdateKind {
		dragVisualController.updateDraggedFrame(frameInHost)
	}

	func beginSettle(
		to targetFrame: CGRect,
		commit: Bool,
		backgroundColor: NSColor,
		appearance: ReorderDragAppearance,
		animated: Bool,
		durationOverride: TimeInterval? = nil
	) {
		dragVisualController.beginSettle(
			to: targetFrame,
			commit: commit,
			backgroundColor: backgroundColor,
			appearance: appearance,
			animated: animated,
			durationOverride: durationOverride
		)
	}

	func tearDown() {
		dragVisualController.tearDown()
	}

	func stopAnimationAndFreeze() {
		dragVisualController.freezeToPresentation()
	}

	func overrideDragShape(to size: CGSize, cornerRadius: CGFloat, targetSnapshot: NSImage?, animated: Bool) {
		dragVisualController.overrideDragShape(to: size, cornerRadius: cornerRadius, targetSnapshot: targetSnapshot, animated: animated)
	}

	func clearDragShapeOverride(animated: Bool, sourceCursorX: CGFloat? = nil, targetCenterX: CGFloat? = nil) {
		dragVisualController.clearDragShapeOverride(animated: animated, sourceCursorX: sourceCursorX, targetCenterX: targetCenterX)
	}
}
