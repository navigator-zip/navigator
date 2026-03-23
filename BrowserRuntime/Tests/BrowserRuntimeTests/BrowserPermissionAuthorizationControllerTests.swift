import AVFoundation
@testable import BrowserRuntime
import CoreLocation
import ModelKit
import ObjectiveC.runtime
import XCTest

@MainActor
@objcMembers
private final class AVCaptureDeviceRequestAccessSwizzler: NSObject {
	static var handler: ((AVMediaType, @escaping (Bool) -> Void) -> Void)?

	@objc(navigator_test_requestAccessForMediaType:completionHandler:)
	class func navigator_test_requestAccess(
		for mediaType: NSString,
		completionHandler: @escaping (Bool) -> Void
	) {
		handler?(AVMediaType(rawValue: mediaType as String), completionHandler)
	}
}

@MainActor
final class BrowserPermissionAuthorizationControllerTests: XCTestCase {
	func testMappingHelpersCoverKnownSystemStatuses() {
		XCTAssertEqual(
			BrowserPermissionAuthorizationController.captureAuthorizationStatus(from: .notDetermined),
			.notDetermined
		)
		XCTAssertEqual(
			BrowserPermissionAuthorizationController.captureAuthorizationStatus(from: .restricted),
			.restricted
		)
		XCTAssertEqual(
			BrowserPermissionAuthorizationController.captureAuthorizationStatus(from: .denied),
			.denied
		)
		XCTAssertEqual(
			BrowserPermissionAuthorizationController.captureAuthorizationStatus(from: .authorized),
			.authorized
		)

		XCTAssertEqual(
			BrowserPermissionAuthorizationController.locationAuthorizationStatus(from: .notDetermined),
			.notDetermined
		)
		XCTAssertEqual(
			BrowserPermissionAuthorizationController.locationAuthorizationStatus(from: .restricted),
			.restricted
		)
		XCTAssertEqual(
			BrowserPermissionAuthorizationController.locationAuthorizationStatus(from: .denied),
			.denied
		)
		XCTAssertEqual(
			BrowserPermissionAuthorizationController.locationAuthorizationStatus(from: .authorizedAlways),
			.authorized
		)
	}

	func testMappingHelpersCoverUnknownSystemStatuses() throws {
		let unknownCaptureStatus = try XCTUnwrap(AVAuthorizationStatus(rawValue: 99))
		let unknownLocationStatus = try XCTUnwrap(CLAuthorizationStatus(rawValue: 99))

		XCTAssertEqual(
			BrowserPermissionAuthorizationController.captureAuthorizationStatus(from: unknownCaptureStatus),
			.unsupported
		)
		XCTAssertEqual(
			BrowserPermissionAuthorizationController.locationAuthorizationStatus(from: unknownLocationStatus),
			.unsupported
		)
	}

	func testLiveEnvironmentAndDefaultInitializerProvideConcreteAuthorizers() {
		let environment = BrowserPermissionAuthorizationController.Environment.live
		let locationAuthorizer = environment.makeLocationAuthorizer()
		let controller = BrowserPermissionAuthorizationController()

		XCTAssertNotNil(locationAuthorizer as AnyObject)
		_ = controller.cachedState()
	}

	func testLiveEnvironmentCaptureAccessUsesInjectedRequester() {
		defer {
			BrowserPermissionAuthorizationController.resetCaptureAccessRequesterForTesting()
		}
		BrowserPermissionAuthorizationController.setCaptureAccessRequesterForTesting { _, completion in
			completion(true)
		}
		let environment = BrowserPermissionAuthorizationController.Environment.live
		var completionStatus: BrowserPermissionOSAuthorizationStatus?
		let completionExpectation = expectation(description: "capture completion")

		environment.requestCaptureAccess(.video) { status in
			completionStatus = status
			completionExpectation.fulfill()
		}

		wait(for: [completionExpectation], timeout: 1)
		XCTAssertEqual(completionStatus, .authorized)
	}

