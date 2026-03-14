import Foundation
import SwiftData

enum FundStoreError: Error, LocalizedError {
    case invalidAssetCode
    case invalidShares
    case fractionalStockShares
    case maximumTrackedFundsReached
    case fundNotFound
    case duplicateAsset

    var errorDescription: String? {
        switch self {
        case .invalidAssetCode:
            return "请输入 6 位代码；股票支持 600519 或 sh600519。"
        case .invalidShares:
            return "持仓数量必须是非负数字。"
        case .fractionalStockShares:
            return "股票持仓股数必须为整数。"
        case .maximumTrackedFundsReached:
            return "最多只能添加 5 个自选项。"
        case .fundNotFound:
            return "未找到对应自选项。"
        case .duplicateAsset:
            return "该资产已经在自选列表里了。"
        }
    }
}

enum FundStoreLimits {
    static let maximumTrackedFunds = 5
}

@MainActor
final class FundStore {
    static let maximumTrackedFunds = FundStoreLimits.maximumTrackedFunds

    private let context: ModelContext

    init(modelContext: ModelContext) {
        self.context = modelContext
    }

    func loadTrackedFunds() throws -> [TrackedFund] {
        let funds = try context.fetch(FetchDescriptor<TrackedFund>())
        let ranked = funds.map { fund in
            (fund: fund, isPrimary: fund.isPrimary, updatedAt: fund.updatedAt)
        }
        return ranked.sorted {
            if $0.isPrimary != $1.isPrimary {
                return $0.isPrimary && !$1.isPrimary
            }
            return $0.updatedAt > $1.updatedAt
        }
        .map(\.fund)
    }

    func loadSnapshots() throws -> [FundSnapshot] {
        let snapshots = try context.fetch(FetchDescriptor<FundSnapshot>())
        let ranked = snapshots.map { snapshot in
            (snapshot: snapshot, updatedAt: snapshot.updatedAt)
        }
        return ranked.sorted { $0.updatedAt > $1.updatedAt }
            .map(\.snapshot)
    }

    func snapshot(for code: String) throws -> FundSnapshot? {
        try loadSnapshots().first(where: { $0.fundCode == code })
    }

    func upsertTrackedFund(code rawCode: String, assetKind: AssetKind, shares: Double, makePrimary: Bool) throws -> TrackedFund {
        try saveTrackedFund(originalStorageCode: nil, code: rawCode, assetKind: assetKind, shares: shares, makePrimary: makePrimary)
    }

    func saveTrackedFund(
        originalStorageCode: String?,
        code rawCode: String,
        assetKind: AssetKind,
        shares: Double,
        makePrimary: Bool
    ) throws -> TrackedFund {
        let code = AssetIdentity.normalizedDisplayCode(rawCode, kind: assetKind)
        guard AssetIdentity.isValidDisplayCode(code, kind: assetKind) else {
            throw FundStoreError.invalidAssetCode
        }
        try Self.validateShares(shares, for: assetKind)

        let storageCode = AssetIdentity.storageCode(for: code, kind: assetKind)

        let existingFunds = try loadTrackedFunds()
        if let originalStorageCode {
            guard let existing = existingFunds.first(where: { $0.code == originalStorageCode }) else {
                throw FundStoreError.fundNotFound
            }

            if storageCode != originalStorageCode,
               existingFunds.contains(where: { $0.code == storageCode }) {
                throw FundStoreError.duplicateAsset
            }

            if storageCode != originalStorageCode {
                existing.code = storageCode
                if let existingSnapshot = try snapshot(for: originalStorageCode) {
                    existingSnapshot.fundCode = storageCode
                }
            }

            existing.shares = shares
            existing.updatedAt = .now
            if makePrimary {
                try setPrimary(storageCode: storageCode)
            } else if existingFunds.filter(\.isPrimary).isEmpty {
                existing.isPrimary = true
            }
            try save()
            return existing
        }

        if let existing = existingFunds.first(where: { $0.code == storageCode }) {
            existing.shares = shares
            existing.updatedAt = .now
            if makePrimary {
                try setPrimary(storageCode: storageCode)
            } else if existingFunds.filter(\.isPrimary).isEmpty {
                existing.isPrimary = true
            }
            try save()
            return existing
        }

        guard existingFunds.count < Self.maximumTrackedFunds else {
            throw FundStoreError.maximumTrackedFundsReached
        }

        let trackedFund = TrackedFund(code: storageCode, shares: shares, isPrimary: false)
        context.insert(trackedFund)
        if makePrimary || existingFunds.isEmpty {
            try setPrimary(storageCode: storageCode)
        }
        try save()
        return trackedFund
    }

