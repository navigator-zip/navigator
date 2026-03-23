# MiumCEFBridgeNative Rewrite Engineering Specification

## Purpose

This document defines the implementation specification for rewriting `MiumCEFBridgeNative` into a smaller, safer, and more maintainable bridge architecture for:

- CEF runtime lifecycle
- browser lifecycle
- request-context lifecycle
- AppKit host embedding
- callback delivery
- shutdown sequencing
- testing and observability

It is intended as a direct handoff to an engineer implementing the rewrite.

This is not a cosmetic refactor. The objective is to eliminate crash-prone lifetime ambiguity, especially around:

- CEF refcounted object ownership
- borrowed-vs-retained pointer misuse
- host view lifetime
- browser replacement
- stale callback delivery
- shutdown races
- synchronous thread-hop deadlocks

## 1. Objectives

The rewrite must achieve all of the following:

- Eliminate raw-lifetime ambiguity for CEF objects.
- Make one subsystem the source of truth for each lifecycle invariant.
- Remove heuristic AppKit subview cleanup.
- Make callback delivery stale-safe after replacement and teardown.
- Make shutdown deterministic through an explicit state machine.
- Make thread-hopping rules explicit and auditable.
- Shrink the exported C ABI layer into a thin wrapper.
- Add structured observability sufficient to debug races in production and tests.

## 2. Non-Negotiable Architecture Rules

### 2.1 One owner per truth

Each major invariant must have exactly one authoritative owner.

- `RuntimeManager` owns runtime and request-context truth.
- `BrowserManager` owns browser lifecycle truth.
- `HostViewManager` owns host/container resources only.
- `CallbackDispatcher` owns callback queueing only.
- `CefThreadGate` owns thread-hop execution rules only.

No subsystem may keep an independent competing copy of another subsystem's truth.

### 2.2 No borrowed CEF pointer escapes lexical scope

A borrowed CEF pointer may:

- be read
- be checked
- be used synchronously inside the same lexical scope

A borrowed CEF pointer may not:

- be stored in state
- be captured into an async closure
- cross a queue boundary
- cross a thread hop
- be delivered through a callback later

Any CEF pointer that crosses one of those boundaries must first be converted into bridge-owned retained local ownership.

### 2.3 No direct refcount manipulation outside the ref layer

No code outside the dedicated CEF ref wrapper layer may call:

- `add_ref`
- `release`
- `has_one_ref`
- `has_at_least_one_ref`

No exceptions.

### 2.4 No sync thread hop while holding bridge locks

No synchronous thread hop may occur while a bridge manager lock is held.

This must be asserted in debug builds.

### 2.5 Host views are resources, not browser lifecycle authorities

A host view does not define whether a browser is alive, active, valid, or callback-deliverable.

A host view only defines whether AppKit embedding resources currently exist.

### 2.6 Shutdown is a state machine, not a flag

Runtime shutdown must progress through explicit states with defined API behavior at each state.

## 3. High-Level Module Layout

### 3.1 `MiumCEFBridgeNative.mm`

Thin exported C ABI only.

Responsibilities:

- validate public arguments
- translate handles to ids
- call facade methods
- translate internal results to public result codes

It must not contain substantial lifecycle logic.

### 3.2 `MiumCEFBridge.h` / `MiumCEFBridge.mm`

Facade only.

Responsibilities:

- own managers
- perform coarse orchestration between managers
- translate API intent into subsystem calls

It must not become a second god object.

### 3.3 `CefBaseTraits.h`

Single audited location for base-access rules for supported CEF types.

This file must contain all supported type accessors in one place, with comments tied to the vendored CEF header definitions used by this target.

### 3.4 `CefRef.h`

Central ref wrapper layer.

Responsibilities:

- retain borrowed refs
- adopt already-owned refs
- reset/release refs
- expose lexical raw pointer access only

### 3.5 `CefThreadGate.h` / `CefThreadGate.mm`

Central execution gate for:

- AppKit main thread work
- CEF UI thread work