	func testLiveEnvironmentCaptureAccessMapsDeniedResult() {
		defer {
			BrowserPermissionAuthorizationController.resetCaptureAccessRequesterForTesting()
		}
		BrowserPermissionAuthorizationController.setCaptureAccessRequesterForTesting { _, completion in
			completion(false)
		}
		let environment = BrowserPermissionAuthorizationController.Environment.live
		var completionStatus: BrowserPermissionOSAuthorizationStatus?
		let completionExpectation = expectation(description: "capture completion denied")

		environment.requestCaptureAccess(.audio) { status in
			completionStatus = status
			completionExpectation.fulfill()
		}

		wait(for: [completionExpectation], timeout: 1)
		XCTAssertEqual(completionStatus, .denied)
	}

	func testLiveEnvironmentCaptureAccessFallsBackToSystemRequesterWhenNoOverrideExists() throws {
		BrowserPermissionAuthorizationController.resetCaptureAccessRequesterForTesting()

		let originalSelector = NSSelectorFromString("requestAccessForMediaType:completionHandler:")
		let swizzledSelector = #selector(
			AVCaptureDeviceRequestAccessSwizzler.navigator_test_requestAccess(for:completionHandler:)
		)
		let originalMethod = try XCTUnwrap(class_getClassMethod(AVCaptureDevice.self, originalSelector))
		let swizzledMethod = try XCTUnwrap(
			class_getClassMethod(AVCaptureDeviceRequestAccessSwizzler.self, swizzledSelector)
		)
		method_exchangeImplementations(originalMethod, swizzledMethod)
		defer {
			method_exchangeImplementations(swizzledMethod, originalMethod)
			AVCaptureDeviceRequestAccessSwizzler.handler = nil
		}

		AVCaptureDeviceRequestAccessSwizzler.handler = { mediaType, completion in
			XCTAssertEqual(mediaType, .video)
			completion(false)
		}

		let environment = BrowserPermissionAuthorizationController.Environment.live
		var completionStatus: BrowserPermissionOSAuthorizationStatus?
		let completionExpectation = expectation(description: "capture completion default path")

		environment.requestCaptureAccess(.video) { status in
			completionStatus = status
			completionExpectation.fulfill()
		}

