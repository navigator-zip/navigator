import AppKit
@testable import Navigator
import XCTest

@MainActor
final class BrowserRootViewControllerTests: XCTestCase {
	func testToastTitleForegroundMatchesLabelColorInDarkMode() throws {
		let appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))

		assertColor(
			BrowserRootViewController.resolvedToastTitleForegroundColor(for: appearance),
			matches: resolvedColor(.labelColor, for: appearance),
			file: #filePath,
			line: #line
		)
	}

	func testToastSubtitleForegroundMatchesSecondaryLabelColorInDarkMode() throws {
		let appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))

		assertColor(
			BrowserRootViewController.resolvedToastSubtitleForegroundColor(for: appearance),
			matches: resolvedColor(.secondaryLabelColor, for: appearance),
			file: #filePath,
			line: #line
		)
	}

	private func resolvedColor(_ color: NSColor, for appearance: NSAppearance) -> NSColor {
		var resolved = color
		appearance.performAsCurrentDrawingAppearance {
			resolved = color.usingColorSpace(.deviceRGB) ?? color
		}
		return resolved
	}

	private func assertColor(
		_ actualColor: NSColor,
		matches expectedColor: NSColor,
		file: StaticString,
		line: UInt
	) {
		guard
			let actualRGB = actualColor.usingColorSpace(.deviceRGB),
			let expectedRGB = expectedColor.usingColorSpace(.deviceRGB)
		else {
			XCTFail("Unable to resolve colors for comparison", file: file, line: line)
			return
		}

		XCTAssertEqual(actualRGB.redComponent, expectedRGB.redComponent, accuracy: 0.001, file: file, line: line)
		XCTAssertEqual(actualRGB.greenComponent, expectedRGB.greenComponent, accuracy: 0.001, file: file, line: line)
		XCTAssertEqual(actualRGB.blueComponent, expectedRGB.blueComponent, accuracy: 0.001, file: file, line: line)
		XCTAssertEqual(actualRGB.alphaComponent, expectedRGB.alphaComponent, accuracy: 0.001, file: file, line: line)
	}
}
