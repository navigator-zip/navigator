@testable import BrowserSidebar
import ModelKit
import XCTest

final class BrowserCameraDiagnosticsFormatterTests: XCTestCase {
	func testFormatterOmitsPublisherLineWhenPublisherNotRequired() {
		let text = BrowserCameraDiagnosticsFormatter.text(
			from: makeSummary(publisherStatus: .notRequired),
			routingFormat: "Routing: %@",
			consumersFormat: "Live consumers: %d • Preview consumers: %d",
			framesFormat: "Frames: %d • Dropped: %d • Avg: %@ ms",
			pipelineFormat: "Pipeline: %@ • %@ • %d filters",
			browserTransportFormat: "Browser transport: tabs %d • Tracks: %d • Fallback: %d",
			latestEventFormat: "Latest event: %@",
			publisherFormat: "Publisher: %@ • Transport: %@",
			unknownTransport: "Unknown",
			localizeDiagnosticEvent: { $0.fallbackValue(localeIdentifier: nil) },
			localizedRoutingAvailability: { availability in
				switch availability {
				case .available:
					"Managed output available"
				default:
					availability.rawValue
				}
			},
			localizedPublisherState: { $0.rawValue },
			localizedPublisherTransport: { $0.rawValue }
		)

		XCTAssertEqual(
			text,
			"""
			Routing: Managed output available
			Live consumers: 1 • Preview consumers: 1
			Frames: 24 • Dropped: 2 • Avg: 14.5 ms
			"""
		)
	}

	func testFormatterIncludesPublisherLineWhenPublisherIsConfigured() {
		let text = BrowserCameraDiagnosticsFormatter.text(
			from: makeSummary(
				publisherStatus: BrowserCameraVirtualPublisherStatus(
					state: .ready,
					configuration: BrowserCameraVirtualPublisherConfiguration(
						sourceDeviceID: "camera-main",
						filterPreset: .folia,
						frameWidth: 1280,
						frameHeight: 720,
						nominalFramesPerSecond: 30,
						pixelFormat: .bgra8888,
						backpressurePolicy: .dropOldest,
						transportMode: .sharedMemory
					),
					lastPublishedFrame: nil,
					lastErrorDescription: nil
				)
			),
			routingFormat: "Routing: %@",
			consumersFormat: "Live consumers: %d • Preview consumers: %d",
			framesFormat: "Frames: %d • Dropped: %d • Avg: %@ ms",
			pipelineFormat: "Pipeline: %@ • %@ • %d filters",
			browserTransportFormat: "Browser transport: tabs %d • Tracks: %d • Fallback: %d",
			latestEventFormat: "Latest event: %@",
			publisherFormat: "Publisher: %@ • Transport: %@",
			unknownTransport: "Unknown",
			localizeDiagnosticEvent: { $0.fallbackValue(localeIdentifier: nil) },
			localizedRoutingAvailability: {
				switch $0 {
				case .available:
					"Managed output available"
				default:
					$0.rawValue
				}
			},
			localizedPublisherState: {
				switch $0 {
				case .ready:
					"Ready"
				default:
					$0.rawValue
				}
			},
			localizedPublisherTransport: {
				switch $0 {
				case .sharedMemory:
					"Shared memory"
				default:
					$0.rawValue
				}
			}
		)

		XCTAssertEqual(
			text,
			"""
			Routing: Managed output available
			Live consumers: 1 • Preview consumers: 1
			Frames: 24 • Dropped: 2 • Avg: 14.5 ms
			Publisher: Ready • Transport: Shared memory
			"""
		)
	}

