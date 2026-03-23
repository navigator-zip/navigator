import Foundation
@testable import TrackpadGestures
import XCTest

final class TrackpadGestureServiceTests: XCTestCase {
	func testPublicInitStartsInIdleState() async {
		let service = TrackpadGestureService()

		let state = await service.currentState()

		XCTAssertEqual(state, .idle)
	}

	func testSystemMonotonicNowReturnsPositiveUptime() {
		XCTAssertGreaterThan(systemMonotonicNow(), 0)
	}

	func testCapabilityReportsDegradedWhenPermissionsAreMissingButPolicyIsDiagnosticOnly() async {
		let service = makeService(
			permissionSnapshot: .init(accessibilityTrusted: false, inputMonitoringTrusted: false),
			backendFactory: ServiceTestBackendFactory(
				probeResult: .success(()),
				backend: ServiceTestBackend()
			)
		)

		let capability = await service.capability()

		XCTAssertEqual(
			capability,
			.degraded(
				TrackpadGestureCapabilityDetails(
					permissionStatus: .init(accessibilityTrusted: false, inputMonitoringTrusted: false)
				),
				warnings: [
					.permissionDenied(.accessibility),
					.permissionDenied(.inputMonitoring),
				]
			)
		)
	}

	func testCapabilityReportsUnavailableWhenPermissionsAreRequired() async {
		let service = makeService(
			configuration: .init(
				recognizerConfiguration: .v1,
				permissionPolicy: .requireAll
			),
			permissionSnapshot: .init(accessibilityTrusted: false, inputMonitoringTrusted: true),
			backendFactory: ServiceTestBackendFactory(
				probeResult: .success(()),
				backend: ServiceTestBackend()
			)
		)

		let capability = await service.capability()

		XCTAssertEqual(capability, .unavailable(.permissionDenied(.accessibility)))
	}

	func testCapabilityReportsBackendProbeFailure() async {
		let service = makeService(
			backendFactory: ServiceTestBackendFactory(
				probeResult: .failure(.captureFailed("probe failed")),
				backend: ServiceTestBackend()
			)
		)

		let capability = await service.capability()

		XCTAssertEqual(capability, .unavailable(.backendFailure(.captureFailed("probe failed"))))
	}

	func testStartRecognizesGestureAndSharesStreams() async throws {
		let backend = ServiceTestBackend()
		let service = makeService(
			backendFactory: ServiceTestBackendFactory(
				probeResult: .success(()),
				backend: backend
			)
		)

		let diagnostics = await service.diagnosticEvents()
		let gestures = await service.gestureEvents()
		let secondGestures = await service.gestureEvents()
		let states = await service.stateUpdates()

		let runningSeen = expectation(description: "running state")
		let gestureSeen = expectation(description: "gesture received")
		let secondSubscriberSeen = expectation(description: "second subscriber received gesture")
		let startupDiagnosticSeen = expectation(description: "startup diagnostic")

		let stateTask = Task {
			for await state in states {
				if case .running = state {
					runningSeen.fulfill()
					break
				}
			}
		}

		let diagnosticTask = Task {
			for await event in diagnostics {
				if case .startupCompleted = event.kind {
					startupDiagnosticSeen.fulfill()
					break
				}
			}
		}

		let gestureTask = Task {
			for await gesture in gestures {
				XCTAssertEqual(gesture.direction, .right)
				gestureSeen.fulfill()
				break
			}
		}

		let secondGestureTask = Task {
			for await _ in secondGestures {
				secondSubscriberSeen.fulfill()
				break
			}
		}

		let sessionID = try await service.start()
		backend.emit(TouchFrame(timestamp: 0.0, contacts: contacts(at: 0.20)))
		backend.emit(TouchFrame(timestamp: 0.05, contacts: contacts(at: 0.34)))
		backend.emit(TouchFrame(timestamp: 0.10, contacts: contacts(at: 0.48)))

		await fulfillment(
			of: [runningSeen, gestureSeen, secondSubscriberSeen, startupDiagnosticSeen],
			timeout: 1
		)

		let runningState = await service.currentState()
		XCTAssertEqual(runningState, .running(sessionID))

		await service.stop()
		let idleState = await service.currentState()
		XCTAssertEqual(idleState, .idle)

		stateTask.cancel()
		diagnosticTask.cancel()
		gestureTask.cancel()
		secondGestureTask.cancel()
	}

