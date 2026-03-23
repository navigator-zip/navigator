# AppKit Engineering Guide: Rebuilding ReorderableList From Scratch

> Note: This guide is for a new, fresh AppKit component. It is not a rewrite, retrofit, or in-place modification of existing reorderable list components.

## Objective

Recreate the existing `ReorderableList` behavior as a native AppKit component that:

- supports smooth drag-to-reorder interaction for large lists
- preserves the current visual behavior of the iOS implementation
- allows the actively dragged item to appear visually lifted
- supports transform effects on the moving item:
  - scale
  - rotation
  - shadow
  - opacity
  - optional translation offsets
- dims non-dragged rows while a reorder is in progress
- supports optional drag-handle-only initiation
- supports separator hiding for the actively dragged cell
- is architected for high performance with hundreds of rows
- is flexible enough to host arbitrary row content
- avoids SwiftUI gesture/state churn during drag

This guide assumes an AppKit-first implementation. SwiftUI hosting can still be used for row content if needed, but the reordering system itself should be fully AppKit-native.

## 1. Existing Behavior To Preserve

Before designing the AppKit version, define exactly what the current component does.

### Public API Behavior

The current component accepts:

- a collection of items
- a stable ID key path
- optional bottom inset or margin
- optional reorder handle width
- `onMove(IndexSet, Int)`
- a row-content builder

The AppKit version should preserve the same conceptual API:

- data source of items
- stable ID for diffing and drag ownership
- optional bottom content inset
- optional handle-gated drag initiation
- move callback
- arbitrary row content

### Visual Behavior

Each row receives a `ReorderableListCellState` with:

- `isReordering`
- `isListReordering`
- `isHighlighted`
- `isSelected`

The styling behavior is:

- When this row is being dragged:
  - accent stroke appears
  - scale increases slightly to `1.02`
  - shadow appears
  - rotation is applied at `3°`
  - separator may be hidden
  - animation duration is `0.15s easeInOut`
- When the list is reordering but this row is not the dragged row:
  - row opacity is reduced to `0.6`
- When not reordering:
  - row returns to normal state

### Interaction Behavior

- reorder begins after long press
- if a handle width is set, drag must start from the handle zone
- drag is interactive and follows the pointer
- the lifted item appears visually detached
- the list updates order as the item moves
- on end, state resets
- on cancel, state resets
- data updates from outside are ignored while reordering
- visible cells are reconfigured when reorder state changes

Those are the baseline semantics the AppKit implementation must preserve.

## 2. Recommended AppKit Architecture

Do not try to reproduce the UIKit version literally.

The UIKit version leans on `UICollectionView` interactive movement. In AppKit, the best implementation is not gesture recognizers plus hosted views plus ad hoc frame moves. For performance and correctness, treat this as a table-rendering system with a dedicated drag controller.

Recommended top-level structure:

### `ReorderableListView<Item, ID>`

Public AppKit view exposed to the rest of the app.

Responsibilities:

- owns scroll view and table view
- exposes configuration
- wires controller to host
- accepts data updates

### `ReorderableListController<Item, ID>`

Core orchestration object.

Responsibilities:

- current row models
- display order
- drag lifecycle
- move calculations
- visible row invalidation
- diff-based updates when not dragging
- coordinating placeholder and overlay behavior

### `ReorderableListTableView`

Custom `NSTableView`.

Responsibilities:

- event forwarding
- row hit testing helpers
- optimized row queries
- optional suppression of default AppKit visuals

### `ReorderableListRowView`

Custom `NSTableRowView`.

Responsibilities:

- background drawing
- selected, highlighted, and reordering state visuals
- separator visibility
- static layout container
- cheap non-host-level style updates

### `ReorderableListCellView`

Custom `NSView` or `NSHostingView` container per row.

Responsibilities:

- hosts user row content
- exposes handle frame
- reports preferred hit region
- applies dimming for non-dragged items if desired

### `ReorderableListDragController<ID>`

Dedicated drag state machine.

Responsibilities:

- begin drag
- track pointer
- create lifted snapshot or view
- compute target index
- animate surrounding rows or placeholder
- autoscroll near edges
- finish or cancel drag

### `ReorderableListLiftedOverlayView`

Detached visual for the moving row.

Responsibilities:

- render the dragged item above the table
- apply shadow, scale, rotation, opacity, and transforms
- animate into and out of drag state

### `ReorderableListPlaceholderView`

Placeholder-row model state during drag.

Responsibilities:

- preserve table layout
- avoid content collapse
- optionally draw insertion gap or subdued placeholder

### `ReorderableListAnimator`

Optional helper around Core Animation timing and transform composition.

Responsibilities:

- centralize animation constants
- ensure consistent easing and duration
- keep drag visual updates cheap

## 3. Core Design Choice: Overlay-Based Drag, Not Moving The Real Row

This is the most important architectural recommendation.

### What Not To Do

Do not directly drag the live row view around inside the table as the main implementation. That causes problems:

- row reuse and table invalidation become messy
- AppKit may fight layout
- clipping and z-order become awkward
- transforms like rotation and shadow are harder to isolate cleanly
- performance degrades when the live row participates in normal table relayout

### What To Do Instead

Use this drag model:

1. User begins drag on a row.
2. Capture a visual representation of that row.
3. Hide or fade the original content in place.
4. Show a detached overlay copy above the table.
5. Move the overlay with the pointer.
6. Update list ordering or placeholder position independently.
7. On end, animate overlay back into final row position, then tear it down.

This cleanly supports:

- shadow
- rotation
- scale
- opacity
- custom transforms
- performant reordering
- predictable row layout

This is how to preserve the lifted feel from the SwiftUI modifier in an AppKit-native way.

## 4. Data Model

Use stable row models internally.

```swift
struct ReorderableListRowModel<Item, ID: Hashable> {
    let id: ID
    var item: Item
}
```

Controller state:

