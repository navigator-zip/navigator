import Foundation

public enum BrowserCameraFilterPreset: String, Codable, CaseIterable, Sendable {
	case none
	case monochrome
	case dither
	case folia
	case supergold
	case tonachrome
	case bubblegum
	case darkroom
	case glowInTheDark
	case habenero

	public init(from decoder: any Decoder) throws {
		let container = try decoder.singleValueContainer()
		let rawValue = try container.decode(String.self)
		self = Self.normalized(rawValue: rawValue)
	}

	public func encode(to encoder: any Encoder) throws {
		var container = encoder.singleValueContainer()
		try container.encode(rawValue)
	}

	public static func normalized(rawValue: String) -> Self {
		switch rawValue {
		case monochrome.rawValue, "mononoke", "mononokeFront":
			.monochrome
		case dither.rawValue:
			.dither
		case folia.rawValue:
			.folia
		case supergold.rawValue:
			.supergold
		case tonachrome.rawValue, "vertichrome":
			.tonachrome
		case bubblegum.rawValue:
			.bubblegum
		case darkroom.rawValue:
			.darkroom
		case glowInTheDark.rawValue:
			.glowInTheDark
		case habenero.rawValue:
			.habenero
		default:
			.none
		}
	}
}

public extension BrowserCameraFilterPreset {
	static let mononoke = Self.monochrome
	static let vertichrome = Self.tonachrome
}

public enum BrowserCameraConsumerKind: String, Codable, CaseIterable, Sendable {
	case browserTabCapture
	case browserPreview
	case menuBarPreview

	public var requiresLiveFrames: Bool {
		switch self {
		case .browserTabCapture:
			true
		case .browserPreview, .menuBarPreview:
			false
		}
	}

	public var isPreviewConsumer: Bool {
		!requiresLiveFrames
	}
}

public enum BrowserCameraLifecycleState: String, Codable, CaseIterable, Sendable {
	case idle
	case preparing
	case starting
	case running
	case stopping
	case failed
}

public enum BrowserCameraHealthState: String, Codable, CaseIterable, Sendable {
	case healthy
	case degraded
	case sourceLost
	case pipelineFallback
}

public enum BrowserCameraOutputMode: String, Codable, CaseIterable, Sendable {
	case directPhysicalCapture
	case processedNavigatorFeed
	case unavailable
}

public struct BrowserCameraSource: Identifiable, Codable, Equatable, Hashable, Sendable {
	public let id: String
	public let name: String
	public let isDefault: Bool

	public init(
		id: String,
		name: String,
		isDefault: Bool
	) {
		self.id = id
		self.name = name
		self.isDefault = isDefault
	}
}

public struct BrowserCameraRoutingSettings: Codable, Equatable, Hashable, Sendable {
	private enum CodingKeys: String, CodingKey {
		case routingEnabled
		case preferNavigatorCameraWhenPossible
		case preferredSourceID
		case preferredFilterPreset
		case preferredGrainPresence
		case prefersHorizontalFlip
		case previewEnabled
	}

	public static let defaults = Self(
		routingEnabled: true,
		preferNavigatorCameraWhenPossible: true,
		preferredSourceID: nil,
		preferredFilterPreset: .none,
		preferredGrainPresence: .none,
		prefersHorizontalFlip: false,
		previewEnabled: false
	)

	public var routingEnabled: Bool
	public var preferNavigatorCameraWhenPossible: Bool
	public var preferredSourceID: String?
	public var preferredFilterPreset: BrowserCameraFilterPreset
	public var preferredGrainPresence: BrowserCameraPipelineGrainPresence
	public var prefersHorizontalFlip: Bool
	public var previewEnabled: Bool

	public var preferredDeviceID: String? {
		get { preferredSourceID }
		set { preferredSourceID = newValue }
	}

	public init(
		routingEnabled: Bool,
		preferNavigatorCameraWhenPossible: Bool,
		preferredSourceID: String?,
		preferredFilterPreset: BrowserCameraFilterPreset,
		preferredGrainPresence: BrowserCameraPipelineGrainPresence,
		prefersHorizontalFlip: Bool,
		previewEnabled: Bool
	) {
		self.routingEnabled = routingEnabled
		self.preferNavigatorCameraWhenPossible = preferNavigatorCameraWhenPossible
		self.preferredSourceID = preferredSourceID
		self.preferredFilterPreset = preferredFilterPreset
		self.preferredGrainPresence = preferredGrainPresence
		self.prefersHorizontalFlip = prefersHorizontalFlip
		self.previewEnabled = previewEnabled
	}

	public init(
		routingEnabled: Bool,
		preferNavigatorCameraWhenPossible: Bool,
		preferredSourceID: String?,
		preferredFilterPreset: BrowserCameraFilterPreset,
		prefersHorizontalFlip: Bool,
		previewEnabled: Bool
	) {
		self.init(
			routingEnabled: routingEnabled,
			preferNavigatorCameraWhenPossible: preferNavigatorCameraWhenPossible,
			preferredSourceID: preferredSourceID,
			preferredFilterPreset: preferredFilterPreset,
			preferredGrainPresence: .none,
			prefersHorizontalFlip: prefersHorizontalFlip,
			previewEnabled: previewEnabled
		)
	}

