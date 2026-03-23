# Trackpad Gestures Stability Refactor Guide

## Objective

Refactor the `TrackpadGestures` package into a safer, more predictable subsystem with:

- explicit and typed lifecycle APIs
- deterministic state transitions
- no silent failures
- bounded resource usage
- stable public semantics that do not leak implementation quirks
- process-level isolation for private-framework risk where feasible

This guide is specifically about a complete stability refactor of the current package at:

- [TrackpadGestures](/Users/rk/Developer/Navigator/TrackpadGestures)

It assumes the current implementation remains private-API-backed unless the product chooses to remove `MultitouchSupport` entirely.

## Hard Reality

If raw multitouch capture continues to use the undocumented `MultitouchSupport` ABI in-process, it is not technically credible to promise zero crashes.

The current highest-risk boundary is the private pointer bridge in:

- [PrivateMultitouchBridge.swift](/Users/rk/Developer/Navigator/TrackpadGestures/Sources/TrackpadGestures/PrivateMultitouchBridge.swift)

The only strong way to make private-ABI faults non-fatal to the app is:

1. move the private bridge into a helper process or XPC service
2. keep the app process on a versioned, validated IPC protocol
3. treat helper failure as a recoverable backend failure instead of an app crash

If helper isolation is out of scope, this guide still improves correctness and predictability substantially, but it must not be described as “crash-proof.”

## Current Branch Snapshot

This branch has already completed the first structural pass of the refactor.

