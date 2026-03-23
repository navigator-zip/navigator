# Engineering Guide: Browser Spaces for Tab Persistence

## Objective

Add a first-class “space” model so tabs are persisted and restored per space rather than through one global flat collection.  
There is no live user migration concern, so this guide assumes a clean initial state and focuses on a single-pass schema update.

## Current Architecture

### What already exists

The current browser state is effectively single-space:

- Persisted tabs are stored as `StoredBrowserTabCollection` with:
  - `storageVersion`
  - `collectionID`
  - `hasStoredState`
  - `[StoredBrowserTab]`
- Persisted selection is one global `StoredBrowserTabSelection` with:
  - `collectionID`
  - `selectedTabID`
- App hydration/persistence is centralized in:
  - [Navigator/AppViewModel.swift](/Users/rk/Developer/Navigator/Navigator/AppViewModel.swift)
- Sidebar runtime state is one active list:
  - [BrowserSidebar/Sources/BrowserSidebar/BrowserSidebarTabCollection.swift](/Users/rk/Developer/Navigator/BrowserSidebar/Sources/BrowserSidebar/BrowserSidebarTabCollection.swift)
  - [BrowserSidebar/Sources/BrowserSidebar/BrowserSidebarViewModel.swift](/Users/rk/Developer/Navigator/BrowserSidebar/Sources/BrowserSidebar/BrowserSidebarViewModel.swift)
- Import flow currently flattens windows/groups into one batch:
  - [Navigator/AppViewModel.swift](/Users/rk/Developer/Navigator/Navigator/AppViewModel.swift)

### Consequence

- One persisted collection is shared across all tabs.
- Exactly one selected tab is stored globally.
- There is no concept of user-visible “space”.

## Desired State

- Add explicit spaces.
- Each space has:
  - stable `spaceID`
  - optional name
  - ordered tabs
  - selected tab ID
- Switching active space only changes the active in-memory list; other spaces persist.
- Import maps imported browser clusters into spaces.
- Pinning, ordering, and restore behavior remain per active space.

## Constraints and Repo Rules

- Model types that are shared should stay in `ModelKit`.
- Runtime layers should remain deterministic and strict about defaults/fallbacks.
- Keep property observers side-effect free; use explicit sync methods.
- Add cold-start/empty-cache coverage before finalizing.
- Concurrency updates must respect strict-sendable and actor rules.

## Storage Design

### 1) Extend stored tab model with explicit space identity

File: [ModelKit/Sources/ModelKit/StoredBrowserTabModels.swift](/Users/rk/Developer/Navigator/ModelKit/Sources/ModelKit/StoredBrowserTabModels.swift)

- Add explicit `spaceID: String` to `StoredBrowserTab`.
- Keep `parentObjectID` temporarily if needed for backward/backstop compatibility, but avoid using it as space.
- Decoding fallback: if `spaceID` is missing, map to default space constant.

### 2) Add persisted space entity

- Add `StoredBrowserSpace` with:
  - `id: String`
  - `name: String`
  - `orderKey: String`
  - `selectedTabID: UUID?`
  - optional timestamps if useful (`createdAt`, `updatedAt`)

### 3) Expand collection container

Current `StoredBrowserTabCollection` is global and flat.  
Recommended future-compatible structure:

- `activeSpaceID: String`
- `spaces: [StoredBrowserSpace]`
- `tabs: [StoredBrowserTab]` (flat list with per-tab `spaceID`)

Why keep flat `tabs` now:

- Keeps write path localized.
- Preserves existing tab ordering/helpers.
- Minimizes initial blast radius.

### 4) Expand selection representation

- Keep `StoredBrowserTabSelection`, but add space-scoped selection:
  - `selectedSpaceID`
  - `selectedTabID`
- This avoids introducing another persistence key and keeps write logic simple.

### 5) Versioning

- Bump schema versions for:
  - `StoredBrowserTabCollection`
  - `StoredBrowserTabSelection`
- Since no migration is required, defensive defaults can remain permissive but explicit.

## Runtime Architecture Changes

