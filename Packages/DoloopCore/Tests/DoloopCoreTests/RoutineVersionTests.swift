import Foundation
import Testing
@testable import DoloopCore

@Suite("습관과 버전")
struct RoutineVersionTests {
    @Test("만든 날부터 나온다")
    func create() throws {
        let store = try makeStore()
        let routine = try store.createRoutine(RoutineDraft(title: "일기", cue: "자기 전", schedule: .band(.evening), repeatRule: try daily()))
        #expect(routine.startDay == day("2026-11-23"))
        #expect(try store.routines(on: day("2026-11-22")).isEmpty)
        #expect(try store.routines(on: day("2026-11-23")).first?.version.title == "일기")
        #expect(try store.versions(ofRoutine: routine.id).first?.validAfter == day("2026-11-22"))
    }

    @Test("고치면 내일부터 적용된다")
    func editAppliesTomorrow() throws {
        let store = try makeStore()
        let routine = try store.createRoutine(RoutineDraft(title: "일기 세 줄", repeatRule: try daily()), startDay: day("2026-11-20"))
        let version = try store.updateRoutine(id: routine.id, RoutinePatch(title: "일기 다섯 줄", repeatRule: try daily()))
        #expect(version.validAfter == day("2026-11-23"))
        #expect(try store.routines(on: day("2026-11-23")).first?.version.title == "일기 세 줄")
        #expect(try store.routines(on: day("2026-11-24")).first?.version.title == "일기 다섯 줄")
    }

    @Test("버전을 바꿔도 과거 기록과 제목이 그대로다")
    func pastIsImmutable() throws {
        let clock = TestClock("2026-11-22 20:00")
        let store = try makeStore(clock: clock)
        let routine = try store.createRoutine(RoutineDraft(title: "처음 제목", repeatRule: try daily(), maxCountPerDay: 2), startDay: day("2026-11-20"))
        let done = try #require(try store.setRoutineStatus(id: routine.id, on: day("2026-11-21"), to: .done))
        try store.setRoutineStatus(id: routine.id, on: day("2026-11-22"), to: .rest)
        let before = try [day("2026-11-20"), day("2026-11-21"), day("2026-11-22")].map { try store.routines(on: $0) }

        try store.updateRoutine(id: routine.id, RoutinePatch(title: "바꾼 제목", repeatRule: try RepeatRule(.everyWeeks(1, on: [.monday])), maxCountPerDay: 5))
        clock.set("2026-11-24 12:00")
        try store.updateRoutine(id: routine.id, RoutinePatch(title: "또 바꾼 제목", repeatRule: try daily()))

        let after = try [day("2026-11-20"), day("2026-11-21"), day("2026-11-22")].map { try store.routines(on: $0) }
        #expect(after == before)
        #expect(try store.record(ofRoutine: routine.id, on: day("2026-11-21")) == done)
        #expect(done.count == 2)
    }

    @Test("이미 기록한 날을 고쳐도 기록할 때의 버전을 유지한다")
    func recordKeepsVersion() throws {
        let clock = TestClock("2026-11-23 12:00")
        let store = try makeStore(clock: clock)
        let routine = try store.createRoutine(RoutineDraft(title: "처음", repeatRule: try daily()))
        let first = try #require(try store.setRoutineStatus(id: routine.id, to: .done))
        try store.updateRoutine(id: routine.id, RoutinePatch(title: "나중", repeatRule: try daily()))
        clock.set("2026-11-25 12:00")
        let changed = try #require(try store.setRoutineStatus(id: routine.id, on: day("2026-11-23"), to: .rest))
        #expect(changed.versionID == first.versionID)
        #expect(try store.routines(on: day("2026-11-23")).first?.version.title == "처음")
    }

    @Test("지난날을 뒤늦게 기록하면 그날의 버전을 쓴다")
    func backfillUsesVersionOfDay() throws {
        let clock = TestClock("2026-11-23 12:00")
        let store = try makeStore(clock: clock)
        let routine = try store.createRoutine(RoutineDraft(title: "처음", repeatRule: try daily()), startDay: day("2026-11-20"))
        let original = try #require(try store.versions(ofRoutine: routine.id).first)
        try store.updateRoutine(id: routine.id, RoutinePatch(title: "나중", repeatRule: try daily()))
        clock.set("2026-11-26 12:00")
        let past = try #require(try store.setRoutineStatus(id: routine.id, on: day("2026-11-22"), to: .done))
        let recent = try #require(try store.setRoutineStatus(id: routine.id, on: day("2026-11-25"), to: .done))
        #expect(past.versionID == original.id)
        #expect(recent.versionID != original.id)
    }

