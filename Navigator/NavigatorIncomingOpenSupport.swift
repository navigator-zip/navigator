import Foundation

enum NavigatorLaunchEnvironment {
	private static let testEnvironmentKeys = [
		"XCTestConfigurationFilePath",
		"XCTestBundlePath",
	]

	static func isRunningTests(
		environment: [String: String] = ProcessInfo.processInfo.environment
	) -> Bool {
		testEnvironmentKeys.contains { environment[$0].map { $0.isEmpty == false } == true }
	}
}

enum NavigatorIncomingOpenRequestResolver {
	private static let supportedSchemes = Set(["http", "https"])

	nonisolated static func urlStrings(from urls: [URL]) -> [String] {
		urls.compactMap(urlString(from:))
	}

	nonisolated static func fileURLs(from filePaths: [String]) -> [URL] {
		filePaths.map { URL(fileURLWithPath: $0) }
	}

	private nonisolated static func urlString(from url: URL) -> String? {
		let absoluteString = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
		guard absoluteString.isEmpty == false else { return nil }
		guard url.isFileURL == false else { return absoluteString }

		guard let scheme = url.scheme?.lowercased(), supportedSchemes.contains(scheme) else {
			return nil
		}

		return absoluteString
	}
}
