import Foundation

public enum DayBoundary {
    /// 하루가 바뀌는 시각. 그 전의 기록은 전날 밤으로 친다.
    public static let startHour = 4
}

extension LogicalDay {
    /// 벽시계 시각으로 하루를 정한다. 절대 시간에서 4시간을 빼면 일광 절약 시간이 바뀌는 날 어긋난다.
    public init(date: Date, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        guard let year = parts.year, let month = parts.month, let dayOfMonth = parts.day, let hour = parts.hour,
              let civilDay = LogicalDay(year: year, month: month, day: dayOfMonth)
        else {
            preconditionFailure("표현할 수 없는 날짜: \(date)")
        }
        self = hour < DayBoundary.startHour ? civilDay.adding(days: -1) : civilDay
    }
}
