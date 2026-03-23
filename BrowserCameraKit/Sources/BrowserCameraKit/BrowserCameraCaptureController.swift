@preconcurrency import AVFoundation
import Combine
import CoreGraphics
import Foundation
import ModelKit
import Observation
import OSLog
import Pipeline
import Shared

private enum BrowserCameraPreviewFramePublishingFeatureFlag {
	static func isDisabled(environment _: [String: String]) -> Bool {
		return false
	}
}

private enum BrowserCameraVirtualFramePublishingFeatureFlag {
	static func isDisabled(environment _: [String: String]) -> Bool {
		return false
	}
}

protocol BrowserCameraCaptureControlling: AnyObject {
	var delegate: (any BrowserCameraCaptureControllingDelegate)? { get set }
	func startCapture(with configuration: BrowserCameraCaptureConfiguration)
	func updateCaptureConfiguration(_ configuration: BrowserCameraCaptureConfiguration)
	func stopCapture()
}

@MainActor
protocol BrowserCameraCaptureControllingDelegate: AnyObject {
	func browserCameraCaptureControllerDidReceiveEvent(_ event: BrowserCameraCaptureEvent)
	func browserCameraCaptureControllerDidOutputPreviewFrame(_ previewFrame: BrowserCameraPreviewFrame?)
	func browserCameraCaptureControllerDidOutputVirtualPublisherFrame(
		_ frame: BrowserCameraVirtualOutputFrame
	)
}

@MainActor
extension BrowserCameraCaptureControllingDelegate {
	func browserCameraCaptureControllerDidOutputVirtualPublisherFrame(
		data: Data,
		width: Int,
		height: Int,
		bytesPerRow: Int,
		pixelFormat: BrowserCameraVirtualPublisherPixelFormat,
		timestampHostTime: UInt64,
		durationHostTime: UInt64
	) {
		browserCameraCaptureControllerDidOutputVirtualPublisherFrame(
			BrowserCameraVirtualOutputFrame(
				data: data,
				width: width,
				height: height,
				bytesPerRow: bytesPerRow,
				pixelFormat: pixelFormat,
				timestampHostTime: timestampHostTime,
				durationHostTime: durationHostTime
			)
		)
	}

	func browserCameraCaptureControllerDidOutputVirtualPublisherFrame(
		_ frame: BrowserCameraVirtualOutputFrame
	) {}
}

struct BrowserCameraPreviewFrame: @unchecked Sendable {
	let image: CGImage
}

@Observable
public final class BrowserCameraPreviewFrameUpdater: @unchecked Sendable {
	public static let shared = BrowserCameraPreviewFrameUpdater()

	public private(set) var previewFrame: CGImage?

	private let mainQueue: DispatchQueue
	private let stateQueue = DispatchQueue(label: "navigator.browserCamera.previewFrameUpdater")
	private var pendingFrame: BrowserCameraPreviewFrame?
	private var hasPendingFrame = false
	private var isFlushScheduled = false
	private var observers = [UUID: @MainActor (CGImage?) -> Void]()

	public init(mainQueue: DispatchQueue = .main) {
		self.mainQueue = mainQueue
	}

	func publish(_ previewFrame: BrowserCameraPreviewFrame?) {
		let shouldScheduleFlush = stateQueue.sync {
			pendingFrame = previewFrame
			hasPendingFrame = true
			// Keep latest frame for coalescing while preserving single-frame in-flight publication.
			guard isFlushScheduled == false else { return false }
			isFlushScheduled = true
			return true
		}
		guard shouldScheduleFlush else { return }

		mainQueue.async { [weak self] in
			guard let self else { return }
			Task { @MainActor in
				self.flushPendingFrames()
			}
		}
	}

	public func publishImage(_ previewImage: CGImage?) {
		publish(previewImage.map(BrowserCameraPreviewFrame.init(image:)))
	}

	@discardableResult
	public func addObserver(
		_ observer: @escaping @MainActor (CGImage?) -> Void
	) -> UUID {
		let observerID = UUID()
		let currentFrame = stateQueue.sync {
			observers[observerID] = observer
			return previewFrame
		}
		Task { @MainActor in
			observer(currentFrame)
		}
		return observerID
	}

	public func removeObserver(id: UUID) {
		_ = stateQueue.sync {
			observers.removeValue(forKey: id)
		}
	}

	@MainActor
	private func flushPendingFrames() {
		while true {
			let nextFrame: (
				hasFrame: Bool,
				frame: BrowserCameraPreviewFrame?,
				observers: [@MainActor (CGImage?) -> Void]
			) = stateQueue.sync {
				guard hasPendingFrame else {
					isFlushScheduled = false
					return (hasFrame: false, frame: nil, observers: [@MainActor (CGImage?) -> Void]())
				}
				let frame = pendingFrame
				hasPendingFrame = false
				pendingFrame = nil
				return (hasFrame: true, frame: frame, observers: Array(observers.values))
			}
			guard nextFrame.hasFrame else { return }
			let image = nextFrame.frame?.image
			let deliveredImage = image
			previewFrame = deliveredImage
			for observer in nextFrame.observers {
				observer(deliveredImage)
			}
		}
	}
}

struct BrowserCameraCaptureConfiguration: Equatable, Sendable {
	let deviceID: String
	let filterPreset: BrowserCameraFilterPreset
	let grainPresence: BrowserCameraPipelineGrainPresence
	let prefersHorizontalFlip: Bool

	init(
		deviceID: String,
		filterPreset: BrowserCameraFilterPreset,
		grainPresence: BrowserCameraPipelineGrainPresence,
		prefersHorizontalFlip: Bool
	) {
		self.deviceID = deviceID
		self.filterPreset = filterPreset
		self.grainPresence = grainPresence
		self.prefersHorizontalFlip = prefersHorizontalFlip
	}

