import AVFoundation
@testable import BrowserCameraKit
import CoreImage
import CoreVideo
import ModelKit
import XCTest

final class BrowserCameraFrameProcessorTests: XCTestCase {
	func testFrameProcessorWarmsApertureStyleProfilesAndLoadsInitialDataOnce() throws {
		var loadInitialDataCount = 0
		var primedFilters = [BrowserCameraPipelineFilterName]()
		let processor = LiveBrowserCameraFrameProcessor(
			environment: makeEnvironment(
				loadInitialPipelineData: {
					loadInitialDataCount += 1
				},
				makeFilter: { filterName in
					primedFilters.append(filterName)
					return CIFilter(name: filterName.rawValue)
				}
			)
		)

		try processor.warmIfNeeded(for: .mononoke)
		try processor.warmIfNeeded(for: .folia)
		try processor.warmIfNeeded(for: .mononoke)

		XCTAssertEqual(loadInitialDataCount, 1)
		XCTAssertGreaterThanOrEqual(
			primedFilters.filter { $0 == .photoEffectMono }.count,
			1
		)
		XCTAssertGreaterThanOrEqual(
			primedFilters.filter { $0 == .colorMatrix }.count,
			1
		)
	}

	func testFrameProcessorAllowsPassthroughPresetWhenApertureBootstrapDataIsUnavailable() throws {
		let processor = LiveBrowserCameraFrameProcessor(
			environment: makeEnvironment(
				loadInitialPipelineData: {
					struct TestFailure: Error {}
					throw TestFailure()
				},
				makeFilter: { filterName in
					CIFilter(name: filterName.rawValue)
				}
			)
		)

		let processedFrame = try processor.process(
			pixelBuffer: makePixelBuffer(),
			preset: .none,
			devicePosition: .front
		)

		XCTAssertGreaterThanOrEqual(processedFrame.processingLatency, 0)
		XCTAssertEqual(processedFrame.pipelineRuntimeState.implementation, .passthrough)
		XCTAssertEqual(processedFrame.pipelineRuntimeState.warmupProfile, .passthrough)
	}

	func testFrameProcessorFallsBackToNavigatorFiltersWhenApertureBootstrapDataIsUnavailable() throws {
		let processor = LiveBrowserCameraFrameProcessor(
			environment: makeEnvironment(
				loadInitialPipelineData: {
					struct TestFailure: Error {}
					throw TestFailure()
				},
				processWithAperture: { _, _, _ in
					XCTFail("Aperture processing should not run after bootstrap loading fails.")
					return nil
				},
				makeFilter: { filterName in
					CIFilter(name: filterName.rawValue)
				}
			)
		)

		let processedFrame = try processor.process(
			pixelBuffer: makePixelBuffer(),
			preset: .folia,
			devicePosition: .front
		)

		XCTAssertGreaterThanOrEqual(processedFrame.processingLatency, 0)
		XCTAssertEqual(processedFrame.pipelineRuntimeState.implementation, .navigatorFallback)
		XCTAssertEqual(processedFrame.pipelineRuntimeState.warmupProfile, .chromaticFolia)
	}

	func testFrameProcessorWarmsAndProcessesEveryPreset() throws {
		let processor = LiveBrowserCameraFrameProcessor()
		let pixelBuffer = try makePixelBuffer()

		for preset in BrowserCameraFilterPreset.allCases {
			try processor.warmIfNeeded(for: preset)
			let processedFrame = try processor.process(
				pixelBuffer: pixelBuffer,
				preset: preset,
				devicePosition: .front
			)
			XCTAssertGreaterThanOrEqual(processedFrame.processingLatency, 0)
			XCTAssertGreaterThan(processedFrame.previewImage.width, 0)
			XCTAssertEqual(processedFrame.pipelineRuntimeState.preset, preset)
		}
	}

	func testLivePixelBufferFactoryCreatesIOSurfaceBackedBuffers() {
		let pixelBuffer = LiveBrowserCameraFrameProcessor.Environment.live().makePixelBuffer(32, 32)

		XCTAssertNotNil(pixelBuffer)
		XCTAssertNotNil(pixelBuffer.flatMap(CVPixelBufferGetIOSurface))
	}

	func testFrameProcessorHandlesMononokeForBackCameraPosition() throws {
		let processor = LiveBrowserCameraFrameProcessor()
		let pixelBuffer = try makePixelBuffer()

		let processedFrame = try processor.process(
			pixelBuffer: pixelBuffer,
			preset: .mononoke,
			devicePosition: .back
		)

		XCTAssertGreaterThanOrEqual(processedFrame.processingLatency, 0)
		XCTAssertGreaterThan(processedFrame.previewImage.height, 0)
		XCTAssertEqual(processedFrame.pipelineRuntimeState.warmupProfile, .monochromatic)
	}

