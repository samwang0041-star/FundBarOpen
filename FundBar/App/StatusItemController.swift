import AppKit
import Combine
import SwiftData
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let viewModel: MenuBarViewModel
    private let modelContainer: ModelContainer
    private let supportPurchaseManager: SupportPurchaseManager
    private let updateChecker: GitHubUpdateChecker
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let popoverHostingController: NSHostingController<AnyView>
    private let labelHostingView: PassthroughHostingView<AnyView>

    private var cancellables: Set<AnyCancellable> = []
    private var layoutRefreshTask: Task<Void, Never>?

    init(viewModel: MenuBarViewModel, modelContainer: ModelContainer, supportPurchaseManager: SupportPurchaseManager, updateChecker: GitHubUpdateChecker) {
        self.viewModel = viewModel
        self.modelContainer = modelContainer
        self.supportPurchaseManager = supportPurchaseManager
        self.updateChecker = updateChecker
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        self.popoverHostingController = NSHostingController(rootView: AnyView(EmptyView()))
        self.labelHostingView = PassthroughHostingView(rootView: AnyView(EmptyView()))
        super.init()

        configureStatusItem()
        configurePopover()
        observeViewModel()
        scheduleLayoutRefresh()
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(sender)
            return
        }

        refreshPopoverContentSize()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.becomeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])
        button.title = ""
        button.image = nil
        button.addSubview(labelHostingView)
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popoverHostingController.rootView = AnyView(
            MenuBarContentView(viewModel: viewModel)
                .environment(\.colorScheme, .light)
                .environmentObject(supportPurchaseManager)
                .environmentObject(updateChecker)
                .modelContainer(modelContainer)
        )
        popover.contentViewController = popoverHostingController
        popover.contentViewController?.view.appearance = NSAppearance(named: .aqua)
    }

    private func observeViewModel() {
        viewModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleLayoutRefresh()
            }
            .store(in: &cancellables)

        updateChecker.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleLayoutRefresh()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.closePopover()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard
                    let self,
                    self.popover.isShown,
                    let popoverWindow = self.popover.contentViewController?.view.window,
                    let resignedWindow = notification.object as? NSWindow,
                    resignedWindow === popoverWindow
                else {
                    return
                }
                self.closePopover()
            }
            .store(in: &cancellables)
    }

    private func scheduleLayoutRefresh() {
        layoutRefreshTask?.cancel()
        layoutRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000)
            guard let self else { return }
            self.refreshStatusLabel()
            self.refreshStatusItemLayout()
            self.refreshPopoverContentSize()
        }
    }

    private func refreshStatusLabel() {
        labelHostingView.rootView = AnyView(StatusBarLabelView(viewModel: viewModel))
    }

    private func refreshStatusItemLayout() {
        guard let button = statusItem.button else { return }

        let fittingSize = labelHostingView.fittingSize
        let width = max(28, ceil(fittingSize.width) + 10)
        statusItem.length = width

        let height = max(18, ceil(fittingSize.height))
        let buttonHeight = button.bounds.height
        let originY = floor((buttonHeight - height) / 2)
        labelHostingView.frame = NSRect(x: 5, y: originY, width: ceil(fittingSize.width), height: height)
        button.toolTip = viewModel.statusBarText
    }

    private func refreshPopoverContentSize() {
        let view = popoverHostingController.view
        view.layoutSubtreeIfNeeded()
        let fittingSize = view.fittingSize
        guard fittingSize.width > 0, fittingSize.height > 0 else { return }
        popover.contentSize = fittingSize
    }

    private func closePopover() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }
}

private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
