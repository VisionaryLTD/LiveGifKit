// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LiveGifKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "LiveGifKit",
            targets: ["LiveGifKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "LiveGifKit",
            dependencies: [
                .product(name: "Dependencies", package: "swift-dependencies"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "LiveGifKitTests",
            dependencies: [
                "LiveGifKit",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
    ]
    ,
    swiftLanguageModes: [.v6]
)
