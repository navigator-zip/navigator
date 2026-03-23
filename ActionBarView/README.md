# ActionBarView

This package will host a native macOS alternative to `cmdk`: a command-bar style component driven by SwiftUI first and pushed down into AppKit where SwiftUI alone cannot provide the required behavior or fidelity.

This document is the initial specification pass. It records the behavior, architecture, and tradeoffs observed in the upstream `cmdk` repository at `v1.1.1` / commit `dd2250e`, then translates that behavior into a macOS-oriented implementation plan for `ActionBarView`.

## Goals

- Preserve the composable authoring model that makes `cmdk` useful.
- Preserve the end-user behaviors that define the component: search, ranking, keyboard navigation, grouping, selection, empty states, and dialog-style presentation.
- Adapt the implementation to native macOS expectations instead of copying React internals literally.
- Use SwiftUI for public composition and AppKit for focus, key handling, IME, measurement, scrolling, and window/panel integration when SwiftUI falls short.

## Upstream Repository Snapshot

The upstream `cmdk` repository is small and centered around a single implementation file:

- `cmdk/src/index.tsx`
  - public API
  - internal store
  - item/group registration
  - filtering, sorting, keyboard handling, and accessibility wiring
- `cmdk/src/command-score.ts`
  - default fuzzy scoring implementation
- `README.md`
  - public behavior and usage model
- `ARCHITECTURE.md`
  - rationale for the compound-component architecture and its tradeoffs
- `test/*.test.ts` plus `test/pages/*.tsx`
  - concrete behavior coverage
- `website/components/cmdk/*.tsx`
  - product-quality demos showing intended usage patterns

## Product Model Observed In `cmdk`

`cmdk` is a command menu and accessible combobox primitive.

It is not a data-driven widget in the classic sense. The user does not pass an array of items into a renderer. Instead, the user composes React components directly:

- `<Command>`
- `<Command.Input>`
- `<Command.List>`
- `<Command.Item>`
- `<Command.Group>`
- `<Command.Separator>`
- `<Command.Empty>`
- `<Command.Loading>`
- `<Command.Dialog>`

That composable structure is the core product choice. The upstream architecture explicitly rejects:

- array-driven item definitions as the primary API
- render props
- tree walking through `React.Children`

The reason is composition. Items can be wrapped in arbitrary components, rendered conditionally, grouped in custom structures, or mixed with static content.

## Behavioral Inventory

### Root Command Surface

Observed root behavior:

- The root can render inline or inside a dialog host.
- The root owns selected-item state.
- The root also coordinates search filtering, ranking, and visible ordering.
- The root can be uncontrolled or controlled for selected value.
- `defaultValue` seeds initial selection.
- Selected values are trimmed before storage and comparison.
- The root exposes a custom filter hook.
- The root can disable automatic filtering and sorting with `shouldFilter = false`.
- The root can enable wrapped keyboard navigation with `loop = true`.
- The root can disable pointer-hover selection.
- The root enables vim-style control bindings by default and can disable them.

### Search Input

Observed input behavior:

- The input can be uncontrolled or controlled independently from selected value.
- Search text is distinct from selected item value.
- Input changes trigger immediate re-filtering and re-ranking.
- Search values are effectively treated as trimmed during matching because item values and keywords are trimmed before scoring.
- The input is wired as a combobox with `aria-activedescendant`.
- Input autocomplete, autocorrect, and spellcheck are disabled.

### Item Semantics

Observed item behavior:

- Each item has a stable internal identifier plus a user-facing value.
- Explicit `value` wins over derived text content.
- If no `value` is provided, the item value is inferred from rendered text content.
- Item values are trimmed.
- `keywords` act as aliases and are also trimmed.
- Disabled items remain visible but are excluded from valid keyboard selection.
- Disabled items do not respond to click selection.
- Pointer movement selects an enabled item unless pointer selection is disabled at the root.
- Clicking an item selects it and calls `onSelect`.
- Pressing Enter on the selected item dispatches the same selection pathway through a custom event.
- `forceMount` keeps an item rendered even when it would normally be filtered out.
- If item text changes across renders and the user relies on inferred values, the item must still produce a stable identity or selection/filtering becomes ambiguous.

