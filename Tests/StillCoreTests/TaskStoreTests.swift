import Foundation
import Testing
@testable import StillCore

@MainActor
@Suite("Task operations")
struct TaskStoreTests {
    let clock = TestClock(date("2026-10-08 09:00"))

    @Test func addingATaskAppendsToTheOpenList() throws {
        let store = try makeStore(clock: clock)
        try store.addTask(title: "Water the plants")
        try store.addTask(title: "Pay the electricity bill")
        #expect(store.titles(now: clock.now) == ["Water the plants", "Pay the electricity bill"])
    }

    @Test func blankTitlesAreIgnoredAndWhitespaceIsTrimmed() throws {
        let store = try makeStore(clock: clock)
        #expect(try store.addTask(title: "") == nil)
        #expect(try store.addTask(title: "   \n\t ") == nil)
        try store.addTask(title: "  Call the plumber \n")
        #expect(store.titles(now: clock.now) == ["Call the plumber"])
    }

    @Test func inProgressIsPersistedClearedOnCompletionAndUndoable() throws {
        let path = temporaryDatabasePath()
        let store = try makeStore(path: path, clock: clock)
        let task = try #require(try store.addTask(title: "Plan the weekend"))
        try store.step { try $0.setInProgress(id: task.id, true) }
        #expect(try store.task(id: task.id)?.isInProgress == true)

        let reopened = try makeStore(path: path, clock: clock)
        #expect(try reopened.task(id: task.id)?.isInProgress == true)

        try store.step { try $0.completeTask(id: task.id) }
        #expect(try store.task(id: task.id)?.isInProgress == false)
        store.undoManager.undo()
        #expect(try store.task(id: task.id)?.isInProgress == true)

        try store.step { try $0.setInProgress(id: task.id, false) }
        #expect(try store.task(id: task.id)?.startedAt == nil)
    }

    @Test func pastedMultilineTextBecomesOneLine() {
        #expect(TaskTitle.sanitize("Line one\n  line two\r\n\nline three") == "Line one line two line three")
    }

    @Test func longTitlesArePreservedUpToTheLimit() throws {
        let store = try makeStore(clock: clock)
        let long = String(repeating: "Sort out the spare room and clear the garage ", count: 20)
        let task = try #require(try store.addTask(title: long))
        #expect(task.title == long.trimmingCharacters(in: .whitespaces))
        let huge = String(repeating: "x", count: TaskTitle.maximumLength + 500)
        let capped = try #require(try store.addTask(title: huge))
        #expect(capped.title.count == TaskTitle.maximumLength)
    }

    @Test func unicodeAndEmojiSurviveARoundTrip() throws {
        let path = temporaryDatabasePath()
        do {
            let store = try makeStore(path: path, clock: clock)
            try store.addTask(title: "Café – 日本語 ✨ 👩🏽‍💻 \"quotes\" 'and' %_\\")
        }
        let reopened = try makeStore(path: path, clock: clock)
        #expect(reopened.titles(now: clock.now) == ["Café – 日本語 ✨ 👩🏽‍💻 \"quotes\" 'and' %_\\"])
    }

    @Test func editingATaskChangesOnlyItsTitle() throws {
        let store = try makeStore(clock: clock)
        let task = try #require(try store.addTask(title: "Call the plumbr"))
        clock.advance(60)
        try store.updateTitle(id: task.id, to: "Call the plumber")
        let edited = try #require(try store.task(id: task.id))
        #expect(edited.title == "Call the plumber")
        #expect(edited.createdAt == task.createdAt)
        #expect(edited.updatedAt > task.updatedAt)
        #expect(edited.position == task.position)
    }

    @Test func editingToABlankTitleKeepsTheOriginal() throws {
        let store = try makeStore(clock: clock)
        let task = try #require(try store.addTask(title: "Keep me"))
        try store.updateTitle(id: task.id, to: "   ")
        #expect(try store.task(id: task.id)?.title == "Keep me")
    }

    @Test func completingATaskRecordsTheTimeAndMovesItToTheBottom() throws {
        let store = try makeStore(clock: clock)
        let a = try #require(try store.addTask(title: "A"))
        try store.addTask(title: "B")
        try store.addTask(title: "C")
        try store.completeTask(id: a.id)
        let layout = store.layout(now: clock.now)
        #expect(layout.primary.map(\.title) == ["B", "C"])
        #expect(layout.completed.map(\.title) == ["A"])
        #expect(layout.completed.first?.completedAt == clock.now)
    }

    @Test func completedTasksAreOrderedByCompletionTime() throws {
        let store = try makeStore(clock: clock)
        let a = try #require(try store.addTask(title: "A"))
        let b = try #require(try store.addTask(title: "B"))
        let c = try #require(try store.addTask(title: "C"))
        try store.completeTask(id: c.id)
        clock.advance(1)
        try store.completeTask(id: a.id)
        clock.advance(1)
        try store.completeTask(id: b.id)
        #expect(store.layout(now: clock.now).completed.map(\.title) == ["C", "A", "B"])
    }

