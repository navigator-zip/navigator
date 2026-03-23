@testable import BrowserView
import Foundation
import XCTest

@MainActor
final class BrowserChromeViewModelTests: XCTestCase {
	func testMouseMovementNearLeftEdgeSchedulesOpen() {
		let scheduler = BrowserViewModelTestScheduler()
		let model = BrowserChromeViewModel(
			geometry: .init(),
			workItemScheduler: scheduler.schedule,
			sidebarPresentation: .init()
		)
		var presentationUpdates: [(Bool, Bool)] = []
		model.onPresentationChange = { isPresented, animated in
			presentationUpdates.append((isPresented, animated))
		}

		model.handleMouseMovement(at: CGPoint(x: 5, y: 100), in: CGSize(width: 1200, height: 800))

		XCTAssertTrue(scheduler.didScheduleWork)
		XCTAssertEqual(model.hasPendingSidebarOpen, true)
		XCTAssertTrue(presentationUpdates.isEmpty)
	}

	func testMouseMovementInResizeHandleSchedulesOpen() {
		let scheduler = BrowserViewModelTestScheduler()
		let model = BrowserChromeViewModel(
			geometry: .init(),
			workItemScheduler: scheduler.schedule,
			sidebarPresentation: .init()
		)

		model.handleMouseMovement(at: CGPoint(x: -5, y: 100), in: CGSize(width: 1200, height: 800))

		XCTAssertTrue(scheduler.didScheduleWork)
		XCTAssertTrue(model.hasPendingSidebarOpen)
	}

	func testMouseMovementOutsideBoundsDoesNotOpenSidebar() {
		let scheduler = BrowserViewModelTestScheduler()
		let model = BrowserChromeViewModel(
			geometry: .init(),
			workItemScheduler: scheduler.schedule,
			sidebarPresentation: .init()
		)

		model.handleMouseMovement(at: CGPoint(x: -100, y: 100), in: CGSize(width: 1200, height: 800))

		XCTAssertFalse(scheduler.didScheduleWork)
		XCTAssertFalse(model.hasPendingSidebarOpen)
	}

	func testMouseMovementLeavesOpenTriggerCancelsPendingOpen() {
		let scheduler = BrowserViewModelTestScheduler()
		let model = BrowserChromeViewModel(
			geometry: .init(),
			workItemScheduler: scheduler.schedule,
			sidebarPresentation: .init()
		)

		model.handleMouseMovement(at: CGPoint(x: 5, y: 100), in: CGSize(width: 1200, height: 800))
		model.handleMouseMovement(at: CGPoint(x: 50, y: 100), in: CGSize(width: 1200, height: 800))

		XCTAssertFalse(model.hasPendingSidebarOpen)
		XCTAssertNil(scheduler.lastWorkItem)
		XCTAssertEqual(scheduler.cancelInvocationCount, 1)
	}

	func testOpenTriggerEventuallyPresentsSidebar() {
		let scheduler = BrowserViewModelTestScheduler()
		let model = BrowserChromeViewModel(
			geometry: .init(),
			workItemScheduler: scheduler.schedule,
			sidebarPresentation: .init()
		)
		var presentationUpdates: [(Bool, Bool)] = []
		model.onPresentationChange = { isPresented, animated in
			presentationUpdates.append((isPresented, animated))
		}

		model.handleMouseMovement(at: CGPoint(x: 5, y: 100), in: CGSize(width: 1200, height: 800))
		XCTAssertEqual(scheduler.cancelInvocationCount, 0)
		XCTAssertEqual(presentationUpdates.count, 0)

		scheduler.runScheduledWork()

		XCTAssertEqual(model.isSidebarPresented, true)
		XCTAssertEqual(presentationUpdates.count, 1)
		XCTAssertEqual(presentationUpdates.first?.0, true)
		XCTAssertEqual(presentationUpdates.first?.1, true)
		XCTAssertFalse(model.hasPendingSidebarOpen)
		XCTAssertEqual(scheduler.cancelInvocationCount, 0)
	}

	func testPresentedSidebarClosesWhenCursorLeavesDismissDistance() {
		let scheduler = BrowserViewModelTestScheduler()
		let model = BrowserChromeViewModel(
			geometry: .init(),
			workItemScheduler: scheduler.schedule,
			sidebarPresentation: .init()
		)
		var presentationUpdates: [(Bool, Bool)] = []
		model.onPresentationChange = { isPresented, animated in
			presentationUpdates.append((isPresented, animated))
		}

		model.handleMouseMovement(at: CGPoint(x: 5, y: 100), in: CGSize(width: 1200, height: 800))
		scheduler.runScheduledWork()
		XCTAssertEqual(model.isSidebarPresented, true)

		model.handleMouseMovement(
			at: CGPoint(x: model.dismissDistance + 5, y: 100),
			in: CGSize(width: 1200, height: 800)
		)

		XCTAssertEqual(model.isSidebarPresented, false)
		XCTAssertEqual(presentationUpdates.last?.0, false)
		XCTAssertEqual(presentationUpdates.last?.1, true)
	}

