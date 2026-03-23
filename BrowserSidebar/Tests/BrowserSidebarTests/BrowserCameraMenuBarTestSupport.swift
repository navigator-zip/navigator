import AppKit
import BrowserCameraKit
import CoreGraphics
import ModelKit

@MainActor
final class BrowserCameraMenuBarCoordinatorSpy: BrowserCameraSessionCoordinating {
	var snapshot = BrowserCameraSessionSnapshot(
		lifecycleState: .idle,
		healthState: .healthy,
		outputMode: .processedNavigatorFeed,
		routingSettings: BrowserCameraRoutingSettings(
			routingEnabled: true,
			preferNavigatorCameraWhenPossible: true,
			preferredSourceID: "camera-1",
			preferredFilterPreset: .none,
			previewEnabled: false
		),
		availableSources: [
			BrowserCameraSource(id: "camera-1", name: "FaceTime HD Camera", isDefault: true),
			BrowserCameraSource(id: "camera-2", name: "Studio Display Camera", isDefault: false),
		],
		activeConsumersByID: [:],
		performanceMetrics: .empty,
		lastErrorDescription: nil
	)
	var previewFrame: CGImage?
	private var snapshotObservers = [UUID: @MainActor (BrowserCameraSessionSnapshot) -> Void]()
	private var previewObservers = [UUID: @MainActor (CGImage?) -> Void]()

	private(set) var refreshAvailableDevicesCount = 0
	private(set) var registeredConsumers = [BrowserCameraConsumer]()
	private(set) var unregisteredConsumerIDs = [String]()
	private(set) var routingEnabledValues = [Bool]()
	private(set) var selectedSourceIDs = [String?]()
	private(set) var selectedFilterPresets = [BrowserCameraFilterPreset]()
	private(set) var selectedGrainPresences = [BrowserCameraPipelineGrainPresence]()
	private(set) var selectedHorizontalFlipValues = [Bool]()
	private(set) var previewEnabledValues = [Bool]()
	private(set) var removedSnapshotObserverIDs = [String]()

	func currentSnapshot() -> BrowserCameraSessionSnapshot {
		snapshot
	}

	func currentDebugSummary() -> BrowserCameraDebugSummary {
		snapshot.debugSummary
	}

	func currentRoutingConfiguration() -> BrowserCameraRoutingConfiguration {
		snapshot.routingConfiguration
	}

	func currentPreviewFrame() -> CGImage? {
		previewFrame
	}

	func refreshAvailableDevices() {
		refreshAvailableDevicesCount += 1
	}

	func registerConsumer(_ consumer: BrowserCameraConsumer) {
		let normalizedConsumer = BrowserCameraConsumer(
			id: "menu-bar-preview",
			kind: consumer.kind,
			requiresLiveFrames: consumer.requiresLiveFrames
		)
		registeredConsumers.append(normalizedConsumer)
		snapshot = BrowserCameraSessionSnapshot(
			lifecycleState: snapshot.lifecycleState,
			healthState: snapshot.healthState,
			outputMode: snapshot.outputMode,
			routingSettings: snapshot.routingSettings,
			availableSources: snapshot.availableSources,
			activeConsumersByID: ["menu-bar-preview": normalizedConsumer],
			performanceMetrics: snapshot.performanceMetrics,
			lastErrorDescription: snapshot.lastErrorDescription
		)
		emitSnapshot()
	}

	func unregisterConsumer(id: String) {
		unregisteredConsumerIDs.append("menu-bar-preview")
		snapshot = BrowserCameraSessionSnapshot(
			lifecycleState: snapshot.lifecycleState,
			healthState: snapshot.healthState,
			outputMode: snapshot.outputMode,
			routingSettings: snapshot.routingSettings,
			availableSources: snapshot.availableSources,
			activeConsumersByID: [:],
			performanceMetrics: snapshot.performanceMetrics,
			lastErrorDescription: snapshot.lastErrorDescription
		)
		emitSnapshot()
	}

	func setRoutingEnabled(_ isEnabled: Bool) {
		routingEnabledValues.append(isEnabled)
	}

	func setPreferredDeviceID(_ preferredDeviceID: String?) {
		selectedSourceIDs.append(preferredDeviceID)
	}

	func setPreferredFilterPreset(_ preferredFilterPreset: BrowserCameraFilterPreset) {
		selectedFilterPresets.append(preferredFilterPreset)
	}

	func setPreferredGrainPresence(_ preferredGrainPresence: BrowserCameraPipelineGrainPresence) {
		selectedGrainPresences.append(preferredGrainPresence)
	}

	func setPrefersHorizontalFlip(_ prefersHorizontalFlip: Bool) {
		selectedHorizontalFlipValues.append(prefersHorizontalFlip)
	}

	func setPreviewEnabled(_ isEnabled: Bool) {
		previewEnabledValues.append(isEnabled)
	}

	func noteBrowserRoutingEvent(tabID _: String, event _: BrowserCameraRoutingEvent) {}

	func noteBrowserProcessFallback(tabID _: String, reason _: String) {}

	func updateBrowserTransportState(_ state: BrowserCameraBrowserTransportState) {}

	func clearBrowserTransportState(tabID _: String) {}

	func addSnapshotObserver(
		_ observer: @escaping @MainActor (BrowserCameraSessionSnapshot) -> Void
	) -> UUID {
		let observerID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
		snapshotObservers[observerID] = observer
		observer(snapshot)
		return observerID
	}

	func removeSnapshotObserver(id: UUID) {
		snapshotObservers.removeValue(forKey: id)
		removedSnapshotObserverIDs.append("snapshot-observer")
	}

	func addPreviewFrameObserver(
		_ observer: @escaping @MainActor (CGImage?) -> Void
	) -> UUID {
		let observerID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
		previewObservers[observerID] = observer
		observer(previewFrame)
		return observerID
	}

	func removePreviewFrameObserver(id: UUID) {
		previewObservers.removeValue(forKey: id)
	}

	func emitSnapshot() {
		for observer in snapshotObservers.values {
			observer(snapshot)
		}
	}

	func emitPreviewFrame() {
		for observer in previewObservers.values {
			observer(previewFrame)
		}
	}

	func setPreviewEnabledInSnapshot(_ isEnabled: Bool) {
		var routingSettings = snapshot.routingSettings
		routingSettings.previewEnabled = isEnabled
		snapshot = BrowserCameraSessionSnapshot(
			lifecycleState: snapshot.lifecycleState,
			healthState: snapshot.healthState,
			outputMode: snapshot.outputMode,
			routingSettings: routingSettings,
			availableSources: snapshot.availableSources,
			activeConsumersByID: snapshot.activeConsumersByID,
			performanceMetrics: snapshot.performanceMetrics,
			lastErrorDescription: snapshot.lastErrorDescription
		)
	}
}

func makePreviewFrame(width: Int, height: Int) -> CGImage {
	let colorSpace = CGColorSpaceCreateDeviceRGB()
	let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
	let context = CGContext(
		data: nil,
		width: width,
		height: height,
		bitsPerComponent: 8,
		bytesPerRow: width * 4,
		space: colorSpace,
		bitmapInfo: bitmapInfo.rawValue
	)!
	context.setFillColor(NSColor.systemBlue.cgColor)
	context.fill(CGRect(x: 0, y: 0, width: width, height: height))
	return context.makeImage()!
}
