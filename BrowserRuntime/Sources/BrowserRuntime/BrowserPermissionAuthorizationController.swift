import AVFoundation
import CoreLocation
import Foundation
import ModelKit

@MainActor
protocol BrowserPermissionLocationAuthorizing: AnyObject {
	func currentStatus() -> BrowserPermissionOSAuthorizationStatus
	func requestAuthorization(
		completion: @escaping @MainActor (BrowserPermissionOSAuthorizationStatus) -> Void
	)
}

@MainActor
protocol BrowserPermissionAuthorizing: AnyObject {
	func cachedState() -> BrowserPermissionOSAuthorizationState
	func requestAuthorization(
		for kinds: BrowserPermissionKindSet,
		completion: @escaping @MainActor (BrowserPermissionOSAuthorizationState) -> Void
	)
}

@MainActor
final class BrowserPermissionAuthorizationController: NSObject, BrowserPermissionAuthorizing {
	typealias CaptureAccessRequester = (
		AVMediaType,
		@escaping @Sendable (Bool) -> Void
	) -> Void

	struct Environment {
		let captureAuthorizationStatus: (AVMediaType) -> BrowserPermissionOSAuthorizationStatus
		let requestCaptureAccess: (
			AVMediaType,
			@escaping @MainActor (BrowserPermissionOSAuthorizationStatus) -> Void
		) -> Void
		let makeLocationAuthorizer: () -> any BrowserPermissionLocationAuthorizing

		@MainActor
		static var live: Self {
			Self(
				captureAuthorizationStatus: BrowserPermissionAuthorizationController.captureAuthorizationStatus(for:),
				requestCaptureAccess: BrowserPermissionAuthorizationController.requestCaptureAccessLive,
				makeLocationAuthorizer: CoreLocationPermissionAuthorizer.init
			)
		}
	}

	#if DEBUG
		private static var captureAccessRequesterOverride: CaptureAccessRequester?
	#endif
	private let environment: Environment
	private var cachedAuthorizationState = BrowserPermissionOSAuthorizationState()
	private var activeLocationAuthorizer: (any BrowserPermissionLocationAuthorizing)?

	override init() {
		environment = .live
		super.init()
		refreshCachedState()
	}

	init(environment: Environment) {
		self.environment = environment
		super.init()
		refreshCachedState()
	}

	func cachedState() -> BrowserPermissionOSAuthorizationState {
		refreshCachedState()
		return cachedAuthorizationState
	}

	func requestAuthorization(
		for kinds: BrowserPermissionKindSet,
		completion: @escaping @MainActor (BrowserPermissionOSAuthorizationState) -> Void
	) {
		var mutableState = cachedState()
		let requestedKinds = kinds.kinds

		func requestNext(at index: Int) {
			guard index < requestedKinds.count else {
				self.cachedAuthorizationState = mutableState
				completion(mutableState)
				return
			}

			let kind = requestedKinds[index]
			switch kind {
			case .camera:
				requestCaptureAuthorization(for: .video) { status in
					mutableState[.camera] = status
					requestNext(at: index + 1)
				}
			case .microphone:
				requestCaptureAuthorization(for: .audio) { status in
					mutableState[.microphone] = status
					requestNext(at: index + 1)
				}
			case .geolocation:
				requestLocationAuthorization { status in
					mutableState[.geolocation] = status
					requestNext(at: index + 1)
				}
			}
		}

		requestNext(at: 0)
	}

	private func refreshCachedState() {
		let locationAuthorizer = environment.makeLocationAuthorizer()
		cachedAuthorizationState = BrowserPermissionOSAuthorizationState(
			camera: environment.captureAuthorizationStatus(.video),
			microphone: environment.captureAuthorizationStatus(.audio),
			geolocation: locationAuthorizer.currentStatus()
		)
	}

	private func requestCaptureAuthorization(
		for mediaType: AVMediaType,
		completion: @escaping @MainActor (BrowserPermissionOSAuthorizationStatus) -> Void
	) {
		let currentStatus = environment.captureAuthorizationStatus(mediaType)
		guard currentStatus == .notDetermined else {
			completion(currentStatus)
			return
		}

		environment.requestCaptureAccess(mediaType) { status in
			if mediaType == .video {
				self.cachedAuthorizationState[.camera] = status
			}
			else {
				self.cachedAuthorizationState[.microphone] = status
			}
			completion(status)
		}
	}