	func testStartFailureDisablesServiceAfterFrameworkFailure() async {
		let service = makeService(
			backendFactory: ServiceTestBackendFactory(
				probeResult: .success(()),
				backendError: .frameworkUnavailable("missing symbols")
			)
		)

		do {
			_ = try await service.start()
			XCTFail("Expected startup failure")
		}
		catch {
			XCTAssertEqual(error as? TrackpadGestureError, .backendStartFailed(.frameworkUnavailable("missing symbols")))
		}

		let currentState = await service.currentState()
		XCTAssertEqual(currentState, .disabled(.disabled("missing symbols")))
		let capability = await service.capability()
		XCTAssertEqual(capability, .unavailable(.disabled("missing symbols")))

		do {
			_ = try await service.start()
			XCTFail("Expected disabled capability failure")
		}
		catch {
			XCTAssertEqual(error as? TrackpadGestureError, .capabilityUnavailable(.disabled("missing symbols")))
		}
	}

	func testStartThrowsAlreadyRunningWhenSessionIsActive() async throws {
		let backend = ServiceTestBackend()
		let service = makeService(
			backendFactory: ServiceTestBackendFactory(
				probeResult: .success(()),
				backend: backend
			)
		)

		_ = try await service.start()

		do {
			_ = try await service.start()
			XCTFail("Expected alreadyRunning")
		}
		catch {
			XCTAssertEqual(error as? TrackpadGestureError, .alreadyRunning)
		}
	}

	func testStartCapabilityFailureWithoutDisableSetsFailedState() async {
		let service = makeService(
			configuration: .init(
				recognizerConfiguration: .v1,
				permissionPolicy: .require([.inputMonitoring])
			),
			permissionSnapshot: .init(accessibilityTrusted: true, inputMonitoringTrusted: false),
			backendFactory: ServiceTestBackendFactory(
				probeResult: .success(()),
				backend: ServiceTestBackend()
			)
		)

		do {
			_ = try await service.start()
			XCTFail("Expected capability failure")
		}
		catch {
			XCTAssertEqual(error as? TrackpadGestureError, .capabilityUnavailable(.permissionDenied(.inputMonitoring)))
		}

		let currentState = await service.currentState()
		XCTAssertEqual(currentState, .failed(.capabilityUnavailable(.permissionDenied(.inputMonitoring))))
	}

	func testStartMapsGenericBackendConstructionErrors() async {
		let service = makeService(
			backendFactory: ServiceTestBackendFactory(
				probeResult: .success(()),
				backend: ServiceTestBackend(),
				makeBackendError: ServiceFactoryError.backendConstruction
			)
		)

		do {
			_ = try await service.start()
			XCTFail("Expected generic backend construction failure")
		}
		catch {
			XCTAssertEqual(
				error as? TrackpadGestureError,
				.backendStartFailed(.captureFailed(String(describing: ServiceFactoryError.backendConstruction)))
			)
		}
	}

	func testStartMapsBackendStartFailuresFromTouchCaptureErrors() async {
		let backend = ServiceTestBackend(startError: ServiceFactoryError
			.touchCapture(.registrationFailed("late registration")))
		let service = makeService(
			backendFactory: ServiceTestBackendFactory(
				probeResult: .success(()),
				backend: backend
			)
		)

		do {
			_ = try await service.start()
			XCTFail("Expected touch-capture start failure")
		}
		catch {
			XCTAssertEqual(
				error as? TrackpadGestureError,
				.backendStartFailed(.captureFailed("late registration"))
			)
		}
	}