	func testRevealDelayIsSetToZeroPointZeroFive() {
		let geometry = BrowserChromeViewModel.Geometry(sidebarRevealDelay: 0.05)
		XCTAssertEqual(geometry.sidebarRevealDelay, 0.05)
	}

	func testDismissDistanceReflectsConfiguredSidebarWidth() {
		let geometry = BrowserChromeViewModel.Geometry(sidebarWidth: 320, dismissBufferDistance: 12)
		let model = BrowserChromeViewModel(
			geometry: geometry,
			workItemScheduler: BrowserChromeViewModel.defaultWorkItemScheduler,
			sidebarPresentation: .init()
		)

		XCTAssertEqual(model.dismissDistance, 332)
	}

	func testUpdatingSidebarWidthRefreshesDismissDistanceAndCloseThreshold() {
		let scheduler = BrowserViewModelTestScheduler()
		let model = BrowserChromeViewModel(
			geometry: .init(sidebarWidth: 220, dismissBufferDistance: 45),
			workItemScheduler: scheduler.schedule,
			sidebarPresentation: .init()
		)

		model.handleMouseMovement(at: CGPoint(x: 1, y: 100), in: CGSize(width: 1200, height: 800))
		scheduler.runScheduledWork()
		XCTAssertTrue(model.isSidebarPresented)

		model.updateSidebarWidth(320)
		XCTAssertEqual(model.dismissDistance, 365)

		model.handleMouseMovement(at: CGPoint(x: 300, y: 100), in: CGSize(width: 1200, height: 800))
		XCTAssertTrue(model.isSidebarPresented)

		model.handleMouseMovement(at: CGPoint(x: 380, y: 100), in: CGSize(width: 1200, height: 800))
		XCTAssertFalse(model.isSidebarPresented)
	}

	func testConvenienceInitializersUseDefaultGeometryAndSchedulers() {
		let defaultModel = BrowserChromeViewModel()
		XCTAssertEqual(defaultModel.dismissDistance, 330)

		let geometryOnlyModel = BrowserChromeViewModel(
			geometry: .init(sidebarWidth: 320, dismissBufferDistance: 15),
			workItemScheduler: BrowserChromeViewModel.defaultWorkItemScheduler,
			sidebarPresentation: .init()
		)
		XCTAssertEqual(geometryOnlyModel.dismissDistance, 335)

		let scheduler = BrowserViewModelTestScheduler()
		let schedulerOnlyModel = BrowserChromeViewModel(workItemScheduler: scheduler.schedule)
		schedulerOnlyModel.handleMouseMovement(at: CGPoint(x: 5, y: 10), in: CGSize(width: 100, height: 100))
		XCTAssertTrue(scheduler.didScheduleWork)
	}

	func testDefaultWorkItemSchedulerRunsAndCancelsWork() {
		let runExpectation = expectation(description: "scheduled action runs")
		let cancelExpectation = expectation(description: "cancelled action does not run")
		cancelExpectation.isInverted = true

		_ = BrowserChromeViewModel.defaultWorkItemScheduler(0.01) {
			runExpectation.fulfill()
		}
		let cancel = BrowserChromeViewModel.defaultWorkItemScheduler(0.05) {
			cancelExpectation.fulfill()
		}
		cancel()

		wait(for: [runExpectation, cancelExpectation], timeout: 0.2)
	}

	func testRepeatedOpenTriggerDoesNotReschedulePendingOpen() {
		let scheduler = BrowserViewModelTestScheduler()
		let model = BrowserChromeViewModel(
			geometry: .init(),
			workItemScheduler: scheduler.schedule,
			sidebarPresentation: .init()
		)

		model.handleMouseMovement(at: CGPoint(x: 5, y: 100), in: CGSize(width: 1200, height: 800))
		model.handleMouseMovement(at: CGPoint(x: 5, y: 100), in: CGSize(width: 1200, height: 800))

		XCTAssertEqual(scheduler.scheduleInvocationCount, 1)
		XCTAssertTrue(model.hasPendingSidebarOpen)
	}

	func testPresentedSidebarStaysVisibleWithinDismissDistance() {
		let scheduler = BrowserViewModelTestScheduler()
		let model = BrowserChromeViewModel(
			geometry: .init(),
			workItemScheduler: scheduler.schedule,
			sidebarPresentation: .init()
		)

		model.handleMouseMovement(at: CGPoint(x: 5, y: 100), in: CGSize(width: 1200, height: 800))
		scheduler.runScheduledWork()
		model.handleMouseMovement(at: CGPoint(x: model.dismissDistance - 1, y: 100), in: CGSize(width: 1200, height: 800))

		XCTAssertTrue(model.isSidebarPresented)
	}