    @Test("같은 날 여러 번 고치면 버전 하나로 합쳐진다")
    func sameDayEdits() throws {
        let store = try makeStore()
        let routine = try store.createRoutine(RoutineDraft(title: "처음", repeatRule: try daily()), startDay: day("2026-11-20"))
        try store.updateRoutine(id: routine.id, RoutinePatch(title: "둘째", repeatRule: try daily()))
        try store.updateRoutine(id: routine.id, RoutinePatch(title: "셋째", repeatRule: try daily()))
        let versions = try store.versions(ofRoutine: routine.id)
        #expect(versions.map(\.title) == ["처음", "셋째"])
    }

    @Test("아직 시작하지 않은 습관은 그 자리에서 고친다")
    func editBeforeStart() throws {
        let store = try makeStore()
        let routine = try store.createRoutine(RoutineDraft(title: "처음", repeatRule: try daily()), startDay: day("2026-12-01"))
        try store.updateRoutine(id: routine.id, RoutinePatch(title: "나중", repeatRule: try daily()))
        let versions = try store.versions(ofRoutine: routine.id)
        #expect(versions.map(\.title) == ["나중"])
        #expect(try store.routines(on: day("2026-12-01")).first?.version.title == "나중")
    }

    @Test("반복을 바꾸면 내일이 새 기준일이고 안 바꾸면 기준일을 유지한다")
    func repeatAnchor() throws {
        let store = try makeStore()
        let every2 = try RepeatRule(.everyDays(2))
        let routine = try store.createRoutine(RoutineDraft(title: "격일", repeatRule: every2), startDay: day("2026-11-21"))
        let same = try store.updateRoutine(id: routine.id, RoutinePatch(title: "이름만", repeatRule: every2))
        #expect(same.repeatAnchor == day("2026-11-21"))
        let changed = try store.updateRoutine(id: routine.id, RoutinePatch(title: "이름만", repeatRule: try RepeatRule(.everyDays(3))))
        #expect(changed.repeatAnchor == day("2026-11-24"))
    }

    @Test("규칙을 바꿔도 오늘 할 일은 오늘의 규칙을 따른다")
    func ruleChangeNotToday() throws {
        let store = try makeStore()
        let routine = try store.createRoutine(RoutineDraft(title: "매일", repeatRule: try daily()), startDay: day("2026-11-20"))
        try store.updateRoutine(id: routine.id, RoutinePatch(title: "화요일만", repeatRule: try RepeatRule(.everyWeeks(1, on: [.tuesday]))))
        #expect(try store.routines(on: day("2026-11-23")).count == 1)
        #expect(try store.routines(on: day("2026-11-24")).first?.version.title == "화요일만")
        #expect(try store.routines(on: day("2026-11-25")).isEmpty)
    }

    @Test("쉬는 날과 건너뜀을 기록하고 비울 수 있다")
    func statuses() throws {
        let store = try makeStore()
        let routine = try store.createRoutine(RoutineDraft(title: "습관", repeatRule: try daily()))
        for status in [RoutineStatus.rest, .skipped, .done] {
            let record = try store.setRoutineStatus(id: routine.id, to: status)
            #expect(record?.status == status)
        }
        let cleared = try store.setRoutineStatus(id: routine.id, to: .empty)
        #expect(cleared?.count == 0)
        #expect(try store.routines(on: store.today()).first?.status == .empty)
    }

    @Test("기록이 없는데 비우면 아무것도 남기지 않는다")
    func clearNothing() throws {
        let store = try makeStore()
        let routine = try store.createRoutine(RoutineDraft(title: "습관", repeatRule: try daily()))
        let before = try store.changeLog().count
        #expect(try store.setRoutineStatus(id: routine.id, to: .empty) == nil)
        #expect(try store.changeLog().count == before)
    }

