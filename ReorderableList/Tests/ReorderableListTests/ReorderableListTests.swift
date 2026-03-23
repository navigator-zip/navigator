import Aesthetics
import AppKit
@testable import ReorderableList
import XCTest

@MainActor
final class ReorderableListTests: XCTestCase {
	struct MoveRecord: Equatable {
		let source: Int
		let destination: Int
	}

	final class FixedHeightView: NSView {
		private let height: CGFloat

		init(height: CGFloat) {
			self.height = height
			super.init(frame: .zero)
		}

		@available(*, unavailable)
		required init?(coder: NSCoder) {
			fatalError("init(coder:) has not been implemented")
		}

		override var intrinsicContentSize: NSSize {
			NSSize(width: 120, height: height)
		}
	}

	final class ControlRowView: NSView {
		let button = NSButton(title: "Close", target: nil, action: nil)

		override init(frame frameRect: NSRect) {
			super.init(frame: frameRect)
			button.translatesAutoresizingMaskIntoConstraints = false
			addSubview(button)
			NSLayoutConstraint.activate([
				button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
				button.centerYAnchor.constraint(equalTo: centerYAnchor),
			])
		}

		@available(*, unavailable)
		required init?(coder: NSCoder) {
			fatalError("init(coder:) has not been implemented")
		}

		override var intrinsicContentSize: NSSize {
			NSSize(width: 120, height: 40)
		}
	}

	final class ForwardingView: NSView {
		var mouseDownCount = 0
		var mouseDraggedCount = 0
		var mouseUpCount = 0
		var keyDownCount = 0
		var cancelOperationCount = 0

		override func mouseDown(with _: NSEvent) {
			mouseDownCount += 1
		}

		override func mouseDragged(with _: NSEvent) {
			mouseDraggedCount += 1
		}

		override func mouseUp(with _: NSEvent) {
			mouseUpCount += 1
		}

		override func keyDown(with _: NSEvent) {
			keyDownCount += 1
		}

		override func cancelOperation(_ sender: Any?) {
			cancelOperationCount += 1
		}
	}

	final class DragObserverRowView: NSView, ReorderableListItemDragObserver {
		private let height: CGFloat
		var beginCount = 0
		var endCancelledStates = [Bool]()

		init(height: CGFloat) {
			self.height = height
			super.init(frame: .zero)
		}

		@available(*, unavailable)
		required init?(coder: NSCoder) {
			fatalError("init(coder:) has not been implemented")
		}

		override var intrinsicContentSize: NSSize {
			NSSize(width: 120, height: height)
		}

		func reorderableListItemDidBeginDrag() {
			beginCount += 1
		}

		func reorderableListItemDidEndDrag(cancelled: Bool) {
			endCancelledStates.append(cancelled)
		}
	}

	final class CellStateObserverRowView: NSView, ReorderableListItemCellStateObserver {
		private let height: CGFloat
		private(set) var receivedStates = [(cellState: ReorderableListCellState, animated: Bool)]()

		init(height: CGFloat) {
			self.height = height
			super.init(frame: .zero)
			wantsLayer = true
		}

		@available(*, unavailable)
		required init?(coder: NSCoder) {
			fatalError("init(coder:) has not been implemented")
		}

		override var intrinsicContentSize: NSSize {
			NSSize(width: 120, height: height)
		}

		func reorderableListItemDidUpdate(
			cellState: ReorderableListCellState,
			animated: Bool
		) {
			receivedStates.append((cellState, animated))
			layer?.borderWidth = cellState.isReordering ? 7 : 0
		}

		func resetReceivedStates() {
			receivedStates.removeAll()
		}
	}

	final class PerformanceTraceRecorder: ReorderableListPerformanceTracing {
		struct Record: Equatable {
			enum Phase: Equatable {
				case begin
				case end
			}

			let phase: Phase
			let event: ReorderableListPerformanceTraceEvent
		}

		private(set) var records = [Record]()

		func beginInterval(_ event: ReorderableListPerformanceTraceEvent) -> ReorderableListPerformanceTraceHandle {
			records.append(Record(phase: .begin, event: event))
			return ReorderableListPerformanceTraceHandle(event: event)
		}

		func endInterval(_ handle: ReorderableListPerformanceTraceHandle) {
			records.append(Record(phase: .end, event: handle.event))
		}
	}

	final class SteppedMonotonicClock {
		private let values: [TimeInterval]
		private var nextIndex = 0

		init(values: [TimeInterval]) {
			self.values = values
		}

		func now() -> TimeInterval {
			guard let fallbackValue = values.last else { return 0 }
			guard nextIndex < values.count else { return fallbackValue }
			let value = values[nextIndex]
			nextIndex += 1
			return value
		}
	}

	final class FrameDriverSpy: ReorderFrameDriver {
		private(set) var startCount = 0
		private(set) var stopCount = 0
		private(set) var callback: (() -> Void)?

		func start(callback: @escaping () -> Void) {
			startCount += 1
			self.callback = callback
		}

		func stop() {
			stopCount += 1
			callback = nil
		}
	}

	final class WidthResponsiveHeightView: NSView {
		override var intrinsicContentSize: NSSize {
			NSSize(width: NSView.noIntrinsicMetric, height: resolvedHeight)
		}

		override var fittingSize: NSSize {
			NSSize(width: frame.width, height: resolvedHeight)
		}

		private var resolvedHeight: CGFloat {
			(superview?.bounds.width ?? bounds.width) < 180 ? 80 : 40
		}
	}

	final class NonHittingView: NSView {
		private let height: CGFloat

		init(height: CGFloat) {
			self.height = height
			super.init(frame: .zero)
		}

		@available(*, unavailable)
		required init?(coder: NSCoder) {
			fatalError("init(coder:) has not been implemented")
		}

		override var intrinsicContentSize: NSSize {
			NSSize(width: 120, height: height)
		}

		override func hitTest(_: NSPoint) -> NSView? {
			nil
		}
	}

	final class HandleProvidingRowView: NSView, ReorderableListHandleProviding {
		private let height: CGFloat
		let reorderHandleRect: NSRect?

		init(height: CGFloat, reorderHandleRect: NSRect?) {
			self.height = height
			self.reorderHandleRect = reorderHandleRect
			super.init(frame: .zero)
		}

		@available(*, unavailable)
		required init?(coder: NSCoder) {
			fatalError("init(coder:) has not been implemented")
		}

		override var intrinsicContentSize: NSSize {
			NSSize(width: 120, height: height)
		}
	}

	final class NestedHitRowView: NSView {
		private let height: CGFloat
		let childView = NSView(frame: CGRect(x: 16, y: 8, width: 44, height: 24))

		init(height: CGFloat) {
			self.height = height
			super.init(frame: .zero)
			childView.wantsLayer = true
			addSubview(childView)
		}

		@available(*, unavailable)
		required init?(coder: NSCoder) {
			fatalError("init(coder:) has not been implemented")
		}

		override var intrinsicContentSize: NSSize {
			NSSize(width: 120, height: height)
		}
	}

	final class ResponderSpy: NSResponder {
		var cancelOperationCount = 0

		@objc
		override func cancelOperation(_ sender: Any?) {
			cancelOperationCount += 1
		}
	}

	final class MouseTrackingWindow: NSWindow {
		var trackedMouseLocation = NSPoint.zero

		override var mouseLocationOutsideOfEventStream: NSPoint {
			trackedMouseLocation
		}
	}

	func testGeometryContentHeightIncludesInsets() {
		let height = ReorderableListGeometry.contentHeight(
			itemHeights: [10, 20, 30],
			contentInsets: NSEdgeInsets(top: 5, left: 0, bottom: 7, right: 0)
		)

		XCTAssertEqual(height, 72)
	}

	func testGeometryFramesStacksRowsVertically() {
		let frames = ReorderableListGeometry.frames(
			for: [40, 50],
			width: 200,
			contentInsets: NSEdgeInsets(top: 8, left: 16, bottom: 0, right: 16)
		)

		XCTAssertEqual(frames[0], CGRect(x: 16, y: 8, width: 168, height: 40))
		XCTAssertEqual(frames[1], CGRect(x: 16, y: 48, width: 168, height: 50))
	}

	func testGeometryFramesIncludeConfiguredRowSpacing() {
		let frames = ReorderableListGeometry.frames(
			for: [40, 50],
			width: 200,
			rowSpacing: 5,
			contentInsets: NSEdgeInsets(top: 8, left: 16, bottom: 0, right: 16)
		)

		XCTAssertEqual(frames[0], CGRect(x: 16, y: 8, width: 168, height: 40))
		XCTAssertEqual(frames[1], CGRect(x: 16, y: 53, width: 168, height: 50))
	}

	func testGeometryContentHeightIncludesConfiguredRowSpacing() {
		let height = ReorderableListGeometry.contentHeight(
			itemHeights: [10, 20, 30],
			rowSpacing: 5,
			contentInsets: NSEdgeInsets(top: 5, left: 0, bottom: 7, right: 0)
		)

		XCTAssertEqual(height, 82)
	}

	func testGeometryReorderedIndicesMatchesMoveDownwardSemantics() {
		let reordered = ReorderableListGeometry.reorderedIndices(
			count: 4,
			moving: 1,
			to: 3
		)

		XCTAssertEqual(reordered, [0, 2, 1, 3])
	}

	func testGeometryReorderedIndicesMatchesMoveUpwardSemantics() {
		let reordered = ReorderableListGeometry.reorderedIndices(
			count: 4,
			moving: 3,
			to: 1
		)

		XCTAssertEqual(reordered, [0, 3, 1, 2])
	}

	func testGeometryReorderedIndicesReturnsEmptyForEmptyList() {
		let reordered = ReorderableListGeometry.reorderedIndices(
			count: 0,
			moving: 0,
			to: 0
		)

		XCTAssertEqual(reordered, [])
	}

	func testGeometryReorderedIndicesReturnsIdentityForInvalidSourceIndex() {
		let reordered = ReorderableListGeometry.reorderedIndices(
			count: 3,
			moving: 9,
			to: 1
		)

		XCTAssertEqual(reordered, [0, 1, 2])
	}

	func testGeometryDestinationChoosesClosestPreviewSlot() {
		let destination = ReorderableListGeometry.destinationIndex(
			for: 105,
			sourceIndex: 0,
			itemHeights: [40, 40, 40],
			width: 200,
			contentInsets: NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0)
		)

