/// 기기 현지의 시각. 시간대 정보 없이 벽시계 값만 가진다.
public struct WallTime: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let hour: Int
    public let minute: Int

    public init?(hour: Int, minute: Int) {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        self.hour = hour
        self.minute = minute
    }

    /// `HH:mm`만 받는다.
    public init?(_ text: String) {
        let bytes = Array(text.utf8)
        guard bytes.count == 5, bytes[2] == 58,
              bytes.enumerated().allSatisfy({ $0.offset == 2 || (48...57).contains($0.element) }),
              let hour = Int(text.prefix(2)), let minute = Int(text.suffix(2))
        else { return nil }
        self.init(hour: hour, minute: minute)
    }

    public var description: String {
        "\(hour < 10 ? "0" : "")\(hour):\(minute < 10 ? "0" : "")\(minute)"
    }

    /// 하루가 시작하는 새벽 4시부터 지난 분. 00:30은 23:00보다 뒤에 온다.
    public var minutesFromDayStart: Int {
        (hour * 60 + minute - DayBoundary.startHour * 60 + 1_440) % 1_440
    }

    public static func < (lhs: WallTime, rhs: WallTime) -> Bool {
        lhs.minutesFromDayStart < rhs.minutesFromDayStart
    }
}

public enum TimeBand: String, CaseIterable, Codable, Hashable, Sendable {
    case morning, day, evening

    /// 아침 4~12시, 낮 12~18시, 저녁 18시부터 다음 날 4시 전까지.
    public init(time: WallTime) {
        switch time.hour {
        case 4..<12: self = .morning
        case 12..<18: self = .day
        default: self = .evening
        }
    }

    var startMinutesFromDayStart: Int {
        switch self {
        case .morning: 0
        case .day: 480
        case .evening: 840
        }
    }
}

/// 언제 할지. 시간대와 시각을 한 값으로 묶어서 필드별 병합 뒤에도 둘이 어긋나지 않는다.
public enum Schedule: Hashable, Sendable {
    case none
    case band(TimeBand)
    case time(WallTime)

    /// 시각이 있으면 시간대는 저장하지 않고 시각에서 계산한다.
    public var band: TimeBand? {
        switch self {
        case .none: nil
        case .band(let band): band
        case .time(let time): TimeBand(time: time)
        }
    }

    var storageValue: String {
        switch self {
        case .none: "none"
        case .band(let band): band.rawValue
        case .time(let time): time.description
        }
    }

    init?(storageValue: String) {
        if storageValue == "none" {
            self = .none
        } else if let band = TimeBand(rawValue: storageValue) {
            self = .band(band)
        } else if let time = WallTime(storageValue) {
            self = .time(time)
        } else {
            return nil
        }
    }

    /// 하루 안의 정렬 위치. 정하지 않은 일은 맨 뒤에 온다.
    var sortPosition: Int {
        switch self {
        case .none: Int.max
        case .band(let band): band.startMinutesFromDayStart
        case .time(let time): time.minutesFromDayStart
        }
    }
}
