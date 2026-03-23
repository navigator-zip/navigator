# Browser Tab Activation Lifecycle Guide

## Purpose

This document defines a tab-activation and browser-lifecycle model for Navigator’s macOS browser shell so rapid tab traversal does not waste CPU, network, and renderer work on pages the user never meaningfully stopped on.

The guide exists because the current architecture already does one useful optimization:

- tabs that have never been selected do not create a browser yet

But after a tab has been selected once, its browser stays alive even when the tab becomes hidden again. During fast keyboard or pointer traversal through many tabs, Navigator can therefore accumulate a large set of hidden live browsers that continue loading and rendering.

This guide defines a better model without breaking legitimate background loading.

## Problem Statement

Navigator must distinguish between two user behaviors that currently look similar at the selection layer but are not the same product intent.

### Intentional background loading

Examples:

- the user enters a URL in a tab and then switches away
- the user waits on a page long enough that it is clearly the chosen tab
- the user scrolls, clicks, or otherwise interacts with the page, then moves on

Expected behavior:

- the page is allowed to keep loading in the background
- the user should be able to return to a meaningful in-progress or completed page load

### Incidental transient activation

Examples:

- the user rapidly arrows through many tabs searching for the right one
- the user scrubs across tabs and only pauses on some of them for a fraction of a second
- the user briefly lands on a tab during fast navigation and immediately leaves

Expected behavior:

- Navigator should avoid creating a full browser if the user never really committed to that tab
- if work was started transiently, Navigator should be allowed to stop or discard it

The feature must optimize the second case without regressing the first.

## Current Behavior

Relevant current implementation points:

- [`BrowserView/Sources/BrowserView/BrowserViewController.swift`](/Users/rk/Developer/Navigator/BrowserView/Sources/BrowserView/BrowserViewController.swift)
- [`BrowserView/Sources/BrowserView/BrowserContainerView.swift`](/Users/rk/Developer/Navigator/BrowserView/Sources/BrowserView/BrowserContainerView.swift)
- [`BrowserView/Sources/BrowserView/BrowserViewTestSeams.swift`](/Users/rk/Developer/Navigator/BrowserView/Sources/BrowserView/BrowserViewTestSeams.swift)
- [`BrowserRuntime/Sources/BrowserRuntime/BrowserRuntime.swift`](/Users/rk/Developer/Navigator/BrowserRuntime/Sources/BrowserRuntime/BrowserRuntime.swift)

Today:

- every tab has a `BrowserContainerView`
- only the selected tab enables browser creation
- selecting a tab calls `createBrowserIfNeeded()`
- once created, a browser remains alive until the tab is removed or the view tears down
- hidden tabs are hidden visually, but their underlying browser is not discarded simply because selection changed

This means the current behavior is:

- good for cold unopened tabs
- weak for previously opened tabs during rapid traversal

## Design Goals

Navigator must:

- preserve normal background loading for tabs the user intentionally opened or interacted with
- avoid expensive browser creation for tabs that are only selected transiently
- provide deterministic rules that are easy to test
- keep the implementation compatible with the existing “tab exists without browser” architecture
- avoid broad hidden side effects in property setters or observers
- remain main-actor-safe for UI-driven state changes

## Non-Goals

This feature is not trying to:

- implement full Chromium tab freezing or renderer suspension
- build a speculative preloading system
- preserve exact in-memory JS/runtime state for every previously touched tab forever
- stop all hidden-tab network activity under every condition
- change session-restore persistence semantics

## Core Model

Navigator should treat tab activation as an intent-sensitive lifecycle instead of a simple selected versus not-selected toggle.

### Lifecycle states

Each tab should conceptually move through these states:

- `cold`
  - the tab has no live browser
  - sidebar state exists
  - URL, title, favicon, and other persisted metadata remain available
- `transientSelected`
  - the tab was selected
  - Navigator has not yet decided this selection is intentional
  - browser creation should be deferred behind a short activation window unless explicit interaction commits immediately
