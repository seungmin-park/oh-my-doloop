import Foundation
import GRDB

/// 할 일을 만들 때 넘기는 값.
public struct TaskDraft: Hashable, Sendable {
    public var title: String
    public var note: String
    public var schedule: Schedule
    public var dueDay: LogicalDay?
    public var weight: TaskWeight
    public var repeatRule: RepeatRule?

    public init(
        title: String,
        note: String = "",
        schedule: Schedule = .none,
        dueDay: LogicalDay? = nil,
        weight: TaskWeight = .light,
        repeatRule: RepeatRule? = nil
    ) {
        self.title = title
        self.note = note
        self.schedule = schedule
        self.dueDay = dueDay
        self.weight = weight
        self.repeatRule = repeatRule
    }
}

/// 사용자가 바꾼 필드만 담는다. 편집 중 다른 기기가 고친 필드를 옛 값으로 되돌리지 않기 위해서다.
public struct TaskPatch: Hashable, Sendable {
    public var title: String?
    public var note: String?
    public var schedule: Schedule?
    /// `.some(nil)`이면 마감을 지운다.
    public var dueDay: LogicalDay??
    public var weight: TaskWeight?
    /// `.some(nil)`이면 반복을 지운다.
    public var repeatRule: RepeatRule??

    public init(
        title: String? = nil,
        note: String? = nil,
        schedule: Schedule? = nil,
        dueDay: LogicalDay?? = nil,
        weight: TaskWeight? = nil,
        repeatRule: RepeatRule?? = nil
    ) {
        self.title = title
        self.note = note
        self.schedule = schedule
        self.dueDay = dueDay
        self.weight = weight
        self.repeatRule = repeatRule
    }

    fileprivate func apply(to draft: inout TaskDraft) -> Set<String> {
        var fields = Set<String>()
        if let title { draft.title = title; fields.insert("title") }
        if let note { draft.note = note; fields.insert("note") }
        if let schedule { draft.schedule = schedule; fields.insert("schedule") }
        if let dueDay { draft.dueDay = dueDay; fields.insert("due_day") }
        if let weight { draft.weight = weight; fields.insert("weight") }
        if let repeatRule { draft.repeatRule = repeatRule; fields.insert("repeat_rule") }
        return fields
    }
}

extension DoloopStore {
    @discardableResult
    public func createTask(_ draft: TaskDraft) throws -> DoloopTask {
        let fields = try taskFields(draft)
        let id = newID()
        return try write { db, log in
            var row = fields
            row["created_at"] = log.timestamp.databaseValue
            row["list_id"] = .null
            row["parent_id"] = .null
            row["completed_day"] = .null
            row["deleted_at"] = .null
            try log.apply(db, .task, id: id, fields: row)
            return try fetchTask(db, id: id)
        }
    }

    @discardableResult
    public func updateTask(id: String, _ patch: TaskPatch) throws -> DoloopTask {
        try write { db, log in
            let current = try activeTask(db, id: id)
            var draft = TaskDraft(
                title: current.title,
                note: current.note,
                schedule: current.schedule,
                dueDay: current.dueDay,
                weight: current.weight,
                repeatRule: current.repeatRule
            )
            let touched = patch.apply(to: &draft)
            let fields = try taskFields(draft).filter { touched.contains($0.key) }
            try log.apply(db, .task, id: id, fields: fields)
            return try fetchTask(db, id: id)
        }
    }

    /// 지운 표시만 남긴다. 다른 기기와 합칠 수 있도록 행을 없애지 않는다.
    public func deleteTask(id: String) throws {
        try write { db, log in
            _ = try activeTask(db, id: id)
            try log.apply(db, .task, id: id, fields: ["deleted_at": log.timestamp.databaseValue])
        }
    }

