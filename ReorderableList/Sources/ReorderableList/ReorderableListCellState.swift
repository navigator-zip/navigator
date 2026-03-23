import Foundation

public struct ReorderableListCellState: Equatable, Sendable {
	public var isReordering: Bool
	public var isListReordering: Bool
	public var isHighlighted: Bool
	public var isSelected: Bool

	public init(
		isReordering: Bool,
		isListReordering: Bool,
		isHighlighted: Bool,
		isSelected: Bool
	) {
		self.isReordering = isReordering
		self.isListReordering = isListReordering
		self.isHighlighted = isHighlighted
		self.isSelected = isSelected
	}
}
