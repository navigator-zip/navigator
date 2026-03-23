import AppKit
import BrandColors
import BrowserActionBar
import BrowserSidebar
import BrowserView
import Helpers
import Observation
import OverlayView
import SwiftUI
import Vendors

@MainActor
final class BrowserRootViewController: NSViewController, NavigatorBrowserWindowContent {
	private var sidebarPanel: BrowserSidebarPanel?
	private var sidebarPanelLeadingConstraint: NSLayoutConstraint?
	private var sidebarPanelWidthConstraint: NSLayoutConstraint?
	private var actionBarPanel: BrowserActionBarView?
	private var sidebarHideWorkItem: DispatchWorkItem?
	private var toastHostView: NSHostingView<AnyView>?
	private static let sidebarOuterPadding: CGFloat = 10
	private static let sidebarVisibleInset: CGFloat = 5
	private static let toastTitleFontSize: CGFloat = 14
	private static let toastSubtitleFontSize: CGFloat = 14
	private static let toastHorizontalPadding: CGFloat = 32
	private static let toastInnerVerticalPadding: CGFloat = 2.5
	private static let toastTitleForegroundColor = Color(nsColor: .labelColor)
	private static let toastSubtitleForegroundColor = Color(nsColor: .secondaryLabelColor)

	@ObservationIgnored @Shared(.navigatorSidebarWidth) private var persistedSidebarWidth: NavigatorSidebarWidth

	private var sidebarWidth: CGFloat = .init(NavigatorSidebarWidth.default)
	let navigatorAppViewModel: AppViewModel
	private let windowID: UUID?
	private let sidebarViewModel: BrowserSidebarViewModel
	private let sidebarPresentation: BrowserSidebarPresentation
	private let browserChromeViewModel: BrowserChromeViewModel
	private let browserActionBarViewModel: BrowserActionBarViewModel

	private lazy var browserViewController: BrowserViewController = .init(
		windowID: windowID,
		sidebarViewModel: sidebarViewModel,
		sidebarPresentation: sidebarPresentation,
		sidebarWidth: sidebarWidth,
		browserRuntime: nil,
		browserChromeViewModel: browserChromeViewModel,
		eventMonitoring: .live
	)

