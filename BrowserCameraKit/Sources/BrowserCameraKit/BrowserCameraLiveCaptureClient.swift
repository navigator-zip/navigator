@preconcurrency import AVFoundation
import Combine
import Foundation
import OSLog

enum BrowserCameraCaptureClientState: Equatable {
	case idle
	case running
	case notAuthorized
	case error(NSError, canRetry: Bool)
}

final class BrowserCameraLiveCaptureClient: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate,
	@unchecked Sendable {
	private enum Defaults {
		static let sessionQueueLabel = "navigator.browserCamera.captureClient.session"
		static let dataOutputQueueLabel = "navigator.browserCamera.captureClient.videoOutput"
		static let sampleTraceInterval = 60
		static let pixelFormat = kCVPixelFormatType_32BGRA
	}

	private static let logger = Logger(
		subsystem: "com.navigator.Navigator",
		category: "BrowserCameraLiveCaptureClient"
	)

	var statePublisher: AnyPublisher<BrowserCameraCaptureClientState, Never> {
		stateSubject
			.subscribe(on: sessionQueue)
			.eraseToAnyPublisher()
	}

	var videoSampleBufferPublisher: AnyPublisher<CMSampleBuffer, Never> {
		videoSampleBufferSubject.eraseToAnyPublisher()
	}

	private let stateSubject = CurrentValueSubject<BrowserCameraCaptureClientState, Never>(.idle)
	private let videoSampleBufferSubject = PassthroughSubject<CMSampleBuffer, Never>()

	private let sessionQueue = DispatchQueue(
		label: Defaults.sessionQueueLabel,
		qos: .userInitiated
	)
	private let dataOutputQueue = DispatchQueue(
		label: Defaults.dataOutputQueueLabel,
		qos: .userInitiated
	)

	private let session: AVCaptureSession = {
		let session = AVCaptureSession()
		if session.canSetSessionPreset(.high) {
			session.sessionPreset = .high
		}
		else if session.canSetSessionPreset(.hd1280x720) {
			session.sessionPreset = .hd1280x720
		}
		return session
	}()

	private var currentDevice: AVCaptureDevice?
	private var preferredVideoDeviceID: String?
	private var requestedPosition: AVCaptureDevice.Position = .unspecified
	private var hasAddedIO = false
	private var deliveredSampleBufferCount = 0

	private var videoInput: AVCaptureDeviceInput?
	private var videoDataOutput: AVCaptureVideoDataOutput?

	override init() {
		super.init()
		installObservers()
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	func setPreferredVideoDeviceID(_ deviceID: String?) {
		Self.logger.info(
			"setPreferredVideoDeviceID deviceID=\(deviceID ?? "none", privacy: .public)"
		)
		preferredVideoDeviceID = deviceID
	}

	func setCameraPosition(_ position: AVCaptureDevice.Position) {
		sessionQueue.async {
			Self.logger.info(
				"setCameraPosition requested=\(Self.positionName(position), privacy: .public) current=\(Self.positionName(self.position), privacy: .public)"
			)
			self.requestedPosition = position
			guard self.position != position else { return }
			do {
				try self.rebuildSessionIO(position: position)
			}
			catch {
				Self.logger.error(
					"setCameraPosition failed position=\(Self.positionName(position), privacy: .public) error=\(error.localizedDescription, privacy: .public)"
				)
				self.stateSubject.send(.error(error as NSError, canRetry: false))
			}
		}
	}

	func startCaptureSession() {
		sessionQueue.async {
			do {
				Self.logger.info(
					"startCaptureSession requested preferredDeviceID=\(self.preferredVideoDeviceID ?? "none", privacy: .public) requestedPosition=\(Self.positionName(self.requestedPosition), privacy: .public) hasAddedIO=\(Self.flagDescription(self.hasAddedIO), privacy: .public)"
				)
				if self.hasAddedIO == false {
					try self.rebuildSessionIO(position: self.requestedPosition)
				}
				guard self.session.isRunning == false else { return }
				self.session.startRunning()
				self.logVideoConnectionState(context: "startCaptureSession")
				Self.logger.info(
					"startCaptureSession completed running=\(Self.flagDescription(self.session.isRunning), privacy: .public) device=\(self.currentDevice?.localizedName ?? "none", privacy: .public)"
				)
				if self.session.isRunning {
					self.stateSubject.send(.running)
				}
			}
			catch {
				Self.logger.error(
					"startCaptureSession failed error=\(error.localizedDescription, privacy: .public)"
				)
				self.stateSubject.send(.error(error as NSError, canRetry: false))
			}
		}
	}

	func stopCaptureSession() {
		sessionQueue.async {
			Self.logger.info(
				"stopCaptureSession requested running=\(Self.flagDescription(self.session.isRunning), privacy: .public) deliveredSamples=\(self.deliveredSampleBufferCount)"
			)
			guard self.session.isRunning else {
				self.stateSubject.send(.idle)
				return
			}
			self.session.stopRunning()
			Self.logger.info(
				"stopCaptureSession completed running=\(Self.flagDescription(self.session.isRunning), privacy: .public)"
			)
			self.stateSubject.send(.idle)
		}
	}

	func captureOutput(
		_ output: AVCaptureOutput,
		didOutput sampleBuffer: CMSampleBuffer,
		from connection: AVCaptureConnection
	) {
		deliveredSampleBufferCount += 1
		if deliveredSampleBufferCount <= 3
			|| deliveredSampleBufferCount.isMultiple(of: Defaults.sampleTraceInterval) {
			let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
			let width = imageBuffer.map(CVPixelBufferGetWidth) ?? 0
			let height = imageBuffer.map(CVPixelBufferGetHeight) ?? 0
			Self.logger.debug(
				"captureOutput delivered sample count=\(self.deliveredSampleBufferCount) size=\(width)x\(height) valid=\(Self.flagDescription(CMSampleBufferIsValid(sampleBuffer)), privacy: .public)"
			)
		}
		videoSampleBufferSubject.send(sampleBuffer)
	}

	private var position: AVCaptureDevice.Position {
		currentDevice?.position ?? requestedPosition
	}

	private func rebuildSessionIO(position: AVCaptureDevice.Position) throws {
		Self.logger.info(
			"rebuildSessionIO start requestedPosition=\(Self.positionName(position), privacy: .public) preferredDeviceID=\(self.preferredVideoDeviceID ?? "none", privacy: .public)"
		)
		session.beginConfiguration()
		defer { session.commitConfiguration() }

		removeAllSessionIO()

		guard let captureDevice = preferredDevice(for: position) else {
			Self.logger.error(
				"rebuildSessionIO failed: no compatible device for requestedPosition=\(Self.positionName(position), privacy: .public) preferredDeviceID=\(self.preferredVideoDeviceID ?? "none", privacy: .public)"
			)
			throw BrowserCameraLiveCaptureClientError.missingVideoDevice
		}
		Self.logger.info(
			"rebuildSessionIO selected deviceID=\(captureDevice.uniqueID, privacy: .public) name=\(captureDevice.localizedName, privacy: .public) position=\(Self.positionName(captureDevice.position), privacy: .public)"
		)

		let deviceInput = try AVCaptureDeviceInput(device: captureDevice)
		guard session.canAddInput(deviceInput) else {
			Self.logger.error(
				"rebuildSessionIO failed: cannot add input deviceID=\(captureDevice.uniqueID, privacy: .public)"
			)
			throw BrowserCameraLiveCaptureClientError.invalidCaptureInput
		}
		session.addInput(deviceInput)

		let videoDataOutput = AVCaptureVideoDataOutput()
		videoDataOutput.alwaysDiscardsLateVideoFrames = true
		videoDataOutput.videoSettings = [
			kCVPixelBufferPixelFormatTypeKey as String: Defaults.pixelFormat,
		]
		videoDataOutput.setSampleBufferDelegate(self, queue: dataOutputQueue)
		guard session.canAddOutput(videoDataOutput) else {
			Self.logger.error(
				"rebuildSessionIO failed: cannot add video output deviceID=\(captureDevice.uniqueID, privacy: .public)"
			)
			throw BrowserCameraLiveCaptureClientError.invalidCaptureOutput
		}
		session.addOutput(videoDataOutput)

		if let connection = videoDataOutput.connection(with: .video),
		   connection.isVideoMirroringSupported {
			connection.isVideoMirrored = captureDevice.position == .front
			Self.logger.debug(
				"rebuildSessionIO configured mirroring mirrored=\(Self.flagDescription(connection.isVideoMirrored), privacy: .public)"
			)
		}
		else {
			Self.logger.debug("rebuildSessionIO video connection missing or mirroring unsupported")
		}

		currentDevice = captureDevice
		videoInput = deviceInput
		self.videoDataOutput = videoDataOutput
		hasAddedIO = true
		deliveredSampleBufferCount = 0
		logVideoConnectionState(context: "rebuildSessionIO")
		Self.logger.info(
			"rebuildSessionIO complete inputCount=\(self.session.inputs.count) outputCount=\(self.session.outputs.count)"
		)
	}

	private func removeAllSessionIO() {
		if session.inputs.isEmpty == false || session.outputs.isEmpty == false {
			Self.logger.debug(
				"removeAllSessionIO inputs=\(self.session.inputs.count) outputs=\(self.session.outputs.count)"
			)
		}
		session.inputs.forEach(session.removeInput)
		session.outputs.forEach(session.removeOutput)
		session.connections.forEach(session.removeConnection)
		videoInput = nil
		videoDataOutput = nil
		hasAddedIO = false
	}

	private func preferredDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
		let deviceTypes: [AVCaptureDevice.DeviceType] = if #available(macOS 14.0, *) {
			[
				.builtInWideAngleCamera,
				.external,
			]
		}
		else {
			[.builtInWideAngleCamera]
		}
		let discoverySession = AVCaptureDevice.DiscoverySession(
			deviceTypes: deviceTypes,
			mediaType: .video,
			position: .unspecified
		)
		let devices = discoverySession.devices
		let deviceSummary = devices.map {
			"\($0.uniqueID):\($0.localizedName):\(Self.positionName($0.position))"
		}.joined(separator: ",")
		Self.logger.debug(
			"preferredDevice candidates count=\(devices.count) requestedPosition=\(Self.positionName(position), privacy: .public) preferredDeviceID=\(self.preferredVideoDeviceID ?? "none", privacy: .public) devices=\(deviceSummary, privacy: .public)"
		)

		if let preferredVideoDeviceID,
		   let matchingDevice = devices.first(where: { $0.uniqueID == preferredVideoDeviceID }) {
			Self.logger.debug(
				"preferredDevice matched explicit deviceID=\(matchingDevice.uniqueID, privacy: .public)"
			)
			return matchingDevice
		}

		let resolvedDevice = devices.first(where: {
			position == .unspecified || $0.position == position || $0.position == .unspecified
		})
		Self.logger.debug(
			"preferredDevice resolved deviceID=\(resolvedDevice?.uniqueID ?? "none", privacy: .public)"
		)
		return resolvedDevice
	}

	private func installObservers() {
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(handleSessionRuntimeError(_:)),
			name: .AVCaptureSessionRuntimeError,
			object: session
		)
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(handleSessionDidStartRunning(_:)),
			name: .AVCaptureSessionDidStartRunning,
			object: session
		)
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(handleSessionDidStopRunning(_:)),
			name: .AVCaptureSessionDidStopRunning,
			object: session
		)
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(handleSessionWasInterrupted(_:)),
			name: .AVCaptureSessionWasInterrupted,
			object: session
		)
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(handleSessionInterruptionEnded(_:)),
			name: .AVCaptureSessionInterruptionEnded,
			object: session
		)
	}

	@objc
	private func handleSessionRuntimeError(_ notification: Notification) {
		let description = (notification.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.localizedDescription
			?? "unknown"
		Self.logger.error("AVCaptureSession runtime error=\(description, privacy: .public)")
	}

	@objc
	private func handleSessionDidStartRunning(_ notification: Notification) {
		Self.logger.info("AVCaptureSessionDidStartRunning")
	}

	@objc
	private func handleSessionDidStopRunning(_ notification: Notification) {
		Self.logger.info("AVCaptureSessionDidStopRunning")
	}

	@objc
	private func handleSessionWasInterrupted(_ notification: Notification) {
		Self.logger.error(
			"AVCaptureSessionWasInterrupted userInfo=\(String(describing: notification.userInfo), privacy: .public)"
		)
	}

	@objc
	private func handleSessionInterruptionEnded(_ notification: Notification) {
		Self.logger.info("AVCaptureSessionInterruptionEnded")
	}

	private static func positionName(_ position: AVCaptureDevice.Position) -> String {
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

	private static func flagDescription(_ value: Bool) -> String {
		value ? "true" : "false"
	}

	private func logVideoConnectionState(context: StaticString) {
		guard let videoDataOutput else {
			Self.logger.error("\(context) missing videoDataOutput")
			return
		}
		guard let connection = videoDataOutput.connection(with: .video) else {
			Self.logger.error("\(context) missing video connection")
			return
		}
		let configuredPixelFormat = (videoDataOutput.videoSettings?[kCVPixelBufferPixelFormatTypeKey as String] as? NSNumber)?
			.uint32Value ?? 0
		Self.logger.info(
			"\(context) connection enabled=\(Self.flagDescription(connection.isEnabled), privacy: .public) active=\(Self.flagDescription(connection.isActive), privacy: .public) mirroringSupported=\(Self.flagDescription(connection.isVideoMirroringSupported), privacy: .public) mirrored=\(Self.flagDescription(connection.isVideoMirrored), privacy: .public) pixelFormat=\(configuredPixelFormat) sessionPreset=\(self.session.sessionPreset.rawValue, privacy: .public)"
		)
	}
}

private enum BrowserCameraLiveCaptureClientError: LocalizedError {
	case invalidCaptureInput
	case invalidCaptureOutput
	case missingVideoDevice

	var errorDescription: String? {
		switch self {
		case .invalidCaptureInput:
			"Unable to add the selected camera input."
		case .invalidCaptureOutput:
			"Unable to add the camera video output."
		case .missingVideoDevice:
			"No compatible video capture device is available."
		}
	}
}