Must distinguish these explicitly unless runtime config guarantees they are identical.

### 3.6 `RuntimeManager.h` / `RuntimeManager.mm`

Owns:

- framework load state
- CEF runtime initialization
- runtime shutdown state machine
- request-context records
- runtime-level policy around shutdown

### 3.7 `BrowserManager.h` / `BrowserManager.mm`

Owns:

- logical browser records
- native browser presence
- browser active/inactive state
- browser closing/terminal state
- browser generation
- browser-to-runtime association
- browser-to-request-context association
- browser-to-host attachment truth
- callback registration validity

This is the source of truth for browser lifecycle.

### 3.8 `HostViewManager.h` / `HostViewManager.mm`

Owns:

- weak host view references
- container view creation and removal
- host-resource bookkeeping only

It must not own browser lifecycle truth.

### 3.9 `CallbackDispatcher.h` / `CallbackDispatcher.mm`

Owns:

- completion queue
- message queue
- overflow policy
- delivery mechanics
- callback dropping based on snapshot validity

It must not own browser truth.

### 3.10 `CefClientFactory.h` / `CefClientFactory.mm`

Owns:

- creation of the embedded handler bundle
- owner recovery helpers
- CEF callback entry points for client/handlers

### 3.11 `Tracing.h` / `Tracing.mm`

Owns structured logging/tracing helpers and event schemas.

## 4. CEF Base Access Contract

### 4.1 All base access must be explicit and centralized

Every supported CEF type must have an accessor defined in `CefBaseTraits.h`.

Example shape:

```cpp
template <typename T>
struct CefBaseTraits;

template <>
struct CefBaseTraits<cef_browser_t> {
    static cef_base_ref_counted_t* base(cef_browser_t* value) {
        return value == nullptr ? nullptr : &value->base;
    }
};
```

If a type requires nested access such as `&value->base.base`, that must be explicitly documented with a comment pointing to the vendored CEF struct definition for the pinned CEF version.

### 4.2 No scattered specializations

All supported specializations must live in one file in one contiguous block.

### 4.3 Audit requirement

Whenever vendored CEF headers are upgraded, this file must be re-audited first.

## 5. CEF Ref Wrapper Specification

### 5.1 Wrapper type

Use a retained wrapper type with explicit ownership semantics.

Required operations:

- `retain(T* borrowed)`
- `adopt(T* owned)`
- `reset()`
- `get()`
- `operator bool()`
- optionally `leak()`

### 5.2 Semantic rules

`retain()`

Use only when the input pointer is borrowed and must become bridge-retained.

`adopt()`

Use only when a CEF API contract explicitly returns an already-owned `+1` reference.

If there is any ambiguity, `retain()` must be used instead.

All `adopt()` call sites must be rare and commented with the specific CEF API ownership contract.

`get()`

Returns a lexical-use raw pointer only.

A raw pointer returned by `get()` must never be cached or cross an async boundary without another retained wrapper.

### 5.3 Failure policy

If a supposedly refcounted object has:

- null base accessor
- null `add_ref`
- null `release`

that is bridge corruption or invalid input.

In debug builds, this must assert hard.

Silent fallback is forbidden.

### 5.4 Optional debug behavior

In debug builds, the wrapper may log whether `release()` returned final-destruction status when available. This is useful for leak tracing and final-release debugging.

## 6. ClientBundle Specification

### 6.1 One allocation, one refcount domain

Client and all handler structs must live in one heap allocation with one shared refcount domain.

### 6.2 Embedded wrappers

Each embedded wrapper must place the CEF handler struct at offset zero.

Example:

```cpp
struct EmbeddedDisplayHandler {
    cef_display_handler_t value;
    ClientBundle* owner = nullptr;
};

static_assert(offsetof(EmbeddedDisplayHandler, value) == 0);
```

This must be repeated for every embedded wrapper.

### 6.3 Owner recovery

Owner recovery from callback entry points must occur via the embedded wrapper type and must assert owner presence.

### 6.4 Shared refcounting