	private func requestLocationAuthorization(
		completion: @escaping @MainActor (BrowserPermissionOSAuthorizationStatus) -> Void
	) {
		let locationAuthorizer = environment.makeLocationAuthorizer()
		let currentStatus = locationAuthorizer.currentStatus()
		guard currentStatus == .notDetermined else {
			completion(currentStatus)
			return
		}

		activeLocationAuthorizer = locationAuthorizer
		locationAuthorizer.requestAuthorization { status in
			self.cachedAuthorizationState[.geolocation] = status
			self.activeLocationAuthorizer = nil
			completion(status)
		}
	}

	static func captureAuthorizationStatus(from status: AVAuthorizationStatus) -> BrowserPermissionOSAuthorizationStatus {
		switch status {
		case .notDetermined:
			.notDetermined
		case .restricted:
			.restricted
		case .denied:
			.denied
		case .authorized:
			.authorized
		@unknown default:
			.unsupported
		}
	}

	private static func captureAuthorizationStatus(for mediaType: AVMediaType) -> BrowserPermissionOSAuthorizationStatus {
		captureAuthorizationStatus(from: AVCaptureDevice.authorizationStatus(for: mediaType))
	}

	private static func requestCaptureAccessLive(
		for mediaType: AVMediaType,
		completion: @escaping @MainActor (BrowserPermissionOSAuthorizationStatus) -> Void
	) {
		let completeRequest: @Sendable (Bool) -> Void = { granted in
			DispatchQueue.main.async {
				completion(granted ? .authorized : .denied)
			}
		}
		requestSystemCaptureAccess(for: mediaType, completion: completeRequest)
	}

	private static func requestSystemCaptureAccess(
		for mediaType: AVMediaType,
		completion: @escaping @Sendable (Bool) -> Void
	) {
		#if DEBUG
			if let captureAccessRequesterOverride {
				captureAccessRequesterOverride(mediaType, completion)
				return
			}
		#endif
		AVCaptureDevice.requestAccess(for: mediaType, completionHandler: completion)
	}

	static func locationAuthorizationStatus(
		from status: CLAuthorizationStatus
	) -> BrowserPermissionOSAuthorizationStatus {
		switch status {
		case .notDetermined:
			.notDetermined
		case .restricted:
			.restricted
		case .denied:
			.denied
		case .authorizedAlways, .authorizedWhenInUse:
			.authorized
		@unknown default:
			.unsupported
		}
	}

	#if DEBUG
		static func setCaptureAccessRequesterForTesting(_ requester: @escaping CaptureAccessRequester) {
			captureAccessRequesterOverride = requester
		}

		static func resetCaptureAccessRequesterForTesting() {
			captureAccessRequesterOverride = nil
		}
	#endif
}

@MainActor
final class CoreLocationPermissionAuthorizer: NSObject, BrowserPermissionLocationAuthorizing {
	typealias LocationManagerFactory = @MainActor () -> CLLocationManager

	private let locationManagerFactory: LocationManagerFactory
	private var locationManager: CLLocationManager?
	private var completion: ((BrowserPermissionOSAuthorizationStatus) -> Void)?

	override init() {
		locationManagerFactory = { CLLocationManager() }
		super.init()
	}

	init(locationManagerFactory: @escaping LocationManagerFactory) {
		self.locationManagerFactory = locationManagerFactory
		super.init()
	}

	func currentStatus() -> BrowserPermissionOSAuthorizationStatus {
		BrowserPermissionAuthorizationController.locationAuthorizationStatus(
			from: locationManagerFactory().authorizationStatus
		)
	}

	func requestAuthorization(
		completion: @escaping @MainActor (BrowserPermissionOSAuthorizationStatus) -> Void
	) {
		let locationManager = locationManagerFactory()
		let currentStatus = BrowserPermissionAuthorizationController.locationAuthorizationStatus(
			from: locationManager.authorizationStatus
		)
		guard currentStatus == .notDetermined else {
			completion(currentStatus)
			return
		}

		self.completion = completion
		locationManager.delegate = self
		self.locationManager = locationManager
		locationManager.requestWhenInUseAuthorization()
	}

	private func handleLocationAuthorizationChange(_ status: CLAuthorizationStatus) {
		guard let completion else { return }
		let authorizationStatus = BrowserPermissionAuthorizationController.locationAuthorizationStatus(from: status)
		self.completion = nil
		locationManager = nil
		completion(authorizationStatus)
	}
}

extension CoreLocationPermissionAuthorizer: CLLocationManagerDelegate {
	nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
		let status = manager.authorizationStatus
		Task { @MainActor [weak self] in
			self?.handleLocationAuthorizationChange(status)
		}
	}
}
