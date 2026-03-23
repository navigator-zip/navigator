import AppKit
import BrowserRuntime
import ModelKit

@MainActor
public protocol BrowserRuntimeDriving: AnyObject {
	func noteBrowserActivity()
	func hasPendingNativeBrowserClose() -> Bool
	func createBrowser(in parentView: NSView, initialURL: String) -> CEFBridgeBrowserRef?
	func resizeBrowser(_ browser: CEFBridgeBrowserRef?, in view: NSView)
	func load(_ browser: CEFBridgeBrowserRef?, url: String)
	func stopLoad(_ browser: CEFBridgeBrowserRef?)
	func close(_ browser: CEFBridgeBrowserRef?)
	func setAddressChangeHandler(
		for browser: CEFBridgeBrowserRef?,
		handler: ((String) -> Void)?
	)
	func setFaviconURLChangeHandler(
		for browser: CEFBridgeBrowserRef?,
		handler: ((String) -> Void)?
	)
	func setTitleChangeHandler(
		for browser: CEFBridgeBrowserRef?,
		handler: ((String) -> Void)?
	)
	func setTopLevelNativeContentHandler(
		for browser: CEFBridgeBrowserRef?,
		supportedKinds: Set<BrowserRuntimeTopLevelNativeContentKind>,
		handler: ((BrowserRuntimeTopLevelNativeContent) -> Void)?
	)
	func setRenderProcessTerminationHandler(
		for browser: CEFBridgeBrowserRef?,
		handler: ((BrowserRuntimeRenderProcessTermination) -> Void)?
	)
	func setMainFrameNavigationHandler(
		for browser: CEFBridgeBrowserRef?,
		handler: ((BrowserRuntimeMainFrameNavigationEvent) -> Void)?
	)
	func setOpenURLInTabHandler(
		for browser: CEFBridgeBrowserRef?,
		handler: ((BrowserRuntimeOpenURLInTabEvent) -> Void)?
	)
	func setCameraRoutingEventHandler(
		for browser: CEFBridgeBrowserRef?,
		handler: ((BrowserCameraRoutingEvent) -> Void)?
	)
	func setPermissionPromptHandler(
		for browser: CEFBridgeBrowserRef?,
		handler: ((BrowserPermissionSession?) -> Void)?
	)
	func resolvePermissionPrompt(
		sessionID: BrowserPermissionSessionID,
		decision: BrowserPermissionPromptDecision,
		persistence: BrowserPermissionPersistence
	)
	func cancelPermissionPrompt(sessionID: BrowserPermissionSessionID)
	func evaluateJavaScriptWithResult(
		_ browser: CEFBridgeBrowserRef?,
		script: String,
		completion: @escaping @MainActor (String?, String?) -> Void
	)
	func evaluateJavaScriptInRendererWithResult(
		_ browser: CEFBridgeBrowserRef?,
		script: String,
		completion: @escaping @MainActor (String?, String?) -> Void
	)
	func sendRendererProcessMessage(
		_ browser: CEFBridgeBrowserRef?,
		channel: String,
		jsonPayload: String,
		completion: @escaping @MainActor (String?, String?) -> Void
	)
	func goBack(_ browser: CEFBridgeBrowserRef?)
	func goForward(_ browser: CEFBridgeBrowserRef?)
	func reload(_ browser: CEFBridgeBrowserRef?)
	func canGoBack(_ browser: CEFBridgeBrowserRef?) -> Bool
	func canGoForward(_ browser: CEFBridgeBrowserRef?) -> Bool
	func isLoading(_ browser: CEFBridgeBrowserRef?) -> Bool
}

extension BrowserRuntime: BrowserRuntimeDriving {}

@MainActor
public struct BrowserChromeEventMonitoring {
	var addLocalMouseMovedMonitor: (@escaping (NSEvent) -> NSEvent?) -> Any?
	var addLocalCommitInteractionMonitor: (@escaping (NSEvent) -> NSEvent?) -> Any?
	var removeMonitor: (Any) -> Void

	public static let live = Self(
		addLocalMouseMovedMonitor: { handler in
			NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: handler)
		},
		addLocalCommitInteractionMonitor: { handler in
			NSEvent.addLocalMonitorForEvents(
				matching: [
					.leftMouseDown,
					.leftMouseUp,
					.rightMouseDown,
					.rightMouseUp,
					.otherMouseDown,
					.otherMouseUp,
					.scrollWheel,
					.keyDown,
				],
				handler: handler
			)
		},
		removeMonitor: { monitor in
			NSEvent.removeMonitor(monitor)
		}
	)
}

typealias BrowserContainerCreationScheduler = (@escaping () -> Void) -> DispatchWorkItem
