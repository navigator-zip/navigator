# Engineering Guide: Fixing Mouse-Up Loss During Autoscroll in ReorderableList

## Objective

Fix the bug where a dragged row cannot be dropped after autoscroll begins, especially when the user drags farther down the list and releases the mouse while autoscroll is active.

This guide covers:

- root cause analysis
- required architectural fixes
- concrete implementation plan
- suggested code structure changes
- test plan
- debugging guidance
- follow-up hardening improvements

The goal is to preserve the existing architecture, not rewrite the component from scratch.

## 1. Problem Summary

### Observed bug

When the user drags an item near the top or bottom autoscroll zone and the list begins scrolling automatically:

- the dragged overlay continues following the pointer
- destination updates continue
- but releasing the mouse does not always end the drag
- the item can remain "stuck" in drag state and cannot be dropped normally

This is most visible when dragging farther down the list while autoscroll is running.

### Current behavior pattern

The existing system uses two different input models during a drag:

#### Drag start and ordinary drag updates

These are initiated through the view-level handlers:

- `handleMouseDown(locationInSelf:)`
- `handleMouseDragged(locationInSelf:locationInWindow:)`
- `handleMouseUp(locationInSelf:)`

#### Autoscroll-time drag updates

Once autoscroll becomes active, the runtime effectively transitions to timer-driven updates:

- `ReorderTableFrameDriver` fires repeatedly
- `ReorderableListDragRuntime.tick()` runs
- pointer position may be refreshed using `mouseLocationOutsideOfEventStream`
- `prefersLiveWindowPointer = true` is enabled during autoscroll

This means the drag movement loop stops depending purely on normal delivered drag events.

### But drag completion does not change

The drag still ends only when:

- `handleMouseUp(locationInSelf:)` is called

That means the drag can continue to update globally-ish, but completion still depends on local view event delivery.

## 2. Root Cause

### Core issue

The bug is caused by an input model mismatch:

- movement becomes timer-driven and can use live window pointer state
- completion still depends on the original view reliably receiving `mouseUp`

Once autoscroll begins, that assumption is no longer safe.

Depending on timing, scroll position, window routing, first responder state, tracking changes, or overlay/view hierarchy interactions, the original host view may not reliably receive the final mouse-up event through the same path that started the drag.

### Why this becomes visible specifically during autoscroll

Autoscroll changes the interaction from:

`the user is dragging inside a stable local view interaction stream`

to:

`the system is advancing drag state on a timer while the document scrolls and pointer position is reconstructed from window-level state`

That is a more global interaction loop.

If the architecture supports global-ish drag updates but not global-ish drag termination, the drag can be left hanging.

## 3. Fix Strategy Overview

### Primary fix

While a drag is active, install event monitors that allow the controller to observe:

- `leftMouseUp`
- optionally `leftMouseDragged`

This gives the drag controller a reliable fallback for drag completion even when the original host view does not receive the final `mouseUp`.

### Secondary fix

Unify drag completion into one path so there is exactly one way to end a drag, regardless of whether the trigger came from:

- the host view's normal `mouseUp`
- a local event monitor
- future global monitor fallback

### Tertiary fix

Clean up sticky runtime state around live pointer usage:

- currently `prefersLiveWindowPointer` is turned on during autoscroll
- it is not always turned off when autoscroll stops
- this creates a confusing state machine and can cause future maintenance/debugging problems

### Optional robustness improvement

Add a drag-session-level input ownership model so all drag events during an active drag are explicitly handled at the controller/runtime level rather than partially through local view delivery and partially through timer-driven runtime logic.

That is optional for this pass, but the code should move in that direction.

## 4. Desired End State

After the fix:

- drag starts from normal view-level mouse input
- once dragging begins, the controller owns termination robustly
- autoscroll may run continuously
- the user can release anywhere that still produces a mouse-up event in the app event stream
- drag ends immediately and settles correctly
- drag state never remains stuck because the host view missed a local `mouseUp`

## 5. Required Implementation Changes

### 5.1 Extend `ReorderableListEventMonitoring`

The current abstraction already supports key-down monitoring for Escape. Expand it to support mouse monitors.

Required additions:

- local left mouse up monitor
- local left mouse dragged monitor

Depending on current implementation patterns, use closures similar to the existing Escape monitor support.

