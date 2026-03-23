import CoreFoundation
import Foundation
@testable import TrackpadGestures
import XCTest

final class TouchCaptureTests: XCTestCase {
	func testMultitouchCaptureSourceStartStopAndWakeRescanLifecycle() throws {
		let deviceManager = TestTrackpadDeviceManager(deviceCount: 2)
		let schedulerFactory = TestRescanSchedulerFactory()
		let wakeObserverFactory = TestWakeObserverFactory()
		let bridgeRecorder = BridgeRecorder()
		var diagnostics = [GestureDiagnosticEvent.Kind]()
		let source = MultitouchCaptureSource(
			bridge: makeBridge(recorder: bridgeRecorder),
			emitDiagnostic: { diagnostics.append($0) },
			deviceManager: deviceManager,
			rescanSchedulerFactory: schedulerFactory,
			wakeObserverFactory: wakeObserverFactory
		)

		let startInfo = try source.start { _ in }
		XCTAssertEqual(startInfo, .init(deviceCount: 2))
		XCTAssertEqual(deviceManager.registerCount, 1)
		XCTAssertEqual(schedulerFactory.scheduler?.startCount, 1)
		XCTAssertEqual(wakeObserverFactory.observer?.startCount, 1)
		XCTAssertTrue(diagnostics.contains(.deviceSelectionStrategy("allCompatibleDevices")))

		schedulerFactory.scheduler?.fire()
		waitUntil(timeout: 1) {
			deviceManager.registerCount == 2
		}
		XCTAssertEqual(deviceManager.registerCount, 2)

		wakeObserverFactory.observer?.triggerWake()
		waitUntil(timeout: 1) {
			deviceManager.registerCount == 3
		}
		XCTAssertEqual(deviceManager.registerCount, 3)
		XCTAssertTrue(diagnostics.contains(.wakeRescanTriggered))

		source.stop()
		XCTAssertEqual(deviceManager.stopAllCount, 1)
		XCTAssertEqual(schedulerFactory.scheduler?.stopCount, 1)
		XCTAssertEqual(wakeObserverFactory.observer?.stopCount, 1)
		XCTAssertEqual(bridgeRecorder.closeCount, 0)

		schedulerFactory.scheduler?.fire()
		wakeObserverFactory.observer?.triggerWake()
		XCTAssertEqual(deviceManager.registerCount, 3)
	}

	func testMultitouchCaptureSourceIgnoresStaleSchedulerAndWakeCallbacksAfterRestart() throws {
		let deviceManager = TestTrackpadDeviceManager(deviceCount: 1)
		let schedulerFactory = TestRescanSchedulerFactory()
		let wakeObserverFactory = TestWakeObserverFactory()
		let source = MultitouchCaptureSource(
			bridge: makeBridge(recorder: BridgeRecorder()),
			emitDiagnostic: { _ in },
			deviceManager: deviceManager,
			rescanSchedulerFactory: schedulerFactory,
			wakeObserverFactory: wakeObserverFactory
		)

		_ = try source.start { _ in }
		let firstScheduler = try XCTUnwrap(schedulerFactory.schedulers.first)
		let firstWakeObserver = try XCTUnwrap(wakeObserverFactory.observers.first)
		source.stop()

		_ = try source.start { _ in }
		XCTAssertEqual(deviceManager.registerCount, 2)

		firstScheduler.fire()
		firstWakeObserver.triggerWake()
		XCTAssertEqual(deviceManager.registerCount, 2)

		schedulerFactory.scheduler?.fire()
		waitUntil(timeout: 1) {
			deviceManager.registerCount == 3
		}
		XCTAssertEqual(deviceManager.registerCount, 3)
	}

	func testMultitouchCaptureSourceThrowsWhenNoTrackpadsAreAvailable() {
		let source = MultitouchCaptureSource(
			bridge: makeBridge(recorder: BridgeRecorder()),
			emitDiagnostic: { _ in },
			deviceManager: TestTrackpadDeviceManager(deviceCount: 0)
		)

		XCTAssertThrowsError(try source.start { _ in }) { error in
			XCTAssertEqual(error as? TouchCaptureError, .noTrackpads)
		}
	}

	func testTrackpadDeviceManagerMapsScanFailuresToRegistrationFailures() {
		let manager = TrackpadDeviceManager(
			bridge: makeBridge(recorder: BridgeRecorder()),
			emitDiagnostic: { _ in },
			deviceListProvider: {
				struct ScanFailure: Error {}
				throw ScanFailure()
			}
		)

		XCTAssertThrowsError(try manager.registerAvailableDevices(frameHandler: { _ in })) { error in
			guard case .registrationFailed = error as? TouchCaptureError else {
				return XCTFail("Expected registrationFailed")
			}
		}
	}

