# AGENTS.md

## Purpose

This file defines the non-negotiable engineering rules, architectural boundaries, migration strategy, safety constraints, and implementation standards for all future work on the Mium CEF bridge framework.

This framework is a lifecycle-sensitive Objective-C++ / CEF / AppKit bridge. It must be treated as systems code, not ordinary application code.

Any agent, engineer, or contributor working in this framework must follow this file before making changes.

The primary goals of the framework are:

- deterministic ownership of all native and bridge-managed resources
- explicit and auditable CEF refcount handling
- explicit and enforceable thread and shutdown semantics
- elimination of heuristic UI cleanup and ambiguous host-view ownership
- one source of truth per invariant
- safe callback delivery under teardown, replacement, and shutdown
- durable observability for lifecycle debugging

If any proposed change conflicts with this file, this file wins unless the architecture is formally revised.

---

## Core Principles

All future work must preserve these principles.

### 1. One source of truth per invariant

Every lifecycle invariant must have exactly one owning subsystem.

Examples:

- browser lifecycle truth belongs to `BrowserManager`
- runtime lifecycle truth belongs to `RuntimeManager`
- host/container resource truth belongs to `HostViewManager`
- callback queue state belongs to `CallbackDispatcher`
- thread-hop policy belongs to `CefThreadGate`
- CEF refcount behavior belongs to the CEF ref layer

No duplicated authorities are allowed.

If two subsystems can independently decide whether a browser is active, whether a callback is valid, or whether a runtime is shutting down, the design is wrong.

### 2. No borrowed CEF pointer crosses a thread hop or async boundary

Borrowed CEF pointers are lexical only.

A borrowed CEF pointer may:

- be read under lock
- be used in the same synchronous lexical scope
- be immediately retained into a bridge-owned ref wrapper

A borrowed CEF pointer may not:

- be stored in records as durable ownership
- be captured into async lambdas
- be queued for later callback delivery
- cross a thread hop
- survive past the synchronous scope in which it was obtained unless retained

### 3. All refcount manipulation is centralized and audited

No code outside the CEF ref layer may call CEF `add_ref` or `release` directly.

No code outside the CEF ref layer may rely on ad hoc `base`, `base.base`, or similar field walking.

### 4. Browser lifecycle truth has one owner

`BrowserManager` is the only owner of browser lifecycle truth.

No other subsystem may own or infer browser lifecycle state independently.

### 5. Host views are resources, not lifecycle authorities

Host views and container views are embedding resources.
They do not own browser lifecycle truth.

### 6. Shutdown is a state machine, not a boolean

Shutdown is a multi-phase lifecycle.
No future work may introduce boolean-only shutdown semantics for runtime or browser lifecycle.

### 7. CEF UI thread and AppKit main thread are distinct concepts unless explicitly proven identical

No code may assume these are the same thread unless the runtime configuration has asserted that invariant.

### 8. Observability is part of correctness

Lifecycle-sensitive code without structured tracing is incomplete.

---

## Scope of This File

This file governs:

- exported C ABI functions
- Objective-C++ bridge code
- CEF client and handler plumbing
- runtime initialization and shutdown
- request context ownership
- browser creation / attachment / detachment / destruction
- AppKit embedding and host/container view logic
- callback registration, queuing, and delivery
- thread hop logic
- lifecycle logging and tracing
- migration and refactor work
- test hooks and validation strategy

---

## Required Module Boundaries

The framework must be organized around the following module boundaries.

## Public C ABI Layer

### File
- `MiumCEFBridgeNative.mm`

### Responsibilities
- exported C functions only
- argument validation
- opaque handle translation
- translation between ABI result codes and internal results
- forwarding into facade methods

### Non-responsibilities
- no lifecycle truth
- no direct resource ownership
- no ad hoc shutdown logic
- no direct handler creation
- no direct host-view manipulation
- no direct callback routing policy

### Rule
This file must remain thin.

If complexity accumulates here, move it inward.

---

## Bridge Facade

### Files
- `MiumCEFBridge.h`
- `MiumCEFBridge.mm`

### Responsibilities
- API translation only
- coarse orchestration only
- ownership of manager instances
- composition root for internal subsystems

### Non-responsibilities
- no duplicate lifecycle truth
- no hidden global mutable state
- no long-term storage of browser/runtime/host state beyond manager ownership
- no ad hoc special-case sequencing that belongs inside an owning manager

