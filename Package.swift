// swift-tools-version: 6.2
import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "Jec",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .tvOS(.v18),
        .watchOS(.v11),
        .visionOS(.v2),
    ],
    products: [
        .library(name: "Jec", targets: ["Jec"]),
        .library(name: "JecSwiftUI", targets: ["JecSwiftUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "601.0.0"),
    ],
    targets: [
        .macro(
            name: "JecMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "Jec",
            dependencies: ["JecMacros"]
        ),
        .target(
            name: "JecSwiftUI",
            dependencies: ["Jec"]
        ),
        .testTarget(
            name: "JecTests",
            dependencies: [
                "Jec",
                .target(name: "JecMacros", condition: .when(platforms: [.macOS])),
                .product(
                    name: "SwiftSyntaxMacrosTestSupport",
                    package: "swift-syntax",
                    condition: .when(platforms: [.macOS])
                ),
            ]
        ),
        .testTarget(
            name: "JecSwiftUITests",
            dependencies: ["Jec", "JecSwiftUI"]
        ),
    ]
)
