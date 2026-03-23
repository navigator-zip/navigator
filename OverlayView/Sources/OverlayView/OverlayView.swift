import Aesthetics
import BrandColors
import Helpers
import SwiftUI

public struct OverlayView: View {
	@Environment(\.colorScheme) private var colorScheme

	private enum ToastStyle {
		static let hiddenOffsetFallback: CGFloat = -220
		static let hiddenOffsetClearance: CGFloat = 72
		static let cornerRadius: CGFloat = 20
		static let contentVerticalPadding: CGFloat = 7.5
	}

	public enum Styling {
		case view(AnyView)
	}

	private let model: OverlayViewModel
	private let styling: Styling
	private let contentMaxWidth: CGFloat?

	@State private var contentsSize = CGSize.zero
	@State private var offset: CGFloat
	@State private var draggingPadding: CGFloat = 0
	@State private var hasAnimatedPresentation = false

	public init(
		model: OverlayViewModel,
		styling: Styling,
		contentMaxWidth: CGFloat? = nil
	) {
		self.model = model
		self.styling = styling
		self.contentMaxWidth = contentMaxWidth
		_offset = State(initialValue: ToastStyle.hiddenOffsetFallback)
	}

	public var body: some View {
		ZStack(alignment: .top) {
			Color.clear
				.onChange(of: model.isActive) { _, isActive in
					withAnimation(Self.animation) {
						offset = isActive ? 0 : hiddenOffset
					}
				}
				.onAppear {
					guard hasAnimatedPresentation == false else { return }
					hasAnimatedPresentation = true
					offset = hiddenOffset
					withAnimation(Self.animation) {
						offset = model.isActive ? 0 : hiddenOffset
					}
				}

			content
				.onSizeChange { size in
					let previousHeight = contentsSize.height
					contentsSize = size

					guard size.height > 0 else { return }

					let previousWasUnset = previousHeight <= 0
					if previousWasUnset || model.isActive == false {
						offset = model.isActive ? 0 : hiddenOffset
					}
				}
				.padding(.horizontal, 10)
				.frame(maxWidth: .infinity, alignment: .center)
				.gesture(
					DragGesture(minimumDistance: 10, coordinateSpace: .global)
						.onChanged { value in
							guard model.isActive else { return }
							let initial = value.location.y - value.startLocation.y
							draggingPadding = 0
							if initial < 0 {
								offset = initial * 0.65
							}
							else {
								offset = 0
							}
						}
						.onEnded { value in
							guard model.isActive else { return }
							if value.predictedEndTranslation.height < -80 {
								Task { await model.didRequestDismissal() }
							}
							else {
								withAnimation(Self.animation) {
									draggingPadding = 0
									offset = model.isActive ? 0 : hiddenOffset
								}
							}
						}
				)
				.offset(y: offset)
				.animation(Self.animation, value: contentMaxWidth)
		}
	}

	private var content: some View {
		Group {
			switch styling {
			case .view(let view):
				view
			}
		}
		.padding(.bottom, draggingPadding)
		.padding(.vertical, ToastStyle.contentVerticalPadding)
		.frame(maxWidth: contentMaxWidth, alignment: .leading)
		.drawingGroup()
		.clipShape(backgroundShape)
		.background(backgroundShape.fill(toastBackgroundColor))
		.overlay { toastBorderOverlay }
	}

	private var backgroundShape: RoundedRectangle {
		RoundedRectangle(cornerRadius: ToastStyle.cornerRadius, style: .continuous)
	}

	@ViewBuilder
	private var toastBorderOverlay: some View {
		if colorScheme == .dark {
			backgroundShape.strokeBorder(BrandColors.baseBackgroundAlternateDark, lineWidth: 1)
		}
	}

	private var toastBackgroundColor: SwiftUI.Color {
		colorScheme == .dark
			? BrandColors.baseBackgroundDark
			: Color(nsColor: Asset.Colors.background.color)
	}

	private var hiddenOffset: CGFloat {
		let measuredHeight = contentsSize.height
		guard measuredHeight > 0 else { return ToastStyle.hiddenOffsetFallback }
		return -(measuredHeight + ToastStyle.hiddenOffsetClearance)
	}

	private static var animation: Animation {
		.springable
	}
}
