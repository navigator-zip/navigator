import AppKit
import Vendors

@MainActor
public protocol ReorderableListItemDragObserver: AnyObject {
	func reorderableListItemDidBeginDrag()
	func reorderableListItemDidEndDrag(cancelled: Bool)
}

@MainActor
public protocol ReorderableListItemEventForwarding: AnyObject {
	var reorderableListEventForwardingView: NSView? { get set }
}

@MainActor
public final class ReorderableListView<Item, ID: Hashable>: NSView {
	public typealias MoveAction = (IndexSet, Int) -> Void
	public typealias ContentViewBuilder = (Item) -> NSView

	private var configuration: ReorderableListConfiguration<Item, ID>
	private var selectedItemID: ID?
	private var clearTableHeaderHeight: CGFloat = 0
	private var clearTableFooterHeight: CGFloat = 0
	private let scrollView = ReorderableListScrollView()
	private let documentContainerView = ReorderableListDocumentView()
	private let overlayHostView = ReorderableTableOverlayHostView()
	private let clearTableHeaderView = ReorderableListSpacerView()
	private let clearTableFooterView = ReorderableListSpacerView()
	private let tableView = ReorderableListTableView()
	private let tableColumn = NSTableColumn(identifier: .reorderableListColumn)
	private let controller: ReorderableListController<Item, ID>
	private let edgeFadeMaskLayer = CAGradientLayer()
	private var edgeFadeHeight: CGFloat = 0
	private var boundsChangeObservation: NSObjectProtocol?

	public init(
		items: [Item],
		id: KeyPath<Item, ID>,
		contentInsets: NSEdgeInsets,
		rowSpacing: CGFloat,
		rowBackgroundColor: NSColor,
		onMove: @escaping MoveAction,
		contentViewBuilder: @escaping ContentViewBuilder
	) {
		self.configuration = ReorderableListConfiguration<Item, ID>(
			id: id,
			contentInsets: contentInsets,
			rowSpacing: rowSpacing,
			rowBackgroundColor: rowBackgroundColor,
			dragAppearance: .init(),
			autoscroll: .init(),
			reorderHandleWidth: nil,
			longPressDuration: 0,
			accessibilityAnnouncementsEnabled: true,
			accessibilityAnnouncementHandler: { _ in },
			onMove: onMove,
			canMove: nil,
			onMoveStart: nil,
			onMoveUpdate: nil,
			onMoveEnd: nil,
			onReorderInteractionDidFinish: nil,
			contentViewBuilder: contentViewBuilder,
			dragStartThreshold: ReorderableListStyle.dragActivationSlop,
			estimatedRowHeight: 40,
			fixedRowHeight: nil
		)
		self.controller = ReorderableListController(
			items: items,
			configuration: self.configuration,
			tableView: tableView,
			tableColumn: tableColumn
		)
		super.init(frame: .zero)
		setup()
		controller.attach(hostView: self, overlayHostView: overlayHostView)
		controller.reload()
		layoutClearTableChrome()
	}

	public convenience init(
		items: [Item],
		id: KeyPath<Item, ID>,
		contentInsets: NSEdgeInsets,
		rowBackgroundColor: NSColor,
		onMove: @escaping MoveAction,
		contentViewBuilder: @escaping ContentViewBuilder
	) {
		self.init(
			items: items,
			id: id,
			contentInsets: contentInsets,
			rowSpacing: 0,
			rowBackgroundColor: rowBackgroundColor,
			onMove: onMove,
			contentViewBuilder: contentViewBuilder
		)
	}

	init(
		items: [Item],
		configuration: ReorderableListConfiguration<Item, ID>
	) {
		self.configuration = configuration
		self.controller = ReorderableListController(
			items: items,
			configuration: configuration,
			tableView: tableView,
			tableColumn: tableColumn
		)
		super.init(frame: .zero)
		setup()
		controller.attach(hostView: self, overlayHostView: overlayHostView)
		controller.reload()
		layoutClearTableChrome()
	}

