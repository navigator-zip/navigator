import BrowserRuntime
import Foundation
import ModelKit

enum BrowserDiagnosticsReportBuilder {
	private enum AdditionalLocalizationKey: String {
		case cameraPipelineRuntimeLabel = "navigator.debug.label.cameraPipelineRuntime"
		case cameraPublisherEmbeddingStateLabel = "navigator.debug.label.cameraPublisherEmbeddingState"
		case cameraPublisherApprovalStateLabel = "navigator.debug.label.cameraPublisherApprovalState"
		case cameraPublisherReachabilityStateLabel = "navigator.debug.label.cameraPublisherReachabilityState"
		case cameraPublisherProtocolCompatibilityLabel = "navigator.debug.label.cameraPublisherProtocolCompatibilityState"
		case cameraPublisherProtocolVersionLabel = "navigator.debug.label.cameraPublisherProtocolVersion"
		case cameraPublisherHeartbeatAgeLabel = "navigator.debug.label.cameraPublisherHeartbeatAge"
		case cameraPublisherReconnectCountLabel = "navigator.debug.label.cameraPublisherReconnectCount"
		case cameraPublisherPlaceholderActiveLabel = "navigator.debug.label.cameraPublisherPlaceholderActive"
		case cameraPublisherTransportErrorLabel = "navigator.debug.label.cameraPublisherTransportError"
		case cameraPublisherExtensionFailureLabel = "navigator.debug.label.cameraPublisherExtensionFailure"

		var fallbackEnglish: String {
			switch self {
			case .cameraPipelineRuntimeLabel:
				"Pipeline runtime"
			case .cameraPublisherEmbeddingStateLabel:
				"Publisher embedding state"
			case .cameraPublisherApprovalStateLabel:
				"Publisher approval state"
			case .cameraPublisherReachabilityStateLabel:
				"Publisher reachability"
			case .cameraPublisherProtocolCompatibilityLabel:
				"Publisher protocol compatibility"
			case .cameraPublisherProtocolVersionLabel:
				"Publisher protocol version"
			case .cameraPublisherHeartbeatAgeLabel:
				"Publisher heartbeat age"
			case .cameraPublisherReconnectCountLabel:
				"Publisher reconnect count"
			case .cameraPublisherPlaceholderActiveLabel:
				"Publisher placeholder active"
			case .cameraPublisherTransportErrorLabel:
				"Publisher transport error"
			case .cameraPublisherExtensionFailureLabel:
				"Publisher extension failure"
			}
		}
	}