	init(
		deviceID: String,
		filterPreset: BrowserCameraFilterPreset
	) {
		self.init(
			deviceID: deviceID,
			filterPreset: filterPreset,
			grainPresence: .none,
			prefersHorizontalFlip: false
		)
	}
}

enum BrowserCameraCaptureError: Error, Equatable, Sendable {
	case authorizationDenied
	case pipelineUnavailable(description: String)
	case sourceUnavailable(deviceID: String)
	case sessionConfigurationFailed(description: String)
	case runtimeFailure(description: String)
	case interrupted(description: String)
}

enum BrowserCameraCaptureEvent: Equatable, Sendable {
	case didStartRunning(deviceID: String)
	case didUpdateMetrics(BrowserCameraPerformanceMetrics)
	case didUpdatePipelineRuntimeState(BrowserCameraPipelineRuntimeState?)
	case didStop(deviceID: String?)
	case didFail(BrowserCameraCaptureError)
	case sourceWasLost(deviceID: String)
}

final class LiveBrowserCameraCaptureController: NSObject, BrowserCameraCaptureControlling, @unchecked Sendable {
	private enum Defaults {
		static let sessionQueueLabel = "navigator.browserCamera.capture.session"
		static let videoOutputQueueLabel = "navigator.browserCamera.capture.videoOutput"
		static let processingMetricsReportIntervalFrameCount = 15
		static let previewFrameReportInterval: TimeInterval = 1.0 / 60.0
		static let realtimeProcessingBudgetMilliseconds = 1000.0 / 60.0
		static let preferredFramesPerSecond = 60.0
		static let frameTraceInterval = 60
	}

	private static let logger = Logger(
		subsystem: "com.navigator.Navigator",
		category: "BrowserCameraCapture"
	)

	private enum SessionPresets {
		static let primary: AVCaptureSession.Preset = .photo
		static let fallback: AVCaptureSession.Preset = .hd1280x720
	}

	struct Environment {
		var authorizationStatus: () -> AVAuthorizationStatus
		var findDevice: (String) -> AVCaptureDevice?
		var makeSession: () -> AVCaptureSession
		var makeDeviceInput: (AVCaptureDevice) throws -> AVCaptureInput
		var notificationCenter: NotificationCenter

		static func live() -> Self {
			Self(
				authorizationStatus: liveAuthorizationStatus,
				findDevice: liveFindDevice,
				makeSession: liveMakeSession,
				makeDeviceInput: liveMakeDeviceInput,
				notificationCenter: .default
			)
		}

		private static func liveAuthorizationStatus() -> AVAuthorizationStatus {
			AVCaptureDevice.authorizationStatus(for: .video)
		}

		private static func liveFindDevice(deviceID: String) -> AVCaptureDevice? {
			AVCaptureDevice.DiscoverySession(
				deviceTypes: [
					.builtInWideAngleCamera,
					.external,
				],
				mediaType: .video,
				position: .unspecified
			).devices.first(where: { $0.uniqueID == deviceID })
		}

		private static func liveMakeSession() -> AVCaptureSession {
			AVCaptureSession()
		}

		private static func liveMakeDeviceInput(device: AVCaptureDevice) throws -> AVCaptureInput {
			try AVCaptureDeviceInput(device: device)
		}
	}

	weak var delegate: (any BrowserCameraCaptureControllingDelegate)?

	private let environment: Environment
	private let frameProcessor: any BrowserCameraFrameProcessing
	private let sessionQueue: DispatchQueue
	private let videoOutputQueue: DispatchQueue
	private let session: AVCaptureSession
	private let videoDataOutput: AVCaptureVideoDataOutput
	private let avCaptureClient: BrowserCameraLiveCaptureClient?
	private let previewFrameUpdater: BrowserCameraPreviewFrameUpdater
	private let shouldPublishPreviewFrames: Bool
	private let shouldPublishVirtualFrames: Bool
	private var captureClientCancellables = Set<AnyCancellable>()
	private var currentInput: AVCaptureInput?
	private var currentDeviceID: String?
	private var currentDevicePosition: AVCaptureDevice.Position = .unspecified
	private var currentFilterPreset: BrowserCameraFilterPreset = .none
	private var currentGrainPresence: BrowserCameraPipelineGrainPresence = .none
	private var lastProcessingFailureDescription: String?
	private var processedFrameCount = 0
	private var droppedFrameCount = 0
	private var captureStartTime: TimeInterval?
	private var firstFrameLatencyMilliseconds: Double?
	private var lastPreviewFrameReportTime: TimeInterval?
	private var cumulativeProcessingLatency: TimeInterval = 0
	private var lastProcessingLatency: TimeInterval?
	private var lastReportedMetrics = BrowserCameraPerformanceMetrics.empty
	private var lastPipelineRuntimeState: BrowserCameraPipelineRuntimeState?
	private var capturedSampleBufferCount = 0
	private var publishedPreviewFrameCount = 0
	private var publishedVirtualPublisherFrameCount = 0
	private var throttledPreviewFrameCount = 0
	private let virtualFrameOutputQueue = DispatchQueue(label: "navigator.browserCamera.virtualFrameOutput")
	private var pendingVirtualOutputFrame: BrowserCameraVirtualOutputFrame?
	private var isVirtualFrameOutputScheduled = false
	private var shouldProcessCapturedFrames: Bool {
		shouldPublishPreviewFrames || shouldPublishVirtualFrames
	}