	public init(
		items: [Item],
		id: KeyPath<Item, ID>,
		contentInsets: NSEdgeInsets,
		rowSpacing: CGFloat,
		rowBackgroundColor: NSColor,
		fixedRowHeight: CGFloat,
		onMove: @escaping MoveAction,
		contentViewBuilder: @escaping ContentViewBuilder
	) {
		self.configuration = ReorderableListConfiguration<Item, ID>(
			id: id,
			contentInsets: contentInsets,
			rowSpacing: rowSpacing,
			rowBackgroundColor: rowBackgroundColor,
			dragAppearance: .init(),
			autoscroll: .init(),
			reorderHandleWidth: nil,
			longPressDuration: 0,
			accessibilityAnnouncementsEnabled: true,
			accessibilityAnnouncementHandler: { _ in },
			onMove: onMove,
			canMove: nil,
			onMoveStart: nil,
			onMoveUpdate: nil,
			onMoveEnd: nil,
			onReorderInteractionDidFinish: nil,
			contentViewBuilder: contentViewBuilder,
			dragStartThreshold: ReorderableListStyle.dragActivationSlop,
			estimatedRowHeight: fixedRowHeight,
			fixedRowHeight: fixedRowHeight
		)
		self.controller = ReorderableListController(
			items: items,
			configuration: self.configuration,
			tableView: tableView,
			tableColumn: tableColumn
		)
		super.init(frame: .zero)
		setup()
		controller.attach(hostView: self, overlayHostView: overlayHostView)
		controller.reload()
		layoutClearTableChrome()
	}

	public convenience init(
		items: [Item],
		id: KeyPath<Item, ID>,
		contentInsets: NSEdgeInsets,
		rowBackgroundColor: NSColor,
		fixedRowHeight: CGFloat,
		onMove: @escaping MoveAction,
		contentViewBuilder: @escaping ContentViewBuilder
	) {
		self.init(
			items: items,
			id: id,
			contentInsets: contentInsets,
			rowSpacing: 0,
			rowBackgroundColor: rowBackgroundColor,
			fixedRowHeight: fixedRowHeight,
			onMove: onMove,
			contentViewBuilder: contentViewBuilder
		)
	}

	@available(*, unavailable)
	public required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override public var acceptsFirstResponder: Bool {
		true
	}

	override public var isFlipped: Bool {
		true
	}

