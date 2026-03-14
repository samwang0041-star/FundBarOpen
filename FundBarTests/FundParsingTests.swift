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

    // MARK: - Sina Quote Parsing

    func testParseSinaQuotesReturnsExpectedFields() throws {
        let raw = """
        var hq_str_sh600519="贵州茅台,1392.480,1392.000,1413.640,1417.620,1392.000,1413.640,1413.760,3360783,4738808558.000,85,1413.640,100,1413.600,100,1413.580,100,1413.500,100,1413.400,100,1413.760,100,1413.930,200,1413.940,3000,1413.960,100,1413.990,2026-03-13,15:00:01,00,";
        var hq_str_sz000001="平安银行,11.240,11.240,11.310,11.350,11.220,11.310,11.320,52048137,586498771.000,62700,11.310,56700,11.300,44900,11.290,41500,11.280,32600,11.270,42800,11.320,34300,11.330,31100,11.340,32100,11.350,19400,11.360,2026-03-13,15:00:03,00";
        """

        let quotes = try FundParsing.parseSinaQuotes(from: raw)

        let moutai = try XCTUnwrap(quotes["600519"])
        XCTAssertEqual(moutai.name, "贵州茅台")
        XCTAssertEqual(moutai.price, 1413.640, accuracy: 0.001)
        XCTAssertEqual(moutai.changePct, (1413.640 - 1392.000) / 1392.000 * 100, accuracy: 0.01)
        XCTAssertEqual(moutai.change, 1413.640 - 1392.000, accuracy: 0.001)
        XCTAssertEqual(moutai.volume, 3360783, accuracy: 1)

        let pingan = try XCTUnwrap(quotes["000001"])
        XCTAssertEqual(pingan.name, "平安银行")
        XCTAssertEqual(pingan.price, 11.310, accuracy: 0.001)
    }

    func testParseSinaQuotesThrowsOnEmpty() {
        XCTAssertThrowsError(try FundParsing.parseSinaQuotes(from: ""))
        XCTAssertThrowsError(try FundParsing.parseSinaQuotes(from: #"var hq_str_sh600519="";"#))
    }

    // MARK: - Tencent Quote Parsing

    func testParseTencentQuotesReturnsExpectedFields() throws {
        // Simplified Tencent format with enough fields (need ≥ 45)
        var fields = Array(repeating: "0", count: 50)
        fields[1] = "贵州茅台"       // name
        fields[2] = "600519"        // code
        fields[3] = "1413.64"      // price
        fields[4] = "1392.00"      // lastClose
        fields[31] = "21.64"       // change
        fields[32] = "1.55"        // changePct
        fields[36] = "33608"       // volume
        fields[45] = "1770259000000" // totalMarketCap (raw)
        let line = #"v_sh600519=""# + fields.joined(separator: "~") + #"";"#

        let quotes = try FundParsing.parseTencentQuotes(from: line)
        let q = try XCTUnwrap(quotes["600519"])

        XCTAssertEqual(q.name, "贵州茅台")
        XCTAssertEqual(q.price, 1413.64, accuracy: 0.01)
        XCTAssertEqual(q.changePct, 1.55, accuracy: 0.01)
        XCTAssertEqual(q.change, 21.64, accuracy: 0.01)
        XCTAssertEqual(q.marketCap, 17702.59, accuracy: 1)
    }

    func testParseTencentQuotesThrowsOnEmpty() {
        XCTAssertThrowsError(try FundParsing.parseTencentQuotes(from: ""))
    }

    // MARK: - Tencent Historical Parsing

    func testParseTencentHistoricalSeriesFromJSON() throws {
        let raw = """
        {"data":{"sh600519":{"day":[["2026-03-12","1390.00","1392.00"],["2026-03-13","1392.48","1413.64"]]}}}
        """

        let series = try FundParsing.parseTencentHistoricalSeries(from: raw)

        XCTAssertEqual(series.count, 2)
        let first = try XCTUnwrap(series.first)
        XCTAssertEqual(first.date, "2026-03-12")
        XCTAssertEqual(first.open, 1390.00, accuracy: 0.01)
        XCTAssertEqual(first.close, 1392.00, accuracy: 0.01)
        let last = try XCTUnwrap(series.last)
        XCTAssertEqual(last.date, "2026-03-13")
        XCTAssertEqual(last.close, 1413.64, accuracy: 0.01)
    }
}
