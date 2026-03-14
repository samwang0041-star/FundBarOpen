import Foundation

protocol FundAPIClienting: Sendable {
    func fetchPingData(for fundCode: String) async throws -> String
    func fetchDetailHTML(for fundCode: String) async throws -> String
    func fetchHoldings(for fundCode: String) async throws -> String
    func fetchQuotes(secids: [String]) async throws -> String
    func fetchHistoricalClose(secid: String, reportDate: String) async throws -> String
    func fetchHistoricalSeries(secid: String, startDate: String, endDate: String) async throws -> String
}

enum FundAPIError: Error, LocalizedError {
    case requestFailed(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .requestFailed(let statusCode):
            return "接口请求失败，HTTP \(statusCode)。"
        case .invalidResponse:
            return "接口响应无效。"
        }
    }
}

final class FundAPIClient: @unchecked Sendable, FundAPIClienting {
    private let session: URLSession
    private let userAgent: String

    init(session: URLSession? = nil, userAgent: String = FundAPIClient.defaultUserAgent()) {
        self.userAgent = userAgent
        if let session {
            self.session = session
            return
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        self.session = URLSession(configuration: configuration)
    }

    static func defaultUserAgent() -> String {
        "FundBar/1.0 (macOS 14.0+)"
    }

    func fetchPingData(for fundCode: String) async throws -> String {
        try await fetchText(from: "https://fund.eastmoney.com/pingzhongdata/\(fundCode).js")
    }

    func fetchDetailHTML(for fundCode: String) async throws -> String {
        try await fetchText(from: "https://fund.eastmoney.com/\(fundCode).html")
    }

    func fetchHoldings(for fundCode: String) async throws -> String {
        try await fetchText(from: "https://fundf10.eastmoney.com/FundArchivesDatas.aspx?type=jjcc&code=\(fundCode)&topline=10")
    }

    func fetchQuotes(secids: [String]) async throws -> String {
        // 主源：东财
        let joined = secids.joined(separator: ",")
        do {
            return try await fetchText(from: "https://push2.eastmoney.com/api/qt/ulist.np/get?fltt=2&secids=\(joined)&fields=f2,f3,f4,f5,f12,f13,f14,f20&cb=cb")
        } catch {
            // 备用源：新浪 → 腾讯
            let codes = secids.map { secid -> String in
                let parts = secid.split(separator: ".")
                guard parts.count == 2 else { return secid }
                let prefix = parts[0] == "1" ? "sh" : "sz"
                return prefix + parts[1]
            }

            if let result = try? await fetchQuotesFromSina(codes: codes) { return result }
            return try await fetchQuotesFromTencent(codes: codes)
        }
    }

    private func fetchQuotesFromSina(codes: [String]) async throws -> String {
        let joined = codes.joined(separator: ",")
        let raw = try await fetchText(from: "https://hq.sinajs.cn/list=\(joined)",
                                      referer: "http://finance.sina.com.cn")
        let quotes = try FundParsing.parseSinaQuotes(from: raw)
        return reencodeAsEastmoneyJSONP(quotes: quotes)
    }

    private func fetchQuotesFromTencent(codes: [String]) async throws -> String {
        let joined = codes.joined(separator: ",")
        let raw = try await fetchText(from: "https://qt.gtimg.cn/q=\(joined)")
        let quotes = try FundParsing.parseTencentQuotes(from: raw)
        return reencodeAsEastmoneyJSONP(quotes: quotes)
    }

    /// 将 SecurityQuote 字典重新编码为东财 JSONP 格式，保持上游解析代码兼容
    private func reencodeAsEastmoneyJSONP(quotes: [String: SecurityQuote]) -> String {
        let diffs = quotes.values.map { q in
            "{\"f12\":\"\(q.code)\",\"f14\":\"\(q.name)\",\"f2\":\(q.price),\"f3\":\(q.changePct),\"f4\":\(q.change),\"f5\":\(q.volume),\"f20\":\(q.marketCap * 100000000)}"
        }
        return "cb({\"data\":{\"diff\":[\(diffs.joined(separator: ","))]}})"
    }

    func fetchHistoricalClose(secid: String, reportDate: String) async throws -> String {
        try await fetchHistoricalSeries(secid: secid, startDate: reportDate, endDate: reportDate)
    }

    func fetchHistoricalSeries(secid: String, startDate: String, endDate: String) async throws -> String {
        let compactStartDate = startDate.replacingOccurrences(of: "-", with: "")
        let compactEndDate = endDate.replacingOccurrences(of: "-", with: "")
        // 主源：东财
        do {
            let url = "https://push2delay.eastmoney.com/api/qt/stock/kline/get?secid=\(secid)&fields1=f1,f2,f3&fields2=f51,f52,f53&klt=101&fqt=0&beg=\(compactStartDate)&end=\(compactEndDate)&cb=cb"
            return try await fetchText(from: url)
        } catch {
            // 备用源：腾讯日K线
            return try await fetchHistoryFromTencent(secid: secid, startDate: compactStartDate, endDate: compactEndDate)
        }
    }

    private func fetchHistoryFromTencent(secid: String, startDate: String, endDate: String) async throws -> String {
        let parts = secid.split(separator: ".")
        guard parts.count == 2 else { throw FundAPIError.invalidResponse }
        let tencentCode = (parts[0] == "1" ? "sh" : "sz") + parts[1]
        let url = "https://web.ifzq.gtimg.cn/appstock/app/fqkline/get?param=\(tencentCode),day,\(startDate),\(endDate),500,qfq"
        let raw = try await fetchText(from: url)
        let series = try FundParsing.parseTencentHistoricalSeries(from: raw)
        return reencodeAsEastmoneyHistoryJSONP(series: series)
    }

    /// 将历史K线数据重新编码为东财 JSONP 格式
    private func reencodeAsEastmoneyHistoryJSONP(series: [FundParsing.HistoricalPricePoint]) -> String {
        let klines = series.map { "\"\($0.date),\($0.open),\($0.close)\"" }
        return "cb({\"data\":{\"klines\":[\(klines.joined(separator: ","))]}})"
    }

    private func fetchText(from urlString: String, retries: Int = 2, referer: String? = nil) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw FundAPIError.invalidResponse
        }

        var attempt = 0
        while true {
            do {
                let request = makeRequest(for: url, referer: referer)
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw FundAPIError.invalidResponse
                }
                guard 200..<400 ~= httpResponse.statusCode else {
                    throw FundAPIError.requestFailed(httpResponse.statusCode)
                }
                return decode(data: data)
            } catch {
                if attempt >= retries {
                    throw error
                }
                attempt += 1
                try? await Task.sleep(for: .milliseconds(300 * attempt))
            }
        }
    }

    func makeRequest(for url: URL, referer: String? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let referer {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        } else if let host = url.host, host.contains("eastmoney.com") {
            request.setValue("https://fund.eastmoney.com/", forHTTPHeaderField: "Referer")
            request.setValue("text/html,application/json,application/javascript,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        }
        return request
    }

    private func decode(data: Data) -> String {
        if let decoded = String(data: data, encoding: .utf8) {
            return decoded.replacingOccurrences(of: "\u{feff}", with: "")
        }
        if let decoded = String(data: data, encoding: .unicode) {
            return decoded.replacingOccurrences(of: "\u{feff}", with: "")
        }
        return String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\u{feff}", with: "")
    }
}
