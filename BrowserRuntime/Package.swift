// swift-tools-version: 6.2

import PackageDescription

let package = Package(
	name: "BrowserRuntime",
	platforms: [
		.macOS(.v14),
	],
	products: [
		.library(name: "BrowserRuntime", targets: ["BrowserRuntime"]),
	],
	dependencies: [
		.package(path: "../Vendors"),
		.package(path: "../MiumKit"),
		.package(path: "../ModelKit"),
	],
	targets: [
		.target(
			name: "BrowserRuntime",
			dependencies: [
				.product(name: "Vendors", package: "Vendors"),
				.product(name: "MiumKit", package: "MiumKit"),
				.product(name: "ModelKit", package: "ModelKit"),
			]
		),
		.testTarget(
			name: "BrowserRuntimeTests",
			dependencies: ["BrowserRuntime"]
		),
	]
)
