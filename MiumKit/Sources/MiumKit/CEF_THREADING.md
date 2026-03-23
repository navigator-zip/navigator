# CEF_THREADING.md

This document defines the threading contract for the CEF integration in this repository.

It exists because CEF is extremely sensitive to thread correctness. Many crashes that appear inside:

`cef_do_message_loop_work()`

are actually caused by earlier thread violations.

This file is written for future engineers and agents. Treat it as a hard contract.

## 1. Executive summary

This integration uses:

- macOS
- AppKit
- CEF C API
- dynamically loaded CEF framework
- single-threaded browser process message loop
- manual pumping with `cef_do_message_loop_work()`

In this architecture:

- the CEF browser-process UI thread is the macOS main thread.

That means:

- all AppKit view work must run on main thread
- all browser-process CEF object usage must run on main thread
- all manual message loop pumping must run on main thread
- browser creation, browser destruction, frame access, host access, JS execution, navigation, and most callback-driven browser work must be treated as main-thread-only

If you are not absolutely sure a CEF action is safe off-thread, assume it is not.

## 2. Canonical thread model for this repository

Host application threads

There are many possible threads in the host process, but only one matters for CEF browser objects:

- Main thread
  - AppKit UI thread
  - CEF browser-process UI thread in this integration

Other background queues may exist for:

- callback delivery
- logging
- file IO
- state bookkeeping
- tests

Those queues are not allowed to touch live CEF browser/frame/host objects.

## 3. The most important invariant

Invariant A

All live CEF browser object usage must happen on the main thread.

This includes any usage of:

- `cef_browser_t*`
- `cef_browser_host_t*`
- `cef_frame_t*`
- `cef_process_message_t*`
- `cef_client_t*`

unless the specific operation is clearly documented and intentionally designed otherwise.

In this codebase, do not invent exceptions.

## 4. Why this matters

CEF has its own internal thread model. In single-threaded message loop mode, the browser-process UI work is serviced by your app thread when you call:

`cef_do_message_loop_work()`

Because of that, the main thread becomes the thread that owns browser UI state.

If you call CEF browser APIs from some other GCD queue just because it is serialized, that does not make it safe.

This is the critical mistake future agents must never make:

"I have a dedicated serial queue, so that is effectively the CEF thread."

That is false.

A serial queue is only serialization. It is not the browser-process UI thread.

## 5. What is main-thread-only

The following operations are main-thread-only in this repository.

### 5.1 Runtime lifecycle

These must run on the main thread:

- `cef_execute_process(...)`
- `cef_initialize(...)`
- `cef_shutdown()`
- `cef_do_message_loop_work()`

Application argument contract in this repository:

- `cef_execute_process` is called with a fresh subprocess `cef_app_t` wrapper
- `cef_initialize` is called with a fresh browser-process `cef_app_t` wrapper

Do not reuse one `cef_app_t*` across both calls.
Keep the `cef_app_t` passed to `cef_initialize` alive until final `cef_shutdown()` completes.

### 5.2 Browser creation

These must run on the main thread:

- `cef_browser_host_create_browser_sync(...)`

and all setup directly coupled to it:

- `cef_window_info_t` population that depends on NSView
- parent view binding
- synchronous browser creation
- subview observation after creation

### 5.3 Browser methods

Any call through `cef_browser_t*` must be treated as main-thread-only, including:

- `browser->go_back(browser)`
- `browser->go_forward(browser)`
- `browser->reload(browser)`
- `browser->stop_load(browser)`
- `browser->is_loading(browser)`
- `browser->can_go_back(browser)`
- `browser->can_go_forward(browser)`
- `browser->get_main_frame(browser)`
- `browser->get_host(browser)`
- `browser->get_identifier(browser)`
- `browser->is_valid(browser)`

### 5.4 Frame methods

Any call through `cef_frame_t*` must be treated as main-thread-only, including:

- `frame->load_url(frame, ...)`
- `frame->execute_java_script(frame, ...)`
- `frame->send_process_message(frame, ...)`
- `frame->is_main(frame)`

### 5.5 Host methods

Any call through `cef_browser_host_t*` must be treated as main-thread-only, including:

- `host->close_browser(host, ...)`
- `host->notify_move_or_resize_started(host)`
- `host->was_resized(host)`

### 5.6 CEF string/process message creation helpers

Treat these as main-thread-only for consistency unless there is a very strong reason otherwise:

- `cef_process_message_create(...)`

The string conversion helpers loaded from CEF:

- `cef_string_utf8_to_utf16`
- `cef_string_utf16_clear`
- `cef_string_list_size`
- `cef_string_list_value`

