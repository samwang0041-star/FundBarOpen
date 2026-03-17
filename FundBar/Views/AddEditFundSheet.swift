import SwiftUI

struct AddEditFundSheet: View {
    private enum Field: Hashable {
        case assetKind
        case code
        case shares
    }

    private enum ValidationState: Equatable {
        case idle
        case validating
        case success(String)
        case failure(String)
    }

    let state: FundEditorState
    let onCancel: () -> Void
    let onValidate: (_ code: String, _ assetKind: AssetKind) async throws -> String
    let onSave: (_ originalStorageCode: String?, _ code: String, _ assetKind: AssetKind, _ sharesText: String, _ makePrimary: Bool) async -> Void

    @State private var assetKind: AssetKind
    @State private var code: String
    @State private var sharesText: String
    @State private var makePrimary: Bool
    @State private var validationState: ValidationState = .idle
    @State private var verifiedCode: String?
    @State private var verifiedAssetKind: AssetKind?
    @FocusState private var focusedField: Field?

    init(
        state: FundEditorState,
        onCancel: @escaping () -> Void,
        onValidate: @escaping (_ code: String, _ assetKind: AssetKind) async throws -> String,
        onSave: @escaping (_ originalStorageCode: String?, _ code: String, _ assetKind: AssetKind, _ sharesText: String, _ makePrimary: Bool) async -> Void
    ) {
        self.state = state
        self.onCancel = onCancel
        self.onValidate = onValidate
        self.onSave = onSave
        _assetKind = State(initialValue: state.initialAssetKind)
        _code = State(initialValue: state.initialCode)
        _sharesText = State(initialValue: state.initialShares)
        _makePrimary = State(initialValue: state.initialIsPrimary)
    }

    private var isEditing: Bool {
        state.originalStorageCode != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题栏
            HStack(alignment: .firstTextBaseline) {
                Text(state.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(FundBarTheme.textPrimary)
                Spacer()
                Button("关闭", action: onCancel)
                    .buttonStyle(FundBarButtonStyle(tone: .neutral))
            }

            // 资产类型
            fieldBlock(title: "资产类型", focused: focusedField == .assetKind) {
                Picker("资产类型", selection: $assetKind) {
                    ForEach(AssetKind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .focused($focusedField, equals: .assetKind)
            }

            // 代码输入 + 查询按钮
            fieldBlock(title: "\(assetKind.title)代码", hint: codeHint, focused: focusedField == .code) {
                HStack(spacing: 8) {
                    TextField(codePlaceholder, text: $code)
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .code)
                        .onSubmit {
                            guard !normalizedCode.isEmpty, !isCurrentSelectionVerified else { return }
                            Task { await confirmSelection() }
                        }
                    if validationState == .validating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button {
                            Task { await confirmSelection() }
                        } label: {
                            Text("查询")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(normalizedCode.isEmpty || isCurrentSelectionVerified ? FundBarTheme.textTertiary : FundBarTheme.accent))
                        }
                        .buttonStyle(.plain)
                        .disabled(normalizedCode.isEmpty || isCurrentSelectionVerified)
                    }
                }
            }

            // 验证结果反馈
            validationBanner
                .animation(.easeInOut(duration: 0.2), value: validationState)

            // 持仓份额 + 主显示开关
            HStack(spacing: 10) {
                fieldBlock(title: assetKind.quantityTitle, focused: focusedField == .shares) {
                    TextField("选填，用于计算盈亏", text: $sharesText)
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .shares)
                }

                Toggle(isOn: $makePrimary) {
                    Text("主显示")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(FundBarTheme.textPrimary)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(FundBarTheme.accent)
                .frame(width: 120)
                .padding(.top, 16)
            }

            // 操作按钮
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .buttonStyle(FundBarButtonStyle(tone: .neutral))
                Button(saveButtonTitle) {
                    Task { await handleSave() }
                }
                .buttonStyle(FundBarButtonStyle(tone: .accent))
                .disabled(!canAttemptSave)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .background(FundBarCardBackground(tint: Color.white.opacity(0.82)))
        .onAppear {
            focusedField = isEditing ? .shares : .code
        }
        .onChange(of: code) { _, _ in
            invalidateVerificationIfNeeded()
        }
        .onChange(of: assetKind) { _, _ in
            invalidateVerificationIfNeeded()
        }
    }

    private var codeHint: String {
        switch assetKind {
        case .fund:
            return "例如 001437 / 110011"
        case .stock:
            return "支持 600519，也支持 sh600519 / sz000858"
        }
    }

