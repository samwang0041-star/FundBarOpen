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

    @MainActor
    func testOfficialSnapshotRecordsLocalEstimateObservation() throws {
        let container = try TestSupport.makeModelContainer()
        let store = FundStore(modelContext: container.mainContext)
        _ = try store.upsertTrackedFund(code: "001437", assetKind: .fund, shares: 100, makePrimary: true)

        try store.saveSnapshot(
            FundRefreshPayload(
                storageCode: "001437",
                assetKind: .fund,
                name: "测试基金",
                displayValue: 1.0500,
                displayChangePct: 5.0,
                estimatedProfitAmount: 5.0,
                referenceValue: 1.0000,
                referenceDate: "2026-03-13",
                valuationDate: "2026-03-14",
                sourceMode: .estimated,
                statusMessage: "本地参考估算",
                updatedAt: Date(timeIntervalSince1970: 100)
            ),
            shares: 100
        )
        try store.saveSnapshot(
            FundRefreshPayload(
                storageCode: "001437",
                assetKind: .fund,
                name: "测试基金",
                displayValue: 1.0200,
                displayChangePct: 2.0,
                estimatedProfitAmount: 2.0,
                referenceValue: 1.0000,
                referenceDate: "2026-03-14",
                valuationDate: "2026-03-14",
                sourceMode: .official,
                statusMessage: "官方净值已发布",
                updatedAt: Date(timeIntervalSince1970: 200)
            ),
            shares: 100
        )

        let observations = try store.loadEstimateObservations(for: "001437")
        let observation = try XCTUnwrap(observations.first)

        XCTAssertEqual(observations.count, 1)
        XCTAssertEqual(observation.valuationDate, "2026-03-14")
        XCTAssertEqual(observation.estimatedNav, 1.05, accuracy: 0.0001)
        XCTAssertEqual(observation.officialNav, 1.02, accuracy: 0.0001)
        XCTAssertEqual(observation.returnError, 0.03, accuracy: 0.0001)
    }

    @MainActor
    func testEstimatedSnapshotAppliesRollingBiasCorrectionFromObservationHistory() throws {
        let container = try TestSupport.makeModelContainer()
        let store = FundStore(modelContext: container.mainContext)
        _ = try store.upsertTrackedFund(code: "001437", assetKind: .fund, shares: 100, makePrimary: true)

        for day in 14...21 {
            let valuationDate = "2026-03-\(String(format: "%02d", day))"
            try store.saveSnapshot(
                FundRefreshPayload(
                    storageCode: "001437",
                    assetKind: .fund,
                    name: "测试基金",
                    displayValue: 1.0500,
                    displayChangePct: 5.0,
                    estimatedProfitAmount: 5.0,
                    referenceValue: 1.0000,
                    referenceDate: "2026-03-13",
                    valuationDate: valuationDate,
                    sourceMode: .estimated,
                    statusMessage: "本地参考估算",
                    updatedAt: Date(timeIntervalSince1970: TimeInterval(day))
                ),
                shares: 100
            )
            try store.saveSnapshot(
                FundRefreshPayload(
                    storageCode: "001437",
                    assetKind: .fund,
                    name: "测试基金",
                    displayValue: 1.0200,
                    displayChangePct: 2.0,
                    estimatedProfitAmount: 2.0,
                    referenceValue: 1.0000,
                    referenceDate: valuationDate,
                    valuationDate: valuationDate,
                    sourceMode: .official,
                    statusMessage: "官方净值已发布",
                    updatedAt: Date(timeIntervalSince1970: TimeInterval(day) + 0.5)
                ),
                shares: 100
            )
        }

        try store.saveSnapshot(
            FundRefreshPayload(
                storageCode: "001437",
                assetKind: .fund,
                name: "测试基金",
                displayValue: 1.0500,
                displayChangePct: 5.0,
                estimatedProfitAmount: 5.0,
                referenceValue: 1.0000,
                referenceDate: "2026-03-21",
                valuationDate: "2026-03-24",
                sourceMode: .estimated,
                statusMessage: "本地参考估算",
                updatedAt: Date(timeIntervalSince1970: 300)
            ),
            shares: 100
        )

        let correctedSnapshot = try XCTUnwrap(store.snapshot(for: "001437"))
        XCTAssertLessThan(correctedSnapshot.estimatedNav, 1.04)
        XCTAssertGreaterThan(correctedSnapshot.estimatedNav, 1.02)
        XCTAssertLessThan(correctedSnapshot.estimatedChangePct, 5.0)
    }

    @MainActor
    func testLoadEstimateLearningSummariesBuildsConfidenceMetrics() throws {
        let container = try TestSupport.makeModelContainer()
        let context = container.mainContext
        for index in 0..<10 {
            context.insert(
                FundEstimateObservation(
                    fundCode: "001437",
                    valuationDate: "2026-03-\(String(format: "%02d", index + 1))",
                    estimatedNav: 1.0,
                    officialNav: 0.998,
                    referenceValue: 1.0,
                    estimatedReturn: 0,
                    officialReturn: -0.002,
                    returnError: 0.002,
                    absoluteReturnError: 0.002,
                    createdAt: Date(timeIntervalSince1970: TimeInterval(index))
                )
            )
        }
        try context.save()

        let store = FundStore(modelContext: context)
        let summary = try XCTUnwrap(store.loadEstimateLearningSummaries()["001437"])

        XCTAssertEqual(summary.learningDays, 10)
        XCTAssertEqual(summary.averageAbsoluteErrorPct, 0.2, accuracy: 0.0001)
        XCTAssertEqual(summary.confidence, .high)
    }
}
