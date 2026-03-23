# Docs Index

Navigator documentation is organized by topic instead of a single flat folder.

## Browser

- [CEF Bridge Hardening & Architecture Refactor Engineering Guide](/Users/rk/Developer/Navigator/docs/browser/cef-bridge-hardening-architecture-refactor-engineering-guide.md)
  - implementation guide for hardening callback lifetime, CEF ABI assumptions, ownership rules, and native bridge modularity
- [Browser Tab Activation Lifecycle Guide](/Users/rk/Developer/Navigator/docs/browser/tab-activation-lifecycle-guide.md)
  - intent-aware tab activation and browser lifecycle policy for rapid tab traversal and background loading
- [MiumCEFBridgeNative Rewrite Engineering Specification](/Users/rk/Developer/Navigator/docs/browser/mium-cef-bridge-native-rewrite-engineering-specification.md)
  - implementation-oriented rewrite spec for safer CEF runtime, browser, host-view, callback, and shutdown lifecycles
- [CEF Scrolling and Message Pump Notes](/Users/rk/Developer/Navigator/docs/browser/cef-scrolling-and-message-pump-notes.md)
  - investigation and current architecture for Chrome-vs-Navigator scrolling behavior, external pumping, and the fallback watchdog

## AppKit

- [Trackpad Gestures Implementation Guide](/Users/rk/Developer/Navigator/docs/appkit/trackpad-gestures-implementation-guide.md)
  - private-API-backed macOS trackpad gesture architecture and rollout plan
- [Trackpad Gestures Stability Refactor Guide](/Users/rk/Developer/Navigator/docs/appkit/trackpad-gestures-stability-refactor-guide.md)
  - complete refactor plan for safer backend isolation, typed lifecycle APIs, and more predictable runtime behavior
- [ReorderableList AppKit Engineering Guide](/Users/rk/Developer/Navigator/docs/appkit/reorderable-list-appkit-engineering-guide.md)
  - fresh-component AppKit design guide for rebuilding `ReorderableList` without rewriting existing implementations
- [ReorderableList Autoscroll Mouse-Up Fix Guide](/Users/rk/Developer/Navigator/docs/appkit/reorderable-list-autoscroll-mouse-up-fix-guide.md)
  - surgical fix plan for stuck drops when `mouseUp` is lost during autoscroll-driven reordering
- [High-Performance Reorderable AppKit Table Implementation Plan](/Users/rk/Developer/Navigator/docs/appkit/high-performance-reorderable-table-implementation-plan.md)
  - repo-grounded handoff plan for a fixed-height, overlay-driven `NSTableView` reorder component
- [ReorderableList Drag Performance Review](/Users/rk/Developer/Navigator/docs/appkit/reorderable-list-drag-performance-review.md)
  - targeted review of the current tab-drag implementation, including hot paths and prioritized performance fixes
- [Sidebar SwiftUI Interaction Investigation](/Users/rk/Developer/Navigator/docs/appkit/sidebar-swiftui-interaction-investigation.md)
  - investigation notes for sidebar interaction behavior in the SwiftUI/AppKit boundary

## Security

- [Navigator Client E2EE Sync Spec v1](/Users/rk/Developer/Navigator/docs/security/navigator-client-e2ee-sync-spec-v1.md)
  - client-side end-to-end encrypted browser-sync behavior and invariants
- [Navigator Client Key Management Plan](/Users/rk/Developer/Navigator/docs/security/navigator-client-key-management-plan.md)
  - implementation-oriented key lifecycle, recovery, and trusted-device plan