    private var codePlaceholder: String {
        switch assetKind {
        case .fund:
            return "例如 001437"
        case .stock:
            return "例如 600519 或 sh600519"
        }
    }

    private var normalizedCode: String {
        AssetIdentity.normalizedDisplayCode(code, kind: assetKind)
    }

    private var isInitialSelection: Bool {
        state.originalStorageCode != nil &&
        normalizedCode == state.initialCode &&
        assetKind == state.initialAssetKind
    }

    private var isCurrentSelectionVerified: Bool {
        verifiedCode == normalizedCode && verifiedAssetKind == assetKind
    }

    /// 保存按钮可点击：代码非空且非正在验证
    private var canAttemptSave: Bool {
        !normalizedCode.isEmpty && validationState != .validating
    }

    /// 保存按钮文案：根据状态动态变化
    private var saveButtonTitle: String {
        if isInitialSelection || isCurrentSelectionVerified {
            return "保存"
        }
        return "查询并保存"
    }

    /// 保存逻辑：未验证时自动先验证，验证通过后再保存
    private func handleSave() async {
        if isInitialSelection || isCurrentSelectionVerified {
            await onSave(state.originalStorageCode, normalizedCode, assetKind, sharesText, makePrimary)
            return
        }
        // 未验证 → 自动验证
        validationState = .validating
        do {
            let assetName = try await onValidate(normalizedCode, assetKind)
            verifiedCode = normalizedCode
            verifiedAssetKind = assetKind
            validationState = .success(assetName)
            // 验证通过，自动保存
            await onSave(state.originalStorageCode, normalizedCode, assetKind, sharesText, makePrimary)
        } catch {
            verifiedCode = nil
            verifiedAssetKind = nil
            validationState = .failure(error.localizedDescription)
        }
    }

    /// 验证结果横幅
    @ViewBuilder
    private var validationBanner: some View {
        switch validationState {
        case .idle:
            if isInitialSelection {
                bannerRow(
                    icon: "checkmark.circle",
                    text: "当前资产代码未改动",
                    tone: FundBarTheme.textSecondary,
                    background: Color.white.opacity(0.5)
                )
            } else if normalizedCode.isEmpty {
                bannerRow(
                    icon: "magnifyingglass",
                    text: "输入\(assetKind.title)代码后查询",
                    tone: FundBarTheme.textTertiary,
                    background: Color.white.opacity(0.3)
                )
            } else {
                bannerRow(
                    icon: "magnifyingglass",
                    text: "点击查询或按回车验证代码",
                    tone: FundBarTheme.textSecondary,
                    background: Color.white.opacity(0.4)
                )
            }
        case .validating:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("正在查询 \(normalizedCode) ...")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FundBarTheme.accentDeep)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(FundBarTheme.accent.opacity(0.08))
            )
        case .success(let name):
            bannerRow(
                icon: "checkmark.circle.fill",
                text: name,
                tone: FundBarTheme.negative,
                background: FundBarTheme.negative.opacity(0.08)
            )
        case .failure(let message):
            bannerRow(
                icon: "xmark.circle.fill",
                text: message,
                tone: FundBarTheme.positive,
                background: FundBarTheme.positive.opacity(0.08)
            )
        }
    }

    private func bannerRow(icon: String, text: String, tone: Color, background: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tone)
                .font(.system(size: 13))
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tone)
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(background)
        )
    }

    private func invalidateVerificationIfNeeded() {
        guard !isCurrentSelectionVerified else { return }
        if case .failure = validationState {
            return
        }
        validationState = .idle
    }

    private func confirmSelection() async {
        validationState = .validating
        do {
            let assetName = try await onValidate(normalizedCode, assetKind)
            verifiedCode = normalizedCode
            verifiedAssetKind = assetKind
            validationState = .success(assetName)
        } catch {
            verifiedCode = nil
            verifiedAssetKind = nil
            validationState = .failure(error.localizedDescription)
        }
    }

    private func fieldBlock<Content: View>(title: String, hint: String? = nil, focused: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(FundBarTheme.textSecondary)
                Spacer()
                if let hint {
                    Text(hint)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(FundBarTheme.textSecondary)
                }
            }

            content()
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(FundBarTheme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.64))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(focused ? FundBarTheme.accent.opacity(0.50) : Color.clear, lineWidth: 1.5)
                )
                .animation(.easeInOut(duration: 0.15), value: focused)
        }
    }
}