    func deleteTrackedFund(storageCode: String) throws {
        let trackedFunds = try loadTrackedFunds()
        guard let fund = trackedFunds.first(where: { $0.code == storageCode }) else {
            throw FundStoreError.fundNotFound
        }

        let wasPrimary = fund.isPrimary
        context.delete(fund)

        // 一并清理对应的快照，避免孤立数据残留
        if let orphanedSnapshot = try snapshot(for: storageCode) {
            context.delete(orphanedSnapshot)
        }

        if wasPrimary {
            let remaining = try loadTrackedFunds().filter { $0.code != storageCode }
            remaining.first?.isPrimary = true
        }

        try save()
    }

    func setPrimary(storageCode: String) throws {
        let trackedFunds = try loadTrackedFunds()
        for fund in trackedFunds {
            fund.isPrimary = fund.code == storageCode
            if fund.isPrimary {
                fund.updatedAt = .now
            }
        }
        try save()
    }

    func saveSnapshot(_ payload: FundRefreshPayload, shares: Double) throws {
        let snapshot = try snapshot(for: payload.storageCode) ?? {
            let created = FundSnapshot(
                fundCode: payload.storageCode,
                name: payload.name,
                estimatedNav: payload.displayValue,
                estimatedChangePct: payload.displayChangePct,
                estimatedProfitAmount: payload.estimatedProfitAmount,
                lastNav: payload.referenceValue,
                lastNavDate: payload.referenceDate,
                updatedAt: payload.updatedAt,
                isStale: false,
                sourceMode: payload.sourceMode,
                statusMessage: payload.statusMessage
            )
            context.insert(created)
            return created
        }()

        snapshot.name = payload.name
        snapshot.estimatedNav = payload.displayValue
        snapshot.estimatedChangePct = payload.displayChangePct
        snapshot.estimatedProfitAmount = payload.estimatedProfitAmount
        snapshot.lastNav = payload.referenceValue
        snapshot.lastNavDate = payload.referenceDate
        snapshot.updatedAt = payload.updatedAt
        snapshot.lastAttemptAt = payload.updatedAt
        snapshot.isStale = false
        snapshot.sourceMode = payload.sourceMode
        snapshot.statusMessage = payload.statusMessage

        // 仅同步份额，不更新 updatedAt 以保留「用户最后编辑时间」排序语义
        if let trackedFund = try loadTrackedFunds().first(where: { $0.code == payload.storageCode }),
           trackedFund.shares != shares {
            trackedFund.shares = shares
            trackedFund.updatedAt = .now
        }

        try save()
    }

    func markSnapshotStale(for storageCode: String, message: String, attemptedAt: Date = .now) throws {
        guard let snapshot = try snapshot(for: storageCode) else {
            return
        }
        snapshot.isStale = true
        snapshot.statusMessage = message
        snapshot.lastAttemptAt = attemptedAt
        try save()
    }

    @discardableResult
    func updatePreference(
        syncMode: PersistenceSyncMode,
        syncStatusMessage: String,
        lastRefreshAt: Date?
    ) throws -> AppPreference {
        let preference = try currentPreference() ?? {
            let created = AppPreference(syncMode: syncMode, syncStatusMessage: syncStatusMessage, lastRefreshAt: lastRefreshAt)
            context.insert(created)
            return created
        }()

        preference.syncMode = syncMode
        preference.syncStatusMessage = syncStatusMessage
        preference.lastRefreshAt = lastRefreshAt
        try save()
        return preference
    }

    func currentPreference() throws -> AppPreference? {
        try context.fetch(FetchDescriptor<AppPreference>()).first
    }

    private func save() throws {
        if context.hasChanges {
            try context.save()
        }
    }

    private static func validateShares(_ shares: Double, for assetKind: AssetKind) throws {
        guard shares.isFinite, shares >= 0 else {
            throw FundStoreError.invalidShares
        }
        if assetKind == .stock, shares.rounded() != shares {
            throw FundStoreError.fractionalStockShares
        }
    }
}
