import XCTest
@testable import FundBar

final class FundEstimatorTests: XCTestCase {
    private struct MockHistoricalCloseError: Error {}

    private struct OfficialNavPublishedAPIClient: FundAPIClienting {
        let pingData: String
        let detailHTML: String
        let holdingsRaw: String
        let quotesRaw: String

        func fetchPingData(for fundCode: String) async throws -> String { pingData }
        func fetchDetailHTML(for fundCode: String) async throws -> String { detailHTML }
        func fetchHoldings(for fundCode: String) async throws -> String { holdingsRaw }
        func fetchQuotes(secids: [String]) async throws -> String { quotesRaw }
        func fetchHistoricalClose(secid: String, reportDate: String) async throws -> String { "{\"data\":{\"klines\":[]}}" }
    }

    private struct CurrentRepoMeta: Decodable {
        let name: String
        let lastNav: Double
        let lastNavDate: String
        let stockPosition: Double
        let managementFee: Double
        let custodyFee: Double
    }

    private struct IntradayPoint: Decodable {
        let time: String
        let nav: Double
        let changePct: Double
    }

    private struct EstimatorFixture: Decodable {
        let metadata: FundMetadata
        let holdings: [Holding]
        let quotes: [String: SecurityQuote]
        let reportCloses: [String: Double]
    }

    private struct MockFundAPIClient: FundAPIClienting {
        let pingData: String
        let detailHTML: String
        let holdingsRaw: String
        let quotesRaw: String
        let historicalRaw: String
        let failingSecid: String

        func fetchPingData(for fundCode: String) async throws -> String { pingData }
        func fetchDetailHTML(for fundCode: String) async throws -> String { detailHTML }
        func fetchHoldings(for fundCode: String) async throws -> String { holdingsRaw }
        func fetchQuotes(secids: [String]) async throws -> String { quotesRaw }

        func fetchHistoricalClose(secid: String, reportDate: String) async throws -> String {
            if secid == failingSecid {
                throw MockHistoricalCloseError()
            }
            return historicalRaw
        }
    }

    func testCalculateEstimateMatchesCurrentRepoSample() async throws {
        let estimator = FundEstimatorService()
        let currentMeta = try TestSupport.decodeJSON(CurrentRepoMeta.self, named: "current_repo_meta_001437")
        let currentIntraday = try TestSupport.decodeJSON([IntradayPoint].self, named: "current_repo_intraday_2026_03_13")
        let fixture = try TestSupport.decodeJSON(EstimatorFixture.self, named: "estimator_fixture_001437")
        let expected = try XCTUnwrap(currentIntraday.first)

        XCTAssertEqual(fixture.metadata.lastNav, currentMeta.lastNav, accuracy: 0.0001)
        XCTAssertEqual(fixture.metadata.stockPosition, currentMeta.stockPosition, accuracy: 0.0001)
        XCTAssertEqual(fixture.metadata.managementFee, currentMeta.managementFee, accuracy: 0.0001)
        XCTAssertEqual(fixture.metadata.custodyFee, currentMeta.custodyFee, accuracy: 0.0001)

        let breakdown = await estimator.calculateEstimate(
            metadata: fixture.metadata,
            holdings: fixture.holdings,
            quotes: fixture.quotes,
            reportCloses: fixture.reportCloses
        )

        XCTAssertEqual(breakdown.estimatedNav, expected.nav, accuracy: 0.0001)
        XCTAssertEqual(breakdown.estimatedChangePct, expected.changePct, accuracy: 0.01)
        XCTAssertEqual(breakdown.knownCoverage, 100.0, accuracy: 0.01)
    }