	public init(
		routingEnabled: Bool,
		preferNavigatorCameraWhenPossible: Bool,
		preferredSourceID: String?,
		preferredFilterPreset: BrowserCameraFilterPreset,
		previewEnabled: Bool
	) {
		self.init(
			routingEnabled: routingEnabled,
			preferNavigatorCameraWhenPossible: preferNavigatorCameraWhenPossible,
			preferredSourceID: preferredSourceID,
			preferredFilterPreset: preferredFilterPreset,
			preferredGrainPresence: .none,
			prefersHorizontalFlip: false,
			previewEnabled: previewEnabled
		)
	}

	public init() {
		self = .defaults
	}

	public init(
		routingEnabled: Bool,
		preferredDeviceID: String?,
		preferNavigatorCameraWhenPossible: Bool
	) {
		self.init(
			routingEnabled: routingEnabled,
			preferNavigatorCameraWhenPossible: preferNavigatorCameraWhenPossible,
			preferredSourceID: preferredDeviceID,
			preferredFilterPreset: .none,
			preferredGrainPresence: .none,
			prefersHorizontalFlip: false,
			previewEnabled: false
		)
	}

	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		routingEnabled = try container.decode(Bool.self, forKey: .routingEnabled)
		preferNavigatorCameraWhenPossible = try container.decode(
			Bool.self,
			forKey: .preferNavigatorCameraWhenPossible
		)
		preferredSourceID = try container.decodeIfPresent(String.self, forKey: .preferredSourceID)
		preferredFilterPreset = try container.decode(
			BrowserCameraFilterPreset.self,
			forKey: .preferredFilterPreset
		)
		preferredGrainPresence = try container.decodeIfPresent(
			BrowserCameraPipelineGrainPresence.self,
			forKey: .preferredGrainPresence
		) ?? .none
		prefersHorizontalFlip = try container.decodeIfPresent(
			Bool.self,
			forKey: .prefersHorizontalFlip
		) ?? false
		previewEnabled = try container.decode(Bool.self, forKey: .previewEnabled)
	}

	public func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(routingEnabled, forKey: .routingEnabled)
		try container.encode(
			preferNavigatorCameraWhenPossible,
			forKey: .preferNavigatorCameraWhenPossible
		)
		try container.encodeIfPresent(preferredSourceID, forKey: .preferredSourceID)
		try container.encode(preferredFilterPreset, forKey: .preferredFilterPreset)
		try container.encode(preferredGrainPresence, forKey: .preferredGrainPresence)
		try container.encode(prefersHorizontalFlip, forKey: .prefersHorizontalFlip)
		try container.encode(previewEnabled, forKey: .previewEnabled)
	}
}

public typealias BrowserCameraDevice = BrowserCameraSource
public typealias BrowserCameraPreferences = BrowserCameraRoutingSettings

public struct BrowserCameraConsumer: Identifiable, Codable, Equatable, Hashable, Sendable {
	public let id: String
	public let kind: BrowserCameraConsumerKind
	public let requiresLiveFrames: Bool

	public var isPreviewConsumer: Bool {
		!requiresLiveFrames
	}

	public init(
		id: String,
		kind: BrowserCameraConsumerKind,
		requiresLiveFrames: Bool
	) {
		self.id = id
		self.kind = kind
		self.requiresLiveFrames = requiresLiveFrames
	}
}

public struct BrowserCameraManagedFramePayload: Codable, Equatable, Hashable, Sendable {
	public let sequence: UInt64
	public let width: Int
	public let height: Int
	public let imageDataURL: String

	public init(
		sequence: UInt64,
		width: Int,
		height: Int,
		imageDataURL: String
	) {
		self.sequence = sequence
		self.width = width
		self.height = height
		self.imageDataURL = imageDataURL
	}
}

public struct BrowserCameraRoutingConfiguration: Codable, Equatable, Hashable, Sendable {
	public let isRoutingEnabled: Bool
	public let preferredDeviceID: String?
	public let preferNavigatorCameraWhenPossible: Bool
	public let preferredFilterPreset: BrowserCameraFilterPreset
	public let preferredGrainPresence: BrowserCameraPipelineGrainPresence
	public let prefersHorizontalFlip: Bool
	public let previewEnabled: Bool
	public let outputMode: BrowserCameraOutputMode

	public var settings: BrowserCameraRoutingSettings {
		BrowserCameraRoutingSettings(
			routingEnabled: isRoutingEnabled,
			preferNavigatorCameraWhenPossible: preferNavigatorCameraWhenPossible,
			preferredSourceID: preferredDeviceID,
			preferredFilterPreset: preferredFilterPreset,
			preferredGrainPresence: preferredGrainPresence,
			prefersHorizontalFlip: prefersHorizontalFlip,
			previewEnabled: previewEnabled
		)
	}

