import Foundation
@testable import StillCore

/// A controllable clock for date-dependent tests.
final class TestClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

func calendar(_ identifier: String = "Europe/London") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: identifier)!
    calendar.locale = Locale(identifier: "en_GB")
    return calendar
}

func date(_ string: String, _ cal: Calendar = calendar()) -> Date {
    let formatter = DateFormatter()
    formatter.calendar = cal
    formatter.timeZone = cal.timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.date(from: string)!
}

@MainActor
func makeStore(
    path: String = ":memory:",
    clock: TestClock = TestClock(date("2026-10-08 09:00")),
    calendar cal: Calendar = calendar(),
    options: TaskDisplayOptions = TaskDisplayOptions()
) throws -> TaskStore {
    let repository = try TaskRepository(database: Database(path: path))
    let undo = UndoManager()
    undo.groupsByEvent = false
    return try TaskStore(repository: repository, options: options, undoManager: undo, calendar: cal, clock: { clock.now })
}

extension TaskStore {
    /// Wraps a mutation in its own undo group, as one user event would be.
    func step(_ body: (TaskStore) throws -> Void) rethrows {
        undoManager.beginUndoGrouping()
        defer { undoManager.endUndoGrouping() }
        try body(self)
    }

    func titles(now: Date) -> [String] {
        let layout = layout(now: now)
        return (layout.primary + layout.completed).map(\.title)
    }
}

func temporaryDatabasePath() -> String {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("StillTests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("Tasks.sqlite").path
}
