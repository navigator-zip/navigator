import Aesthetics
import AppKit
import Foundation
import ModelKit
import Observation
import ReorderableList
import Vendors

@MainActor
@Observable
public final class BrowserSidebarPresentation {
	public var isPresented: Bool
	public init(isPresented: Bool = false) {
		self.isPresented = isPresented
	}
}

@MainActor
public final class BrowserSidebarView: DoubleStrokePanelView, NSTextFieldDelegate {
	private final class WeakRowViewBox {
		weak var rowView: BrowserSidebarTabRow?

		init(rowView: BrowserSidebarTabRow? = nil) {
			self.rowView = rowView
		}
	}

	public static let sidebarAnimationDuration: Double = 0.24
	private static let controlIconDimension: CGFloat = 16
	private static let rowHeight: CGFloat = 40
	private static let addressFieldCornerRadius: CGFloat = 8
	private static let addressFieldHeight: CGFloat = 24
	private static let addressFieldVerticalBackgroundPadding: CGFloat = 4
	private static let addressFieldVerticalTextInset: CGFloat = 1
	private static let addressFieldVerticalTextOffset: CGFloat = 1.5
	private static let addressFieldHorizontalPadding: CGFloat = 10
	private static let addressFieldBackgroundColor = Color.navigatorChromeFill
	private static let panelHorizontalPadding: CGFloat = 15
	private static let panelTopPadding: CGFloat = 10
	private static let topToolbarTopPadding: CGFloat = 0
	private static let tabListRowSpacing: CGFloat = 5
	private static let tabListHeaderHeight: CGFloat = 10
	private static let tabListFooterHeight: CGFloat = 10
	private static let emptyPinnedTabsGap: CGFloat = 10
	private static let spacePagerVerticalPadding: CGFloat = 20
	private static let spacePagerHorizontalPadding: CGFloat = 12
	private static let spacePagerDotDiameter: CGFloat = 6
	private static let spacePagerDotSpacing: CGFloat = 10
	private let viewModel: BrowserSidebarViewModel
	private let presentation: BrowserSidebarPresentation
	private let width: CGFloat
	private let backgroundColor: NSColor
	private let controlIconSize = NSSize(
		width: controlIconDimension,
		height: controlIconDimension
	)

	private let backButton = NSButton()
	private let forwardButton = NSButton()
	private let reloadButton = NSButton()
	private let closeWindowButton = BrowserSidebarWindowControlButton(baseColor: .systemRed)
	private let minimizeWindowButton = BrowserSidebarWindowControlButton(baseColor: .systemYellow)
	private let fullScreenWindowButton = BrowserSidebarWindowControlButton(baseColor: .systemGreen)
	private let addressFieldContainer = NSView()

	private let spacePagerView = BrowserSidebarSpacePagerView()
	private let spacePagerContainer = NSView()
	private let spacePagerDotsStack = NSStackView()
	private let addSpaceButton = NSButton()
	private let addressField = NSTextField()
	private let emptyStateLabel = NSTextField(labelWithString: "")
	private lazy var pinnedTabsView: BrowserSidebarPinnedTabsView = {
		let pinnedTabsView = BrowserSidebarPinnedTabsView(
			pinTabActionTitle: localized(.pinTabAction),
			unpinTabActionTitle: localized(.unpinTabAction),
			replacePinnedTabURLActionTitle: localized(.replacePinnedTabURLAction),
			sidebarBackgroundColor: backgroundColor
		)
		pinnedTabsView.onSelect = { [weak self] tabID in
			self?.activateTab(id: tabID)
		}
		pinnedTabsView.onTogglePin = { [weak self] tabID in
			self?.togglePin(for: tabID)
		}
		pinnedTabsView.onReplacePinnedURL = { [weak self] tabID in
			self?.viewModel.replacePinnedTabURLWithCurrentURL(id: tabID)
		}
		pinnedTabsView.onMove = { [weak self] source, destination in
			self?.viewModel.moveTabs(in: .pinned, from: source, to: destination)
		}
		return pinnedTabsView
	}()

	private let dragOverlayHostView = BrowserSidebarDragOverlayHostView()
	private let tabListTopSeparator = separator()
	private let sidebarSeparator = separator()
	private var viewStateChangeObserverID: UUID?
	private var rowViewsByTabID = [BrowserTabID: WeakRowViewBox]()
	private var hasDeferredPinnedTabsRefresh = false
	private var hasDeferredTabListRefresh = false

	private var pinnedTabsHeightConstraint: NSLayoutConstraint?
	private var spacePagerHeightConstraint: NSLayoutConstraint?
	private var spacePagerDotButtons = [NSButton]()
	private var reorderableListViewsByPageID = [String: ReorderableListView<BrowserTabViewModel, BrowserTabID>]()

	private var pinnedTabDragCoordinator: PinnedTabDragCoordinator?

