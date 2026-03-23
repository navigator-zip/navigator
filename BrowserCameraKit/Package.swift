// swift-tools-version: 6.2

import PackageDescription

let package = Package(
	name: "BrowserCameraKit",
	platforms: [
		.macOS(.v14),
	],
	products: [
		.library(
			name: "BrowserCameraKit",
			targets: ["BrowserCameraKit"]
		),
	],
	dependencies: [
		.package(path: "../ModelKit"),
		.package(path: "../Vendor/AperturePackages/Pipeline"),
		.package(path: "../Vendor/AperturePackages/Shared"),
	],
	targets: [
		.target(
			name: "BrowserCameraKit",
			dependencies: [
				.product(name: "ModelKit", package: "ModelKit"),
				.product(name: "Pipeline", package: "Pipeline"),
				.product(name: "Shared", package: "Shared"),
			],
			sources: [
				"BrowserCameraLiveCaptureClient.swift",
				"BrowserCameraCaptureController.swift",
				"BrowserCameraFrameProcessor.swift",
				"BrowserCameraPipelineDescriptor.swift",
				"BrowserCameraRenderingContext.swift",
				"BrowserCameraSessionCoordinator.swift",
				"BrowserCameraVirtualExtensionRuntimeStateStore.swift",
				"BrowserCameraVirtualFrameRing.swift",
				"BrowserCameraVirtualOutputFrame.swift",
				"BrowserCameraVirtualPublisher.swift",
				"BrowserCameraVirtualTransportClient.swift",
				"LiveBrowserCameraVirtualPublisher.swift",
			]
		),
		.testTarget(
			name: "BrowserCameraKitTests",
			dependencies: ["BrowserCameraKit"]
		),
	]
)