- `committed`
  - the user clearly intended to activate the tab
  - browser creation is allowed immediately
  - if a load starts here, it may continue in the background after deselection
- `discarded`
  - a previously live browser was intentionally released
  - tab metadata remains
  - the next reactivation recreates the browser from stored state

`discarded` behaves like `cold` from the browser-runtime perspective, but keeping it separate in the design is useful because it explains why a once-live tab is allowed to become browser-less again.

`discarded` is only valid for tabs that previously owned a live browser instance.

Lifecycle state describes user-intent policy. Browser existence describes runtime realization. They are related but not identical.

### Transition table

The lifecycle must be implemented from an explicit transition table, not inferred ad hoc from unrelated callbacks.

| Current state | Event | Next state | Required behavior |
| --- | --- | --- | --- |
| `cold` | tab selected | `transientSelected` | start activation session and commit timer |
| `transientSelected` | dwell threshold expires | `committed` | commit activation and create browser if needed |
| `transientSelected` | explicit commit-worthy interaction | `committed` | cancel timer and create browser immediately if needed |
| `transientSelected` | deselect before browser creation | `cold` | cancel timer and pending creation |
| `transientSelected` | deselect after transient browser creation | `discarded` | stop provisional work when possible and discard browser |
| `committed` | deselect | `committed` | remain logically committed, allow background loading, apply budget later |
| `committed` | budget, visibility, or memory-pressure discard | `discarded` | close browser, preserve metadata and restoration state |
| `committed` | renderer crash | `discarded` | tear down crashed browser and preserve reactivation path |
| `discarded` | tab selected | `committed` | recreate immediately if the tab was previously committed |
| any lifecycle state | tab closed | removed | cancel pending work and ignore future callbacks |
| any lifecycle state | window teardown | removed | invalidate window token and tear down owned runtime state |

The implementation may add internal substates, but it must preserve the externally meaningful behavior above.

### Activation state versus navigation state

Activation commitment and navigation commitment are different and must be modeled separately.

Activation commitment means:

- the user clearly intended to use the tab

Navigation commitment means:

- Chromium or CEF committed a document load for that tab

Navigator must not collapse these into one bit of state.

Recommended navigation model:

- `none`
- `provisional`
- `committed`
- `finished`

Where:

- `none` means no live navigation is in progress
- `provisional` means navigation started but document commit has not happened yet
- `committed` means a document commit occurred
- `finished` means the load finished or settled into an idle loaded state

`finished` is an observability and optimization state, not a guarantee that the page has zero further activity. Pages may continue long polling, streaming, lazy loading, or background work after the primary navigation becomes idle.

Recommended policy:

- transient tab plus provisional navigation plus deselection may be discarded aggressively
- committed navigation must be treated as materially more expensive and user-visible than provisional navigation
- committed hidden tabs may still be discarded later under budget, window-visibility, crash, or memory-pressure rules

This distinction matters because discarding before document commit is much cheaper and less user-visible than destroying an already committed document.

## Commitment Rules

The key requirement is to separate incidental selection from intentional use.

Navigator should mark a selected tab as `committed` when at least one of the following becomes true:

- the tab remains selected past an activation threshold
- the user submits a URL in that tab
- the user clicks inside page content
- the user scrolls the page
- the user performs a browser command that clearly targets that tab, such as reload or back/forward

Navigator should keep a tab `transientSelected` when:

- it was selected only because the user is rapidly moving through tabs
- no explicit interaction happened yet
- the selection ended before the activation threshold expired

### Navigation intent signals

Navigation activity alone must not automatically commit activation.

This includes:

- redirects
- script-driven `window.location` changes
- meta refresh
- target-window or popup-triggered navigation flows
- history-driven route changes that do not clearly reflect user commitment

Recommended rule:

- navigation start does not commit activation by itself
- navigation commit may contribute to commitment only if the tab is still selected and another commitment signal is satisfied

This prevents background scripts or redirect-heavy pages from accidentally converting a transient selection into a committed user intent.

The same rule applies to same-document navigation activity:

- fragment changes
- `history.pushState`
- `history.replaceState`
- client-side route changes in SPAs

