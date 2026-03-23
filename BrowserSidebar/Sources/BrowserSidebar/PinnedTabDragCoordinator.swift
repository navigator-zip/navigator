import AppKit
import ReorderableList

@MainActor
final class PinnedTabDragCoordinator {

	private enum State {
		case idle
		case armed(index: Int, locationInWindow: CGPoint)
		case dragging(sourceIndex: Int, proposedIndex: Int)
		case settling
	}

	private enum Style {
		static let activationSlop: CGFloat = 4
		static let frameDriverInterval: TimeInterval = 1 / 120
	}

	// MARK: - Dependencies

	private weak var pinnedTabsView: BrowserSidebarPinnedTabsView?
	private weak var dragOverlayHostView: NSView?
	private weak var sidebarView: BrowserSidebarView?

	// MARK: - Owned Resources

	private var visualController: ReorderableListDragVisualController?
	nonisolated(unsafe) private var mouseDownEventMonitor: Any?
	nonisolated(unsafe) private var dragMouseEventMonitor: Any?
	nonisolated(unsafe) private var escapeKeyMonitor: Any?
	nonisolated(unsafe) private var dragFrameTimer: Timer?
	private var lastPointerLocationInWindow: CGPoint?

	// MARK: - State

	private var state: State = .idle
	private var isInListArea = false
	private var tileOriginFrameInHost: CGRect?
	private var draggedTabID: BrowserTabID?
	private var cachedTileSnapshot: NSImage?
	private var cachedRowSnapshot: NSImage?
	private var currentListInsertionIndex: Int?

	// MARK: - Callbacks

	var onMove: ((IndexSet, Int) -> Void)?
	var onReorderInteractionDidFinish: (() -> Void)?
	var onTogglePin: ((BrowserTabID, Int?) -> Void)?
	var onShowListPlaceholder: ((Int, CGFloat) -> Void)?
	var onUpdateListPlaceholder: ((Int, CGFloat) -> Void)?
	var onHideListPlaceholder: ((Bool) -> Void)?
	var listInsertionIndexForCursor: ((CGPoint) -> Int)?
	var listRowFrameAtInsertionIndex: ((Int) -> CGRect?)?
	var onPinnedTabCountChange: ((Int, Bool) -> Void)?

	// MARK: - Public Interface

	var blocksModelUpdates: Bool {
		switch state {
		case .dragging, .settling:
			return true
		case .idle, .armed:
			return false
		}
	}

	var hasTransientReorderState: Bool {
		switch state {
		case .dragging, .settling, .armed:
			return pinnedTabsView?.activeDraggedTabID != nil
		case .idle:
			return false
		}
	}

	init(
		pinnedTabsView: BrowserSidebarPinnedTabsView,
		dragOverlayHostView: NSView,
		sidebarView: BrowserSidebarView
	) {
		self.pinnedTabsView = pinnedTabsView
		self.dragOverlayHostView = dragOverlayHostView
		self.sidebarView = sidebarView
	}

	func install() {
		mouseDownEventMonitor = NSEvent.addLocalMonitorForEvents(
			matching: [.leftMouseDown]
		) { [weak self] event in
			self?.handleMouseDown(event)
			return event
		}
	}

	func tearDown() {
		stopFrameTimer()
		removeDragEventMonitors()
		removeEscapeMonitor()
		if let monitor = mouseDownEventMonitor {
			NSEvent.removeMonitor(monitor)
			mouseDownEventMonitor = nil
		}
		visualController?.tearDown()
		visualController = nil
		state = .idle
	}

	deinit {
		if let monitor = mouseDownEventMonitor {
			NSEvent.removeMonitor(monitor)
		}
		if let monitor = dragMouseEventMonitor {
			NSEvent.removeMonitor(monitor)
		}
		if let monitor = escapeKeyMonitor {
			NSEvent.removeMonitor(monitor)
		}
		dragFrameTimer?.invalidate()
	}

	// MARK: - Testing Helpers

	func beginDragForTesting(sourceIndex: Int) {
		guard let pinnedTabsView else { return }
		pinnedTabsView.beginDragVisualState(at: sourceIndex)
		state = .dragging(sourceIndex: sourceIndex, proposedIndex: sourceIndex)
	}

