// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "d_zero_terminal",
    platforms: [
        .macOS("12.0")
    ],
    products: [
        .library(name: "d-zero-terminal", targets: ["d_zero_terminal"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "d_zero_terminal",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            path: "Sources/d_zero_terminal",
            resources: [],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("."),
                .headerSearchPath("include/d_zero_terminal")
            ]
        )
    ],
    cxxLanguageStandard: .cxx17
)