These must not be treated as equivalent to full document commitment unless another commitment signal is present.

### Activation threshold

The initial implementation should use a small threshold such as:

- `150ms` to `250ms`

This should be injectable for tests and tuning.

The threshold must be:

- long enough to filter fast scrubbing
- short enough that ordinary tab selection does not feel delayed

Threshold tuning must be backed by metrics, not guesswork. Navigator should record:

- selection to browser-creation latency
- browser-creation to navigation-commit latency
- transient activation cancellation rate
- discard frequency
- warm-tab hit rate

## Commitment Persistence

Committed state is sticky at the logical tab level.

Required rule:

- once a tab becomes `committed`, it remains logically committed until tab removal

Discarding a committed tab:

- removes the live browser
- does not erase the fact that the tab was intentionally used
- does not downgrade the tab back into a never-used transient candidate

This prevents surprising behavior where intentionally used tabs become treated like brand-new incidental selections after routine eviction.

## Lifecycle Policy

### On tab selection

When a tab becomes selected:

- within a window, exactly one tab may be the selected activation target at a time
- if the selected tab is logically `committed` and has no browser, create it immediately
- if the selected tab is `cold`, enter `transientSelected`
- if the selected tab is `discarded`, follow the committed-tab reactivation policy for that tab
- schedule a commit timer for that tab
- do not create the browser immediately unless there is explicit commit-worthy interaction

Selection changes must remain visually immediate. UI tab switching must not wait for browser creation or load start.

Required latency guarantee:

- tab selection and container swapping should remain effectively frame-bound and must not be blocked on runtime browser creation

The intended sequence is:

- update selected tab state immediately
- swap visible container state immediately
- create the browser asynchronously after the activation policy allows it

Lifecycle state mutations must be serialized on the main actor, even if runtime callbacks originate elsewhere.

### Commit-worthy interaction definition

The implementation must use a concrete, shared definition of explicit interaction.

Commit-worthy interaction includes:

- primary pointer down or up inside rendered page content
- wheel or trackpad scrolling targeting page content
- keyboard input routed to page content
- explicit browser chrome commands targeting the selected tab
- URL submission for the selected tab
- accessibility focus entering page content

Non-commit-worthy interaction includes:

- hover alone
- URL bar focus by itself
- selection highlight changes without page-targeted input

### On explicit interaction during transient selection

If the selected transient tab receives an explicit interaction:

- cancel the commit timer
- mark the tab `committed`
- create the browser immediately if needed

Accessibility interaction also counts as commitment-worthy interaction. If assistive technology focus targets the tab or its contents, Navigator should treat that as explicit user use and commit activation.

### On selection leaving a transient tab

If the user leaves a `transientSelected` tab before commitment:

- cancel the commit timer
- if a browser was never created, do nothing further
- if a browser exists and no commit happened, Navigator may stop and discard it

This is the performance win path.

### On selection leaving a committed tab

If the user leaves a `committed` tab:

- do not stop its load purely because it lost selection
- allow background loading to continue
- subject it to a separate live-browser budget and eviction policy

This preserves user intent.

### Browser creation cancellation

Browser creation itself may race with selection changes.

Required behavior:

- if the tab becomes deselected before browser creation begins, cancel creation
- if creation has already been requested but the runtime can still cancel safely, cancel it
- if creation completes after deselection and cancellation was not possible, destroy the browser immediately unless the tab has already become protected by another policy

Navigator must not leave orphaned browser instances alive because a transient selection raced with creation.

### Reactivation of discarded committed tabs

Previously committed tabs that were later discarded remain known tabs, not brand-new transient candidates.

This includes tabs discarded because of:

- live-browser budget eviction
- window-visibility reclaim
- memory pressure
- renderer crash, unless a future crash UX chooses a different surface

Recommended reactivation policy:

- discarded committed tabs recreate immediately when reselected

If product testing later shows that discarded committed tabs should re-enter a transient flow, that must be a deliberate policy change. The default design should preserve the feeling that a previously used tab is trusted state, not a speculative one.

