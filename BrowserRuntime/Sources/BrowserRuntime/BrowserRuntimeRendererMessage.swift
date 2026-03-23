import Foundation

typealias BrowserRuntimeRendererMessageCallback = @convention(c) (
	UInt32,
	UnsafePointer<CChar>?,
	UnsafeMutableRawPointer?
) -> Void

@_silgen_name("miumNativeCEFSendMessage")
private func browserRuntimeMiumCEFSendMessage(
	_ browserRef: CEFBridgeBrowserRef?,
	_ channel: UnsafePointer<CChar>?,
	_ jsonPayload: UnsafePointer<CChar>?,
	_ completionContext: UnsafeMutableRawPointer?,
	_ completion: BrowserRuntimeRendererMessageCallback?
) -> UInt32

@MainActor
private final class BrowserRuntimeRendererMessageResultBox {
	let completion: @MainActor (String?, String?) -> Void

	init(completion: @escaping @MainActor (String?, String?) -> Void) {
		self.completion = completion
	}
}

@MainActor
enum BrowserRuntimeRendererMessageBridge {
	typealias SendMessage = (
		CEFBridgeBrowserRef?,
		UnsafePointer<CChar>?,
		UnsafePointer<CChar>?,
		UnsafeMutableRawPointer?,
		BrowserRuntimeRendererMessageCallback?
	) -> UInt32

	static let liveSendMessage: SendMessage = { browserRef, channel, jsonPayload, completionContext, completion in
		browserRuntimeMiumCEFSendMessage(
			browserRef,
			channel,
			jsonPayload,
			completionContext,
			completion
		)
	}

	static var sendMessage: SendMessage = liveSendMessage

	static func sendLiveMessageForTesting(
		browserRef: CEFBridgeBrowserRef?,
		channel: UnsafePointer<CChar>?,
		jsonPayload: UnsafePointer<CChar>?,
		completionContext: UnsafeMutableRawPointer?,
		completion: BrowserRuntimeRendererMessageCallback?
	) {
		_ = liveSendMessage(
			browserRef,
			channel,
			jsonPayload,
			completionContext,
			completion
		)
	}
}

private let browserRuntimeRendererMessageCallback: BrowserRuntimeRendererMessageCallback = {
	code,
		message,
		userData in
	guard let userData else { return }
	let callbackBox = Unmanaged<BrowserRuntimeRendererMessageResultBox>.fromOpaque(userData).takeRetainedValue()
	let messageString = message.map(String.init(cString:))
	Task { @MainActor in
		if code == 0 {
			callbackBox.completion(messageString, nil)
		}
		else {
			callbackBox.completion(nil, messageString ?? "Renderer message send failed")
		}
	}
}

@MainActor
func browserRuntimeInvokeRendererMessageCallbackForTesting(
	code: UInt32,
	message: UnsafePointer<CChar>?,
	userData: UnsafeMutableRawPointer?
) {
	browserRuntimeRendererMessageCallback(code, message, userData)
}

public extension BrowserRuntime {
	@MainActor
	func sendRendererProcessMessage(
		_ browser: CEFBridgeBrowserRef?,
		channel: String,
		jsonPayload: String,
		completion: @escaping @MainActor (String?, String?) -> Void
	) {
		guard let browser else {
			completion(nil, "Missing browser")
			return
		}
		setActiveBrowser(browser)
		let callbackBox = BrowserRuntimeRendererMessageResultBox(completion: completion)
		let retained = Unmanaged.passRetained(callbackBox)
		channel.withCString { channelCString in
			jsonPayload.withCString { payloadCString in
				_ = BrowserRuntimeRendererMessageBridge.sendMessage(
					browser,
					channelCString,
					payloadCString,
					retained.toOpaque(),
					browserRuntimeRendererMessageCallback
				)
			}
		}
	}
}
