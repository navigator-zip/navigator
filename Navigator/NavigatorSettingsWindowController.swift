import AppKit
import ModelKit
import Vendors

enum NavigatorSettingsWindow {
	static let contentSize = NSSize(width: 520, height: 520)
}

@MainActor
protocol NavigatorSettingsWindowActionHandling: AnyObject {
	func beginStreamingBrowserImport(from source: BrowserImportSource)
	func importBrowserProfileChunk(_ profile: ImportedBrowserProfile, from source: BrowserImportSource)
	func finishStreamingBrowserImport(_ snapshot: ImportedBrowserSnapshot)
	func cancelStreamingBrowserImport(from source: BrowserImportSource)
	func openImportedBookmarks()
	func openImportedHistory(limit: Int)
}

enum NavigatorSettingsWindowShortcutResolver {
	static func shouldClose(
		modifiers: NSEvent.ModifierFlags,
		normalizedCharacter: String?,
		rawCharacter: String?
	) -> Bool {
		let supportedModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
		guard supportedModifiers == [.command] else { return false }
		return (normalizedCharacter ?? rawCharacter) == "w"
	}
}

private final class NavigatorSettingsChromeWindow: NSWindow {
	override var canBecomeKey: Bool {
		true
	}

	override var canBecomeMain: Bool {
		true
	}

	override func performKeyEquivalent(with event: NSEvent) -> Bool {
		let normalizedCharacter = event.charactersIgnoringModifiers?.lowercased()
		let rawCharacter = event.characters?.lowercased()
		if NavigatorSettingsWindowShortcutResolver.shouldClose(
			modifiers: event.modifierFlags,
			normalizedCharacter: normalizedCharacter,
			rawCharacter: rawCharacter
		) {
			close()
			return true
		}

		return super.performKeyEquivalent(with: event)
	}
}

@MainActor
final class NavigatorSettingsWindowActions {
	private let appViewModel: any NavigatorSettingsWindowActionHandling

	init(appViewModel: any NavigatorSettingsWindowActionHandling) {
		self.appViewModel = appViewModel
	}

	func handleImportEvent(_ event: BrowserImportEvent) {
		switch event {
		case .started(let source):
			appViewModel.beginStreamingBrowserImport(from: source)
		case .profileImported(let source, let profile):
			appViewModel.importBrowserProfileChunk(profile, from: source)
		case .finished(let snapshot):
			appViewModel.finishStreamingBrowserImport(snapshot)
		}
	}

	func handleImportFailure(for source: BrowserImportSource) {
		appViewModel.cancelStreamingBrowserImport(from: source)
	}

	func openImportedBookmarks() {
		appViewModel.openImportedBookmarks()
	}

	func openImportedHistory() {
		appViewModel.openImportedHistory(limit: 20)
	}
}

extension AppViewModel: NavigatorSettingsWindowActionHandling {}

@MainActor
final class NavigatorSettingsWindowController: NSWindowController {
	private let actions: NavigatorSettingsWindowActions
	private let settingsViewController: NavigatorSettingsViewController
	private let resolveAnchorWindow: () -> NSWindow?

	init(
		navigatorAppViewModel: AppViewModel? = nil,
		resolveAnchorWindow: @escaping () -> NSWindow? = { nil }
	) {
		self.resolveAnchorWindow = resolveAnchorWindow
		let resolvedNavigatorAppViewModel = navigatorAppViewModel ?? appViewModel
		actions = NavigatorSettingsWindowActions(appViewModel: resolvedNavigatorAppViewModel)
		let settingsViewModel = NavigatorSettingsViewModel(
			bundle: .main,
			onImportEvent: actions.handleImportEvent(_:),
			onImportFailure: actions.handleImportFailure(for:),
			onOpenImportedBookmarks: actions.openImportedBookmarks,
			onOpenImportedHistory: actions.openImportedHistory
		)
		settingsViewController = InjectedViewController(
			NavigatorSettingsViewController(
				viewModel: settingsViewModel
			)
		)
		let window = NavigatorSettingsChromeWindow(
			contentRect: NSRect(origin: .zero, size: NavigatorSettingsWindow.contentSize),
			styleMask: [.titled, .closable, .resizable, .miniaturizable],
			backing: .buffered,
			defer: false
		)
		window.contentViewController = settingsViewController
		window.isReleasedWhenClosed = false
		WindowChromeStyler.apply(to: window)
		window.backgroundColor = .clear
		window.isOpaque = false
		window.hasShadow = true
		window.contentView?.wantsLayer = true
		window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
		window.contentView?.layer?.masksToBounds = false
		window.setContentSize(NavigatorSettingsWindow.contentSize)
		window.contentMinSize = NavigatorSettingsWindow.contentSize
		window.contentMaxSize = NavigatorSettingsWindow.contentSize
		window.styleMask = [.borderless, .closable]
		super.init(window: window)
		shouldCascadeWindows = false
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func showWindow(_ sender: Any?) {
		settingsViewController.refresh()
		positionWindow()
		super.showWindow(sender)
	}

	func invalidate() {
		window?.contentViewController = nil
		settingsViewController.invalidate()
	}

	private func positionWindow() {
		guard let settingsWindow = window else { return }
		guard let anchorWindow = resolveAnchorWindow(), anchorWindow !== settingsWindow else {
			settingsWindow.center()
			return
		}

		let visibleFrame = Self.resolvedVisibleFrame(
			attachedScreenVisibleFrame: anchorWindow.screen?.visibleFrame,
			mainScreenVisibleFrame: NSScreen.main?.visibleFrame
		)
		let targetFrame = NavigatorSettingsWindowPlacementResolver.frame(
			windowSize: settingsWindow.frame.size,
			centeredIn: anchorWindow.frame,
			visibleFrame: visibleFrame
		)
		settingsWindow.setFrame(targetFrame, display: false)
	}

	static func resolvedVisibleFrame(
		attachedScreenVisibleFrame: NSRect?,
		mainScreenVisibleFrame: NSRect?
	) -> NSRect? {
		if let attachedScreenVisibleFrame {
			return attachedScreenVisibleFrame
		}
		return mainScreenVisibleFrame
	}
}

enum NavigatorSettingsWindowPlacementResolver {
	static func frame(
		windowSize: NSSize,
		centeredIn parentFrame: NSRect,
		visibleFrame: NSRect?
	) -> NSRect {
		var targetOrigin = NSPoint(
			x: parentFrame.midX - windowSize.width / 2,
			y: parentFrame.midY - windowSize.height / 2
		)

		if let visibleFrame {
			targetOrigin = clampedOrigin(targetOrigin, windowSize: windowSize, visibleFrame: visibleFrame)
		}

		return NSRect(origin: targetOrigin, size: windowSize)
	}

	private static func clampedOrigin(_ origin: NSPoint, windowSize: NSSize, visibleFrame: NSRect) -> NSPoint {
		let maxX = max(visibleFrame.minX, visibleFrame.maxX - windowSize.width)
		let maxY = max(visibleFrame.minY, visibleFrame.maxY - windowSize.height)
		return NSPoint(
			x: min(max(origin.x, visibleFrame.minX), maxX),
			y: min(max(origin.y, visibleFrame.minY), maxY)
		)
	}
}
