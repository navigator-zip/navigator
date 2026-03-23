# Sidebar SwiftUI Interaction Investigation

Date: March 9, 2026

## Goal

Determine why the browser sidebar's SwiftUI content was not receiving usable mouse interaction when shown above the embedded CEF browser content.

## Initial Symptom

- A SwiftUI tab list hosted inside the browser sidebar did not respond to clicks or hover as expected.
- If the CEF browser view was removed from the view hierarchy, the SwiftUI content started working.

## Findings

### 1. The original in-window overlay was competing with the browser subtree

We confirmed the sidebar was being overlaid inside the same parent window as the browser instead of being isolated from the browser's native view hierarchy.

Relevant files:

- `Navigator/BrowserRootView.swift`
- `BrowserView/Sources/BrowserView/BrowserViewController.swift`
- `BrowserRuntime/Sources/BrowserRuntime/BrowserRuntime.swift`
- `MiumKit/Sources/MiumKit/CEFBridge.mm`
- `MiumKit/Sources/MiumKit/MiumCEFBridgeNative.mm`

Conclusion:

- The embedded browser subtree was a credible source of hit-testing interference.

### 2. The browser-side sidebar exclusion width was stale

The browser hit-test exclusion strip was originally based on a cached sidebar width. When the sidebar width changed, the browser could continue accepting hits in areas now covered by the sidebar.

Fix applied during investigation:

- Made the browser-side exclusion width track the live sidebar width.

Relevant files:

- `BrowserView/Sources/BrowserView/BrowserViewController.swift`
- `Navigator/BrowserRootView.swift`
- `BrowserView/Tests/BrowserViewTests/BrowserViewControllerTests.swift`

Conclusion:

- This was a real bug and needed fixing.
- It was not sufficient by itself to restore SwiftUI interaction.

### 3. Moving the sidebar into a child window was the right direction

We moved the sidebar into its own child window above the browser while keeping the browser's layout unchanged.

Relevant files:

- `Navigator/BrowserRootView.swift`
- `Navigator/BrowserSidebarPanel.swift`

Conclusion:

- This removed the sidebar from the browser's direct view hierarchy.
- It was a necessary isolation step.

### 4. The child window initially had background hit-testing and transparency issues

The full-width child window needed explicit handling for transparent regions and outside-click dismissal.

Fixes applied during investigation:

- Used a custom root container view for the child window.
- Made that container explicitly return itself from `hitTest(_:)` for empty regions when dismissal behavior was enabled.
- Routed empty-region clicks to the sidebar dismissal path.

Relevant file:

- `Navigator/BrowserRootView.swift`

Conclusion:

- The overlay window now reliably owns clicks in the regions it is supposed to own.

### 5. Raw AppKit mouse delivery to the hosted sidebar area works

We instrumented the sidebar hosting path and confirmed that raw `mouseDown` and `mouseUp` events were reaching the hosted area repeatedly.

Conclusion:

- This is not a case of the child window or panel completely dropping input.

### 6. SwiftUI controls inside the hosted sidebar area still did not activate

We tried several increasingly small SwiftUI probes:

- SwiftUI `Button`
- SwiftUI `Text` with `.onTapGesture`
- a reduced hosted probe below a native AppKit control

Observed behavior:

- SwiftUI began interaction in some earlier probe states but never completed activation.
- After simplifying further, AppKit mouse delivery still occurred but the SwiftUI probe still produced no tap output.

Conclusion:

- The failure narrowed from "sidebar cannot receive input" to "hosted SwiftUI interaction path is failing."

### 7. A native AppKit control in the same slot works reliably

We added a temporary AppKit `NSButton` probe in the same sidebar content path.

Observed behavior:

- The top AppKit button printed every time.
- The bottom SwiftUI probe did not print.

Conclusion:

- The sidebar child-window and panel path is usable.
- The failure is specific to the SwiftUI-hosted interaction path, not the entire sidebar slot.

### 8. Inject was not the blocker

We removed Inject-related wrappers from the active hosted SwiftUI probe path.

Relevant files touched during investigation:

- `BrowserSidebar/Sources/BrowserSidebar/BrowserSidebarSwiftUITabListView.swift`
- `BrowserSidebar/Sources/BrowserSidebar/BrowserSidebarSwiftUIView.swift`

Observed behavior:

- Native AppKit probe still worked.
- Hosted SwiftUI probe still failed.

Conclusion:

- Inject/hot-reload wrapping was not the root cause.

### 9. The custom `NSHostingView` subclass was not the blocker

We removed the custom hosting subclass and replaced it with a plain `NSHostingView`.

Relevant file:

- `BrowserSidebar/Sources/BrowserSidebar/BrowserSidebarView.swift`

Observed behavior:

- Behavior was unchanged.

Conclusion:

- The custom hosting wrapper was not the root cause.

### 10. App bootstrap style is very unlikely to be the cause

We reviewed the app entry point and runtime bootstrap.

Relevant files:

- `Navigator/App.swift`
- `Navigator/NavigatorAppRuntime.swift`
- `Navigator/AppDelegate.swift`

Observed structure:

- The app uses an `@main` entry point.
- Startup is AppKit-driven via `NSApplication` and `NSApplicationDelegate`.

Conclusion:

- `NSHostingView` is expected to work in this setup.
- Switching to a `SwiftUI.App` lifecycle would be a large architectural change with weak evidence behind it.
- Nothing in the investigation suggested that the app-wide lifecycle is the reason one specific hosted sidebar subtree fails.

### 11. Current state of the investigation

The latest experiment replaces the child-window panel content with the full restored SwiftUI sidebar root instead of embedding SwiftUI inside the AppKit `BrowserSidebarView`.

Relevant files:

- `Navigator/BrowserSidebarPanel.swift`
- `BrowserSidebar/Sources/BrowserSidebar/BrowserSidebarSwiftUIView.swift`

Purpose of this experiment:

- Distinguish between:
  - "SwiftUI inside the AppKit sidebar shell is broken"
  - "SwiftUI in the child-window sidebar environment is broken more generally"

At the moment of writing this note:

- The code has been changed to host the full SwiftUI sidebar root in the child window.
- Validation and builds passed for that state.
- Live user confirmation of that final experiment was still pending.

## What Was Ruled Out

- Browser layout needing to shrink to make room for the sidebar.
- A stale browser hit-test exclusion width as the only issue.
- The sidebar child window fully dropping mouse events.
- Inject on the active hosted probe path.
- The custom `NSHostingView` subclass.
- The general AppKit app bootstrap model as the most likely explanation.

## Most Likely Remaining Problem Area

The remaining suspect is the SwiftUI interaction stack in this sidebar environment, not raw AppKit event delivery.

More specifically, the evidence points to one of these:

- SwiftUI gesture/control recognition inside this child-window-hosted sidebar setup
- some interaction between the SwiftUI root and the specific panel/view layering used for the sidebar

## Recommended Next Steps

1. Test the latest full-SwiftUI-root child-window build and record whether the SwiftUI debug button prints.
2. If the full SwiftUI root still fails, reduce the child-window root further to a minimal standalone SwiftUI view with a single button and no sidebar chrome.
3. If that minimal SwiftUI child-window root still fails, inspect window/panel behavior specific to the child window rather than the sidebar content.
4. If the minimal SwiftUI child-window root works, reintroduce the sidebar layers incrementally until the exact break point is identified.