	func testTrackpadDeviceManagerMapsSessionCreationFailuresToRegistrationFailures() throws {
		let device = try XCTUnwrap(MTDeviceRef(bitPattern: 0x91))
		let framework = try LoadedMultitouchFramework(
			handle: XCTUnwrap(UnsafeMutableRawPointer(bitPattern: 0x4444)),
			path: "/tmp/fake",
			symbols: MultitouchSymbolTable(
				createDeviceList: { nil },
				registerCallback: { _, _ in },
				unregisterCallback: { _, _ in },
				startDevice: { _, _ in },
				stopDevice: { _ in },
				releaseDevice: { _ in }
			),
			dynamicLibraryClient: DynamicLibraryClient(
				open: { _ in nil },
				symbol: { _, _ in nil },
				close: { _ in }
			),
			unloadPolicy: .explicitClose,
			emitDiagnostic: { _ in }
		)
		framework.closeIfPermitted()
		let manager = TrackpadDeviceManager(
			bridge: framework,
			emitDiagnostic: { _ in },
			deviceListProvider: {
				MultitouchDiscoveredDevices(backingArray: [] as CFArray, devices: [device])
			}
		)

		XCTAssertThrowsError(try manager.registerAvailableDevices(frameHandler: { _ in })) { error in
			guard case .registrationFailed = error as? TouchCaptureError else {
				return XCTFail("Expected registrationFailed")
			}
		}
	}

	func testTrackpadDeviceManagerRegistersUnregistersAndStopsDevicesWithoutDuplicates() throws {
		let firstDevice = try XCTUnwrap(MTDeviceRef(bitPattern: 0x1))
		let secondDevice = try XCTUnwrap(MTDeviceRef(bitPattern: 0x2))
		let thirdDevice = try XCTUnwrap(MTDeviceRef(bitPattern: 0x3))
		let deviceListBox = DeviceListBox(deviceLists: [
			[firstDevice, secondDevice],
			[secondDevice, thirdDevice],
		])
		let recorder = BridgeRecorder()
		let manager = TrackpadDeviceManager(
			bridge: makeBridge(recorder: recorder),
			emitDiagnostic: { kind in
				if case let .deviceUnregistered(rawValue) = kind, let key = UInt(rawValue) {
					recorder.deviceUnregisteredKeys.append(key)
				}
			},
			deviceListProvider: {
				deviceListBox.next()
			}
		)

		XCTAssertEqual(try manager.registerAvailableDevices(frameHandler: { _ in }), 2)
		XCTAssertEqual(recorder.registeredDeviceKeys, [1, 2])
		XCTAssertEqual(recorder.startedDeviceKeys, [1, 2])

		XCTAssertEqual(try manager.registerAvailableDevices(frameHandler: { _ in }), 2)
		XCTAssertEqual(recorder.unregisteredDeviceKeys, [])
		XCTAssertEqual(recorder.stoppedDeviceKeys, [])
		XCTAssertEqual(recorder.releasedDeviceKeys, [])
		XCTAssertEqual(recorder.deviceUnregisteredKeys, [1])
		XCTAssertEqual(recorder.registeredDeviceKeys.sorted(), [1, 2, 3])
		XCTAssertEqual(recorder.startedDeviceKeys.sorted(), [1, 2, 3])

		manager.stopAll()
		XCTAssertEqual(recorder.unregisteredDeviceKeys.sorted(), [2, 3])
		XCTAssertEqual(recorder.stoppedDeviceKeys.sorted(), [2, 3])
		XCTAssertEqual(recorder.releasedDeviceKeys.sorted(), [2, 3])
		XCTAssertEqual(recorder.deviceUnregisteredKeys.sorted(), [1, 2, 3])
	}

	func testMultitouchCaptureSourceStopDuringRegistrationLeavesNoActiveSessions() {
		let deviceManager = BlockingTestTrackpadDeviceManager(deviceCount: 1)
		let source = MultitouchCaptureSource(
			bridge: makeBridge(recorder: BridgeRecorder()),
			emitDiagnostic: { _ in },
			deviceManager: deviceManager
		)

		let startThread = Thread {
			_ = try? source.start { _ in }
		}
		startThread.start()
		XCTAssertTrue(deviceManager.waitForRegistrationAttempt(timeout: 1))

		let stopThread = Thread {
			source.stop()
		}
		stopThread.start()
		deviceManager.allowRegistrationToFinish()

		while !startThread.isFinished || !stopThread.isFinished {
			RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
		}

		XCTAssertEqual(deviceManager.registerCount, 1)
		XCTAssertEqual(deviceManager.stopAllCount, 1)
		XCTAssertEqual(deviceManager.activeCount, 0)
	}

