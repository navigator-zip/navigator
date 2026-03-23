import AppKit
import BrowserRuntime

struct BrowserTopLevelNativeContentViewFactory {
	let supportedKinds: Set<BrowserRuntimeTopLevelNativeContentKind>
	let makeView: @MainActor (BrowserRuntimeTopLevelNativeContent) -> NSView?

	static let live = Self(
		supportedKinds: [.image, .animatedImage],
		makeView: { content in
			guard content.kind == .image || content.kind == .animatedImage else {
				return nil
			}

			return InjectedBrowserView(
				BrowserTopLevelImageContentView(
					viewModel: BrowserTopLevelImageContentViewModel(content: content)
				)
			)
		}
	)
}
