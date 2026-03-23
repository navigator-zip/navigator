# AGENTS.md - CEF Integration Safety & Engineering Contract

This document defines mandatory rules and invariants for any agent modifying the Chromium Embedded Framework (CEF) integration in this repository.

The codebase uses CEF C API dynamically loaded via `dlopen` and embeds Chromium into an AppKit-based macOS application with single-threaded message loop mode.

CEF is extremely sensitive to:

- thread correctness
- object lifetimes
- message loop configuration
- ABI compatibility
- shutdown ordering
- process architecture

Violating these rules will frequently cause crashes inside `cef_do_message_loop_work()`, renderer process failures, or hard-to-debug memory corruption.

This file exists to ensure no agent ever repeats those mistakes.

## 1. Core Architecture Overview

The CEF runtime in this repository follows this architecture:

```text
Host App (AppKit)
        |
        v
CEF Bridge (Objective-C++ / C++)
        |
        v
Dynamically loaded CEF Framework
        |
        v
CEF Browser Process
        |
        |- Renderer Process
        |- GPU Process
        `- Utility Processes
```

Key facts:

- The host app is AppKit-only (no SwiftUI).
- CEF runs in single-threaded message loop mode.
- The host app manually drives Chromium via `cef_do_message_loop_work()`.
- The CEF framework is loaded dynamically via `dlopen`.

## 2. ABSOLUTE RULES (DO NOT BREAK)

These are hard invariants.
Any violation will likely crash Chromium.

### Rule 1 - ALL CEF API calls must run on the CEF UI thread

In this integration the CEF UI thread is the macOS main thread.

Therefore:

- All CEF object usage must run on the main thread.

Examples of APIs that MUST run on main thread:

- `cef_browser_host_create_browser_sync`
- `cef_browser_t` methods
- `cef_frame_t` methods
- `cef_browser_host_t` methods
- `cef_process_message_create`
- `cef_shutdown`
- `cef_initialize`
- `cef_execute_process`
- `cef_do_message_loop_work`

If code touches any of these types:

- `cef_browser_t`
- `cef_frame_t`
- `cef_browser_host_t`
- `cef_process_message_t`

it must execute on the main thread.

Enforce using:

- `runOnCefMainThread(...)`

Never call these from background threads.

### Rule 2 - NEVER use CEF objects across threads

CEF objects are not thread-safe.

Example of a bug:

```cpp
std::thread {
    browser->reload(browser);
}
```

This will crash.

Instead:

```cpp
runOnCefMainThread(^{
    browser->reload(browser);
});
```

### Rule 3 - Never unload the CEF framework while callbacks may run

This is one of the most dangerous bugs.

If `dlclose()` is called while CEF callbacks may still execute:

- CEF may call function pointers inside unloaded code
- crash occurs inside `cef_do_message_loop_work`

Correct sequence:

1. close all browsers
2. wait for browser close completion
3. call `cef_shutdown()`
4. only then `dlclose()`

Agents must never call `dlclose()` while browsers exist.

### Rule 4 - Never access `gCefApi` without synchronization

The global function table:

```cpp
CefApi gCefApi;
```

is mutated during:

- shutdown
- framework unload
- test reset

Access must follow this pattern:

```cpp
CefDoMessageLoopWorkFn fn;

{
    std::lock_guard lock(gStateLock);
    fn = gCefApi.doMessageLoopWork;
}

