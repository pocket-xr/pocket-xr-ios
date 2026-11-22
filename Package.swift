// swift-tools-version:5.10
// Pocket XR for iPhone and iPad: the shared core and Moonlight's stream core as a Swift package. The app itself is an
// Xcode project made by XcodeGen from project.yml (see README), which uses these.
import Foundation
import PackageDescription

// The three copies of Moonlight's stream core are made by scripts/gen-moonlight.sh (on a Mac, before a build of the
// app); without them the package still builds the core and its tests.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let haveMoonlight = FileManager.default.fileExists(atPath: root + "/Sources/CMoonlight1/include/CMoonlight1.h")

var targets: [Target] = [
    // Glasses, head tracking, the control link and the Space's maths. Pure Swift and Foundation; most of it copied
    // from Pocket XR for Mac (pocket-xr-mac at 4c9d588, Sources/PocketXRCore) so the two stay the same.
    .target(name: "PocketXRCore", path: "Sources/PocketXRCore"),
    // A stand-in for the glasses' sensor stream on TCP 52998, for testing the app in the iOS Simulator.
    .executableTarget(name: "FakeGlasses", dependencies: ["PocketXRCore"], path: "Tools/FakeGlasses"),
    .testTarget(name: "PocketXRCoreTests", dependencies: ["PocketXRCore"], path: "Tests/PocketXRCoreTests"),
    // What the three copies share: the interface Swift sees and the AES-GCM hook.
    .target(name: "CMoonlightShared", path: "Native/shared"),
]
var products: [Product] = [.library(name: "PocketXRCore", targets: ["PocketXRCore"])]

if haveMoonlight {
    let mc = "src/moonlight-common-c"
    for i in 1...3 {
        targets.append(.target(
            name: "CMoonlight\(i)",
            dependencies: ["CMoonlightShared"],
            path: "Sources/CMoonlight\(i)",
            cSettings: [
                .headerSearchPath("src"), .headerSearchPath("\(mc)/src"), .headerSearchPath("\(mc)/enet/include"),
                .headerSearchPath("\(mc)/nanors"), .headerSearchPath("\(mc)/nanors/deps"),
                .headerSearchPath("\(mc)/nanors/deps/obl"),
                .define("NDEBUG"), .define("HAS_SOCKLEN_T", to: "1"), .define("HAS_FCNTL", to: "1"),
                .define("HAS_IOCTL", to: "1"), .define("HAS_POLL", to: "1"), .define("HAS_GETADDRINFO", to: "1"),
                .define("HAS_GETNAMEINFO", to: "1"), .define("HAS_INET_PTON", to: "1"), .define("HAS_INET_NTOP", to: "1"),
                .define("HAS_MSGHDR_FLAGS", to: "1"), .unsafeFlags(["-w"]),
            ],
            linkerSettings: [.linkedFramework("Security")]
        ))
    }
    products.append(.library(name: "PXRMoonlight", targets: ["CMoonlightShared", "CMoonlight1", "CMoonlight2", "CMoonlight3"]))
} else {
    products.append(.library(name: "PXRMoonlight", targets: ["CMoonlightShared"]))
}

let package = Package(
    name: "PocketXRCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: products,
    targets: targets
)