	func testStartMapsGenericBackendStartErrors() async {
		let backend = ServiceTestBackend(startError: ServiceFactoryError.genericStart)
		let service = makeService(
			backendFactory: ServiceTestBackendFactory(
				probeResult: .success(()),
				backend: backend
			)
		)

		do {
			_ = try await service.start()
			XCTFail("Expected generic start failure")
		}
		catch {
			XCTAssertEqual(
				error as? TrackpadGestureError,
				.backendStartFailed(.captureFailed(String(describing: ServiceFactoryError.genericStart)))
			)
		}
	}

	func testStartFailureFromNoTrackpadsLeavesServiceRetryable() async {
		let service = makeService(
			backendFactory: ServiceTestBackendFactory(
				probeResult: .success(()),
				backendError: .noTrackpadsDetected
			)
		)

		do {
			_ = try await service.start()
			XCTFail("Expected startup failure")
		}
		catch {
			XCTAssertEqual(error as? TrackpadGestureError, .backendStartFailed(.noTrackpadsDetected))
		}

		let currentState = await service.currentState()
		XCTAssertEqual(currentState, .failed(.backendStartFailed(.noTrackpadsDetected)))
	}

	func testStopIsIdempotentAndPreventsLateFramesFromEscaping() async throws {
		let backend = ServiceTestBackend()
		let service = makeService(
			backendFactory: ServiceTestBackendFactory(
				probeResult: .success(()),
				backend: backend
			)
		)

		let gestures = await service.gestureEvents()
		let unexpectedGesture = expectation(description: "no gesture after stop")
		unexpectedGesture.isInverted = true

		let task = Task {
			for await _ in gestures {
				unexpectedGesture.fulfill()
			}
		}

		_ = try await service.start()
		await service.stop()
		await service.stop()

		backend.emit(TouchFrame(timestamp: 0.0, contacts: contacts(at: 0.20)))
		backend.emit(TouchFrame(timestamp: 0.05, contacts: contacts(at: 0.34)))
		backend.emit(TouchFrame(timestamp: 0.10, contacts: contacts(at: 0.48)))

		await fulfillment(of: [unexpectedGesture], timeout: 0.2)
		XCTAssertEqual(backend.stopCount, 1)
		task.cancel()
	}

	func testLateFramesQueuedAfterStopAreDroppedByServiceStateGuard() async throws {
		let backend = ServiceTestBackend(clearsFrameHandlerOnStop: false)
		let service = makeService(
			backendFactory: ServiceTestBackendFactory(
				probeResult: .success(()),
				backend: backend
			)
		)

		let gestures = await service.gestureEvents()
		let unexpectedGesture = expectation(description: "late frame dropped")
		unexpectedGesture.isInverted = true

		let task = Task {
			for await _ in gestures {
				unexpectedGesture.fulfill()
			}
		}

		_ = try await service.start()
		await service.stop()

		backend.emit(TouchFrame(timestamp: 1.0, contacts: contacts(at: 0.20)))
		backend.emit(TouchFrame(timestamp: 1.05, contacts: contacts(at: 0.34)))
		backend.emit(TouchFrame(timestamp: 1.10, contacts: contacts(at: 0.48)))

		await fulfillment(of: [unexpectedGesture], timeout: 0.2)
		task.cancel()
	}

	func testRepeatedStartStopCyclesCreateDistinctSessions() async throws {
		let backend = ServiceTestBackend()
		let service = makeService(
			backendFactory: ServiceTestBackendFactory(
				probeResult: .success(()),
				backend: backend
			)
		)

		let firstSession = try await service.start()
		await service.stop()
		let secondSession = try await service.start()
		await service.stop()

		XCTAssertNotEqual(firstSession, secondSession)
		XCTAssertEqual(backend.startCount, 2)
		XCTAssertEqual(backend.stopCount, 2)
	}

	func testStateUpdatesReplayLatestValueToLateSubscribers() async throws {
		let backend = ServiceTestBackend()
		let service = makeService(
			backendFactory: ServiceTestBackendFactory(
				probeResult: .success(()),
				backend: backend
			)
		)

		let sessionID = try await service.start()
		let states = await service.stateUpdates()

		var iterator = states.makeAsyncIterator()
		let replayedState = await iterator.next()

		XCTAssertEqual(replayedState, .running(sessionID))
	}

