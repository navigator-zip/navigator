import AppKit

public struct ReorderableListDragChromeGeometry {
	public var chromeFrame: CGRect
	public var cornerRadius: CGFloat
	public var borderWidth: CGFloat

	public init(
		chromeFrame: CGRect,
		cornerRadius: CGFloat,
		borderWidth: CGFloat
	) {
		self.chromeFrame = chromeFrame
		self.cornerRadius = cornerRadius
		self.borderWidth = borderWidth
	}
}

@MainActor
public protocol ReorderableListDragChromePathProviding: AnyObject {
	func reorderableListDragChromeGeometry() -> ReorderableListDragChromeGeometry?
}
