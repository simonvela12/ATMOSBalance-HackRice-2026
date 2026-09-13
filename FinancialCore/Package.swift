// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FinancialCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "FinancialCore", targets: ["FinancialCore"])
    ],
    targets: [
        .target(name: "FinancialCore"),
        .testTarget(
            name: "FinancialCoreTests",
            dependencies: ["FinancialCore"]
        )
    ]
)