	public init(
		isRoutingEnabled: Bool,
		preferredDeviceID: String?,
		preferNavigatorCameraWhenPossible: Bool,
		preferredFilterPreset: BrowserCameraFilterPreset,
		preferredGrainPresence: BrowserCameraPipelineGrainPresence,
		prefersHorizontalFlip: Bool,
		previewEnabled: Bool,
		outputMode: BrowserCameraOutputMode
	) {
		self.isRoutingEnabled = isRoutingEnabled
		self.preferredDeviceID = preferredDeviceID
		self.preferNavigatorCameraWhenPossible = preferNavigatorCameraWhenPossible
		self.preferredFilterPreset = preferredFilterPreset
		self.preferredGrainPresence = preferredGrainPresence
		self.prefersHorizontalFlip = prefersHorizontalFlip
		self.previewEnabled = previewEnabled
		self.outputMode = outputMode
	}

	public init(
		isRoutingEnabled: Bool,
		preferredDeviceID: String?,
		preferNavigatorCameraWhenPossible: Bool,
		preferredFilterPreset: BrowserCameraFilterPreset,
		prefersHorizontalFlip: Bool,
		previewEnabled: Bool,
		outputMode: BrowserCameraOutputMode
	) {
		self.init(
			isRoutingEnabled: isRoutingEnabled,
			preferredDeviceID: preferredDeviceID,
			preferNavigatorCameraWhenPossible: preferNavigatorCameraWhenPossible,
			preferredFilterPreset: preferredFilterPreset,
			preferredGrainPresence: .none,
			prefersHorizontalFlip: prefersHorizontalFlip,
			previewEnabled: previewEnabled,
			outputMode: outputMode
		)
	}

	public init(
		isRoutingEnabled: Bool,
		preferredDeviceID: String?,
		preferNavigatorCameraWhenPossible: Bool,
		preferredFilterPreset: BrowserCameraFilterPreset,
		previewEnabled: Bool,
		outputMode: BrowserCameraOutputMode
	) {
		self.init(
			isRoutingEnabled: isRoutingEnabled,
			preferredDeviceID: preferredDeviceID,
			preferNavigatorCameraWhenPossible: preferNavigatorCameraWhenPossible,
			preferredFilterPreset: preferredFilterPreset,
			preferredGrainPresence: .none,
			prefersHorizontalFlip: false,
			previewEnabled: previewEnabled,
			outputMode: outputMode
		)
	}

	public init(
		isRoutingEnabled: Bool,
		preferredDeviceID: String?,
		preferNavigatorCameraWhenPossible: Bool,
		outputMode: BrowserCameraOutputMode
	) {
		self.init(
			isRoutingEnabled: isRoutingEnabled,
			preferredDeviceID: preferredDeviceID,
			preferNavigatorCameraWhenPossible: preferNavigatorCameraWhenPossible,
			preferredFilterPreset: .none,
			preferredGrainPresence: .none,
			prefersHorizontalFlip: false,
			previewEnabled: false,
			outputMode: outputMode
		)
	}

	public init(
		settings: BrowserCameraRoutingSettings,
		outputMode: BrowserCameraOutputMode
	) {
		self.init(
			isRoutingEnabled: settings.routingEnabled,
			preferredDeviceID: settings.preferredSourceID,
			preferNavigatorCameraWhenPossible: settings.preferNavigatorCameraWhenPossible,
			preferredFilterPreset: settings.preferredFilterPreset,
			preferredGrainPresence: settings.preferredGrainPresence,
			prefersHorizontalFlip: settings.prefersHorizontalFlip,
			previewEnabled: settings.previewEnabled,
			outputMode: outputMode
		)
	}
}

public struct BrowserCameraPerformanceMetrics: Codable, Equatable, Hashable, Sendable {
	private enum CodingKeys: String, CodingKey {
		case processedFrameCount
		case droppedFrameCount
		case firstFrameLatencyMilliseconds
		case averageProcessingLatencyMilliseconds
		case lastProcessingLatencyMilliseconds
		case realtimeBudgetExceeded
	}

	public static let empty = Self(
		processedFrameCount: 0,
		droppedFrameCount: 0,
		firstFrameLatencyMilliseconds: nil,
		averageProcessingLatencyMilliseconds: nil,
		lastProcessingLatencyMilliseconds: nil,
		realtimeBudgetExceeded: false
	)

	public let processedFrameCount: Int
	public let droppedFrameCount: Int
	public let firstFrameLatencyMilliseconds: Double?
	public let averageProcessingLatencyMilliseconds: Double?
	public let lastProcessingLatencyMilliseconds: Double?
	public let realtimeBudgetExceeded: Bool

