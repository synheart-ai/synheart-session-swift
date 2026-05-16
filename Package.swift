// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SynheartSession",
    platforms: [
        .iOS(.v13),
        .macOS(.v13),
        .watchOS(.v6)
    ],
    products: [
        .library(name: "SynheartSession", targets: ["SynheartSession"]),
        .library(name: "SynheartSessionWear", targets: ["SynheartSessionWear"]),
        .library(name: "SynheartSessionHealthKit", targets: ["SynheartSessionHealthKit"]),
        .library(name: "SynheartSessionBehavior", targets: ["SynheartSessionBehavior"]),
    ],
    dependencies: [
        .package(url: "https://github.com/synheart-ai/synheart-wear-swift.git", from: "0.4.0"),
        .package(url: "https://github.com/synheart-ai/synheart-behavior-swift.git", from: "0.3.0"),
    ],
    targets: [
        .target(name: "SynheartSession", dependencies: []),
        .target(name: "SynheartSessionWear", dependencies: [
            "SynheartSession",
            .product(name: "SynheartWear", package: "synheart-wear-swift"),
        ]),
        .target(name: "SynheartSessionHealthKit", dependencies: [
            "SynheartSession",
            .product(name: "SynheartWear", package: "synheart-wear-swift"),
        ]),
        .target(name: "SynheartSessionBehavior", dependencies: [
            "SynheartSession",
            .product(name: "SynheartBehavior", package: "synheart-behavior-swift"),
        ]),
        .testTarget(name: "SynheartSessionTests", dependencies: ["SynheartSession"]),
        .testTarget(name: "SynheartSessionHealthKitTests", dependencies: [
            "SynheartSessionHealthKit",
            "SynheartSession",
            .product(name: "SynheartWear", package: "synheart-wear-swift"),
        ]),
        .testTarget(name: "SynheartSessionBehaviorTests", dependencies: [
            "SynheartSessionBehavior",
            "SynheartSession",
            .product(name: "SynheartBehavior", package: "synheart-behavior-swift"),
        ]),
    ]
)
