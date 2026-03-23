import AppKit
import BrowserCameraKit
import Foundation
import OSLog
import TrackpadGestures

let navigatorTrackpadGestureLogger = Logger(
	subsystem: "com.navigator.Navigator",
	category: "TrackpadGestures"
)

extension GestureDiagnosticEvent.Kind {
	var shouldEmitNavigatorConsoleLog: Bool {
		switch self {
		case .runtimeStateChanged,
		     .startupCompleted,
		     .startupFailed,
		     .permissionSnapshot,
		     .frameworkLoadFailed,
		     .symbolMissing,
		     .wakeRescanTriggered,
		     .recognizerMeasurement,
		     .gestureAccepted,
		     .gestureRejected,
		     .actionDispatched,
		     .killSwitchActivated:
			true
		case .sessionStarted,
		     .sessionStopped,
		     .osVersion,
		     .frameworkOpenAttempt,
		     .frameworkLoaded,
		     .frameworkOpened,
		     .frameworkReady,
		     .frameworkCloseAttempted,
		     .frameworkCloseSkipped,
		     .frameworkClosed,
		     .symbolResolved,
		     .deviceListCreationAttempt,
		     .deviceListCreationResult,
		     .deviceSelectionStrategy,
		     .frameworkSessionCreated,
		     .sessionCallbackRegistered,
		     .sessionDeviceStarted,
		     .sessionStateTransition,
		     .sessionShutdownRequested,
		     .callbackUnregistered,
		     .deviceStopped,
		     .deviceReleased,
		     .callbackIgnoredWhileStopping,
		     .callbackInFlightState,
		     .shutdownQuiescenceWaiting,
		     .shutdownQuiescenceComplete,
		     .deviceRegistered,
		     .deviceUnregistered,
		     .frameDropped,
		     .recognizerTransition:
			false
		}
	}
}

struct NavigatorAppDelegateHooks {
	var isRunningTests: () -> Bool = {
		NavigatorLaunchEnvironment.isRunningTests()
	}

	var isSettingsWindowFocused: () -> Bool = {
		NSApp.keyWindow?.windowController is NavigatorSettingsWindowController
	}

	var startBrowserRuntime: (() -> Void)?
	var makeTrackpadGestureLifecycle: (@escaping @MainActor () -> AppViewModel)
		-> (any NavigatorTrackpadGestureLifecycle)? = { navigatorAppViewModel in
			NavigatorTrackpadGestureServiceLifecycle.makeIfEnabled(
				resolveNavigatorAppViewModel: navigatorAppViewModel
			)
		}

	var logTrackpadGestureDiagnosticEvent: (GestureDiagnosticEvent) -> Void = { diagnosticEvent in
		guard diagnosticEvent.kind.shouldEmitNavigatorConsoleLog else { return }
		navigatorTrackpadGestureLogger.debug("\(String(describing: diagnosticEvent), privacy: .public)")
	}

	var shutdownBrowserRuntime: (() -> Void)?
	var makePrimaryContentViewController: (UUID, AppViewModel) -> NSViewController = { windowID, navigatorAppViewModel in
		BrowserRootViewController(
			windowID: windowID,
			navigatorAppViewModel: navigatorAppViewModel
		)
	}

	var addLocalKeyDownMonitor: (@escaping (NSEvent) -> NSEvent?) -> Any? = { handler in
		NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: handler)
	}

	var addGlobalKeyDownMonitor: (@escaping (NSEvent) -> Void) -> Any? = { handler in
		NSEvent.addGlobalMonitorForEvents(matching: [.keyDown], handler: handler)
	}

	var removeEventMonitor: (Any) -> Void = { monitor in
		NSEvent.removeMonitor(monitor)
	}

	var addSystemAppearanceObserver: (@escaping (Notification) -> Void) -> NSObjectProtocol = { handler in
		DistributedNotificationCenter.default().addObserver(
			forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
			object: nil,
			queue: .main,
			using: handler
		)
	}

	var removeSystemAppearanceObserver: (NSObjectProtocol) -> Void = { observer in
		DistributedNotificationCenter.default().removeObserver(observer)
	}

	var makeCameraStatusItemController: (
		@MainActor (any BrowserCameraSessionCoordinating) -> (any NavigatorCameraStatusItemControlling)?
	) = { browserCameraSessionCoordinator in
		guard NavigatorLaunchEnvironment.isRunningTests() == false else { return nil }
		return NavigatorCameraStatusItemController(
			browserCameraSessionCoordinator: browserCameraSessionCoordinator
		)
	}
}
