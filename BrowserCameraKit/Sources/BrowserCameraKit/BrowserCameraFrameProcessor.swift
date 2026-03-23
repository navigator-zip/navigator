import AVFoundation
import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import ModelKit
import Pipeline
import QuartzCore
import Shared

protocol BrowserCameraFrameProcessing: AnyObject {
	func warmIfNeeded(for preset: BrowserCameraFilterPreset) throws
	func warmIfNeeded(
		for preset: BrowserCameraFilterPreset,
		grainPresence: BrowserCameraPipelineGrainPresence
	) throws
	@discardableResult
	func process(
		pixelBuffer: CVPixelBuffer,
		preset: BrowserCameraFilterPreset,
		devicePosition: AVCaptureDevice.Position
	) throws -> BrowserCameraProcessedFrame
	@discardableResult
	func process(
		pixelBuffer: CVPixelBuffer,
		preset: BrowserCameraFilterPreset,
		grainPresence: BrowserCameraPipelineGrainPresence,
		devicePosition: AVCaptureDevice.Position
	) throws -> BrowserCameraProcessedFrame
}

extension BrowserCameraFrameProcessing {
	func warmIfNeeded(
		for preset: BrowserCameraFilterPreset,
		grainPresence _: BrowserCameraPipelineGrainPresence
	) throws {
		try warmIfNeeded(for: preset)
	}

	@discardableResult
	func process(
		pixelBuffer: CVPixelBuffer,
		preset: BrowserCameraFilterPreset,
		grainPresence _: BrowserCameraPipelineGrainPresence,
		devicePosition: AVCaptureDevice.Position
	) throws -> BrowserCameraProcessedFrame {
		try process(
			pixelBuffer: pixelBuffer,
			preset: preset,
			devicePosition: devicePosition
		)
	}
}

enum BrowserCameraFrameProcessingError: Error, Equatable, Sendable {
	case renderFailed(description: String)
}

struct BrowserCameraProcessedFrame {
	let previewImage: CGImage
	let hasPreviewImage: Bool
	let pixelBuffer: CVPixelBuffer
	let payloadByteCount: Int
	let pixelWidth: Int
	let pixelHeight: Int
	let bytesPerRow: Int
	let processingLatency: TimeInterval
	let pipelineRuntimeState: BrowserCameraPipelineRuntimeState

	init(
		previewImage: CGImage,
		hasPreviewImage: Bool = true,
		pixelBuffer: CVPixelBuffer,
		pixelWidth: Int,
		pixelHeight: Int,
		bytesPerRow: Int,
		processingLatency: TimeInterval,
		pipelineRuntimeState: BrowserCameraPipelineRuntimeState
	) {
		self.previewImage = previewImage
		self.hasPreviewImage = hasPreviewImage
		self.pixelBuffer = pixelBuffer
		self.payloadByteCount = bytesPerRow * pixelHeight
		self.pixelWidth = pixelWidth
		self.pixelHeight = pixelHeight
		self.bytesPerRow = bytesPerRow
		self.processingLatency = processingLatency
		self.pipelineRuntimeState = pipelineRuntimeState
	}

	init(
		previewImage: CGImage,
		hasPreviewImage: Bool = true,
		pixelData: Data,
		pixelWidth: Int,
		pixelHeight: Int,
		bytesPerRow: Int,
		processingLatency: TimeInterval,
		pipelineRuntimeState: BrowserCameraPipelineRuntimeState
	) {
		var pixelBuffer: CVPixelBuffer?
		let attributes = [
			kCVPixelBufferCGImageCompatibilityKey: true,
			kCVPixelBufferCGBitmapContextCompatibilityKey: true,
			kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
		] as CFDictionary
		let status = CVPixelBufferCreate(
			kCFAllocatorDefault,
			pixelWidth,
			pixelHeight,
			kCVPixelFormatType_32BGRA,
			attributes,
			&pixelBuffer
		)
		precondition(status == kCVReturnSuccess && pixelBuffer != nil)
		CVPixelBufferLockBaseAddress(pixelBuffer!, [])
		if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer!) {
			memset(baseAddress, 0, CVPixelBufferGetDataSize(pixelBuffer!))
			pixelData.withUnsafeBytes { sourceBytes in
				guard let sourceBaseAddress = sourceBytes.baseAddress else { return }
				memcpy(baseAddress, sourceBaseAddress, min(pixelData.count, CVPixelBufferGetDataSize(pixelBuffer!)))
			}
		}
		CVPixelBufferUnlockBaseAddress(pixelBuffer!, [])
		self.previewImage = previewImage
		self.hasPreviewImage = hasPreviewImage
		self.pixelBuffer = pixelBuffer!
		self.payloadByteCount = pixelData.count
		self.pixelWidth = pixelWidth
		self.pixelHeight = pixelHeight
		self.bytesPerRow = bytesPerRow
		self.processingLatency = processingLatency
		self.pipelineRuntimeState = pipelineRuntimeState
	}
}

