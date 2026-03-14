import Foundation

protocol AssetRefreshing: Sendable {
    func refreshAsset(storageCode: String, shares: Double, hasExistingSnapshot: Bool) async throws -> FundRefreshPayload
    func validateAsset(storageCode: String) async throws -> String
}

actor FundEstimatorService: AssetRefreshing {
    private struct IndexCode {
        let secid: String
        let code: String
    }

    private struct CachedMeta {
        let metadata: FundMetadata
        let holdings: [Holding]
        let fetchedAt: Date
    }

    private let apiClient: any FundAPIClienting
    private let marketCalendar: MarketCalendar
    private var metadataCache: [String: CachedMeta] = [:]
    private var reportCloseCache: [String: [String: Double]] = [:]

    private let indexCodes: [String: IndexCode] = [
        "hs300": .init(secid: "1.000300", code: "000300"),
        "zz500": .init(secid: "1.000905", code: "000905"),
        "cyb": .init(secid: "0.399006", code: "399006"),
        "kcb": .init(secid: "1.000688", code: "000688")
    ]

    init(apiClient: any FundAPIClienting = FundAPIClient(), marketCalendar: MarketCalendar = MarketCalendar()) {
        self.apiClient = apiClient
        self.marketCalendar = marketCalendar
    }

    func refreshAsset(storageCode: String, shares: Double, hasExistingSnapshot: Bool = false) async throws -> FundRefreshPayload {
        let assetKind = AssetIdentity.kind(from: storageCode)
        let code = AssetIdentity.displayCode(from: storageCode)

        switch assetKind {
        case .fund:
            return try await refreshFund(storageCode: storageCode, code: code, shares: shares, hasExistingSnapshot: hasExistingSnapshot)
        case .stock:
            return try await refreshStock(storageCode: storageCode, code: code, shares: shares)
        }
    }

    func validateAsset(storageCode: String) async throws -> String {
        let assetKind = AssetIdentity.kind(from: storageCode)
        let code = AssetIdentity.displayCode(from: storageCode)

        switch assetKind {
        case .fund:
            guard code.range(of: #"^\d{6}$"#, options: .regularExpression) != nil else {
                throw FundParsingError.invalidAssetCode
            }
            return try await metadata(for: code).metadata.name
        case .stock:
            guard code.range(of: #"^\d{6}$"#, options: .regularExpression) != nil else {
                throw FundParsingError.invalidAssetCode
            }
            return try await fetchStockQuote(for: code).name
        }
    }

    private func refreshFund(storageCode: String, code: String, shares: Double, hasExistingSnapshot: Bool = false) async throws -> FundRefreshPayload {
        guard code.range(of: #"^\d{6}$"#, options: .regularExpression) != nil else {
            throw FundParsingError.invalidAssetCode
        }

        let cached = try await metadata(for: code)
        if cached.metadata.timingProfile == .qdii {
            return try await refreshQDIIFund(
                storageCode: storageCode,
                code: code,
                metadata: cached.metadata,
                shares: shares
            )
        }

        let quotes = try await fetchQuotes(for: cached.holdings)
        let reportCloses = await fetchReportCloses(holdings: cached.holdings, reportDate: cached.metadata.holdingsReportDate)
        let estimate = calculateEstimate(
            metadata: cached.metadata,
            holdings: cached.holdings,
            quotes: quotes,
            reportCloses: reportCloses
        )

        let phase = marketCalendar.phase()
        let shouldUseLiveEstimate = phase == .open || phase == .lunchBreak
        let shouldUsePreOpenEstimate = phase == .preOpenAuction
        let shouldPreferOfficialSnapshot = !shouldUseLiveEstimate && !shouldUsePreOpenEstimate
        var displayNav = estimate.estimatedNav
        var displayChangePct = estimate.estimatedChangePct
        var referenceValue = cached.metadata.lastNav
        var referenceDate = cached.metadata.lastNavDate
        var sourceMode: SnapshotSourceMode
        var statusMessage: String

        switch phase {
        case .open:
            sourceMode = .estimated
            statusMessage = "本地参考估算"
        case .lunchBreak:
            sourceMode = .estimated
            statusMessage = "午间本地估算"
        case .preOpenAuction:
            sourceMode = .preOpenEstimated
            statusMessage = "本地盘前估算"
        case .preOpenQuiet:
            sourceMode = .estimatedClosed
            statusMessage = "待开盘，展示上一交易日本地估算"
        case .overnight, .holidayClosed:
            sourceMode = .estimatedClosed
            statusMessage = "展示上一交易日本地估算"
        case .postClose:
            sourceMode = .estimatedClosed
            statusMessage = "已收盘，展示今日本地估算"
        }

        if shouldPreferOfficialSnapshot {
            let expectedOfficialDate = marketCalendar.expectedOfficialNavDate()
            let officialTrend = try await fetchOfficialNavTrend(for: code)
            if officialTrend.latestDate == expectedOfficialDate {
                displayNav = officialTrend.latestNav
                referenceValue = officialTrend.previousNav
                referenceDate = officialTrend.latestDate
                displayChangePct = rounded((officialTrend.latestNav / max(officialTrend.previousNav, 0.0001) - 1) * 100, scale: 2)
                sourceMode = .official
                statusMessage = officialFundMessage(for: phase)
            }
        }

        if shouldPreferOfficialSnapshot,
           sourceMode != .official,
           !hasExistingSnapshot,
           cached.metadata.lastNavDate != marketCalendar.expectedOfficialNavDate() {
            statusMessage = fallbackFundMessageWithoutOfficial(for: phase)
        }

        let displayChange = displayNav - referenceValue
        let payload = FundRefreshPayload(
            storageCode: storageCode,
            assetKind: .fund,
            name: cached.metadata.name,
            displayValue: displayNav,
            displayChangePct: displayChangePct,
            estimatedProfitAmount: rounded(displayChange * shares, scale: 2),
            referenceValue: referenceValue,
            referenceDate: referenceDate,
            sourceMode: sourceMode,
            statusMessage: statusMessage,
            updatedAt: .now
        )

        return payload
    }

    private func refreshQDIIFund(
        storageCode: String,
        code: String,
        metadata: FundMetadata,
        shares: Double
    ) async throws -> FundRefreshPayload {
        let navTrend = try await fetchOfficialNavTrend(for: code)
        let displayNav = navTrend.latestNav
        let baselineNav = max(navTrend.previousNav, 0.0001)
        let displayChange = rounded(displayNav - navTrend.previousNav, scale: 4)
        let displayChangePct = rounded((displayNav / baselineNav - 1) * 100, scale: 2)

        return FundRefreshPayload(
            storageCode: storageCode,
            assetKind: .fund,
            name: metadata.name,
            displayValue: displayNav,
            displayChangePct: displayChangePct,
            estimatedProfitAmount: rounded(displayChange * shares, scale: 2),
            referenceValue: navTrend.previousNav,
            referenceDate: navTrend.latestDate,
            sourceMode: .official,
            statusMessage: qdiiFundMessage(latestOfficialDate: navTrend.latestDate),
            updatedAt: .now
        )
    }

    private func refreshStock(storageCode: String, code: String, shares: Double) async throws -> FundRefreshPayload {
        guard code.range(of: #"^\d{6}$"#, options: .regularExpression) != nil else {
            throw FundParsingError.invalidAssetCode
        }

        let quote = try await fetchStockQuote(for: code)
        let phase = marketCalendar.phase()
        let usesRealtimeQuote = phase == .open || phase == .lunchBreak || phase == .preOpenAuction
        let lastClose = max(quote.price - quote.change, 0)
        let referenceDate = usesRealtimeQuote
            ? marketCalendar.todayString()
            : (marketCalendar.expectedOfficialNavDate() ?? marketCalendar.todayString())

        let statusMessage: String
        switch phase {
        case .preOpenAuction:
            statusMessage = "盘前竞价参考"
        case .open:
            statusMessage = "盘中实时行情"
        case .lunchBreak:
            statusMessage = "午间行情参考"
        case .preOpenQuiet:
            statusMessage = "待开盘，展示上一交易日收盘"
        case .overnight, .holidayClosed, .postClose:
            statusMessage = "收盘行情参考"
        }

        return FundRefreshPayload(
            storageCode: storageCode,
            assetKind: .stock,
            name: quote.name,
            displayValue: rounded(quote.price, scale: 3),
            displayChangePct: rounded(quote.changePct, scale: 2),
            estimatedProfitAmount: rounded(quote.change * shares, scale: 2),
            referenceValue: rounded(lastClose, scale: 3),
            referenceDate: referenceDate,
            sourceMode: usesRealtimeQuote ? .realtime : .official,
            statusMessage: statusMessage,
            updatedAt: .now
        )
    }

    func calculateEstimate(
        metadata: FundMetadata,
        holdings: [Holding],
        quotes: [String: SecurityQuote],
        reportCloses: [String: Double]
    ) -> EstimateBreakdown {
        let driftCorrected = holdings.map { holding -> (holding: Holding, effectiveWeight: Double) in
            let quote = quotes[holding.code]
            let reportClose = reportCloses[holding.code]
            let driftFactor: Double
            if let reportClose, let quote, quote.price > 0 {
                driftFactor = quote.price / reportClose
            } else if let quote {
                driftFactor = 1 + quote.changePct / 100
            } else {
                driftFactor = 1
            }
            return (holding, holding.weight * driftFactor)
        }

        let totalEffective = driftCorrected.reduce(0) { $0 + $1.effectiveWeight }
        let originalTotal = holdings.reduce(0) { $0 + $1.weight }
        let normalized = driftCorrected.map { item -> (holding: Holding, adjustedWeight: Double) in
            let adjustedWeight = totalEffective > 0 ? (item.effectiveWeight / totalEffective) * originalTotal : item.holding.weight
            return (item.holding, adjustedWeight)
        }

        var totalKnownWeight = 0.0
        var weightedChange = 0.0
        for item in normalized {
            let quote = quotes[item.holding.code]
            let changePct = quote?.changePct ?? 0
            let weight = item.adjustedWeight / 100
            totalKnownWeight += weight
            weightedChange += weight * changePct / 100
        }

        let stockWeight = metadata.stockPosition / 100
        let unknownWeight = max(0, stockWeight - totalKnownWeight)
        let styleWeights = detectStyleWeights(holdings: holdings, quotes: quotes)
        let proxyChangePct = styleWeights.reduce(0.0) { partialResult, element in
            let indexCode = indexCodes[element.key]?.code ?? ""
            let quote = quotes[indexCode]
            return partialResult + element.value * (quote?.changePct ?? 0)
        }
        weightedChange += unknownWeight * proxyChangePct / 100

        let nonStockWeight = max(0, 1 - stockWeight)
        weightedChange += nonStockWeight * 0.7 * (0.025 / 365) + nonStockWeight * 0.3 * (0.015 / 365)
        weightedChange -= (metadata.managementFee + metadata.custodyFee) / 365 / 100

        let estimatedNav = rounded(metadata.lastNav * (1 + weightedChange), scale: 4)
        let estimatedChange = rounded(estimatedNav - metadata.lastNav, scale: 4)
        let estimatedChangePct = rounded((estimatedNav / metadata.lastNav - 1) * 100, scale: 2)
        let knownCoverage = stockWeight > 0 ? rounded((totalKnownWeight / stockWeight) * 100, scale: 2) : 0

        return EstimateBreakdown(
            estimatedNav: estimatedNav,
            estimatedChange: estimatedChange,
            estimatedChangePct: estimatedChangePct,
            knownCoverage: knownCoverage
        )
    }

    private func metadata(for code: String) async throws -> CachedMeta {
        if let cached = metadataCache[code], cached.fetchedAt.addingTimeInterval(60 * 60 * 6) > .now {
            return cached
        }

        async let pingData = apiClient.fetchPingData(for: code)
        async let detailHTML = apiClient.fetchDetailHTML(for: code)
        async let holdingsRaw = apiClient.fetchHoldings(for: code)

        let holdingsPayload = try FundParsing.parseHoldings(from: try await holdingsRaw)
        let metadata = try FundParsing.parseFundMetadata(
            fundCode: code,
            pingData: try await pingData,
            detailHTML: try await detailHTML,
            calendar: marketCalendar,
            holdingsReportDate: holdingsPayload.reportDate
        )

        let cached = CachedMeta(metadata: metadata, holdings: holdingsPayload.holdings, fetchedAt: .now)
        metadataCache[code] = cached
        return cached
    }

    private func fetchQuotes(for holdings: [Holding]) async throws -> [String: SecurityQuote] {
        let secids = holdings.map(\.code).map(toSecid) + indexCodes.values.map(\.secid)
        let raw = try await apiClient.fetchQuotes(secids: secids)
        return try FundParsing.parseQuotes(from: raw)
    }

    private func fetchStockQuote(for code: String) async throws -> SecurityQuote {
        let raw = try await apiClient.fetchQuotes(secids: [toSecid(code)])
        let quotes = try FundParsing.parseQuotes(from: raw)
        guard let quote = quotes[code], quote.name != "-" else {
            throw FundParsingError.missingContent("未找到对应股票，请检查代码。")
        }
        return quote
    }

    private func fetchReportCloses(holdings: [Holding], reportDate: String?) async -> [String: Double] {
        guard let reportDate else { return [:] }
        if let cached = reportCloseCache[reportDate] {
            return cached
        }

        let apiClient = self.apiClient
        let closes = await withTaskGroup(of: (String, Double?).self) { group -> [String: Double] in
            for holding in holdings {
                let secid = toSecid(holding.code)
                let code = holding.code
                group.addTask {
                    do {
                        let raw = try await apiClient.fetchHistoricalClose(secid: secid, reportDate: reportDate)
                        let close = try FundParsing.parseHistoricalClose(from: raw)
                        return (code, close)
                    } catch {
                        return (code, nil)
                    }
                }
            }

            var result: [String: Double] = [:]
            for await (code, close) in group {
                if let close {
                    result[code] = close
                }
            }
            return result
        }

        reportCloseCache[reportDate] = closes
        return closes
    }

    private func fetchOfficialNavTrend(for code: String) async throws -> FundParsing.NavTrendResult {
        let raw = try await apiClient.fetchPingData(for: code)
        return try FundParsing.parseNavTrend(from: raw, calendar: marketCalendar)
    }

    private func detectStyleWeights(holdings: [Holding], quotes: [String: SecurityQuote]) -> [String: Double] {
        var largeCap = 0.0
        var midCap = 0.0
        var gem = 0.0
        var star = 0.0

        for holding in holdings {
            let marketCap = quotes[holding.code]?.marketCap ?? 0
            if holding.code.hasPrefix("30") {
                gem += holding.weight
            } else if holding.code.hasPrefix("68") {
                star += holding.weight
            } else if marketCap >= 200 {
                largeCap += holding.weight
            } else {
                midCap += holding.weight
            }
        }

        let total = max(largeCap + midCap + gem + star, 1)
        return [
            "hs300": (largeCap + midCap * 0.3) / total,
            "zz500": (midCap * 0.7) / total,
            "cyb": gem / total,
            "kcb": star / total
        ]
    }

    private func toSecid(_ code: String) -> String {
        (code.hasPrefix("6") || code.hasPrefix("5") ? "1" : "0") + "." + code
    }

    private func rounded(_ value: Double, scale: Int) -> Double {
        let divisor = pow(10.0, Double(scale))
        return (value * divisor).rounded() / divisor
    }

    private func officialFundMessage(for phase: MarketPhase) -> String {
        switch phase {
        case .postClose:
            return "官方净值已发布"
        case .preOpenQuiet:
            return "待开盘，展示上一交易日官方净值"
        case .overnight, .holidayClosed:
            return "展示上一交易日官方净值"
        case .open, .lunchBreak, .preOpenAuction:
            return "官方净值已发布"
        }
    }

    private func fallbackFundMessageWithoutOfficial(for phase: MarketPhase) -> String {
        switch phase {
        case .postClose:
            return "官方净值尚未更新，当前展示本地参考估算。"
        case .preOpenQuiet:
            return "待开盘，暂展示上一交易日本地估算。"
        case .overnight, .holidayClosed:
            return "官方净值尚未更新，当前展示上次本地估算。"
        case .open:
            return "本地参考估算"
        case .lunchBreak:
            return "午间本地估算"
        case .preOpenAuction:
            return "本地盘前估算"
        }
    }

    private func qdiiFundMessage(latestOfficialDate: String) -> String {
        let today = marketCalendar.todayString()
        let previousTradingDay = marketCalendar.previousTradingDayString()

        if latestOfficialDate == today || latestOfficialDate == previousTradingDay {
            return "QDII 官方净值已发布"
        }

        return "QDII 净值更新通常滞后，当前展示最近已发布净值"
    }
}
