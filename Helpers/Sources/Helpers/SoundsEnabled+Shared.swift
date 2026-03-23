import Foundation
import Vendors

public extension URL {
	static var soundsEnabled: Self {
		self.navigatorApplicationSupportFile(named: "SoundsEnabled")
	}
}

public extension SharedKey where Self == FileStorageKey<Bool> {
	static var soundsEnabled: Self {
		fileStorage(.soundsEnabled)
	}
}

public extension SharedReaderKey where Self == FileStorageKey<Bool>.Default {
	static var soundsEnabled: Self {
		Self[.soundsEnabled, default: true]
	}
}
