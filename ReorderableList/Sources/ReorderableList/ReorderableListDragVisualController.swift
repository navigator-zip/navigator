import AppKit

struct ReorderableListDragVisualState: Equatable {
	var center: CGPoint
	var bounds: CGRect
	var scale: CGFloat
	var rotationRadians: CGFloat
	var shadowOpacity: Float
	var shadowRadius: CGFloat
	var borderOpacity: Float
	var opacity: Float
	var translation: CGSize

	static func rest(frame: CGRect) -> Self {
		Self(
			center: CGPoint(x: frame.midX, y: frame.midY),
			bounds: CGRect(origin: .zero, size: frame.size),
			scale: 1,
			rotationRadians: 0,
			shadowOpacity: 0,
			shadowRadius: 0,
			borderOpacity: 0,
			opacity: 1,
			translation: .zero
		)
	}

	static func lifted(
		frame: CGRect,
		appearance: ReorderDragAppearance
	) -> Self {
		Self(
			center: CGPoint(x: frame.midX, y: frame.midY),
			bounds: CGRect(origin: .zero, size: frame.size),
			scale: appearance.scale,
			rotationRadians: appearance.rotationRadians,
			shadowOpacity: appearance.shadowOpacity,
			shadowRadius: appearance.shadowRadius,
			borderOpacity: Float(appearance.borderOpacity),
			opacity: Float(appearance.opacity),
			translation: appearance.translationOffset
		)
	}
}

enum ReorderableListDragVisualPhase: Equatable {
	case idle
	case lifting
	case dragging
	case settling(commit: Bool)
}

@MainActor
public final class ReorderableListDragVisualController {
	private struct ResolvedDragChromeGeometry {
		let referenceSize: CGSize
		let chromeFrame: CGRect
		let cornerRadius: CGFloat
		let borderWidth: CGFloat
	}

	private let overlayLayer = ReorderableListAnimationLayer()
	private let backgroundLayer = ReorderableListAnimationLayer()
	private let contentLayer = ReorderableListAnimationLayer()
	private let transitionContentLayer = ReorderableListAnimationLayer()
	private let borderLayer = ReorderableListAnimationShapeLayer()

	public init() {}

	private weak var hostView: NSView?
	private(set) var phase: ReorderableListDragVisualPhase = .idle
	private(set) var animationTransactionID: UInt = 0
	public private(set) var settleDuration: TimeInterval?
	private var currentState: ReorderableListDragVisualState?
	private var currentAppearance = ReorderDragAppearance()
	private var currentChromeGeometry: ResolvedDragChromeGeometry?
	private var naturalDragFrameSize: CGSize?
	private var activeShapeOverride: (size: CGSize, cornerRadius: CGFloat)?
	private var positionOnlyUpdateCount = 0
	private var boundsUpdateCount = 0
	private var shapePathUpdateCount = 0

	private static let shapeTransitionDuration: TimeInterval = 0.2

	var currentFrameInHost: CGRect? {
		frame(for: overlayLayer)
	}

	var presentationFrameInHost: CGRect? {
		frame(for: overlayLayer.presentation() ?? overlayLayer)
	}

	var isActive: Bool {
		overlayLayer.superlayer != nil
	}

	var borderOpacityForTesting: Float {
		(borderLayer.presentation() ?? borderLayer).opacity
	}

	var shadowOpacityForTesting: Float {
		(overlayLayer.presentation() ?? overlayLayer).shadowOpacity
	}

	var currentRotationRadiansForTesting: CGFloat {
		resolvedRotation(from: (overlayLayer.presentation() ?? overlayLayer).transform)
	}

	var borderPathBoundsForTesting: CGRect? {
		borderLayer.path?.boundingBoxOfPath
	}

	var shadowPathBoundsForTesting: CGRect? {
		overlayLayer.shadowPath?.boundingBoxOfPath
	}

	var backgroundFrameForTesting: CGRect {
		backgroundLayer.frame
	}