### Rule
The facade must never become a second monolith.

If a flow becomes complex, either:
- put sequencing decisions in the owning manager, or
- introduce a small dedicated coordinator

Do not let the facade absorb subsystem internals.

---

## RuntimeManager

### Ownership
`RuntimeManager` is the sole owner of:

- runtime records
- runtime shutdown state machine
- framework load policy
- CEF runtime initialization / final shutdown sequencing
- request context records
- runtime-scoped admission checks for operations

### Runtime Truth
`RuntimeManager` owns authoritative truth for:

- whether the bridge runtime is uninitialized, initializing, initialized, shutting down, or shut down
- whether new runtimes, browsers, or request contexts may be created
- whether in-flight operations are still admissible
- request-context logical existence and bridge-owned retention

### Non-responsibilities
- no browser lifecycle truth
- no host/container embedding truth
- no independent callback validity decisions

### Rules
- `RuntimeManager` may request browser shutdown through `BrowserManager`
- `RuntimeManager` must not mutate browser lifecycle records directly
- request context destruction means releasing bridge-owned retained refs and removing bridge records, not guaranteeing synchronous native destruction

---

## BrowserManager

### Ownership
`BrowserManager` is the sole owner of browser lifecycle truth.

### Browser Lifecycle Truth
It owns authoritative truth for:

- browser logical existence
- active / inactive state
- closing state
- terminal-but-retained-for-rejection state
- erasure eligibility
- browser generation
- host attachment identity
- runtime association
- request-context association
- native browser presence
- native browser replacement
- callback validity as a function of browser state and registration version

### Responsibilities
- create logical browser records
- decide attach / detach / destroy sequencing
- decide when native browser creation/replacement/close occurs
- resolve callback snapshots
- own browser generation increments
- own browser attachment epoch or equivalent invalidation for host-resource loss
- reject stale work deterministically

### Non-responsibilities
- not a host-view resource implementation
- not a callback queue implementation
- not the thread-hop abstraction
- not the runtime state machine owner

### Rule
`BrowserManager` may orchestrate multi-step flows, but must not absorb `HostViewManager` internals or `CallbackDispatcher` internals.

---

## HostViewManager

### Ownership
`HostViewManager` owns host/container embedding resources only.

### Responsibilities
- weak host-view storage
- container-view creation/removal
- lookup of current live host view
- cleanup of host/container bookkeeping

### Non-responsibilities
- no browser lifecycle truth
- no callback validity decisions
- no runtime shutdown decisions

### Rules
- host views must be stored with true weak semantics
- no raw unretained `NSView*` may be used as a durable weak reference
- container management must be explicit
- no heuristic subview diffing is allowed

### Required Pattern
Use a zeroing weak Objective-C wrapper such as:

```objc
@interface MiumWeakViewBox : NSObject
@property (nonatomic, weak, nullable) NSView *view;
@end
```

Container hierarchy must be explicit:

```text
HostView
└── MiumBrowserContainerView
    └── CEF-owned view hierarchy
```

The container is the ownership boundary for embedding cleanup.

---

## CallbackDispatcher

### Ownership
`CallbackDispatcher` owns callback queueing and queue mechanics only.

### Responsibilities
- enqueue callback payloads
- maintain callback queues
- clear queues for browser/runtime invalidation when instructed
- deliver only via resolved snapshots

### Non-responsibilities
- no browser lifecycle truth
- no independent callback validity judgment
- no host-view authority
- no runtime-state authority

### Rule
`CallbackDispatcher` never decides validity itself.
It must rely on snapshot resolution from the owning manager.

---

## CefThreadGate

### Ownership
`CefThreadGate` owns all thread-hop policy and enforcement.

### Responsibilities
- determine whether execution is already on target lane
- hop to AppKit main thread
- hop to CEF UI thread
- enforce sync-hop and async-hop rules
- assert no manager locks are held on hop entry
- provide trace points for all thread transitions

### Non-responsibilities
- no lifecycle truth
- no callback validity ownership
- no browser/runtime state ownership

### Rule
No direct main-thread or CEF-UI-thread dispatch logic is allowed outside `CefThreadGate`.

---

## CEF Ref Layer

