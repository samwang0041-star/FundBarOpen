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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(FundBarTheme.textPrimary)
                    Text("支持维护基金和股票，主显示项会同步更新状态栏。")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(FundBarTheme.textSecondary)
                }
                Spacer()
                Button("关闭", action: onCancel)
                    .buttonStyle(FundBarButtonStyle(tone: .neutral))
            }

            fieldBlock(title: "资产类型", hint: "基金与股票分开存储", focused: focusedField == .assetKind) {
                Picker("资产类型", selection: $assetKind) {
                    ForEach(AssetKind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .focused($focusedField, equals: .assetKind)
            }

            fieldBlock(title: "\(assetKind.title)代码", hint: codeHint, focused: focusedField == .code) {
                TextField(codePlaceholder, text: $code)
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .code)
            }

            validationRow

            fieldBlock(title: assetKind.quantityTitle, hint: assetKind == .fund ? "支持整数或两位小数" : "默认按整数股处理", focused: focusedField == .shares) {
                TextField("输入\(assetKind.quantityTitle)", text: $sharesText)
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .shares)
            }

            Toggle(isOn: $makePrimary) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("设为状态栏主显示项")
                        .font(.system(size: 13, weight: .semibold))
                    Text("状态栏会优先展示这只资产的涨跌幅和盈亏。")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(FundBarTheme.textSecondary)
                }
            }
            .toggleStyle(.switch)
            .tint(FundBarTheme.accent)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(FundBarTheme.chipFill)
            )

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .buttonStyle(FundBarButtonStyle(tone: .neutral))
                Button("保存") {
                    Task {
                        await onSave(state.originalStorageCode, normalizedCode, assetKind, sharesText, makePrimary)
                    }
                }
                .buttonStyle(FundBarButtonStyle(tone: .accent))
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .background(FundBarCardBackground(tint: Color.white.opacity(0.82)))
        .onAppear {
            focusedField = state.originalStorageCode == nil ? .code : .shares
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

    private var canSave: Bool {
        !normalizedCode.isEmpty && (isInitialSelection || isCurrentSelectionVerified) && validationState != .validating
    }

    @ViewBuilder
    private var validationRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                Task { await confirmSelection() }
            } label: {
                if validationState == .validating {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("确认中")
                    }
                } else if isCurrentSelectionVerified {
                    Text("已确认")
                } else {
                    Text("确认代码")
                }
            }
            .buttonStyle(FundBarButtonStyle(tone: isCurrentSelectionVerified ? .neutral : .accent))
            .disabled(normalizedCode.isEmpty || validationState == .validating || isCurrentSelectionVerified)

            Text(validationMessage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(validationTone)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
    }

    private var validationMessage: String {
        switch validationState {
        case .idle:
            if isInitialSelection {
                return "当前代码未改动，可以直接保存。"
            }
            return "选择类型后点击确认，确认通过才可保存。"
        case .validating:
            return "正在验证资产代码..."
        case .success(let name):
            return "已确认：\(name)"
        case .failure(let message):
            return message
        }
    }

    private var validationTone: Color {
        switch validationState {
        case .idle:
            return FundBarTheme.textSecondary
        case .validating:
            return FundBarTheme.accentDeep
        case .success:
            return FundBarTheme.negative
        case .failure:
            return FundBarTheme.positive
        }
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

    private func fieldBlock<Content: View>(title: String, hint: String, focused: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(FundBarTheme.textSecondary)
                Spacer()
                Text(hint)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(FundBarTheme.textSecondary)
            }

            content()
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(FundBarTheme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(FundBarTheme.chipFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(focused ? FundBarTheme.accent.opacity(0.50) : Color.clear, lineWidth: 1.5)
                )
                .animation(.easeInOut(duration: 0.15), value: focused)
        }
    }
}