	static func makeReport(
		from snapshot: BrowserRuntimeDiagnostics,
		hostSnapshot: BrowserDiagnosticsHostSnapshot,
		cameraSnapshot: BrowserCameraSessionSnapshot,
		crashReports: [URL],
		chromeDebugLogLines: [String],
		localize: (BrowserDiagnosticsLocalizationKey) -> String,
		localizeCameraDiagnosticEvent: (NavigatorCameraDiagnosticLocalizationKey) -> String,
		additionalLocalizationLookup: (String) -> String = { key in
			Bundle.main.localizedString(forKey: key, value: key, table: nil)
		},
		formatTimestamp: (Date) -> String
	) -> String {
		let latestCrashReports = crashReports.prefix(5)

		var lines = [String]()
		lines.append(sectionTitle(.appSection, localize: localize))
		lines.append(row(
			.bundleIdentifierLabel,
			value: hostSnapshot.bundleIdentifier ?? localize(.noneValue),
			localize: localize
		))
		lines.append(row(.versionLabel, value: hostSnapshot.versionDescription, localize: localize))
		lines.append(row(.bundlePathLabel, value: hostSnapshot.bundlePath, localize: localize))
		lines.append(row(
			.resourcePathLabel,
			value: hostSnapshot.resourcePath ?? localize(.noneValue),
			localize: localize
		))
		lines.append("")
		lines.append(sectionTitle(.windowsSection, localize: localize))
		lines.append(row(.windowCountLabel, value: "\(hostSnapshot.windowCount)", localize: localize))
		lines.append(row(
			.visibleWindowCountLabel,
			value: "\(hostSnapshot.visibleWindowCount)",
			localize: localize
		))
		lines.append(row(
			.keyWindowTitleLabel,
			value: hostSnapshot.keyWindowTitle ?? localize(.noneValue),
			localize: localize
		))
		lines.append("")
		lines.append(sectionTitle(.runtimeSection, localize: localize))
		lines.append(row(
			.runtimeInitializedLabel,
			value: booleanValue(snapshot.isInitialized, localize: localize),
			localize: localize
		))
		lines.append(row(
			.trackedBrowserLabel,
			value: booleanValue(snapshot.hasTrackedBrowser, localize: localize),
			localize: localize
		))
		lines.append(row(
			.trackedBrowserCountLabel,
			value: "\(snapshot.trackedBrowserCount)",
			localize: localize
		))
		lines.append(row(
			.trackedBrowserIdentifierLabel,
			value: snapshot.trackedBrowserIdentifier ?? localize(.noneValue),
			localize: localize
		))
		lines.append(row(
			.currentURLLabel,
			value: snapshot.currentURL ?? localize(.noneValue),
			localize: localize
		))
		lines.append(row(
			.isLoadingLabel,
			value: optionalBooleanValue(snapshot.isLoading, localize: localize),
			localize: localize
		))
		lines.append(row(
			.canGoBackLabel,
			value: optionalBooleanValue(snapshot.canGoBack, localize: localize),
			localize: localize
		))
		lines.append(row(
			.canGoForwardLabel,
			value: optionalBooleanValue(snapshot.canGoForward, localize: localize),
			localize: localize
		))
		lines.append(row(
			.lastUserActivityAgeLabel,
			value: secondsDescription(snapshot.lastUserActivityAgeSeconds),
			localize: localize
		))
		lines.append(row(
			.lastActivitySignalAgeLabel,
			value: secondsDescription(snapshot.lastActivitySignalAgeSeconds),
			localize: localize
		))
		lines.append("")
		lines.append(contentsOf: cameraReportLines(
			from: cameraSnapshot,
			localize: localize,
			localizeCameraDiagnosticEvent: localizeCameraDiagnosticEvent,
			additionalLocalizationLookup: additionalLocalizationLookup
		))
		lines.append("")
		lines.append(sectionTitle(.pathsSection, localize: localize))
		lines.append(pathRow(
			.resourcesPathLabel,
			path: snapshot.resourcesPath,
			exists: snapshot.resourcesPathExists,
			localize: localize
		))
		lines.append(pathRow(
			.localesPathLabel,
			path: snapshot.localesPath,
			exists: snapshot.localesPathExists,
			localize: localize
		))
		lines.append(pathRow(
			.cachePathLabel,
			path: snapshot.cachePath,
			exists: snapshot.cachePathExists,
			localize: localize
		))
		lines.append(pathRow(
			.helperPathLabel,
			path: snapshot.subprocessPath,
			exists: snapshot.subprocessPathExists,
			localize: localize
		))
		lines.append("")
		lines.append(sectionTitle(.crashReportsSection, localize: localize))
		if latestCrashReports.isEmpty {
			lines.append(itemLine(localize(.noCrashReportsValue)))
		}
		else {
			for reportURL in latestCrashReports {
				lines.append(itemLine(crashReportDescription(
					for: reportURL,
					formatTimestamp: formatTimestamp
				)))
			}
		}
		lines.append("")
		lines.append(sectionTitle(.chromeDebugLogSection, localize: localize))
		if chromeDebugLogLines.isEmpty {
			lines.append(itemLine(localize(.noCEFLogValue)))
		}
		else {
			lines.append(contentsOf: chromeDebugLogLines.map { itemLine($0) })
		}

		return lines.joined(separator: "\n")
	}

	private static func row(
		_ key: BrowserDiagnosticsLocalizationKey,
		value: String,
		localize: (BrowserDiagnosticsLocalizationKey) -> String
	) -> String {
		"\(localize(key)): \(value)"
	}

	private static func row(_ label: String, value: String) -> String {
		"\(label): \(value)"
	}

	private static func pathRow(
		_ key: BrowserDiagnosticsLocalizationKey,
		path: String,
		exists: Bool,
		localize: (BrowserDiagnosticsLocalizationKey) -> String
	) -> String {
		let status = exists
			? localize(.pathExistsValue)
			: localize(.pathMissingValue)
		return row(key, value: "\(path) [\(status)]", localize: localize)
	}

	private static func sectionTitle(
		_ key: BrowserDiagnosticsLocalizationKey,
		localize: (BrowserDiagnosticsLocalizationKey) -> String
	) -> String {
		localize(key)
	}

