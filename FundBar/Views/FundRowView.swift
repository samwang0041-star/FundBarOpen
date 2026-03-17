import SwiftUI

struct FundRowView: View {
    let asset: FundViewData
    let isManaging: Bool
    let onEdit: () -> Void
    let onMakePrimary: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 第一行：名称 + 标签 | 涨跌幅 + 盈亏
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(asset.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(FundBarTheme.textPrimary)
                            .lineLimit(1)
                        FundBarTag(text: asset.assetKind.title, tone: FundBarTheme.accentDeep)
                        if asset.isPrimary {
                            FundBarTag(text: "主显示", tone: FundBarTheme.accentDeep)
                        }
                        sourceModeTag(asset.sourceMode)
                        if asset.isStale {
                            FundBarTag(text: "过期", tone: FundBarTheme.stale)
                        }
                    }
                    HStack(spacing: 6) {
                        Text(asset.code)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(FundBarTheme.textSecondary)
                        FundBarStatusMessage(
                            text: asset.statusMessage,
                            highlighted: asset.statusMessage.contains("官方净值已发布")
                        )
                        .lineLimit(1)
                    }
                    if let diagnostics = estimateDiagnosticsText {
                        Text(diagnostics)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(FundBarTheme.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(DisplayFormatting.signedPercent(asset.displayChangePct))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(FundBarTheme.trendColor(asset.displayChangePct))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: asset.displayChangePct ?? 0))
                    Text(DisplayFormatting.displayValue(asset.displayValue, for: asset.assetKind))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(FundBarTheme.textPrimary)
                        .monospacedDigit()
                    if asset.shares > 0 {
                        Text(DisplayFormatting.money(asset.estimatedProfitAmount, signed: true))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(FundBarTheme.trendColor(asset.estimatedProfitAmount).opacity(0.86))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: asset.estimatedProfitAmount ?? 0))
                    }
                }
            }

            // 第二行：关键指标 inline
            HStack(spacing: 8) {
                infoPill(title: asset.displayValueTitle, value: DisplayFormatting.displayValue(asset.displayValue, for: asset.assetKind))
                if asset.shares > 0 {
                    infoPill(title: asset.assetKind.quantityTitle, value: DisplayFormatting.quantity(asset.shares, for: asset.assetKind))
                }
                infoPill(title: asset.assetKind.referenceDateTitle, value: asset.referenceDate ?? "--")
            }

            if isManaging {
                HStack {
                    Button("编辑") {
                        HapticManager.generateFeedback()
                        onEdit()
                    }
                    .buttonStyle(FundBarButtonStyle(tone: .neutral))

                    if !asset.isPrimary {
                        Button("设为主显示") {
                            HapticManager.generateFeedback()
                            onMakePrimary()
                        }
                        .buttonStyle(FundBarButtonStyle(tone: .neutral))
                    }

                    Spacer()

                    Button("删除", role: .destructive) {
                        HapticManager.generateFeedback()
                        onDelete()
                    }
                    .buttonStyle(FundBarButtonStyle(tone: .destructive))
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(10)
        .background(FundBarCardBackground(tint: Color.white.opacity(isManaging ? 0.82 : 0.72)))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(isManaging ? FundBarTheme.accent.opacity(0.24) : .clear, lineWidth: 0.8)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7, blendDuration: 0), value: asset) // 数值变动弹性微动效
        .animation(.easeInOut(duration: 0.18), value: isManaging)
        .contextMenu {
            Button("编辑自选项") {
                HapticManager.generateFeedback()
                onEdit()
            }
            if !asset.isPrimary {
                Button("设为主显示") {
                    HapticManager.generateFeedback()
                    onMakePrimary()
                }
            }
            Button("复制资产代码") {
                HapticManager.generateFeedback()
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(asset.code, forType: .string)
            }
            Divider()
            Button("删除自选项", role: .destructive) {
                HapticManager.generateFeedback(.levelChange)
                onDelete()
            }
        }
    }

    @ViewBuilder
    private func sourceModeTag(_ mode: SnapshotSourceMode?) -> some View {
        switch mode {
        case .realtime:
            FundBarTag(text: "实时", tone: FundBarTheme.negative)
        case .estimated:
            FundBarTag(text: "本地估算", tone: FundBarTheme.stale)
        case .preOpenEstimated:
            FundBarTag(text: "盘前估算", tone: FundBarTheme.accent)
        case .estimatedClosed:
            FundBarTag(text: "本地参考", tone: FundBarTheme.textSecondary)
        case .official, nil:
            EmptyView()
        }
    }

    private func infoPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(FundBarTheme.textSecondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(FundBarTheme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.50))
        )
    }

    private var estimateDiagnosticsText: String? {
        guard asset.assetKind == .fund else { return nil }
        switch asset.sourceMode {
        case .estimated, .preOpenEstimated, .estimatedClosed:
            return DisplayFormatting.estimateLearningSummary(for: asset)
                ?? "模型学习中"
        case .official, .realtime, nil:
            return nil
        }
    }
}
