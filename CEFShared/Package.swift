// swift-tools-version: 6.2

import PackageDescription

let package = Package(
	name: "CEFShared",
	platforms: [
		.macOS("14.0"),
	],
	products: [
		.library(
			name: "CEFShared",
			targets: ["CEFShared"]
		),
	],
	targets: [
		.target(
			name: "CEFShared",
			path: "Sources/CEFShared"
		),
		.testTarget(
			name: "CEFSharedTests",
			dependencies: ["CEFShared"],
			path: "Tests/CEFSharedTests"
		),
	]
)
