import CoreFoundation
import Foundation
@testable import TrackpadGestures
import XCTest

final class MultitouchBridgeRuntimeTests: XCTestCase {
	func testDynamicLibraryClientLiveCanOpenResolveAndCloseKnownLibrary() throws {
		let handle = try XCTUnwrap(DynamicLibraryClient.live.open("/usr/lib/libSystem.B.dylib"))
		let symbol = DynamicLibraryClient.live.symbol(handle, "printf")

		XCTAssertNotNil(symbol)

		DynamicLibraryClient.live.close(handle)
	}

	func testDynamicLibraryClientNoopReturnsNilAndCloseDoesNothing() throws {
		XCTAssertNil(DynamicLibraryClient.noop.open("/tmp/missing"))
		XCTAssertNil(
			try DynamicLibraryClient.noop.symbol(
				XCTUnwrap(UnsafeMutableRawPointer(bitPattern: 0x1234)),
				"missing"
			)
		)
		try DynamicLibraryClient.noop.close(XCTUnwrap(UnsafeMutableRawPointer(bitPattern: 0x1234)))
	}

	func testParseTouchContactsReturnsEmptyWhenLayoutUnsupported() {
		let contacts = [makeContact(identifier: 1, state: 1)]
		let parsedContacts: [TouchContact] = contacts.withUnsafeBufferPointer { buffer in
			parseTouchContacts(
				pointer: UnsafeRawPointer(buffer.baseAddress),
				count: Int32(buffer.count),
				maxContactCount: 32,
				layoutSupported: false,
				unsupportedLayoutHandler: { _ in }
			)
		}

		XCTAssertEqual(parsedContacts, [])
	}

	func testReportUnsupportedTouchLayoutIsCallable() {
		reportUnsupportedTouchLayout("Unsupported MTTouchContactRecord layout")
	}

	func testLoaderBuildsFrameworkAndReportsExpectedDiagnostics() {
		let recorder = SymbolCallRecorder()
		let loader = MultitouchBridgeLoader(
			frameworkCandidates: ["/tmp/framework"],
			dynamicLibraryClient: DynamicLibraryClient(
				open: { _ in
					UnsafeMutableRawPointer(bitPattern: 0x1234)
				},
				symbol: { _, name in
					switch name {
					case "MTDeviceCreateList":
						recorder.log("symbol:\(name)")
						return unsafeBitCast(testMTDeviceCreateList as MTDeviceCreateListFunction, to: UnsafeRawPointer.self)
					case "MTRegisterContactFrameCallback":
						recorder.log("symbol:\(name)")
						return unsafeBitCast(
							testMTRegisterContactFrameCallback as MTRegisterContactFrameCallbackFunction,
							to: UnsafeRawPointer.self
						)
					case "MTUnregisterContactFrameCallback":
						recorder.log("symbol:\(name)")
						return unsafeBitCast(
							testMTUnregisterContactFrameCallback as MTUnregisterContactFrameCallbackFunction,
							to: UnsafeRawPointer.self
						)
					case "MTDeviceStart":
						recorder.log("symbol:\(name)")
						return unsafeBitCast(
							testMTDeviceStart as MTDeviceStartFunction,
							to: UnsafeRawPointer.self
						)
					case "MTDeviceStop":
						recorder.log("symbol:\(name)")
						return unsafeBitCast(
							testMTDeviceStop as MTDeviceStopFunction,
							to: UnsafeRawPointer.self
						)
					case "MTDeviceRelease":
						recorder.log("symbol:\(name)")
						return unsafeBitCast(
							testMTDeviceRelease as MTDeviceReleaseFunction,
							to: UnsafeRawPointer.self
						)
					default:
						return nil
					}
				},
				close: { _ in }
			)
		)
		var diagnostics = [GestureDiagnosticEvent.Kind]()

		let result = loader.load { diagnostics.append($0) }

		switch result {
		case .failure(let error):
			XCTFail("expected success, got \(error)")
		case .success:
			break
		}

		XCTAssertTrue(diagnostics.contains(.frameworkOpenAttempt("/tmp/framework")))
		XCTAssertTrue(diagnostics.contains(.frameworkOpened("/tmp/framework")))
		XCTAssertTrue(diagnostics.contains(.frameworkReady("/tmp/framework")))
		XCTAssertTrue(diagnostics.contains(.symbolResolved("MTDeviceCreateList")))
		XCTAssertTrue(diagnostics.contains(.symbolResolved("MTRegisterContactFrameCallback")))
		XCTAssertTrue(diagnostics.contains(.symbolResolved("MTUnregisterContactFrameCallback")))
		XCTAssertTrue(diagnostics.contains(.symbolResolved("MTDeviceStart")))
		XCTAssertTrue(diagnostics.contains(.symbolResolved("MTDeviceStop")))
		XCTAssertTrue(diagnostics.contains(.symbolResolved("MTDeviceRelease")))
	}

