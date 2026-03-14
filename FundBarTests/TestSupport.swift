import Foundation
import SwiftData
import XCTest
@testable import FundBar

enum TestSupport {
    private static let fixtureDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures", isDirectory: true)

    static func fixtureURL(named name: String, extension ext: String) throws -> URL {
        let sourceURL = fixtureDirectory.appendingPathComponent("\(name).\(ext)")
        if FileManager.default.fileExists(atPath: sourceURL.path) {
            return sourceURL
        }

        let bundle = Bundle(for: FixtureBundleToken.self)
        if let url = bundle.url(forResource: name, withExtension: ext) {
            return url
        }
        guard let url = bundle.urls(forResourcesWithExtension: ext, subdirectory: nil)?
            .first(where: { $0.lastPathComponent == "\(name).\(ext)" }) else {
            throw XCTSkip("Missing fixture: \(name).\(ext)")
        }
        return url
    }

    static func fixtureString(named name: String, extension ext: String) throws -> String {
        try String(contentsOf: fixtureURL(named: name, extension: ext), encoding: .utf8)
    }

    static func fixtureData(named name: String, extension ext: String) throws -> Data {
        try Data(contentsOf: fixtureURL(named: name, extension: ext))
    }

    static func decodeJSON<T: Decodable>(_ type: T.Type, named name: String) throws -> T {
        try JSONDecoder().decode(type, from: fixtureData(named: name, extension: "json"))
    }

    static func makeModelContainer() throws -> ModelContainer {
        let schema = Schema([
            TrackedFund.self,
            FundSnapshot.self,
            AppPreference.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

private final class FixtureBundleToken {}
