// swift-tools-version: 6.2

import PackageDescription

let package = Package(
	name: "Helpers",
	platforms: [
		.macOS(.v14),
	],
	products: [
		.library(
			name: "Helpers",
			targets: ["Helpers"]
		),
	],
	dependencies: [
		.package(path: "../Vendors"),
	],
	targets: [
		.target(
			name: "Helpers",
			dependencies: ["Vendors"]
		),
	]
)
