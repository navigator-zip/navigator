import CoreFoundation
import Darwin
import Foundation

typealias MTDeviceRef = UnsafeMutableRawPointer

typealias MTDeviceCreateListFunction = @convention(c) () -> Unmanaged<CFArray>?
typealias MTRegisterContactFrameCallbackFunction = @convention(c) (MTDeviceRef?, MTContactFrameCallback?) -> Void
typealias MTUnregisterContactFrameCallbackFunction = @convention(c) (MTDeviceRef?, MTContactFrameCallback?) -> Void
typealias MTDeviceStartFunction = @convention(c) (MTDeviceRef?, Int32) -> Void
typealias MTDeviceStopFunction = @convention(c) (MTDeviceRef?) -> Void
typealias MTDeviceReleaseFunction = @convention(c) (MTDeviceRef?) -> Void
typealias MTContactFrameCallback = @convention(c) (
	UnsafeMutableRawPointer?,
	UnsafeRawPointer?,
	Int32,
	Double,
	Int32
) -> Int32

func multitouchDeviceDiagnosticID(_ device: MTDeviceRef) -> String {
	String(UInt(bitPattern: device))
}

// MARK: - Private ABI mirror notes

/// This is intentionally a private private-API ABI mirror. The field layout should be
/// revalidated per OS release and hardware family.
/// - Origin: reverse-probed private MultitouchSupport symbol contracts.
/// - Expected validation path: runtime logging + pointer-size sanity checks.
/// - Drift signal: crashes/assertions when field mapping is wrong or size/stride changes.
struct MTTouchContactRecord {
	struct MTTouchVector {
		var x: Float
		var y: Float
	}

	var frame: Int32
	var timestamp: Double
	var identifier: Int32
	var state: Int32
	var unknown0: Int32
	var unknown1: Int32
	var normalizedPosition: MTTouchVector
	var size: Float
	var unknown2: Int32
	var angle: Float
	var majorAxis: Float
	var minorAxis: Float
	var velocity: MTTouchVector
	var unknown3: Int32
	var unknown4: Int32
	var density: Float
}

struct DynamicLibraryClient: Sendable {
	let open: @Sendable (_ path: String) -> UnsafeMutableRawPointer?
	let symbol: @Sendable (_ handle: UnsafeMutableRawPointer, _ name: String) -> UnsafeRawPointer?
	let close: @Sendable (_ handle: UnsafeMutableRawPointer) -> Void

	static let noop = DynamicLibraryClient(
		open: { _ in nil },
		symbol: { _, _ in nil },
		close: { _ in }
	)

	static let live = DynamicLibraryClient(
		open: { path in
			dlopen(path, RTLD_NOW)
		},
		symbol: { handle, name in
			UnsafeRawPointer(dlsym(handle, name))
		},
		close: { handle in
			dlclose(handle)
		}
	)
}

struct MultitouchSymbolTable {
	let createDeviceList: @Sendable () -> Unmanaged<CFArray>?
	let registerCallback: @Sendable (MTDeviceRef?, MTContactFrameCallback?) -> Void
	let unregisterCallback: @Sendable (MTDeviceRef?, MTContactFrameCallback?) -> Void
	let startDevice: @Sendable (MTDeviceRef?, Int32) -> Void
	let stopDevice: @Sendable (MTDeviceRef?) -> Void
	let releaseDevice: @Sendable (MTDeviceRef?) -> Void
}

enum MultitouchBridgeLoadFailure: Error, Equatable {
	case frameworkUnavailable(String)
	case symbolMissing(String)
	case frameworkClosed
}

enum MultitouchFrameworkUnloadPolicy {
	case keepLoaded
	case explicitClose
}

typealias MultitouchDiagnosticsSink = (GestureDiagnosticEvent.Kind) -> Void
typealias MultitouchShutdownDelay = TimeInterval

final class MultitouchDiscoveredDevices {
	let backingArray: CFArray
	let devices: [MTDeviceRef]
	let requiresExplicitDeviceRelease: Bool

	init(
		backingArray: CFArray,
		devices: [MTDeviceRef],
		requiresExplicitDeviceRelease: Bool = true
	) {
		self.backingArray = backingArray
		self.devices = devices
		self.requiresExplicitDeviceRelease = requiresExplicitDeviceRelease
	}
}

