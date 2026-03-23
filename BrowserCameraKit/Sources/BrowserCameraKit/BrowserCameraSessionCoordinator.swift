import AVFoundation
import CoreGraphics
import Foundation
import ModelKit
import Observation
import OSLog

@MainActor
public protocol BrowserCameraSessionCoordinating: AnyObject {
	func currentSnapshot() -> BrowserCameraSessionSnapshot
	func currentDebugSummary() -> BrowserCameraDebugSummary
	func currentRoutingConfiguration() -> BrowserCameraRoutingConfiguration
	func currentPreviewFrame() -> CGImage?
	func refreshAvailableDevices()
	func registerConsumer(_ consumer: BrowserCameraConsumer)
	func unregisterConsumer(id: String)
	func setRoutingEnabled(_ isEnabled: Bool)
	func setPreferredDeviceID(_ preferredDeviceID: String?)
	func setPreferredFilterPreset(_ preferredFilterPreset: BrowserCameraFilterPreset)
	func setPreferredGrainPresence(_ preferredGrainPresence: BrowserCameraPipelineGrainPresence)
	func setPrefersHorizontalFlip(_ prefersHorizontalFlip: Bool)
	func setPreviewEnabled(_ isEnabled: Bool)
	func noteBrowserRoutingEvent(tabID: String, event: BrowserCameraRoutingEvent)
	func noteBrowserProcessFallback(tabID: String, reason: String)
	func updateBrowserTransportState(_ state: BrowserCameraBrowserTransportState)
	func clearBrowserTransportState(tabID: String)
	@discardableResult
	func addSnapshotObserver(
		_ observer: @escaping @MainActor (BrowserCameraSessionSnapshot) -> Void
	) -> UUID
	func removeSnapshotObserver(id: UUID)
	@discardableResult
	func addPreviewFrameObserver(
		_ observer: @escaping @MainActor (CGImage?) -> Void
	) -> UUID
	func removePreviewFrameObserver(id: UUID)
}

@MainActor
protocol BrowserCameraDeviceProviding {
	func availableDevices() -> [BrowserCameraDevice]
}

@MainActor
protocol BrowserCameraPreferencesStoring {
	func loadPreferences() -> BrowserCameraPreferences
	func savePreferences(_ preferences: BrowserCameraPreferences)
}

@MainActor
private enum BrowserCameraManagedCaptureState: Equatable {
	static let realtimeBudgetExceededDescription =
		"Navigator Camera processing is currently exceeding the realtime budget."

	case idle
	case starting(deviceID: String)
	case running(deviceID: String)
	case stopping(previousDeviceID: String?)
	case failed(BrowserCameraCaptureError)
}

@MainActor
private enum BrowserCameraDiagnosticsDefaults {
	static let maxRecentEvents = 20
}

private final class PreviewFrameUpdaterObserverToken {
	private let previewFrameUpdater: BrowserCameraPreviewFrameUpdater
	private let observerID: UUID

	init(updater: BrowserCameraPreviewFrameUpdater, observerID: UUID) {
		self.previewFrameUpdater = updater
		self.observerID = observerID
	}

	deinit {
		previewFrameUpdater.removeObserver(id: observerID)
	}
}

@MainActor
@Observable
public final class BrowserCameraSessionCoordinator: BrowserCameraSessionCoordinating {
	private static let logger = Logger(
		subsystem: "com.navigator.Navigator",
		category: "BrowserCameraSession"
	)

	static let defaultPreferredManagedOutputMode: BrowserCameraOutputMode =
		.processedNavigatorFeed

	public static let shared = BrowserCameraSessionCoordinator()

	private let deviceProvider: any BrowserCameraDeviceProviding
	private let preferencesStore: any BrowserCameraPreferencesStoring
	private let captureController: any BrowserCameraCaptureControlling
	private let previewFrameUpdater: BrowserCameraPreviewFrameUpdater
	private let preferredManagedOutputMode: BrowserCameraOutputMode

	private var preferences: BrowserCameraPreferences
	private var availableDevices = [BrowserCameraDevice]()
	private var consumersByID = [String: BrowserCameraConsumer]()
	private var lastManagedCaptureDeviceID: String?
	private var managedCaptureState: BrowserCameraManagedCaptureState = .idle
	private var lifecycleState: BrowserCameraLifecycleState = .idle
	private var healthState: BrowserCameraHealthState = .healthy
	private var outputMode: BrowserCameraOutputMode = .unavailable
	private var performanceMetrics = BrowserCameraPerformanceMetrics.empty
	private var lastErrorDescription: String?
	private var pipelineRuntimeState: BrowserCameraPipelineRuntimeState?
	private var browserTransportStatesByTabID = [String: BrowserCameraBrowserTransportState]()
	private var recentDiagnosticEvents = [BrowserCameraDiagnosticEvent]()
	private var snapshotObservers = [UUID: @MainActor (BrowserCameraSessionSnapshot) -> Void]()
	private var previewFrameObservers = [UUID: @MainActor (CGImage?) -> Void]()
	private var previewFrameUpdaterObserverToken: PreviewFrameUpdaterObserverToken?
	private var lastPublishedSnapshot: BrowserCameraSessionSnapshot?
	private var previewFrame: CGImage?

