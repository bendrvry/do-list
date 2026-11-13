import Foundation

/// A single to-do item.
///
/// Named `TaskItem` rather than `Task` to avoid shadowing Swift's concurrency `Task`.
///
/// Ordering: every task carries a `position` that represents the user's manual
/// order. It is independent of completion, so switching between "move to bottom"
/// and "stay in position" never loses the order the user arranged.
public struct TaskItem: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var title: String
    public let createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    /// Set while the task is marked in progress (shown as a half-filled circle).
    public var startedAt: Date?
    public var position: Int64

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date,
        updatedAt: Date? = nil,
        completedAt: Date? = nil,
        startedAt: Date? = nil,
        position: Int64
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.completedAt = completedAt
        self.startedAt = startedAt
        self.position = position
    }

    public var isCompleted: Bool { completedAt != nil }
    public var isInProgress: Bool { !isCompleted && startedAt != nil }
}

public enum TaskTitle {
    /// Upper bound for a task title. Generous enough for any real task, small
    /// enough that a pasted document can't bloat the database or the layout.
    public static let maximumLength = 2_000

    /// Normalises user-entered text: collapses line breaks into spaces, trims
    /// surrounding whitespace and caps the length. Returns `nil` for empty input.
    public static func sanitize(_ raw: String) -> String? {
        let singleLine = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let trimmed = singleLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count > maximumLength {
            return String(trimmed.prefix(maximumLength))
        }
        return trimmed
    }
}
