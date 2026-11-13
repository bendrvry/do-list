import StillCore
import SwiftUI

struct TaskRow: View {
    let task: TaskItem
    let model: MainListModel
    let isMovable: Bool

    @State private var isHovering = false

    private var isEditing: Bool { model.editingID == task.id }
    private var isSelected: Bool { model.selectedID == task.id }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.checkboxGap) {
            Checkbox(isOn: task.isCompleted, isInProgress: task.isInProgress, isHighlighted: isHovering || isSelected) {
                model.toggle(task)
            }
            .frame(height: Theme.lineHeight)

            if isEditing {
                TaskEditor(title: task.title) { title in
                    model.commitEdit(task, title: title)
                } onCancel: {
                    model.cancelEdit()
                } onFinishWithKeyboard: {
                    model.inputFocus.focus()
                }
            } else {
                Text(task.title)
                    .font(Theme.taskFont)
                    .foregroundStyle(task.isCompleted ? Theme.completedText : Theme.primaryText)
                    .strikethrough(task.isCompleted, color: Theme.completedText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // The list refuses to start a drag from a point over Text (or over a
                    // gesture), so presses fall through to the row. Clicks to edit are
                    // recognised by the window's event monitor instead of a tap gesture.
                    .allowsHitTesting(false)
            }
        }
        .padding(.vertical, Theme.rowVerticalPadding)
        .padding(.horizontal, Theme.rowBleed)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous)
                .fill(isHovering || isSelected || isEditing ? Theme.hover : .clear)
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1.5)
            }
        }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { isHovering = $0 }
        .contextMenu { menu }
        .accessibilityElement(children: isEditing ? .contain : .ignore)
        .accessibilityLabel(task.title)
        .accessibilityValue(task.isCompleted ? "Completed" : task.isInProgress ? "In progress" : "Not completed")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Toggles completion.")
        .accessibilityAction { model.toggle(task) }
        .accessibilityAction(named: task.isInProgress ? "Mark Not Started" : "Mark In Progress") { model.toggleInProgress(task) }
        .accessibilityAction(named: "Edit") { model.beginEditing(task) }
        .accessibilityAction(named: "Duplicate") { model.duplicate(task) }
        .accessibilityAction(named: "Delete") { model.delete(task) }
        .accessibilityAction(named: "Move Up") { model.nudge(task, by: -1) }
        .accessibilityAction(named: "Move Down") { model.nudge(task, by: 1) }
    }

    @ViewBuilder
    private var menu: some View {
        Button("Edit") { model.beginEditing(task) }
        Button("Duplicate") { model.duplicate(task) }
        Button(task.isCompleted ? "Mark Incomplete" : "Complete") { model.toggle(task) }
        Button(task.isInProgress ? "Mark Not Started" : "Mark In Progress") { model.toggleInProgress(task) }
        if isMovable {
            Divider()
            Button("Move Up") { model.nudge(task, by: -1) }
            Button("Move Down") { model.nudge(task, by: 1) }
        }
        Divider()
        Button("Delete", role: .destructive) { model.delete(task) }
    }
}

/// Inline title editor. Return saves, Escape cancels, clicking elsewhere saves
/// (like renaming in Finder) so an edit is never silently lost.
private struct TaskEditor: View {
    let onCommit: (String) -> Void
    let onCancel: () -> Void
    let onFinishWithKeyboard: () -> Void

    @State private var draft: String
    @State private var finished = false
    @FocusState private var focused: Bool

    init(
        title: String,
        onCommit: @escaping (String) -> Void,
        onCancel: @escaping () -> Void,
        onFinishWithKeyboard: @escaping () -> Void
    ) {
        _draft = State(initialValue: title)
        self.onCommit = onCommit
        self.onCancel = onCancel
        self.onFinishWithKeyboard = onFinishWithKeyboard
    }

    var body: some View {
        TextField("Task", text: $draft, axis: .vertical)
            .labelsHidden()
            .textFieldStyle(.plain)
            .font(Theme.taskFont)
            .foregroundStyle(Theme.primaryText)
            .lineLimit(1...12)
            .focused($focused)
            .onSubmit {
                finish(commit: true)
                onFinishWithKeyboard()
            }
            .onExitCommand {
                finish(commit: false)
                onFinishWithKeyboard()
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { finish(commit: true) }
            }
            .onAppear { focused = true }
            .accessibilityLabel("Edit task")
    }

    private func finish(commit: Bool) {
        guard !finished else { return }
        finished = true
        commit ? onCommit(draft) : onCancel()
    }
}
