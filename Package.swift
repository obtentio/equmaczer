// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "equmaczer",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        // Swift Atomics for thread-safe atomic operations in real-time audio
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0")
    ],
    targets: [
        .target(name: "AudioTransportAtomics", path: "support/AudioTransportAtomics", publicHeadersPath: "include"),
        .executableTarget(
            name: "equmaczer",
            dependencies: [
                "AudioTransportAtomics",
                .product(name: "Atomics", package: "swift-atomics")
            ],
            path: "src",
            exclude: ["app/Info.plist"]
        ),
        .target(name: "RecordingAllocationProbe", path: "tests/support/RecordingAllocationProbe", publicHeadersPath: "include"),
        .testTarget(
            name: "equmaczerTests",
            dependencies: ["equmaczer", "RecordingAllocationProbe"],
            path: "tests",
            exclude: ["support"]
        )
    ]
)