Recommended interface:

```swift
struct ReorderableListEventMonitoring {
	var addLocalKeyDownMonitor: (@escaping (NSEvent) -> NSEvent?) -> Any?
	var addLocalLeftMouseUpMonitor: (@escaping (NSEvent) -> NSEvent?) -> Any?
	var addLocalLeftMouseDraggedMonitor: (@escaping (NSEvent) -> NSEvent?) -> Any?
	var removeMonitor: (Any) -> Void
}
```

Live implementation:

```swift
extension ReorderableListEventMonitoring {
	static let live = ReorderableListEventMonitoring(
		addLocalKeyDownMonitor: { handler in
			NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: handler)
		},
		addLocalLeftMouseUpMonitor: { handler in
			NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp, handler: handler)
		},
		addLocalLeftMouseDraggedMonitor: { handler in
			NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged, handler: handler)
		},
		removeMonitor: { monitor in
			NSEvent.removeMonitor(monitor)
		}
	)
}
```

Why both `mouseUp` and `mouseDragged`?

#### `leftMouseUp`

This is the essential fix. It closes the bug.

#### `leftMouseDragged`

This is optional but strongly recommended. It provides a fallback path so the controller can continue receiving drag movement events even if the host view stops seeing them directly.

This reduces future drift between:

- normal drag movement path
- autoscroll movement path
- monitor-based fallback path

### 5.2 Add monitor storage to `ReorderableListController`

Add fields:

- `private var dragMouseUpMonitor: Any?`
- `private var dragMouseDraggedMonitor: Any?`

These belong near the existing:

- `dragEscapeMonitor`
- observer state flags

### 5.3 Install mouse monitors when drag begins

The controller already uses `installCancellationObservers()` at drag start. Expand this method so that active drag monitoring includes:

- Escape key monitoring
- mouse-up monitoring
- optionally mouse-dragged monitoring
- window/app cancellation notifications

Recommended behavior:

- These monitors should exist only while the component is actively dragging.
- Do not install them while idle or press-armed.

That keeps interaction localized and avoids side effects.

### 5.4 Remove monitors at drag end or cancellation

Expand `removeCancellationObservers()` so it removes:

- Escape monitor
- mouse-up monitor
- mouse-dragged monitor
- existing notification observers

This must happen in all drag termination paths, including:

- normal drop
- Escape cancellation
- window resign key
- application resign active
- view/window teardown
- forced cancellation due to item removal

Failure to remove them consistently can cause duplicate events, leaks, or stale state interactions.

## 6. Introduce a Unified Drag Completion Path

### Current issue

Right now drag completion logic is entered from multiple places, but the conceptual path is not fully unified.

Today:

- `handleMouseUp(locationInSelf:)` calls `finishDrag(cancelled: false, finalLocationInSelf: locationInSelf)`
- monitor path does not yet exist
- future fallback paths would likely duplicate this logic

That is fragile.

### Required change

Create a single private helper responsible for ending an active drag from a resolved pointer location.

Recommended helper:

```swift
private func endActiveDrag(at locationInSelf: CGPoint?) -> Bool {
	guard dragController.isDragging else { return false }
	finishDrag(cancelled: false, finalLocationInSelf: locationInSelf)
	return true
}
```

Then update `handleMouseUp`:

```swift
func handleMouseUp(locationInSelf: CGPoint? = nil) -> Bool {
	if endActiveDrag(at: locationInSelf) {
		return true
	}

	let hadPendingPress = dragController.hasPendingPress
	cancelPendingPressActivation(clearPendingPress: true)
	return hadPendingPress
}
```

Then use the same path from the monitor.

This ensures there is exactly one semantic route for a successful drop.

Benefits:

- less duplicated drag-ending logic
- easier testing
- easier future extension
- lower risk of one path forgetting to clean up state

## 7. Add Mouse-Up Monitor Handler

Recommended implementation:

```swift
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
```

Notes:

### Returning `nil`

Returning `nil` consumes the event from the local monitor path. That is usually appropriate once the drag controller has handled the drop.

However, the engineer should validate whether consuming the event causes any undesired side effects elsewhere in your host hierarchy. If there is a reason to allow the event to continue, return `event` instead, but only if that does not cause duplicate drop handling.

### Use event location, not live pointer fallback