    @Test("주 n회 습관은 쉼을 달성으로 세지 않는다")
    func timesPerWeek() throws {
        let clock = TestClock("2026-11-26 12:00")
        let store = try makeStore(clock: clock)
        let routine = try store.createRoutine(RoutineDraft(title: "운동", repeatRule: try RepeatRule(.timesPerWeek(2))), startDay: day("2026-11-23"))
        try store.setRoutineStatus(id: routine.id, on: day("2026-11-23"), to: .done)
        try store.setRoutineStatus(id: routine.id, on: day("2026-11-24"), to: .rest)
        #expect(try store.routines(on: day("2026-11-25")).count == 1)
        try store.setRoutineStatus(id: routine.id, on: day("2026-11-25"), to: .done)
        #expect(try store.routines(on: day("2026-11-26")).isEmpty)
        #expect(throws: DoloopError.notScheduled) { try store.setRoutineStatus(id: routine.id, on: day("2026-11-26"), to: .done) }
    }

    @Test("시작 전, 미래, 예정 없는 날은 기록할 수 없다")
    func invalidDays() throws {
        let store = try makeStore()
        let routine = try store.createRoutine(RoutineDraft(title: "주말 빼고", repeatRule: try RepeatRule(.everyDays(1), excluding: [.sunday])), startDay: day("2026-11-20"))
        #expect(throws: DoloopError.beforeStart) { try store.setRoutineStatus(id: routine.id, on: day("2026-11-19"), to: .done) }
        #expect(throws: DoloopError.futureDay) { try store.setRoutineStatus(id: routine.id, on: day("2026-11-24"), to: .done) }
        #expect(throws: DoloopError.notScheduled) { try store.setRoutineStatus(id: routine.id, on: day("2026-11-22"), to: .done) }
    }

    @Test("새벽 기록은 전날이고 전날의 버전을 쓴다")
    func earlyMorningRecord() throws {
        let clock = TestClock("2026-11-23 22:00")
        let store = try makeStore(clock: clock)
        let routine = try store.createRoutine(RoutineDraft(title: "처음", repeatRule: try daily()), startDay: day("2026-11-20"))
        try store.updateRoutine(id: routine.id, RoutinePatch(title: "나중", repeatRule: try daily()))
        clock.set("2026-11-24 00:30")
        let record = try #require(try store.setRoutineStatus(id: routine.id, to: .done))
        #expect(record.day == day("2026-11-23"))
        #expect(try store.routines(on: day("2026-11-23")).first?.version.title == "처음")
    }

    @Test("지운 습관은 앞으로 안 나오지만 지난날의 기록은 남는다")
    func deleteKeepsHistory() throws {
        let store = try makeStore()
        let routine = try store.createRoutine(RoutineDraft(title: "습관", repeatRule: try daily()), startDay: day("2026-11-20"))
        try store.setRoutineStatus(id: routine.id, on: day("2026-11-21"), to: .done)
        try store.deleteRoutine(id: routine.id)
        #expect(try store.routines(on: day("2026-11-21")).first?.status == .done)
        #expect(try store.routines(on: day("2026-11-22")).isEmpty)
        #expect(try store.routines(on: store.today()).isEmpty)
        #expect(try store.routines(on: day("2026-11-24")).isEmpty)
    }

    @Test("내용이 같으면 새 버전을 만들지 않는다")
    func noChangeNoVersion() throws {
        let store = try makeStore()
        let rule = try daily()
        let routine = try store.createRoutine(RoutineDraft(title: "같음", cue: "밤", repeatRule: rule), startDay: day("2026-11-20"))
        let before = try store.changeLog().count
        try store.updateRoutine(id: routine.id, RoutinePatch(title: "같음", cue: "밤", repeatRule: rule))
        #expect(try store.versions(ofRoutine: routine.id).count == 1)
        #expect(try store.changeLog().count == before)
    }

