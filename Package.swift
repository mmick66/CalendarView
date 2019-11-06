// swift-tools-version:5.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "KDCalendar",
    platforms: [
        .iOS(.v8)
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
