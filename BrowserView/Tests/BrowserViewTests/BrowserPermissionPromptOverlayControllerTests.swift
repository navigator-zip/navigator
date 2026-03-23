@testable import BrowserView
import ModelKit
import XCTest

@MainActor
final class BrowserPermissionPromptOverlayControllerTests: XCTestCase {
	func testTextValuesExposePromptCopyAndButtons() {
		let overlay = BrowserPermissionPromptOverlayController(localize: localizedString)
		let session = makeSession(
			source: .permissionPrompt,
			requestingOrigin: "https://navigator.test",
			topLevelOrigin: "https://navigator.test",
			promptKinds: [.camera, .microphone]
		)

		overlay.setPrompt(session, onDecision: { _, _ in }, onCancel: {})

		XCTAssertTrue(overlay.isVisibleForTesting)
		XCTAssertTrue(overlay.textValuesForTesting.contains("same:https://navigator.test"))
		XCTAssertTrue(overlay.textValuesForTesting.contains("permission"))
		XCTAssertTrue(overlay.textValuesForTesting.contains(where: { $0.contains("camera") }))
		XCTAssertTrue(overlay.textValuesForTesting.contains(where: { $0.contains("microphone") }))
		XCTAssertTrue(overlay.textValuesForTesting.contains("remember"))
		XCTAssertTrue(overlay.textValuesForTesting.contains("not-now"))
		XCTAssertTrue(overlay.textValuesForTesting.contains("deny"))
		XCTAssertTrue(overlay.textValuesForTesting.contains("allow"))
	}

	func testDefaultLocalizerBuildsNonEmptyPromptText() {
		let overlay = BrowserPermissionPromptOverlayController()
		let session = makeSession(
			source: .permissionPrompt,
			requestingOrigin: "https://navigator.test",
			topLevelOrigin: "https://navigator.test",
			promptKinds: [.camera]
		)

		overlay.setPrompt(session, onDecision: { _, _ in }, onCancel: {})

		XCTAssertTrue(overlay.isVisibleForTesting)
		XCTAssertFalse(overlay.textValuesForTesting.isEmpty)
	}

	func testDebugAccessorsReturnEmptyValuesBeforePromptIsInstalled() {
		let overlay = BrowserPermissionPromptOverlayController(localize: localizedString)

		overlay.setRememberForTesting(true)

		XCTAssertFalse(overlay.isVisibleForTesting)
		XCTAssertEqual(overlay.textValuesForTesting, [])
	}

	func testCrossOriginMediaPromptUsesSessionPersistenceAndCancel() {
		let overlay = BrowserPermissionPromptOverlayController(localize: localizedString)
		let session = makeSession(
			source: .mediaAccess,
			requestingOrigin: "https://frame.example",
			topLevelOrigin: "https://app.example",
			promptKinds: [.geolocation]
		)
		var decisions = [(BrowserPermissionPromptDecision, BrowserPermissionPersistence)]()
		var cancelCount = 0

		overlay.setPrompt(
			session,
			onDecision: { decisions.append(($0, $1)) },
			onCancel: { cancelCount += 1 }
		)

		XCTAssertTrue(overlay.textValuesForTesting.contains("cross:https://frame.example|https://app.example"))
		XCTAssertTrue(overlay.textValuesForTesting.contains("media"))
		XCTAssertTrue(overlay.textValuesForTesting.contains(where: { $0.contains("location") }))

		overlay.performDenyForTesting()
		overlay.performCancelForTesting()

		XCTAssertEqual(decisions.count, 1)
		XCTAssertEqual(decisions.first?.0, .deny)
		XCTAssertEqual(decisions.first?.1, .session)
		XCTAssertEqual(cancelCount, 1)
	}

	private func localizedString(_ key: BrowserPermissionPromptLocalizationKey) -> String {
		switch key {
		case .remember:
			"remember"
		case .notNow:
			"not-now"
		case .deny:
			"deny"
		case .allow:
			"allow"
		case .titleSameOrigin:
			"same:%@"
		case .titleCrossOrigin:
			"cross:%@|%@"
		case .subtitleMedia:
			"media"
		case .subtitlePermission:
			"permission"
		case .kindCamera:
			"camera"
		case .kindMicrophone:
			"microphone"
		case .kindLocation:
			"location"
		}
	}

	private func makeSession(
		source: BrowserPermissionRequestSource,
		requestingOrigin: String,
		topLevelOrigin: String,
		promptKinds: BrowserPermissionKindSet
	) -> BrowserPermissionSession {
		BrowserPermissionSession(
			id: 1,
			browserID: 2,
			promptID: 3,
			frameIdentifier: "frame-1",
			source: source,
			origin: BrowserPermissionOrigin(
				requestingOrigin: requestingOrigin,
				topLevelOrigin: topLevelOrigin
			),
			requestedKinds: promptKinds,
			promptKinds: promptKinds,
			state: .waitingForUserPrompt,
			siteDecision: nil,
			persistence: nil,
			osAuthorizationState: BrowserPermissionOSAuthorizationState(),
			createdAt: .distantPast,
			updatedAt: .distantPast
		)
	}
}
