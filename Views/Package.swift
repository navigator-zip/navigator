// swift-tools-version: 6.2

import PackageDescription

let package = Package(
	name: "Views",
	platforms: [
		.macOS(.v14),
	],
	products: [
		.library(
			name: "Views",
			targets: ["Views"]
		),
	],
	dependencies: [
		.package(path: "../BrandColors"),
		.package(path: "../Helpers"),
	],
	targets: [
		.target(
			name: "Views",
			dependencies: [
				"BrandColors",
				"Helpers",
			]
		),
	]
)
