import SwiftData
import SwiftUI

@main
struct FundBarApp: App {
    private let persistence: AppPersistence
    private let statusItemController: StatusItemController
    @StateObject private var viewModel: MenuBarViewModel
    @StateObject private var supportPurchaseManager: SupportPurchaseManager
    @StateObject private var updateChecker: GitHubUpdateChecker

    init() {
        let persistence = AppPersistence.bootstrap()
        self.persistence = persistence

        let viewModel = MenuBarViewModel(
            modelContainer: persistence.modelContainer,
            syncMode: persistence.syncMode,
            syncStatusMessage: persistence.syncStatusMessage,
            cloudKitContainerIdentifier: persistence.cloudKitContainerIdentifier
        )
        _viewModel = StateObject(wrappedValue: viewModel)
        let supportPurchaseManager = SupportPurchaseManager()
        _supportPurchaseManager = StateObject(wrappedValue: supportPurchaseManager)
        let updateChecker = GitHubUpdateChecker()
        _updateChecker = StateObject(wrappedValue: updateChecker)
        self.statusItemController = StatusItemController(
            viewModel: viewModel,
            modelContainer: persistence.modelContainer,
            supportPurchaseManager: supportPurchaseManager,
            updateChecker: updateChecker
        )

        NSApp.setActivationPolicy(.accessory)

        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            Task { @MainActor in
                await viewModel.start()
                await updateChecker.checkForUpdatesIfNeeded()
            }
        }
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
