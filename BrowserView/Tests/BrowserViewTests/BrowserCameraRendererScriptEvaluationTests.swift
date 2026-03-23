@testable import BrowserView
import XCTest

final class BrowserCameraRendererScriptEvaluationTests: XCTestCase {
	func testRequiresBrowserProcessFallbackWhenRendererReturnsMissingShim() {
		XCTAssertTrue(
			BrowserCameraRendererScriptEvaluation.requiresBrowserProcessFallback(
				result: BrowserCameraRendererScriptStatus.missingShim.rawValue,
				error: nil
			)
		)
	}

	func testRequiresBrowserProcessFallbackWhenRendererReturnsError() {
		XCTAssertTrue(
			BrowserCameraRendererScriptEvaluation.requiresBrowserProcessFallback(
				result: BrowserCameraRendererScriptStatus.installed.rawValue,
				error: "Renderer unavailable"
			)
		)
	}

	func testDoesNotRequireBrowserProcessFallbackForSuccessfulRendererResult() {
		XCTAssertFalse(
			BrowserCameraRendererScriptEvaluation.requiresBrowserProcessFallback(
				result: BrowserCameraRendererScriptStatus.delivered.rawValue,
				error: ""
			)
		)
	}

	func testBrowserProcessFallbackReasonUsesRendererErrorWhenPresent() {
		XCTAssertEqual(
			BrowserCameraRendererScriptEvaluation.browserProcessFallbackReason(
				result: BrowserCameraRendererScriptStatus.delivered.rawValue,
				error: "Renderer unavailable"
			),
			"rendererError=Renderer unavailable"
		)
	}

	func testBrowserProcessFallbackReasonUsesRendererResultWhenErrorIsAbsent() {
		XCTAssertEqual(
			BrowserCameraRendererScriptEvaluation.browserProcessFallbackReason(
				result: BrowserCameraRendererScriptStatus.missingShim.rawValue,
				error: nil
			),
			"rendererResult=missing-shim"
		)
	}

	func testBrowserProcessFallbackReasonUsesNoneWhenRendererResultIsAbsent() {
		XCTAssertEqual(
			BrowserCameraRendererScriptEvaluation.browserProcessFallbackReason(
				result: nil,
				error: nil
			),
			"rendererResult=none"
		)
	}
}
