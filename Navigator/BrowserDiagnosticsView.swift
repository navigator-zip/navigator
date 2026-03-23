import AppKit
import Observation
import Vendors

enum BrowserDiagnosticsWindow {
	static let id = "browser-diagnostics"
}

final class BrowserDiagnosticsViewController: NSViewController {
	private let rootView = BrowserDiagnosticsView()

	override func loadView() {
		view = NSView()
		view = rootView
		view.frame = NSRect(x: 0, y: 0, width: 860, height: 560)
		view.wantsLayer = true
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		rootView.refresh()
	}
}

final class BrowserDiagnosticsView: NSView {
	@ObservationIgnored
	private var viewModel = BrowserDiagnosticsViewModel()

	private let titleLabel = NSTextField(labelWithString: String(localized: .navigatorDebugWindowTitle))
	private let refreshButton = NSButton(title: String(localized: .navigatorDebugActionsRefresh), target: nil, action: nil)
	private let copyReportButton = NSButton(
		title: String(localized: .navigatorDebugActionsCopyReport),
		target: nil,
		action: nil
	)
	private let reloadBrowserButton = NSButton(
		title: String(localized: .navigatorDebugActionsReloadBrowser),
		target: nil,
		action: nil
	)
	private let revealCacheButton = NSButton(
		title: String(localized: .navigatorDebugActionsOpenCache),
		target: nil,
		action: nil
	)
	private let revealCrashReportsButton = NSButton(
		title: String(localized: .navigatorDebugActionsOpenCrashReports),
		target: nil,
		action: nil
	)
	private let reportTextView = NSTextView()
	private let reportScroller = NSScrollView()
	private let toolbar = NSStackView()
	private let buttonRow = NSStackView()

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		setupUI()
		refresh()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	private func setupUI() {
		wantsLayer = true
		layer?.cornerRadius = 8

		titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
		titleLabel.alignment = .left
		titleLabel.translatesAutoresizingMaskIntoConstraints = false

		for item in [refreshButton, copyReportButton, reloadBrowserButton, revealCacheButton, revealCrashReportsButton] {
			item.translatesAutoresizingMaskIntoConstraints = false
			item.bezelStyle = .rounded
		}
		refreshButton.target = self
		refreshButton.action = #selector(refreshReport)
		copyReportButton.target = self
		copyReportButton.action = #selector(copyReport)
		reloadBrowserButton.target = self
		reloadBrowserButton.action = #selector(reloadBrowser)
		revealCacheButton.target = self
		revealCacheButton.action = #selector(revealCache)
		revealCrashReportsButton.target = self
		revealCrashReportsButton.action = #selector(revealCrashReports)

		buttonRow.translatesAutoresizingMaskIntoConstraints = false
		buttonRow.orientation = .horizontal
		buttonRow.alignment = .centerY
		buttonRow.spacing = 8
		buttonRow.addArrangedSubview(refreshButton)
		buttonRow.addArrangedSubview(copyReportButton)
		buttonRow.addArrangedSubview(reloadBrowserButton)
		buttonRow.addArrangedSubview(revealCacheButton)
		buttonRow.addArrangedSubview(revealCrashReportsButton)

		toolbar.translatesAutoresizingMaskIntoConstraints = false
		toolbar.orientation = .vertical
		toolbar.spacing = 12
		toolbar.addArrangedSubview(titleLabel)
		toolbar.addArrangedSubview(buttonRow)

		reportTextView.translatesAutoresizingMaskIntoConstraints = false
		reportTextView.isEditable = false
		reportTextView.isSelectable = true
		reportTextView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
		reportTextView.autoresizingMask = []
		reportTextView.drawsBackground = true
		reportTextView.isRichText = false

		reportScroller.translatesAutoresizingMaskIntoConstraints = false
		reportScroller.documentView = reportTextView
		reportScroller.hasVerticalScroller = true
		reportScroller.hasHorizontalScroller = true
		reportScroller.autohidesScrollers = true
		reportScroller.drawsBackground = false

		addSubview(toolbar)
		addSubview(reportScroller)

		NSLayoutConstraint.activate([
			toolbar.topAnchor.constraint(equalTo: topAnchor, constant: 16),
			toolbar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
			toolbar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
			buttonRow.heightAnchor.constraint(equalToConstant: 28),

			reportScroller.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 12),
			reportScroller.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
			reportScroller.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
			reportScroller.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
		])

		applyResolvedColors()
	}

	override func viewDidChangeEffectiveAppearance() {
		super.viewDidChangeEffectiveAppearance()
		applyResolvedColors()
	}

	private func applyResolvedColors() {
		let textBackgroundColor = NSColor.textBackgroundColor
		layer?.backgroundColor = textBackgroundColor.cgColor
		reportTextView.backgroundColor = textBackgroundColor
	}

	func refresh() {
		viewModel.refresh()
		reloadBrowserButton.isEnabled = viewModel.canReloadBrowser
		reportTextView.string = viewModel.reportText
	}

	@objc private func refreshReport() {
		refresh()
	}

	@objc private func copyReport() {
		viewModel.copyReport()
	}

	@objc private func reloadBrowser() {
		viewModel.reloadBrowser()
		refresh()
	}

	@objc private func revealCache() {
		viewModel.revealCacheFolder()
	}

	@objc private func revealCrashReports() {
		viewModel.revealCrashReportsFolder()
	}
}