Retaining or releasing any of these must affect the single bundle refcount:

- client
- display handler
- lifespan handler
- JS dialog handler
- load handler
- permission handler
- request handler
- resource request handler

### 6.5 Bundle contents

The bundle should contain:

- shared refcount
- embedded client
- embedded handlers
- browser identity metadata needed by callbacks

No child handler should be separately heap-allocated.

## 7. BrowserManager Specification

### 7.1 BrowserManager is the source of truth for browser lifecycle

`BrowserManager` owns and decides:

- whether a browser exists logically
- whether it is active
- whether it is closing
- whether it is terminal
- whether it is still callback-deliverable
- current generation
- current runtime association
- current request-context association
- current host attachment truth
- whether a native browser exists
- whether native replacement is required

No other subsystem may independently decide these.

### 7.2 Browser record shape

Each browser record must contain at least:

- browser id
- runtime id
- request-context id
- active flag
- closing flag
- terminal flag or equivalent erasure-stage representation
- generation
- retained native browser ref
- retained native client ref
- attached host view id
- callback registrations and registration versioning

### 7.3 Record terminal policy

A browser record must not necessarily be erased immediately when it stops accepting work.

There must be a documented policy for:

- active
- closing or terminal
- erased

This is required so stale work can still be rejected deterministically before final erasure.

### 7.4 Browser generation

Generation must increment whenever native replacement or attachment-level invalidation makes previously queued browser-scoped work stale.

Generation is part of callback validity but is not sufficient alone; snapshot resolution is still required.

## 8. HostViewManager Specification

### 8.1 Weak host references must be truly weak

Do not store raw unretained `NSView*` and call it weak.

Use a true weak Objective-C wrapper or equivalent zeroing-weak mechanism.

### 8.2 HostViewManager owns resources only

It may own:

- weak host reference
- container view
- host resource identity

It may not own browser lifecycle truth.

### 8.3 Explicit container model

All AppKit embedding must happen through a dedicated bridge-owned container view.

Shape:

```text
Host NSView
\-- MiumBrowserContainerView
    \-- CEF-created AppKit subtree
```

Cleanup must occur by operating on the container boundary, not by diffing arbitrary host subviews.

### 8.4 No heuristic subview diffing

Subview diff-based ownership inference is forbidden in the rewritten architecture.

### 8.5 Host loss behavior

If the weak host resolves to `nil`, `HostViewManager` must report host-resource loss. `BrowserManager` then performs the browser-state transition defined by policy.

## 9. Attach / Detach / Destroy Contract

### 9.1 Attach

Attach must perform these logical steps:

- validate browser is attachable
- resolve live host resource
- ensure container view exists
- ensure native browser exists or is replaced appropriately for this attachment
- record attachment truth in `BrowserManager`
- leave host-resource bookkeeping in `HostViewManager` only

### 9.2 Detach without destroy

Detach must have deterministic semantics. At minimum:

- browser no longer counts as host-attached
- container resources are removed

`BrowserManager` decides whether native browser remains valid, becomes logical-only, or enters close or replacement flow.

Future host-bound APIs fail deterministically if host-bound native embedding no longer exists.

### 9.3 Destroy while attached

Destroy must define ordering clearly:

- browser stops accepting new work
- callback registrations are invalidated according to policy
- host/container resources are removed in the correct thread and order
- native browser close begins if necessary
- final record erasure occurs only after the browser reaches the terminal removal point

### 9.4 Host disappears unexpectedly

Host disappearance must be treated as a deterministic lifecycle event, not a fuzzy edge case.

Policy must define whether the browser becomes:

- logical-only
- detached-native
- detached-and-closing

depending on embed model and native browser validity.

## 10. Callback Registration and Delivery Specification

### 10.1 Registration lifetime ownership

Callback registrations are lifecycle records owned by `BrowserManager`.

The architecture must explicitly define whether outstanding resolved snapshots may still deliver after unregistration, or whether unregistration invalidates them immediately through generation or registration-version changes.

This policy must be consistent.

### 10.2 Snapshot-based delivery