	func moveDraggedTabForTesting(to destinationIndex: Int) {
		guard let pinnedTabsView else { return }
		pinnedTabsView.updateDragPlaceholderPosition(to: destinationIndex)
		pinnedTabsView.performReorder(from: resolvedSourceIndex(), to: destinationIndex)
	}

	func endDragForTesting(cancelled: Bool) {
		guard let pinnedTabsView else { return }
		pinnedTabsView.clearTileDisplacements()
		state = .idle
		pinnedTabsView.finishDragVisualState()
		onReorderInteractionDidFinish?()
	}

	// MARK: - Mouse Handling

	private func handleMouseDown(_ event: NSEvent) {
		guard let pinnedTabsView,
		      let window = pinnedTabsView.window,
		      event.window === window
		else { return }

		let locationInCollectionView = pinnedTabsView.convertToCollectionView(event.locationInWindow)
		guard let index = pinnedTabsView.tileIndexAtPoint(locationInCollectionView) else { return }

		state = .armed(index: index, locationInWindow: event.locationInWindow)
		installDragEventMonitors()
	}

	private func installDragEventMonitors() {
		dragMouseEventMonitor = NSEvent.addLocalMonitorForEvents(
			matching: [.leftMouseDragged, .leftMouseUp]
		) { [weak self] event in
			guard let self else { return event }
			switch event.type {
			case .leftMouseDragged:
				self.handleMouseDragged(event)
			case .leftMouseUp:
				self.handleMouseUp(event)
			default:
				break
			}
			return event
		}
	}

	private func removeDragEventMonitors() {
		if let monitor = dragMouseEventMonitor {
			NSEvent.removeMonitor(monitor)
			dragMouseEventMonitor = nil
		}
	}

	private func handleMouseDragged(_ event: NSEvent) {
		switch state {
		case let .armed(index, armedLocation):
			let distance = hypot(
				event.locationInWindow.x - armedLocation.x,
				event.locationInWindow.y - armedLocation.y
			)
			guard distance > Style.activationSlop else { return }
			transitionToDragging(sourceIndex: index)
			lastPointerLocationInWindow = event.locationInWindow

		case .dragging:
			lastPointerLocationInWindow = event.locationInWindow

		case .idle, .settling:
			break
		}
	}

	private func handleMouseUp(_ event: NSEvent) {
		switch state {
		case let .armed(index, _):
			removeDragEventMonitors()
			state = .idle
			pinnedTabsView?.selectTile(at: index)

		case let .dragging(sourceIndex, proposedIndex):
			stopFrameTimer()
			removeDragEventMonitors()
			removeEscapeMonitor()

			if isInListArea {
				// Don't hide yet — overlay covers the list during settle.
				// Will be hidden in settle completion alongside data update.
				// Keep currentListInsertionIndex alive so beginSettle can read it
				// for the settle target frame.
			}

			// Capture settle target frame before clearing displacements/reordering.
			var settleTargetInHost: CGRect?
			if !isInListArea, let pinnedTabsView, let dragOverlayHostView,
			   let tileFrame = pinnedTabsView.tileFrame(at: proposedIndex) {
				settleTargetInHost = dragOverlayHostView.convert(tileFrame, from: pinnedTabsView)
			}

			pinnedTabsView?.clearTileDisplacements()

			if !isInListArea {
				// Dropped within pinned area — apply reorder if destination changed.
				let finalDestination = proposedIndex
				if finalDestination != sourceIndex {
					pinnedTabsView?.performReorder(from: sourceIndex, to: finalDestination)
				}
			}
			// If isInListArea, skip reorder — beginSettle will trigger unpin instead.

			state = .settling
			beginSettle(sourceIndex: sourceIndex, settleTargetInHost: settleTargetInHost)

		case .idle, .settling:
			removeDragEventMonitors()
		}
	}

	// MARK: - Drag Lifecycle

