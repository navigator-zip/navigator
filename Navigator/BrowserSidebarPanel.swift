import AppKit
import BrowserSidebar
import Foundation

final class BrowserSidebarPanel: NSView {
	private static let sidebarAnimationDuration: Double = 0.24
	private static let sidebarResizeHandleWidth: CGFloat = 8
	private static let sidebarPanelCornerRadius: CGFloat = 12
	private static let sidebarShadowRadius: CGFloat = 2
	private static let sidebarPanelShadowOpacity: Float = 0.2

	private let sidebarView: BrowserSidebarView
	private let onWidthChange: (CGFloat) -> Void
	private let onCommitWidth: (CGFloat) -> Void
	fileprivate var widthConstraint: NSLayoutConstraint!
	private let resizeHandle = BrowserSidebarResizeHandle()

	@available(*, unavailable)
	override init(frame frameRect: NSRect) {
		fatalError("init(frame:) is not supported")
	}

	init(
		viewModel: BrowserSidebarViewModel,
		presentation: BrowserSidebarPresentation,
		width: CGFloat,
		onWidthChange: @escaping (CGFloat) -> Void,
		onCommitWidth: @escaping (CGFloat) -> Void
	) {
		self.onWidthChange = onWidthChange
		self.onCommitWidth = onCommitWidth
		self.sidebarView = BrowserSidebarView(
			viewModel: viewModel,
			presentation: presentation,
			width: width
		)
		let rootWidth = max(0, width)
		super.init(frame: NSRect(x: 0, y: 0, width: width, height: 720))
		self.widthConstraint = NSLayoutConstraint(
			item: self,
			attribute: .width,
			relatedBy: .equal,
			toItem: nil,
			attribute: .notAnAttribute,
			multiplier: 1,
			constant: rootWidth
		)
		identifier = NSUserInterfaceItemIdentifier("BrowserSidebarPanel")
		wantsLayer = true
		layer?.backgroundColor = NSColor.clear.cgColor
		layer?.cornerRadius = Self.sidebarPanelCornerRadius
		layer?.shadowColor = NSColor.black.cgColor
		layer?.shadowOffset = NSSize.zero
		layer?.shadowRadius = Self.sidebarShadowRadius
		layer?.shadowOpacity = Self.sidebarPanelShadowOpacity
		alphaValue = 1

		setupLayout()
		updateResizeState(rootWidth, animate: false)
	}

	private func setupLayout() {
		sidebarView.wantsLayer = true
		sidebarView.layer?.borderColor = .black
		sidebarView.layer?.borderWidth = 0

		translatesAutoresizingMaskIntoConstraints = false
		sidebarView.translatesAutoresizingMaskIntoConstraints = false
		resizeHandle.translatesAutoresizingMaskIntoConstraints = false
		addSubview(sidebarView)
		addSubview(resizeHandle)

		let padding = CGFloat(0)

		NSLayoutConstraint.activate([
			widthConstraint,
			sidebarView.topAnchor.constraint(equalTo: topAnchor, constant: padding),
			sidebarView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
			sidebarView.trailingAnchor.constraint(equalTo: trailingAnchor),
			sidebarView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding),

			resizeHandle.topAnchor.constraint(equalTo: topAnchor),
			resizeHandle.bottomAnchor.constraint(equalTo: bottomAnchor),
			resizeHandle.widthAnchor.constraint(equalToConstant: Self.sidebarResizeHandleWidth),
			resizeHandle.trailingAnchor.constraint(equalTo: trailingAnchor),
		])

		resizeHandle.onDrag = { [weak self] delta in
			guard let self else { return }
			self.updateWidth(delta, isCommitted: false)
		}
		resizeHandle.onCommit = { [weak self] finalWidth in
			guard let self else { return }
			self.updateWidth(finalWidth, isCommitted: true)
		}
	}

	func setPresented(_ isPresented: Bool, animated: Bool) {
		isHidden = !isPresented
		sidebarView.setPresented(isPresented, animated: animated)
		layer?.shadowOpacity = isPresented ? Self.sidebarPanelShadowOpacity : 0
	}

	func refreshAppearance() {
		sidebarView.refreshAppearance()
	}

	func applySidebarWidthSetting(_ width: CGFloat) {
		updateWidth(width, isCommitted: true)
		layoutSubtreeIfNeeded()
	}

	override func viewDidChangeEffectiveAppearance() {
		super.viewDidChangeEffectiveAppearance()
		refreshAppearance()
	}

	private func updateWidth(_ width: CGFloat, isCommitted: Bool) {
		let resolvedWidth = Self.clampWidth(width)
		let didChange = abs(widthConstraint.constant - resolvedWidth) >= 0.5
		if didChange {
			widthConstraint.constant = resolvedWidth
		}
		if didChange || isCommitted {
			onWidthChange(resolvedWidth)
		}
		if isCommitted {
			onCommitWidth(resolvedWidth)
		}
	}

	private func updateResizeState(_ currentWidth: CGFloat, animate: Bool) {
		let target = Self.clampWidth(currentWidth)
		let apply = {
			self.widthConstraint.constant = target
			self.layoutSubtreeIfNeeded()
		}
		guard animate else {
			apply()
			return
		}

		NSAnimationContext.runAnimationGroup { context in
			context.duration = Self.sidebarAnimationDuration
			context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
			apply()
		}
	}

	private static func clampWidth(_ width: CGFloat) -> CGFloat {
		let minWidth = CGFloat(NavigatorSidebarWidth.minimum)
		let maxWidth = CGFloat(NavigatorSidebarWidth.maximum)
		return min(max(width, minWidth), maxWidth)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	@available(*, unavailable)
	convenience init() {
		fatalError("init() is not available")
	}
}

private final class BrowserSidebarResizeHandle: NSView {
	var onDrag: ((CGFloat) -> Void)?
	var onCommit: ((CGFloat) -> Void)?
	private var isDragging = false
	private var dragStartWindowX: CGFloat = 0
	private var widthOnDragStart: CGFloat = 0

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.backgroundColor = NSColor.clear.cgColor
		addCursorRect(bounds, cursor: .resizeLeftRight)
	}

	override func mouseDown(with event: NSEvent) {
		guard let container = superview as? BrowserSidebarPanel else { return }
		isDragging = true
		dragStartWindowX = event.locationInWindow.x
		widthOnDragStart = container.widthConstraint.constant
		super.mouseDown(with: event)
	}

	override func mouseDragged(with event: NSEvent) {
		guard isDragging else { return }
		let proposedWidth = widthOnDragStart + (event.locationInWindow.x - dragStartWindowX)
		onDrag?(proposedWidth)
	}

	override func mouseUp(with event: NSEvent) {
		guard isDragging else { return }
		isDragging = false
		if let container = superview as? BrowserSidebarPanel {
			onCommit?(container.widthConstraint.constant)
		}
		super.mouseUp(with: event)
	}

	override func resetCursorRects() {
		addCursorRect(bounds, cursor: NSCursor.resizeLeftRight)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
}
