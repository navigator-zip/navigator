import Foundation

typealias BrowserRuntimeRendererJavaScriptResultCallback = @convention(c) (
	UnsafeMutableRawPointer?,
	UnsafePointer<CChar>?,
	UnsafePointer<CChar>?
) -> Void

@_silgen_name("CEFBridge_ExecuteJavaScriptInRendererWithResult")
private func browserRuntimeCEFBridgeExecuteJavaScriptInRendererWithResult(
	_ browserRef: CEFBridgeBrowserRef?,
	_ script: UnsafePointer<CChar>?,
	_ callback: BrowserRuntimeRendererJavaScriptResultCallback?,
	_ userData: UnsafeMutableRawPointer?
)

@MainActor
private final class BrowserRuntimeRendererJavaScriptResultBox {
	let completion: @MainActor (String?, String?) -> Void

	init(completion: @escaping @MainActor (String?, String?) -> Void) {
		self.completion = completion
	}
}

@MainActor
enum BrowserRuntimeRendererJavaScriptBridge {
	typealias ExecuteWithResult = (
		CEFBridgeBrowserRef?,
		UnsafePointer<CChar>?,
		BrowserRuntimeRendererJavaScriptResultCallback?,
		UnsafeMutableRawPointer?
	) -> Void

	static let liveExecuteWithResult: ExecuteWithResult = { browserRef, script, callback, userData in
		browserRuntimeCEFBridgeExecuteJavaScriptInRendererWithResult(
			browserRef,
			script,
			callback,
			userData
		)
	}

	static var executeWithResult: ExecuteWithResult = liveExecuteWithResult

	static func executeLiveWithResultForTesting(
		browserRef: CEFBridgeBrowserRef?,
		script: UnsafePointer<CChar>?,
		callback: BrowserRuntimeRendererJavaScriptResultCallback?,
		userData: UnsafeMutableRawPointer?
	) {
		liveExecuteWithResult(browserRef, script, callback, userData)
	}
}

private let browserRuntimeRendererJavaScriptResultCallback: BrowserRuntimeRendererJavaScriptResultCallback = {
	userData,
		result,
		error in
	guard let userData else { return }
	let callbackBox = Unmanaged<BrowserRuntimeRendererJavaScriptResultBox>.fromOpaque(userData).takeRetainedValue()
	let resultString = result.map(String.init(cString:))
	let errorString = error.map(String.init(cString:))
	Task { @MainActor in
		callbackBox.completion(resultString, errorString)
	}
}

@MainActor
func browserRuntimeInvokeRendererJavaScriptResultCallbackForTesting(
	userData: UnsafeMutableRawPointer?,
	result: UnsafePointer<CChar>?,
	error: UnsafePointer<CChar>?
) {
	browserRuntimeRendererJavaScriptResultCallback(userData, result, error)
}

public extension BrowserRuntime {
	@MainActor
	func evaluateJavaScriptInRendererWithResult(
		_ browser: CEFBridgeBrowserRef?,
		script: String,
		completion: @escaping @MainActor (String?, String?) -> Void
	) {
		guard let browser else {
			completion(nil, "Missing browser")
			return
		}
		let callbackBox = BrowserRuntimeRendererJavaScriptResultBox(completion: completion)
		let retained = Unmanaged.passRetained(callbackBox)
		script.withCString { scriptCString in
			BrowserRuntimeRendererJavaScriptBridge.executeWithResult(
				browser,
				scriptCString,
				browserRuntimeRendererJavaScriptResultCallback,
				retained.toOpaque()
			)
		}
	}
}