```swift
@MainActor
final class ReorderableListController<Item, ID: Hashable>: NSObject {
    var rows: [ReorderableListRowModel<Item, ID>]
    var displayOrder: [ID]

    var draggedID: ID?
    var draggedSourceIndex: Int?
    var currentDestinationIndex: Int?
    var isReordering = false

    var queuedExternalItems: [Item]?
}
```

### Why Keep Both `rows` And `displayOrder`

For large lists, separating identity from presentation order simplifies reordering logic.

- `rows` stores canonical item-by-ID mapping
- `displayOrder` stores current visual order
- reordering becomes moving IDs, not rebuilding full objects
- row view configuration can derive item from ID lookup

You can also keep a single ordered array if simpler, but for larger systems `displayOrder` is often cleaner.

## 5. Event Model: Use Mouse Events, Not Long-Press Gesture Recognizers

On AppKit, the reorder interaction should be driven by mouse event handling, not primarily by `NSGestureRecognizer`.

### Why

Gesture recognizers are fine for simple interactions, but for high-performance reordering they usually become a liability:

- less control over press threshold and drag hysteresis
- awkward coordination with scrolling
- harder handle gating
- harder cancellation semantics
- more surprising conflicts with subviews

### Recommended Interaction Pipeline

Use a dedicated event-forwarding path:

- `mouseDown`
- short press or hold timer if long-press initiation is required
- drag hysteresis threshold
- `mouseDragged`
- `mouseUp`

### Long-Press Behavior

The iOS version uses `minimumPressDuration = 0.3`.

AppKit equivalent:

- on mouse down, determine candidate row
- if handle gating is enabled, validate pointer is inside handle rect
- start a timer for `0.3s`
- if pointer moves beyond drag slop before timer fires, either:
  - cancel reorder initiation and allow scroll or select behavior, or
  - if the desired UX is hold-then-drag only, keep waiting unless movement exceeds a cancel threshold
- when timer fires, enter reorder mode

### Recommended Drag Thresholds

- long press: `0.28s` to `0.35s`
- drag slop before activation: `3pt` to `5pt`
- reorder index switch midpoint: half row height

This reproduces the feel of the iOS component closely.

## 6. Hit Testing And Handle-Gated Reordering

The existing component optionally restricts drag start to a trailing handle area:

```swift
let handleRect = CGRect(
    x: max(cell.contentView.bounds.width - reorderHandleWidth, 0),
    y: 0,
    width: reorderHandleWidth,
    height: cell.contentView.bounds.height
)
```

The AppKit version should preserve this.

### Recommended Implementation

Each row content container should expose a handle rect in its local coordinates.

```swift
protocol ReorderableListHandleProviding: AnyObject {
    var reorderHandleRect: NSRect? { get }
}
```

On `mouseDown`:

- identify row
- convert point into row-local coordinates
- if handle width is configured:
  - either compute trailing rect generically
  - or ask the row view or container for its handle rect
- only permit reorder candidate state if point is inside handle rect

### Why This Matters

Do not infer the handle region from visual subviews unless you control them fully. A generic trailing-width policy is fast and reliable. If content is custom and may change, a protocol-based handle rect is better.

## 7. Row State Model

You need the AppKit equivalent of `ReorderableListCellState`.

```swift
struct ReorderableListCellState: Equatable, Sendable {
    var isReordering: Bool
    var isListReordering: Bool
    var isHighlighted: Bool
    var isSelected: Bool
}
```

Each row view should be configurable with this state.

### How State Is Consumed

Dragged row:

- `isReordering = true`
- `isListReordering = true`

Other rows while dragging:

- `isReordering = false`
- `isListReordering = true`

Normal:

- `isReordering = false`
- `isListReordering = false`

Highlighted or selected:

- preserve for future parity even if current SwiftUI code does not visibly use them much

Important:

Do not make every drag tick rebuild all row content. Only update visible rows when the state meaningfully changes:

- drag began
- dragged row changed
- drag ended or cancelled
- selection or highlight changed

Per-frame updates should only move the overlay and placeholder visuals.

## 8. Visual Styling Parity

The SwiftUI modifier encodes the main visual contract. Recreate each effect intentionally.

### Base Lifted Styling

From the SwiftUI version:

- background: rounded rectangle, radius `8`
- fill: `paneBackground`
- border: accent with alpha `0.8` when dragged
- border width: `2` when dragged
- scale: `1.02` when dragged
- shadow: black with alpha `0.15`, radius `10` when dragged
- rotation: `3°` when dragged
- animation: `easeInOut(0.15)`

### AppKit Implementation Strategy

Apply these in the detached overlay, not the live table row.

### Overlay Visual Stack

The lifted overlay should be a composed view or layer tree:

- outer container layer or view
- rounded background
- hosted content snapshot or live content copy
- border or stroke layer
- shadow on outer layer
- transform on outer layer

This keeps the moving row cheap to animate.

Recommended layer config:

```swift
overlayView.wantsLayer = true
overlayView.layer?.cornerRadius = 8
overlayView.layer?.masksToBounds = false
overlayView.layer?.shadowOpacity = 0.15
overlayView.layer?.shadowRadius = 10
overlayView.layer?.shadowOffset = CGSize(width: 0, height: 4)
```

Apply transform using `CATransform3D`:

```swift
var transform = CATransform3DIdentity
transform = CATransform3DScale(transform, 1.02, 1.02, 1)
transform = CATransform3DRotate(transform, 3 * (.pi / 180), 0, 0, 1)
overlayView.layer?.transform = transform
```

### Why Not Rotate The Real Table Row

Because the table is still laying out rows in a vertical geometry system. Rotation on a live row view can affect hit testing, clipping, invalidation, and visual overlap. The overlay cleanly avoids all of that.

## 9. Separator Hiding On Drag

The current SwiftUI modifier removes the separator entirely for the actively dragged cell.

In AppKit, implement separator drawing in the row view, not via generic table grid lines.

Recommendation:

- disable default `NSTableView` grid drawing
- own separators entirely in `ReorderableListRowView`
- draw separator normally
- skip separator when `cellState.isReordering == true`

This is both faster and more faithful to the existing behavior.

