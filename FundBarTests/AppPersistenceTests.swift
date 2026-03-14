import XCTest
@testable import FundBar

final class AppPersistenceTests: XCTestCase {
    func testCloudKitCapabilityRequiresServiceAndContainer() {
        XCTAssertTrue(
            AppPersistence.hasCloudKitCapability(
                entitlements: [
                    "com.apple.developer.icloud-services": ["CloudKit"],
                    "com.apple.developer.icloud-container-identifiers": ["iCloud.com.yuriwong.FundBar"]
                ]
            )
        )
    }

    func testCloudKitCapabilityFallsBackWithoutEntitlements() {
        XCTAssertFalse(AppPersistence.hasCloudKitCapability(entitlements: [:]))
        XCTAssertFalse(
            AppPersistence.hasCloudKitCapability(
                entitlements: [
                    "com.apple.developer.icloud-services": ["CloudKit"]
                ]
            )
        )
    }

    func testCloudKitContainerIdentifierPrefersCloudKitContainer() {
        let identifier = AppPersistence.cloudKitContainerIdentifier(
            from: [
                "com.apple.developer.icloud-container-identifiers": ["iCloud.com.yuriwong.FundBar"],
                "com.apple.developer.ubiquity-container-identifiers": ["iCloud.com.yuriwong.Legacy"]
            ]
        )

        XCTAssertEqual(identifier, "iCloud.com.yuriwong.FundBar")
    }
}
