# CEF Bridge Hardening & Architecture Refactor Engineering Guide

## Purpose

This document defines the implementation guide for hardening Navigator's CEF bridge and restructuring the current native bridge code into a safer, more maintainable architecture.

The refactor is aimed at four outcomes:

- memory safety
- thread-safety
- lifecycle correctness
- architectural maintainability

The work includes:

- strengthening CEF struct layout guarantees
- improving callback registration safety
- eliminating data races
- clarifying ownership semantics
- restructuring the large native bridge file into maintainable modules

The end goal is a bridge that:

- is safe under heavy asynchronous activity
- cannot dispatch callbacks into freed contexts
- has explicit lifecycle invariants
- can be audited by future maintainers

## 1. Strengthen CEF Base Access Safety

### Files

- `CefBaseTraits.h`

### Problem

The bridge assumes specific CEF C struct layouts, especially for:

- `cef_request_context_t`
- `cef_preference_manager_t`

If those layouts change in a future vendored CEF update, the bridge could silently misinterpret memory.

### Required Fix

Add compile-time layout validation for all supported CEF base-access assumptions.

Example:

```cpp
static_assert(offsetof(cef_browser_t, base) == 0,
  "CEF layout change: cef_browser_t.base must remain first");

static_assert(offsetof(cef_client_t, base) == 0,
  "CEF layout change: cef_client_t.base must remain first");

static_assert(offsetof(cef_request_context_t, base) == 0,
  "CEF layout change: cef_request_context_t.base moved");

static_assert(offsetof(cef_preference_manager_t, base) == 0,
  "CEF layout change: cef_preference_manager_t.base moved");
```

These assertions ensure:

- vendored headers still match bridge expectations
- ABI breakage fails at compile time instead of becoming a runtime memory bug

### Runtime Validation Change

Replace `assertValidCefBaseAccess(...)` with a dual API:

- `bool hasValidCefBaseAccess(...)`
- a debug-only assert wrapper that calls it

Recommended shape:

```cpp
template <typename T>
inline bool hasValidCefBaseAccess(T* value) {
    if (!value) return true;
    auto* base = cefBaseForValue(value);
    return base && base->add_ref && base->release;
}
```

In debug builds, assert aggressively. In release builds, fail safely instead of assuming access is valid.

## 2. Fix Ownership Semantics in `CefRef`

### Files

- `CefRef.h`

### Problem

`CefRef` currently exposes an implicit pointer conversion:

```cpp
operator T*() const;
```

That hides ownership boundaries and makes it too easy to pass a retained bridge-owned ref where a borrowed pointer is expected.

### Required Fix

Remove the implicit conversion and require explicit raw access via `get()`.

```cpp
// REMOVE
operator T*() const;
```

Usage should become:

```cpp
value.get()
```

### Optional Debug Guard

Add a null assertion to `operator->`:

```cpp
T* operator->() const {
    assert(value_ != nullptr);
    return value_;
}
```

This catches logic errors earlier during development.

## 3. Fix Bridge-Level Handler Context Lifetime

### Files

- `CEFBridge.cpp`

### Problem

Handler contexts are currently stored as ephemeral objects such as:

```cpp
unique_ptr<BridgeMessageHandlerContext>
```

and then passed directly into native callback plumbing.

If a handler is unregistered while callbacks are already queued, native code can still invoke a dangling pointer.

### Required Refactor

Replace ephemeral handler contexts with stable registration objects whose lifetime can outlive unregister and queue-drain races.

Recommended shape:

```cpp
struct BridgeMessageRegistration {
    std::atomic<bool> active{true};
    CEFBridgeBrowserRef browserRef = nullptr;
    std::string channel;
    CEFBridgeMessageCallback callback = nullptr;
    void* userData = nullptr;
};
```

Store registrations as:

```cpp
shared_ptr<BridgeMessageRegistration>
```

Maps should become:

```cpp
unordered_map<BrowserRef, unordered_map<string, shared_ptr<Registration>>>
```

Native callbacks should receive the raw pointer derived from the stable registration object. Unregister should only mark the registration inactive:

```cpp
registration->active = false;
```

Before executing the callback, the native side must check:

```cpp
if (!registration->active) return;
```

This guarantees safe teardown even when queued work outlives handler removal.

## 4. Remove Data Races

### Problem

The bridge currently contains read/write patterns such as:

```cpp
if (!g_initialized) { ... }
```

where the value is written under a mutex but read without one.

### Required Fix

Replace those cross-thread flags with atomics unless there is a strong reason to require lock-only access.

Recommended example:

```cpp
std::atomic<bool> g_initialized{false};
```

Alternatively, guard every read with `g_runtime_mutex`, but atomic state is preferred for simple readiness flags.

## 5. Permission System Improvements

### Files

- `MiumCEFBridgePermissions.h`
- `MiumCEFBridgePermissions.cpp`

### 5.1 Fix Attachment Ownership in Reset

Current reset code copies vectors:

```cpp
batch.attachments = sessionPair.second->attachments;
```

Replace that with a move:

```cpp
batch.attachments = std::move(sessionPair.second->attachments);
```

This preserves single ownership of callbacks and avoids accidental duplication of attachment state.

### 5.2 Clarify Deduplication Policy

The current dedupe key is effectively:

- `browserId`
- `permissionFlags`
- `requestingOrigin`
- `topLevelOrigin`

That intentionally merges multiple native attachments into one permission session.

Document this policy explicitly:

> Multiple requests with identical permission flags and origins are coalesced into a single permission session.

If future behavior needs stricter separation, consider extending the key with:

- `frameIdentifier`
- `source`

## 6. Callback Queue Safety

### Files

- `MiumCEFBridgeNative.mm`

### Problem

Queued payloads currently retain raw user contexts:

```cpp
payload.context = context;
```

Even with handler-generation checks, the raw context pointer can become invalid before queued work executes.

### Required Fix

Introduce a stable callback registration token object and store it in queued payloads instead of storing raw user context directly.

Recommended shape:

```cpp
struct CallbackRegistration {
    std::atomic<bool> active{true};
    void* userContext;
};
```

Queued payloads should hold:

```cpp
shared_ptr<CallbackRegistration>
```

Before invoking a callback:

```cpp
if (!registration->active) return;
```

This prevents queued delivery into freed client-owned memory after unregister or teardown.

## 7. Document Public ABI Contracts

### Files

- `CEFBridge.h`

### Required Documentation

Update the public header to make callback ABI and threading guarantees explicit.

### Callback String Lifetime

For callback arguments such as:

```cpp
const char* message
```

document that string memory is valid only for the duration of the callback invocation. Callers must copy any value they need to retain.

### Threading Guarantees

Document which APIs are main-thread-only, including:

- browser creation
- browser resize
- host-view attachment

Document which callbacks may arrive on a background queue, including:

- message callbacks
- JavaScript completion callbacks
- permission callbacks

Callers must dispatch to the main thread before touching AppKit.

## 8. Rename Misleading Types

### Problem

The following names are misleading because the corresponding objects are not actually no-op state holders:

- `MiumNoopClientState`
- `MiumNoopDisplayHandlerState`

### Required Rename

Rename these state containers to reflect their real purpose:

- `MiumBrowserClientState`
- `MiumBrowserDisplayHandlerState`
- `MiumBrowserRequestHandlerState`

This improves readability and reduces maintenance friction for future engineers auditing the bridge.

## 9. Break the Large Native File into Modules

### Problem

The current native bridge file contains several distinct subsystems with overlapping responsibilities. That makes lifecycle reasoning difficult and causes unrelated concerns to accumulate in one compilation unit.

### Target Architecture

Split the native implementation into the following modules.

### Module 1: `MiumCEFBridgeRuntime.mm`

Responsibility:

- CEF runtime lifecycle

Includes:

- framework loading
- symbol validation
- CEF initialization
- CEF shutdown
- message pump scheduling

### Module 2: `MiumCEFBridgeBrowserRegistry.mm`

Responsibility:

- logical browser state management

Contains:

- `gBrowsers`
- `gHostViews`
- `gRuntimes`
- browser-id mappings
- close tracking
- replacement browser logic

Handles:

- `beginClosingNativeBrowserForIdLocked`
- `finalizeClosedBrowserState`
- pending close counters

### Module 3: `MiumCEFBridgeClient.mm`

Responsibility:

- CEF client implementation

Contains:

- `createNoopClient`
- display handler
- request handler
- permission handler
- load handler
- JS dialog handler

All `CEF_CALLBACK` functions should live here.

### Module 4: `MiumCEFBridgeHostView.mm`

Responsibility:

- AppKit host-view integration

Includes:

- browser container view creation
- attach and detach
- resize
- snapshotting
- host-view validation

### Module 5: `MiumCEFBridgeCallbackQueue.mm`

Responsibility:

- asynchronous callback delivery

Includes:

- `nativeCallbackQueueState`
- `enqueueNativeCallbackPayload`
- overflow policies
- queue draining
- payload filtering

This module should own:

- completion queue
- message queue

### Module 6: `MiumCEFBridgeContentClassification.mm`

Responsibility:

- content classification logic

Includes:

- image, GIF, and HLS detection
- MIME classification
- payload JSON creation
- picture-in-picture observer injection

### Module 7: `MiumCEFBridgePermissions`

This subsystem is already separate and should remain separate.

### Resulting File Layout

- `MiumCEFBridgeRuntime.mm`
- `MiumCEFBridgeBrowserRegistry.mm`
- `MiumCEFBridgeClient.mm`
- `MiumCEFBridgeHostView.mm`
- `MiumCEFBridgeCallbackQueue.mm`
- `MiumCEFBridgeContentClassification.mm`
- `MiumCEFBridgePermissions.cpp`
- `CefBaseTraits.h`
- `CefRef.h`

## 10. Add Invariant Assertions

### Required Assertions

Add debug assertions for internal bridge state consistency.

Examples:

```cpp
assert(!browserState->hostViewBound || browserState->hostViewId != 0);
assert(browserState->nativeBrowser || !browserState->attached);
```

Also assert mapping consistency:

```cpp
if (browserState->nativeBrowser)
  assert(pointerMap[browserState->nativeBrowser] == browserState->id);
```

These checks should fail fast in debug builds whenever lifecycle state becomes contradictory.

## 11. Testing Improvements

Extend automated coverage to include the following scenarios.

### Browser Lifecycle

- create browser
- replace native browser
- detach host view
- close browser
- shutdown runtime

### Permission Sessions

- dedupe behavior
- cancel paths
- browser-close cleanup

### Callback Queues

- handler unregister while queue activity is in flight
- browser close while callbacks remain queued

## Final Outcome

After implementing this guide, the bridge should provide:

- verified CEF ABI compatibility
- safe callback registration lifetimes
- eliminated cross-thread races
- explicit ownership semantics
- clear lifecycle invariants
- modular architecture that future engineers can audit

The resulting bridge should be robust enough to:

- handle heavy asynchronous activity
- tolerate shutdown races
- support future CEF upgrades with confidence
