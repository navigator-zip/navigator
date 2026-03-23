# Trackpad Gestures Implementation Guide

## Objective

Implement a private-API-backed trackpad gesture subsystem for macOS, starting with one tightly scoped V1 gesture:

- three-finger swipe-right

The subsystem must:

- use raw multitouch capture as the primary input source
- keep all private API usage quarantined
- expose a small, concurrency-safe Swift API to the app
- degrade safely when symbols, permissions, devices, or OS behavior are unavailable
- remain testable without trackpad hardware through replayable frame fixtures

Community implementations on modern macOS commonly use the private `MultitouchSupport` framework for raw touch coordinates, then use Accessibility APIs for synthetic input, and optionally a `CGEventTap` to coordinate or suppress conflicting events. This package should assume that shape up front instead of drifting into an ad hoc design.

## V1 Scope

V1 only includes:

- three-finger swipe-right
- Apple-built multitouch trackpads explicitly validated by this package
- recognition first
- app-local action routing second
- no gesture remapping UI
- no claim that system gestures can be suppressed unless explicitly verified
- no synthetic mouse or keyboard event posting by default
- one concrete end-to-end success action only

V1 must wire the recognized three-finger swipe-right to exactly one simple app-local command chosen before implementation starts. Do not broaden action routing during the first milestone.

Default V1 success action:

- emit a structured diagnostic event
- invoke exactly one app-local command, such as `navigateForward`

## Non-Goals for V1

V1 does not include:

- a general BetterTouchTool replacement
- an arbitrary gesture editor
- broad multi-gesture support
- guaranteed suppression of built-in system gestures
- App Store-compatible implementation constraints
- synthetic event injection as a required part of the first milestone

## Package

Create a new local Swift package:

- product: `TrackpadGestures`
- test target: `TrackpadGesturesTests`

Primary app integration points:

- [`Navigator/AppDelegate.swift`](/Users/rk/Developer/Navigator/Navigator/AppDelegate.swift)
- [`Navigator/App.swift`](/Users/rk/Developer/Navigator/Navigator/App.swift)
- [`Navigator/AppViewModel.swift`](/Users/rk/Developer/Navigator/Navigator/AppViewModel.swift)

Build expectations:

- dynamically load the private framework at runtime
- do not hard-link `MultitouchSupport`
- isolate all `dlopen` and `dlsym` logic in one file
- log exact symbol failures
- never crash if the framework path or symbol set changes

The current expectation is the usual private framework path under `/System/Library/PrivateFrameworks/MultitouchSupport.framework`, but the package must not assume the path or symbol set is stable forever.

## Architectural Rules

The package must be split into strict layers.

### `PrivateMultitouch`

Responsibilities:

- dynamically load `MultitouchSupport`
- resolve private symbols
- register and unregister raw device callbacks
- convert private callback payloads into package-defined Swift value snapshots immediately

Constraints:

- contains all unsafe/private code
- no recognizer logic
- no action routing
- no private types may escape this layer
- callbacks may arrive on an arbitrary system thread
- callback context ownership must be explicit and auditable
- unmanaged pointers must be created and destroyed in one place only
- no captured Swift closures may cross the bridge without explicit lifetime management
- teardown must guarantee that no callback can outlive its owning Swift object graph

### `TouchCapture`

Responsibilities:

- device registry and callback lifecycle
- built-in trackpad and external Apple trackpad selection
- hot-plug, disconnect, reconnect, and wake/sleep recovery
- emission of normalized `TouchFrame` values

Constraints:

- no gesture recognition
- no synthetic input
- no direct app command routing
- owns callback registration lifecycle
- owns safe buffering or forwarding away from the callback thread

### `GestureCore`

Responsibilities:

- pure Swift recognizer state machines
- deterministic gesture arbitration
- replay-testable recognition over normalized frames

Constraints:

- no private imports
- no AppKit dependencies
- no TCC or permission checks
- no action dispatch
- processes frames through a single serialized execution path
- consumes frames in monotonic timestamp order