## Live Browser Budget

Intent-aware activation solves the “rapid scrub” problem, but it does not by itself bound total live-browser cost once a user has intentionally touched many tabs.

Navigator should therefore keep a small live-browser budget such as:

- selected tab: always retained
- previously selected tab: always retained for one switchback opportunity after selection changes
- warm tab budget: `1`
- total live committed browsers: small LRU cap, for example `2` or `3`

When the cap is exceeded:

- keep the selected tab
- keep the previously selected tab
- keep the most recently active warm tab
- discard older committed hidden tabs by LRU order

The browser budget must be scoped per window, not globally across the application.

Navigator already supports multiple browser windows, so one window’s tab churn must not evict protected tabs in another window.

### Protected-set precedence

Protected tabs may temporarily exceed the nominal live-browser cap.

Protected classes include:

- selected tab
- previously selected tab
- warm protected tab
- DevTools-attached tab
- accessibility-protected tab
- future auth-protected tab

Required rule:

- budget enforcement applies only to non-protected hidden tabs
- if all live tabs are protected, no eviction occurs

The cap is a target for reclaim, not a reason to violate protection guarantees.

Discarding a committed hidden tab means:

- close the browser
- keep tab metadata
- optionally keep the most recent known URL/title/favicon

The first milestone does not need full navigation-entry snapshotting, but it should preserve enough state that discard does not feel broken.

Minimum preserved state should include:

- current URL
- title
- favicon URL
- last known scroll offset when feasible

Full back-forward stack preservation can remain out of scope for the first milestone.

### Renderer churn protection

Discard policy must account for renderer churn, not only browser view count.

If browsers are created and destroyed too aggressively, Chromium may churn renderer processes, compositor state, and GPU resources in a way that costs more than the saved background work.

Navigator should therefore protect very recently created browsers with a small minimum lifetime such as:

- `2s` to `3s`

Unless:

- memory pressure requires immediate reclaim
- the browser never completed creation cleanly
- the tab was closed
- the renderer crashed

This is a renderer-churn protection window, not a user-intent signal.

## Background Loading Policy

The product rule is simple:

- committed tabs may continue background loading
- transient tabs may be canceled or discarded when abandoned

This means Navigator must not use a blanket rule like:

- “stop every load on deselect”

That rule would be incorrect because it breaks the intended case where the user deliberately opened a page and moved to another tab while it continues loading.

### Navigation cancellation hook

To discard transient tabs cleanly, the runtime should expose an explicit navigation stop path before or during close.

Desired behavior:

- stop provisional transient navigations before discard when possible
- close the browser afterward

CEF stop-load semantics may not cancel every outstanding network task immediately, so the runtime contract must document the exact ordering and fallback behavior.

## Browser Creation Debounce

The safest first implementation is to debounce browser creation, not just load commands.

Why:

- if no browser exists yet, the cheapest browser is the one never created
- this avoids renderer spin-up, page bootstrap, and initial load work for transient selections
- it fits the current architecture because unopened tabs already rely on deferred creation

Required behavior:

- selection schedules browser creation for the selected tab after the activation threshold
- if selection changes before the timer fires, the work item is canceled
- explicit commit actions bypass the delay

Activation timers must be race-safe.

Required invariant:

- a timer firing for tab `A` must revalidate that tab `A` is still the currently selected activation target for the same selection generation before committing or creating a browser

Acceptable implementations:

- compare `selectedTabID` before acting
- use an activation generation token
- use a per-tab activation session identifier

Without this, stale timers can commit or create browsers for tabs the user already left.

### Activation session invariant

Every transient activation attempt must belong to exactly one activation session.

Required invariant:

- all asynchronous callbacks that can mutate lifecycle state must carry and validate activation-session identity before acting

This applies to:

- commit timers
- browser creation completion
- deferred stop or close completion, if asynchronous
- crash callbacks
- load-state callbacks that race with discard

A stale callback from an invalidated activation session must be ignored.

## Stop/Discard Behavior

