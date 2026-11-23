import Foundation
import GRDB
import Testing
@testable import DoloopCore

private struct TestFailure: Error {}

/// 같은 데이터에서 갈라진 두 기기를 만든다.
private func twoDevices() throws -> (DoloopStore, DoloopStore, TestClock, TestClock, String) {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("doloop-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let pathA = folder.appendingPathComponent("a.sqlite").path
    let pathB = folder.appendingPathComponent("b.sqlite").path
    let clockA = TestClock("2026-11-23 10:00")
    let clockB = TestClock("2026-11-23 10:00")
    var routineID = ""
    do {
        let seed = try makeStore(device: "a", clock: clockA, path: pathA)
        routineID = try seed.createRoutine(RoutineDraft(title: "처음", cue: "처음 상황", repeatRule: try daily()), startDay: day("2026-11-20")).id
    }
    try FileManager.default.copyItem(atPath: pathA, toPath: pathB)
    return (
        try makeStore(device: "a", clock: clockA, path: pathA),
        try makeStore(device: "b", clock: clockB, path: pathB),
        clockA, clockB, routineID
    )
}

/// 두 기기의 변경 기록을 합친 결과로 새 저장소를 만든다.
private func rebuilt(from entries: [ChangeEntry]) throws -> DoloopStore {
    let store = try makeStore(device: "merged", clock: TestClock("2026-11-30 12:00"))
    let merged = FieldMerge.merge(entries)
    let rows = Dictionary(grouping: merged) { "\($0.key.entity)\u{0}\($0.key.entityID)" }
    try store.write { db, log in
        for pairs in rows.values {
            let key = pairs[0].key
            var fields: [String: DatabaseValue] = [:]
            for (fieldKey, entry) in pairs {
                switch entry.value {
                case .null: fields[fieldKey.field] = .null
                case .integer(let number): fields[fieldKey.field] = number.databaseValue
                case .real(let number): fields[fieldKey.field] = number.databaseValue
                case .text(let text): fields[fieldKey.field] = text.databaseValue
                }
            }
            try log.apply(db, ChangeEntity(rawValue: key.entity)!, id: key.entityID, fields: fields)
        }
    }
    return store
}

@Suite("변경 기록")
struct ChangeLogTests {
    @Test("모든 수정이 기기 id, 시각과 함께 남는다")
    func recordsDeviceAndTime() throws {
        let clock = TestClock("2026-11-23 17:40")
        let store = try makeStore(device: "iphone", clock: clock)
        let task = try store.createTask(TaskDraft(title: "장보기"))
        let entries = try store.changeLog()
        #expect(!entries.isEmpty)
        #expect(entries.allSatisfy { $0.deviceID == "iphone" && $0.entity == "task" && $0.entityID == task.id })
        #expect(entries.allSatisfy { $0.timestamp == Int64(clock.now.timeIntervalSince1970 * 1_000) })
    }

    @Test("바뀐 필드만 남긴다")
    func onlyChangedFields() throws {
        let store = try makeStore()
        let task = try store.createTask(TaskDraft(title: "처음", note: "메모"))
        let before = try store.changeLog().count
        try store.updateTask(id: task.id, TaskPatch(title: "나중", note: "메모"))
        let added = try store.changeLog().dropFirst(before)
        #expect(added.map(\.field) == ["title"])
        #expect(added.first?.value == .text("나중"))
    }

    @Test("바뀐 것이 없으면 아무것도 남기지 않는다")
    func noChange() throws {
        let store = try makeStore()
        let draft = TaskDraft(title: "같음", schedule: .time(WallTime("19:30")!), dueDay: day("2026-11-23"), repeatRule: try RepeatRule(.everyWeeks(1, on: [.monday, .friday])))
        let task = try store.createTask(draft)
        let before = try store.changeLog().count
        try store.updateTask(id: task.id, TaskPatch(title: draft.title, schedule: draft.schedule, dueDay: draft.dueDay, repeatRule: draft.repeatRule))
        #expect(try store.changeLog().count == before)
    }

    @Test("변경 기록은 고치거나 지울 수 없다")
    func appendOnly() throws {
        let store = try makeStore()
        try store.createTask(TaskDraft(title: "장보기"))
        let count = try store.changeLog().count
        #expect(throws: (any Error).self) {
            try store.dbQueue.write { try $0.execute(sql: "UPDATE change_log SET value = 'x'") }
        }
        #expect(throws: (any Error).self) {
            try store.dbQueue.write { try $0.execute(sql: "DELETE FROM change_log") }
        }
        #expect(try store.changeLog().count == count)
    }

    @Test("중간에 실패하면 항목과 기록이 함께 되돌아간다")
    func atomic() throws {
        let store = try makeStore()
        #expect(throws: TestFailure.self) {
            try store.write { db, log in
                try log.apply(db, .task, id: "반쯤", fields: [
                    "title": "x".databaseValue, "note": "".databaseValue, "schedule": "none".databaseValue,
                    "weight": "light".databaseValue, "created_at": log.timestamp.databaseValue,
                ])
                throw TestFailure()
            }
        }
        #expect(try store.changeLog().isEmpty)
        #expect(try store.dbQueue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM task") } == 0)
    }

    @Test("시계가 뒤로 가도 나중 수정이 이긴다")
    func clockRollback() throws {
        let clock = TestClock("2026-11-23 17:40")
        let store = try makeStore(clock: clock)
        let task = try store.createTask(TaskDraft(title: "처음"))
        clock.set("2026-11-20 09:00")
        try store.updateTask(id: task.id, TaskPatch(title: "나중"))
        let entries = try store.changeLog()
        let merged = FieldMerge.merge(entries)
        #expect(merged[FieldKey(entity: "task", entityID: task.id, field: "title")]?.value == .text("나중"))
        #expect(zip(entries, entries.dropFirst()).allSatisfy { $0.timestamp <= $1.timestamp })
    }

    @Test("같은 날 두 기기가 습관의 다른 필드를 고쳐도 둘 다 남는다")
    func sameDayVersionMerge() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("doloop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let pathA = folder.appendingPathComponent("a.sqlite").path
        let pathB = folder.appendingPathComponent("b.sqlite").path
        let clockA = TestClock("2026-11-23 10:00")
        let clockB = TestClock("2026-11-23 10:00")
        var routineID = ""
        do {
            let seed = try makeStore(device: "a", clock: clockA, path: pathA)
            routineID = try seed.createRoutine(RoutineDraft(title: "처음", cue: "처음 상황", repeatRule: try daily()), startDay: day("2026-11-20")).id
        }
        try FileManager.default.copyItem(atPath: pathA, toPath: pathB)
        let a = try makeStore(device: "a", clock: clockA, path: pathA)
        let b = try makeStore(device: "b", clock: clockB, path: pathB)
        clockA.set("2026-11-23 12:00")
        clockB.set("2026-11-23 13:00")
        let versionA = try a.updateRoutine(id: routineID, RoutinePatch(title: "A가 고친 제목"))
        let versionB = try b.updateRoutine(id: routineID, RoutinePatch(cue: "B가 고친 상황"))
        #expect(versionA.id == versionB.id)
        let merged = FieldMerge.merge(try a.changeLog() + b.changeLog())
        func value(_ field: String) -> FieldValue? {
            merged[FieldKey(entity: "routine_version", entityID: versionA.id, field: field)]?.value
        }
        #expect(value("title") == .text("A가 고친 제목"))
        #expect(value("cue") == .text("B가 고친 상황"))
    }

    @Test("날짜가 다른 오프라인 수정도 합치면 둘 다 남는다")
    func differentDayVersionMerge() throws {
        let (a, b, clockA, clockB, routineID) = try twoDevices()
        clockA.set("2026-11-23 12:00")
        clockB.set("2026-11-24 12:00")
        try a.updateRoutine(id: routineID, RoutinePatch(title: "A가 월요일에 고친 제목"))
        try b.updateRoutine(id: routineID, RoutinePatch(cue: "B가 화요일에 고친 상황"))
        for order in [try a.changeLog() + b.changeLog(), try b.changeLog() + a.changeLog()] {
            let version = try #require(try rebuilt(from: order).routines(on: day("2026-11-26")).first?.version)
            #expect(version.title == "A가 월요일에 고친 제목")
            #expect(version.cue == "B가 화요일에 고친 상황")
        }
    }

    @Test("뒤늦게 도착한 수정이 이미 기록한 날을 바꾸지 않는다")
    func lateVersionKeepsPastRecord() throws {
        let (a, b, clockA, clockB, routineID) = try twoDevices()
        clockA.set("2026-11-23 12:00")
        try a.updateRoutine(id: routineID, RoutinePatch(title: "A제목", maxCountPerDay: 3))
        clockB.set("2026-11-24 12:00")
        try b.updateRoutine(id: routineID, RoutinePatch(cue: "B상황"))
        clockB.set("2026-11-25 12:00")
        let before = try #require(try b.setRoutineStatus(id: routineID, to: .done))
        #expect(before.version.title == "처음")
        #expect(before.count == 1)

        let merged = try rebuilt(from: try a.changeLog() + b.changeLog())
        let occurrence = try #require(try merged.routines(on: day("2026-11-25")).first)
        #expect(occurrence.record == before)
        #expect(occurrence.version.title == "처음")
        #expect(occurrence.version.maxCountPerDay == 1)
        #expect(try merged.routines(on: day("2026-11-26")).first?.version.title == "A제목")

        // 합친 뒤에 그날의 상태를 바꿔도 기록할 때의 내용을 유지한다.
        let changed = try #require(try merged.setRoutineStatus(id: routineID, on: day("2026-11-25"), to: .rest))
        #expect(changed.version == before.version)
    }

    @Test("기준 버전이 아직 안 와도 다른 습관과 기록은 읽힌다")
    func partialArrival() throws {
        let (a, b, _, clockB, routineID) = try twoDevices()
        let other = try a.createRoutine(RoutineDraft(title: "다른 습관", repeatRule: try daily()), startDay: day("2026-11-20"))
        clockB.set("2026-11-24 12:00")
        try b.updateRoutine(id: routineID, RoutinePatch(cue: "B상황"))
        clockB.set("2026-11-25 12:00")
        try b.setRoutineStatus(id: routineID, to: .done)
        let baseID = "\(routineID):2026-11-19"
        let arrived = try (a.changeLog() + b.changeLog()).filter { !($0.entity == "routine_version" && $0.entityID == baseID) }
        let merged = try rebuilt(from: arrived)
        let withRecord = try merged.routines(on: day("2026-11-25"))
        #expect(Set(withRecord.map(\.routine.id)) == [routineID, other.id])
        #expect(try merged.routines(on: day("2026-11-26")).map(\.routine.id) == [other.id])
    }

    @Test("규칙을 동시에 고쳐도 규칙과 기준일이 어긋나지 않는다")
    func repeatPlanMerge() throws {
        let (a, b, clockA, clockB, routineID) = try twoDevices()
        clockA.set("2026-11-23 12:00")
        clockB.set("2026-11-23 12:00")
        try a.updateRoutine(id: routineID, RoutinePatch(repeatRule: try RepeatRule(.everyDays(3))))
        try b.updateRoutine(id: routineID, RoutinePatch(repeatRule: try RepeatRule(.everyDays(3))))
        clockB.set("2026-11-23 13:00")
        try b.updateRoutine(id: routineID, RoutinePatch(repeatRule: try daily()))
        clockA.set("2026-11-23 14:00")
        let saved = try a.updateRoutine(id: routineID, RoutinePatch(repeatRule: try RepeatRule(.everyDays(5))))
        let merged = try rebuilt(from: try a.changeLog() + b.changeLog())
        let version = try #require(try merged.versions(ofRoutine: routineID).last)
        #expect(version.repeatRule == saved.repeatRule)
        #expect(version.repeatAnchor == saved.repeatAnchor)
    }

    @Test("선택 값을 지운 수정도 다음 버전에 이어진다")
    func clearOptionalTitle() throws {
        let store = try makeStore()
        let routine = try store.createRoutine(RoutineDraft(title: "습관", repeatRule: try daily(), miniTitle: "작게"), startDay: day("2026-11-20"))
        let cleared = try store.updateRoutine(id: routine.id, RoutinePatch(miniTitle: .some(nil)))
        #expect(cleared.miniTitle == nil)
        #expect(try store.versions(ofRoutine: routine.id).first?.miniTitle == "작게")
    }

    @Test("편집 중 다른 필드만 저장하면 나머지를 기록하지 않는다")
    func patchKeepsOtherFields() throws {
        let store = try makeStore()
        let task = try store.createTask(TaskDraft(title: "제목", note: "메모"))
        let before = try store.changeLog().count
        try store.updateTask(id: task.id, TaskPatch(note: "새 메모"))
        #expect(try store.changeLog().dropFirst(before).map(\.field) == ["note"])
    }

    @Test("습관 기록의 상태와 횟수는 한 필드로 합쳐진다")
    func outcomeIsOneField() throws {
        let store = try makeStore()
        let routine = try store.createRoutine(RoutineDraft(title: "습관", repeatRule: try daily(), maxCountPerDay: 3))
        try store.setRoutineStatus(id: routine.id, to: .done)
        let fields = try store.changeLog().filter { $0.entity == "routine_record" }.map(\.field)
        #expect(fields.contains("outcome"))
        #expect(!fields.contains("status"))
        #expect(!fields.contains("count"))
        #expect(try store.record(ofRoutine: routine.id, on: store.today())?.count == 3)
    }

    @Test("병합으로 마감이 사라진 반복 일도 읽히고 날짜 없는 일로 남는다")
    func mergedRepeatWithoutDueDay() throws {
        let store = try makeStore()
        let task = try store.createTask(TaskDraft(title: "반복", dueDay: day("2026-11-23"), repeatRule: try daily()))
        try store.write { db, log in
            try log.apply(db, .task, id: task.id, fields: ["due_day": .null])
        }
        let merged = try #require(try store.task(id: task.id))
        #expect(merged.dueDay == nil)
        #expect(merged.repeatRule == nil)
        #expect(try store.undatedTasks().map(\.id) == [task.id])
    }

    @Test("변경 기록만으로 모든 표를 다시 만들 수 있다")
    func replayMatchesTables() throws {
        let clock = TestClock("2026-11-23 17:40")
        let store = try makeStore(clock: clock)
        let task = try store.createTask(TaskDraft(title: "할 일", schedule: .band(.day), dueDay: day("2026-11-23"), repeatRule: try daily()))
        try store.updateTask(id: task.id, TaskPatch(title: "고친 일", schedule: .time(WallTime("19:30")!), dueDay: day("2026-11-23"), weight: .heavy))
        try store.completeTask(id: task.id)
        try store.reopenTask(id: task.id)
        let removed = try store.createTask(TaskDraft(title: "지울 일"))
        try store.deleteTask(id: removed.id)
        let routine = try store.createRoutine(RoutineDraft(title: "습관", cue: "밤", repeatRule: try daily(), miniTitle: "작게"), startDay: day("2026-11-20"))
        try store.setRoutineStatus(id: routine.id, on: day("2026-11-21"), to: .done)
        try store.setRoutineStatus(id: routine.id, on: day("2026-11-21"), to: .rest)
        try store.updateRoutine(id: routine.id, RoutinePatch(title: "고친 습관", repeatRule: try RepeatRule(.everyDays(2))))
        clock.set("2026-11-26 09:00")
        try store.updateRoutine(id: routine.id, RoutinePatch(title: "또 고친 습관", repeatRule: try daily(), maxTitle: "크게"))
        try store.setRoutineStatus(id: routine.id, to: .done)
        try store.deleteRoutine(id: routine.id)

        let merged = FieldMerge.merge(try store.changeLog())
        var checkedRows = 0
        try store.dbQueue.read { db in
            for entity in ChangeEntity.allCases {
                for row in try Row.fetchAll(db, sql: "SELECT * FROM \(entity.rawValue)") {
                    let id: String = row["id"]
                    checkedRows += 1
                    for column in row.columnNames where column != "id" {
                        let stored: DatabaseValue = row[column]
                        let key = FieldKey(entity: entity.rawValue, entityID: id, field: column)
                        // 버전의 빈 칸은 앞 버전을 쓴다는 뜻이라 기록이 없다.
                        #expect((merged[key]?.value ?? .null) == (try FieldValue(stored)), "\(entity.rawValue).\(column)")
                    }
                }
            }
        }
        #expect(checkedRows >= 7)
    }

    @Test("같은 파일을 다시 열어도 데이터와 스키마가 유지된다")
    func reopen() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("doloop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("doloop.sqlite").path
        let clock = TestClock()
        var id = ""
        do {
            let store = try makeStore(clock: clock, path: path)
            id = try store.createTask(TaskDraft(title: "남는 일")).id
        }
        let reopened = try makeStore(clock: clock, path: path)
        #expect(try reopened.task(id: id)?.title == "남는 일")
        #expect(try !reopened.changeLog().isEmpty)
    }

    @Test("계획의 표가 모두 있다")
    func schemaTables() throws {
        let store = try makeStore()
        let tables = try store.dbQueue.read { db in
            try Set(String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'"))
        }
        let expected: Set<String> = [
            "change_log", "task_list", "tag", "task", "task_completion", "checklist_item", "reminder",
            "routine", "routine_version", "routine_record", "routine_group", "mode", "mode_schedule",
            "focus_session", "day_note", "sort_order",
        ]
        #expect(expected.isSubset(of: tables))
    }

    @Test("기기 id가 비면 열지 않는다")
    func emptyDevice() {
        #expect(throws: DoloopError.emptyDeviceID) { try DoloopStore(path: nil, deviceID: "  ") }
    }
}

