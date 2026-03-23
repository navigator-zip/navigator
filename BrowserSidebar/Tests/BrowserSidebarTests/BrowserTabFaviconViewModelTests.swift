import AppKit
@testable import BrowserSidebar
import XCTest

@MainActor
final class BrowserTabFaviconViewModelTests: XCTestCase {
	func testLoadUsesExplicitFaviconURLWhenAvailable() async throws {
		let recorder = RequestedURLRecorder()
		let sampleImageData = try XCTUnwrap(Self.sampleImageData())
		let viewModel = BrowserTabFaviconViewModel { url in
			await recorder.record(url)
			return sampleImageData
		}

		await viewModel.load(
			faviconURL: "https://example.com/assets/icon.png",
			pageURL: "https://example.com/articles/1"
		)

		let requestedURLs = await recorder.snapshot()
		XCTAssertEqual(
			requestedURLs,
			try [
				XCTUnwrap(URL(string: "https://example.com/assets/icon.png")),
			]
		)
		XCTAssertNotNil(viewModel.image)
	}

	func testLoadFallsBackToHostFaviconWhenPageDoesNotExposeSpecificURL() async throws {
		let recorder = RequestedURLRecorder()
		let viewModel = BrowserTabFaviconViewModel { url in
			await recorder.record(url)
			return nil
		}

		await viewModel.load(
			faviconURL: nil,
			pageURL: "https://developer.apple.com/documentation"
		)

		let requestedURLs = await recorder.snapshot()
		XCTAssertEqual(requestedURLs, try [XCTUnwrap(URL(string: "https://developer.apple.com/favicon.ico"))])
		XCTAssertNil(viewModel.image)
	}

	func testLoadFallsBackToHostRootFaviconWhenExplicitFaviconReturnsNoData() async throws {
		let recorder = RequestedURLRecorder()
		let sampleImageData = try XCTUnwrap(Self.sampleImageData())
		let viewModel = BrowserTabFaviconViewModel { url in
			await recorder.record(url)
			if url == URL(string: "https://example.com/assets/icon.png") {
				return nil
			}
			return sampleImageData
		}

		await viewModel.load(
			faviconURL: "https://example.com/assets/icon.png",
			pageURL: "https://example.com/articles/1"
		)

		let requestedURLs = await recorder.snapshot()
		XCTAssertEqual(
			requestedURLs,
			try [
				XCTUnwrap(URL(string: "https://example.com/assets/icon.png")),
				XCTUnwrap(URL(string: "https://example.com/favicon.ico")),
			]
		)
		XCTAssertNotNil(viewModel.image)
	}

	func testLoadAvoidsDuplicateFetchForUnchangedResolvedSource() async throws {
		let recorder = RequestedURLRecorder()
		let sampleImageData = try XCTUnwrap(Self.sampleImageData())
		let viewModel = BrowserTabFaviconViewModel { url in
			await recorder.record(url)
			return sampleImageData
		}

		await viewModel.load(
			faviconURL: nil,
			pageURL: "https://navigator.zip/docs"
		)
		await viewModel.load(
			faviconURL: nil,
			pageURL: "https://navigator.zip/other"
		)

		let requestedURLs = await recorder.snapshot()
		XCTAssertEqual(requestedURLs, try [XCTUnwrap(URL(string: "https://navigator.zip/favicon.ico"))])
	}

	func testLoadAvoidsDuplicateFetchForUnchangedExplicitAndFallbackSources() async throws {
		let recorder = RequestedURLRecorder()
		let viewModel = BrowserTabFaviconViewModel { url in
			await recorder.record(url)
			return nil
		}

		await viewModel.load(
			faviconURL: "https://example.com/assets/icon.png",
			pageURL: "https://example.com/articles/1"
		)
		await viewModel.load(
			faviconURL: "https://example.com/assets/icon.png",
			pageURL: "https://example.com/articles/2"
		)

		let requestedURLs = await recorder.snapshot()
		XCTAssertEqual(
			requestedURLs,
			try [
				XCTUnwrap(URL(string: "https://example.com/assets/icon.png")),
				XCTUnwrap(URL(string: "https://example.com/favicon.ico")),
			]
		)
	}