	public init(
		viewModel: BrowserSidebarViewModel,
		presentation: BrowserSidebarPresentation,
		width: CGFloat,
		backgroundColor: NSColor = Asset.Colors.background.color,
		cornerRadius: CGFloat = 14
	) {
		self.viewModel = viewModel
		self.presentation = presentation
		self.width = width
		self.backgroundColor = backgroundColor
		super.init(
			frame: NSRect(x: 0, y: 0, width: width, height: 500),
			fillColor: backgroundColor,
			cornerRadius: cornerRadius
		)
		setupLayout()
		installPinnedTabDragCoordinator()
		installBindings()
		refreshFromViewModel()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	public func setPresented(_ isPresented: Bool, animated _: Bool) {
		isHidden = !isPresented
		guard isPresented else { return }
		needsLayout = true
		layoutSubtreeIfNeeded()
		refreshFromViewModel()
	}

	public func refreshAppearance() {
		refreshDoubleStrokeAppearance()
		applyResolvedColors()
		applyPinnedTabsFromViewModel()
		applyTabListFromViewModel()
	}

	private func setupLayout() {
		let topToolbar = NSView()
		topToolbar.translatesAutoresizingMaskIntoConstraints = false
		topToolbar.wantsLayer = true

		backButton.target = self
		backButton.identifier = NSUserInterfaceItemIdentifier("browserSidebar.backButton")
		backButton.action = #selector(didTapBack)
		backButton.bezelStyle = .texturedRounded
		backButton.isBordered = false
		backButton.translatesAutoresizingMaskIntoConstraints = false
		backButton.isEnabled = false
		backButton.contentTintColor = Asset.Colors.textPrimaryColor.color
		let backIcon = Asset.Iconography.arrowLeft.image
		backIcon.isTemplate = true
		backIcon.size = NSSize(width: Self.controlIconDimension, height: Self.controlIconDimension)
		backButton.imageScaling = .scaleProportionallyDown
		backButton.image = backIcon

		configureWindowControlButton(
			closeWindowButton,
			identifier: "browserSidebar.closeWindowButton",
			accessibilityLabel: localized(.closeWindowAction),
			action: #selector(didTapCloseWindow)
		)
		configureWindowControlButton(
			minimizeWindowButton,
			identifier: "browserSidebar.minimizeWindowButton",
			accessibilityLabel: localized(.minimizeWindowAction),
			action: #selector(didTapMinimizeWindow)
		)
		configureWindowControlButton(
			fullScreenWindowButton,
			identifier: "browserSidebar.fullScreenWindowButton",
			accessibilityLabel: localized(.toggleFullScreenAction),
			action: #selector(didTapToggleFullScreen)
		)

		forwardButton.target = self
		forwardButton.identifier = NSUserInterfaceItemIdentifier("browserSidebar.forwardButton")
		forwardButton.action = #selector(didTapForward)
		forwardButton.bezelStyle = .texturedRounded
		forwardButton.isBordered = false
		forwardButton.translatesAutoresizingMaskIntoConstraints = false
		forwardButton.isEnabled = false
		forwardButton.contentTintColor = Asset.Colors.textPrimaryColor.color
		let forwardIcon = Asset.Iconography.arrowRight.image
		forwardIcon.isTemplate = true
		forwardIcon.size = NSSize(width: Self.controlIconDimension, height: Self.controlIconDimension)
		forwardButton.imageScaling = .scaleProportionallyDown
		forwardButton.image = forwardIcon

		reloadButton.target = self
		reloadButton.identifier = NSUserInterfaceItemIdentifier("browserSidebar.reloadButton")
		reloadButton.action = #selector(didTapReload)
		reloadButton.bezelStyle = .texturedRounded
		reloadButton.isBordered = false
		reloadButton.translatesAutoresizingMaskIntoConstraints = false
		reloadButton.contentTintColor = Asset.Colors.textPrimaryColor.color
		let reloadIcon = Asset.Iconography.refresh.image
		reloadIcon.isTemplate = true
		reloadIcon.size = NSSize(width: Self.controlIconDimension, height: Self.controlIconDimension)
		reloadButton.imageScaling = .scaleProportionallyDown
		reloadButton.image = reloadIcon

		addressFieldContainer.translatesAutoresizingMaskIntoConstraints = false
		addressFieldContainer.wantsLayer = true
		addressFieldContainer.layer?.cornerRadius = Self.addressFieldCornerRadius
		addressFieldContainer.layer?.masksToBounds = true

		addressField.translatesAutoresizingMaskIntoConstraints = false
		addressField.delegate = self
		addressField.cell = VerticallyCenteredTextFieldCell(
			verticalInset: Self.addressFieldVerticalTextInset,
			verticalOffset: Self.addressFieldVerticalTextOffset,
			horizontalInset: Self.addressFieldHorizontalPadding
		)
		addressField.isEditable = true
		addressField.isSelectable = true
		addressField.drawsBackground = false
		addressField.isBordered = false
		addressField.isBezeled = false
		addressField.focusRingType = .none
		addressField.textColor = Asset.Colors.textPrimaryColor.color
		addressField.isAutomaticTextCompletionEnabled = false
		addressField.usesSingleLineMode = true
		addressField.lineBreakMode = .byTruncatingTail
		addressField.font = NSFont.preferredFont(forTextStyle: .body)

		if let cell = addressField.cell as? NSTextFieldCell {
			cell.isEditable = true
			cell.isSelectable = true
			cell.isScrollable = true
			cell.wraps = false
			cell.usesSingleLineMode = true
			cell.lineBreakMode = .byTruncatingTail
		}

		emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
		emptyStateLabel.alignment = .center
		emptyStateLabel.textColor = .secondaryLabelColor
		emptyStateLabel.font = NSFont.preferredFont(forTextStyle: .callout)
		emptyStateLabel.isEditable = false
		emptyStateLabel.isHidden = true
		emptyStateLabel.stringValue = localized(.emptyTabState)

		let trailingButtonStack = NSStackView(views: [
			backButton,
			forwardButton,
			reloadButton,
		])
		trailingButtonStack.translatesAutoresizingMaskIntoConstraints = false
		trailingButtonStack.orientation = .horizontal
		trailingButtonStack.alignment = .centerY
		trailingButtonStack.spacing = 8

		let windowControlStack = NSStackView(views: [
			closeWindowButton,
			minimizeWindowButton,
			fullScreenWindowButton,
		])
		windowControlStack.translatesAutoresizingMaskIntoConstraints = false
		windowControlStack.orientation = .horizontal
		windowControlStack.alignment = .centerY
		windowControlStack.spacing = 8

		let toolbarContent = NSStackView(views: [
			windowControlStack,
			NSView(),
			trailingButtonStack,
		])
		toolbarContent.translatesAutoresizingMaskIntoConstraints = false
		toolbarContent.orientation = .horizontal
		toolbarContent.alignment = .centerY
		toolbarContent.spacing = 8
		topToolbar.addSubview(toolbarContent)
		addressFieldContainer.addSubview(addressField)
		topToolbar.addSubview(addressFieldContainer)
		addSubview(topToolbar)

		addSubview(pinnedTabsView)
		spacePagerView.translatesAutoresizingMaskIntoConstraints = false
		spacePagerView.onPageChange = { [weak self] pageIndex in
			guard let self else { return }
			let pages = viewModel.spacePages
			guard pages.indices.contains(pageIndex) else { return }
			viewModel.selectSpacePage(id: pages[pageIndex].id)
			applyPinnedTabsFromViewModel()
			applySpacePagerColors()
			applyTabListSelectionsFromViewModel()
		}
		spacePagerView.onVisualPageChange = { [weak self] pageIndex in
			self?.applySpacePagerDotSelection(pageIndex)
		}
		addSubview(spacePagerView)

		spacePagerContainer.translatesAutoresizingMaskIntoConstraints = false
		spacePagerContainer.wantsLayer = true
		spacePagerDotsStack.translatesAutoresizingMaskIntoConstraints = false
		spacePagerDotsStack.orientation = .horizontal
		spacePagerDotsStack.alignment = .centerY
		spacePagerDotsStack.spacing = Self.spacePagerDotSpacing
		spacePagerContainer.addSubview(spacePagerDotsStack)

		addSpaceButton.translatesAutoresizingMaskIntoConstraints = false
		addSpaceButton.bezelStyle = .texturedRounded
		addSpaceButton.isBordered = false
		addSpaceButton.target = self
		addSpaceButton.action = #selector(didTapAddSpace)
		addSpaceButton.contentTintColor = .tertiaryLabelColor
		let addIcon = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)!
		addSpaceButton.image = addIcon
		addSpaceButton.imageScaling = .scaleProportionallyDown
		addSpaceButton.setContentHuggingPriority(.required, for: .horizontal)
		spacePagerContainer.addSubview(addSpaceButton)

		addSubview(spacePagerContainer)

		addSubview(emptyStateLabel)
		addSubview(tabListTopSeparator)
		addSubview(sidebarSeparator)
		pinnedTabsHeightConstraint = pinnedTabsView.heightAnchor.constraint(equalToConstant: 0)
		spacePagerHeightConstraint = spacePagerContainer.heightAnchor.constraint(equalToConstant: 0)

		NSLayoutConstraint.activate([
			topToolbar.topAnchor.constraint(equalTo: topAnchor, constant: Self.panelTopPadding),
			topToolbar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.panelHorizontalPadding),
			topToolbar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.panelHorizontalPadding),

			toolbarContent.topAnchor.constraint(equalTo: topToolbar.topAnchor, constant: Self.topToolbarTopPadding),
			toolbarContent.leadingAnchor.constraint(equalTo: topToolbar.leadingAnchor),
			toolbarContent.trailingAnchor.constraint(equalTo: topToolbar.trailingAnchor),
			toolbarContent.heightAnchor.constraint(equalToConstant: 24),

			addressFieldContainer.topAnchor.constraint(
				equalTo: toolbarContent.bottomAnchor,
				constant: 10
			),
			addressFieldContainer.leadingAnchor.constraint(equalTo: topToolbar.leadingAnchor),
			addressFieldContainer.trailingAnchor.constraint(equalTo: topToolbar.trailingAnchor),
			addressFieldContainer.heightAnchor.constraint(
				equalToConstant: Self.addressFieldHeight + (Self.addressFieldVerticalBackgroundPadding * 2)
			),
			addressFieldContainer.bottomAnchor.constraint(
				equalTo: topToolbar.bottomAnchor
			),

			addressField.topAnchor.constraint(
				equalTo: addressFieldContainer.topAnchor,
				constant: Self.addressFieldVerticalBackgroundPadding
			),
			addressField.leadingAnchor.constraint(equalTo: addressFieldContainer.leadingAnchor),
			addressField.trailingAnchor.constraint(equalTo: addressFieldContainer.trailingAnchor),
			addressField.bottomAnchor.constraint(
				equalTo: addressFieldContainer.bottomAnchor,
				constant: -Self.addressFieldVerticalBackgroundPadding
			),
			pinnedTabsView.topAnchor.constraint(equalTo: topToolbar.bottomAnchor),
			pinnedTabsView.leadingAnchor.constraint(
				equalTo: leadingAnchor,
				constant: Self.panelHorizontalPadding
			),
			pinnedTabsView.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -Self.panelHorizontalPadding
			),
			pinnedTabsHeightConstraint!,