Dispatcher must not validate and later re-resolve separately.

Instead, `BrowserManager` must produce an immutable callback delivery snapshot under lock.

Example fields:

- callback pointer
- callback context
- browser id
- generation
- channel
- deliverable flag
- registration version if used

Dispatcher then releases the `BrowserManager` lock and uses only the snapshot.

### 10.3 Queue ownership

`CallbackDispatcher` owns queueing, draining, overflow policy, and delivery mechanics only.

It must not independently decide whether a browser is active or valid.

### 10.4 Stale callback handling

Callbacks may be dropped deterministically for at least:

- browser inactive
- generation mismatch
- registration invalidation
- runtime shutdown state
- browser terminal state

Each drop reason should be observable in tracing.

## 11. Native Browser Indexing Specification

### 11.1 Raw pointer indexes are not ownership

Any `cef_browser_t*` to token map is an index only, never an ownership mechanism.

### 11.2 Preferred canonical mapping

Browser identifier-based mapping should be the canonical long-lived index when available.

Raw pointer mapping may exist as a transient fast path only.

### 11.3 Insertion and removal policy

The architecture must define exactly when native-browser pointer and identifier maps are:

- inserted
- updated during replacement
- invalidated during close
- removed during terminal teardown

These events belong to `BrowserManager`.

## 12. Thread Model and CefThreadGate Specification

### 12.1 Distinguish thread concepts explicitly

The bridge must explicitly model:

- AppKit main thread
- CEF UI thread

They may only be treated as identical if runtime configuration guarantees that invariant and the bridge asserts it.

### 12.2 Gate API

The thread gate must provide explicit sync and async APIs for:

- main thread
- CEF UI thread

### 12.3 Sync-hop policy

The gate must define:

- behavior when already on target thread
- whether nested sync hops are allowed
- whether sync hops are allowed during shutdown phases
- whether sync hops from callback-delivery threads are allowed
- lock assertions required before any sync hop

### 12.4 Lock rule

No manager lock may be held during a sync hop.

This must assert in debug builds.

## 13. RuntimeManager and Shutdown State Machine

### 13.1 RuntimeManager owns runtime truth

`RuntimeManager` owns:

- framework load state
- initialized and uninitialized state
- request-context records
- runtime shutdown state
- admission policy for new work during shutdown

### 13.2 Required runtime states

At minimum:

- `uninitialized`
- `initializing`
- `initialized`
- `shutdownRequested`
- `drainingBrowsers`
- `drainingCallbacks`
- `shuttingDownCEF`
- `shutDown`

### 13.3 API behavior by state

Public APIs must have defined behavior at each state.

Examples:

- browser creation after `shutdownRequested` must fail deterministically
- host attach during `drainingBrowsers` must fail deterministically
- load, eval, and send during `shuttingDownCEF` must fail deterministically

### 13.4 In-flight operation policy

This must be explicit.

Recommended policy:

- operation first acquires a runtime operation snapshot
- if runtime state already disallows the operation, fail immediately
- before execution on target thread, validate runtime state again
- if runtime has advanced to a disallowed state, fail deterministically with a shutdown-related result

This gives two explicit rejection gates:

- pre-dispatch
- pre-execution

### 13.5 Request-context destruction semantics

Destroying a request context means:

- remove logical bridge record
- release bridge-owned retained native ref

It does not guarantee synchronous native destruction beyond refcount semantics.

This must be documented clearly.

## 14. Public API Semantics

### 14.1 Logical-only browser model

Browser creation may produce a logical browser record before native browser creation.

The architecture must define which APIs are valid on a logical-only browser.

Recommended default:

Allowed APIs:

- register handlers
- attach to host
- destroy browser

Not allowed unless explicitly implemented later:

- load URL
- evaluate JS
- snapshot
- send renderer message
- navigation methods

These should fail deterministically with a native-browser-unavailable result.

### 14.2 Dispatch vs completion semantics

APIs such as `LoadURL`, `EvaluateJavaScript`, and `SendMessage` must clearly define whether success means:

- accepted for dispatch
- executed on target thread
- completed semantically

If the current ABI only supports dispatch acknowledgment, that must be documented explicitly.

## 15. Observability Requirements

Observability is mandatory.

### 15.1 Required correlation fields

Every trace or log event should include as applicable:

- runtime id
- browser id
- browser generation
- request-context id
- host-view id
- native browser identifier
- callback event or sequence id
- thread lane
- shutdown state

### 15.2 Required event families

Runtime:

- initialize requested
- initialize succeeded or failed
- shutdown state transitions
- final CEF shutdown begin and end

Request context:

- create
- destroy
- runtime association
- privacy mode

Browser:

- logical record created
- native browser created
- native browser replaced
- generation incremented
- attached
- detached
- close requested
- close completed
- record terminal
- record erased

Host view:

- host registered
- weak host lost
- container created
- container removed

Callback:

- registered
- unregistered
- queued
- delivered
- dropped with reason

Threading:

- main-thread hop
- CEF UI-thread hop
- lock assertion failure
- shutdown-phase hop rejection

## 16. Migration Plan

Phase 0: observability and assertions

- add structured tracing around current lifecycle hotspots
- add lock and thread assertions around current sync-hop sites
- confirm actual crash surface before invasive changes

Phase 1: ref compatibility layer

- introduce `CefBaseTraits.h`
- introduce `CefRef.h`
- replace highest-risk refcount sites first, starting with:
- request context retain and release
- browser retain and release
- frame retain and release
- keep lower-risk legacy call sites temporarily if needed

Phase 2: thread gate

- move thread hops behind `CefThreadGate`
- add lock-held sync-hop assertions

Phase 3: browser truth extraction

- introduce `BrowserManager`
- migrate browser lifecycle truth there
- define record terminal and erasure policy

Phase 4: host resources

- introduce `HostViewManager`
- switch to true weak host storage
- replace heuristic subview cleanup with explicit container model

Phase 5: callback safety

- add callback registration ownership model
- add generation increments
- add snapshot-based callback delivery
- remove stale callback delivery paths

Phase 6: runtime state machine

- introduce `RuntimeManager`
- move request-context ownership there
- implement shutdown state machine
- define in-flight operation policy

Phase 7: client bundle

- introduce `ClientBundle`
- replace scattered handler allocations with embedded owner-recoverable bundle
- add `offsetof == 0` assertions everywhere

Phase 8: ABI thinning and cleanup

- shrink exported C ABI layer
- remove legacy helpers and redundant global state

Conditional reorder:

If current crash evidence implicates client or handler lifetime directly, move Phase 7 earlier.

## 17. Implementation Review Checklist

Before merging the rewrite, verify all of the following:

- no direct `add_ref` or `release` exists outside the ref layer
- all supported CEF base accessors are centralized
- all embedded handler wrappers assert offset-zero layout
- `adopt()` call sites are rare and justified
- borrowed CEF pointers do not cross async boundaries
- `BrowserManager` is the only browser lifecycle truth owner
- `HostViewManager` stores actual weak references
- no heuristic subview diffing remains
- callback delivery uses immutable snapshots
- shutdown state machine exists and is enforced
- in-flight operation rejection points are deterministic
- sync-hop policy is encoded and asserted
- tracing includes correlation ids

## 18. Final Engineering Guidance

This rewrite should be judged by whether it makes lifetime and sequencing easier to prove, not just whether it makes the code look cleaner.

The implementation should bias toward:

- explicit ownership
- explicit invalidation
- explicit state transitions
- explicit thread semantics
- explicit cleanup boundaries

Any place where the implementation is relying on "this is probably okay because CEF usually behaves like X" should be treated as a design smell and tightened.

The success condition is that the bridge becomes auditable: an engineer should be able to answer, for any browser, request-context, host-view, or callback path:

- who owns it
- who can invalidate it
- what thread it runs on
- when it stops accepting work
- when it is finally erased

That is the standard this rewrite must meet.
