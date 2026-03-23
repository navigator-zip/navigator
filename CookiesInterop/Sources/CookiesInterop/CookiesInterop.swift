import Foundation
import Vendors

public enum CookiesInteropError: Error, Equatable, LocalizedError {
	case unsupportedVersion(found: Int, supported: Int)
	case malformedPayload
	case storageDirectoryCreationFailed
	case readFailed(String)
	case writeFailed(String)

	public var errorDescription: String? {
		switch self {
		case let .unsupportedVersion(found, supported):
			"Unsupported cookies document version: found \(found), supported \(supported)"
		case .malformedPayload:
			"Could not decode the stored cookies payload."
		case .storageDirectoryCreationFailed:
			"Unable to create the cookie storage directory."
		case let .readFailed(message), let .writeFailed(message):
			message
		}
	}
}

public enum CookieEngine: String, Sendable, Codable, Equatable {
	case chromium
	case webKit
	case unknown
}

public enum SameSitePolicy: String, Sendable, Codable, Equatable {
	case none
	case lax
	case strict
	case unspecified
}

public struct CookieIdentity: Sendable, Hashable, Codable, Equatable {
	public let name: String
	public let domain: String
	public let path: String

	public init(name: String, domain: String, path: String) {
		self.name = name
		self.domain = domain.lowercased()
		self.path = path.isEmpty ? "/" : path
	}
}

public struct CanonicalCookie: Sendable, Codable, Hashable {
	public let name: String
	public let value: String
	public let domain: String
	public let path: String
	public let isSecure: Bool
	public let isHTTPOnly: Bool
	public let isHostOnly: Bool
	public let sameSite: SameSitePolicy
	public let expiresAt: Date?
	public let createdAt: Date
	public let source: CookieEngine
	public let isPartitioned: Bool
	public var lastAccessedAt: Date

	public init(
		name: String,
		value: String,
		domain: String,
		path: String,
		isSecure: Bool,
		isHTTPOnly: Bool,
		isHostOnly: Bool,
		sameSite: SameSitePolicy,
		expiresAt: Date?,
		createdAt: Date,
		lastAccessedAt: Date,
		source: CookieEngine,
		isPartitioned: Bool = false
	) {
		self.name = name
		self.value = value
		self.domain = domain.lowercased()
		self.path = path.isEmpty ? "/" : path
		self.isSecure = isSecure
		self.isHTTPOnly = isHTTPOnly
		self.isHostOnly = isHostOnly
		self.sameSite = sameSite
		self.expiresAt = expiresAt
		self.createdAt = createdAt
		self.lastAccessedAt = lastAccessedAt
		self.source = source
		self.isPartitioned = isPartitioned
	}

	public var isSessionOnly: Bool {
		expiresAt == nil
	}

	public var key: CookieIdentity {
		CookieIdentity(name: name, domain: domain, path: path)
	}

	public func isExpired(at date: Date) -> Bool {
		if let expiresAt {
			return expiresAt <= date
		}
		return false
	}

	public func isApplicable(toHost host: String, isSecureConnection: Bool) -> Bool {
		guard isSecureConnection || !isSecure else { return false }

		let normalizedHost = host.lowercased()
		let cookieDomain = domain.lowercased()
		if isHostOnly {
			return normalizedHost == cookieDomain
		}

		if normalizedHost == cookieDomain {
			return true
		}

		return normalizedHost.hasSuffix("." + cookieDomain)
	}
}

public struct CookieCorpus: Sendable, Codable, Equatable {
	public static let currentVersion = 1

	public let version: Int
	public private(set) var updatedAt: Date
	public private(set) var cookies: [CanonicalCookie]

	public init(
		version: Int = currentVersion,
		updatedAt: Date = Date(),
		cookies: [CanonicalCookie] = []
	) {
		self.version = version
		self.updatedAt = updatedAt
		self.cookies = cookies
	}

	private static func shouldReplace(_ existing: CanonicalCookie, with replacement: CanonicalCookie) -> Bool {
		if replacement.lastAccessedAt == existing.lastAccessedAt {
			return replacement.createdAt >= existing.createdAt
		}
		return replacement.lastAccessedAt >= existing.lastAccessedAt
	}