final class LiveBrowserCameraFrameProcessor: BrowserCameraFrameProcessing {
	private enum Constants {
		static let maximumPreviewLongEdge: CGFloat = 1280
		static let maximumOutputWidth: CGFloat = 1280
		static let maximumOutputHeight: CGFloat = 720
	}

	private static let placeholderPreviewImage: CGImage = {
		let colorSpace = CGColorSpaceCreateDeviceRGB()
		let context = CGContext(
			data: nil,
			width: 1,
			height: 1,
			bitsPerComponent: 8,
			bytesPerRow: 4,
			space: colorSpace,
			bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
		)
		guard let image = context?.makeImage() else {
			fatalError("Unable to allocate BrowserCameraFrameProcessor placeholder preview image")
		}
		return image
	}()

	struct Environment {
		var makeContext: () -> CIContext
		var render: (CIContext, CIImage, CGRect) -> CGImage?
		var makePixelBuffer: @Sendable (Int, Int) -> CVPixelBuffer?
		var renderToPixelBuffer: (CIContext, CIImage, CVPixelBuffer) -> Void
		var loadInitialPipelineData: () throws -> Void
		var processWithAperture: (
			CIContext,
			CIImage,
			BrowserCameraFilterPreset,
			BrowserCameraPipelineGrainPresence,
			AVCaptureDevice.Position
		) -> CIImage?
		var makeFilter: (BrowserCameraPipelineFilterName) -> CIFilter?

		init(
			makeContext: @escaping () -> CIContext,
			render: @escaping (CIContext, CIImage, CGRect) -> CGImage?,
			makePixelBuffer: @escaping @Sendable (Int, Int) -> CVPixelBuffer?,
			renderToPixelBuffer: @escaping (CIContext, CIImage, CVPixelBuffer) -> Void,
			loadInitialPipelineData: @escaping () throws -> Void,
			processWithAperture: @escaping (
				CIContext,
				CIImage,
				BrowserCameraFilterPreset,
				BrowserCameraPipelineGrainPresence,
				AVCaptureDevice.Position
			) -> CIImage?,
			makeFilter: @escaping (BrowserCameraPipelineFilterName) -> CIFilter?
		) {
			self.makeContext = makeContext
			self.render = render
			self.makePixelBuffer = makePixelBuffer
			self.renderToPixelBuffer = renderToPixelBuffer
			self.loadInitialPipelineData = loadInitialPipelineData
			self.processWithAperture = processWithAperture
			self.makeFilter = makeFilter
		}

		init(
			makeContext: @escaping () -> CIContext,
			render: @escaping (CIContext, CIImage, CGRect) -> CGImage?,
			makePixelBuffer: @escaping @Sendable (Int, Int) -> CVPixelBuffer?,
			renderToPixelBuffer: @escaping (CIContext, CIImage, CVPixelBuffer) -> Void,
			loadInitialPipelineData: @escaping () throws -> Void,
			processWithAperture: @escaping (
				CIImage,
				BrowserCameraFilterPreset,
				AVCaptureDevice.Position
			) -> CIImage?,
			makeFilter: @escaping (BrowserCameraPipelineFilterName) -> CIFilter?
		) {
			self.init(
				makeContext: makeContext,
				render: render,
				makePixelBuffer: makePixelBuffer,
				renderToPixelBuffer: renderToPixelBuffer,
				loadInitialPipelineData: loadInitialPipelineData,
				processWithAperture: { _, image, preset, _, devicePosition in
					processWithAperture(image, preset, devicePosition)
				},
				makeFilter: makeFilter
			)
		}