	public convenience init() {
		self.init(
			deviceProvider: LiveBrowserCameraDeviceProvider(),
			preferencesStore: UserDefaultsBrowserCameraPreferencesStore(),
			captureController: LiveBrowserCameraCaptureController(),
			previewFrameUpdater: .shared,
			preferredManagedOutputMode: Self.defaultPreferredManagedOutputMode
		)
	}

	convenience init(
		deviceProvider: any BrowserCameraDeviceProviding,
		preferencesStore: any BrowserCameraPreferencesStoring,
		captureController: any BrowserCameraCaptureControlling
	) {
		self.init(
			deviceProvider: deviceProvider,
			preferencesStore: preferencesStore,
			captureController: captureController,
			previewFrameUpdater: .shared,
			preferredManagedOutputMode: .processedNavigatorFeed
		)
	}

	init(
		deviceProvider: any BrowserCameraDeviceProviding,
		preferencesStore: any BrowserCameraPreferencesStoring,
		captureController: any BrowserCameraCaptureControlling,
		previewFrameUpdater: BrowserCameraPreviewFrameUpdater = .shared,
		preferredManagedOutputMode: BrowserCameraOutputMode
	) {
		self.deviceProvider = deviceProvider
		self.preferencesStore = preferencesStore
		self.captureController = captureController
		self.previewFrameUpdater = previewFrameUpdater
		self.preferredManagedOutputMode = Self.normalizePreferredManagedOutputMode(
			preferredManagedOutputMode
		)
		preferences = preferencesStore.loadPreferences()
		Self.logger.info(
			"Loaded camera preferences preferredDeviceID=\(self.preferences.preferredDeviceID ?? "automatic", privacy: .public) preset=\(self.preferences.preferredFilterPreset.rawValue, privacy: .public) grain=\(self.preferences.preferredGrainPresence.rawValue, privacy: .public) flipped=\(Self.flagDescription(self.preferences.prefersHorizontalFlip), privacy: .public) routingEnabled=\(Self.flagDescription(self.preferences.routingEnabled), privacy: .public) previewEnabled=\(Self.flagDescription(self.preferences.previewEnabled), privacy: .public)"
		)
		captureController.delegate = self
		previewFrame = previewFrameUpdater.previewFrame
		refreshAvailableDevices()
	}

	public func currentSnapshot() -> BrowserCameraSessionSnapshot {
		BrowserCameraSessionSnapshot(
			lifecycleState: lifecycleState,
			healthState: healthState,
			outputMode: outputMode,
			routingSettings: currentRoutingConfiguration().settings,
			availableSources: availableDevices,
			activeConsumersByID: consumersByID,
			performanceMetrics: performanceMetrics,
			lastErrorDescription: lastErrorDescription,
			pipelineRuntimeState: pipelineRuntimeState,
			browserTransportStates: browserTransportStates,
			recentDiagnosticEvents: recentDiagnosticEvents
		)
	}

	public func currentDebugSummary() -> BrowserCameraDebugSummary {
		currentSnapshot().debugSummary
	}

	public func currentPreviewFrame() -> CGImage? {
		previewFrame
	}

	@discardableResult
	public func addSnapshotObserver(
		_ observer: @escaping @MainActor (BrowserCameraSessionSnapshot) -> Void
	) -> UUID {
		let observerID = UUID()
		snapshotObservers[observerID] = observer
		observer(currentSnapshot())
		return observerID
	}

	public func removeSnapshotObserver(id: UUID) {
		snapshotObservers.removeValue(forKey: id)
	}

	@discardableResult
	public func addPreviewFrameObserver(
		_ observer: @escaping @MainActor (CGImage?) -> Void
	) -> UUID {
		if previewFrameObservers.isEmpty {
			let observerID = previewFrameUpdater.addObserver { [weak self] previewFrame in
				guard let self else { return }
				self.previewFrame = previewFrame
				self.publishPreviewFrame()
			}
			previewFrameUpdaterObserverToken = PreviewFrameUpdaterObserverToken(
				updater: previewFrameUpdater,
				observerID: observerID
			)
		}

		let observerID = UUID()
		previewFrameObservers[observerID] = observer
		observer(previewFrame)
		return observerID
	}

	public func removePreviewFrameObserver(id: UUID) {
		previewFrameObservers.removeValue(forKey: id)
		if previewFrameObservers.isEmpty {
			previewFrameUpdaterObserverToken = nil
		}
	}

