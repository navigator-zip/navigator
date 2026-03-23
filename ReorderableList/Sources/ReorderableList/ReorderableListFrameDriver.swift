import Foundation

@MainActor
protocol ReorderFrameDriver {
	func start(callback: @escaping () -> Void)
	func stop()
}

@MainActor
final class ReorderTableFrameDriver: NSObject, ReorderFrameDriver {
	private let interval: TimeInterval
	private var timer: Timer?
	private var isRunning = false
	private var callback: (() -> Void)?

	init(interval: TimeInterval = 1 / 120) {
		self.interval = interval
	}

	func start(callback: @escaping () -> Void) {
		guard isRunning == false else { return }
		self.callback = callback
		timer = Timer(
			timeInterval: interval,
			target: self,
			selector: #selector(handleTimerTick),
			userInfo: nil,
			repeats: true
		)
		if let timer {
			RunLoop.main.add(timer, forMode: .common)
		}
		isRunning = true
	}

	func stop() {
		timer?.invalidate()
		timer = nil
		callback = nil
		isRunning = false
	}

	@objc
	private func handleTimerTick() {
		callback?()
	}
}
