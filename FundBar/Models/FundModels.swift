import Foundation
import SwiftData

enum AssetKind: String, Codable, CaseIterable, Sendable {
    case fund
    case stock

    var title: String {
        switch self {
        case .fund:
            return "基金"
        case .stock:
            return "股票"
        }
    }

    var displayValueTitle: String {
        switch self {
        case .fund:
            return "参考估值"
        case .stock:
            return "最新价"
        }
    }

    var referenceDateTitle: String {
        switch self {
        case .fund:
            return "净值日"
        case .stock:
            return "行情日"
        }
    }

    var quantityTitle: String {
        switch self {
        case .fund:
            return "持仓份额"
        case .stock:
            return "持仓股数"
        }
    }
}

enum AssetIdentity {
    private static let stockPrefix = "stock:"

    static func normalizedDisplayCode(_ rawCode: String, kind: AssetKind) -> String {
        let trimmed = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .fund:
            return trimmed
        case .stock:
            let lowered = trimmed.lowercased()
            if lowered.hasPrefix("sh") || lowered.hasPrefix("sz") {
                return String(lowered.dropFirst(2))
            }
            return lowered
        }
    }

    static func isValidDisplayCode(_ rawCode: String, kind: AssetKind) -> Bool {
        let normalized = normalizedDisplayCode(rawCode, kind: kind)
        return normalized.range(of: #"^\d{6}$"#, options: .regularExpression) != nil
    }

    static func storageCode(for displayCode: String, kind: AssetKind) -> String {
        let normalized = normalizedDisplayCode(displayCode, kind: kind)
        switch kind {
        case .fund:
            return normalized
        case .stock:
            return stockPrefix + normalized
        }
    }

    static func displayCode(from storageCode: String) -> String {
        if storageCode.hasPrefix(stockPrefix) {
            return String(storageCode.dropFirst(stockPrefix.count))
        }
        return storageCode
    }

    static func kind(from storageCode: String) -> AssetKind {
        storageCode.hasPrefix(stockPrefix) ? .stock : .fund
    }
}

enum SnapshotSourceMode: String, Codable, CaseIterable, Sendable {
    case estimated
    case preOpenEstimated
    case estimatedClosed
    case official
    case realtime
}

enum FundTimingProfile: String, Codable, Sendable {
    case domestic
    case qdii

    static func resolve(name: String, fundType: String) -> Self {
        let normalizedName = name.uppercased()
        let normalizedType = fundType.uppercased()
        if normalizedType.contains("QDII") ||
            normalizedType.contains("海外") ||
            normalizedName.contains("QDII") {
            return .qdii
        }
        return .domestic
    }
}

enum PersistenceSyncMode: String, Codable, Sendable {
    case cloudKit
    case localFallback
}

@Model
final class TrackedFund {
    var code: String = ""
    var shares: Double = 0
    var isPrimary: Bool = false
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(code: String, shares: Double, isPrimary: Bool, createdAt: Date = .now, updatedAt: Date = .now) {
        self.code = code
        self.shares = shares
        self.isPrimary = isPrimary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var assetKind: AssetKind {
        AssetIdentity.kind(from: code)
    }

    var displayCode: String {
        AssetIdentity.displayCode(from: code)
    }
}

@Model
final class FundSnapshot {
    var fundCode: String = ""
    var name: String = ""
    var estimatedNav: Double = 0
    var estimatedChangePct: Double = 0
    var estimatedProfitAmount: Double = 0
    var lastNav: Double = 0
    var lastNavDate: String = ""
    var updatedAt: Date = Date.now
    var lastAttemptAt: Date? = nil
    var isStale: Bool = false
    var sourceModeRaw: String = SnapshotSourceMode.estimated.rawValue
    var statusMessage: String = ""

