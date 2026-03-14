import XCTest
@testable import FundBar

final class FundAPIClientTests: XCTestCase {
    private final class URLProtocolStub: URLProtocol {
        nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
        nonisolated(unsafe) static var observedURLs: [URL] = []

        override class func canInit(with request: URLRequest) -> Bool {
            true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            guard let handler = Self.requestHandler else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }

            guard let url = request.url else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }

            Self.observedURLs.append(url)

            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    override func setUp() {
        super.setUp()
        URLProtocolStub.observedURLs = []
        URLProtocolStub.requestHandler = nil
    }

    func testDefaultUserAgentUsesAppIdentity() {
        XCTAssertEqual(FundAPIClient.defaultUserAgent(), "FundBar/1.0 (macOS 14.0+)")
    }

    func testRequestUsesExplicitAppUserAgentWithoutReferer() {
        let client = FundAPIClient(
            session: URLSession(configuration: .ephemeral),
            userAgent: "FundBar/1.0 (macOS 14.0+)"
        )
        let request = client.makeRequest(for: URL(string: "https://example.com")!)

        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "FundBar/1.0 (macOS 14.0+)")
        XCTAssertNil(request.value(forHTTPHeaderField: "Referer"))
    }

    func testDirectEastMoneyRequestAddsBrowserLikeHeaders() {
        let client = FundAPIClient(
            session: URLSession(configuration: .ephemeral),
            userAgent: "FundBar/1.0 (macOS 14.0+)",
            relayBaseURL: nil
        )
        let request = client.makeRequest(for: URL(string: "https://push2delay.eastmoney.com/api/qt/ulist.np/get")!)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://fund.eastmoney.com/")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept-Language"), "zh-CN,zh;q=0.9,en;q=0.8")
    }

    func testFetchQuotesPrefersRelayWhenConfigured() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        URLProtocolStub.requestHandler = { request in
            let response = try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil))
            return (response, Data("cb({\"data\":{\"diff\":[]}})".utf8))
        }

        let client = FundAPIClient(
            session: session,
            userAgent: "FundBar/1.0 (macOS 14.0+)",
            relayBaseURL: URL(string: "http://wangyuzhao.cn")
        )

        _ = try await client.fetchQuotes(secids: ["1.600000", "0.399006"])

        XCTAssertEqual(
            URLProtocolStub.observedURLs.map(\.absoluteString),
            ["http://wangyuzhao.cn/api/eastmoney/quotes?secids=1.600000,0.399006"]
        )
    }

    func testFetchHistoricalSeriesFallsBackToDirectWhenRelayFails() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        URLProtocolStub.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            if url.host == "wangyuzhao.cn" {
                throw URLError(.cannotConnectToHost)
            }

            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (response, Data("cb({\"data\":{\"klines\":[]}})".utf8))
        }

        let client = FundAPIClient(
            session: session,
            userAgent: "FundBar/1.0 (macOS 14.0+)",
            relayBaseURL: URL(string: "http://wangyuzhao.cn")
        )

        _ = try await client.fetchHistoricalSeries(secid: "1.000300", startDate: "2026-01-01", endDate: "2026-03-14")
        let observedURLs = URLProtocolStub.observedURLs.map(\.absoluteString)

        XCTAssertEqual(
            observedURLs.last,
            "https://push2delay.eastmoney.com/api/qt/stock/kline/get?secid=1.000300&fields1=f1,f2,f3&fields2=f51,f52,f53&klt=101&fqt=0&beg=20260101&end=20260314&cb=cb"
        )
        XCTAssertEqual(
            observedURLs.filter { $0 == "http://wangyuzhao.cn/api/eastmoney/historical-series?secid=1.000300&startDate=2026-01-01&endDate=2026-03-14" }.count,
            3
        )
    }
}
