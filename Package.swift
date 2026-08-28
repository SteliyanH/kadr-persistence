// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KadrPersistence",
    // Matches kadr's floor. Nothing here is platform-specific — the format is
    // plain values — but a package that cannot resolve against kadr is useless.
    platforms: [.iOS(.v17), .macOS(.v14), .tvOS(.v17), .visionOS(.v1)],
    products: [
        .library(name: "KadrPersistence", targets: ["KadrPersistence"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SteliyanH/kadr.git", .upToNextMinor(from: "0.21.0")),
    ],
    targets: [
        .target(
            name: "KadrPersistence",
            dependencies: [.product(name: "Kadr", package: "kadr")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(name: "KadrPersistenceTests", dependencies: ["KadrPersistence"]),
    ]
)
