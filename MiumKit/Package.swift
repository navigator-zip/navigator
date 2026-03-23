// swift-tools-version: 6.2

import PackageDescription

let package = Package(
	name: "MiumKit",
	platforms: [
		.macOS(.v14),
	],
	products: [
		.library(name: "MiumKit", targets: ["MiumKit"]),
	],
	targets: [
		.target(
			name: "MiumKit",
			path: "Sources/MiumKit",
			exclude: [
				"Vendor/CEF",
			],
			publicHeadersPath: "include",
			cSettings: [
				.headerSearchPath("Vendor/CEF"),
				.headerSearchPath("Vendor/CEF/include"),
				.define("MIUM_CEF_BRIDGE_TESTING", .when(configuration: .debug)),
			],
			cxxSettings: [
				.headerSearchPath("Vendor/CEF"),
				.headerSearchPath("Vendor/CEF/include"),
				.headerSearchPath("include"),
				.define("MIUM_CEF_BRIDGE_TESTING", .when(configuration: .debug)),
				.unsafeFlags(["-std=gnu++20"]),
			],
			linkerSettings: [
				.linkedFramework("Foundation"),
				.linkedFramework("AppKit"),
			]
		),
		.testTarget(
			name: "MiumKitTests",
			dependencies: ["MiumKit"],
			path: "Tests/MiumKitTests",
			cSettings: [
				.define("MIUM_CEF_BRIDGE_TESTING"),
				.headerSearchPath("../../Sources/MiumKit/Vendor/CEF"),
				.headerSearchPath("../../Sources/MiumKit/Vendor/CEF/include"),
			],
			cxxSettings: [
				.define("MIUM_CEF_BRIDGE_TESTING"),
				.headerSearchPath("../../Sources/MiumKit/Vendor/CEF"),
				.headerSearchPath("../../Sources/MiumKit/Vendor/CEF/include"),
				.unsafeFlags(["-std=gnu++20"]),
			],
			linkerSettings: [
				.linkedFramework("AppKit"),
				.linkedFramework("Foundation"),
				.linkedFramework("XCTest"),
			]
		),
	]
)
