import Foundation
import ModelKit

enum BrowserCameraDiagnosticLocalizationKey: String {
	case deviceAvailabilityChanged = "browser.sidebar.camera.diagnostics.event.deviceAvailabilityChanged"
	case consumerRegistered = "browser.sidebar.camera.diagnostics.event.consumerRegistered"
	case consumerUnregistered = "browser.sidebar.camera.diagnostics.event.consumerUnregistered"
	case routingChanged = "browser.sidebar.camera.diagnostics.event.routingChanged"
	case preferredSourceChanged = "browser.sidebar.camera.diagnostics.event.preferredSourceChanged"
	case filterPresetChanged = "browser.sidebar.camera.diagnostics.event.filterPresetChanged"
	case previewChanged = "browser.sidebar.camera.diagnostics.event.previewChanged"
	case captureStartRequested = "browser.sidebar.camera.diagnostics.event.captureStartRequested"
	case captureStarted = "browser.sidebar.camera.diagnostics.event.captureStarted"
	case captureStopped = "browser.sidebar.camera.diagnostics.event.captureStopped"
	case captureFailed = "browser.sidebar.camera.diagnostics.event.captureFailed"
	case sourceLost = "browser.sidebar.camera.diagnostics.event.sourceLost"
	case firstFrameProduced = "browser.sidebar.camera.diagnostics.event.firstFrameProduced"
	case processingDegraded = "browser.sidebar.camera.diagnostics.event.processingDegraded"
	case processingRecovered = "browser.sidebar.camera.diagnostics.event.processingRecovered"
	case publisherStatusChanged = "browser.sidebar.camera.diagnostics.event.publisherStatusChanged"
	case managedTrackStarted = "browser.sidebar.camera.diagnostics.event.managedTrackStarted"
	case managedTrackStopped = "browser.sidebar.camera.diagnostics.event.managedTrackStopped"
	case managedTrackEnded = "browser.sidebar.camera.diagnostics.event.managedTrackEnded"
	case permissionProbeFailed = "browser.sidebar.camera.diagnostics.event.permissionProbeFailed"
	case explicitDeviceBypassed = "browser.sidebar.camera.diagnostics.event.explicitDeviceBypassed"
	case managedTrackDeviceSwitchRejected = "browser.sidebar.camera.diagnostics.event.managedTrackDeviceSwitchRejected"
	case browserProcessFallbackActivated = "browser.sidebar.camera.diagnostics.event.browserProcessFallbackActivated"

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

enum BrowserCameraDiagnosticsFormatter {
	static func text(
		from debugSummary: BrowserCameraDebugSummary,
		routingFormat: String,
		consumersFormat: String,
		framesFormat: String,
		pipelineFormat: String,
		browserTransportFormat: String,
		latestEventFormat: String,
		publisherFormat: String,
		unknownTransport: String,
		localizeDiagnosticEvent: (BrowserCameraDiagnosticLocalizationKey) -> String,
		localizedRoutingAvailability: (BrowserCameraManagedRoutingAvailability) -> String,
		localizedPublisherState: (BrowserCameraVirtualPublisherState) -> String,
		localizedPublisherTransport: (BrowserCameraVirtualPublisherTransportMode) -> String
	) -> String {
		let routingLine = String(
			format: routingFormat,
			localizedRoutingAvailability(debugSummary.managedRoutingSummary.availability)
		)
		let consumersLine = String(
			format: consumersFormat,
			debugSummary.activeLiveFrameConsumerIDs.count,
			debugSummary.activePreviewConsumerIDs.count
		)
		let averageLatencyValue = debugSummary.performanceMetrics.averageProcessingLatencyMilliseconds
		let averageLatencyDescription = averageLatencyValue.map(Self.formattedMilliseconds) ?? "--"
		let framesLine = String(
			format: framesFormat,
			debugSummary.performanceMetrics.processedFrameCount,
			debugSummary.performanceMetrics.droppedFrameCount,
			averageLatencyDescription
		)
		var lines = [routingLine, consumersLine, framesLine]
		if let pipelineRuntimeState = debugSummary.pipelineRuntimeState {
			lines.append(
				String(
					format: pipelineFormat,
					pipelineRuntimeState.implementation.rawValue,
					pipelineRuntimeState.warmupProfile.rawValue,
					pipelineRuntimeState.requiredFilterCount
				)
			)
		}
		if !debugSummary.browserTransportStates.isEmpty {
			lines.append(
				String(
					format: browserTransportFormat,
					debugSummary.browserTransportStates.count,
					debugSummary.browserTransportStates.reduce(0) { partialResult, state in
						partialResult + state.activeManagedTrackCount
					},
					debugSummary.browserTransportStates.filter(\.isUsingBrowserProcessFallback).count
				)
			)
		}

		if debugSummary.publisherStatus.state != .notRequired {
			let publisherTransportDescription = if let transportMode = debugSummary.publisherStatus
				.configuration?.transportMode {
				localizedPublisherTransport(transportMode)
			}
			else {
				unknownTransport
			}
			let publisherLine = String(
				format: publisherFormat,
				localizedPublisherState(debugSummary.publisherStatus.state),
				publisherTransportDescription
			)
			lines.append(publisherLine)
		}

		if let latestEvent = debugSummary.recentDiagnosticEvents.last {
			lines.append(
				String(
					format: latestEventFormat,
					diagnosticEventDescription(latestEvent, localizeDiagnosticEvent: localizeDiagnosticEvent)
				)
			)
		}

		return lines.joined(separator: "\n")
	}

	private static func formattedMilliseconds(_ value: Double) -> String {
		String(format: "%.1f", value)
	}

	private static func diagnosticEventDescription(
		_ event: BrowserCameraDiagnosticEvent,
		localizeDiagnosticEvent: (BrowserCameraDiagnosticLocalizationKey) -> String
	) -> String {
		let title = localizeDiagnosticEvent(.init(kind: event.kind))
		guard let detail = event.detail?.trimmingCharacters(in: .whitespacesAndNewlines),
		      detail.isEmpty == false
		else {
			return title
		}
		return "\(title): \(detail)"
	}
}
