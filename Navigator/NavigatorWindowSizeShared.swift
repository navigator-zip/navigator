import AppKit
import Foundation
import Vendors

enum NavigatorBrowserWindowSizing {
	nonisolated static let minimumFrameWidth: CGFloat = 470
	nonisolated static let minimumFrameHeight: CGFloat = 200
	nonisolated static let minimumFrameSize = NSSize(
		width: minimumFrameWidth,
		height: minimumFrameHeight
	)
	nonisolated static let defaultFrameSize = NSSize(width: 1100, height: 700)
}

enum NavigatorWindowPersistenceKeys {
	nonisolated static let primaryFrameAutosaveName = "NavigatorPrimaryWindowFrame"
}

public struct NavigatorWindowFrame: Equatable, Sendable {
	public var origin: NSPoint
	public var size: NSSize

	public nonisolated init(origin: NSPoint = .zero, size: NSSize = NSSize(width: 1100, height: 700)) {
		self.origin = origin
		self.size = size
	}
}

private enum NavigatorWindowFrameDefaults {
	nonisolated static let value = NavigatorWindowFrame()
}

public struct NavigatorSidebarWidth: Equatable, Sendable {
	public let width: Double

	public nonisolated init(width: Double) {
		self.width = Self.clamp(width)
	}

	public nonisolated static let minimum: Double = 180
	public nonisolated static let maximum: Double = 640
	public nonisolated static let `default`: Double = 280

	nonisolated static func clamp(_ width: Double) -> Double {
		min(max(width, minimum), maximum)
	}
}

private enum NavigatorSidebarWidthDefaults {
	nonisolated static let value = NavigatorSidebarWidth(width: NavigatorSidebarWidth.default)
}

private enum NavigatorWindowFrameCoding {
	private struct StoragePayload: Codable {
		let originX: Double?
		let originY: Double?
		let width: Double?
		let height: Double?
	}

	nonisolated static func decode(_ data: Data) throws -> NavigatorWindowFrame {
		let payload = try JSONDecoder().decode(StoragePayload.self, from: data)
		guard
			let width = payload.width,
			let height = payload.height
		else {
			return NavigatorWindowFrameDefaults.value
		}

		let originX = payload.originX ?? 0
		let originY = payload.originY ?? 0

		return NavigatorWindowFrame(
			origin: NSPoint(x: originX, y: originY),
			size: NSSize(width: width, height: height)
		)
	}

	nonisolated static func encode(_ value: NavigatorWindowFrame) throws -> Data {
		try JSONEncoder().encode(StoragePayload(
			originX: value.origin.x,
			originY: value.origin.y,
			width: value.size.width,
			height: value.size.height
		))
	}
}

private enum NavigatorSidebarWidthCoding {
	private nonisolated static let widthKey = "width"

	nonisolated static func decode(_ data: Data) throws -> NavigatorSidebarWidth {
		let serialized = try JSONDecoder().decode([String: Double].self, from: data)
		guard let width = serialized[widthKey] else {
			return NavigatorSidebarWidthDefaults.value
		}
		return NavigatorSidebarWidth(width: width)
	}

	nonisolated static func encode(_ value: NavigatorSidebarWidth) throws -> Data {
		try JSONEncoder().encode([widthKey: value.width])
	}
}

public extension URL {
	nonisolated static var navigatorWindowSize: Self {
		self.navigatorApplicationSupportFile(named: "NavigatorWindowSize")
	}

	nonisolated static var navigatorSidebarWidth: Self {
		self.navigatorApplicationSupportFile(named: "NavigatorSidebarWidth")
	}

	nonisolated static var navigatorAutomaticallyChecksForUpdates: Self {
		self.navigatorApplicationSupportFile(named: "NavigatorAutomaticallyChecksForUpdates")
	}
}

public extension SharedKey where Self == FileStorageKey<NavigatorWindowFrame> {
	nonisolated static var navigatorWindowSize: Self {
		fileStorage(
			.navigatorWindowSize,
			decode: { data in
				try NavigatorWindowFrameCoding.decode(data)
			},
			encode: { value in
				try NavigatorWindowFrameCoding.encode(value)
			}
		)
	}
}

public extension SharedKey where Self == FileStorageKey<NavigatorSidebarWidth> {
	nonisolated static var navigatorSidebarWidth: Self {
		fileStorage(
			.navigatorSidebarWidth,
			decode: { data in
				try NavigatorSidebarWidthCoding.decode(data)
			},
			encode: { value in
				try NavigatorSidebarWidthCoding.encode(value)
			}
		)
	}
}

public extension SharedKey where Self == FileStorageKey<Bool> {
	nonisolated static var navigatorAutomaticallyChecksForUpdates: Self {
		fileStorage(.navigatorAutomaticallyChecksForUpdates)
	}
}

public extension SharedReaderKey where Self == FileStorageKey<NavigatorWindowFrame>.Default {
	nonisolated static var navigatorWindowSize: Self {
		Self[.navigatorWindowSize, default: NavigatorWindowFrameDefaults.value]
	}
}

public extension SharedReaderKey where Self == FileStorageKey<NavigatorSidebarWidth>.Default {
	nonisolated static var navigatorSidebarWidth: Self {
		Self[.navigatorSidebarWidth, default: NavigatorSidebarWidthDefaults.value]
	}
}

public extension SharedReaderKey where Self == FileStorageKey<Bool>.Default {
	nonisolated static var navigatorAutomaticallyChecksForUpdates: Self {
		Self[.navigatorAutomaticallyChecksForUpdates, default: true]
	}
}

nonisolated func loadPersistedNavigatorWindowFrame() -> NavigatorWindowFrame {
	guard
		let data = try? Data(contentsOf: .navigatorWindowSize),
		let persistedFrame = try? NavigatorWindowFrameCoding.decode(data)
	else {
		return NavigatorWindowFrameDefaults.value
	}
	return persistedFrame
}

nonisolated func persistNavigatorWindowFrame(_ value: NavigatorWindowFrame) throws {
	let url = URL.navigatorWindowSize
	try FileManager.default.createDirectory(
		at: url.deletingLastPathComponent(),
		withIntermediateDirectories: true
	)
	try NavigatorWindowFrameCoding.encode(value).write(to: url, options: .atomic)
}