		static func live() -> Self {
			Self(
				makeContext: { BrowserCameraRenderingContext.shared },
				render: { context, image, extent in
					context.createCGImage(image, from: extent)
				},
				makePixelBuffer: { width, height in
					var pixelBuffer: CVPixelBuffer?
					let attributes = [
						kCVPixelBufferCGImageCompatibilityKey: true,
						kCVPixelBufferCGBitmapContextCompatibilityKey: true,
						kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
					] as CFDictionary
					let status = CVPixelBufferCreate(
						kCFAllocatorDefault,
						width,
						height,
						kCVPixelFormatType_32BGRA,
						attributes,
						&pixelBuffer
					)
					guard status == kCVReturnSuccess else { return nil }
					return pixelBuffer
				},
				renderToPixelBuffer: { context, image, pixelBuffer in
					context.render(image, to: pixelBuffer)
				},
				loadInitialPipelineData: {
					try CubeTransformer.loadInitialPipelineDataSync()
				},
				processWithAperture: { context, image, preset, grainPresence, devicePosition in
					BrowserCameraApertureProcessing.process(
						context: context,
						image: image,
						preset: preset,
						grainPresence: grainPresence,
						devicePosition: devicePosition
					)
				},
				makeFilter: { filterName in
					CIFilter(name: filterName.rawValue)
				}
			)
		}
	}

	private let environment: Environment
	private let context: CIContext
	private var hasLoadedInitialPipelineData = false
	private var isInitialPipelineDataUnavailable = false
	private var warmedProfiles = Set<BrowserCameraPipelineWarmupProfile>()

	init(environment: Environment = .live()) {
		self.environment = environment
		context = environment.makeContext()
	}

	func warmIfNeeded(for preset: BrowserCameraFilterPreset) throws {
		try warmIfNeeded(for: preset, grainPresence: .none)
	}

	func warmIfNeeded(
		for preset: BrowserCameraFilterPreset,
		grainPresence: BrowserCameraPipelineGrainPresence
	) throws {
		_ = loadInitialPipelineDataIfNeeded(for: preset)
		for descriptor in BrowserCameraPipelineDescriptorResolver.warmupDescriptors(
			for: preset,
			grainPresence: grainPresence
		) {
			guard warmedProfiles.insert(descriptor.warmupProfile).inserted else { continue }
			for filterName in descriptor.requiredFilters {
				_ = makeFilter(named: filterName)
			}
		}
	}

	@discardableResult
	func process(
		pixelBuffer: CVPixelBuffer,
		preset: BrowserCameraFilterPreset,
		devicePosition: AVCaptureDevice.Position
	) throws -> BrowserCameraProcessedFrame {
		try process(
			pixelBuffer: pixelBuffer,
			preset: preset,
			grainPresence: .none,
			devicePosition: devicePosition
		)
	}

	@discardableResult
	func process(
		pixelBuffer: CVPixelBuffer,
		preset: BrowserCameraFilterPreset,
		grainPresence: BrowserCameraPipelineGrainPresence,
		devicePosition: AVCaptureDevice.Position
	) throws -> BrowserCameraProcessedFrame {
		try warmIfNeeded(for: preset, grainPresence: grainPresence)
		let startTime = CACurrentMediaTime()
		let pipelineRuntimeState = makePipelineRuntimeState(
			preset: .none,
			descriptor: BrowserCameraPipelineDescriptorResolver.descriptor(
				for: .none,
				devicePosition: devicePosition,
				grainPresence: .none
			),
			apertureImage: nil
		)
		return BrowserCameraProcessedFrame(
			previewImage: Self.placeholderPreviewImage,
			hasPreviewImage: false,
			pixelBuffer: pixelBuffer,
			pixelWidth: CVPixelBufferGetWidth(pixelBuffer),
			pixelHeight: CVPixelBufferGetHeight(pixelBuffer),
			bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
			processingLatency: CACurrentMediaTime() - startTime,
			pipelineRuntimeState: pipelineRuntimeState
		)
	}

	private func outputExtent(for extent: CGRect) -> CGRect {
		guard extent.width > 0, extent.height > 0 else { return extent }
		let scale = min(
			Constants.maximumOutputWidth / extent.width,
			Constants.maximumOutputHeight / extent.height,
			1
		)
		guard scale < 1 else { return extent }
		return CGRect(
			x: 0,
			y: 0,
			width: floor(extent.width * scale),
			height: floor(extent.height * scale)
		)
	}

