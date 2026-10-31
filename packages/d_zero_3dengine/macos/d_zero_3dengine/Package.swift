// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "d_zero_3dengine",
    platforms: [
        .macOS("12.0")
    ],
    products: [
        .library(name: "d-zero-3dengine", targets: ["d_zero_3dengine"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "d_zero_3dengine",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            path: "Sources/d_zero_3dengine",
            resources: [],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("."),
                .headerSearchPath("include/d_zero_3dengine")
            ]
        )
    ],
    cxxLanguageStandard: .cxx17
)
