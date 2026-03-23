import AppKit
import BrowserCameraKit
import CoreGraphics
import ModelKit
import Observation

@MainActor
@Observable
public final class BrowserCameraMenuBarViewModel {
	public private(set) var routingEnabled: Bool
	public private(set) var previewEnabled: Bool
	public private(set) var availableSources: [BrowserCameraSource]
	public private(set) var selectedSourceID: String?
	public private(set) var selectedFilterPreset: BrowserCameraFilterPreset
	public private(set) var selectedGrainPresence: BrowserCameraPipelineGrainPresence
	public private(set) var prefersHorizontalFlip: Bool
	public private(set) var lifecycleState: BrowserCameraLifecycleState
	public private(set) var healthState: BrowserCameraHealthState
	public private(set) var outputMode: BrowserCameraOutputMode
	public private(set) var lastErrorDescription: String?
	public private(set) var debugSummary: BrowserCameraDebugSummary
	public let previewFrameUpdater: BrowserCameraPreviewFrameUpdater

	public let availableFilterPresets = BrowserCameraFilterPreset.allCases
	public let availableGrainPresences = BrowserCameraPipelineGrainPresence.allCases

	@ObservationIgnored
	private let browserCameraSessionCoordinator: any BrowserCameraSessionCoordinating
	@ObservationIgnored
	private let menuBarPreviewConsumerID = "menu-bar-preview-\(UUID().uuidString)"
	@ObservationIgnored
	private var snapshotObserverID: UUID?
	@ObservationIgnored
	private var changeObservers = [UUID: @MainActor () -> Void]()
	@ObservationIgnored
	private var isMenuBarPreviewConsumerRegistered = false
	@ObservationIgnored
	private var isPopoverPresented = false

	public var previewFrame: CGImage? {
		previewFrameUpdater.previewFrame
	}

	public init(
		browserCameraSessionCoordinator: any BrowserCameraSessionCoordinating,
		previewFrameUpdater: BrowserCameraPreviewFrameUpdater = .shared
	) {
		self.browserCameraSessionCoordinator = browserCameraSessionCoordinator
		self.previewFrameUpdater = previewFrameUpdater
		let snapshot = browserCameraSessionCoordinator.currentSnapshot()
		routingEnabled = snapshot.routingSettings.routingEnabled
		previewEnabled = snapshot.routingSettings.previewEnabled
		availableSources = snapshot.availableSources
		selectedSourceID = snapshot.routingSettings.preferredSourceID
		selectedFilterPreset = snapshot.routingSettings.preferredFilterPreset
		selectedGrainPresence = snapshot.routingSettings.preferredGrainPresence
		prefersHorizontalFlip = snapshot.routingSettings.prefersHorizontalFlip
		lifecycleState = snapshot.lifecycleState
		healthState = snapshot.healthState
		outputMode = snapshot.outputMode
		lastErrorDescription = snapshot.lastErrorDescription
		debugSummary = snapshot.debugSummary
		snapshotObserverID = browserCameraSessionCoordinator.addSnapshotObserver { [weak self] snapshot in
			self?.applySnapshot(snapshot)
		}
	}

	@discardableResult
	public func addChangeObserver(
		_ observer: @escaping @MainActor () -> Void
	) -> UUID {
		let observerID = UUID()
		changeObservers[observerID] = observer
		observer()
		return observerID
	}

	public func removeChangeObserver(id: UUID) {
		changeObservers.removeValue(forKey: id)
	}

	public func refreshAvailableDevices() {
		browserCameraSessionCoordinator.refreshAvailableDevices()
	}

	public func setRoutingEnabled(_ isEnabled: Bool) {
		browserCameraSessionCoordinator.setRoutingEnabled(isEnabled)
	}

	public func setPreviewEnabled(_ isEnabled: Bool) {
		browserCameraSessionCoordinator.setPreviewEnabled(isEnabled)
	}

	public func selectSource(id: String?) {
		browserCameraSessionCoordinator.setPreferredDeviceID(id)
	}

	public func selectFilterPreset(_ preset: BrowserCameraFilterPreset) {
		browserCameraSessionCoordinator.setPreferredFilterPreset(preset)
	}

	public func selectGrainPresence(_ grainPresence: BrowserCameraPipelineGrainPresence) {
		browserCameraSessionCoordinator.setPreferredGrainPresence(grainPresence)
	}

	public func setPrefersHorizontalFlip(_ prefersHorizontalFlip: Bool) {
		browserCameraSessionCoordinator.setPrefersHorizontalFlip(prefersHorizontalFlip)
	}

	public func setControlsPresented(_ isPresented: Bool) {
		guard isPopoverPresented != isPresented else { return }
		isPopoverPresented = isPresented
		syncMenuBarPreviewConsumerRegistration()
	}

	public func setPopoverPresented(_ isPresented: Bool) {
		setControlsPresented(isPresented)
	}

	public func invalidate() {
		if let snapshotObserverID {
			browserCameraSessionCoordinator.removeSnapshotObserver(id: snapshotObserverID)
			self.snapshotObserverID = nil
		}
		if isMenuBarPreviewConsumerRegistered {
			browserCameraSessionCoordinator.unregisterConsumer(id: menuBarPreviewConsumerID)
			isMenuBarPreviewConsumerRegistered = false
		}
		changeObservers.removeAll()
	}

	private func applySnapshot(_ snapshot: BrowserCameraSessionSnapshot) {
		routingEnabled = snapshot.routingSettings.routingEnabled
		previewEnabled = snapshot.routingSettings.previewEnabled
		availableSources = snapshot.availableSources
		selectedSourceID = snapshot.routingSettings.preferredSourceID
		selectedFilterPreset = snapshot.routingSettings.preferredFilterPreset
		selectedGrainPresence = snapshot.routingSettings.preferredGrainPresence
		prefersHorizontalFlip = snapshot.routingSettings.prefersHorizontalFlip
		lifecycleState = snapshot.lifecycleState
		healthState = snapshot.healthState
		outputMode = snapshot.outputMode
		lastErrorDescription = snapshot.lastErrorDescription
		debugSummary = snapshot.debugSummary
		syncMenuBarPreviewConsumerRegistration()
		notifyChangeObservers()
	}

	private func syncMenuBarPreviewConsumerRegistration() {
		if previewEnabled, isPopoverPresented {
			registerMenuBarPreviewConsumerIfNeeded()
		}
		else {
			unregisterMenuBarPreviewConsumerIfNeeded()
		}
	}

	private func registerMenuBarPreviewConsumerIfNeeded() {
		guard !isMenuBarPreviewConsumerRegistered else { return }
		isMenuBarPreviewConsumerRegistered = true
		browserCameraSessionCoordinator.registerConsumer(
			BrowserCameraConsumer(
				id: menuBarPreviewConsumerID,
				kind: .menuBarPreview,
				requiresLiveFrames: false
			)
		)
	}

	private func unregisterMenuBarPreviewConsumerIfNeeded() {
		guard isMenuBarPreviewConsumerRegistered else { return }
		isMenuBarPreviewConsumerRegistered = false
		browserCameraSessionCoordinator.unregisterConsumer(id: menuBarPreviewConsumerID)
	}

	private func notifyChangeObservers() {
		for observer in changeObservers.values {
			observer()
		}
	}
}
