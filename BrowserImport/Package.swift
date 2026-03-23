// swift-tools-version: 6.2

import PackageDescription

let package = Package(
	name: "BrowserImport",
	platforms: [
		.macOS(.v14),
	],
	products: [
		.library(
			name: "BrowserImport",
			targets: ["BrowserImport"]
		),
	],
	dependencies: [
		.package(path: "../ModelKit"),
	],
	targets: [
		.target(
			name: "BrowserImport",
			dependencies: [
				.product(name: "ModelKit", package: "ModelKit"),
			]
		),
		.testTarget(
			name: "BrowserImportTests",
			dependencies: ["BrowserImport"]
		),
	]
)
