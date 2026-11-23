import Foundation
import Testing
@testable import DoloopCore

@Suite("날짜")
struct LogicalDayTests {
    @Test("문자열로 왕복한다")
    func roundTrip() {
        for text in ["2026-11-23", "2024-02-29", "2000-02-29", "1969-12-31", "0001-01-01", "9999-12-31"] {
            #expect(LogicalDay(text)?.description == text)
        }
    }

    @Test("없는 날짜와 잘못된 형식을 거부한다", arguments: [
        "2026-02-29", "1900-02-29", "2026-13-01", "2026-00-10", "2026-04-31", "2026-1-01", "26-11-23", "2026/11/23", "2026-11-2x", " 2026-11-23", "",
    ])
    func rejectsInvalid(_ text: String) {
        #expect(LogicalDay(text) == nil)
    }

    @Test("요일을 계산한다")
    func weekdays() {
        #expect(day("2026-11-23").weekday == .monday)
        #expect(day("2026-11-29").weekday == .sunday)
        #expect(day("1970-01-01").weekday == .thursday)
        #expect(day("1969-12-29").weekday == .monday)
    }

    @Test("한 주의 시작은 월요일이다")
    func weekStart() {
        #expect(day("2026-11-23").weekStart == day("2026-11-23"))
        #expect(day("2026-11-29").weekStart == day("2026-11-23"))
        #expect(day("2026-11-30").weekStart == day("2026-11-30"))
        #expect(day("2027-01-01").weekStart == day("2026-12-28"))
    }

    @Test("달과 해를 넘겨 더한다")
    func adding() {
        #expect(day("2026-11-30").adding(days: 1) == day("2026-12-01"))
        #expect(day("2026-12-31").adding(days: 1) == day("2027-01-01"))
        #expect(day("2024-02-28").adding(days: 1) == day("2024-02-29"))
        #expect(day("2026-03-01").adding(days: -1) == day("2026-02-28"))
        #expect(day("2027-01-01").days(since: day("2026-01-01")) == 365)
    }
}

@Suite("하루 경계")
struct DayBoundaryTests {
    @Test("새벽 4시 전은 전날이다", arguments: [
        ("2026-11-24 00:00", "2026-11-23"),
        ("2026-11-24 00:30", "2026-11-23"),
        ("2026-11-24 03:59", "2026-11-23"),
        ("2026-11-24 04:00", "2026-11-24"),
        ("2026-11-24 23:59", "2026-11-24"),
        ("2026-12-01 03:00", "2026-11-30"),
        ("2027-01-01 03:00", "2026-12-31"),
        ("2024-03-01 01:00", "2024-02-29"),
    ])
    func boundary(_ wall: String, _ expected: String) {
        #expect(LogicalDay(date: instant(wall), timeZone: seoul) == day(expected))
    }

    @Test("같은 순간도 기기 시간대의 벽시계로 정한다")
    func timeZones() {
        let moment = instant("2026-11-24 02:00", in: seoul)
        #expect(LogicalDay(date: moment, timeZone: seoul) == day("2026-11-23"))
        let utc = TimeZone(identifier: "UTC")!
        #expect(LogicalDay(date: moment, timeZone: utc) == day("2026-11-23"))
        let auckland = TimeZone(identifier: "Pacific/Auckland")!
        #expect(LogicalDay(date: moment, timeZone: auckland) == day("2026-11-24"))
    }

    @Test("일광 절약 시간이 시작하는 날에도 벽시계 4시가 경계다")
    func springForward() {
        let newYork = TimeZone(identifier: "America/New_York")!
        #expect(LogicalDay(date: instant("2026-03-08 03:59", in: newYork), timeZone: newYork) == day("2026-03-07"))
        #expect(LogicalDay(date: instant("2026-03-08 04:00", in: newYork), timeZone: newYork) == day("2026-03-08"))
    }

    @Test("일광 절약 시간이 끝나는 날에도 벽시계 4시가 경계다")
    func fallBack() {
        let newYork = TimeZone(identifier: "America/New_York")!
        let first = instant("2026-11-01 01:30", in: newYork)
        #expect(LogicalDay(date: first, timeZone: newYork) == day("2026-10-31"))
        #expect(LogicalDay(date: first.addingTimeInterval(3_600), timeZone: newYork) == day("2026-10-31"))
        #expect(LogicalDay(date: instant("2026-11-01 03:59", in: newYork), timeZone: newYork) == day("2026-10-31"))
        #expect(LogicalDay(date: instant("2026-11-01 04:00", in: newYork), timeZone: newYork) == day("2026-11-01"))
    }
}

@Suite("시간대")
struct ScheduleTests {
    @Test("시각에서 시간대를 계산한다", arguments: [
        ("00:00", TimeBand.evening), ("00:30", .evening), ("03:59", .evening),
        ("04:00", .morning), ("11:59", .morning),
        ("12:00", .day), ("17:59", .day),
        ("18:00", .evening), ("23:59", .evening),
    ])
    func bands(_ text: String, _ expected: TimeBand) {
        #expect(Schedule.time(WallTime(text)!).band == expected)
    }

    @Test("저장 형식으로 왕복한다", arguments: [
        Schedule.none, .band(.morning), .band(.day), .band(.evening), .time(WallTime("00:30")!), .time(WallTime("19:05")!),
    ])
    func storage(_ schedule: Schedule) {
        #expect(Schedule(storageValue: schedule.storageValue) == schedule)
    }

    @Test("잘못된 값을 거부한다", arguments: ["", "night", "24:00", "12:60", "9:30", "12-30", "١٢:٣٠"])
    func invalid(_ text: String) {
        #expect(Schedule(storageValue: text) == nil)
    }

    @Test("자정 뒤 시각은 그날의 끝으로 정렬한다")
    func ordering() {
        let times = ["00:30", "23:00", "04:00", "03:59", "12:00"].map { WallTime($0)! }.sorted()
        #expect(times.map(\.description) == ["04:00", "12:00", "23:00", "00:30", "03:59"])
    }
}
