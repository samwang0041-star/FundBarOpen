import SwiftData
import XCTest
@testable import FundBar

final class MenuBarViewModelTests: XCTestCase {
    private struct MockRefreshError: LocalizedError {
        let errorDescription: String? = "mock refresh failure"
    }

    private struct MockCloudKitStatusProvider: CloudKitStatusProviding {
        let availabilityValue: CloudKitAvailability

        func availability(containerIdentifier: String?) async -> CloudKitAvailability {
            availabilityValue
        }
    }

    private final class MockLaunchAtLoginController: LaunchAtLoginControlling {
        var isEnabled: Bool
        var nextError: Error?

        init(isEnabled: Bool, nextError: Error? = nil) {
            self.isEnabled = isEnabled
            self.nextError = nextError
        }

        func setEnabled(_ enabled: Bool) throws {
            if let nextError {
                throw nextError
            }
            isEnabled = enabled
        }
    }

    private actor MockAssetRefresher: AssetRefreshing {
        enum Outcome {
            case success(FundRefreshPayload)
            case failure(Error)
        }

        private var outcomes: [Outcome]

        init(outcomes: [Outcome]) {
            self.outcomes = outcomes
        }

        func validateAsset(storageCode: String) async throws -> String {
            "mock asset"
        }

        func refreshAsset(storageCode: String, shares: Double, hasExistingSnapshot: Bool) async throws -> FundRefreshPayload {
            let outcome = outcomes.removeFirst()
            switch outcome {
            case .success(let payload):
                return payload
            case .failure(let error):
                throw error
            }
        }
    }

    private struct MockLaunchAtLoginError: LocalizedError {
        let errorDescription: String? = "mock launch error"
    }

