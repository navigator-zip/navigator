import AppKit

@MainActor
final class ReorderableListDragController<ID: Hashable> {
	private final class DragSettlementController {
		private var workItem: DispatchWorkItem?

		func schedule(
			after delay: TimeInterval,
			_ action: @escaping @MainActor () -> Void
		) {
			cancel()
			let workItem = DispatchWorkItem {
				Task { @MainActor in action() }
			}
			self.workItem = workItem
			DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
		}

		func cancel() {
			workItem?.cancel()
			workItem = nil
		}
	}

	private let dragStartThreshold: CGFloat
	private let settlementController = DragSettlementController()
	private(set) var state: InteractionState<ID> = .idle

	init(dragStartThreshold: CGFloat) {
		self.dragStartThreshold = dragStartThreshold
	}

	var activeSession: DragSession<ID>? {
		guard case let .dragging(session) = state else { return nil }
		return session
	}

	var activeItemID: ID? {
		switch state {
		case let .pressArmed(itemID, _):
			return itemID
		case let .dragging(session):
			return session.itemID
		case let .settling(itemID, _):
			return itemID
		case .idle:
			return nil
		}
	}

	var settlingItemID: ID? {
		guard case let .settling(itemID, _) = state else { return nil }
		return itemID
	}

	var isDragging: Bool {
		activeSession != nil
	}

	var isSettling: Bool {
		guard case .settling = state else { return false }
		return true
	}

	var hasPendingPress: Bool {
		guard case .pressArmed = state else { return false }
		return true
	}

	var armedLocationInView: CGPoint? {
		guard case let .pressArmed(_, locationInView) = state else { return nil }
		return locationInView
	}

	var blocksModelUpdates: Bool {
		switch state {
		case .idle:
			return false
		case .pressArmed:
			return false
		case .dragging, .settling:
			return true
		}
	}

	func armPress(itemID: ID, locationInView: CGPoint) {
		settlementController.cancel()
		state = .pressArmed(itemID: itemID, locationInView: locationInView)
	}

	func clearPendingPress() {
		guard case .pressArmed = state else { return }
		state = .idle
	}

	func updateSession(_ session: DragSession<ID>) {
		state = .dragging(session)
	}

	func beginDragIfArmed(
		at locationInView: CGPoint,
		start: (ID, CGPoint) -> DragSession<ID>?
	) -> Bool {
		guard case let .pressArmed(itemID, armedLocation) = state else { return false }
		let distance = hypot(
			locationInView.x - armedLocation.x,
			locationInView.y - armedLocation.y
		)
		guard distance > dragStartThreshold else { return false }
		guard let session = start(itemID, armedLocation) else {
			state = .idle
			return false
		}
		state = .dragging(session)
		return true
	}

	func activateArmedPress(
		start: (ID, CGPoint) -> DragSession<ID>?
	) -> Bool {
		guard case let .pressArmed(itemID, armedLocation) = state else { return false }
		guard let session = start(itemID, armedLocation) else {
			state = .idle
			return false
		}
		state = .dragging(session)
		return true
	}

	struct FinishedDrag {
		let session: DragSession<ID>
		let cancelled: Bool
		let settlesImmediately: Bool
	}

	func finishDrag(
		cancelled: Bool,
		resetImmediately: Bool = false
	) -> FinishedDrag? {
		guard case let .dragging(session) = state else {
			clearPendingPress()
			return nil
		}

		let itemID = session.itemID
		state = .settling(itemID: itemID, cancelled: cancelled)
		return FinishedDrag(
			session: session,
			cancelled: cancelled,
			settlesImmediately: resetImmediately
		)
	}

	func flushSettlement(
		onSettled: @escaping @MainActor (ID, Bool) -> Void
	) {
		guard case let .settling(itemID, cancelled) = state else { return }
		settlementController.cancel()
		state = .idle
		onSettled(itemID, cancelled)
	}

	func scheduleSettlement(
		after delay: TimeInterval = ReorderableListStyle.animationDuration,
		onSettled: @escaping @MainActor (ID, Bool) -> Void
	) {
		guard case let .settling(itemID, cancelled) = state else { return }
		settlementController.schedule(after: delay) {
			self.state = .idle
			onSettled(itemID, cancelled)
		}
	}

	func cancelSettlement() {
		guard case .settling = state else { return }
		settlementController.cancel()
		state = .idle
	}
}
