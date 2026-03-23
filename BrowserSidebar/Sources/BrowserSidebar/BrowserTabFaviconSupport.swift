import AppKit
import CryptoKit
import Foundation
import Observation

@MainActor
@Observable
final class BrowserTabFaviconViewModel {
	private struct SourceRequest {
		let key: String
		let urls: [URL]
	}

	private(set) var image: NSImage?
	private var activeSourceKey: String?
	private var resolvedSourceKey: String?
	private var activeSourceTask: Task<Data?, Never>?

	private let loadCachedData: @Sendable (URL) async -> Data?
	private let loadData: @Sendable (URL) async -> Data?

	init(
		loadData: @escaping @Sendable (URL) async -> Data? = { url in
			await BrowserTabFaviconRepository.shared.data(for: url)
		},
		loadCachedData: @escaping @Sendable (URL) async -> Data? = { url in
			await BrowserTabFaviconRepository.shared.cachedData(for: url)
		}
	) {
		self.loadData = loadData
		self.loadCachedData = loadCachedData
	}

	func load(faviconURL: String?, pageURL: String) async {
		let sourceRequest = resolvedSourceRequest(faviconURL: faviconURL, pageURL: pageURL)
		let sourceURLs = sourceRequest.urls
		let sourceKey = sourceRequest.key

		guard resolvedSourceKey != sourceKey else { return }
		if activeSourceKey != sourceKey {
			activeSourceTask?.cancel()
			activeSourceKey = sourceKey
			resolvedSourceKey = nil
			image = nil

			guard sourceURLs.isEmpty == false else {
				activeSourceTask = nil
				resolvedSourceKey = sourceKey
				return
			}

			let loadData = self.loadData
			activeSourceTask = Task { @Sendable in
				await Self.loadFirstAvailableData(
					from: sourceURLs,
					loadData: loadData
				)
			}
		}

		guard activeSourceKey == sourceKey else { return }
		guard let activeSourceTask else { return }
		let data = await activeSourceTask.value
		guard activeSourceKey == sourceKey else { return }
		self.activeSourceTask = nil
		image = data.flatMap(NSImage.init(data:))
		resolvedSourceKey = sourceKey
	}

	func restoreCachedImageIfAvailable(faviconURL: String?, pageURL: String) async -> Bool {
		let sourceRequest = resolvedSourceRequest(faviconURL: faviconURL, pageURL: pageURL)
		let sourceURLs = sourceRequest.urls
		let sourceKey = sourceRequest.key

		guard sourceURLs.isEmpty == false else { return false }
		guard resolvedSourceKey != sourceKey || image == nil else { return true }
		guard activeSourceKey != sourceKey else { return false }

		let loadCachedData = self.loadCachedData
		let data = await Self.loadFirstAvailableData(
			from: sourceURLs,
			loadData: loadCachedData
		)
		guard activeSourceKey != sourceKey else { return false }
		guard let data, let cachedImage = NSImage(data: data) else { return false }
		image = cachedImage
		resolvedSourceKey = sourceKey
		return true
	}

	private nonisolated static func loadFirstAvailableData(
		from sourceURLs: [URL],
		loadData: @escaping @Sendable (URL) async -> Data?
	) async -> Data? {
		for sourceURL in sourceURLs {
			guard !Task.isCancelled else { return nil }
			guard let data = await loadData(sourceURL) else { continue }
			return data
		}
		return nil
	}

	private func resolvedSourceRequest(faviconURL: String?, pageURL: String) -> SourceRequest {
		let urls = resolvedSourceURLs(faviconURL: faviconURL, pageURL: pageURL)
		return SourceRequest(
			key: urls.map(\.absoluteString).joined(separator: "|"),
			urls: urls
		)
	}

	private func resolvedSourceURLs(faviconURL: String?, pageURL: String) -> [URL] {
		var sourceURLs = [URL]()
		if let explicitFaviconURL = explicitFaviconURL(from: faviconURL) {
			sourceURLs.append(explicitFaviconURL)
		}
		if let hostFaviconURL = hostFaviconURL(from: pageURL),
		   sourceURLs.contains(hostFaviconURL) == false {
			sourceURLs.append(hostFaviconURL)
		}
		return sourceURLs
	}

	private func explicitFaviconURL(from faviconURL: String?) -> URL? {
		guard let faviconURL = normalizedURLString(faviconURL),
		      let url = URL(string: faviconURL),
		      isSupportedURL(url) else {
			return nil
		}
		return url
	}

	private func hostFaviconURL(from pageURL: String) -> URL? {
		guard var components = URLComponents(string: pageURL), let host = components.host, !host.isEmpty else {
			return nil
		}
		components.scheme = components.scheme?.isEmpty == false ? components.scheme : "https"
		components.user = nil
		components.password = nil
		components.path = "/favicon.ico"
		components.query = nil
		components.fragment = nil
		guard let url = components.url, isSupportedURL(url) else { return nil }
		return url
	}

