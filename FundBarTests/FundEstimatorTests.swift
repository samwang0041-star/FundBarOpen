import XCTest
@testable import FundBar

final class FundEstimatorTests: XCTestCase {
    private struct MockHistoricalCloseError: Error {}
    private struct MockHistoricalSeriesError: Error {}

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
        func fetchHistoricalSeries(secid: String, startDate: String, endDate: String) async throws -> String { "{\"data\":{\"klines\":[]}}" }
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

        func fetchHistoricalSeries(secid: String, startDate: String, endDate: String) async throws -> String {
            historicalRaw
        }
    }

    private struct CalibrationAPIClient: FundAPIClienting {
        let pingData: String
        let detailHTML: String
        let holdingsRaw: String
        let quotesRaw: String
        let reportCloseBySecid: [String: String]
        let historicalSeriesBySecid: [String: String]

        func fetchPingData(for fundCode: String) async throws -> String { pingData }
        func fetchDetailHTML(for fundCode: String) async throws -> String { detailHTML }
        func fetchHoldings(for fundCode: String) async throws -> String { holdingsRaw }
        func fetchQuotes(secids: [String]) async throws -> String { quotesRaw }

        func fetchHistoricalClose(secid: String, reportDate: String) async throws -> String {
            reportCloseBySecid[secid] ?? "{\"data\":{\"klines\":[]}}"
        }

        func fetchHistoricalSeries(secid: String, startDate: String, endDate: String) async throws -> String {
            historicalSeriesBySecid[secid] ?? "{\"data\":{\"klines\":[]}}"
        }
    }

    private struct CalibrationFailureAPIClient: FundAPIClienting {
        let pingData: String
        let detailHTML: String
        let holdingsRaw: String
        let quotesRaw: String
        let reportCloseRaw: String

        func fetchPingData(for fundCode: String) async throws -> String { pingData }
        func fetchDetailHTML(for fundCode: String) async throws -> String { detailHTML }
        func fetchHoldings(for fundCode: String) async throws -> String { holdingsRaw }
        func fetchQuotes(secids: [String]) async throws -> String { quotesRaw }
        func fetchHistoricalClose(secid: String, reportDate: String) async throws -> String { reportCloseRaw }

        func fetchHistoricalSeries(secid: String, startDate: String, endDate: String) async throws -> String {
            throw MockHistoricalSeriesError()
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

    func testStaleHoldingsBlendTowardRecentOfficialFactorBehavior() async throws {
        let fixedNow = makeDate(year: 2026, month: 3, day: 16, hour: 10, minute: 0)
        let detailHTML = """
        类型：<a href="#">混合型</a>&nbsp;&nbsp;|&nbsp;&nbsp;中风险
        托管费 0.25%
        """

        let tradingDays = makeTradingDays(start: makeDate(year: 2026, month: 1, day: 5, hour: 0, minute: 0), count: 50)
        let hs300Returns = [0.018, -0.012, 0.015, 0.007, -0.009, 0.011, -0.004]
        let hs300Closes = makeCloses(start: 100, returns: hs300Returns, count: tradingDays.count)
        let fundCloses = makeCloses(start: 1, returns: hs300Returns.map { $0 * 0.8 }, count: tradingDays.count)
        let pingData = makePingData(dates: tradingDays, navs: fundCloses, stockPosition: 80)
        let quotesRaw = makeCalibrationQuotesRaw(stockPrice: 8, stockChangePct: -20, stockChange: -2, hs300ChangePct: 18)
        let reportCloseRaw = #"cb({"data":{"klines":["2025-09-30,10.00,10.00"]}})"#
        let indexSeries = makeHistoricalSeriesMap(dates: tradingDays, hs300Closes: hs300Closes)

        let staleEstimator = FundEstimatorService(
            apiClient: CalibrationAPIClient(
                pingData: pingData,
                detailHTML: detailHTML,
                holdingsRaw: makeHoldingsRaw(reportDate: "2025-09-30"),
                quotesRaw: quotesRaw,
                reportCloseBySecid: ["1.600000": reportCloseRaw],
                historicalSeriesBySecid: indexSeries
            ),
            marketCalendar: MarketCalendar(nowProvider: { fixedNow })
        )
        let freshEstimator = FundEstimatorService(
            apiClient: CalibrationAPIClient(
                pingData: pingData,
                detailHTML: detailHTML,
                holdingsRaw: makeHoldingsRaw(reportDate: "2026-03-10"),
                quotesRaw: quotesRaw,
                reportCloseBySecid: ["1.600000": reportCloseRaw],
                historicalSeriesBySecid: indexSeries
            ),
            marketCalendar: MarketCalendar(nowProvider: { fixedNow })
        )

        let stalePayload = try await staleEstimator.refreshAsset(storageCode: "001437", shares: 100, hasExistingSnapshot: true)
        let freshPayload = try await freshEstimator.refreshAsset(storageCode: "001437", shares: 100, hasExistingSnapshot: true)

        XCTAssertEqual(stalePayload.sourceMode, .estimated)
        XCTAssertEqual(freshPayload.sourceMode, .estimated)
        XCTAssertGreaterThan(stalePayload.displayValue, freshPayload.displayValue)
        XCTAssertGreaterThan(stalePayload.displayChangePct, freshPayload.displayChangePct)
        XCTAssertGreaterThan(stalePayload.displayChangePct, 0)
        XCTAssertLessThan(freshPayload.displayChangePct, -5)
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
        XCTAssertEqual(payload.valuationDate, "2026-03-13")
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
        XCTAssertEqual(payload.valuationDate, "2026-03-16")
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
        XCTAssertEqual(payload.valuationDate, "2026-03-13")
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

    private func makeTradingDays(start: Date, count: Int) -> [Date] {
        var dates: [Date] = []
        var cursor = start
        let calendar = MarketCalendar.calendar

        while dates.count < count {
            let weekday = calendar.component(.weekday, from: cursor)
            if weekday != 1 && weekday != 7 {
                dates.append(cursor)
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        }

        return dates
    }

    private func makeCloses(start: Double, returns: [Double], count: Int) -> [Double] {
        var closes = [start]
        while closes.count < count {
            let dailyReturn = returns[(closes.count - 1) % returns.count]
            closes.append(closes[closes.count - 1] * (1 + dailyReturn))
        }
        return closes
    }

    private func makePingData(dates: [Date], navs: [Double], stockPosition: Double) -> String {
        let points = zip(dates, navs).map { date, nav in
            let timestamp = Int(date.timeIntervalSince1970 * 1000)
            return #"{"x":\#(timestamp),"y":\#(String(format: "%.4f", nav))}"#
        }.joined(separator: ",")

        return """
        var fS_name = "测试基金";
        var Data_netWorthTrend = [\(points)];
        var Data_fundSharesPositions = [[0,\(String(format: "%.2f", stockPosition))]];
        var Data_currentFundManager = [{"name":"张三"}];
        var fund_sourceRate = "1.50";
        """
    }

    private func makeHoldingsRaw(reportDate: String) -> String {
        #"content:"截止至：<font class='px12'>\#(reportDate)</font><table><tr><td>1</td><td>600000</td><td>浦发银行</td><td>-</td><td>-</td><td>-</td><td>80%</td><td>-</td></tr></table>",arryear:""#
    }

    private func makeCalibrationQuotesRaw(
        stockPrice: Double,
        stockChangePct: Double,
        stockChange: Double,
        hs300ChangePct: Double
    ) -> String {
        """
        jQueryCallback({
          "data": {
            "diff": [
              {"f12":"600000","f14":"浦发银行","f2":\(String(format: "%.2f", stockPrice)),"f3":\(String(format: "%.2f", stockChangePct)),"f4":\(String(format: "%.2f", stockChange)),"f5":1000,"f20":10000000000},
              {"f12":"000300","f14":"沪深300","f2":5000.00,"f3":\(String(format: "%.2f", hs300ChangePct)),"f4":20.00,"f5":0,"f20":0},
              {"f12":"000905","f14":"中证500","f2":5000.00,"f3":0.00,"f4":0.00,"f5":0,"f20":0},
              {"f12":"399006","f14":"创业板指","f2":2000.00,"f3":0.00,"f4":0.00,"f5":0,"f20":0},
              {"f12":"000688","f14":"科创50","f2":1000.00,"f3":0.00,"f4":0.00,"f5":0,"f20":0}
            ]
          }
        })
        """
    }

    private func makeHistoricalSeriesMap(dates: [Date], hs300Closes: [Double]) -> [String: String] {
        let flat = Array(repeating: 100.0, count: dates.count)
        return [
            "1.000300": makeHistoricalSeriesRaw(dates: dates, closes: hs300Closes),
            "1.000905": makeHistoricalSeriesRaw(dates: dates, closes: flat),
            "0.399006": makeHistoricalSeriesRaw(dates: dates, closes: flat),
            "1.000688": makeHistoricalSeriesRaw(dates: dates, closes: flat)
        ]
    }

    private func makeHistoricalSeriesRaw(dates: [Date], closes: [Double]) -> String {
        let lines = zip(dates, closes).map { date, close in
            let dateString = historicalDateString(date)
            return "\"\(dateString),\(String(format: "%.2f", close)),\(String(format: "%.2f", close))\""
        }.joined(separator: ",")
        return #"cb({"data":{"klines":[\#(lines)]}})"#
    }

    private func historicalDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = MarketCalendar.calendar
        formatter.timeZone = MarketCalendar.timeZone
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func testCalibrationFailureFallsBackToHoldingsEstimate() async throws {
        let fixedNow = makeDate(year: 2026, month: 3, day: 16, hour: 10, minute: 0)
        let detailHTML = """
        类型：<a href="#">混合型</a>&nbsp;&nbsp;|&nbsp;&nbsp;中风险
        托管费 0.25%
        """
        let tradingDays = makeTradingDays(start: makeDate(year: 2026, month: 1, day: 5, hour: 0, minute: 0), count: 50)
        let hs300Returns = [0.018, -0.012, 0.015, 0.007, -0.009, 0.011, -0.004]
        let fundCloses = makeCloses(start: 1, returns: hs300Returns.map { $0 * 0.8 }, count: tradingDays.count)
        let pingData = makePingData(dates: tradingDays, navs: fundCloses, stockPosition: 80)
        let quotesRaw = makeCalibrationQuotesRaw(stockPrice: 8, stockChangePct: -20, stockChange: -2, hs300ChangePct: 18)
        let reportCloseRaw = #"cb({"data":{"klines":["2025-09-30,10.00,10.00"]}})"#
        let holdingsRaw = makeHoldingsRaw(reportDate: "2025-09-30")

        let estimator = FundEstimatorService(
            apiClient: CalibrationFailureAPIClient(
                pingData: pingData,
                detailHTML: detailHTML,
                holdingsRaw: holdingsRaw,
                quotesRaw: quotesRaw,
                reportCloseRaw: reportCloseRaw
            ),
            marketCalendar: MarketCalendar(nowProvider: { fixedNow })
        )

        let payload = try await estimator.refreshAsset(storageCode: "001437", shares: 100, hasExistingSnapshot: true)

        XCTAssertEqual(payload.sourceMode, .estimated)
        XCTAssertFalse(payload.displayValue.isNaN)
        XCTAssertLessThan(payload.displayChangePct, -5)
    }
}