### `PermissionState`

Responsibilities:

- Accessibility trust checks
- Input Monitoring checks where relevant
- permission diagnostics

Constraints:

- no gesture logic
- no raw capture logic
- no action routing

### `ActionDispatch`

Responsibilities:

- route recognized gestures to app commands
- optionally host future synthetic input support behind a separate gate

Constraints:

- no raw capture logic
- no recognizer state machine logic
- no private framework imports
- must hop to the main actor before touching app or UI state

### `TrackpadGestures`

Responsibilities:

- public façade
- lifecycle control
- availability reporting
- diagnostic stream exposure

Constraints:

- compose the subsystems without collapsing their boundaries
- owns startup and shutdown sequencing

## Hard Invariants

These are non-negotiable:

- no private-framework struct, symbol, callback type, or opaque handle may escape `PrivateMultitouch`
- all values crossing out of `PrivateMultitouch` must be package-defined Swift value types
- no recognizer code may import or reference bridge internals
- no action dispatch may run inside the raw multitouch callback
- raw callbacks must be converted to value snapshots immediately
- no recognizer logic may depend on callback thread identity
- all cross-thread mutable state must be synchronized explicitly
- `start()` and `stop()` must be idempotent
- repeated starts must not register duplicate callbacks, streams, or device registrations
- repeated stops must not crash, hang, or leak registrations
- gesture recognition must run through a single serialized processing path ordered by monotonic frame timestamp
- no private callback may directly mutate app-facing state
- the feature must fail closed, not crash open

## Public API

Expose a narrow runtime service. The shape is fixed even if names differ:

- `start()`
- `stop()`
- `availability() -> TrackpadGestureAvailability`
- `runtimeState() -> TrackpadGestureRuntimeState`
- `recognizedGestures() -> AsyncStream<RecognizedGesture>`
- `diagnosticEvents() -> AsyncStream<GestureDiagnosticEvent>`

Do not expose raw device frames outside the package façade unless there is a deliberate diagnostics API for them.

Use one public availability enum instead of scattered booleans:

- `.unsupportedOS`
- `.frameworkUnavailable`
- `.noTrackpadDetected`
- `.accessibilityDenied`
- `.inputMonitoringDenied`
- `.captureFailed`
- `.running`

If synthetic input is not enabled in V1, `.accessibilityDenied` may still exist in the model even if it is not yet required for the default action path.

Availability describes whether the subsystem can be started in principle. Transient runtime failures after startup must be surfaced through diagnostics and runtime state, not by collapsing all failures into availability alone.

Stream subscription semantics must be documented explicitly. The implementation must not accidentally create multiple capture pipelines because multiple consumers called `recognizedGestures()` or `diagnosticEvents()`.

Required stream rules:

- calling `recognizedGestures()` must subscribe to a shared fan-out source, not create a new capture pipeline
- calling `diagnosticEvents()` must subscribe to a shared diagnostic source, not create a new capture pipeline
- buffering behavior for late subscribers must be documented explicitly
- behavior on `stop()` must be documented explicitly
- if `start()` creates a new run session, streams and diagnostics must make that boundary observable

Add a public or package-visible runtime state model for transient health:

- `.stopped`
- `.starting`
- `.running`
- `.degraded`
- `.stopping`
- `.failed`

## Device Lifecycle Requirements

Device handling is a first-class subsystem, not an implementation detail.

Add a `TrackpadDeviceManager` or equivalent that handles:

- built-in trackpad versus Magic Trackpad
- multiple simultaneous compatible pointing devices
- choosing whether to monitor one device or all compatible devices
- device add and remove events
- callback re-registration after wake/sleep
- reconnect behavior without requiring app restart

Include at least a lightweight sleep/wake validation pass early in implementation, since wake behavior often forces device-registration design changes.

This area is one of the most common failure points in custom trackpad tooling, so it must be explicit in the design from day one.

## Capture Layer Requirements

The capture layer must:

- dynamically load required symbols from `MultitouchSupport`
- support built-in and external Apple trackpads where possible
- detect device add/remove and re-register callbacks
- unregister cleanly on stop and teardown
- never expose private structs above the bridge
- log framework path and symbol failures precisely
- fail safely when registration or callback startup fails

Add a runtime kill switch:

- launch argument, environment variable, or equivalent local feature flag
- one-shot fail-closed behavior after a fatal bridge failure
- no repeated startup crash loops if the bridge is broken on a given OS build

Also log:

- runtime macOS version
- symbol presence or absence
- device count and selected device strategy

Compatibility policy:

- support the current development macOS baseline first
- treat nearby versions as best-effort
- if symbols differ, fail closed
- do not add compatibility shims until a concrete version mismatch is observed

## Normalized Data Model

Define package-local value types for:

- `TouchContact`
- `TouchFrame`
- `TouchContactPhase`
- `GestureDirection`
- `GesturePhase`
- `RecognizedGesture`
- `GestureRejectReason`
- `GestureDiagnosticEvent`
- `GestureSessionID`
- `SwipeRightRecognizerConfiguration`

`TouchFrame` should include:

- monotonic timestamp
- active contacts
- stable per-contact identifiers if available
- centroid
- derived motion metadata used for diagnostics must be reproducible from the frame data or explicitly documented as computed state

Normalization rules must be explicit:

- compute centroid from active contacts
- choose a single timestamp source of truth
- document whether coordinates are device-space or normalized-space
- define smoothing behavior for short-frame jitter
- define dropped-frame tolerance
- define incidental contact and palm rejection policy
- define expectations around per-contact identity stability
- define stale or out-of-order frame handling

All gesture thresholds and timing constants must live in typed configuration objects, not inline magic numbers.

`SwipeRightRecognizerConfiguration` or equivalent must own:

- minimum horizontal travel
- maximum vertical drift
- maximum duration
- cooldown interval
- smoothing window
- stationary timeout
- reversal tolerance
- confidence thresholds

Configuration must be injectable into tests and replay.

Private low-level fields such as velocity, angle, ellipse axes, or timestamps must be normalized immediately instead of leaking private struct layout upward.

## Gesture Arbitration and Recognition

Recognition requires more than “did three fingers move right.” Add an explicit arbitration pipeline:

- `idle`
- `possibleSwipeRight`
- `trackingSwipeRight`
- `committed`
- `cooldown`

Required recognizer rules:

- exactly three active contacts
- minimum rightward centroid travel
- bounded vertical drift
- bounded duration
- minimum confidence before commitment
- cancel on finger-count instability
- cancel on prolonged stationary hold
- cancel on dominant leftward or diagonal movement
- cancel on reversal before commitment threshold is crossed
- once committed, ignore post-commit frame noise until end or cooldown
- cooldown after completion to prevent duplicate firing

Ordering guarantees:

- frames must be processed in monotonic timestamp order
- stale or out-of-order frames must be dropped or handled by a documented rule
- replay tests must include out-of-order and duplicate-frame scenarios

Recognition bugs in this kind of feature usually come from weak arbitration rather than weak sampling. The structure above exists to prevent the classic false-positive case where a recognizer sometimes fires during scrolling or transitional finger movement.

Do not implement recognizer transitions through property observers or hidden side effects.

## Replay Harness

Add a replay test harness that can feed recorded normalized frames into `GestureCore`.

Support a stable fixture format such as JSON or compact binary snapshots over normalized `TouchFrame` values.

Fixture production rules:

- fixtures must record normalized frames, not private raw structs
- a debug-only recorder may capture normalized `TouchFrame` traces
- fixtures should include metadata such as device type, OS version, frame count, and expected result
- no private struct dumps or binary memory layouts may be used as persistent fixtures

Store fixtures for:

- true-positive three-finger swipe-right
- left swipe
- diagonal swipe
- two-finger scroll
- four-finger gesture
- finger count changes mid-gesture
- jittery near-threshold traces

Replay tests should verify:

