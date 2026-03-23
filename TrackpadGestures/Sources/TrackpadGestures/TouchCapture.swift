import AppKit
import Foundation

struct TouchCaptureStartInfo: Equatable {
	let deviceCount: Int
}

enum TouchCaptureError: Error, Equatable {
	case noTrackpads
	case registrationFailed(String)
	case fatalBridgeFailure(String)
}

protocol TouchCaptureSource: AnyObject {
	func start(frameHandler: @escaping @Sendable (TouchFrame) -> Void) throws -> TouchCaptureStartInfo
	func stop()
}

protocol TouchCaptureSourceFactory {
	func makeSource(emitDiagnostic: @escaping (GestureDiagnosticEvent.Kind) -> Void) throws -> TouchCaptureSource
}

protocol WakeObserving: AnyObject {
	func start()
	func stop()
}

protocol WakeObserverFactory {
	func makeObserver(onWake: @escaping () -> Void) -> WakeObserving
}

protocol RescanScheduling: AnyObject {
	func start()
	func stop()
}

protocol RescanSchedulerFactory {
	func makeScheduler(onTick: @escaping () -> Void) -> RescanScheduling
}

protocol TrackpadDeviceManaging: AnyObject {
	func registerAvailableDevices(frameHandler: @escaping @Sendable (TouchFrame) -> Void) throws -> Int
	func stopAll()
}

private extension NSLock {
	@discardableResult
	func withLock<T>(_ action: () throws -> T) rethrows -> T {
		lock()
		defer { unlock() }
		return try action()
	}
}

struct LiveTouchCaptureSourceFactory: TouchCaptureSourceFactory {
	let bridgeLoader: MultitouchBridgeLoader

	func makeSource(emitDiagnostic: @escaping (GestureDiagnosticEvent.Kind) -> Void) throws -> TouchCaptureSource {
		switch bridgeLoader.load(emitDiagnostic: emitDiagnostic) {
		case let .success(bridge):
			return MultitouchCaptureSource(
				bridge: bridge,
				emitDiagnostic: emitDiagnostic
			)
		case let .failure(error):
			throw mapBridgeLoadFailureToTouchCaptureError(error)
		}
	}
}

func mapBridgeLoadFailureToTouchCaptureError(_ error: MultitouchBridgeLoadFailure) -> TouchCaptureError {
	switch error {
	case let .frameworkUnavailable(description), let .symbolMissing(description):
		.fatalBridgeFailure(description)
	case .frameworkClosed:
		.fatalBridgeFailure("Multitouch framework closed")
	}
}

struct LiveWakeObserverFactory: WakeObserverFactory {
	func makeObserver(onWake: @escaping () -> Void) -> WakeObserving {
		WorkspaceWakeObserver(onWake: onWake)
	}
}

struct LiveRescanSchedulerFactory: RescanSchedulerFactory {
	let queue: DispatchQueue
	let interval: DispatchTimeInterval

	init(
		queue: DispatchQueue = DispatchQueue(label: "TrackpadGestures.TouchCapture.Management"),
		interval: DispatchTimeInterval = .seconds(15)
	) {
		self.queue = queue
		self.interval = interval
	}

	func makeScheduler(onTick: @escaping () -> Void) -> RescanScheduling {
		DispatchRescanScheduler(queue: queue, interval: interval, onTick: onTick)
	}
}

final class WorkspaceWakeObserver: WakeObserving, @unchecked Sendable {
	private let onWake: () -> Void
	private let lock = NSLock()
	private var observer: NSObjectProtocol?

	init(onWake: @escaping () -> Void) {
		self.onWake = onWake
	}

	func start() {
		lock.withLock {
			guard observer == nil else { return }
			observer = NSWorkspace.shared.notificationCenter.addObserver(
				forName: NSWorkspace.didWakeNotification,
				object: nil,
				queue: .main
			) { [weak self] _ in
				self?.onWake()
			}
		}
	}

	func stop() {
		let existingObserver = lock.withLock { () -> NSObjectProtocol? in
			let current = observer
			observer = nil
			return current
		}

		if let existingObserver {
			NSWorkspace.shared.notificationCenter.removeObserver(existingObserver)
		}
	}

	deinit {
		stop()
	}
}

final class DispatchRescanScheduler: RescanScheduling, @unchecked Sendable {
	private let queue: DispatchQueue
	private let interval: DispatchTimeInterval
	private let onTick: () -> Void
	private let lock = NSLock()
	private var timer: DispatchSourceTimer?

