// swift-tools-version: 6.2

import PackageDescription

let package = Package(
	name: "BrowserView",
	platforms: [
		.macOS(.v14),
	],
	products: [
		.library(name: "BrowserView", targets: ["BrowserView"]),
	],
	dependencies: [
		.package(path: "../BrowserCameraKit"),
		.package(path: "../BrowserRuntime"),
		.package(path: "../BrowserSidebar"),
		.package(path: "../ModelKit"),
		.package(path: "../Vendors"),
	],
	targets: [
		.target(
			name: "BrowserView",
			dependencies: [
				.product(name: "BrowserCameraKit", package: "BrowserCameraKit"),
				.product(name: "BrowserRuntime", package: "BrowserRuntime"),
				.product(name: "BrowserSidebar", package: "BrowserSidebar"),
				.product(name: "ModelKit", package: "ModelKit"),
				.product(name: "Vendors", package: "Vendors"),
			],
			resources: [
				.process("Resources"),
			]
		),
		.testTarget(
			name: "BrowserViewTests",
			dependencies: [
				"BrowserView",
				.product(name: "BrowserCameraKit", package: "BrowserCameraKit"),
			]
		),
	]
)