	func testTouchParsingCentralizedAndBoundsChecked() {
		let contacts = [
			makeContact(identifier: 1, state: 0),
			makeContact(identifier: 2, state: 1),
			makeContact(identifier: 3, state: 2),
			makeContact(identifier: 4, state: 3),
			makeContact(identifier: 5, state: 4),
			makeContact(identifier: 6, state: 99),
		]

		let parsedContacts: [TouchContact] = contacts.withUnsafeBufferPointer { buffer in
			parseTouchContacts(
				pointer: UnsafeRawPointer(buffer.baseAddress),
				count: Int32(buffer.count),
				unsupportedLayoutHandler: { _ in }
			)
		}
		XCTAssertEqual(parsedContacts.map(\.identifier), [1, 2, 3, 4, 5, 6])
		XCTAssertEqual(
			parsedContacts.map(\.phase),
			[.began, .moved, .stationary, .ended, .cancelled, .unknown]
		)

		XCTAssertEqual(parseTouchContacts(pointer: nil, count: 2, unsupportedLayoutHandler: { _ in }), [])
		XCTAssertEqual(
			parseTouchContacts(pointer: UnsafeRawPointer(bitPattern: 0x1), count: -1, unsupportedLayoutHandler: { _ in }),
			[]
		)
		XCTAssertEqual(
			parseTouchContacts(pointer: UnsafeRawPointer(bitPattern: 0x1), count: 0, unsupportedLayoutHandler: { _ in }),
			[]
		)
		let cappedContacts: [TouchContact] = contacts.withUnsafeBufferPointer { buffer in
			parseTouchContacts(
				pointer: UnsafeRawPointer(buffer.baseAddress),
				count: Int32(buffer.count),
				maxContactCount: 2,
				unsupportedLayoutHandler: { _ in }
			)
		}
		XCTAssertEqual(cappedContacts.count, 2)
	}

	@MainActor
	func testWorkspaceWakeObserverStartsReceivesWakeAndStops() async {
		let wakeReceived = expectation(description: "wake received")
		wakeReceived.expectedFulfillmentCount = 1
		let observer = WorkspaceWakeObserver {
			wakeReceived.fulfill()
		}

		observer.start()
		NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
		await fulfillment(of: [wakeReceived], timeout: 1)

		observer.stop()
		NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
		try? await Task.sleep(for: .milliseconds(50))
	}

	@MainActor
	func testWorkspaceWakeObserverStartIsIdempotent() async {
		let wakeReceived = expectation(description: "wake received once")
		wakeReceived.expectedFulfillmentCount = 1
		let observer = WorkspaceWakeObserver {
			wakeReceived.fulfill()
		}

		observer.start()
		observer.start()
		NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
		await fulfillment(of: [wakeReceived], timeout: 1)

		observer.stop()
	}

	func testDispatchRescanSchedulerTicksAndStops() async {
		let ticked = expectation(description: "scheduler ticked")
		let scheduler = DispatchRescanScheduler(
			queue: DispatchQueue(label: "TrackpadGesturesTests.DispatchRescanScheduler"),
			interval: .milliseconds(10)
		) {
			ticked.fulfill()
		}

		scheduler.start()
		await fulfillment(of: [ticked], timeout: 1)
		scheduler.stop()
	}

	func testDispatchRescanSchedulerStartIsIdempotent() async {
		let counter = TickCounter()
		let scheduler = DispatchRescanScheduler(
			queue: DispatchQueue(label: "TrackpadGesturesTests.DispatchRescanScheduler.Idempotent"),
			interval: .milliseconds(200)
		) {
			counter.increment()
		}

		scheduler.start()
		scheduler.start()
		try? await Task.sleep(for: .milliseconds(250))
		scheduler.stop()

		XCTAssertEqual(counter.value, 1)
	}

