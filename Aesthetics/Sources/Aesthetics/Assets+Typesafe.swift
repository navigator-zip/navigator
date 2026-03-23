// swiftlint:disable all
// Generated using SwiftGen — https://github.com/SwiftGen/SwiftGen

#if os(macOS)
	import AppKit
#elseif os(iOS)
	import UIKit
#elseif os(tvOS) || os(watchOS)
	import UIKit
#endif

/// Deprecated typealiases
@available(*, deprecated, renamed: "ColorAsset.Color", message: "This typealias will be removed in SwiftGen 7.0")
public typealias AssetColorTypeAlias = ColorAsset.Color
@available(*, deprecated, renamed: "ImageAsset.Image", message: "This typealias will be removed in SwiftGen 7.0")
public typealias AssetImageTypeAlias = ImageAsset.Image

// swiftlint:disable superfluous_disable_command file_length implicit_return

// MARK: - Asset Catalogs

// swiftlint:disable identifier_name line_length nesting type_body_length type_name
public enum Asset {
	public enum Central {
		public static let info = ImageAsset(name: "info")
	}

	public enum Colors {
		public static let accent = ColorAsset(name: "Accent")
		public static let accentForegroundColor = ColorAsset(name: "AccentForegroundColor")
		public static let separatorPrimaryColor = ColorAsset(name: "SeparatorPrimaryColor")
		public static let separatorSecondaryColor = ColorAsset(name: "SeparatorSecondaryColor")
		public static let textPrimaryColor = ColorAsset(name: "TextPrimaryColor")
		public static let unmodifiedCodeBackgroundColor = ColorAsset(name: "UnmodifiedCodeBackgroundColor")
		public static let background = ColorAsset(name: "background")
		public static let controlAccentColor = ColorAsset(name: "controlAccentColor")
	}

	public enum Iconography {
		public static let arrowLeft = ImageAsset(name: "arrowLeft")
		public static let arrowRight = ImageAsset(name: "arrowRight")
		public static let earth = ImageAsset(name: "earth")
		public static let twitterLogoFill = ImageAsset(name: "twitterLogoFill")
		public static let twitterLogoRegular = ImageAsset(name: "twitterLogoRegular")
		public static let refresh = ImageAsset(name: "refresh")
		public static let search = ImageAsset(name: "search")
	}
}

public extension Asset.Iconography {
	static func imageIfAvailable(named name: String) -> ImageAsset.Image? {
		#if os(macOS)
			return BundleToken.image(named: name, in: BundleToken.bundle)
		#elseif os(iOS) || os(tvOS)
			return Image(named: name, in: BundleToken.bundle, compatibleWith: nil)
		#else
			return nil
		#endif
	}
}

// swiftlint:enable identifier_name line_length nesting type_body_length type_name

// MARK: - Implementation Details

public final class ColorAsset: Sendable {
	public let name: String

	#if os(macOS)
		public typealias Color = NSColor
	#elseif os(iOS) || os(tvOS) || os(watchOS)
		public typealias Color = UIColor
	#endif

	@available(iOS 11.0, tvOS 11.0, watchOS 4.0, macOS 10.13, *)
	public let color: Color

	#if os(iOS) || os(tvOS)
		@available(iOS 11.0, tvOS 11.0, *)
		public func color(compatibleWith traitCollection: UITraitCollection) -> Color {
			let bundle = BundleToken.bundle
			guard let color = Color(named: name, in: bundle, compatibleWith: traitCollection) else {
				fatalError("Unable to load color asset named \(name).")
			}
			return color
		}
	#endif

	init(name: String) {
		self.name = name
		#if os(macOS)
			let bundle = BundleToken.bundle
			self.color = BundleToken.color(named: name, in: bundle) ?? BundleToken.missingColor(named: name)
		#else
			guard let color = Color(assetName: name) else {
				fatalError("Unable to load color asset named \(name).")
			}
			self.color = color
		#endif
	}
}

public extension ColorAsset.Color {
	@available(iOS 11.0, tvOS 11.0, watchOS 4.0, macOS 10.13, *)
	convenience init?(assetName: String) {
		let bundle = BundleToken.bundle
		#if os(iOS) || os(tvOS)
			self.init(named: assetName, in: bundle, compatibleWith: nil)
		#elseif os(macOS)
			if let color = BundleToken.color(named: assetName, in: bundle) {
				self.init(cgColor: color.cgColor)!
			}
			else if BundleToken.isRunningTests {
				self.init(calibratedRed: 0, green: 0, blue: 0, alpha: 0)
			}
			else {
				return nil
			}
		#elseif os(watchOS)
			self.init(named: assetName)
		#endif
	}
}

public struct ImageAsset: Sendable {
	public let name: String

	#if os(macOS)
		public typealias Image = NSImage
	#elseif os(iOS) || os(tvOS) || os(watchOS)
		public typealias Image = UIImage
	#endif

	@available(iOS 8.0, tvOS 9.0, watchOS 2.0, macOS 10.7, *)
	public var image: Image {
		let bundle = BundleToken.bundle
		#if os(iOS) || os(tvOS)
			let image = Image(named: name, in: bundle, compatibleWith: nil)
		#elseif os(macOS)
			guard let result = BundleToken.image(named: name, in: bundle) else {
				return BundleToken.missingImage(named: name)
			}
			return result
		#elseif os(watchOS)
			let image = Image(named: name)
		#endif
		#if !os(macOS)
			guard let result = image else {
				fatalError("Unable to load image asset named \(name).")
			}
			return result
		#endif
	}

