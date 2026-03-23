# Mium CEF Bridge Framework

This document describes the system architecture of the Mium CEF bridge.

It is the companion to `AGENTS.md`, which defines the engineering rules and safety constraints.

If `AGENTS.md` defines how engineers must behave, this document defines how the system is designed to work.

The bridge is a lifecycle-sensitive native systems component responsible for:

- integrating Chromium Embedded Framework (CEF)
- managing runtime lifecycle
- managing browser instances
- embedding browsers into AppKit views
- safely routing callbacks across native boundaries
- enforcing deterministic shutdown
- protecting against stale native references

This architecture intentionally avoids ad hoc state sharing and relies on explicit ownership boundaries.

## 1. High-Level Architecture

The system is organized as a thin ABI facade plus linked bridge units and narrow internal support seams.

```text
Public C ABI
      │
      ▼
Thin Native Facade
(MiumCEFBridgeNative.mm)
      │
      ▼
Bridge Facade
(CEFBridge / MiumCEFBridge)
      │
      ├──────── Runtime / Shutdown / Paths
      │
      ├──────── Browser Lifecycle / Actions / Content
      │
      ├──────── Browser Registry / Callback Queue / Messaging
      │
      ├──────── Client / Popup / Browser Events
      │
      ├──────── Renderer JavaScript / Renderer Camera
      │
      ├──────── Host View / Threading / Support
      │
      └──────── Shared Internal Seams
                 - state models
                 - CEF API table
                 - runtime bootstrap support
                 - runtime execution support
                 - adapters
                 - browser payload / messaging support
                 - popup / renderer-camera support
                       │
                       ▼
                   CEF Runtime
```

Supporting layers:

- `CefRef` ownership layer
- client / handler bundle layer
- tracing layer

Each subsystem has clear ownership and authority.

No subsystem is allowed to duplicate another subsystem's lifecycle truth.

## 2. Architectural Goals

The design exists to solve specific problems common to CEF bridges.

### Eliminate unsafe pointer lifetimes

CEF uses manual refcounting. Misuse leads to crashes.

The architecture centralizes refcount logic in a dedicated layer.

### Prevent stale callbacks

CEF callbacks can arrive long after browser replacement or shutdown.

The architecture prevents this via:

- generation invalidation
- snapshot-based callback resolution
- terminal record retention

### Avoid UI ownership ambiguity

CEF often inserts its own views.

The architecture avoids heuristics by introducing a container ownership boundary.

### Enforce deterministic shutdown

CEF shutdown must occur in strict order.

The architecture implements a runtime shutdown state machine.

### Make threading explicit

CEF UI thread and AppKit main thread are modeled separately.

Thread transitions are routed through a single gate.

### Make lifecycle bugs debuggable

All lifecycle-sensitive actions produce structured trace events.

## 3. Subsystem Overview

### 3.1 Public C ABI Layer

#### File

`MiumCEFBridgeNative.mm`

#### Responsibilities

- exported C functions
- argument validation
- opaque handle translation
- forwarding into the bridge facade
- result code translation

#### Non-Responsibilities

- lifecycle truth
- resource ownership
- host-view logic
- shutdown sequencing

#### Rule

This file must remain thin.

If logic accumulates here, it belongs in an internal subsystem.

## 4. Bridge Facade

### Files

- `MiumCEFBridge.h`
- `MiumCEFBridge.mm`

### Responsibilities

- API translation
- orchestration between subsystems
- subsystem construction

### Non-Responsibilities

- lifecycle truth
- direct native resource ownership
- host view logic
- callback routing decisions

### Rule

The facade must never become a second monolith.

Complex flows belong in owning managers.

In the current implementation, the facade composes linked bridge units rather than a single native implementation file.

## 5. RuntimeManager

`RuntimeManager` controls the CEF runtime lifecycle.

### Responsibilities

- initialize the CEF runtime
- manage request contexts
- enforce shutdown rules
- prevent browser creation during shutdown

### Runtime State Machine

- uninitialized
- initializing
- initialized
- shutdownRequested
- drainingBrowsers
- drainingCallbacks
- shuttingDownCEF
- shutDown

### Guarantees

- shutdown progresses deterministically
- no new browsers after `shutdownRequested`
- request contexts are owned here

## 6. BrowserManager

`BrowserManager` is the authoritative owner of browser lifecycle truth.

All browser lifecycle decisions originate here.

### Responsibilities

- create logical browser records
- create native browsers
- manage browser replacement
- manage attach/detach flows
- manage destroy flows
- generation invalidation
- callback snapshot resolution

### Browser Record

Example structure:

```text
BrowserRecord
    BrowserID
    RuntimeID
    RequestContextID

    active
    closing

    generation

    attachedHostViewID

    nativeBrowserRef
    nativeClientRef
```

### Generation

Generation increments invalidate stale work.

Generation must increment when:

- native browser is replaced
- host resource is lost
- callback registrations invalidate

## 7. HostViewManager

`HostViewManager` manages embedding resources only.

It does not own browser lifecycle truth.

### Responsibilities

- weak host view references
- container creation
- container removal
- host view resolution

### Container Model

```text
HostView
└── MiumBrowserContainerView
        └── CEF View Hierarchy
```

The container is owned by the bridge.

Heuristic subview detection is not permitted.

## 8. CallbackDispatcher

`CallbackDispatcher` manages callback queues.

### Responsibilities

- enqueue callbacks
- deliver callbacks
- drop callbacks when invalid

### Non-Responsibilities

- determining callback validity
- browser lifecycle decisions

Callback validity is determined by `BrowserManager` snapshot resolution.

## 9. Callback Snapshot Model

Callback delivery must avoid time-of-check/time-of-use errors.

Correct flow:

```text
callback queued
       │
       ▼
snapshot resolved (under BrowserManager lock)
       │
       ▼
lock released
       │
       ▼
callback delivered
```

Snapshots contain:

- callback pointer
- callback context
- browser id
- browser generation
- registration version

If any mismatch occurs, the callback is dropped.

## 10. Host View Loss Handling

Host view disappearance is treated as a deterministic lifecycle event.

When the weak host reference resolves to `nil`:

- `BrowserManager` records host resource loss
- generation increments
- container resources are removed
- host-dependent APIs fail deterministically

Browser transitions to either:

- logical-only
- detached-native-closing

depending on embedding model.

## 11. ClientBundle Architecture

CEF client and handlers are stored in a single allocation.

```text
ClientBundle
    client
    display handler
    lifespan handler
    load handler
    js dialog handler
    permission handler
    request handler
    resource handler
```

Each handler wrapper contains:

```text
cef_handler_struct value
ClientBundle* owner
```

`value` must be the first field.

```cpp
static_assert(offsetof(EmbeddedDisplayHandler, value) == 0);
```

All handlers share a single refcount domain.

## 12. CEF Ref Layer

The ref layer centralizes reference counting.

Components:

- `CefBaseTraits`
- `CefRetainedRef`

Traits determine how to access `cef_base_ref_counted_t`.

`CefRetainedRef` manages safe ownership.

Borrowed references are lexical only.

## 13. Thread Model

Two execution lanes may exist:

- AppKit Main Thread
- CEF UI Thread

They may or may not be identical depending on runtime configuration.

All thread transitions must go through:

- `CefThreadGate`

Responsibilities:

- detect thread
- perform thread hops
- enforce sync-hop safety
- assert invariants

## 14. Sync Hop Rules

Deadlock prevention rules:

- run inline if already on target thread
- never sync hop while holding manager locks
- nested sync hops only when safe

Violations trigger debug assertions.

## 15. Record Lifetime Strategy

Records cannot be erased immediately when work may still reference them.

Browser records move through:

- active
- closing
- terminal
- erased

Terminal records allow stale work rejection before erasure.

## 16. Native Browser Indexing

Native browser pointer maps may exist for lookup.

However they are indexes only, not ownership.

Preferred canonical index:

- `browserIdentifier → BrowserCallbackToken`

Pointer maps are secondary.

## 17. Shutdown Behavior

Shutdown is multi-phase.

## 18. Current Implementation Shape

As of March 12, 2026:

- `MiumCEFBridgeNative.mm` is a thin forwarding file of roughly 111 lines.
- no `MiumCEFBridge*.mm` implementation files are textually included into another implementation file
- bridge behavior is split across linked units such as runtime, browser lifecycle, browser actions, browser content actions, browser events, messaging, popup, renderer JavaScript, renderer camera, registry, callback queue, threading, shutdown, and support
- shared declarations are split into narrow seams instead of one broad internal header

The most important internal seams are:

- `MiumCEFBridgeInternalState.h`
  shared globals, locks, and guard helpers only
- `MiumCEFBridgeStateModels.h`
  browser/runtime state model types only
- `MiumCEFBridgeCefApi.h`
  dynamically loaded CEF API table only
- `MiumCEFBridgeInternalRuntimeBootstrapSupport.h`
  framework/path/env/bootstrap helpers only
- `MiumCEFBridgeInternalRuntimeExecutionSupport.h`
  message-loop, thread-hop, close, and runtime execution helpers only
- `MiumCEFBridgeInternalAdapters.h`
  state/lifecycle lookup glue only
- `MiumCEFBridgeInternalPermissionAdapters.h`
  permission execution glue only
- `MiumCEFBridgeInternalRendererMessageAdapters.h`
  renderer process-message parsing and dispatch only
- `MiumCEFBridgeInternalBrowserPayloadSupport.h`
  browser payload/string/origin formatting only
- `MiumCEFBridgeInternalBrowserMessagingSupport.h`
  browser message emission and PiP/render-process messaging hooks only
- `MiumCEFBridgeInternalPopupSupport.h`
  popup interception only
- `MiumCEFBridgeInternalRendererCameraSupport.h`
  renderer camera routing only

This means the architecture is no longer in the monolith-breakup phase. The remaining work is seam tightening, state-ownership hardening, verification breadth, and crash-path validation.

After `shutdownRequested`:

- no new browsers
- no new request contexts

Operations must validate:

- pre-dispatch admission
- pre-execution admission

This ensures deterministic shutdown behavior.

## 18. Observability Architecture

All lifecycle events emit structured traces.

Required fields:

- runtime id
- browser id
- browser generation
- request context id
- host view id
- operation type
- thread lane
- shutdown state

This allows lifecycle reconstruction after crashes.

## 19. Migration Strategy

Recommended rollout order:

- observability
- ref layer
- thread gate
- browser manager
- host view manager
- callback dispatcher
- runtime manager
- client bundle
- cleanup

Crash evidence may reorder phases.

## 20. Safety Guarantees

When implemented correctly, the architecture guarantees:

- no stale callbacks after browser replacement
- no borrowed pointer escaping async boundaries
- deterministic shutdown
- safe host view disappearance handling
- auditable CEF reference counting
- lifecycle traceability

## 21. Relationship to `AGENTS.md`

`AGENTS.md` defines engineering rules.

`ARCHITECTURE.md` defines system design.

If implementation diverges from this architecture, the deviation must be documented and justified.

If you'd like, I can also generate two additional GitHub-ready docs that dramatically reduce future regressions in CEF bridges:

- `LIFECYCLE.md` for deep diagrams of runtime/browser/callback lifecycles
- `THREADING.md` for precise threading and hop invariants

These two docs are extremely valuable for large native bridge codebases.