	var borderFrameForTesting: CGRect {
		borderLayer.frame
	}

	var positionOnlyUpdateCountForTesting: Int {
		positionOnlyUpdateCount
	}

	var boundsUpdateCountForTesting: Int {
		boundsUpdateCount
	}

	var shapePathUpdateCountForTesting: Int {
		shapePathUpdateCount
	}

	public func attach(to hostView: NSView) {
		self.hostView = hostView
		hostView.wantsLayer = true
	}

	public func overrideNaturalDragFrameSize(_ size: CGSize) {
		naturalDragFrameSize = size
	}

	public func beginLift(
		snapshotImage: NSImage,
		frame: CGRect,
		backgroundColor: NSColor,
		appearance: ReorderDragAppearance,
		chromeGeometry: ReorderableListDragChromeGeometry? = nil
	) {
		guard let hostLayer = resolvedHostLayer() else { return }
		animationTransactionID &+= 1
		settleDuration = nil
		currentAppearance = appearance
		naturalDragFrameSize = frame.size
		activeShapeOverride = nil
		currentChromeGeometry = chromeGeometry.map {
			ResolvedDragChromeGeometry(
				referenceSize: frame.size,
				chromeFrame: $0.chromeFrame,
				cornerRadius: $0.cornerRadius,
				borderWidth: $0.borderWidth
			)
		}
		configureOverlayIfNeeded(backgroundColor: backgroundColor)
		overlayLayer.removeFromSuperlayer()
		hostLayer.addSublayer(overlayLayer)

		contentLayer.contents = snapshotImage
		contentLayer.contentsGravity = .resize
		contentLayer.frame = CGRect(origin: .zero, size: frame.size)
		contentLayer.opacity = 1
		transitionContentLayer.contents = nil
		transitionContentLayer.opacity = 0
		transitionContentLayer.frame = CGRect(origin: .zero, size: frame.size)
		apply(state: .rest(frame: frame))
		phase = .lifting
		animate(
			from: .rest(frame: frame),
			to: .lifted(frame: frame, appearance: appearance),
			duration: ReorderableListStyle.liftAnimationDuration,
			timingFunctionName: .easeOut
		)
	}

	@discardableResult
	public func updateDraggedFrame(_ frame: CGRect) -> ReorderableListDragVisualUpdateKind {
		guard var currentState else { return .none }
		let nextCenter = CGPoint(x: frame.midX, y: frame.midY)
		let nextBounds = activeShapeOverride.map { CGRect(origin: .zero, size: $0.size) }
			?? CGRect(origin: .zero, size: frame.size)
		let centerChanged = currentState.center != nextCenter
		let boundsChanged = currentState.bounds != nextBounds
		guard centerChanged || boundsChanged else { return .none }
		currentState.center = nextCenter
		currentState.bounds = nextBounds
		self.currentState = currentState

		CATransaction.begin()
		CATransaction.setDisableActions(true)
		overlayLayer.position = currentState.center
		if boundsChanged {
			overlayLayer.bounds = currentState.bounds
			contentLayer.frame = overlayLayer.bounds
			updateShapePath()
		}
		CATransaction.commit()
		phase = .dragging
		if boundsChanged {
			boundsUpdateCount += 1
			return .boundsChanged
		}
		positionOnlyUpdateCount += 1
		return .positionOnly
	}

