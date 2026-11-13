import AppKit
import StillCore
import SwiftUI

/// Completed tasks grouped by the day they were completed, newest first.
///
/// History reflects tasks that are *currently* completed (there is no separate event
/// log): restoring a task removes it from here and returns it to the list.
struct HistoryView: View {
    @Environment(TaskStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var search = ""
    @State private var tasks: [TaskItem] = []
    @State private var hasMore = false
    @State private var loadedQuery: String?

    private static let pageSize = 400

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("History")
                    .font(Theme.headingFont)
                    .foregroundStyle(Theme.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }
            .padding(.horizontal, Theme.margin)
            .padding(.top, 6)

            SearchField(text: $search)
                .frame(height: 28)
                .padding(.horizontal, Theme.margin - 2)
                .padding(.top, 14)
                .padding(.bottom, 8)

            if tasks.isEmpty && loadedQuery != nil {
                Text(search.isEmpty ? "Completed tasks will appear here." : "No matching tasks.")
                    .font(Theme.taskFont)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, Theme.margin)
                    .padding(.top, 12)
                Spacer(minLength: 0)
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background.ignoresSafeArea())
        .task(id: QueryKey(search: search, revision: store.revision)) {
            // Debounce typing; refresh immediately when tasks change.
            if loadedQuery != nil && loadedQuery != search {
                try? await Task.sleep(for: .milliseconds(150))
                if Task.isCancelled { return }
            }
            reload()
        }
    }

    private var list: some View {
        let months = HistoryGrouping.group(tasks, calendar: .autoupdatingCurrent)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(months) { month in
                    Text(month.month, format: .dateTime.month(.wide).year())
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.top, 14)
                        .padding(.bottom, 2)
                        .padding(.horizontal, Theme.margin)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(month.days) { day in
                        Text(day.day, format: .dateTime.weekday(.wide).day().month(.wide))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.primaryText)
                            .padding(.top, 14)
                            .padding(.bottom, 4)
                            .padding(.horizontal, Theme.margin)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(day.tasks) { task in
                            HistoryRow(task: task) { restore(task) } onDelete: { delete(task) }
                        }
                    }
                }
                if hasMore {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .onAppear(perform: loadMore)
                }
            }
            .padding(.bottom, 20)
        }
    }

    private func reload() {
        let query = search.trimmingCharacters(in: .whitespaces)
        // Keep however many rows were already loaded so a refresh doesn't jump.
        let limit = loadedQuery == search ? max(Self.pageSize, tasks.count) : Self.pageSize
        let page = (try? store.completedTasks(matching: query, limit: limit)) ?? []
        tasks = page
        hasMore = page.count == limit
        loadedQuery = search
    }

    private func loadMore() {
        let query = search.trimmingCharacters(in: .whitespaces)
        let next = (try? store.completedTasks(matching: query, limit: Self.pageSize, offset: tasks.count)) ?? []
        tasks += next
        hasMore = next.count == Self.pageSize
    }

    private func restore(_ task: TaskItem) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            perform { try store.restoreTask(id: task.id) }
        }
    }

    private func delete(_ task: TaskItem) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            perform { try store.deleteTask(id: task.id) }
        }
    }

    private struct QueryKey: Equatable {
        let search: String
        let revision: Int
    }
}

private struct HistoryRow: View {
    let task: TaskItem
    let onRestore: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.completedText)
                .frame(width: 14, height: Theme.lineHeight)
            Text(task.title)
                .font(Theme.taskFont)
                .foregroundStyle(Theme.primaryText.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Restore", action: onRestore)
                .buttonStyle(.plain)
                .font(Theme.smallFont)
                .foregroundStyle(Theme.secondaryText)
                .frame(height: Theme.lineHeight)
                .opacity(isHovering ? 1 : 0)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, Theme.rowBleed)
        .background {
            RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous)
                .fill(isHovering ? Theme.hover : .clear)
        }
        .padding(.horizontal, Theme.margin - Theme.rowBleed)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Restore to List", action: onRestore)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(task.title)
        .accessibilityValue(task.completedAt.map { "Completed \($0.formatted(date: .omitted, time: .shortened))" } ?? "")
        .accessibilityAction(named: "Restore to List", onRestore)
        .accessibilityAction(named: "Delete", onDelete)
    }
}

/// Native search field.
private struct SearchField: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "Search"
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        field.focusRingType = .default
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
