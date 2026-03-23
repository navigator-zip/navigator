import AppKit
import Vendors

final class WindowChromeConfigurationView: NSObject {
	func applyIfNeeded(to window: NSWindow?) {
		guard let window else { return }
		WindowChromeStyler.apply(to: window)
	}
}

enum WindowChromeStyler {
	static func apply(to window: NSWindow) {
		window.styleMask.insert(.resizable)
		window.styleMask.insert(.fullSizeContentView)
		window.toolbar = nil
		window.titlebarSeparatorStyle = .none
		[
			NSWindow.ButtonType.closeButton,
			NSWindow.ButtonType.miniaturizeButton,
			NSWindow.ButtonType.zoomButton,
		].forEach { button in
			window.standardWindowButton(button)?.isHidden = true
		}
		window.title = ""
		window.titleVisibility = .hidden
		window.titlebarAppearsTransparent = true
		window.isOpaque = false
		window.isMovableByWindowBackground = true
		applyResolvedColors(to: window)
	}

	static func applyResolvedColors(to window: NSWindow) {
		window.backgroundColor = resolvedBackgroundColor(for: window)
	}

	static func resolvedBackgroundColor(for window: NSWindow) -> NSColor {
		if window.windowController is NavigatorSettingsWindowController {
			// Settings uses a clear host window so the inset floating panel controls the visible chrome.
			return .clear
		}

		let appearance = window.contentView?.effectiveAppearance ?? window.effectiveAppearance
		return resolvedBackgroundColor(for: appearance)
	}

	static func resolvedBackgroundColor(for appearance: NSAppearance) -> NSColor {
		resolveColor(Asset.Colors.background.color, for: appearance)
	}

	private static func resolveColor(_ color: NSColor, for appearance: NSAppearance) -> NSColor {
		var resolvedColor = color
		appearance.performAsCurrentDrawingAppearance {
			resolvedColor = NSColor(cgColor: color.cgColor) ?? color
		}
		return resolvedColor
	}
}
