import Foundation

public enum BrowserRuntimeTopLevelNativeContentKind: String, Sendable, Equatable, CaseIterable, Decodable {
	case image
	case animatedImage
	case hlsStream
}

public struct BrowserRuntimeTopLevelNativeContent: Sendable, Equatable, Decodable {
	public let kind: BrowserRuntimeTopLevelNativeContentKind
	public let url: String
	public let pathExtension: String?
	public let uniformTypeIdentifier: String?

	public init(
		kind: BrowserRuntimeTopLevelNativeContentKind,
		url: String,
		pathExtension: String?,
		uniformTypeIdentifier: String?
	) {
		self.kind = kind
		self.url = url
		self.pathExtension = pathExtension
		self.uniformTypeIdentifier = uniformTypeIdentifier
	}

	static func from(json: String) -> Self? {
		guard let data = json.data(using: .utf8) else { return nil }
		return try? JSONDecoder().decode(Self.self, from: data)
	}
}