	public init(
		processedFrameCount: Int,
		droppedFrameCount: Int,
		firstFrameLatencyMilliseconds: Double?,
		averageProcessingLatencyMilliseconds: Double?,
		lastProcessingLatencyMilliseconds: Double?,
		realtimeBudgetExceeded: Bool
	) {
		self.processedFrameCount = processedFrameCount
		self.droppedFrameCount = droppedFrameCount
		self.firstFrameLatencyMilliseconds = firstFrameLatencyMilliseconds
		self.averageProcessingLatencyMilliseconds = averageProcessingLatencyMilliseconds
		self.lastProcessingLatencyMilliseconds = lastProcessingLatencyMilliseconds
		self.realtimeBudgetExceeded = realtimeBudgetExceeded
	}

	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		processedFrameCount = try container.decodeIfPresent(Int.self, forKey: .processedFrameCount) ?? 0
		droppedFrameCount = try container.decodeIfPresent(Int.self, forKey: .droppedFrameCount) ?? 0
		firstFrameLatencyMilliseconds = try container.decodeIfPresent(
			Double.self,
			forKey: .firstFrameLatencyMilliseconds
		)
		averageProcessingLatencyMilliseconds = try container.decodeIfPresent(
			Double.self,
			forKey: .averageProcessingLatencyMilliseconds
		)
		lastProcessingLatencyMilliseconds = try container.decodeIfPresent(
			Double.self,
			forKey: .lastProcessingLatencyMilliseconds
		)
		realtimeBudgetExceeded = try container.decodeIfPresent(
			Bool.self,
			forKey: .realtimeBudgetExceeded
		) ?? false
	}

	public func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(processedFrameCount, forKey: .processedFrameCount)
		try container.encode(droppedFrameCount, forKey: .droppedFrameCount)
		try container.encodeIfPresent(firstFrameLatencyMilliseconds, forKey: .firstFrameLatencyMilliseconds)
		try container.encodeIfPresent(
			averageProcessingLatencyMilliseconds,
			forKey: .averageProcessingLatencyMilliseconds
		)
		try container.encodeIfPresent(
			lastProcessingLatencyMilliseconds,
			forKey: .lastProcessingLatencyMilliseconds
		)
		try container.encode(realtimeBudgetExceeded, forKey: .realtimeBudgetExceeded)
	}
}

public struct BrowserCameraDebugSummary: Codable, Equatable, Hashable, Sendable {
	public let lifecycleState: BrowserCameraLifecycleState
	public let healthState: BrowserCameraHealthState
	public let outputMode: BrowserCameraOutputMode
	public let selectedSourceID: String?
	public let selectedSourceName: String?
	public let selectedFilterPreset: BrowserCameraFilterPreset
	public let pipelineRuntimeState: BrowserCameraPipelineRuntimeState?
	public let managedRoutingSummary: BrowserCameraManagedRoutingSummary
	public let activeLiveFrameConsumerIDs: [String]
	public let activePreviewConsumerIDs: [String]
	public let performanceMetrics: BrowserCameraPerformanceMetrics
	public let lastErrorDescription: String?
	public let browserTransportStates: [BrowserCameraBrowserTransportState]
	public let recentDiagnosticEvents: [BrowserCameraDiagnosticEvent]

	public init(
		lifecycleState: BrowserCameraLifecycleState,
		healthState: BrowserCameraHealthState,
		outputMode: BrowserCameraOutputMode,
		selectedSourceID: String?,
		selectedSourceName: String?,
		selectedFilterPreset: BrowserCameraFilterPreset,
		pipelineRuntimeState: BrowserCameraPipelineRuntimeState? = nil,
		activeLiveFrameConsumerIDs: [String],
		activePreviewConsumerIDs: [String],
		managedRoutingSummary: BrowserCameraManagedRoutingSummary,
		performanceMetrics: BrowserCameraPerformanceMetrics,
		lastErrorDescription: String?
	) {
		self.init(
			lifecycleState: lifecycleState,
			healthState: healthState,
			outputMode: outputMode,
			selectedSourceID: selectedSourceID,
			selectedSourceName: selectedSourceName,
			selectedFilterPreset: selectedFilterPreset,
			pipelineRuntimeState: pipelineRuntimeState,
			activeLiveFrameConsumerIDs: activeLiveFrameConsumerIDs,
			activePreviewConsumerIDs: activePreviewConsumerIDs,
			managedRoutingSummary: managedRoutingSummary,
			performanceMetrics: performanceMetrics,
			lastErrorDescription: lastErrorDescription,
			browserTransportStates: [],
			recentDiagnosticEvents: []
		)
	}

