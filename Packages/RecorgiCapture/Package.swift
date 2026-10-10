// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "RecorgiCapture",
    platforms: [.macOS(.v26)],
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
