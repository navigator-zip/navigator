import AppKit
import BrowserRuntime
import Foundation

struct NavigatorAppRuntimeHooks {
	var argc: Int32 = .init(CommandLine.argc)
	var arguments: [String] = CommandLine.arguments
	var unsafeArgv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>? = CommandLine.unsafeArgv
	var maybeRunSubprocess: (Int32, UnsafeRawPointer) -> Int32 = { argc, argv in
		BrowserRuntime.maybeRunSubprocess(argc, argv)
	}

	var makeDelegate: () -> NSApplicationDelegate = {
		NavigatorAppDelegate()
	}

	var setDelegate: (NSApplicationDelegate) -> Void = { delegate in
		NSApplication.shared.delegate = delegate
	}

	var setActivationPolicyRegular: () -> Void = {
		NSApplication.shared.setActivationPolicy(.regular)
	}

	var activateIgnoringOtherApps: () -> Void = {
		NSApplication.shared.activate(ignoringOtherApps: true)
	}

	var runApplication: () -> Void = {
		NSApplication.shared.run()
	}

	var isRunningTests: () -> Bool = {
		NavigatorLaunchEnvironment.isRunningTests()
	}

	var exitProcess: (Int32) -> Void = { code in
		exit(code)
	}
}

enum NavigatorAppRuntime {
	static func run(hooks: NavigatorAppRuntimeHooks = .init()) {
		let argc = hooks.arguments.isEmpty ? hooks.argc : Int32(hooks.arguments.count)
		guard let unsafeArgv = hooks.unsafeArgv else {
			hooks.exitProcess(0)
			return
		}
		let argvPointer = UnsafeRawPointer(unsafeArgv)
		let isCefSubprocess = hooks.arguments.contains { $0.hasPrefix("--type=") }
		if isCefSubprocess {
			let subprocessExitCode = hooks.maybeRunSubprocess(argc, argvPointer)
			if subprocessExitCode >= 0 {
				hooks.exitProcess(Int32(subprocessExitCode))
				return
			}
			hooks.exitProcess(0)
			return
		}

		_ = hooks.maybeRunSubprocess(argc, argvPointer)

		let delegate = hooks.makeDelegate()
		hooks.setDelegate(delegate)
		if hooks.isRunningTests() == false {
			hooks.setActivationPolicyRegular()
			hooks.activateIgnoringOtherApps()
		}
		hooks.runApplication()
	}
}