	public init(
		lifecycleState: BrowserCameraLifecycleState,
		healthState: BrowserCameraHealthState,
		outputMode: BrowserCameraOutputMode,
		selectedSourceID: String?,
		selectedSourceName: String?,
		selectedFilterPreset: BrowserCameraFilterPreset,
		pipelineRuntimeState: BrowserCameraPipelineRuntimeState? = nil,
		activeLiveFrameConsumerIDs: [String],
		activePreviewConsumerIDs: [String],
		performanceMetrics: BrowserCameraPerformanceMetrics,
		lastErrorDescription: String?
	) {
		self.init(
			lifecycleState: lifecycleState,
			healthState: healthState,
			outputMode: outputMode,
			selectedSourceID: selectedSourceID,
			selectedSourceName: selectedSourceName,
			selectedFilterPreset: selectedFilterPreset,
			pipelineRuntimeState: pipelineRuntimeState,
			activeLiveFrameConsumerIDs: activeLiveFrameConsumerIDs,
			activePreviewConsumerIDs: activePreviewConsumerIDs,
			managedRoutingSummary: Self.inferredManagedRoutingSummary(
				healthState: healthState,
				outputMode: outputMode
			),
			performanceMetrics: performanceMetrics,
			lastErrorDescription: lastErrorDescription,
			browserTransportStates: [],
			recentDiagnosticEvents: []
		)
	}

	public init(
		lifecycleState: BrowserCameraLifecycleState,
		healthState: BrowserCameraHealthState,
		outputMode: BrowserCameraOutputMode,
		selectedSourceID: String?,
		selectedSourceName: String?,
		selectedFilterPreset: BrowserCameraFilterPreset,
		pipelineRuntimeState: BrowserCameraPipelineRuntimeState? = nil,
		activeLiveFrameConsumerIDs: [String],
		activePreviewConsumerIDs: [String],
		managedRoutingSummary: BrowserCameraManagedRoutingSummary,
		performanceMetrics: BrowserCameraPerformanceMetrics,
		lastErrorDescription: String?,
		browserTransportStates: [BrowserCameraBrowserTransportState] = [],
		recentDiagnosticEvents: [BrowserCameraDiagnosticEvent]
	) {
		self.lifecycleState = lifecycleState
		self.healthState = healthState
		self.outputMode = outputMode
		self.selectedSourceID = selectedSourceID
		self.selectedSourceName = selectedSourceName
		self.selectedFilterPreset = selectedFilterPreset
		self.pipelineRuntimeState = pipelineRuntimeState
		self.managedRoutingSummary = managedRoutingSummary
		self.activeLiveFrameConsumerIDs = activeLiveFrameConsumerIDs
		self.activePreviewConsumerIDs = activePreviewConsumerIDs
		self.performanceMetrics = performanceMetrics
		self.lastErrorDescription = lastErrorDescription
		self.browserTransportStates = browserTransportStates
		self.recentDiagnosticEvents = recentDiagnosticEvents
	}

	public init(
		lifecycleState: BrowserCameraLifecycleState,
		healthState: BrowserCameraHealthState,
		outputMode: BrowserCameraOutputMode,
		selectedSourceID: String?,
		selectedSourceName: String?,
		selectedFilterPreset: BrowserCameraFilterPreset,
		activeLiveFrameConsumerIDs: [String],
		activePreviewConsumerIDs: [String],
		performanceMetrics: BrowserCameraPerformanceMetrics,
		lastErrorDescription: String?,
		browserTransportStates: [BrowserCameraBrowserTransportState] = [],
		recentDiagnosticEvents: [BrowserCameraDiagnosticEvent]
	) {
		self.init(
			lifecycleState: lifecycleState,
			healthState: healthState,
			outputMode: outputMode,
			selectedSourceID: selectedSourceID,
			selectedSourceName: selectedSourceName,
			selectedFilterPreset: selectedFilterPreset,
			activeLiveFrameConsumerIDs: activeLiveFrameConsumerIDs,
			activePreviewConsumerIDs: activePreviewConsumerIDs,
			managedRoutingSummary: Self.inferredManagedRoutingSummary(
				healthState: healthState,
				outputMode: outputMode
			),
			performanceMetrics: performanceMetrics,
			lastErrorDescription: lastErrorDescription,
			browserTransportStates: browserTransportStates,
			recentDiagnosticEvents: recentDiagnosticEvents
		)
	}

	private static func inferredManagedRoutingSummary(
		healthState: BrowserCameraHealthState,
		outputMode: BrowserCameraOutputMode
	) -> BrowserCameraManagedRoutingSummary {
		let availability: BrowserCameraManagedRoutingAvailability = switch outputMode {
		case .directPhysicalCapture:
			.directPhysicalCapture
		case .unavailable:
			.routingDisabled
		case .processedNavigatorFeed:
			switch healthState {
			case .healthy:
				.available
			case .sourceLost:
				.sourceLost
			case .degraded:
				.degraded
			case .pipelineFallback:
				.pipelineFallback
			}
		}

		let failClosedOnManagedVideoRequest = switch availability {
		case .degraded, .pipelineFallback, .sourceLost:
			true
		case .available, .routingDisabled, .navigatorPreferenceDisabled, .noAvailableSource,
		     .directPhysicalCapture, .publisherUnavailable:
			false
		}

		return BrowserCameraManagedRoutingSummary(
			availability: availability,
			genericVideoUsesManagedOutput: availability == .available,
			failClosedOnManagedVideoRequest: failClosedOnManagedVideoRequest,
			exposesManagedDeviceIdentity: availability == .available
				&& outputMode == .processedNavigatorFeed
		)
	}
}