	func testLoaderBuiltFrameworkExecutesResolvedSymbols() throws {
		let calls = CallOrderRecorder()
		let loader = MultitouchBridgeLoader(
			frameworkCandidates: ["/tmp/framework"],
			dynamicLibraryClient: DynamicLibraryClient(
				open: { _ in UnsafeMutableRawPointer(bitPattern: 0x1234) },
				symbol: { _, name in
					switch name {
					case "MTDeviceCreateList":
						return unsafeBitCast(executingMTDeviceCreateList, to: UnsafeRawPointer.self)
					case "MTRegisterContactFrameCallback":
						return unsafeBitCast(executingMTRegisterContactFrameCallback, to: UnsafeRawPointer.self)
					case "MTUnregisterContactFrameCallback":
						return unsafeBitCast(executingMTUnregisterContactFrameCallback, to: UnsafeRawPointer.self)
					case "MTDeviceStart":
						return unsafeBitCast(executingMTDeviceStart, to: UnsafeRawPointer.self)
					case "MTDeviceStop":
						return unsafeBitCast(executingMTDeviceStop, to: UnsafeRawPointer.self)
					case "MTDeviceRelease":
						return unsafeBitCast(executingMTDeviceRelease, to: UnsafeRawPointer.self)
					default:
						return nil
					}
				},
				close: { _ in }
			)
		)

		ExecutingSymbolFixtures.reset(callRecorder: calls)
		let framework: LoadedMultitouchFramework
		switch loader.load(emitDiagnostic: { _ in }) {
		case let .success(loadedFramework):
			framework = loadedFramework
		case let .failure(error):
			XCTFail("Unexpected loader failure: \(error)")
			return
		}
		let device = try XCTUnwrap(MTDeviceRef(bitPattern: 0x70))
		let discovered = try framework.createDeviceList()
		let session = try framework.makeSession(
			device: device,
			deviceLifetimeAnchor: discovered,
			frameHandler: { _ in },
			emitDiagnostic: { _ in }
		)

		try session.registerCallback()
		try session.start()
		session.shutdown()

		XCTAssertEqual(
			calls.calls,
			["createDeviceList", "register", "start", "unregister", "stop"]
		)
	}

	func testSessionLifecycleShutdownIsIdempotentAndReleaseAfterQuiescence() throws {
		let callOrder = CallOrderRecorder()
		let recorder = SymbolCallRecorder()
		let closeCounter = CloseCounter()
		let framework = try LoadedMultitouchFramework(
			handle: XCTUnwrap(UnsafeMutableRawPointer(bitPattern: 0x1234)),
			path: "/tmp/fake",
			symbols: MultitouchSymbolTable(
				createDeviceList: { nil },
				registerCallback: { _, _ in
					callOrder.log("register")
				},
				unregisterCallback: { _, _ in
					callOrder.log("unregister")
				},
				startDevice: { _, _ in
					callOrder.log("start")
				},
				stopDevice: { _ in
					callOrder.log("stop")
				},
				releaseDevice: { _ in
					callOrder.log("release")
				}
			),
			dynamicLibraryClient: DynamicLibraryClient(
				open: { _ in nil },
				symbol: { _, _ in nil },
				close: { _ in
					closeCounter.count += 1
				}
			),
			unloadPolicy: .explicitClose,
			emitDiagnostic: { _ in }
		)

		let device = MTDeviceRef(bitPattern: 0x88)
		let session = try framework.makeSession(
			device: XCTUnwrap(device),
			deviceLifetimeAnchor: MultitouchDiscoveredDevices(backingArray: [] as CFArray, devices: [XCTUnwrap(device)]),
			frameHandler: { _ in },
			emitDiagnostic: { _ in
				recorder.log("diagnostic")
			}
		)
		try session.registerCallback()
		try session.start()

		session.shutdown()
		session.shutdown()

		XCTAssertEqual(callOrder.calls, ["register", "start", "unregister", "stop", "release"])
		XCTAssertEqual(closeCounter.count, 0)
		framework.closeIfPermitted()
		XCTAssertEqual(closeCounter.count, 1)
		framework.closeIfPermitted()
		XCTAssertEqual(closeCounter.count, 1)
	}