		wait(for: [completionExpectation], timeout: 1)
		XCTAssertEqual(completionStatus, .denied)
	}

	func testCachedStateUsesInjectedEnvironment() {
		let locationAuthorizer = BrowserPermissionLocationAuthorizerSpy(currentStatusValue: .restricted)
		let controller = BrowserPermissionAuthorizationController(
			environment: .init(
				captureAuthorizationStatus: { mediaType in
					switch mediaType {
					case .video:
						.authorized
					case .audio:
						.denied
					default:
						.unsupported
					}
				},
				requestCaptureAccess: { _, _ in
					XCTFail("Unexpected capture access request")
				},
				makeLocationAuthorizer: {
					locationAuthorizer
				}
			)
		)

		XCTAssertEqual(
			controller.cachedState(),
			BrowserPermissionOSAuthorizationState(
				camera: .authorized,
				microphone: .denied,
				geolocation: .restricted
			)
		)
	}

	func testRequestAuthorizationReturnsDeterminedStatusesWithoutPromptingOS() {
		let locationAuthorizer = BrowserPermissionLocationAuthorizerSpy(currentStatusValue: .authorized)
		var requestedCaptureTypes = [AVMediaType]()
		let controller = BrowserPermissionAuthorizationController(
			environment: .init(
				captureAuthorizationStatus: { mediaType in
					switch mediaType {
					case .video:
						.authorized
					case .audio:
						.denied
					default:
						.unsupported
					}
				},
				requestCaptureAccess: { mediaType, _ in
					requestedCaptureTypes.append(mediaType)
				},
				makeLocationAuthorizer: {
					locationAuthorizer
				}
			)
		)
		var completionState: BrowserPermissionOSAuthorizationState?
		let requestedKinds: BrowserPermissionKindSet = [.camera, .microphone, .geolocation]

		controller.requestAuthorization(for: requestedKinds) { completionState = $0 }

		XCTAssertEqual(
			completionState,
			BrowserPermissionOSAuthorizationState(
				camera: .authorized,
				microphone: .denied,
				geolocation: .authorized
			)
		)
		XCTAssertTrue(requestedCaptureTypes.isEmpty)
		XCTAssertEqual(locationAuthorizer.requestCount, 0)
	}

	func testRequestAuthorizationChainsCaptureAndLocationRequests() {
		final class StateBox {
			var captureStatuses: [AVMediaType: BrowserPermissionOSAuthorizationStatus] = [
				.video: .notDetermined,
				.audio: .notDetermined,
			]
		}

		let stateBox = StateBox()
		let locationAuthorizer = BrowserPermissionLocationAuthorizerSpy(currentStatusValue: .notDetermined)
		var requestedCaptureTypes = [AVMediaType]()
		let controller = BrowserPermissionAuthorizationController(
			environment: .init(
				captureAuthorizationStatus: { mediaType in
					stateBox.captureStatuses[mediaType] ?? .unsupported
				},
				requestCaptureAccess: { mediaType, completion in
					requestedCaptureTypes.append(mediaType)
					let resolvedStatus: BrowserPermissionOSAuthorizationStatus = mediaType == .video ? .authorized : .denied
					stateBox.captureStatuses[mediaType] = resolvedStatus
					completion(resolvedStatus)
				},
				makeLocationAuthorizer: {
					locationAuthorizer
				}
			)
		)
		var completionState: BrowserPermissionOSAuthorizationState?
		let requestedKinds: BrowserPermissionKindSet = [.camera, .microphone, .geolocation]

		controller.requestAuthorization(for: requestedKinds) { completionState = $0 }

		XCTAssertEqual(requestedCaptureTypes, [.video, .audio])
		XCTAssertEqual(locationAuthorizer.requestCount, 1)
		XCTAssertNil(completionState)

		locationAuthorizer.finish(with: .authorized)

		XCTAssertEqual(
			completionState,
			BrowserPermissionOSAuthorizationState(
				camera: .authorized,
				microphone: .denied,
				geolocation: .authorized
			)
		)
		XCTAssertEqual(controller.cachedState().camera, .authorized)
		XCTAssertEqual(controller.cachedState().microphone, .denied)
		XCTAssertEqual(controller.cachedState().geolocation, .authorized)
	}

	func testCoreLocationPermissionAuthorizerRequestsAndHandlesDelegateChanges() {
		let manager = FakeCoreLocationManager()
		manager.fakeAuthorizationStatus = .notDetermined
		let authorizer = CoreLocationPermissionAuthorizer(locationManagerFactory: { manager })
		var completionStatus: BrowserPermissionOSAuthorizationStatus?

		XCTAssertEqual(authorizer.currentStatus(), .notDetermined)

		authorizer.requestAuthorization { completionStatus = $0 }

		XCTAssertEqual(manager.requestWhenInUseAuthorizationCount, 1)
		XCTAssertNil(completionStatus)

		manager.fakeAuthorizationStatus = .denied
		authorizer.locationManagerDidChangeAuthorization(manager)
		let delegateExpectation = expectation(description: "location delegate callback processed")
		DispatchQueue.main.async {
			delegateExpectation.fulfill()
		}
		wait(for: [delegateExpectation], timeout: 1)

		XCTAssertEqual(completionStatus, .denied)
	}

	func testCoreLocationPermissionAuthorizerReturnsDeterminedStatusImmediately() {
		let manager = FakeCoreLocationManager()
		manager.fakeAuthorizationStatus = .authorizedAlways
		let authorizer = CoreLocationPermissionAuthorizer(locationManagerFactory: { manager })
		var completionStatus: BrowserPermissionOSAuthorizationStatus?

		authorizer.requestAuthorization { completionStatus = $0 }

		XCTAssertEqual(completionStatus, .authorized)
		XCTAssertEqual(manager.requestWhenInUseAuthorizationCount, 0)
	}

	func testCoreLocationPermissionAuthorizerIgnoresDelegateChangesWithoutPendingCompletion() {
		let manager = FakeCoreLocationManager()
		manager.fakeAuthorizationStatus = .denied
		let authorizer = CoreLocationPermissionAuthorizer(locationManagerFactory: { manager })

		authorizer.locationManagerDidChangeAuthorization(manager)

		let delegateExpectation = expectation(description: "location delegate noop processed")
		DispatchQueue.main.async {
			delegateExpectation.fulfill()
		}
		wait(for: [delegateExpectation], timeout: 1)
	}
}
