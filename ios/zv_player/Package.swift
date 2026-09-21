// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "zv_player",
    platforms: [
        .iOS("12.0")
    ],
    products: [
        .library(name: "zv-player", targets: ["zv_player"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "zv_player",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ]
        )
    ]
)
