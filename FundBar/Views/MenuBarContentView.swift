import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @EnvironmentObject private var supportPurchaseManager: SupportPurchaseManager
    @EnvironmentObject private var updateChecker: GitHubUpdateChecker

    @State private var isShowingSupportCard = false
    @State private var didCopyAuthorEmail = false
    @State private var supportCardDismissTask: Task<Void, Never>?

    private let panelWidth: CGFloat = 500
    private let authorEmail = "samwang0041@gmail.com"

    /// 滚动区域内容的理想高度（按实际内容计算）
    private var scrollContentHeight: CGFloat {
        var h: CGFloat = 0
        if viewModel.editorState != nil { h += 340 }
        if !viewModel.assets.isEmpty {
            // section header (~36) + section padding (24)
            h += 60
            let rowH: CGFloat = viewModel.isManagingAssets ? 160 : 125
            h += CGFloat(viewModel.assets.count) * rowH
            h += CGFloat(max(0, viewModel.assets.count - 1)) * 10 // row spacing
            if viewModel.isManagingAssets { h += 20 } // managing hint text
        }
        if viewModel.errorMessage != nil { h += 50 }
        if viewModel.pendingDeleteCode != nil { h += 94 }
        return h
    }

    private var panelHeight: CGFloat {
        if isShowingSupportCard {
            // 打赏页面需要足够空间展示二维码
            return 780
        }
        // 固定区域：header(~56) + controls(~76) + outer padding(28) + spacing(~50)
        let fixedHeight: CGFloat = 210
        let primaryHeight: CGFloat = viewModel.primaryAsset != nil ? 190 : 80
        let updateBannerHeight: CGFloat = updateChecker.isUpdateAvailable ? 58 : 0
        let totalProfitHeight: CGFloat = (viewModel.assets.count > 1 && viewModel.totalDailyProfit != nil) ? 42 : 0
        // 滚动区域：内容实际高度，上限 500
        let scrollHeight = min(scrollContentHeight, 500)
        let computed = fixedHeight + primaryHeight + updateBannerHeight + totalProfitHeight + scrollHeight
        return min(max(computed, 400), 860)
    }

    var body: some View {
        ZStack {
            FundBarCanvasBackground()

            VStack(alignment: .leading, spacing: 10) {
                header

                if updateChecker.isUpdateAvailable {
                    updateBanner
                }

                if let primary = viewModel.primaryAsset {
                    primarySummary(primary)
                } else {
                    emptyState
                }

                // 多只资产时显示总盈亏
                if let totalProfit = viewModel.totalDailyProfit, viewModel.assets.count > 1 {
                    totalProfitBar(totalProfit)
                }

                if let state = viewModel.editorState {
                    AddEditFundSheet(
                        state: state,
                        onCancel: { viewModel.dismissEditor() },
                        onValidate: { code, assetKind in
                            try await viewModel.validateAsset(code: code, assetKind: assetKind)
                        },
                        onSave: { originalStorageCode, code, assetKind, shares, makePrimary in
                            await viewModel.saveAsset(
                                originalStorageCode: originalStorageCode,
                                code: code,
                                assetKind: assetKind,
                                sharesText: shares,
                                makePrimary: makePrimary
                            )
                        }
                    )
                    .id(state.id)
                }

                ScrollView(showsIndicators: shouldShowContentScrollIndicator) {
                    VStack(alignment: .leading, spacing: 10) {
                        if !viewModel.assets.isEmpty {
                            fundsSection
                        }

                        if let errorMessage = viewModel.errorMessage, !errorMessage.isEmpty {
                            errorCard(errorMessage)
                        }

                        if let pendingDeleteCode = viewModel.pendingDeleteCode {
                            deleteConfirmationCard(for: pendingDeleteCode)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 1)
                }
                .frame(maxHeight: .infinity, alignment: .top)

                controls
            }
            .padding(14)
            .blur(radius: isShowingSupportCard ? 1.2 : 0)
            .allowsHitTesting(!isShowingSupportCard)

            if isShowingSupportCard {
                supportOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .frame(width: panelWidth, height: panelHeight, alignment: .top)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.assets)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.primaryAsset)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isShowingSupportCard)
    }

    private var shouldShowContentScrollIndicator: Bool {
        viewModel.assets.count > 2 || viewModel.editorState != nil || (viewModel.errorMessage?.isEmpty == false) || viewModel.pendingDeleteCode != nil
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [FundBarTheme.accent, FundBarTheme.accentDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 36, height: 36)
            .shadow(color: FundBarTheme.accent.opacity(0.24), radius: 8, x: 0, y: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text("FundBar")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(FundBarTheme.textPrimary)
                Text("搬砖摸鱼的时候，一眼就知道今天情况。")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FundBarTheme.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    FundBarTag(text: viewModel.marketStateText, tone: marketStateTone)
                    if viewModel.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(FundBarTheme.accent)
                    }
                }

                Text(viewModel.syncStatusMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FundBarTheme.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 128, alignment: .trailing)
            }
        }
        .padding(10)
        .background(FundBarCardBackground(tint: Color.white.opacity(0.82)))
    }

    private var marketStateTone: Color {
        switch viewModel.marketStateText {
        case "开盘中":
            return FundBarTheme.negative
        case "盘前竞价":
            return FundBarTheme.accent
        case "午休":
            return FundBarTheme.stale
        case "海外时差":
            return FundBarTheme.accent
        default:
            return FundBarTheme.accentDeep
        }
    }

    private func primarySummary(_ fund: FundViewData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // 顶部标签行 + 更新时间
            HStack {
                HStack(spacing: 6) {
                    FundBarTag(text: "主显示", tone: FundBarTheme.accentDeep)
                    FundBarTag(text: fund.assetKind.title, tone: FundBarTheme.accentDeep)
                    sourceModeTag(fund.sourceMode)
                    if fund.isStale {
                        FundBarTag(text: "数据过期", tone: FundBarTheme.stale)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("更新于 \(DisplayFormatting.time(fund.updatedAt))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(FundBarTheme.textSecondary)
                    if let refDate = fund.referenceDate {
                        Text("基准 \(refDate)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(FundBarTheme.textSecondary)
                    }
                }
            }

            // 核心数据区：左侧名称 + 右侧涨跌
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(fund.code)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(FundBarTheme.textSecondary)
                    }
                    Text(fund.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(FundBarTheme.textPrimary)
                        .lineLimit(1)
                    statusMessageView(fund.statusMessage)
                    if let diagnostics = estimateDiagnosticsText(for: fund) {
                        Text(diagnostics)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(FundBarTheme.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(DisplayFormatting.signedPercent(fund.displayChangePct))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(trendColor(for: fund.displayChangePct))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: fund.displayChangePct ?? 0))
                    Text(DisplayFormatting.displayValue(fund.displayValue, for: fund.assetKind))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(FundBarTheme.textPrimary)
                        .monospacedDigit()
                    if fund.shares > 0 {
                        Text(DisplayFormatting.money(fund.estimatedProfitAmount, signed: true))
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(trendColor(for: fund.estimatedProfitAmount).opacity(0.88))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: fund.estimatedProfitAmount ?? 0))
                    }
                }
            }

            // 底部指标条：精简为一行关键数据
            HStack(spacing: 8) {
                FundBarMetricChip(title: fund.displayValueTitle, value: DisplayFormatting.displayValue(fund.displayValue, for: fund.assetKind))
                if fund.shares > 0 {
                    FundBarMetricChip(
                        title: DisplayFormatting.profitTitle(for: fund),
                        value: DisplayFormatting.money(fund.estimatedProfitAmount, signed: true),
                        tint: trendColor(for: fund.estimatedProfitAmount)
                    )
                }
                FundBarMetricChip(title: fund.assetKind.quantityTitle, value: DisplayFormatting.quantity(fund.shares, for: fund.assetKind))
            }
        }
        .padding(12)
        .background(FundBarHeroBackground())
    }

    private func totalProfitBar(_ totalProfit: Double) -> some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(FundBarTheme.accent)
                Text(DisplayFormatting.totalProfitTitle(primaryFund: viewModel.primaryAsset))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FundBarTheme.textSecondary)
            }
            Spacer()
            Text(DisplayFormatting.money(totalProfit, signed: true))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(trendColor(for: totalProfit))
                .monospacedDigit()
                .contentTransition(.numericText(value: totalProfit))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(FundBarCardBackground(tint: Color.white.opacity(0.80)))
    }

    private var emptyState: some View {
        Button {
            HapticManager.generateFeedback()
            viewModel.presentAddSheet()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(FundBarTheme.accent)
                    Text("还没有自选资产")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(FundBarTheme.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(FundBarTheme.textTertiary)
                }
                Text("添加最多 5 个基金或股票，挑一只设成主显示后，搬砖摸鱼的时候也能一眼知道今天情况。")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FundBarTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(FundBarCardBackground(tint: Color.white.opacity(0.82)))
        }
        .buttonStyle(.plain)
        .help("点击添加第一只资产")
    }

    private var fundsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("自选资产")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(FundBarTheme.textPrimary)
                    FundBarTag(text: "\(viewModel.assets.count)/\(FundStore.maximumTrackedFunds)", tone: FundBarTheme.accentDeep)
                }
                Spacer()
                Button(viewModel.isManagingAssets ? "完成" : "管理") {
                    HapticManager.generateFeedback()
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
                        viewModel.isManagingAssets.toggle()
                    }
                }
                .buttonStyle(FundBarButtonStyle(tone: viewModel.isManagingAssets ? .accent : .neutral))
            }

            LazyVStack(spacing: 10) {
                ForEach(viewModel.assets) { fund in
                    FundRowView(
                        asset: fund,
                        isManaging: viewModel.isManagingAssets,
                        onEdit: { viewModel.presentEditSheet(for: fund.storageCode) },
                        onMakePrimary: { Task { await viewModel.setPrimary(storageCode: fund.storageCode) } },
                        onDelete: { viewModel.pendingDeleteCode = fund.storageCode }
                    )
                }
            }

            if viewModel.isManagingAssets {
                Text("管理模式已开启：可直接编辑、删除，或切换主显示。")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FundBarTheme.textSecondary)
                    .padding(.top, 2)
            }
        }
        .padding(12)
        .background(FundBarCardBackground(tint: Color.white.opacity(0.78)))
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("添加资产") {
                    HapticManager.generateFeedback()
                    viewModel.presentAddSheet()
                }
                .buttonStyle(FundBarButtonStyle(tone: .accent))
                .disabled(!viewModel.canAddMoreAssets)
                .keyboardShortcut("n", modifiers: .command)

                Button("立即刷新") {
                    HapticManager.generateFeedback()
                    Task { await viewModel.refreshAll(manual: true) }
                }
                .buttonStyle(FundBarButtonStyle(tone: .neutral))
                .disabled(viewModel.isRefreshing)
                .keyboardShortcut("r", modifiers: .command)

                Spacer()

                if let lastRefreshAt = viewModel.lastRefreshAt {
                    Text("上次刷新 \(DisplayFormatting.time(lastRefreshAt))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(FundBarTheme.textSecondary)
                }

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(FundBarButtonStyle(tone: .neutral))
                .help("退出 FundBar")
            }

            HStack(spacing: 10) {
                Toggle(isOn: .init(
                    get: { viewModel.launchAtLoginEnabled },
                    set: { viewModel.setLaunchAtLoginEnabled($0) }
                )) {
                    Text("开机启动")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(FundBarTheme.textSecondary)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(FundBarTheme.accent)

                Spacer()

                if !isShowingSupportCard {
                    Button("支持这个小工具") {
                        HapticManager.generateFeedback()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            isShowingSupportCard = true
                        }
                    }
                    .buttonStyle(FundBarButtonStyle(tone: .neutral))
                }

                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(FundBarTheme.textTertiary)
            }
        }
        .padding(10)
        .background(FundBarCardBackground(tint: Color.white.opacity(0.78)))
    }

    private var supportOverlay: some View {
        ZStack {
            Color.white.opacity(0.96)
                .contentShape(Rectangle())
                .onTapGesture {
                    collapseSupportCard()
                }

            supportCard
                .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var supportCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("支持这个小工具")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(FundBarTheme.textPrimary)
                    Text("如果它帮你减少了切 App 的次数，欢迎支持后续维护。")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(FundBarTheme.textSecondary)
                }

                Spacer(minLength: 0)

                Button("收起") {
                    collapseSupportCard()
                }
                .buttonStyle(FundBarButtonStyle(tone: .neutral))
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ScrollView(showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {
                    supportIllustration

                    supportFeatureSummary

                    VStack(alignment: .leading, spacing: 8) {
                        Text("FundBar 的目标很简单：让你不用拿起手机，也不用切到行情 App，就能在菜单栏看到今天的变化。")
                        Text("如果它已经帮你省下了一点注意力成本，愿意的话，可以请我喝杯咖啡。")
                        Text("这会直接用于继续维护、修 Bug 和迭代更实用的小功能。")
                        Text("当然，不支持也完全不影响使用。")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FundBarTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                    // QR code donation overlay
                    if let activeMethod = supportPurchaseManager.activeQRMethod {
                        donationQRView(for: activeMethod)
                    } else {
                        donationMethodButtons
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "envelope.badge")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(FundBarTheme.accent)
                        Text(authorEmail)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(FundBarTheme.textPrimary)
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                        Button(didCopyAuthorEmail ? "已复制" : "复制邮箱") {
                            HapticManager.generateFeedback()
                            copyAuthorEmail()
                        }
                        .buttonStyle(FundBarButtonStyle(tone: .accent))
                    }

                    Text("打赏完全自愿，不解锁任何功能。")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(FundBarTheme.textTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(red: 0.88, green: 0.92, blue: 0.98), lineWidth: 0.8)
        )
        .shadow(color: FundBarTheme.softShadow.opacity(0.12), radius: 18, x: 0, y: 10)
    }

    private var donationMethodButtons: some View {
        VStack(spacing: 8) {
            ForEach(SupportPurchaseManager.donationMethods) { method in
                Button {
                    HapticManager.generateFeedback()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        supportPurchaseManager.showQR(for: method)
                    }
                } label: {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: method.iconName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(red: method.brandColor.red, green: method.brandColor.green, blue: method.brandColor.blue))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(method.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(FundBarTheme.textPrimary)
                            Text(method.subtitle)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(FundBarTheme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "qrcode")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(FundBarTheme.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(FundBarButtonStyle(tone: .neutral))
            }
        }
    }

    private func donationQRView(for method: DonationMethod) -> some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: method.iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(red: method.brandColor.red, green: method.brandColor.green, blue: method.brandColor.blue))
                    Text(method.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FundBarTheme.textPrimary)
                }
                Spacer()
                Button("返回") {
                    HapticManager.generateFeedback()
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                        supportPurchaseManager.dismissQR()
                    }
                }
                .buttonStyle(FundBarButtonStyle(tone: .neutral))
            }

            if let nsImage = supportPurchaseManager.qrImage(for: method) {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(maxWidth: 240, maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color(red: method.brandColor.red, green: method.brandColor.green, blue: method.brandColor.blue).opacity(0.20), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(FundBarTheme.textTertiary)
                    Text("二维码图片未找到")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(FundBarTheme.textSecondary)
                    Text("请将 \(method.qrImageName).png 放入项目 Resources 目录")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(FundBarTheme.textTertiary)
                }
                .frame(width: 240, height: 240)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.gray.opacity(0.06))
                )
            }

            Text("打开\(method.title.replacingOccurrences(of: "打赏", with: ""))扫一扫，对准上方二维码")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(FundBarTheme.textSecondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(red: method.brandColor.red, green: method.brandColor.green, blue: method.brandColor.blue).opacity(0.12), lineWidth: 0.8)
        )
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private func errorCard(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(FundBarTheme.stale)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(FundBarTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(FundBarCardBackground(tint: Color(red: 1.0, green: 0.97, blue: 0.92)))
    }

    private func deleteConfirmationCard(for storageCode: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(FundBarTheme.positive)

                VStack(alignment: .leading, spacing: 4) {
                    Text("确认删除")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FundBarTheme.textPrimary)
                    Text("确定要删除「\(viewModel.deletePromptTitle(for: storageCode))」吗？删除后需要重新添加。")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(FundBarTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button("取消") {
                    viewModel.pendingDeleteCode = nil
                }
                .buttonStyle(FundBarButtonStyle(tone: .neutral))

                Button("删除", role: .destructive) {
                    viewModel.confirmDelete()
                }
                .buttonStyle(FundBarButtonStyle(tone: .destructive))

                Spacer()
            }
        }
        .padding(14)
        .background(FundBarCardBackground(tint: Color(red: 1.0, green: 0.97, blue: 0.95)))
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

    private func statusMessageView(_ message: String) -> some View {
        FundBarStatusMessage(
            text: message,
            highlighted: message.contains("官方净值已发布")
        )
        .lineLimit(2)
    }

    private func trendColor(for value: Double?) -> Color {
        FundBarTheme.trendColor(value)
    }

    @ViewBuilder
    private var supportIllustration: some View {
        ZStack {
            if let url = Bundle.main.url(forResource: "developer_coding_illustration", withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 172)
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.15, green: 0.20, blue: 0.33),
                                Color(red: 0.09, green: 0.14, blue: 0.24)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(alignment: .bottomLeading) {
                        Image(systemName: "laptopcomputer.and.iphone")
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.84))
                            .padding(16)
                    }
                    .frame(height: 172)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 172)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.20), lineWidth: 0.5)
        )
    }

    private var supportFeatureSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("这个工具现在能做什么")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(FundBarTheme.textSecondary)
            HStack(spacing: 8) {
                supportFeaturePill("状态栏一眼看涨跌")
                supportFeaturePill("基金和 A 股一起看")
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                supportFeaturePill("盘前估算，收盘切官方净值")
                Spacer(minLength: 0)
            }
        }
    }

    private func supportFeaturePill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(FundBarTheme.accentDeep)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(FundBarTheme.accent.opacity(0.10))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(FundBarTheme.accent.opacity(0.14), lineWidth: 0.5)
            )
    }

    private func copyAuthorEmail() {
        supportCardDismissTask?.cancel()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(authorEmail, forType: .string)
        didCopyAuthorEmail = true

        supportCardDismissTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                didCopyAuthorEmail = false
            }
        }
    }

    private func collapseSupportCard() {
        supportCardDismissTask?.cancel()
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            isShowingSupportCard = false
        }
        didCopyAuthorEmail = false
    }

    private func shouldShowLocalEstimateBasis(for fund: FundViewData) -> Bool {
        guard fund.assetKind == .fund else { return false }
        switch fund.sourceMode {
        case .estimated, .preOpenEstimated, .estimatedClosed:
            return true
        case .official, .realtime, nil:
            return false
        }
    }

    private func estimateDiagnosticsText(for fund: FundViewData) -> String? {
        guard shouldShowLocalEstimateBasis(for: fund) else { return nil }
        return DisplayFormatting.estimateLearningSummary(for: fund)
            ?? "模型学习中，先按最近披露持仓自动计算"
    }

    private var updateBanner: some View {
        Button {
            updateChecker.openReleasePage()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(FundBarTheme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text("有新版本可用")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(FundBarTheme.textPrimary)
                    if let release = updateChecker.latestRelease {
                        Text("最新版本 \(release.tagName)，点击前往 GitHub 下载")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(FundBarTheme.textSecondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(FundBarTheme.textTertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                FundBarCardBackground(tint: Color(red: 0.93, green: 0.97, blue: 1.0))
            )
        }
        .buttonStyle(.plain)
    }
}