	override public func cancelOperation(_ sender: Any?) {
		guard controller.handleCancelOperation() else {
			_ = nextResponder?.tryToPerform(#selector(NSResponder.cancelOperation(_:)), with: sender)
			return
		}
	}

	override public func viewWillMove(toWindow newWindow: NSWindow?) {
		controller.handleViewWillMove(toWindow: newWindow)
		super.viewWillMove(toWindow: newWindow)
	}

	override public func layout() {
		super.layout()
		scrollView.frame = bounds
		overlayHostView.frame = bounds
		controller.layoutDidChange()
		layoutClearTableChrome()
		updateEdgeFadeMask()
	}

	override public func mouseDown(with event: NSEvent) {
		let locationInSelf = convert(event.locationInWindow, from: nil)
		guard controller.handleMouseDown(locationInSelf: locationInSelf) else {
			super.mouseDown(with: event)
			return
		}
	}

	override public func mouseDragged(with event: NSEvent) {
		let locationInSelf = convert(event.locationInWindow, from: nil)
		guard controller.handleMouseDragged(
			locationInSelf: locationInSelf,
			locationInWindow: event.locationInWindow
		) else {
			super.mouseDragged(with: event)
			return
		}
	}

	override public func mouseUp(with event: NSEvent) {
		let locationInSelf = convert(event.locationInWindow, from: nil)
		guard controller.handleMouseUp(locationInSelf: locationInSelf) else {
			super.mouseUp(with: event)
			return
		}
	}

	override public func keyDown(with event: NSEvent) {
		guard handleKeyDown(event) == false else { return }
		super.keyDown(with: event)
	}

	public var hasTransientReorderState: Bool {
		controller.hasTransientReorderState()
	}

	public var selectedID: ID? {
		get { selectedItemID }
		set {
			selectedItemID = newValue
			controller.updateSelectedItemID(newValue)
			if let newValue, let row = controller.tableRow(forItemID: newValue) {
				tableView.scrollRowToVisible(row)
			}
		}
	}

	public var onReorderInteractionDidFinish: (() -> Void)? {
		get { configuration.onReorderInteractionDidFinish }
		set {
			configuration.onReorderInteractionDidFinish = newValue
			controller.updateReorderInteractionDidFinish(newValue)
		}
	}

	public var onDropAboveList: ((ID) -> Void)? {
		didSet { controller.updateDropAboveListHandler(onDropAboveList) }
	}

	public var onDragAboveListThreshold: ((Bool, ID) -> Void)? {
		didSet { controller.updateDragAboveListThresholdHandler(onDragAboveListThreshold) }
	}

	public var onDragAboveListPositionUpdate: ((CGPoint) -> Void)? {
		didSet { controller.onDragAboveListPositionUpdate = onDragAboveListPositionUpdate }
	}

	public var onSettleTargetForDropAboveList: ((ID) -> CGRect?)? {
		didSet { controller.onSettleTargetForDropAboveList = onSettleTargetForDropAboveList }
	}

	public func externalDragPlaceholderFrameInHost(at insertionIndex: Int, rowHeight: CGFloat) -> CGRect? {
		controller.externalDragPlaceholderFrameInHost(at: insertionIndex, rowHeight: rowHeight)
	}

	public func showExternalDragPlaceholder(at insertionIndex: Int, rowHeight: CGFloat) {
		controller.showExternalDragPlaceholder(at: insertionIndex, rowHeight: rowHeight)
	}

	public func updateExternalDragPlaceholder(at insertionIndex: Int, rowHeight: CGFloat) {
		controller.updateExternalDragPlaceholder(at: insertionIndex, rowHeight: rowHeight)
	}

	public func hideExternalDragPlaceholder(animated: Bool = true) {
		controller.hideExternalDragPlaceholder(animated: animated)
	}

	public func setDragOverlayHost(_ host: NSView) {
		controller.attach(hostView: self, overlayHostView: host)
	}

	public func setDragBackgroundColor(_ color: NSColor) {
		controller.setDragBackgroundColor(color)
	}

	public func setActiveDragShapeOverride(size: CGSize, cornerRadius: CGFloat, targetSnapshot: NSImage? = nil, animated: Bool) {
		controller.setActiveDragShapeOverride(size: size, cornerRadius: cornerRadius, targetSnapshot: targetSnapshot, animated: animated)
	}

	public func clearActiveDragShapeOverride(animated: Bool) {
		controller.clearActiveDragShapeOverride(animated: animated)
	}

	public func setHorizontalScrollEventHandler(
		_ handler: (@MainActor (NSEvent) -> Bool)?
	) {
		scrollView.horizontalScrollEventHandler = handler
	}

	public func setEdgeFading(height: CGFloat) {
		edgeFadeHeight = max(0, height)
		if edgeFadeHeight > 0 {
			scrollView.wantsLayer = true
			scrollView.layer?.backgroundColor = NSColor.clear.cgColor
			scrollView.layer?.mask = edgeFadeMaskLayer
			if boundsChangeObservation == nil {
				scrollView.contentView.postsBoundsChangedNotifications = true
				boundsChangeObservation = NotificationCenter.default.addObserver(
					forName: NSView.boundsDidChangeNotification,
					object: scrollView.contentView,
					queue: .main
				) { [weak self] _ in
					MainActor.assumeIsolated {
						self?.updateEdgeFadeMask()
					}
				}
			}
			updateEdgeFadeMask()
		} else {
			scrollView.layer?.mask = nil
			if let observation = boundsChangeObservation {
				NotificationCenter.default.removeObserver(observation)
				boundsChangeObservation = nil
			}
		}
	}

	public func setScrollGestureDelegate(_ delegate: NSGestureRecognizerDelegate?) {
		scrollView.gestureRecognizers.forEach { $0.delegate = delegate }
		scrollView.contentView.gestureRecognizers.forEach { $0.delegate = delegate }
		tableView.gestureRecognizers.forEach { $0.delegate = delegate }
	}

	public func setItems(_ items: [Item]) {
		controller.setItems(items)
		controller.updateSelectedItemID(selectedItemID)
		layoutClearTableChrome()
	}

	public func setClearTableChromeHeights(headerHeight: CGFloat, footerHeight: CGFloat) {
		let resolvedHeaderHeight = max(0, headerHeight)
		let resolvedFooterHeight = max(0, footerHeight)
		guard
			clearTableHeaderHeight != resolvedHeaderHeight ||
			clearTableFooterHeight != resolvedFooterHeight
		else {
			return
		}

		clearTableHeaderHeight = resolvedHeaderHeight
		clearTableFooterHeight = resolvedFooterHeight
		controller.updateClearTableChromeHeights(
			headerHeight: resolvedHeaderHeight,
			footerHeight: resolvedFooterHeight
		)
		layoutClearTableChrome()
	}

	func updateMoveAction(_ onMove: @escaping MoveAction) {
		configuration.onMove = onMove
		controller.updateMoveAction(onMove)
	}

	func updateCanMove(_ canMove: ((Item) -> Bool)?) {
		configuration.canMove = canMove
		controller.updateCanMove(canMove)
	}

	func updateMoveLifecycleHandlers(
		onMoveStart: ((ID, Int) -> Void)?,
		onMoveUpdate: ((Int, Int) -> Void)?,
		onMoveEnd: ((Int, Int) -> Void)?
	) {
		configuration.onMoveStart = onMoveStart
		configuration.onMoveUpdate = onMoveUpdate
		configuration.onMoveEnd = onMoveEnd
		controller.updateMoveLifecycleHandlers(
			onMoveStart: onMoveStart,
			onMoveUpdate: onMoveUpdate,
			onMoveEnd: onMoveEnd
		)
	}

	func updateReorderInteractionDidFinish(_ onReorderInteractionDidFinish: (() -> Void)?) {
		configuration.onReorderInteractionDidFinish = onReorderInteractionDidFinish
		controller.updateReorderInteractionDidFinish(onReorderInteractionDidFinish)
	}

	func updateSelectedItemID(_ itemID: ID?) {
		selectedItemID = itemID
		controller.updateSelectedItemID(itemID)
	}

	@discardableResult
	func moveSelectedItem(direction: Int) -> Bool {
		controller.moveSelectedItem(direction: direction)
	}

	var performanceMetrics: ReorderPerformanceMetrics {
		controller.performanceMetrics
	}

	func handleKeyDown(_ event: NSEvent) -> Bool {
		controller.handleKeyDown(event)
	}

	public func appendItems(_ appendedItems: [Item]) {
		controller.appendItems(appendedItems)
		controller.updateSelectedItemID(selectedItemID)
		layoutClearTableChrome()
	}

	public func numberOfRows(in tableView: NSTableView) -> Int {
		controller.numberOfRows(in: tableView)
	}

	func beginDragForTesting(sourceIndex: Int, locationInContent: NSPoint) {
		controller.beginDragForTesting(sourceIndex: sourceIndex, locationInContent: locationInContent)
	}

	func updateDragForTesting(locationInContent: NSPoint) {
		controller.updateDragForTesting(locationInContent: locationInContent)
	}

	func endDragForTesting(cancelled: Bool) {
		controller.endDragForTesting(cancelled: cancelled)
	}

	func setAccessibilityAnnouncementHandlerForTesting(
		_ handler: @escaping @MainActor (String) -> Void
	) {
		controller.setAccessibilityAnnouncementHandlerForTesting(handler)
	}

	func autoscrollIsActiveForTesting() -> Bool {
		controller.autoscrollIsActiveForTesting()
	}

	@discardableResult
	func handleAutoscrollTickForTesting() -> Bool {
		controller.handleAutoscrollTickForTesting()
	}

	func scrollOffsetYForTesting() -> CGFloat {
		controller.scrollOffsetYForTesting()
	}

	func flushPendingDropResetForTesting() {
		controller.flushPendingDropResetForTesting()
	}

	func containerFrame(for index: Int) -> CGRect {
		controller.containerFrame(for: index)
	}

	func documentHeight() -> CGFloat {
		controller.documentHeight()
	}

	func tableFrameForTesting() -> CGRect {
		tableView.frame
	}

	func clearTableHeaderFrameForTesting() -> CGRect? {
		clearTableHeaderView.isHidden ? nil : clearTableHeaderView.frame
	}

	func clearTableFooterFrameForTesting() -> CGRect? {
		clearTableFooterView.isHidden ? nil : clearTableFooterView.frame
	}

	func currentVisualOrder() -> [Int] {
		controller.currentVisualOrder()
	}

	func dropIndicatorFrameForTesting() -> CGRect? {
		controller.dropIndicatorFrameForTesting()
	}

	func dropIndicatorColorForTesting() -> NSColor? {
		controller.dropIndicatorColorForTesting()
	}

	func dragPlaceholderFrameForTesting() -> CGRect? {
		controller.dragPlaceholderFrameForTesting()
	}

	func dragPlaceholderViewForTesting() -> ReorderableListDragPlaceholderView? {
		controller.dragPlaceholderViewForTesting()
	}

	func isReordering() -> Bool {
		controller.isReordering()
	}

	func hasPendingPressForTesting() -> Bool {
		controller.hasPendingPressForTesting()
	}

	func installPendingPressForTesting(sourceIndex: Int?, locationInSelf: NSPoint?) {
		controller.installPendingPressForTesting(sourceIndex: sourceIndex, locationInSelf: locationInSelf)
	}

	func beginPendingDragForTesting(locationInSelf: NSPoint? = nil) {
		controller.beginPendingDragForTesting(locationInSelf: locationInSelf)
	}

	func indexOfContainerForTesting(at locationInSelf: NSPoint) -> Int? {
		controller.indexOfContainerForTesting(at: locationInSelf)
	}

	func shouldBeginContainerDragForTesting(from hitView: NSView?) -> Bool {
		controller.shouldBeginContainerDragForTesting(from: hitView)
	}

	func sourceIndexForTesting(for view: NSView) -> Int? {
		controller.sourceIndexForTesting(for: view)
	}

	func containerViewForTesting(row: Int) -> ReorderableListItemContainerView? {
		controller.containerViewForTesting(row: row)
	}

	func rowViewForTesting(modelIndex: Int) -> ReorderableListRowView? {
		controller.rowViewForTesting(modelIndex: modelIndex)
	}

	func rowFrameForTesting(modelIndex: Int) -> CGRect? {
		guard modelIndex >= 0 else { return nil }
		return controller.containerFrame(for: modelIndex)
	}

	func rowPresentationFrameForTesting(modelIndex: Int) -> CGRect? {
		controller.dragPresentationFrameForTesting(modelIndex: modelIndex)
			?? rowViewForTesting(modelIndex: modelIndex)?.layer?.presentation()?.frame
	}

	func rowSettleAnimationDurationForTesting(modelIndex: Int) -> TimeInterval? {
		controller.rowSettleAnimationDurationForTesting(modelIndex: modelIndex)
	}

	private func updateEdgeFadeMask() {
		guard edgeFadeHeight > 0 else { return }
		let viewHeight = scrollView.bounds.height
		guard viewHeight > 0 else { return }

		CATransaction.begin()
		CATransaction.setDisableActions(true)
		edgeFadeMaskLayer.frame = scrollView.bounds

		let contentHeight = scrollView.documentView?.frame.height ?? 0
		let scrollOffset = scrollView.contentView.bounds.origin.y
		let maxOffset = contentHeight - viewHeight

		let showsTopFade = scrollOffset > 1
		let showsBottomFade = maxOffset - scrollOffset > 1

		let topStop = showsTopFade ? min(edgeFadeHeight / viewHeight, 0.5) : 0
		let bottomStop = showsBottomFade ? max(1.0 - (edgeFadeHeight / viewHeight), 0.5) : 1.0

		edgeFadeMaskLayer.colors = [
			NSColor.clear.cgColor,
			NSColor.black.cgColor,
			NSColor.black.cgColor,
			NSColor.clear.cgColor,
		]
		edgeFadeMaskLayer.locations = [
			0.0,
			NSNumber(value: topStop),
			NSNumber(value: bottomStop),
			1.0,
		]
		edgeFadeMaskLayer.startPoint = CGPoint(x: 0.5, y: 0)
		edgeFadeMaskLayer.endPoint = CGPoint(x: 0.5, y: 1)
		CATransaction.commit()
	}

	private func setup() {
		scrollView.translatesAutoresizingMaskIntoConstraints = true
		scrollView.hasVerticalScroller = true
		scrollView.contentView = ReorderableListClipView()

		documentContainerView.translatesAutoresizingMaskIntoConstraints = true
		overlayHostView.translatesAutoresizingMaskIntoConstraints = true

		tableView.translatesAutoresizingMaskIntoConstraints = true
		tableView.headerView = nil
		tableView.focusRingType = .none
		tableView.allowsColumnReordering = false
		tableView.allowsColumnResizing = false
		tableView.allowsMultipleSelection = false
		tableView.allowsEmptySelection = true
		tableView.style = .plain
		tableView.selectionHighlightStyle = .none
		tableView.intercellSpacing = NSSize(width: 0, height: configuration.rowSpacing)
		tableView.backgroundColor = .clear
		tableView.usesAlternatingRowBackgroundColors = false
		tableView.rowHeight = configuration.estimatedRowHeight
		tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
		tableColumn.resizingMask = .autoresizingMask
		tableView.addTableColumn(tableColumn)

		documentContainerView.addSubview(clearTableHeaderView)
		documentContainerView.addSubview(clearTableFooterView)
		documentContainerView.addSubview(tableView)
		scrollView.documentView = documentContainerView
		scrollView.drawsBackground = false
		scrollView.backgroundColor = .clear
		scrollView.contentView.backgroundColor = .clear
		addSubview(scrollView)
		addSubview(overlayHostView)
	}

	private func layoutClearTableChrome() {
		let documentWidth = max(documentContainerView.bounds.width, tableView.frame.width)

		clearTableHeaderView.isHidden = clearTableHeaderHeight == 0
		clearTableHeaderView.frame = CGRect(
			x: 0,
			y: 0,
			width: documentWidth,
			height: clearTableHeaderHeight
		)

		clearTableFooterView.isHidden = clearTableFooterHeight == 0
		clearTableFooterView.frame = CGRect(
			x: 0,
			y: tableView.frame.maxY,
			width: documentWidth,
			height: clearTableFooterHeight
		)
	}
}

final class ReorderableListScrollView: NSScrollView {
	var horizontalScrollEventHandler: (@MainActor (NSEvent) -> Bool)?

