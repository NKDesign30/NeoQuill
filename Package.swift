// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NeoQuill",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "NeoQuill",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
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
