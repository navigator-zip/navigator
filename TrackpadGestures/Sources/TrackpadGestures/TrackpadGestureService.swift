import Foundation

public actor TrackpadGestureService {
	public struct Configuration: Equatable, Sendable {
		public let recognizerConfiguration: SwipeRightRecognizerConfiguration
		public let permissionPolicy: TrackpadGesturePermissionPolicy
		public let gestureBufferLimit: Int
		public let diagnosticBufferLimit: Int

		public init(
			recognizerConfiguration: SwipeRightRecognizerConfiguration,
			permissionPolicy: TrackpadGesturePermissionPolicy,
			gestureBufferLimit: Int = 16,
			diagnosticBufferLimit: Int = 64
		) {
			self.recognizerConfiguration = recognizerConfiguration
			self.permissionPolicy = permissionPolicy
			self.gestureBufferLimit = max(1, gestureBufferLimit)
			self.diagnosticBufferLimit = max(1, diagnosticBufferLimit)
		}

		public static func v1() -> Configuration {
			Configuration(
				recognizerConfiguration: .v1,
				permissionPolicy: .diagnosticOnly
			)
		}
	}

	struct Dependencies: @unchecked Sendable {
		let backendFactory: TrackpadGestureBackendFactory
		let permissionProvider: PermissionStateProviding
		let monotonicNow: @Sendable () -> TimeInterval
	}

	private struct ActiveSession {
		let id: GestureSessionID
		let backend: TrackpadGestureBackend
		let recognizer: SwipeRightGestureRecognizer
	}

	private let configuration: Configuration
	private let dependencies: Dependencies
	private let gestureBroadcaster: AsyncStreamBroadcaster<RecognizedGesture>
	private let diagnosticBroadcaster: AsyncStreamBroadcaster<GestureDiagnosticEvent>
	private let stateBroadcaster: AsyncStreamBroadcaster<TrackpadGestureServiceState>
	private var state: TrackpadGestureServiceState = .idle
	private var activeSession: ActiveSession?
	private var disabledReason: TrackpadGestureUnavailabilityReason?

	public init(configuration: Configuration = .v1()) {
		self.init(
			configuration: configuration,
			dependencies: Dependencies(
				backendFactory: makeLiveBackendFactory(),
				permissionProvider: SystemPermissionStateProvider(),
				monotonicNow: systemMonotonicNow
			)
		)
	}

	init(configuration: Configuration, dependencies: Dependencies) {
		self.configuration = configuration
		self.dependencies = dependencies
		self.gestureBroadcaster = AsyncStreamBroadcaster(
			bufferingPolicy: .bufferingNewest(max(1, configuration.gestureBufferLimit))
		)
		self.diagnosticBroadcaster = AsyncStreamBroadcaster(
			bufferingPolicy: .bufferingNewest(max(1, configuration.diagnosticBufferLimit))
		)
		self.stateBroadcaster = AsyncStreamBroadcaster(
			replayLimit: 1,
			bufferingPolicy: .bufferingNewest(1)
		)
		self.stateBroadcaster.yield(.idle)
	}

	public func capability() -> TrackpadGestureCapability {
		if let disabledReason {
			return .unavailable(disabledReason)
		}

		let permissionStatus = dependencies.permissionProvider.snapshot().publicStatus
		let missingPermissions = permissionStatus.missingPermissions(in: configuration.permissionPolicy.trackedPermissions)

		switch configuration.permissionPolicy {
		case .require:
			if let firstMissingPermission = missingPermissions.first {
				return .unavailable(.permissionDenied(firstMissingPermission))
			}
		case .reportMissingAsDegraded:
			break
		}

		switch dependencies.backendFactory.probeAvailability() {
		case .success:
			let details = TrackpadGestureCapabilityDetails(permissionStatus: permissionStatus)
			if missingPermissions.isEmpty {
				return .available(details)
			}
			return .degraded(
				details,
				warnings: missingPermissions.map { .permissionDenied($0) }
			)
		case let .failure(failure):
			return .unavailable(.backendFailure(failure))
		}
	}

	public func currentState() -> TrackpadGestureServiceState {
		state
	}

	public func start() throws -> GestureSessionID {
		guard activeSession == nil else {
			throw TrackpadGestureError.alreadyRunning
		}

		switch capability() {
		case let .unavailable(reason):
			if case .disabled = reason {
				setState(.disabled(reason))
			}
			else {
				setState(.failed(.capabilityUnavailable(reason)))
			}
			throw TrackpadGestureError.capabilityUnavailable(reason)
		case .available, .degraded:
			break
		}

		let sessionID = GestureSessionID()
		let permissionStatus = dependencies.permissionProvider.snapshot().publicStatus
		setState(.starting)
		emitDiagnostic(.sessionStarted, sessionID: sessionID)
		emitDiagnostic(.runtimeStateChanged(.starting), sessionID: sessionID)
		emitDiagnostic(.osVersion(ProcessInfo.processInfo.operatingSystemVersionString), sessionID: sessionID)
		emitDiagnostic(
			.permissionSnapshot(
				accessibilityTrusted: permissionStatus.accessibilityTrusted,
				inputMonitoringTrusted: permissionStatus.inputMonitoringTrusted
			),
			sessionID: sessionID
		)

		let backendDiagnostics: @Sendable (GestureDiagnosticEvent.Kind) -> Void = { [service = self] kind in
			Task {
				await service.emitDiagnostic(kind, sessionID: sessionID)
			}
		}

		let backend: TrackpadGestureBackend
		do {
			backend = try dependencies.backendFactory.makeBackend(emitDiagnostic: backendDiagnostics)
		}
		catch let error as TouchCaptureError {
			let backendFailure = mapTouchCaptureError(error)
			transitionToStartupFailure(backendFailure, sessionID: sessionID)
			throw TrackpadGestureError.backendStartFailed(backendFailure)
		}
		catch {
			let backendFailure = TrackpadGestureBackendFailure.captureFailed(String(describing: error))
			transitionToStartupFailure(backendFailure, sessionID: sessionID)
			throw TrackpadGestureError.backendStartFailed(backendFailure)
		}

		let session = ActiveSession(
			id: sessionID,
			backend: backend,
			recognizer: SwipeRightGestureRecognizer(configuration: configuration.recognizerConfiguration)
		)
		activeSession = session

		do {
			let startInfo = try backend.start { [service = self] frame in
				Task {
					await service.process(frame: frame, sessionID: sessionID)
				}
			}
			setState(.running(sessionID))
			emitDiagnostic(.startupCompleted(deviceCount: startInfo.deviceCount), sessionID: sessionID)
			emitDiagnostic(.runtimeStateChanged(.running), sessionID: sessionID)
			return sessionID
		}
		catch let error as TouchCaptureError {
			backend.stop()
			activeSession = nil
			let backendFailure = mapTouchCaptureError(error)
			transitionToStartupFailure(backendFailure, sessionID: sessionID)
			throw TrackpadGestureError.backendStartFailed(backendFailure)
		}
		catch {
			backend.stop()
			activeSession = nil
			let backendFailure = TrackpadGestureBackendFailure.captureFailed(String(describing: error))
			transitionToStartupFailure(backendFailure, sessionID: sessionID)
			throw TrackpadGestureError.backendStartFailed(backendFailure)
		}
	}

	public func stop() {
		guard let session = activeSession else {
			return
		}

		let sessionID = session.id
		let backend = session.backend
		activeSession = nil
		setState(.stopping(sessionID))
		emitDiagnostic(.runtimeStateChanged(.stopping), sessionID: sessionID)
		backend.stop()
		setState(.idle)
		emitDiagnostic(.sessionStopped, sessionID: sessionID)
		emitDiagnostic(.runtimeStateChanged(.stopped), sessionID: sessionID)
	}

	public func gestureEvents() -> AsyncStream<RecognizedGesture> {
		gestureBroadcaster.stream()
	}

	public func diagnosticEvents() -> AsyncStream<GestureDiagnosticEvent> {
		diagnosticBroadcaster.stream()
	}

	public func stateUpdates() -> AsyncStream<TrackpadGestureServiceState> {
		stateBroadcaster.stream()
	}

	private func process(frame: TouchFrame, sessionID: GestureSessionID) {
		guard case let .running(activeSessionID) = state,
		      activeSessionID == sessionID,
		      let activeSession,
		      activeSession.id == sessionID else {
			return
		}
		let result = activeSession.recognizer.process(frame: frame, sessionID: sessionID)
		for diagnostic in result.diagnostics {
			emitDiagnostic(diagnostic, sessionID: sessionID)
		}
		if let recognizedGesture = result.recognizedGesture {
			gestureBroadcaster.yield(recognizedGesture)
		}
	}

	private func transitionToStartupFailure(
		_ failure: TrackpadGestureBackendFailure,
		sessionID: GestureSessionID
	) {
		switch failure {
		case let .frameworkUnavailable(reason):
			let disabled = TrackpadGestureUnavailabilityReason.disabled(reason)
			disabledReason = disabled
			activeSession = nil
			setState(.disabled(disabled))
			emitDiagnostic(.startupFailed(reason), sessionID: sessionID)
			emitDiagnostic(.runtimeStateChanged(.failed), sessionID: sessionID)
			emitDiagnostic(.killSwitchActivated(reason), sessionID: sessionID)
		case .noTrackpadsDetected, .captureFailed:
			activeSession = nil
			setState(.failed(.backendStartFailed(failure)))
			emitDiagnostic(.startupFailed(String(describing: failure)), sessionID: sessionID)
			emitDiagnostic(.runtimeStateChanged(.failed), sessionID: sessionID)
		}
	}

	private func setState(_ nextState: TrackpadGestureServiceState) {
		state = nextState
		stateBroadcaster.yield(nextState)
	}

	private func emitDiagnostic(_ kind: GestureDiagnosticEvent.Kind, sessionID: GestureSessionID) {
		diagnosticBroadcaster.yield(
			GestureDiagnosticEvent(
				sessionID: sessionID,
				timestamp: dependencies.monotonicNow(),
				kind: kind
			)
		)
	}
}