public enum MultitouchDeviceSessionState: String, Equatable, Sendable {
	case created
	case callbackRegistered
	case started
	case stopping
	case stopped
	case released
	case failed
}

private extension NSLock {
	@discardableResult
	func withLock<T>(_ action: () throws -> T) rethrows -> T {
		lock()
		defer { unlock() }
		return try action()
	}
}

private func mapTouchContactPhase(_ state: Int32) -> TouchContactPhase {
	switch state {
	case 0:
		.began
	case 1:
		.moved
	case 2:
		.stationary
	case 3:
		.ended
	case 4:
		.cancelled
	default:
		.unknown
	}
}

func parseTouchContacts(
	pointer: UnsafeRawPointer?,
	count: Int32,
	maxContactCount: Int = 32,
	layoutSupported: Bool = MTTouchContactRecordLayoutValidation.isSupported,
	unsupportedLayoutHandler: (String) -> Void
) -> [TouchContact] {
	guard count >= 0 else { return [] }
	guard count > 0 else { return [] }
	guard let pointer else { return [] }
	guard layoutSupported else {
		unsupportedLayoutHandler("Unsupported MTTouchContactRecord layout")
		return []
	}
	let saneCount = min(Int(count), maxContactCount)
	let records = pointer.bindMemory(to: MTTouchContactRecord.self, capacity: saneCount)
	let buffer = UnsafeBufferPointer(start: records, count: saneCount)
	return buffer.map {
		TouchContact(
			identifier: Int($0.identifier),
			phase: mapTouchContactPhase($0.state),
			normalizedX: Double($0.normalizedPosition.x),
			normalizedY: Double($0.normalizedPosition.y),
			majorAxis: Double($0.majorAxis),
			minorAxis: Double($0.minorAxis),
			pressure: Double($0.size),
			angle: Double($0.angle)
		)
	}
}

func reportUnsupportedTouchLayout(_ message: String) {
	NSLog("%@", message)
}

private final class CallbackContextRegistry: @unchecked Sendable {
	static let shared = CallbackContextRegistry()

	private var contexts = [UInt: MultitouchSessionCallbackContext]()
	private let lock = NSLock()

	func install(_ context: MultitouchSessionCallbackContext, for device: MTDeviceRef) {
		lock.withLock {
			contexts[UInt(bitPattern: device)] = context
		}
	}

	func remove(for device: MTDeviceRef) {
		lock.withLock {
			contexts.removeValue(forKey: UInt(bitPattern: device))
		}
	}

	func lookup(for device: MTDeviceRef) -> MultitouchSessionCallbackContext? {
		lock.withLock {
			contexts[UInt(bitPattern: device)]
		}
	}
}

private enum MTTouchContactRecordLayoutValidation {
	static let expectedSize = 80
	static let expectedStride = 80
	static let expectedAlignment = 8

	static var isSupported: Bool {
		MemoryLayout<MTTouchContactRecord>.size == expectedSize &&
			MemoryLayout<MTTouchContactRecord>.stride == expectedStride &&
			MemoryLayout<MTTouchContactRecord>.alignment == expectedAlignment
	}
}

private let multitouchContactFrameCallback: MTContactFrameCallback = { device, contacts, contactCount, timestamp, _ in
	guard let device else { return 0 }
	guard let context = CallbackContextRegistry.shared.lookup(for: device) else {
		return 0
	}

	let shouldIgnore = context.beginCallback()
	context.owner?.emitCallbackMetrics()
	if shouldIgnore {
		context.owner?.emitIgnoredCallback(for: device)
		context.endCallback()
		context.owner?.emitCallbackMetrics()
		return 0
	}

	context.owner?.handleTouchFrame(
		contactsPointer: contacts,
		contactCount: contactCount,
		timestamp: timestamp
	)
	context.endCallback()
	context.owner?.emitCallbackMetrics()
	return 0
}

func invokeMultitouchContactFrameCallbackForTesting(
	device: MTDeviceRef?,
	contacts: UnsafeRawPointer?,
	contactCount: Int32,
	timestamp: Double
) -> Int32 {
	multitouchContactFrameCallback(device, contacts, contactCount, timestamp, 0)
}

