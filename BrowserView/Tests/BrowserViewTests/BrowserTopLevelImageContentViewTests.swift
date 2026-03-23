import AppKit
import BrowserRuntime
@testable import BrowserView
import XCTest

@MainActor
final class BrowserTopLevelImageContentViewTests: XCTestCase {
	func testPortraitImageUsesCenteredEightyPercentHeightFrame() {
		let content = BrowserRuntimeTopLevelNativeContent(
			kind: .image,
			url: "https://navigator.test/portrait.png",
			pathExtension: "png",
			uniformTypeIdentifier: "public.png"
		)
		let portraitImage = NSImage(size: CGSize(width: 200, height: 400))
		let view = BrowserTopLevelImageContentView(
			viewModel: BrowserTopLevelImageContentViewModel(content: content, image: portraitImage)
		)
		let window = makeWindow(size: CGSize(width: 500, height: 400))

		host(view, in: window, size: CGSize(width: 500, height: 400))
		view.layoutSubtreeIfNeeded()

		let expectedHeight = view.bounds.height * 0.8
		let expectedWidth = expectedHeight * 0.5

		XCTAssertEqual(view.preferredSizingModeForTesting, .fixedHeight)
		XCTAssertEqual(view.imageViewForTesting.frame.width, expectedWidth, accuracy: 0.5)
		XCTAssertEqual(view.imageViewForTesting.frame.height, expectedHeight, accuracy: 0.5)
		XCTAssertEqual(view.imageViewForTesting.frame.midY, view.bounds.midY, accuracy: 0.5)
	}

	func testLandscapeImageUsesCenteredEightyPercentWidthFrame() {
		let content = BrowserRuntimeTopLevelNativeContent(
			kind: .image,
			url: "https://navigator.test/landscape.png",
			pathExtension: "png",
			uniformTypeIdentifier: "public.png"
		)
		let landscapeImage = NSImage(size: CGSize(width: 400, height: 200))
		let view = BrowserTopLevelImageContentView(
			viewModel: BrowserTopLevelImageContentViewModel(content: content, image: landscapeImage)
		)
		let window = makeWindow(size: CGSize(width: 500, height: 400))

		host(view, in: window, size: CGSize(width: 500, height: 400))
		view.layoutSubtreeIfNeeded()

		let expectedWidth = view.bounds.width * 0.8
		let expectedHeight = expectedWidth * 0.5

		XCTAssertEqual(view.preferredSizingModeForTesting, .fixedWidth)
		XCTAssertEqual(view.imageViewForTesting.frame.width, expectedWidth, accuracy: 0.5)
		XCTAssertEqual(view.imageViewForTesting.frame.height, expectedHeight, accuracy: 0.5)
		XCTAssertEqual(view.imageViewForTesting.frame.midX, view.bounds.midX, accuracy: 0.5)
	}

	func testMissingImageShowsFailureText() {
		let content = BrowserRuntimeTopLevelNativeContent(
			kind: .image,
			url: "https://navigator.test/missing.png",
			pathExtension: "png",
			uniformTypeIdentifier: "public.png"
		)
		let view = BrowserTopLevelImageContentView(
			viewModel: BrowserTopLevelImageContentViewModel(content: content)
		)

		XCTAssertEqual(view.failureTextForTesting, content.url)
		XCTAssertTrue(view.imageViewForTesting.isHidden)
	}

	func testLargeImageDoesNotExposeRawIntrinsicSizeToWindowLayout() {
		let content = BrowserRuntimeTopLevelNativeContent(
			kind: .image,
			url: "https://navigator.test/huge-landscape.png",
			pathExtension: "png",
			uniformTypeIdentifier: "public.png"
		)
		let hugeImage = NSImage(size: CGSize(width: 12000, height: 3000))
		let view = BrowserTopLevelImageContentView(
			viewModel: BrowserTopLevelImageContentViewModel(content: content, image: hugeImage)
		)

		XCTAssertEqual(view.imageViewIntrinsicContentSizeForTesting.width, NSView.noIntrinsicMetric)
		XCTAssertEqual(view.imageViewIntrinsicContentSizeForTesting.height, NSView.noIntrinsicMetric)
	}
}
