# Sparkle Integration Engineering Plan

## Purpose

This document defines the target architecture and rollout plan for adding Sparkle-based updates to Navigator.

The integration must do more than surface `Check for Updates…`. It must:

- align with Navigator's existing `@Dependency` architecture
- keep Sparkle isolated behind app-owned interfaces
- preserve AppKit lifecycle correctness
- make update state and preference ownership explicit
- define failure handling instead of assuming the happy path
- define the release pipeline required to actually ship updates

## Current Repo State

Navigator is a programmatic macOS AppKit app.

Relevant code paths:

- [`Navigator/AppDelegate.swift`](/Users/rk/Developer/Navigator/Navigator/AppDelegate.swift)
  - owns `applicationDidFinishLaunching(_:)`
  - installs the app menu in `installMainMenu()`
  - owns settings-window presentation
- [`Navigator/NavigatorAppRuntime.swift`](/Users/rk/Developer/Navigator/Navigator/NavigatorAppRuntime.swift)
  - bootstraps the app delegate and run loop
- [`Navigator/NavigatorSettingsView.swift`](/Users/rk/Developer/Navigator/Navigator/NavigatorSettingsView.swift)
  - renders the settings UI, including the colophon section
- [`Navigator/NavigatorSettingsViewModel.swift`](/Users/rk/Developer/Navigator/Navigator/NavigatorSettingsViewModel.swift)
  - owns settings state and actions
- [`Navigator/Resources/Info.plist`](/Users/rk/Developer/Navigator/Navigator/Resources/Info.plist)
  - currently contains no Sparkle keys
- [`Navigator/Resources/Navigator.entitlements`](/Users/rk/Developer/Navigator/Navigator/Resources/Navigator.entitlements)
  - currently does not enable App Sandbox
- [`Vendors/Package.swift`](/Users/rk/Developer/Navigator/Vendors/Package.swift)
  - is the repo's third-party dependency aggregation layer

Observed constraints:

- third-party libraries are re-exported through `Vendors`
- user-facing strings in `Navigator` are localized through [`Navigator/Localizable.xcstrings`](/Users/rk/Developer/Navigator/Navigator/Localizable.xcstrings)
- the app target is macOS 14
- the repo already uses Point-Free Dependencies; new app services should follow that model
- repo guidance explicitly forbids making an actor-isolated type the direct `DependencyKey` value when protocol requirements are nonisolated

## Product Goals

- allow users to check for updates from within Navigator
- let Sparkle manage scheduled update checks instead of Navigator inventing its own scheduler
- expose updater preferences in the existing settings flow
- support signed website distribution with a hosted appcast
- keep Sparkle-specific APIs out of broad app and UI layers

## Non-Goals

- migrating the app to App Sandbox in the same change
- building a custom updater engine or scheduler
- mirroring Sparkle defaults into a second Navigator-owned persistence layer
- supporting App Store distribution through Sparkle
- implementing a custom update UI before the standard Sparkle path works

## Official Sparkle Constraints

This plan is based on Sparkle's official documentation:

- the modern API is `SPUStandardUpdaterController`, not `SUUpdater`
- programmatic AppKit apps should initialize Sparkle in application code rather than relying on Interface Builder wiring
- `SUFeedURL` and `SUPublicEDKey` belong in `Info.plist`
- Sparkle already owns scheduled checks and update preference persistence
- sandboxed apps require extra Sparkle service configuration, but Navigator is not sandboxed today

Primary references:

- https://sparkle-project.org/documentation/
- https://sparkle-project.org/documentation/programmatic-setup/
- https://sparkle-project.org/documentation/preferences-ui/
- https://sparkle-project.org/documentation/publishing/
- https://sparkle-project.org/documentation/sandboxing/

## Architecture Decision Summary

Navigator should not introduce an `AppDelegate`-owned `NavigatorUpdaterController` as the main abstraction.

Instead:

- Sparkle is wrapped behind an app-owned `UpdaterClient` dependency
- the live dependency is backed by a hidden `@MainActor` Sparkle runtime service
- `AppDelegate` only bootstraps the updater early and routes menu actions into the dependency
- settings view models talk to `UpdaterClient`, not Sparkle types
- Sparkle imports remain isolated to one small integration surface in `Navigator`, plus package wiring in `Vendors`

This is the same architectural shape Navigator already uses for other app services and it keeps the updater testable.

## Module Boundaries

### `Vendors`

Responsibilities:

- declare the remote Sparkle package dependency
- expose the `Sparkle` product for local consumers

