@testable import BrowserRuntime
import Foundation
import ModelKit
import XCTest

@MainActor
final class BrowserPermissionDecisionStoreTests: XCTestCase {
	func testStorePersistsAndReloadsSortedSnapshot() {
		let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		let fileURL = temporaryDirectory.appendingPathComponent("BrowserPermissionDecisions.json")
		let store = BrowserPermissionDecisionStore(fileURL: fileURL, fileManager: .default)

		store.upsert(
			decision: .deny,
			for: BrowserStoredPermissionDecisionKey(
				requestingOrigin: "https://b.example",
				topLevelOrigin: "https://top.example",
				kind: .microphone
			),
			at: Date(timeIntervalSince1970: 20)
		)
		store.upsert(
			decision: .allow,
			for: BrowserStoredPermissionDecisionKey(
				requestingOrigin: "https://a.example",
				topLevelOrigin: "https://top.example",
				kind: .camera
			),
			at: Date(timeIntervalSince1970: 10)
		)

		let reloadedStore = BrowserPermissionDecisionStore(fileURL: fileURL, fileManager: .default)

		XCTAssertEqual(reloadedStore.snapshot().decisions.map(\.id), [
			"https://a.example|https://top.example|camera",
			"https://b.example|https://top.example|microphone",
		])
		XCTAssertEqual(
			reloadedStore.decision(
				for: BrowserStoredPermissionDecisionKey(
					requestingOrigin: "https://b.example",
					topLevelOrigin: "https://top.example",
					kind: .microphone
				)
			),
			.deny
		)
	}

	func testRemovingDecisionUpdatesSnapshot() {
		let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		let fileURL = temporaryDirectory.appendingPathComponent("BrowserPermissionDecisions.json")
		let store = BrowserPermissionDecisionStore(fileURL: fileURL, fileManager: .default)
		let key = BrowserStoredPermissionDecisionKey(
			requestingOrigin: "https://request.example",
			topLevelOrigin: "https://top.example",
			kind: .geolocation
		)

		store.upsert(decision: .allow, for: key, at: Date(timeIntervalSince1970: 50))
		store.removeDecision(for: key)

		XCTAssertEqual(store.snapshot().decisions, [])
	}

	func testInvalidStoredJSONIsIgnored() throws {
		let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		let fileURL = temporaryDirectory.appendingPathComponent("BrowserPermissionDecisions.json")
		try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
		try Data("not-json".utf8).write(to: fileURL)

		let store = BrowserPermissionDecisionStore(fileURL: fileURL, fileManager: .default)

		XCTAssertEqual(store.snapshot().decisions, [])
	}

	func testConvenienceInitializerUsesInjectedDefaultFileURLProvider() {
		let store = BrowserPermissionDecisionStore()

		XCTAssertNotNil(store.snapshot())
	}

	func testDefaultFileURLBuilderUsesNavigatorApplicationSupportPath() {
		let applicationSupportDirectory = URL(fileURLWithPath: "/tmp/Application Support", isDirectory: true)
		let defaultFileURL = BrowserPermissionDecisionStore.makeDefaultFileURLForTesting(
			applicationSupportDirectory: applicationSupportDirectory,
			homeDirectory: URL(fileURLWithPath: "/tmp/home", isDirectory: true)
		)

		XCTAssertEqual(defaultFileURL.lastPathComponent, "BrowserPermissionDecisions.json")
		XCTAssertEqual(defaultFileURL.deletingLastPathComponent().lastPathComponent, "Navigator")
	}

	func testDefaultFileURLBuilderFallsBackToHomeLibraryWhenApplicationSupportIsUnavailable() {
		let homeDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		let defaultFileURL = BrowserPermissionDecisionStore.makeDefaultFileURLForTesting(
			applicationSupportDirectory: nil,
			homeDirectory: homeDirectory
		)

		XCTAssertEqual(
			defaultFileURL.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent,
			"Application Support"
		)
		XCTAssertTrue(defaultFileURL.path.contains("/Library/Application Support/Navigator/"))
	}

	func testRemovingMissingDecisionDoesNotWriteSnapshot() {
		let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		let fileURL = temporaryDirectory.appendingPathComponent("BrowserPermissionDecisions.json")
		let store = BrowserPermissionDecisionStore(fileURL: fileURL, fileManager: .default)
		let missingKey = BrowserStoredPermissionDecisionKey(
			requestingOrigin: "https://missing.example",
			topLevelOrigin: "https://top.example",
			kind: .microphone
		)

		store.removeDecision(for: missingKey)

		XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
	}
}
