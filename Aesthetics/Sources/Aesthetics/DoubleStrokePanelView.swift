import AppKit

open class DoubleStrokePanelView: NSView {
	public var fillColor: NSColor {
		didSet {
			applyResolvedColors()
		}
	}

	public var cornerRadius: CGFloat {
		get { panelCornerRadius }
		set {
			panelCornerRadius = max(0, newValue)
			updatePanelGeometry()
		}
	}

	public var resolvedFillColor: NSColor {
		resolvedColor(fillColor, for: effectiveAppearance)
	}

	private var panelCornerRadius: CGFloat
	private let borderOverlayView: DoubleStrokePanelBorderOverlayView

	public init(
		frame frameRect: NSRect = .zero,
		fillColor: NSColor = Asset.Colors.background.color,
		cornerRadius: CGFloat = 8,
		outerBorderWidth: CGFloat = 2,
		innerBorderWidth: CGFloat = 1
	) {
		self.fillColor = fillColor
		panelCornerRadius = max(0, cornerRadius)
		borderOverlayView = DoubleStrokePanelBorderOverlayView(
			outerBorderWidth: outerBorderWidth,
			innerBorderWidth: innerBorderWidth
		)
		super.init(frame: frameRect)
		setupLayer()
	}

	@available(*, unavailable)
	public required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override open func layout() {
		super.layout()
		updatePanelGeometry()
	}

	override open func didAddSubview(_ subview: NSView) {
		super.didAddSubview(subview)
		guard subview !== borderOverlayView else { return }
		positionBorderOverlayAboveContent()
	}

	override open func viewDidChangeEffectiveAppearance() {
		super.viewDidChangeEffectiveAppearance()
		applyResolvedColors()
	}

	public func refreshDoubleStrokeAppearance() {
		updatePanelGeometry()
		applyResolvedColors()
	}

	private func setupLayer() {
		wantsLayer = true
		layer?.masksToBounds = true
		borderOverlayView.frame = bounds
		borderOverlayView.autoresizingMask = [.width, .height]
		addSubview(borderOverlayView)

		updatePanelGeometry()
		applyResolvedColors()
	}

	private func updatePanelGeometry() {
		layer?.cornerRadius = panelCornerRadius
		borderOverlayView.frame = bounds
		borderOverlayView.updateBorderGeometry(cornerRadius: panelCornerRadius)
		positionBorderOverlayAboveContent()
	}

	private func applyResolvedColors() {
		layer?.backgroundColor = resolvedFillColor.cgColor
		borderOverlayView.applyBorderColors(
			outerColor: resolvedColor(Asset.Colors.separatorPrimaryColor.color, for: effectiveAppearance),
			innerColor: resolvedColor(Asset.Colors.separatorSecondaryColor.color, for: effectiveAppearance)
		)
	}

	private func positionBorderOverlayAboveContent() {
		guard borderOverlayView.superview === self, subviews.last !== borderOverlayView else { return }
		addSubview(borderOverlayView, positioned: .above, relativeTo: nil)
	}

	private func resolvedColor(_ color: NSColor, for appearance: NSAppearance) -> NSColor {
		var resolvedColor = color
		appearance.performAsCurrentDrawingAppearance {
			resolvedColor = NSColor(cgColor: color.cgColor) ?? color
		}
		return resolvedColor
	}
}

private final class DoubleStrokePanelBorderOverlayView: NSView {
	private enum LayerConstants {
		static let overlayZPosition: CGFloat = 1
	}

	private let outerBorderWidth: CGFloat
	private let innerBorderWidth: CGFloat
	private let innerBorderLayer = CALayer()
	private var currentCornerRadius: CGFloat = 0

	init(outerBorderWidth: CGFloat, innerBorderWidth: CGFloat) {
		self.outerBorderWidth = outerBorderWidth
		self.innerBorderWidth = innerBorderWidth
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = NSColor.clear.cgColor
		layer?.borderWidth = outerBorderWidth
		layer?.masksToBounds = true
		layer?.zPosition = LayerConstants.overlayZPosition
		innerBorderLayer.backgroundColor = NSColor.clear.cgColor
		innerBorderLayer.borderWidth = innerBorderWidth
		layer?.addSublayer(innerBorderLayer)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func hitTest(_: NSPoint) -> NSView? {
		nil
	}

	override func layout() {
		super.layout()
		updateInnerBorderGeometry()
	}

	func updateBorderGeometry(cornerRadius: CGFloat) {
		currentCornerRadius = cornerRadius
		layer?.cornerRadius = cornerRadius
		updateInnerBorderGeometry()
	}

	func applyBorderColors(outerColor: NSColor, innerColor: NSColor) {
		layer?.borderColor = outerColor.cgColor
		innerBorderLayer.borderColor = innerColor.cgColor
	}

	private func updateInnerBorderGeometry() {
		innerBorderLayer.frame = bounds.insetBy(dx: outerBorderWidth, dy: outerBorderWidth)
		innerBorderLayer.cornerRadius = max(0, currentCornerRadius - outerBorderWidth)
	}
}