### Group Semantics

Observed group behavior:

- Groups collect items under a heading.
- A group can also have an explicit unique value.
- Groups remain mounted when filtered out; they are hidden rather than removed.
- A group becomes visible when any child item matches search.
- `forceMount` keeps a group visible even when it would otherwise be hidden.
- Group ranking is based on the best visible score among its items.
- Group navigation is a first-class keyboard concept through alt-modified movement.

### Separator, Empty, and Loading

Observed behavior:

- Separators render when search is empty.
- Separators can be forced visible with `alwaysRender`.
- `Empty` renders automatically when there are zero visible results.
- `Loading` does not manage async work; it is purely a consumer-controlled progress surface.
- Async item loading is supported by mounting items as data arrives.

### Filtering and Ranking

Observed default matching behavior:

- The default filter is fuzzy rather than prefix-only.
- Matching rewards continuous runs of characters.
- Matching rewards word starts.
- Matching rewards matches closer to the start of the string.
- Matching slightly rewards exact case over case-insensitive matches.
- Matching slightly penalizes skipped characters.
- Matching slightly penalizes incomplete matches where the candidate has trailing characters beyond the query.
- Matching includes aliases by appending `keywords` to the searchable text.
- Custom filters return a numeric score.
- A score of `0` hides an item.
- Higher scores sort above lower scores.

Observed filtering flow:

- If search is empty, all currently rendered items are effectively eligible.
- If `shouldFilter` is `false`, cmdk stops applying filtering and sorting logic and expects the consumer to manage visible items.
- On every search change, the root recomputes scores, recomputes visible groups, sorts visible items, then selects the first valid result when needed.

Observed ordering behavior:

- Visible items are sorted by descending score.
- Ungrouped items remain above grouped sections.
- Groups are sorted by each group's highest visible child score.
- DOM order is the source of truth for final keyboard navigation order.

### Selection Rules

Observed selection behavior:

- The first valid item becomes selected by default when items mount and there is no current selection.
- When search changes, selection moves to the first valid result.
- When the selected item unmounts, selection falls back to the first valid remaining item.
- Disabled items are skipped for valid selection.
- Controlled selection can point at values that temporarily disappear due to search changes; when no matching visible item exists, the controlled value can effectively become empty until matching items return.

### Keyboard Interaction

Observed keyboard behavior:

- Arrow Down moves to the next valid item.
- Arrow Up moves to the previous valid item.
- Home moves to the first valid item.
- End moves to the last valid item.
- Meta + Arrow Down jumps to the last valid item.
- Meta + Arrow Up jumps to the first valid item.
- Alt + Arrow Down jumps to the first valid item in the next visible group.
- Alt + Arrow Up jumps to the first valid item in the previous visible group.
- `loop = true` wraps item movement from end to start and start to end.
- `Ctrl+J` and `Ctrl+N` map to next item when vim bindings are enabled.
- `Ctrl+K` and `Ctrl+P` map to previous item when vim bindings are enabled.
- Meta and Alt modifiers compose with those vim bindings in the same way they do with arrow keys.
- Enter triggers selection on the currently selected item.
- Key handling is suppressed while IME composition is active.

### Focus and Scrolling

Observed focus behavior:

- When selection changes, cmdk keeps focus on the input or list root so accessibility state remains coherent.
- The selected item is scrolled into view after selection changes.
- If the selected item is the first item in a group, the group heading is also scrolled into view.

Observed list measurement behavior:

- The list measures its content height with `ResizeObserver`.
- The measured height is written to a CSS custom property so consumers can animate list height.

### Accessibility

Observed accessibility model:

- The root exposes a screen-reader-only label.
- The input uses combobox semantics.
- The list uses listbox semantics.
- Items use option semantics.
- Group containers expose group semantics and can label themselves from a heading.
- The currently selected item is mirrored through `aria-activedescendant`.
- The dialog host relies on Radix Dialog for accessible modal behavior.

### Dynamic Content and Composition

Observed dynamic behavior:

- Items can mount after a search has already been entered and still match immediately.
- Items that mount and do not match current search stay hidden.
- Groups can mount progressively and still participate in current search.
- Mounting additional non-selected items does not steal selection from the currently selected item.
- Nested page flows are not built into the library; the recommended approach is plain state that conditionally renders different item sets.
- Nested submenus can be built by hosting another command surface inside a popover.
- Rich row content is expected: icons, metadata, shortcuts, badges, and other layout elements.

## Implementation Architecture Observed In `cmdk`

### Internal Store

The upstream root owns a small external store containing:

- `search`
- selected `value`
- `selectedItemId`
- filtered item scores
- visible group identifiers
- visible result count

Children subscribe through `useSyncExternalStore`.

### Registration Model

Items and groups self-register with the root on mount.

The root tracks:

- all item IDs
- all group IDs
- a group-to-item membership map
- an item-ID-to-value-and-keywords map

This registration is the key mechanism that makes composition work without walking arbitrary JSX children.

### Scheduled Layout Work

The implementation batches operations through a small scheduled layout-effect queue.

That queue is used to avoid repeated work while multiple items mount or unmount in a single render pass. It stages:

- filtering
- sorting
- first-item selection
- selected item lookup
- scroll-to-visible updates

### DOM As Source Of Truth

The upstream implementation treats the DOM as authoritative for navigation order.

That is a direct consequence of the React composition constraint:

- all items stay alive in the React tree
- filtered items often return `null`
- visible ordering is applied imperatively in the DOM
- selection then follows that DOM order

### Explicit Tradeoffs

The upstream docs and architecture notes are clear about the tradeoffs:

- memory usage is higher because all items remain in the React tree
- manual DOM ordering is a little risky
- virtualization is not built in
- concurrent rendering safety is not guaranteed beyond current React expectations
- the approach is considered good enough up to roughly 2,000 to 3,000 items

## Behavioral Coverage Observed In Tests

The upstream test suite verifies:

- prop forwarding
- value derivation from text content
- explicit `value` precedence
- click selection
- default first-item selection
- selection reset on search changes
- keyword-based filtering
- empty-state rendering
- class name forwarding
- mount/unmount correctness
- force-mounted item behavior
- re-matching after item re-render
- group hiding and progressive group mounting
- force-mounted group behavior
- disabling automatic filtering
- custom filter behavior
- controlled selected value
- controlled search
- retaining initial controlled selection
- dialog portal rendering
- numeric-search correctness
- arrow-key navigation
- vim-key navigation
- disabling vim navigation

## What We Should Preserve In `ActionBarView`

The macOS version should preserve:

- composable authoring
- distinct search and selected-value state
- item/group/empty/loading primitives
- fuzzy ranking with override support
- keywords/aliases
- force-mounted rows and groups
- deterministic keyboard navigation
- skip-disabled-item behavior
- search-driven selection fallback
- dynamic mount/unmount correctness
- rich row content support
- panel/popover hosting as a first-class presentation mode

## What We Should Adapt For macOS

We should not copy the React internals literally.

The macOS version should adapt these behaviors:

- Prefer explicit stable item identity rather than inferred text content as the primary identity model.
- Preserve a SwiftUI compound-component API, but back it with a native state coordinator rather than DOM mutation.
- Sort data in state instead of imperatively reordering native views after the fact.
- Use native focus and first-responder management instead of synthetic focus repairs where possible.
- Use native accessibility roles and announcements appropriate for macOS.
- Support keyboard behavior through the responder chain rather than only through a text field's key handlers.

## Proposed `ActionBarView` Public Surface

Initial native-equivalent surface:

- `ActionBarView`
- `ActionBarField`
- `ActionBarList`
- `ActionBarItem`
- `ActionBarGroup`
- `ActionBarSeparator`
- `ActionBarEmpty`
- `ActionBarLoading`
- `ActionBarPanel` or `ActionBarPopover`
- `useActionBarState` equivalent via Swift observation rather than a direct hook clone

State model we should expose:

- query text
- selected item identifier
- selected item value
- visible item identifiers
- visible group identifiers
- loading state

Key configuration points we should support:

- custom scoring/filter function
- manual filtering mode
- wrap navigation
- pointer-hover selection toggle
- vim-style navigation toggle
- optional aliases/keywords
- disabled items
- force-mounted items and groups

## SwiftUI-First Architecture Proposal

### Core State

Use a `@MainActor` observable coordinator that owns:

- current query
- current selection
- all registered items
- group membership
- filtered visible order
- scroll target
- transient keyboard/navigation state

This replaces the React external store and gives us one native place to coordinate updates.

### Registration

Preserve the composable registration model:

- items register themselves with the coordinator
- groups register themselves with the coordinator
- item metadata includes stable ID, value, keywords, disabled state, group membership, and force-mount state

This keeps the compound-component API intact while avoiding tree introspection.

### Rendering

Render visible items from the coordinator's sorted visible model instead of treating the rendered view hierarchy as the source of truth.

That means:

- SwiftUI remains the public composition surface
- the coordinator becomes the ordering authority
- view updates stay deterministic without manual native-subview reordering

### Selection and Navigation

Keep selection keyed by stable item identity rather than visible index.

The coordinator should provide:

- select first valid item
- move by item
- move by group
- jump to first or last
- perform selected action

### Matching

Port the upstream fuzzy scorer into Swift.

The scorer should preserve:

- continuous match preference
- word-boundary preference
- case-aware bias
- skip penalties
- distance-from-start bias
- incomplete-match penalty
- alias expansion through keywords

We should also keep a pluggable scoring override for product-specific ranking.

## AppKit Fallback Plan

SwiftUI alone may not be sufficient for every behavior. Likely AppKit fallbacks:

- text input and IME composition awareness
  - use `NSSearchField` or an AppKit-backed text input bridge if SwiftUI text field behavior is not reliable enough
- first-responder key routing
  - use `NSViewRepresentable` or an AppKit responder bridge for arrow keys, vim keys, home/end, and modified key handling
- precise scroll-to-visible behavior
  - use `NSScrollView` or direct `NSView.scrollToVisible(_:)` when SwiftUI `ScrollViewReader` is not deterministic enough
- panel-style host
  - use `NSPanel` for a Spotlight-like floating command bar host
- popover-style host
  - use `NSPopover` or a custom anchored window where needed
- accessibility fallback
  - drop to AppKit accessibility APIs if SwiftUI's default semantics do not produce a faithful combobox/listbox experience on macOS
- measurement
  - use AppKit measurement or layout observation if SwiftUI preference keys are not stable enough for animated list sizing

## Initial Non-Goals

The first native version does not need to solve everything at once.

Non-goals for the first implementation pass:

- built-in virtualization
- cross-platform support beyond macOS
- a perfect one-to-one clone of Radix Dialog semantics
- automatic global hotkey registration
- arbitrary text-content-derived identity as the primary recommended API

## Risks To Keep In Mind

- A pure SwiftUI implementation may be insufficient for keyboard routing and first responder fidelity.
- IME composition behavior must be validated explicitly.
- Scroll synchronization can drift if selection updates race layout.
- Rich composability can make stable registration more difficult if item identity is underspecified.
- Native panel presentation may introduce focus behavior that differs from inline hosting.
- Accessibility quality should be treated as a first-class requirement rather than a follow-up.

## Suggested Delivery Phases

### Phase 1

- package scaffold
- this document
- native scoring port
- observable coordinator

### Phase 2

- inline SwiftUI surface
- field/list/item/group primitives
- search, ranking, selection, and keyboard navigation

### Phase 3

- AppKit key-routing and focus fallbacks
- scroll-to-visible hardening
- empty/loading/group force-mount behavior

### Phase 4

- floating panel host
- popover host
- richer accessibility validation
- package tests covering dynamic mount, filtering, controlled state, and keyboard behavior

## Immediate Next Implementation Targets

After this document, the next concrete work should be:

1. Define the observable coordinator and stable item/group registration model.
2. Port the default fuzzy scorer from `command-score.ts` into Swift.
3. Build an inline SwiftUI list with deterministic selection and filtering.
4. Add AppKit-backed key handling if SwiftUI key routing is not sufficient.
5. Add a floating `NSPanel` presentation surface once inline behavior is stable.