private func logTouchContactRecordLayout() {
	#if DEBUG
		let size = MemoryLayout<MTTouchContactRecord>.size
		let stride = MemoryLayout<MTTouchContactRecord>.stride
		let alignment = MemoryLayout<MTTouchContactRecord>.alignment
		print("Multitouch: MTTouchContactRecord size=\(size) stride=\(stride) alignment=\(alignment)")
		// Optional production gate when a validated value is captured for a known-good OS/hardware pair:
		// assert(size == 72, "ABI drift detected")
	#endif
}

final class LoadedMultitouchFramework {
	let path: String

	private let handle: UnsafeMutableRawPointer
	private let symbols: MultitouchSymbolTable
	private let dynamicLibraryClient: DynamicLibraryClient
	private let unloadPolicy: MultitouchFrameworkUnloadPolicy
	private let emitDiagnostic: MultitouchDiagnosticsSink
	private let stateLock = NSLock()
	private var isClosed = false
	private var activeSessionCount = 0

	init(
		handle: UnsafeMutableRawPointer,
		path: String,
		symbols: MultitouchSymbolTable,
		dynamicLibraryClient: DynamicLibraryClient,
		unloadPolicy: MultitouchFrameworkUnloadPolicy = .keepLoaded,
		emitDiagnostic: @escaping MultitouchDiagnosticsSink
	) {
		self.handle = handle
		self.path = path
		self.symbols = symbols
		self.dynamicLibraryClient = dynamicLibraryClient
		self.unloadPolicy = unloadPolicy
		self.emitDiagnostic = emitDiagnostic
		logTouchContactRecordLayout()
		emitDiagnostic(.frameworkReady(path))
	}

	deinit {
		closeIfPermitted()
	}

	func createDeviceList() throws -> MultitouchDiscoveredDevices {
		try ensureUsable()
		emitDiagnostic(.deviceListCreationAttempt(path: path))
		guard let unmanaged = symbols.createDeviceList() else {
			return MultitouchDiscoveredDevices(backingArray: [] as CFArray, devices: [])
		}
		let cfArray = unmanaged.takeRetainedValue()
		let count = CFArrayGetCount(cfArray)
		var devices = [MTDeviceRef]()
		devices.reserveCapacity(count)
		for index in 0..<count {
			guard let value = CFArrayGetValueAtIndex(cfArray, index) else { continue }
			devices.append(UnsafeMutableRawPointer(mutating: value))
		}
		emitDiagnostic(.deviceListCreationResult(count: count))
		return MultitouchDiscoveredDevices(
			backingArray: cfArray,
			devices: devices,
			requiresExplicitDeviceRelease: false
		)
	}

	func makeSession(
		device: MTDeviceRef,
		deviceLifetimeAnchor: MultitouchDiscoveredDevices,
		frameHandler: @escaping @Sendable (TouchFrame) -> Void,
		emitDiagnostic: @escaping MultitouchDiagnosticsSink,
		quietPeriod: MultitouchShutdownDelay = 0.0125,
		maxQuiescence: MultitouchShutdownDelay = 0.2,
		postDrainDelay: MultitouchShutdownDelay = 0
	) throws -> MultitouchDeviceSession {
		try reserveSession()
		return MultitouchDeviceSession(
			device: device,
			deviceLifetimeAnchor: deviceLifetimeAnchor,
			framework: self,
			emitDiagnostic: emitDiagnostic,
			frameHandler: frameHandler,
			quietPeriod: quietPeriod,
			maxQuiescence: maxQuiescence,
			postDrainDelay: postDrainDelay
		)
	}

	func closeIfPermitted() {
		let policy = unloadPolicy
		let shouldAttemptClose = stateLock.withLock {
			preambleIfNeeded(policy: policy)
		}

		emitDiagnostic(.frameworkCloseAttempted(path))
		guard shouldAttemptClose else {
			emitDiagnostic(.frameworkCloseSkipped(path))
			return
		}

		dynamicLibraryClient.close(handle)
		stateLock.withLock {
			isClosed = true
		}
		emitDiagnostic(.frameworkClosed(path))
	}

