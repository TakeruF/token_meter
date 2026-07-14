// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TokenMeterCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TokenMeterCore", targets: ["TokenMeterCore"])
    ],
    targets: [
        .target(
            name: "TokenMeterCore",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")],
            linkerSettings: [.linkedFramework("Security")]
        ),
        .testTarget(
            name: "TokenMeterCoreTests",
            dependencies: ["TokenMeterCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