	func testCallbackTrampolineEmitsIgnoredCallbackWhenContextIsStopping() throws {
		let recorder = DiagnosticRecorder()
		let deviceBox = DeviceBox()
		let framework = LoadedMultitouchFramework.forTest(
			symbols: MultitouchSymbolTable(
				createDeviceList: { nil },
				registerCallback: { _, _ in },
				unregisterCallback: { _, _ in
					_ = invokeMultitouchContactFrameCallbackForTesting(
						device: deviceBox.device,
						contacts: nil,
						contactCount: 0,
						timestamp: 9
					)
				},
				startDevice: { _, _ in },
				stopDevice: { _ in },
				releaseDevice: { _ in }
			),
			emitDiagnostic: recorder.record
		)
		let device = try XCTUnwrap(MTDeviceRef(bitPattern: 0x4A))
		deviceBox.device = device
		let session = try framework.makeSession(
			device: device,
			deviceLifetimeAnchor: MultitouchDiscoveredDevices(backingArray: [] as CFArray, devices: [device]),
			frameHandler: { _ in },
			emitDiagnostic: recorder.record
		)

		try session.registerCallback()
		try session.start()
		session.shutdown()

		XCTAssertTrue(recorder.kinds.contains(where: {
			if case .callbackIgnoredWhileStopping = $0 { return true }
			return false
		}))
	}

	func testSessionEmitsCallbackInFlightDiagnosticWhenSnapshotExceedsOne() throws {
		let recorder = DiagnosticRecorder()
		let framework = LoadedMultitouchFramework.forTest(
			symbols: MultitouchSymbolTable(
				createDeviceList: { nil },
				registerCallback: { _, _ in },
				unregisterCallback: { _, _ in },
				startDevice: { _, _ in },
				stopDevice: { _ in },
				releaseDevice: { _ in }
			),
			emitDiagnostic: recorder.record
		)
		let device = try XCTUnwrap(MTDeviceRef(bitPattern: 0x4B))
		let session = try framework.makeSession(
			device: device,
			deviceLifetimeAnchor: MultitouchDiscoveredDevices(backingArray: [] as CFArray, devices: [device]),
			frameHandler: { _ in },
			emitDiagnostic: recorder.record
		)
		try session.registerCallback()
		XCTAssertFalse(session.beginCallbackForTesting())
		XCTAssertFalse(session.beginCallbackForTesting())
		session.emitCallbackMetricsForTesting()
		session.endCallbackForTesting()
		session.endCallbackForTesting()
		session.shutdown()

		XCTAssertTrue(recorder.kinds.contains(where: {
			if case let .callbackInFlightState(_, _, inFlightCount) = $0 {
				return inFlightCount == 2
			}
			return false
		}))
	}

	func testFrameworkCreateDeviceListConvertsRetainedArrayAndKeepLoadedSkipsClose() throws {
		let closeCounter = CloseCounter()
		let deviceA = try UInt(bitPattern: XCTUnwrap(MTDeviceRef(bitPattern: 0x11)))
		let deviceB = try UInt(bitPattern: XCTUnwrap(MTDeviceRef(bitPattern: 0x22)))
		let framework = try LoadedMultitouchFramework(
			handle: XCTUnwrap(UnsafeMutableRawPointer(bitPattern: 0x1235)),
			path: "/tmp/fake",
			symbols: MultitouchSymbolTable(
				createDeviceList: {
					var values: [UnsafeRawPointer?] = [
						UnsafeRawPointer(bitPattern: deviceA),
						UnsafeRawPointer(bitPattern: deviceB),
					]
					let cfArray = CFArrayCreate(nil, &values, values.count, nil)!
					return Unmanaged.passRetained(cfArray)
				},
				registerCallback: { _, _ in },
				unregisterCallback: { _, _ in },
				startDevice: { _, _ in },
				stopDevice: { _ in },
				releaseDevice: { _ in }
			),
			dynamicLibraryClient: DynamicLibraryClient(
				open: { _ in nil },
				symbol: { _, _ in nil },
				close: { _ in
					closeCounter.count += 1
				}
			),
			unloadPolicy: .keepLoaded,
			emitDiagnostic: { _ in }
		)

		let devices = try framework.createDeviceList()
		XCTAssertEqual(devices.devices.map(UInt.init(bitPattern:)), [deviceA, deviceB])

		framework.closeIfPermitted()
		XCTAssertEqual(closeCounter.count, 0)
	}

