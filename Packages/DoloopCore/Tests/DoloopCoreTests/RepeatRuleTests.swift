import Foundation
import Testing
@testable import DoloopCore

@Suite("반복 규칙")
struct RepeatRuleTests {
    private func days(_ rule: RepeatRule, anchor: String, from: String, to: String) -> [String] {
        var result: [String] = []
        var cursor = day(from)
        while cursor <= day(to) {
            if rule.occurs(on: cursor, anchor: day(anchor)) { result.append(cursor.description) }
            cursor = cursor.adding(days: 1)
        }
        return result
    }

    @Test("n일마다")
    func everyDays() throws {
        let rule = try RepeatRule(.everyDays(3))
        #expect(days(rule, anchor: "2026-11-23", from: "2026-11-20", to: "2026-12-02")
            == ["2026-11-23", "2026-11-26", "2026-11-29", "2026-12-02"])
    }

    @Test("예외 요일은 밀지 않고 건너뛴다")
    func excludedDays() throws {
        let rule = try RepeatRule(.everyDays(1), excluding: [.saturday, .sunday])
        #expect(days(rule, anchor: "2026-11-27", from: "2026-11-27", to: "2026-12-01")
            == ["2026-11-27", "2026-11-30", "2026-12-01"])
    }

    @Test("n주마다 지정한 요일")
    func everyWeeks() throws {
        let rule = try RepeatRule(.everyWeeks(2, on: [.monday, .sunday]))
        #expect(days(rule, anchor: "2026-11-25", from: "2026-11-23", to: "2026-12-13")
            == ["2026-11-29", "2026-12-07", "2026-12-13"])
    }

    @Test("주는 월요일에 바뀐다")
    func weekBoundary() throws {
        let rule = try RepeatRule(.everyWeeks(2, on: [.sunday]))
        #expect(days(rule, anchor: "2026-11-29", from: "2026-11-29", to: "2026-12-13") == ["2026-11-29", "2026-12-13"])
    }

    @Test("n개월마다")
    func everyMonths() throws {
        let rule = try RepeatRule(.everyMonths(2, dayOfMonth: 15))
        #expect(days(rule, anchor: "2026-11-15", from: "2026-11-01", to: "2027-03-31")
            == ["2026-11-15", "2027-01-15", "2027-03-15"])
    }

    @Test("그달에 없는 날짜는 말일에 온다")
    func monthEnd() throws {
        let rule = try RepeatRule(.everyMonths(1, dayOfMonth: 31))
        #expect(days(rule, anchor: "2027-01-31", from: "2027-01-01", to: "2027-04-30")
            == ["2027-01-31", "2027-02-28", "2027-03-31", "2027-04-30"])
        #expect(rule.occurs(on: day("2028-02-29"), anchor: day("2027-01-31")))
        #expect(!rule.occurs(on: day("2028-02-28"), anchor: day("2027-01-31")))
    }

    @Test("기준일 전에는 오지 않는다")
    func beforeAnchor() throws {
        let rule = try RepeatRule(.everyMonths(1, dayOfMonth: 15))
        #expect(!rule.occurs(on: day("2026-11-15"), anchor: day("2026-11-20")))
        #expect(rule.occurs(on: day("2026-12-15"), anchor: day("2026-11-20")))
    }

    @Test("주 n회는 채우면 그 주에 더 나오지 않는다")
    func timesPerWeek() throws {
        let rule = try RepeatRule(.timesPerWeek(3), excluding: [.sunday])
        let anchor = day("2026-11-23")
        #expect(rule.occurs(on: day("2026-11-25"), anchor: anchor, completedOtherDaysThisWeek: 2))
        #expect(!rule.occurs(on: day("2026-11-25"), anchor: anchor, completedOtherDaysThisWeek: 3))
        #expect(!rule.occurs(on: day("2026-11-29"), anchor: anchor, completedOtherDaysThisWeek: 0))
    }

    @Test("잘못된 규칙을 거부한다")
    func validation() {
        #expect(throws: RepeatRuleError.invalidInterval) { try RepeatRule(.everyDays(0)) }
        #expect(throws: RepeatRuleError.invalidInterval) { try RepeatRule(.everyWeeks(53, on: [.monday])) }
        #expect(throws: RepeatRuleError.invalidInterval) { try RepeatRule(.everyMonths(25, dayOfMonth: 1)) }
        #expect(throws: RepeatRuleError.noWeekdays) { try RepeatRule(.everyWeeks(1, on: [])) }
        #expect(throws: RepeatRuleError.invalidDayOfMonth) { try RepeatRule(.everyMonths(1, dayOfMonth: 32)) }
        #expect(throws: RepeatRuleError.invalidCount) { try RepeatRule(.timesPerWeek(0)) }
        #expect(throws: RepeatRuleError.invalidCount) { try RepeatRule(.timesPerWeek(6), excluding: [.saturday, .sunday]) }
        #expect(throws: RepeatRuleError.allDaysExcluded) { try RepeatRule(.everyDays(1), excluding: Set(Weekday.allCases)) }
        #expect(throws: RepeatRuleError.allDaysExcluded) { try RepeatRule(.everyWeeks(1, on: [.sunday]), excluding: [.sunday]) }
    }

    @Test("영원히 오지 않는 규칙을 찾는다")
    func neverOccurs() throws {
        let rule = try RepeatRule(.everyDays(7), excluding: [.monday])
        #expect(rule.nextOccurrence(onOrAfter: day("2026-11-23"), anchor: day("2026-11-23")) == nil)
        #expect(rule.nextOccurrence(onOrAfter: day("2026-11-24"), anchor: day("2026-11-24")) == day("2026-11-24"))
    }

    @Test("저장 형식은 요일 순서와 무관하게 같다")
    func stableStorage() throws {
        let first = try RepeatRule(.everyWeeks(2, on: [.friday, .monday, .wednesday]), excluding: [.sunday, .saturday])
        let second = try RepeatRule(.everyWeeks(2, on: [.wednesday, .friday, .monday]), excluding: [.saturday, .sunday])
        #expect(first.storageValue == second.storageValue)
        #expect(RepeatRule(storageValue: first.storageValue) == first)
    }

    @Test("모든 종류가 저장 형식으로 왕복한다")
    func roundTrip() throws {
        let rules = [
            try RepeatRule(.everyDays(2)),
            try RepeatRule(.everyWeeks(1, on: [.monday])),
            try RepeatRule(.everyMonths(3, dayOfMonth: 31), excluding: [.sunday]),
            try RepeatRule(.timesPerWeek(3)),
        ]
        for rule in rules {
            #expect(RepeatRule(storageValue: rule.storageValue) == rule)
        }
    }

    @Test("손상된 저장값은 규칙이 되지 않는다", arguments: [
        "", "{}", #"{"kind":"days"}"#, #"{"kind":"days","every":0}"#, #"{"kind":"weeks","every":1,"weekdays":[8]}"#, #"{"kind":"other","every":1}"#,
    ])
    func corrupt(_ text: String) {
        #expect(RepeatRule(storageValue: text) == nil)
    }
}