### Ownership
The CEF ref layer owns all CEF refcount manipulation and all supported base-access rules.

### Files
- `CefBaseTraits.h`
- `CefRef.h`

### Responsibilities
- base accessor traits for supported CEF types
- retained-ref wrapper implementation
- explicit `retain`, `adopt`, `reset`, `leak`, and lexical raw access policy
- optional debug logging around final release behavior

### Non-responsibilities
- no business logic
- no threading policy
- no host/browser/runtime lifecycle policy

---

## Tracing

### Files
- `Tracing.h`
- `Tracing.mm`

### Responsibility
Structured lifecycle logging.

### Rule
Tracing is mandatory for all lifecycle-sensitive operations.

---

## CEF Refcount Rules

This is one of the most important sections in the entire framework.

## Central Rule
No direct CEF `add_ref` or `release` is allowed outside the CEF ref layer.

Forbidden patterns outside the ref layer include all forms of:

```cpp
ptr->base.add_ref
ptr->base.release
ptr->base.base.add_ref
ptr->base.base.release
```

or equivalent field-walked access.

If code needs a retained native CEF object, it must use the approved wrapper.

## Process-message transfer rule

CEF process-message ownership has a separate transfer contract from ordinary retained refs.

After a successful `cef_frame_t::send_process_message(...)` call:

- CEF takes ownership of the message contents
- the message reference is invalidated
- bridge code must treat that `cef_process_message_t*` as consumed
- bridge code must not call `release`, `reset`, or equivalent cleanup on that same message object

If delivery does not occur, normal ref-layer cleanup still applies.

This rule applies to both browser-to-renderer and renderer-to-browser process-message flows.

Sending a process message and then releasing the same `cef_process_message_t*` is a correctness bug and may crash inside Chromium refcount teardown.

## Composition rule

No internal subsystem implementation file may be textually included into another implementation file.

Forbidden pattern:

```cpp
#include "SomeSubsystem.mm"
```

`MiumCEFBridgeNative.mm` may be a composition root only through headers and linked compilation units, never by `#include`-ing `.mm` files.

---

## CefBaseTraits Rules

All supported `CefBaseTraits<T>` specializations must live in one audited file.

### Requirements
- one file
- one block of specializations
- comments tied to exact vendored CEF headers and pinned version
- no spreading specializations throughout the codebase

### Example Intent
The traits file documents explicitly how each supported type exposes its `cef_base_ref_counted_t`.

### Maintenance Rule
Whenever CEF is upgraded, `CefBaseTraits` must be re-audited against vendored headers before any bridge changes are merged.

---

## CefRetainedRef Rules

The retained wrapper must support explicit ownership vocabulary.

### Required operations
- `retain(T* borrowed)`
- `static adopt(T* owned)`
- `reset()`
- `get()`
- `operator bool()`
- optionally `leak()`

### Semantics
#### `retain()`
Retains a borrowed reference.

#### `adopt()`
Takes ownership of an already-owned `+1` reference returned by documented contract.

#### `get()`
Returns a raw pointer for lexical immediate use only.
The raw pointer is never durable ownership.

#### `reset()`
Releases the currently held retained pointer if any.

### Debug Assertions
If a supported refcounted type resolves a null base, null `add_ref`, or null `release`, this is bridge corruption or unsupported input and must fail loudly in debug builds.

Do not silently mask this.

---

## `adopt()` Restriction Rules

`adopt()` is dangerous if used loosely.

### Non-negotiable rule
`adopt()` may only be used immediately after a documented CEF API that returns a `+1` owned ref by contract.

### If there is any ambiguity
Use `retain()` instead.

### Process rule
Every `adopt()` call site must:
- include a comment naming the exact CEF API contract relied upon
- be reviewed specifically for ownership correctness

### Codebase hygiene rule
`adopt()` should remain rare.
It should ideally appear only in a small audited whitelist of creation or return sites.

---

## Borrowed Ref Escape Rules

Borrowed refs are lexical only.

### Allowed
- read under lock
- immediate synchronous use in lexical scope
- immediate conversion to retained wrapper

### Forbidden
- storing in records as durable ownership
- crossing thread hops
- capturing in async lambdas
- queuing into callback systems
- surviving deferred completion boundaries

### Companion rule
Any native CEF object crossing:
- thread hops
- queued work
- deferred close
- async completion
must first become a `CefRetainedRef<T>`.

