import AppKit
import Carbon.HIToolbox
import StillCore
import SwiftUI

/// UI state for the main window: completion settling, inline editing and keyboard
/// selection. Task changes themselves go through `TaskStore`.
@MainActor
@Observable
final class MainListModel {
    enum Row: Identifiable {
        case task(TaskItem, movable: Bool)
        case divider

        static let dividerID = UUID(uuidString: "00000000-0000-0000-0000-00000000D1D0")!

        var id: UUID {
            switch self {
            case .task(let task, _): task.id
            case .divider: Self.dividerID
            }
        }
    }

    let store: TaskStore
    let clock: DayClock
    let inputFocus: InputFocus

    /// Just-completed tasks that hold their place briefly so the check animation is
    /// seen before they move to the completed group.
    private(set) var settling: Set<UUID> = []
    private(set) var editingID: UUID?
    /// Keyboard selection (arrow keys). Mouse users never see it.
    private(set) var selectedID: UUID?
    /// Set to ask the list to scroll a row into view.
    var scrollRequest: UUID?

    @ObservationIgnored private var settleWork: DispatchWorkItem?

    init(store: TaskStore, clock: DayClock, inputFocus: InputFocus) {
        self.store = store
        self.clock = clock
        self.inputFocus = inputFocus
    }

    var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    var layout: TaskLayout { store.layout(now: clock.now, settling: settling) }

    var rows: [Row] {
        let layout = layout
        var rows = layout.primary.map { Row.task($0, movable: true) }
        if !layout.completed.isEmpty {
            rows.append(.divider)
            rows += layout.completed.map { Row.task($0, movable: false) }
        }
        return rows
    }

    private var orderedTasks: [TaskItem] {
        let layout = layout
        return layout.primary + layout.completed
    }

    // MARK: Task actions

    func add(_ title: String) {
        var added: TaskItem?
        withAnimation(Theme.animation(reduceMotion, duration: 0.18)) {
            perform { added = try store.addTask(title: title) }
        }
        if let added { scrollRequest = added.id }
    }

    func toggle(_ task: TaskItem) {
        let completing = !task.isCompleted
        let movesAway = completing && store.options.placement == .moveToBottom && !reduceMotion
        if movesAway { settling.insert(task.id) } else { settling.remove(task.id) }

        withAnimation(Theme.animation(reduceMotion, duration: 0.22)) {
            perform { try store.setCompleted(id: task.id, completing) }
        }

        if movesAway {
            // Debounced so several quick completions settle together.
            settleWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.settle() }
            }
            settleWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65, execute: work)
        }
    }

    /// Right-click on the checkbox: toggles the half-filled "in progress" state.
    func toggleInProgress(_ task: TaskItem) {
        settling.remove(task.id)
        withAnimation(Theme.animation(reduceMotion, duration: 0.22)) {
            perform { try store.setInProgress(id: task.id, !task.isInProgress) }
        }
    }

    private func settle() {
        guard !settling.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.32)) { settling.removeAll() }
    }

    func beginEditing(_ task: TaskItem) {
        selectedID = nil
        editingID = task.id
    }

    func commitEdit(_ task: TaskItem, title: String) {
        guard editingID == task.id else { return }
        editingID = nil
        perform { try store.updateTitle(id: task.id, to: title) }
    }

    func cancelEdit() {
        editingID = nil
    }

    func duplicate(_ task: TaskItem) {
        withAnimation(Theme.animation(reduceMotion)) {
            perform { _ = try store.duplicateTask(id: task.id) }
        }
    }

    func delete(_ task: TaskItem) {
        if selectedID == task.id {
            let tasks = orderedTasks
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                let next = index + 1 < tasks.count ? tasks[index + 1] : (index > 0 ? tasks[index - 1] : nil)
                selectedID = next?.id
            }
        }
        withAnimation(Theme.animation(reduceMotion)) {
            perform { try store.deleteTask(id: task.id) }
        }
    }

    /// Handles `List.onMove`. Indices refer to `rows`; only the leading movable rows
    /// can be dragged, and drops below the divider land at the end of that group.
    func move(from source: IndexSet, to destination: Int) {
        let movableIDs = rows.prefix { row in
            if case .task(_, true) = row { return true }
            return false
        }.map(\.id)
        let validSource = IndexSet(source.filter { $0 < movableIDs.count })
        guard !validSource.isEmpty else { return }
        perform {
            try store.reorder(displayedIDs: movableIDs, from: validSource, to: min(destination, movableIDs.count))
        }
    }

    /// Moves a task one step up or down (keyboard / VoiceOver reordering).
    func nudge(_ task: TaskItem, by offset: Int) {
        let movableIDs = rows.compactMap { row -> UUID? in
            if case .task(let t, true) = row { return t.id }
            return nil
        }
        guard let index = movableIDs.firstIndex(of: task.id) else { return }
        let target = index + offset
        guard movableIDs.indices.contains(target) else { return }
        withAnimation(Theme.animation(reduceMotion)) {
            perform {
                try store.reorder(displayedIDs: movableIDs, from: [index], to: offset > 0 ? target + 1 : target)
            }
        }
        scrollRequest = task.id
    }

    /// The task shown in list row `index`, if that row is a task.
    func task(atRow index: Int) -> TaskItem? {
        let rows = rows
        guard rows.indices.contains(index), case .task(let task, _) = rows[index] else { return nil }
        return task
    }

    // MARK: Keyboard navigation

    func selectFirst() {
        guard let first = orderedTasks.first else { return }
        select(first.id)
    }

    func clearSelection() {
        selectedID = nil
    }

    private func select(_ id: UUID?) {
        selectedID = id
        if let id { scrollRequest = id }
    }

    /// Key handling while focus is in the list rather than a text field.
    /// Returns `true` if the event was consumed.
    func handleKey(_ event: NSEvent) -> Bool {
        let tasks = orderedTasks
        let command = event.modifierFlags.contains(.command)
        let currentIndex = selectedID.flatMap { id in tasks.firstIndex { $0.id == id } }

        guard let index = currentIndex else {
            selectedID = nil
            if Int(event.keyCode) == kVK_DownArrow, !command { selectFirst(); return selectedID != nil }
            return false
        }
        let task = tasks[index]

        switch Int(event.keyCode) {
        case kVK_DownArrow where command:
            nudge(task, by: 1)
        case kVK_UpArrow where command:
            nudge(task, by: -1)
        case kVK_DownArrow:
            if index + 1 < tasks.count { select(tasks[index + 1].id) }
        case kVK_UpArrow:
            if index > 0 {
                select(tasks[index - 1].id)
            } else {
                selectedID = nil
                inputFocus.focus()
            }
        case kVK_Space:
            toggle(task)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            beginEditing(task)
        case kVK_Delete, kVK_ForwardDelete:
            delete(task)
        case kVK_Escape:
            selectedID = nil
            inputFocus.focus()
        default:
            return false
        }
        return true
    }
}