	public func freezeToPresentation() {
		guard overlayLayer.superlayer != nil else { return }
		let presentationOverlay = overlayLayer.presentation()
		let presentationBorder = borderLayer.presentation()

		CATransaction.begin()
		CATransaction.setDisableActions(true)
		if let presentationOverlay {
			overlayLayer.position = presentationOverlay.position
			overlayLayer.bounds = presentationOverlay.bounds
			overlayLayer.transform = presentationOverlay.transform
			overlayLayer.opacity = presentationOverlay.opacity
			overlayLayer.shadowOpacity = presentationOverlay.shadowOpacity
			overlayLayer.shadowRadius = presentationOverlay.shadowRadius
		}
		if let presentationBorder {
			borderLayer.opacity = presentationBorder.opacity
		}
		if let presentationContent = contentLayer.presentation() {
			contentLayer.opacity = presentationContent.opacity
		}
		if let presentationTransition = transitionContentLayer.presentation() {
			transitionContentLayer.opacity = presentationTransition.opacity
		}
		contentLayer.frame = overlayLayer.bounds
		transitionContentLayer.frame = overlayLayer.bounds
		updateShapePath()
		CATransaction.commit()

		overlayLayer.removeAllAnimations()
		borderLayer.removeAllAnimations()
		contentLayer.removeAllAnimations()
		transitionContentLayer.removeAllAnimations()

		currentState = ReorderableListDragVisualState(
			center: overlayLayer.position,
			bounds: overlayLayer.bounds,
			scale: resolvedScale(from: overlayLayer.transform),
			rotationRadians: resolvedRotation(from: overlayLayer.transform),
			shadowOpacity: overlayLayer.shadowOpacity,
			shadowRadius: overlayLayer.shadowRadius,
			borderOpacity: borderLayer.opacity,
			opacity: overlayLayer.opacity,
			translation: currentAppearance.translationOffset
		)
	}

	public func beginSettle(
		to targetFrame: CGRect,
		commit: Bool,
		backgroundColor: NSColor,
		appearance: ReorderDragAppearance,
		animated: Bool,
		durationOverride: TimeInterval? = nil
	) {
		currentAppearance = appearance
		activeShapeOverride = nil
		configureOverlayIfNeeded(backgroundColor: backgroundColor)
		freezeToPresentation()
		animationTransactionID &+= 1
		phase = .settling(commit: commit)

		guard animated else {
			settleDuration = 0
			apply(state: .rest(frame: targetFrame))
			return
		}

		let sourceFrame = currentFrameInHost!
		let duration = durationOverride ?? Self.resolvedSettleDuration(from: sourceFrame, to: targetFrame)
		settleDuration = duration
		animate(
			from: currentState ?? .lifted(frame: targetFrame, appearance: appearance),
			to: .rest(frame: targetFrame),
			duration: duration,
			timingFunctionName: .easeOut
		)
	}

	public func tearDown() {
		overlayLayer.removeAllAnimations()
		borderLayer.removeAllAnimations()
		contentLayer.removeAllAnimations()
		transitionContentLayer.removeAllAnimations()
		overlayLayer.removeFromSuperlayer()
		currentState = nil
		currentAppearance = ReorderDragAppearance()
		currentChromeGeometry = nil
		naturalDragFrameSize = nil
		activeShapeOverride = nil
		settleDuration = nil
		phase = .idle
	}

	public func overrideDragShape(to size: CGSize, cornerRadius: CGFloat, targetSnapshot: NSImage?, animated: Bool) {
		guard activeShapeOverride?.size != size || activeShapeOverride?.cornerRadius != cornerRadius else { return }
		// Capture source state BEFORE mutating activeShapeOverride so resolvedChromeGeometry
		// uses the old override (or nil), giving the correct source corner radius.
		let sourceBounds = (overlayLayer.presentation() ?? overlayLayer).bounds
		let sourceChrome = resolvedChromeGeometry(in: sourceBounds)
		activeShapeOverride = (size: size, cornerRadius: cornerRadius)
		let targetBounds = CGRect(origin: .zero, size: size)
		applyShapeChange(to: targetBounds, sourceBounds: sourceBounds, sourceChrome: sourceChrome, cornerRadius: cornerRadius, targetSnapshot: targetSnapshot, animated: animated)
	}