	#if os(iOS) || os(tvOS)
		@available(iOS 8.0, tvOS 9.0, *)
		public func image(compatibleWith traitCollection: UITraitCollection) -> Image {
			let bundle = BundleToken.bundle
			guard let result = Image(named: name, in: bundle, compatibleWith: traitCollection) else {
				fatalError("Unable to load image asset named \(name).")
			}
			return result
		}
	#endif
}

public extension ImageAsset.Image {
	@available(iOS 8.0, tvOS 9.0, watchOS 2.0, *)
	@available(
		macOS,
		deprecated,
		message: "This initializer is unsafe on macOS, please use the ImageAsset.image property"
	)
	convenience init?(asset: ImageAsset) {
		#if os(iOS) || os(tvOS)
			let bundle = BundleToken.bundle
			self.init(named: asset.name, in: bundle, compatibleWith: nil)
		#elseif os(macOS)
			if let image = BundleToken.namedImage(named: asset.name),
			   let data = image.tiffRepresentation,
			   let copy = NSImage(data: data) {
				self.init(data: data)
				self.size = copy.size
			}
			else if let fallback = BundleToken.missingCopiedImage() {
				self.init(size: fallback.size)
			}
			else {
				return nil
			}
		#elseif os(watchOS)
			self.init(named: asset.name)
		#endif
	}
}

// swiftlint:disable convenience_type
private final class BundleToken {
	static let defaultIsRunningTests = Bundle.allBundles.contains { $0.bundlePath.hasSuffix(".xctest") }
	static let defaultBundle: Bundle = {
		#if SWIFT_PACKAGE
			return Bundle.module
		#else
			return Bundle(for: BundleToken.self)
		#endif
	}()

	static var isRunningTestsOverride: Bool?
	static var bundleOverride: Bundle?

	#if os(macOS)
		static var colorLoaderOverride: ((_ name: String, _ bundle: Bundle) -> NSColor?)?
		static var imageLoaderOverride: ((_ name: String, _ bundle: Bundle) -> NSImage?)?
		static var namedImageLoaderOverride: ((_ name: String) -> NSImage?)?

		static func color(named name: String, in bundle: Bundle) -> NSColor? {
			if let loader = colorLoaderOverride {
				return loader(name, bundle)
			}
			return NSColor(named: NSColor.Name(name), bundle: bundle)
		}

		static func image(named name: String, in bundle: Bundle) -> NSImage? {
			if let loader = imageLoaderOverride {
				return loader(name, bundle)
			}
			let resolvedName = NSImage.Name(name)
			return bundle == .main ? NSImage(named: resolvedName) : bundle.image(forResource: resolvedName)
		}

		static func namedImage(named name: String) -> NSImage? {
			if let loader = namedImageLoaderOverride {
				return loader(name)
			}
			return NSImage(named: NSImage.Name(name))
		}

		static func missingColor(named name: String) -> NSColor {
			#if DEBUG
				return .clear
			#else
				fatalError("Unable to load color asset named \(name).")
			#endif
		}

		static func placeholderImage() -> NSImage {
			NSImage(size: NSSize(width: 1, height: 1))
		}

		static func missingImage(named name: String) -> NSImage {
			#if DEBUG
				return placeholderImage()
			#else
				fatalError("Unable to load image asset named \(name).")
			#endif
		}

		static func missingCopiedImage() -> NSImage? {
			isRunningTests ? placeholderImage() : nil
		}

		static func resetForTesting() {
			isRunningTestsOverride = nil
			bundleOverride = nil
			colorLoaderOverride = nil
			imageLoaderOverride = nil
			namedImageLoaderOverride = nil
		}
	#endif

	static var isRunningTests: Bool {
		isRunningTestsOverride ?? defaultIsRunningTests
	}

	static var bundle: Bundle {
		bundleOverride ?? defaultBundle
	}
}

// swiftlint:enable convenience_type

#if os(macOS)
	enum AssetLoadingForTesting {
		static func setIsRunningTests(_ isRunningTests: Bool) {
			BundleToken.isRunningTestsOverride = isRunningTests
		}

		static func setBundle(_ bundle: Bundle) {
			BundleToken.bundleOverride = bundle
		}

		static func setColorLoader(_ loader: @escaping (_ name: String, _ bundle: Bundle) -> NSColor?) {
			BundleToken.colorLoaderOverride = loader
		}

		static func setImageLoader(_ loader: @escaping (_ name: String, _ bundle: Bundle) -> NSImage?) {
			BundleToken.imageLoaderOverride = loader
		}

		static func setNamedImageLoader(_ loader: @escaping (_ name: String) -> NSImage?) {
			BundleToken.namedImageLoaderOverride = loader
		}

		static func reset() {
			BundleToken.resetForTesting()
		}
	}
#endif

// swiftlint:disable all
// Generated using SwiftGen — https://github.com/SwiftGen/SwiftGen

// No fonts found