@Suite("필드별 병합")
struct FieldMergeTests {
    private func entry(_ id: String, device: String, at timestamp: Int64, field: String = "schedule", value: String) -> ChangeEntry {
        ChangeEntry(id: id, deviceID: device, timestamp: timestamp, entity: "task", entityID: "t", field: field, value: .text(value))
    }

    private var key: FieldKey { FieldKey(entity: "task", entityID: "t", field: "schedule") }

    @Test("나중 값이 이긴다")
    func laterWins() {
        let merged = FieldMerge.merge([entry("1", device: "a", at: 10, value: "09:00"), entry("2", device: "b", at: 20, value: "evening")])
        #expect(merged[key]?.value == .text("evening"))
    }

    @Test("시간대와 시각이 어긋나지 않는다")
    func scheduleStaysConsistent() {
        let offlineTime = entry("1", device: "a", at: 10, value: Schedule.time(WallTime("09:00")!).storageValue)
        let laterBand = entry("2", device: "b", at: 20, value: Schedule.band(.evening).storageValue)
        for entries in [[offlineTime, laterBand], [laterBand, offlineTime]] {
            guard case .text(let stored)? = FieldMerge.merge(entries)[key]?.value else {
                Issue.record("병합 값이 없습니다")
                return
            }
            #expect(Schedule(storageValue: stored) == .band(.evening))
        }
    }

