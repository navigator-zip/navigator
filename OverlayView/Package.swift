// swift-tools-version: 6.2

import PackageDescription

let package = Package(
	name: "OverlayView",
	platforms: [
		.macOS(.v14),
	],
	products: [
		.library(
			name: "OverlayView",
			targets: ["OverlayView"]
		),
	],
	dependencies: [
		.package(path: "../Aesthetics"),
		.package(path: "../BrandColors"),
		.package(path: "../Helpers"),
	],
	targets: [
		.target(
			name: "OverlayView",
			dependencies: [
				"Aesthetics",
				"BrandColors",
				"Helpers",
			]
		),
		.testTarget(
			name: "OverlayViewTests",
			dependencies: ["OverlayView"]
		),
	]
)
