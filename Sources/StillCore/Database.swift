import Foundation
import SQLite3

public struct DatabaseError: Error, LocalizedError, Sendable {
    public let code: Int32
    public let message: String

    public var errorDescription: String? { message }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A deliberately small wrapper around the SQLite C API.
///
/// Single connection, used from one actor (the main actor in the app). Writes go
/// through `transaction` so each user action is atomic.
public final class Database {
    private var handle: OpaquePointer?
    public let path: String

    /// Opens (or creates) the database at `path`. Pass `":memory:"` for tests.
    public init(path: String) throws {
        self.path = path
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &db, flags, nil)
        guard rc == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database"
            sqlite3_close(db)
            throw DatabaseError(code: rc, message: message)
        }
        handle = db
        sqlite3_busy_timeout(db, 2_000)

        // Refuse to work with a damaged file rather than risk making it worse.
        // The caller decides how to present this; nothing is deleted.
        if path != ":memory:" {
            let result = try? scalarText("PRAGMA quick_check")
            guard result == "ok" else {
                sqlite3_close(db)
                handle = nil
                throw DatabaseError(code: SQLITE_CORRUPT, message: "The task database failed its integrity check.")
            }
            try execute("PRAGMA journal_mode = WAL")
        }
        // FULL keeps committed transactions durable across power loss in WAL mode.
        try execute("PRAGMA synchronous = FULL")
        try execute("PRAGMA foreign_keys = ON")
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    // MARK: Execution

    public func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        if rc != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? lastErrorMessage
            sqlite3_free(errorMessage)
            throw DatabaseError(code: rc, message: message)
        }
    }

    public func run(_ sql: String, _ bindings: [SQLValue] = []) throws {
        let statement = try prepare(sql, bindings)
        defer { sqlite3_finalize(statement) }
        let rc = sqlite3_step(statement)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw error(rc) }
    }

    public func query<T>(_ sql: String, _ bindings: [SQLValue] = [], map: (Row) throws -> T) throws -> [T] {
        let statement = try prepare(sql, bindings)
        defer { sqlite3_finalize(statement) }
        var results: [T] = []
        while true {
            let rc = sqlite3_step(statement)
            if rc == SQLITE_ROW {
                results.append(try map(Row(statement: statement!)))
            } else if rc == SQLITE_DONE {
                break
            } else {
                throw error(rc)
            }
        }
        return results
    }

    public func scalarInt(_ sql: String, _ bindings: [SQLValue] = []) throws -> Int64? {
        try query(sql, bindings) { $0.isNull(0) ? nil : $0.int64(0) }.first ?? nil
    }

    public func scalarText(_ sql: String, _ bindings: [SQLValue] = []) throws -> String? {
        try query(sql, bindings) { $0.isNull(0) ? nil : $0.text(0) }.first ?? nil
    }

    /// Runs `body` inside an immediate transaction; rolls back if it throws.
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    public var userVersion: Int {
        get { Int((try? scalarInt("PRAGMA user_version")) ?? 0) }
    }

    public func setUserVersion(_ version: Int) throws {
        try execute("PRAGMA user_version = \(version)")
    }

    // MARK: Internals

    private var lastErrorMessage: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Database is closed"
    }

    private func error(_ rc: Int32) -> DatabaseError {
        DatabaseError(code: rc, message: lastErrorMessage)
    }

    private func prepare(_ sql: String, _ bindings: [SQLValue]) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        let rc = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard rc == SQLITE_OK else { throw error(rc) }
        for (index, value) in bindings.enumerated() {
            let i = Int32(index + 1)
            let bindRC: Int32
            switch value {
            case .null: bindRC = sqlite3_bind_null(statement, i)
            case .int(let v): bindRC = sqlite3_bind_int64(statement, i, v)
            case .double(let v): bindRC = sqlite3_bind_double(statement, i, v)
            case .text(let v): bindRC = sqlite3_bind_text(statement, i, v, -1, SQLITE_TRANSIENT)
            }
            guard bindRC == SQLITE_OK else {
                sqlite3_finalize(statement)
                throw error(bindRC)
            }
        }
        return statement
    }
}

public enum SQLValue: Sendable {
    case null
    case int(Int64)
    case double(Double)
    case text(String)
}

public struct Row {
    let statement: OpaquePointer

    public func isNull(_ column: Int32) -> Bool {
        sqlite3_column_type(statement, column) == SQLITE_NULL
    }

    public func int64(_ column: Int32) -> Int64 {
        sqlite3_column_int64(statement, column)
    }

    public func double(_ column: Int32) -> Double {
        sqlite3_column_double(statement, column)
    }

    public func text(_ column: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: pointer)
    }
}
