# High-Performance Reorderable AppKit Table Implementation Plan

> Historical note: the proposed `ReorderableTable*` API described below was removed from the codebase on March 9, 2026 after the app continued to ship only `ReorderableListView`. Treat this document as an abandoned implementation plan, not the current package surface.

## Purpose

This document turns the reorderable AppKit table brief into a concrete implementation handoff for Navigator.

The goal is to ship a reusable `NSTableView`-backed component that:

- keeps pointer-driven row reordering smooth at 60fps, with a 120fps target on capable displays
- supports a detached dragged-row overlay with configurable transforms
- handles large lists cleanly
- keeps row height fixed and non-negotiable in V1
- minimizes view churn, layout churn, and structural table mutation during drag

This plan is intentionally grounded in the current Navigator codebase rather than assuming a greenfield implementation.

## Repo Fit

Navigator already has a dedicated local Swift package for reorderable AppKit lists:

- [`ReorderableList/Package.swift`](/Users/rk/Developer/Navigator/ReorderableList/Package.swift)
- [`ReorderableList/Sources/ReorderableList/ReorderableListView.swift`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListView.swift)
- [`ReorderableList/Sources/ReorderableList/ReorderableListController.swift`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListController.swift)
- [`BrowserSidebar/Sources/BrowserSidebar/BrowserSidebarView.swift`](/Users/rk/Developer/Navigator/BrowserSidebar/Sources/BrowserSidebar/BrowserSidebarView.swift)

`BrowserSidebar` already consumes that package with a fixed row height of `40` points, so the shortest path to production is to evolve `ReorderableList` in place instead of creating a brand-new package and migrating consumers later.

## Recommendation

Implement this as `ReorderableList` V2 inside the existing `ReorderableList` package.

Recommended product shape:

- keep the package name `ReorderableList` to avoid package and project churn
- add a new V2 core type named `ReorderableTableView<Item, ID>`
- keep `ReorderableListView<Item, ID>` temporarily as a thin compatibility wrapper or deprecated adapter over the new core
- migrate `BrowserSidebar` to the new API once the V2 path is stable

This avoids a wide rename through `Navigator.xcodeproj` while still landing the clearer `ReorderableTable*` type family described in the brief.

## Core Invariant

During an active reorder gesture:

- `NSTableView` row structure does not change
- the dragged row is rendered as a detached overlay
- reorder feedback comes from translating visible row content wrappers only
- the underlying data model commits exactly once at drag end

Every implementation choice in V2 must reinforce that invariant.

## Current State In Navigator

The current package is close enough to reuse, but it does not yet match the required invariant.

### Existing strengths

