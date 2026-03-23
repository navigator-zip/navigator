# Engineering Guide
# Stable ReorderableList Drag System Rewrite

## Objective

Rewrite the current `ReorderableListController` drag implementation to eliminate instability caused by competing input sources and multiple drag update paths.

The new architecture must guarantee:

- Single source of truth for pointer location
- Single per-frame drag update path
- Autoscroll that never fabricates pointer movement
- Stable drag overlay behavior during scroll
- Correct drag behavior when moving from edge zones back into center
- 60–120fps animation performance
- No layout thrashing during drag
- Minimal `NSTableView` mutation during drag
- Compatibility with existing ViewModel-style architecture

## High Level Architecture

The rewrite splits responsibilities into six focused components.

ReorderableListController
```
├── ReorderableListController
│
├── ReorderableListDragRuntime
│   ├── ReorderFrameDriver
│   ├── ReorderAutoscrollDriver
│   └── ReorderableListGeometryEngine
│
├── ReorderableListOverlayCoordinator
│
├── ReorderableListPlaceholderCoordinator
│
└── ReorderableListAnnouncementCoordinator
```

The key design principle:

The drag runtime owns all drag state and updates exactly once per frame.

No other component is allowed to advance drag state.

## Critical Design Rules

These rules must not be violated.

### 1. Pointer position must be stored in window coordinates

Never store drag location in content coordinates.

Why:

- Content coordinates change when the scroll view scrolls.
- Window coordinates are stable.

### 2. Drag updates must happen in one place only

All drag state changes must happen inside:

`ReorderableListDragRuntime.tick()`

No other method may:

- move the drag overlay
- compute destination index
- compute autoscroll
- update placeholder

### 3. Autoscroll must not fabricate pointer movement

Autoscroll is allowed to move the scroll view.

It is not allowed to update pointer position.

After scroll occurs, pointer position must be recomputed from window coordinates.

### 4. Drag preview must be overlay-based

The `NSTableView` must remain visually stable during drag.

Only the overlay moves.

The table row under the pointer must be hidden.

### 5. Table rows must not animate during drag

During drag:

- rows do not shift
- rows do not animate
- rows do not reposition

The preview uses:

- placeholder hole
- drop indicator
- overlay snapshot

Actual row movement occurs only on drop.

## Component Overview

### 1. ReorderableListController

This remains the integration point with the rest of the UI.

Responsibilities:

- `NSTableView` datasource/delegate
- selection management
- drag start detection
- drag completion commit
- model updates

It must not contain drag math.

Responsibilities
- configure table
- manage row models
- begin drag
- end drag
- update selection
- apply final row move

Controller State

```swift
final class ReorderableListController<Item, ID: Hashable> {

    private let tableView: NSTableView
    private let dragRuntime: ReorderableListDragRuntime<ID>
    private let overlayCoordinator: ReorderableListOverlayCoordinator

    private var rows: [RowModel]
    private var displayOrder: [ID]

}
```

Controller Events

Controller forwards events to runtime:

- mouseDown
- mouseDragged
- mouseUp
- cancelOperation
- layoutDidChange
- viewWillMoveToWindow

Controller Example

```swift
func handleMouseDragged(event: NSEvent) {

    let locationInWindow = event.locationInWindow
    dragRuntime.updatePointerLocation(locationInWindow)

    dragRuntime.requestFrame()
}
```

Controller does not compute drag position.

### 2. ReorderableListDragRuntime

This is the core of the rewrite.

It owns:

- active drag session
- pointer state
- autoscroll state
- per-frame update loop

#### Drag Runtime Responsibilities

- maintain drag session state
- compute drag geometry
- compute insertion index
- drive overlay position
- drive autoscroll
- update placeholder + drop indicator

Drag Runtime State

```swift
@MainActor
final class ReorderableListDragRuntime<ID: Hashable> {

    private var phase: DragPhase = .idle

    private var pointerLocationInWindow: CGPoint?

    private let frameDriver: ReorderFrameDriver
    private let autoscrollDriver: ReorderAutoscrollDriver
    private let geometry: ReorderableListGeometryEngine

}
```

Drag Phases

```swift
enum DragPhase<ID: Hashable> {

    case idle

    case armed(
        itemID: ID,
        mouseDownLocationInHost: CGPoint
    )

    case dragging(
        session: DragSession<ID>
    )

    case settling(
        itemID: ID,
        cancelled: Bool
    )
}
```

Drag Session

A drag session stores all data required to compute drag.

```swift
struct DragSession<ID: Hashable> {

    let itemID: ID

    let sourceIndex: Int

    var proposedInsertionIndex: Int

    let pointerOffsetFromRowCenter: CGPoint

    let previewCenters: [CGFloat]

}
```

Pointer Handling

The runtime stores only window pointer location.

`pointerLocationInWindow`

Content coordinates are derived every frame.

Pointer conversion

window -> host -> table -> content

Example:

```swift
let windowPoint = pointerLocationInWindow
let hostPoint = hostView.convert(windowPoint, from: nil)
let contentPoint = tableView.convert(hostPoint, from: hostView)
```

### Frame Driver

The drag runtime is driven by a frame driver.

Purpose:

Guarantee a single drag update per frame.

FrameDriver protocol

```swift
protocol ReorderFrameDriver {

    func start(callback: @escaping () -> Void)

    func stop()

}
```

Implementation options

Recommended:

- `CVDisplayLink`

Alternative:

- Timer scheduled on `.common` run loop

Frame Driver Requirements

- must deliver consistent frame timing
- must avoid nested frame execution
- must stop immediately on drag end

The Drag Update Loop

Every frame the runtime executes:

- `tick()`

Drag Tick Steps

1. Sample pointer location
2. Convert pointer to content coordinates
3. Compute pointer position within visible rect
4. Compute autoscroll delta
5. Apply scroll
6. Recompute pointer position after scroll
7. Compute destination insertion index
8. Update drop indicator
9. Compute dragged overlay frame
10. Update overlay position

Example Implementation

```swift
func tick() {

    guard case .dragging(let session) = phase else { return }

    let pointerInWindow = pointerLocationInWindow ?? window.mouseLocationOutsideOfEventStream

    let pointerInHost = hostView.convert(pointerInWindow, from: nil)

    var pointerInContent = tableView.convert(pointerInHost, from: hostView)

    let pointerInVisible = CGPoint(
        x: pointerInContent.x - tableView.visibleRect.minX,
        y: pointerInContent.y - tableView.visibleRect.minY
    )

    let delta = autoscrollDriver.delta(pointerY: pointerInVisible.y)

    if delta != 0 {
        scrollView.scroll(by: delta)

        pointerInContent = tableView.convert(pointerInHost, from: hostView)
    }

    updateDragProjection(pointerInContent)
}
```

### 3. ReorderAutoscrollDriver

This component calculates scroll speed.

It does not mutate drag state.

Inputs

- pointer Y inside visible rect
- visible rect height
- frame delta time

Outputs

- scroll delta

Example

```swift
func delta(pointerY: CGFloat) -> CGFloat
```

Autoscroll behavior

Speed increases as pointer approaches edge.

Use quadratic easing.

```swift
penetration = distanceIntoEdgeZone / zoneHeight
speed = minSpeed + (maxSpeed - minSpeed) * penetration²
```

### 4. Geometry Engine

Pure functions only.

No state.

Responsibilities

- destination index resolution
- dragged frame calculation
- placeholder frame
- drop indicator frame

Destination Index

For fixed height rows:

`index = floor((targetY + halfRowHeight) / rowHeight)`

For variable height rows:

Binary search preview centers.

Dragged Frame

`centerY = pointerY + pointerOffsetY`

`frame.origin.y = centerY - rowHeight / 2`

Horizontal drag offset may apply easing.

### 5. Overlay Coordinator

Responsible for the lifted visual.

Responsibilities

- create snapshot image
- animate lift
- move overlay
- animate settle
- teardown

Overlay Lifecycle

- lift
- move
- settle
- destroy

Lift

Snapshot the row view.

Use:

- `bitmapImageRepForCachingDisplay`

Overlay Layer

Use:

- `CALayer` backed `NSView`

Apply:

- `shadow`
- `scale`
- `corner radius`

### 6. Placeholder Coordinator

Displays the empty hole where dragged item originated.

Responsibilities:

- show placeholder
- update placeholder
- hide placeholder

Placeholder frame equals original row frame.

### 7. Drop Indicator

Thin line indicating insertion location.

Displayed only when:

- `destinationIndex != sourceIndex`

## Drag Lifecycle

1. Mouse Down

Controller hit-tests row handle.

Runtime enters:

- armed
2. Drag Start

When threshold crossed:

dragging

Runtime:

- computes pointer offset
- snapshots row
- hides live row
- shows placeholder
- starts frame driver
3. Drag Update

Each frame:

`tick()`

Runtime updates overlay and indicators.

4. Drag End

Controller calls:

`endDrag(cancelled)`

Runtime:

- stop frame driver
- compute final index
- animate settle

Controller then applies:

`tableView.moveRow`

## Performance Requirements

The drag loop must remain under 1ms per frame.

Avoid

- `tableView.reloadData()`
- `layoutSubtreeIfNeeded()`
- constraint creation

during drag.

Allowed

- overlay layer transforms
- scrollView scrolling
- drop indicator frame changes

## Testing Requirements

### Critical Tests

- Drag top → bottom → back to center
  - Must follow pointer correctly.
- Drag while autoscrolling up/down
  - No jitter.
- Rapid direction reversal near edges.
- Drop cancel.
- Drop commit.
- 500+ row list performance.

### Debug Instrumentation

Add runtime metrics:

- `dragFrameCount`
- `dragFrameDuration`
- `autoscrollTicks`
- `destinationIndexChanges`
- `overlayUpdates`

## Migration Plan

### Step 1

Implement new components alongside existing controller.

### Step 2

Switch drag path to runtime.

### Step 3

Remove legacy fields:

- lastKnownDragLocationInContent
- autoscrollTimer
- activeDestinationIndexResolver

### Step 4

Stabilize pointer coordinate system.

### Step 5

Enable performance tracing.

## Expected Improvements

The rewrite will eliminate:

- edge sticking
- pointer drift
- scroll race conditions
- recursive drag updates
- content coordinate instability

and produce a much more predictable drag system.

## Estimated Implementation Size

Approximate code size:

DragRuntime                 ~500 lines
OverlayCoordinator          ~250 lines
GeometryEngine              ~200 lines
AutoscrollDriver            ~120 lines
Controller integration      ~200 lines

Total:

~1200 lines

## Final Notes

The most important rule for the engineer implementing this:

Never store drag position in content coordinates. Always derive from window coordinates each frame.

That single principle prevents the majority of drag bugs.
