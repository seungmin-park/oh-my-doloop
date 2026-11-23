import Foundation
import GRDB

public enum DoloopError: Error, Equatable, Sendable {
    case emptyDeviceID
    case emptyTitle
    case notFound
    case deleted
    case repeatNeedsDueDay
    case repeatNeverOccurs
    case invalidCount
    case beforeStart
    case afterFinish
    case futureDay
    case notScheduled
    case corruptValue(String)
}

/// 앱의 모든 데이터를 읽고 쓰는 곳. 데이터베이스는 밖으로 내보내지 않아서 변경 기록을 건너뛰는 쓰기가 없다.
public final class DoloopStore: Sendable {
    let dbQueue: DatabaseQueue
    let deviceID: String
    private let clock: @Sendable () -> Date
    private let timeZone: @Sendable () -> TimeZone

    /// - Parameter path: 데이터베이스 파일 경로. `nil`이면 메모리에만 둔다.
    public init(
        path: String?,
        deviceID: String,
        timeZone: @escaping @Sendable () -> TimeZone = { .current },
        clock: @escaping @Sendable () -> Date = { Date() }
    ) throws {
        guard !deviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DoloopError.emptyDeviceID
        }
        self.deviceID = deviceID
        self.clock = clock
        self.timeZone = timeZone
        if let path {
            dbQueue = try DatabaseQueue(path: path)
        } else {
            dbQueue = try DatabaseQueue()
        }
        try Schema.migrator.migrate(dbQueue)
    }

    /// 새벽 4시 전이면 전날이다.
    public func today() -> LogicalDay {
        LogicalDay(date: clock(), timeZone: timeZone())
    }

    public func changeLog() throws -> [ChangeEntry] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM change_log ORDER BY seq").map { row in
                let value: DatabaseValue = row["value"]
                return ChangeEntry(
                    id: row["change_id"],
                    deviceID: row["device_id"],
                    timestamp: row["timestamp"],
                    entity: row["entity"],
                    entityID: row["entity_id"],
                    field: row["field"],
                    value: try FieldValue(value)
                )
            }
        }
    }

    /// 항목과 변경 기록을 한 트랜잭션으로 쓴다.
    func write<T>(_ body: (Database, ChangeWriter) throws -> T) throws -> T {
        try dbQueue.write { db in
            let writer = try ChangeWriter(db: db, deviceID: deviceID, now: clock())
            return try body(db, writer)
        }
    }

    func newID() -> String {
        UUID().uuidString.lowercased()
    }
}

/// 표와 변경 기록의 유일한 쓰기 경로. 실제로 바뀐 필드만 기록한다.
struct ChangeWriter {
    let deviceID: String
    /// 시계가 뒤로 가도 이 기기의 나중 수정이 앞선 수정을 이기도록 항상 늘어난다.
    let timestamp: Int64

    init(db: Database, deviceID: String, now: Date) throws {
        self.deviceID = deviceID
        let last = try Int64.fetchOne(db, sql: "SELECT MAX(timestamp) FROM change_log")
        let current = Int64((now.timeIntervalSince1970 * 1_000).rounded())
        timestamp = last.map { max(current, $0 + 1) } ?? current
    }

    func apply(_ db: Database, _ entity: ChangeEntity, id: String, fields: [String: DatabaseValue]) throws {
        let table = entity.rawValue
        let existing = try Row.fetchOne(db, sql: "SELECT * FROM \(table) WHERE id = ?", arguments: [id])
        let changed = fields
            .filter { key, value in
                guard let existing else { return true }
                let old: DatabaseValue = existing[key]
                return old != value
            }
            .sorted { $0.key < $1.key }
        guard !changed.isEmpty else { return }

        if existing == nil {
            let columns = (["id"] + changed.map(\.key)).joined(separator: ", ")
            let marks = Array(repeating: "?", count: changed.count + 1).joined(separator: ", ")
            try db.execute(
                sql: "INSERT INTO \(table) (\(columns)) VALUES (\(marks))",
                arguments: StatementArguments([id.databaseValue] + changed.map(\.value))
            )
        } else {
            let assignments = changed.map { "\($0.key) = ?" }.joined(separator: ", ")
            try db.execute(
                sql: "UPDATE \(table) SET \(assignments) WHERE id = ?",
                arguments: StatementArguments(changed.map(\.value) + [id.databaseValue])
            )
        }
        for (field, value) in changed {
            try db.execute(
                sql: """
                INSERT INTO change_log (change_id, device_id, timestamp, entity, entity_id, field, value)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [UUID().uuidString.lowercased(), deviceID, timestamp, table, id, field, value]
            )
        }
    }
}

extension FieldValue {
    init(_ value: DatabaseValue) throws {
        switch value.storage {
        case .null: self = .null
        case .int64(let number): self = .integer(number)
        case .double(let number): self = .real(number)
        case .string(let text): self = .text(text)
        case .blob: throw DoloopError.corruptValue("변경 기록에 이진 값이 있습니다")
        }
    }
}

// 저장 형식 변환
extension Row {
    func day(_ column: String) throws -> LogicalDay {
        let text: String = self[column]
        guard let day = LogicalDay(text) else { throw DoloopError.corruptValue("\(column): \(text)") }
        return day
    }

    func optionalDay(_ column: String) throws -> LogicalDay? {
        let text: String? = self[column]
        guard let text else { return nil }
        guard let day = LogicalDay(text) else { throw DoloopError.corruptValue("\(column): \(text)") }
        return day
    }

    func schedule(_ column: String = "schedule") throws -> Schedule {
        let text: String = self[column]
        guard let schedule = Schedule(storageValue: text) else { throw DoloopError.corruptValue("\(column): \(text)") }
        return schedule
    }

    func repeatRule(_ column: String = "repeat_rule") throws -> RepeatRule? {
        let text: String? = self[column]
        guard let text else { return nil }
        guard let rule = RepeatRule(storageValue: text) else { throw DoloopError.corruptValue("\(column): \(text)") }
        return rule
    }

    func date(_ column: String) -> Date {
        let milliseconds: Int64 = self[column]
        return Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    }

    func optionalDate(_ column: String) -> Date? {
        let milliseconds: Int64? = self[column]
        return milliseconds.map { Date(timeIntervalSince1970: Double($0) / 1_000) }
    }
}

extension Optional where Wrapped: DatabaseValueConvertible {
    var fieldValue: DatabaseValue {
        map(\.databaseValue) ?? .null
    }
}

func cleanedTitle(_ title: String) throws -> String {
    let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { throw DoloopError.emptyTitle }
    return cleaned
}