	func testLoadClearsPreviousImageWhenResolvedSourceBecomesInvalid() async throws {
		let sampleImageData = try XCTUnwrap(Self.sampleImageData())
		let viewModel = BrowserTabFaviconViewModel { _ in
			sampleImageData
		}

		await viewModel.load(
			faviconURL: "https://example.com/icon.png",
			pageURL: "https://example.com"
		)
		XCTAssertNotNil(viewModel.image)

		await viewModel.load(
			faviconURL: nil,
			pageURL: "not a url"
		)

		XCTAssertNil(viewModel.image)
	}

	func testLoadDefaultsSchemeLessPageURLsToHTTPS() async throws {
		let recorder = RequestedURLRecorder()
		let viewModel = BrowserTabFaviconViewModel { url in
			await recorder.record(url)
			return nil
		}

		await viewModel.load(
			faviconURL: "   ",
			pageURL: "//developer.apple.com/documentation"
		)

		let requestedURLs = await recorder.snapshot()
		XCTAssertEqual(requestedURLs, try [XCTUnwrap(URL(string: "https://developer.apple.com/favicon.ico"))])
	}

	func testLoadRejectsUnsupportedOrSchemeLessExplicitFaviconURLs() async {
		let recorder = RequestedURLRecorder()
		let viewModel = BrowserTabFaviconViewModel { url in
			await recorder.record(url)
			return nil
		}

		await viewModel.load(
			faviconURL: "//developer.apple.com/favicon.ico",
			pageURL: "not a url"
		)
		await viewModel.load(
			faviconURL: nil,
			pageURL: "ftp://developer.apple.com/documentation"
		)

		let requestedURLs = await recorder.snapshot()
		XCTAssertTrue(requestedURLs.isEmpty)
		XCTAssertNil(viewModel.image)
	}

	func testRestoreCachedImageIfAvailableUsesDiskCacheWithoutStartingNetworkLoad() async throws {
		let cacheRecorder = RequestedURLRecorder()
		let networkRecorder = RequestedURLRecorder()
		let sampleImageData = try XCTUnwrap(Self.sampleImageData())
		let viewModel = BrowserTabFaviconViewModel(
			loadData: { url in
				await networkRecorder.record(url)
				return nil
			},
			loadCachedData: { url in
				await cacheRecorder.record(url)
				return sampleImageData
			}
		)

		let restored = await viewModel.restoreCachedImageIfAvailable(
			faviconURL: "https://example.com/icon.png",
			pageURL: "https://example.com/articles/1"
		)

		let cachedURLs = await cacheRecorder.snapshot()
		let networkURLs = await networkRecorder.snapshot()
		XCTAssertTrue(restored)
		XCTAssertEqual(
			cachedURLs,
			try [
				XCTUnwrap(URL(string: "https://example.com/icon.png")),
			]
		)
		XCTAssertTrue(networkURLs.isEmpty)
		XCTAssertNotNil(viewModel.image)
	}

	func testRestoreCachedImageIfAvailablePrefersExplicitFaviconURLOverHostFallback() async throws {
		let cacheRecorder = RequestedURLRecorder()
		let sampleImageData = try XCTUnwrap(Self.sampleImageData())
		let explicitURL = try XCTUnwrap(URL(string: "https://example.com/assets/icon.png"))
		let hostFallbackURL = try XCTUnwrap(URL(string: "https://example.com/favicon.ico"))
		let viewModel = BrowserTabFaviconViewModel(
			loadData: { _ in
				XCTFail("Expected cached restore path to avoid network loads")
				return nil
			},
			loadCachedData: { url in
				await cacheRecorder.record(url)
				return url == explicitURL ? sampleImageData : nil
			}
		)

		let restored = await viewModel.restoreCachedImageIfAvailable(
			faviconURL: explicitURL.absoluteString,
			pageURL: "https://example.com/articles/1"
		)

		let cachedURLs = await cacheRecorder.snapshot()
		XCTAssertTrue(restored)
		XCTAssertEqual(cachedURLs, [explicitURL])
		XCTAssertNotEqual(cachedURLs, [hostFallbackURL])
		XCTAssertNotNil(viewModel.image)
	}