    @Test func stayInPositionKeepsCompletedTasksInPlace() throws {
        let store = try makeStore(clock: clock, options: TaskDisplayOptions(placement: .stayInPosition))
        try store.addTask(title: "A")
        let b = try #require(try store.addTask(title: "B"))
        try store.addTask(title: "C")
        try store.completeTask(id: b.id)
        let layout = store.layout(now: clock.now)
        #expect(layout.primary.map(\.title) == ["A", "B", "C"])
        #expect(layout.primary[1].isCompleted)
        #expect(layout.completed.isEmpty)
    }

    @Test func switchingPlacementModesPreservesManualOrder() throws {
        let store = try makeStore(clock: clock)
        let a = try #require(try store.addTask(title: "A"))
        try store.addTask(title: "B")
        try store.addTask(title: "C")
        try store.completeTask(id: a.id)
        #expect(store.titles(now: clock.now) == ["B", "C", "A"])
        store.options.placement = .stayInPosition
        #expect(store.titles(now: clock.now) == ["A", "B", "C"])
        store.options.placement = .moveToBottom
        #expect(store.titles(now: clock.now) == ["B", "C", "A"])
    }

    @Test func uncheckingReturnsATaskToItsOriginalPlace() throws {
        let store = try makeStore(clock: clock)
        let a = try #require(try store.addTask(title: "A"))
        try store.addTask(title: "B")
        try store.completeTask(id: a.id)
        try store.setCompleted(id: a.id, false)
        #expect(store.titles(now: clock.now) == ["A", "B"])
        #expect(try store.task(id: a.id)?.completedAt == nil)
    }

    @Test func settlingTasksKeepTheirPlaceBrieflyAfterCompletion() throws {
        let store = try makeStore(clock: clock)
        let a = try #require(try store.addTask(title: "A"))
        try store.addTask(title: "B")
        try store.completeTask(id: a.id)
        let settling = store.layout(now: clock.now, settling: [a.id])
        #expect(settling.primary.map(\.title) == ["A", "B"])
        #expect(settling.completed.isEmpty)
    }

    @Test func deletingRemovesTheRecord() throws {
        let store = try makeStore(clock: clock)
        let a = try #require(try store.addTask(title: "A"))
        try store.deleteTask(id: a.id)
        #expect(store.tasks.isEmpty)
        #expect(try store.task(id: a.id) == nil)
    }

    @Test func duplicateInsertsAnIncompleteCopyAfterTheOriginal() throws {
        let store = try makeStore(clock: clock)
        let a = try #require(try store.addTask(title: "A"))
        try store.addTask(title: "B")
        try store.completeTask(id: a.id)
        let copy = try #require(try store.duplicateTask(id: a.id))
        #expect(copy.id != a.id)
        #expect(!copy.isCompleted)
        store.options.placement = .stayInPosition
        #expect(store.titles(now: clock.now) == ["A", "A", "B"])
    }

    @Test func reorderingMovesTasksAndPersists() throws {
        let path = temporaryDatabasePath()
        do {
            let store = try makeStore(path: path, clock: clock)
            for title in ["A", "B", "C", "D"] { try store.addTask(title: title) }
            let ids = store.layout(now: clock.now).primary.map(\.id)
            // Drag D to the top, then A to the end.
            try store.reorder(displayedIDs: ids, from: [3], to: 0)
            #expect(store.titles(now: clock.now) == ["D", "A", "B", "C"])
            let next = store.layout(now: clock.now).primary.map(\.id)
            try store.reorder(displayedIDs: next, from: [1], to: 4)
            #expect(store.titles(now: clock.now) == ["D", "B", "C", "A"])
        }
        let reopened = try makeStore(path: path, clock: clock)
        #expect(reopened.titles(now: clock.now) == ["D", "B", "C", "A"])
    }

    @Test func reorderingNeverChangesCompletionStatus() throws {
        let store = try makeStore(clock: clock, options: TaskDisplayOptions(placement: .stayInPosition))
        let a = try #require(try store.addTask(title: "A"))
        try store.addTask(title: "B")
        try store.completeTask(id: a.id)
        let ids = store.layout(now: clock.now).primary.map(\.id)
        try store.reorder(displayedIDs: ids, from: [0], to: 2)
        #expect(store.titles(now: clock.now) == ["B", "A"])
        #expect(try store.task(id: a.id)?.isCompleted == true)
    }

    @Test func reorderingVisibleRowsLeavesHiddenTasksUntouched() throws {
        let store = try makeStore(clock: clock)
        let hidden = try #require(try store.addTask(title: "Old"))
        try store.completeTask(id: hidden.id)
        try store.addTask(title: "A")
        try store.addTask(title: "B")
        clock.advance(86_400) // tomorrow: "Old" is hidden
        let ids = store.layout(now: clock.now).primary.map(\.id)
        try store.reorder(displayedIDs: ids, from: [1], to: 0)
        #expect(store.titles(now: clock.now) == ["B", "A"])
        #expect(try store.task(id: hidden.id)?.position == hidden.position)
    }

