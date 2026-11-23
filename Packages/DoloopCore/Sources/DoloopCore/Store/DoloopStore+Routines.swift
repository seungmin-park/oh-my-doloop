import Foundation
import GRDB

/// 습관을 만들 때 넘기는 값.
public struct RoutineDraft: Hashable, Sendable {
    public var title: String
    public var cue: String
    public var schedule: Schedule
    public var repeatRule: RepeatRule
    public var maxCountPerDay: Int
    public var miniTitle: String?
    public var maxTitle: String?

    public init(
        title: String,
        cue: String = "",
        schedule: Schedule = .none,
        repeatRule: RepeatRule,
        maxCountPerDay: Int = 1,
        miniTitle: String? = nil,
        maxTitle: String? = nil
    ) {
        self.title = title
        self.cue = cue
        self.schedule = schedule
        self.repeatRule = repeatRule
        self.maxCountPerDay = maxCountPerDay
        self.miniTitle = miniTitle
        self.maxTitle = maxTitle
    }
}

/// 사용자가 바꾼 필드만 담는다. 같은 날 다른 기기가 고친 필드를 옛 값으로 되돌리지 않기 위해서다.
public struct RoutinePatch: Hashable, Sendable {
    public var title: String?
    public var cue: String?
    public var schedule: Schedule?
    public var repeatRule: RepeatRule?
    public var maxCountPerDay: Int?
    /// `.some(nil)`이면 지운다.
    public var miniTitle: String??
    /// `.some(nil)`이면 지운다.
    public var maxTitle: String??

    public init(
        title: String? = nil,
        cue: String? = nil,
        schedule: Schedule? = nil,
        repeatRule: RepeatRule? = nil,
        maxCountPerDay: Int? = nil,
        miniTitle: String?? = nil,
        maxTitle: String?? = nil
    ) {
        self.title = title
        self.cue = cue
        self.schedule = schedule
        self.repeatRule = repeatRule
        self.maxCountPerDay = maxCountPerDay
        self.miniTitle = miniTitle
        self.maxTitle = maxTitle
    }

    fileprivate func apply(to draft: inout RoutineDraft) -> Set<String> {
        var fields = Set<String>()
        if let title { draft.title = title; fields.insert("title") }
        if let cue { draft.cue = cue; fields.insert("cue") }
        if let schedule { draft.schedule = schedule; fields.insert("schedule") }
        if let repeatRule { draft.repeatRule = repeatRule; fields.insert("repeat_rule") }
        if let maxCountPerDay { draft.maxCountPerDay = maxCountPerDay; fields.insert("max_count_per_day") }
        if let miniTitle { draft.miniTitle = miniTitle; fields.insert("mini_title") }
        if let maxTitle { draft.maxTitle = maxTitle; fields.insert("max_title") }
        return fields
    }
}

extension DoloopStore {
    @discardableResult
    public func createRoutine(_ draft: RoutineDraft, startDay: LogicalDay? = nil) throws -> Routine {
        let start = startDay ?? today()
        let fields = try versionFields(draft, anchor: start)
        let id = newID()
        return try write { db, log in
            try log.apply(db, .routine, id: id, fields: [
                "start_day": start.description.databaseValue,
                "finish_day": .null,
                "archived_at": .null,
                "created_at": log.timestamp.databaseValue,
                "deleted_at": .null,
            ])
            try writeVersion(db, log, routineID: id, validAfter: start.adding(days: -1), fields: fields)
            return try fetchRoutine(db, id: id)
        }
    }

