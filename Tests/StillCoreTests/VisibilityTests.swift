import Foundation
import Testing
@testable import StillCore

@Suite("Completed-task visibility")
struct VisibilityTests {
    let london = calendar("Europe/London")

    func completed(at completion: String, created: String? = nil, cal: Calendar? = nil) -> TaskItem {
        let cal = cal ?? london
        return TaskItem(
            title: "Task",
            createdAt: date(created ?? completion, cal),
            completedAt: date(completion, cal),
            position: 1
        )
    }

    func visible(_ task: TaskItem, at now: String, _ options: TaskDisplayOptions, cal: Calendar? = nil) -> Bool {
        let cal = cal ?? london
        return TaskVisibility.isVisible(task, now: date(now, cal), options: options, calendar: cal)
    }

    @Test func untilTomorrowCalendarHidesAtMidnight() {
        let task = completed(at: "2026-10-08 23:50")
        let options = TaskDisplayOptions()
        #expect(visible(task, at: "2026-10-08 23:59", options))
        #expect(!visible(task, at: "2026-10-09 00:00", options))
    }

    @Test func untilTomorrowRelativeKeeps24Hours() {
        let task = completed(at: "2026-10-08 23:50")
        let options = TaskDisplayOptions(calculation: .relative)
        #expect(visible(task, at: "2026-10-09 23:49", options))
        #expect(!visible(task, at: "2026-10-09 23:50", options))
    }

    @Test func sevenDaysCalendar() {
        let task = completed(at: "2026-10-08 10:00")
        let options = TaskDisplayOptions(retention: .sevenDays)
        #expect(visible(task, at: "2026-10-14 23:59", options))
        #expect(!visible(task, at: "2026-10-15 00:00", options))
    }

    @Test func sevenDaysRelative() {
        let task = completed(at: "2026-10-08 10:00")
        let options = TaskDisplayOptions(retention: .sevenDays, calculation: .relative)
        #expect(visible(task, at: "2026-10-15 09:59", options))
        #expect(!visible(task, at: "2026-10-15 10:00", options))
    }

    @Test func foreverNeverHides() {
        let task = completed(at: "2020-01-01 10:00")
        #expect(visible(task, at: "2026-10-08 10:00", TaskDisplayOptions(retention: .forever)))
    }

    @Test func incompleteTasksAreAlwaysVisible() {
        let task = TaskItem(title: "Open", createdAt: date("2019-01-01 10:00"), position: 1)
        for retention in CompletedRetention.allCases {
            for calculation in RetentionCalculation.allCases {
                let options = TaskDisplayOptions(retention: retention, calculation: calculation, reference: .creation)
                #expect(visible(task, at: "2026-10-08 10:00", options))
            }
        }
    }

    @Test func creationReferenceCanHideImmediately() {
        let task = completed(at: "2026-10-08 10:00", created: "2026-10-05 10:00")
        let byCompletion = TaskDisplayOptions()
        let byCreation = TaskDisplayOptions(reference: .creation)
        #expect(visible(task, at: "2026-10-08 10:01", byCompletion))
        #expect(!visible(task, at: "2026-10-08 10:01", byCreation))
    }

    @Test func calendarBoundariesSurviveDaylightSavingEnd() throws {
        // UK clocks go back at 02:00 on 25 October 2026 (a 25-hour day).
        let task = completed(at: "2026-10-24 22:00")
        let hide = try #require(TaskVisibility.hideDate(for: task, options: TaskDisplayOptions(), calendar: london))
        #expect(london.dateComponents([.day, .hour, .minute], from: hide) == DateComponents(day: 25, hour: 0, minute: 0))

        let week = try #require(TaskVisibility.hideDate(for: task, options: TaskDisplayOptions(retention: .sevenDays), calendar: london))
        #expect(london.dateComponents([.day, .hour, .minute], from: week) == DateComponents(day: 31, hour: 0, minute: 0))
    }

