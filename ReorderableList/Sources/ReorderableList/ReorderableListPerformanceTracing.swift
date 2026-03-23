import Foundation
import OSLog

enum ReorderableListPerformanceTraceEvent: String, CaseIterable {
	case dragLift = "DragLift"
	case dragUpdate = "DragUpdate"
	case autoscrollTick = "AutoscrollTick"
	case dragSettle = "DragSettle"

	var signpostName: StaticString {
		switch self {
		case .dragLift:
			"DragLift"
		case .dragUpdate:
			"DragUpdate"
		case .autoscrollTick:
			"AutoscrollTick"
		case .dragSettle:
			"DragSettle"
		}
	}
}

struct ReorderableListPerformanceTraceHandle {
	let event: ReorderableListPerformanceTraceEvent
	fileprivate let signpostState: OSSignpostIntervalState?

	init(
		event: ReorderableListPerformanceTraceEvent,
		signpostState: OSSignpostIntervalState? = nil
	) {
		self.event = event
		self.signpostState = signpostState
	}
}

protocol ReorderableListPerformanceTracing {
	func beginInterval(_ event: ReorderableListPerformanceTraceEvent) -> ReorderableListPerformanceTraceHandle
	func endInterval(_ handle: ReorderableListPerformanceTraceHandle)
}

struct ReorderableListOSPerformanceTracing: ReorderableListPerformanceTracing {
	private static let signposter = OSSignposter(
		subsystem: "com.navigator.ReorderableList",
		category: "DragPerformance"
	)

	func beginInterval(_ event: ReorderableListPerformanceTraceEvent) -> ReorderableListPerformanceTraceHandle {
		ReorderableListPerformanceTraceHandle(
			event: event,
			signpostState: Self.signposter.beginInterval(event.signpostName)
		)
	}

	func endInterval(_ handle: ReorderableListPerformanceTraceHandle) {
		guard let signpostState = handle.signpostState else { return }
		Self.signposter.endInterval(handle.event.signpostName, signpostState)
	}
}
