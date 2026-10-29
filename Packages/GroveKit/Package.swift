// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GroveKit",
    platforms: [.macOS("26.0")],
    products: [.library(name: "GroveKit", targets: ["GroveKit"])],
    targets: [
        .target(name: "GroveKit"),
        .executableTarget(name: "grove-probe", dependencies: ["GroveKit"]),
        .testTarget(name: "GroveKitTests", dependencies: ["GroveKit"]),
    ]
)