    @Test func calendarBoundariesSurviveDaylightSavingStart() throws {
        // UK clocks go forward at 01:00 on 29 March 2026 (a 23-hour day).
        let task = completed(at: "2026-03-28 23:30")
        let hide = try #require(TaskVisibility.hideDate(for: task, options: TaskDisplayOptions(), calendar: london))
        #expect(london.dateComponents([.day, .hour], from: hide) == DateComponents(day: 29, hour: 0))
        let week = try #require(TaskVisibility.hideDate(for: task, options: TaskDisplayOptions(retention: .sevenDays), calendar: london))
        #expect(london.dateComponents([.month, .day, .hour], from: week) == DateComponents(month: 4, day: 4, hour: 0))
    }

    @Test func relativeRetentionIsElapsedTimeAcrossDaylightSaving() throws {
        let task = completed(at: "2026-10-24 22:00")
        let options = TaskDisplayOptions(calculation: .relative)
        let hide = try #require(TaskVisibility.hideDate(for: task, options: options, calendar: london))
        #expect(hide.timeIntervalSince(task.completedAt!) == 86_400)
        // Wall clock reads 21:00 because the clocks went back an hour.
        #expect(london.dateComponents([.day, .hour], from: hide) == DateComponents(day: 25, hour: 21))
    }

    @Test func timeZoneChangesUseTheNewLocalDay() {
        // Completed 23:30 in London (18:30 in New York).
        let task = completed(at: "2026-10-08 23:30")
        let newYork = calendar("America/New_York")
        let now = date("2026-10-09 01:00", london) // 20:00 on the 8th in New York
        let options = TaskDisplayOptions()
        #expect(!TaskVisibility.isVisible(task, now: now, options: options, calendar: london))
        #expect(TaskVisibility.isVisible(task, now: now, options: options, calendar: newYork))
    }

    @Test func nextChangeIsMidnightOrTheEarliestHide() {
        let now = date("2026-10-08 12:00")
        #expect(TaskVisibility.nextChange(after: now, tasks: [], options: TaskDisplayOptions(), calendar: london)
                == date("2026-10-09 00:00"))
        let task = completed(at: "2026-10-07 15:00")
        let relative = TaskDisplayOptions(calculation: .relative)
        #expect(TaskVisibility.nextChange(after: now, tasks: [task], options: relative, calendar: london)
                == date("2026-10-08 15:00"))
    }
}

@MainActor
@Suite("Day boundaries")
struct DayBoundaryTests {
    @Test func midnightHidesYesterdaysCompletedTasksWithoutDeletingThem() throws {
        let clock = TestClock(date("2026-10-08 23:50"))
        let store = try makeStore(clock: clock)
        let done = try #require(try store.addTask(title: "Buy a birthday card"))
        try store.addTask(title: "Call the plumber")
        try store.completeTask(id: done.id)
        #expect(store.titles(now: clock.now) == ["Call the plumber", "Buy a birthday card"])

        clock.advance(10 * 60) // 00:00 on the 9th
        #expect(store.titles(now: clock.now) == ["Call the plumber"])
        #expect(try store.task(id: done.id)?.isCompleted == true)
        #expect(try store.completedTasks().map(\.id) == [done.id])
    }

    @Test func reopeningAfterSeveralDaysKeepsOpenTasksAndHidesOldCompletions() throws {
        let path = temporaryDatabasePath()
        let clock = TestClock(date("2026-10-08 09:00"))
        do {
            let store = try makeStore(path: path, clock: clock)
            let a = try #require(try store.addTask(title: "A"))
            try store.addTask(title: "B")
            try store.completeTask(id: a.id)
        }
        clock.advance(86_400 * 5)
        let store = try makeStore(path: path, clock: clock)
        #expect(store.titles(now: clock.now) == ["B"])
        #expect(try store.completedTasks().map(\.title) == ["A"])
    }

    @Test func changingRetentionRevealsOlderCompletions() throws {
        let clock = TestClock(date("2026-10-01 09:00"))
        let store = try makeStore(clock: clock)
        let a = try #require(try store.addTask(title: "A"))
        try store.completeTask(id: a.id)
        clock.advance(86_400 * 3)
        try store.reload()
        #expect(store.titles(now: clock.now).isEmpty)
        store.options.retention = .sevenDays
        #expect(store.titles(now: clock.now) == ["A"])
        store.options.retention = .forever
        clock.advance(86_400 * 30)
        try store.reload()
        #expect(store.titles(now: clock.now) == ["A"])
    }
}
