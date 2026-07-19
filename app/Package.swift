// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Context",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1"),
    ],
    targets: [
        // Generated UniFFI C header + modulemap (see `just bindings`).
        .target(name: "ContextCoreFFI"),
        // Generated UniFFI Swift bindings.
        .target(name: "ContextCore", dependencies: ["ContextCoreFFI"]),
        .executableTarget(
            name: "Context",
            dependencies: [
                "ContextCore",
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ],
            linkerSettings: [
                .unsafeFlags(["-L", "../core/target/release"]),
                .linkedLibrary("context_core"),
            ]
        ),
        .testTarget(
            name: "ContextTests",
            dependencies: ["Context", "ContextCore"]
        ),
    ]
)
