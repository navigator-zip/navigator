import AppKit

enum ReorderableListGeometry {
	private static let upwardDropActivationFraction: CGFloat = 0.1
	private static let downwardDropActivationFraction: CGFloat = 0.9

	static func contentHeight(
		itemHeights: [CGFloat],
		rowSpacing: CGFloat = 0,
		contentInsets: NSEdgeInsets
	) -> CGFloat {
		let totalSpacing = rowSpacing * CGFloat(max(itemHeights.count - 1, 0))
		return contentInsets.top + itemHeights.reduce(0, +) + totalSpacing + contentInsets.bottom
	}

	static func frames(
		for orderedHeights: [CGFloat],
		width: CGFloat,
		rowSpacing: CGFloat = 0,
		contentInsets: NSEdgeInsets
	) -> [CGRect] {
		var nextY = contentInsets.top
		return orderedHeights.enumerated().map { index, height in
			defer {
				nextY += height
				if index < orderedHeights.count - 1 {
					nextY += rowSpacing
				}
			}
			return CGRect(
				x: contentInsets.left,
				y: nextY,
				width: max(0, width - contentInsets.left - contentInsets.right),
				height: height
			)
		}
	}

	static func reorderedIndices(
		count: Int,
		moving sourceIndex: Int,
		to destinationIndex: Int
	) -> [Int] {
		guard count > 0 else { return [] }
		guard sourceIndex >= 0, sourceIndex < count else { return Array(0..<count) }
		var indices = Array(0..<count)
		let movedIndex = indices.remove(at: sourceIndex)
		let boundedDestination = min(max(destinationIndex, 0), count)
		let insertionIndex: Int = if boundedDestination > sourceIndex {
			min(boundedDestination - 1, indices.count)
		}
		else {
			min(boundedDestination, indices.count)
		}
		indices.insert(movedIndex, at: insertionIndex)
		return indices
	}

	static func reorderedValues<Value>(
		_ values: [Value],
		moving sourceIndex: Int,
		to destinationIndex: Int
	) -> [Value] {
		reorderedIndices(count: values.count, moving: sourceIndex, to: destinationIndex)
			.map { values[$0] }
	}

	static func destinationIndex(
		for targetCenterY: CGFloat,
		sourceIndex: Int,
		itemHeights: [CGFloat],
		width: CGFloat,
		rowSpacing: CGFloat = 0,
		contentInsets: NSEdgeInsets
	) -> Int {
		guard !itemHeights.isEmpty else { return 0 }
		let _ = width
		guard let thresholdLayout = destinationThresholdLayout(
			sourceIndex: sourceIndex,
			itemHeights: itemHeights,
			rowSpacing: rowSpacing,
			contentInsets: contentInsets
		) else {
			return sourceIndex
		}
		return destinationIndex(
			for: targetCenterY,
			thresholdLayout: thresholdLayout,
			fallbackDestination: sourceIndex
		)
	}

	static func destinationPreviewCenters(
		sourceIndex: Int,
		itemHeights: [CGFloat],
		rowSpacing: CGFloat = 0,
		contentInsets: NSEdgeInsets
	) -> [CGFloat] {
		guard !itemHeights.isEmpty,
		      sourceIndex >= 0,
		      sourceIndex < itemHeights.count else {
			return []
		}

		let movedItemHeight = itemHeights[sourceIndex]
		let prefixHeights = itemHeights.reduce(into: [CGFloat](arrayLiteral: 0)) { partialResult, height in
			partialResult.append(partialResult[partialResult.endIndex - 1] + height)
		}

		return (0...itemHeights.count).map { destinationIndex in
			let originY: CGFloat = if destinationIndex <= sourceIndex {
				contentInsets.top + prefixHeights[destinationIndex]
					+ (rowSpacing * CGFloat(destinationIndex))
			}
			else {
				contentInsets.top
					+ (prefixHeights[destinationIndex] - movedItemHeight)
					+ (rowSpacing * CGFloat(destinationIndex - 1))
			}
			return originY + (movedItemHeight / 2)
		}
	}

