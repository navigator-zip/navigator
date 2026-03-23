import Foundation
import ModelKit

@MainActor
protocol BrowserPermissionDecisionStoring: AnyObject {
	func decision(for key: BrowserStoredPermissionDecisionKey) -> BrowserPermissionPromptDecision?
	func upsert(
		decision: BrowserPermissionPromptDecision,
		for key: BrowserStoredPermissionDecisionKey,
		at timestamp: Date
	)
	func removeDecision(for key: BrowserStoredPermissionDecisionKey)
	func snapshot() -> BrowserStoredPermissionDecisionStore
}

@MainActor
final class BrowserPermissionDecisionStore: BrowserPermissionDecisionStoring {
	private let fileURL: URL
	private let fileManager: FileManager
	private var decisionsByKey = [BrowserStoredPermissionDecisionKey: BrowserStoredPermissionDecision]()

	convenience init() {
		self.init(fileURL: Self.makeDefaultFileURL(), fileManager: .default)
	}

	init(
		fileURL: URL,
		fileManager: FileManager
	) {
		self.fileURL = fileURL
		self.fileManager = fileManager
		load()
	}

	func decision(for key: BrowserStoredPermissionDecisionKey) -> BrowserPermissionPromptDecision? {
		decisionsByKey[key]?.decision
	}

	func upsert(
		decision: BrowserPermissionPromptDecision,
		for key: BrowserStoredPermissionDecisionKey,
		at timestamp: Date
	) {
		decisionsByKey[key] = BrowserStoredPermissionDecision(
			key: key,
			decision: decision,
			updatedAt: timestamp
		)
		save()
	}

	func removeDecision(for key: BrowserStoredPermissionDecisionKey) {
		guard decisionsByKey.removeValue(forKey: key) != nil else { return }
		save()
	}

	func snapshot() -> BrowserStoredPermissionDecisionStore {
		BrowserStoredPermissionDecisionStore(
			decisions: decisionsByKey.values.sorted { lhs, rhs in
				lhs.id < rhs.id
			}
		)
	}

	private func load() {
		guard let data = try? Data(contentsOf: fileURL) else { return }
		guard let store = try? JSONDecoder().decode(BrowserStoredPermissionDecisionStore.self, from: data) else { return }
		decisionsByKey = Dictionary(
			uniqueKeysWithValues: store.decisions.map { ($0.key, $0) }
		)
	}

	private func save() {
		let directoryURL = fileURL.deletingLastPathComponent()
		try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
		let data = try! JSONEncoder().encode(snapshot())
		try? data.write(to: fileURL, options: .atomic)
	}

	private static func makeDefaultFileURL() -> URL {
		makeDefaultFileURL(
			applicationSupportDirectory: FileManager.default.urls(
				for: .applicationSupportDirectory,
				in: .userDomainMask
			).first,
			homeDirectory: FileManager.default.homeDirectoryForCurrentUser
		)
	}

	private static func makeDefaultFileURL(
		applicationSupportDirectory: URL?,
		homeDirectory: URL
	) -> URL {
		let baseURL = applicationSupportDirectory
			?? homeDirectory.appendingPathComponent("Library/Application Support", isDirectory: true)
		return baseURL
			.appendingPathComponent("Navigator", isDirectory: true)
			.appendingPathComponent("BrowserPermissionDecisions.json", isDirectory: false)
	}

	#if DEBUG
		static func makeDefaultFileURLForTesting(
			applicationSupportDirectory: URL?,
			homeDirectory: URL
		) -> URL {
			makeDefaultFileURL(
				applicationSupportDirectory: applicationSupportDirectory,
				homeDirectory: homeDirectory
			)
		}
	#endif
}
