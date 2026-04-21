// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "winmove",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "winmove", targets: ["winmove"])
    ],
    targets: [
        .executableTarget(
            name: "winmove",
            path: "Sources/winmove",
            swiftSettings: [.unsafeFlags(["-Osize"], .when(configuration: .release))]
        )
    ]
)