For the actual drop event, use the event's `locationInWindow`. That is the most precise and deterministic location for computing the final destination.

Do not rely on `mouseLocationOutsideOfEventStream` for drop completion if you have the actual up event.

## 8. Add Mouse-Dragged Monitor Handler

This is optional but recommended.

Recommended implementation:

```swift
private func handleDragMouseDraggedMonitorEvent(_ event: NSEvent) -> NSEvent? {
	guard dragController.isDragging else { return event }

	let locationInWindow = event.locationInWindow
	dragRuntime.updatePointerLocation(locationInWindow)
	_ = dragRuntime.tickForTesting()
	dragRuntime.requestFrame()

	return nil
}
```

Why this helps:

If the host view stops receiving `mouseDragged` consistently during autoscroll or near view boundary changes, the controller still updates pointer state and drag visuals.

This makes the entire drag interaction more self-contained and less dependent on a specific local responder chain staying perfectly intact.

Caveat:

If both the host view and the local monitor handle every drag event, you must ensure this does not produce harmful double-updates.

In most cases, duplicate drag updates are tolerable if they are idempotent and merely overwrite the latest pointer location. But the engineer should verify:

- no duplicate side effects
- no extra metrics inflation that matters
- no repeated work causing visible stutter

If duplicate updates are undesirable, use the monitor only as a fallback for drag continuation and keep the host view as the primary path.

## 9. Update `installCancellationObservers()`

### Existing responsibility

This method already installs:

- Escape key monitor
- window resign notification
- application resign notification

### New responsibility

Also install:

- mouse-up monitor
- optionally mouse-dragged monitor

Recommended version:

```swift
private func installCancellationObservers() {
	removeCancellationObservers()

	dragEscapeMonitor = eventMonitoring.addLocalKeyDownMonitor { [weak self] event in
		guard let self else { return event }
		return self.handleDragEscapeMonitorEvent(event)
	}

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
```

## 10. Update `removeCancellationObservers()`

### Required behavior

This method must now remove mouse monitors too.

Recommended version:

```swift
private func removeCancellationObservers() {
	if let dragEscapeMonitor {
		eventMonitoring.removeMonitor(dragEscapeMonitor)
		self.dragEscapeMonitor = nil
	}

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
```

## 11. Fix Sticky `prefersLiveWindowPointer` State

### Current issue

In `ReorderableListDragRuntime.tick(allowAutoscroll:)`, when autoscroll becomes active:

- `isAutoscrollActive = true`
- `prefersLiveWindowPointer = true`

But when the pointer leaves the autoscroll edge zone:

```swift
else {
	isAutoscrollActive = false
}
```

This leaves `prefersLiveWindowPointer` sticky.

That may not be the direct cause of the drop bug, but it creates a confusing runtime state where the drag remains in a "prefer live pointer" mode even though autoscroll is no longer active.

### Required improvement

When the pointer is no longer in the autoscroll zone, explicitly reset the mode unless there is a deliberate design reason not to.

Recommended change:

```swift
else {
	isAutoscrollActive = false
	prefersLiveWindowPointer = false
}
```

If you intentionally want it to remain true, then document that choice with a comment and rename the state to something clearer, for example:

- `hasEnteredAutoscrollDrivenTracking`
- `preferWindowLevelPointerForRemainderOfDrag`

As written, the current variable name implies a transient preference, not a sticky permanent mode.

## 12. Optional Improvement: Make Runtime Pointer Source Explicit

This is not mandatory for the first fix, but it is a good cleanup.

### Current behavior

The runtime chooses the pointer source using:

- stored pointer location
- live window pointer fallback
- `prefersLiveWindowPointer`

This works, but it is somewhat implicit.

### Recommended future direction

Replace the boolean with an explicit source mode:

```swift
enum PointerTrackingMode {
	case deliveredEventsPreferred
	case liveWindowPointerPreferred
}
```

Then make transitions explicit:

- start drag -> delivered events preferred
- enter autoscroll -> live window pointer preferred
- exit autoscroll -> delivered events preferred

This makes the runtime state machine easier to reason about and easier to test.

Not necessary for this patch, but worth doing if the engineer is already touching runtime logic.

## 13. Optional Improvement: Separate "Drag Cancellation Observers" from "Drag Event Monitors"

