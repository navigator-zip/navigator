// swift-tools-version: 5.9

import PackageDescription

let package = Package(
	name: "Aesthetics",
	platforms: [
		.iOS(.v15),
		.macOS(.v14),
	],
	products: [
		.library(
			name: "Aesthetics",
			targets: ["Aesthetics"]
		),
	],
	targets: [
		.target(
			name: "Aesthetics",
			resources: [
				.process("Resources"),
			]
		),
		.testTarget(
			name: "AestheticsTests",
			dependencies: ["Aesthetics"]
		),
	]
)