	func testMakeLiveBackendFactoryMapsFrameworkUnavailableProbeFailures() {
		let factory = makeLiveBackendFactory(
			frameworkCandidates: ["/tmp/missing-framework"],
			dynamicLibraryClient: DynamicLibraryClient(
				open: { _ in nil },
				symbol: { _, _ in nil },
				close: { _ in }
			)
		)

		switch factory.probeAvailability() {
		case .success:
			XCTFail("Expected framework unavailable")
		case let .failure(error):
			XCTAssertEqual(error, .frameworkUnavailable("/tmp/missing-framework"))
		}
	}

	func testMakeLiveBackendFactoryMapsNoTrackpadsFromAvailabilityProbe() throws {
		let factory = makeLiveBackendFactory(
			frameworkCandidates: ["/tmp/empty-framework"],
			dynamicLibraryClient: makeLiveDynamicLibraryClient(createDeviceList: { nil })
		)

		switch factory.probeAvailability() {
		case .success:
			XCTFail("Expected no-trackpads failure")
		case let .failure(error):
			XCTAssertEqual(error, .noTrackpadsDetected)
		}
		let backend = try factory.makeBackend(emitDiagnostic: { _ in })
		XCTAssertThrowsError(try backend.start { _ in }) { error in
			XCTAssertEqual(error as? TouchCaptureError, .noTrackpads)
		}
	}

	func testMakeLiveBackendFactoryReportsAvailableWhenProbeFindsDevices() {
		let factory = makeLiveBackendFactory(
			frameworkCandidates: ["/tmp/device-framework"],
			dynamicLibraryClient: makeLiveDynamicLibraryClient(createDeviceList: { nil }),
			availabilityDeviceLoader: { _ in
				var values: [UnsafeRawPointer?] = [UnsafeRawPointer(bitPattern: 0x71)]
				let array = CFArrayCreate(nil, &values, values.count, nil)!
				return MultitouchDiscoveredDevices(backingArray: array, devices: [MTDeviceRef(bitPattern: 0x71)!])
			}
		)

		switch factory.probeAvailability() {
		case .success:
			break
		case let .failure(error):
			XCTFail("Expected success, got \(error)")
		}
	}

	func testMakeLiveBackendFactoryMapsSymbolFailuresThroughBridgeLoadFailure() {
		let factory = makeLiveBackendFactory(
			frameworkCandidates: ["/tmp/bad-symbols"],
			dynamicLibraryClient: DynamicLibraryClient(
				open: { _ in UnsafeMutableRawPointer(bitPattern: 0x4444) },
				symbol: { _, _ in nil },
				close: { _ in }
			)
		)

		switch factory.probeAvailability() {
		case .success:
			XCTFail("Expected symbol failure")
		case let .failure(error):
			XCTAssertEqual(error, .frameworkUnavailable("MTDeviceCreateList"))
		}
	}

	func testMakeLiveBackendFactoryMapsCreateDeviceListErrorsToCaptureFailures() {
		let factory = makeLiveBackendFactory(
			frameworkCandidates: ["/tmp/create-list-throws"],
			dynamicLibraryClient: makeLiveDynamicLibraryClient(createDeviceList: { nil }),
			availabilityDeviceLoader: { _ in
				throw ServiceFactoryError.genericStart
			}
		)

		switch factory.probeAvailability() {
		case .success:
			XCTFail("Expected capture failure")
		case let .failure(error):
			XCTAssertEqual(error, .captureFailed(String(describing: ServiceFactoryError.genericStart)))
		}
	}

	func testMapBridgeLoadFailureCoversAllCases() {
		XCTAssertEqual(
			mapBridgeLoadFailure(.frameworkUnavailable("framework missing")),
			.frameworkUnavailable("framework missing")
		)
		XCTAssertEqual(
			mapBridgeLoadFailure(.symbolMissing("MTDeviceStart")),
			.frameworkUnavailable("MTDeviceStart")
		)
		XCTAssertEqual(
			mapBridgeLoadFailure(.frameworkClosed),
			.frameworkUnavailable("Multitouch framework closed")
		)
	}

