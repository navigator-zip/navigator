// swift-tools-version: 6.2

import PackageDescription

let package = Package(
	name: "Vendors",
	defaultLocalization: "",
	platforms: [
		.macOS(.v14),
	],
	products: [
		.library(name: "Vendors", targets: ["Vendors"]),
	],
	dependencies: [
		.package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.11.0"),
		.package(url: "https://github.com/pointfreeco/swift-tagged", from: "0.10.0"),
		.package(url: "https://github.com/krzysztofzablocki/Inject", from: "1.5.2"),
		.package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.2.0"),
		.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
		.package(url: "https://github.com/jtrivedi/Wave", from: "0.3.3"),
		.package(path: "../Aesthetics"),
	],
	targets: [
		.target(
			name: "Vendors",
			dependencies: [
				.product(name: "Aesthetics", package: "Aesthetics"),
				.product(name: "Dependencies", package: "swift-dependencies"),
				.product(name: "DependenciesMacros", package: "swift-dependencies"),
				.product(name: "Sparkle", package: "Sparkle"),
				.product(name: "Tagged", package: "swift-tagged"),
				.product(name: "Sharing", package: "swift-sharing"),
				.product(name: "Inject", package: "Inject"),
				.product(name: "Wave", package: "Wave"),
			]
		),
		.testTarget(
			name: "VendorsTests",
			dependencies: ["Vendors"]
		),
	]
)