	func testFrameProcessorCapsPreviewAndOutputRenderSize() throws {
		let processor = LiveBrowserCameraFrameProcessor()
		let pixelBuffer = try makePixelBuffer(width: 3840, height: 2160)

		let processedFrame = try processor.process(
			pixelBuffer: pixelBuffer,
			preset: .none,
			devicePosition: .front
		)

		XCTAssertEqual(processedFrame.previewImage.width, 1280)
		XCTAssertEqual(processedFrame.previewImage.height, 720)
		XCTAssertEqual(processedFrame.pixelWidth, 1280)
		XCTAssertEqual(processedFrame.pixelHeight, 720)
	}

	func testFrameProcessorReportsRenderFailureWhenRendererReturnsNil() throws {
		let processor = LiveBrowserCameraFrameProcessor(
			environment: makeEnvironment(
				render: { _, _, _ in
					nil
				},
				makeFilter: { filterName in
					CIFilter(name: filterName.rawValue)
				}
			)
		)
		let pixelBuffer = try makePixelBuffer()

		XCTAssertThrowsError(
			try processor.process(
				pixelBuffer: pixelBuffer,
				preset: .folia,
				devicePosition: .unspecified
			)
		) { error in
			XCTAssertEqual(
				error as? BrowserCameraFrameProcessingError,
				.renderFailed(description: "Unable to render the processed camera frame.")
			)
		}
	}

	func testFrameProcessorFallsBackWhenNamedFilterCannotBeCreated() throws {
		let processor = LiveBrowserCameraFrameProcessor(
			environment: makeEnvironment(
				render: { context, image, extent in
					context.createCGImage(image, from: extent)
				},
				makeFilter: { filterName in
					filterName == .photoEffectMono ? nil : CIFilter(name: filterName.rawValue)
				}
			)
		)

		XCTAssertGreaterThanOrEqual(
			try processor.process(
				pixelBuffer: makePixelBuffer(),
				preset: .mononoke,
				devicePosition: .unspecified
			).processingLatency,
			0
		)
	}

	func testFrameProcessorFallsBackWhenFilterOutputImageIsNil() throws {
		let processor = LiveBrowserCameraFrameProcessor(
			environment: makeEnvironment(
				render: { context, image, extent in
					context.createCGImage(image, from: extent)
				},
				makeFilter: { filterName in
					filterName == .photoEffectMono ? NilOutputFilter() : CIFilter(name: filterName.rawValue)
				}
			)
		)

		XCTAssertGreaterThanOrEqual(
			try processor.process(
				pixelBuffer: makePixelBuffer(),
				preset: .mononoke,
				devicePosition: .unspecified
			).processingLatency,
			0
		)
	}

	func testFrameProcessorFallsBackWhenNoiseTransformStagesProduceNoOutput() throws {
		let pixelBuffer = try makePixelBuffer()

		let invertFailureProcessor = LiveBrowserCameraFrameProcessor(
			environment: makeEnvironment(
				render: { context, image, extent in
					context.createCGImage(image, from: extent)
				},
				makeFilter: { filterName in
					switch filterName {
					case .colorInvert:
						NilOutputFilter()
					case .randomGenerator:
						RandomImageFilter()
					default:
						PassthroughFilter()
					}
				}
			)
		)
		let colorMatrixFailureProcessor = LiveBrowserCameraFrameProcessor(
			environment: makeEnvironment(
				render: { context, image, extent in
					context.createCGImage(image, from: extent)
				},
				makeFilter: { filterName in
					switch filterName {
					case .colorMatrix:
						NilOutputFilter()
					case .randomGenerator:
						RandomImageFilter()
					default:
						PassthroughFilter()
					}
				}
			)
		)
		let blendFailureProcessor = LiveBrowserCameraFrameProcessor(
			environment: makeEnvironment(
				render: { context, image, extent in
					context.createCGImage(image, from: extent)
				},
				makeFilter: { filterName in
					switch filterName {
					case .multiplyBlendMode:
						NilOutputFilter()
					case .randomGenerator:
						RandomImageFilter()
					default:
						PassthroughFilter()
					}
				}
			)
		)

		XCTAssertGreaterThanOrEqual(
			try invertFailureProcessor.process(
				pixelBuffer: pixelBuffer,
				preset: .mononoke,
				devicePosition: .unspecified
			).processingLatency,
			0
		)
		XCTAssertGreaterThanOrEqual(
			try colorMatrixFailureProcessor.process(
				pixelBuffer: pixelBuffer,
				preset: .mononoke,
				devicePosition: .unspecified
			).processingLatency,
			0
		)
		XCTAssertGreaterThanOrEqual(
			try blendFailureProcessor.process(
				pixelBuffer: pixelBuffer,
				preset: .mononoke,
				devicePosition: .unspecified
			).processingLatency,
			0
		)
	}