Today `installCancellationObservers()` is doing more than cancellation if you add `mouseUp` and `mouseDragged`.

That naming becomes slightly misleading.

### Better structure

Consider splitting into:

- `installDragEventMonitors()`
- `removeDragEventMonitors()`
- `installCancellationObservers()`
- `removeCancellationObservers()`

Or rename the existing methods to something like:

- `installActiveDragObservers()`
- `removeActiveDragObservers()`

This is cleaner long term.

For a minimal patch, keeping the existing method names is acceptable. But if the engineer refactors, the broader name is more accurate.

## 14. Changes to Drag Completion Semantics

### Current flow

`finishDrag(cancelled:resetImmediately:finalLocationInSelf:)`:

- finalizes drag state in `dragController`
- settles runtime
- computes destination
- updates display order
- moves table row
- triggers callbacks
- animates overlay back to resting frame
- schedules settlement cleanup

This overall flow is fine.

### Important rule after the patch

There must be no code path where:

- the drag is visually active
- autoscroll is running or has run
- mouse-up has happened
- but `finishDrag` never runs

That is the invariant this patch is restoring.

## 15. Testing Plan

A fix like this needs more than one manual test. It should be covered at three levels:

- unit-ish/controller tests
- runtime behavior tests
- manual QA scenarios

### 15.1 Automated tests to add

#### A. Drag can end through monitor path during autoscroll

Create a test that simulates:

- drag begins
- autoscroll becomes active
- controller receives no direct host-view `handleMouseUp`
- local mouse-up monitor handler fires
- drag completes
- settlement occurs
- live row is restored
- placeholder and drop indicator are hidden

Assertions:

- `dragController.isDragging == false` after completion path
- reorder interaction finishes
- drag visual tears down after settlement
- no stuck drag state remains

#### B. Monitor path uses final event location

Simulate:

- active drag with autoscroll
- session proposed index differs from final actual mouse-up position
- mouse-up event occurs at a specific `locationInWindow`
- final destination resolves from that location

Assertion:

- final insertion index uses event location, not stale pointer state

#### C. No leaked monitors after drag completion

Test:

- start drag
- install monitors
- drop
- monitors removed

Then start a second drag and verify only one set of monitor callbacks is active.

#### D. Escape cancellation still works

Ensure the addition of mouse monitors does not break existing Escape behavior.

#### E. Window resign / app resign still cancels cleanly

Verify those existing paths still cancel and do not leave monitors installed.

#### F. `prefersLiveWindowPointer` resets when autoscroll stops

Add runtime test coverage for:

- edge zone entered -> `true`
- edge zone exited -> `false`

if you adopt the recommended reset behavior.

### 15.2 Manual QA checklist

#### Basic drag without autoscroll

- drag and drop within visible rows
- verify no regressions

#### Drag downward into bottom autoscroll zone

- drag item near bottom
- allow autoscroll to continue several seconds
- release mouse while scrolling
- verify immediate drop

#### Drag upward into top autoscroll zone

- same as above, upward direction

#### Re-enter center after autoscroll

- start autoscrolling at bottom
- drag pointer back into center
- release
- verify correct drop
- verify overlay is not stuck
- verify destination matches visible location

#### Quick release during autoscroll

- drag to edge
- let one or two autoscroll ticks occur
- release quickly
- verify drag ends every time

#### Release outside original row region

- start drag on one row
- continue drag far from original region
- release
- verify drop still completes

#### Cancel with Escape during autoscroll

- drag into edge autoscroll
- press Escape
- verify cancellation and restore

#### App/window focus changes during drag

- start drag
- move or click to trigger app/window resignation scenario if relevant
- verify cancellation remains clean

## 16. Debug Instrumentation Recommendations

To validate the fix during development, add temporary structured logging around drag input ownership.

Log points to add temporarily:

### Drag start

Log:

- item ID
- source index
- monitor installation success

### Mouse-up receipt

Log whether the drop came from:

- host view path
- local monitor path

### Autoscroll activation/deactivation

Log:

- `isAutoscrollActive`
- `prefersLiveWindowPointer`

### Drag completion

Log:

- cancelled or committed
- final destination
- final row
- whether event location was explicit or fallback-derived

This will make it easy to verify that the bug fix is actually exercising the new path.

## 17. Suggested Refactor Order