    @MainActor
    func testSyncStatusMessageRecoversAfterSuccessfulRefresh() async throws {
        let container = try TestSupport.makeModelContainer()
        let store = FundStore(modelContext: container.mainContext)
        _ = try store.upsertTrackedFund(code: "001437", assetKind: .fund, shares: 100, makePrimary: true)

        let successPayload = FundRefreshPayload(
            storageCode: "001437",
            assetKind: .fund,
            name: "测试基金",
            displayValue: 1.2456,
            displayChangePct: 1.23,
            estimatedProfitAmount: 123.45,
            referenceValue: 1.2000,
            referenceDate: "2026-03-13",
            sourceMode: .estimated,
            statusMessage: "刷新成功",
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let viewModel = MenuBarViewModel(
            modelContainer: container,
            syncMode: .localFallback,
            syncStatusMessage: "CloudKit 未配置，当前使用本地存储。",
            estimator: MockAssetRefresher(outcomes: [
                .failure(MockRefreshError()),
                .success(successPayload)
            ])
        )

        await viewModel.refreshAll(manual: false)
        XCTAssertEqual(viewModel.syncStatusMessage, "部分刷新失败，已保留本地快照。")

        await viewModel.refreshAll(manual: false)
        XCTAssertEqual(viewModel.syncStatusMessage, "CloudKit 未配置，当前使用本地存储。")
    }

    @MainActor
    func testDeletePromptFallsBackToKindAndCodeBeforeFirstRefresh() throws {
        let container = try TestSupport.makeModelContainer()
        let store = FundStore(modelContext: container.mainContext)
        _ = try store.upsertTrackedFund(code: "001437", assetKind: .fund, shares: 0, makePrimary: true)

        let viewModel = MenuBarViewModel(
            modelContainer: container,
            syncMode: .localFallback,
            syncStatusMessage: "CloudKit 未配置，当前使用本地存储。"
        )

        XCTAssertEqual(viewModel.deletePromptTitle(for: "001437"), "基金 001437")
    }

    @MainActor
    func testCloudKitStatusMessageWaitsForAccountAvailability() async throws {
        let container = try TestSupport.makeModelContainer()
        let viewModel = MenuBarViewModel(
            modelContainer: container,
            syncMode: .cloudKit,
            syncStatusMessage: "iCloud 已配置，正在检查账户状态。",
            cloudKitContainerIdentifier: "iCloud.com.yuriwong.FundBar",
            cloudKitStatusProvider: MockCloudKitStatusProvider(availabilityValue: .noAccount)
        )

        await viewModel.start()

        XCTAssertEqual(viewModel.syncStatusMessage, "未登录 iCloud，当前无法同步。")
    }

    @MainActor
    func testOfficialSnapshotMessageOverridesLegacyEstimatedCopy() async throws {
        let container = try TestSupport.makeModelContainer()
        let store = FundStore(modelContext: container.mainContext)
        _ = try store.upsertTrackedFund(code: "001437", assetKind: .fund, shares: 100, makePrimary: true)

        let payload = FundRefreshPayload(
            storageCode: "001437",
            assetKind: .fund,
            name: "测试基金",
            displayValue: 1.2345,
            displayChangePct: 0.88,
            estimatedProfitAmount: 88,
            referenceValue: 1.2237,
            referenceDate: "2026-03-13",
            sourceMode: .official,
            statusMessage: "今日盘中估算参考",
            updatedAt: Date(timeIntervalSince1970: 300)
        )

        let viewModel = MenuBarViewModel(
            modelContainer: container,
            syncMode: .localFallback,
            syncStatusMessage: "CloudKit 未配置，当前使用本地存储。",
            estimator: MockAssetRefresher(outcomes: [.success(payload)])
        )

        await viewModel.refreshAll(manual: false)

        XCTAssertEqual(viewModel.primaryAsset?.sourceMode, .official)
        XCTAssertEqual(viewModel.primaryAsset?.statusMessage, "官方净值已发布")
    }

    @MainActor
    func testOfficialSnapshotKeepsExplicitPreOpenMessage() async throws {
        let container = try TestSupport.makeModelContainer()
        let store = FundStore(modelContext: container.mainContext)
        _ = try store.upsertTrackedFund(code: "001437", assetKind: .fund, shares: 100, makePrimary: true)

        let payload = FundRefreshPayload(
            storageCode: "001437",
            assetKind: .fund,
            name: "测试基金",
            displayValue: 1.2345,
            displayChangePct: 0.88,
            estimatedProfitAmount: 88,
            referenceValue: 1.2237,
            referenceDate: "2026-03-13",
            sourceMode: .official,
            statusMessage: "待开盘，展示上一交易日官方净值",
            updatedAt: Date(timeIntervalSince1970: 300)
        )

        let viewModel = MenuBarViewModel(
            modelContainer: container,
            syncMode: .localFallback,
            syncStatusMessage: "CloudKit 未配置，当前使用本地存储。",
            estimator: MockAssetRefresher(outcomes: [.success(payload)])
        )

        await viewModel.refreshAll(manual: false)

        XCTAssertEqual(viewModel.primaryAsset?.statusMessage, "待开盘，展示上一交易日官方净值")
    }

    @MainActor
    func testQDIIMarketStateUsesOverseasTimingLabel() async throws {
        let container = try TestSupport.makeModelContainer()
        let store = FundStore(modelContext: container.mainContext)
        _ = try store.upsertTrackedFund(code: "001437", assetKind: .fund, shares: 100, makePrimary: true)

        let payload = FundRefreshPayload(
            storageCode: "001437",
            assetKind: .fund,
            name: "全球科技QDII",
            displayValue: 1.2345,
            displayChangePct: 0.88,
            estimatedProfitAmount: 88,
            referenceValue: 1.2237,
            referenceDate: "2026-03-13",
            sourceMode: .official,
            statusMessage: "QDII 官方净值已发布",
            updatedAt: Date(timeIntervalSince1970: 300)
        )

        let viewModel = MenuBarViewModel(
            modelContainer: container,
            syncMode: .localFallback,
            syncStatusMessage: "CloudKit 未配置，当前使用本地存储。",
            estimator: MockAssetRefresher(outcomes: [.success(payload)])
        )

        await viewModel.refreshAll(manual: false)

        XCTAssertEqual(viewModel.marketStateText, "海外时差")
        XCTAssertNil(viewModel.statusBarSessionText)
    }

    @MainActor
    func testLaunchAtLoginToggleUpdatesPublishedStateOnSuccess() throws {
        let container = try TestSupport.makeModelContainer()
        let launchController = MockLaunchAtLoginController(isEnabled: false)
        let viewModel = MenuBarViewModel(
            modelContainer: container,
            syncMode: .localFallback,
            syncStatusMessage: "CloudKit 未配置，当前使用本地存储。",
            launchAtLoginController: launchController
        )

        viewModel.setLaunchAtLoginEnabled(true)

        XCTAssertTrue(viewModel.launchAtLoginEnabled)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testLaunchAtLoginToggleShowsErrorOnFailure() throws {
        let container = try TestSupport.makeModelContainer()
        let launchController = MockLaunchAtLoginController(
            isEnabled: false,
            nextError: MockLaunchAtLoginError()
        )
        let viewModel = MenuBarViewModel(
            modelContainer: container,
            syncMode: .localFallback,
            syncStatusMessage: "CloudKit 未配置，当前使用本地存储。",
            launchAtLoginController: launchController
        )

        viewModel.setLaunchAtLoginEnabled(true)

        XCTAssertFalse(viewModel.launchAtLoginEnabled)
        XCTAssertEqual(viewModel.errorMessage, "开机启动设置失败：mock launch error")
    }
}