    init(
        fundCode: String,
        name: String,
        estimatedNav: Double,
        estimatedChangePct: Double,
        estimatedProfitAmount: Double,
        lastNav: Double,
        lastNavDate: String,
        updatedAt: Date,
        lastAttemptAt: Date? = nil,
        isStale: Bool,
        sourceMode: SnapshotSourceMode,
        statusMessage: String
    ) {
        self.fundCode = fundCode
        self.name = name
        self.estimatedNav = estimatedNav
        self.estimatedChangePct = estimatedChangePct
        self.estimatedProfitAmount = estimatedProfitAmount
        self.lastNav = lastNav
        self.lastNavDate = lastNavDate
        self.updatedAt = updatedAt
        self.lastAttemptAt = lastAttemptAt ?? updatedAt
        self.isStale = isStale
        self.sourceModeRaw = sourceMode.rawValue
        self.statusMessage = statusMessage
    }

    var sourceMode: SnapshotSourceMode {
        get { SnapshotSourceMode(rawValue: sourceModeRaw) ?? .estimated }
        set { sourceModeRaw = newValue.rawValue }
    }

    var assetKind: AssetKind {
        AssetIdentity.kind(from: fundCode)
    }

    var displayCode: String {
        AssetIdentity.displayCode(from: fundCode)
    }
}

@Model
final class AppPreference {
    var key: String = "main"
    var syncModeRaw: String = PersistenceSyncMode.localFallback.rawValue
    var syncStatusMessage: String = ""
    var lastRefreshAt: Date? = nil

    init(
        key: String = "main",
        syncMode: PersistenceSyncMode,
        syncStatusMessage: String,
        lastRefreshAt: Date? = nil
    ) {
        self.key = key
        self.syncModeRaw = syncMode.rawValue
        self.syncStatusMessage = syncStatusMessage
        self.lastRefreshAt = lastRefreshAt
    }

    var syncMode: PersistenceSyncMode {
        get { PersistenceSyncMode(rawValue: syncModeRaw) ?? .localFallback }
        set { syncModeRaw = newValue.rawValue }
    }
}

struct Holding: Codable, Equatable, Sendable {
    let code: String
    let name: String
    let weight: Double
}

struct FundMetadata: Codable, Equatable, Sendable {
    let fundCode: String
    let name: String
    let fundType: String
    let managerName: String
    let managerCompany: String
    let riskLevel: String
    let inceptionDate: String
    let latestScale: String
    let scaleDate: String
    let lastNav: Double
    let lastNavDate: String
    let stockPosition: Double
    let managementFee: Double
    let custodyFee: Double
    let holdingsReportDate: String?

    var timingProfile: FundTimingProfile {
        FundTimingProfile.resolve(name: name, fundType: fundType)
    }
}

struct SecurityQuote: Codable, Equatable, Sendable {
    let code: String
    let name: String
    let price: Double
    let changePct: Double
    let change: Double
    let volume: Double
    let marketCap: Double
}

struct EstimateBreakdown: Equatable, Sendable {
    let estimatedNav: Double
    let estimatedChange: Double
    let estimatedChangePct: Double
    let knownCoverage: Double
}

struct FundRefreshPayload: Equatable, Sendable {
    let storageCode: String
    let assetKind: AssetKind
    let name: String
    let displayValue: Double
    let displayChangePct: Double
    let estimatedProfitAmount: Double
    let referenceValue: Double
    let referenceDate: String
    let sourceMode: SnapshotSourceMode
    let statusMessage: String
    let updatedAt: Date
}

struct FundViewData: Identifiable, Equatable {
    var id: String { storageCode }
    let storageCode: String
    let assetKind: AssetKind
    let code: String
    let name: String
    let shares: Double
    let isPrimary: Bool
    let displayValue: Double?
    let displayChangePct: Double?
    let estimatedProfitAmount: Double?
    let referenceDate: String?
    let updatedAt: Date?
    let isStale: Bool
    let sourceMode: SnapshotSourceMode?
    let statusMessage: String

    var displayValueTitle: String {
        switch assetKind {
        case .fund:
            switch sourceMode {
            case .official:
                return "官方净值"
            default:
                return "参考估值"
            }
        case .stock:
            switch sourceMode {
            case .official:
                return "收盘价"
            case .realtime where statusMessage.contains("盘前"):
                return "竞价参考"
            default:
                return "最新价"
            }
        }
    }
}
