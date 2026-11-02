// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "d_zero_sensor",
    platforms: [
        .macOS("12.0")
    ],
    products: [
        .library(name: "d-zero-sensor", targets: ["d_zero_sensor"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "d_zero_sensor",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            path: "Sources/d_zero_sensor",
            resources: [],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("."),
                .headerSearchPath("include/d_zero_sensor")
            ]
        )
    ],
    cxxLanguageStandard: .cxx17
)
