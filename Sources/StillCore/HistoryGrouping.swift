import Foundation

/// History shows tasks that are *currently* completed, grouped by the day they were
/// completed. It is not an event log: restoring a task removes it from history, and
/// completing it again files it under the new completion date.
public struct HistoryDay: Identifiable, Equatable, Sendable {
    public var id: Date { day }
    /// Start of the local calendar day.
    public let day: Date
    public var tasks: [TaskItem]
}

public struct HistoryMonth: Identifiable, Equatable, Sendable {
    public var id: Date { month }
    /// Start of the local calendar month.
    public let month: Date
    public var days: [HistoryDay]
}

public enum HistoryGrouping {
    /// Groups completed tasks into months and days, newest first. Input order within a
    /// day is preserved, so pass tasks sorted by completion date descending.
    public static func group(_ tasks: [TaskItem], calendar: Calendar) -> [HistoryMonth] {
        var months: [HistoryMonth] = []
        for task in tasks {
            guard let completedAt = task.completedAt else { continue }
            let day = calendar.startOfDay(for: completedAt)
            let month = calendar.dateInterval(of: .month, for: completedAt)?.start ?? day

            if months.last?.month != month {
                months.append(HistoryMonth(month: month, days: []))
            }
            let monthIndex = months.count - 1
            if months[monthIndex].days.last?.day != day {
                months[monthIndex].days.append(HistoryDay(day: day, tasks: []))
            }
            let dayIndex = months[monthIndex].days.count - 1
            months[monthIndex].days[dayIndex].tasks.append(task)
        }
        return months
    }
}
