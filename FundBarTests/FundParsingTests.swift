import XCTest
@testable import FundBar

final class FundParsingTests: XCTestCase {
    private let calendar = MarketCalendar()

    func testParseFundMetadataFromFixtures() throws {
        let pingData = try TestSupport.fixtureString(named: "pingzhongdata_fixture", extension: "js")
        let detailHTML = try TestSupport.fixtureString(named: "detail_fixture", extension: "html")
        let holdingsRaw = try TestSupport.fixtureString(named: "holdings_fixture", extension: "txt")
        let holdingsPayload = try FundParsing.parseHoldings(from: holdingsRaw)

        let metadata = try FundParsing.parseFundMetadata(
            fundCode: "001437",
            pingData: pingData,
            detailHTML: detailHTML,
            calendar: calendar,
            holdingsReportDate: holdingsPayload.reportDate
        )

        XCTAssertEqual(metadata.name, "易方达瑞享混合I")
        XCTAssertEqual(metadata.lastNav, 7.8421, accuracy: 0.0001)
        XCTAssertEqual(metadata.lastNavDate, "2026-03-11")
        XCTAssertEqual(metadata.stockPosition, 95.05, accuracy: 0.001)
        XCTAssertEqual(metadata.managerName, "武阳")
        XCTAssertEqual(metadata.managerCompany, "易方达基金管理有限公司")
        XCTAssertEqual(metadata.latestScale, "25.25亿元")
        XCTAssertEqual(metadata.scaleDate, "2025-12-31")
        XCTAssertEqual(metadata.holdingsReportDate, "2025-12-31")
    }

    func testParseNavSeriesFromFixtures() throws {
        let pingData = try TestSupport.fixtureString(named: "pingzhongdata_fixture", extension: "js")

        let navSeries = try FundParsing.parseNavSeries(from: pingData, calendar: calendar)
        let latest = try XCTUnwrap(navSeries.last)

        XCTAssertEqual(navSeries.count, 1)
        XCTAssertEqual(latest.date, "2026-03-11")
        XCTAssertEqual(latest.nav, 7.8421, accuracy: 0.0001)
    }

    func testParseHoldingsQuotesAndHistoricalClose() throws {
        let holdingsRaw = try TestSupport.fixtureString(named: "holdings_fixture", extension: "txt")
        let quotesRaw = try TestSupport.fixtureString(named: "quotes_fixture", extension: "jsonp")
        let historicalRaw = try TestSupport.fixtureString(named: "historical_close_fixture", extension: "jsonp")

        let holdingsPayload = try FundParsing.parseHoldings(from: holdingsRaw)
        let quotes = try FundParsing.parseQuotes(from: quotesRaw)
        let historicalClose = try FundParsing.parseHistoricalClose(from: historicalRaw)
        let firstHolding = try XCTUnwrap(holdingsPayload.holdings.first)
        let stockQuote = try XCTUnwrap(quotes["300308"])
        let indexQuote = try XCTUnwrap(quotes["000300"])
        let close = try XCTUnwrap(historicalClose)

        XCTAssertEqual(holdingsPayload.reportDate, "2025-12-31")
        XCTAssertEqual(holdingsPayload.holdings.count, 1)
        XCTAssertEqual(firstHolding.code, "300308")
        XCTAssertEqual(firstHolding.weight, 95.05, accuracy: 0.001)
        XCTAssertEqual(stockQuote.price, 100.4965, accuracy: 0.0001)
        XCTAssertEqual(indexQuote.changePct, -0.39, accuracy: 0.0001)
        XCTAssertEqual(close, 100.0, accuracy: 0.0001)
    }

    func testParseHistoricalCloseUsesCloseField() throws {
        let raw = #"cb({"data":{"klines":["2025-12-31,100.00,102.50"]}})"#

        let close = try XCTUnwrap(FundParsing.parseHistoricalClose(from: raw))
        let series = try FundParsing.parseHistoricalSeries(from: raw)
        let first = try XCTUnwrap(series.first)

        XCTAssertEqual(close, 102.5, accuracy: 0.0001)
        XCTAssertEqual(first.open, 100.0, accuracy: 0.0001)
        XCTAssertEqual(first.close, 102.5, accuracy: 0.0001)
    }
}
