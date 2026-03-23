import AVFoundation
@testable import BrowserCameraKit
import CoreGraphics
import CoreMedia
import CoreVideo
import ModelKit
import Observation
import Pipeline
import XCTest

@MainActor
final class LiveBrowserCameraCaptureControllerTests: XCTestCase {
	func testCaptureConfigurationStoresHorizontalFlipPreference() {
		let configuration = BrowserCameraCaptureConfiguration(
			deviceID: "camera-a",
			filterPreset: .folia,
			grainPresence: .high,
			prefersHorizontalFlip: true
		)

		XCTAssertTrue(configuration.prefersHorizontalFlip)
	}

	func testAVCaptureClientTransformationMatchesSelectedFilterPreset() {
		XCTAssertEqual(
			LiveBrowserCameraCaptureController.avCaptureClientTransformation(for: .none),
			Transformation(.none, .chromatic(.tonachrome))
		)
		XCTAssertEqual(
			LiveBrowserCameraCaptureController.avCaptureClientTransformation(
				for: .monochrome,
				grainPresence: .normal
			),
			Transformation(.normal, .monochrome)
		)
		XCTAssertEqual(
			LiveBrowserCameraCaptureController.avCaptureClientTransformation(
				for: .monochrome,
				grainPresence: .high
			),
			Transformation(.high, .monochrome)
		)
		XCTAssertEqual(
			LiveBrowserCameraCaptureController.avCaptureClientTransformation(
				for: .folia,
				grainPresence: .normal
			),
			Transformation(.normal, .chromatic(.folia))
		)
		XCTAssertEqual(
			LiveBrowserCameraCaptureController.avCaptureClientTransformation(
				for: .supergold,
				grainPresence: .none
			),
			Transformation(.none, .chromatic(.supergold))
		)
		XCTAssertEqual(
			LiveBrowserCameraCaptureController.avCaptureClientTransformation(
				for: .tonachrome,
				grainPresence: .high
			),
			Transformation(.high, .chromatic(.tonachrome))
		)
	}

	func testStartCaptureWithoutAuthorizationReportsDeniedFailure() async {
		let eventExpectation = expectation(description: "authorization denied event")
		let delegate = CaptureEventDelegateSpy()
		delegate.onEvent = { _ in eventExpectation.fulfill() }
		let controller = LiveBrowserCameraCaptureController(
			environment: .init(
				authorizationStatus: { .denied },
				findDevice: { _ in nil },
				makeSession: AVCaptureSession.init,
				makeDeviceInput: AVCaptureDeviceInput.init,
				notificationCenter: NotificationCenter()
			),
			sessionQueue: DispatchQueue(label: "LiveBrowserCameraCaptureControllerTests.auth")
		)
		controller.delegate = delegate

		controller.startCapture(
			with: BrowserCameraCaptureConfiguration(deviceID: "camera-a", filterPreset: .none)
		)

		await fulfillment(of: [eventExpectation], timeout: 1)
		XCTAssertEqual(delegate.events, [.didFail(.authorizationDenied)])
	}

	func testStartCaptureWithoutDeviceReportsSourceUnavailable() async {
		let eventExpectation = expectation(description: "missing source event")
		let delegate = CaptureEventDelegateSpy()
		delegate.onEvent = { _ in eventExpectation.fulfill() }
		let controller = LiveBrowserCameraCaptureController(
			environment: .init(
				authorizationStatus: { .authorized },
				findDevice: { _ in nil },
				makeSession: AVCaptureSession.init,
				makeDeviceInput: AVCaptureDeviceInput.init,
				notificationCenter: NotificationCenter()
			),
			sessionQueue: DispatchQueue(label: "LiveBrowserCameraCaptureControllerTests.missingDevice")
		)
		controller.delegate = delegate

		controller.startCapture(
			with: BrowserCameraCaptureConfiguration(deviceID: "camera-a", filterPreset: .none)
		)

		await fulfillment(of: [eventExpectation], timeout: 1)
		XCTAssertEqual(delegate.events, [.didFail(.sourceUnavailable(deviceID: "camera-a"))])
	}

	func testStopCaptureWithoutRunningSessionReportsStoppedEvent() async {
		let eventExpectation = expectation(description: "stopped event")
		let delegate = CaptureEventDelegateSpy()
		delegate.onEvent = { _ in eventExpectation.fulfill() }
		let controller = LiveBrowserCameraCaptureController(
			environment: .init(
				authorizationStatus: { .authorized },
				findDevice: { _ in nil },
				makeSession: AVCaptureSession.init,
				makeDeviceInput: AVCaptureDeviceInput.init,
				notificationCenter: NotificationCenter()
			),
			sessionQueue: DispatchQueue(label: "LiveBrowserCameraCaptureControllerTests.stop")
		)
		controller.delegate = delegate

		controller.stopCapture()

		await fulfillment(of: [eventExpectation], timeout: 1)
		XCTAssertEqual(delegate.events, [.didStop(deviceID: nil)])
	}

	func testRuntimeErrorNotificationReportsFailure() async {
		let notificationCenter = NotificationCenter()
		let session = AVCaptureSession()
		let eventExpectation = expectation(description: "runtime error event")
		let delegate = CaptureEventDelegateSpy()
		delegate.onEvent = { _ in eventExpectation.fulfill() }
		let controller = LiveBrowserCameraCaptureController(
			environment: .init(
				authorizationStatus: { .authorized },
				findDevice: { _ in nil },
				makeSession: { session },
				makeDeviceInput: AVCaptureDeviceInput.init,
				notificationCenter: notificationCenter
			),
			sessionQueue: DispatchQueue(label: "LiveBrowserCameraCaptureControllerTests.runtimeError")
		)
		controller.delegate = delegate

		notificationCenter.post(
			name: .AVCaptureSessionRuntimeError,
			object: session,
			userInfo: [
				AVCaptureSessionErrorKey: NSError(
					domain: AVFoundationErrorDomain,
					code: -11819,
					userInfo: [NSLocalizedDescriptionKey: "Camera runtime failed."]
				),
			]
		)

		await fulfillment(of: [eventExpectation], timeout: 1)
		XCTAssertEqual(
			delegate.events,
			[.didFail(.runtimeFailure(description: "Camera runtime failed."))]
		)
	}

	func testInterruptionNotificationReportsFailure() async {
		let notificationCenter = NotificationCenter()
		let session = AVCaptureSession()
		let eventExpectation = expectation(description: "interruption event")
		let delegate = CaptureEventDelegateSpy()
		delegate.onEvent = { _ in eventExpectation.fulfill() }
		let controller = LiveBrowserCameraCaptureController(
			environment: .init(
				authorizationStatus: { .authorized },
				findDevice: { _ in nil },
				makeSession: { session },
				makeDeviceInput: AVCaptureDeviceInput.init,
				notificationCenter: notificationCenter
			),
			sessionQueue: DispatchQueue(label: "LiveBrowserCameraCaptureControllerTests.interruption")
		)
		controller.delegate = delegate

		notificationCenter.post(
			name: .AVCaptureSessionWasInterrupted,
			object: session
		)

		await fulfillment(of: [eventExpectation], timeout: 1)
		XCTAssertEqual(
			delegate.events,
			[.didFail(.interrupted(description: "The camera capture session was interrupted."))]
		)
	}

