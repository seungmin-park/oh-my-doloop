import Foundation

/// 습관의 수명. 제목과 반복 같은 정의는 `RoutineVersion`에 있다.
public struct Routine: Hashable, Identifiable, Sendable {
    public let id: String
    public var startDay: LogicalDay
    public var finishDay: LogicalDay?
    public var archivedAt: Date?
    public let createdAt: Date
}

/// `validAfter` 다음 날부터 유효한 습관의 정의. 저장은 바꾼 필드만 하고, 읽을 때 앞 버전에서 채운 값이다.
public struct RoutineVersion: Hashable, Identifiable, Sendable {
    public let id: String
    public let routineID: String
    public let validAfter: LogicalDay
    public var title: String
    public var cue: String
    public var groupID: String?
    public var schedule: Schedule
    public var repeatRule: RepeatRule
    public var repeatAnchor: LogicalDay
    public var maxCountPerDay: Int
    public var miniTitle: String?
    public var maxTitle: String?
}

public enum RoutineStatus: String, CaseIterable, Codable, Hashable, Sendable {
    case empty, done, rest, skipped
}

/// 습관의 하루 기록. 기록할 때의 습관 내용을 함께 고정해서 나중에 습관을 고치거나 다른 기기의 수정이 도착해도 과거가 바뀌지 않는다.
public struct RoutineRecord: Hashable, Identifiable, Sendable {
    public let id: String
    public let routineID: String
    public let version: RoutineVersion
    public let day: LogicalDay
    public var status: RoutineStatus
    public var count: Int
    public var memo: String?

    public var versionID: String { version.id }
}

public struct RoutineGroup: Hashable, Identifiable, Sendable {
    public let id: String
    public var title: String
    public var cue: String?
    public var color: String?
    public var sortOrder: Double
}

public struct Mode: Hashable, Identifiable, Sendable {
    public let id: String
    public var name: String
}

public struct ModeSchedule: Hashable, Sendable {
    public let day: LogicalDay
    public var modeID: String
}

/// 날짜별 조회 결과. 기록이 있으면 기록할 때의 버전을 보여 준다.
public struct RoutineOccurrence: Hashable, Sendable {
    public let routine: Routine
    public let version: RoutineVersion
    public let day: LogicalDay
    public let record: RoutineRecord?

    public var status: RoutineStatus { record?.status ?? .empty }
}
