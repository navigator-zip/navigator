# CEF Permissions Engineering Plan

## Purpose

This document defines the engineering plan for adding first-class website permission support to Navigator's CEF embed on macOS, starting with:

- camera
- microphone
- geolocation

It also defines the extension path for other site permissions such as notifications, clipboard access, MIDI, and display capture.

The goal is not only to make `getUserMedia` and geolocation work, but to do it in a way that is:

- compatible with Navigator's current CEF bridge architecture
- explicit about macOS TCC requirements
- safe under CEF's main-thread and callback-lifetime rules
- testable and persistent across app relaunches

## Problem Summary

Today Navigator's CEF integration can render pages and bridge a number of browser events, but it does not yet own the permission lifecycle that modern websites require.

The current gaps are:

- no CEF permission handler is registered on the native client
- no app-owned bridge exists for permission prompts or prompt resolution
- the main app `Info.plist` does not declare camera, microphone, or location usage strings
- the helper bundle normalization path does not guarantee those privacy keys in helper `Info.plist` files
- media access is only conditionally exposed via a coarse `--enable-media-stream` switch, which is not a real per-origin permission system

As a result:

- sites requesting camera or microphone cannot go through an app-owned allow/deny flow
- geolocation has no permission plumbing at all
- there is no persistent site permission model
- behavior depends too heavily on CEF defaults and runtime style details that Navigator does not currently control

## Current State In This Repo

### Native CEF client

[`MiumCEFBridgeNative.mm`](/Users/rk/Developer/Navigator/MiumKit/Sources/MiumKit/MiumCEFBridgeNative.mm) currently creates a native `cef_client_t` with:

- display handler
- life span handler
- JS dialog handler
- load handler
- request handler