	func testStartCaptureWithScreenInputReportsStartedEvent() async throws {
		let device = try cameraDevice()
		let session = AVCaptureSession()
		let eventExpectation = expectation(description: "started event")
		let delegate = CaptureEventDelegateSpy()
		delegate.onEvent = { _ in eventExpectation.fulfill() }
		let controller = LiveBrowserCameraCaptureController(
			environment: .init(
				authorizationStatus: { .authorized },
				findDevice: { deviceID in
					deviceID == device.uniqueID ? device : nil
				},
				makeSession: { session },
				makeDeviceInput: { _ in
					try Self.screenInput()
				},
				notificationCenter: NotificationCenter()
			),
			sessionQueue: DispatchQueue(label: "LiveBrowserCameraCaptureControllerTests.started")
		)
		controller.delegate = delegate

		controller.startCapture(
			with: BrowserCameraCaptureConfiguration(deviceID: device.uniqueID, filterPreset: .none)
		)

		await fulfillment(of: [eventExpectation], timeout: 1)
		XCTAssertEqual(delegate.events, [.didStartRunning(deviceID: device.uniqueID)])
		XCTAssertTrue(session.isRunning)
	}

	func testStartCaptureWithThrowingInputFactoryReportsConfigurationFailure() async throws {
		let device = try cameraDevice()
		let eventExpectation = expectation(description: "configuration failure event")
		let delegate = CaptureEventDelegateSpy()
		delegate.onEvent = { _ in eventExpectation.fulfill() }
		let controller = LiveBrowserCameraCaptureController(
			environment: .init(
				authorizationStatus: { .authorized },
				findDevice: { _ in device },
				makeSession: AVCaptureSession.init,
				makeDeviceInput: { _ in
					throw NSError(
						domain: "LiveBrowserCameraCaptureControllerTests",
						code: 77,
						userInfo: [NSLocalizedDescriptionKey: "Synthetic configuration failure."]
					)
				},
				notificationCenter: NotificationCenter()
			),
			sessionQueue: DispatchQueue(label: "LiveBrowserCameraCaptureControllerTests.configFailure")
		)
		controller.delegate = delegate

		controller.startCapture(
			with: BrowserCameraCaptureConfiguration(deviceID: device.uniqueID, filterPreset: .none)
		)

		await fulfillment(of: [eventExpectation], timeout: 1)
		XCTAssertEqual(
			delegate.events,
			[.didFail(.sessionConfigurationFailed(description: "Synthetic configuration failure."))]
		)
	}

	func testStartCaptureWithFailingFrameProcessorReportsPipelineUnavailable() async throws {
		let device = try cameraDevice()
		let eventExpectation = expectation(description: "pipeline failure event")
		let delegate = CaptureEventDelegateSpy()
		delegate.onEvent = { _ in eventExpectation.fulfill() }
		let controller = LiveBrowserCameraCaptureController(
			environment: .init(
				authorizationStatus: { .authorized },
				findDevice: { _ in device },
				makeSession: AVCaptureSession.init,
				makeDeviceInput: { _ in try Self.screenInput() },
				notificationCenter: NotificationCenter()
			),
			frameProcessor: FailingFrameProcessor(),
			sessionQueue: DispatchQueue(label: "LiveBrowserCameraCaptureControllerTests.pipelineFailure")
		)
		controller.delegate = delegate

		controller.startCapture(
			with: BrowserCameraCaptureConfiguration(deviceID: device.uniqueID, filterPreset: .folia)
		)

		await fulfillment(of: [eventExpectation], timeout: 1)
		XCTAssertEqual(
			delegate.events,
			[
				.didFail(
					.pipelineUnavailable(description: "Synthetic frame processor failure.")
				),
			]
		)
	}

	func testDeviceDisconnectNotificationStopsAndReportsSourceLost() async throws {
		let device = try cameraDevice()
		let notificationCenter = NotificationCenter()
		let session = AVCaptureSession()
		let startedExpectation = expectation(description: "started event")
		let disconnectExpectation = expectation(description: "disconnect events")
		let delegate = CaptureEventDelegateSpy()
		delegate.onEvent = { [weak delegate] _ in
			guard let delegate else { return }
			switch delegate.events.count {
			case 1:
				startedExpectation.fulfill()
			case 3:
				disconnectExpectation.fulfill()
			default:
				break
			}
		}
		let controller = LiveBrowserCameraCaptureController(
			environment: .init(
				authorizationStatus: { .authorized },
				findDevice: { _ in device },
				makeSession: { session },
				makeDeviceInput: { _ in try Self.screenInput() },
				notificationCenter: notificationCenter
			),
			sessionQueue: DispatchQueue(label: "LiveBrowserCameraCaptureControllerTests.disconnect")
		)
		controller.delegate = delegate

		controller.startCapture(
			with: BrowserCameraCaptureConfiguration(deviceID: device.uniqueID, filterPreset: .none)
		)
		await fulfillment(of: [startedExpectation], timeout: 1)

		notificationCenter.post(name: .AVCaptureDeviceWasDisconnected, object: device)

		await fulfillment(of: [disconnectExpectation], timeout: 1)
		XCTAssertEqual(
			delegate.events,
			[
				.didStartRunning(deviceID: device.uniqueID),
				.didStop(deviceID: device.uniqueID),
				.sourceWasLost(deviceID: device.uniqueID),
			]
		)
		XCTAssertFalse(session.isRunning)
	}

	func testInterruptionEndedNotificationRestartsRunningSession() async throws {
		let device = try cameraDevice()
		let notificationCenter = NotificationCenter()
		let session = AVCaptureSession()
		let startedExpectation = expectation(description: "initial start event")
		let restartExpectation = expectation(description: "restart event")
		let delegate = CaptureEventDelegateSpy()
		delegate.onEvent = { [weak delegate] _ in
			guard let delegate else { return }
			switch delegate.events.count {
			case 1:
				startedExpectation.fulfill()
			case 2:
				restartExpectation.fulfill()
			default:
				break
			}
		}
		let controller = LiveBrowserCameraCaptureController(
			environment: .init(
				authorizationStatus: { .authorized },
				findDevice: { _ in device },
				makeSession: { session },
				makeDeviceInput: { _ in try Self.screenInput() },
				notificationCenter: notificationCenter
			),
			sessionQueue: DispatchQueue(label: "LiveBrowserCameraCaptureControllerTests.interruptionEnded")
		)
		controller.delegate = delegate

		controller.startCapture(
			with: BrowserCameraCaptureConfiguration(deviceID: device.uniqueID, filterPreset: .none)
		)
		await fulfillment(of: [startedExpectation], timeout: 1)

		session.stopRunning()
		notificationCenter.post(name: .AVCaptureSessionInterruptionEnded, object: session)

		await fulfillment(of: [restartExpectation], timeout: 1)
		XCTAssertEqual(
			delegate.events,
			[
				.didStartRunning(deviceID: device.uniqueID),
				.didStartRunning(deviceID: device.uniqueID),
			]
		)
		XCTAssertTrue(session.isRunning)
	}

	func testLiveEnvironmentResolvesKnownDeviceAndCreatesSession() throws {
		let device = try cameraDevice()
		let environment = LiveBrowserCameraCaptureController.Environment.live()

		XCTAssertNotNil(environment.findDevice(device.uniqueID))
		XCTAssertNotNil(environment.makeSession())
		_ = environment.authorizationStatus()
	}

	func testLiveEnvironmentMakeDeviceInputDoesNotCrash() throws {
		let device = try cameraDevice()
		let environment = LiveBrowserCameraCaptureController.Environment.live()

		do {
			_ = try environment.makeDeviceInput(device)
		}
		catch {
			XCTAssertFalse(error.localizedDescription.isEmpty)
		}
	}

