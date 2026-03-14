import Foundation
import ServiceManagement

protocol LaunchAtLoginControlling {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

enum LaunchAtLoginError: LocalizedError {
    case operationFailed(String)
    case stateDidNotChange

    var errorDescription: String? {
        switch self {
        case .operationFailed(let description):
            return description
        case .stateDidNotChange:
            return "系统未确认开机启动变更，请在系统设置的登录项里检查权限。"
        }
    }
}

struct SystemLaunchAtLoginController: LaunchAtLoginControlling {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            throw LaunchAtLoginError.operationFailed(error.localizedDescription)
        }

        guard isEnabled == enabled else {
            throw LaunchAtLoginError.stateDidNotChange
        }
    }
}
