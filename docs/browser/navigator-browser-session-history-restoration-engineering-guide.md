# Navigator Browser Session History Restoration Engineering Guide

This document specifies how Navigator should implement browser-session history restoration across app relaunches.

It is intended as an engineering handoff, not a product brief. The target reader is an engineer who will design and implement the feature across `ModelKit`, `Navigator`, `BrowserSidebar`, `BrowserView`, `BrowserRuntime`, and the native CEF bridge.

## Purpose

Ship tab restoration that preserves more than a single current URL after relaunch.

Today Navigator restores only one snapshot per tab:

- current URL
- page title
- favicon URL
- pin state
- order
- selected tab id

After relaunch, a tab comes back at its current page but does not preserve its back-forward stack.

This guide defines:

- what CEF exposes publicly
- what CEF does not expose publicly
- the architectural consequences for Navigator
- the recommended implementation strategy
- data model and lifecycle rules
- divergence and fallback behavior
- test and rollout requirements

## Normative Language

The following keywords are normative:

- `MUST` means required for correctness
- `MUST NOT` means forbidden behavior
- `SHOULD` means recommended unless there is a documented reason not to
- `MAY` means optional

Implementations MUST satisfy every `MUST` and `MUST NOT` requirement in this document.

## Verified CEF Facts

These facts were rechecked against the vendored CEF headers in this repo and the public CEF header mirror on March 12, 2026.