	public func clearDragShapeOverride(animated: Bool, targetSnapshot: NSImage? = nil, sourceCursorX: CGFloat? = nil, targetCenterX: CGFloat? = nil) {
		guard activeShapeOverride != nil else { return }
		// Capture source state BEFORE mutating activeShapeOverride.
		let sourceBounds = (overlayLayer.presentation() ?? overlayLayer).bounds
		let sourceChrome = resolvedChromeGeometry(in: sourceBounds)
		activeShapeOverride = nil
		guard let naturalSize = naturalDragFrameSize else { return }
		let targetBounds = CGRect(origin: .zero, size: naturalSize)
		applyShapeChange(
			to: targetBounds,
			sourceBounds: sourceBounds,
			sourceChrome: sourceChrome,
			cornerRadius: nil,
			targetSnapshot: targetSnapshot,
			animated: animated,
			sourceCursorX: sourceCursorX,
			targetCenterX: targetCenterX
		)
	}

	private func applyShapeChange(
		to targetBounds: CGRect,
		sourceBounds: CGRect,
		sourceChrome: (frame: CGRect, cornerRadius: CGFloat, borderWidth: CGFloat),
		cornerRadius: CGFloat?,
		targetSnapshot: NSImage?,
		animated: Bool,
		sourceCursorX: CGFloat? = nil,
		targetCenterX: CGFloat? = nil
	) {
		guard overlayLayer.superlayer != nil else { return }
		let targetChrome = resolvedChromeGeometryForBounds(targetBounds, cornerRadiusOverride: cornerRadius)

		// Determine content opacity targets.
		// If a target snapshot is provided we're going to pinned state (fade row out, tile in).
		// If returning to row state, always restore contentLayer to full opacity.
		let targetContentOpacity: Float = (targetSnapshot != nil) ? 0 : 1
		let targetTransitionOpacity: Float = (targetSnapshot != nil) ? 1 : 0

		// Read source opacities from presentation before we mutate model values.
		let sourceContentOpacity = (contentLayer.presentation() ?? contentLayer).opacity
		let sourceTransitionOpacity = (transitionContentLayer.presentation() ?? transitionContentLayer).opacity

		CATransaction.begin()
		CATransaction.setDisableActions(true)
		overlayLayer.bounds = targetBounds
		// If a target center X is provided (tile→row), snap the model to resting_X so
		// the additive position.x animation can decay to zero without a snap at completion.
		if let targetCenterX {
			overlayLayer.position = CGPoint(x: targetCenterX, y: overlayLayer.position.y)
		}
		if let currentState {
			self.currentState = ReorderableListDragVisualState(
				center: CGPoint(
					x: targetCenterX ?? currentState.center.x,
					y: currentState.center.y
				),
				bounds: targetBounds,
				scale: currentState.scale,
				rotationRadians: currentState.rotationRadians,
				shadowOpacity: currentState.shadowOpacity,
				shadowRadius: currentState.shadowRadius,
				borderOpacity: currentState.borderOpacity,
				opacity: currentState.opacity,
				translation: currentState.translation
			)
		}
		backgroundLayer.frame = targetChrome.frame
		backgroundLayer.cornerRadius = targetChrome.cornerRadius
		borderLayer.frame = targetChrome.frame
		let borderInset = targetChrome.borderWidth / 2
		borderLayer.path = CGPath(
			roundedRect: borderLayer.bounds.insetBy(dx: borderInset, dy: borderInset),
			cornerWidth: max(0, targetChrome.cornerRadius - borderInset),
			cornerHeight: max(0, targetChrome.cornerRadius - borderInset),
			transform: nil
		)
		overlayLayer.shadowPath = CGPath(
			roundedRect: targetChrome.frame,
			cornerWidth: targetChrome.cornerRadius,
			cornerHeight: targetChrome.cornerRadius,
			transform: nil
		)
		contentLayer.frame = targetBounds
		transitionContentLayer.frame = targetBounds
		if let targetSnapshot {
			transitionContentLayer.contents = targetSnapshot
		}
		contentLayer.opacity = targetContentOpacity
		transitionContentLayer.opacity = targetTransitionOpacity
		CATransaction.commit()

		guard animated else { return }

		// overlayLayer: bounds + shadowPath
		addSpringAnimation(
			keyPath: "bounds",
			fromValue: NSValue(rect: sourceBounds),
			toValue: NSValue(rect: targetBounds),
			layer: overlayLayer
		)
		let sourceShadowPath = CGPath(
			roundedRect: sourceChrome.frame,
			cornerWidth: sourceChrome.cornerRadius,
			cornerHeight: sourceChrome.cornerRadius,
			transform: nil
		)
		let targetShadowPath = CGPath(
			roundedRect: targetChrome.frame,
			cornerWidth: targetChrome.cornerRadius,
			cornerHeight: targetChrome.cornerRadius,
			transform: nil
		)
		addSpringAnimation(
			keyPath: "shadowPath",
			fromValue: sourceShadowPath,
			toValue: targetShadowPath,
			layer: overlayLayer
		)

		// contentLayer + transitionContentLayer: bounds + position + optional opacity cross-fade
		addSpringAnimation(
			keyPath: "bounds",
			fromValue: NSValue(rect: sourceBounds),
			toValue: NSValue(rect: targetBounds),
			layer: contentLayer
		)
		addSpringAnimation(
			keyPath: "position",
			fromValue: NSValue(point: CGPoint(x: sourceBounds.width / 2, y: sourceBounds.height / 2)),
			toValue: NSValue(point: CGPoint(x: targetBounds.width / 2, y: targetBounds.height / 2)),
			layer: contentLayer
		)
		addSpringAnimation(
			keyPath: "bounds",
			fromValue: NSValue(rect: sourceBounds),
			toValue: NSValue(rect: targetBounds),
			layer: transitionContentLayer
		)
		addSpringAnimation(
			keyPath: "position",
			fromValue: NSValue(point: CGPoint(x: sourceBounds.width / 2, y: sourceBounds.height / 2)),
			toValue: NSValue(point: CGPoint(x: targetBounds.width / 2, y: targetBounds.height / 2)),
			layer: transitionContentLayer
		)
		if sourceContentOpacity != targetContentOpacity {
			addSpringAnimation(
				keyPath: "opacity",
				fromValue: sourceContentOpacity,
				toValue: targetContentOpacity,
				layer: contentLayer
			)
		}
		if sourceTransitionOpacity != targetTransitionOpacity {
			addSpringAnimation(
				keyPath: "opacity",
				fromValue: sourceTransitionOpacity,
				toValue: targetTransitionOpacity,
				layer: transitionContentLayer
			)
		}

		// backgroundLayer + borderLayer: bounds + position + cornerRadius (bg) + path (border)
		let sourceBgBounds = CGRect(origin: .zero, size: sourceChrome.frame.size)
		let targetBgBounds = CGRect(origin: .zero, size: targetChrome.frame.size)
		let sourceBgCenter = CGPoint(x: sourceChrome.frame.midX, y: sourceChrome.frame.midY)
		let targetBgCenter = CGPoint(x: targetChrome.frame.midX, y: targetChrome.frame.midY)

		addSpringAnimation(
			keyPath: "bounds",
			fromValue: NSValue(rect: sourceBgBounds),
			toValue: NSValue(rect: targetBgBounds),
			layer: backgroundLayer
		)
		addSpringAnimation(
			keyPath: "position",
			fromValue: NSValue(point: sourceBgCenter),
			toValue: NSValue(point: targetBgCenter),
			layer: backgroundLayer
		)
		addSpringAnimation(
			keyPath: "cornerRadius",
			fromValue: sourceChrome.cornerRadius,
			toValue: targetChrome.cornerRadius,
			layer: backgroundLayer
		)

		addSpringAnimation(
			keyPath: "bounds",
			fromValue: NSValue(rect: sourceBgBounds),
			toValue: NSValue(rect: targetBgBounds),
			layer: borderLayer
		)
		addSpringAnimation(
			keyPath: "position",
			fromValue: NSValue(point: sourceBgCenter),
			toValue: NSValue(point: targetBgCenter),
			layer: borderLayer
		)
		let sourceBorderInset = sourceChrome.borderWidth / 2
		let sourceBorderPath = CGPath(
			roundedRect: sourceBgBounds.insetBy(dx: sourceBorderInset, dy: sourceBorderInset),
			cornerWidth: max(0, sourceChrome.cornerRadius - sourceBorderInset),
			cornerHeight: max(0, sourceChrome.cornerRadius - sourceBorderInset),
			transform: nil
		)
		addSpringAnimation(
			keyPath: "path",
			fromValue: sourceBorderPath,
			toValue: borderLayer.path as Any,
			layer: borderLayer
		)

		// Additive spring: decays the cursor-to-resting offset without fighting model updates.
		// Model is now at resting_X; additive animates (cursor_X - resting_X) → 0 on top of it.
		// When animation ends, presentation = model + 0 = model — no snap regardless of
		// how much rubber-banding has occurred in the meantime.
		if let sourceCursorX, let targetCenterX, sourceCursorX != targetCenterX {
			let animation = CASpringAnimation(keyPath: "position.x")
			animation.fromValue = sourceCursorX - targetCenterX
			animation.toValue = 0
			animation.isAdditive = true
			animation.mass = 1.0
			animation.stiffness = 600
			animation.damping = 36
			animation.duration = min(animation.settlingDuration, 0.5)
			animation.isRemovedOnCompletion = true
			overlayLayer.add(animation, forKey: "position.x")
		}
	}

