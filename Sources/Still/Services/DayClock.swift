import AppKit
import Observation

/// Supplies the "current time" that the task list is laid out against.
///
/// Rather than polling, it advances only when something can actually change: a single
/// timer scheduled for the next visibility boundary (the next midnight, or the moment
/// a completed task should be hidden), plus system notifications for day changes,
/// clock or time-zone changes and wake from sleep.
@MainActor
@Observable
final class DayClock {
    private(set) var now = Date()

    /// Returns the next instant the visible list could change, given `now`.
    @ObservationIgnored var nextBoundary: (Date) -> Date = { now in
        Calendar.autoupdatingCurrent.nextDate(
            after: now, matching: DateComponents(hour: 0), matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(3_600)
    }

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        for name in [Notification.Name.NSCalendarDayChanged, .NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        })
    }

    /// Refreshes `now` and schedules the next boundary.
    func tick() {
        now = Date()
        reschedule()
    }

    /// Call when tasks or preferences change, since the next boundary may move.
    func reschedule() {
        timer?.invalidate()
        let fireDate = max(nextBoundary(Date()), Date().addingTimeInterval(1))
        let timer = Timer(fire: fireDate.addingTimeInterval(0.5), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
