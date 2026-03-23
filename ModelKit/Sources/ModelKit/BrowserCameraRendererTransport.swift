import Foundation

public enum BrowserCameraRendererTransportChannel: String, Codable, CaseIterable, Sendable {
	case routingConfiguration = "__cameraRoutingConfigUpdate__"
	case frameDelivery = "__cameraFrameDelivery__"
	case frameClear = "__cameraFrameClear__"
}

public struct BrowserCameraRendererTransportMessage: Codable, Equatable, Hashable, Sendable {
	public let channel: BrowserCameraRendererTransportChannel
	public let jsonPayload: String

	public init(
		channel: BrowserCameraRendererTransportChannel,
		jsonPayload: String
	) {
		self.channel = channel
		self.jsonPayload = jsonPayload
	}
}

public struct BrowserCameraRendererRoutingConfigurationPayload: Codable, Equatable, Hashable, Sendable {
	public let routingEnabled: Bool
	public let preferNavigatorCameraWhenPossible: Bool
	public let genericVideoUsesManagedOutput: Bool
	public let failClosedOnManagedVideoRequest: Bool
	public let managedRoutingAvailability: String
	public let preferredSourceID: String?
	public let preferredFilterPreset: String
	public let prefersHorizontalFlip: Bool
	public let outputMode: String
	public let healthState: String
	public let publisherState: String
	public let publisherTransportMode: String?
	public let exposesManagedDeviceIdentity: Bool
	public let managedDeviceID: String?
	public let managedDeviceLabel: String?

	public init(
		snapshot: BrowserCameraSessionSnapshot,
		managedDeviceLabel: String?
	) {
		let routingConfiguration = snapshot.routingConfiguration
		let managedRoutingSummary = snapshot.managedRoutingSummary
		routingEnabled = routingConfiguration.isRoutingEnabled
		preferNavigatorCameraWhenPossible = routingConfiguration.preferNavigatorCameraWhenPossible
		genericVideoUsesManagedOutput = managedRoutingSummary.genericVideoUsesManagedOutput
		failClosedOnManagedVideoRequest = managedRoutingSummary.failClosedOnManagedVideoRequest
		managedRoutingAvailability = managedRoutingSummary.availability.rawValue
		preferredSourceID = routingConfiguration.preferredDeviceID
		preferredFilterPreset = routingConfiguration.preferredFilterPreset.rawValue
		prefersHorizontalFlip = routingConfiguration.prefersHorizontalFlip
		outputMode = snapshot.outputMode.rawValue
		healthState = snapshot.healthState.rawValue
		publisherState = "notRequired"
		publisherTransportMode = nil
		exposesManagedDeviceIdentity = managedRoutingSummary.exposesManagedDeviceIdentity
		managedDeviceID = managedRoutingSummary.managedDeviceID
		self.managedDeviceLabel = managedRoutingSummary.exposesManagedDeviceIdentity
			? managedDeviceLabel
			: nil
	}

	public func transportMessage() -> BrowserCameraRendererTransportMessage {
		BrowserCameraRendererTransportMessage(
			channel: .routingConfiguration,
			jsonPayload: encodedJSONString()
		)
	}

	public func encodedJSONString() -> String {
		BrowserCameraRendererTransportEncoder.encode(self)
	}
}

public struct BrowserCameraRendererFrameClearPayload: Codable, Equatable, Hashable, Sendable {
	public init() {}

	public func transportMessage() -> BrowserCameraRendererTransportMessage {
		BrowserCameraRendererTransportMessage(
			channel: .frameClear,
			jsonPayload: encodedJSONString()
		)
	}

	public func encodedJSONString() -> String {
		BrowserCameraRendererTransportEncoder.encode(self)
	}
}

public extension BrowserCameraManagedFramePayload {
	func rendererTransportMessage() -> BrowserCameraRendererTransportMessage {
		BrowserCameraRendererTransportMessage(
			channel: .frameDelivery,
			jsonPayload: BrowserCameraRendererTransportEncoder.encode(self)
		)
	}
}

private enum BrowserCameraRendererTransportEncoder {
	static func encode(_ value: some Encodable) -> String {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.sortedKeys]
		let data = try! encoder.encode(value)
		return String(decoding: data, as: UTF8.self)
	}
}