	func testFrameProcessorBuildsSyntheticNoisePipelineWhenAllStagesProduceOutput() throws {
		let processor = LiveBrowserCameraFrameProcessor(
			environment: makeEnvironment(
				render: { context, image, extent in
					context.createCGImage(image, from: extent)
				},
				makeFilter: { filterName in
					switch filterName {
					case .randomGenerator:
						RandomImageFilter()
					default:
						PassthroughFilter()
					}
				}
			)
		)

		XCTAssertGreaterThanOrEqual(
			try processor.process(
				pixelBuffer: makePixelBuffer(),
				preset: .vertichrome,
				devicePosition: .unspecified
			).processingLatency,
			0
		)
	}

	func testFrameProcessorFallsBackToLocalSupergoldRecipeWhenApertureOutputUnavailable() throws {
		let processor = LiveBrowserCameraFrameProcessor(
			environment: makeEnvironment(
				render: { context, image, extent in
					context.createCGImage(image, from: extent)
				},
				processWithAperture: { _, _, _ in
					nil
				},
				makeFilter: { filterName in
					CIFilter(name: filterName.rawValue)
				}
			)
		)

		let processedFrame = try processor.process(
			pixelBuffer: makePixelBuffer(),
			preset: .supergold,
			devicePosition: .unspecified
		)

		XCTAssertGreaterThanOrEqual(processedFrame.processingLatency, 0)
		XCTAssertEqual(processedFrame.pipelineRuntimeState.implementation, .navigatorFallback)
		XCTAssertEqual(processedFrame.pipelineRuntimeState.warmupProfile, .chromaticSupergold)
	}

	func testFrameProcessorUsesApertureDitheringTransformerWhenFallingBackLocally() throws {
		let processor = LiveBrowserCameraFrameProcessor(
			environment: makeEnvironment(
				loadInitialPipelineData: {
					struct TestFailure: Error {}
					throw TestFailure()
				},
				render: { context, image, extent in
					context.createCGImage(image, from: extent)
				},
				processWithAperture: { _, _, _ in
					XCTFail("Aperture processing should not run after bootstrap loading fails.")
					return nil
				},
				makeFilter: { filterName in
					return CIFilter(name: filterName.rawValue)
				}
			)
		)

		let processedFrame = try processor.process(
			pixelBuffer: makePixelBuffer(),
			preset: .dither,
			devicePosition: .unspecified
		)

		XCTAssertGreaterThanOrEqual(processedFrame.processingLatency, 0)
		XCTAssertEqual(processedFrame.pipelineRuntimeState.implementation, .navigatorFallback)
		XCTAssertEqual(processedFrame.pipelineRuntimeState.warmupProfile, .dither)
		XCTAssertGreaterThan(processedFrame.previewImage.width, 0)
	}

	func testFrameProcessorPrefersApertureProcessingWhenAvailable() throws {
		let expectedExtent = CGRect(x: 0, y: 0, width: 8, height: 6)
		let processor = LiveBrowserCameraFrameProcessor(
			environment: makeEnvironment(
				render: { context, image, extent in
					XCTAssertEqual(extent.integral, expectedExtent)
					return context.createCGImage(image, from: extent)
				},
				processWithAperture: { _, preset, devicePosition in
					XCTAssertEqual(preset, .folia)
					XCTAssertEqual(devicePosition, .front)
					return CIImage(color: .red).cropped(to: expectedExtent)
				},
				makeFilter: { filterName in
					CIFilter(name: filterName.rawValue)
				}
			)
		)

		let frame = try processor.process(
			pixelBuffer: makePixelBuffer(),
			preset: .folia,
			devicePosition: .front
		)

		XCTAssertEqual(frame.previewImage.width, Int(expectedExtent.width))
		XCTAssertEqual(frame.previewImage.height, Int(expectedExtent.height))
		XCTAssertGreaterThan(CVPixelBufferGetDataSize(frame.pixelBuffer), 0)
		XCTAssertEqual(frame.pixelWidth, Int(expectedExtent.width))
		XCTAssertEqual(frame.pixelHeight, Int(expectedExtent.height))
		XCTAssertEqual(frame.pipelineRuntimeState.implementation, .aperture)
		XCTAssertEqual(frame.pipelineRuntimeState.warmupProfile, .chromaticFolia)
	}