    @Test("다른 필드는 서로 지우지 않는다")
    func fieldsIndependent() {
        let merged = FieldMerge.merge([
            entry("1", device: "a", at: 10, field: "title", value: "제목"),
            entry("2", device: "b", at: 20, field: "note", value: "메모"),
        ])
        #expect(merged.count == 2)
    }

    @Test("시각이 같아도 기기마다 결과가 같다")
    func tieBreak() {
        let first = entry("1", device: "a", at: 10, value: "morning")
        let second = entry("2", device: "b", at: 10, value: "evening")
        #expect(FieldMerge.merge([first, second])[key]?.value == .text("evening"))
        #expect(FieldMerge.merge([second, first])[key]?.value == .text("evening"))
    }

    @Test("순서를 바꾸거나 같은 기록을 다시 넣어도 결과가 같다")
    func orderAndDuplicates() {
        let entries = [
            entry("1", device: "a", at: 10, value: "a"), entry("2", device: "b", at: 30, value: "b"),
            entry("3", device: "c", at: 20, value: "c"), entry("4", device: "a", at: 30, value: "d"),
        ]
        let expected = FieldMerge.merge(entries)
        func permutations(_ items: [ChangeEntry]) -> [[ChangeEntry]] {
            guard items.count > 1 else { return [items] }
            return items.indices.flatMap { index -> [[ChangeEntry]] in
                var rest = items
                let head = rest.remove(at: index)
                return permutations(rest).map { [head] + $0 }
            }
        }
        for order in permutations(entries) {
            #expect(FieldMerge.merge(order) == expected)
            #expect(FieldMerge.merge(order + order) == expected)
        }
        #expect(expected[key]?.value == .text("b"))
    }
}