	public func currentRoutingConfiguration() -> BrowserCameraRoutingConfiguration {
		return BrowserCameraRoutingConfiguration(
			isRoutingEnabled: preferences.routingEnabled && resolvedPreferredDeviceID != nil,
			preferredDeviceID: resolvedPreferredDeviceID,
			preferNavigatorCameraWhenPossible: preferences.preferNavigatorCameraWhenPossible,
			preferredFilterPreset: preferences.preferredFilterPreset,
			preferredGrainPresence: preferences.preferredGrainPresence,
			prefersHorizontalFlip: preferences.prefersHorizontalFlip,
			previewEnabled: preferences.previewEnabled,
			outputMode: outputMode
		)
	}

	public func refreshAvailableDevices() {
		let previousDevices = availableDevices
		availableDevices = deviceProvider.availableDevices()
		Self.logger.info(
			"Refreshed camera devices count=\(self.availableDevices.count) preferredDeviceID=\(self.preferences.preferredDeviceID ?? "automatic", privacy: .public) resolvedPreferredDeviceID=\(self.resolvedPreferredDeviceID ?? "none", privacy: .public) sources=\(Self.deviceAvailabilityDetail(for: self.availableDevices), privacy: .public)"
		)
		if Self.deviceSignatures(previousDevices) != Self.deviceSignatures(availableDevices) {
			recordDiagnosticEvent(
				kind: .deviceAvailabilityChanged,
				detail: Self.deviceAvailabilityDetail(for: availableDevices)
			)
		}
		repairPreferredDeviceIfNeeded()
		reconcileManagedCaptureDemand()
		syncDerivedState()
	}

	public func registerConsumer(_ consumer: BrowserCameraConsumer) {
		let previousConsumer = consumersByID.updateValue(consumer, forKey: consumer.id)
		if previousConsumer != consumer {
			recordDiagnosticEvent(
				kind: .consumerRegistered,
				detail: Self.consumerDetail(consumer)
			)
		}
		reconcileManagedCaptureDemand()
		syncDerivedState()
	}

	public func unregisterConsumer(id: String) {
		guard let removedConsumer = consumersByID.removeValue(forKey: id) else { return }
		recordDiagnosticEvent(
			kind: .consumerUnregistered,
			detail: Self.consumerDetail(removedConsumer)
		)
		reconcileManagedCaptureDemand()
		syncDerivedState()
	}

	public func setRoutingEnabled(_ isEnabled: Bool) {
		guard preferences.routingEnabled != isEnabled else { return }
		preferences.routingEnabled = isEnabled
		savePreferences()
		recordDiagnosticEvent(
			kind: .routingChanged,
			detail: "routingEnabled=\(Self.flagDescription(isEnabled))"
		)
		reconcileManagedCaptureDemand()
		syncDerivedState()
	}

	public func setPreferredDeviceID(_ preferredDeviceID: String?) {
		guard preferences.preferredDeviceID != preferredDeviceID else { return }
		Self.logger.info(
			"setPreferredDeviceID old=\(self.preferences.preferredDeviceID ?? "automatic", privacy: .public) new=\(preferredDeviceID ?? "automatic", privacy: .public)"
		)
		preferences.preferredDeviceID = preferredDeviceID
		savePreferences()
		recordDiagnosticEvent(
			kind: .preferredSourceChanged,
			detail: "preferredSourceID=\(preferredDeviceID ?? "automatic")"
		)
		reconcileManagedCaptureDemand()
		syncDerivedState()
	}

	public func setPreferredFilterPreset(_ preferredFilterPreset: BrowserCameraFilterPreset) {
		guard preferences.preferredFilterPreset != preferredFilterPreset else { return }
		Self.logger.info(
			"setPreferredFilterPreset old=\(self.preferences.preferredFilterPreset.rawValue, privacy: .public) new=\(preferredFilterPreset.rawValue, privacy: .public)"
		)
		preferences.preferredFilterPreset = preferredFilterPreset
		savePreferences()
		recordDiagnosticEvent(
			kind: .filterPresetChanged,
			detail: "preset=\(preferredFilterPreset.rawValue)"
		)
		if let desiredManagedCaptureDeviceID {
			captureController.updateCaptureConfiguration(
				BrowserCameraCaptureConfiguration(
					deviceID: desiredManagedCaptureDeviceID,
					filterPreset: preferences.preferredFilterPreset,
					grainPresence: preferences.preferredGrainPresence,
					prefersHorizontalFlip: preferences.prefersHorizontalFlip
				)
			)
		}
		else {
			reconcileManagedCaptureDemand()
		}
		syncDerivedState()
	}

