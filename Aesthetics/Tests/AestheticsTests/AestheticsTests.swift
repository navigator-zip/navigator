@testable import Aesthetics
import AppIntents
import AppKit
import XCTest

final class AestheticsTests: XCTestCase {
	func testFrameSizeHelperUpdatesViewSize() {
		let view = NSView(frame: .zero)

		_ = view.frame(size: CGSize(width: 24, height: 48))

		XCTAssertEqual(view.frame.size.width, 24)
		XCTAssertEqual(view.frame.size.height, 48)
	}

	func testBrandColorExtensionExposesSharedTokens() {
		XCTAssertEqual(Color.brandAccent, Asset.Colors.accent.color)
		XCTAssertEqual(Color.brandAccentForeground, Asset.Colors.accentForegroundColor.color)
		XCTAssertEqual(Color.brandPrimarySeparator, Asset.Colors.separatorPrimaryColor.color)
		XCTAssertEqual(Color.brandSecondarySeparator, Asset.Colors.separatorSecondaryColor.color)
		XCTAssertEqual(Color.brandPrimaryText, Asset.Colors.textPrimaryColor.color)
		XCTAssertEqual(
			Color.brandUnmodifiedCodeBackground,
			Asset.Colors.unmodifiedCodeBackgroundColor.color
		)
		XCTAssertEqual(Color.brandBackground, Asset.Colors.background.color)
		XCTAssertEqual(Color.brandControlAccent, Asset.Colors.controlAccentColor.color)
		XCTAssertEqual(
			Color.navigatorChromeFill,
			NSColor.secondarySystemFill.withAlphaComponent(0.12)
		)
	}

	func testDoubleStrokePanelKeepsBorderOverlayAboveContentSubviews() {
		let panel = DoubleStrokePanelView(frame: NSRect(x: 0, y: 0, width: 120, height: 80))
		let contentView = NSView(frame: panel.bounds)

		panel.addSubview(contentView)
		panel.layoutSubtreeIfNeeded()

		XCTAssertEqual(panel.subviews.count, 2)
		XCTAssertNotEqual(panel.subviews.last, contentView)
	}

	func testDoubleStrokePanelBorderOverlayDoesNotInterceptHitTesting() {
		let panel = DoubleStrokePanelView(frame: NSRect(x: 0, y: 0, width: 120, height: 80))
		let contentView = NSView(frame: panel.bounds)

		panel.addSubview(contentView)
		panel.layoutSubtreeIfNeeded()

		XCTAssertTrue(panel.hitTest(NSPoint(x: 20, y: 20)) === contentView)
	}

	func testDoubleStrokePanelBorderOverlayUsesFiniteZPosition() throws {
		let panel = DoubleStrokePanelView(frame: NSRect(x: 0, y: 0, width: 120, height: 80))

		panel.layoutSubtreeIfNeeded()

		let overlayZPosition = try XCTUnwrap(panel.subviews.last?.layer?.zPosition)
		XCTAssertEqual(overlayZPosition, 1)
		XCTAssertLessThan(abs(overlayZPosition), CGFloat(Float.greatestFiniteMagnitude))
	}

	func testHorizontalSeparatorFitsItsRenderedStrokeHeight() {
		let divider = separator()
		let container = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 40))

		container.addSubview(divider)
		NSLayoutConstraint.activate([
			divider.topAnchor.constraint(equalTo: container.topAnchor),
			divider.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			divider.trailingAnchor.constraint(equalTo: container.trailingAnchor),
		])
		container.layoutSubtreeIfNeeded()

		XCTAssertEqual(divider.frame.height, 3)
	}
}
