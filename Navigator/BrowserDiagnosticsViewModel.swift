import AppKit
import BrowserCameraKit
import BrowserRuntime
import Foundation
import ModelKit
import Observation
import Vendors

@MainActor
struct BrowserDiagnosticsHostSnapshot {
	let bundleIdentifier: String?
	let versionDescription: String
	let bundlePath: String
	let resourcePath: String?
	let windowCount: Int
	let visibleWindowCount: Int
	let keyWindowTitle: String?
}

private enum BrowserDiagnosticsDefaults {
	static let chromeDebugLogTailLineCount = 40
}

@MainActor
@Observable
final class BrowserDiagnosticsViewModel {
	var canReloadBrowser = false
	var reportText = ""

	@ObservationIgnored
	private let runtimeSnapshotProvider: @MainActor () -> BrowserRuntimeDiagnostics
	@ObservationIgnored
	private let reloadBrowserHandler: @MainActor () -> Bool
	@ObservationIgnored
	private let hostSnapshotProvider: @MainActor () -> BrowserDiagnosticsHostSnapshot
	@ObservationIgnored
	private let cameraSnapshotProvider: @MainActor () -> BrowserCameraSessionSnapshot
	@ObservationIgnored
	private let diagnosticReportURLsProvider: @MainActor () -> [URL]
	@ObservationIgnored
	private let tailLinesProvider: @MainActor (URL, Int) -> [String]
	@ObservationIgnored
	private let copyReportHandler: @MainActor (String) -> Void
	@ObservationIgnored
	private let revealItemHandler: @MainActor (URL) -> Void
	@ObservationIgnored
	private let diagnosticReportsDirectoryURLProvider: @MainActor () -> URL
	@ObservationIgnored
	private let localizeHandler: @MainActor (BrowserDiagnosticsLocalizationKey) -> String
	@ObservationIgnored
	private let localizeCameraDiagnosticEventHandler: @MainActor (NavigatorCameraDiagnosticLocalizationKey) -> String
	@ObservationIgnored
	private let timestampFormatterHandler: @MainActor (Date) -> String

	init() {
		@Dependency(\.browserRuntime) var browserRuntime
		runtimeSnapshotProvider = { browserRuntime.diagnosticsSnapshot() }
		reloadBrowserHandler = { browserRuntime.reloadTrackedBrowser() }
		hostSnapshotProvider = Self.liveHostSnapshot
		cameraSnapshotProvider = { BrowserCameraSessionCoordinator.shared.currentSnapshot() }
		diagnosticReportURLsProvider = Self.liveDiagnosticReportURLs
		tailLinesProvider = { url, count in
			Self.liveTailLines(in: url, count: count)
		}
		copyReportHandler = Self.liveCopyReport
		revealItemHandler = Self.liveRevealFileSystemItem
		diagnosticReportsDirectoryURLProvider = Self.liveDiagnosticReportsDirectoryURL
		localizeHandler = Self.liveLocalized
		localizeCameraDiagnosticEventHandler = Self.liveLocalizedCameraDiagnosticEvent
		timestampFormatterHandler = { Self.timestampFormatter.string(from: $0) }
		refresh()
	}

	init(
		runtimeSnapshot: @escaping @MainActor () -> BrowserRuntimeDiagnostics,
		reloadBrowser: @escaping @MainActor () -> Bool,
		hostSnapshot: @escaping @MainActor () -> BrowserDiagnosticsHostSnapshot,
		cameraSnapshot: @escaping @MainActor () -> BrowserCameraSessionSnapshot,
		diagnosticReportURLs: @escaping @MainActor () -> [URL],
		tailLines: @escaping @MainActor (URL, Int) -> [String],
		copyReport: @escaping @MainActor (String) -> Void,
		revealItem: @escaping @MainActor (URL) -> Void,
		diagnosticReportsDirectoryURL: @escaping @MainActor () -> URL,
		localize: @escaping @MainActor (BrowserDiagnosticsLocalizationKey) -> String,
		localizeCameraDiagnosticEvent: @escaping @MainActor (NavigatorCameraDiagnosticLocalizationKey) -> String,
		formatTimestamp: @escaping @MainActor (Date) -> String
	) {
		runtimeSnapshotProvider = runtimeSnapshot
		reloadBrowserHandler = reloadBrowser
		hostSnapshotProvider = hostSnapshot
		cameraSnapshotProvider = cameraSnapshot
		diagnosticReportURLsProvider = diagnosticReportURLs
		tailLinesProvider = tailLines
		copyReportHandler = copyReport
		revealItemHandler = revealItem
		diagnosticReportsDirectoryURLProvider = diagnosticReportsDirectoryURL
		localizeHandler = localize
		localizeCameraDiagnosticEventHandler = localizeCameraDiagnosticEvent
		timestampFormatterHandler = formatTimestamp
		refresh()
	}

