@testable import CookiesInterop
import Foundation
import XCTest

final class CookiesInteropCoverageTests: XCTestCase {
	func testErrorDescriptionsCoverAllCases() {
		XCTAssertEqual(
			CookiesInteropError.unsupportedVersion(found: 9, supported: 1).errorDescription,
			"Unsupported cookies document version: found 9, supported 1"
		)
		XCTAssertEqual(
			CookiesInteropError.malformedPayload.errorDescription,
			"Could not decode the stored cookies payload."
		)
		XCTAssertEqual(
			CookiesInteropError.storageDirectoryCreationFailed.errorDescription,
			"Unable to create the cookie storage directory."
		)
		XCTAssertEqual(
			CookiesInteropError.readFailed("read failed").errorDescription,
			"read failed"
		)
		XCTAssertEqual(
			CookiesInteropError.writeFailed("write failed").errorDescription,
			"write failed"
		)
	}

	func testCookieIdentityAndCanonicalCookieNormalizeDomainPathAndExpiryState() {
		let identity = CookieIdentity(name: "session", domain: "Example.COM", path: "")
		XCTAssertEqual(identity.domain, "example.com")
		XCTAssertEqual(identity.path, "/")

		let sessionCookie = makeCookie(
			name: "session",
			domain: "Example.COM",
			path: "",
			sameSite: .unspecified,
			expiresAt: nil,
			createdAt: Date(timeIntervalSince1970: 10),
			lastAccessedAt: Date(timeIntervalSince1970: 20),
			source: .unknown
		)
		XCTAssertEqual(sessionCookie.domain, "example.com")
		XCTAssertEqual(sessionCookie.path, "/")
		XCTAssertTrue(sessionCookie.isSessionOnly)
		XCTAssertEqual(sessionCookie.key, identity)
		XCTAssertFalse(sessionCookie.isExpired(at: Date(timeIntervalSince1970: 50)))

		let persistentCookie = makeCookie(
			name: "persistent",
			expiresAt: Date(timeIntervalSince1970: 200),
			createdAt: Date(timeIntervalSince1970: 10),
			lastAccessedAt: Date(timeIntervalSince1970: 20)
		)
		XCTAssertFalse(persistentCookie.isSessionOnly)
		XCTAssertFalse(persistentCookie.isExpired(at: Date(timeIntervalSince1970: 199)))
	}

	func testCookieCorpusLookupBatchReplaceAndNoOpRemovalPaths() {
		let base = Date(timeIntervalSince1970: 10)
		let stale = makeCookie(
			name: "session",
			value: "stale",
			createdAt: Date(timeIntervalSince1970: 10),
			lastAccessedAt: Date(timeIntervalSince1970: 10)
		)
		let current = makeCookie(
			name: "session",
			value: "current",
			createdAt: Date(timeIntervalSince1970: 20),
			lastAccessedAt: Date(timeIntervalSince1970: 20)
		)
		let tieBreaker = makeCookie(
			name: "session",
			value: "tie-breaker",
			createdAt: Date(timeIntervalSince1970: 30),
			lastAccessedAt: Date(timeIntervalSince1970: 20)
		)
		let other = makeCookie(
			name: "prefs",
			path: "/prefs",
			createdAt: Date(timeIntervalSince1970: 40),
			lastAccessedAt: Date(timeIntervalSince1970: 40)
		)
		let extra = makeCookie(
			name: "feature",
			path: "/feature",
			createdAt: Date(timeIntervalSince1970: 50),
			lastAccessedAt: Date(timeIntervalSince1970: 50)
		)

		var corpus = CookieCorpus(updatedAt: base, cookies: [])
		corpus.upsert(current, at: Date(timeIntervalSince1970: 21))
		corpus.upsert(stale, at: Date(timeIntervalSince1970: 22))
		corpus.upsert(tieBreaker, at: Date(timeIntervalSince1970: 31))

		XCTAssertEqual(corpus.cookie(for: current.key)?.value, "tie-breaker")
		XCTAssertNil(corpus.cookie(for: CookieIdentity(name: "missing", domain: "example.com", path: "/")))

		corpus.upsert([other, extra], at: Date(timeIntervalSince1970: 60))
		XCTAssertEqual(corpus.cookies.count, 3)

		let updatedAtBeforeNoOpRemoval = corpus.updatedAt
		XCTAssertEqual(corpus.removeExpired(asOf: Date(timeIntervalSince1970: 70)), 0)
		XCTAssertEqual(corpus.updatedAt, updatedAtBeforeNoOpRemoval)

		XCTAssertEqual(corpus.removeAll(where: { $0.name == "missing" }, at: Date(timeIntervalSince1970: 71)), 0)
		XCTAssertEqual(corpus.updatedAt, updatedAtBeforeNoOpRemoval)

		XCTAssertEqual(corpus.removeAll(where: { $0.name == "prefs" }, at: Date(timeIntervalSince1970: 72)), 1)
		XCTAssertEqual(Set(corpus.cookies.map(\.name)), ["session", "feature"])

		corpus.replaceCookies([other], at: Date(timeIntervalSince1970: 80))
		XCTAssertEqual(corpus.cookies, [other])
		XCTAssertEqual(corpus.updatedAt, Date(timeIntervalSince1970: 80))
	}

