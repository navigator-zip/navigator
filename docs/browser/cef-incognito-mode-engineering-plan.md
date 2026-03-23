# CEF Incognito Mode Engineering Plan

## Purpose

This document defines the engineering plan for adding a first-class incognito mode to Navigator's macOS CEF embed.

The goal is to ship an off-the-record browsing mode that:

- uses CEF's request-context model correctly instead of ad hoc cache clearing
- preserves Navigator's current browser-runtime and tab-host architecture
- prevents incognito tabs from leaking into normal tab/session persistence
- keeps popup, new-tab, and permission behavior consistent inside the incognito session
- is testable at the native bridge, runtime, and app layers

## Problem Summary

Navigator currently has one effective browser profile shape:

- the CEF runtime initializes with a single global cache configuration
- browser creation does not accept a per-browser request context
- app tab persistence assumes every tab belongs to the restorable normal session

That means Navigator cannot currently offer a true off-the-record mode.

The gaps are:

- no app-owned concept of browser privacy mode or workspace mode
- no native bridge API for creating a browser with a dedicated `CefRequestContext`
- no routing policy for popups or "open in new tab/window" actions to preserve privacy mode
- no persistence guardrail preventing incognito tabs from being written into shared tab storage
- no lifecycle policy for tearing down off-the-record state when the incognito session ends

## Current State In This Repo

### Browser creation is profile-agnostic

The public bridge API in [`CEFBridge.h`](/Users/rk/Developer/Navigator/MiumKit/Sources/MiumKit/CEFBridge.h) exposes `CEFBridge_CreateBrowser(...)` with only:

- parent view
- initial URL
- size
- scale

There is no request-context or profile argument today.

The bridge implementation in [`CEFBridge.mm`](/Users/rk/Developer/Navigator/MiumKit/Sources/MiumKit/CEFBridge.mm) calls `miumNativeCEFCreateBrowser(...)` before creating the host view, which means the native layer currently owns browser creation without any privacy-mode input.

### Native CEF initialization is global

[`MiumCEFBridgeNative.mm`](/Users/rk/Developer/Navigator/MiumKit/Sources/MiumKit/MiumCEFBridgeNative.mm) configures `cef_settings_t.cache_path` and `cef_settings_t.root_cache_path` once during runtime initialization.

This is correct for the normal persistent profile, but it is not enough for incognito because CEF's off-the-record behavior is a `CefRequestContextSettings.cache_path == ""` decision made per request context, not a special browser flag.

### App tab persistence assumes all tabs are restorable

[`AppViewModel.swift`](/Users/rk/Developer/Navigator/Navigator/AppViewModel.swift) restores and persists the current tab collection through:

- [`StoredBrowserTabCollection`](/Users/rk/Developer/Navigator/ModelKit/Sources/ModelKit/StoredBrowserTabModels.swift)
- [`StoredBrowserTabSelection`](/Users/rk/Developer/Navigator/ModelKit/Sources/ModelKit/StoredBrowserTabModels.swift)
- [`NavigatorStoredBrowserTabsShared.swift`](/Users/rk/Developer/Navigator/Navigator/NavigatorStoredBrowserTabsShared.swift)

The stored tab model currently contains:

- tab ID
- order key
- URL
- title
- favicon URL

It does not represent privacy mode, workspace kind, or an "exclude from persistence" bit.

### Additional browser windows share the same tab collection

[`AppDelegate.swift`](/Users/rk/Developer/Navigator/Navigator/AppDelegate.swift) creates secondary browser windows by constructing a new `AppViewModel` that reuses the source `sharedTabCollection`.

That means the app's current multi-window model is a shared workspace, not independent per-window tab stacks.

This matters for incognito scope: phase one should align with that existing workspace model instead of simultaneously redesigning all browser-window semantics.

### Popup and open-in-tab routing already exists

Navigator already bridges browser-originated open requests through:

- `OnOpenURLFromTab` in [`MiumCEFBridgeNative.mm`](/Users/rk/Developer/Navigator/MiumKit/Sources/MiumKit/MiumCEFBridgeNative.mm)
- `BrowserRuntimeOpenURLInTabEvent` in [`BrowserRuntime.swift`](/Users/rk/Developer/Navigator/BrowserRuntime/Sources/BrowserRuntime/BrowserRuntime.swift)
- tab handling in [`BrowserViewController.swift`](/Users/rk/Developer/Navigator/BrowserView/Sources/BrowserView/BrowserViewController.swift)

That existing path is the right place to preserve privacy mode when links or script-driven windows create additional tabs.

## Goals

- Add a user-visible incognito mode with a dedicated off-the-record browser workspace.
- Ensure every browser created in that workspace uses an incognito `CefRequestContext`.
- Keep all browser callbacks and existing permission plumbing working in incognito.
- Prevent incognito tabs and selection state from being written to the normal restorable session files.
- Preserve privacy mode across in-app tab and popup creation.
- Tear down in-memory off-the-record state when the incognito session ends.
- Keep the design extensible for future profile work beyond a single normal profile plus incognito.

## Non-Goals

