# Engineering Guide: Harden the MultitouchSupport Dynamic Bridge

## Objective

Rewrite the current MultitouchBridge loader/binding file so that it is:

- safe under repeated start/stop cycles
- explicit about ownership and teardown sequencing
- resistant to private-API ABI drift
- idempotent during shutdown
- structured so later device/session code cannot accidentally call into an unloaded framework
- diagnosable when failures occur

This guide is scoped to the file you pasted, but it also defines the contract that the rest of the Multitouch subsystem must follow.

## Summary of what is wrong today

The current file has six major risk areas.

### 1. Loader fallback behavior is wrong

Today, if a framework candidate successfully opens but one symbol fails to resolve, the loader closes that handle and immediately returns failure. It does not continue trying the remaining candidates.

That means a partially compatible first candidate can prevent a valid later candidate from being used.

### 2. The bridge exposes raw function pointers with no lifecycle state

Once `MultitouchBridge.operations` is handed out, callers can theoretically keep using those closures even after `close()` is called. That is an unsafe design for any callback-driven dynamic library, and especially unsafe for a private framework.

### 3. dlclose is too dangerous for this use case

Because this framework drives callbacks on framework-owned threads, unloading the image while device teardown is still in progress is risky. Recent observed crash behavior around unregister/stop sequencing reinforces that teardown is not synchronously complete at the point those calls return.

### 4. Teardown ordering is underspecified

This file doesn’t itself call `releaseDevice`, but it defines the bridge in a way that makes it easy for higher layers to do:

- unregister callback
- stop device
- release device
- close library

with no drain barrier or quiescence model in between.

That pattern is exactly the one most likely to produce intermittent teardown crashes.

### 5. Private ABI assumptions are not isolated enough

`MTTouchContactRecord` and the callback signature are handwritten guesses against a private framework. That may be workable, but it must be treated as an unstable boundary.

### 6. Resource ownership is too implicit

`MTDeviceCreateList()` returns `Unmanaged<CFArray>?`, but the ownership contract is not centralized. Private API plus unmanaged Core Foundation return values is a classic source of leaks and over-releases.

## Rewrite goals

The engineer implementing this should aim for the following architecture:

1. Split loading from runtime usage  
   One type only loads and resolves symbols.  
   Another type owns the opened framework lifetime.  
   A higher-level session type owns device registration/start/stop/release.
2. Do not expose raw function pointers with no lifecycle state  
   Operations should only be callable through a lifetime-checked object.
3. Make shutdown stateful and idempotent  
   Calling shutdown twice must be harmless.  
   Calling any API after shutdown must be prevented or fail deterministically.
4. Assume teardown is asynchronous  
   Unregister does not mean no more callbacks are possible immediately.  
   Stop does not mean the device can be released immediately.  
   Release does not mean the framework can be unloaded immediately.
5. Prefer process-lifetime framework residency  
   In practice, do not `dlclose` unless there is a very strong reason and all device sessions are already drained.

## Recommended architecture

### Layer 1: `MultitouchFrameworkLoader`

Responsibility:

- iterate candidate paths
- `dlopen`
- resolve all required symbols
- if any symbol is missing, close and continue to next candidate
- only return failure after all candidates are exhausted

This layer should not expose device operations directly.

### Layer 2: `LoadedMultitouchFramework`

Responsibility:

- own the resolved symbol table
- own the dynamic library handle
- track whether unloading is allowed
- preferably never unload during normal app runtime

This should be a reference type, not a struct, because it is a resource owner with mutable state and idempotent shutdown behavior.

### Layer 3: `MultitouchDeviceSession`

Responsibility:

- own exactly one `MTDeviceRef`
- own exactly one callback registration lifecycle
- enforce a strict state machine
- serialize teardown

This is the layer that should call:

- register callback
- start
- unregister callback
- stop
- release device

It should not be the generic bridge loader.

## API surface and behavior requirements

### Fix loader fallback behavior