    @Test func moveTaskToIndex() throws {
        let store = try makeStore(clock: clock)
        let a = try #require(try store.addTask(title: "A"))
        try store.addTask(title: "B")
        try store.addTask(title: "C")
        try store.moveTask(id: a.id, toIndex: 2)
        #expect(store.titles(now: clock.now) == ["B", "C", "A"])
        try store.moveTask(id: a.id, toIndex: 0)
        #expect(store.titles(now: clock.now) == ["A", "B", "C"])
    }

    @Test func incompleteTasksPersistIndefinitely() throws {
        let path = temporaryDatabasePath()
        do {
            let store = try makeStore(path: path, clock: clock)
            try store.addTask(title: "Someday")
        }
        clock.advance(86_400 * 400)
        for retention in CompletedRetention.allCases {
            let store = try makeStore(path: path, clock: clock, options: TaskDisplayOptions(retention: retention))
            #expect(store.titles(now: clock.now) == ["Someday"])
        }
    }

    @Test func applicationRestartPreservesEverything() throws {
        let path = temporaryDatabasePath()
        var expected: [TaskItem] = []
        do {
            let store = try makeStore(path: path, clock: clock)
            let a = try #require(try store.addTask(title: "A"))
            try store.addTask(title: "B")
            try store.completeTask(id: a.id)
            expected = store.tasks.sorted { $0.position < $1.position }
        }
        let reopened = try makeStore(path: path, clock: clock)
        #expect(reopened.tasks.sorted { $0.position < $1.position } == expected)
    }
}

@MainActor
@Suite("Undo")
struct UndoTests {
    let clock = TestClock(date("2026-10-08 09:00"))

    @Test func undoAndRedoAdd() throws {
        let store = try makeStore(clock: clock)
        try store.step { try $0.addTask(title: "A") }
        #expect(store.undoManager.undoActionName == "Add Task")
        store.undoManager.undo()
        #expect(store.tasks.isEmpty)
        store.undoManager.redo()
        #expect(store.titles(now: clock.now) == ["A"])
    }

    @Test func undoCompletion() throws {
        let store = try makeStore(clock: clock)
        var id = UUID()
        try store.step { id = try #require(try $0.addTask(title: "A")).id }
        try store.step { try $0.completeTask(id: id) }
        store.undoManager.undo()
        #expect(try store.task(id: id)?.isCompleted == false)
        store.undoManager.redo()
        #expect(try store.task(id: id)?.isCompleted == true)
    }

    @Test func undoEdit() throws {
        let store = try makeStore(clock: clock)
        var id = UUID()
        try store.step { id = try #require(try $0.addTask(title: "Before")).id }
        try store.step { try $0.updateTitle(id: id, to: "After") }
        store.undoManager.undo()
        #expect(try store.task(id: id)?.title == "Before")
        store.undoManager.redo()
        #expect(try store.task(id: id)?.title == "After")
    }

    @Test func undoDeleteRestoresIdentityAndPosition() throws {
        let store = try makeStore(clock: clock)
        var original: TaskItem?
        try store.step {
            try $0.addTask(title: "A")
            original = try $0.addTask(title: "B")
            try $0.addTask(title: "C")
        }
        let b = try #require(original)
        try store.step { try $0.deleteTask(id: b.id) }
        #expect(store.titles(now: clock.now) == ["A", "C"])
        store.undoManager.undo()
        #expect(store.titles(now: clock.now) == ["A", "B", "C"])
        #expect(try store.task(id: b.id) == b)
    }

    @Test func undoReorderAndDuplicate() throws {
        let store = try makeStore(clock: clock)
        try store.step { for t in ["A", "B", "C"] { try $0.addTask(title: t) } }
        let ids = store.layout(now: clock.now).primary.map(\.id)
        try store.step { try $0.reorder(displayedIDs: ids, from: [2], to: 0) }
        #expect(store.titles(now: clock.now) == ["C", "A", "B"])
        store.undoManager.undo()
        #expect(store.titles(now: clock.now) == ["A", "B", "C"])

        try store.step { _ = try $0.duplicateTask(id: ids[0]) }
        #expect(store.titles(now: clock.now) == ["A", "A", "B", "C"])
        store.undoManager.undo()
        #expect(store.titles(now: clock.now) == ["A", "B", "C"])
    }

    @Test func undoRestoreFromHistory() throws {
        let store = try makeStore(clock: clock)
        var id = UUID()
        try store.step { id = try #require(try $0.addTask(title: "A")).id }
        try store.step { try $0.completeTask(id: id) }
        try store.step { try $0.restoreTask(id: id) }
        #expect(try store.task(id: id)?.isCompleted == false)
        store.undoManager.undo()
        #expect(try store.task(id: id)?.isCompleted == true)
    }
}