Non-responsibilities:

- no app-specific updater policy
- no menu wiring
- no settings behavior

### `Navigator`

Responsibilities:

- own the dependency client and live integration
- own app menu wiring
- own settings-view-model integration
- own logging and app-specific failure handling

Non-responsibilities:

- no custom archive signing tool
- no ad hoc publication logic inside runtime app code

### `NavigatorTests`

Responsibilities:

- test dependency wiring
- test menu routing
- test settings behavior against a test updater dependency

Non-responsibilities:

- do not attempt to integration-test Sparkle framework internals

## Target Architecture

### Layer 1: Public dependency surface

Introduce `UpdaterClient` as the only app-facing updater API.

Recommended shape:

```swift
import Dependencies
import Foundation

struct UpdaterState: Equatable, Sendable {
    var canCheckForUpdates: Bool
    var automaticallyChecksForUpdates: Bool
    var automaticallyDownloadsUpdates: Bool
    var lastUpdateCheckDate: Date?
    var isCheckingForUpdates: Bool
}

struct UpdaterClient: Sendable {
    var start: @MainActor @Sendable () -> Void
    var checkForUpdates: @MainActor @Sendable () -> Void
    var state: @MainActor @Sendable () -> UpdaterState
    var setAutomaticallyChecksForUpdates: @MainActor @Sendable (Bool) -> Void
    var setAutomaticallyDownloadsUpdates: @MainActor @Sendable (Bool) -> Void
}
```

Rules:

- app code uses `@Dependency(\.updaterClient)`
- UI and view models do not import `Sparkle`
- settings code reads and writes updater preferences through this client only

### Layer 2: Hidden live runtime service

The live dependency should be backed by a hidden `@MainActor` runtime service inside `Navigator`.

Recommended type:

- `@MainActor final class SparkleUpdaterService`

Responsibilities:

- own `SPUStandardUpdaterController`
- own any Sparkle delegate objects
- translate Sparkle properties into `UpdaterState`
- provide the mutation methods used by `UpdaterClient`
- centralize Sparkle-specific logging

Non-responsibilities:

- it is not a `DependencyKey`
- it is not referenced directly from views or view models

Retention rule:

- `SparkleUpdaterService` must strongly retain all Sparkle delegate and user-driver delegate objects for as long as Sparkle may call them
- do not create delegate objects as ephemeral locals during startup
- delegate lifetime must be tied to the app-lifetime updater service

### Layer 3: Dependency-key wrapper

Because repo guidance forbids actor-isolated types from directly conforming to `DependencyKey`, the key holder must remain nonisolated.

Required shape:

- `UpdaterClient` is the dependency value
- `UpdaterClient.liveValue` is a nonisolated wrapper
- the wrapper forwards into the hidden main-actor runtime service

Important rule:

- do not make `@MainActor SparkleUpdaterService` itself the dependency value
- do not make an actor-isolated type conform to `DependencyKey`
- `UpdaterClient.liveValue` must forward into one retained app-lifetime runtime instance
- do not construct a fresh `SparkleUpdaterService` on each dependency access or closure invocation

### Layer 4: AppDelegate integration

`NavigatorAppDelegate` should not own raw Sparkle objects. It should only interact with the dependency.

Required behavior:

- resolve `@Dependency(\.updaterClient)`
- bootstrap the updater early in `applicationDidFinishLaunching(_:)`
- expose an `@objc` menu action that calls `updaterClient.checkForUpdates()`

This keeps the menu system decoupled from Sparkle types and matches the repo's dependency style.

Ordering rule:

- do not resolve or start the updater from static or global initializers
- dependency access should happen from AppKit lifecycle methods and AppKit action handlers where startup ordering is explicit

### Layer 5: Settings integration

`NavigatorSettingsViewModel` should use `UpdaterClient` for updater settings.

Required behavior:

- snapshot state from `updaterClient.state()`
- drive the settings UI from `UpdaterState`
- call setter methods on the dependency when a user toggles a setting

Do not:

- import `Sparkle` into the settings view or view model
- create duplicate Navigator defaults for updater preferences

## Internal API Contract

The integration should expose exactly one app-facing contract.

### `UpdaterClient`

Required operations:

- `start()`
  - ensures Sparkle is initialized and scheduling is active
  - must be idempotent
- `checkForUpdates()`
  - triggers a user-initiated check
- `state()`
  - returns the current updater snapshot
- `setAutomaticallyChecksForUpdates(_:)`
  - updates Sparkle's persisted preference
