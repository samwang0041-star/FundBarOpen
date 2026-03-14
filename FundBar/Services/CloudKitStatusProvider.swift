import CloudKit
import Foundation

enum CloudKitAvailability: Equatable, Sendable {
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine

    var statusMessage: String {
        switch self {
        case .available:
            return "iCloud 同步已启用。"
        case .noAccount:
            return "未登录 iCloud，当前无法同步。"
        case .restricted:
            return "iCloud 被系统限制，当前无法同步。"
        case .temporarilyUnavailable:
            return "iCloud 暂时不可用，稍后会自动重试。"
        case .couldNotDetermine:
            return "iCloud 状态暂时无法确认，稍后会自动重试。"
        }
    }
}

protocol CloudKitStatusProviding: Sendable {
    func availability(containerIdentifier: String?) async -> CloudKitAvailability
}

struct SystemCloudKitStatusProvider: CloudKitStatusProviding {
    func availability(containerIdentifier: String?) async -> CloudKitAvailability {
        let container: CKContainer
        if let containerIdentifier, !containerIdentifier.isEmpty {
            container = CKContainer(identifier: containerIdentifier)
        } else {
            container = CKContainer.default()
        }

        do {
            let status = try await accountStatus(for: container)
            switch status {
            case .available:
                return .available
            case .noAccount:
                return .noAccount
            case .restricted:
                return .restricted
            case .temporarilyUnavailable:
                return .temporarilyUnavailable
            case .couldNotDetermine:
                return .couldNotDetermine
            @unknown default:
                return .couldNotDetermine
            }
        } catch {
            return .couldNotDetermine
        }
    }

    private func accountStatus(for container: CKContainer) async throws -> CKAccountStatus {
        try await withCheckedThrowingContinuation { continuation in
            container.accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: status)
            }
        }
    }
}
