import AppKit

public struct ReorderDragAppearance {
	public var scale: CGFloat
	public var opacity: CGFloat
	public var shadowOpacity: Float
	public var shadowRadius: CGFloat
	public var shadowOffset: CGSize
	public var rotationRadians: CGFloat
	public var borderOpacity: CGFloat
	public var translationOffset: CGSize

	public init(
		scale: CGFloat = 1.02,
		opacity: CGFloat = 1,
		shadowOpacity: Float = 0.15,
		shadowRadius: CGFloat = 10,
		shadowOffset: CGSize = .zero,
		rotationRadians: CGFloat = (3 * .pi) / 180,
		borderOpacity: CGFloat = 0.8,
		translationOffset: CGSize = .zero
	) {
		self.scale = scale
		self.opacity = opacity
		self.shadowOpacity = shadowOpacity
		self.shadowRadius = shadowRadius
		self.shadowOffset = shadowOffset
		self.rotationRadians = rotationRadians
		self.borderOpacity = borderOpacity
		self.translationOffset = translationOffset
	}
}

public struct ReorderPerformanceMetrics {
	public var overlayUpdates = 0
	public var overlayPositionOnlyUpdates = 0
	public var overlayBoundsUpdates = 0
	public var insertionIndexChanges = 0
	public var visibleRowDisplacementUpdates = 0
	public var autoscrollTicks = 0
	public var autoscrollVisibleRowRealizations = 0
	public var dragPreviewCreations = 0
	public var dragPreviewCacheHits = 0
	public var dragPreviewCacheMisses = 0
	public var fixedHeightDestinationIndexEvaluations = 0
	public var variableHeightDestinationIndexEvaluations = 0
	public var dragLiftMeasurementCount = 0
	public var dragLiftTotalDuration: TimeInterval = 0
	public var dragUpdateMeasurementCount = 0
	public var dragUpdateTotalDuration: TimeInterval = 0
	public var autoscrollTickMeasurementCount = 0
	public var autoscrollTickTotalDuration: TimeInterval = 0
	public var dragSettleMeasurementCount = 0
	public var dragSettleTotalDuration: TimeInterval = 0

	public init() {}
}

public struct AutoscrollConfiguration {
	public var edgeZoneHeight: CGFloat
	public var minimumSpeed: CGFloat
	public var maximumSpeed: CGFloat

	public init(
		edgeZoneHeight: CGFloat = 12,
		minimumSpeed: CGFloat = 180,
		maximumSpeed: CGFloat = 1080
	) {
		self.edgeZoneHeight = edgeZoneHeight
		self.minimumSpeed = minimumSpeed
		self.maximumSpeed = maximumSpeed
	}
}

struct ReorderableListConfiguration<Item, ID: Hashable> {
	let id: KeyPath<Item, ID>
	let contentInsets: NSEdgeInsets
	let rowSpacing: CGFloat
	let rowBackgroundColor: NSColor
	let dragAppearance: ReorderDragAppearance
	let autoscroll: AutoscrollConfiguration
	let reorderHandleWidth: CGFloat?
	let longPressDuration: TimeInterval
	let accessibilityAnnouncementsEnabled: Bool
	let accessibilityAnnouncementHandler: @MainActor (String) -> Void
	var onMove: ReorderableListView<Item, ID>.MoveAction
	var canMove: ((Item) -> Bool)?
	var onMoveStart: ((ID, Int) -> Void)?
	var onMoveUpdate: ((Int, Int) -> Void)?
	var onMoveEnd: ((Int, Int) -> Void)?
	var onReorderInteractionDidFinish: (() -> Void)?
	let contentViewBuilder: ReorderableListView<Item, ID>.ContentViewBuilder
	let dragStartThreshold: CGFloat
	let estimatedRowHeight: CGFloat
	let fixedRowHeight: CGFloat?
}

struct ReorderableListRowModel<Item, ID: Hashable> {
	let id: ID
	let item: Item
	var measuredHeight: CGFloat?
}

struct ReorderableListDragPreviewCacheEntry {
	let size: CGSize
	let image: NSImage
}

struct ReorderableListDestinationThresholdLayout {
	let sourceIndex: Int
	let thresholds: [CGFloat]
	let sourceUpperThresholdY: CGFloat
	let sourceLowerThresholdY: CGFloat

	func destinationIndex(for targetCenterY: CGFloat) -> Int {
		ReorderableListGeometry.destinationIndex(
			for: targetCenterY,
			thresholdLayout: self,
			fallbackDestination: sourceIndex
		)
	}
}

extension NSUserInterfaceItemIdentifier {
	static let reorderableListColumn = NSUserInterfaceItemIdentifier("ReorderableList.Column")
	static let reorderableListContainer = NSUserInterfaceItemIdentifier("ReorderableList.Container")
}

struct DragSession<ID: Hashable> {
	let itemID: ID
	let initialIndex: Int
	var proposedIndex: Int
	let pointerOffset: CGPoint
	let pointerOffsetFromRowCenter: CGPoint
	let destinationThresholdLayout: ReorderableListDestinationThresholdLayout?
	let fixedRowHeight: CGFloat?

	init(
		itemID: ID,
		initialIndex: Int,
		proposedIndex: Int,
		pointerOffset: CGPoint,
		pointerOffsetFromRowCenter: CGPoint? = nil,
		destinationThresholdLayout: ReorderableListDestinationThresholdLayout? = nil,
		fixedRowHeight: CGFloat? = nil
	) {
		self.itemID = itemID
		self.initialIndex = initialIndex
		self.proposedIndex = proposedIndex
		self.pointerOffset = pointerOffset
		self.pointerOffsetFromRowCenter = pointerOffsetFromRowCenter ?? pointerOffset
		self.destinationThresholdLayout = destinationThresholdLayout
		self.fixedRowHeight = fixedRowHeight
	}
}

enum InteractionState<ID: Hashable> {
	case idle
	case pressArmed(itemID: ID, locationInView: CGPoint)
	case dragging(DragSession<ID>)
	case settling(itemID: ID, cancelled: Bool)
}

enum DragEligibility<ID: Hashable> {
	case none
	case row(ID)
	case blockedByControl
}

public enum ReorderableListDragVisualUpdateKind {
	case none
	case positionOnly
	case boundsChanged
}

final class ReorderableTableOverlayHostView: NSView {
	override var isFlipped: Bool {
		true
	}

	override var isOpaque: Bool {
		false
	}

	override func makeBackingLayer() -> CALayer {
		ReorderableListAnimationLayer()
	}

	override func viewDidMoveToSuperview() {
		super.viewDidMoveToSuperview()
		wantsLayer = true
		layer?.masksToBounds = true
		layer?.backgroundColor = NSColor.clear.cgColor
	}

	override func hitTest(_: NSPoint) -> NSView? {
		nil
	}
}