	func testLiveFactoriesCreateExpectedRuntimeTypes() {
		let wakeObserver = LiveWakeObserverFactory().makeObserver {}
		let rescanScheduler = LiveRescanSchedulerFactory(
			queue: DispatchQueue(label: "TrackpadGesturesTests.LiveFactories"),
			interval: .milliseconds(5)
		).makeScheduler {}

		XCTAssertTrue(wakeObserver is WorkspaceWakeObserver)
		XCTAssertTrue(rescanScheduler is DispatchRescanScheduler)
	}

	func testLiveTouchCaptureSourceFactoryReturnsMultitouchCaptureSourceOnSuccessfulLoad() throws {
		let factory = LiveTouchCaptureSourceFactory(
			bridgeLoader: successfulBridgeLoader()
		)

		let source = try factory.makeSource(emitDiagnostic: { _ in })

		XCTAssertTrue(source is MultitouchCaptureSource)
	}

	func testLiveTouchCaptureSourceFactoryMapsBridgeFailuresToFatalBridgeFailure() {
		let factory = LiveTouchCaptureSourceFactory(
			bridgeLoader: MultitouchBridgeLoader(
				frameworkCandidates: ["/tmp/does-not-exist"],
				dynamicLibraryClient: DynamicLibraryClient(
					open: { _ in nil },
					symbol: { _, _ in nil },
					close: { _ in }
				)
			)
		)

		XCTAssertThrowsError(try factory.makeSource(emitDiagnostic: { _ in })) { error in
			XCTAssertEqual(
				error as? TouchCaptureError,
				.fatalBridgeFailure("/tmp/does-not-exist")
			)
		}
	}

	func testMapBridgeLoadFailureToTouchCaptureErrorCoversFrameworkClosed() {
		XCTAssertEqual(
			mapBridgeLoadFailureToTouchCaptureError(.frameworkClosed),
			.fatalBridgeFailure("Multitouch framework closed")
		)
	}

	func testMultitouchCaptureSourceRestartWhileRunningStopsPreviousGeneration() throws {
		let deviceManager = TestTrackpadDeviceManager(deviceCount: 1)
		let source = MultitouchCaptureSource(
			bridge: makeBridge(recorder: BridgeRecorder()),
			emitDiagnostic: { _ in },
			deviceManager: deviceManager,
			rescanSchedulerFactory: TestRescanSchedulerFactory(),
			wakeObserverFactory: TestWakeObserverFactory()
		)

		_ = try source.start { _ in }
		_ = try source.start { _ in }

		XCTAssertEqual(deviceManager.registerCount, 2)
		XCTAssertEqual(deviceManager.stopAllCount, 1)
	}

	func testMultitouchCaptureSourceStopIsIdempotentWhenAlreadyStopped() throws {
		let deviceManager = TestTrackpadDeviceManager(deviceCount: 1)
		let source = MultitouchCaptureSource(
			bridge: makeBridge(recorder: BridgeRecorder()),
			emitDiagnostic: { _ in },
			deviceManager: deviceManager,
			rescanSchedulerFactory: TestRescanSchedulerFactory(),
			wakeObserverFactory: TestWakeObserverFactory()
		)

		source.stop()
		_ = try source.start { _ in }
		source.stop()
		source.stop()

		XCTAssertEqual(deviceManager.stopAllCount, 1)
	}

	func testMultitouchCaptureSourceUsesDefaultDeviceManagerWhenOneIsNotInjected() throws {
		let recorder = BridgeRecorder()
		let devices = try [XCTUnwrap(MTDeviceRef(bitPattern: 0x201))]
		let bridge = makeBridge(recorder: recorder, devices: devices)
		let source = MultitouchCaptureSource(
			bridge: bridge,
			emitDiagnostic: { _ in },
			rescanSchedulerFactory: TestRescanSchedulerFactory(),
			wakeObserverFactory: TestWakeObserverFactory()
		)

		let startInfo = try source.start { _ in }
		source.stop()

		XCTAssertEqual(startInfo.deviceCount, 1)
		XCTAssertEqual(recorder.registeredDeviceKeys, [UInt(bitPattern: devices[0])])
	}