- Full multi-profile support in phase one.
- Reworking Navigator's entire multi-window model to support independent tab stacks for every window.
- Re-implementing Chromium's entire site-settings UI for incognito in the first pass.
- Guaranteeing zero disk writes of any kind; CEF still uses `root_cache_path` for installation-level data.
- Shipping private browsing history/bookmark/download management features beyond the core browsing session.

## Recommended Product Shape

### Incognito should be workspace-scoped, not per-tab-scoped

Phase one should treat incognito as a distinct app workspace/session mode:

- `regular`
- `incognito`

Reasons:

- the current app window model already shares a tab collection across windows
- persistence policy is much simpler when it is owned by the app session instead of mixed tab-by-tab
- CEF request-context sharing works naturally when all tabs in the same workspace share one off-the-record context
- popup routing is less error-prone when "same workspace" is the default rule

### Phase-one multi-window behavior

All incognito windows in a running app session should share the same off-the-record workspace, matching the current normal-window behavior where multiple windows share a tab collection.

This means:

- opening a second incognito window reuses the same incognito tab collection
- all incognito tabs share the same off-the-record request context
- session cookies and other in-memory site state are shared across incognito windows for the current app launch

That is consistent with mainstream browser behavior and minimizes architectural churn.

## Proposed Architecture

## Session and model layer

Introduce app-owned privacy/session types in `ModelKit`.

Recommended additions:

- `BrowserPrivacyMode`
  - `regular`
  - `incognito`
- `BrowserWorkspaceKind`
  - `restorable`
  - `offTheRecord`
- `BrowserWorkspaceSessionID`
- `BrowserWorkspaceDescriptor`

Recommended app-level ownership:

- `AppViewModel` gains a workspace/privacy mode
- normal windows use `.regular`
- incognito windows use `.incognito`

Recommended behavior:

- `.regular` keeps current restore/persist behavior
- `.incognito` never hydrates from the normal stored-tab files
- `.incognito` never writes tab or selected-tab state to the normal stored-tab files

Do not overload `sessionPersistence` alone to imply privacy mode. Persistence and privacy are related, but they are not the same abstraction.

## Request-context ownership

Browser/request-context ownership should remain below SwiftUI/AppKit UI code.

Recommended design:

- keep request-context creation and lifetime in `BrowserRuntime` plus the native Mium bridge
- do not leak raw `CefRequestContext*` pointers into Swift
- expose an app-owned opaque profile/context handle instead

Recommended native concepts:

- `MiumCEFRequestContextHandle`
- persistent default request context
- shared off-the-record request context

Recommended bridge surface additions:

- create request context for `regular` or `incognito`
- create browser with an explicit request-context handle
- destroy request context when the owning runtime/session releases it

This is preferable to adding a one-off `is_incognito` boolean directly to every browser-create call because it creates a reusable abstraction for future browser profiles.

## Native CEF behavior

### Regular context

Continue using the existing persistent cache configuration rooted under the configured `cache_path` and `root_cache_path`.

### Incognito context

Create a `CefRequestContext` with:

- empty `cache_path`
- shared app `root_cache_path`
- explicit `CefRequestContextHandler` if request-context-scoped callbacks are needed later

Important documented behavior:

- empty `cache_path` gives CEF's off-the-record in-memory profile behavior
- installation-specific data may still persist under `root_cache_path`

The implementation and tests should document that distinction clearly so the product does not overclaim privacy semantics.

## Browser creation flow

Recommended new flow:

1. App/window code decides the workspace privacy mode.
2. `BrowserView` / `BrowserRuntime` resolves the matching request-context handle.
3. `CEFBridge_CreateBrowser` receives that handle.
4. Native code creates the browser using that request context.
5. Browser callbacks remain identical regardless of privacy mode.

Key design rule:

- privacy mode must be decided before the native browser is created
- do not create a browser in the default context and attempt to "convert" it afterward

## Popup and navigation routing

Incognito mode must preserve workspace mode for all derived browser opens.

Required rules:

- a regular tab opening a new tab/window stays regular unless the user explicitly requests incognito
- an incognito tab opening a new tab/window stays incognito by default
- popup creation should inherit the source browser's privacy mode
- `CEF_WOD_OFF_THE_RECORD` requests should route into the incognito workspace explicitly

Primary integration seams:

- native `OnBeforePopup`
- native `OnOpenURLFromTab`
- `BrowserRuntimeOpenURLInTabEvent`
- app/window commands such as "New Window" and the new "New Incognito Window"

## Persistence and privacy boundaries

### Tabs and selection

Incognito tabs must never be written into:

- `NavigatorStoredBrowserTabs`
- `NavigatorStoredBrowserTabSelection`

Normal-session hydration must also never pull incognito tabs back into a later launch.

### Imports and external URL flows

Decide explicit behavior for imports and URL opens:

- imported browser snapshots should continue targeting the regular workspace only in phase one
- incoming external URLs should open in the currently active workspace only if that matches an explicit product decision

Recommended phase-one rule:

- external app-open events should target the regular workspace unless the active frontmost window is already incognito and product intentionally wants that behavior

