import BrowserRuntime
import ModelKit

extension BrowserRuntimeDriving {
	func sendRendererProcessMessage(
		_ browser: CEFBridgeBrowserRef?,
		message: BrowserCameraRendererTransportMessage,
		completion: @escaping @MainActor (String?, String?) -> Void
	) {
		sendRendererProcessMessage(
			browser,
			channel: message.channel.rawValue,
			jsonPayload: message.jsonPayload,
			completion: completion
		)
	}
}
