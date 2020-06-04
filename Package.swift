// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RxComposableArchitecture",
    platforms: [.iOS(.v11)],
    products: [
        .library(
            name: "RxComposableArchitecture",
            targets: ["RxComposableArchitecture"]),
        .library(
            name: "RxComposableArchitectureTestSupport",
            targets: ["RxComposableArchitectureTestSupport"])
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-case-paths", from: "0.1.1"),
        .package(url: "https://github.com/ReactiveX/RxSwift", from: "5.0.0")
    ],
    targets: [
        .target(
            name: "RxComposableArchitecture",
            dependencies: [
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "RxCocoa", package: "RxSwift")
        ]),
        .target(
            name: "RxComposableArchitectureTestSupport",
            dependencies: [
                "RxComposableArchitecture",
            ]
        ),
        .testTarget(
            name: "RxComposableArchitectureTests",
            dependencies: ["RxComposableArchitecture"]),
    ]
)
