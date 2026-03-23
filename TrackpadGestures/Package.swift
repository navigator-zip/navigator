// swift-tools-version: 6.2

import PackageDescription

let package = Package(
	name: "TrackpadGestures",
	platforms: [
		.macOS(.v14),
	],
	products: [
		.library(
			name: "TrackpadGestures",
			targets: ["TrackpadGestures"]
		),
	],
	targets: [
		.target(
			name: "TrackpadGestures"
		),
		.testTarget(
			name: "TrackpadGesturesTests",
			dependencies: ["TrackpadGestures"],
			resources: [
				.process("Fixtures"),
			]
		),
	]
)
