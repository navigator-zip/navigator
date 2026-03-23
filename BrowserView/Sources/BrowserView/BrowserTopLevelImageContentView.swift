import AppKit
import Vendors

private final class BrowserTopLevelFittingImageView: NSImageView {
	override var intrinsicContentSize: NSSize {
		NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
	}
}

final class BrowserTopLevelImageContentView: NSView {
	private enum Layout {
		static let contentHeightRatio: CGFloat = 0.8
		static let contentWidthRatio: CGFloat = 0.8
		static let failureHorizontalInset: CGFloat = 24
	}

	private let viewModel: BrowserTopLevelImageContentViewModel
	private let imageView = BrowserTopLevelFittingImageView(frame: .zero)
	private let failureLabel = NSTextField(labelWithString: "")
	private var portraitHeightConstraint: NSLayoutConstraint?
	private var landscapeWidthConstraint: NSLayoutConstraint?
	private var imageAspectRatioConstraint: NSLayoutConstraint?

	init(viewModel: BrowserTopLevelImageContentViewModel) {
		self.viewModel = viewModel
		super.init(frame: .zero)
		translatesAutoresizingMaskIntoConstraints = false
		configureView()
		applyViewModel()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	private func configureView() {
		wantsLayer = true
		layer?.backgroundColor = NSColor.textBackgroundColor.cgColor

		imageView.translatesAutoresizingMaskIntoConstraints = false
		imageView.imageAlignment = .alignCenter
		imageView.imageScaling = .scaleProportionallyUpOrDown
		imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
		imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
		imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

		failureLabel.translatesAutoresizingMaskIntoConstraints = false
		failureLabel.alignment = .center
		failureLabel.lineBreakMode = .byTruncatingMiddle
		failureLabel.textColor = .secondaryLabelColor

		addSubview(imageView)
		addSubview(failureLabel)

		NSLayoutConstraint.activate([
			imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
			imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
			imageView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor),
			imageView.heightAnchor.constraint(lessThanOrEqualTo: heightAnchor),
			failureLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
			failureLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
			failureLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: Layout.failureHorizontalInset),
			failureLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Layout.failureHorizontalInset),
		])
	}

	private func applyViewModel() {
		imageView.image = viewModel.image
		imageView.isHidden = viewModel.image == nil
		failureLabel.stringValue = viewModel.failureText ?? ""
		failureLabel.isHidden = viewModel.failureText == nil
		updateImageLayoutConstraints()
	}

	private func updateImageLayoutConstraints() {
		portraitHeightConstraint?.isActive = false
		landscapeWidthConstraint?.isActive = false
		imageAspectRatioConstraint?.isActive = false
		portraitHeightConstraint = nil
		landscapeWidthConstraint = nil
		imageAspectRatioConstraint = nil

		guard imageView.isHidden == false else { return }
		guard let aspectRatio = viewModel.imageAspectRatio else { return }

		imageAspectRatioConstraint = imageView.widthAnchor.constraint(
			equalTo: imageView.heightAnchor,
			multiplier: aspectRatio
		)

		switch viewModel.preferredSizingMode {
		case .fixedWidth:
			landscapeWidthConstraint = imageView.widthAnchor.constraint(
				equalTo: widthAnchor,
				multiplier: Layout.contentWidthRatio
			)
			landscapeWidthConstraint?.isActive = true
		case .fixedHeight:
			portraitHeightConstraint = imageView.heightAnchor.constraint(
				equalTo: heightAnchor,
				multiplier: Layout.contentHeightRatio
			)
			portraitHeightConstraint?.isActive = true
		}

		imageAspectRatioConstraint?.isActive = true
	}
}

#if DEBUG
	extension BrowserTopLevelImageContentView {
		var imageViewForTesting: NSImageView {
			imageView
		}

		var failureTextForTesting: String? {
			failureLabel.isHidden ? nil : failureLabel.stringValue
		}

		var preferredSizingModeForTesting: BrowserTopLevelImageContentViewModel.PreferredSizingMode {
			viewModel.preferredSizingMode
		}

		var imageViewIntrinsicContentSizeForTesting: NSSize {
			imageView.intrinsicContentSize
		}
	}
#endif