	static func resolvedSettleDuration(
		from sourceFrame: CGRect,
		to targetFrame: CGRect
	) -> TimeInterval {
		let dx = targetFrame.midX - sourceFrame.midX
		let dy = targetFrame.midY - sourceFrame.midY
		let distance = hypot(dx, dy)
		return min(
			ReorderableListStyle.maximumSettleDuration,
			max(
				ReorderableListStyle.minimumSettleDuration,
				ReorderableListStyle.minimumSettleDuration + (distance / 1200)
			)
		)
	}

	private func resolvedHostLayer() -> CALayer? {
		hostView?.wantsLayer = true
		return hostView?.layer
	}

	private func configureOverlayIfNeeded(backgroundColor: NSColor) {
		overlayLayer.masksToBounds = false
		overlayLayer.backgroundColor = NSColor.clear.cgColor
		overlayLayer.cornerRadius = 0
		overlayLayer.shadowColor = ReorderableListStyle.activeShadowColor.cgColor

		backgroundLayer.backgroundColor = backgroundColor.cgColor
		backgroundLayer.masksToBounds = true
		backgroundLayer.cornerRadius = currentChromeGeometry?.cornerRadius
			?? ReorderableListStyle.liftedOverlayCornerRadius
		if backgroundLayer.superlayer == nil {
			overlayLayer.addSublayer(backgroundLayer)
		}

		contentLayer.masksToBounds = true
		contentLayer.cornerRadius = ReorderableListStyle.cornerRadius
		if contentLayer.superlayer == nil {
			overlayLayer.addSublayer(contentLayer)
		}

		transitionContentLayer.masksToBounds = true
		transitionContentLayer.cornerRadius = ReorderableListStyle.cornerRadius
		transitionContentLayer.contentsGravity = .resize
		transitionContentLayer.opacity = 0
		if transitionContentLayer.superlayer == nil {
			overlayLayer.addSublayer(transitionContentLayer)
		}

		borderLayer.fillColor = NSColor.clear.cgColor
		borderLayer.strokeColor = ReorderableListStyle.resolvedColor(
			ReorderableListStyle.accentColor,
			for: hostView?.effectiveAppearance ?? NSAppearance.currentDrawing()
		).cgColor
		borderLayer.lineWidth = currentChromeGeometry?.borderWidth
			?? ReorderableListStyle.borderWidth
		if borderLayer.superlayer == nil {
			overlayLayer.addSublayer(borderLayer)
		}
	}

