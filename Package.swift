// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SynheartSession",
    platforms: [
        .iOS(.v13),
        .macOS(.v13),
        // .v8 not .v6: the SynheartSessionHealthKit + SynheartSessionWear
        // targets depend on synheart-wear-swift which itself declares
        // .watchOS(.v8). Leaving this at .v6 caused SwiftPM to fail with
        // "package product 'SynheartWear' requires minimum platform version
        // 8.0 for the watchOS platform, but this target supports 6.0" the
        // moment a consumer pulled SessionHealthKit on a real watchOS app
        // (e.g. apps/synheart_life/ios/LifeWatch).
        .watchOS(.v8)
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
