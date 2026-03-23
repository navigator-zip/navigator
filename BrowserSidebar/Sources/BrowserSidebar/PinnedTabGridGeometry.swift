import Foundation

enum PinnedTabGridGeometry {
	static func destinationIndex(
		cursorInGrid: CGPoint,
		sourceIndex: Int,
		columnCount: Int,
		tileSize: CGFloat,
		interitemSpacing: CGFloat,
		lineSpacing: CGFloat,
		itemCount: Int
	) -> Int {
		guard itemCount > 0, columnCount > 0 else { return 0 }

		let tileStride = tileSize + interitemSpacing
		let lineStride = tileSize + lineSpacing

		let col = Int(floor(cursorInGrid.x / tileStride))
		let row = Int(floor(cursorInGrid.y / lineStride))

		let clampedCol = min(max(col, 0), columnCount - 1)
		let maxRow = (itemCount - 1) / columnCount
		let clampedRow = min(max(row, 0), maxRow)

		var linearIndex = clampedRow * columnCount + clampedCol
		linearIndex = min(max(linearIndex, 0), itemCount - 1)

		// Dead-zone: if we're within the source tile's bounds, return source index
		// to prevent flicker during small movements.
		let sourceCol = sourceIndex % columnCount
		let sourceRow = sourceIndex / columnCount
		let sourceCenterX = CGFloat(sourceCol) * tileStride + tileSize / 2
		let sourceCenterY = CGFloat(sourceRow) * lineStride + tileSize / 2
		let deadZoneRadius = tileSize * 0.3
		let dx = cursorInGrid.x - sourceCenterX
		let dy = cursorInGrid.y - sourceCenterY
		if (dx * dx + dy * dy) < (deadZoneRadius * deadZoneRadius) {
			return sourceIndex
		}

		return linearIndex
	}

	static func externalInsertionIndex(
		cursorInGrid: CGPoint,
		columnCount: Int,
		tileSize: CGFloat,
		interitemSpacing: CGFloat,
		lineSpacing: CGFloat,
		itemCount: Int
	) -> Int {
		guard itemCount > 0, columnCount > 0 else { return 0 }

		let tileStride = tileSize + interitemSpacing
		let lineStride = tileSize + lineSpacing

		let col = Int(floor(cursorInGrid.x / tileStride))
		let row = Int(floor(cursorInGrid.y / lineStride))

		let clampedCol = min(max(col, 0), columnCount - 1)
		let maxRow = itemCount / columnCount
		let clampedRow = min(max(row, 0), maxRow)

		let linearIndex = clampedRow * columnCount + clampedCol
		return min(max(linearIndex, 0), itemCount)
	}

	static func externalInsertionDisplacementForTile(
		at tileIndex: Int,
		insertionIndex: Int,
		columnCount: Int,
		tileStride: CGSize
	) -> CGPoint {
		guard tileIndex >= insertionIndex else { return .zero }

		let currentCol = tileIndex % columnCount
		let currentRow = tileIndex / columnCount
		let displacedIndex = tileIndex + 1
		let displacedCol = displacedIndex % columnCount
		let displacedRow = displacedIndex / columnCount

		return CGPoint(
			x: CGFloat(displacedCol - currentCol) * tileStride.width,
			y: CGFloat(displacedRow - currentRow) * tileStride.height
		)
	}

	static func displacementForTile(
		at tileIndex: Int,
		sourceIndex: Int,
		insertionIndex: Int,
		columnCount: Int,
		tileStride: CGSize
	) -> CGPoint {
		guard tileIndex != sourceIndex else { return .zero }

		let shift: Int
		if insertionIndex > sourceIndex,
		   tileIndex > sourceIndex,
		   tileIndex <= insertionIndex {
			shift = -1
		} else if insertionIndex < sourceIndex,
		          tileIndex >= insertionIndex,
		          tileIndex < sourceIndex {
			shift = 1
		} else {
			return .zero
		}

		let currentCol = tileIndex % columnCount
		let currentRow = tileIndex / columnCount
		let displacedIndex = tileIndex + shift
		let displacedCol = displacedIndex % columnCount
		let displacedRow = displacedIndex / columnCount

		return CGPoint(
			x: CGFloat(displacedCol - currentCol) * tileStride.width,
			y: CGFloat(displacedRow - currentRow) * tileStride.height
		)
	}
}