	override var isOpaque: Bool {
		false
	}

	override func hitTest(_ point: NSPoint) -> NSView? {
		guard bounds.contains(point) else { return nil }

		let hitView = super.hitTest(point)
		guard hitView === self || hitView === contentView else { return hitView }
		let contentView = contentView
		guard let documentView else { return hitView }

		let pointInContentView = contentView.convert(point, from: self)
		let pointInDocumentView = documentView.convert(pointInContentView, from: contentView)
		return documentView.hitTest(pointInDocumentView) ?? hitView
	}

	override func scrollWheel(with event: NSEvent) {
		if horizontalScrollEventHandler?(event) == true {
			return
		}
		super.scrollWheel(with: event)
	}
}

final class ReorderableListClipView: NSClipView {
	override var isOpaque: Bool {
		false
	}

	override func hitTest(_ point: NSPoint) -> NSView? {
		guard bounds.contains(point) else { return nil }

		let hitView = super.hitTest(point)
		guard hitView === self || hitView === documentView else { return hitView }
		guard let documentView else { return hitView }

		let pointInDocumentView = documentView.convert(point, from: self)
		return documentView.hitTest(pointInDocumentView) ?? hitView
	}
}

final class ReorderableListTableView: NSTableView {
	override var isOpaque: Bool {
		false
	}