	public func setPreferredGrainPresence(_ preferredGrainPresence: BrowserCameraPipelineGrainPresence) {
		guard preferences.preferredGrainPresence != preferredGrainPresence else { return }
		Self.logger.info(
			"setPreferredGrainPresence old=\(self.preferences.preferredGrainPresence.rawValue, privacy: .public) new=\(preferredGrainPresence.rawValue, privacy: .public)"
		)
		preferences.preferredGrainPresence = preferredGrainPresence
		savePreferences()
		recordDiagnosticEvent(
			kind: .filterPresetChanged,
			detail: "grain=\(preferredGrainPresence.rawValue)"
		)
		if let desiredManagedCaptureDeviceID {
			captureController.updateCaptureConfiguration(
				BrowserCameraCaptureConfiguration(
					deviceID: desiredManagedCaptureDeviceID,
					filterPreset: preferences.preferredFilterPreset,
					grainPresence: preferences.preferredGrainPresence,
					prefersHorizontalFlip: preferences.prefersHorizontalFlip
				)
			)
		}
		else {
			reconcileManagedCaptureDemand()
		}
		syncDerivedState()
	}

	public func setPrefersHorizontalFlip(_ prefersHorizontalFlip: Bool) {
		guard preferences.prefersHorizontalFlip != prefersHorizontalFlip else { return }
		Self.logger.info(
			"setPrefersHorizontalFlip old=\(Self.flagDescription(self.preferences.prefersHorizontalFlip), privacy: .public) new=\(Self.flagDescription(prefersHorizontalFlip), privacy: .public)"
		)
		preferences.prefersHorizontalFlip = prefersHorizontalFlip
		preferencesStore.savePreferences(preferences)
		recordDiagnosticEvent(
			kind: .routingChanged,
			detail: "prefersHorizontalFlip=\(prefersHorizontalFlip)"
		)
		if let desiredManagedCaptureDeviceID {
			captureController.updateCaptureConfiguration(
				BrowserCameraCaptureConfiguration(
					deviceID: desiredManagedCaptureDeviceID,
					filterPreset: preferences.preferredFilterPreset,
					grainPresence: preferences.preferredGrainPresence,
					prefersHorizontalFlip: preferences.prefersHorizontalFlip
				)
			)
		}
		else {
			reconcileManagedCaptureDemand()
		}
		syncDerivedState()
	}

	public func setPreviewEnabled(_ isEnabled: Bool) {
		guard preferences.previewEnabled != isEnabled else { return }
		preferences.previewEnabled = isEnabled
		savePreferences()
		recordDiagnosticEvent(
			kind: .previewChanged,
			detail: "previewEnabled=\(Self.flagDescription(isEnabled))"
		)
		reconcileManagedCaptureDemand()
		syncDerivedState()
	}

	public func noteBrowserRoutingEvent(tabID: String, event: BrowserCameraRoutingEvent) {
		let eventKind: BrowserCameraDiagnosticEventKind = switch event.event {
		case .trackStarted:
			.managedTrackStarted
		case .trackStopped:
			.managedTrackStopped
		case .trackEnded:
			.managedTrackEnded
		case .permissionProbeFailed:
			.permissionProbeFailed
		case .explicitDeviceBypassed:
			.explicitDeviceBypassed
		case .managedTrackDeviceSwitchRejected:
			.managedTrackDeviceSwitchRejected
		}
		recordDiagnosticEvent(
			kind: eventKind,
			detail: Self.browserRoutingDetail(tabID: tabID, event: event)
		)
		publishSnapshotIfNeeded()
	}

	public func noteBrowserProcessFallback(tabID: String, reason: String) {
		recordDiagnosticEvent(
			kind: .browserProcessFallbackActivated,
			detail: "tabID=\(tabID) reason=\(reason)"
		)
		publishSnapshotIfNeeded()
	}

	public func updateBrowserTransportState(_ state: BrowserCameraBrowserTransportState) {
		guard browserTransportStatesByTabID[state.tabID] != state else { return }
		browserTransportStatesByTabID[state.tabID] = state
		publishSnapshotIfNeeded()
	}

	public func clearBrowserTransportState(tabID: String) {
		guard browserTransportStatesByTabID.removeValue(forKey: tabID) != nil else { return }
		publishSnapshotIfNeeded()
	}

	private var resolvedPreferredDeviceID: String? {
		if let preferredDeviceID = preferences.preferredDeviceID,
		   availableDevices.contains(where: { $0.id == preferredDeviceID }) {
			return preferredDeviceID
		}
		return automaticPreferredDeviceID
	}

	private var automaticPreferredDeviceID: String? {
		availableDevices.enumerated()
			.min { lhs, rhs in
				let lhsPriority = Self.automaticSelectionPriority(for: lhs.element)
				let rhsPriority = Self.automaticSelectionPriority(for: rhs.element)
				if lhsPriority != rhsPriority {
					return lhsPriority < rhsPriority
				}
				return lhs.offset < rhs.offset
			}?
			.element.id
	}

	private var hasLiveFrameConsumer: Bool {
		consumersByID.values.contains(where: \.requiresLiveFrames)
	}

	private var hasPreviewConsumer: Bool {
		consumersByID.values.contains(where: \.isPreviewConsumer)
	}

	private var wantsManagedCaptureRouting: Bool {
		preferences.routingEnabled && preferences.preferNavigatorCameraWhenPossible
	}

	private var wantsManagedPreview: Bool {
		preferences.previewEnabled && hasPreviewConsumer
	}

