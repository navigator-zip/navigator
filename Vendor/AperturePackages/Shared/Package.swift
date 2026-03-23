// swift-tools-version: 5.8

import PackageDescription

let package = Package(
	name: "Shared",
	platforms: [
		.iOS(.v16),
		.macOS(.v12),
	],
	products: [
		.library(
			name: "Shared",
			targets: ["Shared"]
		),
	],
	targets: [
		.target(
			name: "Shared",
			dependencies: [],
			path: "Sources/Shared",
			sources: [
				"ChromaticTransformation.swift",
				"GrainPresence.swift",
				"Quantization.swift",
				"WarholTransformation.swift",
			],
			swiftSettings: [
				.unsafeFlags(["-Xfrontend", "-application-extension"]),
			],
			linkerSettings: [
				.unsafeFlags(["-Xlinker", "-application_extension"]),
			]
		),
	]
)
