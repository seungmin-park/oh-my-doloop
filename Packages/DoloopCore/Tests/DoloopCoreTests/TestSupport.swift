import Foundation
@testable import DoloopCore

let seoul = TimeZone(identifier: "Asia/Seoul")!

func day(_ text: String) -> LogicalDay {
    LogicalDay(text)!
}

/// `2026-11-23 17:40`을 그 시간대의 벽시계 시각으로 읽는다.
func instant(_ text: String, in timeZone: TimeZone = seoul) -> Date {
    let parts = text.split(separator: " ")
    let date = parts[0].split(separator: "-").map { Int($0)! }
    let time = parts[1].split(separator: ":").map { Int($0)! }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar.date(from: DateComponents(year: date[0], month: date[1], day: date[2], hour: time[0], minute: time[1]))!
}

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ text: String = "2026-11-23 17:40") {
        current = instant(text)
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func set(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        current = instant(text)
    }
}

final class TestZone: @unchecked Sendable {
    private let lock = NSLock()
    private var current: TimeZone

    init(_ zone: TimeZone) {
        current = zone
    }

    var value: TimeZone {
        get {
            lock.lock()
            defer { lock.unlock() }
            return current
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            current = newValue
        }
    }
}

func makeStore(device: String = "mac", clock: TestClock = TestClock(), path: String? = nil) throws -> DoloopStore {
    try DoloopStore(path: path, deviceID: device, timeZone: { seoul }, clock: { clock.now })
}

func daily() throws -> RepeatRule {
    try RepeatRule(.everyDays(1))
}
