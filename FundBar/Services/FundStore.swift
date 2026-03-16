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
    private static let maximumStoredObservationsPerFund = 60

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

    func loadEstimateObservations(for storageCode: String) throws -> [FundEstimateObservation] {
        let observations = try context.fetch(FetchDescriptor<FundEstimateObservation>())
        return observations
            .filter { $0.fundCode == storageCode }
            .sorted { lhs, rhs in
                if lhs.valuationDate != rhs.valuationDate {
                    return lhs.valuationDate > rhs.valuationDate
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    func loadEstimateLearningSummaries() throws -> [String: EstimateLearningSummary] {
        let observations = try context.fetch(FetchDescriptor<FundEstimateObservation>())
        let grouped = Dictionary(grouping: observations, by: \.fundCode)

        return grouped.reduce(into: [:]) { partialResult, element in
            let ordered = element.value.sorted { lhs, rhs in
                if lhs.valuationDate != rhs.valuationDate {
                    return lhs.valuationDate > rhs.valuationDate
                }
                return lhs.createdAt > rhs.createdAt
            }
            let recent = Array(ordered.prefix(15))
            guard !recent.isEmpty else { return }

            let averageAbsoluteErrorPct = recent.reduce(0.0) { partialResult, observation in
                partialResult + observation.absoluteReturnError * 100
            } / Double(recent.count)

            partialResult[element.key] = EstimateLearningSummary(
                learningDays: recent.count,
                averageAbsoluteErrorPct: rounded(averageAbsoluteErrorPct, scale: 2),
                confidence: estimateConfidence(
                    sampleCount: recent.count,
                    averageAbsoluteErrorPct: averageAbsoluteErrorPct
                )
            )
        }
    }

    func latestEstimateComparison(for storageCode: String) throws -> EstimateComparisonData? {
        let observations = try loadEstimateObservations(for: storageCode)
        guard let latest = observations.first, latest.officialNav > 0, latest.referenceValue > 0 else { return nil }
        let errorPct = (latest.estimatedNav / latest.officialNav - 1) * 100
        return EstimateComparisonData(
            valuationDate: latest.valuationDate,
            estimatedNav: latest.estimatedNav,
            officialNav: latest.officialNav,
            errorPct: rounded(errorPct, scale: 2)
        )
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
                try migrateObservations(
                    from: originalStorageCode,
                    to: storageCode,
                    keepsKind: AssetIdentity.kind(from: originalStorageCode) == assetKind
                )
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
        try deleteObservations(for: storageCode)

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
        let existingSnapshot = try snapshot(for: payload.storageCode)
        let adjustedPayload = try applyRollingBiasCorrection(to: payload, shares: shares)

        if adjustedPayload.assetKind == .fund,
           adjustedPayload.sourceMode == .official,
           let existingSnapshot {
            try recordOfficialOutcomeIfNeeded(previousSnapshot: existingSnapshot, officialPayload: adjustedPayload)
        }

        let snapshot = existingSnapshot ?? {
            let created = FundSnapshot(
                fundCode: adjustedPayload.storageCode,
                name: adjustedPayload.name,
                estimatedNav: adjustedPayload.displayValue,
                estimatedChangePct: adjustedPayload.displayChangePct,
                estimatedProfitAmount: adjustedPayload.estimatedProfitAmount,
                lastNav: adjustedPayload.referenceValue,
                lastNavDate: adjustedPayload.referenceDate,
                valuationDate: adjustedPayload.valuationDate,
                updatedAt: adjustedPayload.updatedAt,
                isStale: false,
                sourceMode: adjustedPayload.sourceMode,
                statusMessage: adjustedPayload.statusMessage
            )
            context.insert(created)
            return created
        }()

        snapshot.name = adjustedPayload.name
        snapshot.estimatedNav = adjustedPayload.displayValue
        snapshot.estimatedChangePct = adjustedPayload.displayChangePct
        snapshot.estimatedProfitAmount = adjustedPayload.estimatedProfitAmount
        snapshot.lastNav = adjustedPayload.referenceValue
        snapshot.lastNavDate = adjustedPayload.referenceDate
        snapshot.valuationDate = adjustedPayload.valuationDate
        snapshot.updatedAt = adjustedPayload.updatedAt
        snapshot.lastAttemptAt = adjustedPayload.updatedAt
        snapshot.isStale = false
        snapshot.sourceMode = adjustedPayload.sourceMode
        snapshot.statusMessage = adjustedPayload.statusMessage

        // 仅同步份额，不更新 updatedAt 以保留「用户最后编辑时间」排序语义
        if let trackedFund = try loadTrackedFunds().first(where: { $0.code == adjustedPayload.storageCode }),
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

    private func rounded(_ value: Double, scale: Int) -> Double {
        let divisor = pow(10.0, Double(scale))
        return (value * divisor).rounded() / divisor
    }

    private func applyRollingBiasCorrection(to payload: FundRefreshPayload, shares: Double) throws -> FundRefreshPayload {
        guard payload.assetKind == .fund,
              payload.sourceMode != .official,
              payload.referenceValue > 0 else {
            return payload
        }

        let bias = try rollingBias(for: payload.storageCode)
        guard bias.sampleCount > 0, abs(bias.biasReturn) > 0.000_01 else {
            return payload
        }

        let sampleConfidence = min(Double(bias.sampleCount) / 8, 1)
        let consistency = min(abs(bias.biasReturn) / max(bias.absoluteReturnError, abs(bias.biasReturn)), 1)
        let appliedBias = bias.biasReturn * sampleConfidence * consistency * 0.8
        guard abs(appliedBias) > 0.000_01 else {
            return payload
        }

        let rawReturn = payload.displayValue / payload.referenceValue - 1
        let correctedReturn = rawReturn - appliedBias
        let correctedNav = rounded(max(payload.referenceValue * (1 + correctedReturn), 0.0001), scale: 4)
        let correctedChangePct = rounded((correctedNav / payload.referenceValue - 1) * 100, scale: 2)
        let correctedProfit = rounded((correctedNav - payload.referenceValue) * shares, scale: 2)

        return FundRefreshPayload(
            storageCode: payload.storageCode,
            assetKind: payload.assetKind,
            name: payload.name,
            displayValue: correctedNav,
            displayChangePct: correctedChangePct,
            estimatedProfitAmount: correctedProfit,
            referenceValue: payload.referenceValue,
            referenceDate: payload.referenceDate,
            valuationDate: payload.valuationDate,
            sourceMode: payload.sourceMode,
            statusMessage: payload.statusMessage,
            updatedAt: payload.updatedAt
        )
    }

    private func recordOfficialOutcomeIfNeeded(previousSnapshot: FundSnapshot, officialPayload: FundRefreshPayload) throws {
        guard previousSnapshot.sourceMode != .official,
              previousSnapshot.valuationDate == officialPayload.valuationDate,
              previousSnapshot.lastNav > 0,
              officialPayload.referenceValue > 0 else {
            return
        }

        let estimatedReturn = previousSnapshot.estimatedNav / previousSnapshot.lastNav - 1
        let officialReturn = officialPayload.displayValue / officialPayload.referenceValue - 1
        let returnError = estimatedReturn - officialReturn
        let absoluteReturnError = abs(returnError)

        let observation = try existingObservation(
            for: officialPayload.storageCode,
            valuationDate: officialPayload.valuationDate
        ) ?? {
            let created = FundEstimateObservation(
                fundCode: officialPayload.storageCode,
                valuationDate: officialPayload.valuationDate,
                estimatedNav: previousSnapshot.estimatedNav,
                officialNav: officialPayload.displayValue,
                referenceValue: officialPayload.referenceValue,
                estimatedReturn: estimatedReturn,
                officialReturn: officialReturn,
                returnError: returnError,
                absoluteReturnError: absoluteReturnError,
                createdAt: officialPayload.updatedAt
            )
            context.insert(created)
            return created
        }()

        observation.fundCode = officialPayload.storageCode
        observation.valuationDate = officialPayload.valuationDate
        observation.estimatedNav = previousSnapshot.estimatedNav
        observation.officialNav = officialPayload.displayValue
        observation.referenceValue = officialPayload.referenceValue
        observation.estimatedReturn = estimatedReturn
        observation.officialReturn = officialReturn
        observation.returnError = returnError
        observation.absoluteReturnError = absoluteReturnError
        observation.createdAt = officialPayload.updatedAt

        try trimObservationHistory(for: officialPayload.storageCode)
    }

    private func rollingBias(for storageCode: String) throws -> (biasReturn: Double, absoluteReturnError: Double, sampleCount: Int) {
        let observations = try loadEstimateObservations(for: storageCode)
        guard !observations.isEmpty else {
            return (0, 0, 0)
        }

        let limited = Array(observations.prefix(20))
        var weightedBias = 0.0
        var weightedAbsolute = 0.0
        var totalWeight = 0.0

        for (index, observation) in limited.enumerated() {
            let weight = pow(0.85, Double(index))
            totalWeight += weight
            weightedBias += observation.returnError * weight
            weightedAbsolute += observation.absoluteReturnError * weight
        }

        guard totalWeight > 0 else {
            return (0, 0, 0)
        }

        return (
            biasReturn: weightedBias / totalWeight,
            absoluteReturnError: weightedAbsolute / totalWeight,
            sampleCount: limited.count
        )
    }

    private func existingObservation(for storageCode: String, valuationDate: String) throws -> FundEstimateObservation? {
        try loadEstimateObservations(for: storageCode).first {
            $0.valuationDate == valuationDate
        }
    }

    private func migrateObservations(from originalStorageCode: String, to storageCode: String, keepsKind: Bool) throws {
        let observations = try loadEstimateObservations(for: originalStorageCode)
        for observation in observations {
            if keepsKind {
                observation.fundCode = storageCode
            } else {
                context.delete(observation)
            }
        }
    }

    private func deleteObservations(for storageCode: String) throws {
        for observation in try loadEstimateObservations(for: storageCode) {
            context.delete(observation)
        }
    }

    private func trimObservationHistory(for storageCode: String) throws {
        let observations = try loadEstimateObservations(for: storageCode)
        guard observations.count > Self.maximumStoredObservationsPerFund else {
            return
        }

        for observation in observations.dropFirst(Self.maximumStoredObservationsPerFund) {
            context.delete(observation)
        }
    }

    private func estimateConfidence(sampleCount: Int, averageAbsoluteErrorPct: Double) -> EstimateConfidence {
        if sampleCount >= 10, averageAbsoluteErrorPct <= 0.35 {
            return .high
        }
        if sampleCount >= 5, averageAbsoluteErrorPct <= 0.8 {
            return .medium
        }
        return .low
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
