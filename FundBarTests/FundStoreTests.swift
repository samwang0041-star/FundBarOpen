import XCTest
@testable import FundBar

final class FundStoreTests: XCTestCase {
    func testMaximumTrackedFundsLimit() throws {
        var funds: [TrackedFundState] = []
        for index in 0..<FundStoreLimits.maximumTrackedFunds {
            let code = String(format: "%06d", index + 1)
            funds = try FundStoreRules.upsert(
                funds,
                code: code,
                assetKind: .fund,
                shares: Double(index),
                makePrimary: index == 0,
                now: Date(timeIntervalSince1970: Double(index))
            )
        }

        XCTAssertThrowsError(try FundStoreRules.upsert(funds, code: "999999", assetKind: .stock, shares: 1, makePrimary: false)) { error in
            XCTAssertEqual(error.localizedDescription, FundStoreError.maximumTrackedFundsReached.localizedDescription)
        }
    }

    func testPrimaryFundRemainsUniqueAndPromotesOnDelete() throws {
        var funds: [TrackedFundState] = []
        funds = try FundStoreRules.upsert(funds, code: "001437", assetKind: .fund, shares: 100, makePrimary: false, now: Date(timeIntervalSince1970: 1))
        funds = try FundStoreRules.upsert(funds, code: "002000", assetKind: .stock, shares: 200, makePrimary: true, now: Date(timeIntervalSince1970: 2))

        XCTAssertEqual(funds.filter { $0.isPrimary }.count, 1)
        XCTAssertEqual(funds.first(where: { $0.isPrimary })?.code, "002000")
        XCTAssertEqual(funds.first(where: { $0.isPrimary })?.assetKind, .stock)

        funds = try FundStoreRules.delete(funds, storageCode: "stock:002000")
        XCTAssertEqual(funds.count, 1)
        XCTAssertEqual(funds.first?.code, "001437")
        XCTAssertEqual(funds.first?.isPrimary, true)
    }

    func testFundAndStockWithSameVisibleCodeCanCoexist() throws {
        var funds: [TrackedFundState] = []
        funds = try FundStoreRules.upsert(funds, code: "001437", assetKind: .fund, shares: 100, makePrimary: true)
        funds = try FundStoreRules.upsert(funds, code: "001437", assetKind: .stock, shares: 200, makePrimary: false)

        XCTAssertEqual(funds.count, 2)
        XCTAssertEqual(Set(funds.map(\.storageCode)), ["001437", "stock:001437"])
        XCTAssertEqual(funds.filter { $0.code == "001437" }.count, 2)
    }

    func testStockCodeAcceptsExchangePrefixAndStoresNormalizedCode() throws {
        let funds = try FundStoreRules.upsert([], code: "sh600519", assetKind: .stock, shares: 10, makePrimary: true)

        XCTAssertEqual(funds.count, 1)
        XCTAssertEqual(funds.first?.storageCode, "stock:600519")
        XCTAssertEqual(funds.first?.code, "600519")
        XCTAssertEqual(funds.first?.assetKind, .stock)
    }

    func testOrderingKeepsPrimaryFirstThenNewest() throws {
        let ordered = FundStoreRules.ordered([
            TrackedFundState(storageCode: "stock:000003", shares: 1, isPrimary: false, updatedAt: Date(timeIntervalSince1970: 3)),
            TrackedFundState(storageCode: "000001", shares: 1, isPrimary: true, updatedAt: Date(timeIntervalSince1970: 1)),
            TrackedFundState(storageCode: "000002", shares: 1, isPrimary: false, updatedAt: Date(timeIntervalSince1970: 2))
        ])

        XCTAssertEqual(ordered.map { $0.code }, ["000001", "000003", "000002"])
    }

    func testStockSharesMustBeWholeNumbers() {
        XCTAssertThrowsError(try FundStoreRules.upsert([], code: "600519", assetKind: .stock, shares: 1.5, makePrimary: true)) { error in
            XCTAssertEqual(error.localizedDescription, FundStoreError.fractionalStockShares.localizedDescription)
        }
    }