## 10. Table Layout Strategy

For performance with hundreds of items, prefer fixed row heights if available.

Strong recommendation:

- use a fixed row height in the AppKit implementation unless dynamic height is truly required

Benefits:

- `O(1)` y-position calculations
- cheap index-from-location mapping
- less layout invalidation
- faster autoscroll math
- simpler placeholder animation
- less row measurement complexity

If dynamic row heights are needed later, make that a separate V2 path.

## 11. Drag Lifecycle State Machine

Implement the drag interaction as an explicit state machine.

```swift
enum ReorderState<ID: Hashable> {
    case idle
    case pressArmed(row: Int, id: ID, mouseDownLocation: NSPoint, timestamp: TimeInterval)
    case dragging(
        draggedID: ID,
        sourceIndex: Int,
        currentIndex: Int,
        pointerOffsetInRow: CGFloat
    )
    case settling
}
```

Transition flow:

### `idle -> pressArmed`

On valid mouse down in a row or handle region.

### `pressArmed -> dragging`

After long-press duration elapses and initial conditions still hold.

Actions:

- set `isReordering = true`
- compute pointer offset within row
- create overlay
- hide or fade source row content
- update row states
- begin autoscroll monitoring

### `pressArmed -> idle`

If mouse up occurs before activation, or pointer invalidates candidate.

### `dragging -> dragging`

On `mouseDragged`:

- move overlay
- determine destination row
- update placeholder or order visuals
- autoscroll if near edges

### `dragging -> settling`

On `mouseUp`:

- finalize destination
- call `onMove`
- animate overlay into final frame

### `dragging -> settling` on cancel

On escape, window loss, or invalid drag cancel:

- animate overlay back to source frame
- do not call `onMove`

### `settling -> idle`

After animation completion:

- tear down overlay
- clear state
- apply queued external data update if any
- refresh visible rows

Use explicit states. Avoid boolean soup like `isReordering`, `didBeginMovement`, and `dragOffset`.

## 12. Building The Drag Overlay

This is the core visual piece.

### Options For Overlay Content

Best option for performance and visual stability:

- snapshot the row into an image-backed layer or image view

Pros:

- extremely cheap to move or transform every frame
- preserves exact appearance
- no live subview layout during drag
- best for shadows and rotation

Cons:

- dynamic live subview content inside the dragged row will not update while dragging

For reorder interactions, this tradeoff is usually ideal.

Alternative:

- detach a live content view clone

Pros:

- live content can continue updating

Cons:

- heavier
- more complicated copying or hosting
- more fragile with arbitrary custom content

Recommendation:

- use a snapshot-backed overlay unless there is a strong reason not to

### Snapshot Creation

Capture the row content view as an `NSImage`:

- create bitmap representation
- cache display into bitmap
- build image
- display image in overlay view

Then wrap that image inside a rounded, shadowed, bordered container.

### Overlay Geometry

Store:

- source row frame in table coordinates
- source row frame converted into overlay-host coordinates
- pointer offset within row

Then on drag movement:

```swift
overlayOriginY = pointerLocationInHost.y - pointerOffsetInRow
```

This keeps the overlay locked to the same point the user grabbed.

## 13. Reordering Strategy

There are two broad strategies.

### Strategy A: Real-Time Data Or Model Reorder During Drag

As the dragged item crosses row boundaries, mutate `displayOrder` and ask the table to move rows.

Pros:

- matches final order continuously
- easy reasoning about destination index

Cons:

- can trigger more row churn
- must carefully avoid expensive reloads

### Strategy B: Placeholder Gap Plus Final Commit

Keep the model static during drag, and only move a visual placeholder or gap. Commit final order on drop.

Pros:

- less data churn
- very smooth

Cons:

- more custom layout logic

### Recommended Approach

For AppKit, use a hybrid:

- visually maintain a placeholder index during drag
- update table row positions cheaply to reflect the placeholder
- commit actual model order either:
  - incrementally as the placeholder changes, if row movement APIs are efficient
  - or once at drop, if placeholder rendering is strong enough

For hundreds of rows, either can work. If using `NSTableView`, final commit plus placeholder is often cleaner.

## 14. Calculating Destination Index

With fixed row heights, destination calculation is simple and fast.

Given:

- visible content offset
- pointer y in table or document coordinates
- `rowHeight`
- current dragged source index

Compute raw row slot:

```swift
let rawIndex = Int(floor(pointerY / rowHeight))
let clampedIndex = max(0, min(rawIndex, rowCount - 1))
```

For better feel, use row midpoint crossing.

```swift
let hoveredRow = row(at: pointerY)
let rowRect = rect(ofRow: hoveredRow)
let midpoint = rowRect.midY

let destination: Int
if pointerY < midpoint {
    destination = hoveredRow
} else {
    destination = hoveredRow + 1
}
destination = clamp(destination, 0...rowCount)
```

Then adjust for source-removal semantics when computing the final move callback.

## 15. Move Semantics And `onMove(IndexSet, Int)`

The original callback is:

- `onMove(source, destinationIndex)`

Preserve this exactly.

Important detail:

- if you remove the source element before inserting, destination semantics must match expected caller behavior

Standard reorder rule:

- moving an item from a lower index to a higher index means insertion index may need adjustment after removal
- moving from a higher index to a lower index does not require the same adjustment

Create a single utility function and never duplicate this logic.

```swift
func move<T>(_ array: inout [T], from source: Int, to proposedDestination: Int) -> Int
```

Return the normalized destination used after source removal.

The controller should use the same normalization both:

- internally for preview and final order
- externally when calling `onMove`

That prevents mismatches between UI and caller model updates.

## 16. External Data Updates While Dragging

The UIKit implementation ignores incoming updates while reordering:

```swift
guard !isReordering else { return }
```

Keep that behavior.

Recommended AppKit behavior:

- when external data changes during drag, store it in `queuedExternalItems`
- do not update visible order mid-drag
- after drag completes or cancels:
  - apply queued update
  - diff and reload or move rows as needed

Why:

- mid-drag external reloads can destroy the illusion of stable manipulation
- user intent should dominate during the reorder gesture

## 17. Autoscroll During Drag

A reorderable list feels broken without autoscroll.

Required behavior:

- when the pointer nears the top or bottom edge of the scroll view while dragging:
  - begin scrolling in that direction
  - continue updating placeholder destination and overlay position
  - stop when pointer leaves edge zone or bounds are reached

Recommended implementation:

- use a display-linked timer or equivalent tick
- a simple `Timer` at `60Hz` can work, but display-synced animation is preferable

Edge zones:

- top activation zone: `24pt` to `40pt`
- bottom activation zone: `24pt` to `40pt`

Velocity ramp:

- nearer the edge means faster scroll
- cap maximum speed to something sensible

This makes long-list reorders much more usable.

## 18. Animation Behavior

The SwiftUI implementation uses `easeInOut(duration: 0.15)` for row-state transitions.

Replicate that feel.

Animate on these moments:

### Drag Begin

Animate overlay from normal row snapshot to lifted state:

- scale from `1.0` to `1.02`
- rotation from `0°` to `3°`
- shadow opacity from `0` to `0.15`
- accent border from `0` to visible

### Drag End

Animate overlay from lifted state back into final row frame:

- position to final row rect
- scale back to `1.0`
- rotation back to `0°`
- shadow back to `0`
- border back to `0`

### List Dimming

Animate visible non-dragged rows to opacity `0.6` on start, back to `1.0` on end.

### Separator Hiding

Animate separator opacity out and back in for the dragged row if desired.

Recommendation:

- use Core Animation-backed animations for overlay properties
- use `NSAnimationContext` or layer-backed opacity changes for stable row views
- keep per-frame drag movement non-animated

Only state transitions should animate.

## 19. Performance Guidance

This is where AppKit implementations usually go wrong.

Golden rule:

- during active drag, do not do expensive view reconstruction

Per-frame operations should be limited to:

- moving overlay frame or position
- maybe updating a placeholder or gap
- maybe autoscroll offset
- maybe a very small set of row transforms if visually needed

Avoid per-frame:

- rebuilding hosted row content
- full table reloads
- invalidating all rows
- calling `noteHeightOfRows`
- recreating constraints
- snapshotting repeatedly

Specific recommendations:

- fixed row height
- row reuse
- layer-backed views
- snapshot once
- visible rows only
- no full reload on reorder tick
- precompute geometry

## 20. Recommended View Hierarchy

```text
ReorderableListView
 ├─ NSScrollView
 │   └─ ReorderableListTableView
 └─ ReorderableListOverlayHostView
     └─ ReorderableListLiftedOverlayView (during drag only)
```

Why separate overlay host:

- if the overlay lives inside the table or document view, clipping and scrolling behavior become awkward
- a sibling overlay host above the scroll view is much cleaner

Convert frames between table or document coordinates and overlay-host coordinates during drag.

## 21. Row Styling Implementation

Each row view should know:

- current `ReorderableListCellState`
- background color
- separator visibility
- selection and highlight state
- whether content is hidden because overlay is active

Recommended split:

- row view handles:
  - background fill
  - separator drawing
  - dimming via alpha if not dragged and list active
  - optional border only if you choose to show it in-row too
- overlay handles:
  - lifted border
  - scale
  - shadow
  - rotation

Do not try to make the live row visually identical to the dragged overlay while it remains in the table. The overlay is the hero visual; the row should mostly step aside.

## 22. Preserving Arbitrary Row Content

The SwiftUI implementation accepts a generic row builder. The AppKit equivalent should preserve that flexibility.

Two viable approaches:

### Approach A: Pure AppKit Row Content Builder

Caller provides `NSView` per item.

Best for:

- maximum performance
- native behavior
- no SwiftUI hosting overhead

### Approach B: SwiftUI Hosted Row Content Inside AppKit

Caller provides SwiftUI `View`, internally hosted in `NSHostingView`.

Best for:

- API parity with current code
- incremental migration

Tradeoff:

- more expensive than pure AppKit
- still workable for hundreds of rows if reuse is handled well and active drag avoids rehosting

Recommendation:

- build the reordering engine in pure AppKit
- allow either row-content mode

That preserves a migration path.

## 23. Selection And Highlight Semantics

Even if the current iOS version sets highlight and selection to `false`, the AppKit version should support them correctly.

Suggested rules:

- `isSelected` should reflect table selection if selection is enabled
- `isHighlighted` can reflect mouse hover, pressed, or highlight behavior if desired
- dragged state takes visual priority over selected and highlighted state
- non-dragged rows during list reorder should still dim even if selected, unless design says otherwise

Make the precedence explicit:

1. dragged
2. selection or highlight
3. normal

## 24. Accessibility Considerations

Recommendations:

- preserve table and row accessibility roles
- expose reorder handles if visible as separate accessible elements when feasible
- announce reorder start and end if an accessibility layer exists
- ensure dragged overlay is not treated as a duplicate accessible row
- keep focus or selection anchored to the logical row, not the overlay

This is easier if the overlay is explicitly excluded from accessibility.

## 25. Testing Strategy

This component needs both logic tests and interaction tests.

### Unit Tests

Reorder logic:

- move upward
- move downward
- move to same index
- first to last
- last to first
- destination normalization

State machine:

- `idle -> pressArmed`
- `pressArmed -> dragging`
- cancel before activation
- `dragging -> settling -> idle`
- external update queued during drag

Handle gating:

- drag start inside handle succeeds
- drag start outside handle fails

Destination calculation:

- midpoint behavior
- bounds clamping
- autoscroll boundary handling

### UI Or Integration Tests

- overlay appears on drag begin
- non-dragged rows dim
- dragged row separator hidden
- rotation, scale, and shadow applied
- drop commits callback with correct indices
- cancel does not commit
- external updates after drag apply correctly

### Visual Regression Tests

Especially important for:

- border visibility
- shadow intensity
- rotation angle
- dimming opacity
- separator hiding

