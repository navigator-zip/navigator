import AppKit
@testable import BrowserRuntime
import XCTest

@MainActor
final class BrowserRuntimeRendererJavaScriptTests: XCTestCase {
	func testEvaluateJavaScriptInRendererWithResultReportsMissingBrowser() {
		let runtime = BrowserRuntime()
		let completionExpectation = expectation(description: "missing browser completion")
		var capturedResult: String?
		var capturedError: String?

		runtime.evaluateJavaScriptInRendererWithResult(nil, script: "window.test = true;") { result, error in
			capturedResult = result
			capturedError = error
			completionExpectation.fulfill()
		}

		wait(for: [completionExpectation], timeout: 1.0)
		XCTAssertNil(capturedResult)
		XCTAssertEqual(capturedError, "Missing browser")
	}

	func testEvaluateJavaScriptInRendererWithResultUsesBridgeCallbackForSuccess() {
		let runtime = BrowserRuntime()
		let browserRef = UnsafeMutableRawPointer(bitPattern: 0x1234)
		let completionExpectation = expectation(description: "renderer script success completion")
		var capturedBrowserRef: CEFBridgeBrowserRef?
		var capturedScript: String?
		var capturedResult: String?
		var capturedError: String?
		defer {
			BrowserRuntimeRendererJavaScriptBridge.executeWithResult = BrowserRuntimeRendererJavaScriptBridge
				.liveExecuteWithResult
		}

		BrowserRuntimeRendererJavaScriptBridge.executeWithResult = { browserRef, script, callback, userData in
			capturedBrowserRef = browserRef
			capturedScript = script.map(String.init(cString:))
			callback?(userData, "{\"acknowledged\":true}", "")
		}

		runtime.evaluateJavaScriptInRendererWithResult(browserRef, script: "window.test = true;") { result, error in
			capturedResult = result
			capturedError = error
			completionExpectation.fulfill()
		}

		wait(for: [completionExpectation], timeout: 1.0)
		XCTAssertEqual(capturedBrowserRef, browserRef)
		XCTAssertEqual(capturedScript, "window.test = true;")
		XCTAssertEqual(capturedResult, "{\"acknowledged\":true}")
		XCTAssertEqual(capturedError, "")
	}

	func testEvaluateJavaScriptInRendererWithResultUsesBridgeCallbackForFailure() {
		let runtime = BrowserRuntime()
		let browserRef = UnsafeMutableRawPointer(bitPattern: 0x4321)
		let completionExpectation = expectation(description: "renderer script failure completion")
		var capturedResult: String?
		var capturedError: String?
		defer {
			BrowserRuntimeRendererJavaScriptBridge.executeWithResult = BrowserRuntimeRendererJavaScriptBridge
				.liveExecuteWithResult
		}

		BrowserRuntimeRendererJavaScriptBridge.executeWithResult = { _, _, callback, userData in
			callback?(userData, "", "Renderer unavailable")
		}

		runtime.evaluateJavaScriptInRendererWithResult(browserRef, script: "window.test = false;") { result, error in
			capturedResult = result
			capturedError = error
			completionExpectation.fulfill()
		}

		wait(for: [completionExpectation], timeout: 1.0)
		XCTAssertEqual(capturedResult, "")
		XCTAssertEqual(capturedError, "Renderer unavailable")
	}

	func testRendererJavaScriptResultCallbackIgnoresMissingUserData() {
		browserRuntimeInvokeRendererJavaScriptResultCallbackForTesting(
			userData: nil,
			result: "{\"ignored\":true}",
			error: "Ignored error"
		)
	}

	func testLiveRendererJavaScriptBridgeAcceptsNilInputs() {
		BrowserRuntimeRendererJavaScriptBridge.executeLiveWithResultForTesting(
			browserRef: nil,
			script: nil,
			callback: nil,
			userData: nil
		)
	}
}
