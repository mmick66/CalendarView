// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KDCalendar",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "KDCalendar", targets: ["KDCalendar"]),
        .library(name: "KDCalendarEventKit", targets: ["KDCalendarEventKit"]),
    ],
    targets: [
        .target(
            name: "KDCalendar",
            path: "Sources/KDCalendar",
            resources: [.process("Resources")]
        ),
        .target(
            name: "KDCalendarEventKit",
            dependencies: ["KDCalendar"],
            path: "Sources/KDCalendarEventKit"
        ),
        .testTarget(
            name: "KDCalendarTests",
            dependencies: ["KDCalendar", "KDCalendarEventKit"],
            path: "Tests/KDCalendarTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