	override var wantsDefaultClipping: Bool {
		false
	}

	override func drawBackground(inClipRect _: NSRect) {}

	override func hitTest(_ point: NSPoint) -> NSView? {
		guard bounds.contains(point) else { return nil }

		let hitView = super.hitTest(point)
		let row = row(at: point)
		guard row >= 0,
		      let container = view(
		      	atColumn: 0,
		      	row: row,
		      	makeIfNecessary: true
		      ) as? ReorderableListItemContainerView else {
			return hitView
		}

		let pointInContainer = container.convert(point, from: self)
		return container.hitTest(pointInContainer) ?? container
	}
}

final class ReorderableListDocumentView: NSView {
	override var isFlipped: Bool {
		true
	}

	override var isOpaque: Bool {
		false
	}
}

final class ReorderableListSpacerView: NSView {
	override var isOpaque: Bool {
		false
	}

	override var isFlipped: Bool {
		true
	}

	override func hitTest(_: NSPoint) -> NSView? {
		nil
	}
}

public final class ReorderableListDragPlaceholderView: NSView {
	private enum AnimationKey {
		static let dashPhase = "lineDashPhase"
		static let dashPhaseAnimation = "reorderableListDragPlaceholderDashPhaseAnimation"
	}

	private let strokeLayer = ReorderableListAnimationShapeLayer()

