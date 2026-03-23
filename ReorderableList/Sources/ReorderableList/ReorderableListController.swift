import AppKit
import Vendors

private let reorderableListUpArrowKeyCode: UInt16 = 126
private let reorderableListDownArrowKeyCode: UInt16 = 125
private let reorderableListEscapeKeyCode: UInt16 = 53

@MainActor
final class ReorderableListController<Item, ID: Hashable>: NSObject,
	NSTableViewDataSource,
	NSTableViewDelegate {
	private enum VisibleRowLoadReason {
		case initial
		case autoscrollEdge
	}

	private var configuration: ReorderableListConfiguration<Item, ID>
	private let tableView: ReorderableListTableView
	private let tableColumn: NSTableColumn
	private let dragController: ReorderableListDragController<ID>
	private let dragVisualController = ReorderableListDragVisualController()
	private let geometryEngine = ReorderableListGeometryEngine()
	private var overlayCoordinator: ReorderableListOverlayCoordinator!
	private var placeholderCoordinator: ReorderableListPlaceholderCoordinator!
	private var announcementCoordinator: ReorderableListAnnouncementCoordinator!
	private var dragRuntime: ReorderableListDragRuntime<ID>!
	private let eventMonitoring: ReorderableListEventMonitoring
	private let performanceTracing: any ReorderableListPerformanceTracing
	private let monotonicClock: () -> TimeInterval
	private let dropIndicatorLayer = ReorderableListAnimationLayer()
	private let dragPlaceholderView = ReorderableListDragPlaceholderView()
	private weak var hostView: NSView?
	private weak var overlayHostView: NSView?

	private var rows: [ReorderableListRowModel<Item, ID>]
	private var displayOrder: [ID]
	private var modelIndexByID: [ID: Int]
	private var displayRowByID: [ID: Int]
	private var queuedItems: [Item]?
	private var testingPendingPressIndex: Int?
	private var testingPendingPressLocationInSelf: NSPoint?
	private var pendingPressWorkItem: DispatchWorkItem?
	private var measuredRowWidth: CGFloat = 0
	private var dragPlaceholderFrame: CGRect?
	private var currentDragDisplacement: (sourceIndex: Int, insertionIndex: Int, rowHeight: CGFloat)?
	private var selectedItemID: ID?
	private var currentPerformanceMetrics = ReorderPerformanceMetrics()
	private var observesWindowResignKey = false
	private var observesApplicationResignActive = false
	private var dragEscapeMonitor: Any?
	private var dragMouseUpMonitor: Any?
	private var dragMouseDraggedMonitor: Any?
	private var dragPreviewImageCache = [ID: ReorderableListDragPreviewCacheEntry]()
	private var activeSettleTraceHandle: ReorderableListPerformanceTraceHandle?
	private var activeSettleStartTime: TimeInterval?
	private var clearTableHeaderHeight: CGFloat = 0
	private var clearTableFooterHeight: CGFloat = 0

	private var modelOrder: [ID] {
		rows.map(\.id)
	}

	var performanceMetrics: ReorderPerformanceMetrics {
		currentPerformanceMetrics
	}

	init(
		items: [Item],
		configuration: ReorderableListConfiguration<Item, ID>,
		tableView: ReorderableListTableView,
		tableColumn: NSTableColumn,
		eventMonitoring: ReorderableListEventMonitoring = .live,
		performanceTracing: any ReorderableListPerformanceTracing = ReorderableListOSPerformanceTracing(),
		monotonicClock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
	) {
		self.configuration = configuration
		self.tableView = tableView
		self.tableColumn = tableColumn
		self.eventMonitoring = eventMonitoring
		self.performanceTracing = performanceTracing
		self.monotonicClock = monotonicClock
		self.rows = items.map {
			ReorderableListRowModel(id: $0[keyPath: configuration.id], item: $0, measuredHeight: nil)
		}
		self.displayOrder = self.rows.map(\.id)
		self.modelIndexByID = Self.indexMap(for: self.rows.map(\.id))
		self.displayRowByID = Self.indexMap(for: self.displayOrder)
		self.dragController = ReorderableListDragController(
			dragStartThreshold: configuration.dragStartThreshold
		)
		super.init()
		let runtimeContext = ReorderableListDragRuntime<ID>.Context(
			fallbackWindowPointer: { [weak self] in
				self?.hostView?.window?.mouseLocationOutsideOfEventStream
			},
			convertWindowPointToHost: { [weak self] point in
				guard let self, let hostView = self.hostView else { return point }
				guard hostView.window != nil else { return point }
				return hostView.convert(point, from: nil)
			},
			convertHostPointToTable: { [weak self] point in
				self?.tableView.convert(point, from: self?.hostView) ?? point
			},
			convertTableFrameToHost: { [weak self] frame in
				guard let self else { return frame }
				return self.tableView.convert(frame, to: self.overlayHostView ?? self.hostView)
			},
			sourceRowFrame: { [weak self] session in
				guard let self,
				      let row = self.row(for: session.itemID) else {
					return nil
				}
				return self.tableView.rect(ofRow: row)
			},
			rowCount: { [weak self] in self?.rows.count ?? 0 },
			rowSpacing: { [weak self] in self?.configuration.rowSpacing ?? 0 },
			contentInsets: { NSEdgeInsetsZero },
			visibleRect: { [weak self] in self?.tableView.visibleRect ?? .zero },
			attemptScrollBy: { [weak self] delta in
				guard let self else { return false }
				return self.attemptScrollBy(delta)
			},
			updateSession: { [weak self] session in
				self?.dragController.updateSession(session)
			},
			activeSession: { [weak self] in self?.dragController.activeSession },
			onTick: { [weak self] output in
				self?.didTick(with: output)
			},
			onFrameTiming: { _ in }
		)
		overlayCoordinator = ReorderableListOverlayCoordinator(dragVisualController: dragVisualController)
		placeholderCoordinator = ReorderableListPlaceholderCoordinator(placeholderView: dragPlaceholderView)
		announcementCoordinator = ReorderableListAnnouncementCoordinator(
			accessibilityEnabled: { [weak self] in
				self?.configuration.accessibilityAnnouncementsEnabled ?? false
			},
			announce: { [weak self] announcement in
				guard let configuration = self?.configuration else { return }
				configuration.accessibilityAnnouncementHandler(announcement)
			}
		)
		dragRuntime = ReorderableListDragRuntime<ID>(
			context: runtimeContext,
			autoscrollConfiguration: configuration.autoscroll,
			monotonicClock: { ProcessInfo.processInfo.systemUptime }
		)
		tableView.dataSource = self
		tableView.delegate = self
		tableView.wantsLayer = true
		tableView.layer?.backgroundColor = .clear
		configureDragPlaceholderView()
		configureDropIndicatorLayer()
	}

	func updateMoveAction(_ onMove: @escaping ReorderableListView<Item, ID>.MoveAction) {
		configuration.onMove = onMove
	}

	func updateCanMove(_ canMove: ((Item) -> Bool)?) {
		configuration.canMove = canMove
	}

	func updateMoveLifecycleHandlers(
		onMoveStart: ((ID, Int) -> Void)?,
		onMoveUpdate: ((Int, Int) -> Void)?,
		onMoveEnd: ((Int, Int) -> Void)?
	) {
		configuration.onMoveStart = onMoveStart
		configuration.onMoveUpdate = onMoveUpdate
		configuration.onMoveEnd = onMoveEnd
	}

	func updateReorderInteractionDidFinish(_ onReorderInteractionDidFinish: (() -> Void)?) {
		configuration.onReorderInteractionDidFinish = onReorderInteractionDidFinish
	}

	private var onDropAboveList: ((ID) -> Void)?
	private var onDragAboveListThresholdChanged: ((Bool, ID) -> Void)?
	var onSettleTargetForDropAboveList: ((ID) -> CGRect?)?
	private var isDragAboveListThreshold = false
	private var lastDraggedFrameMidX: CGFloat?
	private var dragBackgroundColor: NSColor?
	private var externalDragDisplacement: (insertionIndex: Int, rowHeight: CGFloat)?
	var onDragAboveListPositionUpdate: ((CGPoint) -> Void)?

	func updateDropAboveListHandler(_ handler: ((ID) -> Void)?) {
		onDropAboveList = handler
	}

	func updateDragAboveListThresholdHandler(_ handler: ((Bool, ID) -> Void)?) {
		onDragAboveListThresholdChanged = handler
	}

	func setDragBackgroundColor(_ color: NSColor) {
		dragBackgroundColor = color
	}

	func setActiveDragShapeOverride(size: CGSize, cornerRadius: CGFloat, targetSnapshot: NSImage?, animated: Bool) {
		overlayCoordinator.overrideDragShape(to: size, cornerRadius: cornerRadius, targetSnapshot: targetSnapshot, animated: animated)
	}

	func clearActiveDragShapeOverride(animated: Bool) {
		let cursorX = animated ? overlayCoordinator.currentFrameInHost?.midX : nil
		let targetX = animated ? lastDraggedFrameMidX : nil
		overlayCoordinator.clearDragShapeOverride(animated: animated, sourceCursorX: cursorX, targetCenterX: targetX)
	}

	func externalDragPlaceholderFrameInHost(at insertionIndex: Int, rowHeight: CGFloat) -> CGRect? {
		guard let overlayHostView else { return nil }
		let frame = externalPlaceholderFrame(at: insertionIndex, rowHeight: rowHeight)
		return tableView.convert(frame, to: overlayHostView)
	}

	func showExternalDragPlaceholder(at insertionIndex: Int, rowHeight: CGFloat) {
		externalDragDisplacement = (insertionIndex: insertionIndex, rowHeight: rowHeight)
		let frame = externalPlaceholderFrame(at: insertionIndex, rowHeight: rowHeight)
		placeholderCoordinator.show(frame: resolvedDragPlaceholderFrame(from: frame))
		updateVisibleRowDisplacements(animated: true)
	}

	func updateExternalDragPlaceholder(at insertionIndex: Int, rowHeight: CGFloat) {
		guard externalDragDisplacement?.insertionIndex != insertionIndex else { return }
		externalDragDisplacement = (insertionIndex: insertionIndex, rowHeight: rowHeight)
		let frame = externalPlaceholderFrame(at: insertionIndex, rowHeight: rowHeight)
		placeholderCoordinator.show(frame: resolvedDragPlaceholderFrame(from: frame))
		updateVisibleRowDisplacements(animated: true)
	}

	func hideExternalDragPlaceholder(animated: Bool = true) {
		externalDragDisplacement = nil
		updateVisibleRowDisplacements(animated: animated)
		placeholderCoordinator.hide()
	}

	private func externalPlaceholderFrame(at insertionIndex: Int, rowHeight: CGFloat) -> CGRect {
		let rowSpacing = configuration.rowSpacing
		if insertionIndex < rows.count {
			let rowRect = tableView.rect(ofRow: insertionIndex)
			return CGRect(x: rowRect.origin.x, y: rowRect.origin.y, width: rowRect.width, height: rowHeight)
		} else if rows.count > 0 {
			let lastRowRect = tableView.rect(ofRow: rows.count - 1)
			return CGRect(
				x: lastRowRect.origin.x,
				y: lastRowRect.maxY + rowSpacing,
				width: lastRowRect.width,
				height: rowHeight
			)
		} else {
			return CGRect(
				x: 0,
				y: configuration.contentInsets.top,
				width: tableView.bounds.width,
				height: rowHeight
			)
		}
	}

	func updateSelectedItemID(_ itemID: ID?) {
		if selectedItemID != itemID {
			invalidateDragPreviewCache()
		}
		selectedItemID = itemID
		syncSelectionIfNeeded()
	}

	func updateClearTableChromeHeights(headerHeight: CGFloat, footerHeight: CGFloat) {
		clearTableHeaderHeight = max(0, headerHeight)
		clearTableFooterHeight = max(0, footerHeight)
		updateTableFrame()
	}

	@discardableResult
	func moveSelectedItem(direction: Int) -> Bool {
		guard dragController.blocksModelUpdates == false,
		      direction == -1 || direction == 1,
		      let selectedItemID,
		      let sourceIndex = row(for: selectedItemID),
		      let rowModel = rowModel(for: selectedItemID),
		      configuration.canMove?(rowModel.item) ?? true else {
			return false
		}

		let insertionIndex: Int
		if direction < 0 {
			guard sourceIndex > 0 else { return false }
			insertionIndex = sourceIndex - 1
		}
		else {
			guard sourceIndex < rows.count - 1 else { return false }
			insertionIndex = min(rows.count, sourceIndex + 2)
		}

		commitMove(
			sourceIndex: sourceIndex,
			insertionIndex: insertionIndex,
			itemID: selectedItemID,
			announceCompletion: true
		)
		return true
	}

	func handleKeyDown(_ event: NSEvent) -> Bool {
		if isPlainEscapeKeyEvent(event) {
			return handleEscapeKeyDown()
		}
		let relevantModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
		guard relevantModifiers == [.command, .option] else { return false }

		switch event.keyCode {
		case reorderableListUpArrowKeyCode:
			return moveSelectedItem(direction: -1)
		case reorderableListDownArrowKeyCode:
			return moveSelectedItem(direction: 1)
		default:
			return false
		}
	}

	func hasTransientReorderState() -> Bool {
		dragController.blocksModelUpdates
	}

	func setAccessibilityAnnouncementHandlerForTesting(
		_ handler: @escaping @MainActor (String) -> Void
	) {
		configuration = ReorderableListConfiguration<Item, ID>(
			id: configuration.id,
			contentInsets: configuration.contentInsets,
			rowSpacing: configuration.rowSpacing,
			rowBackgroundColor: configuration.rowBackgroundColor,
			dragAppearance: configuration.dragAppearance,
			autoscroll: configuration.autoscroll,
			reorderHandleWidth: configuration.reorderHandleWidth,
			longPressDuration: configuration.longPressDuration,
			accessibilityAnnouncementsEnabled: configuration.accessibilityAnnouncementsEnabled,
			accessibilityAnnouncementHandler: handler,
			onMove: configuration.onMove,
			canMove: configuration.canMove,
			onMoveStart: configuration.onMoveStart,
			onMoveUpdate: configuration.onMoveUpdate,
			onMoveEnd: configuration.onMoveEnd,
			onReorderInteractionDidFinish: configuration.onReorderInteractionDidFinish,
			contentViewBuilder: configuration.contentViewBuilder,
			dragStartThreshold: configuration.dragStartThreshold,
			estimatedRowHeight: configuration.estimatedRowHeight,
			fixedRowHeight: configuration.fixedRowHeight
		)
	}

	func autoscrollIsActiveForTesting() -> Bool {
		dragRuntime.isAutoscrollActive
	}

	@discardableResult
	func handleAutoscrollTickForTesting() -> Bool {
		measurePerformanceInterval(.autoscrollTick) {
			measurePerformanceInterval(.dragUpdate) {
				dragRuntime.tickForTesting()
			}
		}
	}

	func scrollOffsetYForTesting() -> CGFloat {
		tableView.enclosingScrollView?.contentView.bounds.origin.y ?? 0
	}

	func attach(hostView: NSView, overlayHostView: NSView? = nil) {
		self.hostView = hostView
		let resolvedOverlayHostView = overlayHostView ?? hostView
		self.overlayHostView = resolvedOverlayHostView
		overlayCoordinator.attach(to: resolvedOverlayHostView)
	}

	func reload() {
		tableColumn.width = resolvedMeasurementWidth()
		tableView.reloadData()
		updateTableFrame()
		ensureVisibleRowsLoaded()
		syncSelectionIfNeeded()
		updateCellStates(animated: false)
	}

	func layoutDidChange() {
		let measurementWidth = resolvedMeasurementWidth()
		tableColumn.width = measurementWidth
		if configuration.fixedRowHeight == nil {
			invalidateMeasuredHeightsIfNeeded(for: measurementWidth)
		}
		updateTableFrame()
		ensureVisibleRowsLoaded()
		if dragController.isDragging || dragController.isSettling {
			_ = measurePerformanceInterval(.dragUpdate) {
				dragRuntime.tickForTestingWithoutAutoscroll()
			}
			dragRuntime.requestFrame()
		}
		updateDragPlaceholderIfNeeded()
		updateDropIndicatorIfNeeded()
	}

	func setItems(_ items: [Item]) {
		guard !dragController.blocksModelUpdates else {
			if let activeItemID = dragController.activeItemID,
			   items.contains(where: { $0[keyPath: configuration.id] == activeItemID }) == false {
				queuedItems = items
				finishDrag(cancelled: true)
				return
			}
			queuedItems = items
			return
		}

		invalidateDragPreviewCache()
		rows = mergedRows(from: items)
		displayOrder = modelOrder
		syncIndexCaches()
		if let selectedItemID,
		   rows.contains(where: { $0.id == selectedItemID }) == false {
			self.selectedItemID = nil
		}
		reload()
	}

	func appendItems(_ appendedItems: [Item]) {
		guard appendedItems.isEmpty == false else { return }
		guard !dragController.blocksModelUpdates else {
			queuedItems = rows.map(\.item) + appendedItems
			return
		}

		let startingCount = rows.count
		rows.append(contentsOf: appendedItems.map {
			ReorderableListRowModel(id: $0[keyPath: configuration.id], item: $0, measuredHeight: nil)
		})
		displayOrder = modelOrder
		syncIndexCaches()
		tableView.beginUpdates()
		tableView.insertRows(at: IndexSet(startingCount..<rows.count), withAnimation: [])
		tableView.endUpdates()
		updateTableFrame()
		syncSelectionIfNeeded()
	}

	func handleMouseDown(locationInSelf: CGPoint) -> Bool {
		guard !dragController.isSettling else { return false }

		switch dragEligibility(at: locationInSelf) {
		case let .row(itemID):
			hostView?.window?.makeFirstResponder(hostView)
			dragController.armPress(itemID: itemID, locationInView: locationInSelf)
			schedulePendingPressActivationIfNeeded()
			installEscapeMonitorIfNeeded()
			return true
		case .blockedByControl, .none:
			cancelPendingPressActivation(clearPendingPress: true)
			return false
		}
	}

	func handleMouseDragged(
		locationInSelf: CGPoint,
		locationInWindow: CGPoint? = nil
	) -> Bool {
		let resolvedLocationInWindow = if let locationInWindow {
			locationInWindow
		}
		else if let hostView, hostView.window != nil {
			hostView.convert(locationInSelf, to: nil)
		}
		else {
			locationInSelf
		}

		if dragController.isDragging {
			dragRuntime.updatePointerLocation(resolvedLocationInWindow)
			_ = dragRuntime.tickForTesting()
			dragRuntime.requestFrame()
			return true
		}

		if configuration.longPressDuration > 0, dragController.hasPendingPress {
			let armedLocation = dragController.armedLocationInView!
			let distance = hypot(
				locationInSelf.x - armedLocation.x,
				locationInSelf.y - armedLocation.y
			)
			guard distance <= configuration.dragStartThreshold else {
				cancelPendingPressActivation(clearPendingPress: true)
				return false
			}
			return true
		}

		guard dragController.beginDragIfArmed(at: locationInSelf, start: beginDrag) else {
			return dragController.hasPendingPress
		}

		cancelPendingPressActivation(clearPendingPress: false)
		updateCellStates(animated: false)
		if let session = dragController.activeSession {
			dragRuntime.begin(session: session)
		}
		dragRuntime.updatePointerLocation(resolvedLocationInWindow)
		_ = dragRuntime.tickForTesting()
		dragRuntime.requestFrame()
		return true
	}

	func handleMouseUp(locationInSelf: CGPoint? = nil) -> Bool {
		if endActiveDrag(at: locationInSelf) {
			return true
		}

		let hadPendingPress = dragController.hasPendingPress
		cancelPendingPressActivation(clearPendingPress: true)
		return hadPendingPress
	}

	func handleCancelOperation() -> Bool {
		if dragController.isDragging {
			finishDrag(cancelled: true)
			return true
		}
		return dragController.isSettling
	}

	func handleViewWillMove(toWindow newWindow: NSWindow?) {
		guard newWindow == nil else { return }
		removeCancellationObservers()
		cancelPendingPressActivation(clearPendingPress: true)
		if dragController.isDragging {
			finishDrag(cancelled: true, resetImmediately: true)
		}
		else {
			dragController.flushSettlement(onSettled: completeSettlement)
		}
	}

	private func schedulePendingPressActivationIfNeeded() {
		cancelPendingPressActivation(clearPendingPress: false)
		guard configuration.longPressDuration > 0 else { return }
		let workItem = DispatchWorkItem { [weak self] in
			reorderableListPerformOnMain {
				self?.activatePendingPressIfNeeded()
			}
		}
		pendingPressWorkItem = workItem
		DispatchQueue.main.asyncAfter(deadline: .now() + configuration.longPressDuration, execute: workItem)
	}

	private func cancelPendingPressActivation(clearPendingPress: Bool) {
		pendingPressWorkItem?.cancel()
		pendingPressWorkItem = nil
		if clearPendingPress {
			dragController.clearPendingPress()
		}
		if dragController.hasPendingPress == false, dragController.isDragging == false {
			removeEscapeMonitor()
		}
	}

	private func activatePendingPressIfNeeded() {
		pendingPressWorkItem = nil
		guard dragController.activateArmedPress(start: beginDrag) else { return }
		updateCellStates(animated: false)
		if let session = dragController.activeSession {
			dragRuntime.begin(session: session)
		}
		if let currentLocationInContent = resolvedCurrentDragLocationInContent() {
			let locationInWindow = pointerLocationInWindow(forContentLocation: currentLocationInContent)
			dragRuntime.updatePointerLocation(locationInWindow)
			_ = dragRuntime.tickForTesting()
			dragRuntime.requestFrame()
		}
	}

	func numberOfRows(in _: NSTableView) -> Int {
		rows.count
	}

	func tableView(_: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
		guard row >= 0, row < displayOrder.count,
		      let itemID = itemID(atDisplayRow: row),
		      let rowModel = rowModel(for: itemID) else {
			return nil
		}

		let contentView = configuration.contentViewBuilder(rowModel.item)
		let container = (tableView.makeView(
			withIdentifier: .reorderableListContainer,
			owner: self
		) as? ReorderableListItemContainerView) ?? ReorderableListItemContainerView(
			contentView: contentView,
			backgroundColor: configuration.rowBackgroundColor
		)

		container.layer?.backgroundColor = .clear

		container.identifier = .reorderableListContainer
		container.prepareForReuse(with: contentView)
		configure(container: container, itemID: itemID)
		applyCurrentCellState(to: container, itemID: itemID, animated: false)
		applyCurrentDisplacement(atRow: row, animated: false)
		if configuration.fixedRowHeight == nil {
			container.frame.size.width = resolvedMeasurementWidth()
			container.layoutSubtreeIfNeeded()
			updateMeasuredHeight(for: itemID, height: measuredHeight(for: container))
		}
		return container
	}

	func tableView(_: NSTableView, heightOfRow row: Int) -> CGFloat {
		if let fixedRowHeight = configuration.fixedRowHeight {
			return fixedRowHeight
		}
		guard row >= 0, row < displayOrder.count,
		      let itemID = itemID(atDisplayRow: row),
		      let rowModel = rowModel(for: itemID) else {
			return configuration.estimatedRowHeight
		}
		if let cachedHeight = rowModel.measuredHeight {
			return cachedHeight
		}

		let resolvedHeight = measureHeight(for: rowModel)
		updateMeasuredHeight(for: itemID, height: resolvedHeight)
		return resolvedHeight
	}

	func tableView(_: NSTableView, rowViewForRow _: Int) -> NSTableRowView? {
		ReorderableListRowView()
	}

	func beginDragForTesting(sourceIndex: Int, locationInContent: NSPoint) {
		cancelPendingPressActivation(clearPendingPress: false)
		guard let itemID = itemID(atModelIndex: sourceIndex) else { return }
		guard let session = beginDrag(itemID: itemID, locationInView: tableView.convert(locationInContent, to: hostView))
		else {
			return
		}
		dragRuntime.begin(session: session)
		let locationInWindow = pointerLocationInWindow(forContentLocation: locationInContent)
		dragRuntime.updatePointerLocation(locationInWindow)
		updateCellStates(animated: false)
	}

	func updateDragForTesting(locationInContent: NSPoint) {
		let locationInWindow = pointerLocationInWindow(forContentLocation: locationInContent)
		dragRuntime.updatePointerLocation(locationInWindow)
		_ = measurePerformanceInterval(.dragUpdate) {
			dragRuntime.tickForTestingWithoutAutoscroll()
		}
	}

	func endDragForTesting(cancelled: Bool, resetImmediately: Bool = false) {
		finishDrag(cancelled: cancelled, resetImmediately: resetImmediately)
	}

	func flushPendingDropResetForTesting() {
		dragController.flushSettlement(onSettled: completeSettlement)
	}

	func containerFrame(for index: Int) -> CGRect {
		guard let itemID = itemID(atModelIndex: index) else { return .zero }
		if dragController.activeItemID == itemID || dragController.settlingItemID == itemID,
		   let visualFrame = dragVisualFrameInTableCoordinates() {
			return visualFrame
		}
		let row = row(for: itemID)!
		return tableView.rect(ofRow: row)
	}

	func dragPresentationFrameForTesting(modelIndex: Int) -> CGRect? {
		guard let itemID = itemID(atModelIndex: modelIndex),
		      dragController.activeItemID == itemID || dragController.settlingItemID == itemID,
		      let overlayHostView,
		      let frameInHost = dragVisualController.presentationFrameInHost else {
			return nil
		}
		return tableView.convert(frameInHost, from: overlayHostView)
	}

	func documentHeight() -> CGFloat {
		tableView.enclosingScrollView?.documentView?.frame.height ?? tableView.frame.height
	}

	func currentVisualOrder() -> [Int] {
		resolvedVisualOrder().compactMap(modelIndex(for:))
	}

	func dropIndicatorFrameForTesting() -> CGRect? {
		guard dropIndicatorLayer.isHidden == false else { return nil }
		return dropIndicatorLayer.frame
	}

	func dropIndicatorColorForTesting() -> NSColor? {
		guard
			dropIndicatorLayer.isHidden == false,
			let backgroundColor = dropIndicatorLayer.backgroundColor
		else {
			return nil
		}
		return NSColor(cgColor: backgroundColor)
	}

	func dragPlaceholderFrameForTesting() -> CGRect? {
		guard dragPlaceholderView.isHidden == false else { return nil }
		return dragPlaceholderView.frame
	}

	func dragPlaceholderViewForTesting() -> ReorderableListDragPlaceholderView? {
		dragPlaceholderView.isHidden ? nil : dragPlaceholderView
	}

	func isReordering() -> Bool {
		dragController.isDragging
	}

	func hasPendingPressForTesting() -> Bool {
		dragController.hasPendingPress
			|| testingPendingPressIndex != nil
			|| testingPendingPressLocationInSelf != nil
	}

	func installPendingPressForTesting(sourceIndex: Int?, locationInSelf: NSPoint?) {
		testingPendingPressIndex = sourceIndex
		testingPendingPressLocationInSelf = locationInSelf
	}

	func armPendingPressForTesting(sourceIndex: Int, locationInView: NSPoint) {
		guard let itemID = itemID(atModelIndex: sourceIndex) else { return }
		dragController.armPress(itemID: itemID, locationInView: locationInView)
	}

	func invalidateMeasuredHeightsForTesting(width: CGFloat) {
		invalidateMeasuredHeightsIfNeeded(for: width)
	}

	func beginPendingDragForTesting(locationInSelf: NSPoint? = nil) {
		defer {
			testingPendingPressIndex = nil
			testingPendingPressLocationInSelf = nil
		}

		if dragController.isDragging {
			return
		}

		guard let sourceIndex = testingPendingPressIndex,
		      let itemID = itemID(atModelIndex: sourceIndex),
		      let pendingLocation = testingPendingPressLocationInSelf else {
			return
		}

		let resolvedLocation = locationInSelf ?? pendingLocation
		cancelPendingPressActivation(clearPendingPress: false)
		guard shouldBeginContainerDrag(at: pendingLocation) else {
			return
		}
		guard let session = beginDrag(itemID: itemID, locationInView: resolvedLocation) else {
			return
		}
		dragController.updateSession(session)
		dragRuntime.begin(session: session)
		updateCellStates(animated: false)
	}

	func activatePendingPressForTesting() {
		activatePendingPressIfNeeded()
	}

	func installEscapeMonitorForTesting() {
		installEscapeMonitorIfNeeded()
	}

	func clearDragPlaceholderForTesting() {
		dragPlaceholderFrame = nil
		placeholderCoordinator.hide()
	}

	func removeDisplayRowCacheEntryForTesting(itemID: ID) {
		displayRowByID[itemID] = nil
	}

	func syncDisplayRowCacheForTesting() {
		syncDisplayRowIndexCache()
	}

	func indexOfContainerForTesting(at locationInSelf: NSPoint) -> Int? {
		guard let itemID = itemIDForPoint(locationInSelf) else { return nil }
		return modelIndex(for: itemID)
	}

	func shouldBeginContainerDragForTesting(from hitView: NSView?) -> Bool {
		guard let hitView else { return shouldBeginContainerDrag(from: nil) }
		if hitView is NSControl {
			return false
		}
		if representedItemID(for: hitView) != nil {
			return true
		}
		return shouldBeginContainerDrag(from: hitView)
	}

	func sourceIndexForTesting(for view: NSView) -> Int? {
		guard let itemID = representedItemID(for: view) else { return nil }
		return modelIndex(for: itemID)
	}

	func containerViewForTesting(row: Int) -> ReorderableListItemContainerView? {
		guard row >= 0, row < rows.count else { return nil }
		return tableView.view(atColumn: 0, row: row, makeIfNecessary: true) as? ReorderableListItemContainerView
	}

	func rowViewForTesting(modelIndex: Int) -> ReorderableListRowView? {
		guard let itemID = itemID(atModelIndex: modelIndex) else { return nil }
		return rowView(for: itemID, makeIfNecessary: true)
	}

	func rowSettleAnimationDurationForTesting(modelIndex: Int) -> TimeInterval? {
		guard let itemID = itemID(atModelIndex: modelIndex),
		      dragController.activeItemID == itemID || dragController.settlingItemID == itemID else {
			return nil
		}
		return dragVisualController.settleDuration
	}

	func cachedIndicesForTesting(itemID: ID) -> (modelIndex: Int?, displayRow: Int?) {
		(
			modelIndex: modelIndexByID[itemID],
			displayRow: displayRowByID[itemID]
		)
	}

	func visibleRowRangeForTesting() -> Range<Int>? {
		visibleRowRange()
	}

	func itemIDForTesting(displayRow: Int) -> ID? {
		itemID(atDisplayRow: displayRow)
	}

	func hasRowModelForTesting(itemID: ID) -> Bool {
		rowModel(for: itemID) != nil
	}

	func ensureAutoscrolledRowsLoadedForTesting(previousVisibleRows: Range<Int>?) {
		ensureAutoscrolledRowsLoaded(previousVisibleRows: previousVisibleRows)
	}

	func tableRow(forItemID itemID: ID) -> Int? {
		row(for: itemID)
	}

	func ensureVisibleRowsLoadedForTesting(in rows: Range<Int>) {
		ensureVisibleRowsLoaded(in: rows, reason: .initial)
	}

	func resolvedDestinationIndexForTesting(targetCenterY: CGFloat, sourceIndex: Int) -> Int {
		resolvedDestinationIndex(for: targetCenterY, sourceIndex: sourceIndex)
	}

	func resolvedAutoscrollDeltaForTesting(pointerYInClipView: CGFloat) -> CGFloat? {
		dragRuntime.resolvedAutoscrollDelta(pointerYInClipView: pointerYInClipView)
	}

	func positionDraggedRowForTesting(itemID: ID, locationInContent: CGPoint) {
		let locationInWindow = pointerLocationInWindow(forContentLocation: locationInContent)
		dragRuntime.updatePointerLocation(locationInWindow)
		_ = measurePerformanceInterval(.dragUpdate) {
			dragRuntime.tickForTestingWithoutAutoscroll()
		}
	}

	func setLastKnownDragLocationInContentForTesting(_ location: CGPoint?) {
		if let location {
			dragRuntime.updatePointerLocation(pointerLocationInWindow(forContentLocation: location))
		}
		else {
			dragRuntime.clearPointerLocation()
		}
	}

	func endSettlePerformanceIntervalForTesting() {
		endSettlePerformanceIntervalIfNeeded()
	}

	func beginSettlePerformanceIntervalForTesting() {
		beginSettlePerformanceIntervalIfNeeded()
	}

	func handleCancellationNotificationForTesting() {
		handleCancellationNotification()
	}

	func dragVisualFrameInTableCoordinatesForTesting() -> CGRect? {
		dragVisualFrameInTableCoordinates()
	}

	func detachOverlayHostForTesting() {
		overlayHostView = nil
		overlayCoordinator.attach(to: tableView)
	}

	private var enclosingContentSize: CGSize {
		tableView.enclosingScrollView?.contentSize ?? .zero
	}

	private func resolvedMeasurementWidth() -> CGFloat {
		max(enclosingContentSize.width, 1)
	}

	private func pointerLocationInWindow(forContentLocation locationInContent: CGPoint) -> CGPoint {
		guard let hostView else { return locationInContent }
		let hostLocation = hostView.convert(locationInContent, from: tableView)
		guard hostView.window != nil else { return hostLocation }
		return hostView.convert(hostLocation, to: nil)
	}

	private func mergedRows(from items: [Item]) -> [ReorderableListRowModel<Item, ID>] {
		let existingHeights = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.measuredHeight) })
		return items.map {
			ReorderableListRowModel(
				id: $0[keyPath: configuration.id],
				item: $0,
				measuredHeight: existingHeights[$0[keyPath: configuration.id]] ?? nil
			)
		}
	}

	private func updateTableFrame() {
		let topInset = configuration.contentInsets.top + clearTableHeaderHeight
		let bottomInset = configuration.contentInsets.bottom + clearTableFooterHeight
		let availableTableHeight = max(enclosingContentSize.height - topInset - bottomInset, 0)
		let tableHeight = max(resolvedContentHeight(), availableTableHeight)
		let documentHeight = max(tableHeight + topInset + bottomInset, enclosingContentSize.height)
		let documentWidth = max(enclosingContentSize.width, 1)

		tableView.enclosingScrollView?.documentView?.frame = CGRect(
			x: 0,
			y: 0,
			width: documentWidth,
			height: documentHeight
		)
		tableView.frame = CGRect(
			x: 0,
			y: topInset,
			width: documentWidth,
			height: tableHeight
		)
	}

	private func resolvedContentHeight() -> CGFloat {
		ReorderableListGeometry.contentHeight(
			itemHeights: rowHeights(),
			rowSpacing: configuration.rowSpacing,
			contentInsets: NSEdgeInsetsZero
		)
	}

	private func rowHeights() -> [CGFloat] {
		if let fixedRowHeight = configuration.fixedRowHeight {
			return Array(repeating: fixedRowHeight, count: rows.count)
		}
		return rows.map { $0.measuredHeight ?? configuration.estimatedRowHeight }
	}

	private func updateMeasuredHeight(for itemID: ID, height: CGFloat) {
		rows[modelIndex(for: itemID)!].measuredHeight = height
	}

	private func invalidateMeasuredHeightsIfNeeded(for width: CGFloat) {
		guard abs(measuredRowWidth - width) > .ulpOfOne else { return }
		measuredRowWidth = width
		guard rows.isEmpty == false else { return }
		for index in rows.indices {
			rows[index].measuredHeight = nil
		}
		tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<rows.count))
	}

	private func measureHeight(for rowModel: ReorderableListRowModel<Item, ID>) -> CGFloat {
		let contentView = configuration.contentViewBuilder(rowModel.item)
		let container = ReorderableListItemContainerView(
			contentView: contentView,
			backgroundColor: configuration.rowBackgroundColor
		)
		container.frame = CGRect(
			x: 0,
			y: 0,
			width: resolvedMeasurementWidth(),
			height: configuration.estimatedRowHeight
		)
		container.layoutSubtreeIfNeeded()
		return measuredHeight(for: container)
	}

	private func measuredHeight(for container: ReorderableListItemContainerView) -> CGFloat {
		let widthConstraint = container.widthAnchor.constraint(equalToConstant: resolvedMeasurementWidth())
		widthConstraint.isActive = true
		defer { widthConstraint.isActive = false }
		container.layoutSubtreeIfNeeded()
		return max(
			container.fittingSize.height,
			container.contentView.fittingSize.height,
			container.intrinsicContentSize.height,
			configuration.estimatedRowHeight
		)
	}

	private func itemID(atModelIndex index: Int) -> ID? {
		guard index >= 0, index < rows.count else { return nil }
		return rows[index].id
	}

	private func itemID(atDisplayRow row: Int) -> ID? {
		guard row >= 0, row < displayOrder.count else { return nil }
		return displayOrder[row]
	}

	private func modelIndex(for itemID: ID) -> Int? {
		modelIndexByID[itemID]
	}

	private func row(for itemID: ID) -> Int? {
		displayRowByID[itemID]
	}

	private func rowModel(for itemID: ID) -> ReorderableListRowModel<Item, ID>? {
		guard let modelIndex = modelIndex(for: itemID) else { return nil }
		return rows[modelIndex]
	}

	private func applyCurrentCellState(
		to container: ReorderableListItemContainerView,
		itemID: ID,
		animated: Bool
	) {
		let isDraggedRow = dragController.activeSession?.itemID == itemID
		let keepsLiftedZPosition = dragController.settlingItemID == itemID
		container.apply(
			cellState: ReorderableListCellState(
				isReordering: isDraggedRow,
				isListReordering: dragController.blocksModelUpdates,
				isHighlighted: false,
				isSelected: false
			),
			animated: animated
		)
		container.layer?.zPosition = 0
		let resolvedRowView = rowView(for: itemID, makeIfNecessary: false)
		resolvedRowView?.layer?.zPosition = isDraggedRow || keepsLiftedZPosition ? 10 : 0
		if isDraggedRow {
			resolvedRowView?.alphaValue = 0
		}
	}

	private func applyCurrentDisplacement(atRow row: Int, animated: Bool) {
		let offset: CGFloat
		if let external = externalDragDisplacement {
			offset = ReorderableListGeometry.externalInsertionDisplacementForRow(
				rowIndex: row,
				insertionIndex: external.insertionIndex,
				rowHeight: external.rowHeight
			)
		} else {
			offset = currentDragDisplacement.map {
				ReorderableListGeometry.displacementOffsetForRow(
					rowIndex: row,
					sourceIndex: $0.sourceIndex,
					insertionIndex: $0.insertionIndex,
					rowHeight: $0.rowHeight
				)
			} ?? 0
		}
		guard let rowView = tableView.rowView(atRow: row, makeIfNecessary: false) else { return }
		applyRowDisplacementTransform(offset, to: rowView, animated: animated)
	}

	private func applyRowDisplacementTransform(
		_ offset: CGFloat,
		to rowView: NSTableRowView,
		animated: Bool
	) {
		let targetTransform = offset == 0
			? CATransform3DIdentity
			: CATransform3DMakeTranslation(0, offset, 0)

		if animated {
			let currentTransform = rowView.layer?.presentation()?.transform
				?? rowView.layer?.transform
				?? CATransform3DIdentity
			let animation = CASpringAnimation(keyPath: "transform")
			animation.fromValue = NSValue(caTransform3D: currentTransform)
			animation.toValue = NSValue(caTransform3D: targetTransform)
			animation.mass = 1.0
			animation.stiffness = 600
			animation.damping = 36
			animation.duration = min(animation.settlingDuration, 0.5)
			animation.isRemovedOnCompletion = true
			rowView.layer?.transform = targetTransform
			rowView.layer?.add(animation, forKey: "rowDisplacement")
		}
		else {
			rowView.layer?.removeAnimation(forKey: "rowDisplacement")
			rowView.layer?.transform = targetTransform
		}
	}

	private func updateCellStates(animated: Bool) {
		tableView.enumerateAvailableRowViews { [weak self] _, row in
			if let self,
			   let container = self.tableView.view(
			   	atColumn: 0,
			   	row: row,
			   	makeIfNecessary: false
			   ) as? ReorderableListItemContainerView,
			   let itemID = self.itemID(atDisplayRow: row) {
				self.applyCurrentCellState(to: container, itemID: itemID, animated: animated)
			}
		}
	}

	private func updateVisibleRowDisplacements(animated: Bool) {
		guard let visibleRows = visibleRowRange() else { return }
		// Extend one row past the visible range so rows that shift into view via
		// displacement transforms also get their transforms applied.
		let extendedEnd = min(visibleRows.upperBound + 1, rows.count)
		for row in visibleRows.lowerBound..<extendedEnd where row >= 0 {
			if row >= visibleRows.upperBound {
				ensureVisibleRowsLoaded(in: row..<(row + 1), reason: .initial)
			}
			applyCurrentDisplacement(atRow: row, animated: animated)
		}
	}

	private func configureDropIndicatorLayer() {
		dropIndicatorLayer.isHidden = true
		dropIndicatorLayer.cornerRadius = ReorderableListStyle.dropIndicatorHeight / 2
		tableView.layer?.addSublayer(dropIndicatorLayer)
	}

	private func configureDragPlaceholderView() {
		dragPlaceholderView.translatesAutoresizingMaskIntoConstraints = true
		dragPlaceholderView.wantsLayer = true
		dragPlaceholderView.layer?.zPosition = 5
		tableView.addSubview(dragPlaceholderView)
	}

	private func resolvedDragPlaceholderFrame(from frame: CGRect) -> CGRect {
		CGRect(
			x: frame.origin.x + ReorderableListStyle.dragPlaceholderHorizontalInset,
			y: frame.origin.y,
			width: max(
				0,
				tableView.bounds.width - (ReorderableListStyle.dragPlaceholderHorizontalInset * 2)
			),
			height: frame.height
		)
	}

	private func configure(container: ReorderableListItemContainerView, itemID: ID) {
		container.representedItemID = itemID
		container.eventForwardingView = hostView
		container.nextResponder = hostView
	}

	private func dragEligibility(at locationInSelf: CGPoint) -> DragEligibility<ID> {
		guard let hit = containerHit(at: locationInSelf) else { return .none }
		let eligibility: DragEligibility<ID> = hit.hitView is NSControl ? .blockedByControl : .row(hit.itemID)
		guard case .row = eligibility else { return eligibility }
		guard let handleRect = resolvedHandleRect(for: hit.container) else { return eligibility }
		return handleRect.contains(hit.pointInContainer) ? eligibility : .none
	}

	private func itemIDForPoint(_ locationInSelf: CGPoint) -> ID? {
		let locationInTable = tableView.convert(locationInSelf, from: hostView)
		for row in displayOrder.indices.reversed() {
			if tableView.rect(ofRow: row).contains(locationInTable) {
				return displayOrder[row]
			}
		}
		return nil
	}

	private func resolvedHandleRect(
		for container: ReorderableListItemContainerView
	) -> CGRect? {
		if let handleRect = (container.contentView as? any ReorderableListHandleProviding)?.reorderHandleRect {
			return handleRect
		}
		guard let reorderHandleWidth = configuration.reorderHandleWidth,
		      reorderHandleWidth > 0 else {
			return nil
		}
		return CGRect(
			x: max(container.bounds.width - reorderHandleWidth, 0),
			y: 0,
			width: min(reorderHandleWidth, container.bounds.width),
			height: container.bounds.height
		)
	}

	private func containerHit(
		at locationInSelf: CGPoint
	) -> (
		container: ReorderableListItemContainerView,
		itemID: ID,
		hitView: NSView,
		pointInContainer: CGPoint
	)? {
		let locationInTable = tableView.convert(locationInSelf, from: hostView)
		let row = tableView.row(at: locationInTable)
		guard row >= 0,
		      let itemID = itemID(atDisplayRow: row),
		      let container = tableView.view(
		      	atColumn: 0,
		      	row: row,
		      	makeIfNecessary: true
		      ) as? ReorderableListItemContainerView else {
			return nil
		}

		let pointInContainer = container.convert(locationInTable, from: tableView)
		return (container, itemID, container.hitTest(pointInContainer) ?? container, pointInContainer)
	}

	private func representedItemID(for view: NSView?) -> ID? {
		var currentView = view
		while let resolvedView = currentView {
			if let containerView = resolvedView as? ReorderableListItemContainerView,
			   let itemID = containerView.representedItemID as? ID {
				return itemID
			}
			currentView = resolvedView.superview
		}
		return nil
	}

	private func shouldBeginContainerDrag(at locationInSelf: CGPoint) -> Bool {
		guard let hit = containerHit(at: locationInSelf) else { return true }
		if let handleRect = resolvedHandleRect(for: hit.container),
		   handleRect.contains(hit.pointInContainer) == false {
			return false
		}
		return shouldBeginContainerDrag(from: hit.hitView, fallbackItemID: hit.itemID)
	}

	private func shouldBeginContainerDrag(from hitView: NSView?, fallbackItemID: ID? = nil) -> Bool {
		if hitView is NSControl {
			return false
		}
		if hitView is ReorderableListItemContainerView || representedItemID(for: hitView) != nil {
			return true
		}
		return fallbackItemID != nil || hitView == nil
	}

	private func beginDrag(itemID: ID, locationInView: CGPoint) -> DragSession<ID>? {
		guard !dragController.isDragging,
		      !dragController.isSettling,
		      let hostView,
		      let overlayHostView,
		      let initialIndex = modelIndex(for: itemID),
		      let currentRow = row(for: itemID),
		      let rowModel = rowModel(for: itemID) else {
			return nil
		}
		guard configuration.canMove?(rowModel.item) ?? true else { return nil }
		return measurePerformanceInterval(.dragLift) {
			guard let rowView = rowView(for: itemID, makeIfNecessary: true),
			      let snapshotImage = dragPreviewImage(for: itemID, rowView: rowView) else {
				return nil
			}

			let locationInContent = tableView.convert(locationInView, from: hostView)
			let hostLocation = hostView.convert(locationInContent, from: tableView)
			let locationInWindow = if hostView.window != nil {
				hostView.convert(hostLocation, to: nil)
			}
			else {
				hostLocation
			}
			dragRuntime.updatePointerLocation(locationInWindow)
			let restingFrame = tableView.rect(ofRow: currentRow)
			let destinationThresholdLayout: ReorderableListDestinationThresholdLayout? = if configuration.fixedRowHeight == nil {
				geometryEngine.thresholdLayoutForVariable(
					sourceIndex: initialIndex,
					itemHeights: rowHeights(),
					rowSpacing: configuration.rowSpacing,
					contentInsets: NSEdgeInsetsZero
				)
			}
			else {
				nil
			}
			let session = DragSession(
				itemID: itemID,
				initialIndex: initialIndex,
				proposedIndex: initialIndex,
				pointerOffset: CGPoint(
					x: restingFrame.midX - locationInContent.x,
					y: restingFrame.midY - locationInContent.y
				),
				pointerOffsetFromRowCenter: CGPoint(
					x: restingFrame.midX - locationInContent.x,
					y: restingFrame.midY - locationInContent.y
				),
				destinationThresholdLayout: destinationThresholdLayout,
				fixedRowHeight: configuration.fixedRowHeight
			)
			dragPlaceholderFrame = restingFrame
			placeholderCoordinator.show(frame: resolvedDragPlaceholderFrame(from: restingFrame))
			let chromeGeometry = resolvedDragChromeGeometry(for: itemID, rowView: rowView)
			overlayCoordinator.beginLift(
				snapshotImage: snapshotImage,
				frame: overlayHostView.convert(restingFrame, from: tableView),
				backgroundColor: ReorderableListStyle.resolvedColor(
					dragBackgroundColor ?? configuration.rowBackgroundColor,
					for: tableView.effectiveAppearance
				),
				appearance: configuration.dragAppearance,
				chromeGeometry: chromeGeometry
			)
			hideLiveRow(for: itemID)
			hostView.window?.makeFirstResponder(hostView)
			installCancellationObservers()
			announcementCoordinator.announceReorderStart(
				totalCount: rows.count,
				initialIndex: initialIndex
			)
			configuration.onMoveStart?(itemID, initialIndex)
			dragObserver(for: itemID)?.reorderableListItemDidBeginDrag()
			return session
		}
	}

	private func didTick(with output: ReorderableListDragRuntimeTickOutput<ID>) {
		let session = output.session
		let usedFixedHeightIndexing = output.usedFixedHeightIndexing
		if usedFixedHeightIndexing {
			currentPerformanceMetrics.fixedHeightDestinationIndexEvaluations += 1
		}
		else {
			currentPerformanceMetrics.variableHeightDestinationIndexEvaluations += 1
		}

		if output.didDestinationChange {
			currentPerformanceMetrics.insertionIndexChanges += 1
			announcementCoordinator.announceReorderDestination(
				sourceIndex: session.initialIndex,
				insertionIndex: output.destinationIndex,
				rows: rows.count
			)
			configuration.onMoveUpdate?(session.initialIndex, output.destinationIndex)

			if !isDragAboveListThreshold {
				let sourceRowHeight = configuration.fixedRowHeight
					?? tableView.rect(ofRow: session.initialIndex).height
				currentDragDisplacement = (
					sourceIndex: session.initialIndex,
					insertionIndex: output.destinationIndex,
					rowHeight: sourceRowHeight
				)
				updateVisibleRowDisplacements(animated: !output.didAutoscroll)
			}
		}

		// Show dashed placeholder at the destination slot instead of a drop indicator bar.
		// Hide when the drag is above the list threshold (cross-threshold into pinned area).
		if isDragAboveListThreshold {
			hideDragPlaceholder()
		} else {
			let placeholderRow: Int = {
				let s = session.initialIndex
				let d = output.destinationIndex
				if d > s { return d - 1 }
				if d < s { return d }
				return s
			}()
			let placeholderFrame = tableView.rect(ofRow: placeholderRow)
			dragPlaceholderFrame = placeholderFrame
			placeholderCoordinator.show(frame: resolvedDragPlaceholderFrame(from: placeholderFrame))
		}

		// Store the resting (non-rubber-banded) column center X every tick.
		lastDraggedFrameMidX = output.restingFrameInHost.midX

		// Cursor-centering only applies while actively above threshold.
		let shouldCenterOnCursor = isDragAboveListThreshold
		var frameForOverlay = output.draggedFrameInHost
		if shouldCenterOnCursor,
		   let overlayHostView {
			let cursorInWindow = tableView.convert(output.pointerLocationInTable, to: nil)
			let cursorInHost = overlayHostView.convert(cursorInWindow, from: nil)
			frameForOverlay.origin.x = cursorInHost.x - frameForOverlay.size.width / 2
		}
		let updateKind = overlayCoordinator.move(frameForOverlay)
		switch updateKind {
		case .none:
			break
		case .positionOnly:
			currentPerformanceMetrics.overlayUpdates += 1
			currentPerformanceMetrics.overlayPositionOnlyUpdates += 1
		case .boundsChanged:
			currentPerformanceMetrics.overlayUpdates += 1
			currentPerformanceMetrics.overlayBoundsUpdates += 1
		}
	}

	private func resolvedCurrentDragLocationInContent() -> CGPoint? {
		guard let hostView,
		      let hostWindow = hostView.window else { return nil }
		let windowPoint = hostWindow.mouseLocationOutsideOfEventStream
		let hostPoint = hostView.convert(windowPoint, from: nil)
		return tableView.convert(hostPoint, from: hostView)
	}

	private func attemptScrollBy(_ delta: CGFloat) -> Bool {
		guard let clipView = tableView.enclosingScrollView?.contentView,
		      let documentView = clipView.documentView else { return false }
		let maximumOffsetY = max(0, documentView.frame.height - clipView.bounds.height)
		let currentOffsetY = clipView.bounds.origin.y
		let nextOffsetY = min(max(currentOffsetY + delta, 0), maximumOffsetY)
		guard abs(nextOffsetY - currentOffsetY) > .ulpOfOne else { return false }
		let previousVisibleRows = visibleRowRange()
		clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: nextOffsetY))
		tableView.enclosingScrollView?.reflectScrolledClipView(clipView)
		ensureAutoscrolledRowsLoaded(previousVisibleRows: previousVisibleRows)
		currentPerformanceMetrics.autoscrollTicks += 1
		return true
	}

	private func installCancellationObservers() {
		installEscapeMonitorIfNeeded()
		dragMouseUpMonitor = eventMonitoring.addLocalLeftMouseUpMonitor { [weak self] event in
			guard let self else { return event }
			return self.handleDragMouseUpMonitorEvent(event)
		}
		dragMouseDraggedMonitor = eventMonitoring.addLocalLeftMouseDraggedMonitor { [weak self] event in
			guard let self else { return event }
			return self.handleDragMouseDraggedMonitorEvent(event)
		}
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(handleWindowResignKeyNotification(_:)),
			name: NSWindow.didResignKeyNotification,
			object: hostView?.window
		)
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(handleApplicationResignActiveNotification(_:)),
			name: NSApplication.didResignActiveNotification,
			object: NSApp
		)
		observesWindowResignKey = true
		observesApplicationResignActive = true
	}

	private func removeCancellationObservers() {
		removeEscapeMonitor()
		if let dragMouseUpMonitor {
			eventMonitoring.removeMonitor(dragMouseUpMonitor)
			self.dragMouseUpMonitor = nil
		}
		if let dragMouseDraggedMonitor {
			eventMonitoring.removeMonitor(dragMouseDraggedMonitor)
			self.dragMouseDraggedMonitor = nil
		}
		if observesWindowResignKey {
			NotificationCenter.default.removeObserver(
				self,
				name: NSWindow.didResignKeyNotification,
				object: hostView?.window
			)
			observesWindowResignKey = false
		}
		if observesApplicationResignActive {
			NotificationCenter.default.removeObserver(
				self,
				name: NSApplication.didResignActiveNotification,
				object: NSApp
			)
			observesApplicationResignActive = false
		}
	}

	@objc
	private func handleWindowResignKeyNotification(_: Notification) {
		handleCancellationNotification()
	}

	@objc
	private func handleApplicationResignActiveNotification(_: Notification) {
		handleCancellationNotification()
	}

	private func handleCancellationNotification() {
		guard dragController.isDragging else { return }
		finishDrag(cancelled: true, resetImmediately: true)
	}

	private func handleEscapeKeyDown() -> Bool {
		if dragController.isDragging {
			finishDrag(cancelled: true)
			return true
		}
		if dragController.hasPendingPress {
			cancelPendingPressActivation(clearPendingPress: true)
			return true
		}
		return false
	}

	private func installEscapeMonitorIfNeeded() {
		guard dragEscapeMonitor == nil else { return }
		dragEscapeMonitor = eventMonitoring.addLocalKeyDownMonitor { [weak self] event in
			guard let self else { return event }
			return self.handleEscapeMonitorEvent(event)
		}
	}

	private func removeEscapeMonitor() {
		if let dragEscapeMonitor {
			eventMonitoring.removeMonitor(dragEscapeMonitor)
			self.dragEscapeMonitor = nil
		}
	}

	private func handleEscapeMonitorEvent(_ event: NSEvent) -> NSEvent? {
		guard isPlainEscapeKeyEvent(event) else {
			return event
		}
		return handleEscapeKeyDown() ? nil : event
	}

	private func handleDragMouseUpMonitorEvent(_ event: NSEvent) -> NSEvent? {
		guard dragController.isDragging else { return event }

		let locationInWindow = event.locationInWindow
		let locationInSelf: CGPoint? = {
			guard let hostView else { return locationInWindow }
			guard hostView.window != nil else { return locationInWindow }
			return hostView.convert(locationInWindow, from: nil)
		}()

		_ = endActiveDrag(at: locationInSelf)
		return nil
	}

	private func handleDragMouseDraggedMonitorEvent(_ event: NSEvent) -> NSEvent? {
		guard dragController.isDragging else { return event }

		dragRuntime.updatePointerLocation(event.locationInWindow)
		_ = dragRuntime.tickForTesting()
		dragRuntime.requestFrame()
		updateDragAboveListThreshold(windowLocation: event.locationInWindow)
		if isDragAboveListThreshold {
			onDragAboveListPositionUpdate?(event.locationInWindow)
		}
		return nil
	}

	private func updateDragAboveListThreshold(windowLocation: CGPoint) {
		guard let hostView else { return }
		let locationInSelf = hostView.convert(windowLocation, from: nil)
		let aboveThreshold = isDragAboveView(location: locationInSelf, in: hostView)
		guard aboveThreshold != isDragAboveListThreshold else { return }
		isDragAboveListThreshold = aboveThreshold
		if aboveThreshold, let session = dragController.activeSession {
			hideDragPlaceholder()
			// Collapse: use insertionIndex past the end so all rows after source shift up.
			let sourceRowHeight = configuration.fixedRowHeight
				?? tableView.rect(ofRow: session.initialIndex).height
			currentDragDisplacement = (
				sourceIndex: session.initialIndex,
				insertionIndex: rows.count,
				rowHeight: sourceRowHeight
			)
			updateVisibleRowDisplacements(animated: true)
		} else if let session = dragController.activeSession {
			// Restore displacement for the current destination.
			let sourceRowHeight = configuration.fixedRowHeight
				?? tableView.rect(ofRow: session.initialIndex).height
			currentDragDisplacement = (
				sourceIndex: session.initialIndex,
				insertionIndex: session.proposedIndex,
				rowHeight: sourceRowHeight
			)
			updateVisibleRowDisplacements(animated: true)
		}
		guard case .dragging(let session) = dragRuntime.phase else { return }
		onDragAboveListThresholdChanged?(aboveThreshold, session.itemID)
	}

	private func isPlainEscapeKeyEvent(_ event: NSEvent) -> Bool {
		let relevantModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
		return relevantModifiers.isEmpty && event.keyCode == reorderableListEscapeKeyCode
	}

	private func resolvedVisualOrder() -> [ID] {
		guard let session = dragController.activeSession else { return displayOrder }
		return ReorderableListGeometry.reorderedValues(
			modelOrder,
			moving: session.initialIndex,
			to: session.proposedIndex
		)
	}

	private func updateDropIndicatorIfNeeded() {
		hideDropIndicator()
	}

	private func updateDragPlaceholderIfNeeded() {
		let shouldShowPlaceholder = switch dragController.state {
		case .dragging, .settling:
			true
		case .idle, .pressArmed:
			false
		}

		guard let frame = dragPlaceholderFrame,
		      shouldShowPlaceholder else {
			hideDragPlaceholder()
			return
		}

		let resolvedFrame = resolvedDragPlaceholderFrame(from: frame)
		dragPlaceholderFrame = resolvedFrame
		placeholderCoordinator.show(frame: resolvedFrame)
	}

	private func updateDropIndicator(for destinationIndex: Int) {
		let yPosition: CGFloat = if destinationIndex <= 0 {
			tableView.rect(ofRow: 0).minY
		}
		else if destinationIndex >= rows.count {
			tableView.rect(ofRow: rows.count - 1).maxY
		}
		else {
			tableView.rect(ofRow: destinationIndex).minY
		}

		let resolvedColor = ReorderableListStyle.resolvedColor(
			ReorderableListStyle.dragPlaceholderStrokeColor,
			for: tableView.effectiveAppearance
		)
		dropIndicatorLayer.backgroundColor = resolvedColor.cgColor
		dropIndicatorLayer.frame = CGRect(
			x: ReorderableListStyle.dropIndicatorHorizontalInset,
			y: yPosition - (ReorderableListStyle.dropIndicatorHeight / 2),
			width: max(
				0,
				tableView.bounds.width - (ReorderableListStyle.dropIndicatorHorizontalInset * 2)
			),
			height: ReorderableListStyle.dropIndicatorHeight
		)
		dropIndicatorLayer.isHidden = false
	}

	private func hideDropIndicator() {
		guard dropIndicatorLayer.isHidden == false else { return }
		dropIndicatorLayer.isHidden = true
	}

	private func hideDragPlaceholder() {
		dragPlaceholderFrame = nil
		placeholderCoordinator.hide()
	}

	private func endActiveDrag(at locationInSelf: CGPoint?) -> Bool {
		guard dragController.isDragging else { return false }
		if let location = locationInSelf,
		   let hostView,
		   isDragAboveView(location: location, in: hostView),
		   let activeItemID = dragController.activeItemID,
		   let handler = onDropAboveList {
			let settleTarget = onSettleTargetForDropAboveList?(activeItemID)
			finishDragAboveList(
				itemID: activeItemID,
				settleTarget: settleTarget,
				onComplete: handler
			)
			return true
		}
		finishDrag(cancelled: false, finalLocationInSelf: locationInSelf)
		return true
	}

	private func isDragAboveView(location: CGPoint, in view: NSView) -> Bool {
		view.isFlipped ? location.y < 0 : location.y > view.bounds.height
	}

	private func moveDraggedRowToRestingFrame(
		itemID: ID,
		to restingFrame: CGRect,
		commit: Bool,
		animated: Bool
	) {
		beginSettlePerformanceIntervalIfNeeded()
		stopRowSettleAnimation()
		hideLiveRow(for: itemID)
		guard let overlayHostView else {
			revealLiveRow(for: itemID)
			return
		}
		dragVisualController.beginSettle(
			to: overlayHostView.convert(restingFrame, from: tableView),
			commit: commit,
			backgroundColor: ReorderableListStyle.resolvedColor(
				dragBackgroundColor ?? configuration.rowBackgroundColor,
				for: tableView.effectiveAppearance
			),
			appearance: configuration.dragAppearance,
			animated: animated,
			durationOverride: ReorderableListStyle.animationDuration
		)
	}

	private func finishDrag(
		cancelled: Bool,
		resetImmediately: Bool = false,
		finalLocationInSelf: CGPoint? = nil
	) {
		guard let finishedDrag = dragController.finishDrag(
			cancelled: cancelled,
			resetImmediately: resetImmediately
		) else {
			return
		}
		let wasDragAboveThreshold = isDragAboveListThreshold
		isDragAboveListThreshold = false
		lastDraggedFrameMidX = nil
		currentDragDisplacement = nil
		updateVisibleRowDisplacements(animated: wasDragAboveThreshold)
		dragRuntime.settle(cancelled: cancelled)
		cancelPendingPressActivation(clearPendingPress: true)
		removeCancellationObservers()
		let session = finishedDrag.session
		let oldRow = displayOrder.firstIndex(of: session.itemID)!

		let finalDestination = finishedDrag.cancelled
			? session.initialIndex
			: resolvedFinalDropDestination(
				for: session,
				explicitLocationInSelf: finalLocationInSelf
			) ?? session.proposedIndex
		let finalDisplayOrder = finishedDrag.cancelled
			? modelOrder
			: ReorderableListGeometry.reorderedValues(
				displayOrder,
				moving: oldRow,
				to: finalDestination
			)
		displayOrder = finalDisplayOrder
		syncDisplayRowIndexCache()
		let newRow = resolvedFinalRowIndex(
			sourceIndex: session.initialIndex,
			insertionIndex: finalDestination,
			cancelled: finishedDrag.cancelled
		)
		if oldRow != newRow {
			tableView.moveRow(at: oldRow, to: newRow)
		}
		syncSelectionIfNeeded()
		let targetFrame = tableView.rect(ofRow: newRow)
		if finishedDrag.cancelled == false, finalDestination != session.initialIndex {
			configuration.onMove(IndexSet(integer: session.initialIndex), finalDestination)
			announcementCoordinator.announceCompletedMove(
				from: session.initialIndex,
				insertionIndex: finalDestination,
				rows: rows.count
			)
		}
		else if finishedDrag.cancelled {
			announcementCoordinator.announceCancel()
		}
		configuration.onMoveEnd?(session.initialIndex, finalDestination)

		moveDraggedRowToRestingFrame(
			itemID: session.itemID,
			to: targetFrame,
			commit: finishedDrag.cancelled == false,
			animated: finishedDrag.settlesImmediately == false
		)
		updateCellStates(animated: false)
		let settleDuration = dragVisualController.settleDuration ?? 0
		if finishedDrag.settlesImmediately || settleDuration.isFinite == false || settleDuration <= 0 {
			dragController.flushSettlement(onSettled: completeSettlement)
		}
		else {
			dragController.scheduleSettlement(
				after: settleDuration,
				onSettled: completeSettlement
			)
		}
		if wasDragAboveThreshold {
			onDragAboveListThresholdChanged?(false, session.itemID)
		}
	}

	private func finishDragAboveList(
		itemID: ID,
		settleTarget: CGRect?,
		onComplete: @escaping (ID) -> Void
	) {
		// Cancel the drag (returns to original row) but we'll override the settle target.
		isDragAboveListThreshold = false
		lastDraggedFrameMidX = nil
		// Keep currentDragDisplacement and row transforms in place — the rows are
		// already collapsed (gap closed) from the above-threshold state. Clearing
		// them here would animate the gap back open, only for the tab removal in
		// onComplete to close it again, causing a visible jitter. completeSettlement
		// will clear displacements non-animated in the same run-loop pass as the
		// model update, so no intermediate frame is rendered.

		guard let finishedDrag = dragController.finishDrag(
			cancelled: true,
			resetImmediately: false
		) else {
			onComplete(itemID)
			return
		}

		dragRuntime.settle(cancelled: true)
		cancelPendingPressActivation(clearPendingPress: true)
		removeCancellationObservers()
		let session = finishedDrag.session
		let oldRow = displayOrder.firstIndex(of: session.itemID)!
		let finalDisplayOrder = modelOrder
		displayOrder = finalDisplayOrder
		syncDisplayRowIndexCache()
		let newRow = resolvedFinalRowIndex(
			sourceIndex: session.initialIndex,
			insertionIndex: session.initialIndex,
			cancelled: true
		)
		if oldRow != newRow {
			tableView.moveRow(at: oldRow, to: newRow)
		}
		syncSelectionIfNeeded()
		announcementCoordinator.announceCancel()
		configuration.onMoveEnd?(session.initialIndex, session.initialIndex)

		if let settleTarget {
			// Settle to the pinned grid tile position instead of the original row.
			beginSettlePerformanceIntervalIfNeeded()
			stopRowSettleAnimation()
			hideLiveRow(for: session.itemID)
			dragVisualController.beginSettle(
				to: settleTarget,
				commit: true,
				backgroundColor: ReorderableListStyle.resolvedColor(
					dragBackgroundColor ?? configuration.rowBackgroundColor,
					for: tableView.effectiveAppearance
				),
				appearance: configuration.dragAppearance,
				animated: true,
				durationOverride: ReorderableListStyle.animationDuration
			)
		} else {
			let targetFrame = tableView.rect(ofRow: newRow)
			moveDraggedRowToRestingFrame(
				itemID: session.itemID,
				to: targetFrame,
				commit: false,
				animated: finishedDrag.settlesImmediately == false
			)
		}
		updateCellStates(animated: false)

		// Skip onDragAboveListThresholdChanged — the separator already animated
		// to the correct position during the drag. Firing the threshold callback
		// here would reset it to the pre-drag position, causing a visible jump
		// before the pin toggle re-applies the correct height.

		let settleDuration = dragVisualController.settleDuration ?? 0
		let capturedItemID = session.itemID
		let completionHandler: @MainActor (ID, Bool) -> Void = { [weak self] itemID, cancelled in
			self?.completeSettlement(itemID: itemID, cancelled: cancelled)
			onComplete(capturedItemID)
		}
		if finishedDrag.settlesImmediately || settleDuration.isFinite == false || settleDuration <= 0 {
			dragController.flushSettlement(onSettled: completionHandler)
		} else {
			dragController.scheduleSettlement(
				after: settleDuration,
				onSettled: completionHandler
			)
		}
	}

	private func resolvedFinalDropDestination(
		for session: DragSession<ID>,
		explicitLocationInSelf: CGPoint?
	) -> Int? {
		let locationInSelf = explicitLocationInSelf ?? resolvedCurrentPointerLocationInSelf()
		guard let locationInSelf,
		      let hostView else {
			return nil
		}
		let locationInContent = tableView.convert(locationInSelf, from: hostView)
		let targetCenterY = locationInContent.y + session.pointerOffsetFromRowCenter.y
		return resolvedDestinationIndex(for: targetCenterY, sourceIndex: session.initialIndex)
	}

	private func resolvedCurrentPointerLocationInSelf() -> CGPoint? {
		guard let pointerLocationInWindow = dragRuntime.pointerLocationInWindow,
		      let hostView else {
			return nil
		}
		if hostView.window != nil {
			return hostView.convert(pointerLocationInWindow, from: nil)
		}
		return pointerLocationInWindow
	}

	private func commitMove(
		sourceIndex: Int,
		insertionIndex: Int,
		itemID: ID,
		announceCompletion: Bool
	) {
		let oldRow = displayOrder.firstIndex(of: itemID)!
		displayOrder = ReorderableListGeometry.reorderedValues(
			displayOrder,
			moving: oldRow,
			to: insertionIndex
		)
		syncDisplayRowIndexCache()
		let newRow = displayOrder.firstIndex(of: itemID)!
		if oldRow != newRow {
			tableView.moveRow(at: oldRow, to: newRow)
		}
		syncSelectionIfNeeded()
		configuration.onMove(IndexSet(integer: sourceIndex), insertionIndex)
		configuration.onMoveEnd?(sourceIndex, insertionIndex)
		if announceCompletion {
			announcementCoordinator.announceCompletedMove(
				from: sourceIndex,
				insertionIndex: insertionIndex,
				rows: rows.count
			)
		}
	}

	private func resolvedFinalRowIndex(
		sourceIndex: Int,
		insertionIndex: Int,
		cancelled: Bool
	) -> Int {
		guard cancelled == false,
		      let itemID = itemID(atModelIndex: sourceIndex) else {
			return sourceIndex
		}
		return displayOrder.firstIndex(of: itemID)!
	}

	private func syncSelectionIfNeeded() {
		guard let selectedItemID,
		      let row = row(for: selectedItemID) else {
			tableView.deselectAll(nil)
			return
		}
		tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
	}

	private func rowView(for itemID: ID, makeIfNecessary: Bool) -> ReorderableListRowView? {
		let row = row(for: itemID)!
		return tableView.rowView(atRow: row, makeIfNecessary: makeIfNecessary) as? ReorderableListRowView
	}

	private func containerView(for itemID: ID, makeIfNecessary: Bool) -> ReorderableListItemContainerView? {
		let row = row(for: itemID)!
		return tableView.view(atColumn: 0, row: row, makeIfNecessary: makeIfNecessary) as? ReorderableListItemContainerView
	}

	private func ensureVisibleRowsLoaded() {
		guard let visibleRows = visibleRowRange() else { return }
		ensureVisibleRowsLoaded(in: visibleRows, reason: .initial)
	}

	private func dragObserver(for itemID: ID) -> ReorderableListItemDragObserver? {
		containerView(for: itemID, makeIfNecessary: true)?.contentView as? ReorderableListItemDragObserver
	}

	private func completeSettlement(itemID: ID, cancelled: Bool) {
		stopRowSettleAnimation()
		dragRuntime.resetToIdle()
		removeCancellationObservers()
		cancelPendingPressActivation(clearPendingPress: true)
		currentDragDisplacement = nil
		updateVisibleRowDisplacements(animated: false)
		hideDragPlaceholder()
		syncSelectionIfNeeded()
		updateCellStates(animated: false)
		revealLiveRow(for: itemID)
		dragVisualController.tearDown()
		dragObserver(for: itemID)?.reorderableListItemDidEndDrag(cancelled: cancelled)
		if let queuedItems {
			self.queuedItems = nil
			setItems(queuedItems)
		}
		endSettlePerformanceIntervalIfNeeded()
		configuration.onReorderInteractionDidFinish?()
	}

	private func stopRowSettleAnimation() {
		dragVisualController.freezeToPresentation()
	}

	private func dragVisualFrameInTableCoordinates() -> CGRect? {
		guard let overlayHostView, let frameInHost = dragVisualController.currentFrameInHost else { return nil }
		return tableView.convert(frameInHost, from: overlayHostView)
	}

	private func hideLiveRow(for itemID: ID) {
		rowView(for: itemID, makeIfNecessary: true)?.alphaValue = 0
	}

	private func revealLiveRow(for itemID: ID) {
		rowView(for: itemID, makeIfNecessary: true)?.alphaValue = 1
	}

	private func syncIndexCaches() {
		syncModelIndexCache()
		syncDisplayRowIndexCache()
	}

	private func syncModelIndexCache() {
		modelIndexByID = Self.indexMap(for: rows.map(\.id))
	}

	private func syncDisplayRowIndexCache() {
		displayRowByID = Self.indexMap(for: displayOrder)
	}

	private static func indexMap(for ids: [ID]) -> [ID: Int] {
		Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
	}

	private func invalidateDragPreviewCache() {
		dragPreviewImageCache.removeAll(keepingCapacity: true)
	}

	private func dragPreviewImage(for itemID: ID, rowView: ReorderableListRowView) -> NSImage? {
		if let cachedPreview = dragPreviewImageCache[itemID],
		   cachedPreview.size == rowView.bounds.size {
			currentPerformanceMetrics.dragPreviewCacheHits += 1
			return cachedPreview.image
		}

		currentPerformanceMetrics.dragPreviewCacheMisses += 1
		guard let snapshotImage = makeSnapshotImage(from: rowView) else {
			return nil
		}
		dragPreviewImageCache[itemID] = ReorderableListDragPreviewCacheEntry(
			size: rowView.bounds.size,
			image: snapshotImage
		)
		currentPerformanceMetrics.dragPreviewCreations += 1
		return snapshotImage
	}

	private func resolvedDragChromeGeometry(
		for itemID: ID,
		rowView: ReorderableListRowView
	) -> ReorderableListDragChromeGeometry? {
		guard let container = containerView(for: itemID, makeIfNecessary: true),
		      let provider = container.contentView as? ReorderableListDragChromePathProviding,
		      let geometry = provider.reorderableListDragChromeGeometry() else {
			return nil
		}

		return ReorderableListDragChromeGeometry(
			chromeFrame: rowView.convert(geometry.chromeFrame, from: container.contentView),
			cornerRadius: geometry.cornerRadius,
			borderWidth: geometry.borderWidth
		)
	}

	private func resolvedDestinationIndex(
		for targetCenterY: CGFloat,
		sourceIndex: Int
	) -> Int {
		if let fixedRowHeight = configuration.fixedRowHeight {
			currentPerformanceMetrics.fixedHeightDestinationIndexEvaluations += 1
			return ReorderableListGeometry.fixedHeightDestinationIndex(
				for: targetCenterY,
				sourceIndex: sourceIndex,
				rowHeight: fixedRowHeight,
				itemCount: rows.count,
				rowSpacing: configuration.rowSpacing,
				contentInsets: NSEdgeInsetsZero
			)
		}

		currentPerformanceMetrics.variableHeightDestinationIndexEvaluations += 1
		return ReorderableListGeometry.destinationIndex(
			for: targetCenterY,
			sourceIndex: sourceIndex,
			itemHeights: rowHeights(),
			width: tableView.bounds.width,
			contentInsets: NSEdgeInsetsZero
		)
	}

	private func visibleRowRange() -> Range<Int>? {
		let visibleRows = tableView.rows(in: tableView.visibleRect)
		guard visibleRows.length > 0 else { return nil }
		return visibleRows.location..<(visibleRows.location + visibleRows.length)
	}

	private func ensureVisibleRowsLoaded(
		in rows: Range<Int>,
		reason: VisibleRowLoadReason
	) {
		guard rows.isEmpty == false else { return }
		var realizedRowCount = 0
		for row in rows where row >= 0 && row < self.rows.count {
			_ = tableView.rowView(atRow: row, makeIfNecessary: true)
			if let container = tableView.view(atColumn: 0, row: row, makeIfNecessary: true) as? ReorderableListItemContainerView,
			   let itemID = itemID(atDisplayRow: row) {
				applyCurrentCellState(to: container, itemID: itemID, animated: false)
				applyCurrentDisplacement(atRow: row, animated: false)
				container.frame.size.width = resolvedMeasurementWidth()
				container.needsLayout = true
				container.layoutSubtreeIfNeeded()
				container.displayIfNeeded()
			}
			realizedRowCount += 1
		}
		tableView.displayIfNeeded()
		if case .autoscrollEdge = reason {
			currentPerformanceMetrics.autoscrollVisibleRowRealizations += realizedRowCount
		}
	}

	private func ensureAutoscrolledRowsLoaded(previousVisibleRows: Range<Int>?) {
		guard let currentVisibleRows = visibleRowRange() else { return }
		guard let previousVisibleRows else {
			ensureVisibleRowsLoaded(in: currentVisibleRows, reason: .autoscrollEdge)
			return
		}

		if currentVisibleRows.lowerBound < previousVisibleRows.lowerBound {
			ensureVisibleRowsLoaded(
				in: currentVisibleRows.lowerBound..<min(previousVisibleRows.lowerBound, currentVisibleRows.upperBound),
				reason: .autoscrollEdge
			)
		}

		if currentVisibleRows.upperBound > previousVisibleRows.upperBound {
			ensureVisibleRowsLoaded(
				in: max(previousVisibleRows.upperBound, currentVisibleRows.lowerBound)..<currentVisibleRows.upperBound,
				reason: .autoscrollEdge
			)
		}
	}

	private func makeSnapshotImage(from rowView: ReorderableListRowView) -> NSImage? {
		guard rowView.bounds.isEmpty == false,
		      let bitmapRep = rowView.bitmapImageRepForCachingDisplay(in: rowView.bounds)
		else {
			return nil
		}

		rowView.cacheDisplay(in: rowView.bounds, to: bitmapRep)
		let image = NSImage(size: rowView.bounds.size)
		image.addRepresentation(bitmapRep)
		return image
	}

	private func measurePerformanceInterval<Result>(
		_ event: ReorderableListPerformanceTraceEvent,
		_ work: () -> Result
	) -> Result {
		let traceHandle = performanceTracing.beginInterval(event)
		let startTime = monotonicClock()
		let result = work()
		let duration = max(monotonicClock() - startTime, 0)
		recordPerformanceDuration(duration, for: event)
		performanceTracing.endInterval(traceHandle)
		return result
	}

	private func beginSettlePerformanceIntervalIfNeeded() {
		guard activeSettleTraceHandle == nil else { return }
		activeSettleTraceHandle = performanceTracing.beginInterval(.dragSettle)
		activeSettleStartTime = monotonicClock()
	}

	private func endSettlePerformanceIntervalIfNeeded() {
		guard let traceHandle = activeSettleTraceHandle,
		      let startTime = activeSettleStartTime else {
			activeSettleTraceHandle = nil
			activeSettleStartTime = nil
			return
		}

		let duration = max(monotonicClock() - startTime, 0)
		recordPerformanceDuration(duration, for: .dragSettle)
		performanceTracing.endInterval(traceHandle)
		activeSettleTraceHandle = nil
		activeSettleStartTime = nil
	}

	private func recordPerformanceDuration(
		_ duration: TimeInterval,
		for event: ReorderableListPerformanceTraceEvent
	) {
		switch event {
		case .dragLift:
			currentPerformanceMetrics.dragLiftMeasurementCount += 1
			currentPerformanceMetrics.dragLiftTotalDuration += duration
		case .dragUpdate:
			currentPerformanceMetrics.dragUpdateMeasurementCount += 1
			currentPerformanceMetrics.dragUpdateTotalDuration += duration
		case .autoscrollTick:
			currentPerformanceMetrics.autoscrollTickMeasurementCount += 1
			currentPerformanceMetrics.autoscrollTickTotalDuration += duration
		case .dragSettle:
			currentPerformanceMetrics.dragSettleMeasurementCount += 1
			currentPerformanceMetrics.dragSettleTotalDuration += duration
		}
	}
}