The engineer should implement in this order:

### Phase 1: Minimal bug fix

- extend `ReorderableListEventMonitoring`
- add mouse monitor storage to controller
- install/remove monitors with active drag
- add unified `endActiveDrag(at:)`
- add mouse-up monitor handler
- verify bug is fixed manually

### Phase 2: Hardening

- add mouse-dragged monitor handler
- reset `prefersLiveWindowPointer` when autoscroll stops
- add automated tests
- add temporary diagnostics

### Phase 3: Cleanup

- rename observer methods if desired
- make runtime pointer tracking mode more explicit if worthwhile

## 18. Code Sketch for the Core Fix

This is not meant to be copied blindly, but it is close to the intended shape.

### Controller storage

```swift
private var dragEscapeMonitor: Any?
private var dragMouseUpMonitor: Any?
private var dragMouseDraggedMonitor: Any?
```

### Unified drop helper

```swift
private func endActiveDrag(at locationInSelf: CGPoint?) -> Bool {
	guard dragController.isDragging else { return false }
	finishDrag(cancelled: false, finalLocationInSelf: locationInSelf)
	return true
}
```

### Updated `handleMouseUp`

```swift
func handleMouseUp(locationInSelf: CGPoint? = nil) -> Bool {
	if endActiveDrag(at: locationInSelf) {
		return true
	}

	let hadPendingPress = dragController.hasPendingPress
	cancelPendingPressActivation(clearPendingPress: true)
	return hadPendingPress
}
```

### Monitor handlers

```swift
private func handleDragMouseUpMonitorEvent(_ event: NSEvent) -> NSEvent? {
	guard dragController.isDragging else { return event }

	let locationInWindow = event.locationInWindow
	let locationInSelf = if let hostView, hostView.window != nil {
		hostView.convert(locationInWindow, from: nil)
	} else {
		locationInWindow
	}

	_ = endActiveDrag(at: locationInSelf)
	return nil
}

private func handleDragMouseDraggedMonitorEvent(_ event: NSEvent) -> NSEvent? {
	guard dragController.isDragging else { return event }

	dragRuntime.updatePointerLocation(event.locationInWindow)
	_ = dragRuntime.tickForTesting()
	dragRuntime.requestFrame()

	return nil
}
```

### Runtime sticky-state fix

```swift
else {
	isAutoscrollActive = false
	prefersLiveWindowPointer = false
}
```

## 19. Risks and What to Watch For

### Risk 1: Duplicate drag updates

If both the host view and the local monitor process drag movement events, drag updates may happen twice.

Usually this is okay if updates are overwrite-only, but verify there is no:

- jitter
- duplicate callback emission
- animation instability
- inflated metrics that affect decisions

### Risk 2: Consuming mouse-up too aggressively

Returning `nil` from the local monitor consumes the event. Ensure this does not break other expected behaviors in the host app.

If it does, the engineer may need to:

- let the event continue, or
- gate monitor consumption more carefully

### Risk 3: Multiple completion paths racing

If both the host view and the monitor can attempt to finish the drag at nearly the same time, the code must remain idempotent.

The current `dragController.isDragging` guard should protect this, but the engineer should validate that double-completion cannot trigger duplicate callbacks or table moves.

### Risk 4: Monitor lifetime bugs

Make absolutely sure monitors are removed on every drag end and cancel path.

Leaked local monitors create extremely confusing bugs later.

## 20. Recommended Acceptance Criteria

This work is complete when all of the following are true:

- a drag can always be dropped successfully after autoscroll begins
- releasing the mouse during bottom-edge autoscroll commits the drop immediately
- releasing during top-edge autoscroll also works
- Escape cancellation still works during autoscroll
- no stuck drag overlay remains after drop or cancel
- no monitor leaks occur across repeated drags
- `prefersLiveWindowPointer` does not remain unintentionally sticky after autoscroll exits
- no visible regressions occur in ordinary non-autoscroll drags

## 21. Final Engineering Recommendation

For this patch, do not attempt a full architectural rewrite. The correct surgical fix is:

- give active drags a monitor-based `mouseUp` fallback
- unify drag completion into one private method
- clean up runtime pointer-mode state
- add tests proving drag completion is no longer dependent on host-view-only `mouseUp`

That should fix the real bug without destabilizing the rest of the component.