- `setAutomaticallyDownloadsUpdates(_:)`
  - updates Sparkle's persisted preference

Optional future expansion, only if product requirements justify it:

- `updates() -> AsyncStream<UpdaterState>`
  - for continuously reactive UI if Navigator later needs explicit in-app update-status presentation

Phase-one state semantics:

- `state()` is a pull-based snapshot API
- phase one does not require continuous observation of Sparkle internals
- views and view models refresh updater state on appearance and after local updater actions
- if Navigator later needs continuous updater UI, add an explicit `updates()` stream instead of overloading `state()`

### `UpdaterState`

Phase-one ownership:

- `canCheckForUpdates`
- `automaticallyChecksForUpdates`
- `automaticallyDownloadsUpdates`
- `lastUpdateCheckDate`
- `isCheckingForUpdates`

Why this model exists:

- it gives the app an explicit state contract
- it prevents raw Sparkle objects from becoming ambient shared state
- it makes tests about behavior rather than third-party framework plumbing

Failure mapping rule:

- `canCheckForUpdates` must be `false` if Sparkle startup failed or required local Sparkle configuration is unavailable in release builds

## Threading and Lifecycle Guarantees

Sparkle interactions are main-thread bound. The plan must state this explicitly.

Required rules:

- all Sparkle framework calls occur on `@MainActor`
- `UpdaterClient` entry points are `@MainActor`
- `NavigatorAppDelegate`, settings view models, and AppKit actions call updater methods from the main actor only
- no `Task.detached` is introduced for updater operations

Lifecycle rules:

- `start()` must run during app launch on a cold start
- the hidden Sparkle runtime service must remain alive for the full app lifetime
- the updater must not be created lazily only after the settings window opens
- `checkForUpdates()` must work from the first cold launch before any settings UI is shown

Recommended startup posture:

- use `SPUStandardUpdaterController(startingUpdater: true, ...)`
- bootstrap it during `applicationDidFinishLaunching(_:)`
- let Sparkle own its scheduling behavior

## Menu Ownership

Navigator should add a standard `Check for Updates…` item to the application menu.

Required wiring:

- menu item target is `NavigatorAppDelegate`
- menu item action is an `@objc` method on the delegate such as `checkForUpdates(_:)`
- that method calls `@Dependency(\.updaterClient).checkForUpdates()`

Do not:

- wire the menu item target directly to `SPUStandardUpdaterController`
- expose Sparkle selectors in app-menu construction code

Reasoning:

- it keeps Sparkle behind the dependency boundary
- it keeps AppKit menu code Sparkle-agnostic
- it preserves one internal API contract for all update actions

Enabled-state rule:

- phase one should keep `Check for Updates…` enabled by default
- if updater startup fails or local Sparkle configuration is invalid in release builds, Navigator may disable the menu item by reflecting `UpdaterState.canCheckForUpdates == false`
- do not add complex menu-state observation in phase one purely to mirror transient internal Sparkle timing

## Settings Ownership

Updater preferences belong to Sparkle, not to a parallel Navigator persistence layer.

Phase-one settings placement:

- add updater controls to the `colophon` section in [`Navigator/NavigatorSettingsView.swift`](/Users/rk/Developer/Navigator/Navigator/NavigatorSettingsView.swift)

Recommended controls:

- `Check for Updates…` button
- `Automatically check for updates` toggle
- `Automatically download updates` toggle

Required behavior:

- initialize from `UpdaterState`
- write changes through `UpdaterClient`
- after each settings mutation, immediately re-read `updaterClient.state()` and publish the refreshed snapshot

Localization requirements:

- add local typed strings in [`Navigator/Localizable.xcstrings`](/Users/rk/Developer/Navigator/Navigator/Localizable.xcstrings)
- include `en` and `ja`

Preference authority rule:

- `Info.plist` keys define first-launch defaults only
- once Sparkle has persisted a user preference, that persisted value is authoritative
- Navigator must not reapply product defaults on subsequent launches

## `Info.plist` and Signing Configuration

### Required keys

Add to [`Navigator/Resources/Info.plist`](/Users/rk/Developer/Navigator/Navigator/Resources/Info.plist):

- `SUFeedURL`
  - stable HTTPS appcast URL
- `SUPublicEDKey`
  - public Ed25519 key from Sparkle's `generate_keys`

### Recommended security defaults

Enable immediately unless a verified Sparkle compatibility issue blocks it:

- `SUVerifyUpdateBeforeExtraction = YES`

Strongly consider enabling in the first rollout if feed signing is part of release ops:

- `SURequireSignedFeed = YES`

Preference defaults, only if product wants explicit non-default initial behavior:

- `SUEnableAutomaticChecks`
- `SUAutomaticallyUpdate`
- `SUAutomaticallyDownloadUpdates`

Rule:

- define startup defaults in `Info.plist`
- do not write runtime "defaulting" code on every launch that stomps user choices
- Sparkle configuration keys must be owned by the shipping app target `Info.plist`
- do not rely on ad hoc Debug-only or Release-only build-setting injection unless this document is updated to explain why

## Entitlements and Bundle Structure

### Entitlements

Navigator is not sandboxed today.

Phase-one posture:

- do not add sandbox-specific Sparkle service keys yet

If Navigator becomes sandboxed later:

- reevaluate `SUEnableInstallerLauncherService`
- reevaluate any downloader-service requirements from Sparkle's sandboxing guide

Important clarification:

- Sparkle does not require `com.apple.security.cs.disable-library-validation`
- Navigator currently has that entitlement for other reasons, but the Sparkle plan must not depend on it

### Bundle verification

Sparkle integration is not complete until the built product is checked.

Required verification:

- Sparkle is embedded in `Navigator.app/Contents/Frameworks/Sparkle.framework`
- the framework is signed correctly in the final app bundle
- Xcode/package integration results in effective `Embed & Sign` behavior for the shipping product

## Failure Strategy

The updater path must define expected behavior for failures.

If Sparkle fails to initialize in release builds:

- updater actions become unavailable through `UpdaterState.canCheckForUpdates == false`
- Navigator logs a high-signal startup failure in a dedicated updater log category
- the app otherwise continues to run

### Feed unavailable

Expected behavior:

- Sparkle presents its standard failure or no-update UI
- Navigator logs the failure context through app logging
- Navigator does not layer a second custom error dialog on top unless product asks for it

### Appcast malformed

Expected behavior:

- Sparkle refuses the update
- Navigator logs a structured error
- release engineering replaces the broken appcast server-side

### Signature mismatch or verification failure

Expected behavior:

- installation is blocked
- Sparkle presents its standard failure path
- Navigator logs a high-signal error event
- no custom bypass or override path exists in the app

### Installation failure

Expected behavior:

- user remains on the current version
- Sparkle presents the error
- Navigator logs the event
- the release owner investigates the archive, notarization, or appcast metadata

### Missing or invalid local Sparkle configuration

Examples:

- missing `SUFeedURL`
- missing `SUPublicEDKey`
- failure to create the Sparkle controller

Expected behavior:

- in debug: assert loudly
- in release: disable updater actions and emit clear logging

## Recovery Plan

If the production update path is broken:

1. fix or replace the hosted appcast server-side if possible
2. remove invalid update items rather than leaving a broken feed live
3. ship a manually distributed hotfix build if users are blocked
4. only publish a new appcast entry after smoke-testing against a real older signed build

There is no in-app bypass for broken verification or invalid signatures.

## Logging Taxonomy

Updater logs should use a dedicated subsystem and category with stable event naming.

Recommended baseline:

- subsystem: `com.navigator.Navigator`
- category: `Updater`

Required event families:

- updater startup
- repeated startup no-op
- user-initiated update check
- scheduled-check lifecycle, if surfaced
- appcast fetch or parse failure
- signature or verification failure
- installation failure
- updater preference mutation

Rule:

- prefer stable structured event names over ad hoc free-form log strings so failures can be correlated across release testing and production diagnostics

## Release Engineering Plan

Sparkle is only shippable when the release pipeline is explicit.

### Required CI or release steps

1. build the release app archive
2. sign the app with Developer ID
3. notarize the build
4. staple the notarization ticket
5. package the app into the chosen distribution archive
6. generate Sparkle signatures and appcast metadata using Sparkle tooling
7. upload the archive, appcast, and any release notes assets
8. invalidate CDN or caches as needed
9. smoke-test update discovery and installation from a previous signed build

### Sparkle tooling

Required tools to document in release automation:

- `generate_keys`
- `generate_appcast`

Optional depending on the chosen signing flow:

- `sign_update`

### Version discipline

Sparkle compares versions using bundle metadata. Navigator must enforce a strict policy.

Required policy:

- `CFBundleVersion` must always increase across published releases
- release automation should fail if the new `CFBundleVersion` is not greater than the latest published appcast item
- `CFBundleShortVersionString` should remain human-meaningful, but Sparkle correctness depends on `CFBundleVersion`

