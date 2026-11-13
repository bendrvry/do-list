import Foundation
import Observation

/// The task service. Every change to tasks — from the UI today, or from App Intents,
/// a CLI or an MCP bridge later — goes through these operations, which keep writes
/// transactional and register undo.
///
/// The store keeps a small in-memory working set (open tasks plus completed tasks
/// that could still be visible) and reloads it from SQLite after each change, so the
/// database is always the source of truth.
@MainActor
@Observable
public final class TaskStore {
    /// Incomplete tasks plus recently completed tasks. Unordered; use `layout`.
    public private(set) var tasks: [TaskItem] = []
    /// Increments after every change. Lets other views (History) refresh cheaply.
    public private(set) var revision = 0

    public var options: TaskDisplayOptions {
        didSet {
            guard options != oldValue else { return }
            if options.retention != oldValue.retention { try? reload() }
            revision += 1
        }
    }

    @ObservationIgnored public let undoManager: UndoManager
    @ObservationIgnored public var clock: () -> Date
    @ObservationIgnored public var calendar: Calendar
    /// Called when an undo or redo fails to write. Direct calls throw instead.
    @ObservationIgnored public var onError: ((Error) -> Void)?

    @ObservationIgnored private let repository: TaskRepository

    public init(
        repository: TaskRepository,
        options: TaskDisplayOptions = TaskDisplayOptions(),
        undoManager: UndoManager = UndoManager(),
        calendar: Calendar = .autoupdatingCurrent,
        clock: @escaping () -> Date = Date.init
    ) throws {
        self.repository = repository
        self.options = options
        self.undoManager = undoManager
        self.calendar = calendar
        self.clock = clock
        try reload()
    }

    // MARK: Reading

    public func reload() throws {
        let cutoff = TaskVisibility.loadCutoff(now: clock(), options: options, calendar: calendar)
        tasks = try repository.openAndRecentTasks(completedSince: cutoff)
        revision += 1
    }

    public func layout(now: Date, settling: Set<UUID> = []) -> TaskLayout {
        TaskLayout.make(tasks: tasks, options: options, now: now, calendar: calendar, settling: settling)
    }

    public func nextVisibilityChange(after now: Date) -> Date {
        TaskVisibility.nextChange(after: now, tasks: tasks, options: options, calendar: calendar)
    }

    /// Incomplete tasks in manual order.
    public func openTasks() -> [TaskItem] {
        tasks.filter { !$0.isCompleted }.sorted { $0.position < $1.position }
    }

    public func task(id: UUID) throws -> TaskItem? {
        if let cached = tasks.first(where: { $0.id == id }) { return cached }
        return try repository.task(id: id)
    }

    public func completedTasks(matching search: String? = nil, limit: Int = .max, offset: Int = 0) throws -> [TaskItem] {
        try repository.completedTasks(matching: search, limit: limit, offset: offset)
    }

    // MARK: Operations

    /// Adds a task to the end of the open list. Returns `nil` for blank titles.
    @discardableResult
    public func addTask(title: String) throws -> TaskItem? {
        guard let title = TaskTitle.sanitize(title) else { return nil }
        let now = clock()
        let task = TaskItem(title: title, createdAt: now, position: try repository.maxPosition() + 1)
        try apply([Change(before: nil, after: task)], actionName: "Add Task")
        return task
    }

    /// Renames a task. Blank titles are ignored rather than deleting the task.
    public func updateTitle(id: UUID, to title: String) throws {
        guard let title = TaskTitle.sanitize(title), var task = try task(id: id) else { return }
        guard task.title != title else { return }
        let before = task
        task.title = title
        task.updatedAt = clock()
        try apply([Change(before: before, after: task)], actionName: "Edit Task")
    }

    /// Completes or un-completes a task in place (its manual position is kept).
    public func setCompleted(id: UUID, _ completed: Bool) throws {
        guard var task = try task(id: id), task.isCompleted != completed else { return }
        let before = task
        let now = clock()
        task.completedAt = completed ? now : nil
        if completed { task.startedAt = nil }
        task.updatedAt = now
        try apply([Change(before: before, after: task)], actionName: completed ? "Complete Task" : "Mark Incomplete")
    }

    /// Marks a task in progress (or back to not started). Marking a completed task in
    /// progress also reopens it, in place.
    public func setInProgress(id: UUID, _ inProgress: Bool) throws {
        guard var task = try task(id: id), task.isInProgress != inProgress else { return }
        let before = task
        let now = clock()
        task.completedAt = nil
        task.startedAt = inProgress ? now : nil
        task.updatedAt = now
        try apply([Change(before: before, after: task)], actionName: inProgress ? "Mark In Progress" : "Mark Not Started")
    }

