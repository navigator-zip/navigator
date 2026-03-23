import AppKit

enum DragPhase<ID: Hashable> {
	case idle
	case armed(itemID: ID, mouseDownLocationInHost: CGPoint)
	case dragging(session: DragSession<ID>)
	case settling(itemID: ID, cancelled: Bool)
}

struct ReorderableListDragRuntimeTickOutput<ID: Hashable> {
	let session: DragSession<ID>
	let pointerLocationInTable: CGPoint
	let pointerLocationInVisibleRect: CGPoint
	let draggedFrameInTable: CGRect
	let draggedFrameInHost: CGRect
	let restingFrameInHost: CGRect
	let destinationIndex: Int
	let didAutoscroll: Bool
	let didDestinationChange: Bool
	let usedFixedHeightIndexing: Bool
}

@MainActor
final class ReorderableListDragRuntime<ID: Hashable> {
	struct Context {
		let fallbackWindowPointer: () -> CGPoint?
		let convertWindowPointToHost: (CGPoint) -> CGPoint
		let convertHostPointToTable: (CGPoint) -> CGPoint
		let convertTableFrameToHost: (CGRect) -> CGRect
		let sourceRowFrame: (DragSession<ID>) -> CGRect?
		let rowCount: () -> Int
		let rowSpacing: () -> CGFloat
		let contentInsets: () -> NSEdgeInsets
		let visibleRect: () -> CGRect
		let attemptScrollBy: (CGFloat) -> Bool
		let updateSession: (DragSession<ID>) -> Void
		let activeSession: () -> DragSession<ID>?
		let onTick: (ReorderableListDragRuntimeTickOutput<ID>) -> Void
		let onFrameTiming: (TimeInterval) -> Void
	}

	private let context: Context
	private let geometryEngine: ReorderableListGeometryEngine
	private let frameDriver: ReorderFrameDriver
	private var autoscrollDriver: ReorderAutoscrollDriver
	private let now: () -> TimeInterval

	private(set) var phase: DragPhase<ID> = .idle
	private(set) var pointerLocationInWindow: CGPoint?
	private(set) var isAutoscrollActive = false
	private var prefersLiveWindowPointer = false

	var usesLiveWindowPointerForActiveDrag: Bool {
		prefersLiveWindowPointer
	}

	init(
		context: Context,
		autoscrollConfiguration: AutoscrollConfiguration,
		geometryEngine: ReorderableListGeometryEngine = .init(),
		frameDriver: ReorderFrameDriver = ReorderTableFrameDriver(),
		monotonicClock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
	) {
		self.context = context
		self.geometryEngine = geometryEngine
		self.frameDriver = frameDriver
		autoscrollDriver = ReorderAutoscrollDriver(configuration: autoscrollConfiguration)
		now = monotonicClock
	}

	func updatePointerLocation(_ locationInWindow: CGPoint) {
		pointerLocationInWindow = locationInWindow
	}

	func clearPointerLocation() {
		pointerLocationInWindow = nil
	}

	func begin(session: DragSession<ID>) {
		autoscrollDriver.reset()
		phase = .dragging(session: session)
		isAutoscrollActive = false
		prefersLiveWindowPointer = false
		context.updateSession(session)
		requestFrame()
	}

	func settle(cancelled: Bool) {
		guard case let .dragging(session) = phase else { return }
		phase = .settling(itemID: session.itemID, cancelled: cancelled)
		stopFrameUpdates()
		isAutoscrollActive = false
	}

	func resetToIdle() {
		stopFrameUpdates()
		phase = .idle
		pointerLocationInWindow = nil
		autoscrollDriver.reset()
		isAutoscrollActive = false
		prefersLiveWindowPointer = false
	}

	func requestFrame() {
		guard case .dragging = phase else { return }
		frameDriver.start { [weak self] in
			self?.tick()
		}
	}

	func tickForTesting() -> Bool {
		tick()
	}

	func tickForTestingWithoutAutoscroll() -> Bool {
		tick(allowAutoscroll: false)
	}

	func resolvedAutoscrollDelta(pointerYInClipView: CGFloat) -> CGFloat? {
		autoscrollDriver.debugDelta(
			pointerYInClipView: pointerYInClipView,
			visibleHeight: context.visibleRect().height,
			now: now()
		)
	}

	@discardableResult
	private func tick() -> Bool {
		tick(allowAutoscroll: true)
	}

