// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "d_zero_player",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "d-zero-player", targets: ["d_zero_player"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "d_zero_player",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            path: "Sources/d_zero_player",
            resources: [],
            publicHeadersPath: ".",
            cxxSettings: [
                .headerSearchPath(".")
            ]
        )
    ],
    cxxLanguageStandard: .cxx17
)