## 26. Recommended Public API

```swift
@MainActor
public final class ReorderableListView<Item, ID: Hashable>: NSView {
    public typealias MoveAction = (IndexSet, Int) -> Void
    public typealias ContentViewBuilder = (Item) -> NSView

    public init(
        items: [Item],
        id: KeyPath<Item, ID>,
        rowHeight: CGFloat,
        bottomContentInset: CGFloat = 0,
        reorderHandleWidth: CGFloat? = nil,
        onMove: @escaping MoveAction,
        contentView: @escaping ContentViewBuilder
    )

    public func updateItems(_ items: [Item])
}
```

Optional configuration object:

```swift
public struct ReorderableListConfiguration<Item, ID: Hashable> {
    var id: KeyPath<Item, ID>
    var rowHeight: CGFloat
    var bottomContentInset: CGFloat
    var reorderHandleWidth: CGFloat?
    var liftedCornerRadius: CGFloat
    var liftedScale: CGFloat
    var liftedRotationDegrees: CGFloat
    var liftedShadowOpacity: Float
    var liftedShadowRadius: CGFloat
    var nonDraggedOpacity: CGFloat
    var animationDuration: TimeInterval
}
```

This makes visual parity configurable without hardcoding every constant.

## 27. Implementation Plan

### Phase 1: Base Table And Row Infrastructure

Build:

- scroll view
- table view
- row reuse
- row content hosting
- custom separator drawing
- fixed row height

Done when:

- list renders correctly
- bottom inset works
- updates can be applied efficiently

### Phase 2: Drag Lifecycle And Overlay

Build:

- mouse-driven press or hold handling
- handle gating
- overlay snapshot creation
- source row hiding or fading
- lifted styling with border, shadow, scale, and rotation

Done when:

- dragged row visually detaches
- overlay follows pointer smoothly

### Phase 3: Reorder Preview And Commit

Build:

- destination index calculation
- placeholder or gap preview movement
- `onMove` callback
- final settle animation

Done when:

- rows reorder correctly
- drop index matches visual preview

### Phase 4: Polish And Edge Behavior

Build:

- autoscroll
- cancellation
- queued external update handling
- visible-row-only state refresh
- highlight and selection precedence

Done when:

- component feels production-ready under stress

### Phase 5: Performance Pass

Measure:

- drag FPS
- row reconfiguration counts
- snapshot cost
- reload count during drag
- autoscroll smoothness

Done when:

- hundreds of rows remain smooth during reorder

## 28. Key Pitfalls To Avoid

1. Reconfiguring all rows every drag tick.
2. Dragging the live row instead of an overlay.
3. Mixing gesture recognizers and mouse event handling.
4. Letting external updates reload the table mid-drag.
5. Doing expensive snapshots repeatedly.
6. Relying on default `NSTableView` separators and visuals.
7. Not normalizing move semantics.
8. Applying rotation or shadow to the real row.

## 29. Exact Behavior Mapping From SwiftUI Or UIKit To AppKit

### `isReordering`

Maps to:

- row is source row of active drag
- source row content hidden or subdued in table
- overlay uses lifted styling

### `isListReordering`

Maps to:

- any drag is active
- non-dragged visible rows set to alpha `0.6`

### `reorderableListLiftedStyling`

Maps to overlay styling:

- rounded background
- accent stroke
- scale `1.02`
- shadow radius `10`, opacity `0.15`
- rotation `3°`
- animated over `0.15s`

### `reorderableListSeparatorHiddenOnDrag`

Maps to row separator drawing suppression when `rowState.isReordering == true`.

### `reorderHandleWidth`

Maps to trailing drag hit-region gating reorder activation.

### `bottomContentMargin`

Maps to scroll-view content inset or document bottom padding.

## 30. Strong Recommendation Summary

If this AppKit component needs to be both faithful and robust, the right design is:

- `NSTableView`-based list
- fixed row height
- custom row views
- mouse-event-driven reorder controller
- detached overlay snapshot for active drag
- placeholder or efficient preview reordering in the table
- all lifted transforms applied to the overlay, not the real row
- visible-row-only state updates
- queued external updates during drag

That structure best preserves the original behavior while giving AppKit the performance headroom it needs for large datasets.

## 31. Suggested Constants For Parity

```swift
enum ReorderableListVisuals {
    static let cornerRadius: CGFloat = 8
    static let liftedScale: CGFloat = 1.02
    static let liftedRotationDegrees: CGFloat = 3
    static let liftedShadowOpacity: Float = 0.15
    static let liftedShadowRadius: CGFloat = 10
    static let liftedShadowYOffset: CGFloat = 4
    static let nonDraggedOpacity: CGFloat = 0.6
    static let borderWidth: CGFloat = 2
    static let animationDuration: TimeInterval = 0.15
    static let longPressDuration: TimeInterval = 0.3
    static let dragActivationSlop: CGFloat = 4
    static let autoscrollEdgeZone: CGFloat = 32
}
```

## 32. Final Build Target

A production-quality AppKit recreation of this component should feel like this:

- press and hold on a row or handle
- row visually lifts into a detached, rotated, shadowed card
- the rest of the list subtly dims
- the original slot remains stable via placeholder treatment
- dragging remains smooth even with hundreds of rows
- rows reshuffle predictably as the dragged item crosses boundaries
- dropping commits the move cleanly
- cancelling restores everything cleanly
- external updates never disrupt the interaction

That is the closest faithful AppKit translation of the current implementation.

## Animation-First Engineering Guide For Reorderable AppKit List

### Core Principle

The dragged representation must be its own animation object, with its own lifecycle, geometry model, and state machine.

Do not think of the drag as the table row moving.

Think of it as:

- the real row becomes a logical source anchor
- a detached visual replica takes over on screen
- that detached replica owns all animated transitions
- the table only updates layout or placeholder state underneath

This separation is what gives you clean lift-off, clean settle, reliable cancel, and interruptability.

## 33. Animation Goals

The system should guarantee these properties.

### Lift-Off

