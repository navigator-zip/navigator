// swift-tools-version: 6.2

import PackageDescription

let package = Package(
	name: "BrowserActionBar",
	platforms: [
		.macOS(.v14),
	],
	products: [
		.library(name: "BrowserActionBar", targets: ["BrowserActionBar"]),
	],
	dependencies: [
		.package(path: "../Aesthetics"),
		.package(path: "../Vendors"),
	],
	targets: [
		.target(
			name: "BrowserActionBar",
			dependencies: [
				.product(name: "Aesthetics", package: "Aesthetics"),
				.product(name: "Vendors", package: "Vendors"),
			],
			resources: [
				.process("Resources"),
			]
		),
		.testTarget(
			name: "BrowserActionBarTests",
			dependencies: ["BrowserActionBar"]
		),
	]
)