	private func makeService(
		configuration: TrackpadGestureService.Configuration = .v1(),
		permissionSnapshot: PermissionStateSnapshot = .init(accessibilityTrusted: true, inputMonitoringTrusted: true),
		backendFactory: ServiceTestBackendFactory
	) -> TrackpadGestureService {
		TrackpadGestureService(
			configuration: configuration,
			dependencies: .init(
				backendFactory: backendFactory,
				permissionProvider: ServicePermissionProvider(permissionSnapshot: permissionSnapshot),
				monotonicNow: { ProcessInfo.processInfo.systemUptime }
			)
		)
	}
}

private struct ServicePermissionProvider: PermissionStateProviding {
	let permissionSnapshot: PermissionStateSnapshot

	func snapshot() -> PermissionStateSnapshot {
		permissionSnapshot
	}
}

private struct ServiceTestBackendFactory: TrackpadGestureBackendFactory {
	let probeResult: Result<Void, TrackpadGestureBackendFailure>
	let backend: ServiceTestBackend?
	let backendError: TrackpadGestureBackendFailure?
	let makeBackendError: Error?

	init(
		probeResult: Result<Void, TrackpadGestureBackendFailure>,
		backend: ServiceTestBackend? = nil,
		backendError: TrackpadGestureBackendFailure? = nil,
		makeBackendError: Error? = nil
	) {
		self.probeResult = probeResult
		self.backend = backend
		self.backendError = backendError
		self.makeBackendError = makeBackendError
	}

	func probeAvailability() -> Result<Void, TrackpadGestureBackendFailure> {
		probeResult
	}

	func makeBackend(emitDiagnostic: @escaping @Sendable (GestureDiagnosticEvent.Kind) -> Void) throws
		-> TrackpadGestureBackend {
		if let makeBackendError {
			throw makeBackendError
		}
		if let backendError {
			throw mapBackendFailure(backendError)
		}
		guard let backend else {
			fatalError("Missing backend test double")
		}
		backend.emitDiagnostic = emitDiagnostic
		return backend
	}
}

private final class ServiceTestBackend: TrackpadGestureBackend, @unchecked Sendable {
	var emitDiagnostic: (@Sendable (GestureDiagnosticEvent.Kind) -> Void)?
	var frameHandler: (@Sendable (TouchFrame) -> Void)?
	private(set) var startCount = 0
	private(set) var stopCount = 0
	private let startError: Error?
	private let clearsFrameHandlerOnStop: Bool

	init(startError: Error? = nil, clearsFrameHandlerOnStop: Bool = true) {
		self.startError = startError
		self.clearsFrameHandlerOnStop = clearsFrameHandlerOnStop
	}

	func start(frameHandler: @escaping @Sendable (TouchFrame) -> Void) throws -> TrackpadGestureBackendStartInfo {
		if let startError {
			if case let ServiceFactoryError.touchCapture(error) = startError {
				throw error
			}
			throw startError
		}
		startCount += 1
		self.frameHandler = frameHandler
		emitDiagnostic?(.startupCompleted(deviceCount: 1))
		return .init(deviceCount: 1)
	}

	func stop() {
		stopCount += 1
		if clearsFrameHandlerOnStop {
			frameHandler = nil
		}
	}

	func emit(_ frame: TouchFrame) {
		frameHandler?(frame)
	}
}

private enum ServiceFactoryError: Error {
	case backendConstruction
	case genericStart
	case touchCapture(TouchCaptureError)
}

extension ServiceFactoryError: CustomStringConvertible {
	var description: String {
		switch self {
		case .backendConstruction:
			"backendConstruction"
		case .genericStart:
			"genericStart"
		case let .touchCapture(error):
			String(describing: error)
		}
	}
}

