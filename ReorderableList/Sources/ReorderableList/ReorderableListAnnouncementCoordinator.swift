import AppKit

@MainActor
final class ReorderableListAnnouncementCoordinator {
	private let announce: @MainActor (String) -> Void
	private let accessibilityEnabled: () -> Bool

	init(
		accessibilityEnabled: @escaping () -> Bool,
		announce: @escaping @MainActor (String) -> Void
	) {
		self.accessibilityEnabled = accessibilityEnabled
		self.announce = announce
	}

	func announceReorderStart(totalCount: Int, initialIndex: Int) {
		guard accessibilityEnabled() else { return }
		announce(
			reorderableListReorderStartedAnnouncement(position: initialIndex + 1, totalCount: totalCount)
		)
	}

	func announceReorderDestination(
		sourceIndex: Int,
		insertionIndex: Int,
		rows: Int
	) {
		guard accessibilityEnabled() else { return }
		let finalPosition = resolvedFinalRowIndex(
			sourceIndex: sourceIndex,
			insertionIndex: insertionIndex,
			cancelled: false,
			rows: rows
		) + 1
		announce(
			reorderableListDestinationAnnouncement(position: finalPosition, totalCount: rows)
		)
	}

	func announceCompletedMove(
		from sourceIndex: Int,
		insertionIndex: Int,
		rows: Int
	) {
		guard accessibilityEnabled() else { return }
		let finalPosition = resolvedFinalRowIndex(
			sourceIndex: sourceIndex,
			insertionIndex: insertionIndex,
			cancelled: false,
			rows: rows
		) + 1
		announce(reorderableListCompletedAnnouncement(from: sourceIndex + 1, to: finalPosition))
	}

	func announceCancel() {
		guard accessibilityEnabled() else { return }
		announce(reorderableListCancelledAnnouncement())
	}
}

private func resolvedFinalRowIndex(
	sourceIndex: Int,
	insertionIndex: Int,
	cancelled: Bool,
	rows: Int
) -> Int {
	guard !cancelled else { return sourceIndex }
	guard rows > 0 else { return sourceIndex }

	if insertionIndex < 0 {
		return 0
	}
	if insertionIndex > rows {
		return rows - 1
	}
	return insertionIndex <= sourceIndex ? insertionIndex : min(insertionIndex, rows - 1)
}
