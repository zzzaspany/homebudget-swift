// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HomeBudgetCore",
    products: [
        .library(name: "HomeBudgetCore", targets: ["HomeBudgetCore"])
    ],
    targets: [
        .target(name: "HomeBudgetCore"),
        .testTarget(name: "HomeBudgetCoreTests", dependencies: ["HomeBudgetCore"]),
    ]
)
