import AppKit
import BrowserCameraKit
import BrowserSidebar
import Foundation
import ModelKit

@MainActor
protocol NavigatorCameraStatusItemControlling: AnyObject {
	func invalidate()
}

enum NavigatorCameraStatusItemTintStyle: Equatable {
	case secondary
	case accent
	case warning
	case error

	var color: NSColor {
		switch self {
		case .secondary:
			.secondaryLabelColor
		case .accent:
			.controlAccentColor
		case .warning:
			.systemOrange
		case .error:
			.systemRed
		}
	}
}

struct NavigatorCameraStatusItemAppearance: Equatable {
	let symbolName: String
	let tintStyle: NavigatorCameraStatusItemTintStyle
}

enum NavigatorCameraStatusItemAppearanceResolver {
	static func resolve(
		lifecycleState: BrowserCameraLifecycleState,
		healthState: BrowserCameraHealthState,
		debugSummary: BrowserCameraDebugSummary
	) -> NavigatorCameraStatusItemAppearance {
		if lifecycleState == .failed {
			return NavigatorCameraStatusItemAppearance(
				symbolName: "exclamationmark.triangle.fill",
				tintStyle: .error
			)
		}

		switch healthState {
		case .healthy:
			let hasActiveCameraUsage =
				!debugSummary.activeLiveFrameConsumerIDs.isEmpty
					|| !debugSummary.activePreviewConsumerIDs.isEmpty
			return NavigatorCameraStatusItemAppearance(
				symbolName: lifecycleState == .running && hasActiveCameraUsage
					? "video.fill"
					: "video",
				tintStyle: lifecycleState == .running && hasActiveCameraUsage
					? .accent
					: .secondary
			)
		case .degraded, .pipelineFallback, .sourceLost:
			return NavigatorCameraStatusItemAppearance(
				symbolName: "video.badge.exclamationmark",
				tintStyle: .warning
			)
		case .publisherUnavailable:
			return NavigatorCameraStatusItemAppearance(
				symbolName: "video.slash",
				tintStyle: .error
			)
		}
	}
}

@MainActor
protocol NavigatorCameraStatusItemButtonControlling: AnyObject {
	var target: AnyObject? { get set }
	var action: Selector? { get set }
	var image: NSImage? { get set }
	var contentTintColor: NSColor? { get set }
	var imagePosition: NSControl.ImagePosition { get set }
	var toolTip: String? { get set }
	var view: NSView { get }
}

extension NSStatusBarButton: NavigatorCameraStatusItemButtonControlling {
	var view: NSView {
		self
	}
}

@MainActor
protocol NavigatorCameraStatusItemHosting: AnyObject {
	var button: (any NavigatorCameraStatusItemButtonControlling)? { get }
	func invalidate()
}

@MainActor
private final class LiveNavigatorCameraStatusItemHost: NSObject, NavigatorCameraStatusItemHosting {
	private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

	var button: (any NavigatorCameraStatusItemButtonControlling)? {
		statusItem.button
	}

	func invalidate() {
		statusItem.button?.target = nil
		statusItem.button?.action = nil
		NSStatusBar.system.removeStatusItem(statusItem)
	}
}

@MainActor
protocol NavigatorCameraStatusItemPopoverControlling: AnyObject {
	var isShown: Bool { get }
	var behavior: NSPopover.Behavior { get set }
	var contentSize: NSSize { get set }
	var contentViewController: NSViewController? { get set }
	var delegate: NSPopoverDelegate? { get set }
	func performClose(_ sender: Any?)
	func show(relativeTo positioningRect: NSRect, of positioningView: NSView, preferredEdge: NSRectEdge)
}

extension NSPopover: NavigatorCameraStatusItemPopoverControlling {}

