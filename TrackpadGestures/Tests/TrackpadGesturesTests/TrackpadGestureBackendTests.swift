import Foundation
@testable import TrackpadGestures
import XCTest

final class TrackpadGestureBackendTests: XCTestCase {
	func testLiveBackendFactoryUsesProbeAndWrapsTouchCaptureSource() throws {
		let source = BackendTestTouchCaptureSource()
		let factory = LiveTrackpadGestureBackendFactory(
			sourceFactory: BackendTestTouchCaptureSourceFactory(source: source),
			availabilityProbe: { .success(()) }
		)

		switch factory.probeAvailability() {
		case .success:
			break
		case let .failure(error):
			XCTFail("Unexpected probe failure: \(error)")
		}

		let backend = try factory.makeBackend(emitDiagnostic: { _ in })
		let startInfo = try backend.start { _ in }
		backend.stop()

		XCTAssertEqual(startInfo, .init(deviceCount: 2))
		XCTAssertEqual(source.startCount, 1)
		XCTAssertEqual(source.stopCount, 1)
	}

	func testMapTouchCaptureErrorCoversAllCases() {
		XCTAssertEqual(
			mapTouchCaptureError(.registrationFailed("registration failed")),
			.captureFailed("registration failed")
		)
		XCTAssertEqual(
			mapTouchCaptureError(.fatalBridgeFailure("bridge failed")),
			.frameworkUnavailable("bridge failed")
		)
		XCTAssertEqual(
			mapTouchCaptureError(.noTrackpads),
			.noTrackpadsDetected
		)
	}
}

private struct BackendTestTouchCaptureSourceFactory: TouchCaptureSourceFactory {
	let source: BackendTestTouchCaptureSource

	func makeSource(emitDiagnostic: @escaping (GestureDiagnosticEvent.Kind) -> Void) throws -> TouchCaptureSource {
		source.emitDiagnostic = emitDiagnostic
		return source
	}
}

private final class BackendTestTouchCaptureSource: TouchCaptureSource {
	var emitDiagnostic: ((GestureDiagnosticEvent.Kind) -> Void)?
	private(set) var startCount = 0
	private(set) var stopCount = 0

	func start(frameHandler: @escaping @Sendable (TouchFrame) -> Void) throws -> TouchCaptureStartInfo {
		startCount += 1
		emitDiagnostic?(.startupCompleted(deviceCount: 2))
		return .init(deviceCount: 2)
	}

	func stop() {
		stopCount += 1
	}
}