	override init() {
		environment = .live()
		frameProcessor = LiveBrowserCameraFrameProcessor()
		sessionQueue = DispatchQueue(label: Defaults.sessionQueueLabel, qos: .userInitiated)
		videoOutputQueue = DispatchQueue(label: Defaults.videoOutputQueueLabel, qos: .userInitiated)
		session = Environment.live().makeSession()
		videoDataOutput = AVCaptureVideoDataOutput()
		avCaptureClient = nil
		previewFrameUpdater = .shared
		shouldPublishPreviewFrames = !BrowserCameraPreviewFramePublishingFeatureFlag.isDisabled(
			environment: ProcessInfo.processInfo.environment
		)
		shouldPublishVirtualFrames = !BrowserCameraVirtualFramePublishingFeatureFlag.isDisabled(
			environment: ProcessInfo.processInfo.environment
		)
		super.init()
		if shouldPublishPreviewFrames == false {
			Self.logger.info("Preview frame publishing to UI disabled via environment flag")
		}
		if shouldPublishVirtualFrames == false {
			Self.logger.info("Virtual frame publishing to ring disabled via environment flag")
		}
		configureVideoDataOutput()
		installObservers()
	}

	init(
		environment: Environment,
		frameProcessor: any BrowserCameraFrameProcessing = LiveBrowserCameraFrameProcessor(),
		sessionQueue: DispatchQueue = DispatchQueue(label: Defaults.sessionQueueLabel),
		previewFrameUpdater: BrowserCameraPreviewFrameUpdater = .shared
	) {
		self.environment = environment
		self.frameProcessor = frameProcessor
		self.sessionQueue = sessionQueue
		videoOutputQueue = DispatchQueue(label: Defaults.videoOutputQueueLabel, qos: .userInitiated)
		session = environment.makeSession()
		videoDataOutput = AVCaptureVideoDataOutput()
		avCaptureClient = nil
		self.previewFrameUpdater = previewFrameUpdater
		shouldPublishPreviewFrames = !BrowserCameraPreviewFramePublishingFeatureFlag.isDisabled(
			environment: ProcessInfo.processInfo.environment
		)
		shouldPublishVirtualFrames = !BrowserCameraVirtualFramePublishingFeatureFlag.isDisabled(
			environment: ProcessInfo.processInfo.environment
		)
		super.init()
		if shouldPublishPreviewFrames == false {
			Self.logger.info("Preview frame publishing to UI disabled via environment flag")
		}
		if shouldPublishVirtualFrames == false {
			Self.logger.info("Virtual frame publishing to ring disabled via environment flag")
		}
		configureVideoDataOutput()
		installObservers()
	}

	deinit {
		environment.notificationCenter.removeObserver(self)
	}

	func startCapture(with configuration: BrowserCameraCaptureConfiguration) {
		logCaptureRequest(
			"startCapture requested",
			configuration: configuration,
			authorizationStatus: environment.authorizationStatus()
		)
		if let avCaptureClient {
			startCaptureWithAVCaptureClient(
				avCaptureClient,
				configuration: configuration
			)
			return
		}
		sessionQueue.async { [weak self] in
			self?.startCaptureOnSessionQueue(with: configuration)
		}
	}

	func stopCapture() {
		Self.logger.info(
			"stopCapture requested deviceID=\(self.currentDeviceID ?? "none", privacy: .public) processed=\(self.processedFrameCount) dropped=\(self.droppedFrameCount)"
		)
		if let avCaptureClient {
			stopCaptureWithAVCaptureClient(avCaptureClient)
			return
		}
		sessionQueue.async { [weak self] in
			self?.stopCaptureOnSessionQueue()
		}
	}

	func updateCaptureConfiguration(_ configuration: BrowserCameraCaptureConfiguration) {
		logCaptureRequest(
			"updateCaptureConfiguration requested",
			configuration: configuration,
			authorizationStatus: environment.authorizationStatus()
		)
		sessionQueue.async { [weak self] in
			self?.updateCaptureConfigurationOnSessionQueue(configuration)
		}
	}

	private func configureAVCaptureClient() {
		guard let avCaptureClient else { return }
		avCaptureClient.videoSampleBufferPublisher
			.sink { [weak self] sampleBuffer in
				Self.logger.debug("AVCaptureClient delivered sample buffer")
				self?.handleCapturedSampleBuffer(sampleBuffer)
			}
			.store(in: &captureClientCancellables)
		avCaptureClient.statePublisher
			.sink { [weak self] state in
				guard let self else { return }
				Self.logger.info("AVCaptureClient state=\(String(describing: state), privacy: .public)")
				switch state {
				case .notAuthorized:
					self.sendEvent(.didFail(.authorizationDenied))
				case .error(let error, _):
					self.sendEvent(.didFail(.runtimeFailure(description: error.localizedDescription)))
				case .idle, .running:
					break
				}
			}
			.store(in: &captureClientCancellables)
	}

	private func startCaptureWithAVCaptureClient(
		_ avCaptureClient: BrowserCameraLiveCaptureClient,
		configuration: BrowserCameraCaptureConfiguration
	) {
		guard environment.authorizationStatus() == .authorized else {
			Self.logger.error("AVCaptureClient start denied: camera authorization unavailable")
			sendEvent(.didFail(.authorizationDenied))
			return
		}

		guard let device = environment.findDevice(configuration.deviceID) else {
			Self.logger.error(
				"AVCaptureClient start failed: missing deviceID=\(configuration.deviceID, privacy: .public)"
			)
			sendEvent(.didFail(.sourceUnavailable(deviceID: configuration.deviceID)))
			return
		}

		do {
			if shouldProcessCapturedFrames {
				try frameProcessor.warmIfNeeded(
					for: configuration.filterPreset,
					grainPresence: configuration.grainPresence
				)
			}
			resetPerformanceMetrics()
			captureStartTime = CACurrentMediaTime()
			currentDeviceID = configuration.deviceID
			currentDevicePosition = device.position
			currentFilterPreset = configuration.filterPreset
			currentGrainPresence = configuration.grainPresence
			lastProcessingFailureDescription = nil
			if shouldPublishPreviewFrames {
				sendPreviewFrame(nil)
			}
			_ = Self.avCaptureClientTransformation(
				for: configuration.filterPreset,
				grainPresence: configuration.grainPresence
			)
			avCaptureClient.setPreferredVideoDeviceID(configuration.deviceID)
			avCaptureClient.setCameraPosition(device.position)
			avCaptureClient.startCaptureSession()
			Self.logger.info(
				"AVCaptureClient start succeeded deviceID=\(configuration.deviceID, privacy: .public) deviceName=\(device.localizedName, privacy: .public) position=\(Self.devicePositionName(device.position), privacy: .public) preset=\(configuration.filterPreset.rawValue, privacy: .public)"
			)
			sendEvent(.didStartRunning(deviceID: configuration.deviceID))
		}
		catch let error as BrowserCameraFrameProcessingError {
			Self.logger.error(
				"AVCaptureClient pipeline warmup failed deviceID=\(configuration.deviceID, privacy: .public) error=\(Self.errorDescription(for: error), privacy: .public)"
			)
			sendEvent(
				.didFail(
					.pipelineUnavailable(description: Self.errorDescription(for: error))
				)
			)
		}
		catch {
			Self.logger.error(
				"AVCaptureClient session configuration failed deviceID=\(configuration.deviceID, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
			)
			sendEvent(.didFail(.sessionConfigurationFailed(description: error.localizedDescription)))
		}
	}

