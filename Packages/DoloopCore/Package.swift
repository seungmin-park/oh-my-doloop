// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DoloopCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "DoloopCore", targets: ["DoloopCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.9.0"),
    ],
    targets: [
        .target(
            name: "DoloopCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(
            name: "DoloopCoreTests",
            dependencies: ["DoloopCore", .product(name: "GRDB", package: "GRDB.swift")]
        ),
    ]
)
