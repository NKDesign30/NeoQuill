// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NeoQuill",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.5.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "NeoQuill",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Sources/NeoQuill",
            resources: [
                .copy("Resources/Fonts"),
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/quill-app-icon.png"),
                .copy("Resources/app-icon-quill.svg"),
                .copy("Resources/pulse-mark.svg"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("EventKit"),
                .linkedFramework("ServiceManagement"),
                .linkedLibrary("sqlite3"),
            ]
        ),
    ]
)