	fileprivate func registerCallback(device: MTDeviceRef, context: MultitouchSessionCallbackContext) throws {
		try ensureUsable()
		CallbackContextRegistry.shared.install(context, for: device)
		symbols.registerCallback(device, multitouchContactFrameCallback)
	}

	fileprivate func unregisterCallback(device: MTDeviceRef) {
		symbols.unregisterCallback(device, multitouchContactFrameCallback)
	}

	fileprivate func removeCallbackContext(device: MTDeviceRef) {
		CallbackContextRegistry.shared.remove(for: device)
	}

	fileprivate func startDevice(_ device: MTDeviceRef) throws {
		try ensureUsable()
		symbols.startDevice(device, 0)
	}

	fileprivate func stopDevice(_ device: MTDeviceRef) {
		tryOrIgnore { try ensureUsable() }
		symbols.stopDevice(device)
	}

	fileprivate func releaseDevice(_ device: MTDeviceRef) {
		tryOrIgnore { try ensureUsable() }
		symbols.releaseDevice(device)
	}

	fileprivate func releaseSessionSlot() {
		stateLock.withLock {
			activeSessionCount = max(0, activeSessionCount - 1)
		}
	}

	private func reserveSession() throws {
		try ensureUsable()
		stateLock.withLock {
			activeSessionCount += 1
		}
	}

	private func ensureUsable() throws {
		try stateLock.withLock {
			guard !isClosed else { throw MultitouchBridgeLoadFailure.frameworkClosed }
		}
	}

	private func preambleIfNeeded(policy: MultitouchFrameworkUnloadPolicy) -> Bool {
		// Return true only when explicit close is enabled and safe.
		if policy == .keepLoaded { return false }
		guard !isClosed, activeSessionCount == 0 else { return false }
		return true
	}
}

typealias MultitouchBridge = LoadedMultitouchFramework

extension LoadedMultitouchFramework {
	static func forTest(
		path: String = "test",
		handle: UnsafeMutableRawPointer = UnsafeMutableRawPointer(bitPattern: 0x1000)!,
		symbols: MultitouchSymbolTable,
		dynamicLibraryClient: DynamicLibraryClient = .noop,
		unloadPolicy: MultitouchFrameworkUnloadPolicy = .keepLoaded,
		emitDiagnostic: @escaping MultitouchDiagnosticsSink = { _ in }
	) -> LoadedMultitouchFramework {
		LoadedMultitouchFramework(
			handle: handle,
			path: path,
			symbols: symbols,
			dynamicLibraryClient: dynamicLibraryClient,
			unloadPolicy: unloadPolicy,
			emitDiagnostic: emitDiagnostic
		)
	}
}

final class MultitouchBridgeLoader: @unchecked Sendable {
	let frameworkCandidates: [String]
	let dynamicLibraryClient: DynamicLibraryClient
	let frameworkUnloadPolicy: MultitouchFrameworkUnloadPolicy

	init(
		frameworkCandidates: [String],
		dynamicLibraryClient: DynamicLibraryClient,
		frameworkUnloadPolicy: MultitouchFrameworkUnloadPolicy = .keepLoaded
	) {
		self.frameworkCandidates = frameworkCandidates
		self.dynamicLibraryClient = dynamicLibraryClient
		self.frameworkUnloadPolicy = frameworkUnloadPolicy
	}

	func load(emitDiagnostic: @escaping (GestureDiagnosticEvent.Kind) -> Void)
		-> Result<LoadedMultitouchFramework, MultitouchBridgeLoadFailure> {
		var attempted = [String]()
		var lastFailure: MultitouchBridgeLoadFailure?

		for candidate in frameworkCandidates {
			attempted.append(candidate)
			emitDiagnostic(.frameworkOpenAttempt(candidate))
			guard let handle = dynamicLibraryClient.open(candidate) else {
				continue
			}

			emitDiagnostic(.frameworkOpened(candidate))
			switch resolveAllSymbols(handle: handle, emitDiagnostic: emitDiagnostic) {
			case let .success(symbols):
				return .success(
					LoadedMultitouchFramework(
						handle: handle,
						path: candidate,
						symbols: symbols,
						dynamicLibraryClient: dynamicLibraryClient,
						unloadPolicy: frameworkUnloadPolicy,
						emitDiagnostic: emitDiagnostic
					)
				)
			case let .failure(failure):
				lastFailure = failure
				dynamicLibraryClient.close(handle)
				continue
			}
		}

		let description = attempted.joined(separator: ", ")
		let failure = lastFailure ?? .frameworkUnavailable(description)
		emitDiagnostic(.frameworkLoadFailed(description))
		return .failure(failure)
	}