			tabListTopSeparator.leadingAnchor.constraint(equalTo: leadingAnchor),
			tabListTopSeparator.trailingAnchor.constraint(equalTo: trailingAnchor),
			tabListTopSeparator.topAnchor.constraint(equalTo: pinnedTabsView.bottomAnchor),

			spacePagerContainer.leadingAnchor.constraint(
				equalTo: leadingAnchor
			),
			spacePagerContainer.trailingAnchor.constraint(
				equalTo: trailingAnchor
			),
			spacePagerContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
			spacePagerHeightConstraint!,
			spacePagerDotsStack.centerXAnchor.constraint(equalTo: spacePagerContainer.centerXAnchor),
			spacePagerDotsStack.centerYAnchor.constraint(equalTo: spacePagerContainer.centerYAnchor),
			spacePagerDotsStack.leadingAnchor.constraint(
				greaterThanOrEqualTo: spacePagerContainer.leadingAnchor,
				constant: Self.spacePagerHorizontalPadding
			),
			spacePagerDotsStack.trailingAnchor.constraint(
				lessThanOrEqualTo: spacePagerContainer.trailingAnchor,
				constant: -Self.spacePagerHorizontalPadding
			),

			addSpaceButton.trailingAnchor.constraint(
				equalTo: spacePagerContainer.trailingAnchor,
				constant: -Self.spacePagerHorizontalPadding
			),
			addSpaceButton.centerYAnchor.constraint(equalTo: spacePagerContainer.centerYAnchor),
			addSpaceButton.widthAnchor.constraint(equalToConstant: 16),
			addSpaceButton.heightAnchor.constraint(equalToConstant: 16),

			sidebarSeparator.leadingAnchor.constraint(equalTo: leadingAnchor),
			sidebarSeparator.trailingAnchor.constraint(equalTo: trailingAnchor),
			sidebarSeparator.bottomAnchor.constraint(equalTo: spacePagerContainer.topAnchor),

			spacePagerView.topAnchor.constraint(equalTo: tabListTopSeparator.bottomAnchor),
			spacePagerView.leadingAnchor.constraint(equalTo: leadingAnchor),
			spacePagerView.trailingAnchor.constraint(equalTo: trailingAnchor),
			spacePagerView.bottomAnchor.constraint(equalTo: sidebarSeparator.topAnchor),

			emptyStateLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
			emptyStateLabel.topAnchor.constraint(equalTo: pinnedTabsView.bottomAnchor, constant: 16),
			emptyStateLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
			emptyStateLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
		])

		dragOverlayHostView.frame = bounds
		dragOverlayHostView.autoresizingMask = [NSView.AutoresizingMask.width, .height]
		addSubview(dragOverlayHostView)

	}

	private func configureWindowControlButton(
		_ button: BrowserSidebarWindowControlButton,
		identifier: String,
		accessibilityLabel: String,
		action: Selector
	) {
		button.identifier = NSUserInterfaceItemIdentifier(identifier)
		button.translatesAutoresizingMaskIntoConstraints = false
		button.title = ""
		button.image = nil
		button.target = self
		button.action = action
		button.toolTip = accessibilityLabel
		button.setAccessibilityLabel(accessibilityLabel)

		NSLayoutConstraint.activate([
			button.widthAnchor.constraint(equalToConstant: BrowserSidebarWindowControlButton.controlDiameter),
			button.heightAnchor.constraint(equalToConstant: BrowserSidebarWindowControlButton.controlDiameter),
		])
	}

	private func installBindings() {
		viewStateChangeObserverID = viewModel.addViewStateChangeObserver { [weak self] in
			Self.handleViewStateChange(owner: self)
		}
	}

	@discardableResult
	private static func handleViewStateChange(owner: BrowserSidebarView?) -> Bool {
		guard let owner else { return false }
		Task { @MainActor in
			owner.refreshFromViewModel()
		}
		return true
	}

	override public func removeFromSuperview() {
		if let observerID = viewStateChangeObserverID {
			viewModel.removeViewStateChangeObserver(observerID)
			viewStateChangeObserverID = nil
		}
		super.removeFromSuperview()
	}

	override public func layout() {
		super.layout()
	}

	private func refreshFromViewModel() {
		backButton.isEnabled = viewModel.canGoBack
		forwardButton.isEnabled = viewModel.canGoForward
		if addressField.currentEditor() == nil, addressField.stringValue != viewModel.addressText {
			addressField.stringValue = viewModel.addressText
		}
		applyPinnedTabsFromViewModel()
		applySpacePagerFromViewModel()
		applyTabListFromViewModel()
		emptyStateLabel.isHidden = !viewModel.tabs.isEmpty
		applyResolvedColors()
	}

	private func applySpacePagerFromViewModel() {
		let pages = viewModel.spacePages
		let showsPager = pages.count > 1
		spacePagerContainer.isHidden = !showsPager
		guard showsPager else {
			for button in spacePagerDotButtons {
				spacePagerDotsStack.removeArrangedSubview(button)
				button.removeFromSuperview()
			}
			spacePagerDotButtons.removeAll(keepingCapacity: false)
			spacePagerHeightConstraint?.constant = 0
			return
		}

		if spacePagerDotButtons.count != pages.count {
			for button in spacePagerDotButtons {
				spacePagerDotsStack.removeArrangedSubview(button)
				button.removeFromSuperview()
			}
			spacePagerDotButtons = pages.enumerated().map { index, _ in
				let button = NSButton(title: "", target: self, action: #selector(didSelectSpacePageDot))
				button.translatesAutoresizingMaskIntoConstraints = false
				button.setButtonType(.momentaryPushIn)
				button.isBordered = false
				button.bezelStyle = .shadowlessSquare
				button.tag = index
				button.wantsLayer = true
				button.layer?.cornerRadius = Self.spacePagerDotDiameter / 2
				NSLayoutConstraint.activate([
					button.widthAnchor.constraint(equalToConstant: Self.spacePagerDotDiameter),
					button.heightAnchor.constraint(equalToConstant: Self.spacePagerDotDiameter),
				])
				spacePagerDotsStack.addArrangedSubview(button)
				return button
			}
		}
		for (index, button) in spacePagerDotButtons.enumerated() {
			button.tag = index
		}
		let contentHeight = max(spacePagerDotsStack.fittingSize.height, Self.spacePagerDotDiameter)
		spacePagerHeightConstraint?.constant = contentHeight + (Self.spacePagerVerticalPadding * 2)
		applySpacePagerColors()
	}

	private func applySpacePagerColors() {
		let pages = viewModel.spacePages
		guard pages.isEmpty == false else { return }
		let selectedIndex = pages.firstIndex(where: { $0.id == viewModel.selectedSpacePageID })
		applySpacePagerDotSelection(selectedIndex)
	}

	private func applySpacePagerDotSelection(_ selectedIndex: Int?) {
		let appearance = effectiveAppearance
		let selectedColor = resolvedColor(Asset.Colors.accent.color, for: appearance)
		let unselectedColor = resolvedColor(NSColor.tertiaryLabelColor, for: appearance)
		for (index, button) in spacePagerDotButtons.enumerated() {
			let isSelected = selectedIndex == index
			button.layer?.backgroundColor = (isSelected ? selectedColor : unselectedColor).cgColor
		}
	}

	private func applyTabListFromViewModel() {
		let anyReordering = reorderableListViewsByPageID.values.contains { $0.hasTransientReorderState }
		guard !anyReordering else {
			hasDeferredTabListRefresh = true
			return
		}
		hasDeferredTabListRefresh = false

		let spacePageVMs = viewModel.spacePageViewModels
		let livePageIDs = Set(spacePageVMs.map(\.id))
		for key in reorderableListViewsByPageID.keys where !livePageIDs.contains(key) {
			reorderableListViewsByPageID.removeValue(forKey: key)
		}

		let pages: [NSView] = spacePageVMs.map { pageVM in
			let listView = resolvedReorderableListView(for: pageVM.id)
			listView.setItems(pageVM.tabs)
			listView.selectedID = pageVM.selectedTabID
			return listView
		}
		spacePagerView.configure(pages: pages)

		if let selectedIndex = spacePageVMs.firstIndex(where: { $0.id == viewModel.selectedSpacePageID }) {
			spacePagerView.scrollToPage(selectedIndex, animated: false)
		}
	}

	private func applyTabListSelectionsFromViewModel() {
		for pageVM in viewModel.spacePageViewModels {
			reorderableListViewsByPageID[pageVM.id]?.selectedID = pageVM.selectedTabID
		}
	}

	private func resolvedReorderableListView(
		for pageID: String
	) -> ReorderableListView<BrowserTabViewModel, BrowserTabID> {
		if let existing = reorderableListViewsByPageID[pageID] {
			return existing
		}
		let listView = ReorderableListView<BrowserTabViewModel, BrowserTabID>(
			items: [],
			id: \.id,
			contentInsets: NSEdgeInsetsZero,
			rowSpacing: Self.tabListRowSpacing,
			rowBackgroundColor: .clear,
			fixedRowHeight: Self.rowHeight,
			onMove: { [weak self] source, destination in
				self?.viewModel.moveTabs(in: .unpinned, from: source, to: destination)
			},
			contentViewBuilder: { [weak self] tab in
				Self.buildTabContentView(
					for: tab,
					owner: self,
					isFaviconLoadingEnabled: !(self?.viewModel.isFaviconLoadingSuspended ?? true)
				)
			}
		)
		listView.setClearTableChromeHeights(
			headerHeight: Self.tabListHeaderHeight,
			footerHeight: Self.tabListFooterHeight
		)
		listView.setDragBackgroundColor(backgroundColor)
		listView.setEdgeFading(height: 16)
		listView.setHorizontalScrollEventHandler { [weak self] event in
			self?.spacePagerView.handleScrollEvent(event) ?? false
		}
		listView.onReorderInteractionDidFinish = { [weak self] in
			self?.flushDeferredTabRefreshesIfNeeded()
		}
		listView.onDropAboveList = { [weak self] tabID in
			self?.pinnedTabsView.hideExternalDragPlaceholder()
			self?.togglePin(for: tabID)
		}
		listView.onDragAboveListThreshold = { [weak self, weak listView] isAbove, tabID in
			guard let self, let listView else { return }
			if isAbove {
				let tileSize = CGSize(
					width: BrowserSidebarPinnedTabsView.tileDimension,
					height: BrowserSidebarPinnedTabsView.tileDimension
				)
				listView.setActiveDragShapeOverride(
					size: tileSize,
					cornerRadius: BrowserSidebarPinnedTabsView.tileCornerRadius,
					targetSnapshot: self.makePinnedTabSnapshot(for: tabID, tileSize: tileSize),
					animated: true
				)
				// Show placeholder in pinned grid at nearest insertion index.
				let cursorInWindow = NSEvent.mouseLocation
				if let window = self.window {
					let windowPoint = window.convertPoint(fromScreen: cursorInWindow)
					let insertionIndex = self.pinnedGridInsertionIndexForWindowLocation(windowPoint)
					self.pinnedTabsView.showExternalDragPlaceholder(at: insertionIndex)
				}
				self.updatePinnedTabsHeight(forTabCount: self.pinnedTabsView.tabCount + 1, animated: true)
			} else {
				listView.clearActiveDragShapeOverride(animated: true)
				self.pinnedTabsView.hideExternalDragPlaceholder()
				self.updatePinnedTabsHeight(forTabCount: self.pinnedTabsView.tabCount, animated: true)
			}
		}
		listView.onDragAboveListPositionUpdate = { [weak self] windowLocation in
			guard let self else { return }
			let insertionIndex = self.pinnedGridInsertionIndexForWindowLocation(windowLocation)
			self.pinnedTabsView.updateExternalDragPlaceholder(at: insertionIndex)
		}
		listView.onSettleTargetForDropAboveList = { [weak self] _ in
			guard let self else { return nil }
			guard let placeholderFrame = self.pinnedTabsView.currentExternalPlaceholderFrame() else {
				return nil
			}
			return self.dragOverlayHostView.convert(placeholderFrame, from: self.pinnedTabsView.collectionViewForCoordinateConversion)
		}
		listView.setDragOverlayHost(dragOverlayHostView)
		reorderableListViewsByPageID[pageID] = listView
		return listView
	}

	private func makePinnedTabSnapshot(for tabID: BrowserTabID, tileSize: CGSize) -> NSImage? {
		let faviconImage: NSImage? = rowViewsByTabID[tabID]?.rowView?.makeFaviconSnapshot()
			?? makeFaviconSnapshotFromTemporaryRow(for: tabID)
		guard let faviconImage else { return nil }
		let iconDimension = BrowserSidebarPinnedTabsView.tileDimension * 0.3
		let tileImage = NSImage(size: tileSize)
		tileImage.lockFocusFlipped(true)
		let iconRect = CGRect(
			x: (tileSize.width - iconDimension) / 2,
			y: (tileSize.height - iconDimension) / 2,
			width: iconDimension,
			height: iconDimension
		)
		faviconImage.draw(in: iconRect)
		tileImage.unlockFocus()
		return tileImage
	}

	private func makeFaviconSnapshotFromTemporaryRow(for tabID: BrowserTabID) -> NSImage? {
		guard let tab = viewModel.tabs.first(where: { $0.id == tabID }) else { return nil }
		let row = BrowserSidebarTabRow(
			isSelected: false,
			newTabTitle: localized(.newTabValue),
			closeTabActionTitle: localized(.closeTabAction),
			pinTabActionTitle: localized(.pinTabAction),
			unpinTabActionTitle: localized(.unpinTabAction),
			controlIconDimensions: controlIconSize,
			rowBackgroundColor: backgroundColor
		)
		row.frame = CGRect(origin: .zero, size: NSSize(width: bounds.width, height: Self.rowHeight))
		row.configure(
			with: tab,
			isFaviconLoadingEnabled: true,
			isSelected: false,
			onClose: {},
			onSelect: {}
		)
		row.layoutSubtreeIfNeeded()
		return row.makeFaviconSnapshot()
	}

	private func applyPinnedTabsFromViewModel() {
		guard pinnedTabsView.hasTransientReorderState == false else {
			hasDeferredPinnedTabsRefresh = true
			return
		}

		let nextPinnedTabs = viewModel.displayedTabs.pinned
		let hasPinnedTabs = !nextPinnedTabs.isEmpty

		// If the current space page has a selected unpinned tab, deselect pinned tabs
		// to avoid dual-selection across pinned and unpinned tab lists.
		let effectiveSelectedTabID: BrowserTabID?
		if let currentPageVM = viewModel.spacePageViewModels.first(where: { $0.id == viewModel.selectedSpacePageID }),
		   currentPageVM.selectedTabID != nil {
			effectiveSelectedTabID = nil
		} else {
			effectiveSelectedTabID = viewModel.selectedTabID
		}

		pinnedTabsView.update(
			tabs: nextPinnedTabs,
			selectedTabID: effectiveSelectedTabID,
			activeCameraTabIDs: [],
			isFaviconLoadingEnabled: !viewModel.isFaviconLoadingSuspended
		)
		pinnedTabsHeightConstraint?.constant = hasPinnedTabs
			? pinnedTabsView.preferredHeight(
				for: max(0, width - (Self.panelHorizontalPadding * 2))
			)
			: Self.emptyPinnedTabsGap
		pinnedTabsView.isHidden = !hasPinnedTabs
		hasDeferredPinnedTabsRefresh = false
	}

	func updatePinnedTabsHeight(forTabCount tabCount: Int, animated: Bool) {
		let availableWidth = max(0, width - (Self.panelHorizontalPadding * 2))
		let newHeight = tabCount > 0
			? pinnedTabsView.preferredHeight(for: availableWidth, tabCount: tabCount)
			: Self.emptyPinnedTabsGap
		guard pinnedTabsHeightConstraint?.constant != newHeight else { return }
		pinnedTabsHeightConstraint?.constant = newHeight
		if animated {
			NSAnimationContext.runAnimationGroup { context in
				context.duration = ReorderableListStyle.animationDuration
				context.allowsImplicitAnimation = true
				self.layoutSubtreeIfNeeded()
			}
		}
	}

	private func flushDeferredTabRefreshesIfNeeded() {
		if hasDeferredPinnedTabsRefresh {
			applyPinnedTabsFromViewModel()
		}
		if hasDeferredTabListRefresh {
			applyTabListFromViewModel()
		}
	}

	private static func buildTabContentView(
		for tab: BrowserTabViewModel,
		owner: BrowserSidebarView?,
		isFaviconLoadingEnabled: Bool
	) -> NSView {
		guard let owner else { return NSView() }
		return owner.makeTabRow(for: tab, isFaviconLoadingEnabled: isFaviconLoadingEnabled)
	}

	private func makeTabRow(for tab: BrowserTabViewModel, isFaviconLoadingEnabled: Bool) -> NSView {
		let rowView: BrowserSidebarTabRow
		if let existingRowView = rowViewsByTabID[tab.id]?.rowView {
			rowView = existingRowView
		}
		else {
			let newRowView = BrowserSidebarTabRow(
				isSelected: viewModel.isSelectedTab(tab.id),
				newTabTitle: localized(.newTabValue),
				closeTabActionTitle: localized(.closeTabAction),
				pinTabActionTitle: localized(.pinTabAction),
				unpinTabActionTitle: localized(.unpinTabAction),
				replacePinnedTabURLActionTitle: localized(.replacePinnedTabURLAction),
				controlIconDimensions: controlIconSize,
				rowBackgroundColor: backgroundColor
			)
			rowViewsByTabID[tab.id] = WeakRowViewBox(rowView: newRowView)
			rowView = newRowView
		}
		rowView.configure(
			with: tab,
			isFaviconLoadingEnabled: isFaviconLoadingEnabled,
			isSelected: viewModel.isSelectedTab(tab.id),
			onClose: { [weak self] in
				self?.viewModel.closeTab(id: tab.id)
			},
			onSelect: { [weak self] in
				self?.activateTab(id: tab.id)
			},
			onTogglePin: { [weak self] in
				self?.togglePin(for: tab.id)
			},
			onReplacePinnedURL: { [weak self] in
				self?.viewModel.replacePinnedTabURLWithCurrentURL(id: tab.id)
			}
		)
		return rowView
	}

	private func togglePin(for id: BrowserTabID, unpinnedInsertionIndex: Int? = nil) {
		guard let tab = viewModel.tabs.first(where: { $0.id == id }) else { return }
		if tab.isPinned {
			viewModel.unpinTab(id: id, toUnpinnedIndex: unpinnedInsertionIndex)
		}
		else {
			viewModel.pinTab(id: id)
		}
		refreshFromViewModel()
	}

	private func pruneCachedTabRows(liveTabIDs: Set<BrowserTabID>) {
		for (tabID, rowViewBox) in rowViewsByTabID
			where !liveTabIDs.contains(tabID) || rowViewBox.rowView == nil {
			rowViewsByTabID.removeValue(forKey: tabID)
		}
	}

	func cachedTabRowEntryCountForTesting() -> Int {
		rowViewsByTabID.count
	}

	func hasCachedTabRowEntryForTesting(_ tabID: BrowserTabID) -> Bool {
		rowViewsByTabID[tabID] != nil
	}

	func insertReleasedTabRowCacheEntryForTesting(_ tabID: BrowserTabID) {
		rowViewsByTabID[tabID] = WeakRowViewBox()
	}

	static func buildTabContentViewForTesting(
		for tab: BrowserTabViewModel,
		owner: BrowserSidebarView?
	) -> NSView {
		buildTabContentView(
			for: tab,
			owner: owner,
			isFaviconLoadingEnabled: true
		)
	}

	@discardableResult
	static func handleViewStateChangeForTesting(owner: BrowserSidebarView?) -> Bool {
		handleViewStateChange(owner: owner)
	}

	private func localized(_ key: BrowserSidebarLocalizationKey) -> String {
		let localizedValue = Bundle.module.localizedString(forKey: key.rawValue, value: key.rawValue, table: nil)
		if localizedValue != key.rawValue {
			return localizedValue
		}
		return key.fallbackValue(localeIdentifier: Locale.preferredLanguages.first)
	}

	@objc private func didTapBack() {
		viewModel.goBack()
		refreshFromViewModel()
	}

	@objc private func didTapForward() {
		viewModel.goForward()
		refreshFromViewModel()
	}

	@objc private func didTapReload() {
		viewModel.reload()
		refreshFromViewModel()
	}

	@objc private func didSelectSpacePageDot(_ sender: NSButton) {
		let selectedIndex = sender.tag
		guard viewModel.spacePages.indices.contains(selectedIndex) else { return }
		let selectedPageID = viewModel.spacePages[selectedIndex].id
		viewModel.selectSpacePage(id: selectedPageID)
		spacePagerView.scrollToPage(selectedIndex, animated: true)
		applyPinnedTabsFromViewModel()
		applySpacePagerColors()
		applyTabListSelectionsFromViewModel()
	}

	@objc private func didTapAddSpace() {
		viewModel.onAddSpace?()
	}

	@objc private func didTapCloseWindow() {
		window?.performClose(nil)
	}

	@objc private func didTapMinimizeWindow() {
		window?.miniaturize(nil)
	}

	@objc private func didTapToggleFullScreen() {
		window?.toggleFullScreen(nil)
	}

	@objc private func didSubmitAddress(_ sender: NSTextField) {
		viewModel.setAddressText(sender.stringValue)
		viewModel.submitAddress()
		refreshFromViewModel()
	}

	private func activateTab(id: BrowserTabID) {
		viewModel.selectTab(id: id)
		refreshFromViewModel()
	}

	public func controlTextDidChange(_ notification: Notification) {
		viewModel.setAddressText(addressField.stringValue)
	}

	public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
		switch commandSelector {
		case #selector(NSResponder.cancelOperation(_:)):
			window?.makeFirstResponder(nil)
			return false
		case #selector(NSResponder.selectAll(_:)):
			textView.selectAll(control)
			return true
		case #selector(NSResponder.insertNewline(_:)),
		     #selector(NSResponder.insertLineBreak(_:)),
		     #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
			didSubmitAddress(addressField)
			return true
		default:
			return false
		}
	}

	override public func viewDidChangeEffectiveAppearance() {
		super.viewDidChangeEffectiveAppearance()
		applyResolvedColors()
	}

	private func applyResolvedColors() {
		let appearance = effectiveAppearance
		let resolvedAddressFieldBackgroundColor = resolvedColor(Self.addressFieldBackgroundColor, for: appearance)
		let resolvedTextColor = resolvedColor(Asset.Colors.textPrimaryColor.color, for: appearance)
		backButton.contentTintColor = resolvedTextColor
		forwardButton.contentTintColor = resolvedTextColor
		reloadButton.contentTintColor = resolvedTextColor
		closeWindowButton.refreshAppearance()
		minimizeWindowButton.refreshAppearance()
		fullScreenWindowButton.refreshAppearance()
		addressFieldContainer.layer?.backgroundColor = resolvedAddressFieldBackgroundColor.cgColor
		addressField.textColor = resolvedTextColor
		applySpacePagerColors()
	}

	private func resolvedColor(_ color: NSColor, for appearance: NSAppearance) -> NSColor {
		var resolvedColor = color
		appearance.performAsCurrentDrawingAppearance {
			resolvedColor = Self.resolvedColor(fallback: color, convertedColor: NSColor(cgColor: color.cgColor))
		}
		return resolvedColor
	}

	private static func resolvedColor(fallback color: NSColor, convertedColor: NSColor?) -> NSColor {
		convertedColor ?? color
	}

	static func resolvedColorForTesting(fallback color: NSColor, convertedColor: NSColor?) -> NSColor {
		resolvedColor(fallback: color, convertedColor: convertedColor)
	}

	// MARK: - Pinned Tab Drag Coordinator

	private var activeReorderableListView: ReorderableListView<BrowserTabViewModel, BrowserTabID>? {
		reorderableListViewsByPageID[viewModel.selectedSpacePageID]
	}

	var sidebarBackgroundColor: NSColor {
		backgroundColor
	}

	private func installPinnedTabDragCoordinator() {
		let coordinator = PinnedTabDragCoordinator(
			pinnedTabsView: pinnedTabsView,
			dragOverlayHostView: dragOverlayHostView,
			sidebarView: self
		)
		coordinator.onMove = { [weak self] source, destination in
			self?.viewModel.moveTabs(in: .pinned, from: source, to: destination)
		}
		coordinator.onReorderInteractionDidFinish = { [weak self] in
			self?.flushDeferredTabRefreshesIfNeeded()
		}
		coordinator.onTogglePin = { [weak self] tabID, insertionIndex in
			self?.togglePin(for: tabID, unpinnedInsertionIndex: insertionIndex)
		}
		coordinator.onShowListPlaceholder = { [weak self] index, height in
			self?.activeReorderableListView?.showExternalDragPlaceholder(at: index, rowHeight: height)
		}
		coordinator.onUpdateListPlaceholder = { [weak self] index, height in
			self?.activeReorderableListView?.updateExternalDragPlaceholder(at: index, rowHeight: height)
		}
		coordinator.onHideListPlaceholder = { [weak self] animated in
			self?.activeReorderableListView?.hideExternalDragPlaceholder(animated: animated)
		}
		coordinator.listInsertionIndexForCursor = { [weak self] windowLocation in
			self?.listInsertionIndexForWindowLocation(windowLocation) ?? 0
		}
		coordinator.listRowFrameAtInsertionIndex = { [weak self] insertionIndex in
			guard let self, let listView = self.activeReorderableListView else { return nil }
			let dimensions = self.listAreaDimensions()
			return listView.externalDragPlaceholderFrameInHost(at: insertionIndex, rowHeight: dimensions.height)
		}
		coordinator.onPinnedTabCountChange = { [weak self] tabCount, animated in
			self?.updatePinnedTabsHeight(forTabCount: tabCount, animated: animated)
		}
		pinnedTabsView.dragCoordinator = coordinator
		coordinator.install()
		pinnedTabDragCoordinator = coordinator
	}

	func pinnedTabsViewFrameInSelf() -> CGRect {
		pinnedTabsView.frame
	}

	func makeRowSnapshot(for tabID: BrowserTabID) -> NSImage? {
		guard let tab = viewModel.tabs.first(where: { $0.id == tabID }) else { return nil }
		let dimensions = listAreaDimensions()
		let rowSize = NSSize(width: dimensions.width, height: dimensions.height)
		let row = BrowserSidebarTabRow(
			isSelected: false,
			newTabTitle: localized(.newTabValue),
			closeTabActionTitle: localized(.closeTabAction),
			pinTabActionTitle: localized(.pinTabAction),
			unpinTabActionTitle: localized(.unpinTabAction),
			controlIconDimensions: controlIconSize,
			rowBackgroundColor: backgroundColor
		)
		row.frame = CGRect(origin: .zero, size: rowSize)
		row.configure(
			with: tab,
			isFaviconLoadingEnabled: true,
			isSelected: false,
			onClose: {},
			onSelect: {}
		)
		row.layoutSubtreeIfNeeded()
		guard let bitmapRep = row.bitmapImageRepForCachingDisplay(in: row.bounds) else { return nil }
		row.cacheDisplay(in: row.bounds, to: bitmapRep)
		let image = NSImage(size: rowSize)
		image.addRepresentation(bitmapRep)
		return image
	}

	func listAreaDimensions() -> (width: CGFloat, height: CGFloat) {
		let listView = activeReorderableListView
		let rowWidth = listView?.bounds.width ?? bounds.width
		return (width: rowWidth, height: Self.rowHeight)
	}

	func listAreaCenterXInHost() -> CGFloat {
		let listView = activeReorderableListView
		return dragOverlayHostView.convert(
			CGPoint(x: (listView?.bounds.midX ?? bounds.midX), y: 0),
			from: listView ?? self
		).x
	}

	func listAreaFrameInHost() -> CGRect {
		let listView = activeReorderableListView
		return dragOverlayHostView.convert(
			listView?.bounds ?? bounds,
			from: listView ?? self
		)
	}

	func listInsertionIndexForWindowLocation(_ windowLocation: CGPoint) -> Int {
		guard let listView = activeReorderableListView else { return 0 }
		let pointInList = listView.convert(windowLocation, from: nil)
		let rowHeight = Self.rowHeight + Self.tabListRowSpacing
		let itemCount = listView.numberOfRows(in: NSTableView())
		let rawSlot = Int(floor(pointInList.y / rowHeight))
		return min(max(rawSlot, 0), itemCount)
	}

	private func pinnedGridInsertionIndexForWindowLocation(_ windowLocation: CGPoint) -> Int {
		let pointInCollectionView = pinnedTabsView.convertToCollectionView(windowLocation)
		let colCount = pinnedTabsView.currentColumnCount()
		return PinnedTabGridGeometry.externalInsertionIndex(
			cursorInGrid: pointInCollectionView,
			columnCount: colCount,
			tileSize: BrowserSidebarPinnedTabsView.tileDimension,
			interitemSpacing: BrowserSidebarPinnedTabsView.gridInteritemSpacing,
			lineSpacing: BrowserSidebarPinnedTabsView.gridLineSpacing,
			itemCount: pinnedTabsView.tabCount
		)
	}

}

