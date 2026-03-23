import AppIntents
@testable import CookiesInterop
import Foundation
import Vendors
import XCTest

final class CookieCorpusTests: XCTestCase {
	func testCookieMatchingSupportsHostOnlyAndDomainCookies() {
		let secureHostCookie = CanonicalCookie(
			name: "sid",
			value: "1",
			domain: "Example.COM",
			path: "/",
			isSecure: true,
			isHTTPOnly: true,
			isHostOnly: true,
			sameSite: .strict,
			expiresAt: nil,
			createdAt: Date(timeIntervalSince1970: 1),
			lastAccessedAt: Date(timeIntervalSince1970: 2),
			source: .chromium
		)

		XCTAssertTrue(secureHostCookie.isApplicable(toHost: "example.com", isSecureConnection: true))
		XCTAssertFalse(secureHostCookie.isApplicable(toHost: "sub.example.com", isSecureConnection: true))
		XCTAssertFalse(secureHostCookie.isApplicable(toHost: "example.com", isSecureConnection: false))

		let domainCookie = CanonicalCookie(
			name: "sid",
			value: "1",
			domain: "example.COM",
			path: "/app",
			isSecure: false,
			isHTTPOnly: false,
			isHostOnly: false,
			sameSite: .lax,
			expiresAt: nil,
			createdAt: Date(timeIntervalSince1970: 1),
			lastAccessedAt: Date(timeIntervalSince1970: 2),
			source: .webKit
		)

		XCTAssertTrue(domainCookie.isApplicable(toHost: "example.com", isSecureConnection: true))
		XCTAssertTrue(domainCookie.isApplicable(toHost: "sub.example.com", isSecureConnection: true))
		XCTAssertFalse(domainCookie.isApplicable(toHost: "otherexample.com", isSecureConnection: true))
	}

	func testUpsertUsesMostRecentLastAccessAndDropsExpiredCookies() {
		let base = Date(timeIntervalSince1970: 10)
		let stale = CanonicalCookie(
			name: "a",
			value: "old",
			domain: "example.com",
			path: "/",
			isSecure: false,
			isHTTPOnly: false,
			isHostOnly: true,
			sameSite: .none,
			expiresAt: nil,
			createdAt: base,
			lastAccessedAt: base,
			source: .chromium
		)
		let fresh = CanonicalCookie(
			name: "a",
			value: "new",
			domain: "example.com",
			path: "/",
			isSecure: false,
			isHTTPOnly: false,
			isHostOnly: true,
			sameSite: .none,
			expiresAt: nil,
			createdAt: base,
			lastAccessedAt: Date(timeIntervalSince1970: 20),
			source: .chromium
		)

		var corpus = CookieCorpus()
		corpus.upsert(stale, at: base)
		corpus.upsert(fresh, at: Date(timeIntervalSince1970: 25))

		XCTAssertEqual(corpus.cookies.count, 1)
		XCTAssertEqual(corpus.cookies[0].value, "new")

		let expired = CanonicalCookie(
			name: "b",
			value: "soon",
			domain: "example.com",
			path: "/",
			isSecure: false,
			isHTTPOnly: false,
			isHostOnly: true,
			sameSite: .none,
			expiresAt: Date(timeIntervalSince1970: 15),
			createdAt: base,
			lastAccessedAt: Date(timeIntervalSince1970: 12),
			source: .chromium
		)
		corpus.upsert(expired, at: Date(timeIntervalSince1970: 30))
		XCTAssertEqual(corpus.cookies.count, 2)

		let removed = corpus.removeExpired(asOf: Date(timeIntervalSince1970: 20))
		XCTAssertEqual(removed, 1)
		XCTAssertEqual(corpus.cookies.count, 1)
		XCTAssertEqual(corpus.cookies.first?.name, "a")
	}

