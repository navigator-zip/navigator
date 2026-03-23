import Foundation

@MainActor
public protocol ReorderableListItemCellStateObserver: AnyObject {
	func reorderableListItemDidUpdate(
		cellState: ReorderableListCellState,
		animated: Bool
	)
}