	private func stopCaptureWithAVCaptureClient(_ avCaptureClient: BrowserCameraLiveCaptureClient) {
		let stoppedDeviceID = currentDeviceID
		avCaptureClient.stopCaptureSession()
		avCaptureClient.setPreferredVideoDeviceID(nil)
		currentDeviceID = nil
		currentDevicePosition = .unspecified
		currentFilterPreset = .none
		currentGrainPresence = .none
		lastProcessingFailureDescription = nil
		updatePipelineRuntimeStateIfNeeded(nil)
		resetPerformanceMetrics()
		sendPreviewFrame(nil)
		Self.logger.info(
			"AVCaptureClient stopped deviceID=\(stoppedDeviceID ?? "none", privacy: .public)"
		)
		sendEvent(.didStop(deviceID: stoppedDeviceID))
	}

	static func avCaptureClientTransformation(
		for filterPreset: BrowserCameraFilterPreset,
		grainPresence: BrowserCameraPipelineGrainPresence
	) -> Transformation {
		switch filterPreset {
		case .none:
			// Navigator consumes the raw sample buffer and performs its own
			// passthrough/output processing, so the Aperture-side transform only
			// needs to stay stable for internal preview plumbing. Avoid routing
			// `.none` through Aperture's dithering path, which expects a different
			// image/buffer contract than the live Navigator capture flow uses.
			Transformation(.none, .chromatic(.tonachrome))
		case .monochrome:
			Transformation(grainPresence.sharedPresence, .monochrome)
		case .dither:
			Transformation(grainPresence.sharedPresence, .dither)
		case .folia:
			Transformation(grainPresence.sharedPresence, .chromatic(.folia))
		case .supergold:
			Transformation(grainPresence.sharedPresence, .chromatic(.supergold))
		case .tonachrome:
			Transformation(grainPresence.sharedPresence, .chromatic(.tonachrome))
		case .bubblegum:
			Transformation(grainPresence.sharedPresence, .warhol(.bubblegum))
		case .darkroom:
			Transformation(grainPresence.sharedPresence, .warhol(.darkroom))
		case .glowInTheDark:
			Transformation(grainPresence.sharedPresence, .warhol(.glowInTheDark))
		case .habenero:
			Transformation(grainPresence.sharedPresence, .warhol(.habenero))
		}
	}

	static func avCaptureClientTransformation(
		for filterPreset: BrowserCameraFilterPreset
	) -> Transformation {
		avCaptureClientTransformation(for: filterPreset, grainPresence: .none)
	}

	private func installObservers() {
		environment.notificationCenter.addObserver(
			self,
			selector: #selector(handleRuntimeErrorNotification(_:)),
			name: .AVCaptureSessionRuntimeError,
			object: session
		)
		environment.notificationCenter.addObserver(
			self,
			selector: #selector(handleInterruptionNotification(_:)),
			name: .AVCaptureSessionWasInterrupted,
			object: session
		)
		environment.notificationCenter.addObserver(
			self,
			selector: #selector(handleInterruptionEndedNotification(_:)),
			name: .AVCaptureSessionInterruptionEnded,
			object: session
		)
		environment.notificationCenter.addObserver(
			self,
			selector: #selector(handleDeviceDisconnectedNotification(_:)),
			name: .AVCaptureDeviceWasDisconnected,
			object: nil
		)
	}

	private func configureVideoDataOutput() {
		if session.canSetSessionPreset(SessionPresets.primary) {
			session.sessionPreset = SessionPresets.primary
		}
		else if session.canSetSessionPreset(SessionPresets.fallback) {
			session.sessionPreset = SessionPresets.fallback
		}
		videoDataOutput.alwaysDiscardsLateVideoFrames = true
		videoDataOutput.videoSettings = [
			kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
		]
		videoDataOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
	}