	func testRestartingCaptureReplacesExistingInput() async throws {
		let device = try cameraDevice()
		let session = CaptureSessionSpy()
		let completionExpectation = expectation(description: "two start events")
		completionExpectation.expectedFulfillmentCount = 2
		let delegate = CaptureEventDelegateSpy()
		delegate.onEvent = { _ in completionExpectation.fulfill() }
		let controller = LiveBrowserCameraCaptureController(
			environment: .init(
				authorizationStatus: { .authorized },
				findDevice: { _ in device },
				makeSession: { session },
				makeDeviceInput: { _ in try Self.screenInput() },
				notificationCenter: NotificationCenter()
			),
			sessionQueue: DispatchQueue(label: "LiveBrowserCameraCaptureControllerTests.reconfigure")
		)
		controller.delegate = delegate

		controller.startCapture(
			with: BrowserCameraCaptureConfiguration(deviceID: device.uniqueID, filterPreset: .none)
		)
		controller.startCapture(
			with: BrowserCameraCaptureConfiguration(deviceID: device.uniqueID, filterPreset: .folia)
		)

		await fulfillment(of: [completionExpectation], timeout: 1)
		XCTAssertEqual(session.addInputCount, 2)
		XCTAssertEqual(session.removeInputCount, 1)
		XCTAssertEqual(
			delegate.events,
			[
				.didStartRunning(deviceID: device.uniqueID),
				.didStartRunning(deviceID: device.uniqueID),
			]
		)
	}

	func testUpdatingCaptureConfigurationDoesNotReplaceExistingInput() async throws {
		let device = try cameraDevice()
		let session = CaptureSessionSpy()
		let startedExpectation = expectation(description: "initial start event")
		let noAdditionalStartExpectation = expectation(description: "no second start event")
		noAdditionalStartExpectation.isInverted = true
		let delegate = CaptureEventDelegateSpy()
		delegate.onEvent = { [weak delegate] event in
			guard let delegate else { return }
			if delegate.events.count == 1, case .didStartRunning = event {
				startedExpectation.fulfill()
				return
			}
			if delegate.events.count > 1, case .didStartRunning = event {
				noAdditionalStartExpectation.fulfill()
			}
		}
		let controller = LiveBrowserCameraCaptureController(
			environment: .init(
				authorizationStatus: { .authorized },
				findDevice: { _ in device },
				makeSession: { session },
				makeDeviceInput: { _ in try Self.screenInput() },
				notificationCenter: NotificationCenter()
			),
			sessionQueue: DispatchQueue(label: "LiveBrowserCameraCaptureControllerTests.inlineUpdate")
		)
		controller.delegate = delegate

		controller.startCapture(
			with: BrowserCameraCaptureConfiguration(deviceID: device.uniqueID, filterPreset: .none)
		)
		await fulfillment(of: [startedExpectation], timeout: 1)

		controller.updateCaptureConfiguration(
			BrowserCameraCaptureConfiguration(
				deviceID: device.uniqueID,
				filterPreset: .folia,
				grainPresence: .high,
				prefersHorizontalFlip: true
			)
		)

		await fulfillment(of: [noAdditionalStartExpectation], timeout: 0.2)
		XCTAssertEqual(session.addInputCount, 1)
		XCTAssertEqual(session.removeInputCount, 0)
		XCTAssertEqual(delegate.events, [.didStartRunning(deviceID: device.uniqueID)])
	}

	func testSessionRejectingInputReportsConfigurationFailure() async throws {
		let device = try cameraDevice()
		let session = CaptureSessionSpy()
		session.canAddInputValue = false
		let eventExpectation = expectation(description: "session rejection failure")
		let delegate = CaptureEventDelegateSpy()
		delegate.onEvent = { _ in eventExpectation.fulfill() }
		let controller = LiveBrowserCameraCaptureController(
			environment: .init(
				authorizationStatus: { .authorized },
				findDevice: { _ in device },
				makeSession: { session },
				makeDeviceInput: { _ in try Self.screenInput() },
				notificationCenter: NotificationCenter()
			),
			sessionQueue: DispatchQueue(label: "LiveBrowserCameraCaptureControllerTests.rejectInput")
		)
		controller.delegate = delegate

		controller.startCapture(
			with: BrowserCameraCaptureConfiguration(deviceID: device.uniqueID, filterPreset: .none)
		)

		await fulfillment(of: [eventExpectation], timeout: 1)
		XCTAssertEqual(
			delegate.events,
			[
				.didFail(
					.sessionConfigurationFailed(
						description: "Unable to add camera input for \(device.localizedName)."
					)
				),
			]
		)
	}

	func testRuntimeErrorWithoutNSErrorUsesFallbackDescription() async {
		let notificationCenter = NotificationCenter()
		let session = AVCaptureSession()
		let eventExpectation = expectation(description: "fallback runtime error event")
		let delegate = CaptureEventDelegateSpy()
		delegate.onEvent = { _ in eventExpectation.fulfill() }
		let controller = LiveBrowserCameraCaptureController(
			environment: .init(
				authorizationStatus: { .authorized },
				findDevice: { _ in nil },
				makeSession: { session },
				makeDeviceInput: AVCaptureDeviceInput.init,
				notificationCenter: notificationCenter
			),
			sessionQueue: DispatchQueue(label: "LiveBrowserCameraCaptureControllerTests.runtimeErrorFallback")
		)
		controller.delegate = delegate

		notificationCenter.post(name: .AVCaptureSessionRuntimeError, object: session)

		await fulfillment(of: [eventExpectation], timeout: 1)
		XCTAssertEqual(
			delegate.events,
			[
				.didFail(
					.runtimeFailure(description: "The camera capture session reported a runtime error.")
				),
			]
		)
	}

	func testDeviceDisconnectNotificationWithNonDeviceObjectDoesNothing() async {
		let notificationCenter = NotificationCenter()
		let session = AVCaptureSession()
		let noEventExpectation = expectation(description: "no disconnect event")
		noEventExpectation.isInverted = true
		let delegate = CaptureEventDelegateSpy()
		delegate.onEvent = { _ in noEventExpectation.fulfill() }
		let controller = LiveBrowserCameraCaptureController(
			environment: .init(
				authorizationStatus: { .authorized },
				findDevice: { _ in nil },
				makeSession: { session },
				makeDeviceInput: AVCaptureDeviceInput.init,
				notificationCenter: notificationCenter
			),
			sessionQueue: DispatchQueue(label: "LiveBrowserCameraCaptureControllerTests.nonDeviceDisconnect")
		)
		controller.delegate = delegate

		notificationCenter.post(
			name: .AVCaptureDeviceWasDisconnected,
			object: NSObject()
		)

		await fulfillment(of: [noEventExpectation], timeout: 0.1)
		XCTAssertTrue(delegate.events.isEmpty)
	}

	func testDeviceDisconnectNotificationWithoutMatchingCurrentDeviceDoesNothing() async throws {
		let device = try cameraDevice()
		let notificationCenter = NotificationCenter()
		let session = AVCaptureSession()
		let noEventExpectation = expectation(description: "no matching disconnect event")
		noEventExpectation.isInverted = true
		let delegate = CaptureEventDelegateSpy()
		delegate.onEvent = { _ in noEventExpectation.fulfill() }
		let controller = LiveBrowserCameraCaptureController(
			environment: .init(
				authorizationStatus: { .authorized },
				findDevice: { _ in device },
				makeSession: { session },
				makeDeviceInput: AVCaptureDeviceInput.init,
				notificationCenter: notificationCenter
			),
			sessionQueue: DispatchQueue(label: "LiveBrowserCameraCaptureControllerTests.mismatchedDisconnect")
		)
		controller.delegate = delegate

		notificationCenter.post(name: .AVCaptureDeviceWasDisconnected, object: device)

		await fulfillment(of: [noEventExpectation], timeout: 0.1)
		XCTAssertTrue(delegate.events.isEmpty)
	}