    public func completeTask(id: UUID) throws { try setCompleted(id: id, true) }

    /// Restores a completed task from History: marks it incomplete and places it at
    /// the end of the open list. Identity and title are preserved.
    public func restoreTask(id: UUID) throws {
        guard var task = try task(id: id), task.isCompleted else { return }
        let before = task
        task.completedAt = nil
        task.startedAt = nil
        task.updatedAt = clock()
        task.position = try repository.maxPosition() + 1
        try apply([Change(before: before, after: task)], actionName: "Restore Task")
    }

    public func deleteTask(id: UUID) throws {
        guard let task = try task(id: id) else { return }
        try apply([Change(before: task, after: nil)], actionName: "Delete Task")
    }

    /// Inserts an incomplete copy directly after the original.
    @discardableResult
    public func duplicateTask(id: UUID) throws -> TaskItem? {
        guard let original = try task(id: id) else { return nil }
        let now = clock()
        var changes: [Change] = try repository.tasks(positionAbove: original.position).map { task in
            var shifted = task
            shifted.position += 1
            return Change(before: task, after: shifted)
        }
        let copy = TaskItem(title: original.title, createdAt: now, position: original.position + 1)
        changes.append(Change(before: nil, after: copy))
        try apply(changes, actionName: "Duplicate Task")
        return copy
    }

    /// Reorders the rows the user is looking at. `displayedIDs` is the current on-screen
    /// order of the movable rows; `source`/`destination` follow SwiftUI's `onMove`.
    ///
    /// The set of positions those rows already occupy is reassigned in the new order, so
    /// tasks that are not on screen (hidden completed tasks) keep their positions.
    public func reorder(displayedIDs: [UUID], from source: IndexSet, to destination: Int) throws {
        let reordered = Self.moving(displayedIDs, from: source, to: destination)
        guard reordered != displayedIDs else { return }
        var records: [UUID: TaskItem] = [:]
        for id in displayedIDs {
            guard let task = try task(id: id) else { return }
            records[id] = task
        }
        var positions = displayedIDs.compactMap { records[$0]?.position }.sorted()
        for i in positions.indices.dropFirst() where positions[i] <= positions[i - 1] {
            positions[i] = positions[i - 1] + 1
        }
        let now = clock()
        var changes: [Change] = []
        for (index, id) in reordered.enumerated() {
            guard var task = records[id], task.position != positions[index] else { continue }
            let before = task
            task.position = positions[index]
            task.updatedAt = now
            changes.append(Change(before: before, after: task))
        }
        try apply(changes, actionName: "Move Task")
    }

    /// Moves an open task to `index` within the open list (integration-friendly form).
    public func moveTask(id: UUID, toIndex index: Int) throws {
        let ids = openTasks().map(\.id)
        guard let from = ids.firstIndex(of: id) else { return }
        let clamped = max(0, min(index, ids.count - 1))
        guard clamped != from else { return }
        try reorder(displayedIDs: ids, from: [from], to: clamped > from ? clamped + 1 : clamped)
    }

    // MARK: Change application and undo

    private struct Change {
        var before: TaskItem?
        var after: TaskItem?
        var inverse: Change { Change(before: after, after: before) }
    }

    private func apply(_ changes: [Change], actionName: String) throws {
        guard !changes.isEmpty else { return }
        try repository.transaction {
            for change in changes {
                if let after = change.after {
                    try repository.upsert(after)
                } else if let before = change.before {
                    try repository.delete(id: before.id)
                }
            }
        }
        let inverse = changes.reversed().map(\.inverse)
        // Without run-loop grouping (tests, future headless callers), give each
        // operation its own undo group.
        let needsGroup = !undoManager.groupsByEvent && undoManager.groupingLevel == 0
        if needsGroup { undoManager.beginUndoGrouping() }
        defer { if needsGroup { undoManager.endUndoGrouping() } }
        undoManager.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated {
                do {
                    try store.apply(inverse, actionName: actionName)
                } catch {
                    store.onError?(error)
                }
            }
        }
        undoManager.setActionName(actionName)
        try reload()
    }

    static func moving<T>(_ array: [T], from source: IndexSet, to destination: Int) -> [T] {
        let moving = source.filter { $0 < array.count }.map { array[$0] }
        var result = array.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let adjusted = destination - source.filter { $0 < destination }.count
        result.insert(contentsOf: moving, at: max(0, min(adjusted, result.count)))
        return result
    }
}
