// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "See",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "See", targets: ["See"])
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift", from: "0.15.3"),
    ],
    targets: [
        .executableTarget(
            name: "See",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
                .byName(name: "cmark_gfm"),
            ],
            path: "Sources/See"
        ),
        .systemLibrary(
            name: "cmark_gfm",
            path: "Sources/cmark-gfm",
            pkgConfig: "libcmark-gfm"
        ),
    ]
)