- CEF exposes read access to the current back-forward list via `CefBrowserHost::GetNavigationEntries(...)`.
  Sources:
  [`cef_browser.h`](/Users/rk/Developer/Navigator/Vendor/CEF/include/cef_browser.h#L663)
  https://github.com/chromiumembedded/cef/blob/master/include/cef_browser.h
- CEF exposes read access to the current visible entry via `CefBrowserHost::GetVisibleNavigationEntry()`.
  Sources:
  [`cef_browser.h`](/Users/rk/Developer/Navigator/Vendor/CEF/include/cef_browser.h#L953)
  https://github.com/chromiumembedded/cef/blob/master/include/cef_browser.h
- CEF exposes metadata for each history entry via `CefNavigationEntry`, including URL, original URL, title, transition type, completion time, and HTTP status.
  Sources:
  [`cef_navigation_entry.h`](/Users/rk/Developer/Navigator/Vendor/CEF/include/cef_navigation_entry.h#L45)
  https://github.com/chromiumembedded/cef/blob/master/include/cef_navigation_entry.h
- CEF exposes normal imperative navigation controls: `CanGoBack`, `GoBack`, `CanGoForward`, `GoForward`, and `LoadURL`.
  Sources:
  [`cef_browser.h`](/Users/rk/Developer/Navigator/Vendor/CEF/include/cef_browser.h#L78)
  [`cef_frame.h`](/Users/rk/Developer/Navigator/Vendor/CEF/include/cef_frame.h#L149)
  https://github.com/chromiumembedded/cef/blob/master/include/cef_browser.h
  https://github.com/chromiumembedded/cef/blob/master/include/cef_frame.h
- The public CEF API does not expose a corresponding write-side API to set, seed, or restore a browser's back-forward list.
  Verified by inspection of the vendored CEF headers under [`Vendor/CEF/include`](/Users/rk/Developer/Navigator/Vendor/CEF/include).

Initial `about:blank` entries created by browser initialization MUST NOT be persisted as history entries and MUST NOT participate in restored session history.

## Current Repo Starting Point

Navigator currently persists only one snapshot per tab:

- [`StoredBrowserTab`](/Users/rk/Developer/Navigator/ModelKit/Sources/ModelKit/StoredBrowserTabModels.swift#L3)
- [`StoredBrowserTabCollection`](/Users/rk/Developer/Navigator/ModelKit/Sources/ModelKit/StoredBrowserTabModels.swift#L62)
- [`StoredBrowserTabSelection`](/Users/rk/Developer/Navigator/ModelKit/Sources/ModelKit/StoredBrowserTabModels.swift#L91)

Persistence currently happens in:

- [`AppViewModel.persistCurrentTabs()`](/Users/rk/Developer/Navigator/Navigator/AppViewModel.swift#L304)

Restore currently happens in:

- [`AppViewModel.hydrateStoredTabsIfNeeded()`](/Users/rk/Developer/Navigator/Navigator/AppViewModel.swift#L275)
- [`BrowserSidebarTabCollection.restoreTabs(_:)`](/Users/rk/Developer/Navigator/BrowserSidebar/Sources/BrowserSidebar/BrowserSidebarTabCollection.swift#L196)

CEF-backed navigation control currently exists only as live session operations:

- [`BrowserViewController.swift`](/Users/rk/Developer/Navigator/BrowserView/Sources/BrowserView/BrowserViewController.swift#L1690)
- [`BrowserRuntime.swift`](/Users/rk/Developer/Navigator/BrowserRuntime/Sources/BrowserRuntime/BrowserRuntime.swift#L1144)
- [`MiumCEFBridgeBrowserActions.mm`](/Users/rk/Developer/Navigator/MiumKit/Sources/MiumKit/MiumCEFBridgeBrowserActions.mm)

The repo does not currently contain:

- a persisted session-history model
- a `BrowserRuntime` API to enumerate CEF navigation entries
- a `MiumKit` bridge API for `GetNavigationEntries`
- a synthetic restoration layer that arbitrates between restored history and live CEF history

## Product Goal

`Session history restoration` means:

- when the app relaunches, each restored tab MAY preserve a back-forward stack instead of only the visible page
- pressing Back after relaunch SHOULD behave as closely as practical to pre-quit tab history
- launch MUST remain fast
- restoration MUST NOT replay every URL at startup
- divergence from true Chromium/CEF session semantics MUST be explicit and well-defined

The following are out of scope for v1:

- restoring JavaScript heap state
- restoring DOM state in memory
- restoring form field contents unless already encoded in the page URL
- restoring POST body re-submission state
- restoring process-local SPA state that was never reflected in committed navigation entries
- patching Chromium internals to inject a true native `NavigationController` stack

## Architectural Constraint

Because public CEF exposes history enumeration but not history restoration, Navigator MUST choose between:

1. replaying old entries into a fresh browser
2. building an app-owned synthetic history restoration layer
3. patching CEF/Chromium internals

This document recommends option `2`.

## Why Replay Is Not Acceptable

Replay means loading `A`, then `B`, then `C` during restore so the browser's native history stack is rebuilt.

Replay is rejected for Navigator because it:

- is slow on launch
- causes real network activity for all replayed pages
- can trigger side effects on pages that are not safe to revisit
- fails badly for POST-based entries
- will not faithfully reconstruct all redirect, frame, SPA, and process state
- complicates cold start and restores unpredictably under flaky connectivity

Navigator MUST NOT use full stack replay as the primary restoration mechanism.

Replay MAY still be used only for:

- test fixtures
- manual debugging
- narrowly scoped migration tooling

## Recommended Architecture: Synthetic Restored History

Navigator SHOULD implement a synthetic restored-history layer that sits above live CEF history only during the restoration phase.

## System Invariants

The following invariants MUST always hold:

1. If `historyEntries` is non-empty, `currentIndex` MUST be in bounds.
2. The visible entry MUST always correspond to `historyEntries[currentIndex]`.
3. The visible entry MUST NEVER be truncated out of persisted history.
4. `diverged` tabs MUST NOT use synthetic back-forward handling.
5. Synthetic persisted index MUST advance only after commit.
6. Stale browser-generation snapshots MUST be dropped.
7. `navigatingSynthetic` MUST always have an expected target URL and expected index.
8. Persisted session state MUST represent committed authoritative state, never speculative in-flight state.

## Source Of Truth Hierarchy

Authority changes by phase and MUST be explicit.

- Before live browser attach, persisted session state is the source of truth.
- While a tab is `eligible` or `navigatingSynthetic`, synthetic restored state is authoritative for back-forward semantics and target URL projection.
- While synthetic restored state is active, live engine history MAY exist but is not semantically authoritative for restored back-forward behavior.
- After a tab becomes `diverged`, live runtime history is authoritative.
- Persistence writes MUST only store committed authoritative state, never speculative state.

The visible URL shown in UI MUST always correspond to the authoritative history source for the current phase. UI layers MUST NOT invent intermediate URLs that cannot be traced to persisted state, synthetic restored state, or live runtime state.

## State Diagram

```text
persisted restore
    |
    v
 eligible <---- successful synthetic commit ---- navigatingSynthetic
    |                                            |
    | organic nav / timeout / mismatch / reload  |
    +-----------------------> diverged ----------+
                             |
                             v
                    live runtime authoritative
```

### Core Model

For each restored tab, Navigator persists:

- a list of committed history entries
- a current index inside that list
- the currently visible entry
- enough metadata to know whether the stack is still eligible for synthetic back-forward handling

At relaunch:

- Navigator loads only the current entry URL into the live browser
- Navigator keeps the rest of the stack in app-owned state
- if the user presses Back before divergence, Navigator uses the stored stack instead of asking CEF to go back
- if the user presses Forward before divergence, Navigator uses the stored stack instead of asking CEF to go forward
- once divergence occurs, Navigator discards the synthetic restored stack and hands off completely to live CEF history

### Example

Assume the user quit with:

- `A -> B -> C`
- current index = `2`

At restore:

- only `C` loads on startup
- stored restored session remains `[A, B, C]`

If the user presses Back before divergence:

- Navigator updates the restored index to `1`
- Navigator loads `B`
- Navigator does not call `CEF GoBack`

If the user presses Back again before divergence:

- Navigator updates the restored index to `0`
- Navigator loads `A`

If the user then clicks a new link to `D`:

- synthetic restored history is discarded
- live browser history becomes authoritative from that point onward

## Session Model

Add a new pure model in `ModelKit`.

Suggested types:

- `StoredBrowserTabSession`
- `StoredBrowserHistoryEntry`
- `StoredBrowserTabSessionCollection`

### `StoredBrowserHistoryEntry`

Suggested fields:

- stable entry id
- `url`
- `displayURL`
- `originalURL`
- `title`
- `transitionType`
- `completionTime`
- `httpStatusCode`
- `hadPostData`
- `isTopLevelNativeContent`
- `nativeContentKind`

Not every field must be used in UI immediately, but the persisted model SHOULD preserve the entry semantics that CEF already exposes publicly.

### `StoredBrowserTabSession`

Suggested fields:

- tab id
- object version
- order key
- pinned state
- archived state
- current history index
- visible URL
- page title
- favicon URL
- history entries
- restoration provenance
- synthetic-restoration eligibility version

### Versioning

The session model MUST be versioned independently of the current `StoredBrowserTab` model.

The implementation SHOULD support:

- reading old single-URL tab snapshots
- writing new session-history snapshots
- fallback to old behavior if no session data exists

## Runtime Bridge Requirements

Navigator needs a read-only bridge for CEF history enumeration.

### New `MiumKit` Responsibilities

Add a native bridge API that:

- calls `CefBrowserHost::GetNavigationEntries`
- visits all entries on the correct CEF/UI thread
- materializes a plain bridge-owned value snapshot
- returns that snapshot to Swift through existing callback delivery rules

The bridge MUST NOT:

- retain `CefNavigationEntry` objects beyond visitor scope
- return raw CEF pointers to Swift
- assume history enumeration is safe from arbitrary threads

### New `BrowserRuntime` Responsibilities

Add a `BrowserRuntime` API shaped approximately like:

```swift
public func getNavigationEntries(
    _ browser: CEFBridgeBrowserRef?,
    completion: @escaping @MainActor ([BrowserRuntimeNavigationEntry]) -> Void
)
```

The exact API shape MAY differ, but the result type MUST be a Swift value type, not a borrowed native handle.

Navigation snapshots returned from `BrowserRuntime` are ephemeral runtime values and MUST NOT be treated as long-lived cached state outside tab-scoped restored-history coordination or persistence.

### Required Snapshot Shape

The runtime API MUST return a snapshot shape, not just an unstructured array.

Suggested shape:

```swift
public struct BrowserRuntimeNavigationSnapshot: Sendable, Equatable {
    public let entries: [BrowserRuntimeNavigationEntry]
    public let currentIndex: Int
}
```

`entries` MUST be ordered from oldest to newest.

`currentIndex` MUST identify the currently visible main-frame entry inside `entries`.

If the native engine cannot provide a coherent snapshot, the runtime MUST fail the request instead of guessing.

### Snapshot Consistency Contract

Navigation snapshot enumeration MUST produce a logically consistent view of the navigation stack.

If the underlying browser navigates while enumeration is occurring, the runtime MUST discard the partially collected snapshot and either retry or fail the request.

The runtime MUST NOT return:

- partially collected entries
- a mismatched `currentIndex`
- entries from one browser generation with an index from another

Snapshots MUST be associated with:

- browser generation
- the navigation commit generation visible at capture time

If a newer committed navigation occurs before the snapshot is persisted, the snapshot MUST be discarded.

### Navigation Entry Identity

CEF does not expose a stable navigation-entry identifier suitable for persistence.

The runtime MUST derive a deterministic per-entry identity from stable observable fields, preferably:

- normalized URL
- completion time
- transition type
- original URL when available

The derived identity MUST be stable across repeated snapshot captures within the same browser generation.

If the engine cannot produce a stable identifier, the implementation MUST treat the entire snapshot as replaceable rather than attempting fine-grained merging or diffing.

### Navigation Entry Filtering

Only main-frame committed navigation entries MUST be persisted.

The implementation MUST ignore:

- subframe navigations
- favicon updates
- provisional address changes
- entries that do not correspond to a committed visible page

Same-document navigations MAY be included only if the engine implementation can identify them reliably and tests prove the behavior remains intuitive.

### URL Normalization Rules

URL comparisons for synthetic navigation and snapshot deduplication MUST use normalized URLs.

Normalization SHOULD include:

- lowercased host comparison
- default-port normalization
- consistent trailing-slash handling
- stable percent-encoding comparison where safe

Fragment identifiers MUST be preserved only when they materially distinguish same-document navigation semantics.

The implementation MUST use one shared normalization routine for:

- snapshot identity derivation
- synthetic expected-target matching
- redirect equivalence checks
- divergence decisions

### Snapshot Timing

Navigator SHOULD refresh persisted history snapshots at stable moments:

- main-frame committed navigation
- history-affecting back navigation
- history-affecting forward navigation
- reload completion
- top-level native content presentation/dismissal when represented as navigation semantics
- tab close
- app lifecycle transitions that already trigger session persistence

Navigator MUST avoid sampling on every transient loading state if it causes redundant churn.

Snapshot persistence SHOULD be coalesced.

If multiple committed navigations occur within a short stabilization window, such as redirect-heavy flows, the implementation MAY delay persistence briefly so that the persisted snapshot reflects the final committed visible entry after redirect resolution.

## Navigation Event Sources

Synthetic restoration and persisted-history capture MUST be driven only by committed main-frame navigation events.

For the current runtime, the implementation SHOULD anchor on the existing main-frame navigation event path exposed through [`BrowserRuntimeMainFrameNavigationEvent`](/Users/rk/Developer/Navigator/BrowserRuntime/Sources/BrowserRuntime/BrowserRuntime.swift#L92).

The implementation MUST define one authoritative commit signal and use it consistently for:

- history snapshot updates
- divergence detection
- synthetic navigation completion
- persisted current-index advancement

The implementation MUST ignore:

- subframe navigations
- favicon updates
- provisional address changes
- transient loading-state flips without a new committed main-frame entry
- intermediate redirects before the final committed destination is known

History snapshots MUST only occur when the committed visible main-frame entry changes or when an explicit synthetic-history control path requires re-snapshotting.

## Threading And Concurrency Contract

This feature crosses:

- CEF UI thread
- native bridge queues
- Swift main actor
- AppKit UI state

The threading contract MUST be explicit.

### CEF Threading Requirements

All navigation entry enumeration MUST occur on the CEF UI thread.

The native bridge MUST ensure:

- `CefBrowserHost::GetNavigationEntries` executes on the CEF UI thread
- the visitor executes entirely on that thread
- no Swift code executes from inside the visitor
- the visitor copies entry data into bridge-owned plain values before returning

The native bridge MUST NOT:

- capture borrowed `CefNavigationEntry` references outside the visitor callback
- directly invoke Swift or AppKit work from the visitor
- block the CEF UI thread waiting for Swift main-actor work

### Swift Concurrency Requirements

Swift callbacks from the runtime MUST be dispatched asynchronously to the main actor.

`BrowserView` and `Navigator` state that drives restored-history behavior MUST be `@MainActor`.

The implementation MUST NOT mutate restored-history state from background queues.

If native enumeration completes after the owning tab has closed or the browser generation has changed, the result MUST be dropped.

### Reentrancy Guarding

Synthetic navigation introduces reentrancy:

- user presses Back
- Navigator issues `LoadURL`
- CEF emits normal navigation callbacks for that load

Navigator MUST track:

- whether a synthetic navigation is in flight
- the expected destination URL
- the expected restored index
- the browser generation associated with that synthetic load

While synthetic navigation is in flight:

- the next committed main-frame navigation MUST be matched against the expected destination
- if it matches, the tab returns to `eligible`
- if it does not match, the tab transitions to `diverged`

History snapshot capture MUST ignore intermediate navigations initiated by synthetic restoration until the synthetic navigation completes.

Only the final committed result of a synthetic navigation MAY update persisted history.

## Browser Engine Abstraction

Navigator has browser engine abstraction work in flight, so session-history restoration MUST NOT hardcode a CEF-only contract into higher layers.

`BrowserRuntime` MUST expose history enumeration as an engine-agnostic capability.

`BrowserRuntime` SHOULD also expose an explicit capability such as:

```swift
supportsNavigationSnapshot: Bool
```

Feature behavior MUST branch on runtime capability explicitly, not implicitly on engine kind.

CEF and future WebKit implementations MUST conform to the same high-level contract:

- value-based snapshot result
- ordered entries from oldest to newest
- stable current index
- main-frame committed-entry semantics

If one engine cannot provide coherent history snapshots, that engine MUST fall back to single-URL restoration without breaking the other engine.

## Browser Generation Definition

`Browser generation` refers to the lifetime of a single underlying browser instance.

Generation MUST increment when:

- a new CEF browser object is created
- a browser process crash causes recreation
- a tab moves across runtimes or windows and receives a new underlying browser instance
- the tab is explicitly rebuilt after teardown

Synthetic restored-history state and history snapshots MUST be keyed to browser generation.

## State Ownership

The following ownership split MUST hold:

- `BrowserRuntime` owns live browser history access
- `Navigator` owns persisted session history
- `BrowserView` owns restoration handoff logic between synthetic restored history and live CEF history
- `BrowserSidebar` continues to own tab list state and visible URL projection
- `ModelKit` owns the pure stored data shapes

No single layer should own both the raw CEF bridge and the persisted session policy.

## Recommended Decomposition

The implementation SHOULD be decomposed as follows:

- `ModelKit`
  Owns pure session models, schema versioning, truncation rules, and migration helpers.
- `MiumKit`
  Owns CEF history snapshot enumeration only.
- `BrowserRuntime`
  Owns engine-agnostic snapshot APIs, capability discovery, and value conversion.
- `BrowserView`
  Owns the tab-scoped restored-history coordinator and state machine.
- `Navigator`
  Owns persistence orchestration, restore integration, and workspace-level flushing.
- `BrowserSidebar`
  Owns derived visible URL and back-forward affordance projection only.

The restored-history coordinator SHOULD be a dedicated `@MainActor` type.

This feature SHOULD NOT be implemented as ad hoc branches spread across `BrowserViewController`.

## Dependency And Test Seams

The implementation MUST use existing dependency boundaries.

- history enumeration MUST be accessed through `BrowserRuntime`
- persistence logic MUST be testable without a live browser instance
- timeout and debounce timing MUST use injectable clock or scheduler dependencies
- synthetic-history coordination MUST be testable independently of AppKit view lifecycle

## Restored History State Machine

Each restored tab SHOULD have one of these states:

- `none`
  No restored history exists. Live CEF history is authoritative.
- `eligible`
  Restored history exists and has not yet diverged. Synthetic back-forward is allowed.
- `navigatingSynthetic`
  Navigator is loading a synthetic entry chosen from restored history.
- `diverged`
  The restored stack has diverged from live behavior. Synthetic handling is permanently disabled for this tab session.

### Transitions

`none -> eligible`

- when a tab is restored from persisted session history

`eligible -> navigatingSynthetic`

- when the user presses Back or Forward and the target exists in the restored stack

`navigatingSynthetic -> eligible`

- after the synthetic target load commits successfully and remains consistent with the restored target

`eligible -> diverged`

- when the user performs a new navigation not represented by synthetic restoration
- when a redirect chain changes the visible result unexpectedly
- when a form post, replace-state-like behavior, or native content transition cannot be modeled safely
- when the user reloads and the implementation chooses not to preserve synthetic semantics
- when the tab opens devtools flows or scripted navigation that invalidates simple restored stack reasoning

`eligible -> diverged` also implies:

- synthetic forward entries are discarded
- live browser history becomes the only forward/back authority

When divergence occurs from a restored back position, all synthetic forward entries MUST be discarded immediately and MUST NOT appear in UI forward affordances thereafter.

`diverged` is terminal for the life of that restored tab session.

## Tab-Scoped Lifecycle Rules

Synthetic restored-history state is tab-scoped and generation-scoped.

It MUST be destroyed when:

- a tab closes
- a tab is duplicated
- a tab moves to another window and gets a new runtime/browser instance
- the browser process crashes or is recreated
- the underlying browser generation changes
- the tab is discarded and later rebuilt from only a single URL

When a tab is duplicated:

- the duplicated tab SHOULD inherit the persisted session-history snapshot
- the duplicated tab MUST start with fresh synthetic-restoration state
- synthetic in-flight state MUST NOT be copied

## `navigatingSynthetic` Input Policy

While a tab is `navigatingSynthetic`, behavior MUST be explicit.

Recommended v1 rules:

- additional synthetic Back or Forward requests SHOULD be ignored or disabled
- user-entered address submission MUST force divergence
- reload MUST force divergence unless explicitly modeled otherwise
- tab close MUST cancel pending synthetic completion handling
- browser recreation MUST cancel pending synthetic completion handling

The implementation MUST NOT queue unbounded synthetic navigation requests while another synthetic navigation is in flight.

Synthetic restored-history state MUST NOT survive browser-instance replacement unless the replacement is part of explicit cold restore and the restored session is reattached intentionally.

## Divergence Rules

The synthetic stack is only useful while Navigator can still reason clearly about it.

Navigator MUST discard synthetic restored history on any event that makes the restored stack semantically untrustworthy.

At minimum, divergence SHOULD occur on:

- any user-entered new address submission
- link click or script-triggered main-frame navigation to a URL outside the currently modeled restored target
- redirect chains that land on a different final URL than expected
- `LoadURL` requests not initiated by restored back-forward handling
- explicit reload if the implementation cannot preserve consistent semantics
- any POST-backed entry chosen for restoration
- top-level native content transitions that are not explicitly modeled in the restored history format

Redirects during synthetic navigation MAY be treated as equivalent rather than divergent if:

- the redirect chain began from the expected synthetic target
- the final committed URL matches the restored entry's normalized `url`, `originalURL`, or `displayURL`

Otherwise the redirected result MUST be treated as divergence.

Navigator MAY preserve synthetic eligibility through simple same-document navigation only if that behavior is explicitly tested and reliable.

## DevTools Policy

Opening DevTools MUST force divergence for that tab session in v1.

Rationale:

- DevTools inspection changes event timing and navigation observability
- the additional complexity is not required for an initial implementation
- forcing divergence is simpler and safer than pretending synthetic semantics remain trustworthy

## Synthetic Navigation Algorithms

The implementation SHOULD follow explicit algorithms rather than ad hoc branching.

### Handle Back Action

```text
if restoredState == eligible and restoredIndex > 0
    restoredIndex -= 1
    state = navigatingSynthetic
    expectedURL = restoredEntries[restoredIndex].url
    expectedIndex = restoredIndex
    issue runtime.loadURL(expectedURL)
else
    issue runtime.goBack()
```

### Handle Forward Action

```text
if restoredState == eligible and restoredIndex + 1 < restoredEntries.count
    restoredIndex += 1
    state = navigatingSynthetic
    expectedURL = restoredEntries[restoredIndex].url
    expectedIndex = restoredIndex
    issue runtime.loadURL(expectedURL)
else
    issue runtime.goForward()
```

### Handle Committed Main-Frame Navigation

```text
if restoredState == navigatingSynthetic
    if committedURL matches expectedURL or redirect-equivalent target
        state = eligible
        persist restoredIndex only now
    else
        state = diverged
else if restoredState == eligible
    if committed navigation is not explainable as restored synthetic navigation
        state = diverged
```

### Persist Current Index

The restored current index MUST be persisted only after the expected synthetic target commits successfully.

Navigator MUST NOT eagerly persist the target index at button-tap time.

### Synthetic Timeout And Abandonment

Synthetic navigation MUST resolve through one of the following outcomes:

- successful commit
- explicit failure
- browser replacement
- timeout

If the expected synthetic target does not commit within a bounded interval, the tab SHOULD transition to `diverged`.

Timeout handling MUST be instrumented.

Timeout sources SHOULD be injectable for tests.

### Synthetic Load Failure Semantics

The implementation MUST define synthetic load failure explicitly.

Recommended v1 policy:

- a committed error page counts as a committed navigation if it corresponds to the expected target
- browser- or transport-level failure before commit forces divergence
- load cancellation before commit forces divergence unless it is directly explained by tab close or browser replacement

### Reload Policy

Until product explicitly decides otherwise, reload MUST force divergence in v1.

Reload-triggered snapshots MAY still be captured after divergence using live-history semantics.

## Crash Recovery Policy

If the app crashes during synthetic navigation, the last persisted committed index is authoritative.

Example:

- restored state is `A -> B -> C`
- current persisted index is `2`
- user initiates synthetic Back toward `B`
- app crashes before `B` commits

After relaunch, the restored index MUST still be `2`.

Only committed synthetic navigations may advance the persisted current index.

## Shutdown Persistence Rules

Shutdown persistence MUST use the last coherent committed snapshot only.

In-flight synthetic transitions MUST NOT advance the persisted current index.

If no coherent history snapshot is available at shutdown, the implementation MUST fall back to visible-URL-only persistence semantics.

Shutdown paths MUST NOT attempt to salvage partially committed redirect chains or speculative synthetic state.

## Storage Strategy

Session history MUST be stored alongside the existing persisted browser workspace state.

For Navigator’s current architecture, the implementation SHOULD extend the same storage used for:

- [`StoredBrowserTabCollection`](/Users/rk/Developer/Navigator/ModelKit/Sources/ModelKit/StoredBrowserTabModels.swift#L62)
- [`StoredBrowserTabSelection`](/Users/rk/Developer/Navigator/ModelKit/Sources/ModelKit/StoredBrowserTabModels.swift#L91)

The history session payload SHOULD be encoded as part of the same workspace state document or an adjacent versioned state file in the same persistence domain.

The implementation MUST NOT introduce a separate ad hoc persistence mechanism for session history unless there is a documented operational reason.

## Persistence Write Strategy

For v1, tab-session persistence SHOULD replace the stored coherent snapshot wholesale.

The implementation SHOULD NOT perform fine-grained incremental merging of persisted history entries in v1.

If a new coherent snapshot is available, it SHOULD replace the prior stored snapshot for that tab.

This avoids subtle merge bugs while entry identity rules mature.

## UI Integration Rules

UI state MUST reflect synthetic restored history, not just live CEF history.

### Address Bar

When a synthetic Back or Forward starts, the address bar SHOULD update to the expected target URL immediately.

If the synthetic navigation later diverges, the committed visible URL becomes authoritative.

### Loading State

Synthetic navigation MUST surface loading state in the same way as ordinary browser navigation.

### Back And Forward Availability

UI affordances MUST be computed as:

- back available = `syntheticBackAvailable || runtimeCanGoBack`
- forward available = `syntheticForwardAvailable || runtimeCanGoForward`

Where synthetic availability applies only while the tab is `eligible`.

### Visible Tab URL

The selected tab’s visible URL MUST track the synthetic target during successful synthetic navigation, but persisted current index MUST still wait for commit.

### Background Tabs

Synthetic Back or Forward initiated for a background tab MAY execute immediately, but the implementation MUST define one consistent behavior.

Recommended v1 behavior:

- allow synthetic navigation for background tabs
- keep the same commit, divergence, and persistence rules
- avoid special-casing foreground status in the restoration state machine

## Observability And Metrics

This feature MUST emit structured diagnostics.

At minimum, add hooks for:

- `SyntheticHistoryActivated`
- `SyntheticHistorySnapshotSaved`
- `SyntheticHistoryDiverged`
- `SyntheticHistoryLoadMismatch`
- `SyntheticHistoryDroppedBecauseBrowserGenerationChanged`
- `SyntheticHistoryRestoreFallback`

Each event SHOULD include:

- tab id
- browser generation
- engine kind
- restored state
- expected URL if present
- committed URL if present
- history entry count

## Debounced Persistence Policy

Runtime snapshot capture MAY happen on each authoritative committed navigation.

Persisted writes SHOULD be debounced or coalesced across short windows.

Tab close, app backgrounding, and shutdown MUST flush the latest coherent pending session state.

## Enumeration Failure Policy

If the browser engine returns:

- zero entries for a browser that has a visible page
- an out-of-range current index
- entries with invalid URLs
- an internally inconsistent snapshot

the runtime MUST treat the snapshot as invalid.

Invalid snapshots MUST NOT be partially trusted by default.

Fallback behavior:

- discard the invalid snapshot
- preserve the visible URL if known
- continue with single-URL restoration semantics
- emit structured diagnostics

## Native Top-Level Content

Navigator already overlays some top-level content, such as native image view presentation.

Synthetic session history MUST define whether these appear as persisted entries.

Recommended v1 rule:

- persist top-level native image view entries only as metadata on a history entry
- restore to the underlying URL, not directly into a native overlay at launch
- if the user navigates into a stored native-content entry through synthetic Back/Forward, the tab MAY either:
  - load the underlying URL and allow the normal top-level native content handler to present it, or
  - directly re-present native content if enough metadata exists

Navigator SHOULD start with the simpler approach: load the underlying URL and allow normal detection/presentation to re-occur.

## Launch Performance Requirements

Session-history restoration MUST preserve fast startup.

The implementation MUST:

- restore each tab by loading only its current entry URL
- avoid replaying older entries at launch
- avoid background hydration of the entire stack through network requests
- avoid blocking tab creation on session-history decoding beyond ordinary persisted tab restore work

The implementation SHOULD:

- decode persisted history lazily if needed for very large sessions
- cap persisted entries per tab for v1
- cap total restored-history payload size per workspace
- prefer truncation around the visible index instead of keeping only the newest tail

The implementation MAY opportunistically drop persisted session-history snapshots for background or discarded tabs under memory pressure, falling back to single-URL restoration semantics.

The persisted payload size SHOULD be estimated from the encoded representation of the stored session-history document.

If the encoded payload exceeds the configured limit, truncation MUST occur before persistence completes.

## Privacy And Security Rules

Persisting session history expands the privacy surface.

Navigator MUST NOT persist entries for:

- `about:blank`
- internal browser chrome pages
- extension-internal URLs
- obviously invalid or empty URLs

Navigator SHOULD consider redacting or skipping:

- URLs with embedded secrets or tokens in query strings
- authentication callback URLs
- one-time-use session bootstrap URLs

If the implementation cannot safely classify a sensitive URL, it SHOULD prefer omitting that entry rather than persisting questionable data.

If a URL is omitted or redacted for privacy reasons, associated title and related metadata SHOULD also be omitted or redacted.

Navigator SHOULD avoid preserving more metadata than the URL persistence decision allows.

## Schema Migration Rules

When upgrading session schema versions:

- unknown fields MUST be ignored when safe
- compatible additive schema changes SHOULD preserve prior data
- incompatible schema versions MUST fall back to single-URL restoration
- migration failures MUST NOT block launch

## Data Limits

Navigator SHOULD impose explicit limits to prevent unbounded restore payload growth.

Recommended v1 defaults:

- maximum persisted entries per tab: `50`
- maximum persisted tabs per workspace: reuse existing tab limits
- maximum persisted session payload size per workspace: `5 MB`

When limits are exceeded:

- preserve entries around the current index
- discard entries furthest from the visible index first
- preserve the visible entry and immediate back-forward neighborhood

Recommended truncation algorithm:

1. preserve the visible entry
2. preserve a symmetric window before and after the visible entry when possible
3. discard entries furthest from the visible entry first
4. never discard the visible entry
5. if only one side can be preserved, prefer preserving back entries over forward entries only when product explicitly decides that policy

Limits MUST be documented in code comments near the truncation logic.

## Failure And Fallback Behavior

If anything in session-history restore fails, Navigator MUST degrade cleanly to current behavior.

Examples:

- if session decode fails, restore only the current tab URL
- if a synthetic target load fails, mark the tab `diverged`
- if runtime enumeration fails, keep persisting single-URL snapshots
- if stored history is malformed, ignore invalid entries and salvage the visible entry

Navigator MUST NOT block launch or crash the browser window because session-history restoration is unavailable.

## Migration Plan

### Phase 1: Read-only capture

Ship bridge support for CEF history enumeration and log/inspect snapshots in tests.

Deliverables:

- native bridge API for enumerating navigation entries
- `BrowserRuntimeNavigationEntry` Swift value type
- tests proving snapshots are returned safely and in order

### Phase 2: Persisted session model

Persist session-history snapshots without changing runtime behavior on restore.

Deliverables:

- new `ModelKit` storage types
- migration from current `StoredBrowserTab`
- app persistence updates
- restore still falls back to current URL only

### Phase 3: Synthetic restored Back/Forward

Use stored history for restored tabs before divergence.

Deliverables:

- restored-history state machine
- back-forward routing in `BrowserViewController`
- divergence handling
- targeted UI and integration tests

### Phase 4: Native-content integration and polish

Handle native image view and other top-level content consistently inside the restored session model.

### Phase 5: Telemetry and tuning

Measure:

- restored-session decode size
- divergence rate
- synthetic back-forward success rate
- fallback frequency

## Files Likely To Change

The following repo areas are likely involved:

- [`ModelKit/Sources/ModelKit/StoredBrowserTabModels.swift`](/Users/rk/Developer/Navigator/ModelKit/Sources/ModelKit/StoredBrowserTabModels.swift)
- [`Navigator/AppViewModel.swift`](/Users/rk/Developer/Navigator/Navigator/AppViewModel.swift)
- [`BrowserSidebar/Sources/BrowserSidebar/BrowserSidebarTabCollection.swift`](/Users/rk/Developer/Navigator/BrowserSidebar/Sources/BrowserSidebar/BrowserSidebarTabCollection.swift)
- [`BrowserView/Sources/BrowserView/BrowserViewController.swift`](/Users/rk/Developer/Navigator/BrowserView/Sources/BrowserView/BrowserViewController.swift)
- [`BrowserRuntime/Sources/BrowserRuntime/BrowserRuntime.swift`](/Users/rk/Developer/Navigator/BrowserRuntime/Sources/BrowserRuntime/BrowserRuntime.swift)
- [`MiumKit/Sources/MiumKit/MiumCEFBridgeBrowserActions.mm`](/Users/rk/Developer/Navigator/MiumKit/Sources/MiumKit/MiumCEFBridgeBrowserActions.mm)
- [`MiumKit/Sources/MiumKit/MiumCEFBridgeNative.h`](/Users/rk/Developer/Navigator/MiumKit/Sources/MiumKit/MiumCEFBridgeNative.h)
- [`MiumKit/Sources/MiumKit/CEFBridge.h`](/Users/rk/Developer/Navigator/MiumKit/Sources/MiumKit/CEFBridge.h)
- [`MiumKit/Sources/MiumKit/CEFBridge.mm`](/Users/rk/Developer/Navigator/MiumKit/Sources/MiumKit/CEFBridge.mm)

## Testing Requirements

The implementation MUST include tests at the following layers.

### `ModelKit`

- encode/decode of new history session models
- migration from legacy single-URL tab snapshots
- truncation behavior around limits

### `MiumKit`

- enumeration of navigation entries from the native bridge
- visitor lifecycle safety
- thread-gating correctness
- error behavior when browser handles are invalid or closing

### `BrowserRuntime`

- Swift value conversion from native history entries
- callback delivery ordering
- safe empty-history behavior
- invalid snapshot rejection
- ordering and current-index semantics

### `Navigator` / `BrowserView`

- restore `A -> B -> C`, current `C`, Back goes to `B`
- repeated Back/Forward while still eligible
- divergence on new navigation to `D`
- divergence on redirect mismatch
- fallback when a restored entry cannot be loaded
- native image view interaction
- synthetic navigation completion matching
- persisted index advances only after commit
- DevTools forces divergence
- browser-generation replacement drops stale synthetic results
- UI back-forward enablement combines synthetic and live availability

### Race And Timing Tests

- rapid Back spam during restored synthetic navigation
- tab close while synthetic navigation is in flight
- redirect during synthetic load
- browser recreation during pending history enumeration
- synthetic load result arriving after divergence
- crash-recovery persistence semantics at commit boundaries

### Manual Verification

At minimum:

1. navigate through several ordinary pages
2. quit and relaunch
3. confirm only the visible page loads at startup
4. press Back and Forward
5. confirm new navigation invalidates restored synthetic history
6. confirm malformed persisted history falls back to current-page restore

## Risks

The main risks are semantic, not mechanical.

- Users may expect true browser-session restoration, but v1 only restores URL history.
- Some pages will not behave exactly like Chromium Back because in-memory page state is gone.
- Redirect-heavy or POST-heavy flows will diverge quickly.
- Native-content entries need explicit policy or they will feel inconsistent.

These are acceptable for v1 only if the product language and internal expectations are clear.

## Explicit Non-Goals

This feature MUST NOT attempt to:

- guarantee identical behavior to a never-terminated Chromium process
- restore renderer memory state
- preserve service-worker timing or process-local JS state
- silently patch Chromium internals through unsupported private hooks

## Recommended Decision

Navigator SHOULD proceed with:

- CEF history snapshotting through `GetNavigationEntries`
- persisted app-owned session-history storage
- synthetic restored Back/Forward for restored tabs
- explicit divergence to live CEF history on the first untrustworthy transition

Navigator SHOULD NOT attempt true native `NavigationController` restoration unless we deliberately choose to maintain a custom Chromium/CEF patchset.

This design intentionally leaves room for a future native-history restoration mode if Navigator ships a patched Chromium/CEF build exposing navigation stack injection.

## Open Questions

The implementation owner must resolve these before Phase 3 lands:

1. Should reload preserve synthetic eligibility or force divergence?
2. Should same-document navigations be modeled explicitly in restored history?
3. Should native top-level image view entries be first-class persisted entries in v1?
4. What maximum history depth per tab is acceptable for product and disk budget?
5. Do we want session-history restore only for normal tabs, or also for pinned tabs?

## Summary

CEF gives Navigator enough public API to read a tab's history stack, but not enough to re-inject that stack into a newly created browser.

Therefore:

- true native history restoration is not available through public CEF alone
- launch-time replay is too slow and too risky
- the right implementation is an app-owned synthetic restored-history layer with explicit divergence rules

That is the design this document specifies.
