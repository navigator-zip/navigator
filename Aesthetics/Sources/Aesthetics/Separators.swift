import AppKit

public func separator() -> NSView {
	SeparatorView.horizontal()
}

public func verticalSeparator() -> NSView {
	SeparatorView.vertical()
}

private final class SeparatorView: NSView {
	private enum Layout {
		static let horizontalPrimaryHeight: CGFloat = 1.5
		static let horizontalSecondaryHeight: CGFloat = 1
		static let horizontalHeight: CGFloat = 3
	}

	private let isVertical: Bool
	private let primary = NSView()
	private let secondary = NSView()
	private var systemAppearanceObserver: NSObjectProtocol?

	private init(isVertical: Bool) {
		self.isVertical = isVertical
		super.init(frame: .zero)
		setupLayout()
		installSystemAppearanceObserver()
		applyResolvedColors()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	deinit {
		if let systemAppearanceObserver {
			DistributedNotificationCenter.default().removeObserver(systemAppearanceObserver)
		}
	}

	override func viewDidChangeEffectiveAppearance() {
		super.viewDidChangeEffectiveAppearance()
		applyResolvedColors()
	}

	private func installSystemAppearanceObserver() {
		systemAppearanceObserver = DistributedNotificationCenter.default().addObserver(
			forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
			object: nil,
			queue: .main
		) { [weak self] _ in
			guard let self else { return }
			self.applyResolvedColors()
		}
	}

	private func setupLayout() {
		translatesAutoresizingMaskIntoConstraints = false
		if isVertical {
			widthAnchor.constraint(equalToConstant: 3).isActive = true
		}
		else {
			heightAnchor.constraint(equalToConstant: Layout.horizontalHeight).isActive = true
		}

		primary.translatesAutoresizingMaskIntoConstraints = false
		primary.wantsLayer = true
		addSubview(primary)

		secondary.translatesAutoresizingMaskIntoConstraints = false
		secondary.wantsLayer = true
		addSubview(secondary)

		if isVertical {
			NSLayoutConstraint.activate([
				secondary.topAnchor.constraint(equalTo: topAnchor),
				secondary.bottomAnchor.constraint(equalTo: bottomAnchor),
				secondary.leadingAnchor.constraint(equalTo: leadingAnchor),
				secondary.widthAnchor.constraint(equalToConstant: 1),

				primary.topAnchor.constraint(equalTo: topAnchor),
				primary.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
				primary.leadingAnchor.constraint(equalTo: secondary.trailingAnchor),
				primary.widthAnchor.constraint(equalToConstant: 2),
			])
		}
		else {
			NSLayoutConstraint.activate([
				secondary.bottomAnchor.constraint(equalTo: bottomAnchor),
				secondary.centerXAnchor.constraint(equalTo: centerXAnchor),
				secondary.heightAnchor.constraint(equalToConstant: Layout.horizontalSecondaryHeight),
				secondary.widthAnchor.constraint(equalTo: widthAnchor, constant: -2),

				primary.topAnchor.constraint(equalTo: topAnchor),
				primary.centerXAnchor.constraint(equalTo: centerXAnchor),
				primary.heightAnchor.constraint(equalToConstant: Layout.horizontalPrimaryHeight),
				primary.widthAnchor.constraint(equalTo: widthAnchor),
			])
		}
	}

	private func applyResolvedColors() {
		let appearance = effectiveAppearance
		let primarySeparatorColor = resolvedColor(Asset.Colors.separatorPrimaryColor.color, for: appearance)
		let secondarySeparatorColor = resolvedColor(Asset.Colors.separatorSecondaryColor.color, for: appearance)
		primary.layer?.backgroundColor = primarySeparatorColor.cgColor
		secondary.layer?.backgroundColor = secondarySeparatorColor.cgColor
	}

	private func resolvedColor(_ color: NSColor, for appearance: NSAppearance) -> NSColor {
		var resolvedColor = color
		appearance.performAsCurrentDrawingAppearance {
			resolvedColor = NSColor(cgColor: color.cgColor) ?? color
		}
		return resolvedColor
	}

	fileprivate static func horizontal() -> SeparatorView {
		SeparatorView(isVertical: false)
	}

	fileprivate static func vertical() -> SeparatorView {
		SeparatorView(isVertical: true)
	}
}
