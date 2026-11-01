// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenMouse",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "OpenMouse", targets: ["OpenMouse"])],
    targets: [
        .target(name: "OpenMouseCore"),
        .executableTarget(name: "OpenMouse", dependencies: ["OpenMouseCore"]),
        .testTarget(name: "OpenMouseCoreTests", dependencies: ["OpenMouseCore"])
    ]
)
