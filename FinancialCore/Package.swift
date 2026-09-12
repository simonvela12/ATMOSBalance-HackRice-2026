// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FinancialCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "FinancialCore", targets: ["FinancialCore"]),
        .executable(name: "FinancialCoreDemo", targets: ["FinancialCoreDemo"])
    ],
    targets: [
        .target(name: "FinancialCore"),
        .executableTarget(
            name: "FinancialCoreDemo",
            dependencies: ["FinancialCore"]
        ),
        .testTarget(
            name: "FinancialCoreTests",
            dependencies: ["FinancialCore"]
        )
    ]
)
