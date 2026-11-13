import Foundation

/// Pure rules deciding which completed tasks appear in the active list.
///
/// Visibility is derived from timestamps and preferences at render time. Nothing is
/// moved or deleted at midnight: hiding a completed task never touches its record.
public enum TaskVisibility {
    /// The moment a completed task leaves the active list, or `nil` if it never does
    /// (incomplete tasks, or the "forever" setting).
    public static func hideDate(for task: TaskItem, options: TaskDisplayOptions, calendar: Calendar) -> Date? {
        guard let completedAt = task.completedAt, let days = options.retention.days else { return nil }
        let reference = options.reference == .completion ? completedAt : task.createdAt
        switch options.calculation {
        case .calendar:
            // Local calendar boundaries. Adding days to the start of day (rather than
            // adding 24h) keeps this correct across daylight-saving transitions.
            let startOfDay = calendar.startOfDay(for: reference)
            return calendar.date(byAdding: .day, value: days, to: startOfDay)
        case .relative:
            // Elapsed time: exactly 24 hours per day, regardless of clock changes.
            return reference.addingTimeInterval(TimeInterval(days) * 86_400)
        }
    }

    public static func isVisible(_ task: TaskItem, now: Date, options: TaskDisplayOptions, calendar: Calendar) -> Bool {
        guard task.isCompleted else { return true }
        guard let hide = hideDate(for: task, options: options, calendar: calendar) else { return true }
        return now < hide
    }

    /// The next instant after `now` at which the active list could change on its own:
    /// the earliest pending hide date, or the next midnight (the heading date changes).
    public static func nextChange(after now: Date, tasks: [TaskItem], options: TaskDisplayOptions, calendar: Calendar) -> Date {
        let midnight = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(86_400)
        var next = midnight
        for task in tasks where task.isCompleted {
            if let hide = hideDate(for: task, options: options, calendar: calendar), hide > now, hide < next {
                next = hide
            }
        }
        return next
    }

    /// Completed tasks finished before this date can never be visible under `options`;
    /// used to keep the in-memory working set small. `nil` means "load everything".
    public static func loadCutoff(now: Date, options: TaskDisplayOptions, calendar: Calendar) -> Date? {
        guard let days = options.retention.days else { return nil }
        // One extra day of slack covers calendar rounding and DST.
        let start = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -(days + 1), to: start)
    }
}

/// The ordered rows shown in the main window.
public struct TaskLayout: Equatable, Sendable {
    /// Rows above the divider (all rows when completed tasks stay in position).
    public var primary: [TaskItem]
    /// Completed rows below the divider; always empty in stay-in-position mode.
    public var completed: [TaskItem]

    public var isEmpty: Bool { primary.isEmpty && completed.isEmpty }

    /// - Parameter settling: recently completed tasks that should keep their place for a
    ///   moment so the completion animation is visible before they move.
    public static func make(
        tasks: [TaskItem],
        options: TaskDisplayOptions,
        now: Date,
        calendar: Calendar,
        settling: Set<UUID> = []
    ) -> TaskLayout {
        let visible = tasks.filter {
            settling.contains($0.id) || TaskVisibility.isVisible($0, now: now, options: options, calendar: calendar)
        }
        switch options.placement {
        case .stayInPosition:
            return TaskLayout(primary: visible.sorted(by: byPosition), completed: [])
        case .moveToBottom:
            let primary = visible
                .filter { !$0.isCompleted || settling.contains($0.id) }
                .sorted(by: byPosition)
            let completed = visible
                .filter { $0.isCompleted && !settling.contains($0.id) }
                .sorted { a, b in
                    // Completion order, newest at the bottom.
                    if a.completedAt != b.completedAt { return a.completedAt! < b.completedAt! }
                    return byPosition(a, b)
                }
            return TaskLayout(primary: primary, completed: completed)
        }
    }

    private static func byPosition(_ a: TaskItem, _ b: TaskItem) -> Bool {
        if a.position != b.position { return a.position < b.position }
        return a.createdAt < b.createdAt
    }
}