	private func normalizedURLString(_ value: String?) -> String? {
		guard let value else { return nil }
		let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmedValue.isEmpty ? nil : trimmedValue
	}

	private func isSupportedURL(_ url: URL) -> Bool {
		guard let scheme = url.scheme?.lowercased() else { return false }
		return scheme == "http" || scheme == "https"
	}
}

actor BrowserTabFaviconRepository {
	static let shared = BrowserTabFaviconRepository()

	private enum DiskCache {
		static let directoryName = "NavigatorFavicons"
		static let fileExtension = "favicon"
	}

	private let maximumCachedEntries: Int
	private let loadData: @Sendable (URL) async -> Data?
	private let cacheDirectoryURL: URL?
	private let fileManager: FileManager
	private var cachedDataByURL = [URL: Data]()
	private var cacheOrder = [URL]()
	private var inflightRequests = [URL: Task<Data?, Never>]()

	init(maximumCachedEntries: Int = 128) {
		self.maximumCachedEntries = maximumCachedEntries
		self.loadData = BrowserTabFaviconDataLoader().data(for:)
		self.fileManager = .default
		self.cacheDirectoryURL = Self.defaultCacheDirectoryURL(fileManager: fileManager)
	}

	init(
		maximumCachedEntries: Int,
		loadData: @escaping @Sendable (URL) async -> Data?,
		cacheDirectoryURL: URL? = nil,
		fileManager: FileManager = .default
	) {
		self.maximumCachedEntries = maximumCachedEntries
		self.loadData = loadData
		self.cacheDirectoryURL = cacheDirectoryURL
		self.fileManager = fileManager
	}

	func data(for url: URL) async -> Data? {
		if let cachedData = await cachedData(for: url) {
			return cachedData
		}
		if let inflightRequest = inflightRequests[url] {
			return await inflightRequest.value
		}

		let loadData = self.loadData
		let requestTask = Task { [loadData, url] in
			await loadData(url)
		}
		inflightRequests[url] = requestTask
		defer {
			inflightRequests[url] = nil
		}

		let data = await requestTask.value

		if let data {
			store(data: data, for: url)
			storeOnDisk(data: data, for: url)
		}
		return data
	}

	func cachedData(for url: URL) async -> Data? {
		if let cachedData = cachedDataByURL[url] {
			return cachedData
		}
		if let cachedData = cachedDataOnDisk(for: url) {
			store(data: cachedData, for: url)
			return cachedData
		}
		return nil
	}

	private func store(data: Data, for url: URL) {
		if cachedDataByURL[url] == nil {
			cacheOrder.append(url)
		}
		cachedDataByURL[url] = data

		while cacheOrder.count > maximumCachedEntries {
			let evictedURL = cacheOrder.removeFirst()
			cachedDataByURL.removeValue(forKey: evictedURL)
		}
	}

	private func cachedDataOnDisk(for url: URL) -> Data? {
		guard let fileURL = diskCacheFileURL(for: url) else { return nil }
		guard let data = try? Data(contentsOf: fileURL), data.isEmpty == false else { return nil }
		return data
	}

	private func storeOnDisk(data: Data, for url: URL) {
		guard let directoryURL = cacheDirectoryURL else { return }
		guard let fileURL = diskCacheFileURL(for: url) else { return }

		do {
			try fileManager.createDirectory(
				at: directoryURL,
				withIntermediateDirectories: true,
				attributes: nil
			)
			try data.write(to: fileURL, options: .atomic)
		}
		catch {}
	}

	private func diskCacheFileURL(for url: URL) -> URL? {
		guard let cacheDirectoryURL else { return nil }
		return cacheDirectoryURL.appendingPathComponent(
			Self.diskCacheFileName(for: url),
			isDirectory: false
		)
	}

	private nonisolated static func diskCacheFileName(for url: URL) -> String {
		let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
		let hexDigest = digest.map { String(format: "%02x", $0) }.joined()
		return "\(hexDigest).\(DiskCache.fileExtension)"
	}

	private nonisolated static func defaultCacheDirectoryURL(fileManager: FileManager) -> URL? {
		fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?
			.appendingPathComponent(DiskCache.directoryName, isDirectory: true)
	}
}

struct BrowserTabFaviconDataLoader: Sendable {
	private let fetchResponse: @Sendable (URLRequest) async throws -> (Data, URLResponse)

	init(
		fetchResponse: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
			try await URLSession.shared.data(for: request)
		}
	) {
		self.fetchResponse = fetchResponse
	}

	func data(for url: URL) async -> Data? {
		var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
		request.setValue("image/*", forHTTPHeaderField: "Accept")

		do {
			let (data, response) = try await fetchResponse(request)
			if let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
				return nil
			}
			return data.isEmpty ? nil : data
		}
		catch {
			return nil
		}
	}
}
