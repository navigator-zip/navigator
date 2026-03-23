import AppKit

final class BrowserSidebarLabel: NSView {
	private let textLayer = CATextLayer()

	var stringValue: String = "" {
		didSet {
			textLayer.string = stringValue
			invalidateIntrinsicContentSize()
		}
	}

	var font: NSFont = .systemFont(ofSize: 13) {
		didSet {
			textLayer.font = font
			textLayer.fontSize = font.pointSize
			invalidateIntrinsicContentSize()
		}
	}

	var textColor: NSColor = .labelColor {
		didSet {
			textLayer.foregroundColor = textColor.cgColor
		}
	}

	var lineBreakMode: NSLineBreakMode = .byTruncatingTail {
		didSet {
			textLayer.truncationMode = lineBreakMode.caTextLayerTruncationMode
		}
	}

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.addSublayer(textLayer)
		textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
		textLayer.truncationMode = .end
		textLayer.allowsFontSubpixelQuantization = true
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func layout() {
		super.layout()
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		textLayer.frame = textLayerFrame()
		CATransaction.commit()
	}

	override func viewDidChangeBackingProperties() {
		super.viewDidChangeBackingProperties()
		if let scale = window?.backingScaleFactor {
			textLayer.contentsScale = scale
		}
	}

	override var intrinsicContentSize: NSSize {
		let size = measureText()
		return NSSize(width: size.width, height: size.height)
	}

	private func textLayerFrame() -> CGRect {
		let textHeight = measureText().height
		let y = (bounds.height - textHeight) / 2
		return CGRect(x: 0, y: y, width: bounds.width, height: textHeight)
	}

	private func measureText() -> CGSize {
		guard !stringValue.isEmpty else { return .zero }
		let attributes: [NSAttributedString.Key: Any] = [.font: font]
		let size = (stringValue as NSString).size(withAttributes: attributes)
		return CGSize(width: ceil(size.width), height: ceil(size.height))
	}
}

private extension NSLineBreakMode {
	var caTextLayerTruncationMode: CATextLayerTruncationMode {
		switch self {
		case .byTruncatingTail: .end
		case .byTruncatingHead: .start
		case .byTruncatingMiddle: .middle
		default: .none
		}
	}
}