- The component is already AppKit-first and `NSTableView`-backed in [`ReorderableListView.swift`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListView.swift#L16).
- Dragging already uses a detached proxy view path in [`ReorderableListController.swift`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListController.swift#L23) and [`ReorderableListController.swift`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListController.swift#L820).
- There is already a pure geometry helper file in [`ReorderableListGeometry.swift`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListGeometry.swift#L3).
- `BrowserSidebar` is already using the fixed-row-height path in [`BrowserSidebarView.swift`](/Users/rk/Developer/Navigator/BrowserSidebar/Sources/BrowserSidebar/BrowserSidebarView.swift#L70).

### Current mismatches to fix

- The package still supports variable row heights through measurement and invalidation paths in [`ReorderableListController.swift`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListController.swift#L71) and [`ReorderableListController.swift`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListController.swift#L204). V1 should remove that complexity from the active reorder path.
- Destination calculation currently evaluates candidate full-table reorder layouts in [`ReorderableListGeometry.swift`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListGeometry.swift#L65), which is heavier than the slot-based fixed-height math required here.
- The current finish path mutates `displayOrder` and calls `tableView.moveRow(at:to:)` in [`ReorderableListController.swift`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListController.swift#L889), which is acceptable at drop time but must never occur during live drag.
- The container view currently animates alpha and transforms on the row container itself in [`ReorderableListItemContainerView.swift`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListItemContainerView.swift#L122). V2 needs a dedicated inner content wrapper so row geometry stays inert.

## Scope

### V1 includes

- single-row reordering within one table
- fixed row height only
- direct mouse-driven reordering
- detached drag preview overlay
- visible-row displacement
- one final commit on drag end
- autoscroll near top and bottom edges
- configurable drag-preview transforms
- accessibility announcements
- keyboard reorder fallback

### V1 excludes

- cross-table reordering
- pasteboard integration
- multi-row reordering
- variable row heights
- section or group rows
- live structural row mutation during drag
- floating drag windows outside the component window
- rich interactive controls inside the detached drag preview

## Package Placement

Implementation home:

- `ReorderableList`

Primary consumer for first integration:

- `BrowserSidebar`

Do not create a new top-level package for V1 unless `ReorderableList` proves unsalvageable during implementation. The existing package is already the correct boundary for reusable AppKit list behavior in this repo.

## Target Public API

Add a new public surface in the existing package:

```swift
@MainActor
public final class ReorderableTableView<Item, ID: Hashable>: NSView {
	public typealias CanMove = (Item) -> Bool
	public typealias MoveHandler = (_ from: Int, _ to: Int) -> Void
	public typealias MoveLifecycleHandler = (_ id: ID, _ index: Int) -> Void
	public typealias MoveUpdateHandler = (_ source: Int, _ destination: Int) -> Void
	public typealias RowContentBuilder = (_ item: Item) -> NSView

	public init(
		items: [Item],
		id: KeyPath<Item, ID>,
		rowHeight: CGFloat,
		configuration: ReorderConfiguration<Item, ID>,
		contentBuilder: @escaping RowContentBuilder
	)

	public var items: [Item] { get set }
	public var canMove: CanMove?
	public var onMove: MoveHandler?
	public var onMoveStart: MoveLifecycleHandler?
	public var onMoveUpdate: MoveUpdateHandler?
	public var onMoveEnd: MoveHandler?
}
```

Compatibility plan:

- keep `ReorderableListView` during migration
- implement it as a thin adapter onto `ReorderableTableView`
- preserve the existing `onMove(IndexSet, Int)` shape only at the adapter boundary
- move new work to `from/to` integer semantics internally

## Proposed Internal Type Layout

Add or rename toward the following structure inside `ReorderableList/Sources/ReorderableList/`:

- `ReorderableTableView.swift`
- `ReorderableTableController.swift`
- `ReorderDragSession.swift`
- `ReorderInteractionState.swift`
- `ReorderLayoutState.swift`
- `ReorderGeometry.swift`
- `ReorderConfiguration.swift`
- `ReorderDragAppearance.swift`
- `ReorderPerformanceMetrics.swift`
- `ReorderAutoscrollController.swift`
- `ReorderOverlayContainerView.swift`
- `ReorderableTableRowView.swift`
- `ReorderableTableCellView.swift`
- `ReorderAccessibilityCoordinator.swift`
- `ReorderInstrumentation.swift`

Files to retire or reduce to V2 wrappers:

- `ReorderableListView.swift`
- `ReorderableListController.swift`
- `ReorderableListGeometry.swift`
- `ReorderableListItemContainerView.swift`

The old names can remain temporarily while code moves, but the end state should converge on `ReorderTable*` naming for new internals.

## File-Level Responsibilities

### `ReorderableTableView.swift`

Responsibilities:

- own the scroll view, table view, and overlay container hierarchy
- expose the public API
- be the single responder entry point for `mouseDown`, `mouseDragged`, `mouseUp`, `cancelOperation(_:)`, and keyboard reorder commands
- forward all drag work into the controller

### `ReorderableTableController.swift`

Responsibilities:

- own committed order and transient reorder state
- implement the explicit interaction state machine
- coordinate row configuration, visible-row updates, overlay movement, autoscroll, final commit, cancellation, and external-update queuing

### `ReorderDragSession.swift`

Responsibilities:

- hold drag-only state keyed by stable identity
- store source index, proposed insertion index, pointer offset, initial row frame, current document-space drag location, and overlay view

### `ReorderLayoutState.swift`

Responsibilities:

- capture transient layout inputs needed to render visible displacement
- track previous and current insertion index
- compute union-of-affected-visible-rows for minimal updates

### `ReorderGeometry.swift`

Pure helpers only:

- insertion slot calculation
- affected range calculation
- per-row displacement mapping
- final committed order generation
- visible row intersection logic

No AppKit APIs should be required in this file.

### `ReorderOverlayContainerView.swift`

Responsibilities:

- host the detached drag preview above the scroll view
- remain layer-backed
- apply preview appearance transforms only to the detached overlay

### `ReorderableTableRowView.swift`

Responsibilities:

- subclass `NSTableRowView`
- host a dedicated `contentWrapperView`
- keep row geometry stable
- support source suppression, placeholder styling, and reset-on-reuse

### `ReorderableTableCellView.swift`

Responsibilities:

- own the row content root mounted inside the row view wrapper
- handle content reuse without recreating the entire row view hierarchy when avoidable
- wire optional event-forwarding or drag-handle routing

### `ReorderAutoscrollController.swift`

Responsibilities:

- own edge-zone detection and timer/display-link lifecycle
- tick scrolling independent of mouse event frequency
- call back into the table controller with canonical document-space updates

### `ReorderAccessibilityCoordinator.swift`

Responsibilities:

- announce reorder start, destination changes, completion, and cancellation
- preserve the semantic row anchor rather than exposing the overlay as the primary accessible element
- coordinate keyboard reorder commands with the same callbacks used by mouse-driven reordering

### `ReorderInstrumentation.swift`

Responsibilities:

- centralize signpost names and performance probes
- avoid ad hoc profiling code spread across the controller

## Architectural Rules

### 1. Fixed row height only in V1

The V2 core should reject or not expose variable-height paths in V1.

Concretely:

- `rowHeight` is required in the new public initializer
- the V2 controller does not measure cells
- there is no `noteHeightOfRows` path
- there is no row-height invalidation path in the drag lifecycle

### 2. Stable identity over positional bookkeeping

Internal state should track:

- `itemsByID: [ID: Item]`
- `orderedIDs: [ID]`
- `baseOrderedIDs: [ID]`
- `draggedID: ID?`
- `sourceIndex: Int?`
- `proposedInsertionIndex: Int?`
- `queuedStructuralUpdate: QueuedExternalUpdate<Item, ID>?`

Position must always be derived. Identity is the source of truth.

### 3. Transient rendering state must be separate from committed model state

During drag:

- committed order remains in `baseOrderedIDs`
- visible displacement is derived from `proposedInsertionIndex`
- only the overlay and visible wrappers move
- `items` and `orderedIDs` commit once on drag end

### 4. One canonical coordinate path

The implementation must converge on these methods:

- `localPointInContainer(from:)`
- `dragLocationInDocumentSpace(from:)`
- `overlayOriginY(for:)`
- `proposedInsertionIndex(for:)`

No alternate coordinate conversions should be added elsewhere in rows, cell views, or autoscroll helpers.

### 5. Row geometry stays inert during drag

Only `contentWrapperView` may be translated for displacement.

Do not:

- translate `NSTableRowView` itself
- reparent the live row into the overlay
- animate selection or hit-test roots during drag

## Concrete Implementation Plan

### Phase 1: Introduce V2 pure reorder engine

Add new pure helpers in `ReorderGeometry.swift`:

- `proposedInsertionIndex(for:rowHeight:itemCount:)`
- `affectedRange(sourceIndex:insertionIndex:)`
- `displacementOffsetForRow(rowIndex:sourceIndex:insertionIndex:rowHeight:)`
- `committedOrder(afterMoving:from:to:)`
- optional hysteresis helpers for boundary flicker control

Acceptance criteria:

- no AppKit dependency
- unit tests cover top clamp, bottom clamp, same-slot behavior, upward moves, downward moves, and final commit order
- destination calculation is O(1) for fixed-height rows

### Phase 2: Add inert V2 row architecture

Replace the current container-centric transform approach with:

- `ReorderableTableRowView`
- inner `contentWrapperView`
- a cell/root content host that can swap mounted content without rebuilding the row shell

Acceptance criteria:

- row shell stays stable through reuse
- wrapper translation does not break selection drawing
- row reuse resets suppression, alpha, transforms, and highlight state

### Phase 3: Build the new table shell and controller

Implement:

- `ReorderableTableView`
- `ReorderableTableController`
- explicit `ReorderInteractionState`

The controller should support:

- `.idle`
- `.pressed`
- `.dragging`
- `.settling`

Acceptance criteria:

- direct mouse routing works end to end
- a valid press arms a drag without immediately creating an overlay
- non-draggable rows are rejected cleanly

### Phase 4: Overlay-backed drag session

Implement:

- `ReorderDragSession`
- snapshot preview generation as the default mode
- `ReorderOverlayContainerView`
- source row suppression

Default preview mode:

- one snapshot captured at drag start

Optional extension point:

- replica-based preview builder for future advanced consumers

Acceptance criteria:

- overlay follows pointer with no implicit animation
- source row remains in the table but appears suppressed
- no order mutation occurs while dragging

### Phase 5: Visible displacement without structural mutation

Implement the slot-based transient rendering pipeline:

- compute previous and new affected ranges when insertion slot changes
- union those ranges
- intersect with visible rows
- update only visible wrappers whose offset changed

The controller must not call:

- `reloadData()` during drag
- `beginUpdates()/endUpdates()` during drag
- `moveRow(at:to:)` during drag

Acceptance criteria:

- visible rows shift as the insertion slot changes
- offscreen rows do not update during drag
- rows entering the viewport configure to the correct displacement from transient state

### Phase 6: Commit, cancellation, and cleanup

At drag end:

- stop autoscroll
- compute final normalized insertion index
- optionally settle the overlay into its final slot
- commit model order exactly once
- clear transient displacement
- restore source row
- reconcile queued external structural updates

On cancel:

- remove overlay
- clear all displacement
- restore suppression state
- emit no move callback

Acceptance criteria:

- exactly one move callback fires on successful reorder
- no move callback fires on cancel
- no stale overlay, displacement, or suppression remains after either path

### Phase 7: Autoscroll

Add a dedicated autoscroll controller with:

- edge-zone detection based on visible viewport
- a continuous timing source independent of mouse event density
- a configurable speed curve
- canonical overlay and insertion updates during scroll ticks

Default tuning:

- `edgeZoneHeight = min(56, visibleHeight * 0.12)`

Acceptance criteria:

- dragging across long lists works without overlay drift
- entering or leaving edge zones does not jitter
- insertion logic stays synchronized while the clip view scrolls

### Phase 8: Accessibility and keyboard fallback

Add:

- announcement on drag start
- announcement on destination change
- announcement on completion and cancellation
- keyboard move up and move down commands using the same reorder core

Acceptance criteria:

- moved row remains selected after keyboard reorder
- mouse and keyboard paths emit the same external callbacks

### Phase 9: Migration and cleanup

After `ReorderableTableView` is stable:

- migrate `BrowserSidebar` from `ReorderableListView` to the new API
- keep `ReorderableListView` only if another consumer still depends on it
- otherwise collapse the adapter and expose `ReorderableTableView` as the primary API of the package

Acceptance criteria:

- `BrowserSidebar` behavior matches current product expectations
- no duplicated reorder engine remains in the package

## Current-Code Migration Notes

These existing implementation details should not be carried forward unchanged:

- full-table candidate destination scanning in [`ReorderableListGeometry.swift`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListGeometry.swift#L65)
- variable-height measurement inside `tableView(_:viewFor:row:)` and `tableView(_:heightOfRow:)` in [`ReorderableListController.swift`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListController.swift#L174)
- row-container transform ownership in [`ReorderableListItemContainerView.swift`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListItemContainerView.swift#L155)
- reliance on display-order structural movement semantics as the primary live-drag model

These implementation assets are still worth reusing:

- package boundary and dependency footprint in [`ReorderableList/Package.swift`](/Users/rk/Developer/Navigator/ReorderableList/Package.swift)
- existing drag proxy experience as a starting point for the detached overlay path
- existing tests as a seed for the new geometry and interaction coverage
- `BrowserSidebar` as the first concrete integration target

## External Update Policy

V1 must define external-update behavior explicitly.

During drag:

- content updates for existing IDs may apply if they do not change order
- insertions, deletions, and externally initiated reorders must be queued
- if a queued update removes the dragged item, cancel the drag safely

Add an explicit queued-update model rather than ad hoc `queuedItems` replacement.

Recommended shape:

```swift
enum QueuedExternalUpdate<Item, ID: Hashable> {
	case replaceAll(items: [Item])
}
```

If multiple updates arrive during one drag, latest-wins replacement is acceptable for V1.

## Instrumentation Plan

Add signposts around:

- mouse down received
- drag threshold crossed
- drag preview creation
- overlay follow update
- insertion index change
- visible-row displacement update
- autoscroll tick
- final reorder commit
- cancel cleanup

Profile with:

- Time Profiler
- Core Animation
- Allocations
- animation hitch tooling where relevant

## Performance Budgets

Target budgets for V1:

- overlay follow update under `0.5 ms` main-thread work
- insertion slot recomputation under `0.1 ms`
- visible-row displacement update under `1.5 ms`
- preview creation under `4 ms` target and under `8 ms` worst case
- no allocations proportional to full item count during steady-state drag
- no full-table reload during drag
- no full relayout during steady-state pointer follow

These should be treated as ship criteria, not as optional aspirations.

## Test Plan

### Unit tests

Add or migrate tests under:

- `ReorderableList/Tests/ReorderableListTests/`

Cover:

- insertion slot calculation
- affected range calculation
- displacement mapping
- top and bottom clamping
- no-op reorder behavior
- final order generation
- destination normalization

### Integration tests

Extend the package test suite to cover:

- drag begins only from a valid draggable region
- non-draggable items reject drag start
- source row suppression
- boundary crossing updates only the required visible rows
- fast drag movement across many rows
- exactly one commit on drag end
- clean cancellation
- autoscroll up and down
- row reuse during drag
- source row scrolling offscreen during drag
- queued external updates
- dragged item removal causing cancel
- window loss causing cancel

### Accessibility tests

Cover:

- announcement on drag start
- announcement on destination change
- announcement on completion
- announcement on cancellation
- keyboard reorder preserving selection

### Performance tests

Measure at:

- 100 items
- 300 items
- 1000 items

Capture:

- preview creation cost
- overlay follow cost
- insertion change cost
- autoscroll tick cost
- final commit cost
- row reconfiguration count during one drag
- layout pass count during one drag

## BrowserSidebar Integration Plan

First consumer migration target:

- [`BrowserSidebar/Sources/BrowserSidebar/BrowserSidebarView.swift`](/Users/rk/Developer/Navigator/BrowserSidebar/Sources/BrowserSidebar/BrowserSidebarView.swift#L70)

Migration steps:

1. Land `ReorderableTableView` in `ReorderableList`.
2. Keep `BrowserSidebar` on the compatibility wrapper until geometry, overlay, and cleanup behavior are stable.
3. Switch `BrowserSidebar` to the new initializer with explicit `rowHeight`.
4. Verify sidebar-specific row content still forwards events correctly and does not regress tab selection, hover behavior, or favicon rendering.

## Rollout Strategy

Recommended order:

1. Ship pure geometry plus tests.
2. Ship new row-shell architecture behind the existing package.
3. Ship overlay and transient displacement in package tests before migrating the sidebar.
4. Migrate `BrowserSidebar`.
5. Add accessibility, keyboard, autoscroll, instrumentation, and performance verification.

Do not attempt to rewrite the package and migrate `BrowserSidebar` in one large diff.

## Open Decisions For The Implementing Engineer

These should be resolved during implementation kickoff, not deferred until late polish:

- whether drag start is full-row by default or handle-only by default in Navigator product UX
- whether the source row appearance is dimmed, hidden, or placeholder-styled while dragging
- whether V1 should expose preview `rotationRadians` publicly or keep rotation product-controlled
- whether overlay settling at drop should always animate or skip for very short moves
- whether autoscroll should use `CVDisplayLink`-style display sync or a main-thread timer first

The architecture in this plan works with either answer, but the answers should be chosen before row and overlay APIs freeze.

## Handoff Summary

The recommended implementation is not a new package. It is a V2 rewrite inside the existing `ReorderableList` package, with:

- a new `ReorderableTableView<Item, ID>` public core
- fixed-height-only slot-based reorder math
- a detached snapshot overlay
- row-content-wrapper displacement only
- exactly one commit at drag end
- explicit cancellation, autoscroll, accessibility, and instrumentation

That is the most direct path from Navigator's current codebase to the required performance and interaction model.
