// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EmbyVideoPlayer",
    platforms: [
        .iOS(.v16),
        .tvOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "EmbyVideoPlayer", targets: ["EmbyVideoPlayer"]),
        .executable(name: "EmbyVideoPlayerApp", targets: ["EmbyVideoPlayerApp"])
    ],
    dependencies: [
            // MobileVLCKit for LibVLC - using official SPM package
            .package(url: "https://github.com/videolan/MobileVLCKit.git", from: "3.6.0"),
        // Kingfisher for image loading
        .package(url: "https://github.com/onevcat/Kingfisher.git", from: "7.0.0"),
    ],
    targets: [
        .target(
                    name: "EmbyVideoPlayer",
                    dependencies: [
                        .product(name: "MobileVLCKit", package: "libvlc-ios"),
                        .product(name: "Kingfisher", package: "Kingfisher"),
                    ],
                    path: "Sources",
                    resources: []
                ),
        .executableTarget(
            name: "EmbyVideoPlayerApp",
            dependencies: ["EmbyVideoPlayer"],
            path: "App"
        ),
        .testTarget(
            name: "EmbyVideoPlayerTests",
            dependencies: ["EmbyVideoPlayer"],
            path: "Tests"
        ),
    ]
)