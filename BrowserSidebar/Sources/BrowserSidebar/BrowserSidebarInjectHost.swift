import AppKit
import Vendors

#if canImport(Inject)
	import Inject

	@inline(__always)
	@MainActor
	public func InjectedBrowserSidebarView(
		_ construct: @escaping @autoclosure @MainActor () -> some NSView
	) -> NSView {
		#if DEBUG
			return ViewHost(construct())
		#else
			return construct()
		#endif
	}
#else
	@inline(__always)
	@MainActor
	public func InjectedBrowserSidebarView(
		_ construct: @autoclosure @MainActor () -> some NSView
	) -> NSView {
		construct()
	}
#endif
