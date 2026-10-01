#!/bin/bash
# Runs the checks CI runs: swift-format lint, the package tests, the documentation build for both
# products and the example app build. `scripts/check.sh quick` stops after the tests.
#
# Each checkout (the main one or an Orchestra worktree) gets its own simulator and build folder,
# so checks running side by side do not wait on, or reset, one shared "iPhone 17 Pro".
set -euo pipefail

mode="${1:-full}"
root="$(git rev-parse --show-toplevel)"
cd "$root"

derived_data="$root/.build/check-DerivedData"
log="$root/.build/check.log"
mkdir -p "$root/.build"

# One simulator per checkout, named after its folder, created on first use from the newest
# installed iOS runtime.
simulator_name="KDCalendar check $(basename "$root")"
udid="$(xcrun simctl list devices -j | python3 -c '
import json, sys
name = sys.argv[1]
for devices in json.load(sys.stdin)["devices"].values():
    for device in devices:
        if device["name"] == name and device.get("isAvailable", True):
            print(device["udid"]); sys.exit()
' "$simulator_name")"
if [ -z "$udid" ]; then
    runtime="$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
ios = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]]
print(max(ios, key=lambda r: [int(p) for p in r["version"].split(".")])["identifier"])
')"
    udid="$(xcrun simctl create "$simulator_name" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro "$runtime")"
fi
destination="id=$udid"

# Runs a build step quietly, printing its log tail only when it fails.
step() {
    local title="$1"
    shift
    if "$@" >"$log" 2>&1; then
        echo "✔ $title"
    else
        echo "✘ $title failed; the end of $log:"
        grep -E "error:|✘|failed" "$log" | tail -20
        tail -20 "$log"
        exit 1
    fi
}

step "swift-format lint" xcrun swift-format lint --strict --recursive Sources Tests Example/KDCalendarDemo
step "package tests" xcodebuild -scheme KDCalendar-Package -destination "$destination" \
    -derivedDataPath "$derived_data" test
grep -E "Test run with" "$log" | tail -1 || true
[ "$mode" = quick ] && exit 0

for scheme in KDCalendar KDCalendarEventKit; do
    step "documentation for $scheme" xcodebuild docbuild -scheme "$scheme" -destination "$destination" \
        -derivedDataPath "$derived_data"
done
step "example app" xcodebuild -project Example/KDCalendarDemo.xcodeproj -scheme KDCalendarDemo \
    -destination "$destination" -derivedDataPath "$derived_data" CODE_SIGNING_ALLOWED=NO build
