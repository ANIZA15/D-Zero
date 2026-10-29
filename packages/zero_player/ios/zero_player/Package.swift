// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "zero_player",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "zero-player", targets: ["zero_player"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "zero_player",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            path: "Sources/zero_player",
            resources: [],
            publicHeadersPath: ".",
            cxxSettings: [
                .headerSearchPath(".")
            ]
        )
    ],
    cxxLanguageStandard: .cxx17
)
