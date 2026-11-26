// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "iPhoneMirror",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "mirrorctl", targets: ["mirrorctl"]),
        .library(name: "MirrorKit", targets: ["MirrorKit"]),
    ],
    targets: [
        .target(name: "MirrorKit"),
        .executableTarget(name: "mirrorctl", dependencies: ["MirrorKit"]),
    ]
)