This needs a conscious product choice before implementation.

### Downloads, permissions, and website state

Incognito should still support:

- site permissions
- cookies/session cookies in memory
- local browser navigation state for the active app session

But it should not persist incognito website state across relaunches.

Existing permission prompts can remain structurally identical. The important requirement is that any permission persistence store must respect privacy mode and avoid converting incognito-only grants into durable app-wide grants unless product explicitly wants that.

Recommended phase-one rule:

- "remember" inside incognito should mean "for this incognito session only"

## App and UI changes

Add explicit product affordances for incognito mode:

- File menu item: `New Incognito Window`
- standard keyboard shortcut if product wants Chrome-style parity
- incognito window appearance treatment so the user can distinguish workspaces at a glance
- address/action bar and sidebar treatment that makes the current workspace obvious

Recommended phase-one minimum:

- menu command
- distinct window title/chrome treatment
- in-app badge or title treatment indicating incognito mode

## Testing Plan

## Native bridge tests

Add or extend tests in `MiumKit` to verify:

- incognito request-context creation uses empty `cache_path`
- regular request-context creation keeps the configured persistent cache path
- browser creation receives the intended request-context handle
- popup/open flows preserve privacy mode
- request-context and browser teardown do not leak callbacks or handles

## Runtime tests

Add `BrowserRuntime` tests to verify:

- privacy mode resolves to the correct native context handle
- derived browser/tab opens inherit the source privacy mode
- incognito permission/session policies do not persist durable grants accidentally

## App/model tests

Add `Navigator` and `ModelKit` tests to verify:

- incognito `AppViewModel` never restores from normal stored tabs
- incognito `AppViewModel` never writes to normal stored-tab files
- opening a new incognito window creates or reuses the incognito workspace as intended
- opening a regular window does not reuse the incognito workspace

## Manual verification

Manual QA should explicitly verify:

- first incognito window starts with no restored tabs
- second incognito window reuses the same incognito workspace in phase one
- normal and incognito workspaces do not leak tabs into each other
- cookies/logins persist across incognito tabs during the same app session only
- relaunch clears incognito browsing state
- popups and script-opened tabs preserve privacy mode
- permission prompts in incognito do not create durable normal-session grants

## Recommended Implementation Phases

### Phase 1: Native profile plumbing

- add request-context handle abstraction to the native bridge
- create persistent and incognito request contexts
- thread request-context selection through browser creation
- add native tests for context creation and browser/context mapping

### Phase 2: App workspace model

- add app-owned privacy/workspace types
- teach `AppViewModel` and window creation about `.regular` vs `.incognito`
- add `New Incognito Window`
- block incognito writes to shared tab persistence

### Phase 3: Derived navigation correctness

- preserve privacy mode across popup, open-in-tab, and new-window routing
- audit incoming URL flows and other programmatic tab creation paths
- add regression tests for mixed normal/incognito behavior

### Phase 4: UX and policy polish

- add incognito-specific visual treatment
- finalize permission-persistence semantics for incognito
- document product behavior for downloads, imports, and external-open routing

## Risks and Open Questions

- Current multi-window behavior shares one tab collection. If product eventually wants independent incognito windows, that should be a separate follow-up rather than phase-one scope creep.
- Incognito permissions need an explicit policy. Reusing the normal durable store would be a privacy bug.
- `root_cache_path` still exists in incognito mode. Product copy should not imply "no disk usage whatsoever."
- If Navigator later adds first-class profiles, a request-context handle abstraction will age much better than a boolean-only API.

## Files of Interest

- [`MiumCEFBridgeNative.mm`](/Users/rk/Developer/Navigator/MiumKit/Sources/MiumKit/MiumCEFBridgeNative.mm)
- [`CEFBridge.h`](/Users/rk/Developer/Navigator/MiumKit/Sources/MiumKit/CEFBridge.h)
- [`CEFBridge.mm`](/Users/rk/Developer/Navigator/MiumKit/Sources/MiumKit/CEFBridge.mm)
- [`BrowserRuntime.swift`](/Users/rk/Developer/Navigator/BrowserRuntime/Sources/BrowserRuntime/BrowserRuntime.swift)
- [`BrowserContainerView.swift`](/Users/rk/Developer/Navigator/BrowserView/Sources/BrowserView/BrowserContainerView.swift)
- [`BrowserViewController.swift`](/Users/rk/Developer/Navigator/BrowserView/Sources/BrowserView/BrowserViewController.swift)
- [`AppViewModel.swift`](/Users/rk/Developer/Navigator/Navigator/AppViewModel.swift)
- [`AppDelegate.swift`](/Users/rk/Developer/Navigator/Navigator/AppDelegate.swift)
- [`StoredBrowserTabModels.swift`](/Users/rk/Developer/Navigator/ModelKit/Sources/ModelKit/StoredBrowserTabModels.swift)
- [`cef_request_context.h`](/Users/rk/Developer/Navigator/Vendor/CEF/include/cef_request_context.h)
- [`cef_browser.h`](/Users/rk/Developer/Navigator/Vendor/CEF/include/cef_browser.h)