public struct BrowserCameraSessionSnapshot: Codable, Equatable, Sendable {
	private enum CodingKeys: String, CodingKey {
		case lifecycleState
		case healthState
		case outputMode
		case routingSettings
		case availableSources
		case activeConsumersByID
		case activeConsumerKindsByID
		case performanceMetrics
		case lastErrorDescription
		case pipelineRuntimeState
		case browserTransportStates
		case recentDiagnosticEvents
	}

	public let lifecycleState: BrowserCameraLifecycleState
	public let healthState: BrowserCameraHealthState
	public let outputMode: BrowserCameraOutputMode
	public let routingSettings: BrowserCameraRoutingSettings
	public let availableSources: [BrowserCameraSource]
	public let activeConsumersByID: [String: BrowserCameraConsumer]
	public let performanceMetrics: BrowserCameraPerformanceMetrics
	public let lastErrorDescription: String?
	public let pipelineRuntimeState: BrowserCameraPipelineRuntimeState?
	public let browserTransportStates: [BrowserCameraBrowserTransportState]
	public let recentDiagnosticEvents: [BrowserCameraDiagnosticEvent]

	public var activeConsumerKindsByID: [String: BrowserCameraConsumerKind] {
		activeConsumersByID.reduce(into: [:]) { partialResult, entry in
			partialResult[entry.key] = entry.value.kind
		}
	}

	public var routingConfiguration: BrowserCameraRoutingConfiguration {
		BrowserCameraRoutingConfiguration(
			settings: routingSettings,
			outputMode: outputMode
		)
	}

	public var availableDevices: [BrowserCameraDevice] {
		availableSources
	}

	public var activeConsumers: [BrowserCameraConsumer] {
		sortedConsumers
	}

	public var activeLiveFrameConsumerIDs: [String] {
		sortedConsumerIDs(matching: { $0.requiresLiveFrames })
	}

	public var activePreviewConsumerIDs: [String] {
		sortedConsumerIDs(matching: { $0.isPreviewConsumer })
	}

	public var liveFrameConsumerCount: Int {
		activeLiveFrameConsumerIDs.count
	}

	public var previewConsumerCount: Int {
		activePreviewConsumerIDs.count
	}

	public var hasActiveConsumers: Bool {
		!activeConsumersByID.isEmpty
	}

	public var debugSummary: BrowserCameraDebugSummary {
		let selectedSourceID = routingSettings.preferredSourceID
		return BrowserCameraDebugSummary(
			lifecycleState: lifecycleState,
			healthState: healthState,
			outputMode: outputMode,
			selectedSourceID: selectedSourceID,
			selectedSourceName: availableSources.first(where: { $0.id == selectedSourceID })?.name,
			selectedFilterPreset: routingSettings.preferredFilterPreset,
			pipelineRuntimeState: pipelineRuntimeState,
			activeLiveFrameConsumerIDs: activeLiveFrameConsumerIDs,
			activePreviewConsumerIDs: activePreviewConsumerIDs,
			managedRoutingSummary: managedRoutingSummary,
			performanceMetrics: performanceMetrics,
			lastErrorDescription: lastErrorDescription,
			browserTransportStates: browserTransportStates,
			recentDiagnosticEvents: recentDiagnosticEvents
		)
	}

	public init(
		lifecycleState: BrowserCameraLifecycleState,
		healthState: BrowserCameraHealthState,
		outputMode: BrowserCameraOutputMode,
		routingSettings: BrowserCameraRoutingSettings,
		availableSources: [BrowserCameraSource],
		activeConsumersByID: [String: BrowserCameraConsumer],
		performanceMetrics: BrowserCameraPerformanceMetrics,
		lastErrorDescription: String?,
		pipelineRuntimeState: BrowserCameraPipelineRuntimeState? = nil
	) {
		self.init(
			lifecycleState: lifecycleState,
			healthState: healthState,
			outputMode: outputMode,
			routingSettings: routingSettings,
			availableSources: availableSources,
			activeConsumersByID: activeConsumersByID,
			performanceMetrics: performanceMetrics,
			lastErrorDescription: lastErrorDescription,
			pipelineRuntimeState: pipelineRuntimeState,
			browserTransportStates: [],
			recentDiagnosticEvents: []
		)
	}