	func testFrameworkCreateDeviceListHandlesNilAndSparseArrays() throws {
		let sparseArrayFramework = LoadedMultitouchFramework.forTest(
			symbols: MultitouchSymbolTable(
				createDeviceList: {
					var values: [UnsafeRawPointer?] = [
						UnsafeRawPointer(bitPattern: 0x11),
						nil,
						UnsafeRawPointer(bitPattern: 0x22),
					]
					let array = CFArrayCreate(nil, &values, values.count, nil)!
					return Unmanaged.passRetained(array)
				},
				registerCallback: { _, _ in },
				unregisterCallback: { _, _ in },
				startDevice: { _, _ in },
				stopDevice: { _ in },
				releaseDevice: { _ in }
			)
		)
		let emptyFramework = LoadedMultitouchFramework.forTest(
			symbols: MultitouchSymbolTable(
				createDeviceList: { nil },
				registerCallback: { _, _ in },
				unregisterCallback: { _, _ in },
				startDevice: { _, _ in },
				stopDevice: { _ in },
				releaseDevice: { _ in }
			)
		)

		let sparseDevices = try sparseArrayFramework.createDeviceList()
		let emptyDevices = try emptyFramework.createDeviceList()

		XCTAssertEqual(sparseDevices.devices.map(UInt.init(bitPattern:)), [0x11, 0x22])
		XCTAssertTrue(emptyDevices.devices.isEmpty)
	}

	func testSessionRejectsInvalidStateTransitionsAndCallbackTrampolineDeliversFrames() throws {
		let recorder = DiagnosticRecorder()
		let delivery = FrameDeliveryRecorder()
		let delivered = expectation(description: "frame delivered")
		delivery.onRecord = {
			delivered.fulfill()
		}
		let framework = try LoadedMultitouchFramework(
			handle: XCTUnwrap(UnsafeMutableRawPointer(bitPattern: 0x1236)),
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
			unloadPolicy: .keepLoaded,
			emitDiagnostic: recorder.record
		)
		let device = try XCTUnwrap(MTDeviceRef(bitPattern: 0x33))
		let invalidSession = try framework.makeSession(
			device: XCTUnwrap(MTDeviceRef(bitPattern: 0x34)),
			deviceLifetimeAnchor: MultitouchDiscoveredDevices(
				backingArray: [] as CFArray,
				devices: [XCTUnwrap(MTDeviceRef(bitPattern: 0x34))]
			),
			frameHandler: delivery.record,
			emitDiagnostic: recorder.record
		)

		XCTAssertThrowsError(try invalidSession.start())

		let duplicateRegisterSession = try framework.makeSession(
			device: XCTUnwrap(MTDeviceRef(bitPattern: 0x35)),
			deviceLifetimeAnchor: MultitouchDiscoveredDevices(
				backingArray: [] as CFArray,
				devices: [XCTUnwrap(MTDeviceRef(bitPattern: 0x35))]
			),
			frameHandler: delivery.record,
			emitDiagnostic: recorder.record
		)
		try duplicateRegisterSession.registerCallback()
		XCTAssertThrowsError(try duplicateRegisterSession.registerCallback())

		let session = try framework.makeSession(
			device: device,
			deviceLifetimeAnchor: MultitouchDiscoveredDevices(backingArray: [] as CFArray, devices: [device]),
			frameHandler: delivery.record,
			emitDiagnostic: recorder.record
		)
		try session.registerCallback()
		try session.start()

		let contacts = [makeContact(identifier: 7, state: 1)]
		contacts.withUnsafeBufferPointer { buffer in
			_ = invokeMultitouchContactFrameCallbackForTesting(
				device: device,
				contacts: UnsafeRawPointer(buffer.baseAddress),
				contactCount: Int32(buffer.count),
				timestamp: 4.5
			)
		}

		wait(for: [delivered], timeout: 1)
		XCTAssertEqual(delivery.frames.count, 1)
		XCTAssertEqual(delivery.frames.first?.contacts.first?.identifier, 7)
	}