	public var cornerRadiusOverride: CGFloat?

	override public var isOpaque: Bool {
		false
	}

	override public var isFlipped: Bool {
		true
	}

	override public func makeBackingLayer() -> CALayer {
		ReorderableListAnimationLayer()
	}

	override public init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		setup()
	}

	@available(*, unavailable)
	public required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override public func layout() {
		super.layout()
		let resolvedCornerRadius = cornerRadiusOverride ?? ReorderableListStyle.cornerRadius
		strokeLayer.frame = bounds
		strokeLayer.path = CGPath(
			roundedRect: bounds.insetBy(
				dx: ReorderableListStyle.borderWidth / 2,
				dy: ReorderableListStyle.borderWidth / 2
			),
			cornerWidth: max(0, resolvedCornerRadius - (ReorderableListStyle.borderWidth / 2)),
			cornerHeight: max(0, resolvedCornerRadius - (ReorderableListStyle.borderWidth / 2)),
			transform: nil
		)
	}

	override public func viewDidChangeEffectiveAppearance() {
		super.viewDidChangeEffectiveAppearance()
		applyResolvedStrokeColor()
	}

	public func show(frame: CGRect) {
		self.frame = frame
		isHidden = false
		needsLayout = true
		layoutSubtreeIfNeeded()
		applyResolvedStrokeColor()
		startDashAnimationIfNeeded()
	}

