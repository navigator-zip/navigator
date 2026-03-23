import AppKit
import BrowserView

#if canImport(Inject)
	import Inject

	@inline(__always)
	func InjectedViewController<Hosted: NSViewController>(_ construct: @escaping @autoclosure () -> Hosted) -> Hosted {
		#if DEBUG
			return ViewControllerHost(construct()).instance
		#else
			return construct()
		#endif
	}
#else
	@inline(__always)
	func InjectedViewController<Hosted: NSViewController>(_ construct: @autoclosure () -> Hosted) -> Hosted {
		return construct()
	}
#endif
