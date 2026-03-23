import Aesthetics
import AppKit
import Foundation
import ReorderableList
import Vendors

enum BrowserSidebarCameraActivityIndicatorIdentifier: String {
	case tabRow = "browserSidebar.tab.cameraActivityIndicator"
	case pinnedTab = "browserSidebar.pinnedTab.cameraActivityIndicator"
}

enum TabDisplayContext {
	case pinned
	case unpinned
}

final class BrowserSidebarTabRow: NSView,
	ReorderableListItemEventForwarding,
	ReorderableListItemCellStateObserver,
	ReorderableListItemDragObserver,
	ReorderableListDragChromePathProviding {
	private enum PinnedStyle {
		static let cornerRadius: CGFloat = 14
		static let cameraIndicatorWidth: CGFloat = 10
		static let cameraIndicatorHeight: CGFloat = 8
		static let cameraIndicatorTrailingInset: CGFloat = 3
		static let cameraIndicatorBottomInset: CGFloat = 3
	}

	private enum DragStyle {
		static let animationDuration: TimeInterval = 0.15
		static let unpinnedCornerRadius: CGFloat = 10
		static let borderWidth: CGFloat = 2
		static let activeBorderOpacity: CGFloat = 0.8
		static let activeRotationDegrees: CGFloat = 3
		static let selectedFillColor = Color.navigatorChromeFill
		static let lightModeSelectedFillColor = NSColor.white
		static let lightModeSelectedShadowOpacity: Float = 0.08
		static let lightModeSelectedShadowRadius: CGFloat = 0.5
		static let lightModeSelectedShadowOffset = CGSize(width: 0, height: 0)
	}

	private enum CloseButtonStyle {
		static let size: CGFloat = 24
		static let cornerRadius: CGFloat = 6
		static let highlightOpacity: CGFloat = 0.45
	}

	private enum CameraActivityIndicatorStyle {
		static let symbolName = "video.fill"
		static let width: CGFloat = 12
		static let height: CGFloat = 10
	}

	private enum LayerAnimationPath {
		static let backgroundColor = "backgroundColor"
		static let shadowOpacity = "shadowOpacity"
		static let shadowRadius = "shadowRadius"
		static let transform = "transform"
	}

	private enum ShapeLayerAnimationPath {
		static let lineWidth = "lineWidth"
		static let strokeColor = "strokeColor"
	}

	let displayContext: TabDisplayContext

	private let closeButton = NSButton(
		image: NSImage(systemSymbolName: "xmark", accessibilityDescription: nil) ?? NSImage(),
		target: nil,
		action: nil
	)
	private let faviconView: BrowserTabFaviconView
	private let titleLabel = BrowserSidebarLabel()
	private let fallbackLabel = NSTextField(labelWithString: "")
	private let selectedBackground = NSView()
	private let selectedBackgroundBorderLayer = CAShapeLayer()
	private let closeButtonHighlightLayer = CALayer()
	private let cameraActivityIndicatorView = NSImageView()
	private let newTabTitle: String
	private let closeTabActionTitle: String
	private let pinTabActionTitle: String
	private let unpinTabActionTitle: String
	private let replacePinnedTabURLActionTitle: String
	private let controlIconDimensions: NSSize
	private let rowBackgroundColor: NSColor
	private var activeCornerRadius: CGFloat {
		displayContext == .pinned ? PinnedStyle.cornerRadius : DragStyle.unpinnedCornerRadius
	}

	private var currentTab: BrowserTabViewModel?
	private var selectClosure: (() -> Void)?
	private var togglePinClosure: (() -> Void)?
	private var replacePinnedURLClosure: (() -> Void)?
	weak var reorderableListEventForwardingView: NSView?
	#if DEBUG
		var mouseLocationInWindowOverride: NSPoint?
	#endif
	private var isSelectedRow = false
	private var isHovered = false
	private var isCloseButtonHovered = false
	private var isCameraActive = false
	private var isTrackingSelectionPress = false
	private var suppressSelectionOnMouseUp = false
	private weak var observedClipView: NSClipView?
	private var rowTrackingArea: NSTrackingArea?
	private var closeButtonTrackingArea: NSTrackingArea?
	private var closeButtonTintColor = NSColor.labelColor
	private var currentCellState = ReorderableListCellState(
		isReordering: false,
		isListReordering: false,
		isHighlighted: false,
		isSelected: false
	)

	init(
		displayContext: TabDisplayContext = .unpinned,
		isSelected: Bool,
		newTabTitle: String = "",
		closeTabActionTitle: String = "",
		pinTabActionTitle: String = "Pin Tab",
		unpinTabActionTitle: String = "Unpin Tab",
		replacePinnedTabURLActionTitle: String = "",
		controlIconDimensions: NSSize,
		rowBackgroundColor: NSColor
	) {
		self.displayContext = displayContext
		self.newTabTitle = newTabTitle
		self.closeTabActionTitle = closeTabActionTitle
		self.pinTabActionTitle = pinTabActionTitle
		self.unpinTabActionTitle = unpinTabActionTitle
		self.replacePinnedTabURLActionTitle = replacePinnedTabURLActionTitle
		self.controlIconDimensions = controlIconDimensions
		self.rowBackgroundColor = rowBackgroundColor
		faviconView = BrowserTabFaviconView(
			tab: BrowserTabViewModel(initialURL: ""),
			showsPlaceholderWhenMissing: displayContext == .unpinned
		)
		super.init(frame: .zero)
		wantsLayer = true
		configureCommon()
		updateSelection(isSelected)
		if displayContext == .unpinned {
			closeButton.toolTip = closeTabActionTitle
			closeButton.action = #selector(performCloseTab)
			closeButton.target = self
			if let closeIcon = closeButton.image {
				closeIcon.isTemplate = true
				closeButton.image = closeIcon
			}
		}
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override var intrinsicContentSize: NSSize {
		switch displayContext {
		case .pinned:
			NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
		case .unpinned:
			NSSize(width: NSView.noIntrinsicMetric, height: 40)
		}
	}

	override var appearance: NSAppearance? {
		didSet {
			updateCloseButtonAppearance()
			applyDragStyling(animated: false)
		}
	}

	var title: String {
		titleLabel.stringValue
	}

	func updateFaviconLogoSelectionState(isSelected: Bool) {
		faviconView.updateLogoSelectionState(isSelected: isSelected)
	}

	func applySelectionState(isSelected: Bool) {
		guard isSelectedRow != isSelected else { return }
		isSelectedRow = isSelected
		applyDragStyling(animated: false)
	}

	/// Returns a snapshot of the favicon view, suitable for compositing into a pinned-tile drag preview.
	func makeFaviconSnapshot() -> NSImage? {
		layoutSubtreeIfNeeded()
		guard faviconView.bounds.isEmpty == false,
		      let bitmapRep = faviconView.bitmapImageRepForCachingDisplay(in: faviconView.bounds)
		else { return nil }
		faviconView.cacheDisplay(in: faviconView.bounds, to: bitmapRep)
		let image = NSImage(size: faviconView.bounds.size)
		image.addRepresentation(bitmapRep)
		return image
	}

	override func layout() {
		super.layout()
		selectedBackground.layer?.shadowPath = CGPath(
			roundedRect: selectedBackground.bounds,
			cornerWidth: activeCornerRadius,
			cornerHeight: activeCornerRadius,
			transform: nil
		)
		updateSelectedBackgroundBorderPath(
			borderWidth: displayedBorderWidth(for: currentCellState)
		)
		updateCloseButtonHighlightFrame()
	}

	override func setFrameOrigin(_ newOrigin: NSPoint) {
		super.setFrameOrigin(newOrigin)
		syncHoverStateForCurrentPointerLocation()
	}

	override func setFrameSize(_ newSize: NSSize) {
		super.setFrameSize(newSize)
		syncHoverStateForCurrentPointerLocation()
	}

	private func configureCommon() {
		addSubview(selectedBackground)
		selectedBackground.translatesAutoresizingMaskIntoConstraints = false
		selectedBackground.wantsLayer = true
		selectedBackground.layer?.cornerRadius = activeCornerRadius
		selectedBackground.layer?.allowsEdgeAntialiasing = true
		selectedBackground.layer?.masksToBounds = false
		configureSelectedBackgroundBorderLayer()

		cameraActivityIndicatorView.translatesAutoresizingMaskIntoConstraints = false
		cameraActivityIndicatorView.identifier = NSUserInterfaceItemIdentifier(
			displayContext == .pinned
				? BrowserSidebarCameraActivityIndicatorIdentifier.pinnedTab.rawValue
				: BrowserSidebarCameraActivityIndicatorIdentifier.tabRow.rawValue
		)
		cameraActivityIndicatorView.imageScaling = .scaleProportionallyDown
		cameraActivityIndicatorView.image = NSImage(
			systemSymbolName: CameraActivityIndicatorStyle.symbolName,
			accessibilityDescription: nil
		)
		cameraActivityIndicatorView.isHidden = true
		selectedBackground.addSubview(cameraActivityIndicatorView)

		faviconView.translatesAutoresizingMaskIntoConstraints = false
		selectedBackground.addSubview(faviconView)

		switch displayContext {
		case .pinned:
			configurePinnedLayout()
		case .unpinned:
			configureUnpinnedLayout()
		}
		updateCameraActivityIndicatorAppearance()
	}

	private func configurePinnedLayout() {
		fallbackLabel.translatesAutoresizingMaskIntoConstraints = false
		fallbackLabel.alignment = .center
		fallbackLabel.font = .systemFont(ofSize: 11, weight: .semibold)
		selectedBackground.addSubview(fallbackLabel)

		titleLabel.isHidden = true
		closeButton.isHidden = true

		let fallbackLeadingConstraint = fallbackLabel.leadingAnchor.constraint(
			greaterThanOrEqualTo: selectedBackground.leadingAnchor,
			constant: 2
		)
		let fallbackTrailingConstraint = fallbackLabel.trailingAnchor.constraint(
			lessThanOrEqualTo: selectedBackground.trailingAnchor,
			constant: -2
		)
		fallbackLeadingConstraint.priority = .defaultHigh
		fallbackTrailingConstraint.priority = .defaultHigh

		NSLayoutConstraint.activate([
			selectedBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
			selectedBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
			selectedBackground.topAnchor.constraint(equalTo: topAnchor),
			selectedBackground.bottomAnchor.constraint(equalTo: bottomAnchor),

			faviconView.centerXAnchor.constraint(equalTo: selectedBackground.centerXAnchor),
			faviconView.centerYAnchor.constraint(equalTo: selectedBackground.centerYAnchor),
			faviconView.widthAnchor.constraint(equalToConstant: controlIconDimensions.width),
			faviconView.heightAnchor.constraint(equalToConstant: controlIconDimensions.height),

			fallbackLabel.centerXAnchor.constraint(equalTo: selectedBackground.centerXAnchor),
			fallbackLabel.centerYAnchor.constraint(equalTo: selectedBackground.centerYAnchor),
			fallbackLeadingConstraint,
			fallbackTrailingConstraint,

			cameraActivityIndicatorView.trailingAnchor.constraint(
				equalTo: selectedBackground.trailingAnchor,
				constant: -PinnedStyle.cameraIndicatorTrailingInset
			),
			cameraActivityIndicatorView.bottomAnchor.constraint(
				equalTo: selectedBackground.bottomAnchor,
				constant: -PinnedStyle.cameraIndicatorBottomInset
			),
			cameraActivityIndicatorView.widthAnchor.constraint(equalToConstant: PinnedStyle.cameraIndicatorWidth),
			cameraActivityIndicatorView.heightAnchor.constraint(equalToConstant: PinnedStyle.cameraIndicatorHeight),
		])
	}

	private func configureUnpinnedLayout() {
		configureCloseButtonHighlightLayer()

		closeButton.translatesAutoresizingMaskIntoConstraints = false
		closeButton.bezelStyle = .texturedRounded
		closeButton.isBordered = false
		closeButton.isHidden = true
		closeButton.setButtonType(.momentaryPushIn)
		closeButton.focusRingType = .none
		closeButton.wantsLayer = true
		closeButton.layer?.backgroundColor = NSColor.clear.cgColor
		selectedBackground.addSubview(closeButton)

		titleLabel.translatesAutoresizingMaskIntoConstraints = false
		titleLabel.lineBreakMode = .byTruncatingTail
		titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
		titleLabel.textColor = .labelColor
		titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
		selectedBackground.addSubview(titleLabel)

		NSLayoutConstraint.activate([
			selectedBackground.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 15),
			selectedBackground.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -15),
			selectedBackground.topAnchor.constraint(equalTo: topAnchor),
			selectedBackground.bottomAnchor.constraint(equalTo: bottomAnchor),

			faviconView.leadingAnchor.constraint(equalTo: selectedBackground.leadingAnchor, constant: 10),
			faviconView.centerYAnchor.constraint(equalTo: centerYAnchor),
			faviconView.widthAnchor.constraint(equalToConstant: controlIconDimensions.width),
			faviconView.heightAnchor.constraint(equalToConstant: controlIconDimensions.height),

			closeButton.trailingAnchor.constraint(equalTo: selectedBackground.trailingAnchor, constant: -10),
			closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
			closeButton.widthAnchor.constraint(equalToConstant: CloseButtonStyle.size),
			closeButton.heightAnchor.constraint(equalToConstant: CloseButtonStyle.size),

			cameraActivityIndicatorView.centerXAnchor.constraint(equalTo: closeButton.centerXAnchor),
			cameraActivityIndicatorView.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
			cameraActivityIndicatorView.widthAnchor.constraint(equalToConstant: CameraActivityIndicatorStyle.width),
			cameraActivityIndicatorView.heightAnchor.constraint(equalToConstant: CameraActivityIndicatorStyle.height),

			titleLabel.leadingAnchor.constraint(equalTo: faviconView.trailingAnchor, constant: 10),
			titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
			titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -10),
		])
	}

	override func updateTrackingAreas() {
		if let rowTrackingArea {
			removeTrackingArea(rowTrackingArea)
		}
		if let closeButtonTrackingArea {
			closeButton.removeTrackingArea(closeButtonTrackingArea)
		}
		super.updateTrackingAreas()

		let rowTrackingArea = NSTrackingArea(
			rect: bounds,
			options: [.activeInActiveApp, .inVisibleRect, .mouseEnteredAndExited],
			owner: self,
			userInfo: nil
		)
		addTrackingArea(rowTrackingArea)
		self.rowTrackingArea = rowTrackingArea

		if displayContext == .unpinned {
			let closeButtonTrackingArea = NSTrackingArea(
				rect: closeButton.bounds,
				options: [.activeInActiveApp, .inVisibleRect, .mouseEnteredAndExited],
				owner: self,
				userInfo: nil
			)
			closeButton.addTrackingArea(closeButtonTrackingArea)
			self.closeButtonTrackingArea = closeButtonTrackingArea
		}
		syncHoverStateForCurrentPointerLocation()
	}

	private func configureSelectedBackgroundBorderLayer() {
		guard let selectedBackgroundLayer = selectedBackground.layer else { return }
		selectedBackgroundBorderLayer.fillColor = NSColor.clear.cgColor
		selectedBackgroundBorderLayer.lineJoin = .round
		selectedBackgroundBorderLayer.lineCap = .round
		selectedBackgroundBorderLayer.allowsEdgeAntialiasing = true
		selectedBackgroundBorderLayer.contentsScale = window?.backingScaleFactor
			?? NSScreen.main?.backingScaleFactor
			?? 2
		selectedBackgroundLayer.addSublayer(selectedBackgroundBorderLayer)
		updateSelectedBackgroundBorderPath(
			borderWidth: displayedBorderWidth(for: currentCellState)
		)
	}

	private func configureCloseButtonHighlightLayer() {
		guard let selectedBackgroundLayer = selectedBackground.layer else { return }
		closeButtonHighlightLayer.backgroundColor = NSColor.clear.cgColor
		closeButtonHighlightLayer.cornerRadius = CloseButtonStyle.cornerRadius
		closeButtonHighlightLayer.masksToBounds = true
		selectedBackgroundLayer.addSublayer(closeButtonHighlightLayer)
	}

	private func updateSelectedBackgroundBorderPath(borderWidth: CGFloat) {
		updateBorderPath(
			for: selectedBackgroundBorderLayer,
			inset: borderWidth > 0 ? borderWidth / 2 : 0.5
		)
	}

	private func updateBorderPath(
		for borderLayer: CAShapeLayer,
		inset: CGFloat
	) {
		let borderBounds = selectedBackground.bounds.insetBy(dx: inset, dy: inset)
		borderLayer.frame = selectedBackground.bounds
		borderLayer.path = CGPath(
			roundedRect: borderBounds,
			cornerWidth: max(0, activeCornerRadius - inset),
			cornerHeight: max(0, activeCornerRadius - inset),
			transform: nil
		)
	}

	func configure(
		with tab: BrowserTabViewModel,
		isFaviconLoadingEnabled: Bool,
		isSelected: Bool,
		isCameraActive: Bool = false,
		cameraActivityAccessibilityLabel: String? = nil,
		fallbackText: String = "",
		fallbackTextColor: NSColor = .labelColor,
		onClose: @escaping () -> Void,
		onSelect: @escaping () -> Void,
		onTogglePin: @escaping () -> Void = {},
		onReplacePinnedURL: @escaping () -> Void = {}
	) {
		currentTab = tab
		faviconView.configure(
			tab: tab,
			isLoadingEnabled: isFaviconLoadingEnabled
		)

		if displayContext == .pinned {
			fallbackLabel.stringValue = fallbackText
			fallbackLabel.textColor = fallbackTextColor
			fallbackLabel.isHidden = faviconView.hasResolvedImage
			faviconView.onResolvedImageAvailabilityChange = { [weak self] hasResolvedImage in
				self?.fallbackLabel.isHidden = hasResolvedImage
			}
		}
		else {
			titleLabel.stringValue = tab.displayTitle.isEmpty ? newTabTitle : tab.displayTitle
		}

		updateSelection(isSelected)
		self.isCameraActive = isCameraActive
		cameraActivityIndicatorView.toolTip = isCameraActive ? cameraActivityAccessibilityLabel : nil
		cameraActivityIndicatorView.setAccessibilityLabel(cameraActivityAccessibilityLabel)
		updateTrailingAccessoryVisibility()
		closeClosure = onClose
		selectClosure = onSelect
		togglePinClosure = onTogglePin
		replacePinnedURLClosure = onReplacePinnedURL
		if displayContext == .unpinned {
			closeButton.toolTip = tab.isPinned ? unpinTabActionTitle : closeTabActionTitle
		}
		menu = makeContextMenu(for: tab)
	}

	private var closeClosure: (() -> Void)?

	private func makeContextMenu(for tab: BrowserTabViewModel) -> NSMenu {
		let menu = NSMenu()
		let togglePinItem = NSMenuItem(
			title: tab.isPinned ? unpinTabActionTitle : pinTabActionTitle,
			action: #selector(togglePinnedState),
			keyEquivalent: ""
		)
		togglePinItem.target = self
		menu.addItem(togglePinItem)
		if tab.isPinned, tab.currentURL != tab.initialURL {
			let replacePinnedURLItem = NSMenuItem(
				title: replacePinnedTabURLActionTitle,
				action: #selector(replacePinnedURL),
				keyEquivalent: ""
			)
			replacePinnedURLItem.target = self
			menu.addItem(replacePinnedURLItem)
		}
		else if !tab.isPinned {
			menu.addItem(.separator())
			let closeItem = NSMenuItem(
				title: closeTabActionTitle,
				action: #selector(performCloseTab),
				keyEquivalent: ""
			)
			closeItem.target = self
			menu.addItem(closeItem)
		}
		return menu
	}

	private func updateSelection(_ isSelected: Bool) {
		isSelectedRow = isSelected
		applyDragStyling(animated: false)
	}

	private var isCloseButtonVisible: Bool {
		isHovered || isCloseButtonHovered
	}

	private func setHoverState(
		isRowHovered: Bool,
		isCloseButtonHovered: Bool
	) {
		let closeButtonVisibilityChanged = isCloseButtonVisible != (isRowHovered || isCloseButtonHovered)
		guard
			self.isHovered != isRowHovered
			|| self.isCloseButtonHovered != isCloseButtonHovered
			|| closeButtonVisibilityChanged
		else {
			return
		}

		self.isHovered = isRowHovered
		self.isCloseButtonHovered = isCloseButtonHovered
		updateTrailingAccessoryVisibility()
		updateCloseButtonAppearance()
		if !isCloseButtonVisible {
			isTrackingSelectionPress = false
		}
		applyDragStyling(animated: false)
	}

	private func updateTrailingAccessoryVisibility() {
		if displayContext == .pinned {
			closeButton.isHidden = true
			cameraActivityIndicatorView.isHidden = !isCameraActive
		}
		else {
			closeButton.isHidden = !isCloseButtonVisible
			cameraActivityIndicatorView.isHidden = !isCameraActive || isCloseButtonVisible
		}
	}

	private func updateCloseButtonAppearance() {
		closeButtonHighlightLayer.backgroundColor = (isCloseButtonHovered
			? resolvedColor(NSColor.secondaryLabelColor).withAlphaComponent(CloseButtonStyle.highlightOpacity)
			: .clear).cgColor
		let tintColor = resolvedCloseButtonTintColor()
		closeButtonTintColor = tintColor
		closeButton.contentTintColor = tintColor
		updateCameraActivityIndicatorAppearance()
	}

	private func resolvedCloseButtonTintColor() -> NSColor {
		if isCloseButtonHovered, usesLightModeSelectedStyle {
			return resolvedColor(.white)
		}
		return resolvedColor(.labelColor)
	}

	private func updateCloseButtonHighlightFrame() {
		let size = CloseButtonStyle.size
		closeButtonHighlightLayer.frame = CGRect(
			x: closeButton.frame.midX - (size / 2),
			y: closeButton.frame.midY - (size / 2),
			width: size,
			height: size
		)
	}

	override func viewDidChangeEffectiveAppearance() {
		super.viewDidChangeEffectiveAppearance()
		updateCloseButtonAppearance()
		applyDragStyling(animated: false)
	}

	private func updateCameraActivityIndicatorAppearance() {
		cameraActivityIndicatorView.contentTintColor = resolvedColor(Asset.Colors.accent.color)
	}

	override func viewDidMoveToSuperview() {
		super.viewDidMoveToSuperview()
		updateClipViewObservation()
		syncHoverStateForCurrentPointerLocation()
	}

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		selectedBackgroundBorderLayer.contentsScale = window?.backingScaleFactor
			?? NSScreen.main?.backingScaleFactor
			?? 2
		updateClipViewObservation()
		syncHoverStateForCurrentPointerLocation()
	}

	override func viewWillMove(toSuperview newSuperview: NSView?) {
		if newSuperview == nil {
			stopObservingClipView()
			setHoverState(isRowHovered: false, isCloseButtonHovered: false)
		}
		super.viewWillMove(toSuperview: newSuperview)
	}

	@objc
	private func clipViewBoundsDidChange(_ notification: Notification) {
		guard notification.object as AnyObject? === observedClipView else { return }
		syncHoverStateForCurrentPointerLocation()
	}

	override func mouseEntered(with event: NSEvent) {
		super.mouseEntered(with: event)
		syncHoverStateForCurrentPointerLocation(mouseLocationInWindow: event.locationInWindow)
	}

	override func mouseExited(with event: NSEvent) {
		super.mouseExited(with: event)
		syncHoverStateForCurrentPointerLocation(mouseLocationInWindow: event.locationInWindow)
	}

	override func mouseDown(with event: NSEvent) {
		let localPoint = convert(event.locationInWindow, from: nil)
		suppressSelectionOnMouseUp = false
		isTrackingSelectionPress = shouldTrackSelection(at: localPoint)
		if let reorderableListEventForwardingView {
			reorderableListEventForwardingView.mouseDown(with: event)
		}
		else {
			nextResponder?.mouseDown(with: event)
		}
	}

	override func mouseDragged(with event: NSEvent) {
		let localPoint = convert(event.locationInWindow, from: nil)
		if !bounds.contains(localPoint) {
			isTrackingSelectionPress = false
		}
		if let reorderableListEventForwardingView {
			reorderableListEventForwardingView.mouseDragged(with: event)
		}
		else {
			nextResponder?.mouseDragged(with: event)
		}
	}

	override func mouseUp(with event: NSEvent) {
		if let reorderableListEventForwardingView {
			reorderableListEventForwardingView.mouseUp(with: event)
		}
		else {
			nextResponder?.mouseUp(with: event)
		}
		let localPoint = convert(event.locationInWindow, from: nil)
		let shouldSelect = !suppressSelectionOnMouseUp
			&& isTrackingSelectionPress
			&& shouldTrackSelection(at: localPoint)
		isTrackingSelectionPress = false
		suppressSelectionOnMouseUp = false
		if shouldSelect {
			selectClosure?()
		}
	}

	override func keyDown(with event: NSEvent) {
		if let reorderableListEventForwardingView {
			reorderableListEventForwardingView.keyDown(with: event)
		}
		else if let nextResponder {
			nextResponder.keyDown(with: event)
		}
		else {
			super.keyDown(with: event)
		}
	}

	override func cancelOperation(_ sender: Any?) {
		if let reorderableListEventForwardingView,
		   reorderableListEventForwardingView.tryToPerform(
		   	#selector(NSResponder.cancelOperation(_:)),
		   	with: sender
		   ) {
			return
		}
		if let nextResponder,
		   nextResponder.tryToPerform(#selector(NSResponder.cancelOperation(_:)), with: sender) {
			return
		}
		super.cancelOperation(sender)
	}

	func reorderableListItemDidBeginDrag() {
		isTrackingSelectionPress = false
		suppressSelectionOnMouseUp = true
	}

	func reorderableListItemDidUpdate(
		cellState: ReorderableListCellState,
		animated: Bool
	) {
		currentCellState = cellState
		applyDragStyling(animated: animated)
	}

	func reorderableListItemDidEndDrag(cancelled _: Bool) {}

	func reorderableListDragChromeGeometry() -> ReorderableListDragChromeGeometry? {
		ReorderableListDragChromeGeometry(
			chromeFrame: selectedBackground.frame,
			cornerRadius: activeCornerRadius,
			borderWidth: DragStyle.borderWidth
		)
	}

	func syncHoverStateForCurrentPointerLocation(mouseLocationInWindow: NSPoint? = nil) {
		guard isHidden == false, superview?.isHiddenOrHasHiddenAncestor != true else {
			setHoverState(isRowHovered: false, isCloseButtonHovered: false)
			return
		}
		guard !currentCellState.isReordering else {
			setHoverState(isRowHovered: false, isCloseButtonHovered: false)
			return
		}
		guard let resolvedMouseLocation = mouseLocationInWindow ?? resolvedMouseLocationInWindow() else {
			setHoverState(isRowHovered: false, isCloseButtonHovered: false)
			return
		}

		let localPoint: NSPoint
		let closeButtonPoint: NSPoint
		if window != nil {
			localPoint = convert(resolvedMouseLocation, from: nil)
			closeButtonPoint = closeButton.convert(resolvedMouseLocation, from: nil)
		}
		else {
			localPoint = resolvedMouseLocation
			closeButtonPoint = closeButton.convert(localPoint, from: self)
		}
		let isPointerInsideVisibleRow = visibleRect.isEmpty == false
			&& bounds.contains(localPoint)
			&& visibleRect.contains(localPoint)
		let isPointerInsideCloseButton = isPointerInsideVisibleRow
			&& closeButton.bounds.contains(closeButtonPoint)
		setHoverState(
			isRowHovered: isPointerInsideVisibleRow,
			isCloseButtonHovered: isPointerInsideCloseButton
		)
	}

	private func resolvedMouseLocationInWindow() -> NSPoint? {
		#if DEBUG
			if let mouseLocationInWindowOverride {
				return mouseLocationInWindowOverride
			}
		#endif
		return window?.mouseLocationOutsideOfEventStream
	}

	private func updateClipViewObservation() {
		let clipView = enclosingScrollView?.contentView
		guard observedClipView !== clipView else { return }
		stopObservingClipView()
		observedClipView = clipView
		clipView?.postsBoundsChangedNotifications = true
		if let clipView {
			NotificationCenter.default.addObserver(
				self,
				selector: #selector(clipViewBoundsDidChange(_:)),
				name: NSView.boundsDidChangeNotification,
				object: clipView
			)
		}
	}

	private func stopObservingClipView() {
		if let observedClipView {
			NotificationCenter.default.removeObserver(
				self,
				name: NSView.boundsDidChangeNotification,
				object: observedClipView
			)
		}
		observedClipView = nil
	}

	private func applyDragStyling(animated: Bool) {
		let cellState = currentCellState
		let targetStyle = effectiveRowStyle(for: cellState)
		let targetBackgroundColor = targetStyle.backgroundColor.cgColor
		let targetBorderWidth = cellState.isReordering ? DragStyle.borderWidth : targetStyle.outerBorderWidth
		let targetBorderColor = (cellState.isReordering
			? resolvedColor(Asset.Colors.accent.color)
			.withAlphaComponent(DragStyle.activeBorderOpacity)
			: targetStyle.outerBorderColor).cgColor
		let targetShadowOpacity = targetStyle.shadowOpacity
		let targetShadowRadius = targetStyle.shadowRadius
		let targetTransform = cellState.isReordering
			? CATransform3DMakeRotation(
				(DragStyle.activeRotationDegrees * .pi) / 180,
				0,
				0,
				1
			)
			: CATransform3DIdentity

		guard let layer = selectedBackground.layer else { return }
		updateSelectedBackgroundBorderPath(borderWidth: targetBorderWidth)
		let shouldAnimateBackgroundColor = animated && shouldAnimateBackgroundColorTransition(
			on: layer,
			to: targetBackgroundColor,
			cellState: cellState
		)

		if shouldAnimateBackgroundColor {
			animateColor(
				on: layer,
				key: BrowserSidebarTabRowLayerAnimationKey.backgroundColor,
				keyPath: LayerAnimationPath.backgroundColor,
				to: targetBackgroundColor
			)
		}

		if animated {
			animateShapeCGFloat(
				on: selectedBackgroundBorderLayer,
				key: BrowserSidebarTabRowLayerAnimationKey.borderWidth,
				keyPath: ShapeLayerAnimationPath.lineWidth,
				to: targetBorderWidth
			)
			animateShapeColor(
				on: selectedBackgroundBorderLayer,
				key: BrowserSidebarTabRowLayerAnimationKey.borderColor,
				keyPath: ShapeLayerAnimationPath.strokeColor,
				to: targetBorderWidth > 0 ? targetBorderColor : NSColor.clear.cgColor
			)
			animateTransform(
				on: layer,
				key: BrowserSidebarTabRowLayerAnimationKey.transform,
				keyPath: LayerAnimationPath.transform,
				to: targetTransform
			)
			animateFloat(
				on: layer,
				key: BrowserSidebarTabRowLayerAnimationKey.shadowOpacity,
				keyPath: LayerAnimationPath.shadowOpacity,
				to: targetShadowOpacity
			)
			animateCGFloat(
				on: layer,
				key: BrowserSidebarTabRowLayerAnimationKey.shadowRadius,
				keyPath: LayerAnimationPath.shadowRadius,
				to: targetShadowRadius
			)
		}
		else {
			removeDragAnimations(from: layer)
			removeBorderAnimations(from: selectedBackgroundBorderLayer)
		}

		if !shouldAnimateBackgroundColor {
			layer.removeAnimation(forKey: BrowserSidebarTabRowLayerAnimationKey.backgroundColor)
		}

		CATransaction.begin()
		CATransaction.setDisableActions(true)
		layer.backgroundColor = targetBackgroundColor
		layer.borderWidth = 0
		layer.borderColor = nil
		layer.shadowColor = NSColor.black.cgColor
		layer.shadowOpacity = targetShadowOpacity
		layer.shadowRadius = targetShadowRadius
		layer.shadowOffset = targetStyle.shadowOffset
		layer.transform = targetTransform
		selectedBackgroundBorderLayer.lineWidth = targetBorderWidth
		selectedBackgroundBorderLayer.strokeColor = targetBorderWidth > 0
			? targetBorderColor
			: NSColor.clear.cgColor
		CATransaction.commit()
	}

	private func shouldAnimateBackgroundColorTransition(
		on layer: CALayer,
		to targetValue: CGColor,
		cellState: ReorderableListCellState
	) -> Bool {
		guard !isHovered else { return false }
		guard cellState.isReordering else { return true }
		guard let currentColor = layer.presentation()?.backgroundColor ?? layer.backgroundColor else {
			return false
		}
		return !colorsMatch(currentColor, NSColor.clear.cgColor)
			&& !colorsMatch(currentColor, targetValue)
	}

	private func animateColor(
		on layer: CALayer,
		key: String,
		keyPath: String,
		to targetValue: CGColor
	) {
		let animation = CABasicAnimation(keyPath: keyPath)
		animation.duration = DragStyle.animationDuration
		animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
		animation.fromValue = layer.presentation()?.backgroundColor ?? layer.backgroundColor
		animation.toValue = targetValue
		layer.add(animation, forKey: key)
	}

	private func animateCGFloat(
		on layer: CALayer,
		key: String,
		keyPath: String,
		to targetValue: CGFloat
	) {
		let currentValue: CGFloat = switch keyPath {
		case LayerAnimationPath.shadowRadius:
			layer.presentation()?.shadowRadius ?? layer.shadowRadius
		default:
			targetValue
		}

		guard abs(currentValue - targetValue) > .ulpOfOne else {
			layer.removeAnimation(forKey: key)
			return
		}

		let animation = CABasicAnimation(keyPath: keyPath)
		animation.duration = DragStyle.animationDuration
		animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
		animation.fromValue = currentValue
		animation.toValue = targetValue
		layer.add(animation, forKey: key)
	}

	private func animateShapeCGFloat(
		on layer: CAShapeLayer,
		key: String,
		keyPath: String,
		to targetValue: CGFloat
	) {
		let currentValue = layer.presentation()?.lineWidth ?? layer.lineWidth
		guard abs(currentValue - targetValue) > .ulpOfOne else {
			layer.removeAnimation(forKey: key)
			return
		}

		let animation = CABasicAnimation(keyPath: keyPath)
		animation.duration = DragStyle.animationDuration
		animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
		animation.fromValue = currentValue
		animation.toValue = targetValue
		layer.add(animation, forKey: key)
	}

	private func animateFloat(
		on layer: CALayer,
		key: String,
		keyPath: String,
		to targetValue: Float
	) {
		let currentValue = layer.presentation()?.shadowOpacity ?? layer.shadowOpacity
		guard abs(currentValue - targetValue) > .ulpOfOne else {
			layer.removeAnimation(forKey: key)
			return
		}

		let animation = CABasicAnimation(keyPath: keyPath)
		animation.duration = DragStyle.animationDuration
		animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
		animation.fromValue = currentValue
		animation.toValue = targetValue
		layer.add(animation, forKey: key)
	}

	private func animateShapeColor(
		on layer: CAShapeLayer,
		key: String,
		keyPath: String,
		to targetValue: CGColor
	) {
		let animation = CABasicAnimation(keyPath: keyPath)
		animation.duration = DragStyle.animationDuration
		animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
		animation.fromValue = layer.presentation()?.strokeColor ?? layer.strokeColor
		animation.toValue = targetValue
		layer.add(animation, forKey: key)
	}

	private func animateTransform(
		on layer: CALayer,
		key: String,
		keyPath: String,
		to targetValue: CATransform3D
	) {
		let currentValue = layer.presentation()?.transform ?? layer.transform
		guard !CATransform3DEqualToTransform(currentValue, targetValue) else {
			layer.removeAnimation(forKey: key)
			return
		}

		let animation = CABasicAnimation(keyPath: keyPath)
		animation.duration = DragStyle.animationDuration
		animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
		animation.fromValue = NSValue(caTransform3D: currentValue)
		animation.toValue = NSValue(caTransform3D: targetValue)
		layer.add(animation, forKey: key)
	}

	private func removeDragAnimations(from layer: CALayer) {
		layer.removeAnimation(forKey: BrowserSidebarTabRowLayerAnimationKey.backgroundColor)
		layer.removeAnimation(forKey: BrowserSidebarTabRowLayerAnimationKey.borderWidth)
		layer.removeAnimation(forKey: BrowserSidebarTabRowLayerAnimationKey.borderColor)
		layer.removeAnimation(forKey: BrowserSidebarTabRowLayerAnimationKey.shadowOpacity)
		layer.removeAnimation(forKey: BrowserSidebarTabRowLayerAnimationKey.shadowRadius)
		layer.removeAnimation(forKey: BrowserSidebarTabRowLayerAnimationKey.transform)
	}

	private func removeBorderAnimations(from layer: CAShapeLayer) {
		layer.removeAnimation(forKey: BrowserSidebarTabRowLayerAnimationKey.borderWidth)
		layer.removeAnimation(forKey: BrowserSidebarTabRowLayerAnimationKey.borderColor)
	}

	private func effectiveRowStyle(
		for cellState: ReorderableListCellState
	) -> BrowserSidebarSelectedRowStyle {
		if cellState.isReordering {
			return BrowserSidebarSelectedRowStyle(backgroundColor: resolvedColor(rowBackgroundColor))
		}

		if displayContext == .pinned {
			if isSelectedRow {
				if usesLightModeSelectedStyle {
					return BrowserSidebarSelectedRowStyle(
						backgroundColor: resolvedColor(DragStyle.lightModeSelectedFillColor),
						outerBorderColor: resolvedColor(Asset.Colors.separatorPrimaryColor.color),
						outerBorderWidth: 1.5,
						shadowOpacity: DragStyle.lightModeSelectedShadowOpacity,
						shadowRadius: DragStyle.lightModeSelectedShadowRadius,
						shadowOffset: DragStyle.lightModeSelectedShadowOffset
					)
				}
				return BrowserSidebarSelectedRowStyle(
					backgroundColor: resolvedColor(DragStyle.selectedFillColor),
					outerBorderColor: resolvedColor(Asset.Colors.accent.color),
					outerBorderWidth: 1.5
				)
			}
			return BrowserSidebarSelectedRowStyle(backgroundColor: resolvedColor(DragStyle.selectedFillColor))
		}

		if isSelectedRow {
			if usesLightModeSelectedStyle {
				return BrowserSidebarSelectedRowStyle(
					backgroundColor: resolvedColor(DragStyle.lightModeSelectedFillColor),
					outerBorderColor: resolvedColor(Asset.Colors.separatorPrimaryColor.color),
					outerBorderWidth: 1.5,
					shadowOpacity: DragStyle.lightModeSelectedShadowOpacity,
					shadowRadius: DragStyle.lightModeSelectedShadowRadius,
					shadowOffset: DragStyle.lightModeSelectedShadowOffset
				)
			}
			return BrowserSidebarSelectedRowStyle(backgroundColor: resolvedColor(DragStyle.selectedFillColor))
		}

		if isHovered {
			return BrowserSidebarSelectedRowStyle(backgroundColor: resolvedColor(DragStyle.selectedFillColor))
		}

		return BrowserSidebarSelectedRowStyle(backgroundColor: resolvedColor(rowBackgroundColor))
	}

	private func displayedBorderWidth(for cellState: ReorderableListCellState) -> CGFloat {
		cellState.isReordering ? DragStyle.borderWidth : effectiveRowStyle(for: cellState).outerBorderWidth
	}

	private func resolvedColor(_ color: NSColor) -> NSColor {
		var resolved = color
		resolvedAppearance.performAsCurrentDrawingAppearance {
			resolved = color.usingColorSpace(.deviceRGB) ?? color
		}
		return resolved
	}

	private var resolvedAppearance: NSAppearance {
		appearance ?? effectiveAppearance
	}

	private var usesLightModeSelectedStyle: Bool {
		Self.usesLightModeSelectedStyle(for: resolvedAppearance)
	}

	var closeButtonHighlightColorForTesting: CGColor? {
		closeButtonHighlightLayer.backgroundColor
	}

	var closeButtonHighlightFrameForTesting: CGRect {
		closeButtonHighlightLayer.frame
	}

	var closeButtonHighlightCornerRadiusForTesting: CGFloat {
		closeButtonHighlightLayer.cornerRadius
	}

	var closeButtonTintColorForTesting: NSColor? {
		closeButtonTintColor
	}

	var contextMenuItemTitlesForTesting: [String] {
		menu?.items.map(\.title) ?? []
	}

	var isCameraActivityIndicatorHiddenForTesting: Bool {
		cameraActivityIndicatorView.isHidden
	}

	var cameraActivityIndicatorToolTipForTesting: String? {
		cameraActivityIndicatorView.toolTip
	}

	private func colorsMatch(_ lhs: CGColor, _ rhs: CGColor) -> Bool {
		guard
			let lhsColor = NSColor(cgColor: lhs)?.usingColorSpace(.deviceRGB),
			let rhsColor = NSColor(cgColor: rhs)?.usingColorSpace(.deviceRGB)
		else {
			return lhs == rhs
		}

		return abs(lhsColor.redComponent - rhsColor.redComponent) <= 0.001
			&& abs(lhsColor.greenComponent - rhsColor.greenComponent) <= 0.001
			&& abs(lhsColor.blueComponent - rhsColor.blueComponent) <= 0.001
			&& abs(lhsColor.alphaComponent - rhsColor.alphaComponent) <= 0.001
	}

	override func hitTest(_ point: NSPoint) -> NSView? {
		guard currentTab != nil, bounds.contains(point) else { return nil }
		if isPointInCloseButton(point) {
			return closeButton
		}
		return self
	}

	@objc private func performCloseTab() {
		if currentTab?.isPinned == true {
			togglePinClosure?()
			return
		}
		closeClosure?()
	}

	@objc private func togglePinnedState() {
		togglePinClosure?()
	}

	@objc private func replacePinnedURL() {
		replacePinnedURLClosure?()
	}

	private func shouldTrackSelection(at localPoint: NSPoint) -> Bool {
		guard bounds.contains(localPoint) else { return false }
		guard !closeButton.isHidden else { return true }
		return !isPointInCloseButton(localPoint)
	}

	private func isPointInCloseButton(_ localPoint: NSPoint) -> Bool {
		guard !closeButton.isHidden else { return false }
		let closeButtonPoint = convert(localPoint, to: closeButton)
		return closeButton.bounds.contains(closeButtonPoint)
	}

	static func usesLightModeSelectedStyle(for appearance: NSAppearance) -> Bool {
		switch appearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight]) {
		case .darkAqua, .vibrantDark:
			false
		default:
			true
		}
	}
}

