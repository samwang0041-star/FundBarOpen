import Foundation

enum MarketState: Equatable, Sendable {
    case preOpen
    case open
    case lunchBreak
    case closed
}

enum MarketPhase: Equatable, Sendable {
    case overnight
    case preOpenQuiet
    case preOpenAuction
    case open
    case lunchBreak
    case postClose
    case holidayClosed
}

struct MarketCalendar: Sendable {
    static let calendar = Calendar(identifier: .gregorian)
    static let timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current

    private let calendar: Calendar
    private let formatter: DateFormatter
    private let holidays: Set<String>
    private let makeupDays: Set<String>
    private let nowProvider: @Sendable () -> Date

    init(nowProvider: @escaping @Sendable () -> Date = { .now }) {
        var configuredCalendar = Self.calendar
        configuredCalendar.timeZone = Self.timeZone
        calendar = configuredCalendar

        let formatter = DateFormatter()
        formatter.calendar = configuredCalendar
        formatter.timeZone = Self.timeZone
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        self.formatter = formatter

        holidays = [
            "2025-01-01", "2025-01-28", "2025-01-29", "2025-01-30", "2025-01-31",
            "2025-02-03", "2025-02-04", "2025-04-04", "2025-05-01", "2025-05-02",
            "2025-05-05", "2025-05-30", "2025-10-01", "2025-10-02", "2025-10-03",
            "2025-10-06", "2025-10-07", "2025-10-08",
            "2026-01-01", "2026-01-02", "2026-02-16", "2026-02-17", "2026-02-18",
            "2026-02-19", "2026-02-20", "2026-04-06", "2026-05-01", "2026-05-04",
            "2026-05-05", "2026-06-19", "2026-10-01", "2026-10-02", "2026-10-05",
            "2026-10-06", "2026-10-07", "2026-10-08"
        ]

        // 补班日：周末但需正常上班/交易的日期
        makeupDays = [
            "2025-01-26", "2025-02-08", "2025-04-27", "2025-09-28", "2025-10-11",
            "2026-02-14", "2026-02-28", "2026-05-09", "2026-06-27", "2026-10-10"
        ]

        self.nowProvider = nowProvider
    }

    func todayString(for date: Date? = nil) -> String {
        formatter.string(from: date ?? nowProvider())
    }

    func formatDate(fromUnixMilliseconds milliseconds: Double) -> String {
        todayString(for: Date(timeIntervalSince1970: milliseconds / 1000))
    }

    func isTradingDay(_ date: Date? = nil) -> Bool {
        let date = date ?? nowProvider()
        let dateString = todayString(for: date)
        if holidays.contains(dateString) {
            return false
        }
        if makeupDays.contains(dateString) {
            return true
        }
        let weekday = calendar.component(.weekday, from: date)
        return weekday != 1 && weekday != 7
    }

    func marketState(at date: Date? = nil) -> MarketState {
        switch phase(at: date) {
        case .overnight, .preOpenQuiet, .preOpenAuction:
            return .preOpen
        case .open:
            return .open
        case .lunchBreak:
            return .lunchBreak
        case .postClose, .holidayClosed:
            return .closed
        }
    }

    func isMarketOpen(_ date: Date? = nil) -> Bool {
        switch phase(at: date) {
        case .open, .lunchBreak, .preOpenAuction:
            return true
        case .overnight, .preOpenQuiet, .postClose, .holidayClosed:
            return false
        }
    }

    func phase(at date: Date? = nil) -> MarketPhase {
        let date = date ?? nowProvider()
        guard isTradingDay(date) else {
            return .holidayClosed
        }

        let minutes = minutesSinceMidnight(for: date)
        switch minutes {
        case 0..<540:
            return .overnight
        case 540..<555:
            return .preOpenQuiet
        case 555..<570:
            return .preOpenAuction
        case 570..<690:
            return .open
        case 690..<780:
            return .lunchBreak
        case 780..<900:
            return .open
        default:
            return .postClose
        }
    }

    func refreshInterval(at date: Date? = nil) -> Duration {
        .seconds(refreshIntervalSeconds(at: date))
    }

    func expectedOfficialNavDate(at date: Date? = nil) -> String? {
        let date = date ?? nowProvider()
        switch phase(at: date) {
        case .overnight, .preOpenQuiet, .preOpenAuction, .holidayClosed:
            return previousTradingDayString(before: date)
        case .open, .lunchBreak, .postClose:
            return todayString(for: date)
        }
    }

    func previousTradingDayString(at date: Date? = nil) -> String? {
        previousTradingDayString(before: date ?? nowProvider())
    }

    func nextRefreshDelay(at date: Date? = nil) -> Duration {
        let date = date ?? nowProvider()
        let intervalSeconds = refreshIntervalSeconds(at: date)
        guard let boundary = nextStateBoundary(after: date) else {
            return .seconds(intervalSeconds)
        }

        let secondsUntilBoundary = max(1, Int(ceil(boundary.timeIntervalSince(date))))
        return .seconds(min(intervalSeconds, secondsUntilBoundary))
    }

    private func refreshIntervalSeconds(at date: Date?) -> Int {
        let date = date ?? nowProvider()
        switch phase(at: date) {
        case .open, .preOpenAuction:
            return 15
        case .lunchBreak, .preOpenQuiet:
            return 60
        case .overnight, .postClose, .holidayClosed:
            return 300
        }
    }

    private func nextStateBoundary(after date: Date) -> Date? {
        let minutes = minutesSinceMidnight(for: date)
        switch phase(at: date) {
        case .overnight:
            return sameDayTime(hour: 9, minute: 0, on: date)
        case .preOpenQuiet:
            return sameDayTime(hour: 9, minute: 15, on: date)
        case .preOpenAuction:
            return sameDayTime(hour: 9, minute: 30, on: date)
        case .open where minutes < 690:
            return sameDayTime(hour: 11, minute: 30, on: date)
        case .open:
            return sameDayTime(hour: 15, minute: 0, on: date)
        case .lunchBreak:
            return sameDayTime(hour: 13, minute: 0, on: date)
        case .postClose, .holidayClosed:
            return nextTradingSessionStart(after: date)
        }
    }

    private func nextTradingSessionStart(after date: Date) -> Date? {
        var candidate = calendar.startOfDay(for: date)
        for _ in 0..<30 {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: candidate) else {
                return nil
            }
            candidate = nextDay
            if isTradingDay(candidate) {
                return sameDayTime(hour: 9, minute: 0, on: candidate)
            }
        }
        return nil
    }

    private func previousTradingDayString(before date: Date) -> String? {
        var candidate = calendar.startOfDay(for: date)
        for _ in 0..<30 {
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: candidate) else {
                return nil
            }
            candidate = previousDay
            if isTradingDay(candidate) {
                return todayString(for: candidate)
            }
        }
        return nil
    }

    private func sameDayTime(hour: Int, minute: Int, on date: Date) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components)
    }

    private func minutesSinceMidnight(for date: Date) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}