	func testFormatterFallsBackToUnknownTransportWhenConfigurationIsMissing() {
		let text = BrowserCameraDiagnosticsFormatter.text(
			from: makeSummary(
				publisherStatus: BrowserCameraVirtualPublisherStatus(
					state: .failed,
					configuration: nil,
					lastPublishedFrame: nil,
					lastErrorDescription: "Publisher crashed"
				)
			),
			routingFormat: "Routing: %@",
			consumersFormat: "Live consumers: %d • Preview consumers: %d",
			framesFormat: "Frames: %d • Dropped: %d • Avg: %@ ms",
			pipelineFormat: "Pipeline: %@ • %@ • %d filters",
			browserTransportFormat: "Browser transport: tabs %d • Tracks: %d • Fallback: %d",
			latestEventFormat: "Latest event: %@",
			publisherFormat: "Publisher: %@ • Transport: %@",
			unknownTransport: "Unknown",
			localizeDiagnosticEvent: { $0.fallbackValue(localeIdentifier: nil) },
			localizedRoutingAvailability: {
				switch $0 {
				case .available:
					"Managed output available"
				default:
					$0.rawValue
				}
			},
			localizedPublisherState: {
				switch $0 {
				case .failed:
					"Failed"
				default:
					$0.rawValue
				}
			},
			localizedPublisherTransport: { $0.rawValue }
		)

		XCTAssertEqual(
			text,
			"""
			Routing: Managed output available
			Live consumers: 1 • Preview consumers: 1
			Frames: 24 • Dropped: 2 • Avg: 14.5 ms
			Publisher: Failed • Transport: Unknown
			"""
		)
	}

	func testFormatterUsesPlaceholderWhenAverageLatencyIsUnavailable() {
		let text = BrowserCameraDiagnosticsFormatter.text(
			from: makeSummary(
				publisherStatus: .notRequired,
				performanceMetrics: BrowserCameraPerformanceMetrics(
					processedFrameCount: 1,
					droppedFrameCount: 0,
					firstFrameLatencyMilliseconds: nil,
					averageProcessingLatencyMilliseconds: nil,
					lastProcessingLatencyMilliseconds: nil,
					realtimeBudgetExceeded: false
				)
			),
			routingFormat: "Routing: %@",
			consumersFormat: "Live consumers: %d • Preview consumers: %d",
			framesFormat: "Frames: %d • Dropped: %d • Avg: %@ ms",
			pipelineFormat: "Pipeline: %@ • %@ • %d filters",
			browserTransportFormat: "Browser transport: tabs %d • Tracks: %d • Fallback: %d",
			latestEventFormat: "Latest event: %@",
			publisherFormat: "Publisher: %@ • Transport: %@",
			unknownTransport: "Unknown",
			localizeDiagnosticEvent: { $0.fallbackValue(localeIdentifier: nil) },
			localizedRoutingAvailability: {
				switch $0 {
				case .available:
					"Managed output available"
				default:
					$0.rawValue
				}
			},
			localizedPublisherState: { $0.rawValue },
			localizedPublisherTransport: { $0.rawValue }
		)

		XCTAssertEqual(
			text,
			"""
			Routing: Managed output available
			Live consumers: 1 • Preview consumers: 1
			Frames: 1 • Dropped: 0 • Avg: -- ms
			"""
		)
	}

	func testFormatterIncludesBrowserTransportSummaryWhenTabsAreTracked() {
		let text = BrowserCameraDiagnosticsFormatter.text(
			from: makeSummary(
				publisherStatus: .notRequired,
				browserTransportStates: [
					BrowserCameraBrowserTransportState(
						tabID: "tab-1",
						routingTransportMode: .rendererProcessMessages,
						frameTransportMode: .rendererProcessMessages,
						activeManagedTrackCount: 2
					),
					BrowserCameraBrowserTransportState(
						tabID: "tab-2",
						routingTransportMode: .browserProcessJavaScriptFallback,
						frameTransportMode: .browserProcessJavaScriptFallback,
						activeManagedTrackCount: 1
					),
				]
			),
			routingFormat: "Routing: %@",
			consumersFormat: "Live consumers: %d • Preview consumers: %d",
			framesFormat: "Frames: %d • Dropped: %d • Avg: %@ ms",
			pipelineFormat: "Pipeline: %@ • %@ • %d filters",
			browserTransportFormat: "Browser transport: tabs %d • Tracks: %d • Fallback: %d",
			latestEventFormat: "Latest event: %@",
			publisherFormat: "Publisher: %@ • Transport: %@",
			unknownTransport: "Unknown",
			localizeDiagnosticEvent: { $0.fallbackValue(localeIdentifier: nil) },
			localizedRoutingAvailability: {
				switch $0 {
				case .available:
					"Managed output available"
				default:
					$0.rawValue
				}
			},
			localizedPublisherState: { $0.rawValue },
			localizedPublisherTransport: { $0.rawValue }
		)

		XCTAssertEqual(
			text,
			"""
			Routing: Managed output available
			Live consumers: 1 • Preview consumers: 1
			Frames: 24 • Dropped: 2 • Avg: 14.5 ms
			Browser transport: tabs 2 • Tracks: 3 • Fallback: 1
			"""
		)
	}