The runtime should expose an explicit stop-load operation in addition to close.

Desired surface area:

- `stopLoad(_ browser: CEFBridgeBrowserRef?)`
- existing `close(_ browser: CEFBridgeBrowserRef?)`

Recommended policy:

- use `stopLoad` only for transient tabs that were abandoned after work began
- use `close` to enforce the live-browser budget or discard abandoned transient tabs
- do not use `stopLoad` as a general deselection side effect

If a tab is closed while transient activation is pending:

- cancel its activation timer
- cancel any pending browser creation
- ignore all future activation callbacks for that tab

Tab removal must invalidate every pending lifecycle action tied to that tab.

## State Ownership

The activation lifecycle should be owned explicitly in `BrowserView`, not inferred from scattered browser-runtime signals.

Recommended ownership:

- a dedicated `BrowserTabActivationViewModel` or a well-scoped extension of the existing host model
- explicit methods for:
  - `selectTab`
  - `commitTabActivation`
  - `cancelTransientActivation`
  - `recordInteraction`
  - `evictHiddenBrowsersIfNeeded`
- explicit per-window ownership of lifecycle bookkeeping

Avoid:

- encoding the policy only in ad hoc timer closures
- mixing lifecycle decisions into random UI setters
- relying on `didSet` observers for cross-model browser teardown

### Window teardown guarantee

Window teardown must invalidate all lifecycle work owned by that window.

Required behavior on window teardown:

- cancel all activation timers
- cancel all pending browser creations
- invalidate the window lifecycle token
- detach browser views
- close live browsers in a defined order
- ignore all late callbacks after invalidation

## Persistence Expectations

This feature should preserve:

- tab ID
- current URL
- current title
- favicon URL
- selected tab

This feature does not need to guarantee preservation of:

- full in-memory JS state after a discarded browser
- partial form edits inside a discarded renderer
- exact back-forward stack for discarded tabs in the first milestone

If future product requirements demand fuller restoration, that should be a later phase built on top of this lifecycle model, not a blocker for the performance fix.

Discard restoration in the first milestone should preserve enough state to remain usable, including last known scroll offset where supported.

## Window Visibility and System Pressure

Navigator should adapt discard behavior to whole-window visibility and process pressure, not just tab selection.

When a browser window becomes:

- minimized
- fully occluded
- otherwise effectively non-visible

Navigator may discard hidden committed browsers more aggressively than when the window is active and visible.

Similarly, system pressure should tighten reclaim behavior.

Potential pressure sources include:

- dispatch memory-pressure signals
- app-level memory-pressure notifications when available

Under memory pressure:

- hidden committed browsers may be discarded immediately
- renderer churn protection windows may be bypassed
- only strongly protected tabs should remain

## User Experience Expectations

Normal usage must still feel immediate.

Expected UX:

- clicking or keyboard-selecting a tab and staying there should feel unchanged or nearly unchanged
- very fast scrubbing through tabs should avoid obvious page churn
- loading a page and switching away should not kill that page’s progress simply because it is now hidden
- returning to a discarded tab may recreate the browser, but should keep the correct tab identity and metadata in the sidebar

## Observability

Navigator should expose lightweight diagnostics for this feature.

At minimum, log or instrument:

- transient selection started
- transient selection committed
- transient selection canceled before browser creation
- transient browser stopped and discarded
- committed hidden browser discarded by LRU budget
- current live-browser count
- navigation commit timing
- renderer churn protection skips
- memory-pressure-triggered discard events
- renderer crash discard events

These diagnostics should stay internal and must not leak browsing content beyond values already visible in local app state.

## Crash and Failure Handling

Renderer crashes and failed browser creation must participate in lifecycle state transitions.

Required rules:

- renderer crash transitions the tab to `discarded`
- failed browser creation leaves the tab in a browser-less state without dangling pending work
- a crashed or failed browser must not remain marked as live, committed, and healthy

Crash recovery UX may be layered later.

Initial implementation:

- may silently recreate a crashed discarded tab from preserved state when the user reselects it

Future work:

- may show a crash placeholder or explicit reload surface if product needs clearer crash affordance

If DevTools is attached to a tab, that tab must be protected from automatic discard while the debugging session is active.

Authentication-sensitive flows should also be considered for protection in future phases. At minimum, the design should allow commit/protection when a tab is clearly in the middle of an auth flow.

GPU and compositor resources are part of discard correctness. The runtime must verify that `close()` fully releases browser-hosted surfaces and does not leave stale texture-backed layers attached to the view hierarchy.

## Test Plan

The feature should be implemented with deterministic tests around lifecycle transitions.

### Unit coverage

Add tests for:

- selecting a tab starts transient activation
- leaving before the threshold cancels transient activation
- staying past the threshold commits activation
- explicit user navigation submission commits immediately
- explicit page interaction commits immediately
- navigation start alone does not commit activation
- provisional navigation plus transient deselection discards correctly
- committed navigation plus deselection is allowed to continue
- deselecting a committed loading tab does not stop it
- deselecting a transient loading tab stops or discards it
- LRU eviction preserves the selected tab
- LRU eviction preserves the previously selected tab
- LRU eviction preserves the warm-tab budget
- stale timers cannot commit deselected tabs
- tab close cancels pending activation work
- browser creation completion after deselection is cleaned up safely
- per-window budgets do not interfere with each other
- renderer crash transitions the tab to discarded state
- memory pressure triggers aggressive hidden-tab discard

### Integration coverage

Add `BrowserView` tests for:

- rapid `selectTab` churn does not create browsers for every visited tab
- intentional tab selection still creates a browser reliably
- background loads in committed tabs survive selection changes
- discarded tabs recreate from stored URL/title state without flashing placeholder metadata

### Cold-start and restore coverage

Because Navigator already restores tabs lazily, this feature must also verify:

- restored tabs remain browser-less until selected or committed
- rapidly traversing restored tabs does not create a browser per stop
- restored committed tabs behave correctly after reactivation and discard
- restored discarded tabs restore enough view state, including scroll offset where supported, to remain usable

## Rollout Strategy

Implement in phases.

### Phase 1

- introduce explicit activation state
- introduce explicit navigation state
- add activation debounce for selected tabs
- add explicit commit triggers from URL submission and dwell time
- add race-safe activation session tokens

### Phase 2

- expose runtime `stopLoad`
- discard abandoned transient browsers that started work
- add browser-creation cancellation and post-create cleanup
- add crash-to-discard transitions

### Phase 3

- add live-browser LRU budget for hidden committed tabs
- scope the budget per window
- add previous-tab protection
- add diagnostics and regression coverage
- integrate memory-pressure discard behavior

This sequencing keeps the first improvement low-risk and ensures the policy distinction is in place before adding more aggressive reclamation.

## Open Questions

These must be decided before implementation is finalized:

- what exact activation threshold feels right on macOS
- whether pointer selection and keyboard selection should use the same threshold
- what counts as sufficient in-page interaction for immediate commitment
- what initial live-browser cap is acceptable for memory versus responsiveness
- whether warm-tab retention should be fixed at one tab or made configurable internally
- whether scroll restoration can be implemented cheaply enough for the first discard milestone
- how auth-flow protection should be detected and scoped
- how DevTools attachment state should be surfaced into lifecycle policy

## Feature Flag

This feature should ship behind an internal kill switch.

Recommended shape:

- `NavigatorFeatureFlags.tabActivationLifecycle`

That allows rapid disablement if the lifecycle policy causes regressions in auth flows, debugging workflows, accessibility behavior, or unexpected renderer churn.

## Recommendation

The recommended implementation for Navigator is:

- do not stop every deselected tab
- treat tab activation as `transient` until the user commits by time or interaction
- debounce browser creation for transient selections
- allow committed tabs to continue background loading
- discard hidden live browsers later with a small LRU cap

This model matches the user expectation that:

- “I intentionally opened this page, let it finish loading”

while still fixing the performance problem caused by:

- “I was only flying past that tab and never meant to load it fully”
