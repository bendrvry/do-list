import Foundation

/// SQL access for tasks. Knows nothing about undo, visibility or UI.
public final class TaskRepository {
    public static let schemaVersion = 2

    let db: Database

    public init(database: Database) throws {
        self.db = database
        try migrate()
    }

    /// Convenience for the standard on-disk location.
    public static func openDefault(directory: URL) throws -> TaskRepository {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Tasks.sqlite")
        return try TaskRepository(database: Database(path: url.path))
    }

    // MARK: Schema

    private func migrate() throws {
        let version = db.userVersion
        if version > Self.schemaVersion {
            throw DatabaseError(
                code: -1,
                message: "The task database was created by a newer version of the app."
            )
        }
        if version < 1 {
            try db.transaction {
                try db.execute("""
                    CREATE TABLE IF NOT EXISTS tasks (
                        id           TEXT PRIMARY KEY NOT NULL,
                        title        TEXT NOT NULL,
                        created_at   REAL NOT NULL,
                        updated_at   REAL NOT NULL,
                        completed_at REAL,
                        position     INTEGER NOT NULL
                    );
                    CREATE INDEX IF NOT EXISTS tasks_open_by_position
                        ON tasks(position) WHERE completed_at IS NULL;
                    CREATE INDEX IF NOT EXISTS tasks_by_completion
                        ON tasks(completed_at) WHERE completed_at IS NOT NULL;
                    """)
                try db.setUserVersion(1)
            }
        }
        if version < 2 {
            try db.transaction {
                try db.execute("ALTER TABLE tasks ADD COLUMN started_at REAL")
                try db.setUserVersion(2)
            }
        }
        // Future migrations: `if version < 3 { ... setUserVersion(3) }`
    }

    // MARK: Reads

    private static let columns = "id, title, created_at, updated_at, completed_at, position, started_at"

    private static func task(from row: Row) -> TaskItem? {
        guard let id = UUID(uuidString: row.text(0)) else { return nil }
        return TaskItem(
            id: id,
            title: row.text(1),
            createdAt: Date(timeIntervalSince1970: row.double(2)),
            updatedAt: Date(timeIntervalSince1970: row.double(3)),
            completedAt: row.isNull(4) ? nil : Date(timeIntervalSince1970: row.double(4)),
            startedAt: row.isNull(6) ? nil : Date(timeIntervalSince1970: row.double(6)),
            position: row.int64(5)
        )
    }

    public func task(id: UUID) throws -> TaskItem? {
        try db.query("SELECT \(Self.columns) FROM tasks WHERE id = ?", [.text(id.uuidString)], map: Self.task)
            .first ?? nil
    }

    /// Every incomplete task plus completed tasks finished on or after `completedSince`.
    /// Pass `nil` to include every completed task.
    public func openAndRecentTasks(completedSince: Date?) throws -> [TaskItem] {
        if let completedSince {
            return try db.query(
                "SELECT \(Self.columns) FROM tasks WHERE completed_at IS NULL OR completed_at >= ?",
                [.double(completedSince.timeIntervalSince1970)],
                map: Self.task
            ).compactMap { $0 }
        }
        return try db.query("SELECT \(Self.columns) FROM tasks", map: Self.task).compactMap { $0 }
    }

    public func openTasks() throws -> [TaskItem] {
        try db.query(
            "SELECT \(Self.columns) FROM tasks WHERE completed_at IS NULL ORDER BY position",
            map: Self.task
        ).compactMap { $0 }
    }

    /// Completed tasks, newest completion first. `search` matches anywhere in the title
    /// (case-insensitive for ASCII, as SQLite's LIKE is).
    public func completedTasks(matching search: String? = nil, limit: Int = .max, offset: Int = 0) throws -> [TaskItem] {
        var sql = "SELECT \(Self.columns) FROM tasks WHERE completed_at IS NOT NULL"
        var bindings: [SQLValue] = []
        if let search, !search.isEmpty {
            sql += " AND title LIKE ? ESCAPE '\\'"
            bindings.append(.text("%" + Self.escapeLike(search) + "%"))
        }
        sql += " ORDER BY completed_at DESC LIMIT ? OFFSET ?"
        bindings.append(.int(Int64(min(limit, Int(Int32.max)))))
        bindings.append(.int(Int64(offset)))
        return try db.query(sql, bindings, map: Self.task).compactMap { $0 }
    }

    public func maxPosition() throws -> Int64 {
        try db.scalarInt("SELECT MAX(position) FROM tasks") ?? 0
    }

    public func tasks(positionAbove position: Int64) throws -> [TaskItem] {
        try db.query(
            "SELECT \(Self.columns) FROM tasks WHERE position > ? ORDER BY position",
            [.int(position)],
            map: Self.task
        ).compactMap { $0 }
    }

    public func count() throws -> Int {
        Int(try db.scalarInt("SELECT COUNT(*) FROM tasks") ?? 0)
    }

    // MARK: Writes

    public func upsert(_ task: TaskItem) throws {
        try db.run("""
            INSERT INTO tasks (id, title, created_at, updated_at, completed_at, position, started_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                updated_at = excluded.updated_at,
                completed_at = excluded.completed_at,
                position = excluded.position,
                started_at = excluded.started_at
            """, [
                .text(task.id.uuidString),
                .text(task.title),
                .double(task.createdAt.timeIntervalSince1970),
                .double(task.updatedAt.timeIntervalSince1970),
                task.completedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
                .int(task.position),
                task.startedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
            ])
    }

    public func delete(id: UUID) throws {
        try db.run("DELETE FROM tasks WHERE id = ?", [.text(id.uuidString)])
    }

    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try db.transaction(body)
    }

    private static func escapeLike(_ text: String) -> String {
        var result = ""
        for character in text {
            if character == "%" || character == "_" || character == "\\" { result.append("\\") }
            result.append(character)
        }
        return result
    }
}
