import AppKit

@MainActor
public protocol ReorderableListHandleProviding: AnyObject {
	var reorderHandleRect: NSRect? { get }
}