    @MainActor
    func testEditingTrackedAssetCanRenameStorageCodeAndMoveSnapshot() throws {
        let container = try TestSupport.makeModelContainer()
        let store = FundStore(modelContext: container.mainContext)
        _ = try store.upsertTrackedFund(code: "001437", assetKind: .fund, shares: 100, makePrimary: true)
        let payload = FundRefreshPayload(
            storageCode: "001437",
            assetKind: .fund,
            name: "测试基金",
            displayValue: 1.2345,
            displayChangePct: 1.23,
            estimatedProfitAmount: 12.34,
            referenceValue: 1.2000,
            referenceDate: "2026-03-13",
            sourceMode: .estimated,
            statusMessage: "刷新成功",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        try store.saveSnapshot(payload, shares: 100)

        _ = try store.saveTrackedFund(
            originalStorageCode: "001437",
            code: "002000",
            assetKind: .stock,
            shares: 200,
            makePrimary: true
        )

        let trackedFunds = try store.loadTrackedFunds()
        XCTAssertEqual(trackedFunds.count, 1)
        XCTAssertEqual(trackedFunds.first?.code, "stock:002000")
        XCTAssertEqual(trackedFunds.first?.shares, 200)
        XCTAssertNil(try store.snapshot(for: "001437"))
        XCTAssertEqual(try store.snapshot(for: "stock:002000")?.fundCode, "stock:002000")
    }

    @MainActor
    func testPersistenceStoreAcceptsPrefixedStockCode() throws {
        let container = try TestSupport.makeModelContainer()
        let store = FundStore(modelContext: container.mainContext)

        _ = try store.upsertTrackedFund(code: "sz000858", assetKind: .stock, shares: 100, makePrimary: true)

        let trackedFunds = try store.loadTrackedFunds()
        XCTAssertEqual(trackedFunds.count, 1)
        XCTAssertEqual(trackedFunds.first?.code, "stock:000858")
        XCTAssertEqual(trackedFunds.first?.displayCode, "000858")
        XCTAssertEqual(trackedFunds.first?.assetKind, .stock)
    }

    func testEditingTrackedAssetCannotChangeToExistingStorageCode() throws {
        var funds: [TrackedFundState] = []
        funds = try FundStoreRules.upsert(funds, code: "001437", assetKind: .fund, shares: 100, makePrimary: true)
        funds = try FundStoreRules.upsert(funds, code: "600519", assetKind: .stock, shares: 10, makePrimary: false)

        XCTAssertThrowsError(
            try FundStoreRules.save(
                funds,
                originalStorageCode: "001437",
                code: "600519",
                assetKind: .stock,
                shares: 10,
                makePrimary: false
            )
        ) { error in
            XCTAssertEqual(error.localizedDescription, FundStoreError.duplicateAsset.localizedDescription)
        }
    }

    @MainActor
    func testMarkingSnapshotStalePreservesLastSuccessfulUpdateTime() throws {
        let container = try TestSupport.makeModelContainer()
        let store = FundStore(modelContext: container.mainContext)
        let updatedAt = Date(timeIntervalSince1970: 100)
        let attemptedAt = Date(timeIntervalSince1970: 250)
        let payload = FundRefreshPayload(
            storageCode: "001437",
            assetKind: .fund,
            name: "测试基金",
            displayValue: 1.2345,
            displayChangePct: 1.23,
            estimatedProfitAmount: 123.45,
            referenceValue: 1.2000,
            referenceDate: "2026-03-13",
            sourceMode: .estimated,
            statusMessage: "刷新成功",
            updatedAt: updatedAt
        )

        try store.saveSnapshot(payload, shares: 100)
        try store.markSnapshotStale(for: "001437", message: "刷新失败，已保留上次成功数据。", attemptedAt: attemptedAt)

        let snapshot = try XCTUnwrap(store.snapshot(for: "001437"))
        XCTAssertEqual(snapshot.updatedAt, updatedAt)
        XCTAssertEqual(snapshot.lastAttemptAt, attemptedAt)
        XCTAssertTrue(snapshot.isStale)
    }
}