private func makeLiveDynamicLibraryClient(
	createDeviceList: @escaping @Sendable () throws -> Unmanaged<CFArray>?
) -> DynamicLibraryClient {
	DynamicLibraryClient(
		open: { _ in UnsafeMutableRawPointer(bitPattern: 0x5555) },
		symbol: { _, name in
			switch name {
			case "MTDeviceCreateList":
				return unsafeBitCast(
					LiveServiceDynamicLibraryFixtures.createDeviceList(createDeviceList),
					to: UnsafeRawPointer.self
				)
			case "MTRegisterContactFrameCallback":
				return unsafeBitCast(
					LiveServiceDynamicLibraryFixtures.registerCallback,
					to: UnsafeRawPointer.self
				)
			case "MTUnregisterContactFrameCallback":
				return unsafeBitCast(
					LiveServiceDynamicLibraryFixtures.unregisterCallback,
					to: UnsafeRawPointer.self
				)
			case "MTDeviceStart":
				return unsafeBitCast(
					LiveServiceDynamicLibraryFixtures.startDevice,
					to: UnsafeRawPointer.self
				)
			case "MTDeviceStop":
				return unsafeBitCast(
					LiveServiceDynamicLibraryFixtures.stopDevice,
					to: UnsafeRawPointer.self
				)
			case "MTDeviceRelease":
				return unsafeBitCast(
					LiveServiceDynamicLibraryFixtures.releaseDevice,
					to: UnsafeRawPointer.self
				)
			default:
				return nil
			}
		},
		close: { _ in
			LiveServiceDynamicLibraryFixtures.reset()
		}
	)
}

private enum LiveServiceDynamicLibraryFixtures {
	static let registerCallback: MTRegisterContactFrameCallbackFunction = { _, _ in }
	static let unregisterCallback: MTUnregisterContactFrameCallbackFunction = { _, _ in }
	static let startDevice: MTDeviceStartFunction = { _, _ in }
	static let stopDevice: MTDeviceStopFunction = { _ in }
	static let releaseDevice: MTDeviceReleaseFunction = { _ in }
	static let createDeviceListShim: MTDeviceCreateListFunction = {
		LiveServiceDynamicLibraryFixtures.tryOrNilCreateDeviceList()
	}

	private static let state = FixtureState()

	static func createDeviceList(
		_ implementation: @escaping @Sendable () throws -> Unmanaged<CFArray>?
	) -> MTDeviceCreateListFunction {
		state.withLock {
			$0.createDeviceListImpl = implementation
		}
		return createDeviceListShim
	}

	static func tryOrNilCreateDeviceList() -> Unmanaged<CFArray>? {
		let implementation = state.withLock { $0.createDeviceListImpl }
		do {
			return try implementation?()
		}
		catch {
			return nil
		}
	}

	static func reset() {
		state.withLock {
			$0.createDeviceListImpl = nil
		}
	}

	private final class FixtureState: @unchecked Sendable {
		private let lock = NSLock()
		var createDeviceListImpl: (@Sendable () throws -> Unmanaged<CFArray>?)?

		func withLock<T>(_ action: (FixtureState) -> T) -> T {
			lock.lock()
			defer { lock.unlock() }
			return action(self)
		}
	}
}

private func mapBackendFailure(_ failure: TrackpadGestureBackendFailure) -> TouchCaptureError {
	switch failure {
	case let .frameworkUnavailable(reason):
		.fatalBridgeFailure(reason)
	case .noTrackpadsDetected:
		.noTrackpads
	case let .captureFailed(reason):
		.registrationFailed(reason)
	}
}

private func contacts(at xOffset: Double) -> [TouchContact] {
	[
		TouchContact(
			identifier: 1,
			phase: .moved,
			normalizedX: xOffset,
			normalizedY: 0.40,
			majorAxis: 0.01,
			minorAxis: 0.01,
			pressure: 0.5,
			angle: 0
		),
		TouchContact(
			identifier: 2,
			phase: .moved,
			normalizedX: xOffset + 0.04,
			normalizedY: 0.46,
			majorAxis: 0.01,
			minorAxis: 0.01,
			pressure: 0.5,
			angle: 0
		),
		TouchContact(
			identifier: 3,
			phase: .moved,
			normalizedX: xOffset + 0.02,
			normalizedY: 0.52,
			majorAxis: 0.01,
			minorAxis: 0.01,
			pressure: 0.5,
			angle: 0
		),
	]
}
