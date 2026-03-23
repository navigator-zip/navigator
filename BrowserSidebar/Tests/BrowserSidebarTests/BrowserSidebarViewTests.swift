import Aesthetics
import AppKit
@testable import BrowserSidebar
import ModelKit
@testable import ReorderableList
import XCTest

@MainActor
final class BrowserSidebarViewTests: XCTestCase {
	func testSidebarUsesReorderableListViewBackedByNSTableView() {
		let viewModel = makeViewModel()
		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		sidebar.layoutSubtreeIfNeeded()

		let subviews = sidebar.recursiveSubviews

		XCTAssertTrue(
			subviews.contains {
				String(describing: type(of: $0)).contains("ReorderableListView")
			}
		)
		XCTAssertTrue(subviews.contains { $0 is NSTableView })
		XCTAssertFalse(
			subviews.contains {
				String(describing: type(of: $0)).contains("ReorderableListHandleView")
			}
		)
		XCTAssertEqual(subviews.compactMap { $0 as? BrowserSidebarTabRow }.count, 1)
	}

	func testSidebarAddsLookalikeWindowControlButtons() throws {
		let viewModel = makeViewModel()
		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		sidebar.layoutSubtreeIfNeeded()

		let closeButton = try windowControlButton(in: sidebar, identifier: "browserSidebar.closeWindowButton")
		let minimizeButton = try windowControlButton(in: sidebar, identifier: "browserSidebar.minimizeWindowButton")
		let fullScreenButton = try windowControlButton(in: sidebar, identifier: "browserSidebar.fullScreenWindowButton")

		XCTAssertEqual(closeButton.title, "")
		XCTAssertNil(closeButton.image)
		XCTAssertEqual(closeButton.toolTip, "Close Window")
		XCTAssertEqual(minimizeButton.toolTip, "Minimize Window")
		XCTAssertEqual(fullScreenButton.toolTip, "Toggle Full Screen")
		XCTAssertEqual(closeButton.bounds.width, 12)
		XCTAssertEqual(closeButton.bounds.height, 12)
		XCTAssertEqual(closeButton.outerCircleFrameForTesting.width, 9)
		XCTAssertEqual(closeButton.outerCircleFrameForTesting.height, 9)
		XCTAssertEqual(closeButton.hoverIndicatorFrameForTesting.width, 5)
		XCTAssertEqual(closeButton.hoverIndicatorFrameForTesting.height, 5)
		XCTAssertFalse(closeButton.isHoverIndicatorVisibleForTesting)
		XCTAssertFalse(minimizeButton.isHoverIndicatorVisibleForTesting)
		XCTAssertFalse(fullScreenButton.isHoverIndicatorVisibleForTesting)
		assertColor(
			closeButton.outerCircleColorForTesting,
			matches: BrowserSidebarWindowControlButton.displayColorForTesting(
				baseColor: .systemRed,
				tone: .resting,
				appearance: closeButton.effectiveAppearance
			),
			file: #filePath,
			line: #line
		)
		assertColor(
			minimizeButton.outerCircleColorForTesting,
			matches: BrowserSidebarWindowControlButton.displayColorForTesting(
				baseColor: .systemYellow,
				tone: .resting,
				appearance: minimizeButton.effectiveAppearance
			),
			file: #filePath,
			line: #line
		)
		assertColor(
			fullScreenButton.outerCircleColorForTesting,
			matches: BrowserSidebarWindowControlButton.displayColorForTesting(
				baseColor: .systemGreen,
				tone: .resting,
				appearance: fullScreenButton.effectiveAppearance
			),
			file: #filePath,
			line: #line
		)
	}

	func testSidebarWindowControlButtonsShowDarkerInnerDotOnHover() throws {
		let viewModel = makeViewModel()
		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		sidebar.layoutSubtreeIfNeeded()

		let closeButton = try windowControlButton(in: sidebar, identifier: "browserSidebar.closeWindowButton")
		let enterEvent = try XCTUnwrap(
			NSEvent.enterExitEvent(
				with: .mouseEntered,
				location: NSPoint(x: closeButton.bounds.midX, y: closeButton.bounds.midY),
				modifierFlags: [],
				timestamp: 0,
				windowNumber: 0,
				context: nil,
				eventNumber: 0,
				trackingNumber: 0,
				userData: nil
			)
		)
		let exitEvent = try XCTUnwrap(
			NSEvent.enterExitEvent(
				with: .mouseExited,
				location: NSPoint(x: closeButton.bounds.maxX + 10, y: closeButton.bounds.maxY + 10),
				modifierFlags: [],
				timestamp: 0,
				windowNumber: 0,
				context: nil,
				eventNumber: 1,
				trackingNumber: 0,
				userData: nil
			)
		)

		closeButton.mouseEntered(with: enterEvent)

		XCTAssertTrue(closeButton.isHoverIndicatorVisibleForTesting)
		assertColor(
			closeButton.hoverIndicatorColorForTesting,
			matches: BrowserSidebarWindowControlButton.displayColorForTesting(
				baseColor: .systemRed,
				tone: .hoverIndicator,
				appearance: closeButton.effectiveAppearance
			),
			file: #filePath,
			line: #line
		)

		closeButton.mouseExited(with: exitEvent)

		XCTAssertFalse(closeButton.isHoverIndicatorVisibleForTesting)
	}

	func testSidebarKeepsOnlyTrafficLightsOnLeadingEdge() throws {
		let viewModel = makeViewModel()
		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		sidebar.layoutSubtreeIfNeeded()

		let closeButton = try windowControlButton(in: sidebar, identifier: "browserSidebar.closeWindowButton")
		let minimizeButton = try windowControlButton(in: sidebar, identifier: "browserSidebar.minimizeWindowButton")
		let fullScreenButton = try windowControlButton(in: sidebar, identifier: "browserSidebar.fullScreenWindowButton")
		let backButton = try button(in: sidebar, identifier: "browserSidebar.backButton")
		let forwardButton = try button(in: sidebar, identifier: "browserSidebar.forwardButton")
		let reloadButton = try button(in: sidebar, identifier: "browserSidebar.reloadButton")
		let trafficLightsMaxX = [closeButton, minimizeButton, fullScreenButton]
			.map { sidebar.convert($0.bounds, from: $0).maxX }
			.max() ?? 0

		let trailingButtonMinX = try XCTUnwrap(
			[backButton, forwardButton, reloadButton]
				.map { sidebar.convert($0.bounds, from: $0).minX }
				.min()
		)

		XCTAssertLessThan(trafficLightsMaxX, sidebar.bounds.midX)
		XCTAssertGreaterThan(trailingButtonMinX, sidebar.bounds.midX)
		XCTAssertFalse(
			sidebar.recursiveSubviews
				.compactMap { $0.identifier?.rawValue }
				.contains("browserSidebar.addTabButton")
		)
	}

	func testSidebarWindowControlButtonsInvokeWindowActions() throws {
		let viewModel = makeViewModel()
		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		let window = BrowserSidebarWindowActionTestWindow(
			contentRect: sidebar.frame,
			styleMask: [.titled, .closable, .miniaturizable, .resizable],
			backing: .buffered,
			defer: false
		)
		window.contentView = sidebar
		sidebar.layoutSubtreeIfNeeded()

		try windowControlButton(in: sidebar, identifier: "browserSidebar.closeWindowButton").performClick(nil)
		try windowControlButton(in: sidebar, identifier: "browserSidebar.minimizeWindowButton").performClick(nil)
		try windowControlButton(in: sidebar, identifier: "browserSidebar.fullScreenWindowButton").performClick(nil)

		XCTAssertTrue(window.didPerformClose)
		XCTAssertTrue(window.didMiniaturize)
		XCTAssertTrue(window.didToggleFullScreen)
	}

	func testSidebarAddsTenPointVerticalBreathingRoomAroundTabList() throws {
		let viewModel = makeViewModel()
		viewModel.addTab()
		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		sidebar.layoutSubtreeIfNeeded()

		let scrollView = try XCTUnwrap(
			sidebar.recursiveSubviews.first {
				guard let scrollView = $0 as? NSScrollView else { return false }
				return scrollView.documentView?.subviews.contains(where: { $0 is NSTableView }) ?? false
			} as? NSScrollView
		)
		let documentView = try XCTUnwrap(scrollView.documentView)
		let tableView = try XCTUnwrap(documentView.subviews.first(where: { $0 is NSTableView }) as? NSTableView)

		XCTAssertEqual(tableView.frame.minY, 10)
		XCTAssertEqual(documentView.bounds.maxY - tableView.frame.maxY, 10)
	}

	func testSidebarClipsDraggedTabOverlayBelowAddressField() throws {
		let viewModel = makeViewModel()
		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		sidebar.layoutSubtreeIfNeeded()

		let reorderListView = try reorderableListView(in: sidebar)
		let overlayHostView = try XCTUnwrap(
			reorderListView.subviews.compactMap { $0 as? ReorderableTableOverlayHostView }.first
		)
		let addressField = try XCTUnwrap(
			sidebar.recursiveSubviews
				.compactMap { $0 as? NSTextField }
				.first { $0.delegate === sidebar }
		)
		let addressFieldContainer = try XCTUnwrap(addressField.superview)
		let overlayFrameInSidebar = sidebar.convert(overlayHostView.bounds, from: overlayHostView)
		let addressFieldFrameInSidebar = sidebar.convert(addressFieldContainer.bounds, from: addressFieldContainer)

		XCTAssertFalse(overlayFrameInSidebar.intersects(addressFieldFrameInSidebar))
		XCTAssertTrue(overlayHostView.layer?.masksToBounds ?? false)
	}

	func testSidebarRendersPinnedTabsInCollectionGridBelowAddressField() throws {
		let viewModel = makeViewModel()
		viewModel.updateTabFaviconURL("https://navigator.zip/favicon.ico", for: viewModel.tabs[0].id)
		viewModel.pinTab(id: viewModel.tabs[0].id)

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		sidebar.layoutSubtreeIfNeeded()

		let collectionView = try pinnedTabsCollectionView(in: sidebar)
		let addressField = try addressField(in: sidebar)
		let addressFieldContainer = try XCTUnwrap(addressField.superview)
		let collectionFrame = sidebar.convert(collectionView.bounds, from: collectionView)
		let addressFieldFrame = sidebar.convert(addressFieldContainer.bounds, from: addressFieldContainer)
		let itemSize = try pinnedTabItemView(in: collectionView).bounds.size

		XCTAssertEqual(collectionView.numberOfItems(inSection: 0), 1)
		XCTAssertLessThanOrEqual(collectionFrame.maxY, addressFieldFrame.minY)
		XCTAssertEqual(itemSize.width, 45)
		XCTAssertEqual(itemSize.height, 45)
	}

	func testSidebarCollapsesPinnedTabsCollectionWithoutConstraintConflictsWhenNoPinnedTabsExist() throws {
		let viewModel = makeViewModel()
		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		sidebar.layoutSubtreeIfNeeded()

		let pinnedTabsView = try pinnedTabsView(in: sidebar)
		let collectionView = try pinnedTabsCollectionView(in: sidebar)

		XCTAssertTrue(pinnedTabsView.isHidden)
		XCTAssertTrue(collectionView.isHidden)
		XCTAssertEqual(pinnedTabsView.frame.height, 10, accuracy: 0.5)
	}

	func testSidebarPreservesAddressBarBottomGapWhenPinnedTabsAreEmpty() throws {
		let viewModel = makeViewModel()
		viewModel.addTab()
		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		sidebar.layoutSubtreeIfNeeded()

		let addressField = try addressField(in: sidebar)
		let addressFieldContainer = try XCTUnwrap(addressField.superview)
		let scrollView = try XCTUnwrap(
			sidebar.recursiveSubviews.first {
				guard let scrollView = $0 as? NSScrollView else { return false }
				return scrollView.documentView?.subviews.contains(where: { $0 is NSTableView }) ?? false
			} as? NSScrollView
		)

		let addressFieldFrame = sidebar.convert(addressFieldContainer.bounds, from: addressFieldContainer)
		let scrollViewFrame = sidebar.convert(scrollView.bounds, from: scrollView)

		XCTAssertEqual(addressFieldFrame.minY - scrollViewFrame.maxY, 13, accuracy: 0.5)
	}

	func testSidebarDoesNotAddExtraReservedGapWhenPinnedTabsExist() throws {
		let viewModel = makeViewModel()
		viewModel.pinTab(id: viewModel.tabs[0].id)

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		sidebar.layoutSubtreeIfNeeded()

		let pinnedTabsView = try pinnedTabsView(in: sidebar)
		let scrollView = try XCTUnwrap(
			sidebar.recursiveSubviews.first {
				guard let scrollView = $0 as? NSScrollView else { return false }
				return scrollView.documentView?.subviews.contains(where: { $0 is NSTableView }) ?? false
			} as? NSScrollView
		)

		let pinnedTabsFrame = sidebar.convert(pinnedTabsView.bounds, from: pinnedTabsView)
		let scrollViewFrame = sidebar.convert(scrollView.bounds, from: scrollView)

		XCTAssertGreaterThan(pinnedTabsFrame.height, 10)
		XCTAssertEqual(pinnedTabsFrame.minY - scrollViewFrame.maxY, 3, accuracy: 0.5)
	}

	func testSidebarDoesNotRenderCameraControls() {
		let viewModel = makeViewModel()
		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 560)
		sidebar.layoutSubtreeIfNeeded()