enum BrowserSidebarTabCloseButton {
	static func identifier(for tabID: BrowserTabID) -> String {
		"browser-sidebar-close-tab-\(tabID.uuidString)"
	}
}

enum BrowserSidebarTabRowLayerAnimationKey {
	static let backgroundColor = "browser-sidebar-tab-row-background-color"
	static let borderWidth = "browser-sidebar-tab-row-border-width"
	static let borderColor = "browser-sidebar-tab-row-border-color"
	static let shadowOpacity = "browser-sidebar-tab-row-shadow-opacity"
	static let shadowRadius = "browser-sidebar-tab-row-shadow-radius"
	static let transform = "browser-sidebar-tab-row-transform"
}

private struct BrowserSidebarSelectedRowStyle {
	let backgroundColor: NSColor
	let outerBorderColor: NSColor
	let outerBorderWidth: CGFloat
	let shadowOpacity: Float
	let shadowRadius: CGFloat
	let shadowOffset: CGSize

	init(
		backgroundColor: NSColor,
		outerBorderColor: NSColor = .clear,
		outerBorderWidth: CGFloat = 0,
		shadowOpacity: Float = 0,
		shadowRadius: CGFloat = 0,
		shadowOffset: CGSize = .zero
	) {
		self.backgroundColor = backgroundColor
		self.outerBorderColor = outerBorderColor
		self.outerBorderWidth = outerBorderWidth
		self.shadowOpacity = shadowOpacity
		self.shadowRadius = shadowRadius
		self.shadowOffset = shadowOffset
	}
}