		XCTAssertEqual(destination, 2)
	}

	func testGeometryDestinationReturnsZeroForEmptyHeights() {
		let destination = ReorderableListGeometry.destinationIndex(
			for: 50,
			sourceIndex: 0,
			itemHeights: [],
			width: 200,
			contentInsets: NSEdgeInsetsZero
		)

		XCTAssertEqual(destination, 0)
	}

	func testGeometryDestinationPreviewCentersMatchSwiftMoveSemantics() {
		let previewCenters = ReorderableListGeometry.destinationPreviewCenters(
			sourceIndex: 1,
			itemHeights: [40, 60, 50],
			rowSpacing: 5,
			contentInsets: NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0)
		)

		XCTAssertEqual(previewCenters, [38, 83, 83, 138])
	}

	func testGeometryDestinationPreviewCentersReturnsEmptyForInvalidSourceIndex() {
		XCTAssertEqual(
			ReorderableListGeometry.destinationPreviewCenters(
				sourceIndex: 3,
				itemHeights: [40, 60, 50],
				rowSpacing: 5,
				contentInsets: NSEdgeInsetsZero
			),
			[]
		)
	}

	func testGeometryDestinationThresholdLayoutUsesLineBiasedActivationPoints() throws {
		let thresholdLayout = try XCTUnwrap(
			ReorderableListGeometry.destinationThresholdLayout(
				sourceIndex: 1,
				itemHeights: [40, 60, 50],
				rowSpacing: 5,
				contentInsets: NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0)
			)
		)

		XCTAssertEqual(thresholdLayout.thresholds, [12, 83, 163])
		XCTAssertEqual(thresholdLayout.sourceUpperThresholdY, 59)
		XCTAssertEqual(thresholdLayout.sourceLowerThresholdY, 107)
	}

	func testGeometryDestinationIndexFallsBackWhenThresholdLayoutIsInvalid() {
		XCTAssertEqual(
			ReorderableListGeometry.destinationIndex(
				for: 60,
				thresholdLayout: ReorderableListDestinationThresholdLayout(
					sourceIndex: 2,
					thresholds: [],
					sourceUpperThresholdY: 0,
					sourceLowerThresholdY: 0
				),
				fallbackDestination: 2
			),
			2
		)
	}

	func testGeometryFixedHeightDestinationIndexWaitsForLineBiasedThreshold() {
		let destination = ReorderableListGeometry.fixedHeightDestinationIndex(
			for: 80,
			sourceIndex: 0,
			rowHeight: 40,
			itemCount: 3,
			rowSpacing: 5,
			contentInsets: NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0)
		)

		XCTAssertEqual(destination, 0)
	}

	func testGeometryFixedHeightDestinationIndexMovesAfterCrossingLineBiasedThreshold() {
		let destination = ReorderableListGeometry.fixedHeightDestinationIndex(
			for: 90,
			sourceIndex: 0,
			rowHeight: 40,
			itemCount: 3,
			rowSpacing: 5,
			contentInsets: NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0)
		)

		XCTAssertEqual(destination, 2)
	}

	func testGeometryFixedHeightDestinationIndexReturnsZeroForInvalidInput() {
		XCTAssertEqual(
			ReorderableListGeometry.fixedHeightDestinationIndex(
				for: 40,
				sourceIndex: 0,
				rowHeight: 0,
				itemCount: 3,
				contentInsets: NSEdgeInsetsZero
			),
			0
		)
	}

	func testGeometryFixedHeightDestinationIndexMovesOneRowDownAfterBiasedThreshold() {
		XCTAssertEqual(
			ReorderableListGeometry.fixedHeightDestinationIndex(
				for: 94,
				sourceIndex: 0,
				rowHeight: 40,
				itemCount: 4,
				rowSpacing: 4,
				contentInsets: NSEdgeInsetsZero
			),
			2
		)
	}

	func testGeometryAffectedRangeReturnsRowsCrossedWhenMovingDownward() {
		let range = ReorderableListGeometry.affectedRange(
			sourceIndex: 0,
			insertionIndex: 3
		)

		XCTAssertEqual(range, 1...2)
	}

	func testGeometryAffectedRangeReturnsRowsCrossedWhenMovingUpward() {
		let range = ReorderableListGeometry.affectedRange(
			sourceIndex: 3,
			insertionIndex: 1
		)

		XCTAssertEqual(range, 1...2)
	}

	func testGeometryAffectedRangeReturnsNilWhenInsertionDoesNotCrossRows() {
		XCTAssertNil(
			ReorderableListGeometry.affectedRange(
				sourceIndex: 1,
				insertionIndex: 1
			)
		)
		XCTAssertNil(
			ReorderableListGeometry.affectedRange(
				sourceIndex: 1,
				insertionIndex: 2
			)
		)
	}

	func testGeometryDisplacementOffsetShiftsRowsBetweenSourceAndDestination() {
		XCTAssertEqual(
			ReorderableListGeometry.displacementOffsetForRow(
				rowIndex: 1,
				sourceIndex: 0,
				insertionIndex: 3,
				rowHeight: 40
			),
			-40
		)
		XCTAssertEqual(
			ReorderableListGeometry.displacementOffsetForRow(
				rowIndex: 2,
				sourceIndex: 3,
				insertionIndex: 1,
				rowHeight: 40
			),
			40
		)
		XCTAssertEqual(
			ReorderableListGeometry.displacementOffsetForRow(
				rowIndex: 3,
				sourceIndex: 3,
				insertionIndex: 1,
				rowHeight: 40
			),
			0
		)
	}

	func testGeometryDisplacementOffsetReturnsZeroForUnaffectedRow() {
		XCTAssertEqual(
			ReorderableListGeometry.displacementOffsetForRow(
				rowIndex: 4,
				sourceIndex: 1,
				insertionIndex: 3,
				rowHeight: 40
			),
			0
		)
	}

	func testGeometryRubberBandedOffsetStaysLinearWithinLimit() {
		let offset = ReorderableListGeometry.rubberBandedOffset(
			for: 12,
			linearLimit: 72,
			maxOffset: 144
		)

		XCTAssertEqual(offset, 12)
	}

	func testGeometryRubberBandedOffsetCapsOverscrollWithinMaximum() {
		let positiveOffset = ReorderableListGeometry.rubberBandedOffset(
			for: 200,
			linearLimit: 72,
			maxOffset: 144
		)
		let negativeOffset = ReorderableListGeometry.rubberBandedOffset(
			for: -200,
			linearLimit: 72,
			maxOffset: 144
		)

		XCTAssertGreaterThan(positiveOffset, 72)
		XCTAssertLessThanOrEqual(positiveOffset, 144)
		XCTAssertLessThan(negativeOffset, -72)
		XCTAssertGreaterThanOrEqual(negativeOffset, -144)
	}

	func testGeometryRubberBandedOffsetReturnsZeroWhenMaximumOffsetIsZero() {
		XCTAssertEqual(
			ReorderableListGeometry.rubberBandedOffset(
				for: 80,
				linearLimit: 20,
				maxOffset: 0
			),
			0
		)
	}

	func testGeometryRubberBandedOffsetClampsWhenLinearLimitConsumesEntireMaximum() {
		XCTAssertEqual(
			ReorderableListGeometry.rubberBandedOffset(
				for: 80,
				linearLimit: 60,
				maxOffset: 60
			),
			60
		)
	}

	func testGeometryFixedHeightInsertionIndexClampsValues() {
		XCTAssertEqual(
			ReorderableListGeometry.fixedHeightInsertionIndex(
				for: -10,
				rowHeight: 40,
				itemCount: 3
			),
			0
		)
		XCTAssertEqual(
			ReorderableListGeometry.fixedHeightInsertionIndex(
				for: 81,
				rowHeight: 40,
				itemCount: 3
			),
			2
		)
		XCTAssertEqual(
			ReorderableListGeometry.fixedHeightInsertionIndex(
				for: 180,
				rowHeight: 40,
				itemCount: 3
			),
			3
		)
		XCTAssertEqual(
			ReorderableListGeometry.fixedHeightInsertionIndex(
				for: 10,
				rowHeight: 0,
				itemCount: 3
			),
			0
		)
	}

	func testItemContainerPinsContentAcrossFullRowWidth() {
		let content = FixedHeightView(height: 40)
		let container = ReorderableListItemContainerView(
			contentView: content,
			backgroundColor: .windowBackgroundColor
		)
		container.frame = CGRect(x: 0, y: 0, width: 200, height: 40)
		container.layoutSubtreeIfNeeded()

		XCTAssertEqual(container.intrinsicContentSize.height, 40)
		XCTAssertTrue(container.contentView.nextResponder === container)
		XCTAssertEqual(container.contentView.frame, CGRect(x: 0, y: 0, width: 200, height: 40))
	}

	func testListUsesClearBackgroundAcrossScrollTableAndRows() throws {
		let list = makeList(items: [0, 1, 2])
		list.frame = CGRect(x: 0, y: 0, width: 240, height: 160)
		list.layoutSubtreeIfNeeded()

		let scrollView = try XCTUnwrap(list.subviews.compactMap { $0 as? ReorderableListScrollView }.first)
		let clipView = try XCTUnwrap(scrollView.contentView as? ReorderableListClipView)
		let documentView = try XCTUnwrap(scrollView.documentView as? ReorderableListDocumentView)
		let tableView = try XCTUnwrap(
			documentView.subviews.first(where: { $0 is ReorderableListTableView }) as? ReorderableListTableView
		)
		let rowView = try XCTUnwrap(tableView.rowView(atRow: 0, makeIfNecessary: true) as? ReorderableListRowView)

		XCTAssertFalse(scrollView.isOpaque)
		XCTAssertFalse(scrollView.drawsBackground)
		XCTAssertEqual(scrollView.backgroundColor, .clear)
		XCTAssertFalse(clipView.isOpaque)
		XCTAssertFalse(documentView.isOpaque)
		XCTAssertTrue(documentView.isFlipped)
		XCTAssertEqual(tableView.frame.minY, 8)
		XCTAssertFalse(tableView.isOpaque)
		XCTAssertFalse(tableView.wantsDefaultClipping)
		XCTAssertEqual(tableView.backgroundColor, .clear)
		XCTAssertEqual(tableView.style, .plain)
		XCTAssertFalse(rowView.isOpaque)
		XCTAssertFalse(rowView.wantsDefaultClipping)
		XCTAssertTrue(rowView.wantsLayer)
		XCTAssertFalse(rowView.layer?.masksToBounds ?? true)
	}

	func testItemContainerForwardsMouseEventsToNextResponder() throws {
		let content = FixedHeightView(height: 40)
		let container = ReorderableListItemContainerView(
			contentView: content,
			backgroundColor: .windowBackgroundColor
		)
		container.frame = CGRect(x: 0, y: 0, width: 200, height: 40)
		let parentView = ForwardingView(frame: CGRect(x: 0, y: 0, width: 200, height: 40))
		parentView.addSubview(container)
		let window = NSWindow(
			contentRect: parentView.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = parentView
		let mouseDownEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDown,
				location: container.convert(NSPoint(x: 20, y: 20), to: nil as NSView?),
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 0,
				clickCount: 1,
				pressure: 1
			)
		)
		let mouseDraggedEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDragged,
				location: container.convert(NSPoint(x: 40, y: 20), to: nil as NSView?),
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 1,
				clickCount: 1,
				pressure: 1
			)
		)
		let mouseUpEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseUp,
				location: container.convert(NSPoint(x: 40, y: 20), to: nil as NSView?),
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 2,
				clickCount: 1,
				pressure: 1
			)
		)

		container.mouseDown(with: mouseDownEvent)
		container.mouseDragged(with: mouseDraggedEvent)
		container.mouseUp(with: mouseUpEvent)

		XCTAssertEqual(parentView.mouseDownCount, 1)
		XCTAssertEqual(parentView.mouseDraggedCount, 1)
		XCTAssertEqual(parentView.mouseUpCount, 1)
	}

	func testItemContainerApplyUsesLiftedStylingForDraggedRow() {
		let content = FixedHeightView(height: 40)
		let container = ReorderableListItemContainerView(
			contentView: content,
			backgroundColor: .windowBackgroundColor
		)
		container.frame = CGRect(x: 0, y: 0, width: 200, height: 40)
		container.layoutSubtreeIfNeeded()
		container.apply(
			cellState: ReorderableListCellState(
				isReordering: true,
				isListReordering: true,
				isHighlighted: false,
				isSelected: false
			),
			animated: false
		)

		XCTAssertEqual(container.alphaValue, 1)
		XCTAssertEqual(container.layer?.borderWidth, ReorderableListStyle.borderWidth)
		XCTAssertEqual(container.layer?.shadowOpacity, ReorderableListStyle.activeShadowOpacity)
		XCTAssertNotEqual(container.layer?.transform.m11, 1)
	}

	func testItemContainerApplyAnimatedPathAlsoUpdatesLayerState() {
		let content = FixedHeightView(height: 40)
		let container = ReorderableListItemContainerView(
			contentView: content,
			backgroundColor: .windowBackgroundColor
		)

		container.apply(
			cellState: ReorderableListCellState(
				isReordering: false,
				isListReordering: false,
				isHighlighted: false,
				isSelected: false
			),
			animated: true
		)

		XCTAssertEqual(container.alphaValue, 1)
		XCTAssertEqual(container.layer?.borderWidth, 0)
	}

	func testItemContainerApplyKeepsNonDraggedRowOpaqueDuringListReorder() {
		let content = FixedHeightView(height: 40)
		let container = ReorderableListItemContainerView(
			contentView: content,
			backgroundColor: .windowBackgroundColor
		)
		container.apply(
			cellState: ReorderableListCellState(
				isReordering: false,
				isListReordering: true,
				isHighlighted: false,
				isSelected: false
			),
			animated: false
		)

		XCTAssertEqual(container.alphaValue, 1)
		XCTAssertEqual(container.layer?.shadowOpacity, 0)
	}

	func testItemContainerForwardsCellStateToObservingContentView() {
		let content = CellStateObserverRowView(height: 40)
		let container = ReorderableListItemContainerView(
			contentView: content,
			backgroundColor: .windowBackgroundColor
		)

		let cellState = ReorderableListCellState(
			isReordering: true,
			isListReordering: true,
			isHighlighted: false,
			isSelected: false
		)
		container.apply(
			cellState: cellState,
			animated: true
		)

		XCTAssertEqual(content.receivedStates.count, 1)
		XCTAssertEqual(content.receivedStates[0].cellState, cellState)
		XCTAssertTrue(content.receivedStates[0].animated)
		XCTAssertEqual(content.layer?.borderWidth, 7)
		XCTAssertEqual(container.layer?.borderWidth, 0)
		XCTAssertEqual(container.layer?.shadowOpacity, 0)
		XCTAssertEqual(container.alphaValue, 1)
	}

	func testItemContainerAppliesDisplacementToContentWrapperOnly() throws {
		let content = FixedHeightView(height: 40)
		let container = ReorderableListItemContainerView(
			contentView: content,
			backgroundColor: .windowBackgroundColor
		)
		container.frame = CGRect(x: 0, y: 0, width: 200, height: 40)
		container.layoutSubtreeIfNeeded()

		container.applyDisplacementOffset(18, animated: false)

		XCTAssertEqual(container.frame.origin.y, 0)
		XCTAssertEqual(content.frame.origin.y, 0)
		let offset = try XCTUnwrap(content.superview?.layer?.transform.m42)
		XCTAssertEqual(offset, CGFloat(18), accuracy: 0.001)
	}

	func testItemContainerAnimatedDisplacementCompletesAtTargetOffset() throws {
		let content = FixedHeightView(height: 40)
		let container = ReorderableListItemContainerView(
			contentView: content,
			backgroundColor: .windowBackgroundColor
		)
		container.frame = CGRect(x: 0, y: 0, width: 200, height: 40)
		container.layoutSubtreeIfNeeded()

		func waitForOffset(
			_ expectedOffset: CGFloat,
			file: StaticString = #filePath,
			line: UInt = #line
		) {
			let deadline = Date(timeIntervalSinceNow: 1)
			while Date() < deadline {
				let currentOffset = content.superview?.layer?.transform.m42 ?? 0
				if abs(currentOffset - expectedOffset) <= 0.001 {
					return
				}
				RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
			}
			XCTFail("Timed out waiting for displacement offset \(expectedOffset)", file: file, line: line)
		}

		container.applyDisplacementOffset(24, animated: true)
		waitForOffset(24)

		let offset = try XCTUnwrap(content.superview?.layer?.transform.m42)
		XCTAssertEqual(offset, CGFloat(24), accuracy: 0.001)

		container.applyDisplacementOffset(0, animated: true)
		waitForOffset(0)
		XCTAssertEqual(content.superview?.layer?.transform.m42 ?? 0, 0, accuracy: 0.001)
		container.applyDisplacementOffset(0, animated: false)
	}

	func testDragControllerLifecycleCoversActivationAndSettlementPaths() {
		let controller = ReorderableListDragController<Int>(dragStartThreshold: 4)

		controller.armPress(itemID: 7, locationInView: CGPoint(x: 10, y: 12))
		XCTAssertTrue(controller.hasPendingPress)
		XCTAssertEqual(controller.armedLocationInView, CGPoint(x: 10, y: 12))
		XCTAssertEqual(controller.activeItemID, 7)
		XCTAssertFalse(controller.blocksModelUpdates)
		XCTAssertFalse(
			controller.beginDragIfArmed(at: CGPoint(x: 11, y: 12)) { _, _ in
				XCTFail("threshold should prevent drag start")
				return nil
			}
		)
		XCTAssertTrue(
			controller.beginDragIfArmed(at: CGPoint(x: 20, y: 12)) { itemID, _ in
				DragSession(
					itemID: itemID,
					initialIndex: 0,
					proposedIndex: 0,
					pointerOffset: .zero
				)
			}
		)
		XCTAssertTrue(controller.isDragging)
		XCTAssertTrue(controller.blocksModelUpdates)

		let finished = controller.finishDrag(cancelled: false)
		XCTAssertNotNil(finished)
		XCTAssertTrue(controller.isSettling)

		let settledExpectation = expectation(description: "drag settlement flushed")
		controller.flushSettlement { itemID, cancelled in
			XCTAssertEqual(itemID, 7)
			XCTAssertFalse(cancelled)
			settledExpectation.fulfill()
		}
		wait(for: [settledExpectation], timeout: 1)
		XCTAssertFalse(controller.isSettling)

		controller.armPress(itemID: 8, locationInView: .zero)
		XCTAssertFalse(controller.activateArmedPress { _, _ in nil })
		XCTAssertFalse(controller.hasPendingPress)

		controller.armPress(itemID: 9, locationInView: CGPoint(x: 1, y: 1))
		XCTAssertTrue(
			controller.activateArmedPress { itemID, _ in
				DragSession(
					itemID: itemID,
					initialIndex: 1,
					proposedIndex: 1,
					pointerOffset: .zero
				)
			}
		)
		_ = controller.finishDrag(cancelled: true)
		XCTAssertTrue(controller.isSettling)
		controller.cancelSettlement()
		XCTAssertFalse(controller.isSettling)
		controller.clearPendingPress()
		XCTAssertNil(controller.armedLocationInView)
	}

	func testDragControllerClearPendingPressAndFailedBeginResetState() {
		let controller = ReorderableListDragController<Int>(dragStartThreshold: 4)

		controller.armPress(itemID: 1, locationInView: CGPoint(x: 8, y: 8))
		controller.clearPendingPress()
		XCTAssertFalse(controller.hasPendingPress)
		XCTAssertNil(controller.armedLocationInView)

		controller.armPress(itemID: 2, locationInView: CGPoint(x: 12, y: 14))
		XCTAssertFalse(
			controller.beginDragIfArmed(at: CGPoint(x: 20, y: 20)) { _, _ in nil }
		)
		XCTAssertFalse(controller.hasPendingPress)
		XCTAssertNil(controller.activeItemID)
	}

	func testDragControllerScheduledSettlementAndIdleNoOpPaths() {
		let controller = ReorderableListDragController<Int>(dragStartThreshold: 4)
		var settled = [(itemID: Int, cancelled: Bool)]()

		controller.scheduleSettlement(after: 0.01) { itemID, cancelled in
			settled.append((itemID, cancelled))
		}
		controller.cancelSettlement()

		controller.armPress(itemID: 4, locationInView: .zero)
		XCTAssertTrue(
			controller.activateArmedPress { itemID, _ in
				DragSession(
					itemID: itemID,
					initialIndex: 0,
					proposedIndex: 0,
					pointerOffset: .zero
				)
			}
		)

		_ = controller.finishDrag(cancelled: true)
		controller.scheduleSettlement(after: 0.01) { itemID, cancelled in
			settled.append((itemID, cancelled))
		}

		RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

		XCTAssertEqual(settled.count, 1)
		XCTAssertEqual(settled.first?.itemID, 4)
		XCTAssertTrue(settled.first?.cancelled ?? false)

		controller.cancelSettlement()
	}

	func testDragVisualControllerLiftFreezeAndSettleLifecycle() throws {
		let hostView = NSView(frame: CGRect(x: 0, y: 0, width: 240, height: 160))
		let window = NSWindow(
			contentRect: hostView.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = hostView
		hostView.layoutSubtreeIfNeeded()

		let controller = ReorderableListDragVisualController()
		controller.attach(to: hostView)

		let snapshot = NSImage(size: NSSize(width: 120, height: 40))
		let sourceFrame = CGRect(x: 12, y: 18, width: 120, height: 40)
		controller.beginLift(
			snapshotImage: snapshot,
			frame: sourceFrame,
			backgroundColor: .windowBackgroundColor,
			appearance: .init()
		)

		let expectedShadowBounds = ReorderableListStyle.liftedOverlayBounds(
			in: CGRect(origin: .zero, size: sourceFrame.size)
		)
		let expectedBorderBounds = ReorderableListStyle.liftedOverlayBorderBounds(
			in: CGRect(origin: .zero, size: sourceFrame.size)
		)
		let expectedBorderBoundsInLocalFrame = CGRect(
			x: ReorderableListStyle.borderWidth / 2,
			y: ReorderableListStyle.borderWidth / 2,
			width: expectedBorderBounds.width,
			height: expectedBorderBounds.height
		)

		XCTAssertTrue(controller.isActive)
		XCTAssertEqual(controller.phase, .lifting)
		XCTAssertEqual(controller.currentFrameInHost, sourceFrame)
		XCTAssertEqual(controller.backgroundFrameForTesting, expectedShadowBounds)
		XCTAssertEqual(controller.borderFrameForTesting, expectedShadowBounds)
		XCTAssertEqual(controller.borderPathBoundsForTesting, expectedBorderBoundsInLocalFrame)
		XCTAssertEqual(controller.shadowPathBoundsForTesting, expectedShadowBounds)

		RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
		controller.freezeToPresentation()
		XCTAssertNotNil(controller.currentFrameInHost)
		XCTAssertGreaterThanOrEqual(controller.borderOpacityForTesting, 0)
		XCTAssertGreaterThanOrEqual(controller.shadowOpacityForTesting, 0)
		XCTAssertGreaterThan(controller.currentRotationRadiansForTesting, 0)

		controller.beginSettle(
			to: CGRect(x: 40, y: 60, width: 120, height: 40),
			commit: true,
			backgroundColor: .windowBackgroundColor,
			appearance: .init(),
			animated: true,
			durationOverride: 0.2
		)
		XCTAssertEqual(controller.phase, .settling(commit: true))
		XCTAssertEqual(try XCTUnwrap(controller.settleDuration), 0.2, accuracy: 0.001)

		controller.tearDown()
		XCTAssertFalse(controller.isActive)
		XCTAssertEqual(controller.phase, .idle)
		XCTAssertNil(controller.settleDuration)
	}

	func testDragVisualControllerCurrentRotationFallsBackToModelLayerWhenNoPresentationExists() {
		let hostView = NSView(frame: CGRect(x: 0, y: 0, width: 240, height: 160))
		let controller = ReorderableListDragVisualController()
		controller.attach(to: hostView)

		controller.beginLift(
			snapshotImage: NSImage(size: NSSize(width: 120, height: 40)),
			frame: CGRect(x: 12, y: 18, width: 120, height: 40),
			backgroundColor: .windowBackgroundColor,
			appearance: .init(rotationRadians: .pi / 8)
		)

		XCTAssertEqual(controller.currentRotationRadiansForTesting, .pi / 8, accuracy: 0.0001)
	}

	func testDragVisualControllerSkipsShapePathRebuildForPositionOnlyUpdates() {
		let hostView = NSView(frame: CGRect(x: 0, y: 0, width: 240, height: 160))
		hostView.wantsLayer = true

		let controller = ReorderableListDragVisualController()
		controller.attach(to: hostView)

		let frame = CGRect(x: 12, y: 18, width: 120, height: 40)
		controller.beginLift(
			snapshotImage: NSImage(size: frame.size),
			frame: frame,
			backgroundColor: .windowBackgroundColor,
			appearance: .init()
		)

		let initialShapePathUpdateCount = controller.shapePathUpdateCountForTesting
		let positionOnlyUpdateKind = controller.updateDraggedFrame(
			CGRect(x: 30, y: 44, width: 120, height: 40)
		)
		let boundsChangedUpdateKind = controller.updateDraggedFrame(
			CGRect(x: 30, y: 44, width: 132, height: 44)
		)

		XCTAssertEqual(positionOnlyUpdateKind, .positionOnly)
		XCTAssertEqual(controller.shapePathUpdateCountForTesting, initialShapePathUpdateCount + 1)
		XCTAssertEqual(controller.positionOnlyUpdateCountForTesting, 1)
		XCTAssertEqual(boundsChangedUpdateKind, .boundsChanged)
		XCTAssertEqual(controller.boundsUpdateCountForTesting, 1)
	}

	func testDragVisualControllerPresentationFrameFallsBackToCurrentFrameWithoutPresentationLayer() {
		let hostView = NSView(frame: CGRect(x: 0, y: 0, width: 200, height: 120))
		hostView.wantsLayer = true
		let controller = ReorderableListDragVisualController()
		controller.attach(to: hostView)
		let frame = CGRect(x: 16, y: 24, width: 100, height: 40)

		controller.beginLift(
			snapshotImage: NSImage(size: frame.size),
			frame: frame,
			backgroundColor: .windowBackgroundColor,
			appearance: .init()
		)

		XCTAssertEqual(controller.presentationFrameInHost, frame)
		controller.beginSettle(
			to: frame,
			commit: false,
			backgroundColor: .windowBackgroundColor,
			appearance: .init(),
			animated: false
		)
		XCTAssertEqual(controller.settleDuration, 0)
	}

	func testDragVisualControllerDefensivePathsWithoutAttachedHost() {
		let controller = ReorderableListDragVisualController()
		let frame = CGRect(x: 20, y: 24, width: 110, height: 44)

		XCTAssertEqual(controller.currentFrameInHost, .zero)
		XCTAssertEqual(controller.presentationFrameInHost, .zero)
		XCTAssertGreaterThanOrEqual(controller.borderOpacityForTesting, 0)
		XCTAssertGreaterThanOrEqual(controller.shadowOpacityForTesting, 0)

		controller.updateDraggedFrame(frame)
		controller.beginLift(
			snapshotImage: NSImage(size: frame.size),
			frame: frame,
			backgroundColor: .windowBackgroundColor,
			appearance: .init()
		)

		XCTAssertFalse(controller.isActive)

		controller.beginSettle(
			to: frame,
			commit: false,
			backgroundColor: .windowBackgroundColor,
			appearance: .init(),
			animated: true
		)

		XCTAssertEqual(controller.phase, .settling(commit: false))
		XCTAssertNotNil(controller.settleDuration)
		XCTAssertFalse(controller.isActive)

		controller.tearDown()
		XCTAssertEqual(controller.phase, .idle)
	}

	func testDragVisualControllerSettleWithoutOverrideUsesResolvedDurationFromCurrentFrame() {
		let hostView = NSView(frame: CGRect(x: 0, y: 0, width: 240, height: 160))
		hostView.wantsLayer = true

		let controller = ReorderableListDragVisualController()
		controller.attach(to: hostView)

		let sourceFrame = CGRect(x: 12, y: 18, width: 120, height: 40)
		let targetFrame = CGRect(x: 72, y: 88, width: 120, height: 40)

		controller.beginLift(
			snapshotImage: NSImage(size: sourceFrame.size),
			frame: sourceFrame,
			backgroundColor: .windowBackgroundColor,
			appearance: .init()
		)
		controller.beginSettle(
			to: targetFrame,
			commit: true,
			backgroundColor: .windowBackgroundColor,
			appearance: .init(),
			animated: true
		)

		XCTAssertEqual(
			try XCTUnwrap(controller.settleDuration),
			ReorderableListDragVisualController.resolvedSettleDuration(
				from: sourceFrame,
				to: targetFrame
			),
			accuracy: 0.001
		)
	}

	func testReorderableListBuildsRowsAndMeasuresDocumentHeight() {
		let list = makeList(items: [0, 1, 2])
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		list.layoutSubtreeIfNeeded()

		XCTAssertEqual(list.currentVisualOrder(), [0, 1, 2])
		XCTAssertEqual(list.documentHeight(), 200)
		XCTAssertEqual(list.containerFrame(for: 0).height, 40)
	}

	func testReorderableListSupportsExplicitClearHeaderAndFooterViews() throws {
		let list = ReorderableListView(
			items: [0, 1, 2],
			id: \.self,
			contentInsets: NSEdgeInsetsZero,
			rowBackgroundColor: .windowBackgroundColor,
			onMove: { _, _ in },
			contentViewBuilder: { _ in
				FixedHeightView(height: 40)
			}
		)
		list.setClearTableChromeHeights(headerHeight: 10, footerHeight: 10)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		list.layoutSubtreeIfNeeded()

		let tableFrame = list.tableFrameForTesting()
		let headerFrame = try XCTUnwrap(list.clearTableHeaderFrameForTesting())
		let footerFrame = try XCTUnwrap(list.clearTableFooterFrameForTesting())

		XCTAssertEqual(tableFrame.minY, 10)
		XCTAssertEqual(headerFrame.height, 10)
		XCTAssertEqual(footerFrame.height, 10)
		XCTAssertEqual(footerFrame.minY, tableFrame.maxY)
		XCTAssertEqual(list.documentHeight() - tableFrame.maxY, 10)
	}

	func testReorderableListUsesMeasuredHeightOnFirstLayout() {
		let list = ReorderableListView(
			items: [0, 1],
			id: \.self,
			contentInsets: NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0),
			rowBackgroundColor: .windowBackgroundColor,
			onMove: { _, _ in },
			contentViewBuilder: { index in
				FixedHeightView(height: index == 0 ? 80 : 40)
			}
		)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		list.layoutSubtreeIfNeeded()

		XCTAssertEqual(list.containerFrame(for: 0).height, 80)
		XCTAssertEqual(list.indexOfContainerForTesting(at: NSPoint(x: 20, y: 60)), 0)
		XCTAssertEqual(list.indexOfContainerForTesting(at: NSPoint(x: 20, y: 100)), 1)
	}

	func testReorderableListInvalidatesMeasuredHeightWhenWidthChanges() {
		let list = ReorderableListView(
			items: [0],
			id: \.self,
			contentInsets: NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0),
			rowBackgroundColor: .windowBackgroundColor,
			onMove: { _, _ in },
			contentViewBuilder: { _ in WidthResponsiveHeightView() }
		)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		list.layoutSubtreeIfNeeded()

		XCTAssertEqual(list.containerFrame(for: 0).height, 40)

		list.frame = CGRect(x: 0, y: 0, width: 140, height: 200)
		list.layoutSubtreeIfNeeded()

		XCTAssertEqual(list.containerFrame(for: 0).height, 80)
	}

	func testReorderableListDragPreviewReordersVisualFrames() {
		let list = makeList(items: [0, 1, 2])
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		list.layoutSubtreeIfNeeded()
		let secondRowFrame = list.containerFrame(for: 1)
		let thirdRowFrame = list.containerFrame(for: 2)

		list.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 260, y: 20)
		)
		list.updateDragForTesting(locationInContent: NSPoint(x: 260, y: 100))

		XCTAssertTrue(list.isReordering())
		XCTAssertEqual(list.currentVisualOrder(), [1, 0, 2])
		XCTAssertEqual(list.containerFrame(for: 1), secondRowFrame)
		XCTAssertEqual(list.containerFrame(for: 2), thirdRowFrame)
		let expectedDropIndicator = CGRect(
			x: ReorderableListStyle.dropIndicatorHorizontalInset,
			y: secondRowFrame.maxY - (ReorderableListStyle.dropIndicatorHeight / 2),
			width: list.bounds.width - (ReorderableListStyle.dropIndicatorHorizontalInset * 2),
			height: ReorderableListStyle.dropIndicatorHeight
		)
		XCTAssertEqual(
			list.dropIndicatorFrameForTesting(),
			expectedDropIndicator
		)
		XCTAssertEqual(
			list.dropIndicatorColorForTesting(),
			ReorderableListStyle.resolvedColor(
				ReorderableListStyle.dragPlaceholderStrokeColor,
				for: list.effectiveAppearance
			)
		)
	}

	func testReorderableListClipsDragOverlayToVisibleViewport() throws {
		let list = makeList(items: [0, 1, 2], handleWidth: nil)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		list.layoutSubtreeIfNeeded()

		let overlayHostView = try XCTUnwrap(
			list.subviews.compactMap { $0 as? ReorderableTableOverlayHostView }.first
		)
		let firstRowFrame = try XCTUnwrap(list.rowFrameForTesting(modelIndex: 0))

		list.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: firstRowFrame.midX, y: firstRowFrame.midY)
		)
		list.updateDragForTesting(
			locationInContent: NSPoint(x: firstRowFrame.midX, y: -24)
		)

		let dragFrame = try XCTUnwrap(list.rowPresentationFrameForTesting(modelIndex: 0))
		XCTAssertLessThan(dragFrame.minY, 0)
		XCTAssertEqual(overlayHostView.frame, list.bounds)
		XCTAssertTrue(overlayHostView.layer?.masksToBounds ?? false)
	}

	func testReorderableListKeepsVisibleRowsStableDuringDrag() throws {
		let list = makeList(items: [0, 1, 2], handleWidth: nil)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		list.layoutSubtreeIfNeeded()

		list.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)
		list.updateDragForTesting(locationInContent: NSPoint(x: 20, y: 100))
		RunLoop.current.run(until: Date().addingTimeInterval(0.05))

		let secondContainer = try XCTUnwrap(list.containerViewForTesting(row: 1))
		let thirdContainer = try XCTUnwrap(list.containerViewForTesting(row: 2))
		let secondOffset = secondContainer.contentView.superview?.layer?.transform.m42 ?? 0
		let thirdOffset = thirdContainer.contentView.superview?.layer?.transform.m42 ?? 0
		XCTAssertEqual(list.currentVisualOrder(), [1, 0, 2])
		XCTAssertEqual(secondOffset, 0, accuracy: 0.001)
		XCTAssertEqual(thirdOffset, 0, accuracy: 0.001)

		list.endDragForTesting(cancelled: false)

		XCTAssertFalse(list.isReordering())
	}

	func testReorderableListFixedHeightDragUsesFastDestinationResolverMetrics() {
		let list = ReorderableListView(
			items: [0, 1, 2],
			id: \.self,
			contentInsets: NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0),
			rowSpacing: 0,
			rowBackgroundColor: .windowBackgroundColor,
			fixedRowHeight: 40,
			onMove: { _, _ in },
			contentViewBuilder: { _ in
				FixedHeightView(height: 40)
			}
		)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		list.layoutSubtreeIfNeeded()

		list.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)
		list.updateDragForTesting(locationInContent: NSPoint(x: 20, y: 100))

		XCTAssertEqual(list.performanceMetrics.fixedHeightDestinationIndexEvaluations, 1)
		XCTAssertEqual(list.performanceMetrics.variableHeightDestinationIndexEvaluations, 0)
		XCTAssertEqual(list.performanceMetrics.overlayUpdates, 1)
		XCTAssertEqual(list.performanceMetrics.overlayPositionOnlyUpdates, 1)
		XCTAssertEqual(list.performanceMetrics.overlayBoundsUpdates, 0)
	}

	func testReorderableListVariableHeightDragUsesPreviewCenterDestinationResolver() {
		let list = ReorderableListView(
			items: [0, 1, 2],
			id: \.self,
			contentInsets: NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0),
			rowSpacing: 5,
			rowBackgroundColor: .windowBackgroundColor,
			onMove: { _, _ in },
			contentViewBuilder: { index in
				FixedHeightView(height: index == 1 ? 80 : 40)
			}
		)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 240)
		list.layoutSubtreeIfNeeded()

		list.beginDragForTesting(
			sourceIndex: 1,
			locationInContent: NSPoint(x: 20, y: 90)
		)
		list.updateDragForTesting(locationInContent: NSPoint(x: 20, y: 150))

		XCTAssertEqual(list.performanceMetrics.fixedHeightDestinationIndexEvaluations, 0)
		XCTAssertEqual(list.performanceMetrics.variableHeightDestinationIndexEvaluations, 1)
	}

	func testReorderableListDragPreviewSnapshotCacheReusesAndInvalidatesImages() {
		let list = makeList(items: [0], handleWidth: nil)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 120)
		list.layoutSubtreeIfNeeded()

		list.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)
		list.endDragForTesting(cancelled: true)
		list.flushPendingDropResetForTesting()

		list.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)
		list.endDragForTesting(cancelled: true)
		list.flushPendingDropResetForTesting()

		XCTAssertEqual(list.performanceMetrics.dragPreviewCreations, 1)
		XCTAssertEqual(list.performanceMetrics.dragPreviewCacheHits, 1)
		XCTAssertEqual(list.performanceMetrics.dragPreviewCacheMisses, 1)

		list.setItems([0])
		list.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)

		XCTAssertEqual(list.performanceMetrics.dragPreviewCreations, 2)
		XCTAssertEqual(list.performanceMetrics.dragPreviewCacheHits, 1)
		XCTAssertEqual(list.performanceMetrics.dragPreviewCacheMisses, 2)
	}

	func testReorderableListDragPreviewSnapshotCacheInvalidatesWhenSelectionChanges() {
		let list = makeList(items: [0], handleWidth: nil)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 120)
		list.layoutSubtreeIfNeeded()

		list.selectedID = 0
		list.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)
		list.endDragForTesting(cancelled: true)
		list.flushPendingDropResetForTesting()

		list.selectedID = nil
		list.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)

		XCTAssertEqual(list.performanceMetrics.dragPreviewCreations, 2)
		XCTAssertEqual(list.performanceMetrics.dragPreviewCacheHits, 0)
		XCTAssertEqual(list.performanceMetrics.dragPreviewCacheMisses, 2)
	}

	func testReorderableListControllerIndexCachesStayInSyncAcrossReorderAndReload() {
		let harness = makeListControllerHarness(
			items: [0, 1, 2],
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			)
		)
		let controller = harness.controller

		XCTAssertEqual(controller.cachedIndicesForTesting(itemID: 0).modelIndex, 0)
		XCTAssertEqual(controller.cachedIndicesForTesting(itemID: 2).displayRow, 2)

		controller.beginDragForTesting(sourceIndex: 0, locationInContent: NSPoint(x: 20, y: 20))
		controller.updateDragForTesting(locationInContent: NSPoint(x: 20, y: 100))
		controller.endDragForTesting(cancelled: false)

		XCTAssertEqual(controller.cachedIndicesForTesting(itemID: 0).modelIndex, 0)
		XCTAssertEqual(controller.cachedIndicesForTesting(itemID: 0).displayRow, 1)

		controller.flushPendingDropResetForTesting()
		controller.setItems([2, 0, 1])
		controller.appendItems([3])

		XCTAssertEqual(controller.cachedIndicesForTesting(itemID: 2).modelIndex, 0)
		XCTAssertEqual(controller.cachedIndicesForTesting(itemID: 2).displayRow, 0)
		XCTAssertEqual(controller.cachedIndicesForTesting(itemID: 0).modelIndex, 1)
		XCTAssertEqual(controller.cachedIndicesForTesting(itemID: 3).modelIndex, 3)
		XCTAssertEqual(controller.cachedIndicesForTesting(itemID: 3).displayRow, 3)
	}

	func testReorderableListControllerAutoscrollLoadsOnlyNewEdgeRows() throws {
		let harness = makeListControllerHarness(
			items: Array(0..<20),
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(
					edgeZoneHeight: 56,
					minimumSpeed: 240,
					maximumSpeed: 960
				),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			)
		)
		let controller = harness.controller
		let clipView = try XCTUnwrap(harness.tableView.enclosingScrollView?.contentView)
		let initialVisibleRows = controller.visibleRowRangeForTesting()

		controller.beginDragForTesting(sourceIndex: 0, locationInContent: NSPoint(x: 20, y: 20))
		controller.updateDragForTesting(
			locationInContent: NSPoint(x: 20, y: harness.tableView.bounds.maxY - 2)
		)
		XCTAssertTrue(controller.handleAutoscrollTickForTesting())
		XCTAssertEqual(controller.performanceMetrics.autoscrollVisibleRowRealizations, 0)

		clipView.scroll(to: NSPoint(x: 0, y: 40))
		harness.tableView.enclosingScrollView?.reflectScrolledClipView(clipView)
		controller.ensureAutoscrolledRowsLoadedForTesting(previousVisibleRows: initialVisibleRows)
		XCTAssertEqual(controller.performanceMetrics.autoscrollVisibleRowRealizations, 1)

		clipView.scroll(to: NSPoint(x: 0, y: 0))
		harness.tableView.enclosingScrollView?.reflectScrolledClipView(clipView)
		controller.ensureAutoscrolledRowsLoadedForTesting(previousVisibleRows: 1..<5)
		XCTAssertEqual(controller.performanceMetrics.autoscrollVisibleRowRealizations, 2)
	}

	func testReorderableListControllerAutoscrollRealizesAndRefreshesNewlyVisibleRows() throws {
		let harness = makeListControllerHarness(
			items: Array(0..<20),
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(
					edgeZoneHeight: 56,
					minimumSpeed: 240,
					maximumSpeed: 960
				),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			)
		)
		let controller = harness.controller
		let clipView = try XCTUnwrap(harness.tableView.enclosingScrollView?.contentView)
		let initialVisibleRows = try XCTUnwrap(controller.visibleRowRangeForTesting())
		let newlyVisibleRow = initialVisibleRows.upperBound

		clipView.scroll(to: NSPoint(x: 0, y: 40))
		harness.tableView.enclosingScrollView?.reflectScrolledClipView(clipView)
		controller.ensureAutoscrolledRowsLoadedForTesting(previousVisibleRows: initialVisibleRows)

		XCTAssertNotNil(controller.rowViewForTesting(modelIndex: newlyVisibleRow))
		XCTAssertNotNil(controller.containerViewForTesting(row: newlyVisibleRow))
	}

	func testReorderableListControllerRecordsTraceEventsAndDurationsAcrossDragLifecycle() {
		let traceRecorder = PerformanceTraceRecorder()
		let monotonicClock = SteppedMonotonicClock(values: [0, 0.1, 0.2, 0.25, 0.5, 0.9])
		let harness = makeListControllerHarness(
			items: [0, 1, 2],
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			),
			performanceTracing: traceRecorder,
			monotonicClock: { monotonicClock.now() }
		)
		let controller = harness.controller

		controller.beginDragForTesting(sourceIndex: 0, locationInContent: NSPoint(x: 20, y: 20))
		controller.updateDragForTesting(locationInContent: NSPoint(x: 20, y: 90))
		controller.endDragForTesting(cancelled: false)
		controller.flushPendingDropResetForTesting()

		XCTAssertEqual(
			traceRecorder.records,
			[
				.init(phase: .begin, event: .dragLift),
				.init(phase: .end, event: .dragLift),
				.init(phase: .begin, event: .dragUpdate),
				.init(phase: .end, event: .dragUpdate),
				.init(phase: .begin, event: .dragSettle),
				.init(phase: .end, event: .dragSettle),
			]
		)
		XCTAssertEqual(controller.performanceMetrics.dragLiftMeasurementCount, 1)
		XCTAssertEqual(controller.performanceMetrics.dragLiftTotalDuration, 0.1, accuracy: 0.0001)
		XCTAssertEqual(controller.performanceMetrics.dragUpdateMeasurementCount, 1)
		XCTAssertEqual(controller.performanceMetrics.dragUpdateTotalDuration, 0.05, accuracy: 0.0001)
		XCTAssertEqual(controller.performanceMetrics.dragSettleMeasurementCount, 1)
		XCTAssertEqual(controller.performanceMetrics.dragSettleTotalDuration, 0.4, accuracy: 0.0001)
	}

	func testReorderableListControllerRecordsAutoscrollTraceEventsAndDurations() {
		let traceRecorder = PerformanceTraceRecorder()
		let monotonicClock = SteppedMonotonicClock(
			values: [0, 0.1, 0.2, 0.25, 0.3, 0.35, 0.4, 0.55]
		)
		let harness = makeListControllerHarness(
			items: Array(0..<20),
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(
					edgeZoneHeight: 56,
					minimumSpeed: 240,
					maximumSpeed: 960
				),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			),
			performanceTracing: traceRecorder,
			monotonicClock: { monotonicClock.now() }
		)
		let controller = harness.controller

		controller.beginDragForTesting(sourceIndex: 0, locationInContent: NSPoint(x: 20, y: 20))
		controller.updateDragForTesting(
			locationInContent: NSPoint(x: 20, y: harness.tableView.bounds.maxY - 2)
		)

		XCTAssertTrue(controller.handleAutoscrollTickForTesting())
		XCTAssertEqual(
			traceRecorder.records,
			[
				.init(phase: .begin, event: .dragLift),
				.init(phase: .end, event: .dragLift),
				.init(phase: .begin, event: .dragUpdate),
				.init(phase: .end, event: .dragUpdate),
				.init(phase: .begin, event: .autoscrollTick),
				.init(phase: .begin, event: .dragUpdate),
				.init(phase: .end, event: .dragUpdate),
				.init(phase: .end, event: .autoscrollTick),
			]
		)
		XCTAssertEqual(controller.performanceMetrics.autoscrollTickMeasurementCount, 1)
		XCTAssertEqual(controller.performanceMetrics.autoscrollTickTotalDuration, 0.25, accuracy: 0.0001)
		XCTAssertEqual(controller.performanceMetrics.dragUpdateMeasurementCount, 2)
		XCTAssertEqual(controller.performanceMetrics.dragUpdateTotalDuration, 0.1, accuracy: 0.0001)
	}

	func testReorderableListControllerResolvedDestinationIndexFallsBackToFreshResolverWhenNoSessionIsActive() {
		let harness = makeListControllerHarness(
			items: [0, 1, 2],
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			)
		)

		XCTAssertEqual(
			harness.controller.resolvedDestinationIndexForTesting(
				targetCenterY: 80,
				sourceIndex: 0
			),
			2
		)
	}

	func testReorderableListDragLifecycleKeepsLiveRowsNonAnimatedAndOpaqueUntilSettleCompletes() throws {
		let rowViews = [
			CellStateObserverRowView(height: 40),
			CellStateObserverRowView(height: 40),
			CellStateObserverRowView(height: 40),
		]
		let list = ReorderableListView(
			items: [0, 1, 2],
			id: \.self,
			contentInsets: NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0),
			rowBackgroundColor: .windowBackgroundColor,
			onMove: { _, _ in },
			contentViewBuilder: { rowViews[$0] }
		)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		list.layoutSubtreeIfNeeded()
		rowViews.forEach { $0.resetReceivedStates() }

		list.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)
		let secondContainer = try XCTUnwrap(list.containerViewForTesting(row: 1))

		XCTAssertEqual(
			try XCTUnwrap(rowViews[0].receivedStates.last).cellState,
			ReorderableListCellState(
				isReordering: true,
				isListReordering: true,
				isHighlighted: false,
				isSelected: false
			)
		)
		XCTAssertEqual(
			try XCTUnwrap(rowViews[1].receivedStates.last).cellState,
			ReorderableListCellState(
				isReordering: false,
				isListReordering: true,
				isHighlighted: false,
				isSelected: false
			)
		)
		XCTAssertTrue(rowViews.flatMap(\.receivedStates).allSatisfy { $0.animated == false })
		XCTAssertEqual(secondContainer.alphaValue, 1)

		list.updateDragForTesting(locationInContent: NSPoint(x: 20, y: 100))
		list.endDragForTesting(cancelled: false)

		XCTAssertEqual(
			try XCTUnwrap(rowViews[0].receivedStates.last).cellState,
			ReorderableListCellState(
				isReordering: false,
				isListReordering: true,
				isHighlighted: false,
				isSelected: false
			)
		)
		XCTAssertEqual(
			try XCTUnwrap(rowViews[1].receivedStates.last).cellState,
			ReorderableListCellState(
				isReordering: false,
				isListReordering: true,
				isHighlighted: false,
				isSelected: false
			)
		)
		XCTAssertTrue(rowViews.flatMap(\.receivedStates).allSatisfy { $0.animated == false })
		XCTAssertEqual(secondContainer.alphaValue, 1)

		list.flushPendingDropResetForTesting()

		XCTAssertEqual(
			try XCTUnwrap(rowViews[0].receivedStates.last).cellState,
			ReorderableListCellState(
				isReordering: false,
				isListReordering: false,
				isHighlighted: false,
				isSelected: false
			)
		)
		XCTAssertEqual(
			try XCTUnwrap(rowViews[1].receivedStates.last).cellState,
			ReorderableListCellState(
				isReordering: false,
				isListReordering: false,
				isHighlighted: false,
				isSelected: false
			)
		)
		XCTAssertTrue(rowViews.flatMap(\.receivedStates).allSatisfy { $0.animated == false })
		XCTAssertEqual(secondContainer.alphaValue, 1)
	}

	func testReorderableListDoesNotShowDropIndicatorAtOriginalIndex() {
		let list = makeList(items: [0, 1, 2], handleWidth: nil)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		list.layoutSubtreeIfNeeded()

		list.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)
		list.updateDragForTesting(locationInContent: NSPoint(x: 20, y: 20))

		XCTAssertTrue(list.isReordering())
		XCTAssertEqual(list.currentVisualOrder(), [0, 1, 2])
		XCTAssertNil(list.dropIndicatorFrameForTesting())
	}

	func testReorderableListShowsAnimatedDashedPlaceholderInOriginalSlotWhileDragging() throws {
		let list = makeList(items: [0, 1, 2], handleWidth: nil)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		list.layoutSubtreeIfNeeded()
		let sourceFrame = list.containerFrame(for: 0)

		list.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)

		let placeholderFrame = try XCTUnwrap(list.dragPlaceholderFrameForTesting())
		let placeholderView = try XCTUnwrap(list.dragPlaceholderViewForTesting())
		let expectedStrokeColor = ReorderableListStyle.resolvedColor(
			ReorderableListStyle.dragPlaceholderStrokeColor,
			for: placeholderView.effectiveAppearance
		)
		let expectedPlaceholderFrame = CGRect(
			x: sourceFrame.origin.x + ReorderableListStyle.dragPlaceholderHorizontalInset,
			y: sourceFrame.origin.y,
			width: sourceFrame.width - (ReorderableListStyle.dragPlaceholderHorizontalInset * 2),
			height: sourceFrame.height
		)

		XCTAssertEqual(placeholderFrame, expectedPlaceholderFrame)
		XCTAssertEqual(
			placeholderView.dashPatternForTesting,
			ReorderableListStyle.dragPlaceholderDashPattern
		)
		XCTAssertEqual(placeholderView.strokeColorForTesting, expectedStrokeColor)
		XCTAssertTrue(placeholderView.isDashAnimationActiveForTesting)
	}

	func testReorderableListKeepsPlaceholderUntilDropResetCompletes() {
		let list = makeList(items: [0, 1, 2], handleWidth: nil)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		list.layoutSubtreeIfNeeded()

		list.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)
		list.endDragForTesting(cancelled: false)

		XCTAssertNotNil(list.dragPlaceholderFrameForTesting())

		list.flushPendingDropResetForTesting()

		XCTAssertNil(list.dragPlaceholderFrameForTesting())
	}

	func testReorderableListDragPreviewRubberBandsHorizontally() {
		let list = makeList(items: [0, 1, 2], handleWidth: nil)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		list.layoutSubtreeIfNeeded()

		list.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)
		list.updateDragForTesting(locationInContent: NSPoint(x: 220, y: 20))

		let draggedFrame = list.containerFrame(for: 0)
		XCTAssertGreaterThan(draggedFrame.origin.x, 0)
		XCTAssertLessThanOrEqual(
			draggedFrame.origin.x,
			ReorderableListStyle.maxHorizontalDragOffset
		)
	}

	func testReorderableListDragPreviewRubberBandAllowsNegativeHorizontalOffset() {
		let list = makeList(items: [0, 1, 2], handleWidth: nil)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		list.layoutSubtreeIfNeeded()

		list.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 260, y: 20)
		)
		list.updateDragForTesting(locationInContent: NSPoint(x: -80, y: 20))

		let draggedFrame = list.containerFrame(for: 0)
		XCTAssertLessThan(draggedFrame.origin.x, 0)
		XCTAssertGreaterThanOrEqual(
			draggedFrame.origin.x,
			-ReorderableListStyle.maxHorizontalDragOffset
		)
	}

	func testReorderableListNoopEntryPointsDoNotMutateState() {
		var moveCalled = false
		let list = makeList(
			items: [0, 1, 2],
			onMove: { _, _ in
				moveCalled = true
			}
		)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		list.layoutSubtreeIfNeeded()

		list.updateDragForTesting(locationInContent: NSPoint(x: 22, y: 40))
		list.endDragForTesting(cancelled: false)
		list.beginDragForTesting(sourceIndex: -1, locationInContent: NSPoint(x: 22, y: 20))
		list.beginDragForTesting(sourceIndex: 0, locationInContent: NSPoint(x: 22, y: 20))
		list.beginDragForTesting(sourceIndex: 1, locationInContent: NSPoint(x: 22, y: 60))
		list.endDragForTesting(cancelled: false)
		list.flushPendingDropResetForTesting()

		XCTAssertFalse(moveCalled)
		XCTAssertFalse(list.isReordering())
		XCTAssertEqual(list.currentVisualOrder(), [0, 1, 2])
	}

	func testReorderableListDuplicateBeginDragIsANoop() {
		let list = makeList(items: [0, 1, 2], handleWidth: nil)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		list.layoutSubtreeIfNeeded()

		list.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)

		list.beginDragForTesting(
			sourceIndex: 1,
			locationInContent: NSPoint(x: 20, y: 60)
		)

		XCTAssertTrue(list.isReordering())
		XCTAssertFalse(list.hasPendingPressForTesting())
	}

	func testReorderableListDropCallsOnMoveWithSwiftMoveDestination() {
		var moves = [(IndexSet, Int)]()
		let list = makeList(
			items: [0, 1, 2],
			onMove: { source, destination in
				moves.append((source, destination))
			}
		)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		list.layoutSubtreeIfNeeded()

		list.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 260, y: 20)
		)
		list.updateDragForTesting(locationInContent: NSPoint(x: 260, y: 100))
		list.endDragForTesting(cancelled: false)

		XCTAssertEqual(moves.count, 1)
		XCTAssertEqual(moves.first?.0, IndexSet(integer: 0))
		XCTAssertEqual(moves.first?.1, 2)
		XCTAssertFalse(list.isReordering())
		XCTAssertNil(list.dropIndicatorFrameForTesting())
		XCTAssertEqual(
			list.rowFrameForTesting(modelIndex: 0),
			list.containerFrame(for: 0)
		)
		list.flushPendingDropResetForTesting()
		XCTAssertFalse(list.isReordering())
	}

	func testReorderableListDropSettleAnimationUsesDistanceAwareDuration() throws {
		let list = makeList(items: [0, 1, 2], handleWidth: nil)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		list.layoutSubtreeIfNeeded()

		list.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 220, y: 20)
		)
		list.updateDragForTesting(locationInContent: NSPoint(x: 140, y: 96))

		list.endDragForTesting(cancelled: false)
		let duration = try XCTUnwrap(list.rowSettleAnimationDurationForTesting(modelIndex: 0))
		XCTAssertGreaterThanOrEqual(duration, ReorderableListStyle.minimumSettleDuration)
		XCTAssertLessThanOrEqual(duration, ReorderableListStyle.maximumSettleDuration)
		XCTAssertGreaterThan(duration, ReorderableListStyle.minimumSettleDuration)
	}

	func testReorderableListCancelledDropDoesNotCallOnMove() {
		var moveCalled = false
		let list = makeList(
			items: [0, 1, 2],
			onMove: { _, _ in
				moveCalled = true
			}
		)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		list.layoutSubtreeIfNeeded()

		list.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 260, y: 20)
		)
		list.updateDragForTesting(locationInContent: NSPoint(x: 260, y: 100))
		list.endDragForTesting(cancelled: true)

		XCTAssertFalse(moveCalled)
		XCTAssertEqual(list.currentVisualOrder(), [0, 1, 2])
		XCTAssertFalse(list.isReordering())
		XCTAssertNil(list.dropIndicatorFrameForTesting())
		XCTAssertEqual(
			list.rowFrameForTesting(modelIndex: 0),
			list.containerFrame(for: 0)
		)
		list.flushPendingDropResetForTesting()
		XCTAssertFalse(list.isReordering())
	}

	func testReorderableListEscapeCancelsActiveDragAndAnimatesBackToOrigin() {
		var moveCalled = false
		let list = makeList(
			items: [0, 1, 2],
			handleWidth: nil,
			onMove: { _, _ in
				moveCalled = true
			}
		)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		let window = NSWindow(
			contentRect: list.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = list
		window.makeKeyAndOrderFront(nil)
		defer { window.orderOut(nil) }
		list.layoutSubtreeIfNeeded()

		list.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)
		list.updateDragForTesting(locationInContent: NSPoint(x: 220, y: 100))

		XCTAssertTrue(window.firstResponder === list)
		XCTAssertTrue(list.isReordering())

		list.cancelOperation(nil)

		XCTAssertFalse(moveCalled)
		XCTAssertFalse(list.isReordering())
		XCTAssertEqual(list.currentVisualOrder(), [0, 1, 2])
		XCTAssertEqual(list.containerFrame(for: 0).origin.x, 0, accuracy: 0.001)
		XCTAssertNil(list.dropIndicatorFrameForTesting())

		list.flushPendingDropResetForTesting()
		XCTAssertFalse(list.isReordering())
	}

	func testReorderableListEscapeKeyDownCancelsActiveDrag() throws {
		var moveCalled = false
		let list = makeList(
			items: [0, 1, 2],
			handleWidth: nil,
			onMove: { _, _ in
				moveCalled = true
			}
		)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		let window = NSWindow(
			contentRect: list.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = list
		list.layoutSubtreeIfNeeded()

		list.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)
		list.updateDragForTesting(locationInContent: NSPoint(x: 220, y: 100))

		let escapeEvent = try XCTUnwrap(
			NSEvent.keyEvent(
				with: .keyDown,
				location: .zero,
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				characters: "\u{1b}",
				charactersIgnoringModifiers: "\u{1b}",
				isARepeat: false,
				keyCode: 53
			)
		)

		list.keyDown(with: escapeEvent)

		XCTAssertFalse(moveCalled)
		XCTAssertFalse(list.isReordering())
		XCTAssertEqual(list.currentVisualOrder(), [0, 1, 2])
		list.flushPendingDropResetForTesting()
	}

	func testReorderableListWindowSendEventEscapeCancelsActiveDrag() throws {
		var moveCalled = false
		let list = makeList(
			items: [0, 1, 2],
			handleWidth: nil,
			onMove: { _, _ in
				moveCalled = true
			}
		)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		let window = NSWindow(
			contentRect: list.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = list
		window.makeKeyAndOrderFront(nil)
		defer { window.orderOut(nil) }
		list.layoutSubtreeIfNeeded()

		list.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)
		list.updateDragForTesting(locationInContent: NSPoint(x: 220, y: 100))

		let escapeEvent = try XCTUnwrap(
			NSEvent.keyEvent(
				with: .keyDown,
				location: .zero,
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				characters: "\u{1b}",
				charactersIgnoringModifiers: "\u{1b}",
				isARepeat: false,
				keyCode: 53
			)
		)

		window.sendEvent(escapeEvent)

		XCTAssertFalse(moveCalled)
		XCTAssertFalse(list.isReordering())
		XCTAssertEqual(list.currentVisualOrder(), [0, 1, 2])
		list.flushPendingDropResetForTesting()
	}

	func testReorderableListPendingPressTakesFirstResponderSoEscapeCancelsBeforeDragBegins() throws {
		var moveCalled = false
		let list = makeList(
			items: [0, 1, 2],
			handleWidth: nil,
			onMove: { _, _ in
				moveCalled = true
			}
		)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		let window = NSWindow(
			contentRect: list.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = list
		list.layoutSubtreeIfNeeded()

		let mouseDownEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDown,
				location: list.convert(NSPoint(x: 20, y: 20), to: nil as NSView?),
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 0,
				clickCount: 1,
				pressure: 1
			)
		)
		let mouseDraggedEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDragged,
				location: list.convert(NSPoint(x: 20, y: 100), to: nil as NSView?),
				modifierFlags: [],
				timestamp: 0.1,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 1,
				clickCount: 1,
				pressure: 1
			)
		)
		let escapeEvent = try XCTUnwrap(
			NSEvent.keyEvent(
				with: .keyDown,
				location: .zero,
				modifierFlags: [],
				timestamp: 0.05,
				windowNumber: window.windowNumber,
				context: nil,
				characters: "\u{1b}",
				charactersIgnoringModifiers: "\u{1b}",
				isARepeat: false,
				keyCode: 53
			)
		)

		list.mouseDown(with: mouseDownEvent)

		XCTAssertTrue(list.hasPendingPressForTesting())
		XCTAssertTrue(window.firstResponder === list)

		window.firstResponder?.keyDown(with: escapeEvent)

		XCTAssertFalse(list.hasPendingPressForTesting())
		XCTAssertFalse(list.isReordering())

		list.mouseDragged(with: mouseDraggedEvent)

		XCTAssertFalse(moveCalled)
		XCTAssertFalse(list.hasPendingPressForTesting())
		XCTAssertFalse(list.isReordering())
		XCTAssertEqual(list.currentVisualOrder(), [0, 1, 2])
	}

	func testReorderableListEscapeWithoutActiveDragLeavesListUntouched() {
		let list = makeList(items: [0, 1, 2], handleWidth: nil)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		list.layoutSubtreeIfNeeded()
		let initialFrames = (0..<3).map { list.containerFrame(for: $0) }

		XCTAssertTrue(list.acceptsFirstResponder)
		list.cancelOperation(nil)

		XCTAssertFalse(list.isReordering())
		XCTAssertEqual(list.currentVisualOrder(), [0, 1, 2])
		XCTAssertEqual((0..<3).map { list.containerFrame(for: $0) }, initialFrames)
	}

	func testReorderableListEscapeDuringPendingResetDoesNotEndDragEarlyOrTwice() {
		let observerRow = DragObserverRowView(height: 40)
		var moveCalled = false
		let list = ReorderableListView(
			items: [0],
			id: \.self,
			contentInsets: NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0),
			rowBackgroundColor: .windowBackgroundColor,
			onMove: { _, _ in
				moveCalled = true
			},
			contentViewBuilder: { _ in observerRow }
		)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 80)
		let window = NSWindow(
			contentRect: list.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = list
		list.layoutSubtreeIfNeeded()

		list.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)
		list.cancelOperation(nil as Any?)

		XCTAssertEqual(observerRow.beginCount, 1)
		XCTAssertTrue(observerRow.endCancelledStates.isEmpty)
		XCTAssertFalse(moveCalled)
		XCTAssertFalse(list.isReordering())

		list.cancelOperation(nil as Any?)

		XCTAssertTrue(observerRow.endCancelledStates.isEmpty)
		XCTAssertFalse(moveCalled)
		XCTAssertEqual(list.currentVisualOrder(), [0])

		list.flushPendingDropResetForTesting()

		XCTAssertEqual(observerRow.endCancelledStates, [true])
	}

	func testReorderableListMouseDownDuringPendingDropResetDoesNotStartAnotherPress() throws {
		let list = makeList(items: [0, 1, 2], handleWidth: nil)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		let window = NSWindow(
			contentRect: list.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = list
		list.layoutSubtreeIfNeeded()
		let mouseDownEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDown,
				location: list.convert(NSPoint(x: 20, y: 20), to: nil as NSView?),
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 0,
				clickCount: 1,
				pressure: 1
			)
		)

		list.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)
		list.endDragForTesting(cancelled: true)
		list.mouseDown(with: mouseDownEvent)

		XCTAssertFalse(list.hasPendingPressForTesting())
		XCTAssertFalse(list.isReordering())
		XCTAssertEqual(list.currentVisualOrder(), [0, 1, 2])

		list.flushPendingDropResetForTesting()
	}

	func testReorderableListEndingWithoutMovementDoesNotCallOnMove() {
		var moveCalled = false
		let list = makeList(
			items: [0, 1, 2],
			onMove: { _, _ in
				moveCalled = true
			}
		)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		list.layoutSubtreeIfNeeded()

		list.beginDragForTesting(
			sourceIndex: 1,
			locationInContent: NSPoint(x: 260, y: 60)
		)
		list.endDragForTesting(cancelled: false)

		XCTAssertFalse(moveCalled)
		XCTAssertEqual(list.currentVisualOrder(), [0, 1, 2])
		XCTAssertFalse(list.isReordering())
		list.flushPendingDropResetForTesting()
		XCTAssertFalse(list.isReordering())
	}

	func testReorderableListQueuesExternalUpdatesUntilDropEnds() {
		let list = makeList(items: [0, 1, 2])
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		list.layoutSubtreeIfNeeded()

		list.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 260, y: 20)
		)
		list.setItems([10, 11])

		XCTAssertEqual(list.currentVisualOrder(), [0, 1, 2])

		list.endDragForTesting(cancelled: true)

		XCTAssertEqual(list.currentVisualOrder(), [0, 1, 2])
		list.flushPendingDropResetForTesting()

		XCTAssertEqual(list.currentVisualOrder(), [0, 1])
		XCTAssertEqual(list.documentHeight(), 200)
	}

	func testReorderableListIncrementallyAppendsRowsWithoutRebuildingExistingContainers() {
		let list = makeList(items: [0, 1])
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		list.layoutSubtreeIfNeeded()

		let initialContainers = containers(in: list)
		let initialFrames = initialContainers.map(\.frame)
		list.appendItems([2, 3])
		let updatedContainers = containers(in: list)

		XCTAssertEqual(initialContainers.count, 2)
		XCTAssertEqual(updatedContainers.count, 4)
		XCTAssertTrue(updatedContainers[0] === initialContainers[0])
		XCTAssertTrue(updatedContainers[1] === initialContainers[1])
		XCTAssertEqual(updatedContainers.prefix(2).map(\.frame), initialFrames)
	}

	func testReorderableListSetItemsKeepsVisibleRowCountStableForStableIDs() {
		let list = makeList(items: [0, 1, 2], handleWidth: nil)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		list.layoutSubtreeIfNeeded()

		list.setItems([2, 1, 0])
		let updatedContainers = containers(in: list)

		XCTAssertEqual(updatedContainers.count, 3)
	}

	func testReorderableListSetItemsUpdatesVisibleRowCountForRemovedAndInsertedItems() {
		let list = makeList(items: [0, 1], handleWidth: nil)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		list.layoutSubtreeIfNeeded()

		list.setItems([1])
		list.setItems([1, 2])
		let updatedContainers = containers(in: list)

		XCTAssertEqual(updatedContainers.count, 2)
	}

	func testReorderableListKeepsBootstrapRowWidthNonZeroBeforeSizing() {
		let list = makeList(items: [0])
		list.frame = .zero
		list.layoutSubtreeIfNeeded()

		list.appendItems([1])
		let updatedContainers = containers(in: list)

		XCTAssertGreaterThan(containers(in: list).first?.frame.width ?? 0, 0)
		XCTAssertGreaterThan(updatedContainers.last?.frame.width ?? 0, 0)
	}

	func testReorderableListResetsDraggedRowStylingWhileKeepingLandingElevationUntilDropResetCompletes() {
		let list = makeList(items: [0, 1, 2], handleWidth: nil)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		list.layoutSubtreeIfNeeded()
		let container = firstContainer(in: list)

		list.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)
		list.updateDragForTesting(locationInContent: NSPoint(x: 20, y: 100))
		list.endDragForTesting(cancelled: false)
		let rowView = list.rowViewForTesting(modelIndex: 0)

		XCTAssertFalse(container.cellState.isReordering)
		XCTAssertEqual(container.layer?.zPosition, 0)
		XCTAssertEqual(rowView?.layer?.zPosition, 10)

		list.flushPendingDropResetForTesting()

		XCTAssertFalse(container.cellState.isReordering)
		XCTAssertEqual(container.layer?.zPosition, 0)
		XCTAssertEqual(rowView?.layer?.zPosition, 0)
	}

	func testReorderableListScheduledDropResetCompletesOnRunLoop() {
		let list = makeList(items: [0, 1, 2], handleWidth: nil)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		list.layoutSubtreeIfNeeded()

		list.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)
		list.endDragForTesting(cancelled: true)

		XCTAssertFalse(list.isReordering())

		RunLoop.current.run(
			until: Date(
				timeIntervalSinceNow: ReorderableListStyle.animationDuration + 0.05
			)
		)

		XCTAssertFalse(list.isReordering())
	}

	func testReorderableListNotifiesDraggedContentViewWhenDragBeginsAndEnds() {
		let observerRow = DragObserverRowView(height: 40)
		let list = ReorderableListView(
			items: [0],
			id: \.self,
			contentInsets: NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0),
			rowBackgroundColor: .windowBackgroundColor,
			onMove: { _, _ in },
			contentViewBuilder: { _ in observerRow }
		)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 80)
		list.layoutSubtreeIfNeeded()

		list.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)
		list.endDragForTesting(cancelled: true)

		XCTAssertEqual(observerRow.beginCount, 1)
		XCTAssertTrue(observerRow.endCancelledStates.isEmpty)

		list.flushPendingDropResetForTesting()

		XCTAssertEqual(observerRow.endCancelledStates, [true])
	}

	func testReorderableListFullRowDragStartsImmediatelyWithoutHandle() throws {
		let list = makeList(items: [0, 1, 2])
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		let window = NSWindow(
			contentRect: list.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = list
		list.layoutSubtreeIfNeeded()
		let container = try XCTUnwrap(list.containerViewForTesting(row: 0))
		_ = container
		list.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)
		list.updateDragForTesting(locationInContent: NSPoint(x: 20, y: 100))

		XCTAssertTrue(list.isReordering())
		XCTAssertEqual(list.currentVisualOrder(), [1, 0, 2])
	}

	func testReorderableListMouseUpCompletesActiveDragAndFallsBackWhenIdle() throws {
		var moves = [(IndexSet, Int)]()
		let list = makeList(
			items: [0, 1, 2],
			handleWidth: nil,
			onMove: { source, destination in
				moves.append((source, destination))
			}
		)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		let window = NSWindow(
			contentRect: list.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = list
		list.layoutSubtreeIfNeeded()
		let mouseUpEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseUp,
				location: list.convert(NSPoint(x: 20, y: 120), to: nil as NSView?),
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 0,
				clickCount: 1,
				pressure: 1
			)
		)

		list.mouseUp(with: mouseUpEvent)
		XCTAssertFalse(list.isReordering())

		list.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)
		list.updateDragForTesting(locationInContent: NSPoint(x: 20, y: 100))
		list.mouseUp(with: mouseUpEvent)

		XCTAssertFalse(list.isReordering())
		XCTAssertEqual(moves.count, 1)
		XCTAssertEqual(moves.first?.0, IndexSet(integer: 0))
		XCTAssertEqual(moves.first?.1, 2)
		list.flushPendingDropResetForTesting()
		XCTAssertFalse(list.isReordering())
	}

	func testReorderableListIndexOfContainerMatchesRowFrames() {
		let list = makeList(items: [0, 1, 2], handleWidth: nil)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		list.layoutSubtreeIfNeeded()

		XCTAssertEqual(list.indexOfContainerForTesting(at: NSPoint(x: 20, y: 20)), 0)
		XCTAssertEqual(list.indexOfContainerForTesting(at: NSPoint(x: 20, y: 60)), 1)
		XCTAssertNil(list.indexOfContainerForTesting(at: NSPoint(x: 20, y: 220)))
	}

	func testReorderableListVisibleFirstRowContentMapsBackToSourceIndex() throws {
		let rowViews = [
			FixedHeightView(height: 40),
			FixedHeightView(height: 40),
			FixedHeightView(height: 40),
		]
		let list = ReorderableListView(
			items: Array(rowViews.indices),
			id: \.self,
			contentInsets: NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0),
			rowBackgroundColor: .windowBackgroundColor,
			onMove: { _, _ in },
			contentViewBuilder: { rowViews[$0] }
		)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		let window = NSWindow(
			contentRect: list.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = list
		list.layoutSubtreeIfNeeded()

		let container = try XCTUnwrap(list.containerViewForTesting(row: 0))

		XCTAssertTrue(container.contentView === rowViews[0])
		XCTAssertEqual(list.sourceIndexForTesting(for: rowViews[0]), 0)
	}

	func testReorderableListFullRowDragDoesNotStartFromControl() throws {
		let list = ReorderableListView(
			items: [0],
			id: \.self,
			contentInsets: NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0),
			rowBackgroundColor: .windowBackgroundColor,
			onMove: { _, _ in },
			contentViewBuilder: { _ in ControlRowView(frame: .zero) }
		)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 80)
		let window = NSWindow(
			contentRect: list.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = list
		list.layoutSubtreeIfNeeded()
		let container = try XCTUnwrap(list.containerViewForTesting(row: 0))
		let controlRow = try XCTUnwrap(container.contentView as? ControlRowView)
		controlRow.layoutSubtreeIfNeeded()
		let buttonCenterInContainer = container.convert(
			NSPoint(
				x: controlRow.button.bounds.midX,
				y: controlRow.button.bounds.midY
			),
			from: controlRow.button
		)
		let mouseDownEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDown,
				location: container.convert(buttonCenterInContainer, to: nil as NSView?),
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 0,
				clickCount: 1,
				pressure: 1
			)
		)
		let mouseDraggedEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDragged,
				location: container.convert(
					NSPoint(x: buttonCenterInContainer.x + 20, y: buttonCenterInContainer.y + 20),
					to: nil as NSView?
				),
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 1,
				clickCount: 1,
				pressure: 1
			)
		)

		container.mouseDown(with: mouseDownEvent)
		container.mouseDragged(with: mouseDraggedEvent)

		XCTAssertFalse(list.isReordering())
	}

	func testReorderableListFullRowDragStartsWhenMovementExceedsThreshold() throws {
		let list = makeList(items: [0, 1, 2])
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		let window = NSWindow(
			contentRect: list.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = list
		list.layoutSubtreeIfNeeded()
		let container = try XCTUnwrap(list.containerViewForTesting(row: 0))
		_ = container
		list.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)
		list.updateDragForTesting(locationInContent: NSPoint(x: 40, y: 40))

		XCTAssertTrue(list.isReordering())
	}

	func testReorderableListMouseDraggedStartsPendingPressWhenThresholdIsExceeded() throws {
		let list = makeList(items: [0, 1, 2])
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		let window = NSWindow(
			contentRect: list.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = list
		list.layoutSubtreeIfNeeded()
		let mouseDraggedEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDragged,
				location: list.convert(NSPoint(x: 40, y: 40), to: nil as NSView?),
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 0,
				clickCount: 1,
				pressure: 1
			)
		)

		list.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)
		list.mouseDragged(with: mouseDraggedEvent)

		XCTAssertFalse(list.hasPendingPressForTesting())
		XCTAssertTrue(list.isReordering())
	}

	func testReorderableListMouseDraggedStartsOnceDefaultDragSlopIsExceeded() throws {
		let list = makeList(items: [0, 1, 2])
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		let window = NSWindow(
			contentRect: list.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = list
		list.layoutSubtreeIfNeeded()
		let mouseDownEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDown,
				location: list.convert(NSPoint(x: 20, y: 20), to: nil as NSView?),
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 0,
				clickCount: 1,
				pressure: 1
			)
		)
		let mouseDraggedEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDragged,
				location: list.convert(NSPoint(x: 26, y: 20), to: nil as NSView?),
				modifierFlags: [],
				timestamp: 0.1,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 1,
				clickCount: 1,
				pressure: 1
			)
		)

		list.mouseDown(with: mouseDownEvent)
		XCTAssertTrue(list.hasPendingPressForTesting())

		list.mouseDragged(with: mouseDraggedEvent)

		XCTAssertTrue(list.isReordering())
		XCTAssertFalse(list.hasPendingPressForTesting())
	}

	func testReorderableListContainerMouseEventsForwardIntoDragLifecycle() throws {
		let list = makeList(items: [0, 1])
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 120)
		let window = NSWindow(
			contentRect: list.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = list
		list.layoutSubtreeIfNeeded()

		let container = try XCTUnwrap(list.containerViewForTesting(row: 0))
		XCTAssertTrue(container.eventForwardingView === list)
		let mouseDownEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDown,
				location: container.convert(NSPoint(x: 20, y: 20), to: nil as NSView?),
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 0,
				clickCount: 1,
				pressure: 1
			)
		)
		let mouseDraggedEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDragged,
				location: container.convert(NSPoint(x: 20, y: 100), to: nil as NSView?),
				modifierFlags: [],
				timestamp: 0.1,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 1,
				clickCount: 1,
				pressure: 1
			)
		)
		container.mouseDown(with: mouseDownEvent)
		XCTAssertTrue(list.hasPendingPressForTesting())
		container.mouseDragged(with: mouseDraggedEvent)
		XCTAssertTrue(list.isReordering())
		list.endDragForTesting(cancelled: true)
	}

	func testReorderableListTestingHelpersCoverPendingPressStates() {
		let list = makeList(items: [0, 1, 2], handleWidth: nil)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		list.layoutSubtreeIfNeeded()

		list.installPendingPressForTesting(
			sourceIndex: 0,
			locationInSelf: nil
		)
		XCTAssertTrue(list.hasPendingPressForTesting())

		list.installPendingPressForTesting(
			sourceIndex: nil,
			locationInSelf: NSPoint(x: 20, y: 20)
		)
		XCTAssertTrue(list.hasPendingPressForTesting())

		list.installPendingPressForTesting(
			sourceIndex: nil,
			locationInSelf: nil
		)
		XCTAssertFalse(list.hasPendingPressForTesting())

		list.installPendingPressForTesting(
			sourceIndex: 0,
			locationInSelf: NSPoint(x: 20, y: 20)
		)
		list.installPendingPressForTesting(
			sourceIndex: 0,
			locationInSelf: NSPoint(x: 20, y: 20)
		)
		XCTAssertTrue(list.hasPendingPressForTesting())
		list.installPendingPressForTesting(
			sourceIndex: nil,
			locationInSelf: nil
		)

		XCTAssertFalse(list.hasPendingPressForTesting())
	}

	func testReorderableListBeginPendingDragWithoutValidPendingStateDoesNotStartDrag() {
		let list = makeList(items: [0, 1, 2], handleWidth: nil)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		list.layoutSubtreeIfNeeded()

		list.beginPendingDragForTesting()
		XCTAssertFalse(list.isReordering())

		list.installPendingPressForTesting(
			sourceIndex: -1,
			locationInSelf: NSPoint(x: 20, y: 20)
		)
		list.beginPendingDragForTesting()

		XCTAssertFalse(list.isReordering())
		XCTAssertFalse(list.hasPendingPressForTesting())
	}

	func testReorderableListBeginPendingDragWhileAlreadyDraggingClearsPendingPress() {
		let list = makeList(items: [0, 1, 2], handleWidth: nil)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		list.layoutSubtreeIfNeeded()
		list.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)
		list.installPendingPressForTesting(
			sourceIndex: 1,
			locationInSelf: NSPoint(x: 20, y: 60)
		)

		list.beginPendingDragForTesting()

		XCTAssertTrue(list.isReordering())
		XCTAssertFalse(list.hasPendingPressForTesting())
	}

	func testReorderableListBeginPendingDragStartsWhenContainerHitTestReturnsNil() {
		let list = makeList(items: [0], handleWidth: nil)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 80)
		list.layoutSubtreeIfNeeded()
		list.installPendingPressForTesting(
			sourceIndex: 0,
			locationInSelf: NSPoint(x: 20, y: 200)
		)

		list.beginPendingDragForTesting()

		XCTAssertTrue(list.isReordering())
	}

	func testReorderableListHandlelessContainerAllowsDragInitiation() {
		let list = makeList(items: [0])
		let container = ReorderableListItemContainerView(
			contentView: FixedHeightView(height: 40),
			backgroundColor: .windowBackgroundColor
		)

		XCTAssertTrue(list.shouldBeginContainerDragForTesting(from: container))
	}

	func testReorderableListViewWillMoveCancelsPendingPressAndActiveDrag() throws {
		let list = makeList(items: [0, 1, 2])
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		let window = NSWindow(
			contentRect: list.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = list
		list.layoutSubtreeIfNeeded()
		let container = try XCTUnwrap(list.containerViewForTesting(row: 0))
		let mouseDownEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDown,
				location: container.convert(NSPoint(x: 20, y: 20), to: nil as NSView?),
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 0,
				clickCount: 1,
				pressure: 1
			)
		)
		container.mouseDown(with: mouseDownEvent)
		list.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)
		XCTAssertTrue(list.isReordering())

		list.viewWillMove(toWindow: nil)

		XCTAssertFalse(list.hasPendingPressForTesting())
		XCTAssertFalse(list.isReordering())
	}

	func testReorderableListPublicInitializerRequiresDragSlopBeforeStartingDrag() throws {
		let list = makeList(items: [0, 1, 2], handleWidth: nil)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		let window = NSWindow(
			contentRect: list.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = list
		list.layoutSubtreeIfNeeded()

		let mouseDown = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDown,
				location: list.convert(NSPoint(x: 20, y: 20), to: nil as NSView?),
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 0,
				clickCount: 1,
				pressure: 1
			)
		)
		let slightDrag = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDragged,
				location: list.convert(NSPoint(x: 22, y: 21), to: nil as NSView?),
				modifierFlags: [],
				timestamp: 0.05,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 1,
				clickCount: 1,
				pressure: 1
			)
		)
		let mouseUp = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseUp,
				location: list.convert(NSPoint(x: 22, y: 21), to: nil as NSView?),
				modifierFlags: [],
				timestamp: 0.1,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 2,
				clickCount: 1,
				pressure: 1
			)
		)

		list.mouseDown(with: mouseDown)
		XCTAssertTrue(list.hasPendingPressForTesting())

		list.mouseDragged(with: slightDrag)

		XCTAssertFalse(list.isReordering())
		XCTAssertTrue(list.hasPendingPressForTesting())

		list.mouseUp(with: mouseUp)

		XCTAssertFalse(list.isReordering())
		XCTAssertFalse(list.hasPendingPressForTesting())
		XCTAssertEqual(list.currentVisualOrder(), [0, 1, 2])
	}

	func testReorderableListViewForwardingAPIsAndInitializers() throws {
		var moveRecords = [MoveRecord]()
		var moveEndRecords = [MoveRecord]()
		var interactionFinishCount = 0
		let configuredList = ReorderableListView(
			items: [0, 1, 2],
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0),
				rowSpacing: 4,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { source, destination in
					moveRecords.append(MoveRecord(source: source.first ?? -1, destination: destination))
				},
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: { source, destination in
					moveEndRecords.append(MoveRecord(source: source, destination: destination))
				},
				onReorderInteractionDidFinish: {
					interactionFinishCount += 1
				},
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 0,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			)
		)
		configuredList.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		let window = NSWindow(
			contentRect: configuredList.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = configuredList
		let responderSpy = ResponderSpy()
		configuredList.nextResponder = responderSpy
		configuredList.layoutSubtreeIfNeeded()

		let fixedHeightList = ReorderableListView(
			items: [0],
			id: \.self,
			contentInsets: NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0),
			rowBackgroundColor: .windowBackgroundColor,
			fixedRowHeight: 44,
			onMove: { _, _ in },
			contentViewBuilder: { _ in FixedHeightView(height: 44) }
		)
		fixedHeightList.frame = CGRect(x: 0, y: 0, width: 200, height: 120)
		fixedHeightList.layoutSubtreeIfNeeded()
		XCTAssertEqual(fixedHeightList.containerFrame(for: 0).height, 44)

		XCTAssertTrue(configuredList.acceptsFirstResponder)
		XCTAssertTrue(configuredList.isFlipped)
		XCTAssertEqual(configuredList.performanceMetrics.overlayUpdates, 0)
		XCTAssertFalse(configuredList.hasTransientReorderState)

		configuredList.updateCanMove { $0 != 2 }
		configuredList.updateSelectedItemID(1)
		XCTAssertTrue(configuredList.moveSelectedItem(direction: 1))
		XCTAssertEqual(moveRecords.last, MoveRecord(source: 1, destination: 3))
		XCTAssertEqual(moveEndRecords.last, MoveRecord(source: 1, destination: 3))

		configuredList.updateMoveAction { source, destination in
			moveRecords.append(MoveRecord(source: source.first ?? -1, destination: destination))
		}
		configuredList.updateMoveLifecycleHandlers(
			onMoveStart: { _, _ in },
			onMoveUpdate: { _, _ in },
			onMoveEnd: { source, destination in
				moveEndRecords.append(MoveRecord(source: source, destination: destination))
			}
		)
		configuredList.updateReorderInteractionDidFinish {
			interactionFinishCount += 1
		}

		let moveUpEvent = try XCTUnwrap(
			NSEvent.keyEvent(
				with: .keyDown,
				location: .zero,
				modifierFlags: [.command, .option],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				characters: "\u{F700}",
				charactersIgnoringModifiers: "\u{F700}",
				isARepeat: false,
				keyCode: 126
			)
		)
		XCTAssertTrue(configuredList.handleKeyDown(moveUpEvent))
		configuredList.keyDown(with: moveUpEvent)

		configuredList.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)
		XCTAssertTrue(configuredList.hasTransientReorderState)
		XCTAssertNotNil(configuredList.rowPresentationFrameForTesting(modelIndex: 0))
		configuredList.cancelOperation(nil)
		configuredList.cancelOperation(nil)
		XCTAssertEqual(responderSpy.cancelOperationCount, 0)
		configuredList.flushPendingDropResetForTesting()
		XCTAssertGreaterThanOrEqual(interactionFinishCount, 1)

		configuredList.cancelOperation(nil)
		XCTAssertEqual(responderSpy.cancelOperationCount, 1)
		configuredList.viewWillMove(toWindow: nil)
	}

	func testReorderableListViewKeyboardAndTestingHooksCoverWrapperPaths() throws {
		var announcements = [String]()
		let list = ReorderableListView(
			items: [0, 1, 2],
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0),
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: true,
				accessibilityAnnouncementHandler: { announcement in
					announcements.append(announcement)
				},
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 0,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			)
		)
		list.frame = CGRect(x: 0, y: 0, width: 240, height: 120)
		list.layoutSubtreeIfNeeded()
		list.setAccessibilityAnnouncementHandlerForTesting { announcement in
			announcements.append(announcement)
		}
		XCTAssertFalse(list.autoscrollIsActiveForTesting())
		XCTAssertFalse(list.handleAutoscrollTickForTesting())
		XCTAssertEqual(list.scrollOffsetYForTesting(), 0)
		list.updateSelectedItemID(0)
		let downEvent = try XCTUnwrap(
			NSEvent.keyEvent(
				with: .keyDown,
				location: .zero,
				modifierFlags: [.command, .option],
				timestamp: 0,
				windowNumber: 0,
				context: nil,
				characters: "\u{F701}",
				charactersIgnoringModifiers: "\u{F701}",
				isARepeat: false,
				keyCode: 125
			)
		)

		list.keyDown(with: downEvent)

		XCTAssertEqual(list.currentVisualOrder(), [1, 0, 2])
		XCTAssertTrue(
			announcements.contains(reorderableListCompletedAnnouncement(from: 1, to: 2))
		)
	}

	func testReorderableListFixedHeightInitializerAndHelperFallbackBranches() {
		_ = NSApplication.shared

		let list = ReorderableListView(
			items: [0, 1],
			id: \.self,
			contentInsets: NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0),
			rowSpacing: 0,
			rowBackgroundColor: .windowBackgroundColor,
			fixedRowHeight: 40,
			onMove: { _, _ in },
			contentViewBuilder: { _ in FixedHeightView(height: 40) }
		)
		list.frame = CGRect(x: 0, y: 0, width: 220, height: 120)
		let window = NSWindow(
			contentRect: list.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = list
		list.layoutSubtreeIfNeeded()

		XCTAssertNil(list.rowFrameForTesting(modelIndex: -1))
		XCTAssertNil(list.rowPresentationFrameForTesting(modelIndex: 0))

		list.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)
		list.endDragForTesting(cancelled: true)
		list.flushPendingDropResetForTesting()

		let standaloneScrollView = ReorderableListScrollView(
			frame: CGRect(x: 0, y: 0, width: 160, height: 80)
		)
		let standaloneClipView = ReorderableListClipView(frame: standaloneScrollView.bounds)
		standaloneScrollView.contentView = standaloneClipView
		XCTAssertNotNil(standaloneScrollView.hitTest(NSPoint(x: 12, y: 12)))
		XCTAssertNotNil(standaloneClipView.hitTest(NSPoint(x: 12, y: 12)))

		let placeholderView = ReorderableListDragPlaceholderView(frame: .zero)
		XCTAssertNil(placeholderView.strokeColorForTesting)
		XCTAssertEqual(
			placeholderView.dashPatternForTesting,
			ReorderableListStyle.dragPlaceholderDashPattern
		)

		let rowView = ReorderableListRowView(frame: CGRect(x: 0, y: 0, width: 160, height: 40))
		let fallbackSubview = NonHittingView(height: 20)
		fallbackSubview.frame = CGRect(x: 12, y: 10, width: 40, height: 20)
		rowView.addSubview(fallbackSubview)
		XCTAssertTrue(rowView.hitTest(NSPoint(x: 120, y: 20)) === rowView)
	}

	func testListHelperViewsRouteHitTestingToNestedContent() throws {
		let list = makeList(items: [0])
		list.frame = CGRect(x: 0, y: 0, width: 240, height: 120)
		let window = NSWindow(
			contentRect: list.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = list
		list.layoutSubtreeIfNeeded()

		let scrollView = try XCTUnwrap(list.subviews.compactMap { $0 as? ReorderableListScrollView }.first)
		let clipView = try XCTUnwrap(scrollView.contentView as? ReorderableListClipView)
		let documentView = try XCTUnwrap(scrollView.documentView as? ReorderableListDocumentView)
		let tableView = try XCTUnwrap(
			documentView.subviews.first(where: { $0 is ReorderableListTableView }) as? ReorderableListTableView
		)
		let rowView = try XCTUnwrap(list.rowViewForTesting(modelIndex: 0))
		let container = try XCTUnwrap(list.containerViewForTesting(row: 0))
		let pointInList = NSPoint(x: 20, y: 20)

		XCTAssertNil(scrollView.hitTest(NSPoint(x: -1, y: -1)))
		XCTAssertNotNil(scrollView.hitTest(scrollView.convert(pointInList, from: list)))
		XCTAssertNil(clipView.hitTest(NSPoint(x: -1, y: -1)))
		XCTAssertNotNil(clipView.hitTest(clipView.convert(pointInList, from: list)))
		XCTAssertNotNil(tableView.hitTest(tableView.convert(pointInList, from: list)))
		XCTAssertNotNil(rowView.hitTest(rowView.convert(pointInList, from: list)))
		XCTAssertTrue(container.eventForwardingView === list)

		let placeholderView = ReorderableListDragPlaceholderView(frame: .zero)
		XCTAssertFalse(placeholderView.isOpaque)

		let overlayHostView = ReorderableTableOverlayHostView(frame: .zero)
		XCTAssertFalse(overlayHostView.isOpaque)
		XCTAssertNil(overlayHostView.hitTest(.zero))
	}

	func testStandaloneHelperViewsCoverFallbackHitTestingBranches() {
		let scrollView = ReorderableListScrollView(frame: CGRect(x: 0, y: 0, width: 160, height: 80))
		let clipView = ReorderableListClipView(frame: scrollView.bounds)
		let documentView = NonHittingView(height: 80)
		documentView.frame = scrollView.bounds
		scrollView.contentView = clipView
		scrollView.documentView = documentView

		XCTAssertNotNil(scrollView.hitTest(NSPoint(x: 20, y: 20)))
		XCTAssertNotNil(clipView.hitTest(NSPoint(x: 20, y: 20)))

		let tableView = ReorderableListTableView(frame: CGRect(x: 0, y: 0, width: 160, height: 80))
		XCTAssertNil(tableView.hitTest(NSPoint(x: -1, y: -1)))
		_ = tableView.hitTest(NSPoint(x: 20, y: 20))
		tableView.drawBackground(inClipRect: tableView.bounds)

		let rowView = ReorderableListRowView(frame: CGRect(x: 0, y: 0, width: 160, height: 40))
		let fallbackSubview = NonHittingView(height: 20)
		fallbackSubview.frame = CGRect(x: 20, y: 10, width: 40, height: 20)
		rowView.addSubview(fallbackSubview)
		rowView.drawBackground(in: rowView.bounds)

		XCTAssertTrue(rowView.hitTest(NSPoint(x: 30, y: 20)) === fallbackSubview)
	}

	func testTableViewHitTestFallsBackToContainerWhenPointMissesInsetContentBounds() throws {
		let list = ReorderableListView(
			items: [0, 1],
			id: \.self,
			contentInsets: NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0),
			rowSpacing: 5,
			rowBackgroundColor: .windowBackgroundColor,
			fixedRowHeight: 40,
			onMove: { _, _ in },
			contentViewBuilder: { _ in FixedHeightView(height: 40) }
		)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
		list.layoutSubtreeIfNeeded()

		let scrollView = try XCTUnwrap(list.subviews.compactMap { $0 as? ReorderableListScrollView }.first)
		let documentView = try XCTUnwrap(scrollView.documentView as? ReorderableListDocumentView)
		let tableView = try XCTUnwrap(
			documentView.subviews.first(where: { $0 is ReorderableListTableView }) as? ReorderableListTableView
		)
		let container = try XCTUnwrap(list.containerViewForTesting(row: 0))
		let candidateYPositions = stride(from: container.frame.maxY, through: container.frame.maxY + 5, by: 0.25)
		let pointInTable = try XCTUnwrap(
			candidateYPositions
				.map { NSPoint(x: container.frame.midX, y: $0) }
				.first { point in
					tableView.row(at: point) == 0
						&& container.hitTest(container.convert(point, from: tableView)) == nil
				}
		)

		XCTAssertTrue(tableView.hitTest(pointInTable) === container)
	}

	func testItemContainerFallbackHitTestingAndResponderForwarding() throws {
		let content = NonHittingView(height: 40)
		let container = ReorderableListItemContainerView(
			contentView: content,
			backgroundColor: .windowBackgroundColor
		)
		container.frame = CGRect(x: 0, y: 0, width: 160, height: 40)
		container.layoutSubtreeIfNeeded()

		XCTAssertTrue(container.hitTest(NSPoint(x: 12, y: 12)) === container)

		let forwardingView = ForwardingView(frame: .zero)
		container.nextResponder = forwardingView
		container.eventForwardingView = nil
		let mouseDown = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDown,
				location: .zero,
				modifierFlags: [],
				timestamp: 0,
				windowNumber: 0,
				context: nil,
				eventNumber: 0,
				clickCount: 1,
				pressure: 1
			)
		)
		let mouseDragged = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDragged,
				location: .zero,
				modifierFlags: [],
				timestamp: 0.1,
				windowNumber: 0,
				context: nil,
				eventNumber: 1,
				clickCount: 1,
				pressure: 1
			)
		)
		let mouseUp = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseUp,
				location: .zero,
				modifierFlags: [],
				timestamp: 0.2,
				windowNumber: 0,
				context: nil,
				eventNumber: 2,
				clickCount: 1,
				pressure: 1
			)
		)
		let escapeEvent = try XCTUnwrap(
			NSEvent.keyEvent(
				with: .keyDown,
				location: .zero,
				modifierFlags: [],
				timestamp: 0.3,
				windowNumber: 0,
				context: nil,
				characters: "\u{1b}",
				charactersIgnoringModifiers: "\u{1b}",
				isARepeat: false,
				keyCode: 53
			)
		)

		container.mouseDown(with: mouseDown)
		container.mouseDragged(with: mouseDragged)
		container.mouseUp(with: mouseUp)
		container.keyDown(with: escapeEvent)
		container.cancelOperation(nil)

		XCTAssertEqual(forwardingView.mouseDownCount, 1)
		XCTAssertEqual(forwardingView.mouseDraggedCount, 1)
		XCTAssertEqual(forwardingView.mouseUpCount, 1)
		XCTAssertEqual(forwardingView.keyDownCount, 1)
		XCTAssertEqual(forwardingView.cancelOperationCount, 1)
	}

	func testReorderableListControllerDirectCoverageForKeyboardQueuedUpdatesAndInvalidRows() throws {
		var announcements = [String]()
		var moves = [MoveRecord]()
		let harness = makeListControllerHarness(
			items: [0, 1, 2],
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0),
				rowSpacing: 5,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: true,
				accessibilityAnnouncementHandler: { announcement in
					announcements.append(announcement)
				},
				onMove: { source, destination in
					moves.append(MoveRecord(source: source.first ?? -1, destination: destination))
				},
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			)
		)
		let controller = harness.controller
		controller.updateCanMove { $0 != 2 }
		controller.updateSelectedItemID(2)
		controller.setAccessibilityAnnouncementHandlerForTesting { announcement in
			announcements.append(announcement)
		}

		XCTAssertFalse(controller.moveSelectedItem(direction: 1))
		XCTAssertFalse(controller.moveSelectedItem(direction: 0))
		XCTAssertFalse(controller.handleAutoscrollTickForTesting())
		XCTAssertFalse(controller.autoscrollIsActiveForTesting())
		XCTAssertEqual(controller.scrollOffsetYForTesting(), 0)
		XCTAssertNil(controller.tableView(NSTableView(), viewFor: nil, row: -1))
		XCTAssertEqual(controller.tableView(NSTableView(), heightOfRow: 99), 40)
		XCTAssertNil(controller.rowSettleAnimationDurationForTesting(modelIndex: 0))
		XCTAssertNil(controller.dragPresentationFrameForTesting(modelIndex: 0))

		controller.updateSelectedItemID(0)
		let defaultKeyEvent = try XCTUnwrap(
			NSEvent.keyEvent(
				with: .keyDown,
				location: .zero,
				modifierFlags: [.command, .option],
				timestamp: 0,
				windowNumber: 0,
				context: nil,
				characters: "",
				charactersIgnoringModifiers: "",
				isARepeat: false,
				keyCode: 124
			)
		)
		let downKeyEvent = try XCTUnwrap(
			NSEvent.keyEvent(
				with: .keyDown,
				location: .zero,
				modifierFlags: [.command, .option],
				timestamp: 0,
				windowNumber: 0,
				context: nil,
				characters: "\u{F701}",
				charactersIgnoringModifiers: "\u{F701}",
				isARepeat: false,
				keyCode: 125
			)
		)

		XCTAssertFalse(controller.handleKeyDown(defaultKeyEvent))
		XCTAssertTrue(controller.handleKeyDown(downKeyEvent))
		XCTAssertEqual(controller.currentVisualOrder(), [1, 0, 2])
		XCTAssertEqual(moves, [MoveRecord(source: 0, destination: 2)])
		XCTAssertTrue(
			announcements.contains(reorderableListCompletedAnnouncement(from: 1, to: 2))
		)

		controller.updateSelectedItemID(0)
		controller.setItems([0])
		XCTAssertFalse(controller.moveSelectedItem(direction: 1))

		controller.beginDragForTesting(sourceIndex: 0, locationInContent: NSPoint(x: 20, y: 20))
		XCTAssertTrue(controller.isReordering())
		controller.appendItems([9])
		controller.endDragForTesting(cancelled: true)
		controller.flushPendingDropResetForTesting()
		XCTAssertEqual(controller.numberOfRows(in: NSTableView()), 2)

		controller.beginDragForTesting(sourceIndex: 0, locationInContent: NSPoint(x: 20, y: 20))
		controller.setItems([7])
		XCTAssertTrue(controller.hasTransientReorderState())
		controller.flushPendingDropResetForTesting()
		XCTAssertEqual(controller.numberOfRows(in: NSTableView()), 1)
		XCTAssertEqual(controller.currentVisualOrder(), [0])
	}

	func testReorderableListControllerLongPressAutoscrollAndHandleGating() throws {
		let handleProviderHarness = makeListControllerHarness(
			items: [0],
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(),
				reorderHandleWidth: 40,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in
					HandleProvidingRowView(
						height: 40,
						reorderHandleRect: CGRect(x: 90, y: 0, width: 30, height: 40)
					)
				},
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			)
		)
		let handleProviderContainer = try XCTUnwrap(
			handleProviderHarness.controller.containerViewForTesting(row: 0)
		)
		let handleProviderOutsidePoint = handleProviderHarness.hostView.convert(
			NSPoint(x: 20, y: 20),
			from: handleProviderContainer
		)
		let handleProviderInsidePoint = handleProviderHarness.hostView.convert(
			NSPoint(x: 100, y: 20),
			from: handleProviderContainer
		)

		XCTAssertFalse(handleProviderHarness.controller.handleMouseDown(locationInSelf: handleProviderOutsidePoint))
		XCTAssertTrue(handleProviderHarness.controller.handleMouseDown(locationInSelf: handleProviderInsidePoint))
		XCTAssertTrue(handleProviderHarness.controller.handleMouseUp())

		let genericHandleHarness = makeListControllerHarness(
			items: Array(0..<20),
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: AutoscrollConfiguration(
					edgeZoneHeight: 56,
					minimumSpeed: 240,
					maximumSpeed: 960
				),
				reorderHandleWidth: 32,
				longPressDuration: 0.01,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			)
		)
		let controller = genericHandleHarness.controller
		let genericHandleContainer = try XCTUnwrap(
			controller.containerViewForTesting(row: 0)
		)
		let genericHandleOutsidePoint = genericHandleHarness.hostView.convert(
			NSPoint(x: 20, y: 20),
			from: genericHandleContainer
		)
		let genericHandleInsidePoint = genericHandleHarness.hostView.convert(
			NSPoint(x: genericHandleContainer.bounds.maxX - 16, y: 20),
			from: genericHandleContainer
		)

		XCTAssertFalse(controller.handleMouseDown(locationInSelf: genericHandleOutsidePoint))
		XCTAssertTrue(controller.handleMouseDown(locationInSelf: genericHandleInsidePoint))
		XCTAssertTrue(controller.hasPendingPressForTesting())
		XCTAssertTrue(
			controller.handleMouseDragged(
				locationInSelf: CGPoint(x: genericHandleInsidePoint.x + 2, y: genericHandleInsidePoint.y + 2)
			)
		)
		XCTAssertFalse(
			controller.handleMouseDragged(
				locationInSelf: CGPoint(x: genericHandleInsidePoint.x + 80, y: genericHandleInsidePoint.y + 100)
			)
		)
		XCTAssertFalse(controller.hasPendingPressForTesting())

		XCTAssertTrue(controller.handleMouseDown(locationInSelf: genericHandleInsidePoint))
		RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

		XCTAssertTrue(controller.isReordering())
		controller.updateDragForTesting(
			locationInContent: NSPoint(
				x: genericHandleContainer.bounds.midX,
				y: genericHandleHarness.tableView.bounds.maxY - 2
			)
		)
		XCTAssertTrue(controller.autoscrollIsActiveForTesting())
		let initialOffset = controller.scrollOffsetYForTesting()
		XCTAssertTrue(controller.handleAutoscrollTickForTesting())
		XCTAssertGreaterThan(controller.scrollOffsetYForTesting(), initialOffset)
		XCTAssertNotNil(controller.dragPresentationFrameForTesting(modelIndex: 0))
		XCTAssertTrue(controller.handleMouseUp())
		controller.flushPendingDropResetForTesting()
	}

	func testReorderableListControllerAdditionalInvalidAndPendingDragBranches() throws {
		let harness = makeListControllerHarness(
			items: [0, 1],
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(),
				reorderHandleWidth: 30,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			)
		)
		let controller = harness.controller
		let window = NSWindow(
			contentRect: harness.hostView.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = harness.hostView

		controller.updateSelectedItemID(0)
		XCTAssertFalse(controller.moveSelectedItem(direction: -1))
		XCTAssertEqual(controller.containerFrame(for: -1), .zero)
		XCTAssertNil(controller.dropIndicatorColorForTesting())
		XCTAssertNil(controller.dragPlaceholderViewForTesting())
		XCTAssertNil(controller.sourceIndexForTesting(for: NSView()))
		XCTAssertNil(controller.containerViewForTesting(row: -1))
		XCTAssertNil(controller.rowViewForTesting(modelIndex: -1))
		XCTAssertEqual(controller.documentHeight(), harness.tableView.enclosingScrollView?.documentView?.frame.height)
		XCTAssertFalse(controller.shouldBeginContainerDragForTesting(from: NSButton()))
		XCTAssertTrue(controller.shouldBeginContainerDragForTesting(from: nil))

		let plainKeyEvent = try XCTUnwrap(
			NSEvent.keyEvent(
				with: .keyDown,
				location: .zero,
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				characters: "",
				charactersIgnoringModifiers: "",
				isARepeat: false,
				keyCode: 125
			)
		)
		XCTAssertFalse(controller.handleKeyDown(plainKeyEvent))

		let container = try XCTUnwrap(controller.containerViewForTesting(row: 0))
		XCTAssertTrue(controller.shouldBeginContainerDragForTesting(from: container))

		let outsideHandlePoint = harness.hostView.convert(
			NSPoint(x: 20, y: 20),
			from: container
		)
		let insideHandlePoint = harness.hostView.convert(
			NSPoint(x: container.bounds.maxX - 10, y: 20),
			from: container
		)

		controller.installPendingPressForTesting(sourceIndex: 0, locationInSelf: outsideHandlePoint)
		controller.beginPendingDragForTesting()
		XCTAssertFalse(controller.isReordering())

		controller.updateCanMove { _ in false }
		controller.installPendingPressForTesting(sourceIndex: 0, locationInSelf: insideHandlePoint)
		controller.beginPendingDragForTesting()
		XCTAssertFalse(controller.isReordering())
		controller.updateCanMove(nil)

		controller.beginDragForTesting(sourceIndex: 0, locationInContent: NSPoint(x: 20, y: 20))
		controller.setItems([0, 9])
		XCTAssertTrue(controller.hasTransientReorderState())
		controller.endDragForTesting(cancelled: true)
		controller.flushPendingDropResetForTesting()
		XCTAssertEqual(controller.numberOfRows(in: NSTableView()), 2)

		let zeroBoundsHarness = makeListControllerHarness(
			items: [0],
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			)
		)
		zeroBoundsHarness.controller.rowViewForTesting(modelIndex: 0)?.frame = .zero
		zeroBoundsHarness.controller.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: .zero
		)
		XCTAssertFalse(zeroBoundsHarness.controller.isReordering())
	}

	func testReorderableListControllerEscapeMonitorCancelsActiveDrag() throws {
		var moveCalled = false
		var capturedEscapeMonitor: ((NSEvent) -> NSEvent?)?
		var removedMonitorCount = 0
		let harness = makeListControllerHarness(
			items: [0, 1, 2],
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0),
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in
					moveCalled = true
				},
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 0,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			),
			eventMonitoring: ReorderableListEventMonitoring(
				addLocalKeyDownMonitor: { handler in
					capturedEscapeMonitor = handler
					return NSObject()
				},
				addLocalLeftMouseUpMonitor: { _ in NSObject() },
				addLocalLeftMouseDraggedMonitor: { _ in NSObject() },
				removeMonitor: { _ in
					removedMonitorCount += 1
				}
			)
		)
		let controller = harness.controller
		let initialFrame = controller.containerFrame(for: 0)
		let window = NSWindow(
			contentRect: harness.hostView.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = harness.hostView

		controller.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)
		controller.updateDragForTesting(
			locationInContent: NSPoint(x: 220, y: 100)
		)

		let escapeMonitor = try XCTUnwrap(capturedEscapeMonitor)
		let escapeEvent = try XCTUnwrap(
			NSEvent.keyEvent(
				with: .keyDown,
				location: .zero,
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				characters: "\u{1b}",
				charactersIgnoringModifiers: "\u{1b}",
				isARepeat: false,
				keyCode: 53
			)
		)

		XCTAssertTrue(controller.isReordering())
		XCTAssertNotEqual(controller.currentVisualOrder(), [0, 1, 2])

		let handledEvent = escapeMonitor(escapeEvent)

		XCTAssertNil(handledEvent)
		XCTAssertFalse(moveCalled)
		XCTAssertFalse(controller.isReordering())
		XCTAssertEqual(controller.currentVisualOrder(), [0, 1, 2])
		XCTAssertNotNil(controller.rowSettleAnimationDurationForTesting(modelIndex: 0))
		XCTAssertEqual(removedMonitorCount, 3)

		controller.flushPendingDropResetForTesting()

		XCTAssertEqual(controller.containerFrame(for: 0), initialFrame)
	}

	func testReorderableListControllerEscapeMonitorReturnsEventWhenItDoesNotCancel() throws {
		var capturedEscapeMonitor: ((NSEvent) -> NSEvent?)?
		let harness = makeListControllerHarness(
			items: [0, 1, 2],
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 0,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			),
			eventMonitoring: ReorderableListEventMonitoring(
				addLocalKeyDownMonitor: { handler in
					capturedEscapeMonitor = handler
					return NSObject()
				},
				addLocalLeftMouseUpMonitor: { _ in NSObject() },
				addLocalLeftMouseDraggedMonitor: { _ in NSObject() },
				removeMonitor: { _ in }
			)
		)
		let controller = harness.controller
		let window = NSWindow(
			contentRect: harness.hostView.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = harness.hostView

		controller.beginDragForTesting(sourceIndex: 0, locationInContent: NSPoint(x: 20, y: 20))
		let escapeMonitor = try XCTUnwrap(capturedEscapeMonitor)
		let nonEscapeEvent = try XCTUnwrap(
			NSEvent.keyEvent(
				with: .keyDown,
				location: .zero,
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				characters: "a",
				charactersIgnoringModifiers: "a",
				isARepeat: false,
				keyCode: 0
			)
		)

		XCTAssertTrue(escapeMonitor(nonEscapeEvent) === nonEscapeEvent)
	}

	func testReorderableListControllerEscapeKeyCancelsPendingPressAndReturnsFalseWhenIdle() throws {
		let harness = makeListControllerHarness(
			items: [0, 1, 2],
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			)
		)
		let controller = harness.controller
		let escapeEvent = try XCTUnwrap(
			NSEvent.keyEvent(
				with: .keyDown,
				location: .zero,
				modifierFlags: [],
				timestamp: 0,
				windowNumber: 0,
				context: nil,
				characters: "\u{1b}",
				charactersIgnoringModifiers: "\u{1b}",
				isARepeat: false,
				keyCode: 53
			)
		)

		controller.armPendingPressForTesting(
			sourceIndex: 0,
			locationInView: NSPoint(x: 20, y: 20)
		)
		XCTAssertTrue(controller.hasPendingPressForTesting())
		XCTAssertTrue(controller.handleKeyDown(escapeEvent))
		XCTAssertFalse(controller.hasPendingPressForTesting())
		XCTAssertFalse(controller.handleKeyDown(escapeEvent))
	}

	func testReorderableListControllerEscapeMonitorCancelsPendingPressBeforeDragBegins() throws {
		var capturedEscapeMonitor: ((NSEvent) -> NSEvent?)?
		var removedMonitorCount = 0
		let harness = makeListControllerHarness(
			items: [0, 1, 2],
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			),
			eventMonitoring: ReorderableListEventMonitoring(
				addLocalKeyDownMonitor: { handler in
					capturedEscapeMonitor = handler
					return NSObject()
				},
				addLocalLeftMouseUpMonitor: { _ in NSObject() },
				addLocalLeftMouseDraggedMonitor: { _ in NSObject() },
				removeMonitor: { _ in
					removedMonitorCount += 1
				}
			)
		)
		let controller = harness.controller
		let escapeEvent = try XCTUnwrap(
			NSEvent.keyEvent(
				with: .keyDown,
				location: .zero,
				modifierFlags: [],
				timestamp: 0,
				windowNumber: 0,
				context: nil,
				characters: "\u{1b}",
				charactersIgnoringModifiers: "\u{1b}",
				isARepeat: false,
				keyCode: 53
			)
		)

		controller.armPendingPressForTesting(
			sourceIndex: 0,
			locationInView: NSPoint(x: 20, y: 20)
		)
		controller.installEscapeMonitorForTesting()
		XCTAssertTrue(controller.hasPendingPressForTesting())
		let escapeMonitor = try XCTUnwrap(capturedEscapeMonitor)

		let handledEvent = escapeMonitor(escapeEvent)

		XCTAssertNil(handledEvent)
		XCTAssertFalse(controller.hasPendingPressForTesting())
		XCTAssertFalse(controller.isReordering())
		XCTAssertEqual(removedMonitorCount, 1)
	}

	func testReorderableListControllerMouseUpMonitorCommitsAutoscrolledDragUsingEventLocation() throws {
		var moves = [MoveRecord]()
		var capturedMouseUpMonitor: ((NSEvent) -> NSEvent?)?
		var capturedMouseDraggedMonitor: ((NSEvent) -> NSEvent?)?
		var removedMonitors = [ObjectIdentifier]()
		let harness = makeListControllerHarness(
			items: Array(0..<20),
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: AutoscrollConfiguration(
					edgeZoneHeight: 56,
					minimumSpeed: 240,
					maximumSpeed: 960
				),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { source, destination in
					moves.append(MoveRecord(source: source.first ?? -1, destination: destination))
				},
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			),
			eventMonitoring: ReorderableListEventMonitoring(
				addLocalKeyDownMonitor: { _ in NSObject() },
				addLocalLeftMouseUpMonitor: { handler in
					capturedMouseUpMonitor = handler
					return NSObject()
				},
				addLocalLeftMouseDraggedMonitor: { handler in
					capturedMouseDraggedMonitor = handler
					return NSObject()
				},
				removeMonitor: { monitor in
					removedMonitors.append(ObjectIdentifier(monitor as AnyObject))
				}
			)
		)
		let controller = harness.controller
		let window = MouseTrackingWindow(
			contentRect: harness.hostView.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = harness.hostView

		controller.beginDragForTesting(sourceIndex: 0, locationInContent: NSPoint(x: 20, y: 20))

		let mouseDraggedMonitor = try XCTUnwrap(capturedMouseDraggedMonitor)
		let mouseUpMonitor = try XCTUnwrap(capturedMouseUpMonitor)
		let bottomEdgeLocation = NSPoint(x: 20, y: harness.tableView.bounds.maxY - 2)
		window.trackedMouseLocation = windowMouseLocation(
			for: bottomEdgeLocation,
			hostView: harness.hostView,
			tableView: harness.tableView
		)
		let dragEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDragged,
				location: window.trackedMouseLocation,
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 0,
				clickCount: 0,
				pressure: 0
			)
		)

		XCTAssertNil(mouseDraggedMonitor(dragEvent))
		XCTAssertTrue(controller.autoscrollIsActiveForTesting())
		XCTAssertGreaterThanOrEqual(controller.scrollOffsetYForTesting(), 0)

		for _ in 0..<3 {
			_ = controller.handleAutoscrollTickForTesting()
		}
		XCTAssertGreaterThan(controller.scrollOffsetYForTesting(), 0)

		let staleLocationInContent = NSPoint(x: 20, y: harness.tableView.bounds.maxY - 2)
		controller.setLastKnownDragLocationInContentForTesting(staleLocationInContent)

		let clipView = try XCTUnwrap(harness.tableView.enclosingScrollView?.contentView)
		let finalLocationInContent = NSPoint(
			x: 20,
			y: controller.scrollOffsetYForTesting() + clipView.bounds.midY
		)
		let expectedDestination = controller.resolvedDestinationIndexForTesting(
			targetCenterY: finalLocationInContent.y,
			sourceIndex: 0
		)
		let staleDestination = controller.resolvedDestinationIndexForTesting(
			targetCenterY: staleLocationInContent.y,
			sourceIndex: 0
		)
		XCTAssertNotEqual(expectedDestination, staleDestination)

		let mouseUpEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseUp,
				location: windowMouseLocation(
					for: finalLocationInContent,
					hostView: harness.hostView,
					tableView: harness.tableView
				),
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 1,
				clickCount: 0,
				pressure: 0
			)
		)

		XCTAssertNil(mouseUpMonitor(mouseUpEvent))
		XCTAssertFalse(controller.isReordering())
		XCTAssertEqual(removedMonitors.count, 3)

		controller.flushPendingDropResetForTesting()

		XCTAssertEqual(moves.last, MoveRecord(source: 0, destination: expectedDestination))
		XCTAssertNil(controller.dragPresentationFrameForTesting(modelIndex: 0))
		XCTAssertNil(controller.dragPlaceholderFrameForTesting())
		XCTAssertTrue(mouseUpMonitor(mouseUpEvent) === mouseUpEvent)
		XCTAssertTrue(mouseDraggedMonitor(dragEvent) === dragEvent)
	}

	func testReorderableListControllerDragMonitorsReinstallPerDragAndReturnEventsWhenInactive() throws {
		var capturedMouseUpMonitor: ((NSEvent) -> NSEvent?)?
		var capturedMouseDraggedMonitor: ((NSEvent) -> NSEvent?)?
		var addCounts = (mouseUp: 0, mouseDragged: 0)
		var removeMonitorCount = 0
		let harness = makeListControllerHarness(
			items: [0, 1, 2],
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			),
			eventMonitoring: ReorderableListEventMonitoring(
				addLocalKeyDownMonitor: { _ in NSObject() },
				addLocalLeftMouseUpMonitor: { handler in
					addCounts.mouseUp += 1
					capturedMouseUpMonitor = handler
					return NSObject()
				},
				addLocalLeftMouseDraggedMonitor: { handler in
					addCounts.mouseDragged += 1
					capturedMouseDraggedMonitor = handler
					return NSObject()
				},
				removeMonitor: { _ in
					removeMonitorCount += 1
				}
			)
		)
		let controller = harness.controller
		let window = NSWindow(
			contentRect: harness.hostView.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = harness.hostView

		controller.beginDragForTesting(sourceIndex: 0, locationInContent: NSPoint(x: 20, y: 20))
		controller.endDragForTesting(cancelled: true)
		controller.flushPendingDropResetForTesting()

		controller.beginDragForTesting(sourceIndex: 1, locationInContent: NSPoint(x: 20, y: 60))
		XCTAssertEqual(addCounts.mouseUp, 2)
		XCTAssertEqual(addCounts.mouseDragged, 2)
		XCTAssertEqual(removeMonitorCount, 3)

		let mouseUpMonitor = try XCTUnwrap(capturedMouseUpMonitor)
		let mouseDraggedMonitor = try XCTUnwrap(capturedMouseDraggedMonitor)
		let mouseUpEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseUp,
				location: NSPoint(x: 20, y: 20),
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 2,
				clickCount: 0,
				pressure: 0
			)
		)
		let mouseDraggedEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDragged,
				location: NSPoint(x: 20, y: 60),
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 3,
				clickCount: 0,
				pressure: 0
			)
		)

		controller.endDragForTesting(cancelled: true)
		controller.flushPendingDropResetForTesting()

		XCTAssertEqual(removeMonitorCount, 6)
		XCTAssertTrue(mouseUpMonitor(mouseUpEvent) === mouseUpEvent)
		XCTAssertTrue(mouseDraggedMonitor(mouseDraggedEvent) === mouseDraggedEvent)
	}

	func testReorderableListControllerCancellationNotificationAndLayoutBranches() {
		_ = NSApplication.shared

		let harness = makeListControllerHarness(
			items: Array(0..<20),
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: AutoscrollConfiguration(
					edgeZoneHeight: 56,
					minimumSpeed: 240,
					maximumSpeed: 960
				),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			)
		)
		let controller = harness.controller
		let window = NSWindow(
			contentRect: harness.hostView.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = harness.hostView

		controller.beginDragForTesting(sourceIndex: 0, locationInContent: NSPoint(x: 20, y: 20))
		controller.layoutDidChange()
		controller.updateDragForTesting(
			locationInContent: NSPoint(x: 20, y: harness.tableView.bounds.maxY - 2)
		)
		RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
		XCTAssertTrue(controller.scrollOffsetYForTesting() >= 0)

		NotificationCenter.default.post(
			name: NSWindow.didResignKeyNotification,
			object: window
		)
		XCTAssertFalse(controller.isReordering())
		controller.flushPendingDropResetForTesting()
		controller.layoutDidChange()

		controller.beginDragForTesting(sourceIndex: 0, locationInContent: NSPoint(x: 20, y: 20))
		NotificationCenter.default.post(
			name: NSApplication.didResignActiveNotification,
			object: NSApp
		)
		XCTAssertFalse(controller.isReordering())
		controller.flushPendingDropResetForTesting()
	}

	func testReorderableListControllerAutoscrollHelperLoadsVisibleRowsWhenPreviousRangeIsMissing() {
		let harness = makeListControllerHarness(
			items: Array(0..<20),
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			)
		)

		harness.controller.ensureAutoscrolledRowsLoadedForTesting(previousVisibleRows: nil)

		XCTAssertGreaterThan(
			harness.controller.performanceMetrics.autoscrollVisibleRowRealizations,
			0
		)
	}

	func testReorderableListControllerTestingHelpersCoverInvalidLookupBranches() {
		let harness = makeListControllerHarness(
			items: [0, 1],
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			)
		)

		harness.controller.armPendingPressForTesting(
			sourceIndex: 99,
			locationInView: NSPoint(x: 20, y: 20)
		)

		XCTAssertFalse(harness.controller.hasPendingPressForTesting())
		XCTAssertNil(harness.controller.itemIDForTesting(displayRow: 99))
		XCTAssertFalse(harness.controller.hasRowModelForTesting(itemID: 99))
	}

	func testReorderableListControllerInvalidateMeasuredHeightsHandlesStableWidthAndEmptyRows() {
		let variableHeightHarness = makeListControllerHarness(
			items: [0, 1],
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 4,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { index in
					FixedHeightView(height: index == 0 ? 40 : 72)
				},
				dragStartThreshold: 4,
				estimatedRowHeight: 44,
				fixedRowHeight: nil
			)
		)
		let emptyHarness = makeListControllerHarness(
			items: [],
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 4,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 44,
				fixedRowHeight: nil
			)
		)

		variableHeightHarness.controller.invalidateMeasuredHeightsForTesting(width: 200)
		variableHeightHarness.controller.invalidateMeasuredHeightsForTesting(width: 200)
		emptyHarness.controller.invalidateMeasuredHeightsForTesting(width: 200)

		XCTAssertEqual(variableHeightHarness.tableView.numberOfRows, 2)
		XCTAssertEqual(emptyHarness.tableView.numberOfRows, 0)
	}

	func testReorderableListControllerPositionHelpersNoOpWithoutActiveSession() {
		let harness = makeListControllerHarness(
			items: [0],
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			)
		)

		harness.controller.detachOverlayHostForTesting()
		XCTAssertNil(harness.controller.dragVisualFrameInTableCoordinatesForTesting())
		harness.controller.positionDraggedRowForTesting(
			itemID: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)
		XCTAssertEqual(harness.controller.performanceMetrics.overlayUpdates, 0)
	}

	func testReorderableListControllerDropResetRevealsLiveRowWhenOverlayHostIsMissing() {
		let harness = makeListControllerHarness(
			items: [0, 1],
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			)
		)

		harness.controller.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)
		harness.controller.detachOverlayHostForTesting()
		harness.controller.endDragForTesting(cancelled: true, resetImmediately: true)

		XCTAssertFalse(harness.controller.isReordering())
		XCTAssertEqual(harness.tableView.rowView(atRow: 0, makeIfNecessary: false)?.alphaValue, 1)
	}

	func testReorderableListControllerResolvedAutoscrollDeltaReturnsNilForZeroVisibleHeight() {
		let harness = makeListControllerHarness(
			items: [0, 1],
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(
					edgeZoneHeight: 56,
					minimumSpeed: 240,
					maximumSpeed: 960
				),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			)
		)
		let zeroHeightScrollView = NSScrollView(frame: .zero)
		zeroHeightScrollView.contentView = NSClipView(frame: .zero)
		zeroHeightScrollView.documentView = harness.tableView
		harness.hostView.addSubview(zeroHeightScrollView)

		XCTAssertNil(harness.controller.resolvedAutoscrollDeltaForTesting(pointerYInClipView: 0))
	}

	func testReorderableListControllerResolvedAutoscrollDeltaReturnsNilForZeroEdgeZone() {
		let harness = makeListControllerHarness(
			items: [0, 1],
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(
					edgeZoneHeight: 0,
					minimumSpeed: 240,
					maximumSpeed: 960
				),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			)
		)

		XCTAssertNil(harness.controller.resolvedAutoscrollDeltaForTesting(pointerYInClipView: 0))
	}

	func testReorderableListControllerEscapeMonitorReturnsEventAfterControllerDeallocation() throws {
		var capturedEscapeMonitor: ((NSEvent) -> NSEvent?)?
		var harness = Optional(makeListControllerHarness(
			items: [0, 1],
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			),
			eventMonitoring: ReorderableListEventMonitoring(
				addLocalKeyDownMonitor: { handler in
					capturedEscapeMonitor = handler
					return NSObject()
				},
				addLocalLeftMouseUpMonitor: { _ in NSObject() },
				addLocalLeftMouseDraggedMonitor: { _ in NSObject() },
				removeMonitor: { _ in }
			)
		))
		weak var weakController: ReorderableListController<Int, Int>?
		weakController = harness?.controller
		harness?.controller.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)
		let escapeMonitor = try XCTUnwrap(capturedEscapeMonitor)
		let escapeEvent = try XCTUnwrap(
			NSEvent.keyEvent(
				with: .keyDown,
				location: .zero,
				modifierFlags: [],
				timestamp: 0,
				windowNumber: 0,
				context: nil,
				characters: "\u{1b}",
				charactersIgnoringModifiers: "\u{1b}",
				isARepeat: false,
				keyCode: 53
			)
		)

		harness = nil

		XCTAssertNil(weakController)
		XCTAssertTrue(escapeMonitor(escapeEvent) === escapeEvent)
	}

	func testPerformanceTracingEndIntervalWithoutSignpostStateIsANoOp() {
		let tracing = ReorderableListOSPerformanceTracing()

		tracing.endInterval(
			ReorderableListPerformanceTraceHandle(event: .dragLift)
		)
	}

	func testReorderableListControllerEndingSettleMeasurementWithoutActiveIntervalIsANoOp() {
		let harness = makeListControllerHarness(
			items: [0],
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			)
		)

		harness.controller.endSettlePerformanceIntervalForTesting()

		XCTAssertEqual(harness.controller.performanceMetrics.dragSettleMeasurementCount, 0)
	}

	func testReorderableListControllerBeginSettleMeasurementDoesNotDoubleStart() {
		let traceRecorder = PerformanceTraceRecorder()
		let monotonicClock = SteppedMonotonicClock(values: [0, 0.4])
		let harness = makeListControllerHarness(
			items: [0],
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			),
			performanceTracing: traceRecorder,
			monotonicClock: { monotonicClock.now() }
		)

		harness.controller.beginSettlePerformanceIntervalForTesting()
		harness.controller.beginSettlePerformanceIntervalForTesting()
		harness.controller.endSettlePerformanceIntervalForTesting()

		XCTAssertEqual(
			traceRecorder.records,
			[
				.init(phase: .begin, event: .dragSettle),
				.init(phase: .end, event: .dragSettle),
			]
		)
		XCTAssertEqual(harness.controller.performanceMetrics.dragSettleMeasurementCount, 1)
		XCTAssertEqual(harness.controller.performanceMetrics.dragSettleTotalDuration, 0.4, accuracy: 0.0001)
	}

	func testReorderableListControllerCancellationAndVisibleRowHelpersNoOpWhenIdleOrEmpty() {
		let harness = makeListControllerHarness(
			items: [0, 1],
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			)
		)
		let emptyHarness = makeListControllerHarness(
			items: [],
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			)
		)

		harness.controller.handleCancellationNotificationForTesting()
		harness.controller.ensureVisibleRowsLoadedForTesting(in: 0..<0)
		emptyHarness.controller.ensureAutoscrolledRowsLoadedForTesting(previousVisibleRows: nil)

		XCTAssertFalse(harness.controller.isReordering())
		XCTAssertNil(emptyHarness.controller.visibleRowRangeForTesting())
	}

	func testReorderableListControllerCoversRemainingHitTestingAndVariableHeightBranches() throws {
		let variableHeightHarness = makeListControllerHarness(
			items: [0],
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: nil
			)
		)
		XCTAssertEqual(variableHeightHarness.controller.tableView(NSTableView(), heightOfRow: -1), 40)

		let controlHarness = makeListControllerHarness(
			items: [0],
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in ControlRowView(frame: .zero) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			)
		)
		let controlContainer = try XCTUnwrap(controlHarness.controller.containerViewForTesting(row: 0))
		controlContainer.layoutSubtreeIfNeeded()
		let button = try XCTUnwrap((controlContainer.contentView as? ControlRowView)?.button)
		XCTAssertFalse(controlHarness.controller.shouldBeginContainerDragForTesting(from: button))

		let nonHittingHarness = makeListControllerHarness(
			items: [0],
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in NonHittingView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			)
		)
		let nonHittingContainer = try XCTUnwrap(nonHittingHarness.controller.containerViewForTesting(row: 0))
		let nonHittingPoint = nonHittingHarness.hostView.convert(
			NSPoint(x: 20, y: 20),
			from: nonHittingContainer
		)
		XCTAssertTrue(nonHittingHarness.controller.handleMouseDown(locationInSelf: nonHittingPoint))
		XCTAssertTrue(nonHittingHarness.controller.handleMouseUp())

		let nestedHarness = makeListControllerHarness(
			items: [0],
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in NestedHitRowView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			)
		)
		let nestedContainer = try XCTUnwrap(nestedHarness.controller.containerViewForTesting(row: 0))
		let childView = try XCTUnwrap((nestedContainer.contentView as? NestedHitRowView)?.childView)
		let childPoint = nestedHarness.hostView.convert(
			NSPoint(x: childView.bounds.midX, y: childView.bounds.midY),
			from: childView
		)
		nestedHarness.controller.installPendingPressForTesting(sourceIndex: 0, locationInSelf: childPoint)
		nestedHarness.controller.beginPendingDragForTesting()
		XCTAssertTrue(nestedHarness.controller.isReordering())
		nestedHarness.controller.endDragForTesting(cancelled: true)
		nestedHarness.controller.flushPendingDropResetForTesting()
	}

	func testReorderableListControllerCoversRemainingDragLayoutBranches() throws {
		let harness = makeListControllerHarness(
			items: Array(0..<4),
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			)
		)
		let controller = harness.controller

		controller.beginDragForTesting(sourceIndex: 2, locationInContent: NSPoint(x: 20, y: 100))
		controller.updateDragForTesting(locationInContent: NSPoint(x: 20, y: -20))
		controller.layoutDidChange()
		let topIndicatorY = try XCTUnwrap(controller.dropIndicatorFrameForTesting()?.minY)
		XCTAssertEqual(
			topIndicatorY,
			harness.tableView.rect(ofRow: 0).minY - (ReorderableListStyle.dropIndicatorHeight / 2),
			accuracy: 0.001
		)

		controller.updateDragForTesting(locationInContent: NSPoint(x: 20, y: 0))
		controller.layoutDidChange()
		let middleIndicatorY = try XCTUnwrap(controller.dropIndicatorFrameForTesting()?.minY)
		XCTAssertEqual(
			middleIndicatorY,
			harness.tableView.rect(ofRow: 1).minY - (ReorderableListStyle.dropIndicatorHeight / 2),
			accuracy: 0.001
		)
		XCTAssertNotNil(controller.dropIndicatorColorForTesting())
		XCTAssertFalse(controller.handleAutoscrollTickForTesting())

		let displacedContainer = try XCTUnwrap(
			controller.tableView(NSTableView(), viewFor: nil, row: 1) as? ReorderableListItemContainerView
		)
		let displacedOffset = displacedContainer.contentView.superview?.layer?.transform.m42 ?? 0
		XCTAssertEqual(displacedOffset, 0, accuracy: 0.001)

		controller.endDragForTesting(cancelled: true)
		controller.flushPendingDropResetForTesting()

		let hostView = NSView(frame: CGRect(x: 0, y: 0, width: 280, height: 200))
		hostView.wantsLayer = true
		let scrollView = ReorderableListScrollView(frame: hostView.bounds)
		scrollView.hasVerticalScroller = true
		scrollView.contentView = ReorderableListClipView(frame: hostView.bounds)
		let documentView = ReorderableListDocumentView(frame: hostView.bounds)
		let tableView = ReorderableListTableView(frame: hostView.bounds)
		tableView.headerView = nil
		tableView.focusRingType = .none
		tableView.selectionHighlightStyle = .none
		tableView.backgroundColor = .clear
		tableView.rowHeight = 40
		tableView.intercellSpacing = .zero
		let tableColumn = NSTableColumn(identifier: .reorderableListColumn)
		tableColumn.resizingMask = .autoresizingMask
		tableView.addTableColumn(tableColumn)
		documentView.addSubview(tableView)
		scrollView.documentView = documentView
		hostView.addSubview(scrollView)
		var overlayHostView: NSView? = NSView(frame: hostView.bounds)
		overlayHostView?.wantsLayer = true
		try hostView.addSubview(XCTUnwrap(overlayHostView))
		let missingOverlayController = ReorderableListController(
			items: [0, 1],
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			),
			tableView: tableView,
			tableColumn: tableColumn
		)
		missingOverlayController.attach(hostView: hostView, overlayHostView: overlayHostView)
		missingOverlayController.reload()
		missingOverlayController.layoutDidChange()
		missingOverlayController.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)
		overlayHostView?.removeFromSuperview()
		overlayHostView = nil
		missingOverlayController.detachOverlayHostForTesting()
		missingOverlayController.updateDragForTesting(locationInContent: NSPoint(x: 20, y: 60))
		missingOverlayController.attach(hostView: hostView)
		XCTAssertTrue(missingOverlayController.isReordering())
		missingOverlayController.endDragForTesting(cancelled: true)
		missingOverlayController.flushPendingDropResetForTesting()
	}

	func testReorderableListControllerCoversRemainingStandaloneAndControlFallbackBranches() throws {
		let standaloneHostView = NSView(frame: CGRect(x: 0, y: 0, width: 240, height: 160))
		let standaloneTableView = ReorderableListTableView(frame: standaloneHostView.bounds)
		standaloneTableView.headerView = nil
		standaloneTableView.focusRingType = .none
		standaloneTableView.selectionHighlightStyle = .none
		standaloneTableView.backgroundColor = .clear
		standaloneTableView.rowHeight = 40
		let standaloneColumn = NSTableColumn(identifier: .reorderableListColumn)
		standaloneTableView.addTableColumn(standaloneColumn)
		let standaloneController = ReorderableListController(
			items: [0],
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(edgeZoneHeight: 0),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			),
			tableView: standaloneTableView,
			tableColumn: standaloneColumn
		)
		standaloneController.attach(hostView: standaloneHostView)
		standaloneController.reload()
		standaloneController.layoutDidChange()

		XCTAssertEqual(standaloneController.scrollOffsetYForTesting(), 0)
		XCTAssertEqual(standaloneController.documentHeight(), standaloneTableView.frame.height)
		standaloneController.appendItems([])
		XCTAssertEqual(standaloneController.numberOfRows(in: NSTableView()), 1)
		XCTAssertNil(standaloneController.tableView(NSTableView(), viewFor: nil, row: 99))
		standaloneController.updateSelectedItemID(99)
		XCTAssertFalse(standaloneController.moveSelectedItem(direction: 1))
		XCTAssertFalse(standaloneController.handleMouseDown(locationInSelf: NSPoint(x: -20, y: -20)))
		standaloneController.beginDragForTesting(sourceIndex: 0, locationInContent: NSPoint(x: 20, y: 20))
		XCTAssertTrue(standaloneController.isReordering())
		standaloneController.updateDragForTesting(locationInContent: NSPoint(x: 24, y: 60))
		standaloneController.endDragForTesting(cancelled: true)
		standaloneController.flushPendingDropResetForTesting()

		let controlHarness = makeListControllerHarness(
			items: [0],
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in ControlRowView(frame: .zero) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			)
		)
		let controlContainer = try XCTUnwrap(controlHarness.controller.containerViewForTesting(row: 0))
		controlContainer.layoutSubtreeIfNeeded()
		controlHarness.hostView.layoutSubtreeIfNeeded()
		let button = try XCTUnwrap((controlContainer.contentView as? ControlRowView)?.button)
		(controlContainer.contentView as? ControlRowView)?.layoutSubtreeIfNeeded()
		let buttonPoint = controlHarness.hostView.convert(
			NSPoint(x: button.bounds.midX, y: button.bounds.midY),
			from: button
		)
		controlHarness.controller.installPendingPressForTesting(
			sourceIndex: 0,
			locationInSelf: buttonPoint
		)
		controlHarness.controller.beginPendingDragForTesting()
		XCTAssertFalse(controlHarness.controller.isReordering())

		let longPressHarness = makeListControllerHarness(
			items: [0],
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(),
				reorderHandleWidth: nil,
				longPressDuration: 0.01,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			)
		)
		let longPressContainer = try XCTUnwrap(longPressHarness.controller.containerViewForTesting(row: 0))
		let longPressPoint = longPressHarness.hostView.convert(
			NSPoint(x: 20, y: 20),
			from: longPressContainer
		)
		longPressHarness.controller.rowViewForTesting(modelIndex: 0)?.frame = .zero
		_ = longPressHarness.controller.handleMouseDown(locationInSelf: longPressPoint)
		RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
		XCTAssertFalse(longPressHarness.controller.isReordering())
	}

	func testReorderableListControllerAutoscrollStopsAtScrollBounds() {
		let harness = makeListControllerHarness(
			items: Array(0..<20),
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: AutoscrollConfiguration(
					edgeZoneHeight: 56,
					minimumSpeed: 240,
					maximumSpeed: 960
				),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			)
		)
		let controller = harness.controller

		controller.beginDragForTesting(sourceIndex: 0, locationInContent: NSPoint(x: 20, y: 20))
		controller.updateDragForTesting(locationInContent: NSPoint(x: 20, y: 1))

		XCTAssertTrue(controller.autoscrollIsActiveForTesting())
		XCTAssertFalse(controller.handleAutoscrollTickForTesting())

		controller.endDragForTesting(cancelled: true)
		controller.flushPendingDropResetForTesting()
	}

	func testReorderableListControllerDoesNotAutoscrollForMidViewportDragAfterScrolling() throws {
		let harness = makeListControllerHarness(
			items: Array(0..<20),
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: AutoscrollConfiguration(
					edgeZoneHeight: 56,
					minimumSpeed: 240,
					maximumSpeed: 960
				),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			)
		)
		let controller = harness.controller
		let clipView = try XCTUnwrap(harness.tableView.enclosingScrollView?.contentView)

		clipView.scroll(to: NSPoint(x: 0, y: 240))
		harness.tableView.enclosingScrollView?.reflectScrolledClipView(clipView)

		let midViewportLocation = NSPoint(x: 20, y: 300)
		controller.beginDragForTesting(sourceIndex: 7, locationInContent: midViewportLocation)
		controller.updateDragForTesting(locationInContent: midViewportLocation)

		XCTAssertFalse(controller.autoscrollIsActiveForTesting())
		XCTAssertEqual(controller.scrollOffsetYForTesting(), 240, accuracy: 0.001)

		controller.endDragForTesting(cancelled: true)
		controller.flushPendingDropResetForTesting()
	}

	func testReorderableListControllerAutoscrollTickPrefersLiveWindowPointerOverLastKnownDragLocation() {
		let harness = makeListControllerHarness(
			items: Array(0..<20),
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: AutoscrollConfiguration(
					edgeZoneHeight: 56,
					minimumSpeed: 240,
					maximumSpeed: 960
				),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			)
		)
		let controller = harness.controller
		let window = MouseTrackingWindow(
			contentRect: harness.hostView.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = harness.hostView

		controller.beginDragForTesting(sourceIndex: 0, locationInContent: NSPoint(x: 20, y: 20))
		controller.updateDragForTesting(
			locationInContent: NSPoint(x: 20, y: harness.tableView.bounds.maxY - 2)
		)
		XCTAssertTrue(controller.autoscrollIsActiveForTesting())

		window.trackedMouseLocation = windowMouseLocation(
			for: NSPoint(x: 20, y: harness.tableView.bounds.maxY - 2),
			hostView: harness.hostView,
			tableView: harness.tableView
		)
		controller.setLastKnownDragLocationInContentForTesting(
			NSPoint(x: 20, y: harness.tableView.enclosingScrollView?.contentView.bounds.midY ?? 100)
		)

		XCTAssertTrue(controller.handleAutoscrollTickForTesting())
		XCTAssertTrue(controller.autoscrollIsActiveForTesting())

		controller.endDragForTesting(cancelled: true)
		controller.flushPendingDropResetForTesting()
	}

	func testReorderableListControllerAutoscrollStopsWhenLivePointerReturnsToViewportCenter() {
		let harness = makeListControllerHarness(
			items: Array(0..<20),
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: AutoscrollConfiguration(
					edgeZoneHeight: 56,
					minimumSpeed: 240,
					maximumSpeed: 960
				),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			)
		)
		let controller = harness.controller
		let window = MouseTrackingWindow(
			contentRect: harness.hostView.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = harness.hostView

		controller.beginDragForTesting(sourceIndex: 0, locationInContent: NSPoint(x: 20, y: 20))

		let bottomEdgeLocation = NSPoint(x: 20, y: harness.tableView.bounds.maxY - 2)
		controller.updateDragForTesting(locationInContent: bottomEdgeLocation)
		XCTAssertTrue(controller.autoscrollIsActiveForTesting())

		window.trackedMouseLocation = windowMouseLocation(
			for: NSPoint(x: 20, y: harness.tableView.enclosingScrollView?.contentView.bounds.midY ?? 100),
			hostView: harness.hostView,
			tableView: harness.tableView
		)
		controller.setLastKnownDragLocationInContentForTesting(bottomEdgeLocation)

		XCTAssertFalse(controller.handleAutoscrollTickForTesting())
		XCTAssertFalse(controller.autoscrollIsActiveForTesting())

		controller.endDragForTesting(cancelled: true)
		controller.flushPendingDropResetForTesting()
	}

	func testReorderableListControllerAutoscrollRestartsWhenFreshDragUpdateReturnsToBottomEdgeAfterStopping() {
		let harness = makeListControllerHarness(
			items: Array(0..<20),
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: AutoscrollConfiguration(
					edgeZoneHeight: 56,
					minimumSpeed: 240,
					maximumSpeed: 960
				),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			)
		)
		let controller = harness.controller
		let window = MouseTrackingWindow(
			contentRect: harness.hostView.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = harness.hostView

		controller.beginDragForTesting(sourceIndex: 0, locationInContent: NSPoint(x: 20, y: 20))

		let bottomEdgeLocation = NSPoint(x: 20, y: harness.tableView.bounds.maxY - 2)
		controller.updateDragForTesting(locationInContent: bottomEdgeLocation)
		XCTAssertTrue(controller.autoscrollIsActiveForTesting())

		window.trackedMouseLocation = windowMouseLocation(
			for: NSPoint(x: 20, y: harness.tableView.enclosingScrollView?.contentView.bounds.midY ?? 100),
			hostView: harness.hostView,
			tableView: harness.tableView
		)
		controller.setLastKnownDragLocationInContentForTesting(bottomEdgeLocation)

		XCTAssertFalse(controller.handleAutoscrollTickForTesting())
		XCTAssertFalse(controller.autoscrollIsActiveForTesting())

		window.trackedMouseLocation = windowMouseLocation(
			for: bottomEdgeLocation,
			hostView: harness.hostView,
			tableView: harness.tableView
		)

		XCTAssertFalse(controller.handleAutoscrollTickForTesting())
		XCTAssertFalse(controller.autoscrollIsActiveForTesting())

		controller.updateDragForTesting(locationInContent: bottomEdgeLocation)
		XCTAssertTrue(controller.handleAutoscrollTickForTesting())
		XCTAssertTrue(controller.autoscrollIsActiveForTesting())

		controller.endDragForTesting(cancelled: true)
		controller.flushPendingDropResetForTesting()
	}

	func testReorderableListControllerDropAtBottomAfterAutoscrollCommitsFinalMove() {
		var moves = [MoveRecord]()
		let harness = makeListControllerHarness(
			items: Array(0..<20),
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: AutoscrollConfiguration(
					edgeZoneHeight: 56,
					minimumSpeed: 240,
					maximumSpeed: 960
				),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { source, destination in
					moves.append(MoveRecord(source: source.first ?? -1, destination: destination))
				},
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			)
		)
		let controller = harness.controller
		let window = MouseTrackingWindow(
			contentRect: harness.hostView.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = harness.hostView

		controller.beginDragForTesting(sourceIndex: 0, locationInContent: NSPoint(x: 20, y: 20))

		let bottomEdgeLocation = NSPoint(x: 20, y: harness.tableView.bounds.maxY - 2)
		window.trackedMouseLocation = windowMouseLocation(
			for: bottomEdgeLocation,
			hostView: harness.hostView,
			tableView: harness.tableView
		)
		controller.updateDragForTesting(locationInContent: bottomEdgeLocation)

		var previousOffset = -1.0
		while controller.scrollOffsetYForTesting() > previousOffset {
			previousOffset = controller.scrollOffsetYForTesting()
			_ = controller.handleAutoscrollTickForTesting()
		}

		controller.endDragForTesting(cancelled: false)

		XCTAssertEqual(moves.last, MoveRecord(source: 0, destination: 20))
		XCTAssertEqual(controller.currentVisualOrder().last, 0)
	}

	func testReorderableListControllerMouseUpAfterStoppingAutoscrollSettlesAndCommits() throws {
		var moves = [MoveRecord]()
		let harness = makeListControllerHarness(
			items: Array(0..<20),
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: AutoscrollConfiguration(
					edgeZoneHeight: 56,
					minimumSpeed: 240,
					maximumSpeed: 960
				),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { source, destination in
					moves.append(MoveRecord(source: source.first ?? -1, destination: destination))
				},
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			)
		)
		let controller = harness.controller
		let window = MouseTrackingWindow(
			contentRect: harness.hostView.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = harness.hostView

		controller.beginDragForTesting(sourceIndex: 0, locationInContent: NSPoint(x: 20, y: 20))

		let bottomEdgeLocation = NSPoint(x: 20, y: harness.tableView.bounds.maxY - 2)
		window.trackedMouseLocation = windowMouseLocation(
			for: bottomEdgeLocation,
			hostView: harness.hostView,
			tableView: harness.tableView
		)
		controller.updateDragForTesting(locationInContent: bottomEdgeLocation)

		for _ in 0..<3 {
			_ = controller.handleAutoscrollTickForTesting()
		}
		XCTAssertGreaterThan(controller.scrollOffsetYForTesting(), 0)

		let clipView = try XCTUnwrap(harness.tableView.enclosingScrollView?.contentView)
		let centerLocation = NSPoint(
			x: 20,
			y: controller.scrollOffsetYForTesting() + clipView.bounds.midY
		)
		window.trackedMouseLocation = windowMouseLocation(
			for: centerLocation,
			hostView: harness.hostView,
			tableView: harness.tableView
		)
		controller.setLastKnownDragLocationInContentForTesting(bottomEdgeLocation)

		XCTAssertFalse(controller.handleAutoscrollTickForTesting())
		XCTAssertFalse(controller.autoscrollIsActiveForTesting())

		let centerLocationInSelf = harness.hostView.convert(centerLocation, from: harness.tableView)
		XCTAssertTrue(controller.handleMouseUp(locationInSelf: centerLocationInSelf))
		controller.flushPendingDropResetForTesting()

		XCTAssertNil(controller.dragPresentationFrameForTesting(modelIndex: 0))
		XCTAssertNil(controller.dragPlaceholderFrameForTesting())
		XCTAssertFalse(controller.isReordering())
		XCTAssertFalse(moves.isEmpty)
	}

	func testReorderableListControllerLayoutUsesLastKnownDragLocationForDraggedRowPosition() throws {
		let harness = makeListControllerHarness(
			items: Array(0..<20),
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsetsZero,
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(),
				reorderHandleWidth: nil,
				longPressDuration: 0,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in FixedHeightView(height: 40) },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: 40
			)
		)
		let controller = harness.controller
		let window = MouseTrackingWindow(
			contentRect: harness.hostView.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = harness.hostView

		controller.beginDragForTesting(sourceIndex: 0, locationInContent: NSPoint(x: 20, y: 20))
		window.trackedMouseLocation = windowMouseLocation(
			for: NSPoint(x: 20, y: harness.tableView.bounds.maxY - 2),
			hostView: harness.hostView,
			tableView: harness.tableView
		)
		controller.setLastKnownDragLocationInContentForTesting(NSPoint(x: 20, y: 100))

		controller.layoutDidChange()

		let restingFrame = harness.tableView.rect(ofRow: 0)
		let expectedDraggedFrame = ReorderableListGeometry.draggedFrame(
			restingFrame: restingFrame,
			pointerLocation: NSPoint(x: 20, y: 100),
			pointerOffset: CGPoint(
				x: restingFrame.midX - 20,
				y: restingFrame.midY - 20
			),
			linearLimit: ReorderableListStyle.horizontalDragLinearLimit,
			maxOffset: ReorderableListStyle.maxHorizontalDragOffset
		)
		let draggedFrame = try XCTUnwrap(controller.dragPresentationFrameForTesting(modelIndex: 0))
		XCTAssertEqual(draggedFrame.midY, expectedDraggedFrame.midY, accuracy: 0.5)

		controller.endDragForTesting(cancelled: true)
		controller.flushPendingDropResetForTesting()
	}

	func testReorderableListViewWillMoveCompletesPendingDropReset() {
		let observerRow = DragObserverRowView(height: 40)
		let list = ReorderableListView(
			items: [0],
			id: \.self,
			contentInsets: NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0),
			rowBackgroundColor: .windowBackgroundColor,
			onMove: { _, _ in },
			contentViewBuilder: { _ in observerRow }
		)
		list.frame = CGRect(x: 0, y: 0, width: 280, height: 80)
		list.layoutSubtreeIfNeeded()

		list.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)
		list.endDragForTesting(cancelled: true)

		XCTAssertTrue(observerRow.endCancelledStates.isEmpty)

		list.viewWillMove(toWindow: nil)

		XCTAssertFalse(list.isReordering())
		XCTAssertEqual(observerRow.endCancelledStates, [true])
	}

	func testReorderableListViewWillMoveWithoutPendingPressIsANoop() {
		let list = makeList(items: [0, 1, 2])

		list.viewWillMove(toWindow: nil)

		XCTAssertFalse(list.hasPendingPressForTesting())
		XCTAssertFalse(list.isReordering())
	}

	func testReorderableListViewPlainKeyDownFallsBackToSuperImplementation() throws {
		let list = makeList(items: [0, 1, 2])
		let window = NSWindow(
			contentRect: CGRect(x: 0, y: 0, width: 240, height: 120),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = list
		list.frame = window.contentView?.bounds ?? .zero
		list.layoutSubtreeIfNeeded()

		let plainEvent = try XCTUnwrap(
			NSEvent.keyEvent(
				with: .keyDown,
				location: .zero,
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				characters: "",
				charactersIgnoringModifiers: "",
				isARepeat: false,
				keyCode: 124
			)
		)

		XCTAssertFalse(list.handleKeyDown(plainEvent))
		list.keyDown(with: plainEvent)
	}

	func testReorderableListItemContainerViewPreservesFullWidthLayoutAfterReuse() {
		let initialContent = FixedHeightView(height: 40)
		let replacementContent = FixedHeightView(height: 40)
		let container = ReorderableListItemContainerView(
			contentView: initialContent,
			backgroundColor: .windowBackgroundColor
		)
		container.frame = CGRect(x: 0, y: 0, width: 280, height: 40)
		container.layoutSubtreeIfNeeded()
		XCTAssertEqual(initialContent.frame, CGRect(x: 0, y: 0, width: 280, height: 40))

		container.prepareForReuse(with: replacementContent)
		container.layoutSubtreeIfNeeded()

		XCTAssertEqual(replacementContent.frame, CGRect(x: 0, y: 0, width: 280, height: 40))
	}

	func testStyleResolvedColorAndAccentAreAccessible() {
		let appearance = NSAppearance(named: .aqua) ?? .currentDrawing()
		let resolved = ReorderableListStyle.resolvedColor(.windowBackgroundColor, for: appearance)

		XCTAssertNotNil(resolved.cgColor)
		XCTAssertNotNil(ReorderableListStyle.accentColor.cgColor)
	}

	func testStyleResolvedColorFallsBackWhenCGColorCannotRoundTrip() throws {
		let appearance = try XCTUnwrap(NSAppearance(named: .aqua))
		let resolved = ReorderableListStyle.resolvedColor(
			.windowBackgroundColor,
			for: appearance,
			roundTripColor: { _ in nil }
		)

		XCTAssertEqual(resolved, .windowBackgroundColor)
	}

	func testStyleConstantsMatchExpectedValues() {
		XCTAssertEqual(
			ReorderableListStyle.animationDuration,
			ReorderableListStyle.animationSpring.settlingDuration,
			accuracy: 0.001
		)
		XCTAssertEqual(ReorderableListStyle.cornerRadius, 8)
		XCTAssertEqual(ReorderableListStyle.borderWidth, 2)
		XCTAssertEqual(ReorderableListStyle.activeBorderOpacity, 0.8)
		XCTAssertEqual(ReorderableListStyle.inactiveRowOpacity, 1)
		XCTAssertEqual(ReorderableListStyle.activeScale, 1.02)
		XCTAssertEqual(ReorderableListStyle.activeShadowOpacity, 0.15)
		XCTAssertEqual(ReorderableListStyle.activeShadowRadius, 10)
		XCTAssertEqual(ReorderableListStyle.liftedOverlayHorizontalInset, 15)
		XCTAssertEqual(ReorderableListStyle.liftedOverlayCornerRadius, 10)
		XCTAssertEqual(ReorderableListStyle.activeRotationDegrees, 3)
		XCTAssertEqual(ReorderableListStyle.activeShadowColor, .black)
		XCTAssertEqual(ReorderableListStyle.horizontalDragLinearLimit, 72)
		XCTAssertEqual(ReorderableListStyle.maxHorizontalDragOffset, 144)
		XCTAssertEqual(ReorderableListStyle.dragPlaceholderDashPattern, [8, 6])
		XCTAssertEqual(
			ReorderableListStyle.dragPlaceholderAnimationDuration,
			0.75,
			accuracy: 0.001
		)
		XCTAssertEqual(ReorderableListStyle.dragPlaceholderHorizontalInset, 10)
		XCTAssertEqual(
			ReorderableListStyle.dragPlaceholderStrokeColor,
			Color.navigatorChromeFill
		)
	}

	func testReorderDragAppearanceDefaultsUsePositiveLiftRotation() {
		XCTAssertEqual(
			ReorderDragAppearance().rotationRadians,
			(3 * .pi) / 180,
			accuracy: 0.0001
		)
	}

	func testDirectCoordinatorRuntimeAndWrapperCoverageBranches() {
		let hostView = NSView(frame: CGRect(x: 0, y: 0, width: 240, height: 120))
		hostView.wantsLayer = true
		let dragVisualController = ReorderableListDragVisualController()
		let overlayCoordinator = ReorderableListOverlayCoordinator(
			dragVisualController: dragVisualController
		)
		overlayCoordinator.attach(to: hostView)
		let snapshot = NSImage(size: CGSize(width: 40, height: 20))
		let liftFrame = CGRect(x: 10, y: 12, width: 40, height: 20)
		overlayCoordinator.beginLift(
			snapshotImage: snapshot,
			frame: liftFrame,
			backgroundColor: .windowBackgroundColor,
			appearance: .init()
		)
		XCTAssertTrue(overlayCoordinator.isActive)
		XCTAssertEqual(overlayCoordinator.currentFrameInHost, liftFrame)
		overlayCoordinator.stopAnimationAndFreeze()
		overlayCoordinator.beginSettle(
			to: CGRect(x: 14, y: 18, width: 40, height: 20),
			commit: true,
			backgroundColor: .windowBackgroundColor,
			appearance: .init(),
			animated: false,
			durationOverride: 0
		)
		XCTAssertNotNil(overlayCoordinator.settleDuration)
		overlayCoordinator.tearDown()
		XCTAssertFalse(overlayCoordinator.isActive)
		XCTAssertNotNil(overlayCoordinator.currentFrameInHost)

		let placeholderCoordinator = ReorderableListPlaceholderCoordinator(
			placeholderView: ReorderableListDragPlaceholderView()
		)
		let placeholderFrame = CGRect(x: 4, y: 6, width: 50, height: 30)
		placeholderCoordinator.show(frame: placeholderFrame)
		XCTAssertEqual(placeholderCoordinator.frameIfVisible(), placeholderFrame)
		placeholderCoordinator.hide()
		XCTAssertNil(placeholderCoordinator.frameIfVisible())

		var announcements = [String]()
		let announcementCoordinator = ReorderableListAnnouncementCoordinator(
			accessibilityEnabled: { true },
			announce: { announcements.append($0) }
		)
		announcementCoordinator.announceReorderStart(totalCount: 3, initialIndex: 0)
		announcementCoordinator.announceReorderDestination(sourceIndex: 1, insertionIndex: -1, rows: 3)
		announcementCoordinator.announceCompletedMove(from: 1, insertionIndex: 10, rows: 3)
		announcementCoordinator.announceCancel()
		XCTAssertEqual(announcements.count, 4)

		let geometry = ReorderableListGeometryEngine()
		XCTAssertEqual(
			geometry.destinationIndex(targetCenterY: 10, sourceIndex: 2, thresholdLayout: nil),
			2
		)
		let previewLayout = ReorderableListDestinationThresholdLayout(
			sourceIndex: 1,
			thresholds: [4, 20, 36],
			sourceUpperThresholdY: 12,
			sourceLowerThresholdY: 28
		)
		XCTAssertEqual(previewLayout.destinationIndex(for: 24), 1)

		let list = makeList(items: [0, 1, 2])
		list.selectedID = 1
		XCTAssertEqual(list.selectedID, 1)
		var finishCount = 0
		list.onReorderInteractionDidFinish = { finishCount += 1 }
		XCTAssertNotNil(list.onReorderInteractionDidFinish)
		list.onReorderInteractionDidFinish?()
		XCTAssertEqual(finishCount, 1)
	}

	func testDragRuntimeFallbackResetAndClearPointerBranches() throws {
		let frameDriver = FrameDriverSpy()
		var session: DragSession<Int>? = DragSession(
			itemID: 1,
			initialIndex: 0,
			proposedIndex: 0,
			pointerOffset: .zero
		)
		var updatedSessions = [DragSession<Int>]()
		let runtime = ReorderableListDragRuntime<Int>(
			context: .init(
				fallbackWindowPointer: { nil },
				convertWindowPointToHost: { $0 },
				convertHostPointToTable: { $0 },
				convertTableFrameToHost: { $0 },
				sourceRowFrame: { _ in CGRect(x: 0, y: 0, width: 40, height: 20) },
				rowCount: { 1 },
				rowSpacing: { 0 },
				contentInsets: { NSEdgeInsetsZero },
				visibleRect: { CGRect(x: 0, y: 0, width: 100, height: 100) },
				attemptScrollBy: { _ in false },
				updateSession: { updatedSessions.append($0); session = $0 },
				activeSession: { session },
				onTick: { _ in },
				onFrameTiming: { _ in }
			),
			autoscrollConfiguration: .init(),
			frameDriver: frameDriver
		)

		runtime.updatePointerLocation(CGPoint(x: 5, y: 5))
		runtime.clearPointerLocation()
		XCTAssertNil(runtime.pointerLocationInWindow)

		let activeSession = try XCTUnwrap(session)
		runtime.begin(session: activeSession)
		session = nil
		XCTAssertFalse(runtime.tickForTestingWithoutAutoscroll())
		if case .idle = runtime.phase {} else {
			XCTFail("Runtime should reset to idle when the active session disappears")
		}

		session = activeSession
		runtime.begin(session: activeSession)
		runtime.clearPointerLocation()
		XCTAssertFalse(runtime.tickForTestingWithoutAutoscroll())
		XCTAssertGreaterThanOrEqual(frameDriver.startCount, 2)
		XCTAssertFalse(updatedSessions.isEmpty)
	}

	func testDragRuntimeResetsLiveWindowPointerPreferenceWhenAutoscrollStops() throws {
		let frameDriver = FrameDriverSpy()
		var session: DragSession<Int>? = DragSession(
			itemID: 1,
			initialIndex: 0,
			proposedIndex: 0,
			pointerOffset: .zero
		)
		let runtime = ReorderableListDragRuntime<Int>(
			context: .init(
				fallbackWindowPointer: { nil },
				convertWindowPointToHost: { $0 },
				convertHostPointToTable: { $0 },
				convertTableFrameToHost: { $0 },
				sourceRowFrame: { _ in CGRect(x: 0, y: 0, width: 40, height: 20) },
				rowCount: { 20 },
				rowSpacing: { 0 },
				contentInsets: { NSEdgeInsetsZero },
				visibleRect: { CGRect(x: 0, y: 0, width: 100, height: 100) },
				attemptScrollBy: { _ in true },
				updateSession: { session = $0 },
				activeSession: { session },
				onTick: { _ in },
				onFrameTiming: { _ in }
			),
			autoscrollConfiguration: AutoscrollConfiguration(
				edgeZoneHeight: 20,
				minimumSpeed: 240,
				maximumSpeed: 960
			),
			frameDriver: frameDriver
		)
		let activeSession = try XCTUnwrap(session)

		runtime.begin(session: activeSession)
		runtime.updatePointerLocation(CGPoint(x: 20, y: 99))
		XCTAssertTrue(runtime.tickForTesting())
		XCTAssertTrue(runtime.isAutoscrollActive)
		XCTAssertTrue(runtime.usesLiveWindowPointerForActiveDrag)

		runtime.updatePointerLocation(CGPoint(x: 20, y: 50))
		XCTAssertFalse(runtime.tickForTesting())
		XCTAssertFalse(runtime.isAutoscrollActive)
		XCTAssertFalse(runtime.usesLiveWindowPointerForActiveDrag)
	}

	func testControllerWindowFallbackVariableHeightAndPlaceholderRecoveryBranches() throws {
		let harness = makeListControllerHarness(
			items: [0, 1, 2],
			configuration: ReorderableListConfiguration(
				id: \.self,
				contentInsets: NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
				rowSpacing: 0,
				rowBackgroundColor: .windowBackgroundColor,
				dragAppearance: .init(),
				autoscroll: .init(),
				reorderHandleWidth: nil,
				longPressDuration: 0.01,
				accessibilityAnnouncementsEnabled: false,
				accessibilityAnnouncementHandler: { _ in },
				onMove: { _, _ in },
				canMove: nil,
				onMoveStart: nil,
				onMoveUpdate: nil,
				onMoveEnd: nil,
				onReorderInteractionDidFinish: nil,
				contentViewBuilder: { _ in WidthResponsiveHeightView() },
				dragStartThreshold: 4,
				estimatedRowHeight: 40,
				fixedRowHeight: nil
			)
		)
		let window = MouseTrackingWindow(
			contentRect: CGRect(x: 0, y: 0, width: 320, height: 240),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.contentView = NSView(frame: window.frame)
		try XCTUnwrap(window.contentView).addSubview(harness.hostView)
		let controller = harness.controller
		let container = try XCTUnwrap(controller.containerViewForTesting(row: 0))
		let pressLocation = harness.hostView.convert(
			NSPoint(x: container.bounds.midX, y: container.bounds.midY),
			from: container
		)
		let dragLocationInContent = NSPoint(x: 20, y: 30)
		let windowLocation = harness.hostView.convert(dragLocationInContent, from: harness.tableView)
		window.trackedMouseLocation = windowLocation

		XCTAssertTrue(controller.handleMouseDown(locationInSelf: pressLocation))
		controller.activatePendingPressForTesting()
		XCTAssertTrue(controller.isReordering())
		controller.setLastKnownDragLocationInContentForTesting(nil)
		XCTAssertFalse(controller.handleAutoscrollTickForTesting())
		XCTAssertNotEqual(
			controller.resolvedDestinationIndexForTesting(targetCenterY: 120, sourceIndex: 0),
			0
		)
		controller.endDragForTesting(cancelled: true)
		controller.flushPendingDropResetForTesting()

		controller.beginDragForTesting(sourceIndex: 0, locationInContent: dragLocationInContent)
		controller.removeDisplayRowCacheEntryForTesting(itemID: 0)
		controller.updateDragForTesting(locationInContent: dragLocationInContent)
		controller.syncDisplayRowCacheForTesting()
		controller.clearDragPlaceholderForTesting()
		controller.updateDragForTesting(locationInContent: dragLocationInContent)
		XCTAssertNotNil(controller.dragPlaceholderFrameForTesting())
		controller.endDragForTesting(cancelled: true, resetImmediately: true)
		controller.flushPendingDropResetForTesting()
	}

	func testItemContainerFallbackKeyDownAndCancelOperationBranches() throws {
		let forwardingContainer = ReorderableListItemContainerView(
			contentView: FixedHeightView(height: 40),
			backgroundColor: .windowBackgroundColor
		)
		let forwardingView = ForwardingView()
		let responderSpy = ResponderSpy()
		forwardingContainer.eventForwardingView = forwardingView
		forwardingView.nextResponder = responderSpy

		let standaloneContainer = ReorderableListItemContainerView(
			contentView: FixedHeightView(height: 40),
			backgroundColor: .windowBackgroundColor
		)
		let window = MouseTrackingWindow(
			contentRect: CGRect(x: 0, y: 0, width: 200, height: 100),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.contentView = forwardingContainer

		let keyEvent = try XCTUnwrap(
			NSEvent.keyEvent(
				with: .keyDown,
				location: .zero,
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				characters: "",
				charactersIgnoringModifiers: "",
				isARepeat: false,
				keyCode: 124
			)
		)

		forwardingContainer.keyDown(with: keyEvent)
		forwardingContainer.cancelOperation(nil)
		standaloneContainer.keyDown(with: keyEvent)
		standaloneContainer.cancelOperation(nil)

		XCTAssertEqual(forwardingView.keyDownCount, 1)
		XCTAssertEqual(forwardingView.cancelOperationCount, 1)
		XCTAssertEqual(responderSpy.cancelOperationCount, 0)
	}

	private func makeList(
		items: [Int],
		handleWidth _: CGFloat? = nil,
		onMove: @escaping (IndexSet, Int) -> Void = { _, _ in }
	) -> ReorderableListView<Int, Int> {
		ReorderableListView(
			items: items,
			id: \.self,
			contentInsets: NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0),
			rowBackgroundColor: .windowBackgroundColor,
			onMove: onMove,
			contentViewBuilder: { _ in
				FixedHeightView(height: 40)
			}
		)
	}

	private func makeListControllerHarness(
		items: [Int],
		configuration: ReorderableListConfiguration<Int, Int>,
		eventMonitoring: ReorderableListEventMonitoring = .live,
		performanceTracing: any ReorderableListPerformanceTracing = ReorderableListOSPerformanceTracing(),
		monotonicClock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
	) -> (
		controller: ReorderableListController<Int, Int>,
		hostView: NSView,
		tableView: ReorderableListTableView,
		overlayHostView: NSView
	) {
		let hostView = NSView(frame: CGRect(x: 0, y: 0, width: 280, height: 200))
		hostView.wantsLayer = true
		let scrollView = ReorderableListScrollView(frame: hostView.bounds)
		scrollView.hasVerticalScroller = true
		scrollView.contentView = ReorderableListClipView(frame: hostView.bounds)
		let documentView = ReorderableListDocumentView(frame: hostView.bounds)
		let tableView = ReorderableListTableView(frame: hostView.bounds)
		tableView.headerView = nil
		tableView.focusRingType = .none
		tableView.selectionHighlightStyle = .none
		tableView.backgroundColor = .clear
		tableView.rowHeight = configuration.estimatedRowHeight
		tableView.intercellSpacing = NSSize(width: 0, height: configuration.rowSpacing)
		let tableColumn = NSTableColumn(identifier: .reorderableListColumn)
		tableColumn.resizingMask = .autoresizingMask
		tableView.addTableColumn(tableColumn)
		documentView.addSubview(tableView)
		scrollView.documentView = documentView
		hostView.addSubview(scrollView)
		let overlayHostView = NSView(frame: hostView.bounds)
		overlayHostView.wantsLayer = true
		hostView.addSubview(overlayHostView)
		let controller = ReorderableListController(
			items: items,
			configuration: configuration,
			tableView: tableView,
			tableColumn: tableColumn,
			eventMonitoring: eventMonitoring,
			performanceTracing: performanceTracing,
			monotonicClock: monotonicClock
		)
		controller.attach(hostView: hostView, overlayHostView: overlayHostView)
		controller.reload()
		controller.layoutDidChange()
		return (controller, hostView, tableView, overlayHostView)
	}

	private func windowMouseLocation(
		for locationInContent: NSPoint,
		hostView: NSView,
		tableView: NSView
	) -> NSPoint {
		hostView.convert(locationInContent, from: tableView)
	}

	private func firstContainer(in list: ReorderableListView<Int, Int>) -> ReorderableListItemContainerView {
		containers(in: list).first!
	}

	private func containers(in list: ReorderableListView<Int, Int>) -> [ReorderableListItemContainerView] {
		(0..<list.numberOfRows(in: NSTableView())).compactMap {
			list.containerViewForTesting(row: $0)
		}
	}
}