---

## Optional Debug Release Logging

In debug builds, the ref layer should optionally log the return value of `release()` when useful.

This helps diagnose:
- leaks
- extra retains
- unexpected final destruction timing

This is not required to change the API surface.
It is a debugging aid.

---

## Client and Handler Bundle Rules

CEF client and handler ownership must use a unified bundle model.

## Bundle Rule
Client and all child handlers must live in one owned allocation with one refcount domain.

### Required shape
Every embedded wrapper must store the CEF-facing value as its first field and a pointer back to the owning bundle.

Example pattern:

```cpp
struct EmbeddedDisplayHandler {
    cef_display_handler_t value;
    ClientBundle* owner = nullptr;
};

static_assert(offsetof(EmbeddedDisplayHandler, value) == 0);
```

### Required wrappers
Apply this pattern to:
- client
- display handler
- lifespan handler
- JS dialog handler
- load handler
- permission handler
- request handler
- resource request handler
- any future embedded handler type

### Owner Recovery Rule
Owner recovery from a handler pointer is only valid because the CEF-facing struct field is first.
That invariant must be documented and asserted.

### Refcount Rule
Any embedded object’s `add_ref` and `release` must forward into the bundle-wide refcount domain.

Bundle destruction occurs only when all retained entry points have been released.

### Forbidden
- separately allocated child handlers with ad hoc release cascades
- hidden ownership trees across multiple refcount domains

---

## Browser Lifecycle Model

The framework supports two browser existence levels.

## State Categories
### 1. Logical-only browser
The browser record exists, but no native browser is currently available.

### 2. Logical + native browser
The browser record exists and owns a current native browser instance.

### Recommended API Contract
#### Allowed on logical-only browser
- register handlers
- attach to host view
- destroy browser

#### Not allowed on logical-only browser unless explicitly added later
- load URL
- back/forward navigation
- evaluate JavaScript
- snapshot
- send renderer messages

These operations must fail deterministically with a “native browser unavailable” style result.

Do not introduce implicit pending-operation queues during migration unless explicitly designed and documented.

---

## Browser Record States

A browser record should move through clearly defined lifecycle phases.

Recommended internal model:
- active
- closing
- terminal but retained for stale-work rejection
- erased

A named tombstone-like state is encouraged if it improves clarity.

### Required erasure policy
The architecture must define exactly when:
- the record stops accepting new work
- stale callbacks can still be rejected cleanly
- the record becomes eligible for final map erasure

Do not erase records so early that stale work can no longer be rejected deterministically.

---

## Browser Generation and Invalidation

`BrowserManager` owns browser generation.

### Required uses
Generation must be incremented when native browser identity changes in ways that invalidate stale work, including:
- native browser replacement
- host-resource loss when attachment-scoped validity is broken
- callback registration invalidation when implemented through generation/versioning

### Rule
Generation is not merely informational.
It is part of stale-work rejection semantics.

---

## Callback Registration Lifetime Rules

Browser validity is not enough.
Callback registration lifetime must also be explicit.

### Required model
Callback registrations are immutable records while installed.
Registration and unregistration are serialized through `BrowserManager`.

### Snapshot resolution
A callback snapshot must capture callback pointer and context from the currently installed registration record atomically under `BrowserManager` control.

### Default invalidation policy
The safer default is:

**unregistration invalidates outstanding snapshots**

Prefer generation or registration-version invalidation to implement this.

Only allow already-resolved snapshots to still deliver if there is a deliberate and documented exception for that callback class.

---

## Callback Snapshot Delivery Rules

The dispatcher may not validate and later re-resolve separately.

### Required pattern
1. callback item reaches delivery point
2. dispatcher asks owning manager for a delivery snapshot
3. snapshot resolution happens atomically under manager lock
4. snapshot contains everything needed for delivery
5. lock is released
6. dispatcher delivers using snapshot contents only

### Snapshot contents
As appropriate, snapshots may contain:
- callback pointer
- callback context
- browser id
- browser generation
- registration version
- event payload or stable references to payload
- shutdown rejection metadata if needed

### Forbidden
- validate token now, resolve callback later
- consult raw browser record again after releasing lock
- invoke callback while holding manager lock

---

## Native Browser Indexing Rules

