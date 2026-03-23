import Foundation

public enum BrowserImportEvent: Equatable, Sendable {
	case started(BrowserImportSource)
	case profileImported(BrowserImportSource, ImportedBrowserProfile)
	case finished(ImportedBrowserSnapshot)
}
