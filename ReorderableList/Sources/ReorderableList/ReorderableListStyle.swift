import Aesthetics
import AppKit
import Vendors

@MainActor
public enum ReorderableListStyle {
	static var animationSpring: Spring {
		Spring(dampingRatio: 1, response: 0.082)
	}

	public static let animationDuration: TimeInterval = animationSpring.settlingDuration
	static let liftAnimationDuration: TimeInterval = 0.15
	static let minimumSettleDuration: TimeInterval = 0.14
	static let maximumSettleDuration: TimeInterval = 0.22
	static let rowShiftAnimationDuration: TimeInterval = 0.12
	static let cornerRadius: CGFloat = 8
	static let borderWidth: CGFloat = 2
	static let liftedOverlayHorizontalInset: CGFloat = 15
	static let liftedOverlayCornerRadius: CGFloat = 10
	static let activeBorderOpacity: CGFloat = 0.8
	static let inactiveRowOpacity: CGFloat = 1
	static let activeScale: CGFloat = 1.02
	static let activeShadowOpacity: Float = 0.15
	static let activeShadowRadius: CGFloat = 10
	static let activeRotationDegrees: CGFloat = 3
	static let activeShadowColor = NSColor.black
	static let horizontalDragLinearLimit: CGFloat = 72
	static let maxHorizontalDragOffset: CGFloat = 144
	static let dropIndicatorHeight: CGFloat = 3
	static let dropIndicatorHorizontalInset: CGFloat = 12
	static let dragPlaceholderDashPattern = [8, 6] as [NSNumber]
	static let dragPlaceholderAnimationDuration: TimeInterval = 0.75
	static let dragPlaceholderStrokeColor = Color.navigatorChromeFill
	static let dragPlaceholderHorizontalInset: CGFloat = 10
	static let longPressDuration: TimeInterval = 0.3
	static let dragActivationSlop: CGFloat = 4

	static var accentColor: NSColor {
		Asset.Colors.accent.color
	}

	static func resolvedColor(
		_ color: NSColor,
		for appearance: NSAppearance
	) -> NSColor {
		resolvedColor(
			color,
			for: appearance,
			roundTripColor: NSColor.init(cgColor:)
		)
	}

	static func resolvedColor(
		_ color: NSColor,
		for appearance: NSAppearance,
		roundTripColor: (CGColor) -> NSColor?
	) -> NSColor {
		var resolvedColor = color
		appearance.performAsCurrentDrawingAppearance {
			resolvedColor = roundTripColor(color.cgColor) ?? color
		}
		return resolvedColor
	}

	static func liftedOverlayBounds(in bounds: CGRect) -> CGRect {
		bounds.insetBy(dx: liftedOverlayHorizontalInset, dy: 0)
	}

	static func liftedOverlayBorderBounds(in bounds: CGRect) -> CGRect {
		liftedOverlayBounds(in: bounds).insetBy(
			dx: borderWidth / 2,
			dy: borderWidth / 2
		)
	}
}
