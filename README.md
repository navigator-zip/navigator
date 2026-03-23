# Navigator

A native macOS web browser built with Swift, AppKit, and Chromium Embedded Framework (CEF). Navigator combines the rendering power of Chromium with a fully native macOS experience — including a real-time camera pipeline with film-style color grading that can route processed video directly to websites.

## Features

### Browser

- **Chromium-powered rendering** — Full web compatibility via CEF, with multi-process architecture (renderer, GPU, plugin helpers)
- **Tab spaces** — Organize tabs into separate workspaces with independent tab lists and a dot-pager for switching between them
- **Pinned tabs** — Pin up to 20 tabs in a persistent grid at the top of the sidebar
- **Closed tab recovery** — Reopen recently closed tabs (up to 20 in the stack)
- **Session persistence** — Tabs, selections, and spaces survive app relaunches
- **Browser import** — Import tabs, bookmarks, and history from Chrome, Arc, and Safari
- **Picture-in-Picture** — Native PiP support for video content
- **Trackpad gestures** — Three-finger horizontal swipes for navigation via private multitouch APIs
- **Default browser** — Register as the system default browser for HTTP/HTTPS URLs

### Camera

- **Live preview** — Real-time camera feed displayed in the sidebar and menu bar
- **Film color grading** — LUT-based filters: Tonachrome, Folia, Supergold (chromatic); Monochrome; Dither; Warhol variants (Bubblegum, Darkroom, Glow in the Dark, Habanero)
- **Film grain** — Adjustable grain presence (subtle, moderate, strong)
- **Horizontal flip** — Mirror the camera preview and output
- **Camera routing** — Route processed camera frames directly to web pages within the browser

### Interface

- **Native sidebar** — AppKit-based tab sidebar with drag-and-drop reordering, powered by a custom `ReorderableList` component
- **Action bar** — Floating location bar for URL entry and navigation
- **Menu bar indicator** — Camera status and quick controls accessible from the macOS menu bar
- **Spring animations** — Sidebar open/close and drag interactions use spring physics (via Wave)
- **Dark mode** — Full system appearance support with runtime color resolution

## Architecture

Navigator is structured as a collection of ~20 local Swift packages orchestrated by a main Xcode app target. This modular design enforces clear boundaries between browser engine integration, UI components, camera processing, and shared models.

```
Navigator/
├── Navigator/                  # Main app target (AppKit + SwiftUI)
├── BrowserRuntime/             # CEF lifecycle, permission handling, JS evaluation
├── BrowserView/                # Browser tab views, camera routing, permission prompts
├── BrowserSidebar/             # Tab sidebar, spaces, pinned tabs, camera controls
├── BrowserActionBar/           # Location bar and navigation controls
├── BrowserImport/              # Chrome/Arc/Safari data import parsers
├── BrowserCameraKit/           # AVCapture session, frame processing, virtual publisher
├── ModelKit/                   # Pure data models shared across all packages
├── MiumKit/                    # CEF C++/Objective-C bridge layer
├── CEFShared/                  # Shared CEF utilities
├── CookiesInterop/             # Cookie storage integration with CEF
├── Networking/                 # Network layer
├── TrackpadGestures/           # Private API multitouch gesture recognition
├── ReorderableList/            # Generic drag-and-drop reorderable list (AppKit)
├── OverlayView/                # Toast notifications
├── Aesthetics/                 # Design tokens, fonts, colors
├── BrandColors/                # Brand color palette
├── Helpers/                    # Utility extensions
├── Views/                      # Shared UI components
├── ActionBarView/              # Action bar primitives
├── Vendors/                    # SPM dependency aggregator (re-exports)
├── Vendor/
│   ├── AperturePackages/       # Image processing pipeline (LUT transforms, grain, dithering)
│   └── CEF/                    # Chromium Embedded Framework distribution (Git LFS)
├── docs/                       # Engineering guides and specifications
├── scripts/                    # CEF packaging, signing, notarization
└── fastlane/                   # Release automation
```

