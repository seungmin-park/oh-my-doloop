import Foundation

public enum Weekday: Int, CaseIterable, Comparable, Codable, Hashable, Sendable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// 시간대가 없는 하루. 기록의 날짜는 이 값으로 저장해서 기기 시간대가 바뀌어도 달라지지 않는다.
public struct LogicalDay: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    /// 1970-01-01부터 센 날 수.
    let serial: Int

    init(serial: Int) {
        self.serial = serial
    }

    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year),
              (1...12).contains(month),
              (1...Self.daysInMonth(year: year, month: month)).contains(day)
        else { return nil }
        serial = Self.serial(year: year, month: month, day: day)
    }

    /// `YYYY-MM-DD`만 받는다.
    public init?(_ text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard text.utf8.count == 10, parts.count == 3,
              parts[0].utf8.count == 4, parts[1].utf8.count == 2, parts[2].utf8.count == 2,
              parts.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) } }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let day = LogicalDay(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "잘못된 날짜: \(text)")
        }
        self = day
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    public static func < (lhs: LogicalDay, rhs: LogicalDay) -> Bool {
        lhs.serial < rhs.serial
    }

    public var year: Int { civil.year }
    public var month: Int { civil.month }
    public var day: Int { civil.day }

    public var description: String {
        let value = civil
        return String(format: "%04d-%02d-%02d", value.year, value.month, value.day)
    }

    public var weekday: Weekday {
        // 1970-01-01은 목요일이다.
        Weekday(rawValue: Self.modulo(serial + 3, 7) + 1)!
    }

    public func adding(days: Int) -> LogicalDay {
        LogicalDay(serial: serial + days)
    }

    public func days(since other: LogicalDay) -> Int {
        serial - other.serial
    }

    /// 이 날이 속한 주의 월요일.
    public var weekStart: LogicalDay {
        adding(days: 1 - weekday.rawValue)
    }

    var monthIndex: Int {
        let value = civil
        return value.year * 12 + value.month - 1
    }

    var lastDayOfMonth: Int {
        let value = civil
        return Self.daysInMonth(year: value.year, month: value.month)
    }

    private var civil: (year: Int, month: Int, day: Int) {
        let shifted = serial + 719_468
        let era = Self.floorDivide(shifted, 146_097)
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthPart = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthPart + 2) / 5 + 1
        let month = monthPart < 10 ? monthPart + 3 : monthPart - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        return (year, month, day)
    }

    private static func serial(year: Int, month: Int, day: Int) -> Int {
        let shiftedYear = month <= 2 ? year - 1 : year
        let era = floorDivide(shiftedYear, 400)
        let yearOfEra = shiftedYear - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    private static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2:
            let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            return leap ? 29 : 28
        case 4, 6, 9, 11:
            return 30
        default:
            return 31
        }
    }

    private static func floorDivide(_ value: Int, _ divisor: Int) -> Int {
        let quotient = value / divisor
        return value % divisor != 0 && (value < 0) != (divisor < 0) ? quotient - 1 : quotient
    }

    private static func modulo(_ value: Int, _ divisor: Int) -> Int {
        value - floorDivide(value, divisor) * divisor
    }
}
