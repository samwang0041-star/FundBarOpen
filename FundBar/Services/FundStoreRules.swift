import Foundation

struct TrackedFundState: Equatable {
    let storageCode: String
    var shares: Double
    var isPrimary: Bool
    var updatedAt: Date

    var code: String {
        AssetIdentity.displayCode(from: storageCode)
    }

    var assetKind: AssetKind {
        AssetIdentity.kind(from: storageCode)
    }
}

enum FundStoreRules {
    static func ordered(_ funds: [TrackedFundState]) -> [TrackedFundState] {
        funds.sorted {
            if $0.isPrimary != $1.isPrimary {
                return $0.isPrimary && !$1.isPrimary
            }
            return $0.updatedAt > $1.updatedAt
        }
    }

    static func upsert(
        _ funds: [TrackedFundState],
        code rawCode: String,
        assetKind: AssetKind,
        shares: Double,
        makePrimary: Bool,
        now: Date = .now
    ) throws -> [TrackedFundState] {
        try save(
            funds,
            originalStorageCode: nil,
            code: rawCode,
            assetKind: assetKind,
            shares: shares,
            makePrimary: makePrimary,
            now: now
        )
    }

    static func save(
        _ funds: [TrackedFundState],
        originalStorageCode: String?,
        code rawCode: String,
        assetKind: AssetKind,
        shares: Double,
        makePrimary: Bool,
        now: Date = .now
    ) throws -> [TrackedFundState] {
        let code = AssetIdentity.normalizedDisplayCode(rawCode, kind: assetKind)
        guard AssetIdentity.isValidDisplayCode(code, kind: assetKind) else {
            throw FundStoreError.invalidAssetCode
        }
        guard shares.isFinite, shares >= 0 else {
            throw FundStoreError.invalidShares
        }
        if assetKind == .stock, shares.rounded() != shares {
            throw FundStoreError.fractionalStockShares
        }

        let storageCode = AssetIdentity.storageCode(for: code, kind: assetKind)

        var next = funds
        if let originalStorageCode {
            guard let index = next.firstIndex(where: { $0.storageCode == originalStorageCode }) else {
                throw FundStoreError.fundNotFound
            }
            if storageCode != originalStorageCode,
               next.contains(where: { $0.storageCode == storageCode }) {
                throw FundStoreError.duplicateAsset
            }

            next[index] = TrackedFundState(
                storageCode: storageCode,
                shares: shares,
                isPrimary: next[index].isPrimary,
                updatedAt: now
            )
        } else if let index = next.firstIndex(where: { $0.storageCode == storageCode }) {
            next[index].shares = shares
            next[index].updatedAt = now
        } else {
            guard next.count < FundStoreLimits.maximumTrackedFunds else {
                throw FundStoreError.maximumTrackedFundsReached
            }
            next.append(TrackedFundState(storageCode: storageCode, shares: shares, isPrimary: false, updatedAt: now))
        }

        if makePrimary || next.filter(\.isPrimary).isEmpty {
            next = next.map {
                var fund = $0
                fund.isPrimary = fund.storageCode == storageCode
                return fund
            }
        }

        return ordered(next)
    }

    static func delete(_ funds: [TrackedFundState], storageCode: String) throws -> [TrackedFundState] {
        guard let removing = funds.first(where: { $0.storageCode == storageCode }) else {
            throw FundStoreError.fundNotFound
        }

        var remaining = funds.filter { $0.storageCode != storageCode }
        if removing.isPrimary, !remaining.isEmpty, remaining.allSatisfy({ !$0.isPrimary }) {
            remaining[0].isPrimary = true
        }

        return ordered(remaining)
    }
}
