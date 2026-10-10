// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "RecorgiCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RecorgiCore", targets: ["RecorgiCore"])
    ],
    targets: [
        .target(name: "RecorgiCore")
    ]
)
