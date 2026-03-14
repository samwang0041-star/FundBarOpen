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
            userAgent: "FundBar/1.0 (macOS 14.0+)"
        )
        let request = client.makeRequest(for: URL(string: "https://push2delay.eastmoney.com/api/qt/ulist.np/get")!)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://fund.eastmoney.com/")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept-Language"), "zh-CN,zh;q=0.9,en;q=0.8")
    }
}