	private func startCaptureOnSessionQueue(with configuration: BrowserCameraCaptureConfiguration) {
		guard environment.authorizationStatus() == .authorized else {
			Self.logger.error("Session start denied: camera authorization unavailable")
			sendEvent(.didFail(.authorizationDenied))
			return
		}

		guard let device = environment.findDevice(configuration.deviceID) else {
			Self.logger.error(
				"Session start failed: missing deviceID=\(configuration.deviceID, privacy: .public)"
			)
			sendEvent(.didFail(.sourceUnavailable(deviceID: configuration.deviceID)))
			return
		}

		do {
			if shouldProcessCapturedFrames {
				try frameProcessor.warmIfNeeded(
					for: configuration.filterPreset,
					grainPresence: configuration.grainPresence
				)
			}
			try configureSession(
				device: device,
				prefersHorizontalFlip: configuration.prefersHorizontalFlip
			)
			resetPerformanceMetrics()
			captureStartTime = CACurrentMediaTime()
			currentDeviceID = configuration.deviceID
			currentDevicePosition = device.position
			currentFilterPreset = configuration.filterPreset
			currentGrainPresence = configuration.grainPresence
			lastProcessingFailureDescription = nil
			if shouldPublishPreviewFrames {
				sendPreviewFrame(nil)
			}
			if session.isRunning == false {
				session.startRunning()
			}
			Self.logger.info(
				"Session started deviceID=\(configuration.deviceID, privacy: .public) deviceName=\(device.localizedName, privacy: .public) position=\(Self.devicePositionName(device.position), privacy: .public) preset=\(configuration.filterPreset.rawValue, privacy: .public) running=\(Self.flagDescription(self.session.isRunning), privacy: .public)"
			)
			sendEvent(.didStartRunning(deviceID: configuration.deviceID))
		}
		catch {
			let captureError: BrowserCameraCaptureError = if let captureError = error as? BrowserCameraCaptureError {
				captureError
			}
			else if let processingError = error as? BrowserCameraFrameProcessingError {
				.pipelineUnavailable(description: Self.errorDescription(for: processingError))
			}
			else {
				.sessionConfigurationFailed(description: error.localizedDescription)
			}
			Self.logger.error(
				"Session start failed deviceID=\(configuration.deviceID, privacy: .public) error=\(Self.captureErrorDescription(captureError), privacy: .public)"
			)
			sendEvent(.didFail(captureError))
		}
	}

	private func configureSession(
		device: AVCaptureDevice,
		prefersHorizontalFlip: Bool
	) throws {
		session.beginConfiguration()
		defer {
			session.commitConfiguration()
		}

		if let currentInput {
			session.removeInput(currentInput)
			self.currentInput = nil
		}
		if session.outputs.contains(videoDataOutput) {
			session.removeOutput(videoDataOutput)
		}
		session.connections.forEach(session.removeConnection)

		let input = try environment.makeDeviceInput(device)
		guard session.canAddInput(input) else {
			throw BrowserCameraCaptureError.sessionConfigurationFailed(
				description: "Unable to add camera input for \(device.localizedName)."
			)
		}

		session.addInputWithNoConnections(input)
		currentInput = input
		Self.logger.debug(
			"Configured camera input deviceID=\(device.uniqueID, privacy: .public) deviceName=\(device.localizedName, privacy: .public)"
		)

		if shouldProcessCapturedFrames == false {
			Self.logger.debug("Skipping AVCapture video data output; both preview and virtual publishing are disabled")
			return
		}

		guard session.canAddOutput(videoDataOutput) else {
			throw BrowserCameraCaptureError.sessionConfigurationFailed(
				description: "Unable to add camera video output for \(device.localizedName)."
			)
		}
		session.addOutputWithNoConnections(videoDataOutput)
		Self.logger.debug("Added AVCapture video data output")

		guard let port = input.ports.first(where: { $0.mediaType == .video }) else {
			throw BrowserCameraCaptureError.sessionConfigurationFailed(
				description: "Unable to find a video input port for \(device.localizedName)."
			)
		}

		let connection = AVCaptureConnection(inputPorts: [port], output: videoDataOutput)
		#if !os(macOS)
			if connection.isVideoOrientationSupported {
				connection.videoOrientation = .portrait
			}
		#endif
		if connection.isVideoMirroringSupported {
			connection.isVideoMirrored = prefersHorizontalFlip
		}
		guard session.canAddConnection(connection) else {
			throw BrowserCameraCaptureError.sessionConfigurationFailed(
				description: "Unable to add a camera connection for \(device.localizedName)."
			)
		}
		session.addConnection(connection)
		Self.logger.debug(
			"Configured video connection mirrored=\(Self.flagDescription(connection.isVideoMirrored), privacy: .public) enabled=\(Self.flagDescription(connection.isEnabled), privacy: .public) active=\(Self.flagDescription(connection.isActive), privacy: .public)"
		)
	}

	private func updateCaptureConfigurationOnSessionQueue(
		_ configuration: BrowserCameraCaptureConfiguration
	) {
		guard currentDeviceID == configuration.deviceID else {
			startCaptureOnSessionQueue(with: configuration)
			return
		}

		do {
			if shouldProcessCapturedFrames {
				try frameProcessor.warmIfNeeded(
					for: configuration.filterPreset,
					grainPresence: configuration.grainPresence
				)
			}
			currentFilterPreset = configuration.filterPreset
			currentGrainPresence = configuration.grainPresence
			updateVideoMirroringIfNeeded(prefersHorizontalFlip: configuration.prefersHorizontalFlip)
			Self.logger.info(
				"Capture configuration updated deviceID=\(configuration.deviceID, privacy: .public) preset=\(configuration.filterPreset.rawValue, privacy: .public) grain=\(configuration.grainPresence.rawValue, privacy: .public) flipped=\(Self.flagDescription(configuration.prefersHorizontalFlip), privacy: .public)"
			)
		}
		catch let processingError as BrowserCameraFrameProcessingError {
			sendEvent(
				.didFail(
					.pipelineUnavailable(description: Self.errorDescription(for: processingError))
				)
			)
		}
		catch {
			sendEvent(.didFail(.sessionConfigurationFailed(description: error.localizedDescription)))
		}
	}

	private func updateVideoMirroringIfNeeded(prefersHorizontalFlip: Bool) {
		guard let connection = videoDataOutput.connection(with: .video),
		      connection.isVideoMirroringSupported
		else {
			return
		}
		connection.isVideoMirrored = prefersHorizontalFlip
		Self.logger.debug(
			"Updated video connection mirrored=\(Self.flagDescription(connection.isVideoMirrored), privacy: .public)"
		)
	}