When drag begins, the row should:

- appear to detach from the table, not pop
- preserve its exact screen position on the first animated frame
- animate from rest to lifted styling:
  - scale up
  - rotate slightly
  - shadow in
  - accent border in
  - optionally raise z-depth visually
- keep the grabbed point attached to the pointer during the transition

### Active Drag

While dragging:

- the dragged representation should move at full framerate
- movement should not be animated with easing lag
- pointer-to-object relationship should remain stable
- transforms should remain stable
- table reshuffling underneath should not visually perturb the dragged object

### Drop Or Cancel Settle

When drag ends, the dragged representation should:

- continue from its exact final gesture position
- animate directly into the final row frame
- settle to either:
  - new row position if committed
  - original row position if cancelled
- remove lifted styling during the same settle transition
- never snap first and animate second
- never disappear and reappear in-row

### Interruptability

If the user begins another interaction quickly, or the component is updated during settle:

- animation must be cancellable or restartable
- presentation geometry must be sampled correctly
- no stale completion handler should tear down the wrong overlay
- the system must remain internally consistent

## 34. The Most Important Animation Rule

Never animate from model values that are stale relative to on-screen presentation.

This is the biggest source of broken drag and drop animations.

If the overlay is already moving and a new animation starts from its last assigned model frame instead of its presentation frame, the result is:

- snapping
- first-frame jumps
- visibly discontinuous settle animations
- incorrect interruption behavior

For any interruptable drag animation system, read from active presentation state when transitioning between animation phases.

In practical terms:

- before starting lift, use actual current geometry
- before starting settle, use the overlay layer’s current presentation position and transform if available
- if an animation is interrupted, freeze current presentation into model state first

That is non-negotiable.

## 35. Recommended Animation Architecture

Use a dedicated animation coordinator for the dragged object.

### Recommended Components

#### `ReorderableListDragVisualController`

Owns the detached drag representation and all animation transitions.

Responsibilities:

- create overlay from row snapshot
- store source and destination geometry
- apply lifted styling
- track current pointer position
- perform lift animation
- perform settle animation
- expose freeze-from-presentation behavior
- tear down safely

#### `ReorderableListDragVisualState`

Pure geometry and state snapshot:

```swift
struct ReorderableListDragVisualState {
    var center: CGPoint
    var bounds: CGRect
    var scale: CGFloat
    var rotationRadians: CGFloat
    var shadowOpacity: Float
    var shadowRadius: CGFloat
    var borderOpacity: CGFloat
    var opacity: CGFloat
}
```

This makes animation transitions explicit instead of smearing them across several view properties.

#### `ReorderableListAnimationTransactionID`

Every lift and settle animation should have a monotonically increasing transaction token.

Why:

- old completions must not tear down a newer overlay
- cancel and re-drop edge cases become safe
- race conditions become much easier to reason about

## 36. Use Core Animation For The Dragged Object

For the dragged representation, Core Animation is the right tool.

Why:

- transform animation
- shadow animation
- border opacity animation
- position animation
- presentation-layer sampling
- reliable interruptability
- cheap compositing
- `60fps` motion

`NSAnimationContext` is fine for some row opacity work underneath, but the dragged representation should be layer-backed and animated through Core Animation.

Recommendation:

- make the overlay view layer-backed and treat its root layer as the animation surface
- animate:
  - `position`
  - `transform`
  - `shadowOpacity`
  - `shadowRadius`
  - `opacity`
  - border-layer opacity
- do not animate via Auto Layout constraints during drag or settle

Constraints are not the right abstraction for this interaction.

## 37. Lift-Off Animation Design

Lift-off should feel like the row is being peeled off the list, not toggled into a new style.

### Sequence At Drag Begin

When the press threshold is satisfied and drag officially begins:

1. Identify source row and source frame in overlay-host coordinates.
2. Create snapshot overlay exactly matching the row’s current visible frame.
3. Hide or fade the in-table source row content.
4. Compute pointer offset relative to row.
5. Freeze overlay at exact source geometry.
6. Begin lift animation to lifted style.
7. Immediately begin non-animated tracking of pointer position.

### Key Detail: Position Continuity

The overlay must start in the exact same on-screen position as the original row before the row is hidden.

That means:

- source row frame must be converted precisely
- overlay creation must happen before the source row fully disappears
- first displayed overlay frame must align exactly with the row

If this is missed, the lift will blink.

### What Should Animate In Lift-Off

Animate these properties over about `120ms` to `180ms`:

- scale: `1.0 -> 1.02`
- rotation: `0 -> 3°`
- shadow opacity: `0 -> 0.15`
- shadow radius: `0 -> 10`
- border opacity: `0 -> 1`
- optionally row content opacity underneath: `1 -> 0` or near-zero

### What Should Not Lag

The overlay’s position should remain locked to the pointer relationship immediately. Do not ease the object into following the pointer after drag begin.

Better approach:

- position updates immediately from the first drag frame
- style properties animate into lifted state
- motion is direct and styling eases in

This produces the cleanest feel.

## 38. Pointer Tracking Should Be Direct, Not Animated

During active drag, movement should not be driven by repeated easing animations.

Correct approach:

- on every relevant drag event:
  - compute target center from pointer position plus stored grab offset
  - set layer or view position directly
  - use no implicit animation
  - use no easing
  - use no spring
  - use no catch-up effect

Use transaction suppression:

```swift
CATransaction.begin()
CATransaction.setDisableActions(true)
// update position / frame
CATransaction.commit()
```

This ensures the overlay tracks input exactly.

If every mouse-drag event starts a new animation, the result is:

- timing contention
- presentation and model drift
- inconsistent latency
- apparent frame loss

The dragged object should be composited directly at the latest position, not animated toward it.

## 39. Settle Animation Design

The settle must begin from the exact visual state at gesture end and animate into the final row frame.

### On Drop Or Cancel

At gesture end:

- stop pointer-driven updates
- freeze overlay at its current presentation state
- determine logical final destination frame
- determine target final styling state
- animate from current presentation state to target row state
- on completion, reveal final row content and destroy overlay