	func testActiveCookiesFiltersByHostAndSecureState() {
		let now = Date(timeIntervalSince1970: 100)
		var corpus = CookieCorpus()
		corpus.upsert(
			CanonicalCookie(
				name: "session",
				value: "x",
				domain: "example.com",
				path: "/",
				isSecure: true,
				isHTTPOnly: false,
				isHostOnly: true,
				sameSite: .strict,
				expiresAt: nil,
				createdAt: now,
				lastAccessedAt: now,
				source: .chromium
			),
			at: now
		)
		corpus.upsert(
			CanonicalCookie(
				name: "api",
				value: "y",
				domain: "example.com",
				path: "/",
				isSecure: false,
				isHTTPOnly: false,
				isHostOnly: false,
				sameSite: .lax,
				expiresAt: nil,
				createdAt: now,
				lastAccessedAt: now,
				source: .webKit
			),
			at: now
		)

		let secureActive = corpus.activeCookies(forHost: "sub.example.com", isSecureConnection: true, asOf: now)
		let insecureActive = corpus.activeCookies(forHost: "sub.example.com", isSecureConnection: false, asOf: now)

		XCTAssertEqual(secureActive.map(\.name), ["api"])
		XCTAssertEqual(insecureActive.map(\.name), ["api"])
	}
}

final class CookiesInteropStorageTests: XCTestCase {
	func testDefaultStorageURLUsesExpectedDirectoryStructure() {
		let appSupport = URL(fileURLWithPath: "/tmp/test-app-support")
		let storageURL = CookiesInteropPath.defaultStorageURL(
			applicationSupportDirectory: appSupport,
			bundleIdentifier: "com.example.testapp",
			fileName: "cookies.json"
		)

		XCTAssertEqual(
			storageURL.path,
			"/tmp/test-app-support/Navigator/com.example.testapp/SharedCookies/cookies.json"
		)
	}

	func testStoreMigratesLegacyDefaultStorageIntoNavigatorFolder() async throws {
		let supportDirectory = FileManager.default.temporaryDirectory
			.appendingPathComponent("cookiesinterop-migration-\(UUID().uuidString)", isDirectory: true)
		let bundleIdentifier = "com.example.cookiesinterop"
		let legacyStorageURL = CookiesInteropPath.legacyStorageURL(
			applicationSupportDirectory: supportDirectory,
			bundleIdentifier: bundleIdentifier
		)
		let migratedStorageURL = CookiesInteropPath.defaultStorageURL(
			applicationSupportDirectory: supportDirectory,
			bundleIdentifier: bundleIdentifier
		)
		let legacyDirectory = legacyStorageURL.deletingLastPathComponent()
		try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
		defer {
			try? FileManager.default.removeItem(at: supportDirectory)
		}

		var corpus = CookieCorpus()
		let now = Date(timeIntervalSince1970: 100)
		corpus.upsert(
			CanonicalCookie(
				name: "session",
				value: "abc",
				domain: "example.com",
				path: "/",
				isSecure: false,
				isHTTPOnly: false,
				isHostOnly: true,
				sameSite: .lax,
				expiresAt: nil,
				createdAt: now,
				lastAccessedAt: now,
				source: .chromium
			),
			at: now
		)
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .secondsSince1970
		try encoder.encode(corpus).write(to: legacyStorageURL, options: .atomic)

		let loaded = try await withDependencies {
			$0.defaultFileStorage = .fileSystem
		} operation: {
			let store = CookiesInteropStore(storageURL: migratedStorageURL)
			return try await store.load()
		}

		XCTAssertEqual(loaded, corpus)
		XCTAssertFalse(FileManager.default.fileExists(atPath: legacyStorageURL.path))
		XCTAssertTrue(FileManager.default.fileExists(atPath: migratedStorageURL.path))
	}

	func testLoadMissingFileYieldsEmptyCorpus() async throws {
		try await withIsolatedCookieStorage(fileName: "cookiesinterop-missing.json") { storageURL in
			let store = CookiesInteropStore(storageURL: storageURL)
			let corpus = try await store.load()
			XCTAssertEqual(corpus.version, CookieCorpus.currentVersion)
			XCTAssertTrue(corpus.cookies.isEmpty)
		}
	}