- the public facade is now an actor-backed service:
  - [TrackpadGestureService.swift](/Users/rk/Developer/Navigator/TrackpadGestures/Sources/TrackpadGestures/TrackpadGestureService.swift#L3)
- the runtime already talks to a backend protocol instead of directly owning the private bridge:
  - [TrackpadGestureBackend.swift](/Users/rk/Developer/Navigator/TrackpadGestures/Sources/TrackpadGestures/TrackpadGestureBackend.swift#L7)
- stream fan-out is already bounded and state replay is explicit:
  - [AsyncStreamBroadcaster.swift](/Users/rk/Developer/Navigator/TrackpadGestures/Sources/TrackpadGestures/AsyncStreamBroadcaster.swift#L3)
- the service test suite already covers typed startup failures, shared streams, stop barriers, and repeated session cycles:
  - [TrackpadGestureServiceTests.swift](/Users/rk/Developer/Navigator/TrackpadGestures/Tests/TrackpadGesturesTests/TrackpadGestureServiceTests.swift#L5)
- the old controller and action dispatcher have already been deleted from this branch

The remaining work is therefore not “replace the controller.” It is to harden the new service/backend split into a smaller, clearer, and safer long-term contract.

## Current Problems To Fix

### Public API problems

- `start()` now returns `GestureSessionID` and throws typed errors, which is the correct direction:
  - [TrackpadGestureService.swift](/Users/rk/Developer/Navigator/TrackpadGestures/Sources/TrackpadGestures/TrackpadGestureService.swift#L114)
- the public surface still exposes both legacy `TrackpadGestureAvailability` / `TrackpadGestureRuntimeState` and the new `TrackpadGestureCapability` / `TrackpadGestureServiceState`, which leaves the long-term contract ambiguous:
  - [TrackpadGestureModels.swift](/Users/rk/Developer/Navigator/TrackpadGestures/Sources/TrackpadGestures/TrackpadGestureModels.swift#L3)
- `SwipeRightGestureRecognizer` name does not match behavior because it can recognize leftward travel too:
  - [SwipeRightGestureRecognizer.swift](/Users/rk/Developer/Navigator/TrackpadGestures/Sources/TrackpadGestures/SwipeRightGestureRecognizer.swift#L171)
- diagnostics still expose dead or misleading cases such as `.actionDispatched`, even though app command routing has been removed from the package core:
  - [TrackpadGestureModels.swift](/Users/rk/Developer/Navigator/TrackpadGestures/Sources/TrackpadGestures/TrackpadGestureModels.swift#L159)
- `reversalTolerance` is still public configuration even though the recognizer does not read it:
  - [TrackpadGestureModels.swift](/Users/rk/Developer/Navigator/TrackpadGestures/Sources/TrackpadGestures/TrackpadGestureModels.swift#L219)

### Runtime contract problems

- framework failures are still collapsed into coarse stringly-typed backend errors, which makes it hard to distinguish symbol failure, ABI drift, device enumeration failure, and explicit disable policy:
  - [TrackpadGestureModels.swift](/Users/rk/Developer/Navigator/TrackpadGestures/Sources/TrackpadGestures/TrackpadGestureModels.swift#L318)
- `stop()` transitions to `.idle` immediately after `backend.stop()` with no explicit backend-acknowledged quiescence barrier or timeout contract:
  - [TrackpadGestureService.swift](/Users/rk/Developer/Navigator/TrackpadGestures/Sources/TrackpadGestures/TrackpadGestureService.swift#L201)
- framework failure still installs a sticky disabled reason inside the service actor, but the API does not yet classify which failures are retryable versus terminal:
  - [TrackpadGestureService.swift](/Users/rk/Developer/Navigator/TrackpadGestures/Sources/TrackpadGestures/TrackpadGestureService.swift#L245)
- permissions now support both required and degraded policies, but the default product contract is still a policy choice rather than a clearly documented invariant
- multiple internal queues, locks, and callback lifetimes exist, but the external contract does not define barriers clearly

### Safety problems

- undocumented struct layout is mirrored manually:
  - [PrivateMultitouchBridge.swift](/Users/rk/Developer/Navigator/TrackpadGestures/Sources/TrackpadGestures/PrivateMultitouchBridge.swift#L28)
- callback delivery and teardown rely on careful local discipline rather than a hard process boundary
- the broadcaster is bounded now, but ownership still depends on an `NSLock`-backed shared fan-out primitive instead of a purpose-specific runtime stream abstraction:
  - [AsyncStreamBroadcaster.swift](/Users/rk/Developer/Navigator/TrackpadGestures/Sources/TrackpadGestures/AsyncStreamBroadcaster.swift#L3)
- the private bridge still relies on a global callback registry that stays process-wide instead of session- or helper-local:
  - [PrivateMultitouchBridge.swift](/Users/rk/Developer/Navigator/TrackpadGestures/Sources/TrackpadGestures/PrivateMultitouchBridge.swift#L170)

## Refactor Goals

The refactor must deliver the following outcomes.

### Stability

- no silent no-op starts
- no public API that requires diagnostics scraping to know whether startup failed
- no app-facing crash path from malformed backend state if helper isolation is adopted
- no stale session events after `stop()` completion
- no duplicate capture registrations after repeated `start()` calls

### Predictability

- one authoritative runtime state machine
- one typed error model
- one documented stream model
- one documented capability model
- one documented shutdown barrier

### Separation of concerns

- raw capture backend is independent from gesture recognition
- gesture recognition is independent from app command routing
- app command routing is removed from the package or moved behind an explicit adapter
- diagnostics are split into stable operational signals and debug-only telemetry

## Non-Goals

This refactor should not expand product scope.

It is not a goal to:

- add gesture remapping UI
- add many new gestures before the runtime contract is stable
- promise system-gesture suppression
- keep exact source compatibility with every current internal type
- preserve internal implementation details that make the package harder to reason about

## Proposed Target Architecture

Split the package into four layers and one optional helper.

### Layer 1: Public API

Responsibility:

- stable package-facing service API
- typed capability reporting
- typed lifecycle control
- stream access for runtime state and gesture events

Constraints:

- no private imports
- no callback thread assumptions
- no app command routing

Suggested module or folder:

- `Sources/TrackpadGestures/API`

### Layer 2: Runtime Orchestrator

Responsibility:

- own lifecycle state machine
- own current session identity
- bridge backend frames into recognizers
- enforce stop barriers
- expose shared streams

Constraints:

- implemented as an `actor`
- one state mutation path
- no `NSLock` for public orchestration state

Suggested module or folder:

- `Sources/TrackpadGestures/Runtime`

### Layer 3: Gesture Recognition

Responsibility:

- pure deterministic gesture state machines
- gesture arbitration
- replay-testable recognition

Constraints:

- pure Swift values only
- no AppKit
- no backend knowledge
- no global state

Suggested module or folder:

- `Sources/TrackpadGestures/Recognition`

### Layer 4: Capture Backend Adapter

Responsibility:

- normalize backend-originating frames into stable package value types
- manage backend lifecycle
- surface backend faults in typed form

Constraints:

- backend interface is protocol-based
- the runtime does not know whether frames came from helper/XPC or in-process capture

Suggested module or folder:

- `Sources/TrackpadGestures/Backend`

### Optional Layer 5: Helper / XPC Bridge

Responsibility:

- own all private framework loading
- own private ABI pointer parsing
- own callback registration with `MultitouchSupport`

Constraints:

- no app business logic
- strict versioned protocol boundary
- helper crash must not crash the app

## Recommended Public API

Keep the new service-oriented API, but tighten it into a smaller and more explicit contract than the current transitional surface in:

- [TrackpadGestureService.swift](/Users/rk/Developer/Navigator/TrackpadGestures/Sources/TrackpadGestures/TrackpadGestureService.swift)

```swift
public actor TrackpadGestureService {
    public struct Configuration: Sendable, Equatable {
        public var backendPolicy: BackendPolicy
        public var recognizers: [RecognizerConfiguration]
    }

    public enum Capability: Sendable, Equatable {
        case available(AvailabilityDetails)
        case unavailable(UnavailabilityReason)
        case degraded(AvailabilityDetails, degradedBy: [CapabilityWarning])
    }

    public enum State: Sendable, Equatable {
        case idle
        case starting
        case running(SessionID)
        case stopping(SessionID)
        case failed(TrackpadGestureError)
        case disabled(DisableReason)
    }

    public func capability() -> Capability
    public func currentState() -> State
    public func start() throws -> SessionID
    public func stop()
    public func stateUpdates() -> AsyncStream<State>
    public func gestureEvents() -> AsyncStream<GestureEvent>
}
```

### Rules for the new API

- `start()` must either return a `SessionID` or throw `TrackpadGestureError`
- `stop()` must be a completion barrier for the active session
- `capability()` must answer “can the service run on this machine/configuration?”
- `State` must answer “what is the runtime doing right now?”
- gesture events must be pure package events, not app actions
- stream functions must return subscriptions to shared internal broadcasters, never create new capture pipelines

## Replace The Current Model Layer

The current public model file:

- [TrackpadGestureModels.swift](/Users/rk/Developer/Navigator/TrackpadGestures/Sources/TrackpadGestures/TrackpadGestureModels.swift)

should be split into clearer types.

### `Capability`

Use capability to answer static or semi-static readiness.

```swift
public enum UnavailabilityReason: Sendable, Equatable {
    case unsupportedOS
    case backendUnavailable(BackendFailure)
    case permissionDenied(PermissionKind)
    case noTrackpadDetected
    case disabledByPolicy
}
```

### `State`

Use state to answer transient lifecycle.

```swift
public enum ServiceState: Sendable, Equatable {
    case idle
    case starting
    case running(SessionID)
    case stopping(SessionID)
    case failed(TrackpadGestureError)
    case disabled(DisableReason)
}
```

### `TrackpadGestureError`

Add one top-level typed error enum.

```swift
public enum TrackpadGestureError: Error, Sendable, Equatable {
    case alreadyRunning
    case startCancelled
    case capabilityUnavailable(UnavailabilityReason)
    case backendStartFailed(BackendFailure)
    case backendTerminated(BackendTermination)
    case invalidConfiguration(ConfigurationError)
    case recognizerInvariantViolation(String)
}
```

### `GestureEvent`

Separate gesture events from diagnostics.

```swift
public struct GestureEvent: Sendable, Equatable {
    public let sessionID: SessionID
    public let timestamp: TimeInterval
    public let gesture: RecognizedGesture
}
```

### `DiagnosticEvent`

Keep diagnostics but split them into:

- stable operational lifecycle events
- backend faults
- debug telemetry

Do not expose implementation-only event names as permanent public API unless they are intended to remain stable.

## Remove App Command Routing From The Package

This branch has already removed direct app command routing from the package core, which is the right architectural direction.

What remains is contract cleanup:

- package emits gesture events only
- host app adapts those events into commands
- any convenience adapter lives in app code or a clearly separate integration target
- dead diagnostics that imply command routing, such as `.actionDispatched`, should be removed from the stable package API:
  - [TrackpadGestureModels.swift](/Users/rk/Developer/Navigator/TrackpadGestures/Sources/TrackpadGestures/TrackpadGestureModels.swift#L200)

This matters because a stable library API should expose gesture semantics, not one app’s current navigation action.

## Backend Isolation Strategy

### Preferred design: helper process or XPC service

Create a backend process that owns:

- framework `dlopen`
- symbol resolution
- device enumeration
- callback registration
- raw contact parsing

The app process should talk to it over a versioned message contract.

### Required helper protocol messages

- `hello(protocolVersion, supportedFeatures)`
- `backendReady(abiProfile, deviceSummary)`
- `frameBatch(sessionID, frames)`
- `deviceSetChanged(devices)`
- `permissionStateChanged(snapshot)`
- `backendFault(fault)`
- `backendStopped(reason)`

### Helper startup requirements

- validate required symbols before reporting ready
- validate struct size/stride assumptions before reporting ready
- emit exact failure reasons for unsupported configurations
- never partially enter a running state

### Helper shutdown requirements

- unregister callbacks before reporting stopping
- stop and release all devices before exiting
- guarantee no post-stop frame messages for a completed session

### If helper isolation is deferred

If the backend stays in-process temporarily:

- wrap it behind the same backend protocol anyway
- treat the in-process backend as a swappable implementation
- keep all private-ABI code confined to one backend implementation
- do not let runtime or recognizer code import bridge internals

## Runtime State Machine

The runtime should become a single actor-owned state machine.

```swift
enum RuntimeState {
    case idle
    case starting(StartAttempt)
    case running(ActiveSession)
    case stopping(StoppingSession)
    case failed(TrackpadGestureError)
    case disabled(DisableReason)
}
```

### Invariants

- only one active session exists at a time
- a session is identified by one `SessionID`
- a frame from an old session must never produce a gesture in the new session
- `stop()` completion is a barrier after which old-session frames are dropped
- `start()` while already running throws `alreadyRunning`
- `start()` during `stopping` must either wait or fail deterministically

### Runtime responsibilities

- preflight capability
- instantiate backend session
- instantiate recognizer pipeline
- connect backend frames to recognizer reducer
- publish state updates
- publish gesture events
- publish operational faults

## Recognition Refactor

The current recognizer file:

- [SwipeRightGestureRecognizer.swift](/Users/rk/Developer/Navigator/TrackpadGestures/Sources/TrackpadGestures/SwipeRightGestureRecognizer.swift)

should be rewritten into pure reducers.

### Naming

Either:

- rename to `ThreeFingerHorizontalSwipeRecognizer`

or:

- truly limit behavior to rightward recognition only

The current name is inaccurate and should not survive the refactor.

### Configuration cleanup

Configuration must validate its own invariants.

Remove any field that is not enforced, or implement it fully.

Today, `reversalTolerance` is dead configuration and should not remain public in that state.

### Pure reducer shape

```swift
struct HorizontalSwipeRecognizer {
    struct State: Sendable, Equatable { ... }

    mutating func reduce(frame: TouchFrame) -> [RecognizerOutput]
}
```

### Recognizer output

Outputs should be explicit:

- `.stateTransition`
- `.gestureRecognized`
- `.gestureRejected`
- `.debugMetric`

### Recognition requirements

- monotonic timestamp enforcement
- exact duplicate/stale policy
- explicit finger-count invalidation
- explicit timeout handling
- explicit cooldown semantics
- deterministic handling of left vs right travel
- tested threshold edges for every public threshold

## Streaming Contract

The current broadcaster already enforces bounded buffering and optional replay:

- [AsyncStreamBroadcaster.swift](/Users/rk/Developer/Navigator/TrackpadGestures/Sources/TrackpadGestures/AsyncStreamBroadcaster.swift#L3)

That is good enough for the first pass. The remaining work is to make the stream contract explicit and category-specific instead of relying on one generic primitive.

### Required stream semantics

- multiple subscribers share one producer
- late subscribers do not backfill unbounded history by default
- per-subscriber buffering is bounded
- termination removes subscriber state promptly
- stop/start session boundaries are observable

### Recommended buffering choices

- gesture events: newest-only or small bounded buffer
- state updates: latest-value replay of size 1
- diagnostics: bounded ring buffer with explicit truncation policy

## Permission Contract Refactor

The current implementation already supports both required and degraded permission policies:

- [TrackpadGestureService.swift](/Users/rk/Developer/Navigator/TrackpadGestures/Sources/TrackpadGestures/TrackpadGestureService.swift#L78)
- [TrackpadGestureModels.swift](/Users/rk/Developer/Navigator/TrackpadGestures/Sources/TrackpadGestures/TrackpadGestureModels.swift#L265)
- [TrackpadGestureServiceTests.swift](/Users/rk/Developer/Navigator/TrackpadGestures/Tests/TrackpadGesturesTests/TrackpadGestureServiceTests.swift#L18)

The remaining task is to pick the product-default policy and keep the public types aligned with that choice.

### Option A: permissions are required

If gesture capture or action routing requires trust:

- `capability()` returns unavailable with exact permission reason
- `start()` throws `.capabilityUnavailable(.permissionDenied(...))`
- diagnostics may still include raw permission snapshots

### Option B: permissions are optional but affect feature subsets

If recognition can run but some actions need trust:

- `capability()` returns `.degraded`
- gesture events still flow
- app-level adapters decide whether to route actions

Do not keep the current ambiguous middle ground.

## Backend Fault Model

Define typed backend failures.

```swift
public enum BackendFailure: Sendable, Equatable {
    case frameworkUnavailable(pathHints: [String])
    case symbolMissing(String)
    case abiValidationFailed(ABIValidationFailure)
    case sessionRegistrationFailed(String)
    case backendClosed
    case helperLaunchFailed(String)
    case helperProtocolMismatch
}
```

### Fatal vs recoverable faults

Classify each backend failure as:

- recoverable now
- recoverable after restart
- terminal until process restart
- terminal until OS/app update

Avoid the current sticky kill-switch pattern unless it is represented as an explicit disabled state visible to callers.

## Teardown And Stop Barrier

The refactor must define the exact meaning of `stop()`.

### Required semantics

When `stop()` returns:

- the active session is no longer running
- no more gesture events from that session will be emitted
- backend or helper resources for that session are either fully released or detached from the app-facing event path

### Implementation guidance

- mark session stopping before touching the backend
- detach frame ingress from recognizers immediately
- then request backend stop
- then await backend stop confirmation or timeout
- then finalize runtime state

This is stricter than the current design and should remain explicit in tests.

## Memory And Resource Safety

### Remove raw callback reachability from app state

The app-facing runtime should never be directly retained by a C callback closure path.

### Limit buffering

No public stream should be unbounded unless explicitly justified and documented.

### Normalize ownership

Every backend resource owner should be one of:

- runtime session owner
- backend session owner
- helper process

No mixed ownership between global registries and controller state should survive.

### Replace implicit globals where possible

`CallbackContextRegistry` is pragmatic today, but it should become helper-local or backend-local infrastructure, not a package-wide singleton reachable from the app runtime.

## File And Type Migration Map

### Current `TrackpadGestureService.swift`

Current role:

- public facade
- lifecycle orchestration
- session ownership
- recognizer ownership
- stream fan-out
- diagnostics emission

Target:

- keep as the public actor facade
- shrink it toward a stricter runtime contract
- move more lifecycle detail behind dedicated runtime and backend types
- keep app command routing out of the package

### Current `PrivateMultitouchBridge.swift`

Current role:

- private ABI mirror
- loader
- symbol table
- callback trampoline
- device session state

Target:

- isolate behind backend protocol
- move to helper target if feasible
- keep only versioned backend-facing value outputs

### Current `TouchCapture.swift`

Current role:

- source lifecycle
- wake observation
- timer rescan
- device manager

Target:

- keep as backend-side device manager logic
- surface typed backend events instead of service-specific diagnostics

### Current `SwipeRightGestureRecognizer.swift`

Current role:

- one recognizer implementation

Target:

- move into pure recognition layer
- rename for accurate behavior
- convert to reducer-style outputs

### Current `AsyncStreamBroadcaster.swift`

Target:

- either keep as internal infrastructure with clearer semantics
- or replace with dedicated state/gesture/diagnostic broadcasters that encode their contract directly

## Test Plan

The current branch already has meaningful regression coverage. The remaining test work should extend that coverage around the still-open contract gaps.

### Public API tests already present

- `start()` returns `SessionID` on success
- `start()` throws exact typed error on capability failure
- `start()` while running throws `alreadyRunning`
- `stop()` is idempotent
- `stop()` is a hard barrier for event delivery
- multiple subscribers share one producer
- bounded buffers behave as documented

Primary coverage:

- [TrackpadGestureServiceTests.swift](/Users/rk/Developer/Navigator/TrackpadGestures/Tests/TrackpadGesturesTests/TrackpadGestureServiceTests.swift)

### Runtime state machine tests still needed

- cold start success path
- cold start backend failure
- start then immediate stop before backend ready
- helper/backend crash while running
- restart after recoverable backend crash
- terminal disable after repeated crash threshold

### Recognition tests

- exact right-swipe acceptance
- exact left-swipe acceptance or rejection based on final API choice
- threshold edge for minimum horizontal travel
- threshold edge for maximum vertical drift
- threshold edge for maximum duration
- threshold edge for stationary timeout
- reversal behavior if `reversalTolerance` remains
- duplicate/stale frame behavior

### Backend tests

- all symbol-missing paths
- device attach/detach diffing
- session teardown idempotence
- stale callback suppression
- quiescence timeout handling
- malformed raw payload rejection
- helper protocol version mismatch

### Integration tests

- real backend smoke test when environment allows
- helper crash does not crash app
- stop/start cycles do not leak sessions
- wake/sleep rescan contract remains stable

## Migration Sequence

### Phase 0: Freeze current behavior

Status: largely complete

- add missing regression tests around stop barrier, buffering, and typed failure intent
- mark known dead or misleading public cases in docs

### Phase 1: Add the new API alongside the old one

Status: complete on this branch

- introduce new model types
- introduce runtime actor
- old controller has already been removed instead of retained as an adapter

### Phase 2: Extract recognition

Status: partially complete

- move recognizers into pure reducer layer
- remove service-owned recognizer mutation logic

### Phase 3: Introduce backend protocol

Status: complete for the in-process path

- put current in-process multitouch path behind a backend interface
- make runtime independent from bridge details

### Phase 4: Add helper/XPC backend

Status: not started

- move private bridge into helper
- validate protocol and lifecycle behavior

### Phase 5: Remove app command routing

Status: largely complete

- direct routing has already been removed
- finish cleanup by deleting dead routing-oriented diagnostics and keeping adapters outside the package

### Phase 6: Collapse transitional surface area

Status: not complete

- remove dead enums and dead config fields
- simplify diagnostics into stable versus debug-only channels
- tighten backend failures into retryable versus terminal categories

## Rollout Strategy

- ship behind a runtime feature flag
- log backend selection and failure mode
- collect restart counts, backend faults, and stop-barrier violations
- keep ability to disable the feature remotely or via local kill switch
- if helper backend exists, prefer helper backend by default and keep in-process backend only as a debug fallback

## Definition Of Done

The refactor is complete only when all of the following are true.

- `start()` and `stop()` have explicit typed semantics
- silent failure paths are removed
- package emits gesture events, not app-local commands
- public enums no longer contain dead or misleading states
- unbounded stream buffering is removed or justified and documented
- stale-session events cannot escape after stop completion
- backend faults are typed and visible
- private framework code is isolated behind a backend protocol
- helper/XPC isolation is in place, or the remaining in-process crash risk is explicitly documented as accepted

## Recommended First Cuts

If follow-up work needs to be broken into the highest-value next steps from the current branch state:

1. collapse the public surface onto `TrackpadGestureCapability` and `TrackpadGestureServiceState`
2. split diagnostics into stable operational events versus debug-only backend telemetry
3. extract the recognizer into a pure reducer and either rename it or constrain it to rightward-only behavior
4. remove dead public configuration such as `reversalTolerance`
5. add an explicit backend-acknowledged stop barrier with timeout semantics
6. refine backend failures into typed retryable versus terminal cases
7. move the private bridge into a helper

Those steps produce the largest remaining stability and contract gains before helper isolation is complete.