### Freeze From Presentation First

Before computing settle animation, explicitly capture:

- presentation position
- presentation transform
- presentation opacity
- presentation shadow state
- presentation border opacity if animated

Then assign those values back to the model layer before starting settle.

This prevents first-frame jumps.

### Target States

Successful drop:

- final row frame center
- scale `1.0`
- rotation `0`
- shadow opacity `0`
- shadow radius `0`
- border opacity `0`

Cancel:

- original source row frame center
- same neutral styling values as above

The visual motion should be identical in principle. Only the destination frame differs.

## 40. Recommended Settle Timing

Settle animation should generally be a little crisper than lift.

Recommended range:

- `140ms` to `180ms` for short settle distances
- optionally `180ms` to `220ms` for longer travel distances

Recommendation:

- use a distance-aware but tightly bounded duration:
  - minimum: `0.14`
  - maximum: `0.22`

Example:

```swift
let distance = hypot(dx, dy)
let duration = min(0.22, max(0.14, 0.14 + (distance / 1200.0)))
```

Keep the band narrow. Too much dynamic variation makes the component feel inconsistent.

## 41. Timing Curves

For lift and settle, timing curve matters more than many teams realize.

### Lift

Use a smooth ease-out or ease-in-out.

Goal:

- quick detachment
- slightly polished styling arrival
- no bounce

Recommended:

- cubic ease-out
- or standard `.easeInEaseOut` if simplicity is preferred

### Settle

Use a slightly stronger ease-out.

Goal:

- leave from exact gesture-end position
- arrive confidently into row slot
- avoid floatiness

Recommended:

- cubic ease-out
- or a critically damped spring only if extremely carefully tuned

Strong recommendation:

- do not use a bouncy spring by default

Why:

- it makes target-row arrival feel imprecise
- it complicates interruptability
- it can read as toy-like in dense productivity UI
- it makes cancellation less trustworthy

For a reorderable AppKit table, a well-tuned ease-out is usually the best choice.

## 42. Animation Phases Should Be Explicit

Do not let dragging and settling coexist ambiguously.

Use explicit phases like:

```swift
enum DragVisualPhase {
    case idle
    case lifting
    case dragging
    case settling(commit: Bool)
}
```

This matters because each phase has different animation rules:

- `lifting`
  - style animates
  - position tracks pointer directly
- `dragging`
  - style stable
  - position direct and unanimated
- `settling`
  - style and position animate to neutral or final
  - pointer no longer drives geometry

Without explicit phases, drag updates often end up fighting settle animations.

## 43. Underlying Row Animation Must Be Decoupled

The table rows underneath may dim, shift, or reveal placeholder state during drag, but those animations should never own the dragged visual.

That means:

- row insertion or reordering underneath can animate independently
- the dragged overlay should not depend on the row view remaining alive
- if the row view is reused while the overlay is settling, the animation should still succeed

This is why the dragged object must be a stable independent visual.

## 44. Placeholder And Row Movement Animation

The quality of the drag animation also depends on how the rest of the list responds.

Recommendation:

- when placeholder or destination changes:
  - animate affected row shifts using position or frame animation
  - keep those animations short and consistent
  - avoid full reload
  - only animate rows whose slot changed

Timing:

- use roughly `100ms` to `140ms` ease-in-out for row shifts beneath the dragged item

This should be slightly subordinate to the dragged object’s motion.

## 45. Interruptability Rules

A reliable component needs a clear answer to what happens if a new state arrives during animation.

Cases to handle:

### Case A: Drop animation starts while lift is still finishing

Solution:

- freeze from presentation
- cancel current animation transaction logically
- start settle from actual presentation state

### Case B: Component is updated externally during settle

Solution:

- settling overlay continues independently
- queued data update is applied only after settle completes
- or if the component must hard-reset, freeze and tear down safely without stale completion effects

### Case C: Window or layout changes during drag

Solution:

- either disallow certain structural changes during active drag
- or recompute destination geometry in overlay-host coordinates before settle begins

### Case D: Drag cancels abruptly

Solution:

- use the same settle system with original source frame as target

Practical rule:

- every animation start should:
  - increment animation transaction ID
  - freeze from presentation
  - clear or supersede previous completions
  - start new animation with current transaction ID
  - ignore any completion whose ID is stale

This is what makes the system reliable instead of mostly working.

## 46. Guard Animation Completions With Tokens

Completion handlers are dangerous if they assume they still refer to the current animation state.

Always gate completions with a token.

Conceptually:

```swift
let token = nextAnimationToken()
currentAnimationToken = token

startSettleAnimation { [weak self] in
    guard let self else { return }
    guard self.currentAnimationToken == token else { return }
    self.finishSettle()
}
```

Without this, rapid interruption can:

- destroy a newer overlay
- reveal row content too early
- apply the wrong final state
- corrupt internal drag state

## 47. Presentation-Layer Freezing Method

Before any transition from one animated phase to another, implement a utility like:

```swift
func freezeOverlayToPresentation()
```

Its job is:

- read current presentation-layer values if available
- assign them back to the real layer
- remove previous animations

Capture at least:

- position
- bounds
- transform
- opacity
- `shadowOpacity`
- `shadowRadius`
- animated border-layer opacity

Then remove animations so the new transition starts from exactly what the user sees.

This utility eliminates a large class of visual glitches.

## 48. Geometry Ownership During Settle

At the moment of drop, the overlay is still authoritative visually.

The real row underneath should not become visible until the overlay is nearly done or fully done settling.

Best practice:

- during settle, keep destination row content hidden or mostly hidden
- animate overlay into target slot
- upon completion:
  - reveal real row content
  - remove overlay

This prevents the common bug where both the overlay and destination row are visible at once.

## 49. Shadow Performance

Shadow is visually important here, but it can become expensive if done carelessly.

Recommendations:

- use shadow on the overlay only
- do not add live shadows to many table rows during reorder
- set a shadow path if possible

Because the overlay shape is a rounded rectangle with stable bounds, precompute the shadow path.