	private func outputImage(from image: CIImage, extent: CGRect) -> CIImage {
		let imageExtent = image.extent
		guard extent != imageExtent,
		      extent.width > 0, extent.height > 0,
		      imageExtent.width > 0, imageExtent.height > 0 else {
			return image
		}
		return image.transformed(
			by: .init(
				scaleX: extent.width / imageExtent.width,
				y: extent.height / imageExtent.height
			)
		)
	}

	private func previewExtent(for extent: CGRect) -> CGRect {
		guard extent.width > 0, extent.height > 0 else { return extent }
		let longEdge = max(extent.width, extent.height)
		guard longEdge > Constants.maximumPreviewLongEdge else { return extent }

		let scale = Constants.maximumPreviewLongEdge / longEdge
		return CGRect(
			x: 0,
			y: 0,
			width: floor(extent.width * scale),
			height: floor(extent.height * scale)
		)
	}

	@discardableResult
	private func loadInitialPipelineDataIfNeeded(for preset: BrowserCameraFilterPreset) -> Bool {
		guard preset != .none else { return false }
		guard hasLoadedInitialPipelineData == false else { return true }
		guard isInitialPipelineDataUnavailable == false else { return false }
		do {
			try environment.loadInitialPipelineData()
			hasLoadedInitialPipelineData = true
			return true
		}
		catch {
			isInitialPipelineDataUnavailable = true
			return false
		}
	}

	private func shouldUseAperture(for preset: BrowserCameraFilterPreset) -> Bool {
		preset != .none && hasLoadedInitialPipelineData
	}

	private func applyDescriptor(
		_ descriptor: BrowserCameraPipelineDescriptor,
		to image: CIImage
	) -> CIImage {
		switch descriptor.recipeKind {
		case .passthrough:
			image
		case .monochrome(let exposureAdjustment):
			applyMonochrome(
				to: image,
				exposureAdjustment: exposureAdjustment,
				grainPresence: descriptor.grainPresence
			)
		case .dither:
			applyDither(to: image, grainPresence: descriptor.grainPresence)
		case .chromatic(
			let neutralTemperature,
			let targetTemperature,
			let saturation,
			let contrast,
			let redVector
		):
			applyChromatic(
				to: image,
				neutralTemperature: neutralTemperature,
				targetTemperature: targetTemperature,
				saturation: saturation,
				contrast: contrast,
				colorVector: redVector.ciVector,
				grainPresence: descriptor.grainPresence
			)
		case .supergold:
			applySupergold(to: image)
		case .warhol(let transformation):
			applyWarhol(
				to: image,
				transformation: transformation,
				grainPresence: descriptor.grainPresence
			)
		}
	}

	private func applyMonochrome(
		to image: CIImage,
		exposureAdjustment: Double,
		grainPresence: BrowserCameraPipelineGrainPresence
	) -> CIImage {
		let toned = applyTemperature(
			to: image,
			neutralTemperature: 6500,
			targetTemperature: 7600
		)
		let monochrome = applyPhotoEffectMono(to: toned)
		let contrasted = applyColorControls(
			to: monochrome,
			saturation: 0,
			brightness: 0,
			contrast: 1.10
		)
		let exposed = applyExposure(to: contrasted, value: exposureAdjustment)
		return applyNoise(to: exposed, presence: grainPresence)
	}

	private func applyDither(
		to image: CIImage,
		grainPresence: BrowserCameraPipelineGrainPresence
	) -> CIImage {
		let transformedImage = Transformation(grainPresence.sharedPresence, .dither).transform(image)
		guard let outputImage = try? DitheringTransformer(
			image: transformedImage,
			context: context
		).outputImage else {
			return transformedImage
		}
		return CIImage(cgImage: outputImage)
	}

	private func applySupergold(to image: CIImage) -> CIImage {
		let exposed = applyExposure(to: image, value: 0.20)
		let warmed = applyTemperature(
			to: exposed,
			neutralTemperature: 6500,
			targetTemperature: 8200
		)
		let sepia = applySepia(to: warmed, intensity: 0.28)
		let contrasted = applyColorControls(
			to: sepia,
			saturation: 1.04,
			brightness: 0,
			contrast: 1.04
		)
		return applyNoise(to: contrasted, presence: .none)
	}

