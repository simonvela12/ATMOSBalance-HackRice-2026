// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FinanceCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "FinanceCore", targets: ["FinanceCore"])
    ],
    targets: [
        .target(name: "FinanceCore"),
        .testTarget(
            name: "FinanceCoreTests",
            dependencies: ["FinanceCore"],
            resources: [.process("Fixtures")]
        )
    ]
)
