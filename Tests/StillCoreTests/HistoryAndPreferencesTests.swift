import Foundation
import Testing
@testable import StillCore

@MainActor
@Suite("History")
struct HistoryTests {
    @Test func groupsByCompletionDayAndMonthNewestFirst() throws {
        let clock = TestClock(date("2026-09-30 10:00"))
        let store = try makeStore(clock: clock)
        func complete(_ title: String, at when: String) throws {
            let task = try #require(try store.addTask(title: title))
            clock.now = date(when)
            try store.completeTask(id: task.id)
        }
        try complete("Return library books", at: "2026-09-30 16:00")
        try complete("Call the plumber", at: "2026-10-07 09:00")
        try complete("Pay the electricity bill", at: "2026-10-07 17:00")
        try complete("Buy a birthday card", at: "2026-10-08 11:00")
        try complete("Book the car in for a service", at: "2026-10-08 15:00")

        let months = HistoryGrouping.group(try store.completedTasks(), calendar: calendar())
        #expect(months.count == 2)
        #expect(months[0].days.map { $0.tasks.map(\.title) } == [
            ["Book the car in for a service", "Buy a birthday card"],
            ["Pay the electricity bill", "Call the plumber"],
        ])
        #expect(months[1].days.map { $0.tasks.map(\.title) } == [["Return library books"]])
        #expect(months[0].days[0].day == date("2026-10-08 00:00"))
    }

    @Test func restoringFromHistoryReturnsTheTaskToTheEndOfTheList() throws {
        let clock = TestClock(date("2026-10-01 10:00"))
        let store = try makeStore(clock: clock)
        let old = try #require(try store.addTask(title: "Old"))
        try store.completeTask(id: old.id)
        clock.advance(86_400 * 7)
        try store.reload()
        try store.addTask(title: "Current")
        #expect(store.titles(now: clock.now) == ["Current"])

        try store.restoreTask(id: old.id)
        #expect(store.titles(now: clock.now) == ["Current", "Old"])
        let restored = try #require(try store.task(id: old.id))
        #expect(restored.id == old.id && restored.title == "Old" && !restored.isCompleted)
        #expect(try store.completedTasks().isEmpty)
    }

    @Test func searchMatchesTitleSubstringsCaseInsensitively() throws {
        let clock = TestClock(date("2026-10-08 10:00"))
        let store = try makeStore(clock: clock)
        for title in ["Water the plants", "Call the plumber", "100% done_ok"] {
            let task = try #require(try store.addTask(title: title))
            try store.completeTask(id: task.id)
        }
        #expect(try store.completedTasks(matching: "plants").map(\.title) == ["Water the plants"])
        #expect(try store.completedTasks(matching: "%").map(\.title) == ["100% done_ok"])
        #expect(try store.completedTasks(matching: "_").map(\.title) == ["100% done_ok"])
        #expect(try store.completedTasks(matching: "zzz").isEmpty)
    }

    @Test func pagination() throws {
        let clock = TestClock(date("2026-10-08 10:00"))
        let store = try makeStore(clock: clock)
        for i in 0..<10 {
            let task = try #require(try store.addTask(title: "T\(i)"))
            clock.advance(1)
            try store.completeTask(id: task.id)
        }
        let first = try store.completedTasks(limit: 4)
        let second = try store.completedTasks(limit: 4, offset: 4)
        #expect(first.map(\.title) == ["T9", "T8", "T7", "T6"])
        #expect(second.map(\.title) == ["T5", "T4", "T3", "T2"])
    }
}

@MainActor
@Suite("Preferences")
struct PreferencesTests {
    @Test func defaultsAreSensible() {
        let suite = "StillTests.\(UUID().uuidString)"
        let prefs = Preferences(defaults: UserDefaults(suiteName: suite)!)
        #expect(prefs.placement == .moveToBottom)
        #expect(prefs.retention == .untilTomorrow)
        #expect(prefs.calculation == .calendar)
        #expect(prefs.reference == .completion)
        #expect(prefs.appearance == .system)
        #expect(prefs.keepWindowOnTop == false)
        #expect(prefs.showMenuBarIcon)
        #expect(prefs.hotKey == .default)
        #expect(prefs.hotKeyEnabled)
        UserDefaults().removePersistentDomain(forName: suite)
    }

    @Test func valuesPersistAcrossInstances() {
        let suite = "StillTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        do {
            let prefs = Preferences(defaults: defaults)
            prefs.placement = .stayInPosition
            prefs.retention = .forever
            prefs.calculation = .relative
            prefs.reference = .creation
            prefs.appearance = .dark
            prefs.keepWindowOnTop = true
            prefs.showMenuBarIcon = false
            prefs.hotKey = KeyCombo(keyCode: 49, modifiers: KeyCombo.commandMask | KeyCombo.shiftMask)
            prefs.hotKeyEnabled = false
        }
        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.placement == .stayInPosition)
        #expect(reloaded.retention == .forever)
        #expect(reloaded.calculation == .relative)
        #expect(reloaded.reference == .creation)
        #expect(reloaded.appearance == .dark)
        #expect(reloaded.keepWindowOnTop)
        #expect(!reloaded.showMenuBarIcon)
        #expect(reloaded.hotKey == KeyCombo(keyCode: 49, modifiers: KeyCombo.commandMask | KeyCombo.shiftMask))
        #expect(!reloaded.hotKeyEnabled)
        UserDefaults().removePersistentDomain(forName: suite)
    }
}

@MainActor
@Suite("Robustness")
struct RobustnessTests {
    @Test func performanceWithLargeHistory() throws {
        let path = temporaryDatabasePath()
        let repository = try TaskRepository(database: Database(path: path))
        let base = date("2024-01-01 09:00")
        try repository.transaction {
            for i in 0..<20_000 {
                let created = base.addingTimeInterval(Double(i) * 3_600)
                try repository.upsert(TaskItem(
                    title: "Historical task number \(i)",
                    createdAt: created,
                    completedAt: created.addingTimeInterval(600),
                    position: Int64(i)
                ))
            }
            for i in 0..<300 {
                try repository.upsert(TaskItem(title: "Open \(i)", createdAt: base, position: Int64(20_000 + i)))
            }
        }
        let clock = TestClock(date("2026-10-08 10:00"))
        let elapsed = try ContinuousClock().measure {
            let store = try makeStore(path: path, clock: clock)
            #expect(store.layout(now: clock.now).primary.count == 300)
            try store.addTask(title: "One more")
            _ = try store.completedTasks(limit: 200)
            #expect(try store.completedTasks(matching: "number 1999").count == 11)
        }
        #expect(elapsed < .seconds(1), "Opening and querying a large history took \(elapsed)")

        let size = try FileManager.default.attributesOfItem(atPath: path)[.size] as? Int ?? 0
        #expect(size < 4_000_000, "20k tasks used \(size) bytes")
    }

    @Test func newerSchemaIsRefusedNotOverwritten() throws {
        let path = temporaryDatabasePath()
        do {
            let db = try Database(path: path)
            try db.setUserVersion(99)
        }
        #expect(throws: DatabaseError.self) { try TaskRepository(database: Database(path: path)) }
        #expect(try Database(path: path).userVersion == 99)
    }

    @Test func corruptFilesAreReportedNotReplaced() throws {
        let path = temporaryDatabasePath()
        let garbage = Data(repeating: 0xAB, count: 8_192)
        try garbage.write(to: URL(fileURLWithPath: path))
        #expect(throws: DatabaseError.self) { try TaskRepository(database: Database(path: path)) }
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == garbage)
    }
}
