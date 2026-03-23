# ReorderableList Drag Performance Review

## Purpose

This document captures a focused engineering review of the current drag-to-reorder implementation used by the Navigator tab sidebar.

It is intended as a handoff note for engineers who want to improve interaction smoothness, reduce drag latency, and prioritize the highest-return optimizations in the existing AppKit implementation.

## Scope

This review covers the current live drag path in:

- [`BrowserSidebar/Sources/BrowserSidebar/BrowserSidebarView.swift`](/Users/rk/Developer/Navigator/BrowserSidebar/Sources/BrowserSidebar/BrowserSidebarView.swift)
- [`BrowserSidebar/Sources/BrowserSidebar/BrowserSidebarTabRow.swift`](/Users/rk/Developer/Navigator/BrowserSidebar/Sources/BrowserSidebar/BrowserSidebarTabRow.swift)
- [`ReorderableList/Sources/ReorderableList/ReorderableListView.swift`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListView.swift)
- [`ReorderableList/Sources/ReorderableList/ReorderableListController.swift`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListController.swift)
- [`ReorderableList/Sources/ReorderableList/ReorderableListDragController.swift`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListDragController.swift)
- [`ReorderableList/Sources/ReorderableList/ReorderableListGeometry.swift`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListGeometry.swift)
- [`ReorderableList/Sources/ReorderableList/ReorderableListDragVisualController.swift`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListDragVisualController.swift)

This is a static code-path review. It is not an Instruments capture, and the recommendations below should be validated with profiling before or during implementation.

## Current Drag Pipeline

The active tab drag path is:

1. `BrowserSidebarView` constructs a fixed-height `ReorderableListView` for tabs in [`BrowserSidebarView.swift`](/Users/rk/Developer/Navigator/BrowserSidebar/Sources/BrowserSidebar/BrowserSidebarView.swift#L70).
2. `BrowserSidebarTabRow` forwards pointer and keyboard events into the list host in [`BrowserSidebarTabRow.swift`](/Users/rk/Developer/Navigator/BrowserSidebar/Sources/BrowserSidebar/BrowserSidebarTabRow.swift#L309).
3. `ReorderableListView` receives `mouseDown`, `mouseDragged`, `mouseUp`, and `keyDown`, then forwards them to the controller in [`ReorderableListView.swift`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListView.swift#L165).
4. `ReorderableListController.handleMouseDragged` either crosses the drag activation threshold or updates an active session in [`ReorderableListController.swift`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListController.swift#L280).
5. `ReorderableListController.updateDrag` computes the destination index, updates the drop indicator, updates the detached overlay position, and manages autoscroll in [`ReorderableListController.swift`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListController.swift#L924).
6. `ReorderableListController.finishDrag` applies the final order and settles the overlay in [`ReorderableListController.swift`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListController.swift#L1313).

The most performance-sensitive path is:

`handleMouseDragged` -> `updateDrag` -> `ReorderableListGeometry.destinationIndex` -> `dragVisualController.updateDraggedFrame`

## Findings

### 1. Destination index calculation is too expensive for the sidebar use case

`updateDrag` recalculates the destination index on every drag tick in [`ReorderableListController.swift`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListController.swift#L924).

That calculation currently uses [`ReorderableListGeometry.destinationIndex`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListGeometry.swift#L65), which:

- iterates over every candidate destination
- rebuilds reordered indices for each candidate
- maps reordered heights for each candidate
- computes frames for each candidate
- compares the dragged row center against every synthetic layout

This is effectively O(n²) work plus repeated short-lived allocations per mouse-move.

That is especially hard to justify for the tab sidebar because the sidebar uses a fixed row height in [`BrowserSidebarView.swift`](/Users/rk/Developer/Navigator/BrowserSidebar/Sources/BrowserSidebar/BrowserSidebarView.swift#L76), and the geometry layer already has a simpler helper in [`ReorderableListGeometry.fixedHeightInsertionIndex`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListGeometry.swift#L102).

#### Recommendation

Introduce a fast path in `updateDrag`:

- if `configuration.fixedRowHeight` exists, compute insertion index with a fixed-height slot formula
- use the current generic path only for variable-height lists

For variable-height lists, the current implementation should still be replaced later with a prefix-sum plus binary-search approach rather than candidate-layout enumeration.

#### Expected payoff

- lower CPU cost on every drag tick
- fewer allocations during pointer movement
- smoother drag on large tab sets and high-refresh-rate displays

### 2. The controller performs repeated linear ID lookups in hot paths

The controller resolves IDs repeatedly with:

- [`modelIndex(for:)`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListController.swift#L697)
- [`row(for:)`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListController.swift#L701)

Both are linear scans over arrays. Those helpers are used throughout drag start, drag update, drag finish, selection synchronization, row lookup, and visual cleanup.

This means the live drag path is paying extra O(n) work even before considering the destination-index algorithm.

#### Recommendation

Maintain index maps alongside `rows` and `displayOrder`:

- `modelIndexByID: [ID: Int]`
- `displayRowByID: [ID: Int]`

Refresh them whenever `rows` or `displayOrder` changes.

#### Expected payoff

- lower constant overhead across all drag phases
- simpler reasoning about row and model lookup cost
- better scaling as tab counts grow

### 3. The drag path still sweeps visible rows for displacement that is always zero

When the proposed destination changes, `updateDrag` calls [`clearVisibleDisplacement`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListController.swift#L1239) in [`ReorderableListController.swift`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListController.swift#L947).

That sweep walks visible rows and applies a displacement offset of `0` to every container.

At the same time, [`applyCurrentDisplacement`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListController.swift#L730) has already been simplified to keep all live rows stationary during drag:

> the overlay, placeholder, and drop indicator provide the preview instead of shifting live rows under the pointer

The net effect is that the controller is paying for a visible-row iteration that currently has no user-facing effect.

#### Recommendation

Remove the displacement reset from the live drag update path while displacement remains intentionally disabled.

Keep the helper only if it is still needed for teardown or for a future return of visible-row displacement.

#### Expected payoff

- fewer visible-row iterations during drag
- less redundant view mutation
- less animation/setup churn on repeated insertion-index changes

### 4. Autoscroll can trigger cell realization and layout during an active drag

Autoscroll ticks are driven by a timer in [`ReorderableListController.swift`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListController.swift#L1045), using a 120 Hz interval defined in [`ReorderableListController.swift`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListController.swift#L7).

On each tick, [`handleAutoscrollTick`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListController.swift#L996):

- scrolls the clip view
- calls `ensureVisibleRowsLoaded()`
- then calls `updateDrag(...)` again

`ensureVisibleRowsLoaded()` in [`ReorderableListController.swift`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListController.swift#L1465) may create missing row views, and row creation can force layout and height measurement in [`ReorderableListController.swift`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListController.swift#L380).

This is likely to cause hitching during long drags near the edges of a large list.

#### Recommendation

Reduce drag-time realization work:

- avoid unconditional `ensureVisibleRowsLoaded()` on every autoscroll tick
- consider realizing only the newly exposed edge rows
- keep autoscroll on `.common` run loop mode, but reconsider whether 120 Hz is materially better than a lower callback rate for this UI

#### Expected payoff

- fewer drag hitches while autoscrolling
- lower layout churn during prolonged reorders

### 5. Drag start pays a synchronous bitmap snapshot cost

The drag session does not begin unless the controller can create a snapshot image in [`ReorderableListController.swift`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListController.swift#L874).

That snapshot is created with:

- `bitmapImageRepForCachingDisplay`
- `cacheDisplay`

in [`makeSnapshotImage(from:)`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListController.swift#L1514).

This work happens on the main thread at the exact moment the user expects the row to lift.

#### Recommendation

Profile first, but likely options are:

- reuse a lightweight view-backed overlay instead of bitmap capture
- cache recent drag previews if the row content is stable enough
- defer or simplify some of the visual polish applied at lift time

The right choice depends on whether the lag is CPU rasterization, layer setup, or both.

#### Expected payoff

- faster perceived drag start
- lower lift latency on complex row content

### 6. The overlay update path rebuilds shape and shadow paths on every move

`updateDraggedFrame` in [`ReorderableListDragVisualController.swift`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListDragVisualController.swift#L135) updates layer bounds and then calls `updateShapePath()`.

[`updateShapePath()`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListDragVisualController.swift#L396) rebuilds:

- the background frame
- the rounded border path
- the overlay shadow path

on every drag-frame update.

For the tab sidebar, the dragged row size is usually stable during the entire gesture. If only the position changed, rebuilding paths is unnecessary.

#### Recommendation

Split overlay updates into:

- position-only updates for normal drag motion
- bounds/path updates only when size or appearance actually changes

This can be done by tracking the last applied size and skipping `updateShapePath()` unless the bounds changed.

#### Expected payoff

- lower per-frame Core Animation work
- fewer CGPath allocations during drag

### 7. The sidebar retains one row view per tab, reducing effective reuse

`BrowserSidebarView` caches `BrowserSidebarTabRow` instances by tab ID in [`BrowserSidebarView.swift`](/Users/rk/Developer/Navigator/BrowserSidebar/Sources/BrowserSidebar/BrowserSidebarView.swift#L398).

That may be intentional to preserve row-specific state, but it also means row content is not benefiting from normal table reuse as much as it could.

This is not necessarily the first optimization to implement, but it should stay on the list if the sidebar needs to scale to much larger tab counts.

#### Recommendation

Evaluate whether the cached row map is still necessary.

If it is not:

- let `NSTableView` and `ReorderableListItemContainerView` own more of the reuse story

If it is necessary:

- document the state that requires retention
- keep the cache bounded and cheap to refresh

#### Expected payoff

- lower memory growth with many tabs
- reduced view churn and layout complexity over time

### 8. Existing performance metrics are not yet strong enough for optimization work

The package already has `ReorderPerformanceMetrics` in [`ReorderableListTypes.swift`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListTypes.swift#L34), but the current reporting is incomplete and at least one metric reset is misleading.

For example, `dragPreviewCreations` is incremented in [`ReorderableListController.swift`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListController.swift#L913) and then the whole metrics struct is reset immediately afterward in [`ReorderableListController.swift`](/Users/rk/Developer/Navigator/ReorderableList/Sources/ReorderableList/ReorderableListController.swift#L916).

Without reliable counters or signposts, optimization work will be harder to validate.

#### Recommendation

Before broad tuning:

- fix `ReorderPerformanceMetrics` so counters survive a single drag session
- add drag-session scoped timing
- add signposts around lift, update, autoscroll, and settle

#### Expected payoff

- clearer measurement before and after each change
- faster iteration on the highest-value performance fixes

## Priority Order

Recommended implementation order:

1. Add a fixed-height destination fast path for the tab sidebar.
2. Add `ID -> index` caches for model and display order.
3. Remove the dead displacement sweep from the live drag path.
4. Reduce overlay path rebuilding to bounds changes only.
5. Reduce autoscroll-triggered view realization and layout.
6. Profile and revisit drag-preview snapshotting.
7. Reevaluate the tab-row cache if large-tab-count performance still matters.
8. Improve instrumentation so later changes are measurable rather than anecdotal.

## Validation Plan

Before and after each optimization, measure:

- drag start latency from threshold crossing to visible lift
- average and worst-case drag update cost
- autoscroll smoothness near list edges
- CPU usage during rapid pointer movement
- allocations during long drags

Recommended tooling:

- Instruments Time Profiler
- Instruments Core Animation
- Allocations
- `os_signpost` around drag begin, destination recompute, autoscroll tick, and settle

## Suggested First Change

If only one performance improvement is implemented first, it should be the fixed-height destination fast path.

Reason:

- it is the most obvious hot-path inefficiency in the current code
- the sidebar already satisfies the precondition for the optimization
- it reduces work on every drag update instead of only on drag start or finish
- it does not require a large architectural rewrite

## Notes

This document is intentionally limited to the current implementation. It complements, but does not replace:

- [`docs/appkit/high-performance-reorderable-table-implementation-plan.md`](/Users/rk/Developer/Navigator/docs/appkit/high-performance-reorderable-table-implementation-plan.md)
- [`docs/appkit/reorderable-list-appkit-engineering-guide.md`](/Users/rk/Developer/Navigator/docs/appkit/reorderable-list-appkit-engineering-guide.md)

Those documents are broader architectural guides. This document is a targeted review of the code that is shipping today.