private final class BrowserSidebarDragOverlayHostView: NSView {
	override var isFlipped: Bool { false }
	override var isOpaque: Bool { false }

	override func hitTest(_: NSPoint) -> NSView? {
		nil
	}

	override func viewDidMoveToSuperview() {
		super.viewDidMoveToSuperview()
		wantsLayer = true
		layer?.masksToBounds = false
		layer?.backgroundColor = NSColor.clear.cgColor
		layer?.zPosition = 2
	}
}

private final class BrowserSidebarSpacePagerView: NSScrollView {
	private let pageContainer = NSView()
	private var pageViews: [NSView] = []
	private var currentPage = 0
	private var isTrackingHorizontalScroll = false
	private var didCompleteHorizontalScroll = false
	private var lastScrollTimestamp: TimeInterval = 0
	private var scrollVelocityX: CGFloat = 0
	private var visualPage = 0
	private var isAnimating = false
	var onPageChange: ((Int) -> Void)?
	var onVisualPageChange: ((Int) -> Void)?

	override init(frame: NSRect) {
		super.init(frame: frame)
		setup()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	private func setup() {
		drawsBackground = false
		hasHorizontalScroller = false
		hasVerticalScroller = false
		horizontalScrollElasticity = .none
		verticalScrollElasticity = .none
		documentView = pageContainer
	}

	func configure(pages: [NSView]) {
		for view in pageViews {
			view.removeFromSuperview()
		}
		pageViews = pages
		for view in pages {
			pageContainer.addSubview(view)
		}
		if pages.isEmpty {
			currentPage = 0
		} else {
			currentPage = min(currentPage, pages.count - 1)
		}
		needsLayout = true
	}

	func scrollToPage(_ page: Int, animated: Bool) {
		guard pageViews.indices.contains(page) else { return }
		guard !isAnimating else { return }
		currentPage = page
		visualPage = page
		if animated {
			navigate(to: page)
		} else {
			let targetOrigin = NSPoint(x: CGFloat(page) * resolvedPageWidth(), y: 0)
			contentView.scroll(to: targetOrigin)
			reflectScrolledClipView(contentView)
		}
	}

	override func layout() {
		super.layout()
		let pageWidth = resolvedPageWidth()
		let pageHeight = bounds.height
		pageContainer.frame = NSRect(
			x: 0, y: 0,
			width: pageWidth * CGFloat(max(pageViews.count, 1)),
			height: pageHeight
		)
		for (index, view) in pageViews.enumerated() {
			view.frame = NSRect(x: CGFloat(index) * pageWidth, y: 0, width: pageWidth, height: pageHeight)
		}
		contentView.scroll(to: NSPoint(x: CGFloat(currentPage) * pageWidth, y: 0))
		reflectScrolledClipView(contentView)
	}

	override func scrollWheel(with event: NSEvent) {
		if handleHorizontalScroll(with: event) {
			return
		}
		super.scrollWheel(with: event)
	}

	func handleScrollEvent(_ event: NSEvent) -> Bool {
		handleHorizontalScroll(with: event)
	}

	private func handleHorizontalScroll(with event: NSEvent) -> Bool {
		guard pageViews.count > 1 else { return false }

		// Consume momentum and non-gesture events to prevent free-scrolling between pages.
		if event.momentumPhase != [] || event.phase == [] {
			if event.momentumPhase == .ended {
				didCompleteHorizontalScroll = false
			}
			return isTrackingHorizontalScroll || didCompleteHorizontalScroll
		}

		switch event.phase {
		case .changed:
			if !isTrackingHorizontalScroll {
				guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return false }
				isTrackingHorizontalScroll = true
				scrollVelocityX = 0
				lastScrollTimestamp = event.timestamp
			}

			// Track velocity from event timing.
			let dt = event.timestamp - lastScrollTimestamp
			if dt > 0 {
				scrollVelocityX = event.scrollingDeltaX / dt
			}
			lastScrollTimestamp = event.timestamp

			// Clamp drag to at most one page from the page we started the gesture on.
			let pageWidth = resolvedPageWidth()
			let anchorX = CGFloat(currentPage) * pageWidth
			let minX = max(anchorX - pageWidth, 0)
			let maxX = min(anchorX + pageWidth, CGFloat(pageViews.count - 1) * pageWidth)
			let newX = min(max(contentView.bounds.origin.x - event.scrollingDeltaX, minX), maxX)
			contentView.scroll(to: NSPoint(x: newX, y: 0))
			reflectScrolledClipView(contentView)

			// Update the visual page indicator as soon as the midpoint is crossed.
			if pageWidth > 0 {
				let nearestPage = min(
					max(Int((newX / pageWidth).rounded()), 0),
					pageViews.count - 1
				)
				if nearestPage != visualPage {
					visualPage = nearestPage
					onVisualPageChange?(nearestPage)
				}
			}
			return true

		case .ended, .cancelled:
			guard isTrackingHorizontalScroll else { return false }
			isTrackingHorizontalScroll = false
			didCompleteHorizontalScroll = true
			let pageWidth = resolvedPageWidth()
			guard pageWidth > 0 else { return true }

			let velocityThreshold: CGFloat = 200
			let targetPage: Int
			if abs(scrollVelocityX) > velocityThreshold {
				// Flick: advance one page in the flick direction regardless of position.
				targetPage = scrollVelocityX > 0
					? max(currentPage - 1, 0)
					: min(currentPage + 1, pageViews.count - 1)
			} else {
				// Slow drag: snap to whichever page the offset is nearest to.
				targetPage = min(
					max(Int((contentView.bounds.origin.x / pageWidth).rounded()), 0),
					pageViews.count - 1
				)
			}
			currentPage = targetPage
			onPageChange?(targetPage)
			navigate(to: targetPage)
			return true

		default:
			return false
		}
	}