	public func hide() {
		isHidden = true
		strokeLayer.removeAnimation(forKey: AnimationKey.dashPhaseAnimation)
	}

	var strokeColorForTesting: NSColor? {
		guard let cgColor = strokeLayer.strokeColor else { return nil }
		return NSColor(cgColor: cgColor)
	}

	var dashPatternForTesting: [NSNumber] {
		strokeLayer.lineDashPattern ?? []
	}

	var isDashAnimationActiveForTesting: Bool {
		strokeLayer.animation(forKey: AnimationKey.dashPhaseAnimation) != nil
	}

	private func setup() {
		wantsLayer = true
		layer?.masksToBounds = false
		layer?.backgroundColor = NSColor.clear.cgColor
		strokeLayer.fillColor = NSColor.clear.cgColor
		strokeLayer.lineWidth = ReorderableListStyle.borderWidth
		strokeLayer.lineDashPattern = ReorderableListStyle.dragPlaceholderDashPattern
		strokeLayer.lineCap = .round
		layer?.addSublayer(strokeLayer)
		isHidden = true
	}

	private func applyResolvedStrokeColor() {
		let resolvedColor = ReorderableListStyle.resolvedColor(
			ReorderableListStyle.dragPlaceholderStrokeColor,
			for: effectiveAppearance
		)
		strokeLayer.strokeColor = resolvedColor.cgColor
	}

	private func startDashAnimationIfNeeded() {
		guard strokeLayer.animation(forKey: AnimationKey.dashPhaseAnimation) == nil else { return }
		let phaseShift = ReorderableListStyle.dragPlaceholderDashPattern
			.reduce(0) { $0 + $1.doubleValue }
		let animation = CABasicAnimation(keyPath: AnimationKey.dashPhase)
		animation.byValue = -phaseShift
		animation.duration = ReorderableListStyle.dragPlaceholderAnimationDuration
		animation.repeatCount = .infinity
		animation.timingFunction = CAMediaTimingFunction(name: .linear)
		animation.isRemovedOnCompletion = false
		strokeLayer.add(animation, forKey: AnimationKey.dashPhaseAnimation)
	}
}

final class ReorderableListRowView: NSTableRowView {
	override var isOpaque: Bool {
		false
	}

	override var wantsDefaultClipping: Bool {
		false
	}

	override func makeBackingLayer() -> CALayer {
		ReorderableListAnimationLayer()
	}

	override func drawBackground(in _: NSRect) {}

	override func viewDidMoveToSuperview() {
		super.viewDidMoveToSuperview()
		wantsLayer = true
		layer?.masksToBounds = false
	}

	override func hitTest(_ point: NSPoint) -> NSView? {
		guard bounds.contains(point) else { return nil }

		for subview in subviews.reversed() {
			let pointInSubview = convert(point, to: subview)
			if let hitView = subview.hitTest(pointInSubview) {
				return hitView
			}
			if subview.frame.contains(point) {
				return subview
			}
		}

		return super.hitTest(point)
	}
}
