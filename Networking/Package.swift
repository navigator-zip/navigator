// swift-tools-version: 6.2

import PackageDescription

let package = Package(
	name: "Networking",
	platforms: [
		.macOS(.v14),
	],
	products: [
		.library(
			name: "Networking",
			targets: ["Networking"]
		),
	],
	dependencies: [
		.package(path: "../Vendors"),
	],
	targets: [
		.target(
			name: "Networking",
			dependencies: [
				.product(name: "Vendors", package: "Vendors"),
			]
		),
		.testTarget(
			name: "NetworkingTests",
			dependencies: ["Networking"]
		),
	]
)