	func testMouseMovementIgnoresNonFinitePoints() {
		let scheduler = BrowserViewModelTestScheduler()
		let model = BrowserChromeViewModel(
			geometry: .init(),
			workItemScheduler: scheduler.schedule,
			sidebarPresentation: .init()
		)

		model.handleMouseMovement(
			at: CGPoint(x: CGFloat.nan, y: 10),
			in: CGSize(width: 100, height: 100)
		)
		model.handleMouseMovement(
			at: CGPoint(x: 10, y: CGFloat.infinity),
			in: CGSize(width: 100, height: 100)
		)

		XCTAssertFalse(scheduler.didScheduleWork)
		XCTAssertFalse(model.hasPendingSidebarOpen)
	}

	func testPresentedSidebarClosesWhenCursorMovesBeyondDismissDistance() {
		let scheduler = BrowserViewModelTestScheduler()
		let geometry = BrowserChromeViewModel.Geometry(sidebarWidth: 220, dismissBufferDistance: 45)
		let model = BrowserChromeViewModel(
			geometry: geometry,
			workItemScheduler: scheduler.schedule,
			sidebarPresentation: .init()
		)
		var presentationUpdates: [(Bool, Bool)] = []
		model.onPresentationChange = { isPresented, animated in
			presentationUpdates.append((isPresented, animated))
		}

		model.handleMouseMovement(at: CGPoint(x: 1, y: 100), in: CGSize(width: 1200, height: 800))
		scheduler.runScheduledWork()

		XCTAssertEqual(model.isSidebarPresented, true)
		XCTAssertEqual(model.dismissDistance, 265)

		model.handleMouseMovement(at: CGPoint(x: 300, y: 100), in: CGSize(width: 1200, height: 800))

		XCTAssertEqual(model.isSidebarPresented, false)
		XCTAssertEqual(presentationUpdates.count, 2)
		XCTAssertEqual(presentationUpdates.last?.0, false)
		XCTAssertEqual(presentationUpdates.last?.1, true)
	}

	func testRunningScheduledOpenTwiceDoesNotRepublishPresentation() {
		let scheduler = BrowserViewModelTestScheduler()
		let model = BrowserChromeViewModel(
			geometry: .init(),
			workItemScheduler: scheduler.schedule,
			sidebarPresentation: .init()
		)
		var presentationUpdates: [(Bool, Bool)] = []
		model.onPresentationChange = { isPresented, animated in
			presentationUpdates.append((isPresented, animated))
		}

		model.handleMouseMovement(at: CGPoint(x: 5, y: 100), in: CGSize(width: 1200, height: 800))
		scheduler.runScheduledWork()
		scheduler.runScheduledWork()

		XCTAssertEqual(presentationUpdates.count, 1)
		XCTAssertEqual(presentationUpdates.first?.0, true)
	}

	func testResizeHandlePathEvaluatesHeightCheckWhenOpenTriggerMisses() {
		let scheduler = BrowserViewModelTestScheduler()
		let model = BrowserChromeViewModel(
			geometry: .init(openTriggerDistance: 2, resizeRevealDistance: 10),
			workItemScheduler: scheduler.schedule,
			sidebarPresentation: .init()
		)

		model.handleMouseMovement(at: CGPoint(x: 5, y: 20), in: CGSize(width: 100, height: 60))

		XCTAssertTrue(scheduler.didScheduleWork)
	}

	func testScheduledOpenDoesNothingAfterModelDeallocation() {
		let scheduler = BrowserViewModelTestScheduler()
		weak var weakModel: BrowserChromeViewModel?

		do {
			let model = BrowserChromeViewModel(
				geometry: .init(),
				workItemScheduler: scheduler.schedule,
				sidebarPresentation: .init()
			)
			weakModel = model
			model.handleMouseMovement(at: CGPoint(x: 5, y: 100), in: CGSize(width: 1200, height: 800))
		}

		XCTAssertNil(weakModel)
		scheduler.runScheduledWork()
	}

	private final class BrowserViewModelTestScheduler {
		private(set) var didScheduleWork = false
		private(set) var cancelInvocationCount = 0
		private(set) var scheduleInvocationCount = 0
		private(set) var lastWorkItem: (() -> Void)?
		private var action: (() -> Void)?

		func schedule(delay: TimeInterval, action: @escaping () -> Void) -> () -> Void {
			didScheduleWork = true
			scheduleInvocationCount += 1
			self.action = action
			let workItem: () -> Void = { [weak self] in
				self?.action = nil
			}
			lastWorkItem = workItem
			return { [weak self] in
				self?.cancelInvocationCount += 1
				self?.action = nil
				self?.lastWorkItem = nil
			}
		}

		func runScheduledWork() {
			let action = action
			action?()
		}
	}
}
