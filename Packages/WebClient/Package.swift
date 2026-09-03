// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WebClient",
    dependencies: [
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", from: "0.58.0"),
        .package(path: "../HomeBudgetCore"),
    ],
    targets: [
        .executableTarget(
            name: "WebClient",
            dependencies: [
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
                .product(name: "HomeBudgetCore", package: "HomeBudgetCore"),
            ]
        )
    ]
)