if (fn) {
    fn();
}
```

Never do:

```cpp
gCefApi.doMessageLoopWork()
```

directly.

### Rule 5 - NEVER mix message loop modes

CEF has three modes:

- `multi_threaded_message_loop`
- `external_message_pump`
- manual `cef_do_message_loop_work`

This project uses:

- `multi_threaded_message_loop = 0`
- `external_message_pump = 0` by default
- `external_message_pump = 1` only behind the external-pump bridge path

and one scheduling mode at a time.

Therefore:

Agents must never enable:

- `external_message_pump = 1`

unless they also implement:

- `cef_browser_process_handler_t::OnScheduleMessagePumpWork`
- a browser-process `cef_app_t` wrapper that stays alive until shutdown
- host-side cancellation so manual pumping is disabled while external pump mode is active

### Rule 6 - CEF shutdown must happen after ALL browsers close

Shutdown ordering must be:

1. create browser
2. use browser
3. close browser
4. wait for browser invalid
5. release browser refs
6. `cef_shutdown()`
7. unload framework

Agents must never call `cef_shutdown()` while any browser still exists.

### Rule 7 - Browser replacement is dangerous

Replacing a browser instance:

- `oldBrowser -> newBrowser`

is a major lifecycle risk.

Agents should prefer:

- rebind host view
- resize host view
- reuse browser

instead of destroying and recreating.

Replacement should be rare and intentional.

### Rule 8 - CEF callbacks may occur during shutdown

Callbacks such as:

- `on_address_change`
- `on_title_change`
- `on_favicon_urlchange`
- `on_load_end`

may fire while shutdown is happening.

All callbacks must assume:

- browser may already be closing
- state may be partially torn down

Always guard lookups.

### Rule 9 - Never hold bridge locks while calling into CEF

Do not hold `gStateLock` while invoking:

- any `cef_*` object method
- any function pointer from `gCefApi`

Correct pattern:

1. acquire lock
2. copy plain state / retain refs / copy function pointer
3. release lock
4. call CEF on main thread

Holding locks while calling CEF risks:

- deadlocks
- reentrancy corruption
- shutdown races
- callback reentry into locked state

### Rule 10 - Ref retention protects lifetime, not thread affinity

Retaining a `cef_browser_t*`, `cef_frame_t*`, or `cef_browser_host_t*` does not make it safe to use on a background queue.

Wrong mental model:

"I retained the ref, so I can use it anywhere."

Correct mental model:

"I retained the ref so it stays alive until I marshal back to the main thread."

### Rule 11 - Callback code must not assume stable browser mappings

In callbacks such as:

- `on_address_change`
- `on_title_change`
- `on_favicon_urlchange`
- `on_load_end`

assume that:

- the logical browser may be closing
- native browser mappings may already be stale
- host view bindings may already be gone
- framework unload may be pending

Callback handlers must:

- validate mappings
- avoid touching stale pointers
- avoid unsynchronized `gCefApi` reads
- avoid creating new browser work during shutdown

### Rule 12 - Keep `cef_execute_process` and `cef_initialize` application arguments distinct

In this repository, call:

- `cef_execute_process(&args, nullptr, nullptr)`
- `cef_initialize(&args, &settings, app, nullptr)` with a fresh `cef_app_t` wrapper

Do not reuse a single `cef_app_t*` across both calls.

If subprocess customization is not required, keep `cef_execute_process` on a null app wrapper path.

### Rule 13 - Keep the browser-process `cef_app_t` alive until final shutdown

The `cef_app_t` used for `cef_initialize` must stay alive for the entire initialized runtime.

Do not create it as a short-lived local that is destroyed immediately after `cef_initialize` returns.

Release that app wrapper only after final `cef_shutdown()` completes and before framework unload.

## 3. Thread and Process Model

Browser process:

- Main thread
  - AppKit UI thread
  - CEF browser-process UI thread in this integration
- CEF internal browser-process threads
  - network
  - IO
  - GPU coordination / internal tasks

Separate subprocesses:

- renderer process
- GPU process
- utility processes

Agents must never assume callbacks run on main thread unless documented.

Many browser-process callbacks are expected on the browser-process UI thread in this architecture. Even so, callback code must be written defensively and must not assume stable lifecycle state.

## 4. Initialization Contract

Correct initialization sequence:

1. load framework via `dlopen`
2. verify ABI compatibility
3. load required symbols
4. call `cef_execute_process`
5. call `cef_initialize`

Agents must always verify:

- `cef_api_hash`
- `CEF_API_VERSION`

before initialization.

ABI mismatches cause hard crashes.

Important:

Passing `nullptr` for the application parameter to `cef_execute_process` / `cef_initialize` is an intentionally simplified mode, not a robust long-term foundation.

If process messaging, render-process hooks, browser-process scheduling hooks, or more advanced lifecycle control are introduced, a real `cef_app_t` must be implemented and passed explicitly.

## 5. Subprocess Model

CEF launches subprocesses for:

- renderer
- GPU
- utility

The path is configured via:

- `cef_settings.browser_subprocess_path`

Agents must ensure:

- `Navigator Helper.app`
- `Chromium Helper.app`

exists and contains a valid executable.

Incorrect subprocess configuration causes:

- `cef_execute_process` returning `>= 0`

which means the process must exit immediately.

## 6. Message Loop Pumping

The message loop must be pumped regularly:

- `cef_do_message_loop_work()`

Recommended frequency:

- ~16ms (60fps)

Agents must also ensure:

- `cef_do_message_loop_work()` is never called concurrently
- it is never called before successful `cef_initialize()`
- it is never called after final `cef_shutdown()`
- shutdown pumping, if present, remains main-thread-only

Agents must not call it:

- during shutdown (except for the controlled shutdown pumping flow in Section 10)
- after `cef_shutdown`
- before `cef_initialize`

## 7. Safe Browser Destruction

Correct destruction pattern:

```cpp
browser->get_host()
host->close_browser(force_close = true)