	private func resolveAllSymbols(
		handle: UnsafeMutableRawPointer,
		emitDiagnostic: (GestureDiagnosticEvent.Kind) -> Void
	) -> Result<MultitouchSymbolTable, MultitouchBridgeLoadFailure> {
		do {
			let createDeviceList = try resolveSymbol(
				name: "MTDeviceCreateList",
				handle: handle,
				emitDiagnostic: emitDiagnostic
			) as MTDeviceCreateListFunction
			let registerCallback = try resolveSymbol(
				name: "MTRegisterContactFrameCallback",
				handle: handle,
				emitDiagnostic: emitDiagnostic
			) as MTRegisterContactFrameCallbackFunction
			let unregisterCallback = try resolveSymbol(
				name: "MTUnregisterContactFrameCallback",
				handle: handle,
				emitDiagnostic: emitDiagnostic
			) as MTUnregisterContactFrameCallbackFunction
			let startDevice = try resolveSymbol(
				name: "MTDeviceStart",
				handle: handle,
				emitDiagnostic: emitDiagnostic
			) as MTDeviceStartFunction
			let stopDevice = try resolveSymbol(
				name: "MTDeviceStop",
				handle: handle,
				emitDiagnostic: emitDiagnostic
			) as MTDeviceStopFunction
			let releaseDevice = try resolveSymbol(
				name: "MTDeviceRelease",
				handle: handle,
				emitDiagnostic: emitDiagnostic
			) as MTDeviceReleaseFunction

			return .success(MultitouchSymbolTable(
				createDeviceList: {
					createDeviceList()
				},
				registerCallback: { device, callback in
					registerCallback(device, callback)
				},
				unregisterCallback: { device, callback in
					unregisterCallback(device, callback)
				},
				startDevice: { device, mode in
					startDevice(device, mode)
				},
				stopDevice: { device in
					stopDevice(device)
				},
				releaseDevice: { device in
					releaseDevice(device)
				}
			))
		}
		catch {
			return .failure(error as! MultitouchBridgeLoadFailure)
		}
	}

	private func resolveSymbol<T>(
		name: String,
		handle: UnsafeMutableRawPointer,
		emitDiagnostic: (GestureDiagnosticEvent.Kind) -> Void
	) throws -> T {
		guard let symbol = dynamicLibraryClient.symbol(handle, name) else {
			emitDiagnostic(.symbolMissing(name))
			throw MultitouchBridgeLoadFailure.symbolMissing(name)
		}
		emitDiagnostic(.symbolResolved(name))
		return unsafeBitCast(symbol, to: T.self)
	}
}

final class MultitouchSessionCallbackContext {
	let sessionID: UUID
	weak var owner: MultitouchDeviceSession?
	private let lock = NSLock()
	private var isStopping = false
	private var inFlight = 0
	private var lastCallbackNanos: UInt64 = 0

	init(sessionID: UUID) {
		self.sessionID = sessionID
	}

	func beginCallback() -> Bool {
		lock.withLock {
			inFlight += 1
			lastCallbackNanos = DispatchTime.now().uptimeNanoseconds
			return isStopping
		}
	}

	func endCallback() {
		lock.withLock {
			inFlight = max(0, inFlight - 1)
		}
	}

	func markStopping() {
		lock.withLock {
			isStopping = true
		}
	}

	func snapshot() -> (isStopping: Bool, inFlight: Int, lastCallbackNanos: UInt64) {
		lock.withLock {
			(isStopping, inFlight, lastCallbackNanos)
		}
	}
}

final class MultitouchDeviceSession {
	enum ShutdownMode {
		case fullNativeTeardown
		case deviceRemovedFromDiscovery
	}

