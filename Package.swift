// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "local-echo",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "LocalEchoLib",
            path: "Sources/LocalEchoLib",
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AppKit"),
            ]
        ),
        .executableTarget(
            name: "local-echo",
            dependencies: ["LocalEchoLib"],
            path: "Sources/LocalEcho"
        ),
        .testTarget(
            name: "LocalEchoTests",
            dependencies: ["LocalEchoLib"],
            path: "Tests/LocalEchoTests"
        ),
    ]
)