    func testHistoricalCloseFailureFallsBackToQuoteDrift() async throws {
        let pingData = try TestSupport.fixtureString(named: "pingzhongdata_fixture", extension: "js")
        let detailHTML = try TestSupport.fixtureString(named: "detail_fixture", extension: "html")
        let holdingsRaw = try TestSupport.fixtureString(named: "holdings_fixture", extension: "txt")
        let quotesRaw = try TestSupport.fixtureString(named: "quotes_fixture", extension: "jsonp")
        let historicalRaw = try TestSupport.fixtureString(named: "historical_close_fixture", extension: "jsonp")
        let holdingsPayload = try FundParsing.parseHoldings(from: holdingsRaw)
        let failingCode = try XCTUnwrap(holdingsPayload.holdings.first?.code)
        let failingSecid = (failingCode.hasPrefix("6") || failingCode.hasPrefix("5") ? "1" : "0") + "." + failingCode
        let estimator = FundEstimatorService(
            apiClient: MockFundAPIClient(
                pingData: pingData,
                detailHTML: detailHTML,
                holdingsRaw: holdingsRaw,
                quotesRaw: quotesRaw,
                historicalRaw: historicalRaw,
                failingSecid: failingSecid
            )
        )

        let payload = try await estimator.refreshAsset(storageCode: "001437", shares: 100, hasExistingSnapshot: true)

        XCTAssertEqual(payload.storageCode, "001437")
        XCTAssertEqual(payload.assetKind, .fund)
        XCTAssertFalse(payload.displayValue.isNaN)
        XCTAssertFalse(payload.displayChangePct.isNaN)
    }

    func testOfficialNavDoesNotKeepEstimatedClosedMessageOnFirstRefresh() async throws {
        let detailHTML = """
        类型：<a href="#">混合型</a>&nbsp;&nbsp;|&nbsp;&nbsp;中风险
        托管费 0.25%
        """
        let holdingsRaw = #"content:"<table><tr><td>1</td><td>600000</td><td>浦发银行</td><td>-</td><td>-</td><td>-</td><td>10%</td><td>-</td></tr></table>",arryear:"""#
        let quotesRaw = """
        jQueryCallback({
          "data": {
            "diff": [
              {"f12":"600000","f14":"浦发银行","f2":10.00,"f3":1.00,"f4":0.10,"f5":1000,"f20":10000000000},
              {"f12":"000300","f14":"沪深300","f2":4000.00,"f3":0.50,"f4":20.00,"f5":0,"f20":0},
              {"f12":"000905","f14":"中证500","f2":5000.00,"f3":0.20,"f4":10.00,"f5":0,"f20":0},
              {"f12":"399006","f14":"创业板指","f2":2000.00,"f3":0.30,"f4":6.00,"f5":0,"f20":0},
              {"f12":"000688","f14":"科创50","f2":1000.00,"f3":0.10,"f4":1.00,"f5":0,"f20":0}
            ]
          }
        })
        """

        let fixedNow = makeDate(year: 2026, month: 3, day: 13, hour: 21, minute: 0)
        let calendar = MarketCalendar.calendar
        let todayMidnight = calendar.startOfDay(for: fixedNow)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: todayMidnight) ?? todayMidnight
        let yesterdayTs = Int(yesterday.timeIntervalSince1970 * 1000)
        let todayTs = Int(todayMidnight.timeIntervalSince1970 * 1000)

        let pingData = """
        var fS_name = "测试基金";
        var Data_netWorthTrend = [{"x":\(yesterdayTs),"y":1.0000},{"x":\(todayTs),"y":1.0200}];
        var Data_fundSharesPositions = [[0,80]];
        var Data_currentFundManager = [{"name":"张三"}];
        var fund_sourceRate = "1.50";
        """

        let estimator = FundEstimatorService(
            apiClient: OfficialNavPublishedAPIClient(
                pingData: pingData,
                detailHTML: detailHTML,
                holdingsRaw: holdingsRaw,
                quotesRaw: quotesRaw
            ),
            marketCalendar: MarketCalendar(nowProvider: { fixedNow })
        )

        let payload = try await estimator.refreshAsset(storageCode: "001437", shares: 100, hasExistingSnapshot: false)