	private func apply(state: ReorderableListDragVisualState) {
		currentState = state
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		overlayLayer.position = state.center
		overlayLayer.bounds = state.bounds
		overlayLayer.opacity = state.opacity
		overlayLayer.shadowOpacity = state.shadowOpacity
		overlayLayer.shadowRadius = state.shadowRadius
		overlayLayer.transform = transform(for: state)
		contentLayer.frame = overlayLayer.bounds
		borderLayer.opacity = state.borderOpacity
		updateShapePath()
		CATransaction.commit()
	}

	private func animate(
		from sourceState: ReorderableListDragVisualState,
		to targetState: ReorderableListDragVisualState,
		duration: TimeInterval,
		timingFunctionName: CAMediaTimingFunctionName
	) {
		apply(state: targetState)
		let timingFunction = CAMediaTimingFunction(name: timingFunctionName)

		addAnimation(
			keyPath: "position",
			fromValue: NSValue(point: sourceState.center),
			toValue: NSValue(point: targetState.center),
			duration: duration,
			timingFunction: timingFunction,
			layer: overlayLayer
		)
		addAnimation(
			keyPath: "bounds",
			fromValue: NSValue(rect: sourceState.bounds),
			toValue: NSValue(rect: targetState.bounds),
			duration: duration,
			timingFunction: timingFunction,
			layer: overlayLayer
		)
		addAnimation(
			keyPath: "transform",
			fromValue: NSValue(caTransform3D: transform(for: sourceState)),
			toValue: NSValue(caTransform3D: transform(for: targetState)),
			duration: duration,
			timingFunction: timingFunction,
			layer: overlayLayer
		)
		addAnimation(
			keyPath: "opacity",
			fromValue: sourceState.opacity,
			toValue: targetState.opacity,
			duration: duration,
			timingFunction: timingFunction,
			layer: overlayLayer
		)
		addAnimation(
			keyPath: "shadowOpacity",
			fromValue: sourceState.shadowOpacity,
			toValue: targetState.shadowOpacity,
			duration: duration,
			timingFunction: timingFunction,
			layer: overlayLayer
		)
		addAnimation(
			keyPath: "shadowRadius",
			fromValue: sourceState.shadowRadius,
			toValue: targetState.shadowRadius,
			duration: duration,
			timingFunction: timingFunction,
			layer: overlayLayer
		)
		addAnimation(
			keyPath: "opacity",
			fromValue: sourceState.borderOpacity,
			toValue: targetState.borderOpacity,
			duration: duration,
			timingFunction: timingFunction,
			layer: borderLayer
		)
	}

