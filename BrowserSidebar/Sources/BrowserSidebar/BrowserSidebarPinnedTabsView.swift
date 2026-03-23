import Aesthetics
import AppKit
import ReorderableList
import Vendors

@MainActor
final class BrowserSidebarPinnedTabsView: NSView, NSCollectionViewDataSource, NSCollectionViewDelegate,
	NSCollectionViewDelegateFlowLayout {
	private struct RenderedPinnedTabState: Equatable {
		let id: BrowserTabID
		let currentURL: String
		let faviconURL: String?
		let isSelected: Bool
		let isCameraActive: Bool
		let isPinned: Bool

		static func ==(lhs: Self, rhs: Self) -> Bool {
			lhs.id == rhs.id
				&& lhs.currentURL == rhs.currentURL
				&& lhs.faviconURL == rhs.faviconURL
				&& lhs.isCameraActive == rhs.isCameraActive
				&& lhs.isPinned == rhs.isPinned
		}
	}

	private enum Grid {
		static let itemIdentifier = NSUserInterfaceItemIdentifier("browserSidebar.pinnedTabItem")
		static let collectionIdentifier = NSUserInterfaceItemIdentifier("browserSidebar.pinnedTabsCollection")
		static let faviconIdentifier = NSUserInterfaceItemIdentifier("browserSidebar.pinnedTabFavicon")
		static let fallbackLabelIdentifier = NSUserInterfaceItemIdentifier("browserSidebar.pinnedTabFallback")
		static let topPadding: CGFloat = 10
		static let bottomPadding: CGFloat = 10
		static let interitemSpacing: CGFloat = 8
		static let lineSpacing: CGFloat = 8
		static let tileDimension: CGFloat = 45
		static let cornerRadius: CGFloat = 14
		static let iconDimension: CGFloat = tileDimension * 0.3
		static let maxColumns = 4
		static let compactGridWidth: CGFloat = (tileDimension * 2) + interitemSpacing
	}

	static let compactPinnedTabsReorderWidth: CGFloat = Grid.compactGridWidth
	static let tileDimension: CGFloat = Grid.tileDimension
	static let tileCornerRadius: CGFloat = Grid.cornerRadius

	private enum ContextAction: Int {
		case togglePin
		case replacePinnedURL
	}

	private enum DragPreviewStyle {
		static let borderWidth: CGFloat = 2
		static let cornerRadius = Grid.cornerRadius
		static let canvasInset: CGFloat = 2
	}

	static let dragPasteboardType = NSPasteboard.PasteboardType("browserSidebar.pinnedTab")
	static let gridInteritemSpacing: CGFloat = Grid.interitemSpacing
	static let gridLineSpacing: CGFloat = Grid.lineSpacing

	private final class PinnedTabCollectionViewItem: NSCollectionViewItem {
		var dragPreviewImage: NSImage?
		var dragPreviewFrame = CGRect.zero

		override var draggingImageComponents: [NSDraggingImageComponent] {
			guard let dragPreviewImage else {
				return super.draggingImageComponents
			}

			let component = NSDraggingImageComponent(
				key: NSDraggingItem.ImageComponentKey.icon
			)
			component.contents = dragPreviewImage
			component.frame = dragPreviewFrame
			return [component]
		}
	}

	// MARK: - Coordinator

	weak var dragCoordinator: PinnedTabDragCoordinator?
	private var currentDragDisplacement: (sourceIndex: Int, insertionIndex: Int)?
	private var queuedUpdate: (tabs: [BrowserTabViewModel], selectedTabID: BrowserTabID?, activeCameraTabIDs: Set<BrowserTabID>, isFaviconLoadingEnabled: Bool)?

	// MARK: - Properties

	private let pinTabActionTitle: String
	private let unpinTabActionTitle: String
	private let replacePinnedTabURLActionTitle: String
	private let sidebarBackgroundColor: NSColor
	private let dragAppearance = ReorderDragAppearance()
	private let collectionViewLayout = NSCollectionViewFlowLayout()
	private let dragPlaceholderView = ReorderableListDragPlaceholderView()
	private var collectionViewTopConstraint: NSLayoutConstraint?
	private var collectionViewBottomConstraint: NSLayoutConstraint?
	private lazy var collectionView: NSCollectionView = {
		collectionViewLayout.minimumInteritemSpacing = Grid.interitemSpacing
		collectionViewLayout.minimumLineSpacing = Grid.lineSpacing
		collectionViewLayout.sectionInset = NSEdgeInsetsZero

		let collectionView = NSCollectionView()
		collectionView.identifier = Grid.collectionIdentifier
		collectionView.translatesAutoresizingMaskIntoConstraints = false
		collectionView.backgroundColors = [.clear]
		collectionView.isSelectable = true
		collectionView.allowsEmptySelection = true
		collectionView.collectionViewLayout = collectionViewLayout
		collectionView.register(
			PinnedTabCollectionViewItem.self,
			forItemWithIdentifier: Grid.itemIdentifier
		)
		collectionView.dataSource = self
		collectionView.delegate = self
		return collectionView
	}()

	private var tabs = [BrowserTabViewModel]()
	private var renderedTabStates = [RenderedPinnedTabState]()
	private var selectedTabID: BrowserTabID?
	private var activeCameraTabIDs = Set<BrowserTabID>()
	private var isFaviconLoadingEnabled = true
	private(set) var activeDraggedTabID: BrowserTabID?
	private var activeDragOriginPlaceholderFrame: CGRect?

	var onSelect: ((BrowserTabID) -> Void)?
	var onTogglePin: ((BrowserTabID) -> Void)?
	var onReplacePinnedURL: ((BrowserTabID) -> Void)?
	var onMove: ((IndexSet, Int) -> Void)?

	init(
		pinTabActionTitle: String,
		unpinTabActionTitle: String,
		replacePinnedTabURLActionTitle: String,
		sidebarBackgroundColor: NSColor
	) {
		self.pinTabActionTitle = pinTabActionTitle
		self.unpinTabActionTitle = unpinTabActionTitle
		self.replacePinnedTabURLActionTitle = replacePinnedTabURLActionTitle
		self.sidebarBackgroundColor = sidebarBackgroundColor
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

	var hasTransientReorderState: Bool {
		dragCoordinator?.hasTransientReorderState ?? (activeDraggedTabID != nil)
	}

	private var blocksModelUpdates: Bool {
		dragCoordinator?.blocksModelUpdates ?? false
	}

	func update(
		tabs: [BrowserTabViewModel],
		selectedTabID: BrowserTabID?,
		activeCameraTabIDs: Set<BrowserTabID>,
		isFaviconLoadingEnabled: Bool
	) {
		if blocksModelUpdates {
			queuedUpdate = (tabs, selectedTabID, activeCameraTabIDs, isFaviconLoadingEnabled)
			return
		}
		let previousTabStates = renderedTabStates
		let previousSelectedTabID = self.selectedTabID
		self.tabs = tabs
		self.selectedTabID = selectedTabID
		self.activeCameraTabIDs = activeCameraTabIDs
		self.isFaviconLoadingEnabled = isFaviconLoadingEnabled
		let nextTabStates = resolvedRenderedTabStates(
			for: tabs,
			selectedTabID: selectedTabID,
			activeCameraTabIDs: activeCameraTabIDs
		)
		applyCollapsedState()
		applyCollectionViewUpdate(
			from: previousTabStates,
			to: nextTabStates
		)
		renderedTabStates = nextTabStates
		updateSelection(previouslySelectedTabID: previousSelectedTabID)
	}

	func preferredHeight(for availableWidth: CGFloat) -> CGFloat {
		preferredHeight(for: availableWidth, tabCount: tabs.count)
	}

	func preferredHeight(for availableWidth: CGFloat, tabCount: Int) -> CGFloat {
		guard tabCount > 0 else { return 0 }
		let columnCount = self.columnCount(for: availableWidth)
		let rowCount = Int(ceil(Double(tabCount) / Double(max(columnCount, 1))))
		let contentHeight = (CGFloat(rowCount) * Grid.tileDimension) + (CGFloat(max(0, rowCount - 1)) * Grid.lineSpacing)
		return Grid.topPadding + contentHeight + Grid.bottomPadding
	}

	override func viewDidChangeEffectiveAppearance() {
		super.viewDidChangeEffectiveAppearance()
		collectionView.reloadData()
	}

	// MARK: - Testing Helpers

	func beginDragForTesting(sourceIndex: Int) {
		dragCoordinator?.beginDragForTesting(sourceIndex: sourceIndex)
	}

	func moveDraggedTabForTesting(to destinationIndex: Int) {
		dragCoordinator?.moveDraggedTabForTesting(to: destinationIndex)
	}

	func endDragForTesting(cancelled: Bool) {
		dragCoordinator?.endDragForTesting(cancelled: cancelled)
	}

	func displayedTabIDsForTesting() -> [BrowserTabID] {
		tabs.map(\.id)
	}

	func dragPlaceholderViewForTesting() -> ReorderableListDragPlaceholderView? {
		dragPlaceholderView.isHidden ? nil : dragPlaceholderView
	}

	func dragPlaceholderFrameForTesting() -> CGRect? {
		dragPlaceholderView.isHidden ? nil : dragPlaceholderView.frame
	}

	func dragPreviewFrameForTesting(at index: Int) -> CGRect? {
		guard let item = collectionView.item(
			at: IndexPath(item: index, section: 0)
		) as? PinnedTabCollectionViewItem else {
			return nil
		}
		return item.draggingImageComponents.first?.frame
	}

	func dragPreviewImageSizeForTesting(at index: Int) -> CGSize? {
		guard let item = collectionView.item(
			at: IndexPath(item: index, section: 0)
		) as? PinnedTabCollectionViewItem else {
			return nil
		}
		return (item.draggingImageComponents.first?.contents as? NSImage)?.size
	}

	func makeTileSnapshot(for tabID: BrowserTabID) -> NSImage? {
		guard let index = tabs.firstIndex(where: { $0.id == tabID }),
		      let item = collectionView.item(at: IndexPath(item: index, section: 0))
		else { return nil }
		return makeSnapshotImage(from: item.view)
	}

	// MARK: - Setup

	private func setup() {
		translatesAutoresizingMaskIntoConstraints = false
		addSubview(collectionView)
		setupDragPlaceholderView()

		let collectionViewTopConstraint = collectionView.topAnchor.constraint(
			equalTo: topAnchor,
			constant: Grid.topPadding
		)
		let collectionViewBottomConstraint = collectionView.bottomAnchor.constraint(
			equalTo: bottomAnchor,
			constant: -Grid.bottomPadding
		)
		self.collectionViewTopConstraint = collectionViewTopConstraint
		self.collectionViewBottomConstraint = collectionViewBottomConstraint

		NSLayoutConstraint.activate([
			collectionViewTopConstraint,
			collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
			collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
			collectionViewBottomConstraint,
		])
		applyCollapsedState()
	}

	private func setupDragPlaceholderView() {
		dragPlaceholderView.translatesAutoresizingMaskIntoConstraints = true
		dragPlaceholderView.cornerRadiusOverride = Grid.cornerRadius
		collectionView.addSubview(dragPlaceholderView)
	}

	// MARK: - Tile Displacement Animation

	func applyTileDisplacements(source: Int, insertion: Int, animated: Bool) {
		currentDragDisplacement = (sourceIndex: source, insertionIndex: insertion)
		let colCount = columnCount(for: collectionView.bounds.width)
		let tileStride = CGSize(
			width: Grid.tileDimension + Grid.interitemSpacing,
			height: Grid.tileDimension + Grid.lineSpacing
		)

		for item in collectionView.visibleItems() {
			guard let indexPath = collectionView.indexPath(for: item) else { continue }
			let tileIndex = indexPath.item

			let offset: CGPoint
			if let displacement = currentDragDisplacement {
				offset = PinnedTabGridGeometry.displacementForTile(
					at: tileIndex,
					sourceIndex: displacement.sourceIndex,
					insertionIndex: displacement.insertionIndex,
					columnCount: colCount,
					tileStride: tileStride
				)
			} else {
				offset = CGPoint(x: 0, y: 0)
			}

			applyTileDisplacementTransform(offset, to: item.view, animated: animated)
		}
	}

	private func applyTileDisplacementTransform(
		_ offset: CGPoint,
		to view: NSView,
		animated: Bool
	) {
		let targetTransform = (offset.x == 0 && offset.y == 0)
			? CATransform3DIdentity
			: CATransform3DMakeTranslation(offset.x, offset.y, 0)

		guard let layer = view.layer else {
			view.wantsLayer = true
			view.layer?.transform = targetTransform
			return
		}

		if animated {
			let currentTransform = layer.presentation()?.transform
				?? layer.transform
			let animation = CASpringAnimation(keyPath: "transform")
			animation.fromValue = NSValue(caTransform3D: currentTransform)
			animation.toValue = NSValue(caTransform3D: targetTransform)
			animation.mass = 1.0
			animation.stiffness = 600
			animation.damping = 36
			animation.duration = min(animation.settlingDuration, 0.5)
			animation.isRemovedOnCompletion = true
			layer.transform = targetTransform
			layer.add(animation, forKey: "tileDisplacement")
		} else {
			layer.removeAnimation(forKey: "tileDisplacement")
			layer.transform = targetTransform
		}
	}

	func clearTileDisplacements() {
		currentDragDisplacement = nil
		for item in collectionView.visibleItems() {
			item.view.layer?.removeAnimation(forKey: "tileDisplacement")
			item.view.layer?.transform = CATransform3DIdentity
		}
	}

	// MARK: - Selection

	private func updateSelection() {
		updateSelection(previouslySelectedTabID: nil)
	}

	private func updateSelection(previouslySelectedTabID: BrowserTabID?) {
		guard let selectedTabID else {
			collectionView.selectionIndexPaths = []
			if
				let previouslySelectedTabID,
				let previousIndex = tabs.firstIndex(where: { $0.id == previouslySelectedTabID }) {
				updatePinnedTileSelectionState(at: previousIndex, isSelected: false)
			}
			return
		}
		guard let selectedIndex = tabs.firstIndex(where: { $0.id == selectedTabID }) else {
			collectionView.selectionIndexPaths = []
			return
		}
		collectionView.selectionIndexPaths = [IndexPath(item: selectedIndex, section: 0)]

		updatePinnedTileSelectionState(at: selectedIndex, isSelected: true)
		guard
			let previouslySelectedTabID,
			previouslySelectedTabID != selectedTabID,
			let previousIndex = tabs.firstIndex(where: { $0.id == previouslySelectedTabID })
		else {
			return
		}
		updatePinnedTileSelectionState(at: previousIndex, isSelected: false)
	}

	private func updatePinnedTileSelectionState(at index: Int, isSelected: Bool) {
		guard let tabRow = pinnedTabRow(at: index) else { return }
		tabRow.updateFaviconLogoSelectionState(isSelected: isSelected)
		tabRow.applySelectionState(isSelected: isSelected)
	}

	private func pinnedTabRow(at index: Int) -> BrowserSidebarTabRow? {
		guard tabs.indices.contains(index) else { return nil }
		let item = collectionView.item(
			at: IndexPath(item: index, section: 0)
		) as? PinnedTabCollectionViewItem
		return item?.view.subviews.first as? BrowserSidebarTabRow
	}

	// MARK: - Layout Helpers

	private func applyCollapsedState() {
		let isCollapsed = tabs.isEmpty
		collectionView.isHidden = isCollapsed
		collectionViewTopConstraint?.constant = isCollapsed ? 0 : Grid.topPadding
		collectionViewBottomConstraint?.constant = isCollapsed ? 0 : -Grid.bottomPadding
		if isCollapsed {
			dragPlaceholderView.hide()
		}
	}

	private func resolvedRenderedTabStates(
		for tabs: [BrowserTabViewModel],
		selectedTabID: BrowserTabID?,
		activeCameraTabIDs: Set<BrowserTabID>
	) -> [RenderedPinnedTabState] {
		tabs.map { tab in
			RenderedPinnedTabState(
				id: tab.id,
				currentURL: tab.currentURL,
				faviconURL: tab.faviconURL,
				isSelected: selectedTabID == tab.id,
				isCameraActive: activeCameraTabIDs.contains(tab.id),
				isPinned: tab.isPinned
			)
		}
	}

	private func applyCollectionViewUpdate(
		from previousTabStates: [RenderedPinnedTabState],
		to nextTabStates: [RenderedPinnedTabState]
	) {
		guard previousTabStates.isEmpty == false else {
			collectionView.reloadData()
			return
		}

		guard previousTabStates.count == nextTabStates.count else {
			collectionView.reloadData()
			return
		}

		let previousTabIDs = previousTabStates.map(\.id)
		let nextTabIDs = nextTabStates.map(\.id)
		guard previousTabIDs == nextTabIDs else {
			collectionView.reloadData()
			return
		}

		let changedIndexPaths = zip(previousTabStates, nextTabStates)
			.enumerated()
			.compactMap { index, pair -> IndexPath? in
				let (previousState, nextState) = pair
				return previousState == nextState ? nil : IndexPath(item: index, section: 0)
			}

		guard changedIndexPaths.isEmpty == false else { return }
		collectionView.reloadItems(at: Set(changedIndexPaths))
	}

	private func columnCount(for availableWidth: CGFloat) -> Int {
		let denominator = Grid.tileDimension + Grid.interitemSpacing
		let fittingColumns = Int(floor((availableWidth + Grid.interitemSpacing) / denominator))
		return max(1, min(Grid.maxColumns, fittingColumns))
	}

	// MARK: - Drag Lifecycle (Coordinator-Driven)

	func beginDragVisualState(at sourceIndex: Int) {
		guard tabs.indices.contains(sourceIndex) else { return }
		let indexPath = IndexPath(item: sourceIndex, section: 0)
		if let item = collectionView.item(at: indexPath) as? PinnedTabCollectionViewItem {
			updateDragPreview(for: item)
		}
		activeDragOriginPlaceholderFrame = itemFrame(at: sourceIndex)
		activeDraggedTabID = tabs[sourceIndex].id
		if let draggedView = collectionView.item(at: indexPath)?.view.subviews.first {
			draggedView.alphaValue = 0
		}
		updateSelection()
		showDragPlaceholder()
	}

	func performReorder(from sourceIndex: Int, to destinationIndex: Int) {
		let clampedDestination = min(max(destinationIndex, 0), tabs.count)
		guard sourceIndex != clampedDestination else { return }

		var reorderedTabs = tabs
		reorderedTabs.move(
			fromOffsets: IndexSet(integer: sourceIndex),
			toOffset: clampedDestination
		)
		tabs = reorderedTabs

		let moveTarget = clampedDestination > sourceIndex ? clampedDestination - 1 : clampedDestination
		collectionView.animator().moveItem(
			at: IndexPath(item: sourceIndex, section: 0),
			to: IndexPath(item: moveTarget, section: 0)
		)
		updateSelection()
		onMove?(IndexSet(integer: sourceIndex), clampedDestination)
	}

	func revealDraggedTile() {
		guard let draggedID = activeDraggedTabID,
		      let index = tabs.firstIndex(where: { $0.id == draggedID }),
		      let item = collectionView.item(at: IndexPath(item: index, section: 0))
		else { return }
		if let tabRow = item.view.subviews.first as? BrowserSidebarTabRow {
			tabRow.alphaValue = 1
		}
	}

	func finishDragVisualState() {
		dragPlaceholderView.hide()
		activeDragOriginPlaceholderFrame = nil
		activeDraggedTabID = nil
		updateSelection()
	}

	func applyQueuedUpdateIfNeeded() {
		guard let queued = queuedUpdate else { return }
		queuedUpdate = nil
		update(
			tabs: queued.tabs,
			selectedTabID: queued.selectedTabID,
			activeCameraTabIDs: queued.activeCameraTabIDs,
			isFaviconLoadingEnabled: queued.isFaviconLoadingEnabled
		)
	}

	func showDragPlaceholder() {
		guard let frame = activeDragOriginPlaceholderFrame else {
			dragPlaceholderView.hide()
			return
		}

		collectionView.addSubview(dragPlaceholderView, positioned: .above, relativeTo: nil)
		dragPlaceholderView.show(frame: frame)
	}

	func updateDragPlaceholderPosition(to insertionIndex: Int) {
		guard let targetFrame = tileFrameInCollectionView(at: insertionIndex) else { return }
		collectionView.addSubview(dragPlaceholderView, positioned: .above, relativeTo: nil)
		dragPlaceholderView.show(frame: targetFrame)
	}

	func hideDragPlaceholder() {
		dragPlaceholderView.hide()
	}

	// MARK: - External Drag Placeholder (List → Pinned)

	private var externalDragInsertionIndex: Int?

	func showExternalDragPlaceholder(at insertionIndex: Int) {
		externalDragInsertionIndex = insertionIndex
		let frame = externalPlaceholderFrame(at: insertionIndex)
		collectionView.addSubview(dragPlaceholderView, positioned: .above, relativeTo: nil)
		dragPlaceholderView.show(frame: frame)
		applyExternalTileDisplacements(insertion: insertionIndex, animated: true)
	}

	func updateExternalDragPlaceholder(at insertionIndex: Int) {
		guard insertionIndex != externalDragInsertionIndex else { return }
		externalDragInsertionIndex = insertionIndex
		let frame = externalPlaceholderFrame(at: insertionIndex)
		collectionView.addSubview(dragPlaceholderView, positioned: .above, relativeTo: nil)
		dragPlaceholderView.show(frame: frame)
		applyExternalTileDisplacements(insertion: insertionIndex, animated: true)
	}

	func hideExternalDragPlaceholder() {
		externalDragInsertionIndex = nil
		dragPlaceholderView.hide()
		clearTileDisplacements()
	}

	func currentExternalPlaceholderFrame() -> CGRect? {
		guard let index = externalDragInsertionIndex else { return nil }
		return externalPlaceholderFrame(at: index)
	}

	var collectionViewForCoordinateConversion: NSView {
		collectionView
	}

	private func externalPlaceholderFrame(at insertionIndex: Int) -> CGRect {
		if let frame = tileFrameInCollectionView(at: insertionIndex) {
			return frame
		}
		// Synthesize frame for appending after last tile.
		let colCount = columnCount(for: collectionView.bounds.width)
		let col = insertionIndex % colCount
		let row = insertionIndex / colCount
		let x = CGFloat(col) * (Grid.tileDimension + Grid.interitemSpacing)
		let y = CGFloat(row) * (Grid.tileDimension + Grid.lineSpacing)
		return CGRect(x: x, y: y, width: Grid.tileDimension, height: Grid.tileDimension)
	}

	private func applyExternalTileDisplacements(insertion: Int, animated: Bool) {
		let colCount = columnCount(for: collectionView.bounds.width)
		let tileStride = CGSize(
			width: Grid.tileDimension + Grid.interitemSpacing,
			height: Grid.tileDimension + Grid.lineSpacing
		)

		for item in collectionView.visibleItems() {
			guard let indexPath = collectionView.indexPath(for: item) else { continue }
			let offset = PinnedTabGridGeometry.externalInsertionDisplacementForTile(
				at: indexPath.item,
				insertionIndex: insertion,
				columnCount: colCount,
				tileStride: tileStride
			)
			applyTileDisplacementTransform(offset, to: item.view, animated: animated)
		}
	}

	func tileFrame(at index: Int) -> CGRect? {
		guard let frame = tileFrameInCollectionView(at: index) else { return nil }
		return convert(frame, from: collectionView)
	}

	private func tileFrameInCollectionView(at index: Int) -> CGRect? {
		collectionView.layoutSubtreeIfNeeded()
		let indexPath = IndexPath(item: index, section: 0)
		if let itemView = collectionView.item(at: indexPath)?.view {
			return itemView.frame
		}
		return collectionViewLayout.layoutAttributesForItem(at: indexPath)?.frame
	}

	func tileIndexAtPoint(_ pointInCollectionView: CGPoint) -> Int? {
		guard collectionView.bounds.contains(pointInCollectionView) else { return nil }
		guard let indexPath = collectionView.indexPathForItem(at: pointInCollectionView),
		      tabs.indices.contains(indexPath.item)
		else { return nil }
		return indexPath.item
	}

	func convertToCollectionView(_ locationInWindow: CGPoint) -> CGPoint {
		collectionView.convert(locationInWindow, from: nil)
	}

	func currentColumnCount() -> Int {
		columnCount(for: collectionView.bounds.width)
	}

	var tabCount: Int {
		tabs.count
	}

	func tabID(at index: Int) -> BrowserTabID? {
		guard tabs.indices.contains(index) else { return nil }
		return tabs[index].id
	}

	func indexForTabID(_ tabID: BrowserTabID) -> Int? {
		tabs.firstIndex(where: { $0.id == tabID })
	}

	func selectTile(at index: Int) {
		let indexPath = IndexPath(item: index, section: 0)
		collectionView.deselectAll(nil)
		collectionView.selectItems(at: [indexPath], scrollPosition: [])
		collectionView(collectionView, didSelectItemsAt: [indexPath])
	}

	private func itemFrame(at index: Int) -> CGRect? {
		tileFrameInCollectionView(at: index)
	}

	// MARK: - Drag Preview

	private func updateDragPreview(for item: PinnedTabCollectionViewItem) {
		guard let previewImage = makeLiftedDragPreviewImage(from: item.view) else {
			item.dragPreviewImage = nil
			item.dragPreviewFrame = .zero
			return
		}

		item.dragPreviewImage = previewImage
		item.dragPreviewFrame = CGRect(
			x: (item.view.bounds.width - previewImage.size.width) / 2,
			y: (item.view.bounds.height - previewImage.size.height) / 2,
			width: previewImage.size.width,
			height: previewImage.size.height
		)
	}

	private func makeLiftedDragPreviewImage(from itemView: NSView) -> NSImage? {
		guard let snapshotImage = makeSnapshotImage(from: itemView) else {
			return nil
		}

		let itemBounds = CGRect(origin: .zero, size: itemView.bounds.size)
		let previewSize = dragPreviewSize(for: itemBounds.size)
		let previewImage = NSImage(size: previewSize)
		previewImage.lockFocusFlipped(true)
		defer { previewImage.unlockFocus() }

		guard let graphicsContext = NSGraphicsContext.current else {
			return nil
		}

		let context = graphicsContext.cgContext
		let previewBounds = CGRect(origin: .zero, size: previewSize)
		let chromePath = NSBezierPath(
			roundedRect: itemBounds,
			xRadius: DragPreviewStyle.cornerRadius,
			yRadius: DragPreviewStyle.cornerRadius
		)
		context.saveGState()
		context.translateBy(
			x: previewBounds.midX,
			y: previewBounds.midY
		)
		context.translateBy(
			x: dragAppearance.translationOffset.width,
			y: dragAppearance.translationOffset.height
		)
		context.rotate(by: dragAppearance.rotationRadians)
		context.scaleBy(
			x: dragAppearance.scale,
			y: dragAppearance.scale
		)
		context.translateBy(
			x: -itemBounds.midX,
			y: -itemBounds.midY
		)

		NSGraphicsContext.saveGraphicsState()
		let shadow = NSShadow()
		shadow.shadowColor = NSColor.black.withAlphaComponent(
			CGFloat(dragAppearance.shadowOpacity)
		)
		shadow.shadowBlurRadius = dragAppearance.shadowRadius
		shadow.shadowOffset = dragAppearance.shadowOffset
		shadow.set()
		resolvedDragBackdropColor(for: itemView.effectiveAppearance).setFill()
		chromePath.fill()
		NSGraphicsContext.restoreGraphicsState()

		NSGraphicsContext.saveGraphicsState()
		chromePath.addClip()
		snapshotImage.draw(in: itemBounds)
		NSGraphicsContext.restoreGraphicsState()

		resolvedColor(
			Asset.Colors.accent.color,
			for: itemView.effectiveAppearance
		)
		.withAlphaComponent(dragAppearance.borderOpacity)
		.setStroke()
		chromePath.lineWidth = DragPreviewStyle.borderWidth
		chromePath.stroke()
		context.restoreGState()
		return previewImage
	}

	private func makeSnapshotImage(from view: NSView) -> NSImage? {
		view.layoutSubtreeIfNeeded()
		guard view.bounds.isEmpty == false,
		      let bitmapRep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
		else {
			return nil
		}

		view.cacheDisplay(in: view.bounds, to: bitmapRep)
		let image = NSImage(size: view.bounds.size)
		image.addRepresentation(bitmapRep)
		return image
	}

	private func dragPreviewSize(for itemSize: CGSize) -> CGSize {
		let scaledWidth = itemSize.width * dragAppearance.scale
		let scaledHeight = itemSize.height * dragAppearance.scale
		let cosTheta = abs(cos(dragAppearance.rotationRadians))
		let sinTheta = abs(sin(dragAppearance.rotationRadians))
		let rotatedWidth = (scaledWidth * cosTheta) + (scaledHeight * sinTheta)
		let rotatedHeight = (scaledWidth * sinTheta) + (scaledHeight * cosTheta)
		let horizontalPadding = (dragAppearance.shadowRadius * 2) +
			abs(dragAppearance.shadowOffset.width) +
			(DragPreviewStyle.canvasInset * 2)
		let verticalPadding = (dragAppearance.shadowRadius * 2) +
			abs(dragAppearance.shadowOffset.height) +
			(DragPreviewStyle.canvasInset * 2)
		return CGSize(
			width: ceil(rotatedWidth + horizontalPadding),
			height: ceil(rotatedHeight + verticalPadding)
		)
	}

	// MARK: - Context Menu

	private func makeContextMenu(for tab: BrowserTabViewModel) -> NSMenu {
		let menu = NSMenu()
		let toggleItem = NSMenuItem(
			title: tab.isPinned ? unpinTabActionTitle : pinTabActionTitle,
			action: #selector(didChooseContextAction(_:)),
			keyEquivalent: ""
		)
		toggleItem.target = self
		toggleItem.tag = ContextAction.togglePin.rawValue
		toggleItem.representedObject = tab.id
		menu.addItem(toggleItem)
		if tab.currentURL != tab.initialURL {
			let replacePinnedURLItem = NSMenuItem(
				title: replacePinnedTabURLActionTitle,
				action: #selector(didChooseContextAction(_:)),
				keyEquivalent: ""
			)
			replacePinnedURLItem.target = self
			replacePinnedURLItem.tag = ContextAction.replacePinnedURL.rawValue
			replacePinnedURLItem.representedObject = tab.id
			menu.addItem(replacePinnedURLItem)
		}
		return menu
	}

	@objc
	private func didChooseContextAction(_ sender: NSMenuItem) {
		guard let tabID = sender.representedObject as? BrowserTabID else { return }
		guard let action = ContextAction(rawValue: sender.tag) else { return }

		switch action {
		case .togglePin:
			onTogglePin?(tabID)
		case .replacePinnedURL:
			onReplacePinnedURL?(tabID)
		}
	}

	// MARK: - Cell Configuration

	private func configurePinnedTabItem(
		_ item: PinnedTabCollectionViewItem,
		with tab: BrowserTabViewModel
	) {
		let view = item.view
		let isDragging = activeDraggedTabID == tab.id
		let isSelected = selectedTabID == tab.id
		view.wantsLayer = true
		view.layer?.backgroundColor = NSColor.clear.cgColor

		let tabRow: BrowserSidebarTabRow
		if let existingRow = view.subviews.first as? BrowserSidebarTabRow {
			tabRow = existingRow
		}
		else {
			let newRow = BrowserSidebarTabRow(
				displayContext: .pinned,
				isSelected: isSelected,
				pinTabActionTitle: pinTabActionTitle,
				unpinTabActionTitle: unpinTabActionTitle,
				replacePinnedTabURLActionTitle: replacePinnedTabURLActionTitle,
				controlIconDimensions: NSSize(width: Grid.iconDimension, height: Grid.iconDimension),
				rowBackgroundColor: sidebarBackgroundColor
			)
			newRow.translatesAutoresizingMaskIntoConstraints = false
			view.addSubview(newRow)

			NSLayoutConstraint.activate([
				newRow.topAnchor.constraint(equalTo: view.topAnchor),
				newRow.leadingAnchor.constraint(equalTo: view.leadingAnchor),
				newRow.trailingAnchor.constraint(equalTo: view.trailingAnchor),
				newRow.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			])

			tabRow = newRow
		}

		let fallbackText = pinnedTabFallbackCharacter(for: tab)
		let isCameraActive = activeCameraTabIDs.contains(tab.id)
		tabRow.alphaValue = isDragging ? 0 : 1
		tabRow.configure(
			with: tab,
			isFaviconLoadingEnabled: isFaviconLoadingEnabled,
			isSelected: isSelected,
			isCameraActive: isCameraActive,
			cameraActivityAccessibilityLabel: isCameraActive
				? BrowserSidebarPinnedTabsViewLocalization.cameraActivityAccessibilityLabel
				: nil,
			fallbackText: fallbackText,
			fallbackTextColor: resolvedColor(Asset.Colors.textPrimaryColor.color, for: effectiveAppearance),
			onClose: {},
			onSelect: { [weak self] in
				self?.onSelect?(tab.id)
			},
			onTogglePin: { [weak self] in
				self?.onTogglePin?(tab.id)
			},
			onReplacePinnedURL: { [weak self] in
				self?.onReplacePinnedURL?(tab.id)
			}
		)
		view.menu = makeContextMenu(for: tab)
		if !isDragging {
			updateDragPreview(for: item)
		}
	}

	private func pinnedTabFallbackCharacter(for tab: BrowserTabViewModel) -> String {
		let host = URL(string: tab.currentURL)?.host()
		let candidate = normalizedPinnedTabFallbackHostLabel(from: host)
		let value = candidate?.first ?? tab.currentURL.first ?? "?"
		return String(value).uppercased()
	}


	private func resolvedDragBackdropColor(for appearance: NSAppearance) -> NSColor {
		let resolvedSidebarBackground = resolvedColor(sidebarBackgroundColor, for: appearance)
		if resolvedSidebarBackground.alphaComponent > 0.99 {
			return resolvedSidebarBackground
		}
		return resolvedColor(NSColor.windowBackgroundColor, for: appearance)
	}

	private func normalizedPinnedTabFallbackHostLabel(from host: String?) -> String? {
		guard let host else { return nil }
		let labels = host
			.split(separator: ".")
			.map(String.init)
		guard labels.isEmpty == false else { return nil }
		if labels.first?.caseInsensitiveCompare("www") == .orderedSame, labels.count > 1 {
			return labels[1]
		}
		return labels[0]
	}

	private func resolvedColor(_ color: NSColor, for appearance: NSAppearance) -> NSColor {
		var resolvedColor = color
		appearance.performAsCurrentDrawingAppearance {
			resolvedColor = Self.resolvedColor(
				fallback: color,
				convertedColor: NSColor(cgColor: color.cgColor)
			)
		}
		return resolvedColor
	}

	private static func resolvedColor(fallback color: NSColor, convertedColor: NSColor?) -> NSColor {
		convertedColor ?? color
	}

	// MARK: - NSCollectionViewDataSource

	func numberOfSections(in _: NSCollectionView) -> Int {
		1
	}

	func collectionView(_ _: NSCollectionView, numberOfItemsInSection _: Int) -> Int {
		tabs.count
	}

	func collectionView(
		_ collectionView: NSCollectionView,
		itemForRepresentedObjectAt indexPath: IndexPath
	) -> NSCollectionViewItem {
		guard let item = collectionView.makeItem(
			withIdentifier: Grid.itemIdentifier,
			for: indexPath
		) as? PinnedTabCollectionViewItem else {
			fatalError("Unexpected pinned tab item type")
		}
		if item.view.frame == .zero {
			item.view.frame = CGRect(
				origin: .zero,
				size: NSSize(width: Grid.tileDimension, height: Grid.tileDimension)
			)
		}
		configurePinnedTabItem(item, with: tabs[indexPath.item])
		return item
	}

	// MARK: - NSCollectionViewDelegate

	func collectionView(
		_ collectionView: NSCollectionView,
		didSelectItemsAt indexPaths: Set<IndexPath>
	) {
		guard let indexPath = indexPaths.first, tabs.indices.contains(indexPath.item) else { return }
		onSelect?(tabs[indexPath.item].id)
		collectionView.selectionIndexPaths = [indexPath]
	}

	// MARK: - NSCollectionViewDelegateFlowLayout

	func collectionView(
		_: NSCollectionView,
		layout _: NSCollectionViewLayout,
		sizeForItemAt _: IndexPath
	) -> NSSize {
		NSSize(width: Grid.tileDimension, height: Grid.tileDimension)
	}

	func collectionView(
		_: NSCollectionView,
		layout _: NSCollectionViewLayout,
		insetForSectionAt _: Int
	) -> NSEdgeInsets {
		NSEdgeInsetsZero
	}
}

private enum BrowserSidebarPinnedTabsViewLocalization {
	static let cameraActivityAccessibilityLabel: String = {
		let key = "browser.sidebar.camera.indicator.active"
		let localizedValue = Bundle.module.localizedString(forKey: key, value: key, table: nil)
		if localizedValue != key {
			return localizedValue
		}
		let isJapanese = Locale.preferredLanguages.first?.hasPrefix("ja") == true
		return isJapanese ? "Navigator Camera が有効です" : "Navigator Camera active"
	}()
}