	private var hasManagedCaptureDemand: Bool {
		(wantsManagedCaptureRouting && hasLiveFrameConsumer) || wantsManagedPreview
	}

	private var desiredManagedCaptureDeviceID: String? {
		guard hasManagedCaptureDemand else { return nil }
		return resolvedPreferredDeviceID
	}

	private func repairPreferredDeviceIfNeeded() {
		guard let preferredDeviceID = preferences.preferredDeviceID else {
			return
		}
		guard availableDevices.contains(where: { $0.id == preferredDeviceID }) == false else {
			return
		}
		Self.logger.info(
			"Clearing unavailable preferredDeviceID=\(preferredDeviceID, privacy: .public) and returning to automatic selection"
		)
		preferences.preferredDeviceID = nil
		savePreferences()
	}

	private func savePreferences() {
		preferencesStore.savePreferences(preferences)
	}

	private func reconcileManagedCaptureDemand() {
		guard let desiredDeviceID = desiredManagedCaptureDeviceID else {
			if hasManagedCaptureDemand {
				switch managedCaptureState {
				case .starting, .running:
					stopManagedCapture()
				case .idle, .stopping, .failed:
					return
				}
				return
			}

			switch managedCaptureState {
			case .idle:
				return
			case .stopping:
				return
			case .starting, .running, .failed:
				stopManagedCapture()
				return
			}
		}

		switch managedCaptureState {
		case .idle:
			startManagedCapture(deviceID: desiredDeviceID)
		case .starting(let currentDeviceID), .running(let currentDeviceID):
			guard currentDeviceID != desiredDeviceID else { return }
			startManagedCapture(deviceID: desiredDeviceID)
		case .stopping, .failed:
			startManagedCapture(deviceID: desiredDeviceID)
		}
	}

	private func startManagedCapture(deviceID: String) {
		lastManagedCaptureDeviceID = deviceID
		managedCaptureState = .starting(deviceID: deviceID)
		performanceMetrics = .empty
		lastErrorDescription = nil
		Self.logger.info(
			"Starting managed capture deviceID=\(deviceID, privacy: .public) storedPreferredDeviceID=\(self.preferences.preferredDeviceID ?? "automatic", privacy: .public) resolvedPreferredDeviceID=\(self.resolvedPreferredDeviceID ?? "none", privacy: .public) preset=\(self.preferences.preferredFilterPreset.rawValue, privacy: .public) grain=\(self.preferences.preferredGrainPresence.rawValue, privacy: .public) flipped=\(Self.flagDescription(self.preferences.prefersHorizontalFlip), privacy: .public)"
		)
		recordDiagnosticEvent(
			kind: .captureStartRequested,
			detail: Self.captureDetail(
				deviceID: deviceID,
				filterPreset: preferences.preferredFilterPreset,
				grainPresence: preferences.preferredGrainPresence,
				prefersHorizontalFlip: preferences.prefersHorizontalFlip
			)
		)
		captureController.startCapture(
			with: BrowserCameraCaptureConfiguration(
				deviceID: deviceID,
				filterPreset: preferences.preferredFilterPreset,
				grainPresence: preferences.preferredGrainPresence,
				prefersHorizontalFlip: preferences.prefersHorizontalFlip
			)
		)
	}

	private func stopManagedCapture() {
		managedCaptureState = .stopping(previousDeviceID: lastManagedCaptureDeviceID)
		captureController.stopCapture()
	}

	private func syncDerivedState() {
		let hasAvailableDevice = resolvedPreferredDeviceID != nil
		let supportsProcessedOutput = hasAvailableDevice && (
			wantsManagedCaptureRouting || wantsManagedPreview
		)

		outputMode = supportsProcessedOutput
			? .processedNavigatorFeed
			: .unavailable

		if hasManagedCaptureDemand == false {
			switch managedCaptureState {
			case .stopping:
				lifecycleState = .stopping
			case .idle, .starting, .running, .failed:
				lifecycleState = .idle
			}
		}
		else if hasAvailableDevice == false {
			lifecycleState = .failed
		}
		else {
			switch managedCaptureState {
			case .starting, .idle, .stopping:
				lifecycleState = .starting
			case .running:
				lifecycleState = .running
			case .failed:
				lifecycleState = .failed
			}
		}

		if hasAvailableDevice == false {
			healthState = .sourceLost
			lastErrorDescription = "No available video capture devices."
		}
		else if performanceMetrics.realtimeBudgetExceeded {
			healthState = .degraded
			lastErrorDescription = BrowserCameraManagedCaptureState.realtimeBudgetExceededDescription
		}
		else {
			switch managedCaptureState {
			case .failed(let error):
				healthState = Self.healthState(for: error)
				lastErrorDescription = Self.errorDescription(for: error)
			case .idle, .starting, .running, .stopping:
				healthState = .healthy
				lastErrorDescription = nil
			}
		}

		publishSnapshotIfNeeded()
	}

