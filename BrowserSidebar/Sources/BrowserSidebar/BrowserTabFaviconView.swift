import Aesthetics
import AppKit
import Foundation

final class BrowserTabFaviconView: NSView {
	typealias LogoImages = (regular: NSImage, filled: NSImage)

	private let faviconImageView = NSImageView()
	private var activeLoadKey: String?
	private var resolvedLoadKey: String?
	private let viewModel: BrowserTabFaviconViewModel
	private var tab: BrowserTabViewModel
	private let showsPlaceholderWhenMissing: Bool
	private var logoImages: LogoImages?
	private var isLogoSelected = false
	private var isLoadingEnabled = true
	private var activeCacheRestoreKey: String?
	private var cacheRestoreTask: Task<Void, Never>?
	private var loadTask: Task<Void, Never>?
	private weak var observedClipView: NSClipView?
	private(set) var hasResolvedImage = false {
		didSet {
			guard oldValue != hasResolvedImage else { return }
			onResolvedImageAvailabilityChange?(hasResolvedImage)
		}
	}

	var onResolvedImageAvailabilityChange: ((Bool) -> Void)?

	init(
		tab: BrowserTabViewModel,
		viewModel: BrowserTabFaviconViewModel = BrowserTabFaviconViewModel(),
		showsPlaceholderWhenMissing: Bool = true,
		logoImages: LogoImages? = nil
	) {
		self.tab = tab
		self.viewModel = viewModel
		self.showsPlaceholderWhenMissing = showsPlaceholderWhenMissing
		self.logoImages = logoImages
		super.init(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
		wantsLayer = true
		translatesAutoresizingMaskIntoConstraints = false
		faviconImageView.translatesAutoresizingMaskIntoConstraints = false
		faviconImageView.imageScaling = .scaleProportionallyUpOrDown
		addSubview(faviconImageView)

		NSLayoutConstraint.activate([
			faviconImageView.topAnchor.constraint(equalTo: topAnchor),
			faviconImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
			faviconImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
			faviconImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
		])

		if logoImages == nil {
			applyPlaceholderImage()
			restoreCachedImageIfNeeded()
			refreshLoadScheduling()
		}
		else {
			applyLogoImage()
		}
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	deinit {
		cacheRestoreTask?.cancel()
		loadTask?.cancel()
		NotificationCenter.default.removeObserver(self)
	}

	func configure(
		tab: BrowserTabViewModel,
		isLoadingEnabled: Bool,
		isLogoSelected: Bool = false,
		logoImages: LogoImages? = nil
	) {
		let previousLoadKey = self.tab.faviconLoadKey
		self.tab = tab
		self.isLoadingEnabled = isLoadingEnabled

		let isLogoMode = logoImages != nil
		let wasLogoMode = self.logoImages != nil
		self.logoImages = logoImages

		if isLogoMode {
			if wasLogoMode == false {
				cacheRestoreTask?.cancel()
				cacheRestoreTask = nil
				activeCacheRestoreKey = nil
				loadTask?.cancel()
				loadTask = nil
				activeLoadKey = nil
				resolvedLoadKey = nil
			}
			self.isLogoSelected = isLogoSelected
			applyLogoImage()
			return
		}

		if wasLogoMode {
			cacheRestoreTask?.cancel()
			cacheRestoreTask = nil
			activeCacheRestoreKey = nil
			loadTask?.cancel()
			loadTask = nil
			activeLoadKey = nil
			resolvedLoadKey = nil
			self.isLogoSelected = false
			applyPlaceholderImage()
			restoreCachedImageIfNeeded()
			refreshLoadScheduling()
			return
		}

		if previousLoadKey != tab.faviconLoadKey {
			cacheRestoreTask?.cancel()
			cacheRestoreTask = nil
			activeCacheRestoreKey = nil
			loadTask?.cancel()
			loadTask = nil
			activeLoadKey = nil
			resolvedLoadKey = nil
			applyPlaceholderImage()
		}
		restoreCachedImageIfNeeded()
		refreshLoadScheduling()
	}

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		updateClipViewObservation()
		refreshLoadScheduling()
	}

	override func viewDidMoveToSuperview() {
		super.viewDidMoveToSuperview()
		updateClipViewObservation()
		refreshLoadScheduling()
	}

	override func layout() {
		super.layout()
		refreshLoadScheduling()
	}

	override func viewDidChangeEffectiveAppearance() {
		super.viewDidChangeEffectiveAppearance()
		guard logoImages != nil else { return }
		applyLogoImage()
	}

	override func viewDidHide() {
		super.viewDidHide()
		refreshLoadScheduling()
	}

	func updateLogoSelectionState(isSelected: Bool) {
		guard logoImages != nil else { return }
		guard isLogoSelected != isSelected else { return }
		isLogoSelected = isSelected
		applyLogoImage()
	}

	override func viewDidUnhide() {
		super.viewDidUnhide()
		refreshLoadScheduling()
	}

	private func reloadIfNeeded(
		loadKey: String,
		faviconURL: String?,
		pageURL: String
	) async {
		guard resolvedLoadKey != loadKey else { return }
		defer {
			if activeLoadKey == loadKey {
				activeLoadKey = nil
			}
		}
		await viewModel.load(faviconURL: faviconURL, pageURL: pageURL)
		guard !Task.isCancelled, activeLoadKey == loadKey else { return }
		resolvedLoadKey = loadKey
		applyResolvedImageIfAvailable()
	}

	@objc
	private func clipViewBoundsDidChange(_ notification: Notification) {
		guard notification.object as AnyObject? === observedClipView else { return }
		refreshLoadScheduling()
	}

	private func refreshLoadScheduling() {
		guard logoImages == nil else { return }
		guard isLoadingEnabled else {
			loadTask?.cancel()
			loadTask = nil
			activeLoadKey = nil
			if viewModel.image == nil {
				applyPlaceholderImage()
			}
			return
		}

		guard isEligibleForVisibleFaviconLoad else {
			if resolvedLoadKey == tab.faviconLoadKey {
				applyResolvedImageIfAvailable()
			}
			else if viewModel.image == nil {
				applyPlaceholderImage()
			}
			return
		}

		let loadKey = tab.faviconLoadKey
		guard activeLoadKey != loadKey else { return }
		guard resolvedLoadKey != loadKey else {
			applyResolvedImageIfAvailable()
			return
		}

		loadTask?.cancel()
		activeLoadKey = loadKey
		let faviconURL = tab.faviconURL
		let pageURL = tab.currentURL
		loadTask = Task { [weak self] in
			await self?.reloadIfNeeded(
				loadKey: loadKey,
				faviconURL: faviconURL,
				pageURL: pageURL
			)
		}
	}

	private func restoreCachedImageIfNeeded() {
		let loadKey = tab.faviconLoadKey
		guard activeCacheRestoreKey != loadKey else { return }
		guard resolvedLoadKey != loadKey || viewModel.image == nil else {
			applyResolvedImageIfAvailable()
			return
		}

		cacheRestoreTask?.cancel()
		activeCacheRestoreKey = loadKey
		let faviconURL = tab.faviconURL
		let pageURL = tab.currentURL
		cacheRestoreTask = Task { @MainActor [weak self] in
			guard let self else { return }
			let restoredImage = await self.viewModel.restoreCachedImageIfAvailable(
				faviconURL: faviconURL,
				pageURL: pageURL
			)
			defer {
				if self.activeCacheRestoreKey == loadKey {
					self.activeCacheRestoreKey = nil
					self.cacheRestoreTask = nil
				}
			}
			guard !Task.isCancelled, restoredImage, self.tab.faviconLoadKey == loadKey else { return }
			self.resolvedLoadKey = loadKey
			self.applyResolvedImageIfAvailable()
		}
	}

	private var isEligibleForVisibleFaviconLoad: Bool {
		guard window != nil else { return false }
		guard isHidden == false, superview?.isHiddenOrHasHiddenAncestor != true else { return false }
		return visibleRect.isEmpty == false && visibleRect.intersects(bounds)
	}

	private func updateClipViewObservation() {
		let clipView = enclosingScrollView?.contentView
		guard observedClipView !== clipView else { return }
		stopObservingClipView()
		observedClipView = clipView
		clipView?.postsBoundsChangedNotifications = true
		if let clipView {
			NotificationCenter.default.addObserver(
				self,
				selector: #selector(clipViewBoundsDidChange(_:)),
				name: NSView.boundsDidChangeNotification,
				object: clipView
			)
		}
	}

	private func stopObservingClipView() {
		if let observedClipView {
			NotificationCenter.default.removeObserver(
				self,
				name: NSView.boundsDidChangeNotification,
				object: observedClipView
			)
		}
		observedClipView = nil
	}

	private func applyPlaceholderImage() {
		hasResolvedImage = false
		faviconImageView.contentTintColor = nil
		if showsPlaceholderWhenMissing {
			faviconImageView.isHidden = false
			faviconImageView.image = NSImage(
				systemSymbolName: "globe",
				accessibilityDescription: nil
			)
		}
		else {
			faviconImageView.image = nil
			faviconImageView.isHidden = true
		}
	}

	private func applyLogoImage() {
		guard let logoImages else { return }
		hasResolvedImage = true
		faviconImageView.isHidden = false
		faviconImageView.contentTintColor = resolvedLogoTintColor
		faviconImageView.image = templatedLogoImage(
			isLogoSelected ? logoImages.filled : logoImages.regular
		)
	}

	private func applyResolvedImageIfAvailable() {
		guard let loadedImage = viewModel.image else {
			applyPlaceholderImage()
			return
		}
		hasResolvedImage = true
		faviconImageView.isHidden = false
		faviconImageView.contentTintColor = nil
		faviconImageView.image = loadedImage
	}

	private var resolvedLogoTintColor: NSColor {
		var resolvedColor = Asset.Colors.textPrimaryColor.color
		(effectiveAppearance).performAsCurrentDrawingAppearance {
			resolvedColor = Asset.Colors.textPrimaryColor.color.usingColorSpace(.deviceRGB)
				?? Asset.Colors.textPrimaryColor.color
		}
		return resolvedColor
	}

	private func templatedLogoImage(_ image: NSImage) -> NSImage {
		guard let copy = image.copy() as? NSImage else {
			image.isTemplate = true
			return image
		}
		copy.isTemplate = true
		return copy
	}
}

#if DEBUG
	extension BrowserTabFaviconView {
		var imageViewIsHiddenForTesting: Bool {
			faviconImageView.isHidden
		}
	}
#endif
