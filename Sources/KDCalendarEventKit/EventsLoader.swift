import Combine
import Foundation
import KDCalendar

/// What an ``EventsLoader`` needs of the view it loads for: the days to load and where the events go.
///
/// `CalendarView` conforms as it is; a test stands in for it without laying out a view.
@MainActor
protocol EventsLoaderHost: AnyObject {
    /// The events the host shows.
    var events: [CalendarEvent] { get set }
    /// The days the host spans, at the start of each day in ``calendar``.
    var dateRange: ClosedRange<Date> { get }
    /// The calendar the host counts its days in.
    var calendar: Calendar { get }
}

extension CalendarView: EventsLoaderHost {}

/// The state of one view's event loads and the rules that tie it together.
///
/// It decides which of several loads may assign its events (the latest to start), keeps the events
/// saved while a load runs, and, when asked to, loads again after the store reports a change. A
/// `CalendarView` keeps one as its only associated object; the loader holds the view weakly.
@MainActor
final class EventsLoader {

    private weak var host: (any EventsLoaderHost)?

    /// The manager the host was given, or `nil` while it uses ``EventsManager/shared``.
    var manager: EventsManager?

    /// Counts the loads started, so that a load can tell whether a later one has superseded it.
    private var latestLoad = 0

    /// The events saved since the latest load started, or `nil` when no load is running.
    ///
    /// The load's query may have run before they were saved, so it keeps the ones its result lacks.
    private var savedDuringLoad: [CalendarEvent]?

    /// Creates the loader of `host`.
    init(host: any EventsLoaderHost) {
        self.host = host
    }

    // MARK: Loading and saving

    /// Loads the events in the host's range from `manager` and assigns them to the host.
    ///
    /// The latest load to start wins however long each query takes. Events saved through
    /// ``save(_:using:)`` while the load runs are kept, whether or not its query found them.
    ///
    /// - Throws: The error ``EventsManager/load(from:to:)`` threw, or `CancellationError` when a
    ///   later load started, or the host went away, before this one finished; the host's events are
    ///   then left alone.
    func load(using manager: EventsManager) async throws {
        latestLoad += 1
        let load = latestLoad
        // A save before this point is in the store when the query runs; a later one may not be.
        savedDuringLoad = []
        // So is a change the observed store has reported, when the query is made of that store.
        if manager.store === observedStore { hasUnloadedStoreChange = false }
        defer {
            if load == latestLoad {
                savedDuringLoad = nil
                // A change reported while this load ran waited for it to end.
                scheduleReload()
            }
        }
        // Read through the weak reference: the host is not kept alive while the query runs.
        guard let range = host?.dateRange, let calendar = host?.calendar else { throw CancellationError() }
        guard let end = calendar.date(byAdding: .day, value: 1, to: range.upperBound) else { return }
        let events = try await manager.load(from: range.lowerBound, to: end)
        // Queries can finish out of order; only the latest load may assign its events.
        guard load == latestLoad, let host else { throw CancellationError() }
        var missing = savedDuringLoad ?? []
        for event in events {
            if let index = missing.firstIndex(of: event) { missing.remove(at: index) }
        }
        host.events = events + missing
        loadedManager = manager
        updateStoreObservation()
    }

    /// Saves `event` through `manager` and adds it to the host's events.
    ///
    /// - Throws: The error ``EventsManager/save(_:)`` threw; the host's events are then left alone.
    func save(_ event: CalendarEvent, using manager: EventsManager) throws {
        try manager.save(event)
        host?.events.append(event)
        savedDuringLoad?.append(event)
    }

    // MARK: Store changes

    /// Whether a change reported by the store of the latest successful load starts another load.
    var reloadsWhenStoreChanges = false {
        didSet { updateStoreObservation() }
    }

    /// How long the loader waits after the store reports a change before it loads again.
    ///
    /// Stores report changes in bursts, as when a calendar syncs; the changes reported during the
    /// wait are answered by the one load that follows it.
    var storeChangeDelay: Duration = .milliseconds(300)

    /// The manager of the latest successful load, whose store the host's events came from.
    private var loadedManager: EventsManager?

    /// The store being observed, or `nil` when none is.
    private var observedStore: (any CalendarEventStore)?

    /// Removes the observer of ``observedStore`` from the notification center when released: on
    /// assigning `nil`, or with the loader when its host goes away.
    private(set) var storeObservation: AnyCancellable?

    /// Whether the store reported a change that no load has started after.
    private var hasUnloadedStoreChange = false

    /// The wait before the load that answers a change.
    private var pendingReload: Task<Void, Never>?

    /// Observes the store of the latest successful load if changes are to be answered, and no
    /// store otherwise.
    private func updateStoreObservation() {
        let store = reloadsWhenStoreChanges ? loadedManager?.store : nil
        guard let store, let name = store.changeNotification else {
            stopObservingStore()
            return
        }
        guard observedStore !== store else { return }
        stopObservingStore()
        let observer = NotificationCenter.default.addObserver(forName: name, object: store, queue: .main) {
            [weak self] _ in
            // `queue: .main` runs the block on the main thread, whichever thread posts.
            MainActor.assumeIsolated { self?.storeDidChange() }
        }
        storeObservation = AnyCancellable { NotificationCenter.default.removeObserver(observer) }
        observedStore = store
    }

    private func stopObservingStore() {
        storeObservation = nil
        observedStore = nil
        hasUnloadedStoreChange = false
        pendingReload?.cancel()
        pendingReload = nil
    }

    private func storeDidChange() {
        hasUnloadedStoreChange = true
        scheduleReload()
    }

    /// Starts the wait for the load that answers a change.
    ///
    /// Does nothing when no change is unanswered, when a wait is already running, so that a burst
    /// of changes starts one load, or when a load is running: its query may have missed the change,
    /// and superseding it would fail a load the app started, so the wait starts when it ends.
    private func scheduleReload() {
        guard hasUnloadedStoreChange, pendingReload == nil, savedDuringLoad == nil else { return }
        let delay = storeChangeDelay
        pendingReload = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            pendingReload = nil
            await reloadForStoreChange()
        }
    }

    /// Loads again from the store that reported a change, without asking for access.
    private func reloadForStoreChange() async {
        // A load that started during the wait either ran its query after the change, and cleared
        // the flag, or is still running and schedules again when it ends.
        guard hasUnloadedStoreChange, savedDuringLoad == nil else { return }
        // Nobody is there to answer a prompt, so the events stay as they are without access.
        guard let manager = loadedManager, manager.hasFullAccess else { return }
        do {
            try await load(using: manager)
        } catch {
            // With access in hand the manager does not throw, which leaves `CancellationError`:
            // the app started a load of its own, or the host went away. Neither needs a report.
        }
    }
}