must also be considered unsafe to call from arbitrary threads in this bridge because their function pointers live inside the dynamically loaded framework and are part of the same teardown risk surface.

## 6. What is allowed off the main thread

These things may happen off-thread, as long as they do not touch live CEF objects:

- copying plain C++ state
- moving strings
- updating bookkeeping maps under locks
- draining callback queues
- file path resolution
- filesystem probing
- JSON parsing that does not use CEF APIs
- building plain payloads for later main-thread dispatch

Rule of thumb:

If the work does not dereference a `cef_*` object and does not call a function pointer loaded from the CEF framework, it may be okay off-thread.

## 7. Approved dispatch pattern

If a function needs to use a CEF object, do this:

```cpp
runOnCefMainThread([&] {
  // CEF object access here
});
```

If a function needs to use AppKit views and CEF objects together, that also belongs on the main thread.

Examples:

```cpp
runOnCefMainThread([&] {
  cef_browser_host_t* host = browser->get_host(browser);
  if (host && host->was_resized) {
    host->was_resized(host);
  }
  releaseOwnedCefRef(host);
});
```

```cpp
runOnCefMainThread([&] {
  initializeWindowInfoForHostView(info, hostView);
  created = gCefApi.createBrowserSync(&info, client, &blankURL, &settings, nullptr, nullptr);
});
```

## 8. Forbidden dispatch pattern

Do not introduce a dedicated serial queue and use it for browser operations.

Wrong:

```objc
dispatch_queue_t queue = dispatch_queue_create("cef.queue", DISPATCH_QUEUE_SERIAL);

dispatch_async(queue, ^{
  browser->reload(browser);
});
```

Wrong:

```cpp
runOnCefExecutor([&] {
  browser->go_back(browser);
});
```

if `runOnCefExecutor` is anything other than main-thread dispatch.

If a helper called `runOnCefExecutor` exists, it must be equivalent to main-thread execution in this project. If it ever stops being equivalent, this document must be updated and the architecture must be revisited.

## 9. Current architectural assumption

At the time of writing, this repository supports two browser-process scheduling modes:

```cpp
settings.multi_threaded_message_loop = 0;
settings.external_message_pump = 0;  // default
settings.external_message_pump = 1;  // only when a browser-process handler schedules work on main
```

The default path remains manual pumping on the main thread. The external-pump path is experimental
and only valid when paired with a live `cef_app_t` / browser-process handler implementation that
forwards `OnScheduleMessagePumpWork` onto the main thread.

Because of that, any future agent must preserve the following invariant:

Invariant B

The only thread allowed to service browser-process UI work is the main thread.

This means `cef_do_message_loop_work()` must only ever be called on the main thread.

## 10. Why external_message_pump matters for threading

Do not enable:

```cpp
settings.external_message_pump = 1;
```

unless the codebase also introduces a real browser-process scheduling bridge via `cef_app_t` /
browser-process handler and documents a new threading model.

Why:

- manual pumping and external pump are different models
- mixing them produces undefined behavior
- crashes often appear at `cef_do_message_loop_work()`

For this repository, keep the model strict:

- no multithreaded loop
- main thread only
- use either manual pumping or external pump scheduling, never both
- when external pump is enabled, honor `OnScheduleMessagePumpWork` and disable the host fixed timer

## 11. Main-thread helpers: required semantics

### runOnCefMainThread

This helper must satisfy:

- if already on main thread: run inline
- otherwise: synchronously or asynchronously marshal to main thread depending on helper contract
- never invoke CEF work on a background thread

### runOnCefExecutor

If this helper exists in this repository, it must either:

- be an alias for main-thread execution, or
- be removed/renamed to avoid misleading future engineers

The name "executor" is dangerous because it suggests any serialized queue is acceptable. It is not.

Recommendation: prefer only one helper name:

`runOnCefMainThread(...)`

and use it consistently.

## 12. Reentrancy hazards

The current code has helpers that synchronously wait for main-thread work while pumping the run loop. This is extremely risky.

Pattern to be careful with:

```objc
dispatch_async(mainQueue, ^{
  block();
  signal();
});

while (!done) {
  [[NSRunLoop currentRunLoop] runMode:... beforeDate:...];
}
```

This can cause reentrancy:

- unrelated UI events may run
- CEF callbacks may fire
- shutdown may progress
- browser state may mutate while caller assumes it is in a synchronous transition

Invariant C

Do not add nested run-loop pumping unless there is no alternative and the behavior is explicitly documented.

Whenever possible, prefer:

- direct inline execution on main thread if already there
- one-shot dispatch to main thread
- completion-based design instead of synchronous waiting

## 13. Callback threading rules

CEF callbacks like these are logically part of browser-process UI activity:

- `on_address_change`
- `on_title_change`
- `on_favicon_urlchange`
- `on_jsdialog`
- `on_load_end`

Treat them as main-thread callbacks unless proven otherwise.

Even if they are called on the main thread, callback bodies must still be defensive because they may run during:

- browser close
- shutdown
- host view teardown
- replacement logic
- stale mapping windows

Callback rule 1

Do not assume the browser is still active.

Callback rule 2

Do not assume mappings still exist.

Callback rule 3

Do not touch CEF global API pointers unsafely during callbacks.

### Callback re-entry deadlock contract

Some public APIs currently route to `runOnCefMainThread`, which dispatches
`dispatch_sync` to the main queue when called off-thread.

Because bridge completions/messages are drained on dedicated callback queues,
the callback queues are **not** the CEF executor and are not lock-safe execution
sites for synchronous re-entry.

If callback handling code holds any application lock and synchronously calls back
into a bridge API that needs main-thread execution, lock-order inversions can
still deadlock, even though CEF calls themselves stay on main.

Practical rule:

- callback handlers should not call synchronous bridge APIs while holding locks
- if a synchronous re-entry is required, release external locks before dispatching
- prefer async handoff to a domain-owned queue and return promptly from callbacks

If callback code needs CEF helper function pointers from `gCefApi`, it must first take a stable snapshot under lock.

## 14. Dynamic framework lifetime and threading

This project loads CEF dynamically. That means `gCefApi` contains function pointers into a shared library that can later be unloaded.

This creates a threading risk surface that is more dangerous than a normal static link.

Invariant D

No thread may call a CEF function pointer while another path is capable of resetting `gCefApi` or unloading the framework.

That means all of these must be coordinated:

- message loop pumping
- callbacks using `gCefApi` helper functions
- browser creation
- shutdown
- unload

Required pattern

When you need a CEF function pointer:

```cpp
CefDoMessageLoopWorkFn fn = nullptr;
{
  std::lock_guard<std::mutex> lock(gStateLock);
  if (gCEFInitialized) {
    fn = gCefApi.doMessageLoopWork;
  }
}
if (fn) {
  fn();
}
```

Do not do this:

```cpp
if (gCefApi.doMessageLoopWork) {
  gCefApi.doMessageLoopWork();
}
```

because another thread may reset or unload between the check and the call.

## 15. Browser object lifetime and threading

Retaining a CEF ref does not make cross-thread use valid.

This is a subtle but important point.

Wrong mental model:

"I retained `cef_browser_t*`, so I can now safely use it from another queue."

False.

Retaining protects lifetime, not thread affinity.

A retained browser must still only be used on the main thread in this architecture.

Correct pattern:

```cpp
cef_browser_t* browser = nullptr;
{
  std::lock_guard<std::mutex> lock(gStateLock);
  browser = retainCefRef(browserState->nativeBrowser);
}

runOnCefMainThread([&] {
  if (browser && browser->reload) {
    browser->reload(browser);
  }
});

releaseBrowser(browser);
```

## 16. Close and release threading rules

Browser shutdown is asynchronous. The current code polls `browser->is_valid(browser)` after calling `close_browser`.

That logic must remain on the main thread.

Invariant E

A browser close sequence must not bounce across threads.

Keep the entire sequence on main thread:

- get host
- call `close_browser`
- poll `is_valid`
- release host
- release browser
- invoke close completion

Do not split those phases across mixed queues.

## 17. Resize threading rules

A browser resize involves both:

- AppKit view changes
- CEF host notifications

Both must happen on the main thread.

Correct sequence:

1. resize embedded AppKit browser-hosted view on main thread
2. obtain `cef_browser_host_t*` on main thread
3. call:
   - `notify_move_or_resize_started`
   - `was_resized`
4. release refs

Do not do AppKit on one thread and CEF host notifications on another.

## 18. JavaScript execution threading rules

All JS execution must run on the main thread because it touches:

- `cef_browser_t`
- `cef_frame_t`
- `execute_java_script`

Pattern:

```cpp
runOnCefMainThread([&] {
  auto* frame = browser->get_main_frame(browser);
  if (frame && frame->execute_java_script) {
    frame->execute_java_script(frame, &script, nullptr, 0);
  }
  releaseOwnedCefRef(frame);
});
```

Never queue JS execution to a background queue.

## 19. Navigation threading rules

