import Foundation

public enum RepeatRuleError: Error, Equatable, Sendable {
    case invalidInterval
    case noWeekdays
    case invalidDayOfMonth
    case invalidCount
    case allDaysExcluded
}

/// 반복 규칙. 예외 요일에 걸린 날은 다른 날로 밀지 않고 건너뛴다.
public struct RepeatRule: Hashable, Codable, Sendable {
    public enum Cadence: Hashable, Sendable {
        case everyDays(Int)
        case everyWeeks(Int, on: Set<Weekday>)
        /// 그달에 그 날짜가 없으면 말일에 온다.
        case everyMonths(Int, dayOfMonth: Int)
        /// 요일을 정하지 않고 한 주(월~일)에 n번 한다.
        case timesPerWeek(Int)
    }

    public let cadence: Cadence
    public let excludedWeekdays: Set<Weekday>

    public init(_ cadence: Cadence, excluding excludedWeekdays: Set<Weekday> = []) throws {
        guard excludedWeekdays.count < Weekday.allCases.count else { throw RepeatRuleError.allDaysExcluded }
        switch cadence {
        case .everyDays(let every):
            guard (1...365).contains(every) else { throw RepeatRuleError.invalidInterval }
        case .everyWeeks(let every, let weekdays):
            guard (1...52).contains(every) else { throw RepeatRuleError.invalidInterval }
            guard !weekdays.isEmpty else { throw RepeatRuleError.noWeekdays }
            guard !weekdays.isSubset(of: excludedWeekdays) else { throw RepeatRuleError.allDaysExcluded }
        case .everyMonths(let every, let dayOfMonth):
            guard (1...24).contains(every) else { throw RepeatRuleError.invalidInterval }
            guard (1...31).contains(dayOfMonth) else { throw RepeatRuleError.invalidDayOfMonth }
        case .timesPerWeek(let count):
            guard (1...7).contains(count), count <= 7 - excludedWeekdays.count else {
                throw RepeatRuleError.invalidCount
            }
        }
        self.cadence = cadence
        self.excludedWeekdays = excludedWeekdays
    }

    /// 주 n회는 `completedOtherDaysThisWeek`에 같은 주의 다른 날 끝낸 횟수를 넘긴다.
    public func occurs(on day: LogicalDay, anchor: LogicalDay, completedOtherDaysThisWeek: Int = 0) -> Bool {
        guard day >= anchor, !excludedWeekdays.contains(day.weekday) else { return false }
        switch cadence {
        case .everyDays(let every):
            return day.days(since: anchor) % every == 0
        case .everyWeeks(let every, let weekdays):
            let weeks = day.weekStart.days(since: anchor.weekStart) / 7
            return weekdays.contains(day.weekday) && weeks % every == 0
        case .everyMonths(let every, let dayOfMonth):
            let months = day.monthIndex - anchor.monthIndex
            return months % every == 0 && day.day == min(dayOfMonth, day.lastDayOfMonth)
        case .timesPerWeek(let count):
            return completedOtherDaysThisWeek < count
        }
    }

    /// 규칙의 가장 긴 주기를 일곱 번 돌아도 안 오면 영원히 오지 않는 규칙이다.
    public func nextOccurrence(onOrAfter day: LogicalDay, anchor: LogicalDay) -> LogicalDay? {
        var candidate = max(day, anchor)
        for _ in 0..<(366 * 15) {
            if occurs(on: candidate, anchor: anchor) { return candidate }
            candidate = candidate.adding(days: 1)
        }
        return nil
    }

    private struct Payload: Codable {
        var kind: String
        var every: Int?
        var weekdays: [Int]?
        var dayOfMonth: Int?
        var count: Int?
        var except: [Int]?
    }

    public func encode(to encoder: Encoder) throws {
        var payload: Payload
        switch cadence {
        case .everyDays(let every):
            payload = Payload(kind: "days", every: every)
        case .everyWeeks(let every, let weekdays):
            payload = Payload(kind: "weeks", every: every, weekdays: weekdays.map(\.rawValue).sorted())
        case .everyMonths(let every, let dayOfMonth):
            payload = Payload(kind: "months", every: every, dayOfMonth: dayOfMonth)
        case .timesPerWeek(let count):
            payload = Payload(kind: "timesPerWeek", count: count)
        }
        if !excludedWeekdays.isEmpty {
            payload.except = excludedWeekdays.map(\.rawValue).sorted()
        }
        try payload.encode(to: encoder)
    }

    public init(from decoder: Decoder) throws {
        let payload = try Payload(from: decoder)
        func weekdays(_ raw: [Int]?) throws -> Set<Weekday> {
            try Set((raw ?? []).map { value in
                guard let weekday = Weekday(rawValue: value) else {
                    throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "잘못된 요일: \(value)"))
                }
                return weekday
            })
        }
        func required(_ value: Int?) throws -> Int {
            guard let value else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "반복 값이 없습니다"))
            }
            return value
        }
        let cadence: Cadence
        switch payload.kind {
        case "days": cadence = .everyDays(try required(payload.every))
        case "weeks": cadence = .everyWeeks(try required(payload.every), on: try weekdays(payload.weekdays))
        case "months": cadence = .everyMonths(try required(payload.every), dayOfMonth: try required(payload.dayOfMonth))
        case "timesPerWeek": cadence = .timesPerWeek(try required(payload.count))
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "잘못된 반복: \(payload.kind)"))
        }
        try self.init(cadence, excluding: try weekdays(payload.except))
    }

    /// 같은 규칙은 항상 같은 문자열이 되어 변경 기록에 헛된 수정이 남지 않는다.
    var storageValue: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else {
            preconditionFailure("반복 규칙을 저장 형식으로 바꿀 수 없습니다")
        }
        return text
    }

    init?(storageValue: String) {
        guard let data = storageValue.data(using: .utf8),
              let rule = try? JSONDecoder().decode(RepeatRule.self, from: data)
        else { return nil }
        self = rule
    }
}