	func testInterruptionEndedWithoutCurrentDeviceDoesNotEmitEvent() async {
		let notificationCenter = NotificationCenter()
		let session = AVCaptureSession()
		let noEventExpectation = expectation(description: "no restart event")
		noEventExpectation.isInverted = true
		let delegate = CaptureEventDelegateSpy()
		delegate.onEvent = { _ in noEventExpectation.fulfill() }
		let controller = LiveBrowserCameraCaptureController(
			environment: .init(
				authorizationStatus: { .authorized },
				findDevice: { _ in nil },
				makeSession: { session },
				makeDeviceInput: AVCaptureDeviceInput.init,
				notificationCenter: notificationCenter
			),
			sessionQueue: DispatchQueue(label: "LiveBrowserCameraCaptureControllerTests.noCurrentDevice")
		)
		controller.delegate = delegate

		notificationCenter.post(name: .AVCaptureSessionInterruptionEnded, object: session)

		await fulfillment(of: [noEventExpectation], timeout: 0.1)
		XCTAssertTrue(delegate.events.isEmpty)
	}

	func testHandleCapturedPixelBufferWithNilBufferDoesNothing() {
		let delegate = CaptureEventDelegateSpy()
		let controller = LiveBrowserCameraCaptureController(
			environment: .init(
				authorizationStatus: { .authorized },
				findDevice: { _ in nil },
				makeSession: AVCaptureSession.init,
				makeDeviceInput: AVCaptureDeviceInput.init,
				notificationCenter: NotificationCenter()
			),
			frameProcessor: RecordingFrameProcessor(),
			sessionQueue: DispatchQueue(label: "LiveBrowserCameraCaptureControllerTests.nilPixelBuffer")
		)
		controller.delegate = delegate

		controller.handleCapturedPixelBuffer(nil)

		XCTAssertTrue(delegate.events.isEmpty)
	}

	func testHandleCapturedPixelBufferProcessesFrameAndEmitsMetricsEvent() async throws {
		let metricsExpectation = expectation(description: "metrics event")
		let previewExpectation = expectation(description: "preview frame")
		let delegate = CaptureEventDelegateSpy()
		let previewFrameUpdater = BrowserCameraPreviewFrameUpdater(mainQueue: .main)
		let previewRecorder = PreviewFrameUpdaterRecorder(updater: previewFrameUpdater)
		previewRecorder.onFrame = { previewFrame in
			guard previewFrame != nil else { return }
			previewExpectation.fulfill()
		}
		delegate.onEvent = { event in
			guard case .didUpdateMetrics = event else { return }
			metricsExpectation.fulfill()
		}
		let frameProcessor = RecordingFrameProcessor()
		let controller = LiveBrowserCameraCaptureController(
			environment: .init(
				authorizationStatus: { .authorized },
				findDevice: { _ in nil },
				makeSession: AVCaptureSession.init,
				makeDeviceInput: AVCaptureDeviceInput.init,
				notificationCenter: NotificationCenter()
			),
			frameProcessor: frameProcessor,
			sessionQueue: DispatchQueue(label: "LiveBrowserCameraCaptureControllerTests.successfulProcessing"),
			previewFrameUpdater: previewFrameUpdater
		)
		controller.delegate = delegate

		try controller.handleCapturedPixelBuffer(makePixelBuffer())
		await fulfillment(of: [metricsExpectation, previewExpectation], timeout: 1)

		XCTAssertEqual(frameProcessor.processCallCount, 1)
		XCTAssertEqual(
			delegate.events,
			[
				.didUpdatePipelineRuntimeState(
					makePipelineRuntimeState(preset: .none)
				),
				.didUpdateMetrics(
					BrowserCameraPerformanceMetrics(
						processedFrameCount: 1,
						droppedFrameCount: 0,
						firstFrameLatencyMilliseconds: nil,
						averageProcessingLatencyMilliseconds: 2,
						lastProcessingLatencyMilliseconds: 2,
						realtimeBudgetExceeded: false
					)
				),
			]
		)
		XCTAssertEqual(previewFrameUpdater.previewFrame?.width, 2)
	}

	func testPreviewFramesAreThrottledBetweenProcessedFrames() async throws {
		let previewExpectation = expectation(description: "single preview frame")
		previewExpectation.expectedFulfillmentCount = 1
		let previewFrameUpdater = BrowserCameraPreviewFrameUpdater(mainQueue: .main)
		let previewRecorder = PreviewFrameUpdaterRecorder(updater: previewFrameUpdater)
		previewRecorder.onFrame = { previewFrame in
			guard previewFrame != nil else { return }
			previewExpectation.fulfill()
		}
		let controller = LiveBrowserCameraCaptureController(
			environment: .init(
				authorizationStatus: { .authorized },
				findDevice: { _ in nil },
				makeSession: AVCaptureSession.init,
				makeDeviceInput: AVCaptureDeviceInput.init,
				notificationCenter: NotificationCenter()
			),
			frameProcessor: RecordingFrameProcessor(),
			sessionQueue: DispatchQueue(label: "LiveBrowserCameraCaptureControllerTests.previewThrottle"),
			previewFrameUpdater: previewFrameUpdater
		)

		try controller.handleCapturedPixelBuffer(makePixelBuffer())
		try controller.handleCapturedPixelBuffer(makePixelBuffer())
		await fulfillment(of: [previewExpectation], timeout: 1)

		XCTAssertEqual(previewRecorder.frames.compactMap { $0 }.count, 1)
	}

	func testPreviewFramesResumeAtVideoCadence() async throws {
		let firstPreviewExpectation = expectation(description: "first preview frame")
		let secondPreviewExpectation = expectation(description: "second preview frame")
		let previewFrameUpdater = BrowserCameraPreviewFrameUpdater(mainQueue: .main)
		let previewRecorder = PreviewFrameUpdaterRecorder(updater: previewFrameUpdater)
		let frameProcessor = AlternatingPreviewFrameProcessor()
		var observedPreviewCount = 0
		previewRecorder.onFrame = { previewFrame in
			guard previewFrame != nil else { return }
			observedPreviewCount += 1
			if observedPreviewCount == 1 {
				firstPreviewExpectation.fulfill()
			}
			else if observedPreviewCount == 2 {
				secondPreviewExpectation.fulfill()
			}
		}
		let controller = LiveBrowserCameraCaptureController(
			environment: .init(
				authorizationStatus: { .authorized },
				findDevice: { _ in nil },
				makeSession: AVCaptureSession.init,
				makeDeviceInput: AVCaptureDeviceInput.init,
				notificationCenter: NotificationCenter()
			),
			frameProcessor: frameProcessor,
			sessionQueue: DispatchQueue(label: "LiveBrowserCameraCaptureControllerTests.previewCadence"),
			previewFrameUpdater: previewFrameUpdater
		)

		try controller.handleCapturedPixelBuffer(makePixelBuffer())
		await fulfillment(of: [firstPreviewExpectation], timeout: 1)
		try await Task.sleep(nanoseconds: 40_000_000)
		try controller.handleCapturedPixelBuffer(makePixelBuffer())
		await fulfillment(of: [secondPreviewExpectation], timeout: 1)

		XCTAssertEqual(previewRecorder.frames.compactMap { $0 }.count, 2)
		XCTAssertEqual(frameProcessor.processCallCount, 2)
	}