	func testDefaultStorageURLConvenienceOverloadsUseExpectedDefaults() {
		let applicationSupportDirectory = CookiesInteropPath.defaultApplicationSupportDirectory
		XCTAssertTrue(applicationSupportDirectory.path.contains("Application Support"))

		let defaultStorageURL = CookiesInteropPath.defaultStorageURL()
		XCTAssertTrue(defaultStorageURL.path.hasPrefix(applicationSupportDirectory.path))
		XCTAssertTrue(defaultStorageURL.path.hasSuffix("/Navigator/com.mium.navigator/SharedCookies/SharedCookies.json"))

		let customStorageURL = CookiesInteropPath.defaultStorageURL(
			bundleIdentifier: "com.example.browser",
			fileName: "cookies.bin"
		)
		XCTAssertTrue(customStorageURL.path.hasPrefix(applicationSupportDirectory.path))
		XCTAssertTrue(customStorageURL.path.hasSuffix("/Navigator/com.example.browser/SharedCookies/cookies.bin"))
	}

	func testApplicationSupportDirectoryHelperCoversPreferredAndFallbackPaths() {
		let preferred = URL(fileURLWithPath: "/tmp/preferred-app-support")
		let homeDirectory = URL(fileURLWithPath: "/tmp/home")

		XCTAssertEqual(
			CookiesInteropPath.applicationSupportDirectory(
				from: [preferred],
				homeDirectory: homeDirectory
			),
			preferred
		)
		XCTAssertEqual(
			CookiesInteropPath.applicationSupportDirectory(
				from: [],
				homeDirectory: homeDirectory
			).path,
			"/tmp/home/Library/Application Support"
		)
	}

	func testLegacyStorageURLHelpersResolveParentLevelCookiePath() {
		let applicationSupportDirectory = URL(fileURLWithPath: "/tmp/app-support", isDirectory: true)
		let currentStorageURL = CookiesInteropPath.defaultStorageURL(
			applicationSupportDirectory: applicationSupportDirectory,
			bundleIdentifier: "com.example.browser",
			fileName: "cookies.bin"
		)
		let legacyStorageURL = CookiesInteropPath.legacyStorageURL(
			applicationSupportDirectory: applicationSupportDirectory,
			bundleIdentifier: "com.example.browser",
			fileName: "cookies.bin"
		)

		XCTAssertEqual(
			legacyStorageURL.path,
			"/tmp/app-support/com.example.browser/SharedCookies/cookies.bin"
		)
		XCTAssertEqual(CookiesInteropPath.legacyStorageURL(for: currentStorageURL), legacyStorageURL)
		XCTAssertNil(
			CookiesInteropPath.legacyStorageURL(
				for: URL(fileURLWithPath: "/tmp/custom-location/cookies.bin", isDirectory: false)
			)
		)
	}

	func testCookieCorpusCodingRoundTripsAndFallsBackToEmptyCorpus() throws {
		let cookie = makeCookie(
			name: "session",
			createdAt: Date(timeIntervalSince1970: 10),
			lastAccessedAt: Date(timeIntervalSince1970: 20)
		)
		let corpus = CookieCorpus(
			updatedAt: Date(timeIntervalSince1970: 30),
			cookies: [cookie]
		)

		let encoded = try CookieCorpusCoding.encode(corpus)
		XCTAssertEqual(try CookieCorpusCoding.decode(encoded), corpus)

		let fallback = CookieCorpusCoding.decodeOrEmpty(Data("{bad-json".utf8))
		XCTAssertEqual(fallback.version, CookieCorpus.currentVersion)
		XCTAssertTrue(fallback.cookies.isEmpty)

		let sharedFallback = decodeSharedCookiesInteropCorpus(Data("{bad-json".utf8))
		XCTAssertEqual(sharedFallback.version, CookieCorpus.currentVersion)
		XCTAssertTrue(sharedFallback.cookies.isEmpty)
	}

