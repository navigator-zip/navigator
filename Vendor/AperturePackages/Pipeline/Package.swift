// swift-tools-version: 5.8

import PackageDescription

let package = Package(
	name: "Pipeline",
	platforms: [
		.iOS(.v16),
		.macOS(.v12),
	],
	products: [
		.library(
			name: "Pipeline",
			targets: ["Pipeline"]
		),
	],
	dependencies: [
		.package(name: "Shared", path: "../Shared"),
	],
	targets: [
		.target(
			name: "Pipeline",
			dependencies: [
				.product(name: "Shared", package: "Shared"),
			],
			path: "Sources/Pipeline",
			sources: [
				"CIFilters.swift",
				"Errors.swift",
				"Filters.swift",
				"LUT+Folia.swift",
				"LUT+Helpers.swift",
				"LUT+Mononoke.swift",
				"LUT+MononokeFront.swift",
				"LUT+MononokeFrontTwo.swift",
				"LUT+Supergold.swift",
				"LUT+Vertichrome.swift",
				"Transformation.swift",
				"Transformers/CubeTransformer.swift",
				"Transformers/DitheringTransformer.swift",
				"Transformers/PolynomialTransformer.swift",
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