	private static func cameraReportLines(
		from snapshot: BrowserCameraSessionSnapshot,
		localize: (BrowserDiagnosticsLocalizationKey) -> String,
		localizeCameraDiagnosticEvent: (NavigatorCameraDiagnosticLocalizationKey) -> String,
		additionalLocalizationLookup: (String) -> String
	) -> [String] {
		let debugSummary = snapshot.debugSummary
		let routingSummary = snapshot.managedRoutingSummary
		var lines = [String]()
		lines.append(sectionTitle(.cameraSection, localize: localize))
		lines.append(row(.cameraLifecycleLabel, value: debugSummary.lifecycleState.rawValue, localize: localize))
		lines.append(row(.cameraHealthLabel, value: debugSummary.healthState.rawValue, localize: localize))
		lines.append(row(.cameraOutputModeLabel, value: debugSummary.outputMode.rawValue, localize: localize))
		lines.append(row(
			.cameraSelectedSourceLabel,
			value: debugSummary.selectedSourceName
				?? debugSummary.selectedSourceID
				?? localize(.noneValue),
			localize: localize
		))
		lines.append(row(
			.cameraSelectedPresetLabel,
			value: debugSummary.selectedFilterPreset.rawValue,
			localize: localize
		))
		lines.append(row(
			.cameraRoutingEnabledLabel,
			value: booleanValue(snapshot.routingSettings.routingEnabled, localize: localize),
			localize: localize
		))
		lines.append(row(
			.cameraPreferNavigatorCameraLabel,
			value: booleanValue(
				snapshot.routingSettings.preferNavigatorCameraWhenPossible,
				localize: localize
			),
			localize: localize
		))
		lines.append(row(
			.cameraPreviewEnabledLabel,
			value: booleanValue(snapshot.routingSettings.previewEnabled, localize: localize),
			localize: localize
		))
		lines.append(row(
			.cameraManagedRoutingAvailabilityLabel,
			value: routingSummary.availability.rawValue,
			localize: localize
		))
		lines.append(row(
			.cameraGenericManagedOutputLabel,
			value: booleanValue(routingSummary.genericVideoUsesManagedOutput, localize: localize),
			localize: localize
		))
		lines.append(row(
			.cameraFailClosedLabel,
			value: booleanValue(routingSummary.failClosedOnManagedVideoRequest, localize: localize),
			localize: localize
		))
		lines.append(row(
			.cameraManagedDeviceIdentityLabel,
			value: booleanValue(routingSummary.exposesManagedDeviceIdentity, localize: localize),
			localize: localize
		))
		lines.append(row(
			.cameraLiveConsumersLabel,
			value: consumerDescription(debugSummary.activeLiveFrameConsumerIDs),
			localize: localize
		))
		lines.append(row(
			.cameraPreviewConsumersLabel,
			value: consumerDescription(debugSummary.activePreviewConsumerIDs),
			localize: localize
		))
		lines.append(row(
			.cameraBrowserTransportTabsLabel,
			value: browserTransportDescription(debugSummary.browserTransportStates),
			localize: localize
		))
		lines.append(row(
			.cameraProcessedFramesLabel,
			value: "\(debugSummary.performanceMetrics.processedFrameCount)",
			localize: localize
		))
		lines.append(row(
			.cameraDroppedFramesLabel,
			value: "\(debugSummary.performanceMetrics.droppedFrameCount)",
			localize: localize
		))
		lines.append(row(
			.cameraFirstFrameLatencyLabel,
			value: millisecondsDescription(
				debugSummary.performanceMetrics.firstFrameLatencyMilliseconds,
				localize: localize
			),
			localize: localize
		))
		lines.append(row(
			.cameraAverageLatencyLabel,
			value: millisecondsDescription(
				debugSummary.performanceMetrics.averageProcessingLatencyMilliseconds,
				localize: localize
			),
			localize: localize
		))
		lines.append(row(
			localized(.cameraPipelineRuntimeLabel, lookup: additionalLocalizationLookup),
			value: pipelineRuntimeDescription(
				debugSummary.pipelineRuntimeState,
				localize: localize
			)
		))
		lines.append(row(
			.cameraPublisherStateLabel,
			value: debugSummary.publisherStatus.state.rawValue,
			localize: localize
		))
		lines.append(row(
			.cameraPublisherTransportLabel,
			value: debugSummary.publisherStatus.configuration?.transportMode.rawValue
				?? localize(.noneValue),
			localize: localize
		))
		lines.append(row(
			localized(.cameraPublisherEmbeddingStateLabel, lookup: additionalLocalizationLookup),
			value: debugSummary.publisherStatus.embeddingState.rawValue
		))
		lines.append(row(
			localized(.cameraPublisherApprovalStateLabel, lookup: additionalLocalizationLookup),
			value: debugSummary.publisherStatus.approvalState.rawValue
		))
		lines.append(row(
			localized(.cameraPublisherReachabilityStateLabel, lookup: additionalLocalizationLookup),
			value: debugSummary.publisherStatus.reachabilityState.rawValue
		))
		lines.append(row(
			localized(.cameraPublisherProtocolCompatibilityLabel, lookup: additionalLocalizationLookup),
			value: debugSummary.publisherStatus.protocolCompatibilityState.rawValue
		))
		lines.append(row(
			localized(.cameraPublisherProtocolVersionLabel, lookup: additionalLocalizationLookup),
			value: debugSummary.publisherStatus.transportConfiguration.map { "\($0.protocolVersion)" }
				?? localize(.noneValue)
		))
		lines.append(row(
			localized(.cameraPublisherHeartbeatAgeLabel, lookup: additionalLocalizationLookup),
			value: debugSummary.publisherStatus.healthSnapshot?.heartbeatAgeSeconds.map {
				secondsDescription($0)
			} ?? localize(.noneValue)
		))
		lines.append(row(
			localized(.cameraPublisherReconnectCountLabel, lookup: additionalLocalizationLookup),
			value: debugSummary.publisherStatus.healthSnapshot.map { "\($0.reconnectCount)" }
				?? localize(.noneValue)
		))
		lines.append(row(
			localized(.cameraPublisherPlaceholderActiveLabel, lookup: additionalLocalizationLookup),
			value: optionalBooleanValue(
				debugSummary.publisherStatus.healthSnapshot?.placeholderFrameActive,
				localize: localize
			)
		))
		lines.append(row(
			localized(.cameraPublisherTransportErrorLabel, lookup: additionalLocalizationLookup),
			value: debugSummary.publisherStatus.lastTransportErrorDescription ?? localize(.noneValue)
		))
		lines.append(row(
			localized(.cameraPublisherExtensionFailureLabel, lookup: additionalLocalizationLookup),
			value: debugSummary.publisherStatus.lastExtensionFailureDescription ?? localize(.noneValue)
		))
		lines.append(row(
			.cameraLastErrorLabel,
			value: debugSummary.lastErrorDescription ?? localize(.noneValue),
			localize: localize
		))
		lines.append("")
		lines.append(sectionTitle(.cameraEventsSection, localize: localize))
		if debugSummary.recentDiagnosticEvents.isEmpty {
			lines.append(itemLine(localize(.noCameraEventsValue)))
		}
		else {
			for event in debugSummary.recentDiagnosticEvents {
				lines.append(itemLine(cameraEventDescription(
					event,
					localizeCameraDiagnosticEvent: localizeCameraDiagnosticEvent
				)))
			}
		}
		return lines
	}

