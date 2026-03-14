import XCTest
@testable import FundBar

final class DisplayFormattingTests: XCTestCase {
    func testCompactMoneyUsesWanUnitForLargeValues() {
        XCTAssertEqual(DisplayFormatting.compactMoney(12_345.67), "+1.23万")
        XCTAssertEqual(DisplayFormatting.compactMoney(-23_456.78), "-2.35万")
    }

    func testCompactMoneyRoundsThousandsForStatusBar() {
        XCTAssertEqual(DisplayFormatting.compactMoney(1_160.71), "+1161")
        XCTAssertEqual(DisplayFormatting.compactMoney(-1_160.71), "-1161")
    }

    func testCompactStatusBarPercentDropsSignAndKeepsMagnitude() {
        XCTAssertEqual(DisplayFormatting.compactStatusBarPercent(2.56), "2.56%")
        XCTAssertEqual(DisplayFormatting.compactStatusBarPercent(-0.09), "0.09%")
    }

    func testCompactStatusBarMoneyUsesShortSignedFormat() {
        XCTAssertEqual(DisplayFormatting.compactStatusBarMoney(345.67), "+346")
        XCTAssertEqual(DisplayFormatting.compactStatusBarMoney(-1_160.71), "-1161")
        XCTAssertEqual(DisplayFormatting.compactStatusBarMoney(12_345.67), "+1.2万")
    }

    func testCompactStatusBarAmountUsesYuanUntilHundredThousand() {
        XCTAssertEqual(DisplayFormatting.compactStatusBarAmount(345.67), "345.67元")
        XCTAssertEqual(DisplayFormatting.compactStatusBarAmount(-1_160.71), "1160.71元")
        XCTAssertEqual(DisplayFormatting.compactStatusBarAmount(12_345.67), "12345.67元")
        XCTAssertEqual(DisplayFormatting.compactStatusBarAmount(123_456.78), "12.35万")
    }

    func testDirtyFractionalStockQuantityKeepsActualValue() {
        XCTAssertEqual(DisplayFormatting.quantity(1.5, for: .stock), "1.5")
    }

    func testStatusBarTitleShowsPercentAndAmountWhenSharesExist() {
        let fund = FundViewData(
            storageCode: "001437",
            assetKind: .fund,
            code: "001437",
            name: "测试基金",
            shares: 100,
            isPrimary: true,
            displayValue: 1.2345,
            displayChangePct: 2.56,
            estimatedProfitAmount: 345.67,
            referenceDate: "2026-03-13",
            updatedAt: Date(timeIntervalSince1970: 0),
            isStale: false,
            sourceMode: .estimated,
            statusMessage: "刷新成功"
        )

        XCTAssertEqual(DisplayFormatting.statusBarTitle(primaryFund: fund), "基金 001437 +2.56% +345.67")
    }

    func testStatusBarVisibleSummaryShowsPercentAndAmountWhenSharesExist() {
        let fund = FundViewData(
            storageCode: "001437",
            assetKind: .fund,
            code: "001437",
            name: "测试基金",
            shares: 100,
            isPrimary: true,
            displayValue: 1.2345,
            displayChangePct: 2.56,
            estimatedProfitAmount: 345.67,
            referenceDate: "2026-03-13",
            updatedAt: Date(timeIntervalSince1970: 0),
            isStale: false,
            sourceMode: .estimated,
            statusMessage: "刷新成功"
        )

        XCTAssertEqual(DisplayFormatting.statusBarVisibleSummary(primaryFund: fund), "345.67元 2.56%")
    }

    func testStatusBarTitleFallsBackToPercentWhenSharesMissing() {
        let fund = FundViewData(
            storageCode: "stock:600519",
            assetKind: .stock,
            code: "600519",
            name: "测试股票",
            shares: 0,
            isPrimary: true,
            displayValue: 123.45,
            displayChangePct: -0.09,
            estimatedProfitAmount: -1_160.71,
            referenceDate: "2026-03-13",
            updatedAt: Date(timeIntervalSince1970: 0),
            isStale: false,
            sourceMode: .realtime,
            statusMessage: "刷新成功"
        )

        XCTAssertEqual(DisplayFormatting.statusBarTitle(primaryFund: fund), "股票 600519 -0.09%")
    }