	func refresh() {
		let snapshot = runtimeSnapshotProvider()
		canReloadBrowser = snapshot.hasTrackedBrowser
		let cameraSnapshot = cameraSnapshotProvider()
		let crashReports = diagnosticReportURLsProvider()
		let chromeDebugLogURL = URL(fileURLWithPath: snapshot.cachePath, isDirectory: true)
			.appendingPathComponent("chrome_debug.log", isDirectory: false)
		let chromeDebugLogLines = tailLinesProvider(
			chromeDebugLogURL,
			BrowserDiagnosticsDefaults.chromeDebugLogTailLineCount
		)
		reportText = makeReport(
			from: snapshot,
			hostSnapshot: hostSnapshotProvider(),
			cameraSnapshot: cameraSnapshot,
			crashReports: crashReports,
			chromeDebugLogLines: chromeDebugLogLines
		)
	}

	func reloadBrowser() {
		guard reloadBrowserHandler() else { return }
		refresh()
	}

	func copyReport() {
		guard !reportText.isEmpty else { return }
		copyReportHandler(reportText)
	}

	func revealCacheFolder() {
		let snapshot = runtimeSnapshotProvider()
		revealItemHandler(URL(fileURLWithPath: snapshot.cachePath, isDirectory: true))
	}

	func revealCrashReportsFolder() {
		revealItemHandler(diagnosticReportsDirectoryURLProvider())
	}

	private func makeReport(
		from snapshot: BrowserRuntimeDiagnostics,
		hostSnapshot: BrowserDiagnosticsHostSnapshot,
		cameraSnapshot: BrowserCameraSessionSnapshot,
		crashReports: [URL],
		chromeDebugLogLines: [String]
	) -> String {
		BrowserDiagnosticsReportBuilder.makeReport(
			from: snapshot,
			hostSnapshot: hostSnapshot,
			cameraSnapshot: cameraSnapshot,
			crashReports: crashReports,
			chromeDebugLogLines: chromeDebugLogLines,
			localize: localizeHandler,
			localizeCameraDiagnosticEvent: localizeCameraDiagnosticEventHandler,
			formatTimestamp: timestampFormatterHandler
		)
	}

	private static func liveHostSnapshot() -> BrowserDiagnosticsHostSnapshot {
		let bundle = Bundle.main
		let windows = NSApplication.shared.windows
		return BrowserDiagnosticsHostSnapshot(
			bundleIdentifier: bundle.bundleIdentifier,
			versionDescription: liveAppVersionDescription(bundle: bundle),
			bundlePath: bundle.bundlePath,
			resourcePath: bundle.resourcePath,
			windowCount: windows.count,
			visibleWindowCount: windows.filter(\.isVisible).count,
			keyWindowTitle: NSApplication.shared.keyWindow?.title.nilIfEmpty
		)
	}

	private static func liveAppVersionDescription(bundle: Bundle) -> String {
		let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
		let buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String

		switch (shortVersion?.nilIfEmpty, buildNumber?.nilIfEmpty) {
		case let (.some(shortVersion), .some(buildNumber)):
			return "\(shortVersion) (\(buildNumber))"
		case let (.some(shortVersion), nil):
			return shortVersion
		case let (nil, .some(buildNumber)):
			return buildNumber
		case (nil, nil):
			return "none"
		}
	}

	private static func liveDiagnosticReportsDirectoryURL() -> URL {
		FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
	}