Raw native pointer maps are transient indexes only.
They are never ownership.

### Preferred indexing
Prefer browser identifier maps as the canonical long-lived index where available.

### Raw pointer map usage
Raw pointer maps may be used as short-lived fast paths only.

### Required cleanup
Entries must be removed deterministically when:
- browser is replaced
- browser enters terminal close path
- final lifespan callback or equivalent confirms final invalidation, depending on ownership model

### Rule
Never treat raw native pointer maps as ownership or long-lived truth.

---

## Host View and Embedding Rules

## Weak Host Reference Rule
All host-view references must have true weak semantics.

Raw unretained `NSView*` is not a weak reference.
It must not be used as one.

## Container Ownership Rule
Embedding must use an explicit container view managed by the bridge.

### Forbidden
- diffing subviews before and after browser creation
- heuristic managed-subview discovery
- trying to infer CEF ownership from arbitrary host hierarchy changes

### Required
The bridge owns a dedicated `MiumBrowserContainerView`.

Cleanup occurs by removing the owned container in the correct lifecycle order.

### Important nuance
Container removal is the AppKit resource boundary.
It is not by itself a complete browser close protocol.
Browser close sequencing still belongs to `BrowserManager`.

---

## Host-View Loss Rules

Host-view disappearance must be a deterministic state transition.

### Required behavior when weak host resolves to nil
- `BrowserManager` records host-resource loss
- generation or attachment epoch is incremented if attachment-scoped validity is broken
- `HostViewManager` removes any remaining container bookkeeping
- APIs requiring a live attached host/native embedding fail deterministically from then on
- browser transitions into a clearly defined state, such as:
  - logical-only, or
  - detached-native-closing
  depending on embedding model

Do not leave host loss behavior interpretive or ad hoc.

---

## Attach / Detach / Destroy Contract

These flows must be explicitly defined and consistently implemented.

## Attach
### Required sequence
- validate browser is attachable
- resolve live host view
- create/update owned container view
- ensure native browser exists for that container
- record attachment truth in `BrowserManager`
- keep generation unchanged unless native replacement occurred

## Detach without destroy
### Required sequence
- mark browser detached from host resource in `BrowserManager`
- decide whether native browser must close or be replaced based on embed model
- remove container via `HostViewManager` on correct thread
- track resulting native close flow through `BrowserManager`
- reject stale callbacks deterministically by generation/version/state

## Destroy while attached
### Required sequence
- mark browser inactive/closing
- invalidate callback registrations logically
- remove container in correct lifecycle order
- initiate native close if present
- retain terminal record long enough for stale-work rejection
- erase record only when final erasure policy says it is safe

---

## Threading and Thread-Hop Rules

This framework contains two potentially distinct execution lanes:

- AppKit main thread
- CEF UI thread

These may or may not be identical in a given runtime configuration.

## Invariant Rule
The bridge must state explicitly whether:
- they are distinct, or
- the runtime guarantees they are identical

If identical, assert this at initialization and treat it as a hard invariant.

If not identical, never conflate them.

---

## `CefThreadGate` Required API Shape

It should provide explicit operations such as:
- `isOnMainThread()`
- `isOnCefUIThread()`
- `runOnMainThreadSync(...)`
- `runOnMainThreadAsync(...)`
- `runOnCefUIThreadSync(...)`
- `runOnCefUIThreadAsync(...)`

---

## Sync-Hop Deadlock Policy

This is mandatory.

### Required rules
- if already on target thread, run inline
- no sync hop may occur while any bridge manager lock is held
- nested sync hops are only allowed when they cannot create a cycle
- sync hops from callback-delivery contexts must be explicitly allowed or forbidden by policy
- sync hops may be restricted during late shutdown states
- every sync hop must assert thread and lock invariants in debug builds

### Rule
Do not introduce ad hoc dispatch sync logic outside `CefThreadGate`.

---

## Manager Lock Rules

Locks are for:
- record lookup
- record mutation
- generation/version changes
- snapshot capture
- ownership transfer of retained wrappers

Locks are not for:
- CEF API calls
- AppKit mutations
- callback invocation
- filesystem operations
- `dlopen` / framework loading
- JSON serialization
- long-running computation

### Absolute rule
Never invoke callbacks while holding a manager lock.

### Absolute rule
Never perform thread hops while holding a manager lock.

