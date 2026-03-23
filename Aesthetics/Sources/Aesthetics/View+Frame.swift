import AppKit

public extension NSView {
	func frame(dimension: CGFloat?, alignment: Any? = nil) -> Self {
		guard let dimension else { return self }
		let newFrame = CGRect(
			x: frame.origin.x,
			y: frame.origin.y,
			width: dimension,
			height: dimension
		)
		frame = newFrame
		return self
	}

	func frame(dimensions: CGSize, alignment: Any? = nil) -> Self {
		setFrameSize(NSSize(width: dimensions.width, height: dimensions.height))
		return self
	}

	func frame(size: CGSize, alignment: Any? = nil) -> Self {
		setFrameSize(NSSize(width: size.width, height: size.height))
		return self
	}
}