	func testFormatterIncludesLatestDiagnosticEventWhenPresent() {
		let text = BrowserCameraDiagnosticsFormatter.text(
			from: makeSummary(
				publisherStatus: .notRequired,
				recentDiagnosticEvents: [
					BrowserCameraDiagnosticEvent(
						kind: .permissionProbeFailed,
						detail: "tabID=tab-7 error=Permission denied"
					),
				]
			),
			routingFormat: "Routing: %@",
			consumersFormat: "Live consumers: %d • Preview consumers: %d",
			framesFormat: "Frames: %d • Dropped: %d • Avg: %@ ms",
			pipelineFormat: "Pipeline: %@ • %@ • %d filters",
			browserTransportFormat: "Browser transport: tabs %d • Tracks: %d • Fallback: %d",
			latestEventFormat: "Latest event: %@",
			publisherFormat: "Publisher: %@ • Transport: %@",
			unknownTransport: "Unknown",
			localizeDiagnosticEvent: { $0.fallbackValue(localeIdentifier: nil) },
			localizedRoutingAvailability: {
				switch $0 {
				case .available:
					"Managed output available"
				default:
					$0.rawValue
				}
			},
			localizedPublisherState: { $0.rawValue },
			localizedPublisherTransport: { $0.rawValue }
		)

		XCTAssertEqual(
			text,
			"""
			Routing: Managed output available
			Live consumers: 1 • Preview consumers: 1
			Frames: 24 • Dropped: 2 • Avg: 14.5 ms
			Latest event: Permission probe failed: tabID=tab-7 error=Permission denied
			"""
		)
	}

	func testFormatterUsesLocalizedEventTitleWhenLatestEventHasNoDetail() {
		let text = BrowserCameraDiagnosticsFormatter.text(
			from: makeSummary(
				publisherStatus: .notRequired,
				recentDiagnosticEvents: [
					BrowserCameraDiagnosticEvent(
						kind: .processingDegraded,
						detail: nil
					),
				]
			),
			routingFormat: "Routing: %@",
			consumersFormat: "Live consumers: %d • Preview consumers: %d",
			framesFormat: "Frames: %d • Dropped: %d • Avg: %@ ms",
			pipelineFormat: "Pipeline: %@ • %@ • %d filters",
			browserTransportFormat: "Browser transport: tabs %d • Tracks: %d • Fallback: %d",
			latestEventFormat: "Latest event: %@",
			publisherFormat: "Publisher: %@ • Transport: %@",
			unknownTransport: "Unknown",
			localizeDiagnosticEvent: { $0.fallbackValue(localeIdentifier: nil) },
			localizedRoutingAvailability: {
				switch $0 {
				case .available:
					"Managed output available"
				default:
					$0.rawValue
				}
			},
			localizedPublisherState: { $0.rawValue },
			localizedPublisherTransport: { $0.rawValue }
		)

		XCTAssertEqual(
			text,
			"""
			Routing: Managed output available
			Live consumers: 1 • Preview consumers: 1
			Frames: 24 • Dropped: 2 • Avg: 14.5 ms
			Latest event: Processing degraded
			"""
		)
	}