	init(queue: DispatchQueue, interval: DispatchTimeInterval, onTick: @escaping () -> Void) {
		self.queue = queue
		self.interval = interval
		self.onTick = onTick
	}

	func start() {
		lock.withLock {
			guard timer == nil else { return }

			let timer = DispatchSource.makeTimerSource(queue: queue)
			timer.schedule(deadline: .now() + interval, repeating: interval)
			timer.setEventHandler(handler: onTick)
			self.timer = timer
			timer.resume()
		}
	}

	func stop() {
		let existingTimer = lock.withLock { () -> DispatchSourceTimer? in
			let current = timer
			timer = nil
			return current
		}

		existingTimer?.cancel()
	}

	deinit {
		stop()
	}
}

final class MultitouchCaptureSource: TouchCaptureSource, @unchecked Sendable {
	private enum State {
		case stopped
		case starting
		case running
		case stopping
	}

	fileprivate enum RescanTrigger {
		case timer
		case wake
	}

	private let bridge: MultitouchBridge
	fileprivate let emitDiagnostic: (GestureDiagnosticEvent.Kind) -> Void
	fileprivate let deviceManager: any TrackpadDeviceManaging
	private let rescanSchedulerFactory: RescanSchedulerFactory
	private let wakeObserverFactory: WakeObserverFactory
	private let managementQueue: DispatchQueue
	private var rescanScheduler: (any RescanScheduling)?
	private var wakeObserver: (any WakeObserving)?
	private var frameHandler: (@Sendable (TouchFrame) -> Void)?
	private var state: State = .stopped
	private var generation: UInt64 = 0
	private var rescanProxy: CaptureRescanProxy?

	init(
		bridge: MultitouchBridge,
		emitDiagnostic: @escaping (GestureDiagnosticEvent.Kind) -> Void,
		deviceManager: (any TrackpadDeviceManaging)? = nil,
		rescanSchedulerFactory: RescanSchedulerFactory = LiveRescanSchedulerFactory(),
		wakeObserverFactory: WakeObserverFactory = LiveWakeObserverFactory(),
		managementQueue: DispatchQueue = DispatchQueue(
			label: "TrackpadGestures.TouchCapture.SourceManagement",
			qos: .userInitiated
		)
	) {
		self.bridge = bridge
		self.emitDiagnostic = emitDiagnostic
		self.deviceManager = deviceManager ?? TrackpadDeviceManager(
			bridge: bridge,
			emitDiagnostic: emitDiagnostic
		)
		self.rescanSchedulerFactory = rescanSchedulerFactory
		self.wakeObserverFactory = wakeObserverFactory
		self.managementQueue = managementQueue
	}

	func start(frameHandler: @escaping @Sendable (TouchFrame) -> Void) throws -> TouchCaptureStartInfo {
		try managementQueue.sync {
			try startOnManagementQueue(frameHandler: frameHandler)
		}
	}

	func stop() {
		managementQueue.sync {
			stopOnManagementQueue()
		}
	}

	fileprivate func enqueueRescan(trigger: RescanTrigger, generation: UInt64) {
		managementQueue.async { [weak self] in
			self?.rescanOnManagementQueue(trigger: trigger, generation: generation)
		}
	}

	private func startOnManagementQueue(
		frameHandler: @escaping @Sendable (TouchFrame) -> Void
	) throws -> TouchCaptureStartInfo {
		if state != .stopped {
			stopOnManagementQueue()
		}

		state = .starting
		generation &+= 1
		let currentGeneration = generation

		do {
			let deviceCount = try deviceManager.registerAvailableDevices(frameHandler: frameHandler)
			guard deviceCount > 0 else {
				state = .stopped
				self.frameHandler = nil
				throw TouchCaptureError.noTrackpads
			}

			emitDiagnostic(.deviceSelectionStrategy("allCompatibleDevices"))

			let rescanProxy = CaptureRescanProxy(captureSource: self, generation: currentGeneration)
			let rescanScheduler = rescanSchedulerFactory.makeScheduler {
				rescanProxy.rescanIfNeeded()
			}
			let wakeObserver = wakeObserverFactory.makeObserver {
				rescanProxy.rescanAfterWake()
			}

			self.frameHandler = frameHandler
			self.rescanProxy = rescanProxy
			self.rescanScheduler = rescanScheduler
			self.wakeObserver = wakeObserver
			state = .running

			rescanScheduler.start()
			wakeObserver.start()

			return TouchCaptureStartInfo(deviceCount: deviceCount)
		}
		catch {
			state = .stopped
			self.frameHandler = nil
			rescanProxy = nil
			rescanScheduler = nil
			wakeObserver = nil
			deviceManager.stopAll()
			throw error
		}
	}