	func testProcessedFrameProducesVirtualPublisherPayload() async throws {
		let delegate = CaptureEventDelegateSpy()
		let publisherFrameExpectation = expectation(description: "virtual publisher frame")
		delegate.onVirtualPublisherFrame = { _ in
			publisherFrameExpectation.fulfill()
		}
		let controller = LiveBrowserCameraCaptureController(
			environment: .init(
				authorizationStatus: { .authorized },
				findDevice: { _ in nil },
				makeSession: AVCaptureSession.init,
				makeDeviceInput: AVCaptureDeviceInput.init,
				notificationCenter: NotificationCenter()
			),
			frameProcessor: RecordingFrameProcessor(),
			sessionQueue: DispatchQueue(label: "LiveBrowserCameraCaptureControllerTests.virtualPublisherFrame")
		)
		controller.delegate = delegate

		try controller.handleCapturedPixelBuffer(makePixelBuffer())

		await fulfillment(of: [publisherFrameExpectation], timeout: 1)
		XCTAssertEqual(delegate.virtualPublisherFrames.count, 1)
		XCTAssertEqual(delegate.virtualPublisherFrames.first?.pixelFormat, .bgra8888)
		XCTAssertEqual(delegate.virtualPublisherFrames.first?.data, Data([0x2A, 0x6A, 0xAA, 0xFF]))
	}

	func testPreviewFrameUpdaterCoalescesQueuedFrames() async throws {
		let updater = BrowserCameraPreviewFrameUpdater(mainQueue: .main)
		let firstFrame = try XCTUnwrap(makePreviewFrame(width: 2))
		let secondFrame = try XCTUnwrap(makePreviewFrame(width: 4))
		let thirdFrame = try XCTUnwrap(makePreviewFrame(width: 8))
		let deliveryExpectation = expectation(description: "coalesced preview deliveries")
		deliveryExpectation.expectedFulfillmentCount = 2
		var deliveredWidths = [Int]()
		let recorder = PreviewFrameUpdaterRecorder(updater: updater)
		recorder.onFrame = { previewFrame in
			guard let previewFrame else { return }
			deliveredWidths.append(previewFrame.width)
			deliveryExpectation.fulfill()
			if deliveredWidths.count == 1 {
				updater.publish(secondFrame)
				updater.publish(thirdFrame)
			}
		}

		updater.publish(firstFrame)

		await fulfillment(of: [deliveryExpectation], timeout: 1)
		XCTAssertEqual(deliveredWidths, [2, 8])
	}

	func testStableProcessingOnlyReportsAgainAtMetricsInterval() async throws {
		let firstMetricsExpectation = expectation(description: "first metrics event")
		let intervalMetricsExpectation = expectation(description: "interval metrics event")
		let delegate = CaptureEventDelegateSpy()
		var metricsEventCount = 0
		delegate.onEvent = { [weak delegate] event in
			guard case .didUpdateMetrics = event else { return }
			_ = delegate
			metricsEventCount += 1
			switch metricsEventCount {
			case 1:
				firstMetricsExpectation.fulfill()
			case 2:
				intervalMetricsExpectation.fulfill()
			default:
				break
			}
		}
		let controller = LiveBrowserCameraCaptureController(
			environment: .init(
				authorizationStatus: { .authorized },
				findDevice: { _ in nil },
				makeSession: AVCaptureSession.init,
				makeDeviceInput: AVCaptureDeviceInput.init,
				notificationCenter: NotificationCenter()
			),
			frameProcessor: RecordingFrameProcessor(),
			sessionQueue: DispatchQueue(label: "LiveBrowserCameraCaptureControllerTests.metricsInterval")
		)
		controller.delegate = delegate

		for _ in 0..<15 {
			try controller.handleCapturedPixelBuffer(makePixelBuffer())
		}
		await fulfillment(of: [firstMetricsExpectation, intervalMetricsExpectation], timeout: 1)

		XCTAssertEqual(
			delegate.events.filter {
				if case .didUpdateMetrics = $0 { return true }
				return false
			}.count,
			2
		)
	}

	func testStartCaptureThenProcessedFrameReportsFirstFrameLatency() async throws {
		let device = try cameraDevice()
		let startedExpectation = expectation(description: "started event")
		let metricsExpectation = expectation(description: "metrics event")
		let delegate = CaptureEventDelegateSpy()
		delegate.onEvent = { event in
			switch event {
			case .didStartRunning:
				startedExpectation.fulfill()
			case .didUpdateMetrics:
				metricsExpectation.fulfill()
			default:
				break
			}
		}
		let controller = LiveBrowserCameraCaptureController(
			environment: .init(
				authorizationStatus: { .authorized },
				findDevice: { _ in device },
				makeSession: AVCaptureSession.init,
				makeDeviceInput: { _ in try Self.screenInput() },
				notificationCenter: NotificationCenter()
			),
			frameProcessor: RecordingFrameProcessor(),
			sessionQueue: DispatchQueue(label: "LiveBrowserCameraCaptureControllerTests.firstFrameLatency")
		)
		controller.delegate = delegate

		controller.startCapture(
			with: BrowserCameraCaptureConfiguration(deviceID: device.uniqueID, filterPreset: .none)
		)
		await fulfillment(of: [startedExpectation], timeout: 1)

		try controller.handleCapturedPixelBuffer(makePixelBuffer())
		await fulfillment(of: [metricsExpectation], timeout: 1)

		guard case .didUpdateMetrics(let metrics)? = delegate.events.last else {
			return XCTFail("Expected metrics event.")
		}
		XCTAssertNotNil(metrics.firstFrameLatencyMilliseconds)
		XCTAssertFalse(metrics.realtimeBudgetExceeded)
	}

	func testHandleCapturedPixelBufferSuppressesRepeatedProcessingFailures() async throws {
		let failureExpectation = expectation(description: "single pipeline failure event")
		let delegate = CaptureEventDelegateSpy()
		delegate.onEvent = { _ in failureExpectation.fulfill() }
		let controller = LiveBrowserCameraCaptureController(
			environment: .init(
				authorizationStatus: { .authorized },
				findDevice: { _ in nil },
				makeSession: AVCaptureSession.init,
				makeDeviceInput: AVCaptureDeviceInput.init,
				notificationCenter: NotificationCenter()
			),
			frameProcessor: FailingProcessFrameProcessor(),
			sessionQueue: DispatchQueue(label: "LiveBrowserCameraCaptureControllerTests.failingProcessing")
		)
		controller.delegate = delegate
		let pixelBuffer = try makePixelBuffer()

		controller.handleCapturedPixelBuffer(pixelBuffer)
		await fulfillment(of: [failureExpectation], timeout: 1)
		controller.handleCapturedPixelBuffer(pixelBuffer)

		XCTAssertEqual(
			delegate.events,
			[
				.didFail(
					.pipelineUnavailable(description: "Synthetic frame processor failure.")
				),
			]
		)
	}

	func testHandleCapturedPixelBufferReportsGenericProcessingFailures() async throws {
		let genericFailureExpectation = expectation(description: "generic pipeline failure event")
		let delegate = CaptureEventDelegateSpy()
		delegate.onEvent = { _ in genericFailureExpectation.fulfill() }
		let controller = LiveBrowserCameraCaptureController(
			environment: .init(
				authorizationStatus: { .authorized },
				findDevice: { _ in nil },
				makeSession: AVCaptureSession.init,
				makeDeviceInput: AVCaptureDeviceInput.init,
				notificationCenter: NotificationCenter()
			),
			frameProcessor: GenericFailingProcessFrameProcessor(),
			sessionQueue: DispatchQueue(label: "LiveBrowserCameraCaptureControllerTests.genericFailingProcessing")
		)
		controller.delegate = delegate

		try controller.handleCapturedPixelBuffer(makePixelBuffer())

		await fulfillment(of: [genericFailureExpectation], timeout: 1)
		XCTAssertEqual(
			delegate.events,
			[
				.didFail(
					.pipelineUnavailable(description: "Synthetic generic frame processor failure.")
				),
			]
		)
	}

