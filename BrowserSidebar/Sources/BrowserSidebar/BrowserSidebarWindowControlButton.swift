import AppKit

@MainActor
public final class BrowserSidebarWindowControlButton: NSButton {
	enum DisplayTone {
		case resting
		case hoverIndicator
	}

	public static let controlDiameter: CGFloat = 12
	private static let outerCircleDiameter: CGFloat = 12
	private static let hoverIndicatorDiameter: CGFloat = 6
	private static let restingShadowLevel: CGFloat = 0.18
	private static let hoverIndicatorShadowLevel: CGFloat = 0.5

	private let baseColor: NSColor
	private static let restingColor: NSColor = .systemGray
	private let outerCircleLayer = CALayer()
	private let hoverIndicatorLayer = CALayer()
	private var hoverTrackingArea: NSTrackingArea?
	private var isHovered = false

	public init(baseColor: NSColor) {
		self.baseColor = baseColor
		super.init(frame: .zero)
		title = ""
		image = nil
		isBordered = false
		bezelStyle = .regularSquare
		setButtonType(.momentaryPushIn)
		focusRingType = .none
		wantsLayer = true
		layer?.backgroundColor = NSColor.clear.cgColor
		layer?.masksToBounds = false

		outerCircleLayer.masksToBounds = true
		hoverIndicatorLayer.masksToBounds = true
		hoverIndicatorLayer.isHidden = true

		layer?.addSublayer(outerCircleLayer)
		layer?.addSublayer(hoverIndicatorLayer)
		applyResolvedColors()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override public func layout() {
		super.layout()
		updateCircleFrames()
		syncHoverStateForCurrentPointerLocation()
	}

	override public func updateTrackingAreas() {
		if let hoverTrackingArea {
			removeTrackingArea(hoverTrackingArea)
		}
		super.updateTrackingAreas()
		let trackingArea = NSTrackingArea(
			rect: bounds,
			options: [.activeInActiveApp, .inVisibleRect, .mouseEnteredAndExited],
			owner: self,
			userInfo: nil
		)
		addTrackingArea(trackingArea)
		hoverTrackingArea = trackingArea
		syncHoverStateForCurrentPointerLocation()
	}

	override public func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		syncHoverStateForCurrentPointerLocation()
	}

	override public func viewDidMoveToSuperview() {
		super.viewDidMoveToSuperview()
		syncHoverStateForCurrentPointerLocation()
	}

	override public func viewDidChangeEffectiveAppearance() {
		super.viewDidChangeEffectiveAppearance()
		applyResolvedColors()
	}

	override public func mouseEntered(with event: NSEvent) {
		super.mouseEntered(with: event)
		setHovered(true)
	}

	override public func mouseExited(with event: NSEvent) {
		super.mouseExited(with: event)
		setHovered(false)
	}

	public func refreshAppearance() {
		applyResolvedColors()
	}

	private func setHovered(_ isHovered: Bool) {
		guard self.isHovered != isHovered else { return }
		self.isHovered = isHovered
		hoverIndicatorLayer.isHidden = !isHovered
		applyRestingColor()
	}

	private func syncHoverStateForCurrentPointerLocation() {
		guard
			let window,
			isHidden == false,
			alphaValue > 0
		else {
			setHovered(false)
			return
		}

		let pointerLocation = convert(window.mouseLocationOutsideOfEventStream, from: nil)
		setHovered(bounds.contains(pointerLocation))
	}

	private func updateCircleFrames() {
		let outerCircleFrame = centeredFrame(forDiameter: Self.outerCircleDiameter)
		outerCircleLayer.frame = outerCircleFrame
		outerCircleLayer.cornerRadius = outerCircleFrame.width / 2

		let hoverIndicatorFrame = centeredFrame(forDiameter: Self.hoverIndicatorDiameter)
		hoverIndicatorLayer.frame = hoverIndicatorFrame
		hoverIndicatorLayer.cornerRadius = hoverIndicatorFrame.width / 2
	}

	private func centeredFrame(forDiameter diameter: CGFloat) -> CGRect {
		CGRect(
			x: (bounds.width - diameter) / 2,
			y: (bounds.height - diameter) / 2,
			width: diameter,
			height: diameter
		)
	}

	private func applyResolvedColors() {
		applyRestingColor()
		hoverIndicatorLayer.backgroundColor = Self.displayColor(
			for: baseColor,
			tone: .hoverIndicator,
			appearance: effectiveAppearance
		).cgColor
	}

	private func applyRestingColor() {
		let color = isHovered ? baseColor : Self.restingColor
		outerCircleLayer.backgroundColor = Self.displayColor(
			for: color,
			tone: .resting,
			appearance: effectiveAppearance
		).cgColor
	}

	private static func displayColor(
		for baseColor: NSColor,
		tone: DisplayTone,
		appearance: NSAppearance
	) -> NSColor {
		var resolvedColor = baseColor
		appearance.performAsCurrentDrawingAppearance {
			let dynamicColor = NSColor(cgColor: baseColor.cgColor) ?? baseColor
			let shadowLevel = switch tone {
			case .resting: restingShadowLevel
			case .hoverIndicator: hoverIndicatorShadowLevel
			}
			resolvedColor = dynamicColor.shadow(withLevel: shadowLevel) ?? dynamicColor
		}
		return resolvedColor
	}

	var outerCircleColorForTesting: CGColor? {
		outerCircleLayer.backgroundColor
	}

	var hoverIndicatorColorForTesting: CGColor? {
		hoverIndicatorLayer.backgroundColor
	}

	var isHoverIndicatorVisibleForTesting: Bool {
		hoverIndicatorLayer.isHidden == false
	}

	var outerCircleFrameForTesting: CGRect {
		outerCircleLayer.frame
	}

	var hoverIndicatorFrameForTesting: CGRect {
		hoverIndicatorLayer.frame
	}

	static func displayColorForTesting(
		baseColor: NSColor,
		tone: DisplayTone,
		appearance: NSAppearance
	) -> NSColor {
		displayColor(for: baseColor, tone: tone, appearance: appearance)
	}
}
