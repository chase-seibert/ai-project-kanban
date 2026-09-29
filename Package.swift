// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StageChase",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "StageChaseCore", targets: ["StageChaseCore"])
    ],
    targets: [
        .target(name: "StageChaseCore"),
        .testTarget(name: "StageChaseCoreTests", dependencies: ["StageChaseCore"])
    ]
)
