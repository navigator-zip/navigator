import AppKit
import BrowserRuntime
import Observation

@MainActor
@Observable
final class BrowserTopLevelImageContentViewModel {
	enum PreferredSizingMode {
		case fixedWidth
		case fixedHeight
	}

	private(set) var image: NSImage?
	private(set) var failureText: String?
	let content: BrowserRuntimeTopLevelNativeContent

	init(content: BrowserRuntimeTopLevelNativeContent) {
		self.content = content
		resolveDisplayState()
	}

	init(
		content: BrowserRuntimeTopLevelNativeContent,
		image: NSImage?,
		failureText: String? = nil
	) {
		self.content = content
		self.image = image
		self.failureText = failureText ?? (image == nil ? content.url : nil)
	}

	var preferredSizingMode: PreferredSizingMode {
		guard let image, image.size.width > 0, image.size.height > 0 else {
			return .fixedHeight
		}
		return image.size.width > image.size.height ? .fixedWidth : .fixedHeight
	}

	var imageAspectRatio: CGFloat? {
		guard let image, image.size.width > 0, image.size.height > 0 else {
			return nil
		}
		return image.size.width / image.size.height
	}

	private func resolveDisplayState() {
		guard let url = URL(string: content.url) else {
			image = nil
			failureText = content.url
			return
		}

		image = NSImage(contentsOf: url)
		failureText = image == nil ? content.url : nil
	}
}