	private func transitionToDragging(sourceIndex: Int) {
		guard let pinnedTabsView, let dragOverlayHostView, let sidebarView else { return }

		// Capture snapshots BEFORE hiding the tile so they contain visible content.
		let tabID = pinnedTabsView.tabID(at: sourceIndex)
		draggedTabID = tabID
		let tileSnapshot = tabID.flatMap { pinnedTabsView.makeTileSnapshot(for: $0) }
			?? NSImage(size: NSSize(width: 1, height: 1))
		cachedTileSnapshot = tileSnapshot
		cachedRowSnapshot = tabID.flatMap { sidebarView.makeRowSnapshot(for: $0) }

		pinnedTabsView.beginDragVisualState(at: sourceIndex)
		state = .dragging(sourceIndex: sourceIndex, proposedIndex: sourceIndex)
		isInListArea = false

		guard let tileFrame = pinnedTabsView.tileFrame(at: sourceIndex) else { return }
		let tileFrameInHost = dragOverlayHostView.convert(tileFrame, from: pinnedTabsView)
		tileOriginFrameInHost = tileFrameInHost

		let tileSize = CGSize(
			width: BrowserSidebarPinnedTabsView.tileDimension,
			height: BrowserSidebarPinnedTabsView.tileDimension
		)

		let controller = ReorderableListDragVisualController()
		controller.attach(to: dragOverlayHostView)
		visualController = controller

		let listDimensions = sidebarView.listAreaDimensions()

		controller.beginLift(
			snapshotImage: tileSnapshot,
			frame: tileFrameInHost,
			backgroundColor: sidebarView.sidebarBackgroundColor,
			appearance: ReorderDragAppearance()
		)

		controller.overrideNaturalDragFrameSize(
			CGSize(width: listDimensions.width, height: listDimensions.height)
		)

		controller.overrideDragShape(
			to: tileSize,
			cornerRadius: BrowserSidebarPinnedTabsView.tileCornerRadius,
			targetSnapshot: nil as NSImage?,
			animated: false
		)

		startFrameTimer()
		installEscapeMonitor()
	}