poll browser->is_valid()

when invalid:
release browser refs
```

Never release the browser immediately after `close_browser`.

CEF internally destroys it asynchronously.

## 8. Dynamic Framework Loading

The framework is loaded via:

- `dlopen("Chromium Embedded Framework")`

Agents must ensure:

- `RTLD_NOW | RTLD_LOCAL`

is used.

Never use:

- `RTLD_GLOBAL`

as it can cause symbol collisions.

## 9. AppKit Integration Rules

The browser is embedded into an `NSView`.

Agents must follow:

- `windowInfo.parent_view = hostView`

and allow CEF to create its own subviews.

Never manually manipulate Chromium subviews.

## 10. Shutdown Pumping

During shutdown the system may continue pumping the loop:

- `cef_do_message_loop_work`

until:

- all browser closes complete

This ensures:

- renderer exits cleanly
- internal tasks finish

Shutdown pumping exists to let CEF finish close-related work before final shutdown/unload.

Removing it, shortening it casually, or moving it off the main thread is unsafe.

Any shutdown-pump changes must be accompanied by end-to-end browser-close and framework-unload validation.

## 11. Dangerous Patterns (NEVER introduce)

Calling CEF APIs without main thread

Wrong:

```cpp
dispatch_async(queue) {
   browser->reload(browser)
}
```

Correct:

```cpp
runOnCefMainThread(...)
```

Accessing CEF after shutdown

Wrong:

```cpp
cef_shutdown()
browser->reload(browser)
```

Using CEF objects after release

Wrong:

```cpp
releaseBrowser(browser)
browser->reload(browser)
```

Unloading framework while callbacks run

Wrong:

```cpp
dlclose(framework)
while callbacks still active
```

## 12. Debugging Guidance

If `cef_do_message_loop_work()` crashes:

Check:

- invalid thread usage
- framework unloaded early
- ABI mismatch
- browser closed incorrectly
- use-after-free CEF object
- missing helper subprocess

## 13. Logging

Agents should add logging around:

- browser creation
- browser destruction
- framework load
- framework unload
- `cef_initialize`
- `cef_shutdown`

to assist debugging.

## 14. Recommended Future Improvements

Agents should consider adding:

1. Maintain a single explicit execution model for CEF calls. In the current architecture, that model is main-thread-only. Do not introduce a separate executor unless the entire CEF threading architecture is intentionally redesigned and documented.
2. A real `cef_app_t`  
   This enables:
   - render process handlers
   - message routing
   - process lifecycle hooks
3. Centralized CEF call wrapper  
   Route browser/frame/host calls through one explicit main-thread path.
4. Explicit browser lifecycle state machine  
   Avoid heuristic polling.

## 15. Testing Requirements

Agents modifying CEF integration must validate:

- browser creation
- browser resize
- URL navigation
- JS execution
- shutdown sequence
- multiple browsers

on:

- macOS debug build
- macOS release build

## 16. Golden Rule

If an agent is unsure whether a CEF API is thread-safe:

assume it is not.

Always run it on the main thread.

## Final Note

CEF is extremely sensitive to lifecycle mistakes.

Even small errors may appear as crashes in:

- `cef_do_message_loop_work()`

while the real bug occurred earlier.

Agents must treat the rules in this document as strict contracts, not suggestions.