	private static func liveDiagnosticReportURLs() -> [URL] {
		let directoryURL = liveDiagnosticReportsDirectoryURL()
		let fileManager = FileManager.default
		guard let reportURLs = try? fileManager.contentsOfDirectory(
			at: directoryURL,
			includingPropertiesForKeys: [.contentModificationDateKey],
			options: [.skipsHiddenFiles]
		) else {
			return []
		}

		return reportURLs
			.filter { url in
				let fileName = url.lastPathComponent
				let matchesNavigator = fileName.hasPrefix("Navigator")
				let matchesCrashSuffix = fileName.hasSuffix(".ips") || fileName.hasSuffix(".crash")
				return matchesNavigator && matchesCrashSuffix
			}
			.sorted { lhs, rhs in
				let lhsDate = try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
				let rhsDate = try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
				return (lhsDate ?? .distantPast) > (rhsDate ?? .distantPast)
			}
	}

	private static func liveTailLines(in url: URL, count: Int) -> [String] {
		guard let contents = try? String(contentsOf: url), !contents.isEmpty else { return [] }
		return contents
			.split(whereSeparator: \.isNewline)
			.suffix(count)
			.map(String.init)
	}

	private static func liveCopyReport(_ report: String) {
		let pasteboard = NSPasteboard.general
		pasteboard.clearContents()
		pasteboard.setString(report, forType: .string)
	}

	private static func liveRevealFileSystemItem(at url: URL) {
		let fileManager = FileManager.default
		if fileManager.fileExists(atPath: url.path) {
			NSWorkspace.shared.activateFileViewerSelecting([url])
			return
		}

		NSWorkspace.shared.open(url.deletingLastPathComponent())
	}

	private static func liveLocalized(_ key: BrowserDiagnosticsLocalizationKey) -> String {
		String(localized: key.resource)
	}

	private static func liveLocalizedCameraDiagnosticEvent(
		_ key: NavigatorCameraDiagnosticLocalizationKey
	) -> String {
		let localizedValue = Bundle.main.localizedString(
			forKey: key.rawValue,
			value: key.rawValue,
			table: nil
		)
		let localeIdentifier = Locale.preferredLanguages.first
		return localizedValue == key.rawValue ? key.fallbackValue(localeIdentifier: localeIdentifier) : localizedValue
	}

	private static let timestampFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .medium
		formatter.timeStyle = .medium
		return formatter
	}()
}