	func testApertureProcessingReturnsNilForChromaticOutputFailure() {
		let inputImage = CIImage(color: .blue).cropped(to: CGRect(x: 0, y: 0, width: 11, height: 7))

		let outputImage = BrowserCameraApertureProcessing.process(
			image: inputImage,
			preset: .folia,
			devicePosition: .front,
			makeMonochromaticOutput: { _, _ in
				XCTFail("Chromatic preset should not use the monochromatic output factory.")
				return nil
			},
			makeChromaticOutput: { _, _ in
				nil
			}
		)

		XCTAssertNil(outputImage)
	}

	func testApertureProcessingReturnsNilForMonochromaticOutputFailure() {
		let inputImage = CIImage(color: .green).cropped(to: CGRect(x: 0, y: 0, width: 9, height: 5))

		let outputImage = BrowserCameraApertureProcessing.process(
			image: inputImage,
			preset: .mononoke,
			devicePosition: .back,
			makeMonochromaticOutput: { _, _ in
				nil
			},
			makeChromaticOutput: { _, _ in
				XCTFail("Monochromatic preset should not use the chromatic output factory.")
				return nil
			}
		)

		XCTAssertNil(outputImage)
	}

	private func makePixelBuffer(width: Int = 32, height: Int = 32) throws -> CVPixelBuffer {
		var pixelBuffer: CVPixelBuffer?
		let status = CVPixelBufferCreate(
			kCFAllocatorDefault,
			width,
			height,
			kCVPixelFormatType_32BGRA,
			[
				kCVPixelBufferCGImageCompatibilityKey: true,
				kCVPixelBufferCGBitmapContextCompatibilityKey: true,
			] as CFDictionary,
			&pixelBuffer
		)
		guard status == kCVReturnSuccess, let pixelBuffer else {
			throw XCTSkip("Unable to create a test pixel buffer.")
		}

		CVPixelBufferLockBaseAddress(pixelBuffer, [])
		defer {
			CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
		}

		guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
			throw XCTSkip("Unable to access the test pixel buffer.")
		}
		memset(baseAddress, 0x7F, CVPixelBufferGetDataSize(pixelBuffer))
		return pixelBuffer
	}

	private func makeEnvironment(
		loadInitialPipelineData: @escaping () throws -> Void = {},
		render: @escaping (CIContext, CIImage, CGRect) -> CGImage? = { context, image, extent in
			context.createCGImage(image, from: extent)
		},
		makePixelBuffer: @escaping @Sendable (Int, Int) -> CVPixelBuffer? = { width, height in
			var pixelBuffer: CVPixelBuffer?
			let status = CVPixelBufferCreate(
				kCFAllocatorDefault,
				width,
				height,
				kCVPixelFormatType_32BGRA,
				[
					kCVPixelBufferCGImageCompatibilityKey: true,
					kCVPixelBufferCGBitmapContextCompatibilityKey: true,
					kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
				] as CFDictionary,
				&pixelBuffer
			)
			guard status == kCVReturnSuccess else { return nil }
			return pixelBuffer
		},
		renderToPixelBuffer: @escaping (CIContext, CIImage, CVPixelBuffer) -> Void = { context, image, pixelBuffer in
			context.render(image, to: pixelBuffer)
		},
		processWithAperture: @escaping (CIImage, BrowserCameraFilterPreset, AVCaptureDevice.Position)
			-> CIImage? = { _, _, _ in
				nil
			},
		makeFilter: @escaping (BrowserCameraPipelineFilterName) -> CIFilter?
	) -> LiveBrowserCameraFrameProcessor.Environment {
		.init(
			makeContext: {
				BrowserCameraRenderingContext.shared
			},
			render: render,
			makePixelBuffer: makePixelBuffer,
			renderToPixelBuffer: renderToPixelBuffer,
			loadInitialPipelineData: loadInitialPipelineData,
			processWithAperture: processWithAperture,
			makeFilter: makeFilter
		)
	}
}

private final class NilOutputFilter: CIFilter {
	override func setValue(_ value: Any?, forKey key: String) {
		switch key {
		case kCIInputImageKey, kCIInputBackgroundImageKey, kCIInputColorKey, kCIInputIntensityKey, "inputAVector":
			return
		default:
			super.setValue(value, forKey: key)
		}
	}

	override var outputImage: CIImage? {
		nil
	}
}

private final class PassthroughFilter: CIFilter {
	private var inputImage: CIImage?

	override func setValue(_ value: Any?, forKey key: String) {
		if key == kCIInputImageKey || key == kCIInputBackgroundImageKey {
			inputImage = value as? CIImage
		}
	}

	override var outputImage: CIImage? {
		inputImage
	}
}

private final class RandomImageFilter: CIFilter {
	override var outputImage: CIImage? {
		CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 32, height: 32))
	}
}