- recognized gesture count
- duplicate-fire resistance
- cancel and reject reasons
- bounded latency from threshold crossing to emitted gesture

This harness is required because hardware-only validation is too slow and too fragile for threshold tuning.

## Permissions

Permission handling must be explicit and factually correct.

Rules:

- raw `MultitouchSupport` capture must not assume permission coupling unless the chosen action path requires it
- listen-only `CGEventTap` paths are governed by Input Monitoring
- modifying event taps and synthetic event posting are governed by Accessibility
- `AXIsProcessTrustedWithOptions` is the standard way to check or request Accessibility trust
- if a recognized gesture only routes to an internal app command, synthetic input permission may not be needed
- do not request broader permissions than the active action path actually needs

Permission state must not be inferred indirectly from recognizer or action failures. Model it directly and report it directly.

## Action Routing

V1 action routing should be internal only:

- convert a recognized gesture into an app command or callback
- do not synthesize mouse or keyboard events in the first pass
- do not require `CGEventTap` or Accessibility permission unless the chosen V1 action path actually needs them

Synthetic input, if added later, must live behind a separate dispatcher and permission gate so that capture and recognition remain independently testable.

## Diagnostics

Diagnostics must be structured rather than ad hoc print statements.

Emit traces for:

- subsystem startup
- runtime OS version
- symbol resolution
- permission checks
- device registration and unregistration
- frame throughput and dropped-frame counters
- recognizer state transitions
- gesture accept and reject reasons
- action dispatch outcome
- shutdown
- last failure reason

Add a verbose mode for frame-level logging and sampling when gesture tuning needs raw inspection.

Every diagnostic event must include a `GestureSessionID` so that startup, runtime, and teardown traces can be correlated across repeated `start()` and `stop()` cycles.

Without this trace model, threshold tuning tends to become guesswork.

## Latency and Reliability Targets

Define success numerically for V1:

- target detection latency from commitment threshold crossing to app callback
- maximum duplicate fire count per completed gesture
- zero triggers during common two-finger scroll replay traces
- minimum true-positive rate on the replay corpus

Exact values can be tuned later, but the document should not treat “reliable” as purely subjective.

## Execution Order

Implement in this order:

1. scaffold `TrackpadGestures` and the public availability model
2. implement the public façade and diagnostic streams
3. implement the dynamic private-framework bridge
4. implement the device registry and callback lifecycle
5. define the normalized touch-frame model
6. implement the recognizer arbitration state machine
7. add replay harness and recognizer tests
8. integrate app-local command routing
9. add permission helpers
10. wire startup behind a feature flag or kill switch
11. validate sleep, wake, and reconnect behavior
12. validate end to end on real hardware

## Verification Criteria

Do not claim completion until all of the following are true:

1. Cold launch succeeds without crash.
2. Symbol load failure disables the subsystem cleanly.
3. No-trackpad path reports unavailable cleanly.
4. Permission-denied paths do not break the app.
5. A real three-finger swipe-right triggers exactly one event.
6. Common two-finger scrolling does not trigger false positives.
7. Repeated start and stop cycles do not leak callbacks or duplicate streams.
8. Wake, sleep, or device reconnect does not require app restart.
9. Package tests and replay tests pass.

## Repo-Specific Constraints

The implementation must also follow repo rules:

- keep side effects out of `didSet` and `willSet`
- avoid `Task.detached`
- keep unsafe concurrency escape hatches quarantined to infrastructure code only
- avoid public default arguments on injectable or hot-reload-facing APIs
- define typed constants instead of hardcoded internal string keys
- if user-facing text is added, define it in the local package’s `Localizable.xcstrings`
- use `AsyncStream` or bounded task coordination instead of checked continuations

## Command-Level Verification

When implementation begins, validate only the touched modules and follow repo formatting rules:

1. `make validate-xcstrings`
2. `swift test --package-path TrackpadGestures`
3. `make format`

If strict-concurrency cleanliness is not trivially obvious, run the relevant package build or test command and resolve all diagnostics before claiming completion.
