import BrowserSidebar
import Foundation
import Observation

@MainActor
@Observable
public final class BrowserChromeViewModel {
	public enum Constants {
		public static let sidebarSpringAnimationKey = "navigator.sidebar.spring"
	}

	public struct Geometry {
		public var sidebarWidth: CGFloat = 280
		public var openTriggerDistance: CGFloat = 10
		public var sidebarRevealDelay: TimeInterval = 0.05
		public var dismissBufferDistance: CGFloat = 50
		public var resizeRevealDistance: CGFloat = 10

		public init(
			sidebarWidth: CGFloat = 280,
			openTriggerDistance: CGFloat = 10,
			sidebarRevealDelay: TimeInterval = 0.05,
			dismissBufferDistance: CGFloat = 50,
			resizeRevealDistance: CGFloat = 10
		) {
			self.sidebarWidth = sidebarWidth
			self.openTriggerDistance = openTriggerDistance
			self.sidebarRevealDelay = sidebarRevealDelay
			self.dismissBufferDistance = dismissBufferDistance
			self.resizeRevealDistance = resizeRevealDistance
		}
	}

	public typealias WorkItemScheduler = (TimeInterval, @escaping () -> Void) -> () -> Void

	private let sidebarPresentation: BrowserSidebarPresentation
	public private(set) var hasPendingSidebarOpen = false
	public var onPresentationChange: ((Bool, Bool) -> Void)?
	private var geometry: Geometry
	private let workItemScheduler: WorkItemScheduler
	private var cancelPendingSidebarOpenWorkItem: (() -> Void)?

	public var isSidebarPresented: Bool {
		sidebarPresentation.isPresented
	}

	public init(
		geometry: Geometry,
		workItemScheduler: @escaping WorkItemScheduler,
		sidebarPresentation: BrowserSidebarPresentation
	) {
		self.geometry = geometry
		self.workItemScheduler = workItemScheduler
		self.sidebarPresentation = sidebarPresentation
	}

	public convenience init() {
		self.init(
			geometry: Geometry(),
			workItemScheduler: Self.defaultWorkItemScheduler,
			sidebarPresentation: .init()
		)
	}

	public convenience init(geometry: Geometry) {
		self.init(
			geometry: geometry,
			workItemScheduler: Self.defaultWorkItemScheduler,
			sidebarPresentation: .init()
		)
	}

	public convenience init(workItemScheduler: @escaping WorkItemScheduler) {
		self.init(
			geometry: Geometry(),
			workItemScheduler: workItemScheduler,
			sidebarPresentation: .init()
		)
	}

	public static let defaultWorkItemScheduler: WorkItemScheduler = { delay, action in
		let workItem = DispatchWorkItem(block: action)
		DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
		return {
			workItem.cancel()
		}
	}

	public var dismissDistance: CGFloat {
		geometry.sidebarWidth + geometry.dismissBufferDistance
	}

	public func updateSidebarWidth(_ width: CGFloat) {
		geometry.sidebarWidth = width
	}

	public func handleMouseMovement(at point: CGPoint, in bounds: CGSize) {
		guard bounds.width > 0,
		      bounds.height > 0,
		      point.x >= -geometry.resizeRevealDistance,
		      point.y >= 0,
		      point.y <= bounds.height,
		      point.x <= bounds.width,
		      point.x.isFinite,
		      point.y.isFinite else { return }

		if isSidebarPresented {
			if point.x > dismissDistance {
				setSidebarPresented(false, animated: true)
			}
			cancelPendingSidebarOpen()
			return
		}

		if shouldOpenSidebar(from: point, in: bounds) {
			scheduleSidebarOpen()
		}
		else {
			cancelPendingSidebarOpen()
		}
	}

	public func cancelPendingSidebarOpen() {
		cancelPendingSidebarOpenWorkItem?()
		cancelPendingSidebarOpenWorkItem = nil
		hasPendingSidebarOpen = false
	}

	private func scheduleSidebarOpen() {
		guard cancelPendingSidebarOpenWorkItem == nil else { return }
		hasPendingSidebarOpen = true
		cancelPendingSidebarOpenWorkItem = workItemScheduler(geometry.sidebarRevealDelay) { [weak self] in
			guard let self else { return }
			self.setSidebarPresented(true, animated: true)
			self.cancelPendingSidebarOpenWorkItem = nil
			self.hasPendingSidebarOpen = false
		}
	}

	private func setSidebarPresented(_ present: Bool, animated: Bool) {
		guard present != sidebarPresentation.isPresented else { return }
		if !present {
			cancelPendingSidebarOpen()
		}
		sidebarPresentation.isPresented = present
		onPresentationChange?(present, animated)
	}

	private func shouldOpenSidebar(from point: CGPoint, in bounds: CGSize) -> Bool {
		(point.x <= geometry.openTriggerDistance)
			|| isWithinLeftResizeHandle(from: point, in: bounds)
	}

	private func isWithinLeftResizeHandle(from point: CGPoint, in bounds: CGSize) -> Bool {
		point.x >= -geometry.resizeRevealDistance
			&& point.x <= geometry.resizeRevealDistance
			&& bounds.height >= 0
	}
}
