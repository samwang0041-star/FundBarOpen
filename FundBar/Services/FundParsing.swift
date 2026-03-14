import Foundation

enum FundParsingError: Error, LocalizedError {
    case missingContent(String)
    case invalidJSON(String)
    case invalidAssetCode

    var errorDescription: String? {
        switch self {
        case .missingContent(let message):
            return message
        case .invalidJSON(let message):
            return message
        case .invalidAssetCode:
            return "代码必须为 6 位数字。"
        }
    }
}

enum FundParsing {
    struct NavPoint: Equatable, Sendable {
        let date: String
        let nav: Double
    }

    struct HistoricalPricePoint: Equatable, Sendable {
        let date: String
        let open: Double
        let close: Double
    }

    static func extractVariableBlock(from raw: String, variableName: String) -> String? {
        let marker = "var \(variableName)"
        guard let start = raw.range(of: marker)?.lowerBound else {
            return nil
        }
        guard let equal = raw[start...].firstIndex(of: "=") else {
            return nil
        }

        var cursor = raw.index(after: equal)
        while cursor < raw.endIndex, raw[cursor].isWhitespace {
            cursor = raw.index(after: cursor)
        }

        guard let end = raw[cursor...].firstIndex(of: ";") else {
            return nil
        }

        return String(raw[cursor..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func inferFundType(from fundName: String) -> String {
        if fundName.contains("混合") { return "混合型" }
        if fundName.contains("股票") { return "股票型" }
        if fundName.contains("债") { return "债券型" }
        if fundName.contains("指数") { return "指数型" }
        if fundName.contains("货币") { return "货币型" }
        return "其他"
    }

    static func inferRiskLevel(fundType: String, stockPosition: Double) -> String {
        if fundType.contains("债") { return "中低风险" }
        if fundType.contains("货币") { return "低风险" }
        if fundType.contains("股票") { return "高风险" }
        if fundType.contains("指数") { return stockPosition >= 80 ? "中高风险" : "中风险" }
        if fundType.contains("混合") { return stockPosition >= 80 ? "中高风险" : "中风险" }
        return stockPosition >= 80 ? "中高风险" : "中风险"
    }

    struct NavTrendResult {
        let latestNav: Double
        let latestDate: String
        /// 前一个交易日的净值，用作涨跌幅计算的基准
        let previousNav: Double
        let previousDate: String
    }

    static func parseNavSeries(from pingData: String, calendar: MarketCalendar) throws -> [NavPoint] {
        guard let block = extractVariableBlock(from: pingData, variableName: "Data_netWorthTrend") else {
            throw FundParsingError.missingContent("缺少净值走势数据。")
        }

        guard let data = block.data(using: .utf8) else {
            throw FundParsingError.invalidJSON("净值走势编码无效。")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        guard let items = json, !items.isEmpty else {
            throw FundParsingError.invalidJSON("净值走势数据不足。")
        }

        let points = items.compactMap { item -> NavPoint? in
            guard let nav = item["y"] as? Double,
                  let timestamp = item["x"] as? Double else {
                return nil
            }
            return NavPoint(date: calendar.formatDate(fromUnixMilliseconds: timestamp), nav: nav)
        }

        guard !points.isEmpty else {
            throw FundParsingError.invalidJSON("净值走势数据格式无效。")
        }

        return points
    }

    static func parseNavTrend(from pingData: String, calendar: MarketCalendar) throws -> NavTrendResult {
        let points = try parseNavSeries(from: pingData, calendar: calendar)
        let latest = points[points.count - 1]
        let previous = points.count >= 2 ? points[points.count - 2] : latest

        return NavTrendResult(
            latestNav: latest.nav,
            latestDate: latest.date,
            previousNav: previous.nav,
            previousDate: previous.date
        )
    }

    /// 兼容旧签名
    static func parseLatestNavPoint(from pingData: String, calendar: MarketCalendar) throws -> (nav: Double, date: String) {
        let trend = try parseNavTrend(from: pingData, calendar: calendar)
        return (trend.latestNav, trend.latestDate)
    }

    static func parseFundMetadata(
        fundCode: String,
        pingData: String,
        detailHTML: String,
        calendar: MarketCalendar,
        holdingsReportDate: String?
    ) throws -> FundMetadata {
        let name = firstMatch(in: pingData, pattern: #"var fS_name\s*=\s*"([^"]+)""#) ?? fundCode
        let fundType = inferFundType(from: name)
        let navTrend = try parseNavTrend(from: pingData, calendar: calendar)

        var stockPosition = 80.0
        if let block = extractVariableBlock(from: pingData, variableName: "Data_fundSharesPositions"),
           let data = block.data(using: .utf8),
           let json = try JSONSerialization.jsonObject(with: data) as? [[Any]],
           let latest = json.last,
           latest.count > 1,
           let positionValue = latest[1] as? Double {
            stockPosition = positionValue
        }

        var managerName = "—"
        if let block = extractVariableBlock(from: pingData, variableName: "Data_currentFundManager"),
           let data = block.data(using: .utf8),
           let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let name = json.first?["name"] as? String {
            managerName = name
        }

        let latestScaleMatch = firstMatchGroups(in: detailHTML, pattern: #"规模<\/a>：([^（<]+)（([^）]+)）"#)
        let latestScale = latestScaleMatch[safe: 0]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "—"
        let scaleDate = latestScaleMatch[safe: 1]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let managerCompany = firstMatch(in: detailHTML, pattern: #"管\s*理\s*人<\/span>：<a [^>]*>([^<]+)<\/a>"#) ?? "—"
        let inceptionDate = firstMatch(in: detailHTML, pattern: #"成\s*立\s*日(?:期)?(?:<\/span>)?：([0-9-]{10})"#) ?? navTrend.latestDate
        let typeRiskMatch = firstMatchGroups(in: detailHTML, pattern: #"类型：<a [^>]*>([^<]+)<\/a>&nbsp;&nbsp;\|&nbsp;&nbsp;([^<]+)"#)
        let detailedType = typeRiskMatch[safe: 0]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? fundType
        let riskLevel = typeRiskMatch[safe: 1]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? inferRiskLevel(fundType: fundType, stockPosition: stockPosition)

        var managementFee = 1.5
        if let feeString = firstMatch(in: pingData, pattern: #"var fund_sourceRate\s*=\s*"([\d.]+)""#),
           let fee = Double(feeString) {
            managementFee = fee
        }

        var custodyFee = 0.25
        if let feeString = firstMatch(in: detailHTML, pattern: #"托管费[^0-9]{0,20}([\d.]+)%"#),
           let fee = Double(feeString) {
            custodyFee = fee
        }

        // 当天官方净值已发布时，Data_netWorthTrend 最后一条是今天的数据，
        // 此时用倒数第二个点（前一交易日）作为 lastNav 基准，确保涨跌幅计算正确。
        let todayStr = calendar.todayString()
        let useLastNav: Double
        let useLastNavDate: String
        if navTrend.latestDate == todayStr {
            useLastNav = navTrend.previousNav
            useLastNavDate = navTrend.previousDate
        } else {
            useLastNav = navTrend.latestNav
            useLastNavDate = navTrend.latestDate
        }

        return FundMetadata(
            fundCode: fundCode,
            name: name,
            fundType: detailedType,
            managerName: managerName,
            managerCompany: managerCompany,
            riskLevel: riskLevel,
            inceptionDate: inceptionDate,
            latestScale: latestScale,
            scaleDate: scaleDate,
            lastNav: useLastNav,
            lastNavDate: useLastNavDate,
            stockPosition: stockPosition,
            managementFee: managementFee,
            custodyFee: custodyFee,
            holdingsReportDate: holdingsReportDate
        )
    }

    static func parseHoldings(from raw: String) throws -> (holdings: [Holding], reportDate: String?) {
        guard let contentRange = raw.range(of: #"content:""#, options: .regularExpression) else {
            throw FundParsingError.missingContent("持仓返回缺少 content 字段。")
        }
        guard let tailRange = raw[contentRange.upperBound...].range(of: #"",arryear:"#) else {
            throw FundParsingError.missingContent("持仓返回缺少 arryear 结尾。")
        }

        let encodedHTML = String(raw[contentRange.upperBound..<tailRange.lowerBound])
            .replacingOccurrences(of: #"\""#, with: #"""#)
            .replacingOccurrences(of: #"\/"#, with: "/")
        let reportDate = firstMatch(in: encodedHTML, pattern: #"截止至：<font class='px12'>(\d{4}-\d{2}-\d{2})<\/font>"#)
            ?? normalizedDate(firstMatchGroups(in: encodedHTML, pattern: #"(\d{4})年(\d{1,2})月(\d{1,2})日"#))

        let rowPattern = #"<tr>([\s\S]*?)<\/tr>"#
        let columnPattern = #"<td[^>]*>([\s\S]*?)<\/td>"#
        let rows = matches(in: encodedHTML, pattern: rowPattern)
        var holdings: [Holding] = []

        for row in rows {
            let columns = matches(in: row, pattern: columnPattern).map(cleanHTMLText)
            guard columns.count >= 8 else {
                continue
            }
            let code = columns[1]
            let name = columns[2]
            let weight = Double(columns[6].replacingOccurrences(of: "%", with: "")) ?? 0
            if code.count == 6, !name.isEmpty, weight > 0 {
                holdings.append(Holding(code: code, name: name, weight: weight))
            }
        }

        return (holdings, reportDate)
    }

    static func parseQuotes(from jsonp: String) throws -> [String: SecurityQuote] {
        let json = stripJSONP(jsonp)
        guard let data = json.data(using: .utf8) else {
            throw FundParsingError.invalidJSON("行情编码无效。")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = object["data"] as? [String: Any],
              let diff = payload["diff"] as? [[String: Any]] else {
            throw FundParsingError.invalidJSON("行情数据格式无效。")
        }

        var quotes: [String: SecurityQuote] = [:]
        for item in diff {
            guard let code = item["f12"] as? String else { continue }
            let quote = SecurityQuote(
                code: code,
                name: item["f14"] as? String ?? code,
                price: doubleValue(item["f2"]),
                changePct: doubleValue(item["f3"]),
                change: doubleValue(item["f4"]),
                volume: doubleValue(item["f5"]),
                marketCap: doubleValue(item["f20"]) / 100000000
            )
            quotes[code] = quote
        }
        return quotes
    }

    static func parseHistoricalClose(from jsonp: String) throws -> Double? {
        try parseHistoricalSeries(from: jsonp).first?.close
    }

    static func parseHistoricalSeries(from jsonp: String) throws -> [HistoricalPricePoint] {
        let json = stripJSONP(jsonp)
        guard let data = json.data(using: .utf8) else {
            throw FundParsingError.invalidJSON("历史收盘价编码无效。")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = object["data"] as? [String: Any],
              let klines = payload["klines"] as? [String] else {
            return []
        }

        return klines.compactMap { line in
            let parts = line.split(separator: ",")
            guard parts.count > 2,
                  let open = Double(parts[1]),
                  let close = Double(parts[2]) else {
                return nil
            }

            return HistoricalPricePoint(
                date: String(parts[0]),
                open: open,
                close: close
            )
        }
    }

    static func stripJSONP(_ raw: String) -> String {
        guard let start = raw.firstIndex(of: "("),
              let end = raw.lastIndex(of: ")"),
              start < end else {
            return raw
        }
        return String(raw[raw.index(after: start)..<end])
    }

    // MARK: - Sina Quote Parsing

    /// 解析新浪行情返回文本 `var hq_str_shXXXXXX="名称,开盘价,昨收,当前价,...";` 为 SecurityQuote 字典
    static func parseSinaQuotes(from raw: String) throws -> [String: SecurityQuote] {
        let lines = raw.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var quotes: [String: SecurityQuote] = [:]

        for line in lines {
            guard !line.isEmpty,
                  let eqIndex = line.firstIndex(of: "=") else { continue }
            let varPart = String(line[line.startIndex..<eqIndex])
            let rawCode = varPart.replacingOccurrences(of: "var hq_str_", with: "")
            let pureCode: String
            if rawCode.hasPrefix("sh") || rawCode.hasPrefix("sz") {
                pureCode = String(rawCode.dropFirst(2))
            } else {
                continue
            }

            let valuePart = String(line[line.index(after: eqIndex)...])
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            guard !valuePart.isEmpty else { continue }

            let fields = valuePart.components(separatedBy: ",")
            // A 股：0=名称 1=开盘价 2=昨收 3=当前价 4=最高 5=最低 8=成交量(股) 9=成交额
            guard fields.count >= 10 else { continue }
            let name = fields[0]
            let price = Double(fields[3]) ?? 0
            let lastClose = Double(fields[2]) ?? 0
            let change = price - lastClose
            let changePct = lastClose > 0 ? (change / lastClose) * 100 : 0
            let volume = Double(fields[8]) ?? 0

            quotes[pureCode] = SecurityQuote(
                code: pureCode,
                name: name,
                price: price,
                changePct: changePct,
                change: change,
                volume: volume,
                marketCap: 0
            )
        }

        guard !quotes.isEmpty else {
            throw FundParsingError.invalidJSON("新浪行情数据为空。")
        }
        return quotes
    }

    // MARK: - Tencent Quote Parsing

    /// 解析腾讯行情返回文本 `v_shXXXXXX="51~名称~代码~当前价~昨收~..."` 为 SecurityQuote 字典
    static func parseTencentQuotes(from raw: String) throws -> [String: SecurityQuote] {
        let lines = raw.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var quotes: [String: SecurityQuote] = [:]

        for line in lines {
            guard !line.isEmpty,
                  let eqIndex = line.firstIndex(of: "=") else { continue }
            let valuePart = String(line[line.index(after: eqIndex)...])
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            guard !valuePart.isEmpty else { continue }

            let fields = valuePart.components(separatedBy: "~")
            // 腾讯：1=名称 2=代码 3=当前价 4=昨收 31=涨跌额 32=涨跌幅 36=成交量(手) 45=总市值
            guard fields.count >= 45 else { continue }
            let code = fields[2]
            let name = fields[1]
            let price = Double(fields[3]) ?? 0
            let lastClose = Double(fields[4]) ?? 0
            let change = Double(fields[31]) ?? (price - lastClose)
            let changePct = Double(fields[32]) ?? (lastClose > 0 ? (change / lastClose) * 100 : 0)
            let volume = Double(fields[36]) ?? 0
            let marketCapRaw = Double(fields[45]) ?? 0

            quotes[code] = SecurityQuote(
                code: code,
                name: name,
                price: price,
                changePct: changePct,
                change: change,
                volume: volume,
                marketCap: marketCapRaw / 100000000
            )
        }

        guard !quotes.isEmpty else {
            throw FundParsingError.invalidJSON("腾讯行情数据为空。")
        }
        return quotes
    }

    // MARK: - Sina Historical K-line Parsing

    /// 解析新浪历史K线JSON: `[{day:"2026-03-13",open:"10.00",close:"10.50",...}]`
    static func parseSinaHistoricalSeries(from raw: String) throws -> [HistoricalPricePoint] {
        let cleaned = raw
            .replacingOccurrences(of: #"(\w+):"#, with: #""$1":"#, options: .regularExpression)
        guard let data = cleaned.data(using: .utf8) else {
            throw FundParsingError.invalidJSON("新浪历史K线编码无效。")
        }

        guard let items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return items.compactMap { item in
            guard let day = item["day"] as? String else { return nil }
            let open = doubleFromAny(item["open"])
            let close = doubleFromAny(item["close"])
            guard open > 0 || close > 0 else { return nil }
            return HistoricalPricePoint(date: day, open: open, close: close)
        }
    }

    // MARK: - Tencent Historical K-line Parsing

    /// 解析腾讯日K线: `{"data":{"shXXXXXX":{"day":[["2026-03-13","10.00","10.50",...]]}}}`
    static func parseTencentHistoricalSeries(from raw: String) throws -> [HistoricalPricePoint] {
        guard let data = raw.data(using: .utf8) else {
            throw FundParsingError.invalidJSON("腾讯历史K线编码无效。")
        }

        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = object["data"] as? [String: Any] else {
            return []
        }

        // 找到第一个股票代码对应的数据
        for (_, value) in dataObj {
            guard let stockObj = value as? [String: Any] else { continue }
            // 尝试 "day" 或 "qfqday" (前复权)
            let klines = (stockObj["day"] as? [[String]]) ?? (stockObj["qfqday"] as? [[String]]) ?? []
            return klines.compactMap { parts in
                guard parts.count >= 3,
                      let open = Double(parts[1]),
                      let close = Double(parts[2]) else {
                    return nil
                }
                return HistoricalPricePoint(date: parts[0], open: open, close: close)
            }
        }

        return []
    }

    private static func doubleFromAny(_ value: Any?) -> Double {
        switch value {
        case let d as Double: return d
        case let i as Int: return Double(i)
        case let s as String: return Double(s) ?? 0
        default: return 0
        }
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        firstMatchGroups(in: text, pattern: pattern).first
    }

    private static func firstMatchGroups(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) else {
            return []
        }
        guard match.numberOfRanges > 1 else { return [] }
        return (1..<match.numberOfRanges).compactMap { index in
            let range = match.range(at: index)
            guard range.location != NSNotFound else { return nil }
            return nsText.substring(with: range)
        }
    }

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }
        let nsText = text as NSString
        return regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let range = match.range(at: 1)
            guard range.location != NSNotFound else { return nil }
            return nsText.substring(with: range)
        }
    }

    private static func cleanHTMLText(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedDate(_ groups: [String]) -> String? {
        guard groups.count == 3 else { return nil }
        return "\(groups[0])-\(groups[1].leftPadded(to: 2))-\(groups[2].leftPadded(to: 2))"
    }

    private static func doubleValue(_ raw: Any?) -> Double {
        switch raw {
        case let number as Double:
            return number
        case let number as Int:
            return Double(number)
        case let string as String:
            if string == "-" { return 0 }
            return Double(string) ?? 0
        default:
            return 0
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

private extension String {
    func leftPadded(to width: Int) -> String {
        guard count < width else { return self }
        return String(repeating: "0", count: width - count) + self
    }
}
