import Foundation

public enum TaskWeight: String, CaseIterable, Codable, Hashable, Sendable {
    /// 1시간 이상.
    case heavy
    /// 30분 이내.
    case light
}

public struct TaskList: Hashable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var color: String?
    public var folderID: String?
    public var viewMode: String
    public var sortOrder: Double
}

public struct Tag: Hashable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var color: String?
    public var parentID: String?
}

/// 할 일. Swift의 `Task`와 겹치지 않게 이름을 구분한다.
public struct DoloopTask: Hashable, Identifiable, Sendable {
    public let id: String
    public var listID: String?
    public var parentID: String?
    public var title: String
    public var note: String
    public var schedule: Schedule
    /// 마감일. 반복하는 일은 반복의 기준일이다.
    public var dueDay: LogicalDay?
    public var weight: TaskWeight
    public var repeatRule: RepeatRule?
    /// 한 번 하는 일을 실제로 끝낸 날. 반복하는 일은 날짜별로 따로 기록한다.
    public var completedDay: LogicalDay?
    public let createdAt: Date
}

public struct ChecklistItem: Hashable, Identifiable, Sendable {
    public let id: String
    public var taskID: String
    public var title: String
    public var isDone: Bool
    public var sortOrder: Double
}

public enum ReminderOwner: String, CaseIterable, Codable, Hashable, Sendable {
    case task, routine
}

public struct Reminder: Hashable, Identifiable, Sendable {
    public let id: String
    public var ownerType: ReminderOwner
    public var ownerID: String
    public var rule: String
}

/// 날짜별 조회 결과. 반복하는 일은 날짜마다 완료 여부가 따로 있다.
public struct TaskOccurrence: Hashable, Sendable {
    public let task: DoloopTask
    public let day: LogicalDay
    public let isCompleted: Bool
}
