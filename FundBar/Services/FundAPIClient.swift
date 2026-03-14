import Foundation

protocol FundAPIClienting: Sendable {
    func fetchPingData(for fundCode: String) async throws -> String
    func fetchDetailHTML(for fundCode: String) async throws -> String
    func fetchHoldings(for fundCode: String) async throws -> String
    func fetchQuotes(secids: [String]) async throws -> String
    func fetchHistoricalClose(secid: String, reportDate: String) async throws -> String
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
        let joined = secids.joined(separator: ",")
        return try await fetchText(from: "https://push2.eastmoney.com/api/qt/ulist.np/get?fltt=2&secids=\(joined)&fields=f2,f3,f4,f5,f12,f13,f14,f20&cb=cb")
    }

    func fetchHistoricalClose(secid: String, reportDate: String) async throws -> String {
        let compactDate = reportDate.replacingOccurrences(of: "-", with: "")
        let url = "https://push2his.eastmoney.com/api/qt/stock/kline/get?secid=\(secid)&fields1=f1,f2,f3&fields2=f51,f52,f53&klt=101&fqt=0&beg=\(compactDate)&end=\(compactDate)&cb=cb"
        return try await fetchText(from: url)
    }

    private func fetchText(from urlString: String, retries: Int = 2) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw FundAPIError.invalidResponse
        }

        var attempt = 0
        while true {
            do {
                let request = makeRequest(for: url)
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

    func makeRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
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
