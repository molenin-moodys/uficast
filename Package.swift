// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Uficast",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "Uficast", targets: ["Uficast"])],
    targets: [
        .target(name: "UficastCore"),
        .executableTarget(name: "Uficast", dependencies: ["UficastCore"]),
        .testTarget(name: "UficastCoreTests", dependencies: ["UficastCore"]),
    ]
)
