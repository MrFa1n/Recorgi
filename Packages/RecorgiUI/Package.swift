// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "RecorgiUI",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "RecorgiUI", targets: ["RecorgiUI"])
    ],
    dependencies: [
        .package(path: "../RecorgiCore"),
        .package(path: "../RecorgiCapture")
    ],
    targets: [
        .target(name: "RecorgiUI", dependencies: ["RecorgiCore", "RecorgiCapture"])
    ]
)