See the client assembly in [`MiumCEFBridgeNative.mm`](/Users/rk/Developer/Navigator/MiumKit/Sources/MiumKit/MiumCEFBridgeNative.mm#L1452).

It does not currently expose:

- `get_permission_handler`
- `on_request_media_access_permission`
- `on_show_permission_prompt`
- `on_dismiss_permission_prompt`

CEF supports those hooks in:

- [`cef_client.h`](/Users/rk/Developer/Navigator/Vendor/CEF/include/cef_client.h#L137)
- [`cef_permission_handler.h`](/Users/rk/Developer/Navigator/Vendor/CEF/include/cef_permission_handler.h#L87)

### Swift bridge surface

The current exported bridge API in [`CEFBridge.h`](/Users/rk/Developer/Navigator/MiumKit/Sources/MiumKit/CEFBridge.h#L44) only exposes message-style handlers for:

- address changes
- title changes
- favicon URL changes
- picture-in-picture state
- top-level native content
- render-process termination
- main-frame navigation

`BrowserRuntime` only consumes those same event families in [`BrowserRuntime.swift`](/Users/rk/Developer/Navigator/BrowserRuntime/Sources/BrowserRuntime/BrowserRuntime.swift#L142) and related callback wiring in [`BrowserRuntime.swift`](/Users/rk/Developer/Navigator/BrowserRuntime/Sources/BrowserRuntime/BrowserRuntime.swift#L510).

There is no prompt model, no permission token, and no Swift API to resolve a pending CEF permission request.

### App and helper privacy metadata

The main app plist at [`Navigator/Resources/Info.plist`](/Users/rk/Developer/Navigator/Navigator/Resources/Info.plist#L5) does not include:

- `NSCameraUsageDescription`
- `NSMicrophoneUsageDescription`
- `NSLocationWhenInUseUsageDescription`

The packaged helper bundle plists under `Vendor/CEF/Release` also do not include those keys. Those files are generated artifacts and should not be treated as the implementation source of truth.

The relevant source-of-truth layers for packaging are:

- main app plist: [`Navigator/Resources/Info.plist`](/Users/rk/Developer/Navigator/Navigator/Resources/Info.plist#L1)
- helper normalization and verification: [`CEFPackager/main.swift`](/Users/rk/Developer/Navigator/CEFPackager/main.swift#L798), [`CEFPackager/main.swift`](/Users/rk/Developer/Navigator/CEFPackager/main.swift#L1081)
- app/helper signing path: [`BundleCEFRuntime.sh`](/Users/rk/Developer/Navigator/BundleCEFRuntime.sh#L224)

### Current media-stream behavior

CEF initialization currently appends `--enable-media-stream` only when `MIUM_CEF_ENABLE_MEDIA_STREAM` is set in [`MiumCEFBridgeNative.mm`](/Users/rk/Developer/Navigator/MiumKit/Sources/MiumKit/MiumCEFBridgeNative.mm#L4231).

This is insufficient for product-quality permissions because it:

- is global, not per-origin
- does not cover geolocation
- bypasses the shape of a real allow/deny/persist flow
- creates ambiguity about whether permission decisions are being made by Navigator or by command-line override

## Goals

- Support site permission requests for camera, microphone, and geolocation in Navigator's CEF embed.
- Present a Navigator-owned permission flow instead of relying on CEF default behavior.
- Keep the implementation explicit and deterministic across CEF runtime styles.
- Support per-origin persistence of permission decisions.
- Support "allow once", "always allow for this origin", and "deny" semantics.
- Correctly coordinate website permissions with macOS TCC.
- Make prompt dismissal safe on navigation, tab close, browser destruction, and app shutdown.
- Build an extension path for additional site permissions without redesigning the bridge.

## Non-Goals

- Re-implement Chrome's full site settings UI in the first pass.
- Support every Chromium permission type in phase one.
- Add app sandboxing as part of this change.
- Depend on generated `Vendor/CEF/Release/.../Info.plist` files as stable editable inputs.
- Ship display capture or notification permissions before the base prompt architecture exists.

## Recommended Product Scope

### Phase-one supported permissions

Ship first:

- camera
- microphone
- combined camera+microphone requests
- geolocation

### Phase-two extension path

Design the bridge so it can later support:

- notifications
- clipboard read/write prompts where applicable
- MIDI / MIDI sysex
- display capture
- file-system style prompts if Navigator exposes those APIs later

## Design Principles

### 1. Navigator must own permission decisions

Do not rely on CEF's default permission UI.

Reasons:

- the current embed does not expose a stable app-owned prompt path
- default behavior differs by runtime style and permission type
- Navigator needs per-origin persistence and product-specific UX

### 2. Treat website permission and macOS permission as separate layers

A site permission grant is not the same thing as OS-level permission.

Navigator must resolve both:

- website-level allow/deny for an origin
- macOS TCC authorization for the underlying device or location service

### 3. Keep CEF callback ownership native

Pending CEF callbacks must remain owned in `MiumCEFBridgeNative.mm`.

Swift should not directly retain raw CEF callback pointers. Instead:

- native code stores callback state behind a session ID
- Swift receives a request or prompt model with that session ID
- Swift resolves the session through an explicit bridge call
- native code calls the corresponding CEF callback on the CEF UI thread

### 4. Persist app policy independently of CEF defaults

Navigator should not depend on Chromium's internal permission persistence as the source of truth for product decisions.

Reasons:

- Navigator needs a settings/reset story
- custom UI needs deterministic stored decisions
- app-side persistence is easier to test and reason about

CEF may still internally persist related content settings, but Navigator should maintain its own authoritative grant record.

## Proposed Architecture

## Permission Types

Introduce an app-owned permission taxonomy that maps CEF request flags into stable product concepts.

Recommended initial enum:

- `camera`
- `microphone`
- `cameraAndMicrophone`
- `geolocation`
- `unknown(rawValue)`

For future-proofing, also support representing multi-permission requests as a set when CEF surfaces combined flags.

## Data Model

New shared model types should live in `ModelKit`, per repo rules.

Recommended additions:

- `BrowserPermissionKind`
- `BrowserPermissionDecision`
- `BrowserPermissionPersistence`
- `BrowserPermissionOrigin`
- `BrowserPermissionRequest`
- `BrowserPermissionGrant`
- `BrowserPermissionPromptPresentation`
- `BrowserPermissionSessionID`
- `BrowserOSAuthorizationState`
- `BrowserPermissionSessionLifecycleState`

Recommended meanings:

- `BrowserPermissionDecision`
  - `allow`
  - `deny`
- `BrowserPermissionPersistence`
  - `once`
  - `persist`
- `BrowserPermissionGrant`
  - origin
  - permission kind
  - decision
  - timestamp
  - optional metadata such as last-used time

### Origin model

Permission requests must distinguish between:

- requesting origin
- top-level origin

Reason:

- CEF permission requests can originate from iframes, not only from the main frame
- product UI must not misleadingly imply that the top-level page directly requested the permission when an embedded frame did

Recommended model:

- `BrowserPermissionOrigin`
  - `requestingOrigin`
  - `topLevelOrigin`

Recommended prompt wording:

- if both origins match, show a normal single-origin prompt
- if they differ, show that the embedded origin is requesting access within the top-level site

### Permission request model versus prompt model

Do not let the runtime permission model depend on product UI wording.

Recommended split:

- `BrowserPermissionRequest`
  - browser ID
  - optional frame ID for diagnostics
  - requesting origin
  - top-level origin
  - requested kinds
  - request source metadata
- `BrowserPermissionPromptPresentation`
  - display title
  - explanation text
  - iconography
  - user-facing action labels

This keeps browser semantics stable even if prompt copy or presentation changes later. Concrete UI view-model types should live in the browser UI layer, not in `ModelKit`.

### Permission session model

Prompt tokens are necessary but not sufficient. The system should revolve around an explicit permission-session abstraction.

Recommended model:

- `BrowserPermissionSession`
  - session ID
  - browser ID
  - optional frame ID for diagnostics
  - requesting origin
  - top-level origin
  - requested kinds
  - current lifecycle state
  - optional site decision
  - optional persistence mode
  - current OS authorization state snapshot
  - pending native callback handles associated with the session

Why this matters:

- a permission request often spans multiple asynchronous steps
- site decision and OS authorization are separate phases
- multiple incoming CEF callbacks may need to collapse into one user-visible prompt
- session state is the only reliable place to enforce one-time callback resolution

### Permission resolution state machine

The implementation should use an explicit state machine instead of ad hoc booleans.

Recommended states:

- `idle`
- `requestedBySite`
- `checkingStoredPolicy`
- `waitingForUserPrompt`
- `waitingForOSAuthorization`
- `resolvedAllow`
- `resolvedDeny`
- `cancelled`

Recommended invariant:

- every session reaches exactly one terminal state:
  - `resolvedAllow`
  - `resolvedDeny`
  - `cancelled`

Recommended guard:

- terminal sessions must reject any further resolution attempts

### Dismissal semantics

Define dismissal without explicit user choice as `cancelled`.

Examples:

- user closes the prompt UI without choosing
- the active tab changes and the prompt is removed
- the browser loses visibility and Navigator dismisses the prompt
- the app begins shutdown

Required behavior:

- cancelled sessions resolve all attached native callbacks with deny or cancel semantics as required by the underlying CEF callback type
- cancelled sessions do not persist policy
- cancelled sessions are terminal and may not later become allow or deny

### Request deduplication

Navigator should not create one prompt per raw CEF callback.

Recommended deduplication rule:

- only one active permission session may exist for a given:
  - browser ID
  - requesting origin
  - top-level origin
  - effective permission set

Recommended behavior for duplicate incoming requests:

- attach the new native callback to the existing active session
- do not present a second prompt
- resolve all attached callbacks together when the session completes

This is important for WebRTC pages that often request camera and microphone in multiple overlapping calls.

Recommended diagnostics note:

- capture frame ID in the request and session metadata for debugging
- do not include frame ID in the initial deduplication key unless a concrete product need emerges

## High-Level Service Split

`BrowserRuntime` should not become the long-term owner of site-permission policy, storage, and UI.

Recommended structure:

- `BrowserRuntime`
  - thin bridge adapter
  - browser identity and lifecycle integration
  - no product-level permission policy
- `BrowserPermissionService`
  - central orchestration entry point
- `BrowserPermissionSessionManager`
  - session state machine
  - deduplication
  - native callback ownership coordination through session IDs
- `BrowserPermissionStore`
  - persisted grants and reset operations
- `BrowserPermissionUIController`
  - prompt presentation and dismissal
- `LocationAuthorizationController`
  - Core Location authorization controller

Recommended ownership rule:

- `BrowserRuntime` forwards native permission requests into `BrowserPermissionService`
- `BrowserPermissionService` decides whether to:
  - auto-resolve from stored policy
  - request OS authorization
  - show UI
  - cancel

This keeps `BrowserRuntime` from turning into a large mixed-responsibility object.

### Canonical session ownership

Session ownership must be explicit to avoid split-brain behavior.

Recommended rule:

- native owns the pending raw callback attachment registry keyed by session ID
- Swift owns the canonical logical session record and terminal session state through `BrowserPermissionSessionManager`

Recommended flow:

- native receives the CEF callback first and provisions or looks up the native pending entry
- Swift becomes authoritative for logical lifecycle once the request is bridged into `BrowserPermissionService`
- native must not independently run product-policy decisions in phase one
- native may only use a deliberately designed fast-path cache if it is explicitly introduced later with strict coherence rules

## Native bridge layer

Add a dedicated CEF permission handler in `MiumKit`.

### CEF thread model

All CEF permission callbacks are invoked on the CEF UI thread, not the app main thread by default.

Native code must ensure that:

- CEF continuation or cancellation callbacks execute on the CEF UI thread
- bridging into Swift does not block the CEF UI thread
- no Swift UI or main-thread work is performed synchronously inside the CEF callback path

This prevents deadlocks where a CEF callback synchronously re-enters Swift UI or other main-thread-only work.

Recommended native additions:

- include `cef_permission_handler_capi.h` in [`MiumCEFBridgeCefTypes.h`](/Users/rk/Developer/Navigator/MiumKit/Sources/MiumKit/include/MiumCEFBridgeCefTypes.h#L1)
- add `MiumNoopPermissionHandlerState`
- implement native ref-count methods for the permission handler
- wire `state->client.get_permission_handler`
- implement:
  - media access prompt path
  - generic permission prompt path
  - prompt dismissal path
  - session lookup and callback attachment
  - browser teardown cancellation
  - navigation-driven cancellation

Native responsibilities:

- map incoming CEF permission requests into Navigator request models
- create or reuse a permission session
- attach raw CEF callbacks to the active session
- forward permission requests into the Swift-owned permission service unless an explicitly designed synchronized fast-path policy cache exists
- ensure callbacks are continued or canceled exactly once
- cancel stale prompts when the browser closes, navigates away, or the prompt is dismissed upstream

### Session ID generation

Session IDs should be generated in the native layer when the first CEF permission callback for a logical session is observed.

Reason:

- native receives the callback first
- native must attach callbacks immediately
- Swift cannot safely create the first identifier before native callback storage exists

### Permission flag normalization

Native permission requests should normalize raw CEF permission flags into Navigator's internal permission-kind representation before bridging into Swift.

Reasons:

- Swift should not need to understand raw CEF flag combinations
- unsupported raw flag combinations can be classified consistently in one place
- logging stays tied to Navigator's internal vocabulary instead of CEF-specific bit patterns

### Stable bridge payload

Do not use ad hoc JSON as the primary ABI for permission requests.

Recommended approach:

- add a dedicated stable C bridge payload for permission events
- prefer a fixed struct or fixed callback signature containing:
  - session ID
  - browser ID
  - requesting origin
  - top-level origin
  - permission flags

The exact ABI shape can be:

- a stable C struct
- or a dedicated callback with fixed scalar/string parameters

The important constraint is:

- permission transport should be typed and ABI-stable
- it should not rely on free-form dictionaries or JSON blobs

### Browser lifetime invariants

Add explicit invariants:

- no active permission session may outlive its browser
- browser destruction must cancel all active sessions for that browser
- native cancellation must call the corresponding CEF callback cancellation path even if Swift never responds

### Navigation invariants

Add explicit rule:

- if the main-frame origin changes while a permission session is unresolved, cancel the session

This avoids orphaned prompts when the user navigates away while the permission UI is still visible.

### Renderer termination invariants

Add explicit rule:

- renderer termination or browser invalidation must cancel all unresolved sessions for that browser
- prompt UI should dismiss immediately
- no persistence should occur unless a terminal explicit user decision had already been recorded and the OS-authorization path completed successfully

### Session timeout safeguard

Permission sessions should automatically cancel if unresolved after a reasonable timeout to prevent stale prompts from surviving unusual UI states.

Recommended initial behavior:

- use a long but finite timeout measured in minutes, not seconds
- timeout should resolve the session as `cancelled`
- timeout should not persist policy

## Swift runtime layer

Extend `BrowserRuntime` with a thin permission request transport and resolution API.

Recommended public runtime surface:

- a handler registration API for browser-scoped permission requests
- a resolution API that accepts:
  - session ID
  - decision
  - persistence mode

`BrowserRuntime` should remain `@MainActor` for UI-facing prompt coordination.

`BrowserRuntime` should not own:

- deduplication policy
- stored grant policy
- OS authorization orchestration
- prompt presentation logic beyond forwarding to the owning service

## Permission service layer

Add an explicit `BrowserPermissionService` on the Swift side.

Recommended responsibilities:

- receive typed permission requests from `BrowserRuntime`
- create or look up sessions in the session manager
- consult the persisted permission store
- preflight macOS TCC status
- present prompt UI
- resolve native session IDs

This service should be the only layer allowed to combine:

- app persistence
- OS permission state
- browser prompt UI

Recommended supporting components:

- `BrowserPermissionSessionManager`
- `BrowserPermissionStore`
- `BrowserPermissionUIController`
- `LocationAuthorizationController`

## Persistence layer

Persist site permission decisions in app-owned storage rather than only in CEF internals.

Recommended behavior:

- key by normalized origin, not full URL
- store permission kind separately
- support clearing all permissions and clearing per-origin
- treat "allow once" as ephemeral and non-persistent
- treat "allow for this site" as persistent

Recommended storage location:

- model definitions in `ModelKit`
- persistence implementation in the app's existing storage layer, likely via `DataStore` or the browser-specific persistence area already used for stored browser state

### Grant normalization

For phase one, use exact origin matching:

- scheme
- host
- effective port

Do not key by:

- full URL path
- query
- fragment

Recommended explicit policy:

- phase one persists by exact origin, not by eTLD+1

Reason:

- exact origin is safer
- it matches the stricter browser security boundary
- it avoids surprising grant bleed between sibling subdomains

If product later wants site-group behavior, add it intentionally as a separate abstraction instead of silently collapsing hosts.

### Persistence rules

- `Allow Once`
  - resolve prompt as allowed only if OS authorization succeeds
  - do not persist
- `Always Allow`
  - persist allow for the origin and permission kind only after OS authorization succeeds
- `Deny`
  - persist deny immediately only when the user explicitly chooses deny and product opts into durable denials

Recommendation:

- persist both durable allows and durable denials
- allow clearing from a future settings surface

### Combined-request persistence semantics

Combined requests should be combined only at the prompt layer, not at the persistence layer.

Recommended rule:

- camera + microphone may appear as one prompt
- persistence should still store independent grants per permission kind

Reasons:

- later microphone-only requests can reuse the microphone grant
- later camera-only requests can reuse the camera grant
- revocation remains per-kind instead of requiring combined opaque grant handling

### Persistence write timing

Recommended sequencing:

- `Allow Once`
  - user chooses allow once
  - OS authorization is checked or requested
  - if OS authorization succeeds, resolve allow
  - do not persist
- `Always Allow`
  - user chooses always allow
  - OS authorization is checked or requested
  - only if OS authorization succeeds, persist the allow grant
  - then resolve allow
- `Deny`
  - if the user explicitly chooses deny, persist deny immediately only if durable denials are enabled
  - then resolve deny
- `Cancelled`
  - never persist

### Optional expiration support

Optional but recommended fields:

- `lastUsedAt`
- `expiresAt`

Phase one does not need automatic expiration, but the model should leave room for it so the persistence format does not need a breaking redesign later.

### Settings follow-up

Phase one can ship without a full settings UI if storage and reset hooks are implemented.

Minimum recommended management path:

- internal API to clear all browser site permissions
- internal API to clear one origin

Product-facing settings UI can follow after the core flow ships.

## UI layer

Navigator should present an explicit site permission prompt in the browser shell.

Recommended UX shape for phase one:

- anchored browser-level prompt surface
- clear origin display
- clear permission type display
- buttons:
  - `Allow Once`
  - `Always Allow`
  - `Deny`

Optional but recommended:

- a disclosure for macOS-level denial with guidance to System Settings
- when origins differ, show both the requesting origin and the top-level site

Prompt requirements:

- handle combined requests such as camera + microphone in a single prompt
- remain scoped to the active browser or tab
- never present as a global app-level prompt disconnected from the requesting browser context

Anchoring rule:

- the prompt UI should attach to the browser chrome or tab container corresponding to the requesting browser instance
- permission prompts must remain spatially associated with the correct tab rather than appearing as floating global windows

If new views are added, follow repo view rules:

- add `Inject`
- import `Vendors`
- pair each new view with a view model
- make view models `@Observable`

## macOS TCC Strategy

## Privacy usage strings

Add the following to the main app plist:

- `NSCameraUsageDescription`
- `NSMicrophoneUsageDescription`
- `NSLocationWhenInUseUsageDescription`

These strings are required before macOS can grant the underlying permissions.

Recommended source of truth:

- edit [`Navigator/Resources/Info.plist`](/Users/rk/Developer/Navigator/Navigator/Resources/Info.plist#L1)

## Helper bundle privacy keys

Navigator runs a multi-process CEF architecture with helper apps. The safest packaging invariant is to ensure helper `Info.plist` files also carry the same privacy usage strings.

Implementation recommendation:

- do not hand-edit `Vendor/CEF/Release/.../Info.plist`
- extend helper normalization in [`CEFPackager/main.swift`](/Users/rk/Developer/Navigator/CEFPackager/main.swift#L820) so required privacy keys are inserted or verified while helpers are renamed and normalized
- optionally add verification in packaging scripts so missing privacy keys fail packaging early

Even if macOS ultimately attributes TCC to the main app bundle in most flows, mirroring the keys into helpers avoids brittle process-boundary assumptions in a Chromium multi-process embed.

## OS authorization preflight

Before resolving a site-level allow decision, Navigator should preflight OS authorization.

Recommended approach:

- camera: use AVFoundation authorization status for video capture
- microphone: use AVFoundation authorization status for audio capture
- geolocation: use Core Location authorization status

Recommended policy:

- if OS status is already authorized, proceed with site-level allow
- if OS status is not determined, request OS permission before continuing the CEF callback
- if OS status is denied or restricted, deny the site request and surface user guidance

This avoids a poor experience where Navigator tells the site "allowed" but the OS blocks access immediately afterward.

## OS authorization caching

Maintain an app-owned cached authorization snapshot for:

- camera
- microphone
- location

Recommended refresh points:

- app launch
- app foreground
- completion of an OS authorization request
- any relevant delegate or authorization callback

This reduces duplicated authorization checks and keeps diagnostics clearer.

## Location authorization controller

Geolocation requires a real `CLLocationManager` owner to request authorization.

Recommended component:

- `LocationAuthorizationController`

Responsibilities:

- own a `CLLocationManager`
- request `when in use` authorization
- forward delegate updates into the permission service
- remain main-thread-owned

Do not bury `CLLocationManager` ownership inside unrelated runtime code.

## Detailed Implementation Workstreams

## Workstream 1: Privacy metadata and packaging

### Required changes

- update [`Navigator/Resources/Info.plist`](/Users/rk/Developer/Navigator/Navigator/Resources/Info.plist#L1) with camera, microphone, and location usage descriptions
- extend helper plist normalization in [`CEFPackager/main.swift`](/Users/rk/Developer/Navigator/CEFPackager/main.swift#L820)
- add packaging verification for those keys

### Recommended verification additions

- `CEFPackager` should fail if required helper privacy keys are absent after normalization
- optionally extend [`scripts/verify_runtime.sh`](/Users/rk/Developer/Navigator/scripts/verify_runtime.sh#L1) to validate helper privacy metadata in packaged output

### Explicit caution

Do not treat files under `Vendor/CEF/Release` as hand-maintained inputs.

## Workstream 2: Native CEF permission plumbing

### Required changes

In [`MiumCEFBridgeNative.mm`](/Users/rk/Developer/Navigator/MiumKit/Sources/MiumKit/MiumCEFBridgeNative.mm):

- add permission handler structs and ref-count support
- add permission-session bookkeeping
- add session ID generation
- map CEF permission callbacks to session records
- expose native resolution entry points

In [`CEFBridge.h`](/Users/rk/Developer/Navigator/MiumKit/Sources/MiumKit/CEFBridge.h#L1):

- add C bridge APIs to:
  - register a permission request handler
  - resolve a pending permission session
  - optionally clear or dismiss pending sessions if needed

In [`CEFBridge.mm`](/Users/rk/Developer/Navigator/MiumKit/Sources/MiumKit/CEFBridge.mm#L1):

- forward new APIs to native bridge functions

In [`MiumCEFBridgeCefTypes.h`](/Users/rk/Developer/Navigator/MiumKit/Sources/MiumKit/include/MiumCEFBridgeCefTypes.h#L1):

- include permission-handler C API types

### Callback-lifetime rules

The native implementation must guarantee:

- every pending callback is resolved once
- callbacks are canceled on browser teardown if unresolved
- prompt dismissal is idempotent
- continuation runs on the CEF UI thread
- duplicate requests attached to the same session are resolved consistently

Recommended guard:

- native resolution must be idempotent
- repeated attempts to resolve the same session after terminal completion should be ignored safely

### Request categorization rules

Recommended initial mapping:

- `OnRequestMediaAccessPermission`
  - audio only -> microphone
  - video only -> camera
  - audio + video -> cameraAndMicrophone
- `OnShowPermissionPrompt`
  - geolocation -> geolocation
  - unsupported types -> explicitly deny and log the attempted kind and origin

Unsupported permission kinds should not silently auto-allow.

## Workstream 3: Swift bridge and service

### Required changes

In [`BrowserRuntime.swift`](/Users/rk/Developer/Navigator/BrowserRuntime/Sources/BrowserRuntime/BrowserRuntime.swift#L1):

- add a permission request callback type
- add decode or transport handling for typed permission payloads
- add registration and cleanup paths parallel to existing browser-scoped handlers
- add an API for resolving permission sessions

Recommended new types:

- `BrowserRuntimePermissionRequest`
- `BrowserRuntimePermissionResolution`

### Service responsibilities

Recommended new service responsibilities:

- normalize origin display
- collapse duplicate prompts for the same browser and origin while one is already visible
- preflight OS authorization
- ask user for site-level permission
- persist durable grants
- resolve session IDs back through `BrowserRuntime`

### UI location

Preferred first integration point:

- browser chrome or top-of-page permission bar attached to the active browser tab

This avoids modal global sheets for ordinary site prompts and matches browser expectations more closely.

## Workstream 4: Persistence and settings

### Grant normalization

Use exact origin-level matching:

- scheme
- host
- effective port

Do not key by:

- full URL path
- query
- fragment

### Persistence rules

- `Allow Once`
  - resolve prompt as allowed only if OS authorization succeeds
  - do not persist
- `Always Allow`
  - persist per-permission-kind allow only after OS authorization succeeds
- `Deny`
  - persist deny immediately only for explicit user-deny actions when durable denials are enabled

Recommendation:

- persist both durable allows and durable denials
- allow clearing from a future settings surface

### Settings follow-up

Phase one can ship without a full settings UI if storage and reset hooks are implemented.

Minimum recommended management path:

- internal API to clear all browser site permissions
- internal API to clear one origin

Product-facing settings UI can follow after the core flow ships.

## Media-Stream Flag Policy

`MIUM_CEF_ENABLE_MEDIA_STREAM` should not remain the primary production path for site media access.

Recommended policy:

- keep it only as a development/test override
- gate it clearly as an override
- ensure normal product builds use the permission handler flow instead

Override rule:

- when enabled, the flag must bypass the permission service entirely and allow media access unconditionally
- it must not enter a hybrid state where the permission service still attempts site-level prompting or persistence

If kept, document that it bypasses normal per-origin policy.

## Phase Plan

## Phase -1: Permission plumbing diagnostics

Deliverables:

- native permission handler wired
- typed bridge payloads or equivalent stable ABI wired
- structured logging for incoming permission requests
- auto-deny behavior for all requests

Acceptance criteria:

- `getUserMedia` requests reach Navigator-owned permission plumbing
- geolocation requests reach Navigator-owned permission plumbing
- requests can be observed and auto-denied without crashes, leaks, or dangling callbacks

## Phase 0: Packaging and prompt architecture groundwork

Deliverables:

- plist privacy keys in the main app
- helper privacy key normalization in packager
- native permission-session scaffolding
- permission service and session-manager architecture
- prompt and request model split

Acceptance criteria:

- packaged app and helpers contain required privacy keys
- no permission UI yet, but the bridge can emit a typed prompt event and deny safely if unhandled

## Phase 1: Camera and microphone

Deliverables:

- `OnRequestMediaAccessPermission` handling
- Swift prompt UI
- OS preflight for camera and mic
- durable per-origin store

Acceptance criteria:

- a camera-only site can prompt and succeed
- a microphone-only site can prompt and succeed
- a combined audio/video site can prompt and succeed
- durable grants suppress repeat prompts after relaunch

## Phase 2: Geolocation

Deliverables:

- `OnShowPermissionPrompt` support for geolocation
- OS location preflight
- same prompt and persistence system as media access

Acceptance criteria:

- a geolocation site can prompt and receive location after grant
- denied OS location yields clear denial behavior
- durable geolocation grants behave consistently across relaunch

## Phase 3: Settings and broader permission coverage

Deliverables:

- clear/reset management UI or app command
- additional permission kinds if needed
- diagnostics for current stored grants

Acceptance criteria:

- stored permissions are inspectable and clearable
- unsupported permissions fail explicitly rather than silently

## File-Level Implementation Map

Primary implementation targets:

- [`MiumCEFBridgeNative.mm`](/Users/rk/Developer/Navigator/MiumKit/Sources/MiumKit/MiumCEFBridgeNative.mm)
- [`CEFBridge.h`](/Users/rk/Developer/Navigator/MiumKit/Sources/MiumKit/CEFBridge.h)
- [`CEFBridge.mm`](/Users/rk/Developer/Navigator/MiumKit/Sources/MiumKit/CEFBridge.mm)
- [`MiumCEFBridgeCefTypes.h`](/Users/rk/Developer/Navigator/MiumKit/Sources/MiumKit/include/MiumCEFBridgeCefTypes.h)
- [`BrowserRuntime.swift`](/Users/rk/Developer/Navigator/BrowserRuntime/Sources/BrowserRuntime/BrowserRuntime.swift)
- [`Navigator/Resources/Info.plist`](/Users/rk/Developer/Navigator/Navigator/Resources/Info.plist)
- [`CEFPackager/main.swift`](/Users/rk/Developer/Navigator/CEFPackager/main.swift)

Likely new files:

- `ModelKit/Sources/ModelKit/BrowserPermissionModels.swift`
- a browser permission service and session manager in the app or browser runtime layer
- a permission prompt view and view model in the browser UI package or Navigator target

Likely test files:

- new `MiumKit` native bridge tests for permission callbacks
- new `BrowserRuntime` tests for prompt decoding and routing
- `ModelKit` tests for origin normalization and persistence model behavior
- packager tests for helper privacy key normalization if the current test surface supports it

## Verification Plan

## Automated tests

### MiumKit native tests

Add tests for:

- permission handler registration on the native client
- media session creation
- geolocation session creation
- callback continuation on allow
- callback cancellation on deny
- callback cancellation on browser destroy
- prompt dismissal on navigation or browser close
- unsupported permission kinds not auto-allowing
- duplicate incoming requests collapsing into one session
- iframe-origin request metadata carrying both requesting and top-level origin
- renderer crash cancelling unresolved sessions
- repeated resolution attempts being ignored safely

### BrowserRuntime tests

Add tests for:

- decoding or forwarding permission request payloads
- prompt delivery to the correct browser
- duplicate suppression behavior if added
- resolution API routing
- cleanup on browser close and runtime shutdown
- cross-tab isolation for simultaneous requests

### Packager tests

Add tests or verification checks for:

- required privacy keys in the app plist
- required privacy keys copied or normalized into helper plists
- package-time failure when required privacy keys are missing

## Manual verification matrix

Minimum manual matrix:

- fresh install, camera site, first grant
- fresh install, microphone site, first grant
- fresh install, camera+microphone site, first grant
- fresh install, geolocation site, first grant
- deny camera, reload page
- deny geolocation, reload page
- allow once, reload page
- always allow, relaunch app, revisit origin
- site triggers overlapping camera requests before the first prompt is answered; one prompt appears and all attached requests resolve consistently
- user chooses site-level allow, macOS OS prompt appears, user denies at the OS layer, and no durable allow grant is persisted
- close tab while prompt is visible
- navigate away while prompt is visible
- OS-level denied camera with site-level allow
- OS-level denied microphone with site-level allow
- OS-level denied location with site-level allow

Suggested public test sites:

- WebRTC demo page for camera and microphone
- a simple geolocation demo page

## Observability and Diagnostics

Add targeted logging around:

- incoming permission request type
- requesting origin
- whether a stored grant was used
- whether OS authorization blocked the request
- final resolution path

Do not log sensitive page content or device payloads.

Recommended diagnostics additions:

- include permission-store summary in browser diagnostics later
- surface "prompt unresolved on teardown" as a debug assertion or log in development

## Permission debug panel

Add a diagnostics surface or dump API for permission state.

Recommended output:

- active sessions
- stored grants
- cached OS authorization status
- pending native callback counts per session

Minimum useful API:

- `BrowserRuntime.dumpPermissionState()` or equivalent service-level diagnostics hook

## Permission event trace

Emit structured permission lifecycle events such as:

- `permissionRequested`
- `permissionPromptShown`
- `permissionUserDecision`
- `permissionOSRequest`
- `permissionOSResult`
- `permissionCallbackResolved`
- `permissionSessionCancelled`

Recommended fields:

- browser ID
- session ID
- requesting origin
- top-level origin
- permission kinds
- final resolution state

## Risks

## Callback lifetime bugs

Risk:

- leaking or double-resolving CEF callbacks

Mitigation:

- keep callback ownership native
- session-based resolution only
- teardown cancellation tests

## Deadlocks or incorrect thread usage

Risk:

- resolving prompts off the CEF UI thread

Mitigation:

- continue/cancel only from `runOnCefMainThread(...)`
- do not call CEF APIs while holding `gStateLock`

## Repeated site requests causing prompt storms

Risk:

- overlapping callbacks for the same origin and permission create duplicate prompts

Mitigation:

- session deduplication
- multi-callback attachment to one active session
- browser-scoped prompt suppression while a matching session is already active

## TCC ordering problems

Risk:

- Navigator grants the site request before macOS authorization is known

Mitigation:

- OS preflight before allowing the site-level request

## Packaging drift

Risk:

- app plist is fixed but helpers remain missing privacy strings in packaged artifacts

Mitigation:

- enforce helper normalization in `CEFPackager`
- add packaging verification

## Persistence mismatches

Risk:

- storing by full URL or inconsistent origin normalization leads to surprising re-prompts

Mitigation:

- centralize origin normalization in one shared model/helper
- test scheme, host, and port combinations explicitly

## Remaining Open Questions

- Where should the first permission prompt UI live: browser chrome, toolbar popover, or a lightweight sheet?
- Should the current `MIUM_CEF_ENABLE_MEDIA_STREAM` override remain available in production builds, or be restricted to development and CI only?

## Recommended Decisions

Unless product direction says otherwise, the recommended defaults are:

- persist both durable allows and durable denials
- use a browser-attached prompt bar for first UX
- preflight OS authorization for camera, microphone, and geolocation
- geolocation uses app-owned Core Location preflight in phase two
- keep `MIUM_CEF_ENABLE_MEDIA_STREAM` as a development-only override

## Definition Of Done

This work should only be considered complete when all of the following are true:

- Navigator prompts for camera, microphone, and geolocation at the site level
- macOS privacy usage strings exist in the app and packaged helpers
- site-level decisions can be allowed once, always allowed, or denied
- persistent grants survive relaunch
- duplicate overlapping requests collapse into one active session per browser and origin tuple
- iframe-origin requests preserve both requesting-origin and top-level-origin context
- browser teardown and navigation cannot leave dangling unresolved CEF callbacks
- the original unsupported behavior is verified end-to-end on a clean install, not just after prior permissions or warmed caches
