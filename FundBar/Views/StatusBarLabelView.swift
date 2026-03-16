import SwiftUI

struct StatusBarLabelView: View {
    @ObservedObject var viewModel: MenuBarViewModel

    @State private var isFlashing = false
    @State private var flashTask: Task<Void, Never>?
    @State private var flashTrendOverride: StatusBarTrend?
    @State private var lastObservedSnapshot: StatusBarSnapshot?

    var body: some View {
        Group {
            if let primaryAsset = viewModel.primaryAsset {
                if primaryAsset.displayChangePct != nil {
                    populatedLabel(primaryAsset)
                } else {
                    Text("刷新中")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
            } else {
                Text("添加")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
        }
        .onChange(of: viewModel.statusBarPulseToken) { _, _ in
            handlePulseUpdate()
        }
        .onChange(of: viewModel.primaryAsset?.storageCode) { _, _ in
            syncSnapshot()
        }
        .onAppear {
            syncSnapshot()
        }
        .onDisappear {
            flashTask?.cancel()
        }
    }

    private func populatedLabel(_ primaryAsset: FundViewData) -> some View {
        let displayMode = viewModel.statusBarDisplayMode
        let currentTrend = trend(for: primaryAsset.displayChangePct)
        let arrowTrend = isFlashing ? (flashTrendOverride ?? currentTrend) : currentTrend
        let hasProfitAmount = DisplayFormatting.shouldShowProfitAmount(for: primaryAsset)
        let showAmount = hasProfitAmount && (displayMode == .percentAndAmount || displayMode == .amountOnly)
        let showPercent = displayMode == .percentOnly || displayMode == .percentAndAmount || (displayMode == .amountOnly && !hasProfitAmount)
        let amountText = showAmount ? DisplayFormatting.compactStatusBarAmount(primaryAsset.estimatedProfitAmount) : nil
        let percentText = DisplayFormatting.compactStatusBarPercent(primaryAsset.displayChangePct)
        let sessionText = viewModel.statusBarSessionText

        return HStack(spacing: 4) {
            if let amountText {
                Text(amountText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(currentTrend.color.opacity(isFlashing ? 1.0 : 0.94))
                    .monospacedDigit()
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }

            if showPercent {
                Text(percentText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(currentTrend.color.opacity(isFlashing ? 1.0 : 0.94))
                    .monospacedDigit()
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }

            if displayMode == .hidden {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(currentTrend.color.opacity(0.88))
            } else if let sessionText {
                Text(sessionText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white)
            } else {
                Image(systemName: arrowTrend.symbol)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(arrowTrend.color.opacity(isFlashing ? 1.0 : 0.88))
                    .scaleEffect(isFlashing ? 1.18 : 1.0)
                    .offset(y: isFlashing ? arrowTrend.flashOffset : 0)
                    .frame(width: 10, height: 12, alignment: .center)
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: 20, alignment: .center)
        .padding(.vertical, 0)
        .accessibilityLabel(DisplayFormatting.statusBarTitle(primaryFund: primaryAsset))
    }

    // MARK: - Flash

    private func handlePulseUpdate() {
        guard let primaryAsset = viewModel.primaryAsset else { return }
        let snapshot = StatusBarSnapshot(primaryAsset)
        flashTrendOverride = deltaTrend(from: lastObservedSnapshot, to: snapshot)
        lastObservedSnapshot = snapshot
        triggerFlash()
    }

    private func syncSnapshot() {
        guard let primaryAsset = viewModel.primaryAsset else {
            lastObservedSnapshot = nil
            flashTrendOverride = nil
            return
        }
        lastObservedSnapshot = StatusBarSnapshot(primaryAsset)
        flashTrendOverride = nil
    }

    private func triggerFlash() {
        flashTask?.cancel()

        flashTask = Task {
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.12)) {
                    isFlashing = true
                }
            }

            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.28)) {
                    isFlashing = false
                }
            }
        }
    }

    private func deltaTrend(from previous: StatusBarSnapshot?, to current: StatusBarSnapshot) -> StatusBarTrend? {
        guard let previous, previous.storageCode == current.storageCode else {
            return nil
        }

        let pctDelta = current.changePct - previous.changePct
        if abs(pctDelta) >= 0.005 {
            return pctDelta > 0 ? .up : .down
        }

        let amountDelta = current.profitAmount - previous.profitAmount
        if abs(amountDelta) >= 0.005 {
            return amountDelta > 0 ? .up : .down
        }

        return .neutral
    }

    private func trend(for value: Double?) -> StatusBarTrend {
        guard let value else { return .neutral }
        if value > 0 { return .up }
        if value < 0 { return .down }
        return .neutral
    }
}

private struct StatusBarSnapshot {
    let storageCode: String
    let changePct: Double
    let profitAmount: Double

    init(_ asset: FundViewData) {
        self.storageCode = asset.storageCode
        self.changePct = asset.displayChangePct ?? 0
        self.profitAmount = asset.estimatedProfitAmount ?? 0
    }
}

private enum StatusBarTrend {
    case up
    case down
    case neutral

    var symbol: String {
        switch self {
        case .up:
            return "arrowtriangle.up.fill"
        case .down:
            return "arrowtriangle.down.fill"
        case .neutral:
            return "minus"
        }
    }

    var color: Color {
        switch self {
        case .up:
            return FundBarTheme.positive
        case .down:
            return FundBarTheme.negative
        case .neutral:
            return .secondary
        }
    }

    var flashOffset: CGFloat {
        switch self {
        case .up:
            return -1.2
        case .down:
            return 1.2
        case .neutral:
            return 0
        }
    }
}