    /// 고친 내용은 내일부터 적용한다. 오늘까지의 버전과 기록은 건드리지 않는다.
    @discardableResult
    public func updateRoutine(id: String, _ patch: RoutinePatch) throws -> RoutineVersion {
        let today = today()
        return try write { db, log in
            _ = try activeRoutine(db, id: id)
            let versions = try Self.resolvedVersions(db, routineID: id)
            guard let latest = versions.last else { throw DoloopError.notFound }
            var draft = RoutineDraft(
                title: latest.title,
                cue: latest.cue,
                schedule: latest.schedule,
                repeatRule: latest.repeatRule,
                maxCountPerDay: latest.maxCountPerDay,
                miniTitle: latest.miniTitle,
                maxTitle: latest.maxTitle
            )
            let touched = patch.apply(to: &draft)

            // 시간대를 옮겨 오늘이 앞당겨져도 이미 기록에 쓰인 날은 건드리지 않는다.
            let lastRecordDay = try String
                .fetchOne(db, sql: "SELECT MAX(day) FROM routine_record WHERE routine_id = ?", arguments: [id])
                .flatMap { LogicalDay($0) }
            let validAfter = max(today, latest.validAfter, lastRecordDay ?? latest.validAfter)
            let editsPending = validAfter == latest.validAfter

            // 기준일은 이 버전 직전의 규칙과 비교한다. 같은 날 되돌리면 원래 기준일로 돌아온다.
            let previous = editsPending ? versions.dropLast().last : latest
            let anchor: LogicalDay
            if let previous {
                anchor = draft.repeatRule == previous.repeatRule ? previous.repeatAnchor : validAfter.adding(days: 1)
            } else {
                anchor = latest.repeatAnchor
            }

            // 사용자가 바꾼 필드 중 실제로 달라진 것만 이 버전에 저장한다. 나머지는 앞 버전에서 읽는다.
            let current = Self.storedFields(of: latest)
            let changed = try versionFields(draft, anchor: anchor).filter { key, value in
                let isTouched = touched.contains(key == "repeat_plan" ? "repeat_rule" : key)
                return isTouched && current[key] != value
            }
            guard !changed.isEmpty else { return latest }
            return try writeVersion(db, log, routineID: id, validAfter: validAfter, fields: changed)
        }
    }

    /// 앞으로는 나오지 않게 하고, 어제까지의 기록은 지난 날짜 조회에 남긴다.
    public func deleteRoutine(id: String) throws {
        let yesterday = today().adding(days: -1)
        try write { db, log in
            let routine = try activeRoutine(db, id: id)
            let finish = min(routine.finishDay ?? yesterday, yesterday)
            try log.apply(db, .routine, id: id, fields: [
                "finish_day": finish.description.databaseValue,
                "deleted_at": log.timestamp.databaseValue,
            ])
        }
    }