	@discardableResult
	private func tick(allowAutoscroll: Bool) -> Bool {
		let frameStart = now()
		guard case .dragging = phase else {
			resetToIdle()
			return false
		}
		guard var session = context.activeSession() else {
			resetToIdle()
			return false
		}

		let visibleRect = context.visibleRect()
		let storedPointerInWindow = pointerLocationInWindow
		let livePointerInWindow = context.fallbackWindowPointer()
		let pointerInWindow = if prefersLiveWindowPointer {
			livePointerInWindow ?? storedPointerInWindow
		}
		else {
			storedPointerInWindow ?? livePointerInWindow
		}
		guard let pointerInWindow else {
			return false
		}
		pointerLocationInWindow = pointerInWindow

		let pointerInHost = context.convertWindowPointToHost(pointerInWindow)
		var pointerInContent = context.convertHostPointToTable(pointerInHost)
		var pointerInVisible = CGPoint(
			x: pointerInContent.x - visibleRect.minX,
			y: pointerInContent.y - visibleRect.minY
		)

		var didAutoscroll = false
		if let delta = autoscrollDriver.delta(
			pointerYInClipView: pointerInVisible.y,
			visibleHeight: visibleRect.height,
			now: frameStart
		) {
			isAutoscrollActive = true
			prefersLiveWindowPointer = true
			if allowAutoscroll {
				didAutoscroll = context.attemptScrollBy(delta)
				if didAutoscroll == false {
					isAutoscrollActive = false
				}
			}
			if didAutoscroll {
				let refreshedPointerInContent = context.convertHostPointToTable(
					context.convertWindowPointToHost(pointerInWindow)
				)
				pointerInContent = refreshedPointerInContent
				let refreshedVisibleRect = context.visibleRect()
				pointerInVisible = CGPoint(
					x: pointerInContent.x - refreshedVisibleRect.minX,
					y: pointerInContent.y - refreshedVisibleRect.minY
				)
			}
		}
		else {
			isAutoscrollActive = false
			prefersLiveWindowPointer = false
		}

		let destinationIndex = destinationIndex(
			for: session,
			targetCenterY: pointerInContent.y + session.pointerOffsetFromRowCenter.y,
			rowCount: context.rowCount(),
			rowSpacing: context.rowSpacing(),
			contentInsets: context.contentInsets()
		)

		var didDestinationChange = false
		if destinationIndex != session.proposedIndex {
			session.proposedIndex = destinationIndex
			didDestinationChange = true
		}

		let sourceFrame = context.sourceRowFrame(session) ?? .zero
		let draggedFrame = geometryEngine.draggedFrame(
			restingFrame: sourceFrame,
			pointerLocation: pointerInContent,
			pointerOffsetFromRowCenter: session.pointerOffsetFromRowCenter,
			linearLimit: ReorderableListStyle.horizontalDragLinearLimit,
			maxOffset: ReorderableListStyle.maxHorizontalDragOffset
		)

		if didDestinationChange {
			context.updateSession(session)
			phase = .dragging(session: session)
		}

		context.onTick(
			ReorderableListDragRuntimeTickOutput(
				session: session,
				pointerLocationInTable: pointerInContent,
				pointerLocationInVisibleRect: CGPoint(
					x: pointerInVisible.x,
					y: pointerInVisible.y
				),
				draggedFrameInTable: draggedFrame,
				draggedFrameInHost: context.convertTableFrameToHost(draggedFrame),
				restingFrameInHost: context.convertTableFrameToHost(sourceFrame),
				destinationIndex: destinationIndex,
				didAutoscroll: didAutoscroll,
				didDestinationChange: didDestinationChange,
				usedFixedHeightIndexing: session.fixedRowHeight != nil
			)
		)
		context.onFrameTiming(max(now() - frameStart, 0))
		return allowAutoscroll ? didAutoscroll : true
	}

	private func destinationIndex(
		for session: DragSession<ID>,
		targetCenterY: CGFloat,
		rowCount: Int,
		rowSpacing: CGFloat,
		contentInsets: NSEdgeInsets
	) -> Int {
		if let fixedRowHeight = session.fixedRowHeight {
			return geometryEngine.destinationIndex(
				targetCenterY: targetCenterY,
				sourceIndex: session.initialIndex,
				itemCount: rowCount,
				rowHeight: fixedRowHeight,
				rowSpacing: rowSpacing,
				contentInsets: contentInsets
			)
		}

		return geometryEngine.destinationIndex(
			targetCenterY: targetCenterY,
			sourceIndex: session.initialIndex,
			thresholdLayout: session.destinationThresholdLayout
		)
	}

	private func stopFrameUpdates() {
		frameDriver.stop()
	}
}