	public func cookie(for identity: CookieIdentity) -> CanonicalCookie? {
		cookies.first { $0.key == identity }
	}

	public mutating func upsert(_ cookie: CanonicalCookie, at date: Date) {
		if let existingIndex = cookies.firstIndex(where: { $0.key == cookie.key }) {
			let existing = cookies[existingIndex]
			if Self.shouldReplace(existing, with: cookie) {
				cookies[existingIndex] = cookie
			}
		}
		else {
			cookies.append(cookie)
		}
		updatedAt = date
	}

	public mutating func upsert(_ cookies: [CanonicalCookie], at date: Date) {
		for cookie in cookies {
			upsert(cookie, at: date)
		}
		updatedAt = date
	}

	public mutating func replaceCookies(_ cookies: [CanonicalCookie], at date: Date) {
		self.cookies = cookies
		self.updatedAt = date
	}

	public mutating func removeExpired(asOf date: Date) -> Int {
		let before = cookies.count
		cookies.removeAll { $0.isExpired(at: date) }
		if cookies.count != before {
			updatedAt = date
		}
		return before - cookies.count
	}

	public mutating func removeAll(where shouldRemove: (CanonicalCookie) -> Bool, at date: Date) -> Int {
		let before = cookies.count
		cookies.removeAll(where: shouldRemove)
		if cookies.count != before {
			updatedAt = date
		}
		return before - cookies.count
	}

	public func activeCookies(
		forHost host: String,
		isSecureConnection: Bool,
		asOf date: Date
	) -> [CanonicalCookie] {
		cookies.filter { !$0.isExpired(at: date) && $0.isApplicable(toHost: host, isSecureConnection: isSecureConnection) }
	}
}

public enum CookiesInteropPath {
	public static let defaultFileName = "SharedCookies.json"
	static let navigatorDirectoryName = "Navigator"
	static let sharedCookiesDirectoryName = "SharedCookies"

	public static func defaultStorageURL(
		applicationSupportDirectory: URL,
		bundleIdentifier: String,
		fileName: String = defaultFileName
	) -> URL {
		applicationSupportDirectory
			.appendingPathComponent(navigatorDirectoryName, isDirectory: true)
			.appendingPathComponent(bundleIdentifier, isDirectory: true)
			.appendingPathComponent(sharedCookiesDirectoryName, isDirectory: true)
			.appendingPathComponent(fileName)
	}

	static func legacyStorageURL(
		applicationSupportDirectory: URL,
		bundleIdentifier: String,
		fileName: String = defaultFileName
	) -> URL {
		applicationSupportDirectory
			.appendingPathComponent(bundleIdentifier, isDirectory: true)
			.appendingPathComponent(sharedCookiesDirectoryName, isDirectory: true)
			.appendingPathComponent(fileName)
	}

	static func applicationSupportDirectory(
		from directories: [URL],
		homeDirectory: URL
	) -> URL {
		directories.first ?? homeDirectory.appendingPathComponent("Library")
			.appendingPathComponent("Application Support")
	}

	public static var defaultApplicationSupportDirectory: URL {
		applicationSupportDirectory(
			from: FileManager.default.urls(
				for: .applicationSupportDirectory,
				in: .userDomainMask
			),
			homeDirectory: FileManager.default.homeDirectoryForCurrentUser
		)
	}

	public static func defaultStorageURL(
		bundleIdentifier: String = "com.mium.navigator",
		fileName: String = defaultFileName
	) -> URL {
		defaultStorageURL(
			applicationSupportDirectory: defaultApplicationSupportDirectory,
			bundleIdentifier: bundleIdentifier,
			fileName: fileName
		)
	}

	static func legacyStorageURL(for storageURL: URL) -> URL? {
		let components = storageURL.standardizedFileURL.pathComponents
		guard
			let navigatorIndex = components.lastIndex(of: navigatorDirectoryName),
			navigatorIndex > 0,
			navigatorIndex + 3 < components.count,
			components[navigatorIndex + 2] == sharedCookiesDirectoryName
		else {
			return nil
		}

		var legacyComponents = components
		legacyComponents.remove(at: navigatorIndex)
		return URL(fileURLWithPath: NSString.path(withComponents: legacyComponents), isDirectory: false)
	}
}