enum NavigatorCameraStatusItemLocalizationKey: String {
	case browserTransportFormat = "navigator.camera.statusItem.browserTransport.format"
	case latestEventFormat = "navigator.camera.statusItem.latestEvent.format"
	case lastErrorFormat = "navigator.camera.statusItem.lastError.format"
	case pipelineFormat = "navigator.camera.statusItem.pipeline.format"
	case summaryActive = "navigator.camera.statusItem.summary.active"
	case summaryReady = "navigator.camera.statusItem.summary.ready"
	case summaryDegraded = "navigator.camera.statusItem.summary.degraded"
	case summaryFailed = "navigator.camera.statusItem.summary.failed"
	case summaryPublisherUnavailable = "navigator.camera.statusItem.summary.publisherUnavailable"

	var fallbackValue: String {
		switch self {
		case .browserTransportFormat:
			"Browser transport: tabs %d • Tracks: %d • Fallback: %d"
		case .latestEventFormat:
			"Latest event: %@"
		case .lastErrorFormat:
			"Last error: %@"
		case .pipelineFormat:
			"Pipeline: %@ • %@ • %d filters"
		case .summaryActive:
			"Navigator Camera active"
		case .summaryReady:
			"Navigator Camera ready"
		case .summaryDegraded:
			"Navigator Camera degraded"
		case .summaryFailed:
			"Navigator Camera unavailable"
		case .summaryPublisherUnavailable:
			"Navigator Camera publisher unavailable"
		}
	}
}

enum NavigatorCameraDiagnosticLocalizationKey: String {
	case deviceAvailabilityChanged = "navigator.camera.diagnosticEvent.deviceAvailabilityChanged"
	case consumerRegistered = "navigator.camera.diagnosticEvent.consumerRegistered"
	case consumerUnregistered = "navigator.camera.diagnosticEvent.consumerUnregistered"
	case routingChanged = "navigator.camera.diagnosticEvent.routingChanged"
	case preferredSourceChanged = "navigator.camera.diagnosticEvent.preferredSourceChanged"
	case filterPresetChanged = "navigator.camera.diagnosticEvent.filterPresetChanged"
	case previewChanged = "navigator.camera.diagnosticEvent.previewChanged"
	case captureStartRequested = "navigator.camera.diagnosticEvent.captureStartRequested"
	case captureStarted = "navigator.camera.diagnosticEvent.captureStarted"
	case captureStopped = "navigator.camera.diagnosticEvent.captureStopped"
	case captureFailed = "navigator.camera.diagnosticEvent.captureFailed"
	case sourceLost = "navigator.camera.diagnosticEvent.sourceLost"
	case firstFrameProduced = "navigator.camera.diagnosticEvent.firstFrameProduced"
	case processingDegraded = "navigator.camera.diagnosticEvent.processingDegraded"
	case processingRecovered = "navigator.camera.diagnosticEvent.processingRecovered"
	case publisherStatusChanged = "navigator.camera.diagnosticEvent.publisherStatusChanged"
	case managedTrackStarted = "navigator.camera.diagnosticEvent.managedTrackStarted"
	case managedTrackStopped = "navigator.camera.diagnosticEvent.managedTrackStopped"
	case managedTrackEnded = "navigator.camera.diagnosticEvent.managedTrackEnded"
	case permissionProbeFailed = "navigator.camera.diagnosticEvent.permissionProbeFailed"
	case explicitDeviceBypassed = "navigator.camera.diagnosticEvent.explicitDeviceBypassed"
	case managedTrackDeviceSwitchRejected = "navigator.camera.diagnosticEvent.managedTrackDeviceSwitchRejected"
	case browserProcessFallbackActivated = "navigator.camera.diagnosticEvent.browserProcessFallbackActivated"

