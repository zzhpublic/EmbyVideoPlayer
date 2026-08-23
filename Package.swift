// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "EmbyVideoPlayer",
    platforms: [
            .iOS(.v16),
            .tvOS(.v16),
            .macOS(.v13),
        ],
    products: [
        .library(name: "EmbyVideoPlayer", targets: ["EmbyVideoPlayer"]),
        .executable(name: "EmbyVideoPlayerApp", targets: ["EmbyVideoPlayerApp"]),
            .executable(name: "EmbyVideoPlayerMacOS", targets: ["EmbyVideoPlayerMacOS"]),
            .executable(name: "EmbyVideoPlayerWindows", targets: ["EmbyVideoPlayerWindows"])
        ],
    dependencies: [
        // VLCKit for all Apple platforms - using official VideoLAN VLCKit (supports iOS, macOS, tvOS)
        .package(url: "https://code.videolan.org/videolan/VLCKit.git", exact: "4.0.0-a22"),
        // Kingfisher for image loading
        .package(url: "https://github.com/onevcat/Kingfisher.git", from: "7.0.0"),
        // libvlc for Windows (when available via SPM)
        // For Windows, we use system libvlc - no SPM package needed
    ],
    targets: [
        .target(
                name: "CLibVLC",
                path: "Sources/CLibVLC",
                publicHeadersPath: ".",
                cSettings: [
            .define("LIBVLC_API_VERSION", to: "3"),
                ]
            ),
            .target(
                name: "EmbyVideoPlayer",
            dependencies: [
                .product(name: "VLCKit", package: "VLCKit", condition: .when(platforms: [.iOS, .tvOS, .macOS])),
                .product(name: "Kingfisher", package: "Kingfisher", condition: .when(platforms: [.iOS, .tvOS, .macOS])),
            .target(name: "CLibVLC", condition: .when(platforms: [.windows])),
                ],
                path: "Sources",
                resources: [],
                swiftSettings: [
            .define("USE_VLCKIT", .when(platforms: [.iOS, .tvOS, .macOS])),
            .define("USE_LIBVLC", .when(platforms: [.windows])),
                ]
            ),
        .executableTarget(
            name: "EmbyVideoPlayerApp",
            dependencies: ["EmbyVideoPlayer"],
            path: "App",
            resources: [
                .copy("Assets.xcassets")
            ]
        ),
        .executableTarget(
            name: "EmbyVideoPlayerMacOS",
            dependencies: ["EmbyVideoPlayer"],
            path: "AppMacOS",
            resources: [
                .copy("Assets.xcassets")
            ]
            ),
            .executableTarget(
                name: "EmbyVideoPlayerWindows",
                dependencies: ["EmbyVideoPlayer"],
                path: "AppWindows"
            )
    ]
)