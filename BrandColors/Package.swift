// swift-tools-version: 6.2

import PackageDescription

let package = Package(
	name: "BrandColors",
	platforms: [
		.macOS(.v14),
	],
	products: [
		.library(
			name: "BrandColors",
			targets: ["BrandColors"]
		),
	],
	targets: [
		.target(
			name: "BrandColors"
		),
	]
)