	static func destinationIndex(
		for targetCenterY: CGFloat,
		thresholdLayout: ReorderableListDestinationThresholdLayout,
		fallbackDestination: Int
	) -> Int {
		let thresholds = thresholdLayout.thresholds
		guard !thresholds.isEmpty,
		      thresholdLayout.sourceIndex >= 0,
		      thresholdLayout.sourceIndex < thresholds.count else {
			return fallbackDestination
		}

		let finalRowPosition: Int
		if targetCenterY < thresholdLayout.sourceUpperThresholdY {
			var candidate = thresholdLayout.sourceIndex
			for rowIndex in stride(from: thresholdLayout.sourceIndex - 1, through: 0, by: -1) {
				if targetCenterY < thresholds[rowIndex] {
					candidate = rowIndex
					continue
				}
				break
			}
			finalRowPosition = candidate
		}
		else if targetCenterY > thresholdLayout.sourceLowerThresholdY {
			var candidate = thresholdLayout.sourceIndex
			for rowIndex in (thresholdLayout.sourceIndex + 1)..<thresholds.count {
				if targetCenterY > thresholds[rowIndex] {
					candidate = rowIndex
					continue
				}
				break
			}
			finalRowPosition = candidate
		}
		else {
			finalRowPosition = thresholdLayout.sourceIndex
		}

		return insertionIndex(
			forFinalRowPosition: finalRowPosition,
			sourceIndex: thresholdLayout.sourceIndex
		)
	}

	static func destinationThresholdLayout(
		sourceIndex: Int,
		itemHeights: [CGFloat],
		rowSpacing: CGFloat = 0,
		contentInsets: NSEdgeInsets
	) -> ReorderableListDestinationThresholdLayout? {
		guard !itemHeights.isEmpty,
		      sourceIndex >= 0,
		      sourceIndex < itemHeights.count else {
			return nil
		}

		let rowFrames = frames(
			for: itemHeights,
			width: 0,
			rowSpacing: rowSpacing,
			contentInsets: contentInsets
		)
		let sourceFrame = rowFrames[sourceIndex]
		let thresholds = rowFrames.enumerated().map { rowIndex, frame in
			let activationFraction: CGFloat = if rowIndex < sourceIndex {
				upwardDropActivationFraction
			}
			else if rowIndex > sourceIndex {
				downwardDropActivationFraction
			}
			else {
				0.5
			}
			return frame.minY + (frame.height * activationFraction)
		}

		return ReorderableListDestinationThresholdLayout(
			sourceIndex: sourceIndex,
			thresholds: thresholds,
			sourceUpperThresholdY: sourceFrame.minY + (sourceFrame.height * upwardDropActivationFraction),
			sourceLowerThresholdY: sourceFrame.minY + (sourceFrame.height * downwardDropActivationFraction)
		)
	}

	static func fixedHeightDestinationIndex(
		for targetCenterY: CGFloat,
		sourceIndex: Int,
		rowHeight: CGFloat,
		itemCount: Int,
		rowSpacing: CGFloat = 0,
		contentInsets: NSEdgeInsets
	) -> Int {
		guard itemCount > 0,
		      sourceIndex >= 0,
		      sourceIndex < itemCount,
		      rowHeight > 0 else {
			return 0
		}

		let rowSpan = rowHeight + rowSpacing
		let sourceRowMinY = contentInsets.top + (CGFloat(sourceIndex) * rowSpan)
		let sourceUpperThresholdY = sourceRowMinY + (rowHeight * upwardDropActivationFraction)
		let sourceLowerThresholdY = sourceRowMinY + (rowHeight * downwardDropActivationFraction)

		let finalRowPosition: Int
		if targetCenterY < sourceUpperThresholdY {
			var candidate = sourceIndex
			for rowIndex in stride(from: sourceIndex - 1, through: 0, by: -1) {
				let rowMinY = contentInsets.top + (CGFloat(rowIndex) * rowSpan)
				let thresholdY = rowMinY + (rowHeight * upwardDropActivationFraction)
				if targetCenterY < thresholdY {
					candidate = rowIndex
					continue
				}
				break
			}
			finalRowPosition = candidate
		}
		else if targetCenterY > sourceLowerThresholdY {
			var candidate = sourceIndex
			for rowIndex in (sourceIndex + 1)..<itemCount {
				let rowMinY = contentInsets.top + (CGFloat(rowIndex) * rowSpan)
				let thresholdY = rowMinY + (rowHeight * downwardDropActivationFraction)
				if targetCenterY > thresholdY {
					candidate = rowIndex
					continue
				}
				break
			}
			finalRowPosition = candidate
		}
		else {
			finalRowPosition = sourceIndex
		}

		return insertionIndex(
			forFinalRowPosition: finalRowPosition,
			sourceIndex: sourceIndex
		)
	}

