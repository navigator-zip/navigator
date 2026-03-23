// swift-tools-version: 6.2

import PackageDescription

let package = Package(
	name: "CookiesInterop",
	platforms: [
		.macOS(.v14),
	],
	products: [
		.library(name: "CookiesInterop", targets: ["CookiesInterop"]),
	],
	dependencies: [
		.package(path: "../Vendors"),
	],
	targets: [
		.target(
			name: "CookiesInterop",
			dependencies: [
				.product(name: "Vendors", package: "Vendors"),
			]
		),
		.testTarget(
			name: "CookiesInteropTests",
			dependencies: ["CookiesInterop"]
		),
	]
)
