import AppKit
import BrowserCameraKit
import CoreGraphics
import ModelKit

public struct BrowserSidebarCameraControls {
	public let snapshot: () -> BrowserCameraSessionSnapshot
	public let routingConfiguration: () -> BrowserCameraRoutingConfiguration
	public let previewFrame: () -> CGImage?
	public let refreshAvailableDevices: () -> Void
	public let setRoutingEnabled: (Bool) -> Void
	public let setPreferredSourceID: (String?) -> Void
	public let setPreferredFilterPreset: (BrowserCameraFilterPreset) -> Void
	public let setPreferredGrainPresence: (BrowserCameraPipelineGrainPresence) -> Void
	public let setPrefersHorizontalFlip: (Bool) -> Void
	public let setPreviewEnabled: (Bool) -> Void

	public init(
		snapshot: @escaping () -> BrowserCameraSessionSnapshot,
		routingConfiguration: @escaping () -> BrowserCameraRoutingConfiguration,
		previewFrame: @escaping () -> CGImage?,
		refreshAvailableDevices: @escaping () -> Void,
		setRoutingEnabled: @escaping (Bool) -> Void,
		setPreferredSourceID: @escaping (String?) -> Void,
		setPreferredFilterPreset: @escaping (BrowserCameraFilterPreset) -> Void,
		setPreferredGrainPresence: @escaping (BrowserCameraPipelineGrainPresence) -> Void,
		setPrefersHorizontalFlip: @escaping (Bool) -> Void,
		setPreviewEnabled: @escaping (Bool) -> Void
	) {
		self.snapshot = snapshot
		self.routingConfiguration = routingConfiguration
		self.previewFrame = previewFrame
		self.refreshAvailableDevices = refreshAvailableDevices
		self.setRoutingEnabled = setRoutingEnabled
		self.setPreferredSourceID = setPreferredSourceID
		self.setPreferredFilterPreset = setPreferredFilterPreset
		self.setPreferredGrainPresence = setPreferredGrainPresence
		self.setPrefersHorizontalFlip = setPrefersHorizontalFlip
		self.setPreviewEnabled = setPreviewEnabled
	}

	public init(
		snapshot: @escaping () -> BrowserCameraSessionSnapshot,
		routingConfiguration: @escaping () -> BrowserCameraRoutingConfiguration,
		previewFrame: @escaping () -> CGImage?,
		refreshAvailableDevices: @escaping () -> Void,
		setRoutingEnabled: @escaping (Bool) -> Void,
		setPreferredSourceID: @escaping (String?) -> Void,
		setPreferredFilterPreset: @escaping (BrowserCameraFilterPreset) -> Void,
		setPreviewEnabled: @escaping (Bool) -> Void
	) {
		self.init(
			snapshot: snapshot,
			routingConfiguration: routingConfiguration,
			previewFrame: previewFrame,
			refreshAvailableDevices: refreshAvailableDevices,
			setRoutingEnabled: setRoutingEnabled,
			setPreferredSourceID: setPreferredSourceID,
			setPreferredFilterPreset: setPreferredFilterPreset,
			setPreferredGrainPresence: { _ in },
			setPrefersHorizontalFlip: { _ in },
			setPreviewEnabled: setPreviewEnabled
		)
	}

	public init() {
		self = Self.unavailable
	}

	public var previewImage: NSImage? {
		previewFrame().map { previewFrame in
			NSImage(cgImage: previewFrame, size: NSSize(width: previewFrame.width, height: previewFrame.height))
		}
	}

	public var isVisible: Bool {
		let snapshot = snapshot()
		if snapshot.availableSources.isEmpty == false {
			return true
		}
		if snapshot.lastErrorDescription?.isEmpty == false {
			return true
		}
		return snapshot.outputMode != .unavailable
	}

	public static var unavailable: Self {
		Self(
			snapshot: {
				BrowserCameraSessionSnapshot(
					lifecycleState: .idle,
					healthState: .healthy,
					outputMode: .unavailable,
					routingSettings: .defaults,
					availableSources: [],
					activeConsumersByID: [:],
					performanceMetrics: .empty,
					lastErrorDescription: nil
				)
			},
			routingConfiguration: {
				BrowserCameraRoutingConfiguration(
					settings: .defaults,
					outputMode: .unavailable
				)
			},
			previewFrame: { nil },
			refreshAvailableDevices: {},
			setRoutingEnabled: { _ in },
			setPreferredSourceID: { _ in },
			setPreferredFilterPreset: { _ in },
			setPreferredGrainPresence: { _ in },
			setPrefersHorizontalFlip: { _ in },
			setPreviewEnabled: { _ in }
		)
	}
}