		assertNoCameraControls(in: sidebar)
	}

	func testSidebarDoesNotRenderCameraIndicatorsForActiveCameraTabs() throws {
		let viewModel = makeViewModel()
		viewModel.tabs[0].updatePageTitle("Pinned")
		viewModel.pinTab(id: viewModel.tabs[0].id)
		viewModel.openNewTab(with: "https://navigator.example/unpinned")
		viewModel.tabs[1].updatePageTitle("Unpinned")
		viewModel.updateActiveCameraTabIDs([
			viewModel.tabs[0].id,
			viewModel.tabs[1].id,
		])

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		sidebar.layoutSubtreeIfNeeded()

		let row = try XCTUnwrap(
			row(
				titled: "Unpinned",
				in: sidebar.recursiveSubviews.compactMap { $0 as? BrowserSidebarTabRow }
			)
		)
		XCTAssertTrue(row.isCameraActivityIndicatorHiddenForTesting)
		XCTAssertNil(row.cameraActivityIndicatorToolTipForTesting)

		let collectionView = try pinnedTabsCollectionView(in: sidebar)
		let pinnedTile = try pinnedTileView(in: collectionView)
		let pinnedIndicator = try XCTUnwrap(
			pinnedTile.recursiveSubviews
				.compactMap { $0 as? NSImageView }
				.first {
					$0.identifier?.rawValue == BrowserSidebarCameraActivityIndicatorIdentifier.pinnedTab.rawValue
				}
		)
		XCTAssertTrue(pinnedIndicator.isHidden)
		XCTAssertNil(pinnedIndicator.toolTip)
	}

	func testSidebarKeepsOnlyUnpinnedTabsInVerticalListWhenPinnedTabsExist() throws {
		let viewModel = makeViewModel()
		viewModel.tabs[0].updatePageTitle("Pinned")
		viewModel.pinTab(id: viewModel.tabs[0].id)
		viewModel.openNewTab(with: "https://swift.org")
		viewModel.tabs[1].updatePageTitle("Unpinned")

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		sidebar.layoutSubtreeIfNeeded()

		let collectionView = try pinnedTabsCollectionView(in: sidebar)

		XCTAssertEqual(collectionView.numberOfItems(inSection: 0), 1)
		XCTAssertEqual(
			sidebar.recursiveSubviews.compactMap { $0 as? BrowserSidebarTabRow }.count,
			1
		)
		XCTAssertEqual(try rowTitlesInVisualOrder(in: sidebar), ["Unpinned"])
	}

	func testSidebarReordersPinnedTabsViaPinnedTabsViewDrag() throws {
		let viewModel = makeViewModel()
		viewModel.addTab()
		let firstPinnedTabID = viewModel.tabs[0].id
		let secondPinnedTabID = viewModel.tabs[1].id
		viewModel.tabs[0].updatePageTitle("First pinned")
		viewModel.tabs[1].updatePageTitle("Second pinned")
		viewModel.pinTab(id: firstPinnedTabID)
		viewModel.pinTab(id: secondPinnedTabID)

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		let window = NSWindow(
			contentRect: sidebar.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = sidebar
		sidebar.layoutSubtreeIfNeeded()

		let pinnedTabsView = try pinnedTabsView(in: sidebar)

		pinnedTabsView.beginDragForTesting(sourceIndex: 0)
		pinnedTabsView.moveDraggedTabForTesting(to: 2)
		pinnedTabsView.endDragForTesting(cancelled: false)

		XCTAssertEqual(viewModel.tabs.map(\.id), [secondPinnedTabID, firstPinnedTabID])
		XCTAssertEqual(pinnedTabsView.displayedTabIDsForTesting(), [secondPinnedTabID, firstPinnedTabID])
	}

	func testSidebarReordersPinnedTabToNextSlotInCompactGrid() throws {
		let viewModel = makeViewModel()
		viewModel.addTab()
		let firstPinnedTabID = viewModel.tabs[0].id
		let secondPinnedTabID = viewModel.tabs[1].id
		viewModel.pinTab(id: firstPinnedTabID)
		viewModel.pinTab(id: secondPinnedTabID)

		let pinnedTabGridWidth = BrowserSidebarPinnedTabsView.compactPinnedTabsReorderWidth
		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: pinnedTabGridWidth
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: pinnedTabGridWidth, height: 500)
		sidebar.layoutSubtreeIfNeeded()

		let pinnedTabsView = try pinnedTabsView(in: sidebar)
		pinnedTabsView.beginDragForTesting(sourceIndex: 0)
		pinnedTabsView.moveDraggedTabForTesting(to: 1)
		pinnedTabsView.endDragForTesting(cancelled: false)

		XCTAssertEqual(viewModel.tabs.map(\.id), [secondPinnedTabID, firstPinnedTabID])
	}

	func testPinnedTabsShowAnimatedDashedPlaceholderWhileDragging() throws {
		let viewModel = makeViewModel()
		viewModel.addTab()
		viewModel.pinTab(id: viewModel.tabs[0].id)
		viewModel.pinTab(id: viewModel.tabs[1].id)

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		sidebar.layoutSubtreeIfNeeded()

		let pinnedTabsView = try pinnedTabsView(in: sidebar)
		let collectionView = try pinnedTabsCollectionView(in: sidebar)
		let sourceItemView = try XCTUnwrap(
			collectionView.item(at: IndexPath(item: 0, section: 0))?.view
		)

		pinnedTabsView.beginDragForTesting(sourceIndex: 0)
		sidebar.layoutSubtreeIfNeeded()

		let placeholderView = try XCTUnwrap(pinnedTabsView.dragPlaceholderViewForTesting())
		let placeholderFrame = try XCTUnwrap(pinnedTabsView.dragPlaceholderFrameForTesting())

		XCTAssertEqual(placeholderFrame, sourceItemView.frame)
		XCTAssertEqual(placeholderView.dashPatternForTesting, [8, 6])
		XCTAssertTrue(placeholderView.isDashAnimationActiveForTesting)

		pinnedTabsView.endDragForTesting(cancelled: true)
		XCTAssertNil(pinnedTabsView.dragPlaceholderViewForTesting())
	}

	func testPinnedTabsMovePlaceholderToDestinationWhileReordering() throws {
		let viewModel = makeViewModel()
		viewModel.addTab()
		viewModel.addTab()
		viewModel.pinTab(id: viewModel.tabs[0].id)
		viewModel.pinTab(id: viewModel.tabs[1].id)
		viewModel.pinTab(id: viewModel.tabs[2].id)

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		sidebar.layoutSubtreeIfNeeded()

		let pinnedTabsView = try pinnedTabsView(in: sidebar)
		let collectionView = try pinnedTabsCollectionView(in: sidebar)
		let destinationItemView = try XCTUnwrap(
			collectionView.item(at: IndexPath(item: 2, section: 0))?.view
		)
		let destinationFrame = destinationItemView.frame

		pinnedTabsView.beginDragForTesting(sourceIndex: 0)
		pinnedTabsView.moveDraggedTabForTesting(to: 2)
		sidebar.layoutSubtreeIfNeeded()

		let placeholderFrame = try XCTUnwrap(pinnedTabsView.dragPlaceholderFrameForTesting())

		XCTAssertEqual(placeholderFrame, destinationFrame)

		pinnedTabsView.endDragForTesting(cancelled: true)
	}

	func testPinnedTabsUseLiftedDragPreviewMatchingTabRowTransforms() throws {
		let viewModel = makeViewModel()
		viewModel.addTab()
		viewModel.pinTab(id: viewModel.tabs[0].id)
		viewModel.pinTab(id: viewModel.tabs[1].id)

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		sidebar.layoutSubtreeIfNeeded()

		let pinnedTabsView = try pinnedTabsView(in: sidebar)
		let collectionView = try pinnedTabsCollectionView(in: sidebar)
		let itemView = try XCTUnwrap(
			collectionView.item(at: IndexPath(item: 0, section: 0))?.view
		)
		let previewFrame = try XCTUnwrap(
			pinnedTabsView.dragPreviewFrameForTesting(at: 0)
		)
		let previewImageSize = try XCTUnwrap(
			pinnedTabsView.dragPreviewImageSizeForTesting(at: 0)
		)

		XCTAssertLessThan(previewFrame.minX, 0)
		XCTAssertLessThan(previewFrame.minY, 0)
		XCTAssertEqual(previewFrame.midX, itemView.bounds.midX, accuracy: 0.01)
		XCTAssertEqual(previewFrame.midY, itemView.bounds.midY, accuracy: 0.01)
		XCTAssertGreaterThan(previewFrame.width, itemView.bounds.width)
		XCTAssertGreaterThan(previewFrame.height, itemView.bounds.height)
		XCTAssertEqual(previewImageSize, previewFrame.size)
	}

	func testPinnedTabsUseOpaqueBackdropWhileDragged() throws {
		let viewModel = makeViewModel()
		viewModel.addTab()
		viewModel.pinTab(id: viewModel.tabs[0].id)
		viewModel.pinTab(id: viewModel.tabs[1].id)

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		sidebar.layoutSubtreeIfNeeded()

		let pinnedTabsView = try pinnedTabsView(in: sidebar)
		let collectionView = try pinnedTabsCollectionView(in: sidebar)
		let indexPath = IndexPath(item: 0, section: 0)

		pinnedTabsView.beginDragForTesting(sourceIndex: 0)
		sidebar.layoutSubtreeIfNeeded()

		let draggedItemView = try XCTUnwrap(collectionView.item(at: indexPath)?.view)
		let draggedBackdropColor = try XCTUnwrap(
			draggedItemView.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))
		)

		XCTAssertGreaterThan(draggedBackdropColor.alphaComponent, 0.99)
		XCTAssertEqual(draggedItemView.subviews.first?.alphaValue ?? 0, CGFloat(0), accuracy: 0.01)

		pinnedTabsView.endDragForTesting(cancelled: true)
		sidebar.layoutSubtreeIfNeeded()

		let restoredItemView = try XCTUnwrap(collectionView.item(at: indexPath)?.view)
		let restoredBackdropColor = restoredItemView.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))

		XCTAssertEqual(restoredBackdropColor?.alphaComponent ?? 0, 0, accuracy: 0.01)
		XCTAssertEqual(restoredItemView.subviews.first?.alphaValue ?? 0, CGFloat(1), accuracy: 0.01)
	}

	func testSidebarDefersPinnedTabsRefreshUntilPinnedDragRelease() throws {
		let viewModel = makeViewModel()
		viewModel.addTab()
		let firstPinnedTabID = viewModel.tabs[0].id
		let secondPinnedTabID = viewModel.tabs[1].id
		viewModel.pinTab(id: firstPinnedTabID)
		viewModel.pinTab(id: secondPinnedTabID)

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		sidebar.layoutSubtreeIfNeeded()

		let pinnedTabsView = try pinnedTabsView(in: sidebar)

		XCTAssertEqual(pinnedTabsView.displayedTabIDsForTesting(), [firstPinnedTabID, secondPinnedTabID])

		pinnedTabsView.beginDragForTesting(sourceIndex: 0)
		viewModel.moveTabs(in: .pinned, from: IndexSet(integer: 0), to: 2)
		sidebar.refreshAppearance()
		sidebar.layoutSubtreeIfNeeded()

		XCTAssertEqual(pinnedTabsView.displayedTabIDsForTesting(), [firstPinnedTabID, secondPinnedTabID])

		pinnedTabsView.endDragForTesting(cancelled: true)
		sidebar.layoutSubtreeIfNeeded()

		XCTAssertEqual(pinnedTabsView.displayedTabIDsForTesting(), [secondPinnedTabID, firstPinnedTabID])
	}

	func testSidebarReordersUnpinnedRowsWhenPinnedTabsExist() throws {
		let viewModel = makeViewModel()
		viewModel.addTab()
		viewModel.addTab()
		let pinnedTabID = viewModel.tabs[0].id
		viewModel.tabs[0].updatePageTitle("Pinned")
		viewModel.tabs[1].updatePageTitle("First")
		viewModel.tabs[2].updatePageTitle("Second")
		viewModel.pinTab(id: pinnedTabID)

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		let window = NSWindow(
			contentRect: sidebar.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = sidebar
		sidebar.layoutSubtreeIfNeeded()

		let reorderListView = try reorderableListView(in: sidebar)
		let firstRowFrame = try XCTUnwrap(reorderListView.rowFrameForTesting(modelIndex: 0))
		let secondRowFrame = try XCTUnwrap(reorderListView.rowFrameForTesting(modelIndex: 1))

		reorderListView.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: firstRowFrame.midX, y: firstRowFrame.midY)
		)
		reorderListView.updateDragForTesting(
			locationInContent: NSPoint(x: secondRowFrame.midX, y: secondRowFrame.maxY + 20)
		)
		reorderListView.endDragForTesting(cancelled: false)

		XCTAssertEqual(viewModel.tabs.map(\.displayTitle), ["Pinned", "Second", "First"])
	}

	func testSidebarCapsPinnedGridAtTwentyItemsAndLeavesOverflowInList() throws {
		let viewModel = makeViewModel()
		viewModel.updateTabFaviconURL("https://example0.com/favicon.ico", for: viewModel.tabs[0].id)
		for index in 1..<21 {
			viewModel.openNewTab(with: "https://example\(index).com")
			viewModel.updateTabFaviconURL("https://example\(index).com/favicon.ico", for: viewModel.tabs[index].id)
		}
		let tabIDs = viewModel.tabs.map(\.id)
		for tabID in tabIDs {
			viewModel.pinTab(id: tabID)
		}

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		sidebar.layoutSubtreeIfNeeded()

		let collectionView = try pinnedTabsCollectionView(in: sidebar)

		XCTAssertEqual(collectionView.numberOfItems(inSection: 0), 20)
		XCTAssertEqual(try rowTitlesInVisualOrder(in: sidebar), ["https://example20.com"])
	}

	func testSidebarPinnedGridShowsDomainInitialWhenFaviconIsMissing() throws {
		let viewModel = makeViewModel()
		viewModel.pinTab(id: viewModel.tabs[0].id)

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		sidebar.layoutSubtreeIfNeeded()

		let collectionView = try pinnedTabsCollectionView(in: sidebar)

		XCTAssertEqual(collectionView.numberOfItems(inSection: 0), 1)
		XCTAssertEqual(pinnedFallbackLabels(in: collectionView), ["N"])
	}

	func testSidebarKeepsUntouchedPinnedFaviconViewWhenAnotherPinnedTabStartsLoading() throws {
		let viewModel = makeViewModel()
		viewModel.openNewTab(with: "https://swift.org")
		let firstPinnedTabID = viewModel.tabs[0].id
		let secondPinnedTabID = viewModel.tabs[1].id
		viewModel.updateTabFaviconURL("https://navigator.zip/favicon.ico", for: firstPinnedTabID)
		viewModel.updateTabFaviconURL("https://swift.org/favicon.ico", for: secondPinnedTabID)
		viewModel.pinTab(id: firstPinnedTabID)
		viewModel.pinTab(id: secondPinnedTabID)

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		sidebar.layoutSubtreeIfNeeded()

		let collectionView = try pinnedTabsCollectionView(in: sidebar)
		let untouchedFaviconViewBefore = try pinnedFaviconView(
			in: collectionView,
			at: 1
		)

		viewModel.selectTab(id: firstPinnedTabID)
		viewModel.updateTabURL("https://navigator.zip/loading", for: firstPinnedTabID)
		sidebar.layoutSubtreeIfNeeded()

		let untouchedFaviconViewAfter = try pinnedFaviconView(
			in: collectionView,
			at: 1
		)

		XCTAssertTrue(untouchedFaviconViewBefore === untouchedFaviconViewAfter)
	}

	func testPinnedSelectionChangeDoesNotRecreatePinnedFaviconViews() throws {
		let viewModel = makeViewModel()
		viewModel.openNewTab(with: "https://swift.org")
		let firstPinnedTabID = viewModel.tabs[0].id
		let secondPinnedTabID = viewModel.tabs[1].id
		viewModel.updateTabFaviconURL("https://navigator.zip/favicon.ico", for: firstPinnedTabID)
		viewModel.updateTabFaviconURL("https://swift.org/favicon.ico", for: secondPinnedTabID)
		viewModel.pinTab(id: firstPinnedTabID)
		viewModel.pinTab(id: secondPinnedTabID)
		viewModel.selectTab(id: firstPinnedTabID)

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		sidebar.layoutSubtreeIfNeeded()

		let collectionView = try pinnedTabsCollectionView(in: sidebar)
		let firstFaviconBefore = try pinnedFaviconView(in: collectionView, at: 0)
		let secondFaviconBefore = try pinnedFaviconView(in: collectionView, at: 1)

		viewModel.selectTab(id: secondPinnedTabID)
		sidebar.layoutSubtreeIfNeeded()

		let firstFaviconAfter = try pinnedFaviconView(in: collectionView, at: 0)
		let secondFaviconAfter = try pinnedFaviconView(in: collectionView, at: 1)

		XCTAssertTrue(firstFaviconBefore === firstFaviconAfter)
		XCTAssertTrue(secondFaviconBefore === secondFaviconAfter)
	}

	func testSidebarPinnedGridSkipsWWWForFallbackInitial() throws {
		let viewModel = makeViewModel()
		viewModel.updateTabURL("https://www.example.com/path", for: viewModel.tabs[0].id)
		viewModel.pinTab(id: viewModel.tabs[0].id)

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		sidebar.layoutSubtreeIfNeeded()

		let collectionView = try pinnedTabsCollectionView(in: sidebar)

		XCTAssertEqual(collectionView.numberOfItems(inSection: 0), 1)
		XCTAssertEqual(pinnedFallbackLabels(in: collectionView), ["E"])
	}

	func testPinnedTileUsesSelectedRowChromeWhenSelected() throws {
		let viewModel = makeViewModel()
		viewModel.updateTabFaviconURL("https://navigator.zip/favicon.ico", for: viewModel.tabs[0].id)
		viewModel.pinTab(id: viewModel.tabs[0].id)

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.appearance = NSAppearance(named: .aqua)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		sidebar.layoutSubtreeIfNeeded()

		let tileView = try pinnedTileView(in: pinnedTabsCollectionView(in: sidebar))

		assertColor(
			tileView.layer?.backgroundColor,
			matches: .white,
			file: #filePath,
			line: #line
		)
		XCTAssertEqual(tileView.layer?.shadowOpacity, 0.08)
		XCTAssertEqual(tileView.layer?.shadowRadius, 0.5)
	}

	func testPinnedTileUsesAccentBorderWhenSelectedInDarkMode() throws {
		let viewModel = makeViewModel()
		viewModel.updateTabFaviconURL("https://navigator.zip/favicon.ico", for: viewModel.tabs[0].id)
		viewModel.pinTab(id: viewModel.tabs[0].id)

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.appearance = NSAppearance(named: .darkAqua)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		sidebar.layoutSubtreeIfNeeded()

		let tileView = try pinnedTileView(in: pinnedTabsCollectionView(in: sidebar))
		let borderLayer = try XCTUnwrap(tileView.layer?.sublayers?.compactMap { $0 as? CAShapeLayer }.first)

		XCTAssertEqual(borderLayer.lineWidth, 1.5)
		assertColor(
			borderLayer.strokeColor,
			matches: Asset.Colors.accent.color,
			file: #filePath,
			line: #line
		)
	}

	func testPinnedTileSizesFaviconToHalfOfTileDimension() throws {
		let viewModel = makeViewModel()
		viewModel.updateTabFaviconURL("https://navigator.zip/favicon.ico", for: viewModel.tabs[0].id)
		viewModel.pinTab(id: viewModel.tabs[0].id)

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		sidebar.layoutSubtreeIfNeeded()

		let tileView = try pinnedTileView(in: pinnedTabsCollectionView(in: sidebar))
		let faviconView = try XCTUnwrap(
			tileView.subviews.compactMap { $0 as? BrowserTabFaviconView }.first
		)

		XCTAssertEqual(faviconView.bounds.width, 15, accuracy: 0.01)
		XCTAssertEqual(faviconView.bounds.height, 15, accuracy: 0.01)
	}

	func testPinnedTileUsesHoverRowChromeWhenHovered() throws {
		let viewModel = makeViewModel()
		viewModel.pinTab(id: viewModel.tabs[0].id)
		viewModel.openNewTab(with: "https://swift.org")
		viewModel.selectTab(id: viewModel.tabs[1].id)

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		sidebar.layoutSubtreeIfNeeded()

		let tileView = try pinnedTileView(in: pinnedTabsCollectionView(in: sidebar))
		let hoverEvent = try XCTUnwrap(
			NSEvent.enterExitEvent(
				with: .mouseEntered,
				location: NSPoint(x: tileView.bounds.midX, y: tileView.bounds.midY),
				modifierFlags: [],
				timestamp: 0,
				windowNumber: 0,
				context: nil,
				eventNumber: 0,
				trackingNumber: 0,
				userData: nil
			)
		)

		tileView.mouseEntered(with: hoverEvent)

		assertColor(
			tileView.layer?.backgroundColor,
			matches: Color.navigatorChromeFill,
			file: #filePath,
			line: #line
		)
	}

	func testPinnedTileUsesHoverRowChromeWhenUnselectedAndIdle() throws {
		let viewModel = makeViewModel()
		viewModel.pinTab(id: viewModel.tabs[0].id)
		viewModel.openNewTab(with: "https://swift.org")
		viewModel.selectTab(id: viewModel.tabs[1].id)

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		sidebar.layoutSubtreeIfNeeded()

		let tileView = try pinnedTileView(in: pinnedTabsCollectionView(in: sidebar))

		assertColor(
			tileView.layer?.backgroundColor,
			matches: Color.navigatorChromeFill,
			file: #filePath,
			line: #line
		)
	}

	func testSidebarAppliesFivePointSpacingBetweenTabRows() throws {
		let viewModel = makeViewModel()
		viewModel.addTab()

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		sidebar.layoutSubtreeIfNeeded()

		let rowFrames = sidebar.recursiveSubviews
			.compactMap { $0 as? BrowserSidebarTabRow }
			.map { row in
				sidebar.convert(row.bounds, from: row)
			}
			.sorted { $0.minY < $1.minY }
		let firstRow = try XCTUnwrap(rowFrames.first)
		let secondRow = try XCTUnwrap(rowFrames.dropFirst().first)

		XCTAssertEqual(secondRow.minY - firstRow.maxY, 5)
	}

	func testSidebarRefreshesCachedRowsWhenShownAgain() throws {
		let viewModel = makeViewModel()
		viewModel.tabs[0].updatePageTitle("First")

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(isPresented: true),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		let window = NSWindow(
			contentRect: sidebar.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = sidebar
		sidebar.layoutSubtreeIfNeeded()

		XCTAssertNotNil(
			row(
				titled: "First",
				in: sidebar.recursiveSubviews.compactMap { $0 as? BrowserSidebarTabRow }
			)
		)

		sidebar.setPresented(false, animated: false)
		viewModel.tabs[0].updatePageTitle("Updated")
		sidebar.setPresented(true, animated: false)
		sidebar.layoutSubtreeIfNeeded()

		let updatedRow = try XCTUnwrap(
			row(
				titled: "Updated",
				in: sidebar.recursiveSubviews.compactMap { $0 as? BrowserSidebarTabRow }
			)
		)

		XCTAssertNotNil(updatedRow)
	}

	func testAddressFieldUsesDedicatedContainerBackground() throws {
		let viewModel = makeViewModel()
		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		sidebar.layoutSubtreeIfNeeded()

		let addressField = try XCTUnwrap(
			sidebar.recursiveSubviews
				.compactMap { $0 as? NSTextField }
				.first { $0.delegate === sidebar }
		)
		let addressFieldContainer = try XCTUnwrap(addressField.superview)
		XCTAssertFalse(addressField.drawsBackground)
		XCTAssertNil(addressField.layer?.backgroundColor)
		XCTAssertLessThanOrEqual(addressField.frame.minX, addressFieldContainer.bounds.minX)
		XCTAssertGreaterThanOrEqual(addressField.frame.maxX, addressFieldContainer.bounds.maxX)
		XCTAssertEqual(addressField.frame.height, 24)
		XCTAssertEqual(addressFieldContainer.bounds.height, 32)
		XCTAssertEqual(addressField.frame.minY, 4)
		XCTAssertEqual(addressField.frame.maxY, 28)
		XCTAssertEqual(addressFieldContainer.layer?.cornerRadius, 8)
		assertColor(
			addressFieldContainer.layer?.backgroundColor,
			matches: Color.navigatorChromeFill,
			file: #filePath,
			line: #line
		)
	}

	func testAddressFieldHitTestRoutesToTextField() throws {
		let viewModel = makeViewModel()
		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		sidebar.layoutSubtreeIfNeeded()

		let addressField = try XCTUnwrap(
			sidebar.recursiveSubviews
				.compactMap { $0 as? NSTextField }
				.first { $0.delegate === sidebar }
		)
		let pointInSidebar = sidebar.convert(
			NSPoint(x: addressField.bounds.midX, y: addressField.bounds.midY),
			from: addressField
		)
		let hitView = try XCTUnwrap(sidebar.hitTest(pointInSidebar))

		XCTAssertTrue(hitView === addressField, "Expected address field hit target, got \(type(of: hitView))")
	}

	func testAddressFieldEditingRectMatchesDisplayRect() {
		let bounds = CGRect(x: 0, y: 0, width: 280, height: 24)
		let font = NSFont.preferredFont(forTextStyle: .body)
		let displayRect = BrowserSidebarAddressFieldLayout.displayRect(
			forBounds: bounds,
			font: font,
			verticalInset: 1,
			verticalOffset: 1.5,
			horizontalInset: 10
		)
		let editingRect = BrowserSidebarAddressFieldLayout.editingRect(
			forBounds: bounds,
			font: font,
			verticalInset: 1,
			verticalOffset: 1.5,
			horizontalInset: 10
		)

		XCTAssertEqual(displayRect, editingRect)
		XCTAssertEqual(displayRect.origin.x, 10)
		XCTAssertGreaterThan(displayRect.origin.y, bounds.origin.y)
	}

	func testAddressFieldLayoutFallsBackToSystemFontWhenFontMissing() {
		let bounds = CGRect(x: 0, y: 0, width: 280, height: 24)

		let displayRect = BrowserSidebarAddressFieldLayout.displayRect(
			forBounds: bounds,
			font: nil,
			verticalInset: 1,
			verticalOffset: 1.5,
			horizontalInset: 10
		)

		XCTAssertEqual(displayRect.origin.x, 10)
		XCTAssertGreaterThan(displayRect.height, 0)
	}

	func testSidebarResolvedColorFallsBackWhenConversionReturnsNil() {
		let fallbackColor = NSColor.systemBlue

		let resolvedColor = BrowserSidebarView.resolvedColorForTesting(
			fallback: fallbackColor,
			convertedColor: nil
		)

		XCTAssertEqual(resolvedColor, fallbackColor)
	}

	func testSidebarViewStateChangeHandlerReturnsFalseWithoutOwner() {
		let handled = BrowserSidebarView.handleViewStateChangeForTesting(owner: nil)

		XCTAssertFalse(handled)
	}

	func testTabRowPreservesSidebarCellDesignMetricsAndContent() throws {
		let tab = BrowserTabViewModel(initialURL: "https://navigator.zip/path")
		tab.updatePageTitle("Navigator")

		let row = BrowserSidebarTabRow(
			isSelected: true,
			newTabTitle: "New Tab",
			closeTabActionTitle: "Close Tab",
			controlIconDimensions: NSSize(width: 16, height: 16),
			rowBackgroundColor: .windowBackgroundColor
		)
		row.configure(
			with: tab,
			isFaviconLoadingEnabled: true,
			isSelected: true,
			onClose: {},
			onSelect: {}
		)
		row.appearance = NSAppearance(named: .aqua)
		row.frame = CGRect(x: 0, y: 0, width: 280, height: 40)
		row.layoutSubtreeIfNeeded()

		let labels = row.recursiveSubviews.compactMap { $0 as? BrowserSidebarLabel }
		let closeButton = try XCTUnwrap(row.recursiveSubviews.compactMap { $0 as? NSButton }.first)
		let selectedBackground = try XCTUnwrap(row.subviews.first)
		let borderLayer = try XCTUnwrap(
			selectedBackground.layer?.sublayers?.compactMap { $0 as? CAShapeLayer }.first
		)

		XCTAssertEqual(row.intrinsicContentSize.height, 40)
		XCTAssertEqual(labels.map(\.stringValue), ["Navigator"])
		XCTAssertTrue(closeButton.isHidden)
		XCTAssertEqual(closeButton.toolTip, "Close Tab")
		XCTAssertEqual(selectedBackground.layer?.allowsEdgeAntialiasing, true)
		XCTAssertEqual(borderLayer.allowsEdgeAntialiasing, true)
		XCTAssertEqual(selectedBackground.frame.minX, 15)
		XCTAssertEqual(selectedBackground.frame.width, row.bounds.width - 30)
		assertColor(
			selectedBackground.layer?.backgroundColor,
			matches: .white,
			file: #filePath,
			line: #line
		)
		XCTAssertEqual(selectedBackground.layer?.shadowOpacity, 0.18)
		XCTAssertEqual(selectedBackground.layer?.shadowRadius, 1)
		XCTAssertEqual(borderLayer.lineWidth, 1)
	}

	func testTabRowShowsCameraActivityIndicatorUntilCloseButtonIsVisible() {
		let tab = BrowserTabViewModel(initialURL: "https://navigator.zip/path")
		tab.updatePageTitle("Navigator")

		let row = BrowserSidebarTabRow(
			isSelected: true,
			newTabTitle: "New Tab",
			closeTabActionTitle: "Close Tab",
			controlIconDimensions: NSSize(width: 16, height: 16),
			rowBackgroundColor: .windowBackgroundColor
		)
		row.configure(
			with: tab,
			isFaviconLoadingEnabled: true,
			isSelected: true,
			isCameraActive: true,
			cameraActivityAccessibilityLabel: "Navigator Camera active",
			onClose: {},
			onSelect: {}
		)
		row.frame = CGRect(x: 0, y: 0, width: 280, height: 40)

		let window = NSWindow(
			contentRect: row.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		let container = NSView(frame: row.frame)
		container.addSubview(row)
		window.contentView = container
		container.layoutSubtreeIfNeeded()

		XCTAssertFalse(row.isCameraActivityIndicatorHiddenForTesting)
		XCTAssertEqual(row.cameraActivityIndicatorToolTipForTesting, "Navigator Camera active")

		let hoverPoint = row.convert(NSPoint(x: row.bounds.maxX - 12, y: row.bounds.midY), to: nil as NSView?)
		row.syncHoverStateForCurrentPointerLocation(mouseLocationInWindow: hoverPoint)

		XCTAssertTrue(row.isCameraActivityIndicatorHiddenForTesting)
	}

	func testTabRowHitTestReturnsRowForNonControlContent() throws {
		let tab = BrowserTabViewModel(initialURL: "https://navigator.zip/path")
		tab.updatePageTitle("Navigator")

		let row = BrowserSidebarTabRow(
			isSelected: true,
			newTabTitle: "New Tab",
			closeTabActionTitle: "Close Tab",
			controlIconDimensions: NSSize(width: 16, height: 16),
			rowBackgroundColor: .windowBackgroundColor
		)
		row.configure(
			with: tab,
			isFaviconLoadingEnabled: true,
			isSelected: true,
			onClose: {},
			onSelect: {}
		)
		row.frame = CGRect(x: 0, y: 0, width: 280, height: 40)
		row.layoutSubtreeIfNeeded()

		let titleLabel = try XCTUnwrap(
			row.recursiveSubviews
				.compactMap { $0 as? BrowserSidebarLabel }
				.first { $0.stringValue == "Navigator" }
		)
		let hitPoint = row.convert(
			NSPoint(x: titleLabel.bounds.midX, y: titleLabel.bounds.midY),
			from: titleLabel
		)

		XCTAssertTrue(row.hitTest(hitPoint) === row)
	}

	func testTabRowShowsURLWhenPageTitleIsUnavailable() {
		let tab = BrowserTabViewModel(
			id: BrowserTabID(),
			initialURL: "https://navigator.zip",
			currentURL: "https://navigator.zip/path"
		)

		let row = BrowserSidebarTabRow(
			isSelected: false,
			newTabTitle: "New Tab",
			closeTabActionTitle: "Close Tab",
			controlIconDimensions: NSSize(width: 16, height: 16),
			rowBackgroundColor: .windowBackgroundColor
		)
		row.configure(
			with: tab,
			isFaviconLoadingEnabled: true,
			isSelected: false,
			onClose: {},
			onSelect: {}
		)
		row.frame = CGRect(x: 0, y: 0, width: 280, height: 40)
		row.layoutSubtreeIfNeeded()

		let labels = row.recursiveSubviews.compactMap { $0 as? BrowserSidebarLabel }

		XCTAssertEqual(labels.map(\.stringValue), ["https://navigator.zip/path"])
	}

	func testTabRowShowsUnpinMenuItemWhenPinned() {
		let tab = BrowserTabViewModel(initialURL: "https://navigator.zip", isPinned: true)
		tab.updatePageTitle("Navigator")

		let row = BrowserSidebarTabRow(
			isSelected: false,
			newTabTitle: "New Tab",
			closeTabActionTitle: "Close Tab",
			pinTabActionTitle: "Pin Tab",
			unpinTabActionTitle: "Unpin Tab",
			controlIconDimensions: NSSize(width: 16, height: 16),
			rowBackgroundColor: .windowBackgroundColor
		)
		row.configure(
			with: tab,
			isFaviconLoadingEnabled: true,
			isSelected: false,
			onClose: {},
			onSelect: {}
		)

		XCTAssertEqual(row.contextMenuItemTitlesForTesting, ["Unpin Tab"])
	}

	func testTabRowShowsReplacePinnedURLMenuItemWhenPinnedURLDiffersFromCurrentURL() {
		let tab = BrowserTabViewModel(initialURL: "https://navigator.zip", isPinned: true)
		tab.updateCurrentURL("https://swift.org")

		let row = BrowserSidebarTabRow(
			isSelected: false,
			newTabTitle: "New Tab",
			closeTabActionTitle: "Close Tab",
			pinTabActionTitle: "Pin Tab",
			unpinTabActionTitle: "Unpin Tab",
			replacePinnedTabURLActionTitle: "Replace Pinned Tab URL with Current URL",
			controlIconDimensions: NSSize(width: 16, height: 16),
			rowBackgroundColor: .windowBackgroundColor
		)
		row.configure(
			with: tab,
			isFaviconLoadingEnabled: true,
			isSelected: false,
			onClose: {},
			onSelect: {}
		)

		XCTAssertEqual(
			row.contextMenuItemTitlesForTesting,
			["Unpin Tab", "Replace Pinned Tab URL with Current URL"]
		)
	}

	func testTabRowShowsPinMenuItemWhenUnpinned() {
		let tab = BrowserTabViewModel(initialURL: "https://navigator.zip", isPinned: false)
		tab.updatePageTitle("Navigator")

		let row = BrowserSidebarTabRow(
			isSelected: false,
			newTabTitle: "New Tab",
			closeTabActionTitle: "Close Tab",
			pinTabActionTitle: "Pin Tab",
			unpinTabActionTitle: "Unpin Tab",
			controlIconDimensions: NSSize(width: 16, height: 16),
			rowBackgroundColor: .windowBackgroundColor
		)
		row.configure(
			with: tab,
			isFaviconLoadingEnabled: true,
			isSelected: false,
			onClose: {},
			onSelect: {}
		)

		XCTAssertEqual(row.contextMenuItemTitlesForTesting, ["Pin Tab", "", "Close Tab"])
	}

	func testTabRowContextMenuToggleActionInvokesPinClosure() throws {
		let tab = BrowserTabViewModel(initialURL: "https://navigator.zip")
		let row = BrowserSidebarTabRow(
			isSelected: false,
			newTabTitle: "New Tab",
			closeTabActionTitle: "Close Tab",
			pinTabActionTitle: "Pin Tab",
			unpinTabActionTitle: "Unpin Tab",
			controlIconDimensions: NSSize(width: 16, height: 16),
			rowBackgroundColor: .windowBackgroundColor
		)
		var didTogglePin = false
		row.configure(
			with: tab,
			isFaviconLoadingEnabled: true,
			isSelected: false,
			onClose: {},
			onSelect: {},
			onTogglePin: {
				didTogglePin = true
			}
		)

		let toggleItem = try XCTUnwrap(row.menu?.items.first)
		_ = row.perform(toggleItem.action)

		XCTAssertTrue(didTogglePin)
	}

	func testTabRowConstrainsLongTitlesWithinSidebarWidth() throws {
		let tab = BrowserTabViewModel(initialURL: "https://navigator.zip/path")
		tab.updatePageTitle(
			"Navigator Navigator Navigator Navigator Navigator Navigator Navigator Navigator"
		)

		let row = BrowserSidebarTabRow(
			isSelected: false,
			newTabTitle: "New Tab",
			closeTabActionTitle: "Close Tab",
			controlIconDimensions: NSSize(width: 16, height: 16),
			rowBackgroundColor: .windowBackgroundColor
		)
		row.configure(
			with: tab,
			isFaviconLoadingEnabled: true,
			isSelected: false,
			onClose: {},
			onSelect: {}
		)
		row.frame = CGRect(x: 0, y: 0, width: 280, height: 40)
		row.layoutSubtreeIfNeeded()

		let titleLabel = try XCTUnwrap(
			row.recursiveSubviews
				.compactMap { $0 as? BrowserSidebarLabel }
				.first { $0.stringValue == tab.displayTitle }
		)
		let selectedBackground = try XCTUnwrap(row.subviews.first)

		XCTAssertLessThanOrEqual(selectedBackground.frame.maxX, row.bounds.maxX)
		XCTAssertGreaterThanOrEqual(selectedBackground.frame.minX, row.bounds.minX)
		XCTAssertLessThanOrEqual(titleLabel.frame.maxX, selectedBackground.bounds.maxX)
	}

	func testTabRowAppliesDragStylingToInnerBackground() throws {
		let row = BrowserSidebarTabRow(
			isSelected: false,
			newTabTitle: "New Tab",
			closeTabActionTitle: "Close Tab",
			controlIconDimensions: NSSize(width: 16, height: 16),
			rowBackgroundColor: .windowBackgroundColor
		)
		row.frame = CGRect(x: 0, y: 0, width: 280, height: 40)
		row.layoutSubtreeIfNeeded()

		row.reorderableListItemDidUpdate(
			cellState: ReorderableListCellState(
				isReordering: true,
				isListReordering: true,
				isHighlighted: false,
				isSelected: false
			),
			animated: false
		)

		let selectedBackground = try XCTUnwrap(row.subviews.first)
		let borderLayer = try XCTUnwrap(
			selectedBackground.layer?.sublayers?.compactMap { $0 as? CAShapeLayer }.first
		)
		assertColor(
			selectedBackground.layer?.backgroundColor,
			matches: .windowBackgroundColor,
			file: #filePath,
			line: #line
		)
		XCTAssertEqual(selectedBackground.layer?.borderWidth, 0)
		XCTAssertEqual(borderLayer.lineWidth, 2)
		XCTAssertEqual(selectedBackground.layer?.shadowOpacity, 0)
		XCTAssertGreaterThan(abs(selectedBackground.layer?.transform.m12 ?? 0), 0.0001)
	}

	func testSelectedTabRowUsesSidebarBackgroundWhileDragging() throws {
		let row = BrowserSidebarTabRow(
			isSelected: true,
			newTabTitle: "New Tab",
			closeTabActionTitle: "Close Tab",
			controlIconDimensions: NSSize(width: 16, height: 16),
			rowBackgroundColor: .windowBackgroundColor
		)
		row.frame = CGRect(x: 0, y: 0, width: 280, height: 40)
		row.layoutSubtreeIfNeeded()

		row.reorderableListItemDidUpdate(
			cellState: ReorderableListCellState(
				isReordering: true,
				isListReordering: true,
				isHighlighted: false,
				isSelected: true
			),
			animated: false
		)

		let selectedBackground = try XCTUnwrap(row.subviews.first)
		assertColor(
			selectedBackground.layer?.backgroundColor,
			matches: .windowBackgroundColor,
			file: #filePath,
			line: #line
		)
	}

	func testTabRowAnimatedDragStylingAddsExplicitLiftAnimation() throws {
		let row = BrowserSidebarTabRow(
			isSelected: false,
			newTabTitle: "New Tab",
			closeTabActionTitle: "Close Tab",
			controlIconDimensions: NSSize(width: 16, height: 16),
			rowBackgroundColor: .windowBackgroundColor
		)
		row.frame = CGRect(x: 0, y: 0, width: 280, height: 40)
		row.layoutSubtreeIfNeeded()

		row.reorderableListItemDidUpdate(
			cellState: ReorderableListCellState(
				isReordering: true,
				isListReordering: true,
				isHighlighted: false,
				isSelected: false
			),
			animated: true
		)

		let selectedBackground = try XCTUnwrap(row.subviews.first)
		let borderLayer = try XCTUnwrap(
			selectedBackground.layer?.sublayers?.compactMap { $0 as? CAShapeLayer }.first
		)
		XCTAssertNotNil(
			selectedBackground.layer?.animation(
				forKey: BrowserSidebarTabRowLayerAnimationKey.transform
			)
		)
		XCTAssertNotNil(
			borderLayer.animation(
				forKey: BrowserSidebarTabRowLayerAnimationKey.borderWidth
			)
		)
	}

	func testTabRowDefaultStateUsesSidebarBackground() throws {
		let row = BrowserSidebarTabRow(
			isSelected: false,
			newTabTitle: "New Tab",
			closeTabActionTitle: "Close Tab",
			controlIconDimensions: NSSize(width: 16, height: 16),
			rowBackgroundColor: .windowBackgroundColor
		)
		row.frame = CGRect(x: 0, y: 0, width: 280, height: 40)
		row.layoutSubtreeIfNeeded()

		let selectedBackground = try XCTUnwrap(row.subviews.first)
		assertColor(
			selectedBackground.layer?.backgroundColor,
			matches: .windowBackgroundColor,
			file: #filePath,
			line: #line
		)
	}

	func testTabRowFirstAnimatedDragUsesSidebarBackgroundImmediately() throws {
		let row = BrowserSidebarTabRow(
			isSelected: false,
			newTabTitle: "New Tab",
			closeTabActionTitle: "Close Tab",
			controlIconDimensions: NSSize(width: 16, height: 16),
			rowBackgroundColor: .windowBackgroundColor
		)
		row.frame = CGRect(x: 0, y: 0, width: 280, height: 40)
		row.layoutSubtreeIfNeeded()

		let selectedBackground = try XCTUnwrap(row.subviews.first)
		assertColor(
			selectedBackground.layer?.backgroundColor,
			matches: .windowBackgroundColor,
			file: #filePath,
			line: #line
		)

		row.reorderableListItemDidUpdate(
			cellState: ReorderableListCellState(
				isReordering: true,
				isListReordering: true,
				isHighlighted: false,
				isSelected: false
			),
			animated: true
		)

		assertColor(
			selectedBackground.layer?.backgroundColor,
			matches: .windowBackgroundColor,
			file: #filePath,
			line: #line
		)
		XCTAssertNil(
			selectedBackground.layer?.animation(
				forKey: BrowserSidebarTabRowLayerAnimationKey.backgroundColor
			)
		)
		XCTAssertNotNil(
			selectedBackground.layer?.animation(
				forKey: BrowserSidebarTabRowLayerAnimationKey.transform
			)
		)
	}

	func testTabRowSelectedStateUsesWhiteFillAndShadowInLightMode() throws {
		let row = BrowserSidebarTabRow(
			isSelected: true,
			newTabTitle: "New Tab",
			closeTabActionTitle: "Close Tab",
			controlIconDimensions: NSSize(width: 16, height: 16),
			rowBackgroundColor: .windowBackgroundColor
		)
		row.appearance = NSAppearance(named: .aqua)
		row.frame = CGRect(x: 0, y: 0, width: 280, height: 40)
		row.layoutSubtreeIfNeeded()

		let selectedBackground = try XCTUnwrap(row.subviews.first)
		let outerBorderLayer = try XCTUnwrap(
			selectedBackground.layer?.sublayers?.compactMap { $0 as? CAShapeLayer }.first
		)
		assertColor(
			selectedBackground.layer?.backgroundColor,
			matches: .white,
			file: #filePath,
			line: #line
		)
		assertColor(
			outerBorderLayer.strokeColor,
			matches: Asset.Colors.separatorPrimaryColor.color,
			file: #filePath,
			line: #line
		)
		XCTAssertEqual(outerBorderLayer.lineWidth, 1)
		XCTAssertEqual(selectedBackground.layer?.shadowOpacity, 0.18)
		XCTAssertEqual(selectedBackground.layer?.shadowRadius, 1)
		XCTAssertEqual(selectedBackground.layer?.shadowOffset.height, 0)
	}

	func testTabRowUsesDarkModeSelectedStyleResolverForDarkAppearances() throws {
		let darkAppearance = try XCTUnwrap(NSAppearance(named: .darkAqua))

		XCTAssertFalse(BrowserSidebarTabRow.usesLightModeSelectedStyle(for: darkAppearance))
	}

	func testTabRowHoverStateUsesSidebarSelectionFill() throws {
		let row = BrowserSidebarTabRow(
			isSelected: false,
			newTabTitle: "New Tab",
			closeTabActionTitle: "Close Tab",
			controlIconDimensions: NSSize(width: 16, height: 16),
			rowBackgroundColor: .windowBackgroundColor
		)
		row.frame = CGRect(x: 0, y: 0, width: 280, height: 40)
		row.layoutSubtreeIfNeeded()

		let selectedBackground = try XCTUnwrap(row.subviews.first)
		assertColor(
			selectedBackground.layer?.backgroundColor,
			matches: .windowBackgroundColor,
			file: #filePath,
			line: #line
		)

		let hoverEvent = try XCTUnwrap(
			NSEvent.enterExitEvent(
				with: .mouseEntered,
				location: NSPoint(x: row.bounds.midX, y: row.bounds.midY),
				modifierFlags: [],
				timestamp: 0,
				windowNumber: 0,
				context: nil,
				eventNumber: 0,
				trackingNumber: 0,
				userData: nil
			)
		)
		row.mouseEntered(with: hoverEvent)

		assertColor(
			selectedBackground.layer?.backgroundColor,
			matches: Color.navigatorChromeFill,
			file: #filePath,
			line: #line
		)
	}

	func testTabRowsResyncHoverWhenScrollMovesRowsUnderStationaryPointer() throws {
		let topRow = BrowserSidebarTabRow(
			isSelected: false,
			newTabTitle: "New Tab",
			closeTabActionTitle: "Close Tab",
			controlIconDimensions: NSSize(width: 16, height: 16),
			rowBackgroundColor: .windowBackgroundColor
		)
		let bottomRow = BrowserSidebarTabRow(
			isSelected: false,
			newTabTitle: "New Tab",
			closeTabActionTitle: "Close Tab",
			controlIconDimensions: NSSize(width: 16, height: 16),
			rowBackgroundColor: .windowBackgroundColor
		)
		let documentView = NSView(frame: CGRect(x: 0, y: 0, width: 280, height: 120))
		topRow.frame = CGRect(x: 0, y: 0, width: 280, height: 40)
		bottomRow.frame = CGRect(x: 0, y: 40, width: 280, height: 40)
		documentView.addSubview(topRow)
		documentView.addSubview(bottomRow)

		let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: 280, height: 40))
		scrollView.documentView = documentView
		let window = NSWindow(
			contentRect: scrollView.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = scrollView
		scrollView.layoutSubtreeIfNeeded()
		documentView.layoutSubtreeIfNeeded()

		let stationaryMouseLocation = topRow.convert(
			NSPoint(x: topRow.bounds.midX, y: topRow.bounds.midY),
			to: nil
		)
		topRow.mouseLocationInWindowOverride = stationaryMouseLocation
		bottomRow.mouseLocationInWindowOverride = stationaryMouseLocation

		topRow.syncHoverStateForCurrentPointerLocation()
		bottomRow.syncHoverStateForCurrentPointerLocation()

		let topCloseButton = try XCTUnwrap(topRow.recursiveSubviews.compactMap { $0 as? NSButton }.first)
		let bottomCloseButton = try XCTUnwrap(
			bottomRow.recursiveSubviews.compactMap { $0 as? NSButton }.first
		)
		let topSelectedBackground = try XCTUnwrap(topRow.subviews.first)
		let bottomSelectedBackground = try XCTUnwrap(bottomRow.subviews.first)

		XCTAssertFalse(topCloseButton.isHidden)
		XCTAssertTrue(bottomCloseButton.isHidden)
		assertColor(
			topSelectedBackground.layer?.backgroundColor,
			matches: Color.navigatorChromeFill,
			file: #filePath,
			line: #line
		)
		assertColor(
			bottomSelectedBackground.layer?.backgroundColor,
			matches: .windowBackgroundColor,
			file: #filePath,
			line: #line
		)

		scrollView.contentView.scroll(to: NSPoint(x: 0, y: 40))
		scrollView.reflectScrolledClipView(scrollView.contentView)
		NotificationCenter.default.post(
			name: NSView.boundsDidChangeNotification,
			object: scrollView.contentView
		)

		XCTAssertTrue(topCloseButton.isHidden)
		XCTAssertFalse(bottomCloseButton.isHidden)
		assertColor(
			topSelectedBackground.layer?.backgroundColor,
			matches: .windowBackgroundColor,
			file: #filePath,
			line: #line
		)
		assertColor(
			bottomSelectedBackground.layer?.backgroundColor,
			matches: Color.navigatorChromeFill,
			file: #filePath,
			line: #line
		)
	}

	func testTabRowTextUsesTrailingSpaceUntilHoverShowsCloseButton() throws {
		let tab = BrowserTabViewModel(initialURL: "https://navigator.example/really/long/path")
		tab.updatePageTitle(
			"Navigator Navigator Navigator Navigator Navigator Navigator Navigator Navigator"
		)

		let row = BrowserSidebarTabRow(
			isSelected: false,
			newTabTitle: "New Tab",
			closeTabActionTitle: "Close Tab",
			controlIconDimensions: NSSize(width: 16, height: 16),
			rowBackgroundColor: .windowBackgroundColor
		)
		row.configure(
			with: tab,
			isFaviconLoadingEnabled: true,
			isSelected: false,
			onClose: {},
			onSelect: {}
		)
		row.frame = CGRect(x: 0, y: 0, width: 280, height: 40)
		row.layoutSubtreeIfNeeded()

		let titleLabel = try XCTUnwrap(
			row.recursiveSubviews
				.compactMap { $0 as? BrowserSidebarLabel }
				.first { $0.stringValue == tab.displayTitle }
		)
		let closeButton = try XCTUnwrap(row.recursiveSubviews.compactMap { $0 as? NSButton }.first)
		let selectedBackground = try XCTUnwrap(row.subviews.first)
		let initialMaxX = titleLabel.frame.maxX

		XCTAssertTrue(closeButton.isHidden)
		XCTAssertEqual(
			activeTrailingConstraints(for: titleLabel, in: selectedBackground).count,
			1
		)

		let hoverEvent = try XCTUnwrap(
			NSEvent.enterExitEvent(
				with: .mouseEntered,
				location: NSPoint(x: row.bounds.midX, y: row.bounds.midY),
				modifierFlags: [],
				timestamp: 0,
				windowNumber: 0,
				context: nil,
				eventNumber: 0,
				trackingNumber: 0,
				userData: nil
			)
		)
		row.mouseEntered(with: hoverEvent)
		row.layoutSubtreeIfNeeded()

		XCTAssertFalse(closeButton.isHidden)
		XCTAssertLessThan(titleLabel.frame.maxX, initialMaxX)
		XCTAssertEqual(
			activeTrailingConstraints(for: titleLabel, in: selectedBackground).count,
			1
		)
	}

	func testTabRowCloseButtonUsesDedicatedHoverHighlight() throws {
		let tab = BrowserTabViewModel(initialURL: "https://navigator.example/really/long/path")
		tab.updatePageTitle("Navigator")

		let row = BrowserSidebarTabRow(
			isSelected: false,
			newTabTitle: "New Tab",
			closeTabActionTitle: "Close Tab",
			controlIconDimensions: NSSize(width: 16, height: 16),
			rowBackgroundColor: .windowBackgroundColor
		)
		row.configure(
			with: tab,
			isFaviconLoadingEnabled: true,
			isSelected: false,
			onClose: {},
			onSelect: {}
		)
		row.appearance = NSAppearance(named: .aqua)
		row.frame = CGRect(x: 0, y: 0, width: 280, height: 40)
		row.layoutSubtreeIfNeeded()

		let closeButton = try XCTUnwrap(row.recursiveSubviews.compactMap { $0 as? NSButton }.first)
		let titleLabel = try XCTUnwrap(
			row.recursiveSubviews
				.compactMap { $0 as? BrowserSidebarLabel }
				.first { $0.stringValue == "Navigator" }
		)

		let rowHoverLocation = row.convert(
			NSPoint(x: titleLabel.bounds.midX, y: titleLabel.bounds.midY),
			from: titleLabel
		)
		row.syncHoverStateForCurrentPointerLocation(
			mouseLocationInWindow: row.convert(rowHoverLocation, to: nil)
		)

		assertColor(
			row.closeButtonHighlightColorForTesting,
			matches: .clear,
			file: #filePath,
			line: #line
		)

		let closeButtonHoverLocation = row.convert(
			NSPoint(x: closeButton.bounds.midX, y: closeButton.bounds.midY),
			from: closeButton
		)
		row.syncHoverStateForCurrentPointerLocation(
			mouseLocationInWindow: row.convert(closeButtonHoverLocation, to: nil)
		)

		var expectedHighlightColor = NSColor.secondaryLabelColor.withAlphaComponent(0.45)
		(row.appearance ?? row.effectiveAppearance).performAsCurrentDrawingAppearance {
			expectedHighlightColor = NSColor.secondaryLabelColor.withAlphaComponent(0.45)
		}

		assertColor(
			row.closeButtonHighlightColorForTesting,
			matches: expectedHighlightColor,
			file: #filePath,
			line: #line
		)
		assertColor(
			row.closeButtonTintColorForTesting?.usingColorSpace(.deviceRGB)?.cgColor,
			matches: .white,
			file: #filePath,
			line: #line
		)
		XCTAssertEqual(row.closeButtonHighlightFrameForTesting.width, 24)
		XCTAssertEqual(row.closeButtonHighlightFrameForTesting.height, 24)
		XCTAssertEqual(row.closeButtonHighlightCornerRadiusForTesting, 6)

		row.syncHoverStateForCurrentPointerLocation(
			mouseLocationInWindow: row.convert(rowHoverLocation, to: nil)
		)

		assertColor(
			row.closeButtonHighlightColorForTesting,
			matches: .clear,
			file: #filePath,
			line: #line
		)
	}

	func testTabRowTrailingWhitespaceClickStillSelectsWhenCloseButtonIsVisible() throws {
		let tab = BrowserTabViewModel(initialURL: "https://navigator.example/really/long/path")
		tab.updatePageTitle("Navigator")
		var selectCount = 0

		let row = BrowserSidebarTabRow(
			isSelected: false,
			newTabTitle: "New Tab",
			closeTabActionTitle: "Close Tab",
			controlIconDimensions: NSSize(width: 16, height: 16),
			rowBackgroundColor: .windowBackgroundColor
		)
		row.configure(
			with: tab,
			isFaviconLoadingEnabled: true,
			isSelected: false,
			onClose: {},
			onSelect: { selectCount += 1 }
		)
		row.frame = CGRect(x: 0, y: 0, width: 280, height: 40)
		let window = NSWindow(
			contentRect: row.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = row
		row.layoutSubtreeIfNeeded()

		let closeButton = try XCTUnwrap(row.recursiveSubviews.compactMap { $0 as? NSButton }.first)
		let actualCloseButtonFrame = row.convert(closeButton.bounds, from: closeButton)
		let clickPoint = NSPoint(
			x: actualCloseButtonFrame.minX - 4,
			y: actualCloseButtonFrame.midY
		)
		let eventLocation = row.convert(clickPoint, to: nil as NSView?)

		row.syncHoverStateForCurrentPointerLocation(mouseLocationInWindow: eventLocation)

		XCTAssertFalse(closeButton.isHidden)

		let mouseDownEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDown,
				location: eventLocation,
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 0,
				clickCount: 1,
				pressure: 1
			)
		)
		let mouseUpEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseUp,
				location: eventLocation,
				modifierFlags: [],
				timestamp: 0.1,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 1,
				clickCount: 1,
				pressure: 1
			)
		)

		row.mouseDown(with: mouseDownEvent)
		row.mouseUp(with: mouseUpEvent)

		XCTAssertEqual(selectCount, 1)
	}

	func testFaviconViewDefersLoadingUntilItIsVisibleInWindow() async throws {
		let recorder = FaviconLoadRecorder()
		let tab = BrowserTabViewModel(initialURL: "https://example.com/page")
		let faviconView = BrowserTabFaviconView(
			tab: tab,
			viewModel: BrowserTabFaviconViewModel(
				loadData: { _ in
					await recorder.recordLoad()
					return Data("favicon".utf8)
				},
				loadCachedData: { _ in nil }
			)
		)
		faviconView.frame = CGRect(x: 0, y: 0, width: 16, height: 16)

		try await Task.sleep(for: .milliseconds(50))
		let initialLoadCount = await recorder.loadCount()
		XCTAssertEqual(initialLoadCount, 0)

		let documentView = NSView(frame: CGRect(x: 0, y: 0, width: 120, height: 200))
		documentView.addSubview(faviconView)
		let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: 120, height: 80))
		scrollView.documentView = documentView
		let window = NSWindow(
			contentRect: scrollView.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = scrollView
		scrollView.layoutSubtreeIfNeeded()
		documentView.layoutSubtreeIfNeeded()

		for _ in 0..<50 {
			if await recorder.loadCount() == 1 {
				return
			}
			try await Task.sleep(for: .milliseconds(10))
		}

		XCTFail("Expected visible favicon view to trigger a load")
	}

	func testFaviconViewRestoresCachedImageBeforeItBecomesVisible() async throws {
		let recorder = FaviconLoadRecorder()
		let sampleImageData = try XCTUnwrap(sampleImageData())
		let tab = BrowserTabViewModel(initialURL: "https://example.com/page")
		let faviconView = BrowserTabFaviconView(
			tab: tab,
			viewModel: BrowserTabFaviconViewModel(
				loadData: { _ in
					await recorder.recordLoad()
					return nil
				},
				loadCachedData: { _ in sampleImageData }
			),
			showsPlaceholderWhenMissing: false
		)
		faviconView.frame = CGRect(x: 0, y: 0, width: 16, height: 16)

		for _ in 0..<50 {
			if faviconView.hasResolvedImage {
				XCTAssertFalse(faviconView.imageViewIsHiddenForTesting)
				let networkLoadCount = await recorder.loadCount()
				XCTAssertEqual(networkLoadCount, 0)
				return
			}
			try await Task.sleep(for: .milliseconds(10))
		}

		XCTFail("Expected cached favicon image to resolve before the view became visible")
	}

	func testFaviconViewRestoresCachedExplicitFaviconBeforeItBecomesVisible() async throws {
		let recorder = FaviconLoadRecorder()
		let cacheRecorder = RequestedURLRecorder()
		let sampleImageData = try XCTUnwrap(sampleImageData())
		let explicitFaviconURL = "https://example.com/assets/icon.png"
		let tab = BrowserTabViewModel(initialURL: "https://example.com/page")
		tab.updateFaviconURL(explicitFaviconURL)
		let faviconView = BrowserTabFaviconView(
			tab: tab,
			viewModel: BrowserTabFaviconViewModel(
				loadData: { _ in
					await recorder.recordLoad()
					return nil
				},
				loadCachedData: { url in
					await cacheRecorder.record(url)
					return url.absoluteString == explicitFaviconURL ? sampleImageData : nil
				}
			),
			showsPlaceholderWhenMissing: false
		)
		faviconView.frame = CGRect(x: 0, y: 0, width: 16, height: 16)

		for _ in 0..<50 {
			if faviconView.hasResolvedImage {
				XCTAssertFalse(faviconView.imageViewIsHiddenForTesting)
				let networkLoadCount = await recorder.loadCount()
				let cachedURLs = await cacheRecorder.snapshot()
				XCTAssertEqual(networkLoadCount, 0)
				XCTAssertEqual(cachedURLs.map(\.absoluteString), [explicitFaviconURL])
				return
			}
			try await Task.sleep(for: .milliseconds(10))
		}

		XCTFail("Expected cached explicit favicon image to resolve before the view became visible")
	}

	func testFaviconViewCanSuppressPlaceholderUntilARealImageLoads() async throws {
		let sampleImageData = try XCTUnwrap(sampleImageData())
		let tab = BrowserTabViewModel(initialURL: "https://example.com/page")
		let faviconView = BrowserTabFaviconView(
			tab: tab,
			viewModel: BrowserTabFaviconViewModel(
				loadData: { _ in sampleImageData },
				loadCachedData: { _ in nil }
			),
			showsPlaceholderWhenMissing: false
		)
		faviconView.frame = CGRect(x: 0, y: 0, width: 16, height: 16)

		XCTAssertFalse(faviconView.hasResolvedImage)
		XCTAssertTrue(faviconView.imageViewIsHiddenForTesting)

		let documentView = NSView(frame: CGRect(x: 0, y: 0, width: 120, height: 200))
		documentView.addSubview(faviconView)
		let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: 120, height: 80))
		scrollView.documentView = documentView
		let window = NSWindow(
			contentRect: scrollView.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = scrollView
		scrollView.layoutSubtreeIfNeeded()
		documentView.layoutSubtreeIfNeeded()

		for _ in 0..<50 {
			if faviconView.hasResolvedImage {
				XCTAssertFalse(faviconView.imageViewIsHiddenForTesting)
				return
			}
			try await Task.sleep(for: .milliseconds(10))
		}

		XCTFail("Expected favicon view to resolve an image")
	}

	func testFaviconViewKeepsLoadingSameTabAfterReconfigureCancelsInFlightTask() async throws {
		let recorder = FaviconLoadRecorder()
		let sampleImageData = try XCTUnwrap(sampleImageData())
		let tab = BrowserTabViewModel(initialURL: "https://example.com/page")
		let faviconView = BrowserTabFaviconView(
			tab: tab,
			viewModel: BrowserTabFaviconViewModel(
				loadData: { _ in
					await recorder.recordLoad()
					try? await Task.sleep(for: .milliseconds(60))
					return sampleImageData
				},
				loadCachedData: { _ in nil }
			),
			showsPlaceholderWhenMissing: false
		)
		faviconView.frame = CGRect(x: 0, y: 0, width: 16, height: 16)

		let documentView = NSView(frame: CGRect(x: 0, y: 0, width: 120, height: 200))
		documentView.addSubview(faviconView)
		let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: 120, height: 80))
		scrollView.documentView = documentView
		let window = NSWindow(
			contentRect: scrollView.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = scrollView
		scrollView.layoutSubtreeIfNeeded()
		documentView.layoutSubtreeIfNeeded()

		try await waitForFaviconLoadCount(1, recorder: recorder)
		faviconView.configure(tab: tab, isLoadingEnabled: true)

		for _ in 0..<50 {
			if faviconView.hasResolvedImage {
				XCTAssertFalse(faviconView.imageViewIsHiddenForTesting)
				return
			}
			try await Task.sleep(for: .milliseconds(10))
		}

		XCTFail("Expected same-tab reconfigure to keep the favicon load alive")
	}

	func testFaviconViewKeepsLoadingSameTabAfterVisibilityChurn() async throws {
		let recorder = FaviconLoadRecorder()
		let sampleImageData = try XCTUnwrap(sampleImageData())
		let tab = BrowserTabViewModel(initialURL: "https://example.com/page")
		let faviconView = BrowserTabFaviconView(
			tab: tab,
			viewModel: BrowserTabFaviconViewModel(
				loadData: { _ in
					await recorder.recordLoad()
					try? await Task.sleep(for: .milliseconds(60))
					return sampleImageData
				},
				loadCachedData: { _ in nil }
			),
			showsPlaceholderWhenMissing: false
		)
		faviconView.frame = CGRect(x: 0, y: 0, width: 16, height: 16)

		let documentView = NSView(frame: CGRect(x: 0, y: 0, width: 120, height: 200))
		documentView.addSubview(faviconView)
		let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: 120, height: 80))
		scrollView.documentView = documentView
		let window = NSWindow(
			contentRect: scrollView.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = scrollView
		scrollView.layoutSubtreeIfNeeded()
		documentView.layoutSubtreeIfNeeded()

		try await waitForFaviconLoadCount(1, recorder: recorder)
		scrollView.contentView.scroll(to: NSPoint(x: 0, y: 100))
		scrollView.reflectScrolledClipView(scrollView.contentView)
		scrollView.contentView.scroll(to: .zero)
		scrollView.reflectScrolledClipView(scrollView.contentView)

		for _ in 0..<50 {
			if faviconView.hasResolvedImage {
				XCTAssertFalse(faviconView.imageViewIsHiddenForTesting)
				return
			}
			try await Task.sleep(for: .milliseconds(10))
		}

		XCTFail("Expected same-tab visibility churn to keep the favicon load alive")
	}

	func testFaviconViewLoadsWhenHiddenAncestorBecomesVisible() async throws {
		let sampleImageData = try XCTUnwrap(sampleImageData())
		let tab = BrowserTabViewModel(initialURL: "https://example.com/page")
		let faviconView = BrowserTabFaviconView(
			tab: tab,
			viewModel: BrowserTabFaviconViewModel(
				loadData: { _ in sampleImageData },
				loadCachedData: { _ in nil }
			),
			showsPlaceholderWhenMissing: false
		)
		faviconView.frame = CGRect(x: 0, y: 0, width: 16, height: 16)

		let hiddenContainer = NSView(frame: CGRect(x: 0, y: 0, width: 120, height: 40))
		hiddenContainer.isHidden = true
		hiddenContainer.addSubview(faviconView)
		let documentView = NSView(frame: CGRect(x: 0, y: 0, width: 120, height: 200))
		documentView.addSubview(hiddenContainer)
		let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: 120, height: 80))
		scrollView.documentView = documentView
		let window = NSWindow(
			contentRect: scrollView.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = scrollView
		scrollView.layoutSubtreeIfNeeded()
		documentView.layoutSubtreeIfNeeded()

		XCTAssertFalse(faviconView.hasResolvedImage)
		hiddenContainer.isHidden = false
		hiddenContainer.needsLayout = true
		documentView.layoutSubtreeIfNeeded()
		scrollView.layoutSubtreeIfNeeded()

		for _ in 0..<50 {
			if faviconView.hasResolvedImage {
				XCTAssertFalse(faviconView.imageViewIsHiddenForTesting)
				return
			}
			try await Task.sleep(for: .milliseconds(10))
		}

		XCTFail("Expected favicon view to resolve after its hidden ancestor became visible")
	}

	private func makeViewModel() -> BrowserSidebarViewModel {
		BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: BrowserSidebarActions(
				onGoBack: { _ in },
				onGoForward: { _ in },
				onReload: { _ in },
				onSubmitAddress: { _, _ in },
				navigationState: { _ in .idle }
			)
		)
	}

	private func makeViewModel(actions: BrowserSidebarActions) -> BrowserSidebarViewModel {
		BrowserSidebarViewModel(
			initialAddress: "https://navigator.zip",
			actions: actions
		)
	}

	private func rowTitlesInVisualOrder(
		in sidebar: BrowserSidebarView,
		pageIndex: Int? = nil
	) throws -> [String] {
		try tabRows(in: sidebar, pageIndex: pageIndex)
			.sorted {
				sidebar.convert($0.bounds, from: $0).minY > sidebar.convert($1.bounds, from: $1).minY
			}
			.compactMap { row in
				row.recursiveSubviews
					.compactMap { $0 as? BrowserSidebarLabel }
					.first?.stringValue
			}
	}

	private func tabRows(
		in sidebar: BrowserSidebarView,
		pageIndex: Int? = nil,
		file: StaticString = #filePath,
		line: UInt = #line
	) throws -> [BrowserSidebarTabRow] {
		try spacePageItemView(
			in: sidebar,
			pageIndex: pageIndex,
			file: file,
			line: line
		)
		.recursiveSubviews
		.compactMap { $0 as? BrowserSidebarTabRow }
	}

	private func spacePageItemView(
		in sidebar: BrowserSidebarView,
		pageIndex: Int? = nil,
		file: StaticString = #filePath,
		line: UInt = #line
	) throws -> NSView {
		let collectionView = try spacePagesCollectionView(
			in: sidebar,
			file: file,
			line: line
		)
		let resolvedPageIndex = pageIndex ?? 0
		let indexPath = IndexPath(item: resolvedPageIndex, section: 0)
		sidebar.layoutSubtreeIfNeeded()
		collectionView.scrollToItems(at: Set([indexPath]), scrollPosition: .nearestHorizontalEdge)
		collectionView.layoutSubtreeIfNeeded()
		sidebar.layoutSubtreeIfNeeded()
		return try XCTUnwrap(
			collectionView.item(at: indexPath)?.view,
			file: file,
			line: line
		)
	}

	private func reorderableListView(
		in sidebar: BrowserSidebarView,
		pageIndex: Int? = nil,
		file: StaticString = #filePath,
		line: UInt = #line
	) throws -> ReorderableListView<BrowserTabViewModel, BrowserTabID> {
		try XCTUnwrap(
			try spacePageItemView(
				in: sidebar,
				pageIndex: pageIndex,
				file: file,
				line: line
			).recursiveSubviews.first {
				$0 is ReorderableListView<BrowserTabViewModel, BrowserTabID>
			} as? ReorderableListView<BrowserTabViewModel, BrowserTabID>,
			file: file,
			line: line
		)
	}

	private func pinnedTabsView(
		in sidebar: BrowserSidebarView,
		file: StaticString = #filePath,
		line: UInt = #line
	) throws -> BrowserSidebarPinnedTabsView {
		try XCTUnwrap(
			sidebar.recursiveSubviews.first {
				$0 is BrowserSidebarPinnedTabsView
			} as? BrowserSidebarPinnedTabsView,
			file: file,
			line: line
		)
	}

	private func pinnedTabsCollectionView(
		in sidebar: BrowserSidebarView,
		file: StaticString = #filePath,
		line: UInt = #line
	) throws -> NSCollectionView {
		try XCTUnwrap(
			sidebar.recursiveSubviews.first {
				guard let collectionView = $0 as? NSCollectionView else { return false }
				return collectionView.identifier?.rawValue == "browserSidebar.pinnedTabsCollection"
			} as? NSCollectionView,
			file: file,
			line: line
		)
	}

	private func spacePagesCollectionView(
		in sidebar: BrowserSidebarView,
		file: StaticString = #filePath,
		line: UInt = #line
	) throws -> NSCollectionView {
		try XCTUnwrap(
			sidebar.recursiveSubviews.first {
				guard let collectionView = $0 as? NSCollectionView else { return false }
				return collectionView.identifier?.rawValue == "browserSidebar.spacePagesCollection"
			} as? NSCollectionView,
			file: file,
			line: line
		)
	}

	private func spacePagesScrollView(
		in sidebar: BrowserSidebarView,
		file: StaticString = #filePath,
		line: UInt = #line
	) throws -> NSScrollView {
		try XCTUnwrap(
			sidebar.recursiveSubviews.first {
				guard let scrollView = $0 as? NSScrollView else { return false }
				guard let documentView = scrollView.documentView as? NSCollectionView else { return false }
				return documentView.identifier?.rawValue == "browserSidebar.spacePagesCollection"
			} as? NSScrollView,
			file: file,
			line: line
		)
	}

	private func pinnedTabItemView(
		in collectionView: NSCollectionView,
		file: StaticString = #filePath,
		line: UInt = #line
	) throws -> NSView {
		try XCTUnwrap(
			collectionView.recursiveSubviews.first { view in
				view.subviews.contains { $0 is BrowserTabFaviconView } || view.subviews.contains {
					($0 as? NSTextField)?.stringValue.isEmpty == false
				}
			},
			file: file,
			line: line
		)
	}

	private func pinnedTileView(
		in collectionView: NSCollectionView,
		file: StaticString = #filePath,
		line: UInt = #line
	) throws -> NSView {
		try XCTUnwrap(
			collectionView.recursiveSubviews.first { view in
				view.layer?.cornerRadius == 6
					&& view.subviews.contains { $0 is BrowserTabFaviconView }
			},
			file: file,
			line: line
		)
	}

	private func pinnedFaviconView(
		in collectionView: NSCollectionView,
		at index: Int,
		file: StaticString = #filePath,
		line: UInt = #line
	) throws -> BrowserTabFaviconView {
		let item = try XCTUnwrap(
			collectionView.item(at: IndexPath(item: index, section: 0)),
			file: file,
			line: line
		)
		return try XCTUnwrap(
			item.view.recursiveSubviews.first { $0 is BrowserTabFaviconView } as? BrowserTabFaviconView,
			file: file,
			line: line
		)
	}

	private func pinnedFallbackLabels(in collectionView: NSCollectionView) -> [String] {
		collectionView.recursiveSubviews
			.compactMap { $0 as? NSTextField }
			.filter { !$0.isHidden }
			.map(\.stringValue)
			.filter { !$0.isEmpty }
			.sorted()
	}

	private func sampleImageData() -> Data? {
		let image = NSImage(size: NSSize(width: 16, height: 16))
		image.lockFocus()
		NSColor.systemBlue.setFill()
		NSBezierPath(rect: NSRect(x: 0, y: 0, width: 16, height: 16)).fill()
		image.unlockFocus()
		return image.tiffRepresentation
	}

	private func addressField(
		in sidebar: BrowserSidebarView,
		file: StaticString = #filePath,
		line: UInt = #line
	) throws -> NSTextField {
		try XCTUnwrap(
			sidebar.recursiveSubviews
				.compactMap { $0 as? NSTextField }
				.first { $0.delegate === sidebar },
			file: file,
			line: line
		)
	}

	private func windowControlButton(
		in sidebar: BrowserSidebarView,
		identifier: String,
		file: StaticString = #filePath,
		line: UInt = #line
	) throws -> BrowserSidebarWindowControlButton {
		try XCTUnwrap(
			sidebar.recursiveSubviews
				.compactMap { $0 as? BrowserSidebarWindowControlButton }
				.first { $0.identifier?.rawValue == identifier },
			file: file,
			line: line
		)
	}

	private func button(
		in sidebar: BrowserSidebarView,
		identifier: String,
		file: StaticString = #filePath,
		line: UInt = #line
	) throws -> NSButton {
		try XCTUnwrap(
			sidebar.recursiveSubviews
				.compactMap { $0 as? NSButton }
				.first { $0.identifier?.rawValue == identifier },
			file: file,
			line: line
		)
	}

	private func popupButton(
		in sidebar: BrowserSidebarView,
		identifier: String,
		file: StaticString = #filePath,
		line: UInt = #line
	) throws -> NSPopUpButton {
		try XCTUnwrap(
			sidebar.recursiveSubviews
				.compactMap { $0 as? NSPopUpButton }
				.first { $0.identifier?.rawValue == identifier },
			file: file,
			line: line
		)
	}

	private func imageView(
		in sidebar: BrowserSidebarView,
		identifier: String,
		file: StaticString = #filePath,
		line: UInt = #line
	) throws -> NSImageView {
		try XCTUnwrap(
			sidebar.recursiveSubviews
				.compactMap { $0 as? NSImageView }
				.first { $0.identifier?.rawValue == identifier },
			file: file,
			line: line
		)
	}

	private func label(
		in sidebar: BrowserSidebarView,
		identifier: String,
		file: StaticString = #filePath,
		line: UInt = #line
	) throws -> NSTextField {
		try XCTUnwrap(
			sidebar.recursiveSubviews
				.compactMap { $0 as? NSTextField }
				.first { $0.identifier?.rawValue == identifier },
			file: file,
			line: line
		)
	}

	private func row(
		titled title: String,
		in rows: [BrowserSidebarTabRow]
	) -> BrowserSidebarTabRow? {
		rows.first { row in
			row.recursiveSubviews
				.compactMap { ($0 as? BrowserSidebarLabel)?.stringValue }
				.contains(title)
		}
	}

	private func invokeAction(
		_ selectorName: String,
		on object: NSObject,
		with argument: Any? = nil,
		file: StaticString = #filePath,
		line: UInt = #line
	) {
		let selector = NSSelectorFromString(selectorName)
		XCTAssertTrue(object.responds(to: selector), file: file, line: line)
		if let argument {
			object.perform(selector, with: argument)
		}
		else {
			object.perform(selector)
		}
	}

	private func assertColor(
		_ actualCGColor: CGColor?,
		matches expectedColor: NSColor,
		file: StaticString,
		line: UInt
	) {
		guard
			let actualColor = NSColor(cgColor: actualCGColor ?? NSColor.clear.cgColor)?
			.usingColorSpace(.deviceRGB),
			let expectedRGB = expectedColor.usingColorSpace(.deviceRGB)
		else {
			XCTFail("Unable to resolve colors for comparison", file: file, line: line)
			return
		}

		XCTAssertEqual(actualColor.redComponent, expectedRGB.redComponent, accuracy: 0.001, file: file, line: line)
		XCTAssertEqual(actualColor.greenComponent, expectedRGB.greenComponent, accuracy: 0.001, file: file, line: line)
		XCTAssertEqual(actualColor.blueComponent, expectedRGB.blueComponent, accuracy: 0.001, file: file, line: line)
		XCTAssertEqual(actualColor.alphaComponent, expectedRGB.alphaComponent, accuracy: 0.001, file: file, line: line)
	}

	private func activeTrailingConstraints(
		for label: BrowserSidebarLabel,
		in container: NSView
	) -> [NSLayoutConstraint] {
		container.constraints.filter { constraint in
			constraint.isActive &&
				constraint.firstItem as? BrowserSidebarLabel === label &&
				constraint.firstAttribute == .trailing
		}
	}

	func testSidebarRowClickSelectsTabWithoutHandle() throws {
		let viewModel = makeViewModel()
		let firstTabID = try XCTUnwrap(viewModel.selectedTabID)
		viewModel.addTab()
		let secondTabID = try XCTUnwrap(viewModel.selectedTabID)
		viewModel.tabs[0].updatePageTitle("First")
		viewModel.tabs[1].updatePageTitle("Second")

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		let window = NSWindow(
			contentRect: sidebar.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = sidebar
		sidebar.layoutSubtreeIfNeeded()

		let rows = try tabRows(in: sidebar)
		let firstRow = try XCTUnwrap(
			row(titled: "First", in: rows)
		)
		let clickEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseUp,
				location: firstRow.convert(NSPoint(x: 20, y: 20), to: nil as NSView?),
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 0,
				clickCount: 1,
				pressure: 1
			)
		)
		let mouseDownEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDown,
				location: firstRow.convert(NSPoint(x: 20, y: 20), to: nil as NSView?),
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 0,
				clickCount: 1,
				pressure: 1
			)
		)

		firstRow.mouseDown(with: mouseDownEvent)
		firstRow.mouseUp(with: clickEvent)

		XCTAssertEqual(viewModel.selectedTabID, firstTabID)
		XCTAssertNotEqual(viewModel.selectedTabID, secondTabID)
	}

	func testSidebarRowTrailingWhitespaceClickSelectsTabWhenCloseButtonIsVisible() throws {
		let viewModel = makeViewModel()
		let firstTabID = try XCTUnwrap(viewModel.selectedTabID)
		viewModel.addTab()
		let secondTabID = try XCTUnwrap(viewModel.selectedTabID)
		viewModel.tabs[0].updatePageTitle("First")
		viewModel.tabs[1].updatePageTitle("Second")

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		let window = NSWindow(
			contentRect: sidebar.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = sidebar
		sidebar.layoutSubtreeIfNeeded()

		let rows = sidebar.recursiveSubviews.compactMap { $0 as? BrowserSidebarTabRow }
		let firstRow = try XCTUnwrap(row(titled: "First", in: rows))
		let closeButton = try XCTUnwrap(firstRow.recursiveSubviews.compactMap { $0 as? NSButton }.first)
		let actualCloseButtonFrame = firstRow.convert(closeButton.bounds, from: closeButton)
		let clickPointInRow = NSPoint(
			x: actualCloseButtonFrame.minX - 4,
			y: actualCloseButtonFrame.midY
		)
		let clickLocationInWindow = firstRow.convert(clickPointInRow, to: nil as NSView?)

		firstRow.syncHoverStateForCurrentPointerLocation(mouseLocationInWindow: clickLocationInWindow)

		XCTAssertFalse(closeButton.isHidden)

		let pointInSidebar = sidebar.convert(clickPointInRow, from: firstRow)
		let hitView = try XCTUnwrap(sidebar.hitTest(pointInSidebar))
		let eventLocation = sidebar.convert(pointInSidebar, to: nil as NSView?)
		let mouseDownEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDown,
				location: eventLocation,
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 0,
				clickCount: 1,
				pressure: 1
			)
		)
		let mouseUpEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseUp,
				location: eventLocation,
				modifierFlags: [],
				timestamp: 0.1,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 1,
				clickCount: 1,
				pressure: 1
			)
		)

		hitView.mouseDown(with: mouseDownEvent)
		hitView.mouseUp(with: mouseUpEvent)

		XCTAssertEqual(viewModel.selectedTabID, firstTabID)
		XCTAssertNotEqual(viewModel.selectedTabID, secondTabID)
	}

	func testSidebarRowReleaseOnDifferentRowDoesNotSelectDestination() throws {
		let viewModel = makeViewModel()
		viewModel.addTab()
		let secondTabID = try XCTUnwrap(viewModel.selectedTabID)
		viewModel.tabs[0].updatePageTitle("First")
		viewModel.tabs[1].updatePageTitle("Second")

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		let window = NSWindow(
			contentRect: sidebar.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = sidebar
		sidebar.layoutSubtreeIfNeeded()

		let rows = sidebar.recursiveSubviews.compactMap { $0 as? BrowserSidebarTabRow }
		let firstRow = try XCTUnwrap(
			row(titled: "First", in: rows)
		)
		let secondRow = try XCTUnwrap(
			row(titled: "Second", in: rows)
		)
		let mouseDownEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDown,
				location: firstRow.convert(NSPoint(x: 20, y: 20), to: nil as NSView?),
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 0,
				clickCount: 1,
				pressure: 1
			)
		)
		let mouseUpEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseUp,
				location: secondRow.convert(NSPoint(x: 20, y: 20), to: nil as NSView?),
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 1,
				clickCount: 1,
				pressure: 1
			)
		)

		firstRow.mouseDown(with: mouseDownEvent)
		secondRow.mouseUp(with: mouseUpEvent)

		XCTAssertEqual(viewModel.selectedTabID, secondTabID)
	}

	func testSidebarRowClickStillSelectsTabAfterSidebarIsShownAgain() throws {
		let viewModel = makeViewModel()
		viewModel.addTab()
		let firstTabID = viewModel.tabs[0].id
		viewModel.tabs[0].updatePageTitle("First")
		viewModel.tabs[1].updatePageTitle("Second")

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(isPresented: true),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		let window = NSWindow(
			contentRect: sidebar.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = sidebar
		sidebar.layoutSubtreeIfNeeded()

		sidebar.setPresented(false, animated: false)
		sidebar.setPresented(true, animated: false)
		sidebar.layoutSubtreeIfNeeded()

		let rows = sidebar.recursiveSubviews.compactMap { $0 as? BrowserSidebarTabRow }
		let firstRow = try XCTUnwrap(row(titled: "First", in: rows))
		let pointInSidebar = sidebar.convert(NSPoint(x: 20, y: 20), from: firstRow)
		let hitView = try XCTUnwrap(sidebar.hitTest(pointInSidebar))
		let eventLocation = sidebar.convert(pointInSidebar, to: nil as NSView?)
		let mouseDownEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDown,
				location: eventLocation,
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 0,
				clickCount: 1,
				pressure: 1
			)
		)
		let mouseUpEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseUp,
				location: eventLocation,
				modifierFlags: [],
				timestamp: 0.1,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 1,
				clickCount: 1,
				pressure: 1
			)
		)

		hitView.mouseDown(with: mouseDownEvent)
		hitView.mouseUp(with: mouseUpEvent)

		XCTAssertEqual(viewModel.selectedTabID, firstTabID)
	}

	func testSidebarSmallPointerMotionStaysASelectionClick() throws {
		let viewModel = makeViewModel()
		let firstTabID = try XCTUnwrap(viewModel.selectedTabID)
		viewModel.addTab()
		let secondTabID = try XCTUnwrap(viewModel.selectedTabID)
		viewModel.tabs[0].updatePageTitle("First")
		viewModel.tabs[1].updatePageTitle("Second")

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		let window = NSWindow(
			contentRect: sidebar.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = sidebar
		sidebar.layoutSubtreeIfNeeded()

		let rows = sidebar.recursiveSubviews.compactMap { $0 as? BrowserSidebarTabRow }
		let reorderListView = try reorderableListView(in: sidebar)
		let firstRow = try XCTUnwrap(row(titled: "First", in: rows))
		let pressLocation = NSPoint(x: 20, y: 20)
		let slightDragLocation = NSPoint(x: 22, y: 21)
		let mouseDownEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDown,
				location: firstRow.convert(pressLocation, to: nil as NSView?),
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 0,
				clickCount: 1,
				pressure: 1
			)
		)
		let mouseDraggedEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDragged,
				location: firstRow.convert(slightDragLocation, to: nil as NSView?),
				modifierFlags: [],
				timestamp: 0.05,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 1,
				clickCount: 1,
				pressure: 1
			)
		)
		let mouseUpEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseUp,
				location: firstRow.convert(slightDragLocation, to: nil as NSView?),
				modifierFlags: [],
				timestamp: 0.1,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 2,
				clickCount: 1,
				pressure: 1
			)
		)

		firstRow.mouseDown(with: mouseDownEvent)
		XCTAssertTrue(reorderListView.hasPendingPressForTesting())

		firstRow.mouseDragged(with: mouseDraggedEvent)

		XCTAssertFalse(reorderListView.isReordering())
		XCTAssertTrue(reorderListView.hasPendingPressForTesting())

		firstRow.mouseUp(with: mouseUpEvent)

		XCTAssertFalse(reorderListView.isReordering())
		XCTAssertFalse(reorderListView.hasPendingPressForTesting())
		XCTAssertEqual(viewModel.selectedTabID, firstTabID)
		XCTAssertNotEqual(viewModel.selectedTabID, secondTabID)
		XCTAssertEqual(viewModel.tabs.map(\.displayTitle), ["First", "Second"])
	}

	func testSidebarRowDragStartsReorderOnListHost() throws {
		let viewModel = makeViewModel()
		viewModel.addTab()
		viewModel.tabs[0].updatePageTitle("First")
		viewModel.tabs[1].updatePageTitle("Second")

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		let window = NSWindow(
			contentRect: sidebar.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = sidebar
		sidebar.layoutSubtreeIfNeeded()

		let rows = sidebar.recursiveSubviews.compactMap { $0 as? BrowserSidebarTabRow }
		let reorderListView = try reorderableListView(in: sidebar)
		let firstRow = try XCTUnwrap(
			row(titled: "First", in: rows)
		)
		let secondRow = try XCTUnwrap(
			row(titled: "Second", in: rows)
		)
		XCTAssertTrue(firstRow.reorderableListEventForwardingView != nil)
		let mouseDownEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDown,
				location: firstRow.convert(NSPoint(x: 20, y: 20), to: nil as NSView?),
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 0,
				clickCount: 1,
				pressure: 1
			)
		)
		_ = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseUp,
				location: secondRow.convert(
					NSPoint(x: 20, y: secondRow.bounds.midY + 10),
					to: nil as NSView?
				),
				modifierFlags: [],
				timestamp: 0.5,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 1,
				clickCount: 1,
				pressure: 1
			)
		)
		let mouseDraggedEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDragged,
				location: secondRow.convert(
					NSPoint(x: 20, y: secondRow.bounds.midY + 10),
					to: nil as NSView?
				),
				modifierFlags: [],
				timestamp: 0.1,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 1,
				clickCount: 1,
				pressure: 1
			)
		)

		firstRow.mouseDown(with: mouseDownEvent)
		XCTAssertTrue(reorderListView.hasPendingPressForTesting())
		firstRow.mouseDragged(with: mouseDraggedEvent)
		XCTAssertTrue(reorderListView.isReordering())
		XCTAssertEqual(reorderListView.currentVisualOrder(), [1, 0])
		XCTAssertEqual(try rowTitlesInVisualOrder(in: sidebar), ["First", "Second"])
		reorderListView.endDragForTesting(cancelled: false)

		XCTAssertEqual(viewModel.tabs.map(\.displayTitle), ["Second", "First"])
	}

	func testSidebarRowDragStillReordersAfterSidebarIsShownAgain() throws {
		let viewModel = makeViewModel()
		viewModel.addTab()
		viewModel.tabs[0].updatePageTitle("First")
		viewModel.tabs[1].updatePageTitle("Second")

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(isPresented: true),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		let window = NSWindow(
			contentRect: sidebar.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = sidebar
		sidebar.layoutSubtreeIfNeeded()

		sidebar.setPresented(false, animated: false)
		sidebar.setPresented(true, animated: false)
		sidebar.layoutSubtreeIfNeeded()

		let rows = try tabRows(in: sidebar)
		let reorderListView = try reorderableListView(in: sidebar)
		let firstRow = try XCTUnwrap(row(titled: "First", in: rows))
		let secondRow = try XCTUnwrap(row(titled: "Second", in: rows))
		let pointInSidebar = sidebar.convert(NSPoint(x: 20, y: 20), from: firstRow)
		let hitView = try XCTUnwrap(sidebar.hitTest(pointInSidebar))
		let mouseDownEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDown,
				location: sidebar.convert(pointInSidebar, to: nil as NSView?),
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 0,
				clickCount: 1,
				pressure: 1
			)
		)
		let mouseDraggedEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDragged,
				location: secondRow.convert(
					NSPoint(x: 20, y: secondRow.bounds.midY + 10),
					to: nil as NSView?
				),
				modifierFlags: [],
				timestamp: 0.1,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 1,
				clickCount: 1,
				pressure: 1
			)
		)
		_ = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseUp,
				location: secondRow.convert(
					NSPoint(x: 20, y: secondRow.bounds.midY + 10),
					to: nil as NSView?
				),
				modifierFlags: [],
				timestamp: 0.2,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 2,
				clickCount: 1,
				pressure: 1
			)
		)

		hitView.mouseDown(with: mouseDownEvent)
		XCTAssertTrue(reorderListView.hasPendingPressForTesting())
		hitView.mouseDragged(with: mouseDraggedEvent)
		XCTAssertTrue(reorderListView.isReordering())
		XCTAssertEqual(reorderListView.currentVisualOrder(), [1, 0])
		XCTAssertEqual(try rowTitlesInVisualOrder(in: sidebar), ["First", "Second"])
		reorderListView.endDragForTesting(cancelled: false)

		XCTAssertEqual(viewModel.tabs.map(\.displayTitle), ["Second", "First"])
	}

	func testSidebarKeepsRowContentCorrectWhenTabsReorder() {
		let viewModel = makeViewModel()
		viewModel.addTab()
		viewModel.tabs[0].updatePageTitle("First")
		viewModel.tabs[1].updatePageTitle("Second")

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		let window = NSWindow(
			contentRect: sidebar.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = sidebar
		sidebar.layoutSubtreeIfNeeded()

		let initialRows = sidebar.recursiveSubviews.compactMap { $0 as? BrowserSidebarTabRow }
		XCTAssertNotNil(row(titled: "First", in: initialRows))
		XCTAssertNotNil(row(titled: "Second", in: initialRows))

		viewModel.moveTabs(from: IndexSet(integer: 0), to: 2)
		sidebar.refreshAppearance()
		sidebar.layoutSubtreeIfNeeded()

		let reorderedRows = sidebar.recursiveSubviews.compactMap { $0 as? BrowserSidebarTabRow }
		XCTAssertNotNil(row(titled: "First", in: reorderedRows))
		XCTAssertNotNil(row(titled: "Second", in: reorderedRows))
	}

	func testSidebarReusesVisibleRowViewAcrossStableTabRefreshes() throws {
		let viewModel = makeViewModel()
		viewModel.tabs[0].updatePageTitle("First")

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		let window = NSWindow(
			contentRect: sidebar.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = sidebar
		sidebar.layoutSubtreeIfNeeded()

		let initialRows = sidebar.recursiveSubviews.compactMap { $0 as? BrowserSidebarTabRow }
		let initialRow = try XCTUnwrap(row(titled: "First", in: initialRows))

		viewModel.tabs[0].updatePageTitle("Updated")
		sidebar.refreshAppearance()
		sidebar.layoutSubtreeIfNeeded()

		let refreshedRows = sidebar.recursiveSubviews.compactMap { $0 as? BrowserSidebarTabRow }
		let refreshedRow = try XCTUnwrap(row(titled: "Updated", in: refreshedRows))

		XCTAssertTrue(initialRow === refreshedRow)
	}

	func testSidebarIncrementallyAppendsRowsWithoutRebuildingExistingVisibleRows() throws {
		let viewModel = makeViewModel()
		viewModel.tabs[0].updatePageTitle("First")

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		let window = NSWindow(
			contentRect: sidebar.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = sidebar
		sidebar.layoutSubtreeIfNeeded()

		let initialRow = try XCTUnwrap(
			row(
				titled: "First",
				in: sidebar.recursiveSubviews.compactMap { $0 as? BrowserSidebarTabRow }
			)
		)

		viewModel.appendTabs(with: ["https://second.example"])
		viewModel.tabs[1].updatePageTitle("Second")
		sidebar.refreshAppearance()
		sidebar.layoutSubtreeIfNeeded()

		let refreshedRows = sidebar.recursiveSubviews.compactMap { $0 as? BrowserSidebarTabRow }
		let refreshedFirstRow = try XCTUnwrap(row(titled: "First", in: refreshedRows))

		XCTAssertTrue(initialRow === refreshedFirstRow)
		XCTAssertNotNil(row(titled: "Second", in: refreshedRows))
	}

	func testSidebarListBuilderFallsBackToPlainViewsWithoutOwner() {
		let fallbackView = BrowserSidebarView.buildTabContentViewForTesting(
			for: BrowserTabViewModel(initialURL: "https://fallback.example"),
			owner: nil
		)

		XCTAssertTrue(type(of: fallbackView) == NSView.self)
		XCTAssertFalse(fallbackView is BrowserSidebarTabRow)
	}

	func testSidebarPrunesRemovedTabRowCacheEntries() {
		let viewModel = makeViewModel()
		viewModel.addTab()
		viewModel.tabs[0].updatePageTitle("First")
		viewModel.tabs[1].updatePageTitle("Second")

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		let window = NSWindow(
			contentRect: sidebar.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = sidebar
		sidebar.layoutSubtreeIfNeeded()

		let removedTabID = viewModel.tabs[0].id
		XCTAssertTrue(sidebar.hasCachedTabRowEntryForTesting(removedTabID))
		XCTAssertEqual(sidebar.cachedTabRowEntryCountForTesting(), 2)

		viewModel.closeTab(id: removedTabID)
		viewModel.addTab()
		viewModel.tabs[1].updatePageTitle("Third")
		sidebar.refreshAppearance()
		sidebar.layoutSubtreeIfNeeded()

		let remainingRows = sidebar.recursiveSubviews.compactMap { $0 as? BrowserSidebarTabRow }
		XCTAssertNil(row(titled: "First", in: remainingRows))
		XCTAssertNotNil(row(titled: "Third", in: remainingRows))
		XCTAssertFalse(sidebar.hasCachedTabRowEntryForTesting(removedTabID))
		XCTAssertEqual(sidebar.cachedTabRowEntryCountForTesting(), 2)
	}

	func testSidebarPrunesReleasedWeakCacheEntriesDuringRefresh() {
		let viewModel = makeViewModel()
		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		sidebar.layoutSubtreeIfNeeded()

		let staleTabID = BrowserTabID()
		sidebar.insertReleasedTabRowCacheEntryForTesting(staleTabID)
		XCTAssertTrue(sidebar.hasCachedTabRowEntryForTesting(staleTabID))
		XCTAssertEqual(sidebar.cachedTabRowEntryCountForTesting(), 2)

		sidebar.refreshAppearance()

		XCTAssertFalse(sidebar.hasCachedTabRowEntryForTesting(staleTabID))
		XCTAssertEqual(sidebar.cachedTabRowEntryCountForTesting(), 1)
	}

	func testSidebarToolbarActionsAndCloseButtonDriveViewModel() throws {
		var goBackTabIDs = [BrowserTabID]()
		var goForwardTabIDs = [BrowserTabID]()
		var reloadTabIDs = [BrowserTabID]()
		let viewModel = makeViewModel(
			actions: BrowserSidebarActions(
				onGoBack: { goBackTabIDs.append($0) },
				onGoForward: { goForwardTabIDs.append($0) },
				onReload: { reloadTabIDs.append($0) },
				onSubmitAddress: { _, _ in },
				navigationState: {
					_ in BrowserSidebarNavigationState(
						canGoBack: true,
						canGoForward: true,
						isLoading: false
					)
				}
			)
		)
		viewModel.tabs[0].updatePageTitle("First")
		viewModel.addTab()
		viewModel.tabs[1].updatePageTitle("Second")

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		let window = NSWindow(
			contentRect: sidebar.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = sidebar
		sidebar.layoutSubtreeIfNeeded()

		let selectedTabID = try XCTUnwrap(viewModel.selectedTabID)

		invokeAction("didTapBack", on: sidebar)
		invokeAction("didTapForward", on: sidebar)
		invokeAction("didTapReload", on: sidebar)
		XCTAssertEqual(goBackTabIDs, [selectedTabID])
		XCTAssertEqual(goForwardTabIDs, [selectedTabID])
		XCTAssertEqual(reloadTabIDs, [selectedTabID])
		XCTAssertEqual(viewModel.tabs.count, 2)

		let closeButton = try XCTUnwrap(
			row(
				titled: "First",
				in: sidebar.recursiveSubviews.compactMap { $0 as? BrowserSidebarTabRow }
			)?
				.recursiveSubviews
				.compactMap { $0 as? NSButton }
				.first
		)
		closeButton.performClick(nil)

		XCTAssertEqual(viewModel.tabs.count, 1)
		XCTAssertFalse(viewModel.tabs.contains { $0.pageTitle == "First" })
	}

	func testSidebarAddressFieldDelegateCommandsUpdateAndSubmitInput() throws {
		var submissions = [(BrowserTabID, String)]()
		let viewModel = makeViewModel(
			actions: BrowserSidebarActions(
				onGoBack: { _ in },
				onGoForward: { _ in },
				onReload: { _ in },
				onSubmitAddress: { submissions.append(($0, $1)) },
				navigationState: { _ in .idle }
			)
		)
		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		let window = NSWindow(
			contentRect: sidebar.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = sidebar
		sidebar.layoutSubtreeIfNeeded()

		let addressField = try addressField(in: sidebar)
		let textView = NSTextView()
		addressField.stringValue = "example.com"
		sidebar.controlTextDidChange(
			Notification(name: NSControl.textDidChangeNotification, object: addressField)
		)

		XCTAssertEqual(viewModel.addressText, "example.com")
		XCTAssertFalse(
			sidebar.control(
				addressField,
				textView: textView,
				doCommandBy: #selector(NSResponder.cancelOperation(_:))
			)
		)
		XCTAssertTrue(
			sidebar.control(
				addressField,
				textView: textView,
				doCommandBy: #selector(NSResponder.selectAll(_:))
			)
		)
		XCTAssertTrue(
			sidebar.control(
				addressField,
				textView: textView,
				doCommandBy: #selector(NSResponder.insertNewline(_:))
			)
		)
		XCTAssertFalse(
			sidebar.control(
				addressField,
				textView: textView,
				doCommandBy: #selector(NSResponder.moveDown(_:))
			)
		)

		let selectedTabID = try XCTUnwrap(viewModel.selectedTabID)
		XCTAssertEqual(submissions.map(\.0), [selectedTabID])
		XCTAssertEqual(submissions.map(\.1), ["https://example.com"])
	}

	func testSidebarMaterializesStoredTabsForInactiveSpacePages() throws {
		let viewModel = makeViewModel()
		viewModel.configureSpacePages(
			[
				BrowserSidebarSpacePage(id: "space-1", title: "Space 1"),
				BrowserSidebarSpacePage(id: "space-2", title: "Space 2"),
			],
			selectedPageID: "space-1",
			pageContents: [
				BrowserSidebarSpacePageContent(
					pageID: "space-2",
					tabs: [
						StoredBrowserTab(
							id: UUID(),
							objectVersion: 1,
							orderKey: "00000000",
							spaceID: "space-2",
							url: "https://space-two.example",
							title: "Space Two"
						),
					],
					selectedTabID: nil
				),
			],
			onSelectSpacePage: nil
		)

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		sidebar.layoutSubtreeIfNeeded()

		viewModel.selectSpacePage(id: "space-2")
		sidebar.layoutSubtreeIfNeeded()

		let secondPageRows = try tabRows(in: sidebar, pageIndex: 1)

		XCTAssertEqual(secondPageRows.count, 1)
		XCTAssertEqual(try rowTitlesInVisualOrder(in: sidebar, pageIndex: 1), ["Space Two"])
	}

	func testSidebarNativeHorizontalScrollSelectsNearestSpacePage() throws {
		let viewModel = makeViewModel()
		viewModel.configureSpacePages(
			[
				BrowserSidebarSpacePage(id: "space-1", title: "Space 1"),
				BrowserSidebarSpacePage(id: "space-2", title: "Space 2"),
			],
			selectedPageID: "space-1",
			pageContents: [
				BrowserSidebarSpacePageContent(
					pageID: "space-2",
					tabs: [
						StoredBrowserTab(
							id: UUID(),
							objectVersion: 1,
							orderKey: "00000000",
							spaceID: "space-2",
							url: "https://space-two.example",
							title: "Space Two"
						),
					],
					selectedTabID: nil
				),
			],
			onSelectSpacePage: nil
		)

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		sidebar.layoutSubtreeIfNeeded()

		let scrollView = try spacePagesScrollView(in: sidebar)
		let pageWidth = scrollView.contentView.bounds.width
		XCTAssertGreaterThan(pageWidth, 0)
		scrollView.contentView.scroll(to: CGPoint(x: pageWidth, y: 0))
		scrollView.reflectScrolledClipView(scrollView.contentView)

		XCTAssertEqual(viewModel.selectedSpacePageID, "space-2")
	}

	func testSidebarAppearanceRefreshAndCustomTextFieldCellOverridesExecute() throws {
		let sidebar = BrowserSidebarView(
			viewModel: makeViewModel(),
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		let window = NSWindow(
			contentRect: sidebar.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = sidebar
		sidebar.layoutSubtreeIfNeeded()

		let addressField = try addressField(in: sidebar)
		let addressFieldContainer = try XCTUnwrap(addressField.superview)
		let cell = try XCTUnwrap(addressField.cell as? NSTextFieldCell)
		let bounds = CGRect(x: 0, y: 0, width: 280, height: 24)
		let expectedRect = BrowserSidebarAddressFieldLayout.displayRect(
			forBounds: bounds,
			font: addressField.font,
			verticalInset: 1,
			verticalOffset: 1.5,
			horizontalInset: 10
		)

		sidebar.viewDidChangeEffectiveAppearance()

		XCTAssertEqual(cell.drawingRect(forBounds: bounds), expectedRect)
		XCTAssertEqual(cell.titleRect(forBounds: bounds), expectedRect)
		cell.edit(
			withFrame: bounds,
			in: addressField,
			editor: NSTextView(),
			delegate: nil,
			event: nil
		)
		cell.select(
			withFrame: bounds,
			in: addressField,
			editor: NSTextView(),
			delegate: nil,
			start: 0,
			length: 0
		)

		XCTAssertNotNil(addressFieldContainer.layer?.backgroundColor)
		XCTAssertNotNil(addressField.textColor)
	}

	func testSidebarDefersTabListRefreshUntilDragRelease() throws {
		let viewModel = makeViewModel()
		viewModel.addTab()
		viewModel.tabs[0].updatePageTitle("First")
		viewModel.tabs[1].updatePageTitle("Second")

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		let window = NSWindow(
			contentRect: sidebar.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = sidebar
		sidebar.layoutSubtreeIfNeeded()

		let reorderListView = try reorderableListView(in: sidebar)

		XCTAssertEqual(try rowTitlesInVisualOrder(in: sidebar), ["First", "Second"])

		reorderListView.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)

		XCTAssertTrue(reorderListView.isReordering())
		XCTAssertTrue(reorderListView.hasTransientReorderState)

		viewModel.moveTabs(from: IndexSet(integer: 0), to: 2)
		sidebar.refreshAppearance()
		sidebar.layoutSubtreeIfNeeded()

		XCTAssertEqual(try rowTitlesInVisualOrder(in: sidebar), ["First", "Second"])

		reorderListView.endDragForTesting(cancelled: true)
		reorderListView.flushPendingDropResetForTesting()
		sidebar.layoutSubtreeIfNeeded()

		XCTAssertFalse(reorderListView.hasTransientReorderState)
		XCTAssertEqual(try rowTitlesInVisualOrder(in: sidebar), ["Second", "First"])
	}

	func testSidebarEscapeKeyCancelsDragAndReturnsRowToOriginalPosition() throws {
		let viewModel = makeViewModel()
		viewModel.addTab()
		viewModel.tabs[0].updatePageTitle("First")
		viewModel.tabs[1].updatePageTitle("Second")

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		let window = NSWindow(
			contentRect: sidebar.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = sidebar
		sidebar.layoutSubtreeIfNeeded()

		let reorderListView = try reorderableListView(in: sidebar)
		let initialFrame = try XCTUnwrap(
			reorderListView.rowFrameForTesting(modelIndex: 0)
		)

		reorderListView.beginDragForTesting(
			sourceIndex: 0,
			locationInContent: NSPoint(x: 20, y: 20)
		)
		reorderListView.updateDragForTesting(
			locationInContent: NSPoint(x: 220, y: 100)
		)

		let escapeEvent = try XCTUnwrap(
			NSEvent.keyEvent(
				with: .keyDown,
				location: .zero,
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				characters: "\u{1b}",
				charactersIgnoringModifiers: "\u{1b}",
				isARepeat: false,
				keyCode: 53
			)
		)

		XCTAssertTrue(reorderListView.isReordering())
		XCTAssertEqual(reorderListView.currentVisualOrder(), [1, 0])
		XCTAssertEqual(try rowTitlesInVisualOrder(in: sidebar), ["First", "Second"])
		XCTAssertTrue(window.firstResponder === reorderListView)
		reorderListView.keyDown(with: escapeEvent)

		XCTAssertFalse(reorderListView.isReordering())
		XCTAssertEqual(reorderListView.currentVisualOrder(), [0, 1])
		XCTAssertEqual(viewModel.tabs.map(\.displayTitle), ["First", "Second"])
		XCTAssertEqual(reorderListView.rowFrameForTesting(modelIndex: 0), initialFrame)

		reorderListView.flushPendingDropResetForTesting()

		XCTAssertFalse(reorderListView.hasTransientReorderState)
		XCTAssertEqual(reorderListView.rowFrameForTesting(modelIndex: 0), initialFrame)
	}

	func testSidebarEscapeKeyOnTabRowCancelsDragStartedThroughRowWrapper() throws {
		let viewModel = makeViewModel()
		viewModel.addTab()
		viewModel.tabs[0].updatePageTitle("First")
		viewModel.tabs[1].updatePageTitle("Second")

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		let window = NSWindow(
			contentRect: sidebar.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = sidebar
		sidebar.layoutSubtreeIfNeeded()

		let rows = try tabRows(in: sidebar)
		let reorderListView = try reorderableListView(in: sidebar)
		let firstRow = try XCTUnwrap(
			row(titled: "First", in: rows)
		)
		let secondRow = try XCTUnwrap(
			row(titled: "Second", in: rows)
		)
		let initialFrame = try XCTUnwrap(
			reorderListView.rowFrameForTesting(modelIndex: 0)
		)
		let mouseDownEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDown,
				location: firstRow.convert(NSPoint(x: 20, y: 20), to: nil as NSView?),
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 0,
				clickCount: 1,
				pressure: 1
			)
		)
		let mouseDraggedEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDragged,
				location: secondRow.convert(
					NSPoint(x: 20, y: secondRow.bounds.midY + 10),
					to: nil as NSView?
				),
				modifierFlags: [],
				timestamp: 0.1,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 1,
				clickCount: 1,
				pressure: 1
			)
		)
		let escapeEvent = try XCTUnwrap(
			NSEvent.keyEvent(
				with: .keyDown,
				location: .zero,
				modifierFlags: [],
				timestamp: 0.2,
				windowNumber: window.windowNumber,
				context: nil,
				characters: "\u{1b}",
				charactersIgnoringModifiers: "\u{1b}",
				isARepeat: false,
				keyCode: 53
			)
		)

		firstRow.mouseDown(with: mouseDownEvent)
		XCTAssertTrue(reorderListView.hasPendingPressForTesting())

		firstRow.mouseDragged(with: mouseDraggedEvent)

		XCTAssertTrue(reorderListView.isReordering())
		XCTAssertEqual(reorderListView.currentVisualOrder(), [1, 0])
		XCTAssertEqual(try rowTitlesInVisualOrder(in: sidebar), ["First", "Second"])

		firstRow.keyDown(with: escapeEvent)

		XCTAssertFalse(reorderListView.isReordering())
		XCTAssertEqual(reorderListView.currentVisualOrder(), [0, 1])
		XCTAssertEqual(viewModel.tabs.map(\.displayTitle), ["First", "Second"])
		XCTAssertEqual(reorderListView.rowFrameForTesting(modelIndex: 0), initialFrame)

		reorderListView.flushPendingDropResetForTesting()

		XCTAssertFalse(reorderListView.hasTransientReorderState)
		XCTAssertEqual(reorderListView.rowFrameForTesting(modelIndex: 0), initialFrame)
	}

	func testSidebarEscapeKeyCancelsArmedRowDragBeforeReorderBegins() throws {
		let viewModel = makeViewModel()
		viewModel.addTab()
		viewModel.tabs[0].updatePageTitle("First")
		viewModel.tabs[1].updatePageTitle("Second")

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		let window = NSWindow(
			contentRect: sidebar.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = sidebar
		sidebar.layoutSubtreeIfNeeded()

		let rows = try tabRows(in: sidebar)
		let reorderListView = try reorderableListView(in: sidebar)
		let firstRow = try XCTUnwrap(
			row(titled: "First", in: rows)
		)
		let secondRow = try XCTUnwrap(
			row(titled: "Second", in: rows)
		)
		let mouseDownEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDown,
				location: firstRow.convert(NSPoint(x: 20, y: 20), to: nil as NSView?),
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 0,
				clickCount: 1,
				pressure: 1
			)
		)
		let mouseDraggedEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDragged,
				location: secondRow.convert(
					NSPoint(x: 20, y: secondRow.bounds.midY + 10),
					to: nil as NSView?
				),
				modifierFlags: [],
				timestamp: 0.1,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 1,
				clickCount: 1,
				pressure: 1
			)
		)
		let escapeEvent = try XCTUnwrap(
			NSEvent.keyEvent(
				with: .keyDown,
				location: .zero,
				modifierFlags: [],
				timestamp: 0.05,
				windowNumber: window.windowNumber,
				context: nil,
				characters: "\u{1b}",
				charactersIgnoringModifiers: "\u{1b}",
				isARepeat: false,
				keyCode: 53
			)
		)

		firstRow.mouseDown(with: mouseDownEvent)

		XCTAssertTrue(reorderListView.hasPendingPressForTesting())
		XCTAssertTrue(window.firstResponder === reorderListView)

		window.firstResponder?.keyDown(with: escapeEvent)

		XCTAssertFalse(reorderListView.hasPendingPressForTesting())
		XCTAssertFalse(reorderListView.isReordering())

		firstRow.mouseDragged(with: mouseDraggedEvent)

		XCTAssertFalse(reorderListView.hasPendingPressForTesting())
		XCTAssertFalse(reorderListView.isReordering())
		XCTAssertEqual(reorderListView.currentVisualOrder(), [0, 1])
		XCTAssertEqual(viewModel.tabs.map(\.displayTitle), ["First", "Second"])
	}

	func testSidebarCancelOperationOnTabRowCancelsDragStartedThroughRowWrapper() throws {
		let viewModel = makeViewModel()
		viewModel.addTab()
		viewModel.tabs[0].updatePageTitle("First")
		viewModel.tabs[1].updatePageTitle("Second")

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		let window = NSWindow(
			contentRect: sidebar.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = sidebar
		sidebar.layoutSubtreeIfNeeded()

		let rows = sidebar.recursiveSubviews.compactMap { $0 as? BrowserSidebarTabRow }
		let reorderListView = try reorderableListView(in: sidebar)
		let firstRow = try XCTUnwrap(
			row(titled: "First", in: rows)
		)
		let secondRow = try XCTUnwrap(
			row(titled: "Second", in: rows)
		)
		let initialFrame = try XCTUnwrap(
			reorderListView.rowFrameForTesting(modelIndex: 0)
		)
		let mouseDownEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDown,
				location: firstRow.convert(NSPoint(x: 20, y: 20), to: nil as NSView?),
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 0,
				clickCount: 1,
				pressure: 1
			)
		)
		let mouseDraggedEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDragged,
				location: secondRow.convert(
					NSPoint(x: 20, y: secondRow.bounds.midY + 10),
					to: nil as NSView?
				),
				modifierFlags: [],
				timestamp: 0.1,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 1,
				clickCount: 1,
				pressure: 1
			)
		)

		firstRow.mouseDown(with: mouseDownEvent)
		XCTAssertTrue(reorderListView.hasPendingPressForTesting())

		firstRow.mouseDragged(with: mouseDraggedEvent)

		XCTAssertTrue(reorderListView.isReordering())
		XCTAssertEqual(reorderListView.currentVisualOrder(), [1, 0])
		XCTAssertEqual(try rowTitlesInVisualOrder(in: sidebar), ["First", "Second"])

		firstRow.cancelOperation(nil)

		XCTAssertFalse(reorderListView.isReordering())
		XCTAssertEqual(reorderListView.currentVisualOrder(), [0, 1])
		XCTAssertEqual(viewModel.tabs.map(\.displayTitle), ["First", "Second"])
		XCTAssertEqual(reorderListView.rowFrameForTesting(modelIndex: 0), initialFrame)

		reorderListView.flushPendingDropResetForTesting()

		XCTAssertFalse(reorderListView.hasTransientReorderState)
		XCTAssertEqual(reorderListView.rowFrameForTesting(modelIndex: 0), initialFrame)
	}

	func testSidebarHitTestRoutesFirstRowTitlePressToRowForImmediateReorderDrag() throws {
		let viewModel = makeViewModel()
		viewModel.addTab()
		viewModel.tabs[0].updatePageTitle("First")
		viewModel.tabs[1].updatePageTitle("Second")

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		let window = NSWindow(
			contentRect: sidebar.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = sidebar
		sidebar.layoutSubtreeIfNeeded()

		let rows = sidebar.recursiveSubviews.compactMap { $0 as? BrowserSidebarTabRow }
		let reorderListView = try reorderableListView(in: sidebar)
		let firstRow = try XCTUnwrap(
			row(titled: "First", in: rows)
		)
		let pointInSidebar = sidebar.convert(NSPoint(x: 20, y: 20), from: firstRow)
		let hitView = try XCTUnwrap(sidebar.hitTest(pointInSidebar))
		let eventLocation = sidebar.convert(pointInSidebar, to: nil as NSView?)
		let mouseDownEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDown,
				location: eventLocation,
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 0,
				clickCount: 1,
				pressure: 1
			)
		)
		let mouseUpEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseUp,
				location: eventLocation,
				modifierFlags: [],
				timestamp: 0.5,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 1,
				clickCount: 1,
				pressure: 1
			)
		)
		let mouseDraggedEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDragged,
				location: firstRow.convert(NSPoint(x: 20, y: 100), to: nil as NSView?),
				modifierFlags: [],
				timestamp: 0.1,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 1,
				clickCount: 1,
				pressure: 1
			)
		)

		let hitRow = try XCTUnwrap(hitView as? BrowserSidebarTabRow)
		let hitRowTitle = hitRow.recursiveSubviews
			.compactMap { $0 as? BrowserSidebarLabel }
			.first { $0.stringValue == "First" }

		XCTAssertNotNil(
			hitRowTitle,
			"""
			Expected first row hit target, got \(type(of: hitView))
			pointInSidebar=\(pointInSidebar)
			firstRowFrame=\(firstRow.frame)
			firstRowSuperviewFrame=\(String(describing: firstRow.superview?.frame))
			"""
		)

		hitView.mouseDown(with: mouseDownEvent)
		hitView.mouseDragged(with: mouseDraggedEvent)
		reorderListView.mouseUp(with: mouseUpEvent)
	}

	func testSidebarRowReleaseAfterReorderDoesNotSelectDraggedTab() throws {
		let viewModel = makeViewModel()
		let initiallySelectedTabID = try XCTUnwrap(viewModel.selectedTabID)
		viewModel.addTab()
		let selectedSecondTabID = try XCTUnwrap(viewModel.selectedTabID)
		viewModel.tabs[0].updatePageTitle("First")
		viewModel.tabs[1].updatePageTitle("Second")

		let sidebar = BrowserSidebarView(
			viewModel: viewModel,
			presentation: BrowserSidebarPresentation(),
			width: 320
		)
		sidebar.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
		let window = NSWindow(
			contentRect: sidebar.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = sidebar
		sidebar.layoutSubtreeIfNeeded()

		let rows = sidebar.recursiveSubviews.compactMap { $0 as? BrowserSidebarTabRow }
		let reorderListView = try reorderableListView(in: sidebar)
		let firstRow = try XCTUnwrap(
			row(titled: "First", in: rows)
		)
		let mouseDownEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDown,
				location: firstRow.convert(NSPoint(x: 20, y: 20), to: nil as NSView?),
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 0,
				clickCount: 1,
				pressure: 1
			)
		)
		let mouseDraggedEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseDragged,
				location: firstRow.convert(NSPoint(x: 20, y: 100), to: nil as NSView?),
				modifierFlags: [],
				timestamp: 0.4,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 1,
				clickCount: 1,
				pressure: 1
			)
		)
		let mouseUpEvent = try XCTUnwrap(
			NSEvent.mouseEvent(
				with: .leftMouseUp,
				location: firstRow.convert(NSPoint(x: 20, y: 100), to: nil as NSView?),
				modifierFlags: [],
				timestamp: 0.5,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 2,
				clickCount: 1,
				pressure: 1
			)
		)

		firstRow.mouseDown(with: mouseDownEvent)
		firstRow.mouseDragged(with: mouseDraggedEvent)
		reorderListView.mouseUp(with: mouseUpEvent)

		XCTAssertEqual(initiallySelectedTabID, viewModel.tabs[0].id)
		XCTAssertEqual(viewModel.selectedTabID, selectedSecondTabID)
	}

	private func testValue<T>(named name: String, in object: Any) -> T? {
		Mirror(reflecting: object).children.first { $0.label == name }?.value as? T
	}

	private func waitForFaviconLoadCount(
		_ expectedCount: Int,
		recorder: FaviconLoadRecorder,
		file: StaticString = #filePath,
		line: UInt = #line
	) async throws {
		for _ in 0..<50 {
			if await recorder.loadCount() >= expectedCount {
				return
			}
			try await Task.sleep(for: .milliseconds(10))
		}
		XCTFail("Expected favicon view to start \(expectedCount) load(s)", file: file, line: line)
	}

	private func assertNoCameraControls(
		in sidebar: BrowserSidebarView,
		file: StaticString = #filePath,
		line: UInt = #line
	) {
		let identifiers = [
			"browserSidebar.camera.routingToggle",
			"browserSidebar.camera.previewToggle",
			"browserSidebar.camera.horizontalFlipToggle",
			"browserSidebar.camera.refreshButton",
			"browserSidebar.camera.sourcePopup",
			"browserSidebar.camera.presetPopup",
			"browserSidebar.camera.grainPopup",
			"browserSidebar.camera.activityLabel",
			"browserSidebar.camera.diagnosticsLabel",
			"browserSidebar.camera.previewImageView",
			"browserSidebar.camera.previewPlaceholderLabel",
		].map { NSUserInterfaceItemIdentifier($0) }

		for identifier in identifiers {
			let view = sidebar.recursiveSubviews.first { $0.identifier == identifier }
			XCTAssertNil(view, file: file, line: line)
		}
	}
}

private actor FaviconLoadRecorder {
	private var count = 0

	func recordLoad() {
		count += 1
	}

	func loadCount() -> Int {
		count
	}
}

private actor RequestedURLRecorder {
	private var urls = [URL]()

	func record(_ url: URL) {
		urls.append(url)
	}

	func snapshot() -> [URL] {
		urls
	}
}

private final class BrowserSidebarWindowActionTestWindow: NSWindow {
	var didPerformClose = false
	var didMiniaturize = false
	var didToggleFullScreen = false

	override func performClose(_ sender: Any?) {
		didPerformClose = true
	}

	override func miniaturize(_ sender: Any?) {
		didMiniaturize = true
	}

	override func toggleFullScreen(_ sender: Any?) {
		didToggleFullScreen = true
	}
}

private extension NSView {
	var recursiveSubviews: [NSView] {
		subviews + subviews.flatMap(\.recursiveSubviews)
	}

	var isHiddenOrHasHiddenAncestor: Bool {
		if isHidden {
			return true
		}
		return superview?.isHiddenOrHasHiddenAncestor ?? false
	}
}