	private func applyChromatic(
		to image: CIImage,
		neutralTemperature: CGFloat,
		targetTemperature: CGFloat,
		saturation: CGFloat,
		contrast: CGFloat,
		colorVector: CIVector,
		grainPresence: BrowserCameraPipelineGrainPresence
	) -> CIImage {
		let regulated = applyTemperature(
			to: image,
			neutralTemperature: neutralTemperature,
			targetTemperature: targetTemperature
		)
		let colored = applyColorControls(
			to: regulated,
			saturation: saturation,
			brightness: 0,
			contrast: contrast
		)
		let matrixed = applyColorMatrix(
			to: colored,
			redVector: colorVector,
			greenVector: CIVector(x: 0, y: 1, z: 0, w: 0),
			blueVector: CIVector(x: 0, y: 0, z: 1, w: 0)
		)
		return applyNoise(to: matrixed, presence: grainPresence)
	}

	private func applyWarhol(
		to image: CIImage,
		transformation _: BrowserCameraWarholTransformation,
		grainPresence: BrowserCameraPipelineGrainPresence
	) -> CIImage {
		applyNoise(to: image, presence: grainPresence)
	}

	private func applyExposure(
		to image: CIImage,
		value: Double
	) -> CIImage {
		applyFilter(named: .exposureAdjust, to: image) { filter in
			filter.setValue(value, forKey: kCIInputEVKey)
		}
	}

	private func applyTemperature(
		to image: CIImage,
		neutralTemperature: CGFloat,
		targetTemperature: CGFloat
	) -> CIImage {
		applyFilter(named: .temperatureAndTint, to: image) { filter in
			filter.setValue(
				CIVector(x: neutralTemperature, y: 0),
				forKey: "inputNeutral"
			)
			filter.setValue(
				CIVector(x: targetTemperature, y: 0),
				forKey: "inputTargetNeutral"
			)
		}
	}

	private func applyColorControls(
		to image: CIImage,
		saturation: CGFloat,
		brightness: CGFloat,
		contrast: CGFloat
	) -> CIImage {
		applyFilter(named: .colorControls, to: image) { filter in
			filter.setValue(saturation, forKey: kCIInputSaturationKey)
			filter.setValue(brightness, forKey: kCIInputBrightnessKey)
			filter.setValue(contrast, forKey: kCIInputContrastKey)
		}
	}

	private func applyPhotoEffectMono(to image: CIImage) -> CIImage {
		applyFilter(named: .photoEffectMono, to: image)
	}

	private func applySepia(
		to image: CIImage,
		intensity: CGFloat
	) -> CIImage {
		applyFilter(named: .sepiaTone, to: image) { filter in
			filter.setValue(intensity, forKey: kCIInputIntensityKey)
		}
	}

	private func applyColorMatrix(
		to image: CIImage,
		redVector: CIVector,
		greenVector: CIVector,
		blueVector: CIVector
	) -> CIImage {
		applyFilter(named: .colorMatrix, to: image) { filter in
			filter.setValue(redVector, forKey: "inputRVector")
			filter.setValue(greenVector, forKey: "inputGVector")
			filter.setValue(blueVector, forKey: "inputBVector")
		}
	}

	private func applyNoise(
		to image: CIImage,
		presence: BrowserCameraPipelineGrainPresence
	) -> CIImage {
		guard presence != .none,
		      let monochrome = makeFilter(named: .colorMonochrome),
		      let invert = makeFilter(named: .colorInvert),
		      let colorMatrix = makeFilter(named: .colorMatrix),
		      let blend = makeFilter(named: .multiplyBlendMode),
		      let randomImage = makeFilter(named: .randomGenerator)?.outputImage
		else {
			return image
		}

		monochrome.setValue(randomImage, forKey: kCIInputImageKey)
		monochrome.setValue(CIColor(red: 1, green: 1, blue: 1), forKey: kCIInputColorKey)
		monochrome.setValue(1, forKey: kCIInputIntensityKey)

		invert.setValue(monochrome.outputImage, forKey: kCIInputImageKey)
		guard let invertedNoise = invert.outputImage else { return image }

		colorMatrix.setValue(invertedNoise, forKey: kCIInputImageKey)
		colorMatrix.setValue(
			CIVector(x: 0, y: 0, z: 0, w: presence == .high ? 0.35 : 0.20),
			forKey: "inputAVector"
		)
		guard let alphaNoise = colorMatrix.outputImage else { return image }

		let transformedNoise = alphaNoise
			.transformed(by: CGAffineTransform(scaleX: 1.5, y: 1.75))
			.transformed(
				by: .init(
					rotationAngle: .pi / 7,
					anchor: CGPoint(x: image.extent.midX, y: image.extent.midY)
				)
			)

		blend.setValue(image, forKey: kCIInputBackgroundImageKey)
		blend.setValue(transformedNoise, forKey: kCIInputImageKey)
		return blend.outputImage?.cropped(to: image.extent) ?? image
	}

