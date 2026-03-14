import Foundation

@MainActor
final class RefreshScheduler {
    private let marketCalendar: MarketCalendar
    private var task: Task<Void, Never>?

    init(marketCalendar: MarketCalendar) {
        self.marketCalendar = marketCalendar
    }

    func start(refreshAction: @escaping @Sendable () async -> Void) {
        guard task == nil else {
            return
        }

        task = Task {
            while !Task.isCancelled {
                await refreshAction()
                let delay = marketCalendar.nextRefreshDelay()
                try? await Task.sleep(for: delay)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}
