import Foundation
import SQLite3
import Synchronization

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum SQLValue: Sendable, Equatable {
    case null
    case int(Int64)
    case double(Double)
    case text(String)
    case blob(Data)

    var intValue: Int64? {
        switch self {
        case .int(let value): value
        case .double(let value): Int64(exactly: value.rounded(.towardZero))
        case .text(let value): Int64(value)
        default: nil
        }
    }

    var stringValue: String? {
        switch self {
        case .text(let value): value
        case .int(let value): String(value)
        case .double(let value): String(value)
        default: nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .double(let value): value
        case .int(let value): Double(value)
        case .text(let value): Double(value)
        default: nil
        }
    }

    var dataValue: Data? {
        switch self {
        case .blob(let value): value
        case .text(let value): Data(value.utf8)
        default: nil
        }
    }
}

extension SQLValue {
    static func text(_ id: some Identifier) -> SQLValue { .text(id.rawValue) }

    static func text(_ id: (some Identifier)?) -> SQLValue {
        id.map { .text($0.rawValue) } ?? .null
    }
}

struct Row: Sendable {
    let columns: [String: SQLValue]

    subscript(key: String) -> SQLValue { columns[key] ?? .null }

    func int(_ key: String) -> Int64? { self[key].intValue }
    func string(_ key: String) -> String? { self[key].stringValue }
    func double(_ key: String) -> Double? { self[key].doubleValue }
    func data(_ key: String) -> Data? { self[key].dataValue }

    func bool(_ key: String) -> Bool { (self[key].intValue ?? 0) != 0 }

    func date(_ key: String) -> Date? {
        guard let seconds = self[key].doubleValue else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}

struct SQLiteError: Error, CustomStringConvertible {
    let message: String
    let sql: String?

    var description: String {
        if let sql { return "\(message) [\(sql.prefix(200))]" }
        return message
    }
}

final class SQLiteDatabase: @unchecked Sendable {
    private var handle: OpaquePointer?

    let changes: StoreChangeHub

    private let uncommitted = Mutex<Set<StoreDomain>>([])

    private let relabelled = Mutex<[StoreDomain: StoreDomain]>([:])

    init(path: String) throws {
        self.changes = StoreChangeHub.shared(forPath: path)
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "could not open \(path)"
            sqlite3_close_v2(handle)
            throw SQLiteError(message: message, sql: nil)
        }
        self.handle = handle
        sqlite3_busy_timeout(handle, 5_000)
        try execute("PRAGMA journal_mode = WAL;")
        try execute("PRAGMA synchronous = NORMAL;")
        try execute("PRAGMA foreign_keys = ON;")
        installUpdateHook()
    }

    deinit {
        if let handle {
            sqlite3_update_hook(handle, nil, nil)
            sqlite3_close_v2(handle)
        }
    }

    private func installUpdateHook() {
        sqlite3_update_hook(
            handle,
            { context, _, _, table, _ in
                guard let context, let table,
                      let domain = StoreDomain(rawValue: String(cString: table)) else { return }
                Unmanaged<SQLiteDatabase>.fromOpaque(context)
                    .takeUnretainedValue()
                    .record(domain)
            },
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    private func record(_ domain: StoreDomain) {
        let published = relabelled.withLock { $0[domain] } ?? domain
        uncommitted.withLock { _ = $0.insert(published) }
    }

    private func flushChanges() {
        guard sqlite3_get_autocommit(handle) != 0 else { return }
        let domains = uncommitted.withLock { pending in
            defer { pending.removeAll(keepingCapacity: true) }
            return pending
        }
        changes.publish(domains)
    }

    private func fail(_ sql: String?) -> SQLiteError {
        let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "database is closed"
        return SQLiteError(message: message, sql: sql)
    }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw fail(sql) }
        flushChanges()
    }

    private func prepare(_ sql: String, _ bindings: [SQLValue]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw fail(sql)
        }
        for (offset, value) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let status: Int32 = switch value {
            case .null: sqlite3_bind_null(statement, index)
            case .int(let v): sqlite3_bind_int64(statement, index, v)
            case .double(let v): sqlite3_bind_double(statement, index, v)
            case .text(let v): v.withCString {
                sqlite3_bind_text64(statement, index, $0, UInt64(v.utf8.count), sqliteTransient, UInt8(SQLITE_UTF8))
            }
            case .blob(let v):
                if v.isEmpty {
                    sqlite3_bind_zeroblob(statement, index, 0)
                } else {
                    v.withUnsafeBytes {
                        sqlite3_bind_blob64(statement, index, $0.baseAddress, UInt64(v.count), sqliteTransient)
                    }
                }
            }
            guard status == SQLITE_OK else {
                sqlite3_finalize(statement)
                throw fail(sql)
            }
        }
        return statement
    }

    private func value(of statement: OpaquePointer, at index: Int32) -> SQLValue {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER: .int(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT: .double(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            .text(String(decoding: UnsafeBufferPointer(
                start: sqlite3_column_text(statement, index),
                count: Int(sqlite3_column_bytes(statement, index))
            ), as: UTF8.self))
        case SQLITE_BLOB:
            if let bytes = sqlite3_column_blob(statement, index) {
                .blob(Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index))))
            } else {
                .blob(Data())
            }
        default: .null
        }
    }

    @discardableResult
    func query(_ sql: String, _ bindings: [SQLValue] = []) throws -> [Row] {
        let statement = try prepare(sql, bindings)
        defer { sqlite3_finalize(statement) }

        let columnCount = sqlite3_column_count(statement)
        var names: [String] = []
        names.reserveCapacity(Int(columnCount))
        for index in 0..<columnCount {
            names.append(String(cString: sqlite3_column_name(statement, index)))
        }

        var rows: [Row] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw fail(sql) }
            var columns: [String: SQLValue] = [:]
            columns.reserveCapacity(Int(columnCount))
            for index in 0..<columnCount {
                columns[names[Int(index)]] = value(of: statement, at: index)
            }
            rows.append(Row(columns: columns))
        }
        return rows
    }

    @discardableResult
    func run(_ sql: String, _ bindings: [SQLValue] = []) throws -> Int64 {
        let statement = try prepare(sql, bindings)
        defer { sqlite3_finalize(statement) }
        let step = sqlite3_step(statement)
        guard step == SQLITE_DONE || step == SQLITE_ROW else { throw fail(sql) }
        flushChanges()
        return sqlite3_last_insert_rowid(handle)
    }

    @discardableResult
    func run(_ sql: String, _ bindings: [SQLValue] = [], publishing renames: [StoreDomain: StoreDomain]) throws -> Int64 {
        relabelled.withLock { $0 = renames }
        defer { relabelled.withLock { $0 = [:] } }
        return try run(sql, bindings)
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE;")
        do {
            let result = try body()
            try execute("COMMIT;")
            return result
        } catch {
            uncommitted.withLock { $0.removeAll(keepingCapacity: true) }
            try? execute("ROLLBACK;")
            throw error
        }
    }

    var changedRowCount: Int { Int(sqlite3_changes(handle)) }

    func readUserVersion() throws -> Int32 {
        guard let value = try query("PRAGMA user_version;").first?.int("user_version"),
              let version = Int32(exactly: value) else {
            throw SQLiteError(message: "Could not read the database schema version", sql: nil)
        }
        return version
    }

    func setUserVersion(_ version: Int32) throws {
        try execute("PRAGMA user_version = \(version);")
    }
}