	let sessionID = UUID()
	private let device: MTDeviceRef
	private let deviceLifetimeAnchor: MultitouchDiscoveredDevices
	private let framework: LoadedMultitouchFramework
	private let emitDiagnostic: MultitouchDiagnosticsSink
	private let frameHandler: @Sendable (TouchFrame) -> Void
	private let stateLock = NSLock()
	private var state: MultitouchDeviceSessionState = .created
	private let frameDeliveryQueue: DispatchQueue
	private let callbackContext: MultitouchSessionCallbackContext
	private let quietPeriodNanos: UInt64
	private let maxQuiescenceNanos: UInt64
	private let postDrainDelayNanos: UInt64

	init(
		device: MTDeviceRef,
		deviceLifetimeAnchor: MultitouchDiscoveredDevices,
		framework: LoadedMultitouchFramework,
		emitDiagnostic: @escaping MultitouchDiagnosticsSink,
		frameHandler: @escaping @Sendable (TouchFrame) -> Void,
		quietPeriod: MultitouchShutdownDelay,
		maxQuiescence: MultitouchShutdownDelay,
		postDrainDelay: MultitouchShutdownDelay,
		frameDeliveryQueue: DispatchQueue = DispatchQueue(
			label: "TrackpadGestures.TouchCapture.SessionDelivery",
			qos: .userInitiated
		)
	) {
		self.device = device
		self.deviceLifetimeAnchor = deviceLifetimeAnchor
		self.framework = framework
		self.emitDiagnostic = emitDiagnostic
		self.frameHandler = frameHandler
		self.frameDeliveryQueue = frameDeliveryQueue
		self.quietPeriodNanos = UInt64(max(0, quietPeriod * 1_000_000_000))
		self.maxQuiescenceNanos = UInt64(max(0, maxQuiescence * 1_000_000_000))
		self.postDrainDelayNanos = UInt64(max(0, postDrainDelay * 1_000_000_000))
		self.callbackContext = MultitouchSessionCallbackContext(sessionID: sessionID)
		self.callbackContext.owner = self
		emitDiagnostic(.frameworkSessionCreated(sessionID: sessionID))
	}

	func registerCallback() throws {
		let currentState = stateLock.withLock { state }
		guard currentState == .created else {
			stateLock.withLock {
				state = .failed
			}
			throw MultitouchBridgeLoadFailure.frameworkUnavailable("Invalid session state \(currentState)")
		}
		try framework.registerCallback(device: device, context: callbackContext)
		stateLock.withLock {
			state = .callbackRegistered
		}
		emitDiagnostic(.sessionCallbackRegistered(sessionID: sessionID, device: multitouchDeviceDiagnosticID(device)))
	}

	func start() throws {
		let currentState = stateLock.withLock { state }
		guard currentState == .callbackRegistered else {
			stateLock.withLock {
				state = .failed
			}
			throw MultitouchBridgeLoadFailure.frameworkUnavailable("Invalid session state \(currentState)")
		}
		try framework.startDevice(device)
		stateLock.withLock {
			state = .started
		}
		emitDiagnostic(.sessionDeviceStarted(sessionID: sessionID, device: multitouchDeviceDiagnosticID(device)))
	}