	private func stopCaptureOnSessionQueue() {
		let stoppedDeviceID = currentDeviceID
		if session.isRunning {
			session.stopRunning()
		}
		if let currentInput {
			session.beginConfiguration()
			session.removeInput(currentInput)
			self.currentInput = nil
			if session.outputs.contains(videoDataOutput) {
				session.removeOutput(videoDataOutput)
			}
			session.connections.forEach(session.removeConnection)
			session.commitConfiguration()
		}
		currentDeviceID = nil
		currentDevicePosition = .unspecified
		currentFilterPreset = .none
		currentGrainPresence = .none
		lastProcessingFailureDescription = nil
		updatePipelineRuntimeStateIfNeeded(nil)
		resetPerformanceMetrics()
		sendPreviewFrame(nil)
		Self.logger.info(
			"Session stopped deviceID=\(stoppedDeviceID ?? "none", privacy: .public)"
		)
		sendEvent(.didStop(deviceID: stoppedDeviceID))
	}

	@objc
	private func handleRuntimeErrorNotification(_ notification: Notification) {
		let description: String = if let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError {
			error.localizedDescription
		}
		else {
			"The camera capture session reported a runtime error."
		}
		Self.logger.error("Capture runtime error: \(description, privacy: .public)")
		sendEvent(.didFail(.runtimeFailure(description: description)))
	}

	@objc
	private func handleInterruptionNotification(_ notification: Notification) {
		Self.logger.error("Capture session interrupted")
		sendEvent(.didFail(.interrupted(description: "The camera capture session was interrupted.")))
	}

	@objc
	private func handleInterruptionEndedNotification(_ notification: Notification) {
		Self.logger.info("Capture session interruption ended")
		sessionQueue.async { [weak self] in
			guard let self, let currentDeviceID = self.currentDeviceID else { return }
			if session.isRunning == false {
				session.startRunning()
			}
			sendEvent(.didStartRunning(deviceID: currentDeviceID))
		}
	}

	@objc
	private func handleDeviceDisconnectedNotification(_ notification: Notification) {
		guard let device = notification.object as? AVCaptureDevice else { return }
		let disconnectedDeviceID = device.uniqueID
		Self.logger.error(
			"Capture device disconnected deviceID=\(disconnectedDeviceID, privacy: .public) deviceName=\(device.localizedName, privacy: .public)"
		)
		sessionQueue.async { [weak self] in
			guard let self, self.currentDeviceID == disconnectedDeviceID else { return }
			self.stopCaptureOnSessionQueue()
			self.sendEvent(.sourceWasLost(deviceID: disconnectedDeviceID))
		}
	}

	private func sendEvent(_ event: BrowserCameraCaptureEvent) {
		Self.logger.debug("Capture event=\(Self.describe(event), privacy: .public)")
		let delegate = delegate
		Task { @MainActor in
			delegate?.browserCameraCaptureControllerDidReceiveEvent(event)
		}
	}

	private func resetPerformanceMetrics() {
		processedFrameCount = 0
		droppedFrameCount = 0
		captureStartTime = nil
		firstFrameLatencyMilliseconds = nil
		lastPreviewFrameReportTime = nil
		cumulativeProcessingLatency = 0
		lastProcessingLatency = nil
		lastReportedMetrics = .empty
		capturedSampleBufferCount = 0
		publishedPreviewFrameCount = 0
		publishedVirtualPublisherFrameCount = 0
		throttledPreviewFrameCount = 0
	}

	private func updatePipelineRuntimeStateIfNeeded(
		_ pipelineRuntimeState: BrowserCameraPipelineRuntimeState?
	) {
		guard lastPipelineRuntimeState != pipelineRuntimeState else { return }
		lastPipelineRuntimeState = pipelineRuntimeState
		sendEvent(.didUpdatePipelineRuntimeState(pipelineRuntimeState))
	}

	private func recordProcessedFrame(latency: TimeInterval) {
		processedFrameCount += 1
		if firstFrameLatencyMilliseconds == nil, let captureStartTime {
			firstFrameLatencyMilliseconds = Self.milliseconds(for: CACurrentMediaTime() - captureStartTime)
		}
		cumulativeProcessingLatency += latency
		lastProcessingLatency = latency
		reportMetricsIfNeeded()
	}

	private func recordDroppedFrame() {
		droppedFrameCount += 1
		reportMetricsIfNeeded()
	}

	private func reportMetricsIfNeeded() {
		let metrics = BrowserCameraPerformanceMetrics(
			processedFrameCount: processedFrameCount,
			droppedFrameCount: droppedFrameCount,
			firstFrameLatencyMilliseconds: firstFrameLatencyMilliseconds,
			averageProcessingLatencyMilliseconds: averageProcessingLatencyMilliseconds,
			lastProcessingLatencyMilliseconds: lastProcessingLatency.map(Self.milliseconds(for:)),
			realtimeBudgetExceeded: isRealtimeBudgetExceeded
		)
		guard shouldReport(metrics: metrics) else { return }
		lastReportedMetrics = metrics
		sendEvent(.didUpdateMetrics(metrics))
	}

	private func shouldReport(metrics: BrowserCameraPerformanceMetrics) -> Bool {
		guard metrics != lastReportedMetrics else { return false }
		return metrics.processedFrameCount <= 1
			|| metrics.droppedFrameCount > lastReportedMetrics.droppedFrameCount
			|| metrics.realtimeBudgetExceeded != lastReportedMetrics.realtimeBudgetExceeded
			|| metrics.processedFrameCount.isMultiple(of: Defaults.processingMetricsReportIntervalFrameCount)
	}

	private var averageProcessingLatencyMilliseconds: Double? {
		guard processedFrameCount > 0 else { return nil }
		return Self.milliseconds(for: cumulativeProcessingLatency / Double(processedFrameCount))
	}

	private var isRealtimeBudgetExceeded: Bool {
		guard let averageProcessingLatencyMilliseconds else { return false }
		return averageProcessingLatencyMilliseconds > Defaults.realtimeProcessingBudgetMilliseconds
	}