- Current behavior: `dlopen` succeeds, one symbol lookup fails, loader returns failure immediately.
- Desired behavior: `dlopen` succeeds, one symbol lookup fails, close handle, continue to next candidate, and only fail after exhausting all candidates.

Pseudocode:

```swift
func load(...) -> Result<LoadedMultitouchFramework, MultitouchBridgeLoadFailure> {
    var attemptedPaths: [String] = []
    var lastFailure: MultitouchBridgeLoadFailure?

    for path in frameworkCandidates {
        attemptedPaths.append(path)

        guard let handle = dynamicLibraryClient.open(path) else {
            continue
        }

        do {
            let symbols = try resolveAllSymbols(handle: handle, ...)
            return .success(LoadedMultitouchFramework(handle: handle, symbols: symbols, path: path))
        } catch let failure as MultitouchBridgeLoadFailure {
            lastFailure = failure
            dynamicLibraryClient.close(handle)
            continue
        } catch {
            lastFailure = .frameworkUnavailable(String(describing: error))
            dynamicLibraryClient.close(handle)
            continue
        }
    }

    return .failure(lastFailure ?? .frameworkUnavailable(attemptedPaths.joined(separator: ", ")))
}
```

### Fix the operations API shape

Replace free-form bag of closures with symbol table object:

```swift
struct MultitouchSymbolTable {
    let createDeviceList: MTDeviceCreateListFunction
    let registerCallback: MTRegisterContactFrameCallbackFunction
    let unregisterCallback: MTUnregisterContactFrameCallbackFunction
    let startDevice: MTDeviceStartFunction
    let stopDevice: MTDeviceStopFunction
    let releaseDevice: MTDeviceReleaseFunction
}
```

This symbol table should be private to the framework owner/session types.

### Idempotent and explicit close semantics

Close operations must be deterministic:

- closing twice is harmless
- closing while sessions exist is prevented
- using symbols after close should trap in debug and fail safely in release
- callbacks cannot outlive the close boundary

Example:

```swift
func close() {
    lock.withLock {
        guard !isClosed else { return }
        precondition(activeSessionCount == 0, "Attempted to close Multitouch framework with active sessions")
        dynamicLibraryClient.close(handle)
        isClosed = true
    }
}
```

For production, strongly prefer no-op unload behavior and process-lifetime framework residency.

### Explicit session state machine

Minimum state machine:

```swift
enum SessionState {
    case created
    case callbackRegistered
    case started
    case stopping
    case stopped
    case released
    case failed
}
```

Invariants:

- `registerCallback` only allowed in `.created`
- `startDevice` only allowed after callback registration
- `unregisterCallback` only allowed if callback is registered
- `stopDevice` only allowed after start
- `releaseDevice` only allowed after stop has quiesced
- nothing allowed after `.released`

### Safe shutdown contract

Treat shutdown as staged and asynchronous, not as three synchronous calls:

1. **Stage 1: Mark session as stopping**  
   flip internal state so callback no longer forwards touches into business logic.  
   New events may still arrive briefly, but should be ignored.
2. **Stage 2: Unregister callback**  
   Call `MTUnregisterContactFrameCallback(device, callback)`.  
   This means future callback association, not guaranteed zero callback in-flight.
3. **Stage 3: Stop device**  
   Call `MTDeviceStop(device)` after unregister.
4. **Stage 4: Wait for quiescence**  
   Wait until there is evidence callbacks are drained, then proceed.
   - Preferred: in-flight reference counting + quiet interval.
   - Fallback: conservative delay window if needed (centralized, configurable).
5. **Stage 5: Release device**  
   Only after quiescence:
   - call `MTDeviceRelease(device)`
   - nil out local ownership immediately after success
6. **Stage 6: Framework unload**  
   Default: do not unload.  
   Optional explicit unload (test-only) only when all sessions are released and callbacks are drained, and idempotent.

### Callback wrapping and quiescence tracking

Do not pass the raw C callback into business logic. Use a wrapped context:

```swift
final class CallbackContext {
    let sessionID: UUID
    weak var owner: MultitouchDeviceSession?
    let lock = OSAllocatedUnfairLock(...)
    var isStopping = false
    var inFlightCount = 0
    var lastCallbackUptime: UInt64 = 0
}
```

C callback trampoline:

- recover context from refcon
- increment in-flight count on entry
- update last-callback timestamp
- if stopping, do minimal work and return
- validate pointer/count before parsing records
- forward parsed contacts to owner on intended queue/actor
- decrement in-flight count on exit

This enables:

- avoiding work after logical stop
- quiescence detection
- centralized pointer parsing

### Ownership and ABI hardening for `MTTouchContactRecord`

Add explicit documentation and runtime validation around private ABI assumptions:

- Document origin of field assumptions, validated macOS versions/hardware, and drift signals.
- In debug builds, assert/log:
  - `MemoryLayout<MTTouchContactRecord>.size`
  - `stride`
  - `alignment`
- Optionally assert known-good reference size.

### Centralized CF ownership handling

`MTDeviceCreateList()` return values currently leak ownership semantics to callers. Replace with boundary method:

```swift
func createDeviceList() throws -> [MTDeviceRef] {
    guard let unmanaged = symbols.createDeviceList() else { return [] }
    let cfArray = unmanaged.takeRetainedValue()
    ...
}
```

If ownership is uncertain, document the uncertainty and validate with Instruments.

## Concurrency model

All device lifecycle mutation should be serialized by a single execution domain:

- actor
- dedicated serial queue
- main actor if acceptable

Callbacks may originate on framework threads, so mutations should not interleave unsafely:

- register
- start
- begin shutdown
- unregister
- stop
- quiescence wait
- release

## Diagnostics to add

Structured events for:

- framework candidate open attempt
- framework candidate open success
- symbol resolution success/failure per symbol
- device list creation attempt/result count
- session created
- callback registered
- device started
- shutdown requested
- callback ignored while stopping
- unregister invoked
- stop invoked
- callback in-flight transitions
- quiescence achieved
- release invoked
- release completed
- framework close attempted/skipped/completed

Each log should include:

- session UUID
- device pointer address
- current state
- monotonic timestamp

## Concrete implementation plan

### Phase 1: Refactor loader only

Deliverables:

- `MultitouchFrameworkLoader`
- `LoadedMultitouchFramework`
- symbol table type
- corrected candidate fallback behavior
- no public close-library closure
- no public operations bag

Acceptance:

- symbol failure on candidate 1 still allows candidate 2 to be tried
- loader diagnostics clearly distinguish open vs usable-load

### Phase 2: Add device session wrapper

Deliverables:

- `MultitouchDeviceSession`
- explicit state machine
- callback context/trampoline
- serialized lifecycle methods

Acceptance:

- cannot call start twice
- cannot call release before stop
- cannot use session after release
- repeated shutdown is safe

### Phase 3: Implement safe shutdown barrier

Deliverables:

- in-flight callback counting
- stopping flag
- last-callback timestamp
- configurable quiet period threshold
- optional conservative fallback delay

Acceptance:

- repeated rapid start/stop cycles do not crash
- shutdown does not rely on ad-hoc sleeps
- `MTDeviceRelease` only invoked after barrier completion

### Phase 4: Remove or neuter dlclose

Deliverables:

- framework lifetime policy
- production keeps framework loaded until process exit
- optional test-only unload path guarded by assertions

Acceptance:

- no production code path unloads while sessions may still exist

### Phase 5: ABI hardening

Deliverables:

- `MTTouchContactRecord` validation comments
- debug-time size/alignment assertions
- isolated raw-pointer parser
- copy-out stable parsed touch model

Acceptance:

- no higher-level code touches raw contact pointers
- all private ABI assumptions are centralized in one file

## Final recommendation

Treat `MultitouchSupport` as a callback-driven subsystem with asynchronous teardown rather than a synchronous C library.

That mindset drives:

- owned framework lifetime
- session state machine
- quiescence-aware shutdown
- no eager unload
- minimal raw-pointer exposure

