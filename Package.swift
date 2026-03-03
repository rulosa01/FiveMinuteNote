// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FiveMinuteNote",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "FiveMinuteNote",
            path: "FiveMinuteNote",
            exclude: ["Info.plist", "FiveMinuteNote.entitlements"]
        ),
    ]
)