	static func fixedHeightInsertionIndex(
		for dragCenterY: CGFloat,
		rowHeight: CGFloat,
		itemCount: Int
	) -> Int {
		guard itemCount > 0, rowHeight > 0 else { return 0 }
		let rawSlot = Int(floor(dragCenterY / rowHeight))
		return min(max(rawSlot, 0), itemCount)
	}

	static func affectedRange(
		sourceIndex: Int,
		insertionIndex: Int
	) -> ClosedRange<Int>? {
		if insertionIndex > sourceIndex {
			let upperBound = insertionIndex - 1
			guard upperBound >= sourceIndex + 1 else { return nil }
			return (sourceIndex + 1)...upperBound
		}

		if insertionIndex < sourceIndex {
			return insertionIndex...(sourceIndex - 1)
		}

		return nil
	}

	static func displacementOffsetForRow(
		rowIndex: Int,
		sourceIndex: Int,
		insertionIndex: Int,
		rowHeight: CGFloat
	) -> CGFloat {
		guard rowIndex != sourceIndex else { return 0 }

		if insertionIndex > sourceIndex,
		   rowIndex >= sourceIndex + 1,
		   rowIndex < insertionIndex {
			return -rowHeight
		}

		if insertionIndex < sourceIndex,
		   rowIndex >= insertionIndex,
		   rowIndex < sourceIndex {
			return rowHeight
		}

		return 0
	}

	static func draggedFrame(
		restingFrame: CGRect,
		pointerLocation: CGPoint,
		pointerOffset: CGPoint,
		linearLimit: CGFloat,
		maxOffset: CGFloat
	) -> CGRect {
		let targetCenterY = pointerLocation.y + pointerOffset.y
		let targetCenterX = pointerLocation.x + pointerOffset.x
		let rawHorizontalOffset = targetCenterX - restingFrame.midX
		let rubberBandedHorizontalOffset = rubberBandedOffset(
			for: rawHorizontalOffset,
			linearLimit: linearLimit,
			maxOffset: maxOffset
		)

		var draggedFrame = restingFrame
		draggedFrame.origin.x += rubberBandedHorizontalOffset
		draggedFrame.origin.y = targetCenterY - (restingFrame.height / 2)
		return draggedFrame
	}

	static func rubberBandedOffset(
		for rawOffset: CGFloat,
		linearLimit: CGFloat,
		maxOffset: CGFloat
	) -> CGFloat {
		guard maxOffset > 0 else { return 0 }

		let direction: CGFloat = rawOffset >= 0 ? 1 : -1
		let distance = abs(rawOffset)
		let resolvedLinearLimit = min(max(0, linearLimit), maxOffset)

		guard distance > resolvedLinearLimit else { return rawOffset }
		let remainingDistance = maxOffset - resolvedLinearLimit
		guard remainingDistance > 0 else { return direction * maxOffset }

		let overflowDistance = distance - resolvedLinearLimit
		let rubberBandedOverflow = remainingDistance * (
			1 - exp(-overflowDistance / remainingDistance)
		)
		return direction * min(
			maxOffset,
			resolvedLinearLimit + rubberBandedOverflow
		)
	}

	static func externalInsertionDisplacementForRow(
		rowIndex: Int,
		insertionIndex: Int,
		rowHeight: CGFloat
	) -> CGFloat {
		rowIndex >= insertionIndex ? rowHeight : 0
	}

	private static func insertionIndex(
		forFinalRowPosition finalRowPosition: Int,
		sourceIndex: Int
	) -> Int {
		if finalRowPosition < sourceIndex {
			return finalRowPosition
		}
		if finalRowPosition > sourceIndex {
			return finalRowPosition + 1
		}
		return sourceIndex
	}
}