	private static func errorDescription(for error: BrowserCameraFrameProcessingError) -> String {
		switch error {
		case .renderFailed(let description):
			description
		}
	}

	private static func milliseconds(for interval: TimeInterval) -> Double {
		interval * 1000
	}

	private func reportPreviewFrameIfNeeded(using previewImage: CGImage) {
		guard shouldPublishPreviewFrames else { return }
		guard shouldReportPreviewFrame else {
			throttledPreviewFrameCount += 1
			if throttledPreviewFrameCount <= 3
				|| throttledPreviewFrameCount.isMultiple(of: Defaults.frameTraceInterval) {
				Self.logger.debug(
					"Preview frame throttled count=\(self.throttledPreviewFrameCount) processed=\(self.processedFrameCount)"
				)
			}
			return
		}
		lastPreviewFrameReportTime = CACurrentMediaTime()
		let frame = BrowserCameraPreviewFrame(image: previewImage)
		sendPreviewFrame(frame)
	}

	private var shouldReportPreviewFrame: Bool {
		guard let lastPreviewFrameReportTime else { return true }
		return CACurrentMediaTime() - lastPreviewFrameReportTime >= Defaults.previewFrameReportInterval
	}

	private func sendPreviewFrame(_ previewFrame: BrowserCameraPreviewFrame?) {
		guard shouldPublishPreviewFrames else { return }
		if let previewFrame {
			publishedPreviewFrameCount += 1
			if publishedPreviewFrameCount <= 3
				|| publishedPreviewFrameCount.isMultiple(of: Defaults.frameTraceInterval) {
				Self.logger.debug(
					"Publishing preview frame count=\(self.publishedPreviewFrameCount) size=\(previewFrame.image.width)x\(previewFrame.image.height)"
				)
			}
		}
		else {
			Self.logger.debug("Publishing nil preview frame to clear observers")
		}
		previewFrameUpdater.publish(previewFrame)
	}

	private func logCaptureRequest(
		_ message: StaticString,
		configuration: BrowserCameraCaptureConfiguration,
		authorizationStatus: AVAuthorizationStatus
	) {
		Self.logger.info(
			"\(message) deviceID=\(configuration.deviceID, privacy: .public) preset=\(configuration.filterPreset.rawValue, privacy: .public) authorization=\(Self.authorizationStatusName(authorizationStatus), privacy: .public)"
		)
	}

	private static func authorizationStatusName(_ status: AVAuthorizationStatus) -> String {
		switch status {
		case .authorized:
			"authorized"
		case .notDetermined:
			"notDetermined"
		case .denied:
			"denied"
		case .restricted:
			"restricted"
		@unknown default:
			"unknown"
		}
	}

	private static func devicePositionName(_ position: AVCaptureDevice.Position) -> String {
		switch position {
		case .front:
			"front"
		case .back:
			"back"
		case .unspecified:
			"unspecified"
		@unknown default:
			"unknown"
		}
	}

	private static func captureErrorDescription(_ error: BrowserCameraCaptureError) -> String {
		switch error {
		case .authorizationDenied:
			"authorizationDenied"
		case .pipelineUnavailable(let description):
			"pipelineUnavailable \(description)"
		case .sourceUnavailable(let deviceID):
			"sourceUnavailable \(deviceID)"
		case .sessionConfigurationFailed(let description):
			"sessionConfigurationFailed \(description)"
		case .runtimeFailure(let description):
			"runtimeFailure \(description)"
		case .interrupted(let description):
			"interrupted \(description)"
		}
	}

	private static func describe(_ event: BrowserCameraCaptureEvent) -> String {
		switch event {
		case .didStartRunning(let deviceID):
			return "didStartRunning deviceID=\(deviceID)"
		case .didUpdateMetrics(let metrics):
			return "didUpdateMetrics processed=\(metrics.processedFrameCount) dropped=\(metrics.droppedFrameCount) averageLatencyMs=\(metrics.averageProcessingLatencyMilliseconds.map(String.init(describing:)) ?? "none")"
		case .didUpdatePipelineRuntimeState(let pipelineRuntimeState):
			if let pipelineRuntimeState {
				return "didUpdatePipelineRuntimeState implementation=\(pipelineRuntimeState.implementation.rawValue) " +
					"warmup=\(pipelineRuntimeState.warmupProfile.rawValue) filters=\(pipelineRuntimeState.requiredFilterCount)"
			}
			return "didUpdatePipelineRuntimeState nil"
		case .didStop(let deviceID):
			return "didStop deviceID=\(deviceID ?? "none")"
		case .didFail(let error):
			return "didFail \(captureErrorDescription(error))"
		case .sourceWasLost(let deviceID):
			return "sourceWasLost deviceID=\(deviceID)"
		}
	}

	private static func flagDescription(_ value: Bool) -> String {
		value ? "true" : "false"
	}
}

private extension BrowserCameraPipelineGrainPresence {
	var sharedPresence: GrainPresence {
		switch self {
		case .none:
			.none
		case .normal:
			.normal
		case .high:
			.high
		}
	}
}

extension LiveBrowserCameraCaptureController: AVCaptureVideoDataOutputSampleBufferDelegate {
	func captureOutput(
		_ output: AVCaptureOutput,
		didOutput sampleBuffer: CMSampleBuffer,
		from connection: AVCaptureConnection
	) {
		guard shouldProcessCapturedFrames else { return }
		handleCapturedSampleBuffer(sampleBuffer)
	}

	func captureOutput(
		_ output: AVCaptureOutput,
		didDrop sampleBuffer: CMSampleBuffer,
		from connection: AVCaptureConnection
	) {
		guard shouldProcessCapturedFrames else { return }
		recordDroppedFrame()
	}