    public func routine(id: String) throws -> Routine? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM routine WHERE id = ? AND deleted_at IS NULL", arguments: [id]) else {
                return nil
            }
            return try Self.decodeRoutine(row)
        }
    }

    public func versions(ofRoutine id: String) throws -> [RoutineVersion] {
        try dbQueue.read { db in
            try Self.resolvedVersions(db, routineID: id)
        }
    }

    public func record(ofRoutine id: String, on day: LogicalDay) throws -> RoutineRecord? {
        try dbQueue.read { db in try Self.fetchRecord(db, routineID: id, day: day) }
    }

    /// 그날 할 습관. 이미 기록이 있으면 기록할 때의 버전으로 보여 준다. 지운 습관은 기록이 있는 지난날에만 나온다.
    public func routines(on day: LogicalDay) throws -> [RoutineOccurrence] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM routine
                WHERE start_day <= ? AND (finish_day IS NULL OR finish_day >= ?)
                """, arguments: [day.description, day.description])
            return try rows.compactMap { row -> RoutineOccurrence? in
                let routine = try Self.decodeRoutine(row)
                if let record = try Self.fetchRecord(db, routineID: routine.id, day: day), record.status != .empty {
                    return RoutineOccurrence(routine: routine, version: record.version, day: day, record: record)
                }
                let deletedAt: Int64? = row["deleted_at"]
                guard deletedAt == nil,
                      let version = try Self.effectiveVersion(db, routineID: routine.id, day: day),
                      try Self.isDue(db, version: version, day: day)
                else { return nil }
                let record = try Self.fetchRecord(db, routineID: routine.id, day: day)
                return RoutineOccurrence(routine: routine, version: version, day: day, record: record)
            }
            .sorted {
                ($0.version.schedule.sortPosition, $0.routine.createdAt, $0.routine.id)
                    < ($1.version.schedule.sortPosition, $1.routine.createdAt, $1.routine.id)
            }
        }
    }

    /// 하루 기록을 정한다. 처음 기록할 때의 버전을 계속 유지한다.
    @discardableResult
    public func setRoutineStatus(id: String, on day: LogicalDay? = nil, to status: RoutineStatus) throws -> RoutineRecord? {
        let target = day ?? today()
        guard target <= today() else { throw DoloopError.futureDay }
        return try write { db, log in
            let routine = try activeRoutine(db, id: id)
            guard target >= routine.startDay else { throw DoloopError.beforeStart }
            if let finish = routine.finishDay, target > finish { throw DoloopError.afterFinish }

            let existing = try Self.fetchRecord(db, routineID: id, day: target)
            if existing == nil, status == .empty { return nil }
            let version: RoutineVersion
            if let existing {
                version = existing.version
            } else {
                guard let effective = try Self.effectiveVersion(db, routineID: id, day: target),
                      try Self.isDue(db, version: effective, day: target)
                else { throw DoloopError.notScheduled }
                version = effective
            }
            // 쉼을 달성으로 바꾸는 경로도 주 n회 목표를 넘지 못한다.
            if status == .done, existing?.status != .done, try !Self.isDue(db, version: version, day: target) {
                throw DoloopError.notScheduled
            }
            let count = status == .done ? version.maxCountPerDay : 0
            try log.apply(db, .routineRecord, id: "\(id):\(target)", fields: [
                "routine_id": id.databaseValue,
                "day": target.description.databaseValue,
                // 상태, 횟수, 기록할 때의 습관 내용이 따로 합쳐져 모순되지 않도록 한 필드로 묶는다.
                "outcome": "\(status.rawValue):\(count)|\(Self.encodeSnapshot(version))".databaseValue,
                "memo": existing?.memo.fieldValue ?? .null,
            ])
            return try Self.fetchRecord(db, routineID: id, day: target)
        }
    }

    private func versionFields(_ draft: RoutineDraft, anchor: LogicalDay) throws -> [String: DatabaseValue] {
        let title = try cleanedTitle(draft.title)
        guard draft.maxCountPerDay >= 1 else { throw DoloopError.invalidCount }
        guard draft.repeatRule.nextOccurrence(onOrAfter: anchor, anchor: anchor) != nil else {
            throw DoloopError.repeatNeverOccurs
        }
        return [
            "title": title.databaseValue,
            "cue": draft.cue.databaseValue,
            "schedule": draft.schedule.storageValue.databaseValue,
            "repeat_plan": Self.repeatPlan(rule: draft.repeatRule, anchor: anchor).databaseValue,
            "max_count_per_day": draft.maxCountPerDay.databaseValue,
            "mini_title": (draft.miniTitle ?? "").databaseValue,
            "max_title": (draft.maxTitle ?? "").databaseValue,
        ]
    }

    private static func storedFields(of version: RoutineVersion) -> [String: DatabaseValue] {
        [
            "title": version.title.databaseValue,
            "cue": version.cue.databaseValue,
            "schedule": version.schedule.storageValue.databaseValue,
            "repeat_plan": repeatPlan(rule: version.repeatRule, anchor: version.repeatAnchor).databaseValue,
            "max_count_per_day": version.maxCountPerDay.databaseValue,
            "mini_title": (version.miniTitle ?? "").databaseValue,
            "max_title": (version.maxTitle ?? "").databaseValue,
        ]
    }

    private static func repeatPlan(rule: RepeatRule, anchor: LogicalDay) -> String {
        "\(anchor)|\(rule.storageValue)"
    }

    private static func decodeRepeatPlan(_ text: String) throws -> (rule: RepeatRule, anchor: LogicalDay) {
        let parts = text.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let anchor = LogicalDay(String(parts[0])),
              let rule = RepeatRule(storageValue: String(parts[1]))
        else { throw DoloopError.corruptValue("repeat_plan: \(text)") }
        return (rule, anchor)
    }

    /// 두 기기가 같은 날 고쳐도 한 버전으로 합쳐지도록 id를 내용에서 만든다.
    @discardableResult
    private func writeVersion(
        _ db: Database,
        _ log: ChangeWriter,
        routineID: String,
        validAfter: LogicalDay,
        fields: [String: DatabaseValue]
    ) throws -> RoutineVersion {
        let id = "\(routineID):\(validAfter)"
        var row = fields
        row["routine_id"] = routineID.databaseValue
        row["valid_after"] = validAfter.description.databaseValue
        try log.apply(db, .routineVersion, id: id, fields: row)
        return try Self.fetchVersion(db, id: id)
    }

    private func activeRoutine(_ db: Database, id: String) throws -> Routine {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM routine WHERE id = ?", arguments: [id]) else {
            throw DoloopError.notFound
        }
        let deletedAt: Int64? = row["deleted_at"]
        guard deletedAt == nil else { throw DoloopError.deleted }
        return try Self.decodeRoutine(row)
    }

    private func fetchRoutine(_ db: Database, id: String) throws -> Routine {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM routine WHERE id = ?", arguments: [id]) else {
            throw DoloopError.notFound
        }
        return try Self.decodeRoutine(row)
    }

    private static func fetchVersion(_ db: Database, id: String) throws -> RoutineVersion {
        guard let routineID = try String.fetchOne(db, sql: "SELECT routine_id FROM routine_version WHERE id = ?", arguments: [id]),
              let version = try resolvedVersions(db, routineID: routineID).first(where: { $0.id == id })
        else { throw DoloopError.notFound }
        return version
    }

    /// 그날에 유효한 버전: `validAfter`가 그날보다 앞선 것 중 가장 나중 것.
    private static func effectiveVersion(_ db: Database, routineID: String, day: LogicalDay) throws -> RoutineVersion? {
        try resolvedVersions(db, routineID: routineID).last { $0.validAfter < day }
    }

    /// 버전을 날짜순으로 접어서 비어 있는 필드를 앞 버전의 값으로 채운다.
    /// 값이 빈 문자열인 선택 필드는 지웠다는 뜻이다. 필수 값이 아직 도착하지 않은 버전은 건너뛴다.
    private static func resolvedVersions(_ db: Database, routineID: String) throws -> [RoutineVersion] {
        let rows = try Row.fetchAll(db, sql: "SELECT * FROM routine_version WHERE routine_id = ? ORDER BY valid_after", arguments: [routineID])
        var title: String?
        var cue: String?
        var groupID: String?
        var schedule: Schedule?
        var plan: (rule: RepeatRule, anchor: LogicalDay)?
        var maxCount: Int?
        var miniTitle: String?
        var maxTitle: String?
        var result: [RoutineVersion] = []
        for row in rows {
            let rowTitle: String? = row["title"]
            let rowCue: String? = row["cue"]
            let rowGroup: String? = row["group_id"]
            let rowPlan: String? = row["repeat_plan"]
            let rowMaxCount: Int? = row["max_count_per_day"]
            let rowMini: String? = row["mini_title"]
            let rowMax: String? = row["max_title"]
            let rowSchedule: String? = row["schedule"]
            title = rowTitle ?? title
            cue = rowCue ?? cue
            maxCount = rowMaxCount ?? maxCount
            if let rowGroup { groupID = rowGroup.isEmpty ? nil : rowGroup }
            if let rowMini { miniTitle = rowMini.isEmpty ? nil : rowMini }
            if let rowMax { maxTitle = rowMax.isEmpty ? nil : rowMax }
            if rowSchedule != nil { schedule = try row.schedule() }
            if let rowPlan { plan = try decodeRepeatPlan(rowPlan) }
            guard let resolvedTitle = title, let resolvedCue = cue, let resolvedSchedule = schedule,
                  let resolvedPlan = plan, let resolvedMaxCount = maxCount
            else { continue }
            result.append(RoutineVersion(
                id: row["id"],
                routineID: row["routine_id"],
                validAfter: try row.day("valid_after"),
                title: resolvedTitle,
                cue: resolvedCue,
                groupID: groupID,
                schedule: resolvedSchedule,
                repeatRule: resolvedPlan.rule,
                repeatAnchor: resolvedPlan.anchor,
                maxCountPerDay: resolvedMaxCount,
                miniTitle: miniTitle,
                maxTitle: maxTitle
            ))
        }
        return result
    }

    private static func fetchRecord(_ db: Database, routineID: String, day: LogicalDay) throws -> RoutineRecord? {
        try Row.fetchOne(db, sql: "SELECT * FROM routine_record WHERE routine_id = ? AND day = ?", arguments: [routineID, day.description])
            .map(decodeRecord)
    }

    private static func isDue(_ db: Database, version: RoutineVersion, day: LogicalDay) throws -> Bool {
        let others = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM routine_record
            WHERE routine_id = ? AND outcome LIKE 'done:%' AND day >= ? AND day <= ? AND day <> ?
            """, arguments: [version.routineID, day.weekStart.description, day.weekStart.adding(days: 6).description, day.description]) ?? 0
        return version.repeatRule.occurs(on: day, anchor: version.repeatAnchor, completedOtherDaysThisWeek: others)
    }

    private static func decodeRoutine(_ row: Row) throws -> Routine {
        Routine(
            id: row["id"],
            startDay: try row.day("start_day"),
            finishDay: try row.optionalDay("finish_day"),
            archivedAt: row.optionalDate("archived_at"),
            createdAt: row.date("created_at")
        )
    }

    private struct VersionSnapshot: Codable {
        let id: String
        let routineID: String
        let validAfter: LogicalDay
        let title: String
        let cue: String
        let groupID: String?
        let schedule: String
        let repeatPlan: String
        let maxCountPerDay: Int
        let miniTitle: String?
        let maxTitle: String?
    }

    private static func encodeSnapshot(_ version: RoutineVersion) -> String {
        let snapshot = VersionSnapshot(
            id: version.id,
            routineID: version.routineID,
            validAfter: version.validAfter,
            title: version.title,
            cue: version.cue,
            groupID: version.groupID,
            schedule: version.schedule.storageValue,
            repeatPlan: repeatPlan(rule: version.repeatRule, anchor: version.repeatAnchor),
            maxCountPerDay: version.maxCountPerDay,
            miniTitle: version.miniTitle,
            maxTitle: version.maxTitle
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(snapshot), let text = String(data: data, encoding: .utf8) else {
            preconditionFailure("습관 내용을 저장 형식으로 바꿀 수 없습니다")
        }
        return text
    }

    private static func decodeSnapshot(_ text: String) throws -> RoutineVersion {
        guard let data = text.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(VersionSnapshot.self, from: data),
              let schedule = Schedule(storageValue: snapshot.schedule)
        else { throw DoloopError.corruptValue("outcome snapshot") }
        let plan = try decodeRepeatPlan(snapshot.repeatPlan)
        return RoutineVersion(
            id: snapshot.id,
            routineID: snapshot.routineID,
            validAfter: snapshot.validAfter,
            title: snapshot.title,
            cue: snapshot.cue,
            groupID: snapshot.groupID,
            schedule: schedule,
            repeatRule: plan.rule,
            repeatAnchor: plan.anchor,
            maxCountPerDay: snapshot.maxCountPerDay,
            miniTitle: snapshot.miniTitle,
            maxTitle: snapshot.maxTitle
        )
    }

    private static func decodeRecord(_ row: Row) throws -> RoutineRecord {
        let outcome: String = row["outcome"]
        let sections = outcome.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let parts = sections[0].split(separator: ":", omittingEmptySubsequences: false)
        guard sections.count == 2, parts.count == 2,
              let status = RoutineStatus(rawValue: String(parts[0])),
              let count = Int(parts[1]), count >= 0
        else {
            throw DoloopError.corruptValue("outcome: \(outcome)")
        }
        let version = try decodeSnapshot(String(sections[1]))
        return RoutineRecord(
            id: row["id"],
            routineID: row["routine_id"],
            version: version,
            day: try row.day("day"),
            status: status,
            count: count,
            memo: row["memo"]
        )
    }
}