	private func navigate(to page: Int, completion: (() -> Void)? = nil) {
		currentPage = page
		isAnimating = true
		let targetOrigin = NSPoint(x: CGFloat(page) * resolvedPageWidth(), y: 0)
		NSAnimationContext.runAnimationGroup { context in
			context.duration = 0.3
			context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
			contentView.animator().setBoundsOrigin(targetOrigin)
		} completionHandler: {
			MainActor.assumeIsolated { [self] in
				isAnimating = false
				reflectScrolledClipView(contentView)
				completion?()
			}
		}
	}

	private func resolvedPageWidth() -> CGFloat {
		return bounds.width
	}
}

private final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
	private let verticalInset: CGFloat
	private let verticalOffset: CGFloat
	private let horizontalInset: CGFloat

	init(verticalInset: CGFloat, verticalOffset: CGFloat = 0, horizontalInset: CGFloat = 0) {
		self.verticalInset = max(0, verticalInset)
		self.verticalOffset = verticalOffset
		self.horizontalInset = max(0, horizontalInset)
		super.init(textCell: "")
	}

	@available(*, unavailable)
	required init(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func drawingRect(forBounds rect: NSRect) -> NSRect {
		BrowserSidebarAddressFieldLayout.displayRect(
			forBounds: rect,
			font: font,
			verticalInset: verticalInset,
			verticalOffset: verticalOffset,
			horizontalInset: horizontalInset
		)
	}

	override func titleRect(forBounds rect: NSRect) -> NSRect {
		BrowserSidebarAddressFieldLayout.displayRect(
			forBounds: rect,
			font: font,
			verticalInset: verticalInset,
			verticalOffset: verticalOffset,
			horizontalInset: horizontalInset
		)
	}

	override func edit(
		withFrame aRect: NSRect,
		in controlView: NSView,
		editor textObj: NSText,
		delegate anObject: Any?,
		event theEvent: NSEvent?
	) {
		super.edit(
			withFrame: BrowserSidebarAddressFieldLayout.editingRect(
				forBounds: aRect,
				font: font,
				verticalInset: verticalInset,
				verticalOffset: verticalOffset,
				horizontalInset: horizontalInset
			),
			in: controlView,
			editor: textObj,
			delegate: anObject,
			event: theEvent
		)
	}

	override func select(
		withFrame aRect: NSRect,
		in controlView: NSView,
		editor textObj: NSText,
		delegate anObject: Any?,
		start selStart: Int,
		length selLength: Int
	) {
		super.select(
			withFrame: BrowserSidebarAddressFieldLayout.editingRect(
				forBounds: aRect,
				font: font,
				verticalInset: verticalInset,
				verticalOffset: verticalOffset,
				horizontalInset: horizontalInset
			),
			in: controlView,
			editor: textObj,
			delegate: anObject,
			start: selStart,
			length: selLength
		)
	}
}