enum BrowserDiagnosticsLocalizationKey: String {
	case appSection = "navigator.debug.section.app"
	case cameraSection = "navigator.debug.section.camera"
	case cameraEventsSection = "navigator.debug.section.cameraEvents"
	case windowsSection = "navigator.debug.section.windows"
	case runtimeSection = "navigator.debug.section.runtime"
	case pathsSection = "navigator.debug.section.paths"
	case crashReportsSection = "navigator.debug.section.crashReports"
	case chromeDebugLogSection = "navigator.debug.section.chromeDebugLog"
	case bundleIdentifierLabel = "navigator.debug.label.bundleIdentifier"
	case versionLabel = "navigator.debug.label.version"
	case bundlePathLabel = "navigator.debug.label.bundlePath"
	case resourcePathLabel = "navigator.debug.label.resourcePath"
	case cameraAverageLatencyLabel = "navigator.debug.label.cameraAverageLatency"
	case cameraDroppedFramesLabel = "navigator.debug.label.cameraDroppedFrames"
	case cameraFailClosedLabel = "navigator.debug.label.cameraFailClosed"
	case cameraFirstFrameLatencyLabel = "navigator.debug.label.cameraFirstFrameLatency"
	case cameraGenericManagedOutputLabel = "navigator.debug.label.cameraGenericManagedOutput"
	case cameraHealthLabel = "navigator.debug.label.cameraHealth"
	case cameraLastErrorLabel = "navigator.debug.label.cameraLastError"
	case cameraLifecycleLabel = "navigator.debug.label.cameraLifecycle"
	case cameraLiveConsumersLabel = "navigator.debug.label.cameraLiveConsumers"
	case cameraBrowserTransportTabsLabel = "navigator.debug.label.cameraBrowserTransportTabs"
	case cameraManagedDeviceIdentityLabel = "navigator.debug.label.cameraManagedDeviceIdentity"
	case cameraManagedRoutingAvailabilityLabel = "navigator.debug.label.cameraManagedRoutingAvailability"
	case cameraOutputModeLabel = "navigator.debug.label.cameraOutputMode"
	case cameraPreviewEnabledLabel = "navigator.debug.label.cameraPreviewEnabled"
	case cameraPreferNavigatorCameraLabel = "navigator.debug.label.cameraPreferNavigatorCamera"
	case cameraPreviewConsumersLabel = "navigator.debug.label.cameraPreviewConsumers"
	case cameraProcessedFramesLabel = "navigator.debug.label.cameraProcessedFrames"
	case cameraPublisherStateLabel = "navigator.debug.label.cameraPublisherState"
	case cameraPublisherTransportLabel = "navigator.debug.label.cameraPublisherTransport"
	case cameraRoutingEnabledLabel = "navigator.debug.label.cameraRoutingEnabled"
	case cameraSelectedPresetLabel = "navigator.debug.label.cameraSelectedPreset"
	case cameraSelectedSourceLabel = "navigator.debug.label.cameraSelectedSource"
	case windowCountLabel = "navigator.debug.label.windowCount"
	case visibleWindowCountLabel = "navigator.debug.label.visibleWindowCount"
	case keyWindowTitleLabel = "navigator.debug.label.keyWindowTitle"
	case runtimeInitializedLabel = "navigator.debug.label.runtimeInitialized"
	case trackedBrowserLabel = "navigator.debug.label.trackedBrowser"
	case trackedBrowserCountLabel = "navigator.debug.label.trackedBrowserCount"
	case trackedBrowserIdentifierLabel = "navigator.debug.label.trackedBrowserIdentifier"
	case currentURLLabel = "navigator.debug.label.currentURL"
	case isLoadingLabel = "navigator.debug.label.isLoading"
	case canGoBackLabel = "navigator.debug.label.canGoBack"
	case canGoForwardLabel = "navigator.debug.label.canGoForward"
	case lastUserActivityAgeLabel = "navigator.debug.label.lastUserActivityAge"
	case lastActivitySignalAgeLabel = "navigator.debug.label.lastActivitySignalAge"
	case resourcesPathLabel = "navigator.debug.label.resourcesPath"
	case localesPathLabel = "navigator.debug.label.localesPath"
	case cachePathLabel = "navigator.debug.label.cachePath"
	case helperPathLabel = "navigator.debug.label.helperPath"
	case noneValue = "navigator.debug.value.none"
	case yesValue = "navigator.debug.value.yes"
	case noValue = "navigator.debug.value.no"
	case pathExistsValue = "navigator.debug.value.exists"
	case pathMissingValue = "navigator.debug.value.missing"
	case noCrashReportsValue = "navigator.debug.value.noCrashReports"
	case noCEFLogValue = "navigator.debug.value.noCEFLog"
	case noCameraEventsValue = "navigator.debug.value.noCameraEvents"
}