	func testStoreSnapshotBatchOperationsAndPurgePaths() async throws {
		try await withIsolatedCookieStorage(fileName: "cookiesinterop-coverage-store.json") { storageURL in
			let store = CookiesInteropStore(storageURL: storageURL)
			let now = Date(timeIntervalSince1970: 100)
			let initialCookie = makeCookie(
				name: "session",
				value: "abc",
				createdAt: now,
				lastAccessedAt: now
			)
			let initialCorpus = CookieCorpus(
				updatedAt: now,
				cookies: [initialCookie]
			)

			try await store.save(initialCorpus)
			let snapshot = try await store.snapshot()
			XCTAssertEqual(snapshot, initialCorpus)

			let batchCookies = [
				makeCookie(
					name: "prefs",
					path: "/prefs",
					createdAt: Date(timeIntervalSince1970: 110),
					lastAccessedAt: Date(timeIntervalSince1970: 110)
				),
				makeCookie(
					name: "temp",
					expiresAt: Date(timeIntervalSince1970: 130),
					createdAt: Date(timeIntervalSince1970: 110),
					lastAccessedAt: Date(timeIntervalSince1970: 110)
				),
			]

			let afterBatch = try await store.upsert(batchCookies, asOf: Date(timeIntervalSince1970: 111))
			XCTAssertEqual(afterBatch.cookies.count, 3)

			let removedExpired = try await store.removeExpired(asOf: Date(timeIntervalSince1970: 120))
			XCTAssertEqual(removedExpired, 0)

			let replacementCookie = makeCookie(
				name: "replacement",
				value: "ok",
				createdAt: Date(timeIntervalSince1970: 140),
				lastAccessedAt: Date(timeIntervalSince1970: 140)
			)
			let afterReplace = try await store.replaceCookies(
				[replacementCookie],
				asOf: Date(timeIntervalSince1970: 141)
			)
			XCTAssertEqual(afterReplace.cookies, [replacementCookie])

			let removedNothing = try await store.purge(
				where: { $0.name == "missing" },
				asOf: Date(timeIntervalSince1970: 142)
			)
			XCTAssertEqual(removedNothing, 0)
			let removedReplacement = try await store.purge(
				where: { $0.name == "replacement" },
				asOf: Date(timeIntervalSince1970: 143)
			)
			XCTAssertEqual(removedReplacement, 1)

			let finalCorpus = try await store.load()
			XCTAssertTrue(finalCorpus.cookies.isEmpty)
		}
	}
}

private func makeCookie(
	name: String,
	value: String = "value",
	domain: String = "example.com",
	path: String = "/",
	isSecure: Bool = false,
	isHTTPOnly: Bool = false,
	isHostOnly: Bool = true,
	sameSite: SameSitePolicy = .lax,
	expiresAt: Date? = nil,
	createdAt: Date = Date(timeIntervalSince1970: 1),
	lastAccessedAt: Date = Date(timeIntervalSince1970: 2),
	source: CookieEngine = .chromium,
	isPartitioned: Bool = false
) -> CanonicalCookie {
	CanonicalCookie(
		name: name,
		value: value,
		domain: domain,
		path: path,
		isSecure: isSecure,
		isHTTPOnly: isHTTPOnly,
		isHostOnly: isHostOnly,
		sameSite: sameSite,
		expiresAt: expiresAt,
		createdAt: createdAt,
		lastAccessedAt: lastAccessedAt,
		source: source,
		isPartitioned: isPartitioned
	)
}

private func withIsolatedCookieStorage<T>(
	fileName: String,
	_ body: (_ storageURL: URL) async throws -> T
) async throws -> T {
	let supportDirectory = FileManager.default.temporaryDirectory
		.appendingPathComponent("cookiesinterop-\(UUID().uuidString)")
	let storageURL = CookiesInteropPath.defaultStorageURL(
		applicationSupportDirectory: supportDirectory,
		bundleIdentifier: "com.example.cookiesinterop",
		fileName: fileName
	)
	let directory = storageURL.deletingLastPathComponent()

	try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
	defer {
		try? FileManager.default.removeItem(at: supportDirectory)
	}

	return try await body(storageURL)
}