	func testCaptureOutputForwardsImageBuffersToPixelBufferHandler() async throws {
		let metricsExpectation = expectation(description: "capture output metrics event")
		let delegate = CaptureEventDelegateSpy()
		delegate.onEvent = { event in
			guard case .didUpdateMetrics = event else { return }
			metricsExpectation.fulfill()
		}
		let frameProcessor = RecordingFrameProcessor()
		let controller = LiveBrowserCameraCaptureController(
			environment: .init(
				authorizationStatus: { .authorized },
				findDevice: { _ in nil },
				makeSession: AVCaptureSession.init,
				makeDeviceInput: AVCaptureDeviceInput.init,
				notificationCenter: NotificationCenter()
			),
			frameProcessor: frameProcessor,
			sessionQueue: DispatchQueue(label: "LiveBrowserCameraCaptureControllerTests.captureOutputForwarding")
		)
		controller.delegate = delegate

		try controller.captureOutput(
			AVCaptureVideoDataOutput(),
			didOutput: makeSampleBuffer(),
			from: AVCaptureConnection(inputPorts: [], output: AVCaptureVideoDataOutput())
		)
		await fulfillment(of: [metricsExpectation], timeout: 1)

		XCTAssertEqual(frameProcessor.processCallCount, 1)
		XCTAssertEqual(delegate.events.count, 2)
	}

	func testCaptureOutputDidDropReportsMetricsWithDroppedFrames() async throws {
		let metricsExpectation = expectation(description: "drop metrics event")
		let delegate = CaptureEventDelegateSpy()
		delegate.onEvent = { _ in
			metricsExpectation.fulfill()
		}
		let controller = LiveBrowserCameraCaptureController(
			environment: .init(
				authorizationStatus: { .authorized },
				findDevice: { _ in nil },
				makeSession: AVCaptureSession.init,
				makeDeviceInput: AVCaptureDeviceInput.init,
				notificationCenter: NotificationCenter()
			),
			frameProcessor: RecordingFrameProcessor(),
			sessionQueue: DispatchQueue(label: "LiveBrowserCameraCaptureControllerTests.captureDrop")
		)
		controller.delegate = delegate

		try controller.captureOutput(
			AVCaptureVideoDataOutput(),
			didDrop: makeSampleBuffer(),
			from: AVCaptureConnection(inputPorts: [], output: AVCaptureVideoDataOutput())
		)
		await fulfillment(of: [metricsExpectation], timeout: 1)

		XCTAssertEqual(
			delegate.events,
			[
				.didUpdateMetrics(
					BrowserCameraPerformanceMetrics(
						processedFrameCount: 0,
						droppedFrameCount: 1,
						firstFrameLatencyMilliseconds: nil,
						averageProcessingLatencyMilliseconds: nil,
						lastProcessingLatencyMilliseconds: nil,
						realtimeBudgetExceeded: false
					)
				),
			]
		)
	}

	func testDroppedFrameAfterProcessedFramesReportsUpdatedDropMetrics() async throws {
		let firstMetricsExpectation = expectation(description: "first metrics event")
		let dropMetricsExpectation = expectation(description: "drop metrics event")
		let delegate = CaptureEventDelegateSpy()
		var metricsEventCount = 0
		delegate.onEvent = { [weak delegate] event in
			guard case .didUpdateMetrics = event else { return }
			_ = delegate
			metricsEventCount += 1
			switch metricsEventCount {
			case 1:
				firstMetricsExpectation.fulfill()
			case 2:
				dropMetricsExpectation.fulfill()
			default:
				break
			}
		}
		let controller = LiveBrowserCameraCaptureController(
			environment: .init(
				authorizationStatus: { .authorized },
				findDevice: { _ in nil },
				makeSession: AVCaptureSession.init,
				makeDeviceInput: AVCaptureDeviceInput.init,
				notificationCenter: NotificationCenter()
			),
			frameProcessor: RecordingFrameProcessor(),
			sessionQueue: DispatchQueue(label: "LiveBrowserCameraCaptureControllerTests.dropAfterFrames")
		)
		controller.delegate = delegate

		try controller.handleCapturedPixelBuffer(makePixelBuffer())
		try controller.handleCapturedPixelBuffer(makePixelBuffer())
		await fulfillment(of: [firstMetricsExpectation], timeout: 1)
		try controller.captureOutput(
			AVCaptureVideoDataOutput(),
			didDrop: makeSampleBuffer(),
			from: AVCaptureConnection(inputPorts: [], output: AVCaptureVideoDataOutput())
		)
		await fulfillment(of: [dropMetricsExpectation], timeout: 1)

		guard case .didUpdateMetrics(let metrics)? = delegate.events.last else {
			return XCTFail("Expected metrics event.")
		}
		XCTAssertEqual(metrics.processedFrameCount, 2)
		XCTAssertEqual(metrics.droppedFrameCount, 1)
	}

	func testSlowProcessingMetricsReportRealtimeBudgetExceeded() async throws {
		let metricsExpectation = expectation(description: "slow metrics event")
		let delegate = CaptureEventDelegateSpy()
		delegate.onEvent = { event in
			if case .didUpdateMetrics = event {
				metricsExpectation.fulfill()
			}
		}
		let controller = LiveBrowserCameraCaptureController(
			environment: .init(
				authorizationStatus: { .authorized },
				findDevice: { _ in nil },
				makeSession: AVCaptureSession.init,
				makeDeviceInput: AVCaptureDeviceInput.init,
				notificationCenter: NotificationCenter()
			),
			frameProcessor: SlowRecordingFrameProcessor(),
			sessionQueue: DispatchQueue(label: "LiveBrowserCameraCaptureControllerTests.slowProcessing")
		)
		controller.delegate = delegate

		try controller.handleCapturedPixelBuffer(makePixelBuffer())
		await fulfillment(of: [metricsExpectation], timeout: 1)

		guard case .didUpdateMetrics(let metrics)? = delegate.events.last else {
			return XCTFail("Expected metrics event.")
		}
		XCTAssertEqual(metrics.averageProcessingLatencyMilliseconds, 45)
		XCTAssertEqual(metrics.lastProcessingLatencyMilliseconds, 45)
		XCTAssertTrue(metrics.realtimeBudgetExceeded)
	}

	func testRealtimeBudgetFlipTriggersUpdatedMetricsEvent() async throws {
		let firstMetricsExpectation = expectation(description: "first metrics event")
		let degradedMetricsExpectation = expectation(description: "degraded metrics event")
		let delegate = CaptureEventDelegateSpy()
		var metricsEventCount = 0
		delegate.onEvent = { [weak delegate] event in
			guard case .didUpdateMetrics = event else { return }
			_ = delegate
			metricsEventCount += 1
			switch metricsEventCount {
			case 1:
				firstMetricsExpectation.fulfill()
			case 2:
				degradedMetricsExpectation.fulfill()
			default:
				break
			}
		}
		let controller = LiveBrowserCameraCaptureController(
			environment: .init(
				authorizationStatus: { .authorized },
				findDevice: { _ in nil },
				makeSession: AVCaptureSession.init,
				makeDeviceInput: AVCaptureDeviceInput.init,
				notificationCenter: NotificationCenter()
			),
			frameProcessor: FluctuatingLatencyFrameProcessor(),
			sessionQueue: DispatchQueue(label: "LiveBrowserCameraCaptureControllerTests.realtimeFlip")
		)
		controller.delegate = delegate

		try controller.handleCapturedPixelBuffer(makePixelBuffer())
		await fulfillment(of: [firstMetricsExpectation], timeout: 1)
		try controller.handleCapturedPixelBuffer(makePixelBuffer())
		await fulfillment(of: [degradedMetricsExpectation], timeout: 1)

		guard case .didUpdateMetrics(let metrics)? = delegate.events.last else {
			return XCTFail("Expected metrics event.")
		}
		XCTAssertTrue(metrics.realtimeBudgetExceeded)
	}