	public init(
		lifecycleState: BrowserCameraLifecycleState,
		healthState: BrowserCameraHealthState,
		outputMode: BrowserCameraOutputMode,
		routingSettings: BrowserCameraRoutingSettings,
		availableSources: [BrowserCameraSource],
		activeConsumersByID: [String: BrowserCameraConsumer],
		performanceMetrics: BrowserCameraPerformanceMetrics,
		lastErrorDescription: String?,
		pipelineRuntimeState: BrowserCameraPipelineRuntimeState? = nil,
		browserTransportStates: [BrowserCameraBrowserTransportState] = [],
		recentDiagnosticEvents: [BrowserCameraDiagnosticEvent]
	) {
		self.lifecycleState = lifecycleState
		self.healthState = healthState
		self.outputMode = outputMode
		self.routingSettings = routingSettings
		self.availableSources = availableSources
		self.activeConsumersByID = Self.normalizeActiveConsumers(activeConsumersByID)
		self.performanceMetrics = performanceMetrics
		self.lastErrorDescription = lastErrorDescription
		self.pipelineRuntimeState = pipelineRuntimeState
		self.browserTransportStates = Self.normalizeBrowserTransportStates(browserTransportStates)
		self.recentDiagnosticEvents = recentDiagnosticEvents
	}

	public init(
		lifecycleState: BrowserCameraLifecycleState,
		healthState: BrowserCameraHealthState,
		outputMode: BrowserCameraOutputMode,
		routingSettings: BrowserCameraRoutingSettings,
		availableSources: [BrowserCameraSource],
		activeConsumersByID: [String: BrowserCameraConsumer],
		performanceMetrics: BrowserCameraPerformanceMetrics,
		lastErrorDescription: String?
	) {
		self.init(
			lifecycleState: lifecycleState,
			healthState: healthState,
			outputMode: outputMode,
			routingSettings: routingSettings,
			availableSources: availableSources,
			activeConsumersByID: activeConsumersByID,
			performanceMetrics: performanceMetrics,
			lastErrorDescription: lastErrorDescription,
			pipelineRuntimeState: nil,
			browserTransportStates: [],
			recentDiagnosticEvents: []
		)
	}

	public init(
		lifecycleState: BrowserCameraLifecycleState,
		healthState: BrowserCameraHealthState,
		outputMode: BrowserCameraOutputMode,
		routingSettings: BrowserCameraRoutingSettings,
		availableSources: [BrowserCameraSource],
		activeConsumersByID: [String: BrowserCameraConsumer],
		lastErrorDescription: String?
	) {
		self.init(
			lifecycleState: lifecycleState,
			healthState: healthState,
			outputMode: outputMode,
			routingSettings: routingSettings,
			availableSources: availableSources,
			activeConsumersByID: activeConsumersByID,
			performanceMetrics: .empty,
			lastErrorDescription: lastErrorDescription,
			pipelineRuntimeState: nil,
			browserTransportStates: [],
			recentDiagnosticEvents: []
		)
	}

	public init(
		lifecycleState: BrowserCameraLifecycleState,
		healthState: BrowserCameraHealthState,
		outputMode: BrowserCameraOutputMode,
		routingSettings: BrowserCameraRoutingSettings,
		availableSources: [BrowserCameraSource],
		activeConsumerKindsByID: [String: BrowserCameraConsumerKind],
		performanceMetrics: BrowserCameraPerformanceMetrics,
		lastErrorDescription: String?
	) {
		self.init(
			lifecycleState: lifecycleState,
			healthState: healthState,
			outputMode: outputMode,
			routingSettings: routingSettings,
			availableSources: availableSources,
			activeConsumersByID: activeConsumerKindsByID.reduce(into: [:]) { partialResult, entry in
				partialResult[entry.key] = BrowserCameraConsumer(
					id: entry.key,
					kind: entry.value,
					requiresLiveFrames: entry.value.requiresLiveFrames
				)
			},
			performanceMetrics: performanceMetrics,
			lastErrorDescription: lastErrorDescription,
			pipelineRuntimeState: nil,
			browserTransportStates: [],
			recentDiagnosticEvents: []
		)
	}

	public init(
		lifecycleState: BrowserCameraLifecycleState,
		healthState: BrowserCameraHealthState,
		outputMode: BrowserCameraOutputMode,
		routingSettings: BrowserCameraRoutingSettings,
		availableSources: [BrowserCameraSource],
		activeConsumerKindsByID: [String: BrowserCameraConsumerKind],
		lastErrorDescription: String?
	) {
		self.init(
			lifecycleState: lifecycleState,
			healthState: healthState,
			outputMode: outputMode,
			routingSettings: routingSettings,
			availableSources: availableSources,
			activeConsumerKindsByID: activeConsumerKindsByID,
			performanceMetrics: .empty,
			lastErrorDescription: lastErrorDescription
		)
	}