Archive format rule:

- archive format selection is not cosmetic
- it affects packaging, signing flow, appcast generation details, update installation behavior, and whether delta-update workflows are practical
- implementation should not begin until release engineering chooses one canonical website-distribution format

## Recommended Rollout Phases

### Phase 0: Finalize operational decisions

- choose the canonical `SUFeedURL`
- choose the archive format for website distribution
- define private-key ownership
- define where appcast publication runs
- decide whether signed feeds are enabled in v1

Exit criteria:

- release ownership and publication flow are explicit

### Phase 1: Package and dependency integration

- add Sparkle to [`Vendors/Package.swift`](/Users/rk/Developer/Navigator/Vendors/Package.swift)
- add the app-owned `UpdaterClient`
- add the hidden `SparkleUpdaterService`
- add dependency registration in `Navigator`

Exit criteria:

- the app builds with Sparkle linked
- no broad app code imports Sparkle directly

### Phase 2: Launch and menu integration

- bootstrap `updaterClient.start()` in [`Navigator/AppDelegate.swift`](/Users/rk/Developer/Navigator/Navigator/AppDelegate.swift)
- add `Check for Updates…` menu routing through the delegate
- verify cold-start manual checks

Exit criteria:

- the menu item works on first launch before settings are opened

### Phase 3: Settings integration

- add updater controls to the settings colophon section
- plumb `UpdaterState` through [`Navigator/NavigatorSettingsViewModel.swift`](/Users/rk/Developer/Navigator/Navigator/NavigatorSettingsViewModel.swift)
- localize all new user-facing strings

Exit criteria:

- toggles reflect and persist Sparkle-owned preferences

### Phase 4: Release pipeline activation

- generate keys
- add `SUFeedURL` and `SUPublicEDKey`
- automate appcast generation
- publish a signed test feed

Exit criteria:

- a real older signed Navigator build updates to a newer signed build through the hosted feed

### Phase 5: Hardening

- evaluate `SURequireSignedFeed` if not already enabled
- audit logging and diagnostics
- remove any accidental Sparkle leakage from non-updater code

Exit criteria:

- the updater path is explicit, isolated, and operationally repeatable

## Testing Strategy

### Unit tests

Add focused tests for Navigator-owned behavior.

Recommended coverage:

- `UpdaterClient` test dependency usage in settings view model tests
- settings toggles read and write the correct updater preferences
- app delegate menu action calls the dependency, not Sparkle directly
- updater bootstrap runs during launch even on a cold start
- repeated `start()` calls do not duplicate initialization or crash
- the live dependency does not create multiple independent runtime services across repeated accesses

### Integration tests

Keep integration scope realistic.

Recommended coverage:

- verify the built app bundle embeds `Sparkle.framework`
- verify app launch succeeds with Sparkle linked
- verify `Check for Updates…` is present and routed correctly

Do not attempt:

- mocking Sparkle internals deeply
- claiming real update-install verification from unit tests

### Manual signed-build QA

A real update must be tested with signed artifacts.

Required manual verification:

- install an older signed build
- publish a newer signed build to the test appcast
- launch the older build on a cold start
- run `Check for Updates…`
- verify discovery, download, installation, relaunch, and final version state

### First-run and cold-start checks

Explicitly verify:

- first launch after install
- first launch with no Sparkle defaults
- first manual check before opening settings
- first settings open after Sparkle integration

This is required by repo guidance: do not claim success based only on warmed-state behavior.

## Open Decisions

These must be resolved before implementation starts:

1. What is the production `SUFeedURL`?
2. What archive format will Navigator publish?
3. Will signed feeds be enabled in the first rollout?
4. Will the first release include the automatic-download toggle, or only automatic-checks plus manual update checks?
5. Who owns Sparkle private-key custody and rotation?
6. Which release system generates and uploads the appcast?

## Recommended First Implementation Slice

The smallest production-worthy slice is:

1. add Sparkle to `Vendors`
2. add `UpdaterClient` and the hidden main-actor Sparkle runtime service
3. bootstrap the updater from `AppDelegate`
4. route `Check for Updates…` through an AppDelegate action into the dependency
5. add `SUFeedURL`, `SUPublicEDKey`, and `SUVerifyUpdateBeforeExtraction`
6. verify a real signed update from an older build to a newer one

This keeps the first implementation narrow while still converging on a complete shipping path.