---

## Runtime Shutdown State Machine

Shutdown must be explicit and stateful.

Recommended states:

```cpp
enum class RuntimeShutdownState : uint8_t {
    uninitialized = 0,
    initializing,
    initialized,
    shutdownRequested,
    drainingBrowsers,
    drainingCallbacks,
    shuttingDownCEF,
    shutDown
};
```

## Required semantics
### `uninitialized`
No runtime active.

### `initializing`
Initialization is in progress.
Operations requiring ready runtime must fail or wait according to documented policy.

### `initialized`
Normal operation.

### `shutdownRequested`
No new runtimes, browsers, or request contexts may be created.
Existing operations are admitted only according to policy.

### `drainingBrowsers`
Browser close progression is underway.
No new browser activity may be accepted.

### `drainingCallbacks`
Callback queues are being flushed or dropped according to explicit policy.

### `shuttingDownCEF`
Final CEF shutdown is executing.
Only internal shutdown work may proceed.

### `shutDown`
Terminal state.

---

## In-Flight Operation Policy During Shutdown

This must be uniform and documented.

### Recommended policy
Operations acquire a runtime operation snapshot before dispatch.

If shutdown has already progressed beyond the allowed state, they fail immediately.

If they passed pre-dispatch validation but have not yet executed on the target thread, they may still be rejected at execution time using a deterministic shutdown-related result.

### Required checkpoints
- pre-dispatch validation
- pre-execution validation

### Public API requirement
For debugging and internal traceability, code should distinguish:
- rejected before dispatch
- rejected before execution due to shutdown progression

Even if the public ABI compresses these cases, the internal result model and tracing should preserve the distinction.

---

## Public API Semantics Rules

Public APIs must have deterministic lifecycle semantics.

### No misleading success
If an API only means “accepted for dispatch,” document it as such.
Do not imply completion if completion did not occur.

### LoadURL
If current ABI semantics mean request accepted for dispatch rather than navigation completed, document that clearly.

### EvaluateJavaScript
If semantics are fire-and-forget injection only, document that clearly.
Do not imply result-returning evaluation if none exists.

### Logical-only browser operations
Operations requiring native browser presence must fail deterministically when only a logical record exists.

---

## Record Snapshot and Work Admission Rules

Before any operation that hops threads or touches native objects:
- resolve relevant record under owning manager lock
- retain any native refs needed locally
- capture any callback snapshot needed locally
- release lock
- perform thread hop / native work

### Forbidden pattern
- read raw pointer from record
- release lock
- later use raw pointer without retained wrapper

---

## Observability and Tracing Rules

Structured tracing is required.

## Every lifecycle-sensitive event should include correlation fields as applicable
- runtime id
- browser id
- browser generation
- request-context id
- host-view id
- native browser identifier
- callback sequence id or event id
- registration version if relevant
- operation kind
- thread lane
- shutdown state

## Operation kind examples
- `initialize_runtime`
- `shutdown_transition`
- `create_request_context`
- `destroy_request_context`
- `create_browser`
- `create_native_browser`
- `replace_native_browser`
- `attach_browser`
- `detach_browser`
- `destroy_browser`
- `close_browser`
- `load_url`
- `eval_js`
- `enqueue_callback`
- `deliver_callback`
- `drop_callback`
- `thread_hop_main`
- `thread_hop_cef_ui`

## Minimum events to trace
### Runtime
- initialize requested / succeeded / failed
- shutdown transitions
- final CEF shutdown begin / end

### Request Context
- create requested / succeeded / destroyed
- privacy mode
- owning runtime id

### Browser
- logical browser created
- native browser created
- native browser replaced
- generation incremented
- attachment changed
- host-resource loss
- close requested
- close completed
- browser destroyed
- record erased

### Host View
- host registered
- weak host resolved nil
- container created
- container removed
- attach failed due to dead host

### Callback
- callback registered
- callback unregistered
- queued
- delivered
- dropped for inactive browser
- dropped for generation mismatch
- dropped for registration invalidation
- dropped for shutdown state

### Threading
- main-thread hop
- CEF-UI-thread hop
- invariant violation
- sync-hop rejection due to policy

### Rule
If a lifecycle bug cannot be reconstructed from traces, observability is insufficient.

---

## Migration Rules