	private static func itemLine(_ text: String) -> String {
		"- \(text)"
	}

	private static func consumerDescription(_ consumerIDs: [String]) -> String {
		guard consumerIDs.isEmpty == false else { return "0" }
		return "\(consumerIDs.count) [\(consumerIDs.joined(separator: ", "))]"
	}

	private static func browserTransportDescription(
		_ states: [BrowserCameraBrowserTransportState]
	) -> String {
		guard states.isEmpty == false else { return "0" }
		let values = states.map { state in
			"\(state.tabID):routing=\(state.routingTransportMode.rawValue) frame=\(state.frameTransportMode.rawValue) tracks=\(state.activeManagedTrackCount)"
		}
		return "\(states.count) [\(values.joined(separator: "; "))]"
	}

	private static func booleanValue(
		_ value: Bool,
		localize: (BrowserDiagnosticsLocalizationKey) -> String
	) -> String {
		value ? localize(.yesValue) : localize(.noValue)
	}

	private static func optionalBooleanValue(
		_ value: Bool?,
		localize: (BrowserDiagnosticsLocalizationKey) -> String
	) -> String {
		guard let value else { return localize(.noneValue) }
		return booleanValue(value, localize: localize)
	}

	private static func secondsDescription(_ seconds: TimeInterval) -> String {
		String(format: "%.3fs", seconds)
	}

	private static func millisecondsDescription(
		_ milliseconds: Double?,
		localize: (BrowserDiagnosticsLocalizationKey) -> String
	) -> String {
		guard let milliseconds else { return localize(.noneValue) }
		return String(format: "%.3fms", milliseconds)
	}

	private static func pipelineRuntimeDescription(
		_ runtimeState: BrowserCameraPipelineRuntimeState?,
		localize: (BrowserDiagnosticsLocalizationKey) -> String
	) -> String {
		guard let runtimeState else { return localize(.noneValue) }
		return "\(runtimeState.implementation.rawValue) • \(runtimeState.warmupProfile.rawValue) • filters=\(runtimeState.requiredFilterCount)"
	}

