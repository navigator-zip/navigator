import AppKit
import Foundation
import ModelKit

enum BrowserCameraManagedFrameDelivery {
	static let defaultCompressionFactor = 0.55
	static let minimumFrameInterval: TimeInterval = 1.0 / 8.0

	static func payload(
		from image: CGImage,
		sequence: UInt64,
		compressionFactor: Double = defaultCompressionFactor
	) -> BrowserCameraManagedFramePayload? {
		let imageRep = NSBitmapImageRep(cgImage: image)
		let jpegData = imageRep.representation(
			using: .jpeg,
			properties: [.compressionFactor: compressionFactor]
		)
		guard let jpegData else { return nil }

		return BrowserCameraManagedFramePayload(
			sequence: sequence,
			width: image.width,
			height: image.height,
			imageDataURL: "data:image/jpeg;base64,\(jpegData.base64EncodedString())"
		)
	}

	static func makeFrameDeliveryScript(for payload: BrowserCameraManagedFramePayload) -> String {
		let payloadJSON = makeFrameDeliveryTransportMessage(for: payload).jsonPayload

		return """
		(function() {
		  const shim = window.\(BrowserCameraRoutingScriptConstants.shimKey);
		  if (!shim || typeof shim.receiveFrame !== "function") {
		    return "missing-shim";
		  }
		  shim.receiveFrame(\(payloadJSON));
		  return "delivered";
		})();
		"""
	}

	static func makeFrameDeliveryTransportMessage(
		for payload: BrowserCameraManagedFramePayload
	) -> BrowserCameraRendererTransportMessage {
		payload.rendererTransportMessage()
	}

	static func frameDeliveryMessagePayload(for payload: BrowserCameraManagedFramePayload) -> String {
		makeFrameDeliveryTransportMessage(for: payload).jsonPayload
	}

	static func clearFrameMessagePayload() -> String {
		makeClearFrameTransportMessage().jsonPayload
	}

	static func makeClearFrameScript() -> String {
		"""
		(function() {
		  const shim = window.\(BrowserCameraRoutingScriptConstants.shimKey);
		  if (!shim || typeof shim.clearFrame !== "function") {
		    return "missing-shim";
		  }
		  shim.clearFrame();
		  return "cleared";
		})();
		"""
	}

	static func makeClearFrameTransportMessage() -> BrowserCameraRendererTransportMessage {
		BrowserCameraRendererFrameClearPayload().transportMessage()
	}
}
