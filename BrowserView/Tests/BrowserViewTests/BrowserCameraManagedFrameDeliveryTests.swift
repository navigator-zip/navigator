import AppKit
@testable import BrowserView
import ModelKit
import XCTest

final class BrowserCameraManagedFrameDeliveryTests: XCTestCase {
	func testPayloadEncodesPreviewImageAsJPEGDataURL() throws {
		let payload = try XCTUnwrap(
			BrowserCameraManagedFrameDelivery.payload(
				from: makePreviewFrame(),
				sequence: 4,
				compressionFactor: 0.8
			)
		)

		XCTAssertEqual(payload.sequence, 4)
		XCTAssertEqual(payload.width, 4)
		XCTAssertEqual(payload.height, 3)
		XCTAssertTrue(payload.imageDataURL.hasPrefix("data:image/jpeg;base64,"))
	}

	func testFrameDeliveryScriptInvokesShimReceiverWithEncodedPayload() {
		let payload = BrowserCameraManagedFramePayload(
			sequence: 9,
			width: 640,
			height: 480,
			imageDataURL: "data:image/jpeg;base64,Zm9v"
		)

		let script = BrowserCameraManagedFrameDelivery.makeFrameDeliveryScript(for: payload)

		XCTAssertTrue(script.contains("window.\(BrowserCameraRoutingScriptConstants.shimKey)"))
		XCTAssertTrue(script.contains("shim.receiveFrame("))
		XCTAssertTrue(script.contains("\"sequence\":9"))
		XCTAssertTrue(script.contains("\"width\":640"))
		XCTAssertTrue(script.contains("\"height\":480"))
		XCTAssertTrue(script.contains("\"imageDataURL\":"))
		XCTAssertTrue(script.contains("data:image"))
		XCTAssertTrue(script.contains("Zm9v"))
		XCTAssertTrue(script.contains("return \"delivered\";"))
		XCTAssertTrue(script.contains("return \"missing-shim\";"))
	}

	func testClearFrameScriptInvokesShimClearMethod() {
		let script = BrowserCameraManagedFrameDelivery.makeClearFrameScript()

		XCTAssertTrue(script.contains("window.\(BrowserCameraRoutingScriptConstants.shimKey)"))
		XCTAssertTrue(script.contains("shim.clearFrame()"))
		XCTAssertTrue(script.contains("return \"cleared\";"))
		XCTAssertTrue(script.contains("return \"missing-shim\";"))
	}

	func testFrameDeliveryMessagePayloadEncodesManagedFramePayloadAsJSON() {
		let payload = BrowserCameraManagedFramePayload(
			sequence: 12,
			width: 1280,
			height: 720,
			imageDataURL: "data:image/jpeg;base64,YmFy"
		)

		let jsonPayload = BrowserCameraManagedFrameDelivery.frameDeliveryMessagePayload(for: payload)

		XCTAssertTrue(jsonPayload.contains("\"sequence\":12"))
		XCTAssertTrue(jsonPayload.contains("\"width\":1280"))
		XCTAssertTrue(jsonPayload.contains("\"height\":720"))
		XCTAssertTrue(jsonPayload.contains("\"imageDataURL\":"))
		XCTAssertTrue(jsonPayload.contains("YmFy"))
	}

	func testFrameDeliveryTransportMessageUsesFrameDeliveryChannel() {
		let payload = BrowserCameraManagedFramePayload(
			sequence: 14,
			width: 800,
			height: 600,
			imageDataURL: "data:image/jpeg;base64,QmF6"
		)

		let message = BrowserCameraManagedFrameDelivery.makeFrameDeliveryTransportMessage(for: payload)

		XCTAssertEqual(message.channel.rawValue, BrowserCameraRoutingScriptConstants.cameraFrameDeliveryChannel)
		XCTAssertTrue(message.jsonPayload.contains("\"sequence\":14"))
	}

	func testClearFrameMessagePayloadUsesEmptyJSONObject() {
		XCTAssertEqual(BrowserCameraManagedFrameDelivery.clearFrameMessagePayload(), "{}")
	}

	func testClearFrameTransportMessageUsesFrameClearChannel() {
		let message = BrowserCameraManagedFrameDelivery.makeClearFrameTransportMessage()

		XCTAssertEqual(message.channel.rawValue, BrowserCameraRoutingScriptConstants.cameraFrameClearChannel)
		XCTAssertEqual(message.jsonPayload, "{}")
	}

	private func makePreviewFrame() -> CGImage {
		let colorSpace = CGColorSpaceCreateDeviceRGB()
		let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(.init(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
		let context = CGContext(
			data: nil,
			width: 4,
			height: 3,
			bitsPerComponent: 8,
			bytesPerRow: 0,
			space: colorSpace,
			bitmapInfo: bitmapInfo.rawValue
		)!
		context.setFillColor(NSColor.systemOrange.cgColor)
		context.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
		return context.makeImage()!
	}
}