The bridge is being hardened incrementally.
All migration work must reduce risk, not create uncontrolled churn.

## Recommended migration order
### Phase 0 — observability first
- add structured tracing to current lifecycle hotspots
- add thread/lock assertions
- identify actual crash surfaces with evidence

### Phase 1 — compatibility ref layer
- add `CefBaseTraits.h`
- add `CefRef.h`
- replace highest-risk retain/release sites first
- keep compatibility shims where needed temporarily

### Phase 2 — thread gate
- move all explicit thread hops behind `CefThreadGate`
- assert no lock-held hops

### Phase 3 — browser truth extraction
- introduce `BrowserManager`
- move browser lifecycle truth there first

### Phase 4 — host resource split
- introduce `HostViewManager`
- switch to true weak host storage
- replace subview diffing with explicit container ownership

### Phase 5 — callback hardening
- add generation/version invalidation
- add snapshot-resolution delivery

### Phase 6 — runtime and shutdown
- introduce `RuntimeManager` state machine
- move request-context ownership there
- make shutdown explicit

### Phase 7 — client bundle
- collapse handler/client ownership into one bundle
- assert embedded wrapper layout rules

### Phase 8 — cleanup
- remove legacy global-state helpers
- thin C ABI file
- delete obsolete lifetime paths

## Conditional rule
If current crash evidence implicates handler/client lifetime, move ClientBundle work earlier.

Do not follow migration order blindly if the crash surface says otherwise.

## Current status gate

The CEF layer refactor is not complete while any of the following remain true:

- `MiumCEFBridgeNative.mm` is still a monolith instead of a thin C ABI forwarding file
- subsystem `.mm` files are still `#include`-ed into `MiumCEFBridgeNative.mm`
- browser/runtime/host/callback lifecycle truth still depends on shared native-file globals instead of dedicated owners

As of March 12, 2026, the textual `.mm` composition step is complete: bridge modules compile as linked translation units rather than being `#include`-ed into `MiumCEFBridgeNative.mm`.

As of March 12, 2026, `MiumCEFBridgeNative.mm` is a thin forwarding file at roughly 111 lines. The main bridge logic now lives in linked bridge units such as:

- `MiumCEFBridgeRuntime.mm`
- `MiumCEFBridgeBrowserLifecycle.mm`
- `MiumCEFBridgeBrowserActions.mm`
- `MiumCEFBridgeBrowserContentActions.mm`
- `MiumCEFBridgeBrowserEvents.mm`
- `MiumCEFBridgeMessaging.mm`
- `MiumCEFBridgePopup.mm`
- `MiumCEFBridgeRendererJavaScript.mm`
- `MiumCEFBridgeRendererCamera.mm`
- `MiumCEFBridgeBrowserRegistry.mm`
- `MiumCEFBridgeCallbackQueue.mm`
- `MiumCEFBridgeThreading.mm`
- `MiumCEFBridgeShutdown.mm`
- `MiumCEFBridgeSupport.mm`

That is a real milestone, but the refactor should still be treated as in progress while shared state and internal helper seams remain broader than the long-term architecture wants.

Current bridge seam shape:

- `MiumCEFBridgeNative.mm`: thin public C ABI only
- `MiumCEFBridgeInternalState.h`: shared globals, locks, and guard helpers only
- `MiumCEFBridgeStateModels.h`: browser/runtime state model types only
- `MiumCEFBridgeCefApi.h`: dynamically loaded CEF API table only
- `MiumCEFBridgeInternalRuntimeBootstrapSupport.h`: framework/path/env/bootstrap helpers only
- `MiumCEFBridgeInternalRuntimeExecutionSupport.h`: runtime execution, message-loop, close, and thread-hop helpers only
- `MiumCEFBridgeInternalAdapters.h`: state/lifecycle adapter glue only
- `MiumCEFBridgeInternalPermissionAdapters.h`: permission execution helpers only
- `MiumCEFBridgeInternalRendererMessageAdapters.h`: renderer process-message parsing and result dispatch only
- `MiumCEFBridgeInternalBrowserPayloadSupport.h`: payload, string, and origin formatting helpers only
- `MiumCEFBridgeInternalBrowserMessagingSupport.h`: browser message emission and picture-in-picture/render-process messaging hooks only
- `MiumCEFBridgeInternalPopupSupport.h`: popup interception only
- `MiumCEFBridgeInternalRendererCameraSupport.h`: renderer camera routing only