	private static func normalizePreferredManagedOutputMode(
		_ preferredManagedOutputMode: BrowserCameraOutputMode
	) -> BrowserCameraOutputMode {
		switch preferredManagedOutputMode {
		case .directPhysicalCapture, .processedNavigatorFeed, .unavailable:
			.processedNavigatorFeed
		}
	}

	private static func healthState(for error: BrowserCameraCaptureError) -> BrowserCameraHealthState {
		switch error {
		case .pipelineUnavailable:
			.pipelineFallback
		case .sourceUnavailable:
			.sourceLost
		case .authorizationDenied, .sessionConfigurationFailed, .runtimeFailure, .interrupted:
			.degraded
		}
	}

	private static func errorDescription(for error: BrowserCameraCaptureError) -> String {
		switch error {
		case .authorizationDenied:
			"Navigator does not have permission to access the camera."
		case .pipelineUnavailable(let description):
			description
		case .sourceUnavailable(let deviceID):
			"Camera source \(deviceID) is unavailable."
		case .sessionConfigurationFailed(let description),
		     .runtimeFailure(let description),
		     .interrupted(let description):
			description
		}
	}

	private func publishSnapshotIfNeeded() {
		let snapshot = currentSnapshot()
		guard snapshot != lastPublishedSnapshot else { return }
		lastPublishedSnapshot = snapshot
		for observer in snapshotObservers.values {
			observer(snapshot)
		}
	}

	private func publishPreviewFrame() {
		for observer in previewFrameObservers.values {
			observer(previewFrame)
		}
	}

	private func recordDiagnosticEvent(
		kind: BrowserCameraDiagnosticEventKind,
		detail: String?
	) {
		recentDiagnosticEvents.append(
			BrowserCameraDiagnosticEvent(
				kind: kind,
				detail: detail
			)
		)
		let overflow = recentDiagnosticEvents.count - BrowserCameraDiagnosticsDefaults.maxRecentEvents
		if overflow > 0 {
			recentDiagnosticEvents.removeFirst(overflow)
		}
	}

	private func recordMetricEventsIfNeeded(
		from previousMetrics: BrowserCameraPerformanceMetrics,
		to updatedMetrics: BrowserCameraPerformanceMetrics
	) {
		if previousMetrics.firstFrameLatencyMilliseconds == nil,
		   let firstFrameLatencyMilliseconds = updatedMetrics.firstFrameLatencyMilliseconds {
			recordDiagnosticEvent(
				kind: .firstFrameProduced,
				detail: "latencyMs=\(Self.millisecondsDetail(firstFrameLatencyMilliseconds))"
			)
		}

		if previousMetrics.realtimeBudgetExceeded != updatedMetrics.realtimeBudgetExceeded {
			recordDiagnosticEvent(
				kind: updatedMetrics.realtimeBudgetExceeded ? .processingDegraded : .processingRecovered,
				detail: Self.performanceDetail(
					updatedMetrics,
					pipelineRuntimeState: pipelineRuntimeState
				)
			)
		}
	}

	private static func deviceSignatures(_ devices: [BrowserCameraDevice]) -> [String] {
		devices.map { "\($0.id):\($0.name):\($0.isDefault ? "default" : "nondefault")" }
	}

	private static func deviceAvailabilityDetail(for devices: [BrowserCameraDevice]) -> String {
		let deviceIDs = devices.map(\.id).joined(separator: ",")
		return "count=\(devices.count) sourceIDs=\(deviceIDs)"
	}

	private static func consumerDetail(_ consumer: BrowserCameraConsumer) -> String {
		"id=\(consumer.id) kind=\(consumer.kind.rawValue) live=\(flagDescription(consumer.requiresLiveFrames))"
	}

	private static func captureDetail(
		deviceID: String,
		filterPreset: BrowserCameraFilterPreset,
		grainPresence: BrowserCameraPipelineGrainPresence,
		prefersHorizontalFlip: Bool
	) -> String {
		"deviceID=\(deviceID) preset=\(filterPreset.rawValue) grain=\(grainPresence.rawValue) flipped=\(flagDescription(prefersHorizontalFlip))"
	}

	private static func performanceDetail(
		_ metrics: BrowserCameraPerformanceMetrics,
		pipelineRuntimeState: BrowserCameraPipelineRuntimeState?
	) -> String {
		let averageLatency = metrics.averageProcessingLatencyMilliseconds.map(millisecondsDetail) ?? "none"
		var detail =
			"processed=\(metrics.processedFrameCount) dropped=\(metrics.droppedFrameCount) averageLatencyMs=\(averageLatency)"
		if let pipelineRuntimeState {
			detail +=
				" pipeline=\(pipelineRuntimeState.implementation.rawValue) warmup=\(pipelineRuntimeState.warmupProfile.rawValue) grain=\(pipelineRuntimeState.grainPresence.rawValue) filters=\(pipelineRuntimeState.requiredFilterCount)"
		}
		return detail
	}