    @Test("시간대를 서쪽으로 옮겨도 이미 기록에 쓰인 버전을 고치지 않는다")
    func westwardTimeZone() throws {
        let clock = TestClock("2026-11-23 12:00")
        let zone = TestZone(seoul)
        let store = try DoloopStore(path: nil, deviceID: "mac", timeZone: { zone.value }, clock: { clock.now })
        let routine = try store.createRoutine(RoutineDraft(title: "처음", repeatRule: try daily()), startDay: day("2026-11-20"))
        let used = try store.updateRoutine(id: routine.id, RoutinePatch(title: "기록에 쓰인 제목"))
        clock.set("2026-11-24 12:00")
        let record = try #require(try store.setRoutineStatus(id: routine.id, to: .done))
        #expect(record.versionID == used.id)

        zone.value = TimeZone(identifier: "America/Los_Angeles")!
        #expect(store.today() == day("2026-11-23"))
        let edited = try store.updateRoutine(id: routine.id, RoutinePatch(title: "시간대 옮긴 뒤 제목"))
        #expect(edited.id != used.id)
        #expect(edited.validAfter == day("2026-11-24"))
        #expect(try store.routines(on: day("2026-11-24")).first?.version.title == "기록에 쓰인 제목")
    }

    @Test("같은 날 반복을 되돌리면 원래 기준일로 돌아온다")
    func revertRuleSameDay() throws {
        let store = try makeStore()
        let every2 = try RepeatRule(.everyDays(2))
        let routine = try store.createRoutine(RoutineDraft(title: "격일", repeatRule: every2), startDay: day("2026-11-21"))
        try store.updateRoutine(id: routine.id, RoutinePatch(repeatRule: try RepeatRule(.everyDays(3))))
        let reverted = try store.updateRoutine(id: routine.id, RoutinePatch(repeatRule: every2))
        #expect(reverted.repeatAnchor == day("2026-11-21"))
    }

    @Test("주 n회 습관을 뒤늦게 기록해도 목표를 넘지 않는다")
    func timesPerWeekBackfill() throws {
        let clock = TestClock("2026-11-27 12:00")
        let store = try makeStore(clock: clock)
        let routine = try store.createRoutine(RoutineDraft(title: "운동", repeatRule: try RepeatRule(.timesPerWeek(2))), startDay: day("2026-11-23"))
        try store.setRoutineStatus(id: routine.id, on: day("2026-11-25"), to: .done)
        try store.setRoutineStatus(id: routine.id, on: day("2026-11-26"), to: .done)
        #expect(throws: DoloopError.notScheduled) { try store.setRoutineStatus(id: routine.id, on: day("2026-11-23"), to: .done) }
    }

    @Test("주 n회는 쉼을 달성으로 바꿔도 목표를 넘지 않는다")
    func timesPerWeekRestToDone() throws {
        let clock = TestClock("2026-11-27 12:00")
        let store = try makeStore(clock: clock)
        let routine = try store.createRoutine(RoutineDraft(title: "운동", repeatRule: try RepeatRule(.timesPerWeek(2))), startDay: day("2026-11-23"))
        try store.setRoutineStatus(id: routine.id, on: day("2026-11-23"), to: .rest)
        try store.setRoutineStatus(id: routine.id, on: day("2026-11-25"), to: .done)
        try store.setRoutineStatus(id: routine.id, on: day("2026-11-26"), to: .done)
        #expect(throws: DoloopError.notScheduled) { try store.setRoutineStatus(id: routine.id, on: day("2026-11-23"), to: .done) }
        #expect(try store.record(ofRoutine: routine.id, on: day("2026-11-23"))?.status == .rest)
    }

    @Test("지운 습관은 고치거나 기록할 수 없다")
    func deleteBlocksEdits() throws {
        let store = try makeStore()
        let routine = try store.createRoutine(RoutineDraft(title: "습관", repeatRule: try daily()))
        let record = try store.setRoutineStatus(id: routine.id, to: .done)
        try store.deleteRoutine(id: routine.id)
        #expect(try store.routine(id: routine.id) == nil)
        #expect(try store.record(ofRoutine: routine.id, on: store.today()) == record)
        #expect(throws: DoloopError.deleted) { try store.updateRoutine(id: routine.id, RoutinePatch(title: "x", repeatRule: try daily())) }
        #expect(throws: DoloopError.deleted) { try store.setRoutineStatus(id: routine.id, to: .rest) }
    }

    @Test("잘못된 습관을 거부한다")
    func validation() throws {
        let store = try makeStore()
        #expect(throws: DoloopError.emptyTitle) { try store.createRoutine(RoutineDraft(title: " ", repeatRule: try daily())) }
        #expect(throws: DoloopError.invalidCount) { try store.createRoutine(RoutineDraft(title: "x", repeatRule: try daily(), maxCountPerDay: 0)) }
        #expect(try store.changeLog().isEmpty)
    }
}
