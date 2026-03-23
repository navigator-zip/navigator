// swift-tools-version: 6.2

import PackageDescription

let package = Package(
	name: "BrowserSidebar",
	platforms: [
		.macOS(.v14),
	],
	products: [
		.library(name: "BrowserSidebar", targets: ["BrowserSidebar"]),
	],
	dependencies: [
		.package(path: "../Aesthetics"),
		.package(path: "../BrowserCameraKit"),
		.package(path: "../ModelKit"),
		.package(path: "../ReorderableList"),
		.package(path: "../Vendors"),
	],
	targets: [
		.target(
			name: "BrowserSidebar",
			dependencies: [
				.product(name: "Aesthetics", package: "Aesthetics"),
				.product(name: "BrowserCameraKit", package: "BrowserCameraKit"),
				.product(name: "ModelKit", package: "ModelKit"),
				.product(name: "ReorderableList", package: "ReorderableList"),
				.product(name: "Vendors", package: "Vendors"),
			],
			resources: [
				.process("Resources"),
			]
		),
		.testTarget(
			name: "BrowserSidebarTests",
			dependencies: [
				"BrowserSidebar",
				.product(name: "Aesthetics", package: "Aesthetics"),
				.product(name: "BrowserCameraKit", package: "BrowserCameraKit"),
			]
		),
	]
)
