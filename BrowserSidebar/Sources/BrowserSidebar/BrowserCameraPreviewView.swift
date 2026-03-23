import AppKit
import CoreGraphics
import Vendors

@MainActor
final class BrowserCameraPreviewView: NSImageView {
	var previewFrame: CGImage? {
		didSet {
			image = nil
			layer?.contents = previewFrame
			isHidden = previewFrame == nil
		}
	}

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		setupView()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		setupView()
	}

	private func setupView() {
		wantsLayer = true
		image = nil
		imageScaling = .scaleNone
		layer?.contentsGravity = .resizeAspectFill
		layer?.masksToBounds = true
		isHidden = true
	}
}
