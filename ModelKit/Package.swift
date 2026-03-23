// swift-tools-version: 6.2

import PackageDescription

let package = Package(
	name: "ModelKit",
	platforms: [
		.macOS(.v14),
	],
	products: [
		.library(
			name: "ModelKit",
			targets: ["ModelKit"]
		),
	],
	targets: [
		.target(
			name: "ModelKit"
		),
		.testTarget(
			name: "ModelKitTests",
			dependencies: ["ModelKit"]
		),
	]
)
