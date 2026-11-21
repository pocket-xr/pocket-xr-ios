// swift-tools-version:5.10
// Pocket XR for iPhone and iPad: the shared core as a Swift package. The app itself is an Xcode project made by
// XcodeGen from project.yml (see README), which uses PocketXRCore from here.
import PackageDescription

let package = Package(
    name: "PocketXRCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PocketXRCore", targets: ["PocketXRCore"]),
    ],
    targets: [
        // Glasses, head tracking, the control link and the Space's maths. Pure Swift and Foundation, copied from
        // Pocket XR for Mac (pocket-xr-mac at 4c9d588, Sources/PocketXRCore) so the two stay the same.
        .target(name: "PocketXRCore", path: "Sources/PocketXRCore"),
        // A stand-in for the glasses' sensor stream on TCP 52998, for testing the app in the iOS Simulator.
        .executableTarget(name: "FakeGlasses", dependencies: ["PocketXRCore"], path: "Tools/FakeGlasses"),
        .testTarget(name: "PocketXRCoreTests", dependencies: ["PocketXRCore"], path: "Tests/PocketXRCoreTests"),
    ]
)