### AppViewModel responsibilities

Currently: hydrate once, persist all tabs globally, persist selected tab globally.  
Afterward:

- Track active space and per-space tab slices.
- Hydrate:
  - read full payload
  - ensure a default space exists
  - resolve active space
  - restore only active-space tabs into sidebar
- Persist:
  - update only active-space tabs
  - preserve other-space tab state
  - write active-space selection

### Recommended in-memory state

In [Navigator/AppViewModel.swift](/Users/rk/Developer/Navigator/Navigator/AppViewModel.swift):

- `spaceMap: [String: StoredBrowserSpace]`
- `activeSpaceID: String`
- `tabsBySpaceID: [String: [StoredBrowserTab]]` (or computed slices from flat list)

### Sidebar behavior

- Keep `BrowserSidebarTabCollection` mostly unchanged.
- Space switch replaces active tab set by calling restore API on sidebar VM.
- Ensure restore validates selected tab against active list and applies fallback.

### Selection fallback policy

For any `activeSpaceID`, resolve selection:

1. use stored `selectedTabID` if it exists in that space
2. else first pinned tab
3. else first unpinned tab
4. else nil

Persist with repaired selection to prevent stale cross-space references.

## Import Pipeline Changes

Current import behavior flattens everything into one list.  
New flow should bucket import seeds by target space.

In [Navigator/AppViewModel.swift](/Users/rk/Developer/Navigator/Navigator/AppViewModel.swift):

- Build `spaceID -> [ImportedTabSeed]`
- Map each imported window or tab group deterministically to a space ID
- Merge or replace per target space based on existing import semantics
- Persist per-space metadata + per-space selected tab

## Empty-Cache Semantics (No migration)

On first boot (no stored payload):

1. create one default space (`default-space`)
2. create default tab from existing startup URL/logic
3. set active space and selected tab
4. persist once to avoid transient fallback states

Never let sidebar render without known active-space state.

## Windowing Semantics (v1)

Keep existing multi-window behavior:

- One global active space shared across windows.
- Same persisted spaces/collection read/written from each window session.

If per-window space semantics are later required, separate a secondary runtime context keyed by window token.

## Files to Change

### ModelKit

- [ModelKit/Sources/ModelKit/StoredBrowserTabModels.swift](/Users/rk/Developer/Navigator/ModelKit/Sources/ModelKit/StoredBrowserTabModels.swift)
  - add `StoredBrowserSpace`
  - add `spaceID` to `StoredBrowserTab`
  - add `activeSpaceID` + `spaces` in `StoredBrowserTabCollection`
  - add space selection field(s)

### Storage constants

- [Navigator/NavigatorStoredBrowserTabsShared.swift](/Users/rk/Developer/Navigator/Navigator/NavigatorStoredBrowserTabsShared.swift)
  - keep existing storage keys unless key policy changes

### App runtime

- [Navigator/AppViewModel.swift](/Users/rk/Developer/Navigator/Navigator/AppViewModel.swift)
  - hydrate/persist by active space
  - add space operations: create/switch/rename/delete
  - import to-space mapping and persistence integration

### Sidebar model/viewmodel

- [BrowserSidebar/Sources/BrowserSidebar/BrowserSidebarTabCollection.swift](/Users/rk/Developer/Navigator/BrowserSidebar/Sources/BrowserSidebar/BrowserSidebarTabCollection.swift)
  - minimal or no structural changes
- [BrowserSidebar/Sources/BrowserSidebar/BrowserSidebarViewModel.swift](/Users/rk/Developer/Navigator/BrowserSidebar/Sources/BrowserSidebar/BrowserSidebarViewModel.swift)
  - add/clarify restore API to validate selected tab against space slice

### Tests

- [ModelKit/Tests/ModelKitTests/StoredBrowserTabModelsTests.swift](/Users/rk/Developer/Navigator/ModelKit/Tests/ModelKitTests/StoredBrowserTabModelsTests.swift)
  - add Codable/version tests for space fields
