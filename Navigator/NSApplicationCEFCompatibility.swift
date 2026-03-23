import AppKit
import ObjectiveC

private var cefHandlingSendEventStateKey: UInt8 = 0

extension NSApplication {
	@objc func isHandlingSendEvent() -> Bool {
		guard let value = objc_getAssociatedObject(self, &cefHandlingSendEventStateKey) as? NSNumber else {
			return false
		}
		return value.boolValue
	}

	@objc func setHandlingSendEvent(_ handlingSendEvent: Bool) {
		objc_setAssociatedObject(
			self,
			&cefHandlingSendEventStateKey,
			NSNumber(value: handlingSendEvent),
			.OBJC_ASSOCIATION_RETAIN_NONATOMIC
		)
	}
}
