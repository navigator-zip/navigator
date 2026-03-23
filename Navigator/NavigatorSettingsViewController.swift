import AppKit
import Observation
import Vendors

@MainActor
final class NavigatorSettingsViewController: NSViewController {
	private static let panelInset: CGFloat = 12

	private let viewModel: NavigatorSettingsViewModel
	private let rootView: NavigatorSettingsView

	init(viewModel: NavigatorSettingsViewModel) {
		self.viewModel = viewModel
		rootView = NavigatorSettingsView(viewModel: viewModel)
		super.init(nibName: nil, bundle: nil)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func loadView() {
		let containerView = NSView()
		containerView.wantsLayer = true
		containerView.layer?.backgroundColor = NSColor.clear.cgColor
		containerView.layer?.masksToBounds = false

		rootView.translatesAutoresizingMaskIntoConstraints = false
		containerView.addSubview(rootView)

		NSLayoutConstraint.activate([
			rootView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Self.panelInset),
			rootView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Self.panelInset),
			rootView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Self.panelInset),
			rootView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -Self.panelInset),
		])

		view = containerView
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		startObservingViewModel()
	}

	override func viewDidAppear() {
		super.viewDidAppear()
	}

	override func viewDidDisappear() {
		super.viewDidDisappear()
	}

	func refresh() {
		viewModel.refreshDefaultBrowserStatus()
		viewModel.refreshImportStatus()
		rootView.refresh()
	}

	func invalidate() {
		viewModel.invalidate()
	}

	private func startObservingViewModel() {
		withObservationTracking {
			observeViewModelState()
		} onChange: { [weak self] in
			Self.handleObservationChange(for: self)
		}
	}

	private nonisolated static func handleObservationChange(for controller: NavigatorSettingsViewController?) {
		Task { @MainActor [weak controller] in
			guard let controller else { return }
			controller.rootView.refresh()
			controller.startObservingViewModel()
		}
	}

	private func observeViewModelState() {
		_ = viewModel.selectedSection
		_ = viewModel.defaultBrowserStatus
		_ = viewModel.browserImportStatus
		_ = viewModel.canSetAsDefaultBrowser
		_ = viewModel.showsDefaultBrowserError
		_ = viewModel.showsImportError
		_ = viewModel.isImporting
		_ = viewModel.canOpenImportedBookmarks
		_ = viewModel.canOpenImportedHistory
		_ = viewModel.versionDescription
		_ = viewModel.bundleIdentifier
		_ = viewModel.defaultBrowserTitle
		_ = viewModel.defaultBrowserDescription
		_ = viewModel.defaultBrowserActionTitle
		_ = viewModel.updatesTitle
		_ = viewModel.updatesDescription
		_ = viewModel.automaticallyCheckForUpdatesTitle
		_ = viewModel.automaticallyChecksForUpdates
		_ = viewModel.browserImportTitle
		_ = viewModel.browserImportDescription
		_ = viewModel.importChromeActionTitle
		_ = viewModel.importArcActionTitle
		_ = viewModel.importSafariActionTitle
		_ = viewModel.openImportedBookmarksActionTitle
		_ = viewModel.openImportedHistoryActionTitle
		_ = viewModel.importSummaryText
	}
}