```swift
overlayLayer.shadowPath = CGPath(
    roundedRect: overlayBounds,
    cornerWidth: 8,
    cornerHeight: 8,
    transform: nil
)
```

Avoid animating expensive raster content repeatedly.

Animate shadow opacity and radius on one detached layer, not across a whole subtree of dynamic views.

## 50. Rotation Design

Rotation should be subtle and stable.

The current target is `3°`, which is good. Keep it small.

Important points:

- apply rotation only to the overlay
- rotate around center
- combine with scale in a single transform
- do not continuously vary rotation during drag unless there is a deliberate physical design

A constant slight rotation is more reliable and polished than trying to make the row wobble dynamically.

## 51. Reliable 60fps Requirements

If `60fps` is a hard requirement, the drag path should do almost no heavy work.

Per frame during drag should ideally do only:

- pointer location conversion
- target center calculation
- direct layer or view position set
- maybe autoscroll computation
- maybe placeholder index check
- maybe a very small number of row-shift updates when crossing row boundaries

Per frame should not do:

- new snapshots
- row content rebuilding
- Auto Layout churn
- table reloads
- repeated transform recalculation across many rows
- `layoutSubtreeIfNeeded`
- row view recreation

The overlay path should stay shallow and compositor-friendly.

## 52. Recommended Animation Ownership Model

Recommended responsibility split:

### `DragVisualController`

Owns:

- lift animation
- drag position updates
- settle animation
- presentation freezing
- animation tokening
- overlay teardown

### `ListLayoutController`

Owns:

- placeholder index
- row shift animations
- autoscroll
- destination calculations
- row content hiding and revealing

This separation makes the code easier to reason about and prevents table updates from destabilizing drag animations.

## 53. Implement Lift And Settle As State Interpolation

Instead of sprinkling property mutations around, model start and end states and animate between them.

Example conceptual states:

Rest state:

- `center = sourceRowCenter`
- `scale = 1`
- `rotation = 0`
- `shadowOpacity = 0`
- `shadowRadius = 0`
- `borderOpacity = 0`

Lifted state:

- `center = pointerDerivedCenter`
- `scale = 1.02`
- `rotation = 3°`
- `shadowOpacity = 0.15`
- `shadowRadius = 10`
- `borderOpacity = 1`

Settled state:

- `center = destinationRowCenter`
- `scale = 1`
- `rotation = 0`
- `shadowOpacity = 0`
- `shadowRadius = 0`
- `borderOpacity = 0`

This is more robust than ad hoc property edits scattered through the drag flow.

## 54. Handling Cancel Cleanly

Cancel is where many implementations look worst.

A good cancel should feel like:

- the row was being held in the air
- the user changed their mind or drag failed
- it neatly returns to where it came from

Cancellation flow:

- freeze from presentation
- resolve target to original source row frame
- animate position and style back to neutral
- keep source row hidden during settle
- reveal source row at completion
- destroy overlay
- clear reorder state

Treat cancel as a first-class settle path, not an exceptional shortcut.

## 55. Drop Target Resolution Should Happen Before Settle

Do not begin settling until final destination geometry is fully resolved.

That means:

- the final display order or placeholder position must already be known
- destination row frame must be computable in overlay-host coordinates
- any underlying row shift that affects final frame should be committed or deterministically known

Otherwise the overlay will animate toward a moving target, which looks sloppy.

## 56. Avoid Inconsistent Frame And Transform Animation

A common mistake is mixing frame animation with transform animation in a way that changes perceived anchor points unexpectedly.

Recommendation:

- use a clear geometry model
- either animate layer position plus bounds plus transform
- or animate frame-derived position consistently while transform is centered

For this component, the simplest approach is:

- keep anchor at center
- animate position
- keep bounds constant during drag and settle unless absolutely needed
- animate transform for scale and rotation
- animate shadow and border independently

That yields stable motion.

## 57. Practical Timing Recommendation

Recommended default feel:

### Lift

- duration: `0.15`
- timing: ease-out or ease-in-out
- animate: scale, rotation, shadow, border
- position: direct, not lagged

### Row Shifts Underneath

- duration: `0.12`
- timing: ease-in-out

### Settle

- duration: `0.16` to `0.20`, distance-aware within bounds
- timing: ease-out
- animate: position plus transform back to neutral plus shadow and border out

This stays close to the current `0.15` visual language while making drop feel slightly more deliberate.

## 58. What Interruptable And Reliable Means In Code Terms

Interruptable:

- a running lift can be superseded by settle
- a running settle can be cancelled or restarted safely if architecture permits
- new animations begin from presentation state, not stale model state
- stale completions are ignored

Reliable:

- every drag session has a single owner
- every overlay has a single lifecycle
- every transition has a unique token
- row hiding and reveal is deterministic
- destination frame is resolved before settle
- component state returns to idle exactly once

If those rules are enforced, the component feels solid under abuse, not just ideal use.

## 59. Strong Implementation Recommendation

Enforce these architectural rules:

1. The dragged cell is always represented by a detached overlay snapshot.
2. During drag, overlay position is updated with actions disabled, never eased per event.
3. Lift and settle are the only animated phases of the dragged object.
4. Every lift and settle transition begins by freezing from presentation.
5. Every animation completion is guarded by a transaction token.
6. The underlying source or destination row remains hidden until overlay handoff is complete.
7. Destination geometry is stable before settle begins.
8. Table updates underneath never own the dragged visual.

Those eight rules will do more for animation quality than any specific easing curve.

## 60. Final Recommendation Summary

For animation specifically, the correct mental model is:

- dragging is not an animation
- lift and settle are the animations

During dragging, the object should track input directly and cheaply.

When the drag begins:

- animate styling into lifted state
- preserve exact position continuity

When the drag ends:

- freeze the dragged object at its exact visible position
- animate directly into final slot
- remove lifted styling during settle
- hand off to the real row only at the end

If the goal is premium feel, `60fps`, interruptability, and trustworthiness, those are the foundations.