- [BrowserSidebar/Tests/BrowserSidebarTests/BrowserSidebarViewModelTests.swift](/Users/rk/Developer/Navigator/BrowserSidebar/Tests/BrowserSidebarTests/BrowserSidebarViewModelTests.swift)
  - restore + fallback + per-space ordering cases
- [NavigatorTests/NavigatorKeyboardShortcutTests.swift](/Users/rk/Developer/Navigator/NavigatorTests/NavigatorKeyboardShortcutTests.swift)
  - add/extend persistence + active-space restore assertions

## Rollout Steps

### Phase 1 — Storage schema

1. Extend stored models and Codable defaults/decoding.
2. Add unit tests for `spaceID`, `spaces`, and version compatibility.
3. Add default-space repair paths for malformed payloads.

### Phase 2 — App hydration/persistence

1. Replace single-space restore with active-space restore.
2. Add active-space helpers and storage merge logic for inactive spaces.
3. Ensure `persistCurrentTabs` cannot write partial/unresolved tab state.

### Phase 3 — Import + operations

1. Add import bucketing by space.
2. Add internal API for space lifecycle (`create`, `switch`, `rename`, `delete`).
3. Validate no side effects leak across spaces.

### Phase 4 — Validation

1. Add model, sidebar, and app tests listed above.
2. Add cold-start tests for empty cache.
3. Exercise open/reorder/close/pin scenarios with active-space boundaries.

## End-to-End Data Flow

### Save

1. Sidebar changes tabs/selection in active space.
2. `AppViewModel` builds next payload for active space.
3. Merge with existing other spaces.
4. Persist:
   - collection with all spaces + all tabs + `spaceID`
   - active space selection

### Restore

1. Read persisted collection and selection.
2. Rebuild space map.
3. Resolve active space and tab list.
4. Apply selection fallback and restore into sidebar.

### Import

1. Convert snapshot into per-space seed buckets.
2. Apply bucketed merge.
3. Persist merged per-space metadata and tabs.

## Test Matrix

- Model
  - encode/decode with spaces, missing fields, stale selection
- App
  - fresh install default space behavior
  - active-space mismatch fallback
  - open/reopen order stability
  - close/unpin/reopen within a space
- Sidebar
  - restore validates selected tab
  - move/reorder affects only active space
- Import
  - deterministic window/group -> space mapping
  - selected import tab resolves inside expected space
- Multi-window
  - v1 behavior keeps shared active space

## Risks

- Over-coupling schema changes too early.
  - Mitigation: keep per-space as additive fields and keep flat list strategy.
- Selection drift across deleted/invalid spaces.
  - Mitigation: strict fallback + immediate persistence repair.
- Wrong import bucketing.
  - Mitigation: deterministic mapping + fixtures.
- Performance from repeated writes.
  - Mitigation: keep current flush-debounce strategy.

## Minimal First Milestone

1. Add schema fields + AppViewModel hydration/persistence.
2. Add hidden/internal space switch API.
3. Add per-space import path behind a guarded feature flag.
4. Add tests.
5. Add UI surface only after runtime path is stable.

## Acceptance Criteria

- First launch creates a default space and one default tab.
- Stored space payload opens to persisted active space.
- Switching spaces updates sidebar tabs and selection only for that space.
- Persisted payload includes per-space tabs + per-space selection.
- Single-space behavior remains equivalent to current behavior.
- No panic or broken startup paths in empty-cache flows.

## Rollback Plan

If regressions occur:

1. Revert AppViewModel to global collection behavior.
2. Keep space fields present but ignored.
3. Validate single-space path first, then reintroduce in smaller increments.

## Delivery Checklist

- [ ] `StoredBrowserTab` has `spaceID`.
- [ ] `StoredBrowserSpace` added.
- [ ] `StoredBrowserTabCollection` includes active space and spaces.
- [ ] `StoredBrowserTabSelection` includes space selection.
- [ ] AppViewModel restores/persists active-space state.
- [ ] Import maps incoming data to spaces.
- [ ] Cold-start + fallback tests added.
- [ ] Release note entry is added if user-facing.