enum CookieCorpusCoding {
	static func decode(_ data: Data) throws -> CookieCorpus {
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .secondsSince1970
		return try decoder.decode(CookieCorpus.self, from: data)
	}

	static func decodeOrEmpty(_ data: Data) -> CookieCorpus {
		(try? decode(data)) ?? CookieCorpus()
	}

	static func encode(_ corpus: CookieCorpus) throws -> Data {
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .secondsSince1970
		return try encoder.encode(corpus)
	}
}

func decodeSharedCookiesInteropCorpus(_ data: Data) -> CookieCorpus {
	CookieCorpusCoding.decodeOrEmpty(data)
}

func encodeSharedCookiesInteropCorpus(_ corpus: CookieCorpus) throws -> Data {
	try CookieCorpusCoding.encode(corpus)
}

public actor CookiesInteropStore {
	@Shared private var sharedCorpus: CookieCorpus

	public init(storageURL: URL = CookiesInteropPath.defaultStorageURL()) {
		Self.migrateLegacyStorageIfNeeded(to: storageURL)
		_sharedCorpus = Shared(
			wrappedValue: CookieCorpus(),
			.fileStorage(
				storageURL,
				decode: decodeSharedCookiesInteropCorpus,
				encode: encodeSharedCookiesInteropCorpus
			)
		)
	}

	public func snapshot() throws -> CookieCorpus {
		let corpus = $sharedCorpus.withLock { $0 }
		try validateVersion(corpus)
		return corpus
	}

	public func load() throws -> CookieCorpus {
		try snapshot()
	}

	public func save(_ corpus: CookieCorpus) throws {
		try validateVersion(corpus)
		$sharedCorpus.withLock { $0 = corpus }
	}

	public func upsert(_ cookie: CanonicalCookie, asOf date: Date) throws -> CookieCorpus {
		var next = try snapshot()
		next.upsert(cookie, at: date)
		try save(next)
		return next
	}

	public func upsert(_ cookies: [CanonicalCookie], asOf date: Date) throws -> CookieCorpus {
		var next = try snapshot()
		next.upsert(cookies, at: date)
		try save(next)
		return next
	}

	public func replaceCookies(_ cookies: [CanonicalCookie], asOf date: Date) throws -> CookieCorpus {
		var next = try snapshot()
		next.replaceCookies(cookies, at: date)
		try save(next)
		return next
	}

	public func removeExpired(asOf date: Date) throws -> Int {
		var next = try snapshot()
		let removed = next.removeExpired(asOf: date)
		if removed > 0 {
			try save(next)
		}
		return removed
	}

	public func purge(where shouldRemove: @Sendable (CanonicalCookie) -> Bool, asOf date: Date) throws -> Int {
		var next = try snapshot()
		let removed = next.removeAll(where: shouldRemove, at: date)
		if removed > 0 {
			try save(next)
		}
		return removed
	}

	private func validateVersion(_ corpus: CookieCorpus) throws {
		guard corpus.version == CookieCorpus.currentVersion else {
			throw CookiesInteropError.unsupportedVersion(found: corpus.version, supported: CookieCorpus.currentVersion)
		}
	}

	private static func migrateLegacyStorageIfNeeded(
		to storageURL: URL,
		fileManager: FileManager = .default
	) {
		guard
			fileManager.fileExists(atPath: storageURL.path) == false,
			let legacyStorageURL = CookiesInteropPath.legacyStorageURL(for: storageURL),
			fileManager.fileExists(atPath: legacyStorageURL.path)
		else {
			return
		}

		let destinationDirectory = storageURL.deletingLastPathComponent()
		try? fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
		try? fileManager.moveItem(at: legacyStorageURL, to: storageURL)

		let legacySharedCookiesDirectory = legacyStorageURL.deletingLastPathComponent()
		let legacyBundleDirectory = legacySharedCookiesDirectory.deletingLastPathComponent()
		try? fileManager.removeItem(at: legacySharedCookiesDirectory)
		try? fileManager.removeItem(at: legacyBundleDirectory)
	}
}
