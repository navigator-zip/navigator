import AppKit
import Vendors

final class ReorderableListItemContainerView: NSView {
	private(set) var contentView: NSView
	private let contentWrapperView = NSView()
	var representedItemID: Any?
	weak var eventForwardingView: NSView? {
		didSet {
			syncContentEventForwarding()
		}
	}

	private let backgroundColor: NSColor
	private var contentConstraints = [NSLayoutConstraint]()
	private var alphaAnimator: SpringAnimator<CGFloat>?
	private var transformAnimator: SpringAnimator<CGPoint>?
	private var displacementAnimator: SpringAnimator<CGFloat>?
	private var currentAnimatedAlpha: CGFloat = 1
	private var currentTransformState = CGPoint(x: 1, y: 0)
	private var currentDisplacementOffset: CGFloat = 0
	private var cellStateObserver: (any ReorderableListItemCellStateObserver)? {
		contentView as? (any ReorderableListItemCellStateObserver)
	}

	private(set) var cellState = ReorderableListCellState(
		isReordering: false,
		isListReordering: false,
		isHighlighted: false,
		isSelected: false
	)

	init(
		contentView: NSView,
		backgroundColor: NSColor
	) {
		self.contentView = contentView
		self.backgroundColor = backgroundColor
		super.init(frame: .zero)
		setup()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override var isFlipped: Bool {
		true
	}

	override func makeBackingLayer() -> CALayer {
		ReorderableListAnimationLayer()
	}

	override var intrinsicContentSize: NSSize {
		layoutSubtreeIfNeeded()
		let contentHeight = max(contentWrapperView.fittingSize.height, contentView.fittingSize.height, 0)
		return NSSize(width: NSView.noIntrinsicMetric, height: contentHeight)
	}

	override func hitTest(_ point: NSPoint) -> NSView? {
		guard bounds.contains(point) else { return nil }

		let pointInContent = convert(point, to: contentView)
		if let contentHitView = contentView.hitTest(pointInContent) {
			return contentHitView
		}

		return self
	}

	override func mouseDown(with event: NSEvent) {
		if let eventForwardingView {
			eventForwardingView.mouseDown(with: event)
		}
		else {
			nextResponder?.mouseDown(with: event)
		}
	}

	override func mouseDragged(with event: NSEvent) {
		if let eventForwardingView {
			eventForwardingView.mouseDragged(with: event)
		}
		else {
			nextResponder?.mouseDragged(with: event)
		}
	}

	override func mouseUp(with event: NSEvent) {
		if let eventForwardingView {
			eventForwardingView.mouseUp(with: event)
		}
		else {
			nextResponder?.mouseUp(with: event)
		}
	}

	override func keyDown(with event: NSEvent) {
		if let eventForwardingView {
			eventForwardingView.keyDown(with: event)
		}
		else if let nextResponder {
			nextResponder.keyDown(with: event)
		}
		else {
			super.keyDown(with: event)
		}
	}

	override func cancelOperation(_ sender: Any?) {
		if let eventForwardingView,
		   eventForwardingView.tryToPerform(#selector(NSResponder.cancelOperation(_:)), with: sender) {
			return
		}
		if let nextResponder,
		   nextResponder.tryToPerform(#selector(NSResponder.cancelOperation(_:)), with: sender) {
			return
		}
	}

	override func layout() {
		super.layout()
		contentWrapperView.frame = bounds
		layer?.shadowPath = CGPath(
			roundedRect: bounds,
			cornerWidth: ReorderableListStyle.cornerRadius,
			cornerHeight: ReorderableListStyle.cornerRadius,
			transform: nil
		)
	}

	func prepareForReuse(with contentView: NSView) {
		replaceContentViewIfNeeded(with: contentView)
		syncContentEventForwarding()
		representedItemID = nil
		applyDisplacementOffset(0, animated: false)
		apply(
			cellState: ReorderableListCellState(
				isReordering: false,
				isListReordering: false,
				isHighlighted: false,
				isSelected: false
			),
			animated: false
		)
		layer?.zPosition = 0
	}

	func applyDisplacementOffset(
		_ offset: CGFloat,
		animated: Bool
	) {
		guard currentDisplacementOffset != offset || animated == false else { return }

		if animated {
			startDisplacementAnimation(to: offset)
		}
		else {
			cancelDisplacementAnimation()
			currentDisplacementOffset = offset
			applyDisplacementTransform(offset)
		}
	}

	func apply(
		cellState: ReorderableListCellState,
		animated: Bool,
		containerShowsLiftedState: Bool = true
	) {
		self.cellState = cellState
		cellStateObserver?.reorderableListItemDidUpdate(
			cellState: cellState,
			animated: animated
		)
		let appliesContainerDragStyling = containerShowsLiftedState && cellStateObserver == nil
		let changes = {
			self.layer?.backgroundColor = appliesContainerDragStyling && cellState.isReordering
				? ReorderableListStyle.resolvedColor(
					self.backgroundColor,
					for: self.effectiveAppearance
				).cgColor
				: NSColor.clear.cgColor
			self.layer?.borderWidth = appliesContainerDragStyling && cellState.isReordering
				? ReorderableListStyle.borderWidth
				: 0
			self.layer?.borderColor = ReorderableListStyle.resolvedColor(
				ReorderableListStyle.accentColor,
				for: self.effectiveAppearance
			).withAlphaComponent(ReorderableListStyle.activeBorderOpacity).cgColor
			self.layer?.shadowColor = ReorderableListStyle.activeShadowColor.cgColor
			self.layer?.shadowOpacity = appliesContainerDragStyling && cellState.isReordering
				? ReorderableListStyle.activeShadowOpacity
				: 0
			self.layer?.shadowRadius = appliesContainerDragStyling && cellState.isReordering
				? ReorderableListStyle.activeShadowRadius
				: 0
		}

		let targetAlpha = cellState.isListReordering && !cellState.isReordering
			? ReorderableListStyle.inactiveRowOpacity
			: 1
		let targetTransformState = CGPoint(
			x: appliesContainerDragStyling && cellState.isReordering
				? ReorderableListStyle.activeScale
				: 1,
			y: appliesContainerDragStyling && cellState.isReordering
				? (ReorderableListStyle.activeRotationDegrees * .pi) / 180
				: 0
		)

		if animated {
			Wave.animate(withSpring: ReorderableListStyle.animationSpring) {
				changes()
			}
			startAlphaAnimation(to: targetAlpha)
			startTransformAnimation(to: targetTransformState)
		}
		else {
			cancelAlphaAnimation()
			cancelTransformAnimation()
			changes()
			currentAnimatedAlpha = targetAlpha
			alphaValue = targetAlpha
			currentTransformState = targetTransformState
			applyTransform(state: targetTransformState)
		}
	}

	private func setup() {
		wantsLayer = true
		layer?.cornerRadius = ReorderableListStyle.cornerRadius
		layer?.masksToBounds = false
		contentWrapperView.translatesAutoresizingMaskIntoConstraints = true
		contentWrapperView.frame = bounds
		contentWrapperView.autoresizingMask = [.width, .height]
		contentWrapperView.wantsLayer = true
		contentWrapperView.layer = ReorderableListAnimationLayer()
		addSubview(contentWrapperView)

		installContentView(contentView)
		contentConstraints.append(contentView.trailingAnchor.constraint(equalTo: contentWrapperView.trailingAnchor))

		NSLayoutConstraint.activate(contentConstraints)
	}

	private func startAlphaAnimation(to targetAlpha: CGFloat) {
		cancelAlphaAnimation()
		let animator = SpringAnimator<CGFloat>(
			spring: ReorderableListStyle.animationSpring,
			value: currentAnimatedAlpha,
			target: targetAlpha
		)
		animator.valueChanged = { [weak self] value in
			reorderableListPerformOnMain {
				self?.currentAnimatedAlpha = value
				self?.alphaValue = value
			}
		}
		animator.completion = { [weak self] _ in
			reorderableListPerformOnMain {
				self?.currentAnimatedAlpha = targetAlpha
				self?.alphaValue = targetAlpha
				self?.alphaAnimator = nil
			}
		}
		alphaAnimator = animator
		animator.start()
	}

	private func startTransformAnimation(to targetState: CGPoint) {
		cancelTransformAnimation()
		let animator = SpringAnimator<CGPoint>(
			spring: ReorderableListStyle.animationSpring,
			value: currentTransformState,
			target: targetState
		)
		animator.valueChanged = { [weak self] value in
			reorderableListPerformOnMain {
				self?.currentTransformState = value
				self?.applyTransform(state: value)
			}
		}
		animator.completion = { [weak self] _ in
			reorderableListPerformOnMain {
				self?.currentTransformState = targetState
				self?.applyTransform(state: targetState)
				self?.transformAnimator = nil
			}
		}
		transformAnimator = animator
		animator.start()
	}

	private func startDisplacementAnimation(to targetOffset: CGFloat) {
		cancelDisplacementAnimation()
		let animator = SpringAnimator<CGFloat>(
			spring: ReorderableListStyle.animationSpring,
			value: currentDisplacementOffset,
			target: targetOffset
		)
		animator.valueChanged = { [weak self] value in
			reorderableListPerformOnMain {
				self?.currentDisplacementOffset = value
				self?.applyDisplacementTransform(value)
			}
		}
		animator.completion = { [weak self] _ in
			reorderableListPerformOnMain {
				self?.currentDisplacementOffset = targetOffset
				self?.applyDisplacementTransform(targetOffset)
				self?.displacementAnimator = nil
			}
		}
		displacementAnimator = animator
		animator.start()
	}

	private func cancelAlphaAnimation() {
		alphaAnimator?.valueChanged = nil
		alphaAnimator?.completion = nil
		alphaAnimator?.stop()
		alphaAnimator = nil
	}

	private func cancelTransformAnimation() {
		transformAnimator?.valueChanged = nil
		transformAnimator?.completion = nil
		transformAnimator?.stop()
		transformAnimator = nil
	}

	private func cancelDisplacementAnimation() {
		displacementAnimator?.valueChanged = nil
		displacementAnimator?.completion = nil
		displacementAnimator?.stop()
		displacementAnimator = nil
	}

	private func applyTransform(state: CGPoint) {
		layer?.transform = state == CGPoint(x: 1, y: 0)
			? CATransform3DIdentity
			: CATransform3DConcat(
				CATransform3DMakeScale(state.x, state.x, 1),
				CATransform3DMakeRotation(state.y, 0, 0, 1)
			)
	}

	private func applyDisplacementTransform(_ offset: CGFloat) {
		contentWrapperView.layer?.transform = offset == 0
			? CATransform3DIdentity
			: CATransform3DMakeTranslation(0, offset, 0)
	}

	private func replaceContentViewIfNeeded(with contentView: NSView) {
		guard self.contentView !== contentView else { return }
		NSLayoutConstraint.deactivate(contentConstraints)
		self.contentView.removeFromSuperview()
		self.contentView = contentView
		installContentView(contentView)
		syncContentEventForwarding()

		contentConstraints = [
			contentView.leadingAnchor.constraint(equalTo: contentWrapperView.leadingAnchor),
			contentView.topAnchor.constraint(equalTo: contentWrapperView.topAnchor),
			contentView.bottomAnchor.constraint(equalTo: contentWrapperView.bottomAnchor),
			contentView.trailingAnchor.constraint(equalTo: contentWrapperView.trailingAnchor),
		]
		NSLayoutConstraint.activate(contentConstraints)
	}

	private func installContentView(_ contentView: NSView) {
		contentView.translatesAutoresizingMaskIntoConstraints = false
		contentWrapperView.addSubview(contentView)
		contentConstraints = [
			contentView.leadingAnchor.constraint(equalTo: contentWrapperView.leadingAnchor),
			contentView.topAnchor.constraint(equalTo: contentWrapperView.topAnchor),
			contentView.bottomAnchor.constraint(equalTo: contentWrapperView.bottomAnchor),
		]
		syncContentEventForwarding()
	}

	private func syncContentEventForwarding() {
		contentView.nextResponder = self
		(contentView as? any ReorderableListItemEventForwarding)?
			.reorderableListEventForwardingView = self
	}
}
