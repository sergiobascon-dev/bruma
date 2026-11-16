// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Bruma",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Bruma", targets: ["Bruma"])],
    targets: [
        .target(name: "BrumaCore"),
        .executableTarget(name: "Bruma", dependencies: ["BrumaCore"], resources: [.copy("Frost.metal")]),
        .testTarget(name: "BrumaCoreTests", dependencies: ["BrumaCore"])
    ],
    swiftLanguageModes: [.v5]
)
