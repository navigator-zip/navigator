import Foundation

private enum NavigatorApplicationSupportConstants {
	static let directoryName = "Navigator"
}

public extension URL {
	nonisolated static var navigatorApplicationSupportDirectory: Self {
		let applicationSupportDirectory = baseApplicationSupportDirectory(
			from: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask),
			homeDirectory: FileManager.default.homeDirectoryForCurrentUser
		)
		return navigatorApplicationSupportDirectory(in: applicationSupportDirectory)
	}

	nonisolated static func navigatorApplicationSupportFile(named fileName: String) -> Self {
		let applicationSupportDirectory = baseApplicationSupportDirectory(
			from: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask),
			homeDirectory: FileManager.default.homeDirectoryForCurrentUser
		)
		return navigatorApplicationSupportFile(
			named: fileName,
			applicationSupportDirectory: applicationSupportDirectory,
			fileManager: .default
		)
	}

	static func baseApplicationSupportDirectory(
		from directories: [URL],
		homeDirectory: URL
	) -> URL {
		directories.first
			?? homeDirectory
			.appendingPathComponent("Library", isDirectory: true)
			.appendingPathComponent("Application Support", isDirectory: true)
	}

	static func navigatorApplicationSupportDirectory(in applicationSupportDirectory: URL) -> URL {
		applicationSupportDirectory
			.appendingPathComponent(NavigatorApplicationSupportConstants.directoryName, isDirectory: true)
	}

	static func navigatorApplicationSupportFile(
		named fileName: String,
		applicationSupportDirectory: URL,
		fileManager: FileManager = .default
	) -> URL {
		let navigatorDirectory = navigatorApplicationSupportDirectory(in: applicationSupportDirectory)
		let destinationURL = navigatorDirectory.appendingPathComponent(fileName, isDirectory: false)
		migrateLegacyApplicationSupportFileIfNeeded(
			named: fileName,
			destinationURL: destinationURL,
			applicationSupportDirectory: applicationSupportDirectory,
			fileManager: fileManager
		)
		return destinationURL
	}

	static func legacyApplicationSupportFile(
		named fileName: String,
		applicationSupportDirectory: URL
	) -> URL {
		applicationSupportDirectory.appendingPathComponent(fileName, isDirectory: false)
	}

	private static func migrateLegacyApplicationSupportFileIfNeeded(
		named fileName: String,
		destinationURL: URL,
		applicationSupportDirectory: URL,
		fileManager: FileManager
	) {
		let legacyURL = legacyApplicationSupportFile(
			named: fileName,
			applicationSupportDirectory: applicationSupportDirectory
		)
		guard
			fileManager.fileExists(atPath: destinationURL.path) == false,
			fileManager.fileExists(atPath: legacyURL.path)
		else {
			return
		}

		try? fileManager.createDirectory(
			at: destinationURL.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		try? fileManager.moveItem(at: legacyURL, to: destinationURL)
	}
}