        XCTAssertEqual(payload.sourceMode, .official)
        XCTAssertEqual(payload.statusMessage, "官方净值已发布")
        XCTAssertEqual(payload.displayValue, 1.02, accuracy: 0.0001)
    }

    func testWeekendUsesPreviousTradingDayOfficialNav() async throws {
        let detailHTML = """
        类型：<a href="#">混合型</a>&nbsp;&nbsp;|&nbsp;&nbsp;中风险
        托管费 0.25%
        """
        let holdingsRaw = #"content:"<table><tr><td>1</td><td>600000</td><td>浦发银行</td><td>-</td><td>-</td><td>-</td><td>10%</td><td>-</td></tr></table>",arryear:"""#
        let quotesRaw = """
        jQueryCallback({
          "data": {
            "diff": [
              {"f12":"600000","f14":"浦发银行","f2":10.00,"f3":1.00,"f4":0.10,"f5":1000,"f20":10000000000},
              {"f12":"000300","f14":"沪深300","f2":4000.00,"f3":0.50,"f4":20.00,"f5":0,"f20":0},
              {"f12":"000905","f14":"中证500","f2":5000.00,"f3":0.20,"f4":10.00,"f5":0,"f20":0},
              {"f12":"399006","f14":"创业板指","f2":2000.00,"f3":0.30,"f4":6.00,"f5":0,"f20":0},
              {"f12":"000688","f14":"科创50","f2":1000.00,"f3":0.10,"f4":1.00,"f5":0,"f20":0}
            ]
          }
        })
        """

        let fixedNow = makeDate(year: 2026, month: 3, day: 14, hour: 0, minute: 19)
        let calendar = MarketCalendar.calendar
        let fridayMidnight = calendar.startOfDay(for: makeDate(year: 2026, month: 3, day: 13, hour: 0, minute: 0))
        let thursdayMidnight = calendar.date(byAdding: .day, value: -1, to: fridayMidnight) ?? fridayMidnight
        let thursdayTs = Int(thursdayMidnight.timeIntervalSince1970 * 1000)
        let fridayTs = Int(fridayMidnight.timeIntervalSince1970 * 1000)

        let pingData = """
        var fS_name = "测试基金";
        var Data_netWorthTrend = [{"x":\(thursdayTs),"y":1.0000},{"x":\(fridayTs),"y":1.0200}];
        var Data_fundSharesPositions = [[0,80]];
        var Data_currentFundManager = [{"name":"张三"}];
        var fund_sourceRate = "1.50";
        """

        let estimator = FundEstimatorService(
            apiClient: OfficialNavPublishedAPIClient(
                pingData: pingData,
                detailHTML: detailHTML,
                holdingsRaw: holdingsRaw,
                quotesRaw: quotesRaw
            ),
            marketCalendar: MarketCalendar(nowProvider: { fixedNow })
        )

        let payload = try await estimator.refreshAsset(storageCode: "001437", shares: 100, hasExistingSnapshot: true)

        XCTAssertEqual(payload.sourceMode, .official)
        XCTAssertEqual(payload.statusMessage, "展示上一交易日官方净值")
        XCTAssertEqual(payload.displayValue, 1.02, accuracy: 0.0001)
        XCTAssertEqual(payload.displayChangePct, 2.0, accuracy: 0.01)
        XCTAssertEqual(payload.estimatedProfitAmount, 2.0, accuracy: 0.01)
        XCTAssertEqual(payload.referenceDate, "2026-03-13")
    }

    func testPreOpenQuietShowsPreviousOfficialResult() async throws {
        let detailHTML = """
        类型：<a href="#">混合型</a>&nbsp;&nbsp;|&nbsp;&nbsp;中风险
        托管费 0.25%
        """
        let holdingsRaw = #"content:"<table><tr><td>1</td><td>600000</td><td>浦发银行</td><td>-</td><td>-</td><td>-</td><td>10%</td><td>-</td></tr></table>",arryear:"""#
        let quotesRaw = """
        jQueryCallback({
          "data": {
            "diff": [
              {"f12":"600000","f14":"浦发银行","f2":10.00,"f3":1.00,"f4":0.10,"f5":1000,"f20":10000000000},
              {"f12":"000300","f14":"沪深300","f2":4000.00,"f3":0.50,"f4":20.00,"f5":0,"f20":0},
              {"f12":"000905","f14":"中证500","f2":5000.00,"f3":0.20,"f4":10.00,"f5":0,"f20":0},
              {"f12":"399006","f14":"创业板指","f2":2000.00,"f3":0.30,"f4":6.00,"f5":0,"f20":0},
              {"f12":"000688","f14":"科创50","f2":1000.00,"f3":0.10,"f4":1.00,"f5":0,"f20":0}
            ]
          }
        })
        """

        let fixedNow = makeDate(year: 2026, month: 3, day: 16, hour: 9, minute: 5)
        let calendar = MarketCalendar.calendar
        let fridayMidnight = calendar.startOfDay(for: makeDate(year: 2026, month: 3, day: 13, hour: 0, minute: 0))
        let thursdayMidnight = calendar.date(byAdding: .day, value: -1, to: fridayMidnight) ?? fridayMidnight
        let thursdayTs = Int(thursdayMidnight.timeIntervalSince1970 * 1000)
        let fridayTs = Int(fridayMidnight.timeIntervalSince1970 * 1000)

        let pingData = """
        var fS_name = "测试基金";
        var Data_netWorthTrend = [{"x":\(thursdayTs),"y":1.0000},{"x":\(fridayTs),"y":1.0200}];
        var Data_fundSharesPositions = [[0,80]];
        var Data_currentFundManager = [{"name":"张三"}];
        var fund_sourceRate = "1.50";
        """

        let estimator = FundEstimatorService(
            apiClient: OfficialNavPublishedAPIClient(
                pingData: pingData,
                detailHTML: detailHTML,
                holdingsRaw: holdingsRaw,
                quotesRaw: quotesRaw
            ),
            marketCalendar: MarketCalendar(nowProvider: { fixedNow })
        )

        let payload = try await estimator.refreshAsset(storageCode: "001437", shares: 100, hasExistingSnapshot: true)

        XCTAssertEqual(payload.sourceMode, .official)
        XCTAssertEqual(payload.statusMessage, "待开盘，展示上一交易日官方净值")
        XCTAssertEqual(payload.displayValue, 1.02, accuracy: 0.0001)
        XCTAssertEqual(payload.displayChangePct, 2.0, accuracy: 0.01)
        XCTAssertEqual(payload.estimatedProfitAmount, 2.0, accuracy: 0.01)
        XCTAssertEqual(payload.referenceDate, "2026-03-13")
    }

    func testPreOpenAuctionUsesAuctionEstimate() async throws {
        let detailHTML = """
        类型：<a href="#">混合型</a>&nbsp;&nbsp;|&nbsp;&nbsp;中风险
        托管费 0.25%
        """
        let holdingsRaw = #"content:"<table><tr><td>1</td><td>600000</td><td>浦发银行</td><td>-</td><td>-</td><td>-</td><td>10%</td><td>-</td></tr></table>",arryear:"""#
        let quotesRaw = """
        jQueryCallback({
          "data": {
            "diff": [
              {"f12":"600000","f14":"浦发银行","f2":11.00,"f3":10.00,"f4":1.00,"f5":1000,"f20":10000000000},
              {"f12":"000300","f14":"沪深300","f2":4000.00,"f3":0.50,"f4":20.00,"f5":0,"f20":0},
              {"f12":"000905","f14":"中证500","f2":5000.00,"f3":0.20,"f4":10.00,"f5":0,"f20":0},
              {"f12":"399006","f14":"创业板指","f2":2000.00,"f3":0.30,"f4":6.00,"f5":0,"f20":0},
              {"f12":"000688","f14":"科创50","f2":1000.00,"f3":0.10,"f4":1.00,"f5":0,"f20":0}
            ]
          }
        })
        """

        let fixedNow = makeDate(year: 2026, month: 3, day: 16, hour: 9, minute: 20)
        let calendar = MarketCalendar.calendar
        let fridayMidnight = calendar.startOfDay(for: makeDate(year: 2026, month: 3, day: 13, hour: 0, minute: 0))
        let thursdayMidnight = calendar.date(byAdding: .day, value: -1, to: fridayMidnight) ?? fridayMidnight
        let thursdayTs = Int(thursdayMidnight.timeIntervalSince1970 * 1000)
        let fridayTs = Int(fridayMidnight.timeIntervalSince1970 * 1000)

        let pingData = """
        var fS_name = "测试基金";
        var Data_netWorthTrend = [{"x":\(thursdayTs),"y":1.0000},{"x":\(fridayTs),"y":1.0200}];
        var Data_fundSharesPositions = [[0,80]];
        var Data_currentFundManager = [{"name":"张三"}];
        var fund_sourceRate = "1.50";
        """

        let estimator = FundEstimatorService(
            apiClient: OfficialNavPublishedAPIClient(
                pingData: pingData,
                detailHTML: detailHTML,
                holdingsRaw: holdingsRaw,
                quotesRaw: quotesRaw
            ),
            marketCalendar: MarketCalendar(nowProvider: { fixedNow })
        )

        let payload = try await estimator.refreshAsset(storageCode: "001437", shares: 100, hasExistingSnapshot: true)

        XCTAssertEqual(payload.sourceMode, .preOpenEstimated)
        XCTAssertEqual(payload.statusMessage, "本地盘前估算")
        XCTAssertNotEqual(payload.displayValue, 1.02, accuracy: 0.0001)
    }

    func testLunchBreakKeepsIntradayEstimateMode() async throws {
        let detailHTML = """
        类型：<a href="#">混合型</a>&nbsp;&nbsp;|&nbsp;&nbsp;中风险
        托管费 0.25%
        """
        let holdingsRaw = #"content:"<table><tr><td>1</td><td>600000</td><td>浦发银行</td><td>-</td><td>-</td><td>-</td><td>10%</td><td>-</td></tr></table>",arryear:"""#
        let quotesRaw = """
        jQueryCallback({
          "data": {
            "diff": [
              {"f12":"600000","f14":"浦发银行","f2":10.30,"f3":3.00,"f4":0.30,"f5":1000,"f20":10000000000},
              {"f12":"000300","f14":"沪深300","f2":4000.00,"f3":0.50,"f4":20.00,"f5":0,"f20":0},
              {"f12":"000905","f14":"中证500","f2":5000.00,"f3":0.20,"f4":10.00,"f5":0,"f20":0},
              {"f12":"399006","f14":"创业板指","f2":2000.00,"f3":0.30,"f4":6.00,"f5":0,"f20":0},
              {"f12":"000688","f14":"科创50","f2":1000.00,"f3":0.10,"f4":1.00,"f5":0,"f20":0}
            ]
          }
        })
        """

        let fixedNow = makeDate(year: 2026, month: 3, day: 13, hour: 12, minute: 5)
        let calendar = MarketCalendar.calendar
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: fixedNow)) ?? fixedNow
        let yesterdayTs = Int(calendar.startOfDay(for: yesterday).timeIntervalSince1970 * 1000)
        let todayTs = Int(calendar.startOfDay(for: fixedNow).timeIntervalSince1970 * 1000)

        let pingData = """
        var fS_name = "测试基金";
        var Data_netWorthTrend = [{"x":\(yesterdayTs),"y":1.0000},{"x":\(todayTs),"y":1.0200}];
        var Data_fundSharesPositions = [[0,80]];
        var Data_currentFundManager = [{"name":"张三"}];
        var fund_sourceRate = "1.50";
        """

        let estimator = FundEstimatorService(
            apiClient: OfficialNavPublishedAPIClient(
                pingData: pingData,
                detailHTML: detailHTML,
                holdingsRaw: holdingsRaw,
                quotesRaw: quotesRaw
            ),
            marketCalendar: MarketCalendar(nowProvider: { fixedNow })
        )

        let payload = try await estimator.refreshAsset(storageCode: "001437", shares: 100, hasExistingSnapshot: true)

        XCTAssertEqual(payload.sourceMode, .estimated)
        XCTAssertEqual(payload.statusMessage, "午间本地估算")
    }

    func testQDIIFundUsesLatestPublishedOfficialResult() async throws {
        let detailHTML = """
        类型：<a href="#">QDII</a>&nbsp;&nbsp;|&nbsp;&nbsp;高风险
        托管费 0.25%
        """
        let holdingsRaw = #"content:"<table><tr><td>1</td><td>600000</td><td>浦发银行</td><td>-</td><td>-</td><td>-</td><td>10%</td><td>-</td></tr></table>",arryear:"""#
        let quotesRaw = #"jQueryCallback({"data":{"diff":[]}})"#

        let fixedNow = makeDate(year: 2026, month: 3, day: 17, hour: 10, minute: 0)
        let calendar = MarketCalendar.calendar
        let fridayMidnight = calendar.startOfDay(for: makeDate(year: 2026, month: 3, day: 13, hour: 0, minute: 0))
        let mondayMidnight = calendar.startOfDay(for: makeDate(year: 2026, month: 3, day: 16, hour: 0, minute: 0))
        let fridayTs = Int(fridayMidnight.timeIntervalSince1970 * 1000)
        let mondayTs = Int(mondayMidnight.timeIntervalSince1970 * 1000)

        let pingData = """
        var fS_name = "全球科技QDII";
        var Data_netWorthTrend = [{"x":\(fridayTs),"y":1.0000},{"x":\(mondayTs),"y":1.0200}];
        var Data_fundSharesPositions = [[0,80]];
        var Data_currentFundManager = [{"name":"张三"}];
        var fund_sourceRate = "1.50";
        """

        let estimator = FundEstimatorService(
            apiClient: OfficialNavPublishedAPIClient(
                pingData: pingData,
                detailHTML: detailHTML,
                holdingsRaw: holdingsRaw,
                quotesRaw: quotesRaw
            ),
            marketCalendar: MarketCalendar(nowProvider: { fixedNow })
        )

        let payload = try await estimator.refreshAsset(storageCode: "001437", shares: 1000, hasExistingSnapshot: true)

        XCTAssertEqual(payload.sourceMode, .official)
        XCTAssertEqual(payload.statusMessage, "QDII 官方净值已发布")
        XCTAssertEqual(payload.displayValue, 1.02, accuracy: 0.0001)
        XCTAssertEqual(payload.displayChangePct, 2.0, accuracy: 0.01)
        XCTAssertEqual(payload.referenceDate, "2026-03-16")
    }

    func testQDIIFundShowsLaggedMessageWhenLatestOfficialFallsBehind() async throws {
        let detailHTML = """
        类型：<a href="#">QDII</a>&nbsp;&nbsp;|&nbsp;&nbsp;高风险
        托管费 0.25%
        """
        let holdingsRaw = #"content:"<table><tr><td>1</td><td>600000</td><td>浦发银行</td><td>-</td><td>-</td><td>-</td><td>10%</td><td>-</td></tr></table>",arryear:"""#
        let quotesRaw = #"jQueryCallback({"data":{"diff":[]}})"#

        let fixedNow = makeDate(year: 2026, month: 3, day: 18, hour: 10, minute: 0)
        let calendar = MarketCalendar.calendar
        let fridayMidnight = calendar.startOfDay(for: makeDate(year: 2026, month: 3, day: 13, hour: 0, minute: 0))
        let mondayMidnight = calendar.startOfDay(for: makeDate(year: 2026, month: 3, day: 16, hour: 0, minute: 0))
        let fridayTs = Int(fridayMidnight.timeIntervalSince1970 * 1000)
        let mondayTs = Int(mondayMidnight.timeIntervalSince1970 * 1000)

        let pingData = """
        var fS_name = "全球科技QDII";
        var Data_netWorthTrend = [{"x":\(fridayTs),"y":1.0000},{"x":\(mondayTs),"y":1.0200}];
        var Data_fundSharesPositions = [[0,80]];
        var Data_currentFundManager = [{"name":"张三"}];
        var fund_sourceRate = "1.50";
        """

        let estimator = FundEstimatorService(
            apiClient: OfficialNavPublishedAPIClient(
                pingData: pingData,
                detailHTML: detailHTML,
                holdingsRaw: holdingsRaw,
                quotesRaw: quotesRaw
            ),
            marketCalendar: MarketCalendar(nowProvider: { fixedNow })
        )

        let payload = try await estimator.refreshAsset(storageCode: "001437", shares: 1000, hasExistingSnapshot: true)

        XCTAssertEqual(payload.sourceMode, .official)
        XCTAssertEqual(payload.statusMessage, "QDII 净值更新通常滞后，当前展示最近已发布净值")
        XCTAssertEqual(payload.displayValue, 1.02, accuracy: 0.0001)
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
