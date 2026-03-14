import Foundation
import Security
import SwiftData

struct AppPersistence {
    let modelContainer: ModelContainer
    let syncMode: PersistenceSyncMode
    let syncStatusMessage: String
    let cloudKitContainerIdentifier: String?

    static func bootstrap(bundle: Bundle = .main) -> AppPersistence {
        let schema = Schema([
            TrackedFund.self,
            FundSnapshot.self,
            FundEstimateObservation.self,
            AppPreference.self
        ])

        guard let entitlements = embeddedEntitlements(for: bundle),
              hasCloudKitCapability(entitlements: entitlements) else {
            return makeLocalPersistence(schema: schema, statusMessage: "CloudKit 未配置，当前使用本地存储。")
        }

        do {
            let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            return AppPersistence(
                modelContainer: container,
                syncMode: .cloudKit,
                syncStatusMessage: "iCloud 已配置，正在检查账户状态。",
                cloudKitContainerIdentifier: cloudKitContainerIdentifier(from: entitlements)
            )
        } catch {
            return makeLocalPersistence(schema: schema, statusMessage: "CloudKit 不可用，已切换为本地存储。")
        }
    }

    static func hasCloudKitCapability(entitlements: [String: Any]) -> Bool {
        let services = entitlements["com.apple.developer.icloud-services"] as? [String] ?? []
        let cloudKitContainers = entitlements["com.apple.developer.icloud-container-identifiers"] as? [String] ?? []
        let ubiquityContainers = entitlements["com.apple.developer.ubiquity-container-identifiers"] as? [String] ?? []
        let hasCloudKitService = services.contains { $0.caseInsensitiveCompare("CloudKit") == .orderedSame }
        return hasCloudKitService && !(cloudKitContainers + ubiquityContainers).isEmpty
    }

    static func cloudKitContainerIdentifier(from entitlements: [String: Any]) -> String? {
        let cloudKitContainers = entitlements["com.apple.developer.icloud-container-identifiers"] as? [String] ?? []
        if let first = cloudKitContainers.first, !first.isEmpty {
            return first
        }

        let ubiquityContainers = entitlements["com.apple.developer.ubiquity-container-identifiers"] as? [String] ?? []
        return ubiquityContainers.first(where: { !$0.isEmpty })
    }

    static func embeddedEntitlements(for bundle: Bundle) -> [String: Any]? {
        guard let executableURL = bundle.executableURL else {
            return nil
        }

        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(executableURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else {
            return nil
        }

        var signingInfo: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &signingInfo) == errSecSuccess,
              let info = signingInfo as? [String: Any],
              let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any] else {
            return nil
        }

        return entitlements
    }

    private static func makeLocalPersistence(schema: Schema, statusMessage: String) -> AppPersistence {
        do {
            let configuration = ModelConfiguration(schema: schema)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            return AppPersistence(
                modelContainer: container,
                syncMode: .localFallback,
                syncStatusMessage: statusMessage,
                cloudKitContainerIdentifier: nil
            )
        } catch {
            fatalError("Unable to create model container: \(error.localizedDescription)")
        }
    }
}