	init(kind: BrowserCameraDiagnosticEventKind) {
		switch kind {
		case .deviceAvailabilityChanged:
			self = .deviceAvailabilityChanged
		case .consumerRegistered:
			self = .consumerRegistered
		case .consumerUnregistered:
			self = .consumerUnregistered
		case .routingChanged:
			self = .routingChanged
		case .preferredSourceChanged:
			self = .preferredSourceChanged
		case .filterPresetChanged:
			self = .filterPresetChanged
		case .previewChanged:
			self = .previewChanged
		case .captureStartRequested:
			self = .captureStartRequested
		case .captureStarted:
			self = .captureStarted
		case .captureStopped:
			self = .captureStopped
		case .captureFailed:
			self = .captureFailed
		case .sourceLost:
			self = .sourceLost
		case .firstFrameProduced:
			self = .firstFrameProduced
		case .processingDegraded:
			self = .processingDegraded
		case .processingRecovered:
			self = .processingRecovered
		case .publisherStatusChanged:
			self = .publisherStatusChanged
		case .managedTrackStarted:
			self = .managedTrackStarted
		case .managedTrackStopped:
			self = .managedTrackStopped
		case .managedTrackEnded:
			self = .managedTrackEnded
		case .permissionProbeFailed:
			self = .permissionProbeFailed
		case .explicitDeviceBypassed:
			self = .explicitDeviceBypassed
		case .managedTrackDeviceSwitchRejected:
			self = .managedTrackDeviceSwitchRejected
		case .browserProcessFallbackActivated:
			self = .browserProcessFallbackActivated
		}
	}

	func fallbackValue(localeIdentifier: String?) -> String {
		let isJapanese = localeIdentifier?.hasPrefix("ja") == true
		switch self {
		case .deviceAvailabilityChanged:
			return isJapanese ? "カメラソース更新" : "Camera source availability changed"
		case .consumerRegistered:
			return isJapanese ? "消費者を登録" : "Consumer registered"
		case .consumerUnregistered:
			return isJapanese ? "消費者を解除" : "Consumer unregistered"
		case .routingChanged:
			return isJapanese ? "ルーティング変更" : "Routing changed"
		case .preferredSourceChanged:
			return isJapanese ? "優先ソース変更" : "Preferred source changed"
		case .filterPresetChanged:
			return isJapanese ? "フィルター変更" : "Filter preset changed"
		case .previewChanged:
			return isJapanese ? "プレビュー切り替え" : "Preview toggled"
		case .captureStartRequested:
			return isJapanese ? "キャプチャ開始要求" : "Capture start requested"
		case .captureStarted:
			return isJapanese ? "キャプチャ開始" : "Capture started"
		case .captureStopped:
			return isJapanese ? "キャプチャ停止" : "Capture stopped"
		case .captureFailed:
			return isJapanese ? "キャプチャ失敗" : "Capture failed"
		case .sourceLost:
			return isJapanese ? "ソース喪失" : "Source lost"
		case .firstFrameProduced:
			return isJapanese ? "初回フレーム生成" : "First frame produced"
		case .processingDegraded:
			return isJapanese ? "処理劣化" : "Processing degraded"
		case .processingRecovered:
			return isJapanese ? "処理回復" : "Processing recovered"
		case .publisherStatusChanged:
			return isJapanese ? "公開状態変更" : "Publisher status changed"
		case .managedTrackStarted:
			return isJapanese ? "管理トラック開始" : "Managed track started"
		case .managedTrackStopped:
			return isJapanese ? "管理トラック停止" : "Managed track stopped"
		case .managedTrackEnded:
			return isJapanese ? "管理トラック終了" : "Managed track ended"
		case .permissionProbeFailed:
			return isJapanese ? "権限確認失敗" : "Permission probe failed"
		case .explicitDeviceBypassed:
			return isJapanese ? "明示デバイスをバイパス" : "Explicit device bypassed"
		case .managedTrackDeviceSwitchRejected:
			return isJapanese ? "管理トラック切替を拒否" : "Managed track switch rejected"
		case .browserProcessFallbackActivated:
			return isJapanese ? "ブラウザフォールバック有効" : "Browser fallback activated"
		}
	}
}

enum NavigatorCameraDiagnosticEventTextResolver {
	static func description(
		_ event: BrowserCameraDiagnosticEvent,
		localized: (NavigatorCameraDiagnosticLocalizationKey) -> String
	) -> String {
		let title = localized(.init(kind: event.kind))
		guard let detail = event.detail?.trimmingCharacters(in: .whitespacesAndNewlines),
		      detail.isEmpty == false
		else {
			return title
		}
		return "\(title): \(detail)"
	}
}