	init(windowID: UUID?, navigatorAppViewModel: AppViewModel) {
		self.navigatorAppViewModel = navigatorAppViewModel
		self.windowID = windowID
		sidebarViewModel = navigatorAppViewModel.sidebarViewModel
		sidebarPresentation = navigatorAppViewModel.sidebarPresentation
		browserChromeViewModel = navigatorAppViewModel.sidebarChromeViewModel
		browserActionBarViewModel = navigatorAppViewModel.browserActionBarViewModel
		super.init(nibName: nil, bundle: nil)
		let persisted = $persistedSidebarWidth.withLock { persisted in
			persisted
		}
		sidebarWidth = CGFloat(persisted.width)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func loadView() {
		let rootView = BrowserRootContainerView(frame: NSRect(x: 0, y: 0, width: 1100, height: 700))
		rootView.onAppearanceChange = { [weak self] in
			self?.refreshAppearance()
		}
		view = rootView
		view.wantsLayer = true
		view.layer?.cornerRadius = 10
		view.layer?.masksToBounds = true
		applyResolvedColors()
		browserActionBarViewModel.dismiss()
		buildComposition()
		buildToastHost()
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		configureSidebarPresentationTracking()
		observeToastState()
		actionBarPanel = BrowserActionBarView(viewModel: browserActionBarViewModel)
		actionBarPanel?.updateAnchorWindow = { [weak self] in
			self?.view.window
		}
		actionBarPanel?.attach(to: view.window)
	}

	override func viewDidAppear() {
		super.viewDidAppear()
		actionBarPanel?.attach(to: view.window)
	}

	override func viewWillDisappear() {
		super.viewWillDisappear()
		actionBarPanel?.removeFromWindow()
	}

	override func viewDidLayout() {
		super.viewDidLayout()
		actionBarPanel?.repositionForCurrentWindow(window: view.window)
	}

	private func buildComposition() {
		addChild(browserViewController)
		let browserView = browserViewController.view
		browserView.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(browserView)

		let sidebarView = BrowserSidebarPanel(
			viewModel: sidebarViewModel,
			presentation: sidebarPresentation,
			width: sidebarWidth,
			onWidthChange: { [weak self] nextWidth in
				self?.updateSidebarWidthDuringDrag(nextWidth)
			},
			onCommitWidth: { [weak self] nextWidth in
				self?.commitSidebarWidth(nextWidth)
			}
		)
		sidebarPanel = sidebarView
		sidebarView.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(sidebarView)

		sidebarPanelLeadingConstraint = sidebarView.leadingAnchor.constraint(
			equalTo: view.leadingAnchor,
			constant: sidebarLeadingConstant(isPresented: sidebarPresentation.isPresented, width: sidebarWidth)
		)
		sidebarPanelWidthConstraint = sidebarView.widthAnchor.constraint(equalToConstant: sidebarWidth)

		guard
			let sidebarPanelLeadingConstraint,
			let sidebarPanelWidthConstraint,
			let sidebarView = sidebarPanel
		else { return }

		NSLayoutConstraint.activate([
			browserView.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.sidebarOuterPadding),
			browserView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Self.sidebarOuterPadding),
			browserView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Self.sidebarOuterPadding),
			browserView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Self.sidebarOuterPadding),
			sidebarView.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.sidebarVisibleInset),
			sidebarPanelLeadingConstraint,
			sidebarPanelWidthConstraint,
			sidebarView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Self.sidebarVisibleInset),
		])

		configurePanelFromExistingState()
	}

	private func configurePanelFromExistingState() {
		guard let panel = sidebarPanel else { return }
		panel.setPresented(sidebarPresentation.isPresented, animated: false)
	}

	private func buildToastHost() {
		let hostView = NSHostingView(rootView: AnyView(EmptyView()))
		hostView.translatesAutoresizingMaskIntoConstraints = false
		hostView.setContentHuggingPriority(.required, for: .vertical)
		hostView.setContentCompressionResistancePriority(.required, for: .vertical)
		hostView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
		hostView.isHidden = true
		view.addSubview(hostView)
		toastHostView = hostView
		(view as? BrowserRootContainerView)?.passthroughOverlayView = hostView

		NSLayoutConstraint.activate([
			hostView.topAnchor.constraint(equalTo: view.topAnchor),
			hostView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
			hostView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			hostView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
		])

		updateToastOverlay()
	}

	private func observeToastState() {
		withObservationTracking {
			_ = navigatorAppViewModel.toast
			_ = navigatorAppViewModel.toastTitle
			_ = navigatorAppViewModel.toastBody
		} onChange: { [weak self] in
			Task { @MainActor [weak self] in
				self?.updateToastOverlay()
				self?.observeToastState()
			}
		}
	}

	private func updateToastOverlay() {
		guard let toastHostView else { return }
		guard let toast = navigatorAppViewModel.toast else {
			toastHostView.rootView = AnyView(EmptyView())
			toastHostView.isHidden = true
			return
		}

		let title = navigatorAppViewModel.toastTitle
		let body = navigatorAppViewModel.toastBody
		let usesEmboss = isDarkAppearance == false
		toastHostView.rootView = AnyView(
			OverlayView(
				model: toast,
				styling: .view(
					AnyView(
						HStack {
							Image(nsImage: Asset.Central.info.image)
								.renderingMode(.template)
								.foregroundStyle(Self.toastTitleForegroundColor)
							VStack(alignment: .leading) {
								if usesEmboss {
									Text(title)
										.font(.brandDisplay(size: Self.toastTitleFontSize, weight: .medium))
										.multilineTextAlignment(.leading)
										.emboss
										.foregroundStyle(Self.toastTitleForegroundColor)
								}
								else {
									Text(title)
										.font(.brandDisplay(size: Self.toastTitleFontSize, weight: .medium))
										.foregroundStyle(Self.toastTitleForegroundColor)
										.multilineTextAlignment(.leading)
								}

								if usesEmboss {
									Text(body ?? "")
										.font(.brandDisplay(size: Self.toastSubtitleFontSize, weight: .medium))
										.multilineTextAlignment(.leading)
										.emboss
										.foregroundStyle(Self.toastSubtitleForegroundColor)
										.lineLimit(6)
								}
								else {
									Text(body ?? "")
										.font(.brandDisplay(size: Self.toastSubtitleFontSize, weight: .medium))
										.foregroundStyle(Self.toastSubtitleForegroundColor)
										.multilineTextAlignment(.leading)
										.lineLimit(6)
								}
							}
						}
						.fixedSize(horizontal: true, vertical: false)
						.padding(.horizontal, Self.toastHorizontalPadding)
						.padding(.vertical, Self.toastInnerVerticalPadding)
					)
				),
				contentMaxWidth: nil
			)
		)
		toastHostView.isHidden = false
	}

	private func configureSidebarPresentationTracking() {
		browserChromeViewModel.onPresentationChange = { [weak self] isPresented, animated in
			self?.setSidebarPresented(isPresented, animated: animated)
		}
	}

	private func setSidebarPresented(_ isPresented: Bool, animated: Bool) {
		guard let panel = sidebarPanel, let leadingConstraint = sidebarPanelLeadingConstraint else { return }
		let targetConstant = sidebarLeadingConstant(isPresented: isPresented, width: sidebarWidth)
		let oldConstant = leadingConstraint.constant
		sidebarHideWorkItem?.cancel()
		sidebarHideWorkItem = nil

		if !animated || oldConstant == targetConstant {
			panel.setPresented(isPresented, animated: false)
			if let panelLayer = panel.layer {
				panelLayer.removeAnimation(forKey: BrowserChromeViewModel.Constants.sidebarSpringAnimationKey)
				panelLayer.transform = CATransform3DIdentity
			}
			leadingConstraint.constant = targetConstant
			view.layoutSubtreeIfNeeded()
			return
		}

		if isPresented {
			panel.setPresented(true, animated: false)
		}
		view.layoutSubtreeIfNeeded()
		let startOriginX = panel.frame.minX
		leadingConstraint.constant = targetConstant
		view.layoutSubtreeIfNeeded()
		let endOriginX = panel.frame.minX
		let translation = startOriginX - endOriginX

		guard abs(translation) > 0.5, let panelLayer = panel.layer else {
			if !isPresented {
				panel.setPresented(false, animated: false)
			}
			return
		}

		let springAnimation = CASpringAnimation(keyPath: "transform.translation.x")
		springAnimation.mass = 1
		springAnimation.stiffness = 320
		springAnimation.damping = 26
		springAnimation.initialVelocity = 0.35
		springAnimation.fromValue = translation
		springAnimation.toValue = 0
		springAnimation.duration = springAnimation.settlingDuration
		springAnimation.isRemovedOnCompletion = true
		panelLayer.removeAnimation(forKey: BrowserChromeViewModel.Constants.sidebarSpringAnimationKey)
		panelLayer.transform = CATransform3DMakeTranslation(translation, 0, 0)

		panelLayer.add(springAnimation, forKey: BrowserChromeViewModel.Constants.sidebarSpringAnimationKey)
		panelLayer.transform = CATransform3DIdentity

		if !isPresented {
			let hideWorkItem = DispatchWorkItem { [weak panel] in
				panel?.setPresented(false, animated: false)
			}
			sidebarHideWorkItem = hideWorkItem
			DispatchQueue.main.asyncAfter(
				deadline: .now() + springAnimation.settlingDuration,
				execute: hideWorkItem
			)
		}
	}

	static func resolvedToastTitleForegroundColor(for appearance: NSAppearance) -> NSColor {
		var resolved = NSColor.labelColor
		appearance.performAsCurrentDrawingAppearance {
			resolved = NSColor.labelColor.usingColorSpace(.deviceRGB) ?? .labelColor
		}
		return resolved
	}

	static func resolvedToastSubtitleForegroundColor(for appearance: NSAppearance) -> NSColor {
		var resolved = NSColor.secondaryLabelColor
		appearance.performAsCurrentDrawingAppearance {
			resolved = NSColor.secondaryLabelColor.usingColorSpace(.deviceRGB) ?? .secondaryLabelColor
		}
		return resolved
	}

	private func commitSidebarWidth(_ width: CGFloat) {
		updateSidebarWidth(width, persist: true)
	}

	private func updateSidebarWidthDuringDrag(_ width: CGFloat) {
		updateSidebarWidth(width, persist: false)
	}

	private func updateSidebarWidth(_ width: CGFloat, persist: Bool) {
		let clampedWidth = Self.clampSidebarWidth(width)
		let didChange = abs(sidebarWidth - clampedWidth) >= 0.5

		if didChange {
			sidebarWidth = clampedWidth
			browserViewController.updateSidebarWidth(clampedWidth)
			sidebarPanelWidthConstraint?.constant = clampedWidth
			sidebarPanelLeadingConstraint?.constant = sidebarLeadingConstant(
				isPresented: sidebarPresentation.isPresented,
				width: clampedWidth
			)
		}

		if persist {
			$persistedSidebarWidth.withLock { persisted in
				let nextWidth = NavigatorSidebarWidth(width: Double(clampedWidth))
				guard persisted != nextWidth else { return }
				persisted = nextWidth
			}
		}

		guard didChange else { return }
		view.needsLayout = true
		view.layoutSubtreeIfNeeded()
	}

	func applySidebarWidthSetting(_ width: Double) {
		let clampedWidth = Self.clampSidebarWidth(CGFloat(width))
		sidebarPanel?.applySidebarWidthSetting(clampedWidth)
		if sidebarPanel == nil {
			updateSidebarWidth(clampedWidth, persist: true)
		}
	}

	private func sidebarLeadingConstant(isPresented: Bool, width: CGFloat) -> CGFloat {
		isPresented ? Self.sidebarVisibleInset : -width
	}

	private static func clampSidebarWidth(_ width: CGFloat) -> CGFloat {
		return CGFloat(NavigatorSidebarWidth.clamp(Double(width)))
	}

	func refreshAppearance() {
		applyResolvedColors()
		sidebarPanel?.refreshAppearance()
		updateToastOverlay()
	}

	private func applyResolvedColors() {
		let appearance = view.effectiveAppearance
		let resolvedBackgroundColor = WindowChromeStyler.resolvedBackgroundColor(for: appearance)
		view.layer?.backgroundColor = resolvedBackgroundColor.cgColor
		if let window = view.window {
			WindowChromeStyler.applyResolvedColors(to: window)
		}
	}

	private var isDarkAppearance: Bool {
		view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
	}
}

private final class BrowserRootContainerView: NSView {
	var onAppearanceChange: (() -> Void)?
	weak var passthroughOverlayView: NSView?

	override func viewDidChangeEffectiveAppearance() {
		super.viewDidChangeEffectiveAppearance()
		onAppearanceChange?()
	}

	override func hitTest(_ point: NSPoint) -> NSView? {
		if let passthroughOverlayView, passthroughOverlayView.isHidden == false {
			let pointInOverlay = convert(point, to: passthroughOverlayView)
			if passthroughOverlayView.bounds.contains(pointInOverlay),
			   let hitView = passthroughOverlayView.hitTest(pointInOverlay) {
				return hitView
			}
		}
		return super.hitTest(point)
	}
}