Work in this framework should now prioritize seam narrowing, verification, and crash-path hardening over more monolith breakup for its own sake.

---

## Testing Requirements

This framework must be tested like systems code.

## Required categories
- lifecycle tests
- attach/detach/destroy ordering tests
- stale-callback rejection tests
- generation invalidation tests
- callback registration invalidation tests
- host-view loss tests
- shutdown-state admission tests
- in-flight shutdown race tests
- thread-hop invariant tests
- client/handler bundle retention tests
- request-context lifetime tests

## Tooling
Use sanitizers where possible, including:
- ASAN
- TSAN

## Required test intent
Tests must validate:
- no borrowed ref escapes across async boundaries
- no callback fires after invalidation unless explicitly allowed
- no host-view disappearance yields dangling access
- shutdown rejects work deterministically at documented checkpoints
- native replacements invalidate stale work
- records remain long enough for stale-work rejection and are erased only when safe

---

## Code Review Checklist

Every change in this framework must be reviewed against this checklist.

### Ownership
- Does this introduce any direct `add_ref`/`release` outside the ref layer?
- Does this store any borrowed CEF pointer durably?
- Is `adopt()` used? If yes, is the `+1` contract cited explicitly?

### Lifecycle truth
- Which manager owns the invariant touched by this change?
- Did this introduce duplicated authority?

### Threading
- Does this perform any thread hop outside `CefThreadGate`?
- Could any sync hop deadlock?
- Are any locks held across thread hops?

### Callbacks
- Is callback validity resolved via snapshot, not ad hoc re-check?
- What invalidates this callback path?
- Is registration lifetime handled explicitly?

### Host views
- Is host storage truly weak?
- Is cleanup explicit via owned container?
- Did any heuristic subview ownership logic sneak back in?

### Shutdown
- What happens if shutdown progresses during this operation?
- Are pre-dispatch and pre-execution checks defined?

### Tracing
- Can this lifecycle path be reconstructed from logs?
- Are correlation ids present?

### Erasure
- When does the affected record stop accepting work?
- When is it erased?
- Can stale work still be rejected deterministically until erasure?

---

## Forbidden Patterns

The following patterns are forbidden unless the architecture is formally amended.

### Forbidden lifetime patterns
- direct `base.add_ref` / `base.release` outside ref layer
- durable storage of borrowed CEF pointers
- raw unretained `NSView*` treated as weak state
- separate child-handler ownership trees with ad hoc releases

### Forbidden threading patterns
- direct `dispatch_sync(dispatch_get_main_queue(), ...)` outside `CefThreadGate`
- thread hops while manager locks are held
- callback invocation under manager locks

### Forbidden UI ownership patterns
- subview diffing to infer what CEF inserted
- heuristic AppKit cleanup
- removing arbitrary host subviews because they “look bridge-owned”

### Forbidden truth duplication
- callback validity decided independently by dispatcher
- browser lifecycle state owned by host/resource layer
- runtime layer mutating browser truth directly

### Forbidden shutdown shortcuts
- boolean-only shutdown flags replacing the state machine
- ad hoc “ignore if shutting down” checks without state semantics

---

## Practical Implementation Notes for Future Agents

When touching this framework, always start by asking:

1. What invariant is being changed?
2. Which manager owns that invariant?
3. Is any borrowed native pointer crossing scope or thread boundary?
4. What happens if shutdown progresses right now?
5. What invalidates this callback path?
6. Does host-view loss change this behavior?
7. Can this be reconstructed from structured traces?

If these questions are not answered in the patch, the patch is incomplete.

---

## Final Standard

This framework must be maintained as a safety-critical bridge layer.

A correct change is not merely one that compiles or passes happy-path tests.
A correct change is one that:

- preserves single-owner invariants
- preserves audited refcount handling
- preserves lexical-only borrowed refs
- preserves deterministic shutdown semantics
- preserves deterministic stale-work rejection
- preserves explicit host/container ownership
- preserves thread-hop safety
- preserves observability

Future work must not reintroduce the giant global-state pattern in smaller disguised pieces.

When in doubt, choose the more explicit ownership model, the more deterministic invalidation model, and the more observable lifecycle path.