enum NavigatorCameraStatusItemTooltipResolver {
	static func resolve(
		debugSummary: BrowserCameraDebugSummary,
		localized: (NavigatorCameraStatusItemLocalizationKey) -> String,
		localizedDiagnosticEvent: (NavigatorCameraDiagnosticLocalizationKey) -> String
	) -> String {
		var lines = [localized(summaryKey(for: debugSummary))]
		if !debugSummary.browserTransportStates.isEmpty {
			lines.append(
				String(
					format: localized(.browserTransportFormat),
					debugSummary.browserTransportStates.count,
					debugSummary.browserTransportStates.reduce(0) { partialResult, state in
						partialResult + state.activeManagedTrackCount
					},
					debugSummary.browserTransportStates.filter(\.isUsingBrowserProcessFallback).count
				)
			)
		}
		if let pipelineRuntimeState = debugSummary.pipelineRuntimeState {
			lines.append(
				String(
					format: localized(.pipelineFormat),
					pipelineRuntimeState.implementation.rawValue,
					pipelineRuntimeState.warmupProfile.rawValue,
					pipelineRuntimeState.requiredFilterCount
				)
			)
		}
		if let latestEvent = debugSummary.recentDiagnosticEvents.last {
			lines.append(
				String(
					format: localized(.latestEventFormat),
					NavigatorCameraDiagnosticEventTextResolver.description(
						latestEvent,
						localized: localizedDiagnosticEvent
					)
				)
			)
		}
		else if let lastErrorDescription = debugSummary.lastErrorDescription?
			.trimmingCharacters(in: .whitespacesAndNewlines),
			lastErrorDescription.isEmpty == false {
			lines.append(
				String(
					format: localized(.lastErrorFormat),
					lastErrorDescription
				)
			)
		}
		return lines.joined(separator: "\n")
	}

	private static func summaryKey(
		for debugSummary: BrowserCameraDebugSummary
	) -> NavigatorCameraStatusItemLocalizationKey {
		if debugSummary.lifecycleState == .failed {
			return .summaryFailed
		}

		switch debugSummary.healthState {
		case .healthy:
			let hasActiveCameraUsage =
				!debugSummary.activeLiveFrameConsumerIDs.isEmpty
					|| !debugSummary.activePreviewConsumerIDs.isEmpty
			return hasActiveCameraUsage ? .summaryActive : .summaryReady
		case .degraded, .pipelineFallback, .sourceLost:
			return .summaryDegraded
		case .publisherUnavailable:
			return .summaryPublisherUnavailable
		}
	}
}

@MainActor
final class NavigatorCameraStatusItemController: NSObject, NavigatorCameraStatusItemControlling {
	private enum Layout {
		static let popoverSize = NSSize(width: 320, height: 360)
	}

	private let statusItemHost: any NavigatorCameraStatusItemHosting
	private let popover: any NavigatorCameraStatusItemPopoverControlling
	private let viewModel: BrowserCameraMenuBarViewModel
	private let contentViewProvider: @MainActor (BrowserCameraMenuBarViewModel) -> NSView
	private var viewModelChangeObserverID: UUID?
	private var currentAppearance: NavigatorCameraStatusItemAppearance?

	convenience init(browserCameraSessionCoordinator: any BrowserCameraSessionCoordinating) {
		self.init(
			viewModel: BrowserCameraMenuBarViewModel(
				browserCameraSessionCoordinator: browserCameraSessionCoordinator
			),
			statusItemHost: LiveNavigatorCameraStatusItemHost(),
			popover: NSPopover(),
			contentViewProvider: { viewModel in
				InjectedBrowserSidebarView(
					BrowserCameraMenuBarView(viewModel: viewModel)
				)
			}
		)
	}

