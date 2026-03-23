import Foundation

public final class ActionBarViewModel {
	public let label: String
	public let listLabel: String
	public private(set) var query: String
	public private(set) var selectedValue: String?
	public private(set) var selectedItemID: String?
	public var onValueChange: ((String?) -> Void)?
	public init(label: String, listLabel: String) {
		self.label = label
		self.listLabel = listLabel
		self.query = ""
		self.selectedValue = nil
		self.selectedItemID = nil
	}

	public func updateQuery(_ query: String) {
		guard self.query != query else { return }
		self.query = query
		onValueChange?(query)
	}

	public func selectValue(_ value: String?) {
		selectedValue = value
		selectedItemID = value
		onValueChange?(value)
	}

	public func activateSelection() {
		onValueChange?(selectedValue)
	}
}