	private func makeBridge(
		recorder: BridgeRecorder,
		devices: [MTDeviceRef] = [],
		unloadPolicy: MultitouchFrameworkUnloadPolicy = .keepLoaded
	) -> MultitouchBridge {
		let deviceAddresses = devices.map(UInt.init(bitPattern:))
		return MultitouchBridge.forTest(
			symbols: MultitouchSymbolTable(
				createDeviceList: {
					var values = deviceAddresses.map { UnsafeRawPointer(bitPattern: $0) }
					let backingArray = CFArrayCreate(nil, &values, values.count, nil) ?? ([] as CFArray)
					return Unmanaged.passRetained(backingArray)
				},
				registerCallback: { device, _ in
					recorder.recorded(device: device, in: &recorder.registeredDeviceKeys)
				},
				unregisterCallback: { device, _ in
					recorder.recorded(device: device, in: &recorder.unregisteredDeviceKeys)
				},
				startDevice: { device, _ in
					recorder.recorded(device: device, in: &recorder.startedDeviceKeys)
				},
				stopDevice: { device in
					recorder.recorded(device: device, in: &recorder.stoppedDeviceKeys)
				},
				releaseDevice: { device in
					recorder.recorded(device: device, in: &recorder.releasedDeviceKeys)
				}
			),
			dynamicLibraryClient: DynamicLibraryClient(
				open: { _ in nil },
				symbol: { _, _ in nil },
				close: { _ in
					recorder.closeCount += 1
				}
			),
			unloadPolicy: unloadPolicy
		)
	}

	private func successfulBridgeLoader() -> MultitouchBridgeLoader {
		MultitouchBridgeLoader(
			frameworkCandidates: ["/tmp/framework"],
			dynamicLibraryClient: DynamicLibraryClient(
				open: { _ in
					UnsafeMutableRawPointer(bitPattern: 0x1234)
				},
				symbol: { _, name in
					switch name {
					case "MTDeviceCreateList":
						return unsafeBitCast(
							touchCaptureTestMTDeviceCreateList as MTDeviceCreateListFunction,
							to: UnsafeRawPointer.self
						)
					case "MTRegisterContactFrameCallback":
						return unsafeBitCast(
							touchCaptureTestMTRegisterContactFrameCallback as MTRegisterContactFrameCallbackFunction,
							to: UnsafeRawPointer.self
						)
					case "MTUnregisterContactFrameCallback":
						return unsafeBitCast(
							touchCaptureTestMTUnregisterContactFrameCallback as MTUnregisterContactFrameCallbackFunction,
							to: UnsafeRawPointer.self
						)
					case "MTDeviceStart":
						return unsafeBitCast(
							touchCaptureTestMTDeviceStart as MTDeviceStartFunction,
							to: UnsafeRawPointer.self
						)
					case "MTDeviceStop":
						return unsafeBitCast(
							touchCaptureTestMTDeviceStop as MTDeviceStopFunction,
							to: UnsafeRawPointer.self
						)
					case "MTDeviceRelease":
						return unsafeBitCast(
							touchCaptureTestMTDeviceRelease as MTDeviceReleaseFunction,
							to: UnsafeRawPointer.self
						)
					default:
						return nil
					}
				},
				close: { _ in }
			)
		)
	}

	private func makeContact(identifier: Int32, state: Int32) -> MTTouchContactRecord {
		MTTouchContactRecord(
			frame: 0,
			timestamp: 0,
			identifier: identifier,
			state: state,
			unknown0: 0,
			unknown1: 0,
			normalizedPosition: .init(x: 0.5, y: 0.25),
			size: 0.75,
			unknown2: 0,
			angle: 1.25,
			majorAxis: 2.5,
			minorAxis: 1.5,
			velocity: .init(x: 0, y: 0),
			unknown3: 0,
			unknown4: 0,
			density: 0
		)
	}

	private func waitUntil(timeout: TimeInterval, condition: () -> Bool) {
		let deadline = Date(timeIntervalSinceNow: timeout)
		while !condition(), Date() < deadline {
			RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
		}
	}
}

private let touchCaptureTestMTDeviceCreateList: MTDeviceCreateListFunction = {
	nil
}

private let touchCaptureTestMTRegisterContactFrameCallback: MTRegisterContactFrameCallbackFunction = { _, _ in
}

private let touchCaptureTestMTUnregisterContactFrameCallback: MTUnregisterContactFrameCallbackFunction = { _, _ in
}

private let touchCaptureTestMTDeviceStart: MTDeviceStartFunction = { _, _ in
}

private let touchCaptureTestMTDeviceStop: MTDeviceStopFunction = { _ in
}

private let touchCaptureTestMTDeviceRelease: MTDeviceReleaseFunction = { _ in
}

private final class TestTrackpadDeviceManager: TrackpadDeviceManaging, @unchecked Sendable {
	private let deviceCount: Int
	private(set) var registerCount = 0
	private(set) var stopAllCount = 0

	init(deviceCount: Int) {
		self.deviceCount = deviceCount
	}