	init(
		viewModel: BrowserCameraMenuBarViewModel,
		statusItemHost: any NavigatorCameraStatusItemHosting,
		popover: any NavigatorCameraStatusItemPopoverControlling,
		contentViewProvider: @escaping @MainActor (BrowserCameraMenuBarViewModel) -> NSView
	) {
		self.viewModel = viewModel
		self.statusItemHost = statusItemHost
		self.popover = popover
		self.contentViewProvider = contentViewProvider
		super.init()
		configureStatusItem()
		configurePopover()
		viewModelChangeObserverID = self.viewModel.addChangeObserver { [weak self] in
			self?.refreshStatusItemAppearance()
		}
	}

	func invalidate() {
		popover.performClose(nil)
		if let viewModelChangeObserverID {
			viewModel.removeChangeObserver(id: viewModelChangeObserverID)
			self.viewModelChangeObserverID = nil
		}
		viewModel.setPopoverPresented(false)
		viewModel.invalidate()
		statusItemHost.button?.target = nil
		statusItemHost.button?.action = nil
		statusItemHost.invalidate()
	}

	private func configureStatusItem() {
		guard let button = statusItemHost.button else { return }
		button.target = self
		button.action = #selector(togglePopover(_:))
		button.imagePosition = .imageOnly
		refreshStatusItemAppearance()
	}

	private func configurePopover() {
		let contentViewController = NSViewController()
		let contentView = contentViewProvider(viewModel)
		contentView.frame = NSRect(origin: .zero, size: Layout.popoverSize)
		contentViewController.view = contentView
		popover.delegate = self
		popover.behavior = .transient
		popover.contentSize = Layout.popoverSize
		popover.contentViewController = contentViewController
	}

	private func refreshStatusItemAppearance() {
		guard let button = statusItemHost.button else { return }
		let appearance = NavigatorCameraStatusItemAppearanceResolver.resolve(
			lifecycleState: viewModel.lifecycleState,
			healthState: viewModel.healthState,
			debugSummary: viewModel.debugSummary
		)
		currentAppearance = appearance
		button.image = NSImage(
			systemSymbolName: appearance.symbolName,
			accessibilityDescription: nil
		)
		button.contentTintColor = appearance.tintStyle.color
		button.toolTip = NavigatorCameraStatusItemTooltipResolver.resolve(
			debugSummary: viewModel.debugSummary,
			localized: localized,
			localizedDiagnosticEvent: localized
		)
	}

	@objc private func togglePopover(_ sender: Any?) {
		guard let button = statusItemHost.button else { return }
		if popover.isShown {
			popover.performClose(sender)
			return
		}
		viewModel.setPopoverPresented(true)
		popover.show(relativeTo: button.view.bounds, of: button.view, preferredEdge: .minY)
		popover.contentViewController?.view.window?.makeKey()
	}

	func currentAppearanceForTesting() -> NavigatorCameraStatusItemAppearance? {
		currentAppearance
	}

	func currentToolTipForTesting() -> String? {
		statusItemHost.button?.toolTip
	}

	func togglePopoverForTesting() {
		togglePopover(nil)
	}

	private func localized(_ key: NavigatorCameraStatusItemLocalizationKey) -> String {
		let localizedValue = Bundle.main.localizedString(
			forKey: key.rawValue,
			value: key.rawValue,
			table: nil
		)
		return localizedValue == key.rawValue ? key.fallbackValue : localizedValue
	}

	private func localized(_ key: NavigatorCameraDiagnosticLocalizationKey) -> String {
		let localizedValue = Bundle.main.localizedString(
			forKey: key.rawValue,
			value: key.rawValue,
			table: nil
		)
		let localeIdentifier = Locale.preferredLanguages.first
		return localizedValue == key.rawValue ? key.fallbackValue(localeIdentifier: localeIdentifier) : localizedValue
	}
}

extension NavigatorCameraStatusItemController: NSPopoverDelegate {
	func popoverDidClose(_ notification: Notification) {
		_ = notification
		viewModel.setPopoverPresented(false)
	}
}