enum BrowserSidebarAddressFieldLayout {
	static func displayRect(
		forBounds bounds: NSRect,
		font: NSFont?,
		verticalInset: CGFloat,
		verticalOffset: CGFloat,
		horizontalInset: CGFloat
	) -> NSRect {
		centeredRect(
			forBounds: bounds,
			font: font,
			verticalInset: verticalInset,
			verticalOffset: verticalOffset,
			horizontalInset: horizontalInset
		)
	}

	static func editingRect(
		forBounds bounds: NSRect,
		font: NSFont?,
		verticalInset: CGFloat,
		verticalOffset: CGFloat,
		horizontalInset: CGFloat
	) -> NSRect {
		centeredRect(
			forBounds: bounds,
			font: font,
			verticalInset: verticalInset,
			verticalOffset: verticalOffset,
			horizontalInset: horizontalInset
		)
	}

	private static func centeredRect(
		forBounds bounds: NSRect,
		font: NSFont?,
		verticalInset: CGFloat,
		verticalOffset: CGFloat,
		horizontalInset: CGFloat
	) -> NSRect {
		let fallbackFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
		let textHeight = ceil(font?.boundingRectForFont.height ?? fallbackFont.boundingRectForFont.height)
		let targetHeight = min(bounds.height, max(0, textHeight + (verticalInset * 2)))
		let inset = max(0, horizontalInset)
		var rect = NSRect(
			x: bounds.origin.x + inset,
			y: bounds.origin.y + floor((bounds.height - targetHeight) / 2) + verticalOffset,
			width: max(0, bounds.width - (inset * 2)),
			height: targetHeight
		)
		rect = rect.integral
		return rect
	}
}

