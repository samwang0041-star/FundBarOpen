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
    private enum EastMoneyEndpoint {
        case pingData(fundCode: String)
        case detailHTML(fundCode: String)
        case holdings(fundCode: String)
        case quotes(secids: [String])
        case historicalSeries(secid: String, startDate: String, endDate: String)

        var directURLString: String {
            switch self {
            case .pingData(let fundCode):
                return "https://fund.eastmoney.com/pingzhongdata/\(fundCode).js"
            case .detailHTML(let fundCode):
                return "https://fund.eastmoney.com/\(fundCode).html"
            case .holdings(let fundCode):
                return "https://fundf10.eastmoney.com/FundArchivesDatas.aspx?type=jjcc&code=\(fundCode)&topline=10"
            case .quotes(let secids):
                let joined = secids.joined(separator: ",")
                return "https://push2delay.eastmoney.com/api/qt/ulist.np/get?fltt=2&secids=\(joined)&fields=f2,f3,f4,f5,f12,f13,f14,f20&cb=cb"
            case .historicalSeries(let secid, let startDate, let endDate):
                let compactStartDate = startDate.replacingOccurrences(of: "-", with: "")
                let compactEndDate = endDate.replacingOccurrences(of: "-", with: "")
                return "https://push2delay.eastmoney.com/api/qt/stock/kline/get?secid=\(secid)&fields1=f1,f2,f3&fields2=f51,f52,f53&klt=101&fqt=0&beg=\(compactStartDate)&end=\(compactEndDate)&cb=cb"
            }
        }

        var relayPath: String {
            switch self {
            case .pingData:
                return "/api/eastmoney/pingzhongdata"
            case .detailHTML:
                return "/api/eastmoney/detail"
            case .holdings:
                return "/api/eastmoney/holdings"
            case .quotes:
                return "/api/eastmoney/quotes"
            case .historicalSeries:
                return "/api/eastmoney/historical-series"
            }
        }

        var relayQueryItems: [URLQueryItem] {
            switch self {
            case .pingData(let fundCode), .detailHTML(let fundCode), .holdings(let fundCode):
                return [URLQueryItem(name: "code", value: fundCode)]
            case .quotes(let secids):
                return [URLQueryItem(name: "secids", value: secids.joined(separator: ","))]
            case .historicalSeries(let secid, let startDate, let endDate):
                return [
                    URLQueryItem(name: "secid", value: secid),
                    URLQueryItem(name: "startDate", value: startDate),
                    URLQueryItem(name: "endDate", value: endDate)
                ]
            }
        }
    }

    private let session: URLSession
    private let userAgent: String
    private let relayBaseURL: URL?

    init(
        session: URLSession? = nil,
        userAgent: String = FundAPIClient.defaultUserAgent(),
        relayBaseURL: URL? = FundAPIClient.defaultRelayBaseURL()
    ) {
        self.userAgent = userAgent
        self.relayBaseURL = relayBaseURL
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

    static func defaultRelayBaseURL(bundle: Bundle = .main) -> URL? {
        guard let rawValue = bundle.object(forInfoDictionaryKey: "FundDataRelayBaseURL") as? String,
              !rawValue.isEmpty else {
            return nil
        }
        return URL(string: rawValue)
    }

    func fetchPingData(for fundCode: String) async throws -> String {
        try await fetchText(for: .pingData(fundCode: fundCode))
    }

    func fetchDetailHTML(for fundCode: String) async throws -> String {
        try await fetchText(for: .detailHTML(fundCode: fundCode))
    }

    func fetchHoldings(for fundCode: String) async throws -> String {
        try await fetchText(for: .holdings(fundCode: fundCode))
    }

    func fetchQuotes(secids: [String]) async throws -> String {
        try await fetchText(for: .quotes(secids: secids))
    }

    func fetchHistoricalClose(secid: String, reportDate: String) async throws -> String {
        try await fetchHistoricalSeries(secid: secid, startDate: reportDate, endDate: reportDate)
    }

    func fetchHistoricalSeries(secid: String, startDate: String, endDate: String) async throws -> String {
        try await fetchText(for: .historicalSeries(secid: secid, startDate: startDate, endDate: endDate))
    }

    private func fetchText(for endpoint: EastMoneyEndpoint, retries: Int = 2) async throws -> String {
        if let relayURL = relayURL(for: endpoint) {
            do {
                return try await fetchText(from: relayURL, retries: retries)
            } catch {
                // Fall back to EastMoney directly when relay is unavailable.
            }
        }

        guard let directURL = URL(string: endpoint.directURLString) else {
            throw FundAPIError.invalidResponse
        }
        return try await fetchText(from: directURL, retries: retries)
    }

    private func fetchText(from url: URL, retries: Int = 2) async throws -> String {
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
        if let host = url.host, host.contains("eastmoney.com") {
            request.setValue("https://fund.eastmoney.com/", forHTTPHeaderField: "Referer")
            request.setValue("text/html,application/json,application/javascript,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        }
        return request
    }

    private func relayURL(for endpoint: EastMoneyEndpoint) -> URL? {
        guard let relayBaseURL else { return nil }
        guard var components = URLComponents(url: relayBaseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let relayPath = endpoint.relayPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, relayPath]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        components.queryItems = endpoint.relayQueryItems
        return components.url
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
