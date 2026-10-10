// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "RecorgiCapture",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RecorgiCapture", targets: ["RecorgiCapture"])
    ],
    dependencies: [
        .package(path: "../RecorgiCore")
    ],
    targets: [
        .target(name: "RecorgiCapture", dependencies: ["RecorgiCore"])
    ]
)
