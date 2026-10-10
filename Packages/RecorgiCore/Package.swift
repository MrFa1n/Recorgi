// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "RecorgiCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "RecorgiCore", targets: ["RecorgiCore"])
    ],
    targets: [
        .target(name: "RecorgiCore")
    ]
)