	func testRepeatedGenericProcessingFailuresAreSuppressed() async throws {
		let failureExpectation = expectation(description: "single generic failure event")
		let delegate = CaptureEventDelegateSpy()
		delegate.onEvent = { _ in failureExpectation.fulfill() }
		let controller = LiveBrowserCameraCaptureController(
			environment: .init(
				authorizationStatus: { .authorized },
				findDevice: { _ in nil },
				makeSession: AVCaptureSession.init,
				makeDeviceInput: AVCaptureDeviceInput.init,
				notificationCenter: NotificationCenter()
			),
			frameProcessor: GenericFailingProcessFrameProcessor(),
			sessionQueue: DispatchQueue(label: "LiveBrowserCameraCaptureControllerTests.repeatedGenericFailure")
		)
		controller.delegate = delegate
		let pixelBuffer = try makePixelBuffer()

		controller.handleCapturedPixelBuffer(pixelBuffer)
		await fulfillment(of: [failureExpectation], timeout: 1)
		controller.handleCapturedPixelBuffer(pixelBuffer)

		XCTAssertEqual(delegate.events.count, 1)
	}

	private func cameraDevice() throws -> AVCaptureDevice {
		guard let device = AVCaptureDevice.DiscoverySession(
			deviceTypes: [
				.builtInWideAngleCamera,
				.external,
			],
			mediaType: .video,
			position: .unspecified
		).devices.first else {
			throw XCTSkip("No capture device is available for the live adapter tests.")
		}
		return device
	}

	private func makePixelBuffer() throws -> CVPixelBuffer {
		var pixelBuffer: CVPixelBuffer?
		let status = CVPixelBufferCreate(
			kCFAllocatorDefault,
			32,
			32,
			kCVPixelFormatType_32BGRA,
			[
				kCVPixelBufferCGImageCompatibilityKey: true,
				kCVPixelBufferCGBitmapContextCompatibilityKey: true,
			] as CFDictionary,
			&pixelBuffer
		)
		guard status == kCVReturnSuccess, let pixelBuffer else {
			throw XCTSkip("Unable to create a test pixel buffer.")
		}

		CVPixelBufferLockBaseAddress(pixelBuffer, [])
		defer {
			CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
		}

		guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
			throw XCTSkip("Unable to access the test pixel buffer.")
		}
		memset(baseAddress, 0x4F, CVPixelBufferGetDataSize(pixelBuffer))
		return pixelBuffer
	}

	private func makeSampleBuffer() throws -> CMSampleBuffer {
		let pixelBuffer = try makePixelBuffer()
		var formatDescription: CMVideoFormatDescription?
		let descriptionStatus = CMVideoFormatDescriptionCreateForImageBuffer(
			allocator: kCFAllocatorDefault,
			imageBuffer: pixelBuffer,
			formatDescriptionOut: &formatDescription
		)
		guard descriptionStatus == noErr, let formatDescription else {
			throw XCTSkip("Unable to create a video format description.")
		}

		var sampleBuffer: CMSampleBuffer?
		var timing = CMSampleTimingInfo(
			duration: CMTime(value: 1, timescale: 30),
			presentationTimeStamp: .zero,
			decodeTimeStamp: .invalid
		)
		let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(
			allocator: kCFAllocatorDefault,
			imageBuffer: pixelBuffer,
			formatDescription: formatDescription,
			sampleTiming: &timing,
			sampleBufferOut: &sampleBuffer
		)
		guard sampleStatus == noErr, let sampleBuffer else {
			throw XCTSkip("Unable to create a test sample buffer.")
		}
		return sampleBuffer
	}

	private static func screenInput() throws -> AVCaptureScreenInput {
		guard let input = AVCaptureScreenInput(displayID: CGMainDisplayID()) else {
			throw NSError(
				domain: "LiveBrowserCameraCaptureControllerTests",
				code: 88,
				userInfo: [NSLocalizedDescriptionKey: "Unable to create a screen capture input."]
			)
		}
		return input
	}
}

@MainActor
private final class CaptureEventDelegateSpy: NSObject, BrowserCameraCaptureControllingDelegate {
	private(set) var events = [BrowserCameraCaptureEvent]()
	private(set) var virtualPublisherFrames = [BrowserCameraVirtualOutputFrame]()
	var onEvent: ((BrowserCameraCaptureEvent) -> Void)?
	var onVirtualPublisherFrame: ((BrowserCameraVirtualOutputFrame) -> Void)?

	func browserCameraCaptureControllerDidReceiveEvent(_ event: BrowserCameraCaptureEvent) {
		events.append(event)
		onEvent?(event)
	}

	func browserCameraCaptureControllerDidOutputPreviewFrame(_ previewFrame: BrowserCameraPreviewFrame?) {}

	func browserCameraCaptureControllerDidOutputVirtualPublisherFrame(
		data: Data,
		width: Int,
		height: Int,
		bytesPerRow: Int,
		pixelFormat: BrowserCameraVirtualPublisherPixelFormat,
		timestampHostTime: UInt64,
		durationHostTime: UInt64
	) {
		let frame = BrowserCameraVirtualOutputFrame(
			data: data,
			width: width,
			height: height,
			bytesPerRow: bytesPerRow,
			pixelFormat: pixelFormat,
			timestampHostTime: timestampHostTime,
			durationHostTime: durationHostTime
		)
		virtualPublisherFrames.append(frame)
		onVirtualPublisherFrame?(frame)
	}

	func browserCameraCaptureControllerDidOutputVirtualPublisherFrame(
		_ frame: BrowserCameraVirtualOutputFrame
	) {
		virtualPublisherFrames.append(frame)
		onVirtualPublisherFrame?(frame)
	}
}

private final class CaptureSessionSpy: AVCaptureSession {
	var addInputCount = 0
	var removeInputCount = 0
	var canAddInputValue = true

	override func canAddInput(_ input: AVCaptureInput) -> Bool {
		canAddInputValue
	}

	override func addInput(_ input: AVCaptureInput) {
		addInputCount += 1
		super.addInput(input)
	}

	override func addInputWithNoConnections(_ input: AVCaptureInput) {
		addInputCount += 1
		super.addInputWithNoConnections(input)
	}

	override func removeInput(_ input: AVCaptureInput) {
		removeInputCount += 1
		super.removeInput(input)
	}
}

private final class FailingFrameProcessor: BrowserCameraFrameProcessing {
	func warmIfNeeded(for preset: BrowserCameraFilterPreset) throws {
		throw BrowserCameraFrameProcessingError.renderFailed(
			description: "Synthetic frame processor failure."
		)
	}

	func process(
		pixelBuffer: CVPixelBuffer,
		preset: BrowserCameraFilterPreset,
		devicePosition: AVCaptureDevice.Position
	) throws -> BrowserCameraProcessedFrame {
		XCTFail("process(pixelBuffer:preset:devicePosition:) should not be called")
		return try BrowserCameraProcessedFrame(
			previewImage: Self.previewImage(),
			pixelData: Data([0x2A, 0x6A, 0xAA, 0xFF]),
			pixelWidth: 2,
			pixelHeight: 2,
			bytesPerRow: 4,
			processingLatency: 0,
			pipelineRuntimeState: makePipelineRuntimeState(preset: preset)
		)
	}