private enum BrowserSidebarLocalizationKey: String {
	case closeTabAction = "browser.sidebar.action.closeTab"
	case closeWindowAction = "browser.sidebar.action.closeWindow"
	case emptyTabState = "browser.sidebar.label.emptyTabs"
	case minimizeWindowAction = "browser.sidebar.action.minimizeWindow"
	case newTabValue = "browser.sidebar.value.newTab"
	case pinTabAction = "browser.sidebar.action.pinTab"
	case replacePinnedTabURLAction = "browser.sidebar.action.replacePinnedTabURL"
	case toggleFullScreenAction = "browser.sidebar.action.toggleFullScreen"
	case unpinTabAction = "browser.sidebar.action.unpinTab"
}

private extension BrowserSidebarLocalizationKey {
	var resource: LocalizedStringResource {
		LocalizedStringResource(String.LocalizationValue(self.rawValue), bundle: .module)
	}

	func fallbackValue(localeIdentifier: String?) -> String {
		let isJapanese = localeIdentifier?.hasPrefix("ja") == true
		switch self {
		case .closeTabAction:
			return isJapanese ? "タブを閉じる" : "Close Tab"
		case .closeWindowAction:
			return isJapanese ? "ウインドウを閉じる" : "Close Window"
		case .emptyTabState:
			return isJapanese ? "タブが開かれていません" : "No tabs open"
		case .minimizeWindowAction:
			return isJapanese ? "ウインドウを最小化" : "Minimize Window"
		case .newTabValue:
			return isJapanese ? "新しいタブ" : "New Tab"
		case .pinTabAction:
			return isJapanese ? "タブを固定" : "Pin Tab"
		case .replacePinnedTabURLAction:
			return isJapanese ? "固定タブの URL を現在の URL に置き換える" : "Replace Pinned Tab URL with Current URL"
		case .toggleFullScreenAction:
			return isJapanese ? "フルスクリーンを切り替える" : "Toggle Full Screen"
		case .unpinTabAction:
			return isJapanese ? "タブの固定を解除" : "Unpin Tab"
		}
	}
}
