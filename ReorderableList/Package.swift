// swift-tools-version: 6.2

import PackageDescription

let package = Package(
	name: "ReorderableList",
	platforms: [
		.macOS(.v14),
	],
	products: [
		.library(
			name: "ReorderableList",
			targets: ["ReorderableList"]
		),
	],
	dependencies: [
		.package(path: "../Aesthetics"),
		.package(path: "../Vendors"),
	],
	targets: [
		.target(
			name: "ReorderableList",
			dependencies: [
				.product(name: "Aesthetics", package: "Aesthetics"),
				.product(name: "Vendors", package: "Vendors"),
			],
			resources: [
				.process("Resources"),
			]
		),
		.testTarget(
			name: "ReorderableListTests",
			dependencies: [
				"ReorderableList",
				.product(name: "Aesthetics", package: "Aesthetics"),
			]
		),
	]
)
