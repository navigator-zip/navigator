import AppKit

@MainActor
struct ReorderableListEventMonitoring {
	var addLocalKeyDownMonitor: (@escaping (NSEvent) -> NSEvent?) -> Any?
	var addLocalLeftMouseUpMonitor: (@escaping (NSEvent) -> NSEvent?) -> Any?
	var addLocalLeftMouseDraggedMonitor: (@escaping (NSEvent) -> NSEvent?) -> Any?
	var removeMonitor: (Any) -> Void

	static let live = Self(
		addLocalKeyDownMonitor: { handler in
			NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: handler)
		},
		addLocalLeftMouseUpMonitor: { handler in
			NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp], handler: handler)
		},
		addLocalLeftMouseDraggedMonitor: { handler in
			NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged], handler: handler)
		},
		removeMonitor: { monitor in
			NSEvent.removeMonitor(monitor)
		}
	)
}
