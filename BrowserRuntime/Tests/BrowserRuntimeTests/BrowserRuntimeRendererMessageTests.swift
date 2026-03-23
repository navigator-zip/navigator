import AppKit
@testable import BrowserRuntime
import XCTest

@MainActor
final class BrowserRuntimeRendererMessageTests: XCTestCase {
	func testSendRendererProcessMessageReportsMissingBrowser() {
		let runtime = BrowserRuntime()
		let completionExpectation = expectation(description: "missing browser completion")
		var capturedResult: String?
		var capturedError: String?

		runtime.sendRendererProcessMessage(
			nil,
			channel: "__cameraFrameDelivery__",
			jsonPayload: #"{"sequence":1}"#
		) { result, error in
			capturedResult = result
			capturedError = error
			completionExpectation.fulfill()
		}

		wait(for: [completionExpectation], timeout: 1.0)
		XCTAssertNil(capturedResult)
		XCTAssertEqual(capturedError, "Missing browser")
	}

	func testSendRendererProcessMessageUsesBridgeCallbackForSuccess() {
		let runtime = BrowserRuntime()
		let browserRef = UnsafeMutableRawPointer(bitPattern: 0x2233)
		let completionExpectation = expectation(description: "renderer message success completion")
		var capturedBrowserRef: CEFBridgeBrowserRef?
		var capturedChannel: String?
		var capturedPayload: String?
		var capturedResult: String?
		var capturedError: String?
		defer {
			BrowserRuntimeRendererMessageBridge.sendMessage = BrowserRuntimeRendererMessageBridge.liveSendMessage
		}

		BrowserRuntimeRendererMessageBridge.sendMessage = {
			browserRef,
				channel,
				jsonPayload,
				callbackContext,
				callback in
			capturedBrowserRef = browserRef
			capturedChannel = channel.map(String.init(cString:))
			capturedPayload = jsonPayload.map(String.init(cString:))
			callback?(0, "{\"acknowledged\":true}", callbackContext)
			return 0
		}

		runtime.sendRendererProcessMessage(
			browserRef,
			channel: "__cameraFrameDelivery__",
			jsonPayload: #"{"sequence":1}"#
		) { result, error in
			capturedResult = result
			capturedError = error
			completionExpectation.fulfill()
		}

		wait(for: [completionExpectation], timeout: 1.0)
		XCTAssertEqual(capturedBrowserRef, browserRef)
		XCTAssertEqual(capturedChannel, "__cameraFrameDelivery__")
		XCTAssertEqual(capturedPayload, #"{"sequence":1}"#)
		XCTAssertEqual(capturedResult, "{\"acknowledged\":true}")
		XCTAssertNil(capturedError)
	}

	func testSendRendererProcessMessageUsesBridgeCallbackForFailure() {
		let runtime = BrowserRuntime()
		let browserRef = UnsafeMutableRawPointer(bitPattern: 0x3322)
		let completionExpectation = expectation(description: "renderer message failure completion")
		var capturedResult: String?
		var capturedError: String?
		defer {
			BrowserRuntimeRendererMessageBridge.sendMessage = BrowserRuntimeRendererMessageBridge.liveSendMessage
		}

		BrowserRuntimeRendererMessageBridge.sendMessage = { _, _, _, callbackContext, callback in
			callback?(1, "Renderer transport unavailable", callbackContext)
			return 1
		}

		runtime.sendRendererProcessMessage(
			browserRef,
			channel: "__cameraFrameClear__",
			jsonPayload: "{}"
		) { result, error in
			capturedResult = result
			capturedError = error
			completionExpectation.fulfill()
		}

		wait(for: [completionExpectation], timeout: 1.0)
		XCTAssertNil(capturedResult)
		XCTAssertEqual(capturedError, "Renderer transport unavailable")
	}

	func testSendRendererProcessMessageUsesDefaultFailureMessageWhenBridgeCallbackOmitsError() {
		let runtime = BrowserRuntime()
		let browserRef = UnsafeMutableRawPointer(bitPattern: 0x4422)
		let completionExpectation = expectation(description: "renderer message default failure completion")
		var capturedResult: String?
		var capturedError: String?
		defer {
			BrowserRuntimeRendererMessageBridge.sendMessage = BrowserRuntimeRendererMessageBridge.liveSendMessage
		}

		BrowserRuntimeRendererMessageBridge.sendMessage = { _, _, _, callbackContext, callback in
			callback?(1, nil, callbackContext)
			return 1
		}

		runtime.sendRendererProcessMessage(
			browserRef,
			channel: "__cameraRoutingConfigUpdate__",
			jsonPayload: #"{"routingEnabled":true}"#
		) { result, error in
			capturedResult = result
			capturedError = error
			completionExpectation.fulfill()
		}

		wait(for: [completionExpectation], timeout: 1.0)
		XCTAssertNil(capturedResult)
		XCTAssertEqual(capturedError, "Renderer message send failed")
	}

	func testRendererMessageCallbackIgnoresMissingUserData() {
		browserRuntimeInvokeRendererMessageCallbackForTesting(
			code: 1,
			message: "ignored",
			userData: nil
		)
	}

	func testLiveRendererMessageBridgeAcceptsNilInputs() {
		BrowserRuntimeRendererMessageBridge.sendLiveMessageForTesting(
			browserRef: nil,
			channel: nil,
			jsonPayload: nil,
			completionContext: nil,
			completion: nil
		)
	}
}