URL loading must run on the main thread.

Pattern:

```cpp
runOnCefMainThread([&] {
  auto* frame = browser->get_main_frame(browser);
  if (frame && frame->load_url) {
    frame->load_url(frame, &cefUrl);
  }
  releaseOwnedCefRef(frame);
});
```

## 20. Process messaging threading rules

Sending renderer messages must run on the main thread.

This touches:

- `cef_process_message_create`
- `cef_browser_t`
- `cef_frame_t`
- `send_process_message`

Never send renderer process messages from callback queues or background worker queues.

## 21. AppKit + CEF combined operations

Whenever a function touches both:

- `NSView` / `NSWindow`
- CEF browser/frame/host objects

it belongs on the main thread, full stop.

Examples:

- browser creation with `parent_view`
- resize handling
- host view attach/detach
- embedded subview management
- snapshotting plus browser state coordination

## 22. State lock rules

`gStateLock` protects bridge state, but it must not become a reason to perform CEF operations under lock.

Invariant F

Do not hold `gStateLock` while calling into CEF.

Why:

- CEF callbacks may reenter your bridge
- deadlocks become easier
- shutdown interactions become fragile
- lock scope becomes too large

Preferred pattern:

- take lock
- copy plain state / retain refs / copy function pointer
- release lock
- call CEF on main thread
- reacquire lock only if needed afterward

## 23. Callback queues are not CEF queues

The bridge may use background queues for delivering callbacks to higher-level code.

Those queues are for application callback routing only.

They must never be treated as:

- CEF executor
- browser executor
- renderer executor
- AppKit-safe queue

Invariant G

Callback queues may move strings and plain state only. They may not dereference CEF objects.

In addition, they must not directly perform synchronous bridge re-entry while holding
external locks; that lock-order issue is an integration contract concern and must be
handled in the callback consumer.

## 24. Testing rules for threading changes

Any change touching threading must be validated against the following checklist.

Required validation

- create runtime
- create browser
- attach browser to NSView
- pump message loop repeatedly
- navigate to a page
- execute JavaScript
- resize browser repeatedly
- destroy browser
- shutdown runtime
- confirm no crash in `cef_do_message_loop_work()`

Stress validation

- rapid create/destroy loop
- rapid resize loop
- navigate while resizing
- shutdown during pending callbacks
- multiple browsers if supported

Regression rule

If a change introduces any new queue, thread, or executor abstraction in the CEF layer, it must justify:

- why main-thread execution is not sufficient
- which exact APIs are allowed there
- why those APIs are safe there
- how framework unload races are prevented

If that proof is not clear, the change should not be made.

## 25. Common wrong assumptions to avoid

Wrong assumption 1

"A serial queue is close enough to the CEF thread."

No. It is not.

Wrong assumption 2

"If I retain the browser ref, I can use it anywhere."

No. Lifetime is not thread ownership.

Wrong assumption 3

"`cef_do_message_loop_work()` crashed, so the bug is there."

Often false. The real bug is frequently an earlier thread violation.

Wrong assumption 4

"I only touched helper functions like UTF8/UTF16 conversion, not browser state."

Still dangerous if those function pointers come from a dynamically unloaded framework.

Wrong assumption 5

"Callback delivery queue can do a little CEF work."

No. It cannot.

## 26. Recommended future simplification

To reduce future mistakes, the preferred long-term model is:

- one explicit helper: `runOnCefMainThread`
- no separate `runOnCefExecutor`
- no fake CEF serial queue
- all browser/frame/host access visibly main-thread-constrained
- all `gCefApi` access copied under lock before use
- framework unload only after fully quiescent shutdown

The simpler the model, the fewer hidden threading bugs future agents will introduce.

## 27. Practical code review checklist

When reviewing CEF changes, ask these questions in order:

1. Does this touch any `cef_*` object?
2. If yes, is it guaranteed main-thread-only?
3. Does it touch `gCefApi`?
4. If yes, is the function pointer copied safely under lock first?
5. Does it run during shutdown?
6. If yes, can framework unload race with it?
7. Does it hold `gStateLock` while calling CEF?
8. If yes, that is likely wrong.
9. Does it introduce a new queue?
10. If yes, why is that queue not a future threading footgun?

If any answer looks unclear, stop and simplify.

## 28. Golden rule

When in doubt:

- marshal to main thread
- avoid holding locks while calling CEF
- copy function pointers safely
- simplify instead of introducing another executor abstraction

This repository should prefer boring, explicit, main-thread-only CEF code over clever concurrency.

That is how crashes are prevented.