	func handleCapturedSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
		guard shouldProcessCapturedFrames else { return }
		handleCapturedPixelBuffer(
			CMSampleBufferGetImageBuffer(sampleBuffer),
			timestampHostTime: Self.hostTimeUnits(for: CMSampleBufferGetPresentationTimeStamp(sampleBuffer)),
			durationHostTime: Self.hostTimeUnits(for: CMSampleBufferGetDuration(sampleBuffer))
		)
	}

	func handleCapturedPixelBuffer(_ pixelBuffer: CVPixelBuffer?) {
		handleCapturedPixelBuffer(
			pixelBuffer,
			timestampHostTime: 0,
			durationHostTime: 0
		)
	}

	private func handleCapturedPixelBuffer(
		_ pixelBuffer: CVPixelBuffer?,
		timestampHostTime: UInt64,
		durationHostTime: UInt64
	) {
		guard let pixelBuffer else {
			Self.logger.error("Dropped capture sample: missing image buffer")
			return
		}
		capturedSampleBufferCount += 1
		autoreleasepool {
			do {
				guard shouldPublishVirtualFrames || shouldPublishPreviewFrames else {
					return
				}
				let processedFrame = try frameProcessor.process(
					pixelBuffer: pixelBuffer,
					preset: currentFilterPreset,
					grainPresence: currentGrainPresence,
					devicePosition: currentDevicePosition
				)
				lastProcessingFailureDescription = nil
				updatePipelineRuntimeStateIfNeeded(processedFrame.pipelineRuntimeState)
				recordProcessedFrame(latency: processedFrame.processingLatency)
				if processedFrameCount <= 3 || processedFrameCount.isMultiple(of: Defaults.frameTraceInterval) {
					Self.logger.debug(
						"Processed frame count=\(self.processedFrameCount) preview=\(processedFrame.previewImage.width)x\(processedFrame.previewImage.height) pixels=\(processedFrame.pixelWidth)x\(processedFrame.pixelHeight) latencyMs=\(Self.milliseconds(for: processedFrame.processingLatency), privacy: .public) pipeline=\(processedFrame.pipelineRuntimeState.implementation.rawValue, privacy: .public)"
					)
				}
				if shouldPublishVirtualFrames {
					sendVirtualPublisherFrame(
						pixelBuffer: processedFrame.pixelBuffer,
						payloadByteCount: processedFrame.payloadByteCount,
						width: processedFrame.pixelWidth,
						height: processedFrame.pixelHeight,
						bytesPerRow: processedFrame.bytesPerRow,
						pixelFormat: .bgra8888,
						timestampHostTime: timestampHostTime,
						durationHostTime: durationHostTime
					)
				}
				else {
					return
				}
				reportPreviewFrameIfNeeded(using: processedFrame.previewImage)
			}
			catch let error as BrowserCameraFrameProcessingError {
				let description = Self.errorDescription(for: error)
				guard lastProcessingFailureDescription != description else { return }
				lastProcessingFailureDescription = description
				Self.logger.error(
					"Frame processing failed count=\(self.capturedSampleBufferCount) error=\(description, privacy: .public)"
				)
				sendEvent(.didFail(.pipelineUnavailable(description: description)))
			}
			catch {
				guard lastProcessingFailureDescription != error.localizedDescription else { return }
				lastProcessingFailureDescription = error.localizedDescription
				Self.logger.error(
					"Frame processing failed with unexpected error count=\(self.capturedSampleBufferCount) error=\(error.localizedDescription, privacy: .public)"
				)
				sendEvent(.didFail(.pipelineUnavailable(description: error.localizedDescription)))
			}
		}
	}

	private func sendVirtualPublisherFrame(
		pixelBuffer: CVPixelBuffer,
		payloadByteCount: Int,
		width: Int,
		height: Int,
		bytesPerRow: Int,
		pixelFormat: BrowserCameraVirtualPublisherPixelFormat,
		timestampHostTime: UInt64,
		durationHostTime: UInt64
	) {
		publishedVirtualPublisherFrameCount += 1
		if publishedVirtualPublisherFrameCount <= 3
			|| publishedVirtualPublisherFrameCount.isMultiple(of: Defaults.frameTraceInterval) {
			Self.logger.debug(
				"Publishing virtual frame count=\(self.publishedVirtualPublisherFrameCount) size=\(width)x\(height) bytesPerRow=\(bytesPerRow)"
			)
		}
		let shouldScheduleFlush = virtualFrameOutputQueue.sync {
			pendingVirtualOutputFrame = BrowserCameraVirtualOutputFrame(
				pixelBuffer: pixelBuffer,
				payloadByteCount: payloadByteCount,
				width: width,
				height: height,
				bytesPerRow: bytesPerRow,
				pixelFormat: pixelFormat,
				timestampHostTime: timestampHostTime,
				durationHostTime: durationHostTime
			)
			guard isVirtualFrameOutputScheduled == false else { return false }
			isVirtualFrameOutputScheduled = true
			return true
		}
		guard shouldScheduleFlush else { return }

		DispatchQueue.main.async { [weak self] in
			self?.flushPendingVirtualOutputFrames()
		}
	}

	@MainActor
	private func flushPendingVirtualOutputFrames() {
		while true {
			let nextFrame = virtualFrameOutputQueue.sync { () -> BrowserCameraVirtualOutputFrame? in
				guard let frame = pendingVirtualOutputFrame else {
					isVirtualFrameOutputScheduled = false
					return nil
				}
				defer { pendingVirtualOutputFrame = nil }
				return frame
			}
			guard let frame = nextFrame else { return }
			delegate?.browserCameraCaptureControllerDidOutputVirtualPublisherFrame(frame)
		}
	}

	private static func hostTimeUnits(for time: CMTime) -> UInt64 {
		guard time.isNumeric, time.isValid else { return 0 }
		let scaledTime = CMTimeConvertScale(
			time,
			timescale: 1_000_000_000,
			method: .default
		)
		return scaledTime.value > 0 ? UInt64(scaledTime.value) : 0
	}
}
