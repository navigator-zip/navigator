import AppKit
@testable import BrowserSidebar
import XCTest

final class BrowserTabFaviconRepositoryTests: XCTestCase {
	func testDataLoaderReturnsImageDataForSuccessfulResponse() async throws {
		let url = try XCTUnwrap(URL(string: "https://example.com/favicon.ico"))
		let expectedData = try XCTUnwrap(Self.sampleImageData())
		let recorder = RequestRecorder()
		let loader = BrowserTabFaviconDataLoader { request in
			await recorder.record(request)
			let response = try XCTUnwrap(
				HTTPURLResponse(
					url: url,
					statusCode: 200,
					httpVersion: nil,
					headerFields: nil
				)
			)
			return (expectedData, response)
		}

		let data = await loader.data(for: url)

		XCTAssertEqual(data, expectedData)
		let requests = await recorder.requests()
		XCTAssertEqual(requests.map(\.url), [url])
		XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Accept"), "image/*")
	}

	func testDataLoaderRejectsNonSuccessResponsesEmptyDataAndThrownErrors() async throws {
		let url = try XCTUnwrap(URL(string: "https://example.com/favicon.ico"))
		let nonSuccessLoader = BrowserTabFaviconDataLoader { request in
			let response = try XCTUnwrap(
				try HTTPURLResponse(
					url: XCTUnwrap(request.url),
					statusCode: 404,
					httpVersion: nil,
					headerFields: nil
				)
			)
			return (Data("ignored".utf8), response)
		}
		let emptyLoader = BrowserTabFaviconDataLoader { request in
			let response = try XCTUnwrap(
				try HTTPURLResponse(
					url: XCTUnwrap(request.url),
					statusCode: 204,
					httpVersion: nil,
					headerFields: nil
				)
			)
			return (Data(), response)
		}
		struct SampleError: Error {}
		let failingLoader = BrowserTabFaviconDataLoader { _ in
			throw SampleError()
		}
		let nonSuccessData = await nonSuccessLoader.data(for: url)
		let emptyData = await emptyLoader.data(for: url)
		let failingData = await failingLoader.data(for: url)

		XCTAssertNil(nonSuccessData)
		XCTAssertNil(emptyData)
		XCTAssertNil(failingData)
	}

	func testRepositoryCachesEvictsAndSkipsNilValues() async throws {
		let firstURL = try XCTUnwrap(URL(string: "https://one.example/favicon.ico"))
		let secondURL = try XCTUnwrap(URL(string: "https://two.example/favicon.ico"))
		let missingURL = try XCTUnwrap(URL(string: "https://missing.example/favicon.ico"))
		let recorder = RepositoryLoaderRecorder(
			resultsByURL: [
				firstURL: Data("one".utf8),
				secondURL: Data("two".utf8),
				missingURL: nil,
			]
		)
		let repository = BrowserTabFaviconRepository(
			maximumCachedEntries: 1,
			loadData: { url in
				await recorder.load(url)
			}
		)
		let firstLoad = await repository.data(for: firstURL)
		let cachedFirstLoad = await repository.data(for: firstURL)
		let missingFirstLoad = await repository.data(for: missingURL)
		let missingSecondLoad = await repository.data(for: missingURL)
		let secondLoad = await repository.data(for: secondURL)
		let evictedFirstReload = await repository.data(for: firstURL)
		let firstCount = await recorder.count(for: firstURL)
		let secondCount = await recorder.count(for: secondURL)
		let missingCount = await recorder.count(for: missingURL)

		XCTAssertEqual(firstLoad, Data("one".utf8))
		XCTAssertEqual(cachedFirstLoad, Data("one".utf8))
		XCTAssertNil(missingFirstLoad)
		XCTAssertNil(missingSecondLoad)
		XCTAssertEqual(secondLoad, Data("two".utf8))
		XCTAssertEqual(evictedFirstReload, Data("one".utf8))

		XCTAssertEqual(firstCount, 2)
		XCTAssertEqual(secondCount, 1)
		XCTAssertEqual(missingCount, 2)

		_ = BrowserTabFaviconRepository()
	}

	func testRepositorySharesInflightRequestsForSameURL() async throws {
		let url = try XCTUnwrap(URL(string: "https://example.com/favicon.ico"))
		let expectedData = Data("favicon".utf8)
		let startRecorder = LoadStartRecorder()
		let repository = BrowserTabFaviconRepository(
			maximumCachedEntries: 1,
			loadData: { _ in
				await startRecorder.markStarted()
				try? await Task.sleep(for: .milliseconds(50))
				return expectedData
			}
		)

		let firstTask = Task {
			await repository.data(for: url)
		}
		try await waitForStarts(startRecorder, expectedCount: 1)
		let secondTask = Task {
			await repository.data(for: url)
		}

		let firstResult = await firstTask.value
		let secondResult = await secondTask.value
		let startedCount = await startRecorder.startedCount()

		XCTAssertEqual(firstResult, expectedData)
		XCTAssertEqual(secondResult, expectedData)
		XCTAssertEqual(startedCount, 1)
	}

	func testRepositoryReusesDiskCacheBeforeNetworkFetch() async throws {
		let url = try XCTUnwrap(URL(string: "https://example.com/favicon.ico"))
		let expectedData = Data("disk-cache".utf8)
		let cacheDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		let writerRepository = BrowserTabFaviconRepository(
			maximumCachedEntries: 1,
			loadData: { _ in expectedData },
			cacheDirectoryURL: cacheDirectoryURL
		)
		let readerRepository = BrowserTabFaviconRepository(
			maximumCachedEntries: 1,
			loadData: { _ in
				XCTFail("Expected disk cache hit before network fetch")
				return nil
			},
			cacheDirectoryURL: cacheDirectoryURL
		)

		_ = await writerRepository.data(for: url)
		let cachedData = await readerRepository.data(for: url)

		XCTAssertEqual(cachedData, expectedData)
		try? FileManager.default.removeItem(at: cacheDirectoryURL)
	}

	private func waitForStarts(
		_ recorder: LoadStartRecorder,
		expectedCount: Int,
		file: StaticString = #filePath,
		line: UInt = #line
	) async throws {
		for _ in 0..<50 {
			if await recorder.startedCount() == expectedCount {
				return
			}
			try await Task.sleep(for: .milliseconds(10))
		}
		XCTFail("Expected \(expectedCount) inflight request", file: file, line: line)
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

private actor RequestRecorder {
	private var recordedRequests = [URLRequest]()

	func record(_ request: URLRequest) {
		recordedRequests.append(request)
	}

	func requests() -> [URLRequest] {
		recordedRequests
	}
}

private actor RepositoryLoaderRecorder {
	private let resultsByURL: [URL: Data?]
	private var counts = [URL: Int]()

	init(resultsByURL: [URL: Data?]) {
		self.resultsByURL = resultsByURL
	}

	func load(_ url: URL) -> Data? {
		counts[url, default: 0] += 1
		return resultsByURL[url] ?? nil
	}

	func count(for url: URL) -> Int {
		counts[url, default: 0]
	}
}

private actor LoadStartRecorder {
	private var starts = 0

	func markStarted() {
		starts += 1
	}

	func startedCount() -> Int {
		starts
	}
}
