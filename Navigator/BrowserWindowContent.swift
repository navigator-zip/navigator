import AppKit

@MainActor
protocol NavigatorBrowserWindowContent: AnyObject {
	var navigatorAppViewModel: AppViewModel { get }
}