	private func addAnimation(
		keyPath: String,
		fromValue: Any,
		toValue: Any,
		duration: TimeInterval,
		timingFunction: CAMediaTimingFunction,
		layer: CALayer
	) {
		let animation = CABasicAnimation(keyPath: keyPath)
		animation.fromValue = fromValue
		animation.toValue = toValue
		animation.duration = duration
		animation.timingFunction = timingFunction
		animation.isRemovedOnCompletion = true
		layer.add(animation, forKey: keyPath)
	}

	private func addSpringAnimation(
		keyPath: String,
		fromValue: Any,
		toValue: Any,
		layer: CALayer
	) {
		let animation = CASpringAnimation(keyPath: keyPath)
		animation.fromValue = fromValue
		animation.toValue = toValue
		animation.mass = 1.0
		animation.stiffness = 600
		animation.damping = 36
		animation.duration = min(animation.settlingDuration, 0.5)
		animation.isRemovedOnCompletion = true
		layer.add(animation, forKey: keyPath)
	}

	private func transform(for state: ReorderableListDragVisualState) -> CATransform3D {
		var transform = CATransform3DIdentity
		transform = CATransform3DTranslate(
			transform,
			state.translation.width,
			state.translation.height,
			0
		)
		transform = CATransform3DRotate(transform, state.rotationRadians, 0, 0, 1)
		transform = CATransform3DScale(transform, state.scale, state.scale, 1)
		return transform
	}

