import Foundation
@testable import Vendors
import XCTest

#if canImport(Wave)
	import Wave
#endif

private enum TaggedMarker {}

final class VendorsTests: XCTestCase {
	func testVendorsReexportsDependenciesAndProvidesSmokeSymbol() {
		VendorsSmoke.smoke()

		let value: Tagged<TaggedMarker, String> = "navigator"
		XCTAssertEqual(value.rawValue, "navigator")
	}

	func testVendorsExposesWaveModule() {
		#if canImport(Wave)
			XCTAssertTrue(true)
		#else
			XCTFail("Wave should be available through Vendors")
		#endif
	}

	func testNavigatorApplicationSupportFileUsesNavigatorSubdirectory() {
		let applicationSupportDirectory = URL(fileURLWithPath: "/tmp/app-support", isDirectory: true)
		let fileURL = URL.navigatorApplicationSupportFile(
			named: "NavigatorWindowSize",
			applicationSupportDirectory: applicationSupportDirectory
		)

		XCTAssertEqual(fileURL.path, "/tmp/app-support/Navigator/NavigatorWindowSize")
		XCTAssertEqual(
			URL.navigatorApplicationSupportDirectory(in: applicationSupportDirectory).path,
			"/tmp/app-support/Navigator"
		)
		XCTAssertEqual(
			URL.legacyApplicationSupportFile(
				named: "NavigatorWindowSize",
				applicationSupportDirectory: applicationSupportDirectory
			).path,
			"/tmp/app-support/NavigatorWindowSize"
		)
	}

	func testNavigatorApplicationSupportFileFallsBackToHomeLibraryApplicationSupport() {
		let homeDirectory = URL(fileURLWithPath: "/tmp/test-home", isDirectory: true)

		XCTAssertEqual(
			URL.baseApplicationSupportDirectory(
				from: [],
				homeDirectory: homeDirectory
			).path,
			"/tmp/test-home/Library/Application Support"
		)
	}

	func testNavigatorApplicationSupportFileMigratesLegacyFileIntoNavigatorFolder() throws {
		let applicationSupportDirectory = FileManager.default.temporaryDirectory
			.appendingPathComponent("vendors-app-support-\(UUID().uuidString)", isDirectory: true)
		let legacyURL = URL.legacyApplicationSupportFile(
			named: "NavigatorStoredBrowserTabs",
			applicationSupportDirectory: applicationSupportDirectory
		)
		try FileManager.default.createDirectory(at: applicationSupportDirectory, withIntermediateDirectories: true)
		defer {
			try? FileManager.default.removeItem(at: applicationSupportDirectory)
		}

		let payload = Data("navigator".utf8)
		try payload.write(to: legacyURL, options: .atomic)

		let migratedURL = URL.navigatorApplicationSupportFile(
			named: "NavigatorStoredBrowserTabs",
			applicationSupportDirectory: applicationSupportDirectory,
			fileManager: .default
		)

		XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
		XCTAssertTrue(FileManager.default.fileExists(atPath: migratedURL.path))
		XCTAssertEqual(try Data(contentsOf: migratedURL), payload)
	}
}
