import Foundation
import ModelKit

public enum BrowserImportError: Error, Equatable, LocalizedError {
	case browserNotInstalled(BrowserImportSource)
	case profileNotFound(BrowserImportSource, profileID: String)
	case noProfilesFound(BrowserImportSource)
	case unsupportedSourceData(BrowserImportSource)
	case readFailed(URL)
	case parseFailed(BrowserImportSource, reason: String)

	public var errorDescription: String? {
		switch self {
		case .browserNotInstalled(let source):
			"\(source.displayName) is not installed or no profile data was found."
		case .profileNotFound(let source, let profileID):
			"Could not find profile \(profileID) for \(source.displayName)."
		case .noProfilesFound(let source):
			"No profiles were found for \(source.displayName)."
		case .unsupportedSourceData(let source):
			"Import for \(source.displayName) has not been implemented yet."
		case .readFailed(let url):
			"Could not read browser data at \(url.path)."
		case .parseFailed(let source, let reason):
			"Failed to parse \(source.displayName) browser data: \(reason)"
		}
	}
}