	public init(
		lifecycleState: BrowserCameraLifecycleState,
		healthState: BrowserCameraHealthState,
		outputMode: BrowserCameraOutputMode,
		routingConfiguration: BrowserCameraRoutingConfiguration,
		availableDevices: [BrowserCameraDevice],
		activeConsumers: [BrowserCameraConsumer],
		liveFrameConsumerCount: Int,
		previewConsumerCount: Int,
		lastErrorDescription: String?
	) {
		self.init(
			lifecycleState: lifecycleState,
			healthState: healthState,
			outputMode: outputMode,
			routingSettings: routingConfiguration.settings,
			availableSources: availableDevices,
			activeConsumersByID: activeConsumers.reduce(into: [:]) { partialResult, consumer in
				partialResult[consumer.id] = consumer
			},
			performanceMetrics: .empty,
			lastErrorDescription: lastErrorDescription
		)

		_ = liveFrameConsumerCount
		_ = previewConsumerCount
	}

	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		lifecycleState = try container.decode(BrowserCameraLifecycleState.self, forKey: .lifecycleState)
		healthState = try container.decode(BrowserCameraHealthState.self, forKey: .healthState)
		outputMode = try container.decode(BrowserCameraOutputMode.self, forKey: .outputMode)
		routingSettings = try container.decode(BrowserCameraRoutingSettings.self, forKey: .routingSettings)
		availableSources = try container.decode([BrowserCameraSource].self, forKey: .availableSources)
		performanceMetrics = try container.decodeIfPresent(
			BrowserCameraPerformanceMetrics.self,
			forKey: .performanceMetrics
		) ?? .empty
		lastErrorDescription = try container.decodeIfPresent(String.self, forKey: .lastErrorDescription)
		pipelineRuntimeState = try container.decodeIfPresent(
			BrowserCameraPipelineRuntimeState.self,
			forKey: .pipelineRuntimeState
		)
		browserTransportStates = try Self.normalizeBrowserTransportStates(
			container.decodeIfPresent(
				[BrowserCameraBrowserTransportState].self,
				forKey: .browserTransportStates
			) ?? []
		)
		recentDiagnosticEvents = try container.decodeIfPresent(
			[BrowserCameraDiagnosticEvent].self,
			forKey: .recentDiagnosticEvents
		) ?? []

		if let activeConsumersByID = try container.decodeIfPresent(
			[String: BrowserCameraConsumer].self,
			forKey: .activeConsumersByID
		) {
			self.activeConsumersByID = Self.normalizeActiveConsumers(activeConsumersByID)
			return
		}

		let legacyConsumerKindsByID = try container.decodeIfPresent(
			[String: BrowserCameraConsumerKind].self,
			forKey: .activeConsumerKindsByID
		) ?? [:]
		activeConsumersByID = Self.normalizeActiveConsumers(
			legacyConsumerKindsByID.reduce(into: [:]) { partialResult, entry in
				partialResult[entry.key] = BrowserCameraConsumer(
					id: entry.key,
					kind: entry.value,
					requiresLiveFrames: entry.value.requiresLiveFrames
				)
			}
		)
	}

	public func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(lifecycleState, forKey: .lifecycleState)
		try container.encode(healthState, forKey: .healthState)
		try container.encode(outputMode, forKey: .outputMode)
		try container.encode(routingSettings, forKey: .routingSettings)
		try container.encode(availableSources, forKey: .availableSources)
		try container.encode(activeConsumersByID, forKey: .activeConsumersByID)
		try container.encode(activeConsumerKindsByID, forKey: .activeConsumerKindsByID)
		try container.encode(performanceMetrics, forKey: .performanceMetrics)
		try container.encodeIfPresent(lastErrorDescription, forKey: .lastErrorDescription)
		try container.encodeIfPresent(pipelineRuntimeState, forKey: .pipelineRuntimeState)
		try container.encode(browserTransportStates, forKey: .browserTransportStates)
		try container.encode(recentDiagnosticEvents, forKey: .recentDiagnosticEvents)
	}

	private var sortedConsumers: [BrowserCameraConsumer] {
		activeConsumersByID.sorted { lhs, rhs in
			lhs.key < rhs.key
		}.map(\.value)
	}

	private func sortedConsumerIDs(
		matching predicate: (BrowserCameraConsumer) -> Bool
	) -> [String] {
		sortedConsumers.compactMap { consumer in
			if predicate(consumer) {
				consumer.id
			}
			else {
				nil
			}
		}
	}

	private static func normalizeBrowserTransportStates(
		_ browserTransportStates: [BrowserCameraBrowserTransportState]
	) -> [BrowserCameraBrowserTransportState] {
		browserTransportStates.sorted { lhs, rhs in
			lhs.tabID.localizedStandardCompare(rhs.tabID) == .orderedAscending
		}
	}

	private static func normalizeActiveConsumers(
		_ activeConsumersByID: [String: BrowserCameraConsumer]
	) -> [String: BrowserCameraConsumer] {
		activeConsumersByID.reduce(into: [:]) { partialResult, entry in
			partialResult[entry.key] = BrowserCameraConsumer(
				id: entry.key,
				kind: entry.value.kind,
				requiresLiveFrames: entry.value.requiresLiveFrames
			)
		}
	}
}
