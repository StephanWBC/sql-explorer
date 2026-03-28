// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SQLExplorer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SQLExplorer", targets: ["SQLExplorer"])
    ],
    dependencies: [
        .package(url: "https://github.com/AzureAD/microsoft-authentication-library-for-objc", from: "1.6.0"),
    ],
    targets: [
        // System library: FreeTDS headers (installed via Homebrew)
        .systemLibrary(
            name: "CFreeTDS",
            path: "Sources/CFreeTDS",
            providers: [.brew(["freetds"])]
        ),
        // C shim: exposes FreeTDS macros as functions callable from Swift
        .target(
            name: "CFreeTDSShim",
            dependencies: ["CFreeTDS"],
            path: "Sources/CFreeTDSShim",
            cSettings: [
                .unsafeFlags(["-I/opt/homebrew/include"]),
            ],
            linkerSettings: [
                .unsafeFlags(["-L/opt/homebrew/lib"]),
                .linkedLibrary("sybdb"),
            ]
        ),
        // Main app
        .executableTarget(
            name: "SQLExplorer",
            dependencies: [
                "CFreeTDS",
                "CFreeTDSShim",
                .product(name: "MSAL", package: "microsoft-authentication-library-for-objc"),
            ],
            path: "SQLExplorer",
            swiftSettings: [
                .unsafeFlags(["-I/opt/homebrew/include"]),
            ],
            linkerSettings: [
                .unsafeFlags(["-L/opt/homebrew/lib"]),
                .linkedLibrary("sybdb"),
            ]
        ),
        .testTarget(
            name: "SQLExplorerTests",
            dependencies: ["SQLExplorer"],
            path: "SQLExplorerTests"
        ),
    ]
)
