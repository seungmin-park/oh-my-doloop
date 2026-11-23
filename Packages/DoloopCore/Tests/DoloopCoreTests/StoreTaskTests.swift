import Foundation
import Testing
@testable import DoloopCore

@Suite("할 일 저장소")
struct StoreTaskTests {
    @Test("만들고 읽는다")
    func create() throws {
        let store = try makeStore()
        let task = try store.createTask(TaskDraft(title: "  장보기  ", note: "우유", schedule: .band(.evening), dueDay: day("2026-11-23"), weight: .heavy))
        #expect(task.title == "장보기")
        #expect(try store.task(id: task.id) == task)
        #expect(try store.tasks(on: day("2026-11-23")).map(\.task.id) == [task.id])
    }

    @Test("빈 제목을 거부하고 아무것도 남기지 않는다")
    func emptyTitle() throws {
        let store = try makeStore()
        #expect(throws: DoloopError.emptyTitle) { try store.createTask(TaskDraft(title: "   ")) }
        #expect(try store.changeLog().isEmpty)
    }

    @Test("고치면 그 값으로 읽힌다")
    func update() throws {
        let store = try makeStore()
        let task = try store.createTask(TaskDraft(title: "처음", dueDay: day("2026-11-23")))
        let updated = try store.updateTask(id: task.id, TaskPatch(title: "나중", schedule: .time(WallTime("19:30")!), dueDay: day("2026-11-24"), weight: .heavy))
        #expect(updated.title == "나중")
        #expect(updated.schedule.band == .evening)
        #expect(try store.tasks(on: day("2026-11-23")).isEmpty)
        #expect(try store.tasks(on: day("2026-11-24")).count == 1)
    }

    @Test("지운 일은 안 보이고 고칠 수 없다")
    func delete() throws {
        let store = try makeStore()
        let task = try store.createTask(TaskDraft(title: "지울 일", dueDay: day("2026-11-23")))
        try store.deleteTask(id: task.id)
        #expect(try store.task(id: task.id) == nil)
        #expect(try store.tasks(on: day("2026-11-23")).isEmpty)
        #expect(throws: DoloopError.deleted) { try store.updateTask(id: task.id, TaskPatch(title: "수정")) }
        #expect(throws: DoloopError.deleted) { try store.deleteTask(id: task.id) }
        #expect(throws: DoloopError.deleted) { try store.completeTask(id: task.id, on: day("2026-11-23")) }
    }

    @Test("없는 일은 찾지 못한다")
    func missing() throws {
        let store = try makeStore()
        #expect(throws: DoloopError.notFound) { try store.updateTask(id: "없음", TaskPatch(title: "수정")) }
        #expect(try store.task(id: "없음") == nil)
    }

    @Test("날짜 없는 일은 따로 모이고 완료하면 빠진다")
    func undated() throws {
        let store = try makeStore()
        let task = try store.createTask(TaskDraft(title: "언젠가"))
        #expect(try store.undatedTasks().map(\.id) == [task.id])
        #expect(try store.tasks(on: store.today()).isEmpty)
        try store.completeTask(id: task.id)
        #expect(try store.undatedTasks().isEmpty)
        #expect(try store.tasks(on: store.today()).first?.isCompleted == true)
    }

    @Test("끝낸 날이 지나도 날짜 없는 일을 찾아 되돌릴 수 있다")
    func reopenUndatedLater() throws {
        let clock = TestClock("2026-11-23 12:00")
        let store = try makeStore(clock: clock)
        let task = try store.createTask(TaskDraft(title: "언젠가"))
        try store.completeTask(id: task.id)
        clock.set("2026-11-25 12:00")
        #expect(try store.tasks(on: day("2026-11-23")).first?.isCompleted == true)
        try store.reopenTask(id: task.id)
        #expect(try store.undatedTasks().map(\.id) == [task.id])
        #expect(try store.tasks(on: day("2026-11-23")).isEmpty)
    }

    @Test("마감 전에 끝내면 끝낸 날에 기록한다")
    func completeEarly() throws {
        let store = try makeStore()
        let task = try store.createTask(TaskDraft(title: "내일 마감", dueDay: day("2026-11-25")))
        try store.completeTask(id: task.id)
        #expect(try store.task(id: task.id)?.completedDay == day("2026-11-23"))
        #expect(try store.tasks(on: day("2026-11-23")).first?.isCompleted == true)
        #expect(try store.tasks(on: day("2026-11-25")).isEmpty)
    }

    @Test("끝낸 일의 마감을 옮겨도 완료가 유지된다")
    func moveCompleted() throws {
        let store = try makeStore()
        let task = try store.createTask(TaskDraft(title: "끝낸 일", dueDay: day("2026-11-23")))
        try store.completeTask(id: task.id)
        try store.updateTask(id: task.id, TaskPatch(dueDay: day("2026-11-24")))
        #expect(try store.tasks(on: day("2026-11-23")).first?.isCompleted == true)
        #expect(try store.tasks(on: day("2026-11-24")).isEmpty)
    }

    @Test("반복의 기준일을 옮겨도 전에 끝낸 날이 남는다")
    func moveRepeatAnchor() throws {
        let clock = TestClock("2026-11-23 12:00")
        let store = try makeStore(clock: clock)
        let task = try store.createTask(TaskDraft(title: "매일", dueDay: day("2026-11-22"), repeatRule: try daily()))
        try store.completeTask(id: task.id, on: day("2026-11-22"))
        try store.updateTask(id: task.id, TaskPatch(dueDay: day("2026-11-25")))
        #expect(try store.tasks(on: day("2026-11-22")).first?.isCompleted == true)
        #expect(try store.tasks(on: day("2026-11-23")).isEmpty)
    }

