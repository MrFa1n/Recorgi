// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "RecorgiUI",
    platforms: [.macOS(.v14)],
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