	func testLocalizationKeysCoverAllDiagnosticEventKinds() {
		for kind in BrowserCameraDiagnosticEventKind.allCases {
			let key = BrowserCameraDiagnosticLocalizationKey(kind: kind)
			XCTAssertFalse(key.fallbackValue(localeIdentifier: nil).isEmpty)
			XCTAssertFalse(key.fallbackValue(localeIdentifier: "ja").isEmpty)
		}
	}

	func testFormatterIncludesPipelineRuntimeStateWhenAvailable() {
		let text = BrowserCameraDiagnosticsFormatter.text(
			from: makeSummary(
				publisherStatus: .notRequired,
				pipelineRuntimeState: BrowserCameraPipelineRuntimeState(
					preset: .folia,
					implementation: .aperture,
					warmupProfile: .chromaticFolia,
					grainPresence: .normal,
					requiredFilterCount: 7
				)
			),
			routingFormat: "Routing: %@",
			consumersFormat: "Live consumers: %d • Preview consumers: %d",
			framesFormat: "Frames: %d • Dropped: %d • Avg: %@ ms",
			pipelineFormat: "Pipeline: %@ • %@ • %d filters",
			browserTransportFormat: "Browser transport: tabs %d • Tracks: %d • Fallback: %d",
			latestEventFormat: "Latest event: %@",
			publisherFormat: "Publisher: %@ • Transport: %@",
			unknownTransport: "Unknown",
			localizeDiagnosticEvent: { $0.fallbackValue(localeIdentifier: nil) },
			localizedRoutingAvailability: {
				switch $0 {
				case .available:
					"Managed output available"
				default:
					$0.rawValue
				}
			},
			localizedPublisherState: { $0.rawValue },
			localizedPublisherTransport: { $0.rawValue }
		)

		XCTAssertEqual(
			text,
			"""
			Routing: Managed output available
			Live consumers: 1 • Preview consumers: 1
			Frames: 24 • Dropped: 2 • Avg: 14.5 ms
			Pipeline: aperture • chromatic.folia • 7 filters
			"""
		)
	}

	private func makeSummary(
		publisherStatus: BrowserCameraVirtualPublisherStatus,
		performanceMetrics: BrowserCameraPerformanceMetrics = BrowserCameraPerformanceMetrics(
			processedFrameCount: 24,
			droppedFrameCount: 2,
			firstFrameLatencyMilliseconds: 70.0,
			averageProcessingLatencyMilliseconds: 14.5,
			lastProcessingLatencyMilliseconds: 15.0,
			realtimeBudgetExceeded: false
		),
		pipelineRuntimeState: BrowserCameraPipelineRuntimeState? = nil,
		browserTransportStates: [BrowserCameraBrowserTransportState] = [],
		recentDiagnosticEvents: [BrowserCameraDiagnosticEvent] = []
	) -> BrowserCameraDebugSummary {
		BrowserCameraDebugSummary(
			lifecycleState: .running,
			healthState: .healthy,
			outputMode: publisherStatus.state == .notRequired
				? .processedNavigatorFeed
				: .systemVirtualCameraPublication,
			selectedSourceID: "camera-main",
			selectedSourceName: "FaceTime HD Camera",
			selectedFilterPreset: .folia,
			pipelineRuntimeState: pipelineRuntimeState,
			activeLiveFrameConsumerIDs: ["tab-1"],
			activePreviewConsumerIDs: ["preview-1"],
			managedRoutingSummary: BrowserCameraManagedRoutingSummary(
				availability: .available,
				genericVideoUsesManagedOutput: true,
				failClosedOnManagedVideoRequest: false,
				exposesManagedDeviceIdentity: true
			),
			performanceMetrics: performanceMetrics,
			lastErrorDescription: nil,
			publisherStatus: publisherStatus,
			browserTransportStates: browserTransportStates,
			recentDiagnosticEvents: recentDiagnosticEvents
		)
	}
}