@available(macOS 13, *)
private extension BrowserDiagnosticsLocalizationKey {
	var resource: LocalizedStringResource {
		switch self {
		case .appSection:
			return .navigatorDebugSectionApp
		case .cameraSection:
			return .navigatorDebugSectionCamera
		case .cameraEventsSection:
			return .navigatorDebugSectionCameraEvents
		case .windowsSection:
			return .navigatorDebugSectionWindows
		case .runtimeSection:
			return .navigatorDebugSectionRuntime
		case .pathsSection:
			return .navigatorDebugSectionPaths
		case .crashReportsSection:
			return .navigatorDebugSectionCrashReports
		case .chromeDebugLogSection:
			return .navigatorDebugSectionChromeDebugLog
		case .bundleIdentifierLabel:
			return .navigatorDebugLabelBundleIdentifier
		case .versionLabel:
			return .navigatorDebugLabelVersion
		case .bundlePathLabel:
			return .navigatorDebugLabelBundlePath
		case .resourcePathLabel:
			return .navigatorDebugLabelResourcePath
		case .cameraAverageLatencyLabel:
			return .navigatorDebugLabelCameraAverageLatency
		case .cameraDroppedFramesLabel:
			return .navigatorDebugLabelCameraDroppedFrames
		case .cameraFailClosedLabel:
			return .navigatorDebugLabelCameraFailClosed
		case .cameraFirstFrameLatencyLabel:
			return .navigatorDebugLabelCameraFirstFrameLatency
		case .cameraGenericManagedOutputLabel:
			return .navigatorDebugLabelCameraGenericManagedOutput
		case .cameraHealthLabel:
			return .navigatorDebugLabelCameraHealth
		case .cameraLastErrorLabel:
			return .navigatorDebugLabelCameraLastError
		case .cameraLifecycleLabel:
			return .navigatorDebugLabelCameraLifecycle
		case .cameraLiveConsumersLabel:
			return .navigatorDebugLabelCameraLiveConsumers
		case .cameraBrowserTransportTabsLabel:
			return .navigatorDebugLabelCameraBrowserTransportTabs
		case .cameraManagedDeviceIdentityLabel:
			return .navigatorDebugLabelCameraManagedDeviceIdentity
		case .cameraManagedRoutingAvailabilityLabel:
			return .navigatorDebugLabelCameraManagedRoutingAvailability
		case .cameraOutputModeLabel:
			return .navigatorDebugLabelCameraOutputMode
		case .cameraPreviewEnabledLabel:
			return .navigatorDebugLabelCameraPreviewEnabled
		case .cameraPreferNavigatorCameraLabel:
			return .navigatorDebugLabelCameraPreferNavigatorCamera
		case .cameraPreviewConsumersLabel:
			return .navigatorDebugLabelCameraPreviewConsumers
		case .cameraProcessedFramesLabel:
			return .navigatorDebugLabelCameraProcessedFrames
		case .cameraPublisherStateLabel:
			return .navigatorDebugLabelCameraPublisherState
		case .cameraPublisherTransportLabel:
			return .navigatorDebugLabelCameraPublisherTransport
		case .cameraRoutingEnabledLabel:
			return .navigatorDebugLabelCameraRoutingEnabled
		case .cameraSelectedPresetLabel:
			return .navigatorDebugLabelCameraSelectedPreset
		case .cameraSelectedSourceLabel:
			return .navigatorDebugLabelCameraSelectedSource
		case .windowCountLabel:
			return .navigatorDebugLabelWindowCount
		case .visibleWindowCountLabel:
			return .navigatorDebugLabelVisibleWindowCount
		case .keyWindowTitleLabel:
			return .navigatorDebugLabelKeyWindowTitle
		case .runtimeInitializedLabel:
			return .navigatorDebugLabelRuntimeInitialized
		case .trackedBrowserLabel:
			return .navigatorDebugLabelTrackedBrowser
		case .trackedBrowserCountLabel:
			return .navigatorDebugLabelTrackedBrowserCount
		case .trackedBrowserIdentifierLabel:
			return .navigatorDebugLabelTrackedBrowserIdentifier
		case .currentURLLabel:
			return .navigatorDebugLabelCurrentURL
		case .isLoadingLabel:
			return .navigatorDebugLabelIsLoading
		case .canGoBackLabel:
			return .navigatorDebugLabelCanGoBack
		case .canGoForwardLabel:
			return .navigatorDebugLabelCanGoForward
		case .lastUserActivityAgeLabel:
			return .navigatorDebugLabelLastUserActivityAge
		case .lastActivitySignalAgeLabel:
			return .navigatorDebugLabelLastActivitySignalAge
		case .resourcesPathLabel:
			return .navigatorDebugLabelResourcesPath
		case .localesPathLabel:
			return .navigatorDebugLabelLocalesPath
		case .cachePathLabel:
			return .navigatorDebugLabelCachePath
		case .helperPathLabel:
			return .navigatorDebugLabelHelperPath
		case .noneValue:
			return .navigatorDebugValueNone
		case .yesValue:
			return .navigatorDebugValueYes
		case .noValue:
			return .navigatorDebugValueNo
		case .pathExistsValue:
			return .navigatorDebugValueExists
		case .pathMissingValue:
			return .navigatorDebugValueMissing
		case .noCrashReportsValue:
			return .navigatorDebugValueNoCrashReports
		case .noCEFLogValue:
			return .navigatorDebugValueNoCEFLog
		case .noCameraEventsValue:
			return .navigatorDebugValueNoCameraEvents
		}
	}
}

private extension String {
	var nilIfEmpty: String? {
		isEmpty ? nil : self
	}
}
