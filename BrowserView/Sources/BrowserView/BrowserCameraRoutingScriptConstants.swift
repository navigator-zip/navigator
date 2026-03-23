import Foundation
import ModelKit

enum BrowserCameraRoutingScriptConstants {
	static let shimKey = "__navigatorCameraRoutingShim"
	static let managedFrameStateKey = "__navigatorCameraManagedFrameState"
	static let nativeEventBridgeKey = "__navigatorCameraRoutingEmitEvent"
	static let routingChangeEventName = "navigator-camera-routing-change"
	static let cameraRoutingEventPromptMessage = "__navigatorCameraRoutingEvent__"
	static let cameraRoutingConfigUpdateChannel = BrowserCameraRendererTransportChannel.routingConfiguration.rawValue
	static let cameraFrameDeliveryChannel = BrowserCameraRendererTransportChannel.frameDelivery.rawValue
	static let cameraFrameClearChannel = BrowserCameraRendererTransportChannel.frameClear.rawValue
}
