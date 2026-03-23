import AppKit

let appViewModel = AppViewModel()

enum NavigatorAppMain {
	static var runRuntime: () -> Void = {
		NavigatorAppRuntime.run()
	}
}

@main
final class NavigatorApp {
	static func main() {
		NavigatorAppMain.runRuntime()
	}
}