	private func applyFilter(
		named filterName: BrowserCameraPipelineFilterName,
		to image: CIImage,
		configure: (CIFilter) -> Void = { _ in }
	) -> CIImage {
		guard let filter = makeFilter(named: filterName) else { return image }
		filter.setValue(image, forKey: kCIInputImageKey)
		configure(filter)
		return filter.outputImage ?? image
	}

	private func makeFilter(named filterName: BrowserCameraPipelineFilterName) -> CIFilter? {
		environment.makeFilter(filterName)
	}

	private func makePipelineRuntimeState(
		preset: BrowserCameraFilterPreset,
		descriptor: BrowserCameraPipelineDescriptor,
		apertureImage: CIImage?
	) -> BrowserCameraPipelineRuntimeState {
		let implementation: BrowserCameraPipelineImplementation = if preset == .none {
			.passthrough
		}
		else if apertureImage != nil {
			.aperture
		}
		else {
			.navigatorFallback
		}
		return BrowserCameraPipelineRuntimeState(
			preset: preset,
			implementation: implementation,
			warmupProfile: descriptor.warmupProfile,
			grainPresence: descriptor.grainPresence,
			requiredFilterCount: descriptor.requiredFilters.count
		)
	}
}

enum BrowserCameraApertureProcessing {
	private struct Recipe {
		let transformation: Transformation
		let output: Output
	}

	private enum Output {
		case monochromatic
		case chromatic(ChromaticTransformation)
		case dither
		case warhol(BrowserCameraWarholTransformation)
	}

	typealias MonochromaticOutputFactory = (CIImage, AVCaptureDevice.Position) -> CIImage?
	typealias ChromaticOutputFactory = (CIImage, ChromaticTransformation) -> CIImage?
	typealias DitherOutputFactory = (CIImage) -> CIImage?
	typealias WarholOutputFactory = (CIImage, BrowserCameraWarholTransformation) -> CIImage?

	static func process(
		context: CIContext,
		image: CIImage,
		preset: BrowserCameraFilterPreset,
		grainPresence: BrowserCameraPipelineGrainPresence,
		devicePosition: AVCaptureDevice.Position
	) -> CIImage? {
		process(
			context: context,
			image: image,
			preset: preset,
			grainPresence: grainPresence,
			devicePosition: devicePosition,
			makeMonochromaticOutput: { transformedImage, devicePosition in
				CubeTransformer(
					image: transformedImage,
					.monochromatic(devicePosition)
				).outputImage
			},
			makeChromaticOutput: { transformedImage, transformation in
				CubeTransformer(
					image: transformedImage,
					.chromatic(transformation)
				).outputImage
			},
			makeDitherOutput: { transformedImage in
				guard let outputImage = try? DitheringTransformer(
					image: transformedImage,
					context: context
				).outputImage else {
					return nil
				}
				return CIImage(cgImage: outputImage)
			},
			makeWarholOutput: { transformedImage, transformation in
				guard let outputImage = try? PolynomialTransformer(
					image: transformedImage,
					context: context,
					warhol: transformation.sharedTransformation
				).outputImage else {
					return nil
				}
				return CIImage(cgImage: outputImage)
			}
		)
	}

	static func process(
		image: CIImage,
		preset: BrowserCameraFilterPreset,
		devicePosition: AVCaptureDevice.Position,
		makeMonochromaticOutput: MonochromaticOutputFactory,
		makeChromaticOutput: ChromaticOutputFactory
	) -> CIImage? {
		process(
			context: BrowserCameraRenderingContext.shared,
			image: image,
			preset: preset,
			grainPresence: .none,
			devicePosition: devicePosition,
			makeMonochromaticOutput: makeMonochromaticOutput,
			makeChromaticOutput: makeChromaticOutput,
			makeDitherOutput: { _ in nil },
			makeWarholOutput: { _, _ in nil }
		)
	}

