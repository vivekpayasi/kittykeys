// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CatkeysCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "KeyboardCore", targets: ["KeyboardCore"]),
        .library(name: "KeyboardUI", targets: ["KeyboardUI"]),
    ],
    targets: [
        .target(
            name: "KeyboardCore",
            resources: [.copy("Layouts"), .copy("Emoji/emoji.json"), .copy("TypingTest/sentences.json")]
        ),
        .target(
            name: "KeyboardUI",
            dependencies: ["KeyboardCore"]
        ),
        .testTarget(
            name: "KeyboardCoreTests",
            dependencies: ["KeyboardCore"]
        ),
    ]
)
