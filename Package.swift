// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KDCalendar",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "KDCalendar",
            targets: ["KDCalendar"]
        )
    ],
    targets: [
        .target(
            name: "KDCalendar",
            path: "KDCalendar/CalendarView",
            sources: [
                "."
            ],
            swiftSettings: [
                .define("KDCALENDAR_EVENT_MANAGER_ENABLED"),
            ]
        )
    ]
)
