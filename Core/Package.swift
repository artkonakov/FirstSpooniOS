// swift-tools-version: 5.10
// Бизнес-правила «Ложку за маму» — чистый Swift (только Foundation), без UIKit/SwiftUI/GRDB.
// Перенесены один в один из Android (`domain/*`). Тесты: `swift test` в этой папке.
import PackageDescription

let package = Package(
    name: "FirstSpoonCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FirstSpoonCore", targets: ["FirstSpoonCore"]),
    ],
    targets: [
        .target(
            name: "FirstSpoonCore",
            // Склонение имён: petrovich-rules (MIT), копия `shared/petrovich/` из репозитория Android.
            // Алгоритмы рекомендаций: копия `shared/recommendation/` (Android).
            resources: [.copy("Resources/petrovich-rules.json"), .copy("Resources/PETROVICH-LICENSE"),
                        .copy("Resources/recommendation")]
        ),
        .testTarget(
            name: "FirstSpoonCoreTests",
            dependencies: ["FirstSpoonCore"],
            exclude: ["Resources"]
        ),
    ]
)
