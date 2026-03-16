import Foundation
import SwiftData

struct FundEditorState: Identifiable {
    let id = UUID()
    let originalStorageCode: String?
    let initialCode: String
    let initialShares: String
    let initialIsPrimary: Bool
    let initialAssetKind: AssetKind

    var title: String {
        originalStorageCode == nil ? "添加自选项" : "编辑自选项"
    }
}

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published private(set) var assets: [FundViewData] = []
    @Published private(set) var isRefreshing = false
    @Published var errorMessage: String?
    @Published private(set) var syncStatusMessage: String
    @Published private(set) var syncMode: PersistenceSyncMode
    @Published private(set) var lastRefreshAt: Date?
    @Published private(set) var statusBarPulseToken = 0
    @Published private(set) var launchAtLoginEnabled: Bool
    @Published private(set) var colorSchemePreference: AppColorSchemePreference = .light
    @Published private(set) var statusBarDisplayMode: StatusBarDisplayMode = .percentAndAmount
    @Published var editorState: FundEditorState?
    @Published var pendingDeleteCode: String?
    @Published var isManagingAssets = false

    private let pendingRefreshPlaceholder = "等待首次刷新"

    private var errorDismissTask: Task<Void, Never>?

    private var isPrimaryUsingOverseasTiming: Bool {
        guard let primaryAsset else { return false }
        return primaryAsset.assetKind == .fund && primaryAsset.statusMessage.contains("QDII")
    }

    var primaryAsset: FundViewData? {
        assets.first(where: \.isPrimary)
    }

    var statusBarText: String {
        DisplayFormatting.statusBarTitle(primaryFund: primaryAsset)
    }

    var canAddMoreAssets: Bool {
        assets.count < FundStore.maximumTrackedFunds
    }

    var totalDailyProfit: Double? {
        let profits = assets.compactMap { $0.estimatedProfitAmount }
        guard !profits.isEmpty else { return nil }
        return profits.reduce(0, +)
    }

    var marketStateText: String {
        if isPrimaryUsingOverseasTiming {
            return "海外时差"
        }
        switch marketCalendar.phase() {
        case .open:
            return "开盘中"
        case .lunchBreak:
            return "午休"
        case .preOpenAuction:
            return "盘前竞价"
        case .preOpenQuiet:
            return "待开盘"
        case .overnight, .postClose, .holidayClosed:
            return "已收盘"
        }
    }

    var statusBarSessionText: String? {
        if isPrimaryUsingOverseasTiming {
            return nil
        }
        switch marketCalendar.phase() {
        case .open, .preOpenAuction:
            return nil
        case .lunchBreak:
            return "午休"
        case .preOpenQuiet:
            return "待开盘"
        case .overnight, .postClose, .holidayClosed:
            return "已收盘"
        }
    }

    var showsStatusBarArrow: Bool {
        if isPrimaryUsingOverseasTiming {
            return true
        }
        switch marketCalendar.phase() {
        case .open, .preOpenAuction:
            return true
        case .lunchBreak, .preOpenQuiet, .overnight, .postClose, .holidayClosed:
            return false
        }
    }

    private let store: FundStore
    private let estimator: any AssetRefreshing
    private let scheduler: RefreshScheduler
    private let marketCalendar: MarketCalendar
    private let cloudKitContainerIdentifier: String?
    private let cloudKitStatusProvider: any CloudKitStatusProviding
    private let launchAtLoginController: any LaunchAtLoginControlling
    private var defaultSyncStatusMessage: String
    private var consecutiveFailures: [String: Int] = [:]
    private var refreshCycleCount = 0
    private var didStart = false

    init(
        modelContainer: ModelContainer,
        syncMode: PersistenceSyncMode,
        syncStatusMessage: String,
        estimator: any AssetRefreshing = FundEstimatorService(),
        marketCalendar: MarketCalendar = MarketCalendar(),
        cloudKitContainerIdentifier: String? = nil,
        cloudKitStatusProvider: any CloudKitStatusProviding = SystemCloudKitStatusProvider(),
        launchAtLoginController: any LaunchAtLoginControlling = SystemLaunchAtLoginController()
    ) {
        self.store = FundStore(modelContext: modelContainer.mainContext)
        self.estimator = estimator
        self.syncMode = syncMode
        self.syncStatusMessage = syncStatusMessage
        self.defaultSyncStatusMessage = syncStatusMessage
        self.scheduler = RefreshScheduler(marketCalendar: marketCalendar)
        self.marketCalendar = marketCalendar
        self.cloudKitContainerIdentifier = cloudKitContainerIdentifier
        self.cloudKitStatusProvider = cloudKitStatusProvider
        self.launchAtLoginController = launchAtLoginController
        self.launchAtLoginEnabled = launchAtLoginController.isEnabled
    }

    func start() async {
        guard !didStart else { return }
        didStart = true

        do {
            _ = try store.updatePreference(syncMode: syncMode, syncStatusMessage: defaultSyncStatusMessage, lastRefreshAt: nil)
            try reloadFromStore()
            await refreshCloudSyncStatusIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
        }

        scheduler.start { [weak self] in
            await self?.refreshAll(manual: false)
        }
    }

    func refreshAll(manual: Bool) async {
        if isRefreshing {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }
        errorMessage = nil
        refreshCycleCount += 1
        if manual {
            consecutiveFailures.removeAll()
        }

        do {
            let trackedAssets = try store.loadTrackedFunds()
            guard !trackedAssets.isEmpty else {
                let preference = try store.updatePreference(
                    syncMode: syncMode,
                    syncStatusMessage: defaultSyncStatusMessage,
                    lastRefreshAt: nil
                )
                syncStatusMessage = preference.syncStatusMessage
                lastRefreshAt = preference.lastRefreshAt
                try reloadFromStore()
                return
            }

            var failures: [String] = []
            let primaryStorageCode = trackedAssets.first(where: \.isPrimary)?.code
            var didRefreshPrimary = false
            for asset in trackedAssets {
                // Exponential backoff: skip if not yet due
                if !manual, let failCount = consecutiveFailures[asset.code], failCount > 0 {
                    let backoffCycles = 1 << min(failCount, 5) // 2, 4, 8, 16, 32
                    if refreshCycleCount % backoffCycles != 0 {
                        continue
                    }
                }

                let existingSnapshot = try store.snapshot(for: asset.code)
                do {
                    let payload = try await estimator.refreshAsset(storageCode: asset.code, shares: asset.shares, hasExistingSnapshot: existingSnapshot != nil)
                    try store.saveSnapshot(payload, shares: asset.shares)
                    consecutiveFailures[asset.code] = nil
                    if asset.code == primaryStorageCode {
                        didRefreshPrimary = true
                    }
                } catch {
                    consecutiveFailures[asset.code, default: 0] += 1
                    failures.append("\(asset.displayCode)：\(error.localizedDescription)")
                    try store.markSnapshotStale(
                        for: asset.code,
                        message: "刷新失败，已保留上次成功数据。",
                        attemptedAt: Date()
                    )
                }
            }

            let refreshAt = Date()
            let statusMessage = failures.isEmpty ? defaultSyncStatusMessage : "部分刷新失败，已保留本地快照。"
            let preference = try store.updatePreference(syncMode: syncMode, syncStatusMessage: statusMessage, lastRefreshAt: refreshAt)
            syncStatusMessage = preference.syncStatusMessage
            lastRefreshAt = preference.lastRefreshAt
            try reloadFromStore()
            if didRefreshPrimary {
                statusBarPulseToken += 1
            }

            if let firstFailure = failures.first {
                showError(firstFailure)
            } else if manual {
                errorMessage = nil
            }
        } catch {
            showError(error.localizedDescription)
        }
    }

    func presentAddSheet() {
        guard canAddMoreAssets else {
            showError(FundStoreError.maximumTrackedFundsReached.localizedDescription)
            return
        }
        editorState = FundEditorState(
            originalStorageCode: nil,
            initialCode: "",
            initialShares: "",
            initialIsPrimary: assets.isEmpty,
            initialAssetKind: .fund
        )
    }

    func presentEditSheet(for storageCode: String) {
        guard let asset = assets.first(where: { $0.storageCode == storageCode }) else { return }
        editorState = FundEditorState(
            originalStorageCode: storageCode,
            initialCode: asset.code,
            initialShares: asset.shares == 0 ? "" : DisplayFormatting.quantity(asset.shares, for: asset.assetKind),
            initialIsPrimary: asset.isPrimary,
            initialAssetKind: asset.assetKind
        )
    }

    func dismissEditor() {
        editorState = nil
    }

    func validateAsset(code: String, assetKind: AssetKind) async throws -> String {
        let normalizedCode = AssetIdentity.normalizedDisplayCode(code, kind: assetKind)
        let storageCode = AssetIdentity.storageCode(for: normalizedCode, kind: assetKind)
        return try await estimator.validateAsset(storageCode: storageCode)
    }

    func saveAsset(originalStorageCode: String?, code: String, assetKind: AssetKind, sharesText: String, makePrimary: Bool) async {
        do {
            let normalizedShares = sharesText.trimmingCharacters(in: .whitespacesAndNewlines)
            let shares = normalizedShares.isEmpty ? 0 : (Double(normalizedShares) ?? -1)
            _ = try store.saveTrackedFund(
                originalStorageCode: originalStorageCode,
                code: code,
                assetKind: assetKind,
                shares: shares,
                makePrimary: makePrimary
            )
            editorState = nil
            try reloadFromStore()
            await refreshAll(manual: true)
        } catch {
            showError(error.localizedDescription)
        }
    }

    func moveAssets(fromOffsets source: IndexSet, toOffset destination: Int) {
        do {
            try store.moveAssets(fromOffsets: source, toOffset: destination)
            try reloadFromStore()
        } catch {
            showError(error.localizedDescription)
        }
    }

    func confirmDelete() {
        guard let storageCode = pendingDeleteCode else { return }
        pendingDeleteCode = nil
        do {
            try store.deleteTrackedFund(storageCode: storageCode)
            try reloadFromStore()
        } catch {
            showError(error.localizedDescription)
        }
    }

    func setPrimary(storageCode: String) async {
        do {
            try store.setPrimary(storageCode: storageCode)
            try reloadFromStore()
        } catch {
            showError(error.localizedDescription)
        }
    }

    func deletePromptTitle(for storageCode: String) -> String {
        guard let asset = assets.first(where: { $0.storageCode == storageCode }) else {
            return "\(AssetIdentity.kind(from: storageCode).title) \(AssetIdentity.displayCode(from: storageCode))"
        }

        let sanitizedName = asset.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasResolvedName = !sanitizedName.isEmpty && sanitizedName != pendingRefreshPlaceholder
        if hasResolvedName {
            return "\(asset.assetKind.title) \(asset.code) · \(sanitizedName)"
        }
        return "\(asset.assetKind.title) \(asset.code)"
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            try launchAtLoginController.setEnabled(enabled)
            launchAtLoginEnabled = launchAtLoginController.isEnabled
        } catch {
            launchAtLoginEnabled = launchAtLoginController.isEnabled
            showError("开机启动设置失败：\(error.localizedDescription)")
        }
    }

    func setColorScheme(_ preference: AppColorSchemePreference) {
        do {
            if let pref = try store.currentPreference() {
                pref.colorSchemePreference = preference
                try store.saveContext()
            }
            colorSchemePreference = preference
        } catch {
            showError(error.localizedDescription)
        }
    }

    func setStatusBarDisplayMode(_ mode: StatusBarDisplayMode) {
        do {
            if let pref = try store.currentPreference() {
                pref.statusBarDisplayMode = mode
                try store.saveContext()
            }
            statusBarDisplayMode = mode
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        errorDismissTask?.cancel()
        errorDismissTask = Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            await MainActor.run { errorMessage = nil }
        }
    }

    private func refreshCloudSyncStatusIfNeeded() async {
        guard syncMode == .cloudKit else { return }

        let availability = await cloudKitStatusProvider.availability(containerIdentifier: cloudKitContainerIdentifier)
        let message = availability.statusMessage
        guard message != syncStatusMessage else { return }

        do {
            let preference = try store.updatePreference(
                syncMode: syncMode,
                syncStatusMessage: message,
                lastRefreshAt: lastRefreshAt
            )
            syncStatusMessage = preference.syncStatusMessage
            defaultSyncStatusMessage = preference.syncStatusMessage
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func reloadFromStore() throws {
        let trackedAssets = try store.loadTrackedFunds()
        let snapshots = Dictionary(uniqueKeysWithValues: try store.loadSnapshots().map { ($0.fundCode, $0) })
        let learningSummaries = try store.loadEstimateLearningSummaries()
        let preference = try store.currentPreference()

        assets = trackedAssets.map { asset in
            let snapshot = snapshots[asset.code]
            let comparison: EstimateComparisonData? = asset.assetKind == .fund ? (try? store.latestEstimateComparison(for: asset.code)) : nil
            return FundViewData(
                storageCode: asset.code,
                assetKind: asset.assetKind,
                code: asset.displayCode,
                name: snapshot?.name ?? "等待首次刷新",
                shares: asset.shares,
                isPrimary: asset.isPrimary,
                displayValue: snapshot?.estimatedNav,
                displayChangePct: snapshot?.estimatedChangePct,
                estimatedProfitAmount: snapshot?.estimatedProfitAmount,
                referenceDate: snapshot?.lastNavDate,
                updatedAt: snapshot?.updatedAt,
                isStale: snapshot?.isStale ?? false,
                sourceMode: snapshot?.sourceMode,
                statusMessage: resolvedStatusMessage(snapshot: snapshot, assetKind: asset.assetKind),
                learningSummary: learningSummaries[asset.code],
                estimateComparison: comparison
            )
        }

        lastRefreshAt = preference?.lastRefreshAt
        if let preference {
            syncMode = preference.syncMode
            syncStatusMessage = preference.syncStatusMessage
            colorSchemePreference = preference.colorSchemePreference
            statusBarDisplayMode = preference.statusBarDisplayMode
        }
    }

    private func resolvedStatusMessage(snapshot: FundSnapshot?, assetKind: AssetKind) -> String {
        guard let snapshot else {
            return pendingRefreshPlaceholder
        }

        if snapshot.isStale {
            return snapshot.statusMessage
        }

        let trimmedMessage = snapshot.statusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedMessage.isEmpty {
            if assetKind == .fund,
               snapshot.sourceMode == .official,
               (trimmedMessage.contains("盘中估算")
                || trimmedMessage.contains("估算参考")
                || trimmedMessage.contains("本地估算")
                || trimmedMessage.contains("参考估算")) {
                return "官方净值已发布"
            }
            return trimmedMessage
        }

        switch (assetKind, snapshot.sourceMode) {
        case (.fund, .official):
            return "官方净值已发布"
        case (.fund, .realtime):
            return "本地参考估算"
        case (.fund, .estimated):
            return "本地参考估算"
        case (.fund, .preOpenEstimated):
            return "本地盘前估算"
        case (.fund, .estimatedClosed):
            return "展示上一交易日本地估算"
        case (.stock, .realtime):
            return "盘中实时行情"
        case (.stock, .official):
            return "收盘行情参考"
        case (.stock, .estimated), (.stock, .preOpenEstimated), (.stock, .estimatedClosed):
            return "收盘行情参考"
        }
    }
}
