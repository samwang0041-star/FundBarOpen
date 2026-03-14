import XCTest
@testable import FundBar

final class MarketCalendarTests: XCTestCase {
    private let calendar = MarketCalendar()

    func testMarketStateAndRefreshIntervalDuringTradingHours() {
        let openDate = makeDate(year: 2026, month: 3, day: 13, hour: 10, minute: 0)
        XCTAssertEqual(calendar.marketState(at: openDate), .open)
        XCTAssertEqual(calendar.refreshInterval(at: openDate), .seconds(15))
    }

    func testPreOpenPhasesUseExpectedRefreshIntervals() {
        let quietDate = makeDate(year: 2026, month: 3, day: 16, hour: 9, minute: 5)
        let auctionDate = makeDate(year: 2026, month: 3, day: 16, hour: 9, minute: 25)

        XCTAssertEqual(calendar.phase(at: quietDate), .preOpenQuiet)
        XCTAssertEqual(calendar.phase(at: auctionDate), .preOpenAuction)
        XCTAssertEqual(calendar.refreshInterval(at: quietDate), .seconds(60))
        XCTAssertEqual(calendar.refreshInterval(at: auctionDate), .seconds(15))
    }

    func testLunchBreakAndHolidayAreNotOpen() {
        let lunchDate = makeDate(year: 2026, month: 3, day: 13, hour: 12, minute: 0)
        let holidayDate = makeDate(year: 2026, month: 10, day: 1, hour: 10, minute: 0)

        XCTAssertEqual(calendar.marketState(at: lunchDate), .lunchBreak)
        XCTAssertEqual(calendar.refreshInterval(at: lunchDate), .seconds(60))
        XCTAssertEqual(calendar.phase(at: holidayDate), .holidayClosed)
    }

    func testPreOpenDelaySleepsUntilOpenBoundary() {
        let date = makeDate(year: 2026, month: 3, day: 13, hour: 9, minute: 25)
        XCTAssertEqual(calendar.nextRefreshDelay(at: date), .seconds(15))
    }

    func testNearCloseDelaySleepsUntilMarketCloseBoundary() {
        let date = makeDate(year: 2026, month: 3, day: 13, hour: 14, minute: 59, second: 50)
        XCTAssertEqual(calendar.nextRefreshDelay(at: date), .seconds(10))
    }

    func testExpectedOfficialNavDateUsesPreviousTradingDayOnWeekendAndPreOpen() {
        let weekendDate = makeDate(year: 2026, month: 3, day: 14, hour: 0, minute: 19)
        let preOpenDate = makeDate(year: 2026, month: 3, day: 16, hour: 9, minute: 10)
        let auctionDate = makeDate(year: 2026, month: 3, day: 16, hour: 9, minute: 20)
        let postCloseDate = makeDate(year: 2026, month: 3, day: 13, hour: 20, minute: 30)

        XCTAssertEqual(calendar.expectedOfficialNavDate(at: weekendDate), "2026-03-13")
        XCTAssertEqual(calendar.expectedOfficialNavDate(at: preOpenDate), "2026-03-13")
        XCTAssertEqual(calendar.expectedOfficialNavDate(at: auctionDate), "2026-03-13")
        XCTAssertEqual(calendar.expectedOfficialNavDate(at: postCloseDate), "2026-03-13")
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int = 0) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = MarketCalendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return components.date ?? .now
    }
}
