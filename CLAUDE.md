# Project Instructions for AI Agents

This file provides instructions and context for AI coding agents working on this project.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:1105d646 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/core-concepts/sync-concepts.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->


## Build & Test

Requires Xcode 26 and an iOS 26 simulator. CI (`.github/workflows/ci.yml`) runs the same four steps.

```bash
# Test the package (Swift Testing, KDCalendarTests)
xcodebuild -scheme KDCalendar-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# Build the DocC documentation for both products
xcodebuild docbuild -scheme KDCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild docbuild -scheme KDCalendarEventKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Build the example app
xcodebuild -project Example/KDCalendarDemo.xcodeproj -scheme KDCalendarDemo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO build

# Lint (must pass with no warnings)
xcrun swift-format lint --strict --recursive Sources Tests Example/KDCalendarDemo
scripts/lint-open-documentation.sh   # swift-format skips `open` declarations
```

When several worktrees test at once, give each its own simulator (see `bd memories simulator`):
`xcrun simctl create <name> 'iPhone 17 Pro'`, test with `-destination id=<udid>`, delete it afterwards.

The demo app (`com.karmadust.KDCalendarDemo`) takes two launch arguments: `-tab N` opens tab N
(0 classic, 1 default style, 2 SwiftUI) and `-sampleEvents` seeds events without asking for
calendar access. For example `xcrun simctl launch booted com.karmadust.KDCalendarDemo -tab 2 -sampleEvents`.

## Architecture Overview

A Swift package (`Package.swift`, Swift 6 language mode, iOS 17+) with two products; CocoaPods
mirrors them as the `Core` and `EventKit` subspecs of `KDCalendar.podspec`.

- **`KDCalendar`** (`Sources/KDCalendar`): the calendar view, UIKit first.
  - `CalendarView.swift`: `CalendarView` (a `UIView` around a paging `UICollectionView`): its
    state, setup, layout and right-to-left handling, and the grid it reads from (`reloadData()`,
    `refreshSnapshot()`).
  - `CalendarView+Selection.swift`: the public selection API and the collection view's selection
    callbacks. `CalendarView+Scrolling.swift`: `setDisplayDate`, the next and previous month, the
    scroll callbacks and the month notification. `CalendarView+DataSource.swift`: the cells.
  - `CalendarEvent.swift`, `CalendarViewDataSource.swift` and `CalendarViewDelegate.swift`: the
    event type and the two protocols with their default implementations.
  - `MonthGrid.swift`: `MonthGrid`, the pure date engine. It turns the data source's range, the
    calendar and the first weekday into months of 7 × 6 cells with no UIKit involved.
    `Calendar+Fixed.swift` pins an autoupdating calendar.
  - `EventIndex.swift`: `EventIndex`, the events on each cell of a `MonthGrid`, also pure.
  - `CalendarSnapshot.swift`: `CalendarSnapshot`, the grid, today's cell and the event index built
    by one pure initialiser from the range, calendar, first weekday, events and the time. The view
    keeps one, `refreshSnapshot()` rebuilds it once per reload (reusing the grid and index when the
    inputs did not change), and every reader uses it; no computed property asks the data source.
  - `SelectionState.swift`: the selected days and the rules of the selection modes, kept as
    start-of-day dates so they survive any rebuild of the grid.
  - `CalendarView+Style.swift`: `CalendarView.Style`, a value type; assigning it restyles the view.
  - `CalendarView+Formatters.swift`, `CalendarDayCell.swift` (one `DayCellConfiguration` per
    cell), `CalendarHeaderView.swift`, `CalendarFlowLayout.swift`.
  - `CalendarView+SwiftUI.swift`: `KDCalendarView`, a `UIViewRepresentable` with a selection binding.
  - `Resources/Localizable.xcstrings`, `PrivacyInfo.xcprivacy`, and the DocC catalog
    `KDCalendar.docc` (overview and the 1.x migration guide).
- **`KDCalendarEventKit`** (`Sources/KDCalendarEventKit/EventsManager.swift`): the optional
  EventKit bridge. An `EventsManager` wraps one `CalendarEventStore` (`EventsManager.shared` the
  system `EKEventStore`, a fake in tests); `CalendarView.eventsManager` picks the one its
  `loadEvents()`, `addEvent` and `saveEvent` use.
- **`Tests/KDCalendarTests`**: Swift Testing suites. `EngineTests` (dates, DST, calendars),
  `SelectionStateTests` (no view), `CalendarViewTests`, `ScrollingTests`, `PlatformTests`,
  `EventKitTests` (fake store) and `IssueTests` (named after the GitHub issues they close).
  `TestSupport.swift` holds what they share: `UTCDates` (`utc`, `date(_:_:_:)`) and
  `CalendarFixture` (a window per suite, `makeCalendar` with defaulted style parameters, `cell`,
  `FixedDataSource` and `RecordingDelegate`). Add set-up there rather than to one suite.