	private static func millisecondsDetail(_ value: Double) -> String {
		String(format: "%.1f", value)
	}

	private static func browserRoutingDetail(
		tabID: String,
		event: BrowserCameraRoutingEvent
	) -> String {
		let trackID = event.managedTrackID ?? "none"
		let managedDeviceID = event.managedDeviceID ?? "none"
		let requestedDeviceIDs = event.requestedDeviceIDs?.joined(separator: ",") ?? "none"
		let preferredFilterPreset = event.preferredFilterPreset?.rawValue ?? "none"
		var detail =
			"tabID=\(tabID) activeManagedTrackCount=\(event.activeManagedTrackCount) trackID=\(trackID) managedDeviceID=\(managedDeviceID) requestedDeviceIDs=\(requestedDeviceIDs) preset=\(preferredFilterPreset)"
		if let errorDescription = event.errorDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
		   errorDescription.isEmpty == false {
			detail += " error=\(errorDescription)"
		}
		return detail
	}

	private static func diagnosticDetail(for error: BrowserCameraCaptureError) -> String {
		switch error {
		case .authorizationDenied:
			"authorizationDenied"
		case .pipelineUnavailable(let description):
			"pipelineUnavailable description=\(description)"
		case .sourceUnavailable(let deviceID):
			"sourceUnavailable deviceID=\(deviceID)"
		case .sessionConfigurationFailed(let description):
			"sessionConfigurationFailed description=\(description)"
		case .runtimeFailure(let description):
			"runtimeFailure description=\(description)"
		case .interrupted(let description):
			"interrupted description=\(description)"
		}
	}

	private static func flagDescription(_ value: Bool) -> String {
		value ? "true" : "false"
	}

	private static func automaticSelectionPriority(for device: BrowserCameraDevice) -> Int {
		let normalizedName = device.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
		if normalizedName.contains("display") || normalizedName.contains("monitor") {
			return 0
		}
		if device.isDefault {
			return 1
		}
		if normalizedName.contains("continuity") || normalizedName.contains("iphone") {
			return 3
		}
		return 2
	}

	private var browserTransportStates: [BrowserCameraBrowserTransportState] {
		browserTransportStatesByTabID.values.sorted { lhs, rhs in
			lhs.tabID.localizedStandardCompare(rhs.tabID) == .orderedAscending
		}
	}
}

@MainActor
extension BrowserCameraSessionCoordinator: BrowserCameraCaptureControllingDelegate {
	func browserCameraCaptureControllerDidReceiveEvent(_ event: BrowserCameraCaptureEvent) {
		switch event {
		case .didStartRunning(let deviceID):
			lastManagedCaptureDeviceID = deviceID
			managedCaptureState = .running(deviceID: deviceID)
			recordDiagnosticEvent(
				kind: .captureStarted,
				detail: "deviceID=\(deviceID)"
			)
		case .didUpdateMetrics(let metrics):
			let previousMetrics = performanceMetrics
			performanceMetrics = metrics
			recordMetricEventsIfNeeded(
				from: previousMetrics,
				to: metrics
			)
		case .didUpdatePipelineRuntimeState(let updatedPipelineRuntimeState):
			pipelineRuntimeState = updatedPipelineRuntimeState
		case .didStop:
			performanceMetrics = .empty
			pipelineRuntimeState = nil
			previewFrame = nil
			publishPreviewFrame()
			recordDiagnosticEvent(
				kind: .captureStopped,
				detail: "deviceID=\(lastManagedCaptureDeviceID ?? "none")"
			)
			if let desiredManagedCaptureDeviceID {
				startManagedCapture(deviceID: desiredManagedCaptureDeviceID)
			}
			else {
				managedCaptureState = .idle
			}
		case .didFail(let error):
			pipelineRuntimeState = nil
			previewFrame = nil
			publishPreviewFrame()
			managedCaptureState = .failed(error)
			recordDiagnosticEvent(
				kind: .captureFailed,
				detail: Self.diagnosticDetail(for: error)
			)
		case .sourceWasLost(let deviceID):
			performanceMetrics = .empty
			pipelineRuntimeState = nil
			previewFrame = nil
			publishPreviewFrame()
			managedCaptureState = .failed(.sourceUnavailable(deviceID: deviceID))
			recordDiagnosticEvent(
				kind: .sourceLost,
				detail: "deviceID=\(deviceID)"
			)
			availableDevices = deviceProvider.availableDevices()
			repairPreferredDeviceIfNeeded()
			reconcileManagedCaptureDemand()
		}

		syncDerivedState()
	}

	func browserCameraCaptureControllerDidOutputPreviewFrame(_ previewFrame: BrowserCameraPreviewFrame?) {
		if let previewFrame {
			Self.logger.debug(
				"Received preview frame size=\(previewFrame.image.width)x\(previewFrame.image.height) activePreviewConsumers=\(self.currentDebugSummary().activePreviewConsumerIDs.count)"
			)
		}
		else {
			Self.logger.debug("Received nil preview frame")
		}
		self.previewFrame = previewFrame?.image
		publishPreviewFrame()
	}

}