	func testSharedCorpusIsBackedByTheSameFileStoreAcrossInstances() async throws {
		try await withIsolatedCookieStorage(fileName: "cookiesinterop-shared.json") { storageURL in
			let writer = CookiesInteropStore(storageURL: storageURL)
			let reader = CookiesInteropStore(storageURL: storageURL)
			let now = Date(timeIntervalSince1970: 100)

			_ = try await writer.upsert(
				CanonicalCookie(
					name: "session",
					value: "abc",
					domain: "example.com",
					path: "/",
					isSecure: false,
					isHTTPOnly: false,
					isHostOnly: true,
					sameSite: .lax,
					expiresAt: nil,
					createdAt: now,
					lastAccessedAt: now,
					source: .chromium
				),
				asOf: now
			)

			let loaded = try await reader.load()
			XCTAssertEqual(loaded.cookies.count, 1)
			XCTAssertEqual(loaded.cookies.first?.name, "session")
		}
	}

	func testSaveThenLoadRoundTrips() async throws {
		try await withIsolatedCookieStorage(fileName: "cookiesinterop-roundtrip.json") { storageURL in
			let store = CookiesInteropStore(storageURL: storageURL)
			var initial = CookieCorpus()
			initial.upsert(
				CanonicalCookie(
					name: "token",
					value: "abc",
					domain: "example.com",
					path: "/",
					isSecure: true,
					isHTTPOnly: true,
					isHostOnly: true,
					sameSite: .strict,
					expiresAt: nil,
					createdAt: Date(timeIntervalSince1970: 10),
					lastAccessedAt: Date(timeIntervalSince1970: 10),
					source: .chromium
				),
				at: Date(timeIntervalSince1970: 10)
			)

			try await store.save(initial)
			let loaded = try await store.load()
			XCTAssertEqual(initial, loaded)
		}
	}

	func testStoreUpsertPersistsAndCanPurgeExpired() async throws {
		try await withIsolatedCookieStorage(fileName: "cookiesinterop-upsert.json") { storageURL in
			let store = CookiesInteropStore(storageURL: storageURL)
			let now = Date(timeIntervalSince1970: 100)
			_ = try await store.upsert(
				CanonicalCookie(
					name: "temp",
					value: "1",
					domain: "example.com",
					path: "/",
					isSecure: false,
					isHTTPOnly: false,
					isHostOnly: true,
					sameSite: .lax,
					expiresAt: Date(timeIntervalSince1970: 90),
					createdAt: now,
					lastAccessedAt: now,
					source: .chromium
				),
				asOf: now
			)
			let removed = try await store.removeExpired(asOf: Date(timeIntervalSince1970: 120))
			XCTAssertEqual(removed, 1)
			let remaining = try await store.load()
			XCTAssertTrue(remaining.cookies.isEmpty)
		}
	}

	func testMalformedPayloadFallsBackToEmptyCorpus() async throws {
		try await withIsolatedCookieStorage(fileName: "cookiesinterop-malformed.json") { storageURL in
			let malformed = "{bad-json".data(using: .utf8)!
			try malformed.write(to: storageURL, options: .atomic)

			let store = CookiesInteropStore(storageURL: storageURL)
			let loaded = try await store.load()

			XCTAssertEqual(loaded.version, CookieCorpus.currentVersion)
			XCTAssertTrue(loaded.cookies.isEmpty)
		}
	}

	func testSaveUnsupportedVersionThrows() async throws {
		try await withIsolatedCookieStorage(fileName: "cookiesinterop-version.json") { storageURL in
			let store = CookiesInteropStore(storageURL: storageURL)
			let unsupportedCorpus = CookieCorpus(
				version: 99,
				updatedAt: Date(timeIntervalSince1970: 1),
				cookies: []
			)
			await XCTAssertThrowsErrorAsync(try await store.save(unsupportedCorpus)) { error in
				do {
					let casted = try XCTUnwrap(error as? CookiesInteropError)
					switch casted {
					case let .unsupportedVersion(found, supported):
						XCTAssertEqual(found, 99)
						XCTAssertEqual(supported, CookieCorpus.currentVersion)
					default:
						XCTFail("Expected unsupportedVersion, got \(casted)")
					}
				}
				catch {
					XCTFail("Expected CookiesInteropError")
				}
			}
		}
	}
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

private func XCTAssertThrowsErrorAsync(
	_ body: @autoclosure () async throws -> some Any,
	_ validate: (Error) -> Void
) async {
	do {
		_ = try await body()
		XCTFail("Expected async throw")
	}
	catch {
		validate(error)
	}
}