	static func process(
		context _: CIContext,
		image: CIImage,
		preset: BrowserCameraFilterPreset,
		grainPresence: BrowserCameraPipelineGrainPresence,
		devicePosition: AVCaptureDevice.Position,
		makeMonochromaticOutput: MonochromaticOutputFactory,
		makeChromaticOutput: ChromaticOutputFactory,
		makeDitherOutput: DitherOutputFactory,
		makeWarholOutput: WarholOutputFactory
	) -> CIImage? {
		guard let recipe = recipe(for: preset, grainPresence: grainPresence) else {
			return nil
		}

		let transformedImage = recipe.transformation.transform(image)
		switch recipe.output {
		case .monochromatic:
			return makeMonochromaticOutput(transformedImage, devicePosition)
		case .chromatic(let transformation):
			return makeChromaticOutput(transformedImage, transformation)
		case .dither:
			return makeDitherOutput(transformedImage)
		case .warhol(let transformation):
			return makeWarholOutput(transformedImage, transformation)
		}
	}

	private static func recipe(
		for preset: BrowserCameraFilterPreset,
		grainPresence: BrowserCameraPipelineGrainPresence
	) -> Recipe? {
		switch preset {
		case .none:
			return nil
		case .monochrome:
			return Recipe(
				transformation: Transformation(grainPresence.sharedPresence, .monochrome),
				output: .monochromatic
			)
		case .dither:
			return Recipe(
				transformation: Transformation(grainPresence.sharedPresence, .dither),
				output: .dither
			)
		case .folia:
			return Recipe(
				transformation: Transformation(grainPresence.sharedPresence, .chromatic(.folia)),
				output: .chromatic(.folia)
			)
		case .supergold:
			return Recipe(
				transformation: Transformation(grainPresence.sharedPresence, .chromatic(.supergold)),
				output: .chromatic(.supergold)
			)
		case .tonachrome:
			return Recipe(
				transformation: Transformation(grainPresence.sharedPresence, .chromatic(.tonachrome)),
				output: .chromatic(.tonachrome)
			)
		case .bubblegum:
			return Recipe(
				transformation: Transformation(grainPresence.sharedPresence, .warhol(.bubblegum)),
				output: .warhol(.bubblegum)
			)
		case .darkroom:
			return Recipe(
				transformation: Transformation(grainPresence.sharedPresence, .warhol(.darkroom)),
				output: .warhol(.darkroom)
			)
		case .glowInTheDark:
			return Recipe(
				transformation: Transformation(grainPresence.sharedPresence, .warhol(.glowInTheDark)),
				output: .warhol(.glowInTheDark)
			)
		case .habenero:
			return Recipe(
				transformation: Transformation(grainPresence.sharedPresence, .warhol(.habenero)),
				output: .warhol(.habenero)
			)
		}
	}
}

private extension CGAffineTransform {
	init(rotationAngle: CGFloat, anchor: CGPoint) {
		self.init(
			a: cos(rotationAngle),
			b: sin(rotationAngle),
			c: -sin(rotationAngle),
			d: cos(rotationAngle),
			tx: anchor.x - anchor.x * cos(rotationAngle) + anchor.y * sin(rotationAngle),
			ty: anchor.y - anchor.x * sin(rotationAngle) - anchor.y * cos(rotationAngle)
		)
	}
}

private extension BrowserCameraColorVector {
	var ciVector: CIVector {
		CIVector(x: x, y: y, z: z, w: w)
	}
}

private extension BrowserCameraPipelineGrainPresence {
	var sharedPresence: GrainPresence {
		switch self {
		case .none:
			.none
		case .normal:
			.normal
		case .high:
			.high
		}
	}
}

private extension BrowserCameraWarholTransformation {
	var sharedTransformation: WarholTransformation {
		switch self {
		case .bubblegum:
			.bubblegum
		case .darkroom:
			.darkroom
		case .glowInTheDark:
			.glowInTheDark
		case .habenero:
			.habenero
		}
	}
}