    func testStatusBarVisibleSummaryFallsBackToPercentWhenSharesMissing() {
        let fund = FundViewData(
            storageCode: "stock:600519",
            assetKind: .stock,
            code: "600519",
            name: "测试股票",
            shares: 0,
            isPrimary: true,
            displayValue: 123.45,
            displayChangePct: -0.09,
            estimatedProfitAmount: -1_160.71,
            referenceDate: "2026-03-13",
            updatedAt: Date(timeIntervalSince1970: 0),
            isStale: false,
            sourceMode: .realtime,
            statusMessage: "刷新成功"
        )

        XCTAssertEqual(DisplayFormatting.statusBarVisibleSummary(primaryFund: fund), "0.09%")
    }

    func testProfitTitleUsesReferenceDateForOfficialSnapshots() {
        let fund = FundViewData(
            storageCode: "001437",
            assetKind: .fund,
            code: "001437",
            name: "测试基金",
            shares: 100,
            isPrimary: true,
            displayValue: 1.2345,
            displayChangePct: 2.56,
            estimatedProfitAmount: 345.67,
            referenceDate: "2026-03-13",
            updatedAt: Date(timeIntervalSince1970: 0),
            isStale: false,
            sourceMode: .official,
            statusMessage: "官方净值已发布"
        )

        XCTAssertEqual(DisplayFormatting.profitTitle(for: fund), "03-13盈亏")
        XCTAssertEqual(DisplayFormatting.totalProfitTitle(primaryFund: fund), "03-13总盈亏")
    }

    func testProfitTitleKeepsIntradayLabelForLiveEstimate() {
        let fund = FundViewData(
            storageCode: "001437",
            assetKind: .fund,
            code: "001437",
            name: "测试基金",
            shares: 100,
            isPrimary: true,
            displayValue: 1.2345,
            displayChangePct: 2.56,
            estimatedProfitAmount: 345.67,
            referenceDate: "2026-03-13",
            updatedAt: Date(timeIntervalSince1970: 0),
            isStale: false,
            sourceMode: .estimated,
            statusMessage: "本地参考估算"
        )

        XCTAssertEqual(DisplayFormatting.profitTitle(for: fund), "当日盈亏")
        XCTAssertEqual(DisplayFormatting.totalProfitTitle(primaryFund: fund), "今日总盈亏")
    }

    func testFundDisplayValueTitleUsesOfficialAndReferenceLabels() {
        let officialFund = FundViewData(
            storageCode: "001437",
            assetKind: .fund,
            code: "001437",
            name: "测试基金",
            shares: 100,
            isPrimary: true,
            displayValue: 1.2345,
            displayChangePct: 2.56,
            estimatedProfitAmount: 345.67,
            referenceDate: "2026-03-13",
            updatedAt: Date(timeIntervalSince1970: 0),
            isStale: false,
            sourceMode: .official,
            statusMessage: "官方净值已发布"
        )
        let estimatedFund = FundViewData(
            storageCode: "001437",
            assetKind: .fund,
            code: "001437",
            name: "测试基金",
            shares: 100,
            isPrimary: true,
            displayValue: 1.2345,
            displayChangePct: 2.56,
            estimatedProfitAmount: 345.67,
            referenceDate: "2026-03-13",
            updatedAt: Date(timeIntervalSince1970: 0),
            isStale: false,
            sourceMode: .estimated,
            statusMessage: "本地参考估算"
        )

        XCTAssertEqual(officialFund.displayValueTitle, "官方净值")
        XCTAssertEqual(estimatedFund.displayValueTitle, "参考估值")
    }
}
