// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FinanceCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "FinanceCore", targets: ["FinanceCore"]),
        .executable(name: "FinanceCoreDemo", targets: ["FinanceCoreDemo"])
    ],
    targets: [
        .target(name: "FinanceCore"),
        .executableTarget(
            name: "FinanceCoreDemo",
            dependencies: ["FinanceCore"]
        ),
        .testTarget(
            name: "FinanceCoreTests",
            dependencies: ["FinanceCore"],
            resources: [.process("Fixtures")]
        )
    ]
)