    public func task(id: String) throws -> DoloopTask? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM task WHERE id = ? AND deleted_at IS NULL", arguments: [id]) else {
                return nil
            }
            return try Self.decodeTask(row)
        }
    }

    /// 남은 일은 마감일에, 끝낸 일은 실제로 끝낸 날에 나온다.
    public func tasks(on day: LogicalDay) throws -> [TaskOccurrence] {
        try dbQueue.read { db in
            let key = day.description
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM task
                WHERE deleted_at IS NULL AND (
                  completed_day = :day
                  OR (completed_day IS NULL AND repeat_rule IS NULL AND due_day = :day)
                  OR (repeat_rule IS NOT NULL AND due_day IS NOT NULL AND due_day <= :day)
                  OR EXISTS (
                    SELECT 1 FROM task_completion c
                    WHERE c.task_id = task.id AND c.day = :day AND c.completed_at IS NOT NULL
                  )
                )
                """, arguments: ["day": key])
            return try rows.compactMap { row -> TaskOccurrence? in
                let task = try Self.decodeTask(row)
                let completed = try Self.isCompleted(db, task: task, day: day)
                guard try completed || Self.isDue(db, task: task, day: day) else { return nil }
                return TaskOccurrence(task: task, day: day, isCompleted: completed)
            }
            .sorted(by: Self.taskOrder)
        }
    }

    /// 날짜가 없고 아직 끝내지 않은 일.
    public func undatedTasks() throws -> [DoloopTask] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM task
                WHERE deleted_at IS NULL AND due_day IS NULL AND completed_day IS NULL
                """)
            return try rows.map(Self.decodeTask).sorted {
                ($0.schedule.sortPosition, $0.createdAt, $0.id) < ($1.schedule.sortPosition, $1.createdAt, $1.id)
            }
        }
    }

    /// 한 번 하는 일은 마감 전이어도 끝낼 수 있고, 끝낸 날로 기록한다. 반복하는 일은 그날 예정된 것만 끝낸다.
    public func completeTask(id: String, on day: LogicalDay? = nil) throws {
        let target = day ?? today()
        guard target <= today() else { throw DoloopError.futureDay }
        try write { db, log in
            let task = try activeTask(db, id: id)
            guard task.repeatRule != nil else {
                guard task.completedDay == nil else { return }
                try log.apply(db, .task, id: id, fields: ["completed_day": target.description.databaseValue])
                return
            }
            guard try !Self.isCompleted(db, task: task, day: target) else { return }
            guard try Self.isDue(db, task: task, day: target) else { throw DoloopError.notScheduled }
            try log.apply(db, .taskCompletion, id: Self.completionID(taskID: id, day: target), fields: [
                "task_id": id.databaseValue,
                "day": target.description.databaseValue,
                "completed_at": log.timestamp.databaseValue,
            ])
        }
    }

    /// 한 번 하는 일은 끝낸 날과 상관없이 되돌린다. 반복하는 일은 그날의 완료만 되돌린다.
    public func reopenTask(id: String, on day: LogicalDay? = nil) throws {
        let target = day ?? today()
        try write { db, log in
            let task = try activeTask(db, id: id)
            if task.repeatRule == nil || task.completedDay == target {
                try log.apply(db, .task, id: id, fields: ["completed_day": .null])
            }
            guard try Self.hasCompletionRow(db, taskID: id, day: target) else { return }
            try log.apply(db, .taskCompletion, id: Self.completionID(taskID: id, day: target), fields: [
                "completed_at": .null,
            ])
        }
    }

    private func taskFields(_ draft: TaskDraft) throws -> [String: DatabaseValue] {
        let title = try cleanedTitle(draft.title)
        if let rule = draft.repeatRule {
            guard let anchor = draft.dueDay else { throw DoloopError.repeatNeedsDueDay }
            guard rule.nextOccurrence(onOrAfter: anchor, anchor: anchor) != nil else {
                throw DoloopError.repeatNeverOccurs
            }
        }
        return [
            "title": title.databaseValue,
            "note": draft.note.databaseValue,
            "schedule": draft.schedule.storageValue.databaseValue,
            "due_day": (draft.dueDay?.description).fieldValue,
            "weight": draft.weight.rawValue.databaseValue,
            "repeat_rule": (draft.repeatRule?.storageValue).fieldValue,
        ]
    }

    private func activeTask(_ db: Database, id: String) throws -> DoloopTask {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM task WHERE id = ?", arguments: [id]) else {
            throw DoloopError.notFound
        }
        let deletedAt: Int64? = row["deleted_at"]
        guard deletedAt == nil else { throw DoloopError.deleted }
        return try Self.decodeTask(row)
    }

    private func fetchTask(_ db: Database, id: String) throws -> DoloopTask {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM task WHERE id = ?", arguments: [id]) else {
            throw DoloopError.notFound
        }
        return try Self.decodeTask(row)
    }

    /// 두 기기가 같은 날 완료해도 한 줄로 합쳐지도록 id를 내용에서 만든다.
    private static func completionID(taskID: String, day: LogicalDay) -> String {
        "\(taskID):\(day)"
    }

    private static func hasCompletionRow(_ db: Database, taskID: String, day: LogicalDay) throws -> Bool {
        try Bool.fetchOne(db, sql: """
            SELECT EXISTS (SELECT 1 FROM task_completion WHERE task_id = ? AND day = ? AND completed_at IS NOT NULL)
            """, arguments: [taskID, day.description]) ?? false
    }

    private static func isCompleted(_ db: Database, task: DoloopTask, day: LogicalDay) throws -> Bool {
        if task.repeatRule == nil, task.completedDay != nil { return true }
        if task.completedDay == day { return true }
        return try hasCompletionRow(db, taskID: task.id, day: day)
    }

    private static func isDue(_ db: Database, task: DoloopTask, day: LogicalDay) throws -> Bool {
        guard let due = task.dueDay else { return false }
        guard let rule = task.repeatRule else { return due == day }
        let others = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM task_completion
            WHERE task_id = ? AND completed_at IS NOT NULL AND day >= ? AND day <= ? AND day <> ?
            """, arguments: [task.id, day.weekStart.description, day.weekStart.adding(days: 6).description, day.description]) ?? 0
        return rule.occurs(on: day, anchor: due, completedOtherDaysThisWeek: others)
    }

    private static func taskOrder(_ lhs: TaskOccurrence, _ rhs: TaskOccurrence) -> Bool {
        (lhs.task.schedule.sortPosition, lhs.task.createdAt, lhs.task.id)
            < (rhs.task.schedule.sortPosition, rhs.task.createdAt, rhs.task.id)
    }

    private static func decodeTask(_ row: Row) throws -> DoloopTask {
        let weightText: String = row["weight"]
        guard let weight = TaskWeight(rawValue: weightText) else {
            throw DoloopError.corruptValue("weight: \(weightText)")
        }
        let dueDay = try row.optionalDay("due_day")
        return DoloopTask(
            id: row["id"],
            listID: row["list_id"],
            parentID: row["parent_id"],
            title: row["title"],
            note: row["note"],
            schedule: try row.schedule(),
            dueDay: dueDay,
            weight: weight,
            // 병합으로 기준일이 사라진 반복은 기준일이 다시 생길 때까지 쉬게 둔다.
            repeatRule: dueDay == nil ? nil : try row.repeatRule(),
            completedDay: try row.optionalDay("completed_day"),
            createdAt: row.date("created_at")
        )
    }
}
