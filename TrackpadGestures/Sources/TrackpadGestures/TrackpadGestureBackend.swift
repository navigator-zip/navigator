import Foundation

struct TrackpadGestureBackendStartInfo: Equatable, Sendable {
	let deviceCount: Int
}

protocol TrackpadGestureBackend: AnyObject, Sendable {
	func start(frameHandler: @escaping @Sendable (TouchFrame) -> Void) throws -> TrackpadGestureBackendStartInfo
	func stop()
}

protocol TrackpadGestureBackendFactory {
	func probeAvailability() -> Result<Void, TrackpadGestureBackendFailure>
	func makeBackend(emitDiagnostic: @escaping @Sendable (GestureDiagnosticEvent.Kind) -> Void) throws
		-> TrackpadGestureBackend
}

struct LiveTrackpadGestureBackendFactory: TrackpadGestureBackendFactory {
	let sourceFactory: TouchCaptureSourceFactory
	let availabilityProbe: @Sendable () -> Result<Void, TrackpadGestureBackendFailure>

	func probeAvailability() -> Result<Void, TrackpadGestureBackendFailure> {
		availabilityProbe()
	}

	func makeBackend(emitDiagnostic: @escaping @Sendable (GestureDiagnosticEvent.Kind) -> Void) throws
		-> TrackpadGestureBackend {
		try TouchCaptureBackend(source: sourceFactory.makeSource(emitDiagnostic: emitDiagnostic))
	}
}

private final class TouchCaptureBackend: TrackpadGestureBackend, @unchecked Sendable {
	private let source: TouchCaptureSource

	init(source: TouchCaptureSource) {
		self.source = source
	}

	func start(frameHandler: @escaping @Sendable (TouchFrame) -> Void) throws -> TrackpadGestureBackendStartInfo {
		let startInfo = try source.start(frameHandler: frameHandler)
		return TrackpadGestureBackendStartInfo(deviceCount: startInfo.deviceCount)
	}

	func stop() {
		source.stop()
	}
}

func mapTouchCaptureError(_ error: TouchCaptureError) -> TrackpadGestureBackendFailure {
	switch error {
	case .noTrackpads:
		.noTrackpadsDetected
	case let .registrationFailed(reason):
		.captureFailed(reason)
	case let .fatalBridgeFailure(reason):
		.frameworkUnavailable(reason)
	}
}