	private func updateShapePath() {
		shapePathUpdateCount += 1
		let shapeBounds = overlayLayer.bounds
		let chromeGeometry = resolvedChromeGeometry(in: shapeBounds)
		let chromeBounds = chromeGeometry.frame
		let borderInset = chromeGeometry.borderWidth / 2
		backgroundLayer.frame = chromeBounds
		backgroundLayer.cornerRadius = chromeGeometry.cornerRadius
		borderLayer.lineWidth = chromeGeometry.borderWidth
		borderLayer.frame = chromeBounds
		contentLayer.frame = shapeBounds
		transitionContentLayer.frame = shapeBounds
		let roundedPath = CGPath(
			roundedRect: borderLayer.bounds.insetBy(dx: borderInset, dy: borderInset),
			cornerWidth: max(0, chromeGeometry.cornerRadius - borderInset),
			cornerHeight: max(0, chromeGeometry.cornerRadius - borderInset),
			transform: nil
		)
		borderLayer.path = roundedPath
		overlayLayer.shadowPath = CGPath(
			roundedRect: chromeBounds,
			cornerWidth: chromeGeometry.cornerRadius,
			cornerHeight: chromeGeometry.cornerRadius,
			transform: nil
		)
	}

	private func resolvedChromeGeometry(in bounds: CGRect) -> (
		frame: CGRect,
		cornerRadius: CGFloat,
		borderWidth: CGFloat
	) {
		resolvedChromeGeometryForBounds(bounds, cornerRadiusOverride: activeShapeOverride?.cornerRadius)
	}

	private func resolvedChromeGeometryForBounds(
		_ bounds: CGRect,
		cornerRadiusOverride: CGFloat?
	) -> (
		frame: CGRect,
		cornerRadius: CGFloat,
		borderWidth: CGFloat
	) {
		if let cornerRadiusOverride {
			return (bounds, cornerRadiusOverride, ReorderableListStyle.borderWidth)
		}

		guard let currentChromeGeometry else {
			return (
				ReorderableListStyle.liftedOverlayBounds(in: bounds),
				ReorderableListStyle.liftedOverlayCornerRadius,
				ReorderableListStyle.borderWidth
			)
		}

		let xScale = currentChromeGeometry.referenceSize.width > 0
			? bounds.width / currentChromeGeometry.referenceSize.width
			: 1
		let yScale = currentChromeGeometry.referenceSize.height > 0
			? bounds.height / currentChromeGeometry.referenceSize.height
			: 1
		let scaledFrame = CGRect(
			x: currentChromeGeometry.chromeFrame.origin.x * xScale,
			y: currentChromeGeometry.chromeFrame.origin.y * yScale,
			width: currentChromeGeometry.chromeFrame.width * xScale,
			height: currentChromeGeometry.chromeFrame.height * yScale
		)
		return (
			scaledFrame,
			currentChromeGeometry.cornerRadius * min(xScale, yScale),
			currentChromeGeometry.borderWidth
		)
	}

	private func frame(for layer: CALayer) -> CGRect {
		CGRect(
			x: layer.position.x - (layer.bounds.width / 2),
			y: layer.position.y - (layer.bounds.height / 2),
			width: layer.bounds.width,
			height: layer.bounds.height
		)
	}

	private func resolvedScale(from transform: CATransform3D) -> CGFloat {
		CGFloat(sqrt((transform.m11 * transform.m11) + (transform.m12 * transform.m12)))
	}

	private func resolvedRotation(from transform: CATransform3D) -> CGFloat {
		CGFloat(atan2(transform.m12, transform.m11))
	}
}
