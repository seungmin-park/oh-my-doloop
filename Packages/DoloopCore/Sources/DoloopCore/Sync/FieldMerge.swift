/// 변경 기록에 남는 값.
public enum FieldValue: Hashable, Sendable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
}

/// 추가만 하는 변경 기록의 한 줄. 필드 하나의 수정이다.
public struct ChangeEntry: Hashable, Identifiable, Sendable {
    public let id: String
    public let deviceID: String
    public let timestamp: Int64
    public let entity: String
    public let entityID: String
    public let field: String
    public let value: FieldValue

    public init(id: String, deviceID: String, timestamp: Int64, entity: String, entityID: String, field: String, value: FieldValue) {
        self.id = id
        self.deviceID = deviceID
        self.timestamp = timestamp
        self.entity = entity
        self.entityID = entityID
        self.field = field
        self.value = value
    }
}

public struct FieldKey: Hashable, Sendable {
    public let entity: String
    public let entityID: String
    public let field: String

    public init(entity: String, entityID: String, field: String) {
        self.entity = entity
        self.entityID = entityID
        self.field = field
    }
}

/// 같은 항목의 같은 필드는 나중 것이 이긴다.
public enum FieldMerge {
    /// 시각이 같으면 기기 id와 기록 id로 정해서 어느 기기에서 합쳐도 결과가 같다.
    public static func isLater(_ lhs: ChangeEntry, than rhs: ChangeEntry) -> Bool {
        (lhs.timestamp, lhs.deviceID, lhs.id) > (rhs.timestamp, rhs.deviceID, rhs.id)
    }

    /// 순서를 바꾸거나 같은 기록을 두 번 넣어도 결과가 같다.
    public static func merge(_ entries: some Sequence<ChangeEntry>) -> [FieldKey: ChangeEntry] {
        var latest: [FieldKey: ChangeEntry] = [:]
        for entry in entries {
            let key = FieldKey(entity: entry.entity, entityID: entry.entityID, field: entry.field)
            if let current = latest[key], !isLater(entry, than: current) { continue }
            latest[key] = entry
        }
        return latest
    }
}