	func registerAvailableDevices(frameHandler _: @escaping @Sendable (TouchFrame) -> Void) throws -> Int {
		registerCount += 1
		return deviceCount
	}

	func stopAll() {
		stopAllCount += 1
	}
}

private final class BlockingTestTrackpadDeviceManager: TrackpadDeviceManaging, @unchecked Sendable {
	private let deviceCount: Int
	private let stateLock = NSLock()
	private let registerEntered = DispatchSemaphore(value: 0)
	private let registerRelease = DispatchSemaphore(value: 0)
	private(set) var registerCount = 0
	private(set) var stopAllCount = 0
	private(set) var activeCount = 0

	init(deviceCount: Int) {
		self.deviceCount = deviceCount
	}

	func registerAvailableDevices(frameHandler _: @escaping @Sendable (TouchFrame) -> Void) throws -> Int {
		stateLock.withLock {
			registerCount += 1
		}
		registerEntered.signal()
		_ = registerRelease.wait(timeout: .now() + 1)
		stateLock.withLock {
			activeCount = deviceCount
		}
		return deviceCount
	}

	func stopAll() {
		stateLock.withLock {
			stopAllCount += 1
			activeCount = 0
		}
	}

	func waitForRegistrationAttempt(timeout: TimeInterval) -> Bool {
		registerEntered.wait(timeout: .now() + timeout) == .success
	}

	func allowRegistrationToFinish() {
		registerRelease.signal()
	}
}

private final class TestRescanSchedulerFactory: RescanSchedulerFactory {
	var schedulers = [TestRescanScheduler]()
	var scheduler: TestRescanScheduler?

	func makeScheduler(onTick: @escaping () -> Void) -> any RescanScheduling {
		let scheduler = TestRescanScheduler(onTick: onTick)
		schedulers.append(scheduler)
		self.scheduler = scheduler
		return scheduler
	}
}

private final class TestRescanScheduler: RescanScheduling {
	private let onTick: () -> Void
	private(set) var startCount = 0
	private(set) var stopCount = 0

	init(onTick: @escaping () -> Void) {
		self.onTick = onTick
	}

	func start() {
		startCount += 1
	}

	func stop() {
		stopCount += 1
	}

	func fire() {
		onTick()
	}
}

private final class TestWakeObserverFactory: WakeObserverFactory {
	var observers = [TestWakeObserver]()
	var observer: TestWakeObserver?

	func makeObserver(onWake: @escaping () -> Void) -> any WakeObserving {
		let observer = TestWakeObserver(onWake: onWake)
		observers.append(observer)
		self.observer = observer
		return observer
	}
}

private final class TestWakeObserver: WakeObserving {
	private let onWake: () -> Void
	private(set) var startCount = 0
	private(set) var stopCount = 0

	init(onWake: @escaping () -> Void) {
		self.onWake = onWake
	}

	func start() {
		startCount += 1
	}

	func stop() {
		stopCount += 1
	}

	func triggerWake() {
		onWake()
	}
}

private final class DeviceListBox {
	private var deviceLists: [[MTDeviceRef]]

	init(deviceLists: [[MTDeviceRef]]) {
		self.deviceLists = deviceLists
	}

	func next() -> MultitouchDiscoveredDevices {
		if deviceLists.isEmpty {
			return MultitouchDiscoveredDevices(backingArray: [] as CFArray, devices: [])
		}
		let devices = deviceLists.removeFirst()
		var values = devices.map { Optional(UnsafeRawPointer($0)) }
		let backingArray = CFArrayCreate(nil, &values, values.count, nil) ?? ([] as CFArray)
		return MultitouchDiscoveredDevices(backingArray: backingArray, devices: devices)
	}
}

private final class TickCounter: @unchecked Sendable {
	private let lock = NSLock()
	private var tickCount = 0

	var value: Int {
		lock.withLock { tickCount }
	}

	func increment() {
		lock.withLock {
			tickCount += 1
		}
	}
}

private final class BridgeRecorder: @unchecked Sendable {
	var registeredDeviceKeys = [UInt]()
	var unregisteredDeviceKeys = [UInt]()
	var startedDeviceKeys = [UInt]()
	var stoppedDeviceKeys = [UInt]()
	var releasedDeviceKeys = [UInt]()
	var deviceUnregisteredKeys = [UInt]()
	var closeCount = 0

	func recorded(device: MTDeviceRef?, in collection: inout [UInt]) {
		guard let device else { return }
		collection.append(UInt(bitPattern: device))
	}
}