	func shutdown(mode: ShutdownMode = .fullNativeTeardown) {
		var shouldUnregister = false
		var shouldStopDevice = false
		var shouldReleaseDevice = false
		let shouldSkipNativeTeardown = mode == .deviceRemovedFromDiscovery

		stateLock.withLock {
			emitDiagnostic(.sessionStateTransition(sessionID: sessionID, state: state))
			switch state {
			case .released, .failed, .stopping:
				shouldUnregister = false
				shouldStopDevice = false
				shouldReleaseDevice = false
			case .created, .stopped:
				state = .stopped
				shouldUnregister = false
				shouldStopDevice = false
				shouldReleaseDevice = false
			case .callbackRegistered:
				state = .stopping
				shouldUnregister = true
				shouldStopDevice = false
				shouldReleaseDevice = true
			case .started:
				state = .stopping
				shouldUnregister = true
				shouldStopDevice = true
				shouldReleaseDevice = true
			}
			callbackContext.markStopping()
		}

		emitDiagnostic(.sessionShutdownRequested(sessionID: sessionID, device: multitouchDeviceDiagnosticID(device)))

		guard shouldUnregister || shouldStopDevice || shouldReleaseDevice else {
			framework.releaseSessionSlot()
			stateLock.withLock { state = .released }
			emitDiagnostic(.sessionStateTransition(sessionID: sessionID, state: .released))
			return
		}

		if shouldSkipNativeTeardown {
			framework.removeCallbackContext(device: device)
		}
		if shouldUnregister, !shouldSkipNativeTeardown {
			framework.unregisterCallback(device: device)
			emitDiagnostic(.callbackUnregistered(sessionID: sessionID, device: multitouchDeviceDiagnosticID(device)))
		}
		if shouldStopDevice, !shouldSkipNativeTeardown {
			framework.stopDevice(device)
			emitDiagnostic(.deviceStopped(sessionID: sessionID, device: multitouchDeviceDiagnosticID(device)))
		}
		if shouldReleaseDevice, !shouldSkipNativeTeardown {
			waitForQuiescence()
			framework.removeCallbackContext(device: device)
			if deviceLifetimeAnchor.requiresExplicitDeviceRelease {
				framework.releaseDevice(device)
				emitDiagnostic(.deviceReleased(sessionID: sessionID, device: multitouchDeviceDiagnosticID(device)))
			}
		}
		framework.releaseSessionSlot()
		stateLock.withLock {
			state = .released
		}
		emitDiagnostic(.sessionStateTransition(sessionID: sessionID, state: .released))
	}

	fileprivate func handleTouchFrame(contactsPointer: UnsafeRawPointer?, contactCount: Int32, timestamp: Double) {
		let shouldIgnore = stateLock.withLock { state != .started }
		guard !shouldIgnore else {
			emitDiagnostic(.callbackIgnoredWhileStopping(sessionID: sessionID, device: multitouchDeviceDiagnosticID(device)))
			return
		}
		let contacts = parseTouchContacts(
			pointer: contactsPointer,
			count: contactCount,
			unsupportedLayoutHandler: reportUnsupportedTouchLayout
		)
		let frame = TouchFrame(timestamp: timestamp, contacts: contacts)
		frameDeliveryQueue.async { [frameHandler] in
			frameHandler(frame)
		}
	}

	private func waitForQuiescence() {
		emitDiagnostic(.shutdownQuiescenceWaiting(sessionID: sessionID, device: multitouchDeviceDiagnosticID(device)))
		let startedAt = DispatchTime.now().uptimeNanoseconds
		while true {
			let snapshot = callbackContext.snapshot()
			let now = DispatchTime.now().uptimeNanoseconds
			let hasPastQuietWindow = snapshot.lastCallbackNanos == 0 || (now >= snapshot.lastCallbackNanos + quietPeriodNanos)
			if snapshot.inFlight == 0, hasPastQuietWindow {
				emitDiagnostic(.shutdownQuiescenceComplete(sessionID: sessionID, device: multitouchDeviceDiagnosticID(device)))
				return
			}
			if now >= startedAt + maxQuiescenceNanos {
				break
			}
			usleep(1000)
		}
		if postDrainDelayNanos > 0 {
			usleep(UInt32(postDrainDelayNanos / 1000))
		}
		emitDiagnostic(.shutdownQuiescenceComplete(sessionID: sessionID, device: multitouchDeviceDiagnosticID(device)))
	}

	fileprivate func emitCallbackMetrics() {
		let snapshot = callbackContext.snapshot()
		guard snapshot.inFlight > 1 else { return }
		emitDiagnostic(.callbackInFlightState(
			sessionID: sessionID,
			device: multitouchDeviceDiagnosticID(device),
			inFlightCount: snapshot.inFlight
		))
	}

	fileprivate func emitIgnoredCallback(for device: MTDeviceRef) {
		emitDiagnostic(.callbackIgnoredWhileStopping(sessionID: sessionID, device: multitouchDeviceDiagnosticID(device)))
	}

	func emitCallbackMetricsForTesting() {
		emitCallbackMetrics()
	}

	func beginCallbackForTesting() -> Bool {
		callbackContext.beginCallback()
	}

	func endCallbackForTesting() {
		callbackContext.endCallback()
	}
}

private func tryOrIgnore(_ block: () throws -> Void) {
	_ = try? block()
}