	func testLoadCompletesSharedSameSourceAfterCallerCancellation() async throws {
		let sampleImageData = try XCTUnwrap(Self.sampleImageData())
		let loadStarted = LoadStartSignal()
		let viewModel = BrowserTabFaviconViewModel { _ in
			await loadStarted.markStarted()
			try? await Task.sleep(for: .milliseconds(60))
			return sampleImageData
		}

		let task = Task {
			await viewModel.load(
				faviconURL: "https://example.com/first.png",
				pageURL: "https://example.com/articles/1"
			)
		}
		try await waitForFirstLoadStart(loadStarted)
		task.cancel()
		await task.value

		XCTAssertNotNil(viewModel.image)
	}

	func testLoadReusesInflightSameSourceAfterCallerCancellation() async throws {
		let recorder = RequestedURLRecorder()
		let sampleImageData = try XCTUnwrap(Self.sampleImageData())
		let viewModel = BrowserTabFaviconViewModel { url in
			await recorder.record(url)
			try? await Task.sleep(for: .milliseconds(60))
			return sampleImageData
		}

		let firstTask = Task {
			await viewModel.load(
				faviconURL: "https://example.com/icon.png",
				pageURL: "https://example.com/articles/1"
			)
		}
		try await waitForRequestedURLCount(1, recorder: recorder)
		firstTask.cancel()
		await firstTask.value

		await viewModel.load(
			faviconURL: "https://example.com/icon.png",
			pageURL: "https://example.com/articles/1"
		)

		let requestedURLs = await recorder.snapshot()
		XCTAssertEqual(
			requestedURLs,
			try [
				XCTUnwrap(URL(string: "https://example.com/icon.png")),
			]
		)
		XCTAssertNotNil(viewModel.image)
	}

	private func waitForFirstLoadStart(
		_ signal: LoadStartSignal,
		file: StaticString = #filePath,
		line: UInt = #line
	) async throws {
		for _ in 0..<50 {
			if await signal.hasStarted() {
				return
			}
			try await Task.sleep(for: .milliseconds(10))
		}
		XCTFail("Expected first favicon load to start", file: file, line: line)
	}

	private func waitForRequestedURLCount(
		_ expectedCount: Int,
		recorder: RequestedURLRecorder,
		file: StaticString = #filePath,
		line: UInt = #line
	) async throws {
		for _ in 0..<50 {
			if await recorder.snapshot().count >= expectedCount {
				return
			}
			try await Task.sleep(for: .milliseconds(10))
		}
		XCTFail("Expected favicon load to record \(expectedCount) request(s)", file: file, line: line)
	}

	private static func sampleImageData() -> Data? {
		let image = NSImage(size: NSSize(width: 16, height: 16))
		image.lockFocus()
		NSColor.systemBlue.setFill()
		NSBezierPath(rect: NSRect(x: 0, y: 0, width: 16, height: 16)).fill()
		image.unlockFocus()
		return image.tiffRepresentation
	}
}

private actor RequestedURLRecorder {
	private var urls = [URL]()

	func record(_ url: URL) {
		urls.append(url)
	}

	func snapshot() -> [URL] {
		urls
	}
}

private actor LoadStartSignal {
	private var started = false

	func markStarted() {
		started = true
	}

	func hasStarted() -> Bool {
		started
	}
}