	func testCallbackTrampolineIgnoresMissingDeviceAndUnknownContext() {
		let deviceWithoutContext = MTDeviceRef(bitPattern: 0x4040)

		XCTAssertEqual(
			invokeMultitouchContactFrameCallbackForTesting(
				device: nil,
				contacts: nil,
				contactCount: 0,
				timestamp: 1
			),
			0
		)
		XCTAssertEqual(
			invokeMultitouchContactFrameCallbackForTesting(
				device: deviceWithoutContext,
				contacts: nil,
				contactCount: 0,
				timestamp: 1
			),
			0
		)
	}

	func testCallbackTrampolineEmitsIgnoredCallbackBeforeSessionStart() throws {
		let recorder = DiagnosticRecorder()
		let framework = LoadedMultitouchFramework.forTest(
			symbols: MultitouchSymbolTable(
				createDeviceList: { nil },
				registerCallback: { _, _ in },
				unregisterCallback: { _, _ in },
				startDevice: { _, _ in },
				stopDevice: { _ in },
				releaseDevice: { _ in }
			),
			emitDiagnostic: recorder.record
		)
		let device = try XCTUnwrap(MTDeviceRef(bitPattern: 0x46))
		let session = try framework.makeSession(
			device: device,
			deviceLifetimeAnchor: MultitouchDiscoveredDevices(backingArray: [] as CFArray, devices: [device]),
			frameHandler: { _ in },
			emitDiagnostic: recorder.record
		)

		try session.registerCallback()
		_ = invokeMultitouchContactFrameCallbackForTesting(
			device: device,
			contacts: nil,
			contactCount: 0,
			timestamp: 7
		)

		XCTAssertTrue(recorder.kinds.contains(where: {
			if case .callbackIgnoredWhileStopping = $0 { return true }
			return false
		}))
	}

	func testSessionShutdownFromCreatedAndCallbackRegisteredStatesIsSafe() throws {
		let recorder = CallOrderRecorder()
		let framework = try LoadedMultitouchFramework(
			handle: XCTUnwrap(UnsafeMutableRawPointer(bitPattern: 0x1237)),
			path: "/tmp/fake",
			symbols: MultitouchSymbolTable(
				createDeviceList: { nil },
				registerCallback: { _, _ in recorder.log("register") },
				unregisterCallback: { _, _ in recorder.log("unregister") },
				startDevice: { _, _ in recorder.log("start") },
				stopDevice: { _ in recorder.log("stop") },
				releaseDevice: { _ in recorder.log("release") }
			),
			dynamicLibraryClient: DynamicLibraryClient(
				open: { _ in nil },
				symbol: { _, _ in nil },
				close: { _ in }
			),
			unloadPolicy: .keepLoaded,
			emitDiagnostic: { _ in }
		)

		let createdSession = try framework.makeSession(
			device: XCTUnwrap(MTDeviceRef(bitPattern: 0x44)),
			deviceLifetimeAnchor: MultitouchDiscoveredDevices(
				backingArray: [] as CFArray,
				devices: [XCTUnwrap(MTDeviceRef(bitPattern: 0x44))]
			),
			frameHandler: { _ in },
			emitDiagnostic: { _ in }
		)
		createdSession.shutdown()

		let registeredSession = try framework.makeSession(
			device: XCTUnwrap(MTDeviceRef(bitPattern: 0x45)),
			deviceLifetimeAnchor: MultitouchDiscoveredDevices(
				backingArray: [] as CFArray,
				devices: [XCTUnwrap(MTDeviceRef(bitPattern: 0x45))]
			),
			frameHandler: { _ in },
			emitDiagnostic: { _ in }
		)
		try registeredSession.registerCallback()
		registeredSession.shutdown()

		XCTAssertEqual(recorder.calls, ["register", "unregister", "release"])
	}