let defaultMultitouchFrameworkCandidates = [
	"/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
]

func systemMonotonicNow() -> TimeInterval {
	ProcessInfo.processInfo.systemUptime
}

func makeLiveBackendFactory(
	frameworkCandidates: [String] = defaultMultitouchFrameworkCandidates,
	dynamicLibraryClient: DynamicLibraryClient = .live,
	availabilityDeviceLoader: @escaping @Sendable (LoadedMultitouchFramework) throws -> MultitouchDiscoveredDevices = {
		try $0.createDeviceList()
	}
) -> TrackpadGestureBackendFactory {
	let sourceFactory = LiveTouchCaptureSourceFactory(
		bridgeLoader: MultitouchBridgeLoader(
			frameworkCandidates: frameworkCandidates,
			dynamicLibraryClient: dynamicLibraryClient
		)
	)
	return LiveTrackpadGestureBackendFactory(
		sourceFactory: sourceFactory,
		availabilityProbe: {
			let bridgeLoader = MultitouchBridgeLoader(
				frameworkCandidates: frameworkCandidates,
				dynamicLibraryClient: dynamicLibraryClient,
				frameworkUnloadPolicy: .explicitClose
			)
			switch bridgeLoader.load(emitDiagnostic: { _ in }) {
			case let .failure(failure):
				return .failure(mapBridgeLoadFailure(failure))
			case let .success(bridge):
				defer {
					bridge.closeIfPermitted()
				}
				do {
					let devices = try availabilityDeviceLoader(bridge)
					return devices.devices.isEmpty ? .failure(.noTrackpadsDetected) : .success(())
				}
				catch {
					return .failure(.captureFailed(String(describing: error)))
				}
			}
		}
	)
}

func mapBridgeLoadFailure(_ failure: MultitouchBridgeLoadFailure) -> TrackpadGestureBackendFailure {
	switch failure {
	case let .frameworkUnavailable(reason), let .symbolMissing(reason):
		.frameworkUnavailable(reason)
	case .frameworkClosed:
		.frameworkUnavailable("Multitouch framework closed")
	}
}