	private static func previewImage() throws -> CGImage {
		guard let image = previewImageCache else {
			throw XCTSkip("Unable to create a preview image.")
		}
		return image
	}

	private static let previewImageCache = makeSolidPreviewImage()
}

private final class FailingProcessFrameProcessor: BrowserCameraFrameProcessing {
	func warmIfNeeded(for preset: BrowserCameraFilterPreset) throws {}

	func process(
		pixelBuffer: CVPixelBuffer,
		preset: BrowserCameraFilterPreset,
		devicePosition: AVCaptureDevice.Position
	) throws -> BrowserCameraProcessedFrame {
		throw BrowserCameraFrameProcessingError.renderFailed(
			description: "Synthetic frame processor failure."
		)
	}
}

private final class RecordingFrameProcessor: BrowserCameraFrameProcessing {
	private(set) var processCallCount = 0

	func warmIfNeeded(for preset: BrowserCameraFilterPreset) throws {}

	func process(
		pixelBuffer: CVPixelBuffer,
		preset: BrowserCameraFilterPreset,
		devicePosition: AVCaptureDevice.Position
	) throws -> BrowserCameraProcessedFrame {
		processCallCount += 1
		return BrowserCameraProcessedFrame(
			previewImage: Self.previewImage,
			pixelData: Data([0x2A, 0x6A, 0xAA, 0xFF]),
			pixelWidth: 2,
			pixelHeight: 2,
			bytesPerRow: 4,
			processingLatency: 0.002,
			pipelineRuntimeState: makePipelineRuntimeState(preset: preset)
		)
	}

	private static let previewImage = makeSolidPreviewImage()!
}

private final class AlternatingPreviewFrameProcessor: BrowserCameraFrameProcessing {
	private(set) var processCallCount = 0

	func warmIfNeeded(for preset: BrowserCameraFilterPreset) throws {}

	func process(
		pixelBuffer: CVPixelBuffer,
		preset: BrowserCameraFilterPreset,
		devicePosition: AVCaptureDevice.Position
	) throws -> BrowserCameraProcessedFrame {
		processCallCount += 1
		let previewImage = Self.previewImage(for: processCallCount)
		return BrowserCameraProcessedFrame(
			previewImage: previewImage,
			pixelData: Data([0x2A, 0x6A, 0xAA, 0xFF]),
			pixelWidth: 2,
			pixelHeight: 2,
			bytesPerRow: 4,
			processingLatency: 0.002,
			pipelineRuntimeState: makePipelineRuntimeState(preset: preset)
		)
	}

	private static func previewImage(for call: Int) -> CGImage {
		call == 1 ? previewImage2 : previewImage1
	}

	private static let previewImage1 = makePreviewImage(width: 2)!
	private static let previewImage2 = makePreviewImage(width: 4)!
}

private final class SlowRecordingFrameProcessor: BrowserCameraFrameProcessing {
	func warmIfNeeded(for preset: BrowserCameraFilterPreset) throws {}

	func process(
		pixelBuffer: CVPixelBuffer,
		preset: BrowserCameraFilterPreset,
		devicePosition: AVCaptureDevice.Position
	) throws -> BrowserCameraProcessedFrame {
		BrowserCameraProcessedFrame(
			previewImage: Self.previewImage,
			pixelData: Data([0x2A, 0x6A, 0xAA, 0xFF]),
			pixelWidth: 2,
			pixelHeight: 2,
			bytesPerRow: 4,
			processingLatency: 0.045,
			pipelineRuntimeState: makePipelineRuntimeState(
				preset: preset,
				implementation: .navigatorFallback
			)
		)
	}

	private static let previewImage = makeSolidPreviewImage()!
}

private final class FluctuatingLatencyFrameProcessor: BrowserCameraFrameProcessing {
	private var processCallCount = 0

	func warmIfNeeded(for preset: BrowserCameraFilterPreset) throws {}

	func process(
		pixelBuffer: CVPixelBuffer,
		preset: BrowserCameraFilterPreset,
		devicePosition: AVCaptureDevice.Position
	) throws -> BrowserCameraProcessedFrame {
		processCallCount += 1
		return BrowserCameraProcessedFrame(
			previewImage: Self.previewImage,
			pixelData: Data([0x2A, 0x6A, 0xAA, 0xFF]),
			pixelWidth: 2,
			pixelHeight: 2,
			bytesPerRow: 4,
			processingLatency: processCallCount == 1 ? 0.002 : 0.080,
			pipelineRuntimeState: makePipelineRuntimeState(
				preset: preset,
				implementation: processCallCount == 1 ? .aperture : .navigatorFallback
			)
		)
	}

	private static let previewImage = makeSolidPreviewImage()!
}

private final class GenericFailingProcessFrameProcessor: BrowserCameraFrameProcessing {
	func warmIfNeeded(for preset: BrowserCameraFilterPreset) throws {}

	func process(
		pixelBuffer: CVPixelBuffer,
		preset: BrowserCameraFilterPreset,
		devicePosition: AVCaptureDevice.Position
	) throws -> BrowserCameraProcessedFrame {
		throw NSError(
			domain: "LiveBrowserCameraCaptureControllerTests",
			code: 19,
			userInfo: [NSLocalizedDescriptionKey: "Synthetic generic frame processor failure."]
		)
	}
}

@MainActor
private final class PreviewFrameUpdaterRecorder {
	private let updater: BrowserCameraPreviewFrameUpdater
	private(set) var frames = [CGImage?]()
	var onFrame: ((CGImage?) -> Void)?

	init(updater: BrowserCameraPreviewFrameUpdater) {
		self.updater = updater
		startObserving()
	}

	private func startObserving() {
		withObservationTracking {
			_ = updater.previewFrame
		} onChange: { [weak self] in
			Task { @MainActor [weak self] in
				guard let self else { return }
				let frame = self.updater.previewFrame
				self.frames.append(frame)
				self.onFrame?(frame)
				self.startObserving()
			}
		}
	}
}

private func makePipelineRuntimeState(
	preset: BrowserCameraFilterPreset,
	implementation: BrowserCameraPipelineImplementation = .passthrough
) -> BrowserCameraPipelineRuntimeState {
	BrowserCameraPipelineRuntimeState(
		preset: preset,
		implementation: implementation,
		warmupProfile: implementation == .passthrough ? .passthrough : .chromaticFolia,
		grainPresence: implementation == .navigatorFallback ? .normal : .none,
		requiredFilterCount: implementation == .passthrough ? 0 : 3
	)
}

private func makePreviewFrame(width: Int) -> BrowserCameraPreviewFrame? {
	makePreviewImage(width: width).map(BrowserCameraPreviewFrame.init(image:))
}

private func makeSolidPreviewImage() -> CGImage? {
	makePreviewImage(width: 2)
}

private func makePreviewImage(width: Int) -> CGImage? {
	let colorSpace = CGColorSpaceCreateDeviceRGB()
	let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
	let bytesPerPixel = 4
	guard width > 0 else { return nil }
	let height = 2
	let bytesPerRow = width * bytesPerPixel
	let pixel: [UInt8] = [0x4F, 0x7F, 0xB0, 0xFF]
	let bytes = Array(repeating: pixel, count: width * height).flatMap { $0 }
	guard let provider = CGDataProvider(data: Data(bytes) as CFData) else {
		return nil
	}
	return CGImage(
		width: width,
		height: height,
		bitsPerComponent: 8,
		bitsPerPixel: 32,
		bytesPerRow: bytesPerRow,
		space: colorSpace,
		bitmapInfo: bitmapInfo,
		provider: provider,
		decode: nil,
		shouldInterpolate: false,
		intent: .defaultIntent
	)
}
