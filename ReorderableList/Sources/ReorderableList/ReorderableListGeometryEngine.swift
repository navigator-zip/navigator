import AppKit

struct ReorderableListGeometryEngine {
	func draggedFrame(
		restingFrame: CGRect,
		pointerLocation: CGPoint,
		pointerOffsetFromRowCenter: CGPoint,
		linearLimit: CGFloat,
		maxOffset: CGFloat
	) -> CGRect {
		ReorderableListGeometry.draggedFrame(
			restingFrame: restingFrame,
			pointerLocation: pointerLocation,
			pointerOffset: pointerOffsetFromRowCenter,
			linearLimit: linearLimit,
			maxOffset: maxOffset
		)
	}

	func destinationIndex(
		targetCenterY: CGFloat,
		sourceIndex: Int,
		itemCount: Int,
		rowHeight: CGFloat,
		rowSpacing: CGFloat,
		contentInsets: NSEdgeInsets
	) -> Int {
		ReorderableListGeometry.fixedHeightDestinationIndex(
			for: targetCenterY,
			sourceIndex: sourceIndex,
			rowHeight: rowHeight,
			itemCount: itemCount,
			rowSpacing: rowSpacing,
			contentInsets: contentInsets
		)
	}

	func destinationIndex(
		targetCenterY: CGFloat,
		sourceIndex: Int,
		thresholdLayout: ReorderableListDestinationThresholdLayout?
	) -> Int {
		guard let thresholdLayout else {
			return sourceIndex
		}

		return ReorderableListGeometry.destinationIndex(
			for: targetCenterY,
			thresholdLayout: thresholdLayout,
			fallbackDestination: sourceIndex
		)
	}

	func thresholdLayoutForVariable(
		sourceIndex: Int,
		itemHeights: [CGFloat],
		rowSpacing: CGFloat,
		contentInsets: NSEdgeInsets
	) -> ReorderableListDestinationThresholdLayout? {
		ReorderableListGeometry.destinationThresholdLayout(
			sourceIndex: sourceIndex,
			itemHeights: itemHeights,
			rowSpacing: rowSpacing,
			contentInsets: contentInsets
		)
	}
}