	private func stopOnManagementQueue() {
		guard state != .stopped else { return }

		state = .stopping
		generation &+= 1

		let scheduler = rescanScheduler
		let observer = wakeObserver

		rescanScheduler = nil
		wakeObserver = nil
		rescanProxy = nil
		frameHandler = nil

		scheduler?.stop()
		observer?.stop()
		deviceManager.stopAll()
		bridge.closeIfPermitted()

		state = .stopped
	}

	private func rescanOnManagementQueue(trigger: RescanTrigger, generation: UInt64) {
		guard self.generation == generation, state == .running, let frameHandler else {
			return
		}

		if trigger == .wake {
			emitDiagnostic(.wakeRescanTriggered)
		}

		_ = try? deviceManager.registerAvailableDevices(frameHandler: frameHandler)
	}
}

final class CaptureRescanProxy: @unchecked Sendable {
	private weak var captureSource: MultitouchCaptureSource?
	private let generation: UInt64

	init(captureSource: MultitouchCaptureSource, generation: UInt64) {
		self.captureSource = captureSource
		self.generation = generation
	}

	func rescanIfNeeded() {
		captureSource?.enqueueRescan(trigger: .timer, generation: generation)
	}

	func rescanAfterWake() {
		captureSource?.enqueueRescan(trigger: .wake, generation: generation)
	}
}

final class TrackpadDeviceManager: TrackpadDeviceManaging, @unchecked Sendable {
	private let bridge: MultitouchBridge
	private let emitDiagnostic: (GestureDiagnosticEvent.Kind) -> Void
	private let deviceListProvider: () throws -> MultitouchDiscoveredDevices
	private var activeDevices = [UInt: MultitouchDeviceSession]()

	init(
		bridge: MultitouchBridge,
		emitDiagnostic: @escaping (GestureDiagnosticEvent.Kind) -> Void,
		deviceListProvider: (() throws -> MultitouchDiscoveredDevices)? = nil
	) {
		self.bridge = bridge
		self.emitDiagnostic = emitDiagnostic
		self.deviceListProvider = deviceListProvider ?? {
			try bridge.createDeviceList()
		}
	}

	func registerAvailableDevices(frameHandler: @escaping @Sendable (TouchFrame) -> Void) throws -> Int {
		let discoveredDevices: MultitouchDiscoveredDevices
		do {
			discoveredDevices = try scanDevices()
		}
		catch {
			throw TouchCaptureError.registrationFailed(String(describing: error))
		}

		let discoveredByKey = Dictionary(uniqueKeysWithValues: discoveredDevices.devices.map { (deviceKey($0), $0) })
		let discoveredKeys = Set(discoveredByKey.keys)
		let activeKeys = Set(activeDevices.keys)
		let removedKeys = activeKeys.subtracting(discoveredKeys)
		let addedKeys = discoveredKeys.subtracting(activeKeys)

		for removedKey in removedKeys.sorted() {
			let session = activeDevices.removeValue(forKey: removedKey)!
			session.shutdown(mode: .deviceRemovedFromDiscovery)
			emitDiagnostic(.deviceUnregistered(String(removedKey)))
		}

		for key in addedKeys.sorted() {
			let device = discoveredByKey[key]!
			var createdSession: MultitouchDeviceSession?
			do {
				let session = try bridge.makeSession(
					device: device,
					deviceLifetimeAnchor: discoveredDevices,
					frameHandler: frameHandler,
					emitDiagnostic: emitDiagnostic
				)
				createdSession = session
				try session.registerCallback()
				try session.start()
				activeDevices[key] = session
				emitDiagnostic(.deviceRegistered(String(key)))
			}
			catch {
				createdSession?.shutdown()
				throw TouchCaptureError.registrationFailed(String(describing: error))
			}
		}

		return activeDevices.count
	}

	func stopAll() {
		let sessions = activeDevices.map { ($0.key, $0.value) }
		activeDevices.removeAll(keepingCapacity: false)

		for (key, session) in sessions {
			session.shutdown()
			emitDiagnostic(.deviceUnregistered(String(key)))
		}
	}

	private func scanDevices() throws -> MultitouchDiscoveredDevices {
		try deviceListProvider()
	}

	private func deviceKey(_ device: MTDeviceRef) -> UInt {
		UInt(bitPattern: device)
	}
}
