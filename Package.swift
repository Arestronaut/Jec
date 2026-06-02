// swift-tools-version: 6.2
import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "jec",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .tvOS(.v18),
        .watchOS(.v11),
        .visionOS(.v2),
    ],
    products: [
        .library(name: "jec", targets: ["jec"]),
        .library(name: "jecSwiftUI", targets: ["jecSwiftUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "601.0.0"),
    ],
    targets: [
        .macro(
            name: "jecMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "jec",
            dependencies: ["jecMacros"]
        ),
        .target(
            name: "jecSwiftUI",
            dependencies: ["jec"]
        ),
        .testTarget(
            name: "jecTests",
            dependencies: [
                "jec",
                "jecMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
        .testTarget(
            name: "jecSwiftUITests",
            dependencies: ["jec", "jecSwiftUI"]
        ),
    ]
)
