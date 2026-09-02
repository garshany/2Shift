// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TwoShift",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "TwoShiftCore", targets: ["TwoShiftCore"]),
        .executable(name: "TwoShift", targets: ["TwoShift"]),
        .executable(name: "TwoShiftCoreCheck", targets: ["TwoShiftCoreCheck"])
    ],
    targets: [
        .target(name: "TwoShiftCore"),
        .executableTarget(
            name: "TwoShift",
            dependencies: ["TwoShiftCore"]
        ),
        .executableTarget(
            name: "TwoShiftCoreCheck",
            dependencies: ["TwoShiftCore"]
        )
    ]
)
