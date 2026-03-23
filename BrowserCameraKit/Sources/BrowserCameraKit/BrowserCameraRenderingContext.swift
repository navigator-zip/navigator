import CoreGraphics
import CoreImage
import CoreVideo
import Metal

public enum BrowserCameraRenderingContext {
	private static let maximumPreviewLongEdge: CGFloat = 640

	public static let shared: CIContext = {
		if let device = MTLCreateSystemDefaultDevice() {
			return CIContext(mtlDevice: device)
		}
		return CIContext()
	}()

	public static func makePreviewImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
		let sourceExtent = CGRect(
			x: 0,
			y: 0,
			width: CVPixelBufferGetWidth(pixelBuffer),
			height: CVPixelBufferGetHeight(pixelBuffer)
		)
		let longEdge = max(sourceExtent.width, sourceExtent.height)
		let scale = min(maximumPreviewLongEdge / max(longEdge, 1), 1)
		let image = CIImage(cvPixelBuffer: pixelBuffer)
		guard scale < 1 else {
			return shared.createCGImage(image, from: sourceExtent)
		}

		let previewExtent = CGRect(
			x: 0,
			y: 0,
			width: floor(sourceExtent.width * scale),
			height: floor(sourceExtent.height * scale)
		)
		let previewImage = image.transformed(by: .init(scaleX: scale, y: scale))
		return shared.createCGImage(previewImage, from: previewExtent)
	}
}
