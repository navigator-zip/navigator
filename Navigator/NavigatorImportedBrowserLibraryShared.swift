import Foundation
import ModelKit
import Vendors

private enum NavigatorImportedBrowserLibraryDefaults {
	nonisolated static let value = ImportedBrowserLibrary.empty
}

private enum NavigatorImportedBrowserLibraryCoding {
	nonisolated static func decode(_ data: Data) throws -> ImportedBrowserLibrary {
		try JSONDecoder().decode(ImportedBrowserLibrary.self, from: data)
	}

	nonisolated static func encode(_ value: ImportedBrowserLibrary) throws -> Data {
		try JSONEncoder().encode(value)
	}
}

public extension URL {
	nonisolated static var navigatorImportedBrowserLibrary: Self {
		self.navigatorApplicationSupportFile(named: "NavigatorImportedBrowserLibrary")
	}
}

public extension SharedKey where Self == FileStorageKey<ImportedBrowserLibrary> {
	nonisolated static var navigatorImportedBrowserLibrary: Self {
		fileStorage(
			.navigatorImportedBrowserLibrary,
			decode: { data in
				try NavigatorImportedBrowserLibraryCoding.decode(data)
			},
			encode: { value in
				try NavigatorImportedBrowserLibraryCoding.encode(value)
			}
		)
	}
}

public extension SharedReaderKey where Self == FileStorageKey<ImportedBrowserLibrary>.Default {
	nonisolated static var navigatorImportedBrowserLibrary: Self {
		Self[.navigatorImportedBrowserLibrary, default: NavigatorImportedBrowserLibraryDefaults.value]
	}
}