    @Test("마감을 지우려면 반복도 함께 지워야 한다")
    func clearDueDay() throws {
        let store = try makeStore()
        let task = try store.createTask(TaskDraft(title: "반복", dueDay: day("2026-11-23"), repeatRule: try daily()))
        #expect(throws: DoloopError.repeatNeedsDueDay) { try store.updateTask(id: task.id, TaskPatch(dueDay: .some(nil))) }
        let cleared = try store.updateTask(id: task.id, TaskPatch(dueDay: .some(nil), repeatRule: .some(nil)))
        #expect(cleared.dueDay == nil)
        #expect(cleared.repeatRule == nil)
    }

    @Test("반복하는 일은 날짜마다 따로 완료한다")
    func repeating() throws {
        let clock = TestClock("2026-11-25 12:00")
        let store = try makeStore(clock: clock)
        let task = try store.createTask(TaskDraft(title: "물주기", dueDay: day("2026-11-23"), repeatRule: try RepeatRule(.everyDays(2))))
        #expect(try store.tasks(on: day("2026-11-24")).isEmpty)
        try store.completeTask(id: task.id, on: day("2026-11-23"))
        #expect(try store.tasks(on: day("2026-11-23")).first?.isCompleted == true)
        #expect(try store.tasks(on: day("2026-11-25")).first?.isCompleted == false)
        #expect(throws: DoloopError.notScheduled) { try store.completeTask(id: task.id, on: day("2026-11-24")) }
    }

    @Test("주 n회 할 일은 채우면 그 주에 안 나오지만 끝낸 날은 남는다")
    func timesPerWeek() throws {
        let clock = TestClock("2026-11-26 12:00")
        let store = try makeStore(clock: clock)
        let task = try store.createTask(TaskDraft(title: "청소", dueDay: day("2026-11-23"), repeatRule: try RepeatRule(.timesPerWeek(2))))
        try store.completeTask(id: task.id, on: day("2026-11-23"))
        try store.completeTask(id: task.id, on: day("2026-11-24"))
        #expect(try store.tasks(on: day("2026-11-24")).first?.isCompleted == true)
        #expect(try store.tasks(on: day("2026-11-25")).isEmpty)
        #expect(try store.tasks(on: day("2026-11-30")).count == 1)
    }

    @Test("주 n회 할 일을 뒤늦게 기록해도 목표를 넘지 않는다")
    func timesPerWeekBackfill() throws {
        let clock = TestClock("2026-11-27 12:00")
        let store = try makeStore(clock: clock)
        let task = try store.createTask(TaskDraft(title: "청소", dueDay: day("2026-11-23"), repeatRule: try RepeatRule(.timesPerWeek(2))))
        try store.completeTask(id: task.id, on: day("2026-11-25"))
        try store.completeTask(id: task.id, on: day("2026-11-26"))
        #expect(throws: DoloopError.notScheduled) { try store.completeTask(id: task.id, on: day("2026-11-23")) }
    }

    @Test("미래 날짜는 완료할 수 없다")
    func future() throws {
        let store = try makeStore()
        let task = try store.createTask(TaskDraft(title: "내일 일", dueDay: day("2026-11-24")))
        // 오늘 끝내는 것은 되지만 내일 날짜로 미리 기록할 수는 없다.
        #expect(throws: DoloopError.futureDay) { try store.completeTask(id: task.id, on: day("2026-11-24")) }
    }

    @Test("새벽에 완료하면 전날 기록이다")
    func earlyMorning() throws {
        let clock = TestClock("2026-11-24 00:30")
        let store = try makeStore(clock: clock)
        let task = try store.createTask(TaskDraft(title: "밤일", dueDay: day("2026-11-23")))
        try store.completeTask(id: task.id)
        #expect(try store.tasks(on: day("2026-11-23")).first?.isCompleted == true)
    }

    @Test("반복은 기준일이 필요하고 영원히 안 오는 규칙은 거부한다")
    func repeatValidation() throws {
        let store = try makeStore()
        #expect(throws: DoloopError.repeatNeedsDueDay) { try store.createTask(TaskDraft(title: "x", repeatRule: try daily())) }
        let never = try RepeatRule(.everyDays(7), excluding: [.monday])
        #expect(throws: DoloopError.repeatNeverOccurs) {
            try store.createTask(TaskDraft(title: "x", dueDay: day("2026-11-23"), repeatRule: never))
        }
    }

    @Test("하루 안에서 시간 순으로 정렬하고 정하지 않은 일은 뒤에 둔다")
    func ordering() throws {
        let store = try makeStore()
        let target = day("2026-11-23")
        for (title, schedule) in [("없음", Schedule.none), ("새벽", .time(WallTime("00:30")!)), ("저녁", .band(.evening)), ("아침", .time(WallTime("07:00")!)), ("낮", .band(.day))] {
            try store.createTask(TaskDraft(title: title, schedule: schedule, dueDay: target))
        }
        #expect(try store.tasks(on: target).map(\.task.title) == ["아침", "낮", "저녁", "새벽", "없음"])
    }
}
