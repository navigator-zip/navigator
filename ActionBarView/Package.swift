// swift-tools-version: 6.2

import PackageDescription

let package = Package(
	name: "ActionBarView",
	platforms: [
		.macOS(.v14),
	],
	products: [
		.library(name: "ActionBarView", targets: ["ActionBarView"]),
	],
	dependencies: [
	],
	targets: [
		.target(
			name: "ActionBarView",
			dependencies: [
			]
		),
		.testTarget(
			name: "ActionBarViewTests",
			dependencies: ["ActionBarView"]
		),
	]
)
