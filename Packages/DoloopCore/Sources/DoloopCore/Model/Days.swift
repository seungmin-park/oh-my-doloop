import Foundation

public enum TrafficLight: String, CaseIterable, Codable, Hashable, Sendable {
    case empty, green, yellow, red, rest
}

/// 하루 요약. 기록에서 계산하는 값이라 저장하거나 동기화하지 않는다.
public struct DaySummary: Hashable, Sendable {
    public let day: LogicalDay
    public let light: TrafficLight
    public let successCount: Int
    public let totalCount: Int
}

/// 연속 기록. 기록에서 계산하는 값이라 저장하거나 동기화하지 않는다.
public struct Streak: Hashable, Sendable {
    public let routineID: String
    public let startDay: LogicalDay
    public let endDay: LogicalDay
    public let count: Int
}

public enum FocusOwner: String, CaseIterable, Codable, Hashable, Sendable {
    case task, routine
}

public struct FocusSession: Hashable, Identifiable, Sendable {
    public let id: String
    public var ownerType: FocusOwner?
    public var ownerID: String?
    public var startAt: Date
    public var endAt: Date?
    public var pausedSeconds: Int
    public var note: String?
}

public struct DayNote: Hashable, Sendable {
    public let day: LogicalDay
    public var text: String
}

/// 보기별 수동 정렬. 항목과 분리해서 저장한다.
public struct SortOrderEntry: Hashable, Sendable {
    public let context: String
    public let itemType: String
    public let itemID: String
    public var position: Double
}