	private static func localized(
		_ key: AdditionalLocalizationKey,
		lookup: (String) -> String
	) -> String {
		let localizedValue = lookup(key.rawValue)
		return localizedValue == key.rawValue ? key.fallbackEnglish : localizedValue
	}

	private static func cameraEventDescription(
		_ event: BrowserCameraDiagnosticEvent,
		localizeCameraDiagnosticEvent: (NavigatorCameraDiagnosticLocalizationKey) -> String
	) -> String {
		NavigatorCameraDiagnosticEventTextResolver.description(
			event,
			localized: localizeCameraDiagnosticEvent
		)
	}

	private static func crashReportDescription(
		for url: URL,
		formatTimestamp: (Date) -> String
	) -> String {
		let modificationDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
		if let modificationDate {
			return "\(url.lastPathComponent) (\(formatTimestamp(modificationDate)))"
		}
		return url.lastPathComponent
	}
}

extension BrowserDiagnosticsLocalizationKey {
	var fallbackEnglish: String {
		switch self {
		case .appSection:
			"App"
		case .cameraSection:
			"Camera"
		case .cameraEventsSection:
			"Recent camera events"
		case .windowsSection:
			"Windows"
		case .runtimeSection:
			"Browser runtime"
		case .pathsSection:
			"CEF paths"
		case .crashReportsSection:
			"Recent crash reports"
		case .chromeDebugLogSection:
			"CEF log tail"
		case .bundleIdentifierLabel:
			"Bundle identifier"
		case .versionLabel:
			"Version"
		case .bundlePathLabel:
			"Bundle path"
		case .resourcePathLabel:
			"Resource path"
		case .cameraAverageLatencyLabel:
			"Average processing latency"
		case .cameraDroppedFramesLabel:
			"Dropped frames"
		case .cameraFailClosedLabel:
			"Fail closed when unavailable"
		case .cameraFirstFrameLatencyLabel:
			"First frame latency"
		case .cameraGenericManagedOutputLabel:
			"Generic video uses managed output"
		case .cameraHealthLabel:
			"Camera health"
		case .cameraLastErrorLabel:
			"Camera last error"
		case .cameraLifecycleLabel:
			"Camera lifecycle"
		case .cameraLiveConsumersLabel:
			"Live consumers"
		case .cameraBrowserTransportTabsLabel:
			"Browser transport tabs"
		case .cameraManagedDeviceIdentityLabel:
			"Managed device exposed"
		case .cameraManagedRoutingAvailabilityLabel:
			"Managed routing availability"
		case .cameraOutputModeLabel:
			"Camera output mode"
		case .cameraPreviewEnabledLabel:
			"Preview enabled"
		case .cameraPreferNavigatorCameraLabel:
			"Prefer Navigator camera"
		case .cameraPreviewConsumersLabel:
			"Preview consumers"
		case .cameraProcessedFramesLabel:
			"Processed frames"
		case .cameraPublisherStateLabel:
			"Publisher state"
		case .cameraPublisherTransportLabel:
			"Publisher transport"
		case .cameraRoutingEnabledLabel:
			"Routing enabled"
		case .cameraSelectedPresetLabel:
			"Selected preset"
		case .cameraSelectedSourceLabel:
			"Selected source"
		case .windowCountLabel:
			"Window count"
		case .visibleWindowCountLabel:
			"Visible window count"
		case .keyWindowTitleLabel:
			"Key window title"
		case .runtimeInitializedLabel:
			"Runtime initialized"
		case .trackedBrowserLabel:
			"Tracked browser"
		case .trackedBrowserCountLabel:
			"Tracked browser count"
		case .trackedBrowserIdentifierLabel:
			"Tracked browser identifier"
		case .currentURLLabel:
			"Current URL"
		case .isLoadingLabel:
			"Is loading"
		case .canGoBackLabel:
			"Can go back"
		case .canGoForwardLabel:
			"Can go forward"
		case .lastUserActivityAgeLabel:
			"Last user activity age"
		case .lastActivitySignalAgeLabel:
			"Last activity signal age"
		case .resourcesPathLabel:
			"Resources path"
		case .localesPathLabel:
			"Locales path"
		case .cachePathLabel:
			"Cache path"
		case .helperPathLabel:
			"Helper path"
		case .noneValue:
			"none"
		case .yesValue:
			"yes"
		case .noValue:
			"no"
		case .pathExistsValue:
			"exists"
		case .pathMissingValue:
			"missing"
		case .noCrashReportsValue:
			"No recent crash reports found"
		case .noCEFLogValue:
			"No `chrome_debug.log` output available yet."
		case .noCameraEventsValue:
			"No recent camera events recorded"
		}
	}
}