@MainActor
struct LiveBrowserCameraDeviceProvider: BrowserCameraDeviceProviding {
	func availableDevices() -> [BrowserCameraDevice] {
		let discoverySession = AVCaptureDevice.DiscoverySession(
			deviceTypes: [
				.builtInWideAngleCamera,
				.external,
			],
			mediaType: .video,
			position: .unspecified
		)

		let devices = discoverySession.devices
		let defaultDeviceID = AVCaptureDevice.default(for: .video)?.uniqueID
		return devices.map { device in
			BrowserCameraDevice(
				id: device.uniqueID,
				name: device.localizedName,
				isDefault: device.uniqueID == defaultDeviceID
			)
		}
	}
}

@MainActor
struct UserDefaultsBrowserCameraPreferencesStore: BrowserCameraPreferencesStoring {
	private enum Keys {
		static let routingEnabled = "navigator.browserCamera.routingEnabled"
		static let preferredDeviceID = "navigator.browserCamera.preferredDeviceID"
		static let preferNavigatorCameraWhenPossible = "navigator.browserCamera.preferNavigatorCameraWhenPossible"
		static let preferredFilterPreset = "navigator.browserCamera.preferredFilterPreset"
		static let preferredGrainPresence = "navigator.browserCamera.preferredGrainPresence"
		static let prefersHorizontalFlip = "navigator.browserCamera.prefersHorizontalFlip"
		static let previewEnabled = "navigator.browserCamera.previewEnabled"
	}

	static let allKeys = [
		Keys.routingEnabled,
		Keys.preferredDeviceID,
		Keys.preferNavigatorCameraWhenPossible,
		Keys.preferredFilterPreset,
		Keys.preferredGrainPresence,
		Keys.prefersHorizontalFlip,
		Keys.previewEnabled,
	]

	private let defaults: UserDefaults

	init(defaults: UserDefaults = .standard) {
		self.defaults = defaults
	}

	func loadPreferences() -> BrowserCameraPreferences {
		let legacyRawPreset = defaults.string(forKey: Keys.preferredFilterPreset)
		let preferredFilterPreset = BrowserCameraFilterPreset.normalized(rawValue: legacyRawPreset ?? "")
		let preferredGrainPresence = resolvedPreferredGrainPresence(
			storedValue: defaults.string(forKey: Keys.preferredGrainPresence),
			filterPreset: preferredFilterPreset,
			legacyRawPreset: legacyRawPreset
		)
		return BrowserCameraPreferences(
			routingEnabled: defaults.object(forKey: Keys.routingEnabled) as? Bool ?? true,
			preferNavigatorCameraWhenPossible: defaults.object(
				forKey: Keys.preferNavigatorCameraWhenPossible
			) as? Bool ?? true,
			preferredSourceID: defaults.string(forKey: Keys.preferredDeviceID),
			preferredFilterPreset: preferredFilterPreset,
			preferredGrainPresence: preferredGrainPresence,
			prefersHorizontalFlip: defaults.object(forKey: Keys.prefersHorizontalFlip) as? Bool ?? false,
			previewEnabled: defaults.object(forKey: Keys.previewEnabled) as? Bool ?? false
		)
	}

	func savePreferences(_ preferences: BrowserCameraPreferences) {
		defaults.set(preferences.routingEnabled, forKey: Keys.routingEnabled)
		defaults.set(preferences.preferredDeviceID, forKey: Keys.preferredDeviceID)
		defaults.set(
			preferences.preferNavigatorCameraWhenPossible,
			forKey: Keys.preferNavigatorCameraWhenPossible
		)
		defaults.set(preferences.preferredFilterPreset.rawValue, forKey: Keys.preferredFilterPreset)
		defaults.set(preferences.preferredGrainPresence.rawValue, forKey: Keys.preferredGrainPresence)
		defaults.set(preferences.prefersHorizontalFlip, forKey: Keys.prefersHorizontalFlip)
		defaults.set(preferences.previewEnabled, forKey: Keys.previewEnabled)
	}

	private func resolvedPreferredGrainPresence(
		storedValue: String?,
		filterPreset: BrowserCameraFilterPreset,
		legacyRawPreset: String?
	) -> BrowserCameraPipelineGrainPresence {
		if let storedValue,
		   let storedPresence = BrowserCameraPipelineGrainPresence(rawValue: storedValue) {
			return storedPresence
		}

		switch legacyRawPreset {
		case "mononoke":
			return .normal
		case "mononokeFront", "vertichrome":
			return .high
		case "folia":
			return .normal
		case "supergold", "none", nil:
			return .none
		default:
			switch filterPreset {
			case .none, .supergold:
				return .none
			case .monochrome, .dither, .folia, .tonachrome, .bubblegum, .darkroom, .glowInTheDark, .habenero:
				return .normal
			}
		}
	}
}