- **`Example/KDCalendarDemo.xcodeproj`**: the demo app, consuming the package by local path.

## Conventions & Patterns

- Swift 6 strict concurrency. Views and their API are main-actor isolated; public value types are
  `Sendable`.
- Every date the view computes or hands out is the start of a day in `CalendarView.calendar`
  (`Style.resolvedCalendar`). Never assume Gregorian, UTC or a Sunday first weekday.
- Keep date logic in `MonthGrid`, `EventIndex` and `CalendarSnapshot` and selection logic in
  `SelectionState`, all testable without a view; `CalendarView` wires them to UIKit and the delegate.
- Errors are explicit: APIs throw (`EventsManagerError` or the store's own error) rather than
  return `Bool` or swallow with `try?`; the `Bool` forms remain only for 1.x compatibility.
- Formatting is `swift-format` with the repo's `.swift-format` (4 spaces, 120 columns, ordered
  imports); `lint --strict` must pass.
- Public API gets `///` documentation with DocC symbol links (``` ``CalendarView/style`` ```),
  protocol witnesses included; the lint enforces it (`scripts/lint-open-documentation.sh` for
  `open` declarations, which swift-format skips). The first sentence stands alone as the summary,
  followed by a blank `///` line before any discussion.
- Tests use Swift Testing (`@Test`, `#expect`); suites that lay out views are
  `@Suite(.serialized) @MainActor`.
- A file header, where there is one, is the MIT notice (see `CalendarView.swift`); files without
  one are covered by `LICENSE`. Don't add Xcode's `//  Created by` template header.
- User-visible changes go in `CHANGELOG.md` under `[Unreleased]` (Keep a Changelog). CocoaPods
  gets no releases after 2.0.1, so `KDCalendar.podspec` stays at that version.

## API Conventions

Public API follows the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
The rules this codebase applies, for new names and for any name a change touches:

- Booleans read as assertions about the receiver: `is…`, `has…`, `allows…`, `shows…`, `marks…`
  (`allowsDeselection`, `marksWeekends`, `hasFullAccess`), not `enable…`, `force…` or `show…`.
- Name by role, not type: no `String`, `Options` or `Info` suffix that only repeats the type, no
  `get` prefix, and no implementation words such as `Cached` in public names.
- Spell words out (`backgroundView`, `label`, `isRightToLeft`); acronyms are uniformly cased
  (`LTR`, not `Ltr`).
- Every public declaration has a `///` comment that starts with a one-line summary fragment, then
  `- Parameter`, `- Returns` and `- Throws` where they add information. A computed property that
  is not O(1) or has side effects says so.
- Name closure parameters in public signatures:
  `(_ date: Date, _ events: [CalendarEvent]) -> Void`, not `(Date, [CalendarEvent]) -> Void`.
- Prefer one method with defaulted parameters to a family of overloads, with the defaults last.
- Keep Cocoa precedent where UIKit sets it: delegate method shapes
  (`calendar(_:didSelectDate:withEvents:)`), `setX(_:animated:)`, `isScrollEnabled`.

Names that predate these rules (`enableDeselection`, `forceLtr`, `showAdjacentDays`,
`getCachedSectionInfo(_:)`) stay for 1.x compatibility until their renames land; the
`api-guidelines` beads track them. Don't copy them into new API.

## Concurrency Conventions

The package is source-distributed and not built for library evolution, so the rules that matter
are the source-compatibility ones from the Swift 6 migration guide; binary compatibility doesn't
apply. A change to public API in 2.x must not break a caller that compiles today:

- Adding `@MainActor` to a public protocol, type or function, `@Sendable` to a public function
  type, or a `Sendable` requirement to a generic parameter is source-breaking. In 2.x stage it with
  `@preconcurrency`; make it plain only in a major release.
- Adding `Sendable` to a public concrete type, or `sending` to a result, is compatible; adding
  `sending` to a parameter is not.
- Public value types state `Sendable` explicitly: public types don't get it inferred.
- No `nonisolated(unsafe)` or `@unchecked Sendable` without a comment naming what synchronises the
  state.
- `MainActor.assumeIsolated` only where the callback is guaranteed to run on the main thread, with
  a comment saying why (the `NotificationCenter` observers in `CalendarView.swift` use
  `queue: .main`).
- Work that must leave the main actor is `@concurrent`, not merely `nonisolated async`: under
  `NonisolatedNonsendingByDefault` a `nonisolated async` function runs on its caller's actor.
  `@concurrent` needs Swift 6.2 while the tools version is 6.0, so wrap it in `#if compiler(>=6.2)`.
