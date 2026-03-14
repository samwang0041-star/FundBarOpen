import XCTest
@testable import FundBar

final class FundAPIClientTests: XCTestCase {
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
}
