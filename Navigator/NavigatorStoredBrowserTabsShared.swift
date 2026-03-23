import Foundation
import ModelKit
import Vendors

private enum NavigatorStoredBrowserTabCollectionCoding {
	nonisolated static func decode(_ data: Data) throws -> StoredBrowserTabCollection {
		try JSONDecoder().decode(StoredBrowserTabCollection.self, from: data)
	}

	nonisolated static func encode(_ value: StoredBrowserTabCollection) throws -> Data {
		try JSONEncoder().encode(value)
	}
}

private enum NavigatorStoredBrowserTabSelectionCoding {
	nonisolated static func decode(_ data: Data) throws -> StoredBrowserTabSelection {
		try JSONDecoder().decode(StoredBrowserTabSelection.self, from: data)
	}

	nonisolated static func encode(_ value: StoredBrowserTabSelection) throws -> Data {
		try JSONEncoder().encode(value)
	}
}

public extension URL {
	nonisolated static var navigatorStoredBrowserTabs: Self {
		self.navigatorApplicationSupportFile(named: "NavigatorStoredBrowserTabs")
	}

	nonisolated static var navigatorStoredBrowserTabSelection: Self {
		self.navigatorApplicationSupportFile(named: "NavigatorStoredBrowserTabSelection")
	}
}

public extension SharedKey where Self == FileStorageKey<StoredBrowserTabCollection> {
	nonisolated static var navigatorStoredBrowserTabs: Self {
		fileStorage(
			.navigatorStoredBrowserTabs,
			decode: { data in
				try NavigatorStoredBrowserTabCollectionCoding.decode(data)
			},
			encode: { value in
				try NavigatorStoredBrowserTabCollectionCoding.encode(value)
			}
		)
	}
}

public extension SharedKey where Self == FileStorageKey<StoredBrowserTabSelection> {
	nonisolated static var navigatorStoredBrowserTabSelection: Self {
		fileStorage(
			.navigatorStoredBrowserTabSelection,
			decode: { data in
				try NavigatorStoredBrowserTabSelectionCoding.decode(data)
			},
			encode: { value in
				try NavigatorStoredBrowserTabSelectionCoding.encode(value)
			}
		)
	}
}

public extension SharedReaderKey where Self == FileStorageKey<StoredBrowserTabCollection>.Default {
	nonisolated static var navigatorStoredBrowserTabs: Self {
		Self[.navigatorStoredBrowserTabs, default: .empty]
	}
}

public extension SharedReaderKey where Self == FileStorageKey<StoredBrowserTabSelection>.Default {
	nonisolated static var navigatorStoredBrowserTabSelection: Self {
		Self[.navigatorStoredBrowserTabSelection, default: .empty]
	}
}