### Key Patterns

- **Hybrid UI** — AppKit manages the window, sidebar panel, and browser host views; SwiftUI is embedded via `NSHostingView` for settings and overlay components
- **Observable view models** — All view models use Swift's `@Observable` macro; UI types are `@MainActor`-isolated
- **Dependency injection** — Uses [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) for testable, injectable services
- **Shared state** — Persistent cross-module state via [swift-sharing](https://github.com/pointfreeco/swift-sharing) (`@Shared`)
- **Hot reload** — Views are wired through [Inject](https://github.com/krzysztofzablocki/Inject) for rapid development iteration
- **Strict concurrency** — Swift 6.2 strict concurrency enforced across all targets as a build blocker
- **Model ownership** — All domain model types live in `ModelKit`; feature packages depend on it rather than defining duplicate types

### CEF Integration

The Chromium Embedded Framework is integrated through a layered bridge:

1. **MiumKit** — C++/Objective-C layer that interfaces directly with the CEF C API (compiled with `gnu++20`)
2. **BrowserRuntime** — Swift wrapper providing browser lifecycle management, permission gating, and JavaScript evaluation
3. **BrowserView** — Tab-level browser container that manages CEF browser instances, URL navigation, and native content overlays

CEF runs in external message loop mode with a fallback watchdog timer. The multi-process architecture requires specific entitlements for JIT compilation, unsigned executable memory, and disabled library validation.

### Camera Pipeline

The camera system flows through several stages:

1. **Capture** — `BrowserCameraCaptureController` manages AVFoundation capture sessions and device selection (prefers display-integrated cameras)
2. **Processing** — `BrowserCameraFrameProcessor` runs each `CVPixelBuffer` through the Aperture Pipeline (LUT color transforms, grain, dithering via Core Image)
3. **Preview** — Processed frames are rendered as `CGImage` for the sidebar/menu bar live preview
4. **Browser routing** — Processed frames can be routed directly to web pages via a JavaScript bridge for `getUserMedia()` fulfillment

## Requirements

- **macOS 14.0** (Sonoma) or later
- **Xcode 16+** with Swift 6.2 support
- **Git LFS** — The CEF framework binaries are stored in Git LFS

## Getting Started

### Prerequisites

Install Git LFS and pull the binary assets:

```bash
brew install git-lfs
git lfs install
git lfs pull
```

Install development tools via [mise](https://mise.jdx.dev/):

```bash
# Automatic setup
make ensure-tools

# Or manual
bash scripts/setup-mise.sh
mise install
```

### Building

1. Open `Navigator.xcodeproj` in Xcode
2. Select the **Navigator** scheme
3. Build and run (Cmd+R)

The build process will:
- Resolve SPM dependencies (both remote and local packages)
- Package the CEF runtime via the `CEFPackager` target
- Attach the CEF runtime and helper processes to the app bundle
- Sign helper binaries with the appropriate entitlements

### CEF Runtime

The CEF distribution must be present at `Vendor/CEF/Release/`. It should contain:

- `Chromium Embedded Framework.framework`
- Helper apps: `Navigator Helper.app`, `Navigator Helper (Renderer).app`, `Navigator Helper (GPU).app`, and optionally `Navigator Helper (Plugin).app`

The `CEFPackager` target processes these into `ChromiumEmbeddedRuntime.framework`, which the build phase embeds into the app bundle. See [scripts/README.md](scripts/README.md) for details on runtime packaging, signing, and verification.

### Verification

Verify a built app bundle:

```bash
./scripts/verify_runtime.sh /path/to/Navigator.app
```

This checks framework presence, helper roles, code signatures, and locale resources.

## Development

### Code Formatting

```bash
make format
```

Uses [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) with the project's `.swiftformat` configuration (tab indentation, 120 character width, alphabetized imports).

### Localization

Validate string catalogs before formatting:

```bash
make validate-xcstrings
```

User-facing strings use `Localizable.xcstrings` catalogs with typed `LocalizedStringResource` accessors. Currently supports English and Japanese.

### Code Generation

Asset and font catalogs are processed by [SwiftGen](https://github.com/SwiftGen/SwiftGen) (configured in `swiftgen.yml`) to produce typesafe accessors in the `Aesthetics` package.

### Signing and Notarization

```bash
./scripts/sign_and_notarize.sh /path/to/Navigator.app
```

Requires `TEAM_ID`, `APPLE_ID`, and `NOTARY_PASSWORD` environment variables. The `CEFPackager` target also supports one-step fetch, package, sign, and notarize workflows — see [scripts/README.md](scripts/README.md).

### Release Automation

Releases are managed through [Fastlane](https://fastlane.tools/):

```bash
cd fastlane && bundle exec fastlane release
```

Handles version bumping, code signing, notarization, and distribution.

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+N | New window |
| Cmd+T | New tab |
| Cmd+W | Close tab |
| Cmd+L | Focus location bar |
| Cmd+R | Reload |
| Cmd+[ | Back |
| Cmd+] | Forward |
| Cmd+Shift+T | Reopen closed tab |
| Cmd+P | Toggle pin tab |
| Cmd+Shift+C | Copy current URL |
| Cmd+Shift+[ | Previous tab |
| Cmd+Shift+] | Next tab |
| Cmd+1–9 | Jump to tab by index |

## Dependencies

### External (SPM)

| Package | Purpose |
|---------|---------|
| [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) | Dependency injection |
| [swift-sharing](https://github.com/pointfreeco/swift-sharing) | Persistent shared state |
| [swift-tagged](https://github.com/pointfreeco/swift-tagged) | Type-safe tagged values |
| [swift-collections](https://github.com/apple/swift-collections) | Ordered collections |
| [swift-identified-collections](https://github.com/pointfreeco/swift-identified-collections) | Identified arrays |
| [Inject](https://github.com/krzysztofzablocki/Inject) | Hot reload for views |
| [Sparkle](https://github.com/sparkle-project/Sparkle) | Auto-update framework |
| [Wave](https://github.com/jtrivedi/Wave) | Spring animations |

### Vendored

| Component | Purpose |
|-----------|---------|
| **Chromium Embedded Framework** | Web rendering engine (Git LFS) |
| **Aperture Pipeline** | LUT-based color transforms, film grain, dithering |
| **Aperture Shared** | Quantization modes, grain presets, transformation types |

## Documentation

The `docs/` directory contains detailed engineering guides organized by topic:

### Browser
- CEF bridge hardening and architecture refactor
- CEF scrolling and message pump architecture
- MiumKit native rewrite specification
- Camera routing integration
- Tab activation lifecycle
- Browser session history restoration
- Spaces engineering guide
- Permissions and incognito mode plans

### AppKit
- Trackpad gestures implementation and stability refactor
- ReorderableList design, drag performance, and autoscroll fixes
- High-performance reorderable table implementation plan
- Sidebar SwiftUI interaction investigation
- Sparkle auto-update integration

### Security
- Client-side end-to-end encrypted sync specification
- Key management and trusted device plan

## Project Structure Details

### Entitlements

The main app requires these entitlements for CEF compatibility:

| Entitlement | Reason |
|-------------|--------|
| `com.apple.security.cs.allow-jit` | V8 JavaScript JIT compilation |
| `com.apple.security.cs.allow-unsigned-executable-memory` | CEF runtime memory management |
| `com.apple.security.cs.disable-library-validation` | CEF dynamic library loading |

CEF helper processes have their own entitlement profiles in `scripts/entitlements/`.

### Build Targets

| Target | Description |
|--------|-------------|
| **Navigator** | Main macOS application |
| **NavigatorTests** | Integration and unit tests |
| **CEFBuilder** | Fetches and stages CEF distribution |
| **CEFPackager** | Packages CEF into deterministic runtime artifact |

## License

See [LICENSE](LICENSE) for details.