	private func beginSettle(sourceIndex: Int, settleTargetInHost: CGRect? = nil) {
		guard let controller = visualController,
		      let sidebarView
		else {
			finishDrag()
			return
		}

		let backgroundColor = sidebarView.sidebarBackgroundColor

		if !isInListArea, let tabCount = pinnedTabsView?.tabCount {
			onPinnedTabCountChange?(tabCount, true)
		}

		if isInListArea {
			let listDimensions = sidebarView.listAreaDimensions()
			let listFrameInHost = sidebarView.listAreaFrameInHost()
			let settleFrame: CGRect
			if let insertionIndex = currentListInsertionIndex,
			   let rowFrame = listRowFrameAtInsertionIndex?(insertionIndex) {
				settleFrame = rowFrame
			} else {
				settleFrame = CGRect(
					x: listFrameInHost.origin.x,
					y: listFrameInHost.maxY - listDimensions.height,
					width: listFrameInHost.width,
					height: listDimensions.height
				)
			}
			controller.beginSettle(
				to: settleFrame,
				commit: true,
				backgroundColor: backgroundColor,
				appearance: ReorderDragAppearance(),
				animated: true,
				durationOverride: ReorderableListStyle.animationDuration
			)
			let duration = controller.settleDuration ?? 0.25
			let tabID = draggedTabID
			let insertionIndex = currentListInsertionIndex
			DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
				controller.freezeToPresentation()
				self?.finishDrag()
				controller.tearDown()
				self?.visualController = nil
				// finishDrag() flushes queued/deferred updates with stale data,
				// which resets the separator to its pre-drag position. Re-apply
				// the correct height (N-1) without animation so the separator
				// stays where it already animated to during the drag.
				if let tabCount = self?.pinnedTabsView?.tabCount {
					self?.onPinnedTabCountChange?(tabCount - 1, false)
				}
				// Clear displacement non-animated, then update data — both in same
				// run loop iteration so no intermediate visual state is rendered.
				self?.onHideListPlaceholder?(false)
				if let tabID {
					self?.onTogglePin?(tabID, insertionIndex)
				}
			}
		} else if let targetFrame = settleTargetInHost ?? tileOriginFrameInHost {
			let tileSize = CGSize(
				width: BrowserSidebarPinnedTabsView.tileDimension,
				height: BrowserSidebarPinnedTabsView.tileDimension
			)
			controller.beginSettle(
				to: targetFrame,
				commit: false,
				backgroundColor: backgroundColor,
				appearance: ReorderDragAppearance(),
				animated: true,
				durationOverride: ReorderableListStyle.animationDuration
			)
			// Re-apply tile shape override — beginSettle clears activeShapeOverride,
			// which causes the chrome geometry to fall back to row-style insets.
			controller.overrideDragShape(
				to: tileSize,
				cornerRadius: BrowserSidebarPinnedTabsView.tileCornerRadius,
				targetSnapshot: nil as NSImage?,
				animated: false
			)
			let duration = controller.settleDuration ?? 0.25
			DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
				// Match unpinned settle completion order:
				// freeze → reveal live tile → tear down overlay (prevents flash).
				controller.freezeToPresentation()
				self?.pinnedTabsView?.revealDraggedTile()
				controller.tearDown()
				self?.visualController = nil
				self?.finishDrag()
			}
		} else {
			controller.tearDown()
			visualController = nil
			finishDrag()
		}
	}

	private func finishDrag() {
		pinnedTabsView?.finishDragVisualState()
		state = .idle
		isInListArea = false
		tileOriginFrameInHost = nil
		draggedTabID = nil
		cachedTileSnapshot = nil
		cachedRowSnapshot = nil
		currentListInsertionIndex = nil
		pinnedTabsView?.applyQueuedUpdateIfNeeded()
		onReorderInteractionDidFinish?()
	}

	// MARK: - Frame Driver

	private func startFrameTimer() {
		dragFrameTimer = Timer(
			timeInterval: Style.frameDriverInterval,
			target: self,
			selector: #selector(handleFrameTick),
			userInfo: nil,
			repeats: true
		)
		if let timer = dragFrameTimer {
			RunLoop.main.add(timer, forMode: .common)
		}
	}

	private func stopFrameTimer() {
		dragFrameTimer?.invalidate()
		dragFrameTimer = nil
	}

	@objc
	private func handleFrameTick() {
		guard case let .dragging(sourceIndex, previousProposedIndex) = state,
		      let pointerInWindow = lastPointerLocationInWindow,
		      let pinnedTabsView, let dragOverlayHostView, let sidebarView
		else { return }

		// 1. Morph threshold — detect before displacement so we know which area we're in.
		let cursorInHost = dragOverlayHostView.convert(pointerInWindow, from: nil)
		let cursorInSelf = sidebarView.convert(pointerInWindow, from: nil)
		let pinnedTabsFrame = sidebarView.pinnedTabsViewFrameInSelf()
		let isNowInListArea = cursorInSelf.y < pinnedTabsFrame.origin.y

		let thresholdCrossed = isNowInListArea != isInListArea
		if thresholdCrossed {
			isInListArea = isNowInListArea

			let tileSize = CGSize(
				width: BrowserSidebarPinnedTabsView.tileDimension,
				height: BrowserSidebarPinnedTabsView.tileDimension
			)

			if isNowInListArea {
				// Crossed into list area — clear pinned tile displacements and morph tile→row.
				pinnedTabsView.clearTileDisplacements()
				pinnedTabsView.hideDragPlaceholder()
				onPinnedTabCountChange?(pinnedTabsView.tabCount - 1, true)
				let listCenterX = sidebarView.listAreaCenterXInHost()
				visualController?.clearDragShapeOverride(
					animated: true,
					targetSnapshot: cachedRowSnapshot,
					sourceCursorX: cursorInHost.x,
					targetCenterX: listCenterX
				)
				// Show list placeholder at computed insertion index.
				let listDimensions = sidebarView.listAreaDimensions()
				if let insertionIndex = listInsertionIndexForCursor?(pointerInWindow) {
					currentListInsertionIndex = insertionIndex
					onShowListPlaceholder?(insertionIndex, listDimensions.height)
				}
			} else {
				// Crossed back to pinned area — hide list placeholder and restore grid state.
				onHideListPlaceholder?(true)
				currentListInsertionIndex = nil
				onPinnedTabCountChange?(pinnedTabsView.tabCount, true)

				let pointerInCollectionView = pinnedTabsView.convertToCollectionView(pointerInWindow)
				let colCount = pinnedTabsView.currentColumnCount()
				let recomputedIndex = PinnedTabGridGeometry.destinationIndex(
					cursorInGrid: pointerInCollectionView,
					sourceIndex: sourceIndex,
					columnCount: colCount,
					tileSize: BrowserSidebarPinnedTabsView.tileDimension,
					interitemSpacing: BrowserSidebarPinnedTabsView.gridInteritemSpacing,
					lineSpacing: BrowserSidebarPinnedTabsView.gridLineSpacing,
					itemCount: pinnedTabsView.tabCount
				)
				state = .dragging(sourceIndex: sourceIndex, proposedIndex: recomputedIndex)
				pinnedTabsView.applyTileDisplacements(
					source: sourceIndex,
					insertion: recomputedIndex,
					animated: true
				)
				pinnedTabsView.updateDragPlaceholderPosition(to: recomputedIndex)
				visualController?.overrideDragShape(
					to: tileSize,
					cornerRadius: BrowserSidebarPinnedTabsView.tileCornerRadius,
					targetSnapshot: nil as NSImage?,
					animated: true
				)
			}
		}

		// 2a. Per-frame list insertion tracking — update placeholder while in list area.
		if isInListArea {
			let listDimensions = sidebarView.listAreaDimensions()
			if let newIndex = listInsertionIndexForCursor?(pointerInWindow),
			   newIndex != currentListInsertionIndex {
				onUpdateListPlaceholder?(newIndex, listDimensions.height)
				currentListInsertionIndex = newIndex
			}
		}

		// 2b. Tile displacement — only update while cursor is in the pinned area.
		if !isInListArea {
			let pointerInCollectionView = pinnedTabsView.convertToCollectionView(pointerInWindow)
			let colCount = pinnedTabsView.currentColumnCount()

			let newProposedIndex = PinnedTabGridGeometry.destinationIndex(
				cursorInGrid: pointerInCollectionView,
				sourceIndex: sourceIndex,
				columnCount: colCount,
				tileSize: BrowserSidebarPinnedTabsView.tileDimension,
				interitemSpacing: BrowserSidebarPinnedTabsView.gridInteritemSpacing,
				lineSpacing: BrowserSidebarPinnedTabsView.gridLineSpacing,
				itemCount: pinnedTabsView.tabCount
			)

			if newProposedIndex != previousProposedIndex {
				state = .dragging(sourceIndex: sourceIndex, proposedIndex: newProposedIndex)
				pinnedTabsView.applyTileDisplacements(
					source: sourceIndex,
					insertion: newProposedIndex,
					animated: true
				)
				pinnedTabsView.updateDragPlaceholderPosition(to: newProposedIndex)
			}
		}

		// 3. Overlay position — always follows cursor.
		let listDimensions = sidebarView.listAreaDimensions()
		let overlayFrame = CGRect(
			x: cursorInHost.x - listDimensions.width / 2,
			y: cursorInHost.y - listDimensions.height / 2,
			width: listDimensions.width,
			height: listDimensions.height
		)
		visualController?.updateDraggedFrame(overlayFrame)
	}

	// MARK: - Escape Key Monitoring

	private func installEscapeMonitor() {
		escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(
			matching: [.keyDown]
		) { [weak self] event in
			guard let self else { return event }
			let relevantModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
			guard relevantModifiers.isEmpty, event.keyCode == 53 else { return event }
			self.cancelDrag()
			return nil
		}
	}

	private func removeEscapeMonitor() {
		if let monitor = escapeKeyMonitor {
			NSEvent.removeMonitor(monitor)
			escapeKeyMonitor = nil
		}
	}

	private func cancelDrag() {
		guard case let .dragging(sourceIndex, _) = state else { return }

		stopFrameTimer()
		removeDragEventMonitors()
		removeEscapeMonitor()

		if isInListArea {
			onHideListPlaceholder?(true)
			currentListInsertionIndex = nil
		}

		pinnedTabsView?.clearTileDisplacements()
		if let tabCount = pinnedTabsView?.tabCount {
			onPinnedTabCountChange?(tabCount, true)
		}

		let settleTarget = tileOriginFrameInHost
		isInListArea = false
		state = .settling
		beginSettle(sourceIndex: sourceIndex, settleTargetInHost: settleTarget)
	}

	// MARK: - Helpers

	private func resolvedSourceIndex() -> Int {
		guard let pinnedTabsView,
		      let activeDraggedTabID = pinnedTabsView.activeDraggedTabID
		else { return 0 }
		return pinnedTabsView.indexForTabID(activeDraggedTabID) ?? 0
	}
}