	func testSessionShutdownWaitsForMaxQuiescenceAndAppliesPostDrainDelay() throws {
		let recorder = DiagnosticRecorder()
		let delivery = FrameDeliveryRecorder()
		let framework = LoadedMultitouchFramework.forTest(
			symbols: MultitouchSymbolTable(
				createDeviceList: { nil },
				registerCallback: { _, _ in },
				unregisterCallback: { _, _ in },
				startDevice: { _, _ in },
				stopDevice: { _ in },
				releaseDevice: { _ in }
			),
			emitDiagnostic: recorder.record
		)
		let device = try XCTUnwrap(MTDeviceRef(bitPattern: 0x47))
		let session = try framework.makeSession(
			device: device,
			deviceLifetimeAnchor: MultitouchDiscoveredDevices(backingArray: [] as CFArray, devices: [device]),
			frameHandler: delivery.record,
			emitDiagnostic: recorder.record,
			quietPeriod: 0.05,
			maxQuiescence: 0.001,
			postDrainDelay: 0.001
		)

		try session.registerCallback()
		try session.start()
		let contacts = [makeContact(identifier: 8, state: 1)]
		contacts.withUnsafeBufferPointer { buffer in
			_ = invokeMultitouchContactFrameCallbackForTesting(
				device: device,
				contacts: UnsafeRawPointer(buffer.baseAddress),
				contactCount: Int32(buffer.count),
				timestamp: 5
			)
		}

		session.shutdown()
		delivery.flush()

		XCTAssertTrue(recorder.kinds.contains(where: {
			if case .shutdownQuiescenceWaiting = $0 { return true }
			return false
		}))
		XCTAssertTrue(recorder.kinds.contains(where: {
			if case .shutdownQuiescenceComplete = $0 { return true }
			return false
		}))
	}
}

private final class CloseCounter: @unchecked Sendable {
	var count = 0
}

private final class CallOrderRecorder: @unchecked Sendable {
	var calls = [String]()
	func log(_ value: String) {
		calls.append(value)
	}
}

private final class SymbolCallRecorder: @unchecked Sendable {
	var calls = [String]()
	func log(_ value: String) {
		calls.append(value)
	}
}

private final class DiagnosticRecorder: @unchecked Sendable {
	var kinds = [GestureDiagnosticEvent.Kind]()
	func record(_ kind: GestureDiagnosticEvent.Kind) {
		kinds.append(kind)
	}
}

private final class DeviceBox: @unchecked Sendable {
	var device: MTDeviceRef?
}

private final class FrameDeliveryRecorder: @unchecked Sendable {
	var frames = [TouchFrame]()
	private let queue = DispatchQueue(label: "FrameDeliveryRecorder")
	var onRecord: (() -> Void)?

	func record(_ frame: TouchFrame) {
		queue.async {
			self.frames.append(frame)
			self.onRecord?()
		}
	}

	func flush() {
		queue.sync {}
	}
}

private let testMTDeviceCreateList: MTDeviceCreateListFunction = {
	nil
}

private let testMTRegisterContactFrameCallback: MTRegisterContactFrameCallbackFunction = { _, _ in
}

private let testMTUnregisterContactFrameCallback: MTUnregisterContactFrameCallbackFunction = { _, _ in
}

private let testMTDeviceStart: MTDeviceStartFunction = { _, _ in
}

private let testMTDeviceStop: MTDeviceStopFunction = { _ in
}

private let testMTDeviceRelease: MTDeviceReleaseFunction = { _ in
}

private let executingMTDeviceCreateList: MTDeviceCreateListFunction = {
	ExecutingSymbolFixtures.createDeviceList()
}

private let executingMTRegisterContactFrameCallback: MTRegisterContactFrameCallbackFunction = { _, _ in
	ExecutingSymbolFixtures.record("register")
}

private let executingMTUnregisterContactFrameCallback: MTUnregisterContactFrameCallbackFunction = { _, _ in
	ExecutingSymbolFixtures.record("unregister")
}

private let executingMTDeviceStart: MTDeviceStartFunction = { _, _ in
	ExecutingSymbolFixtures.record("start")
}

private let executingMTDeviceStop: MTDeviceStopFunction = { _ in
	ExecutingSymbolFixtures.record("stop")
}

private let executingMTDeviceRelease: MTDeviceReleaseFunction = { _ in
	ExecutingSymbolFixtures.record("release")
}

private enum ExecutingSymbolFixtures {
	private static let state = FixtureState()

	static func reset(callRecorder: CallOrderRecorder) {
		state.withLock {
			$0.callRecorder = callRecorder
		}
	}

	static func record(_ value: String) {
		let recorder = state.withLock { $0.callRecorder }
		recorder?.log(value)
	}

	static func createDeviceList() -> Unmanaged<CFArray>? {
		record("createDeviceList")
		var values: [UnsafeRawPointer?] = [UnsafeRawPointer(bitPattern: 0x70)]
		let array = CFArrayCreate(nil, &values, values.count, nil)!
		return Unmanaged.passRetained(array)
	}

	private final class FixtureState: @unchecked Sendable {
		private let lock = NSLock()
		var callRecorder: CallOrderRecorder?

		func withLock<T>(_ action: (FixtureState) -> T) -> T {
			lock.lock()
			defer { lock.unlock() }
			return action(self)
		}
	}
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
