import Foundation

enum DisplayFormatting {
    // MARK: - Cached formatters

    private static let moneyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    private static let quantityFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f
    }()

    private static let integerQuantityFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 0
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = MarketCalendar.timeZone
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static let dateParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = MarketCalendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = MarketCalendar.timeZone
        f.dateFormat = "MM-dd"
        return f
    }()

    // MARK: - Formatting functions

    static func signedPercent(_ value: Double?) -> String {
        guard let value else { return "--" }
        let sign = value > 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", value))%"
    }

    static func money(_ value: Double?, signed: Bool = false) -> String {
        guard let value else { return "--" }
        let formatted = moneyFormatter.string(from: NSNumber(value: abs(value))) ?? String(format: "%.2f", abs(value))
        if signed {
            let sign = value > 0 ? "+" : (value < 0 ? "-" : "")
            return "\(sign)\(formatted)"
        }
        return value < 0 ? "-\(formatted)" : formatted
    }

    static func compactMoney(_ value: Double?) -> String {
        guard let value else { return "--" }
        let sign = value > 0 ? "+" : (value < 0 ? "-" : "")
        let absolute = abs(value)

        if absolute >= 10_000 {
            return "\(sign)\(String(format: "%.2f", absolute / 10_000))万"
        }

        if absolute >= 1_000 {
            return "\(sign)\(String(format: "%.0f", absolute))"
        }

        return "\(sign)\(String(format: "%.2f", absolute))"
    }

    // 状态栏百分比：不带正负号，由箭头图标表示方向
    static func compactStatusBarPercent(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(trimmedNumber(abs(value), maximumFractionDigits: abs(value) >= 10 ? 1 : 2))%"
    }

    static func compactStatusBarMoney(_ value: Double?) -> String {
        guard let value else { return "--" }
        let sign = value > 0 ? "+" : (value < 0 ? "-" : "")
        let absolute = abs(value)

        if absolute >= 10_000 {
            return "\(sign)\(trimmedNumber(absolute / 10_000, maximumFractionDigits: 1))万"
        }

        if absolute >= 100 {
            return "\(sign)\(trimmedNumber(absolute, maximumFractionDigits: 0))"
        }

        if absolute >= 10 {
            return "\(sign)\(trimmedNumber(absolute, maximumFractionDigits: 1))"
        }

        return "\(sign)\(trimmedNumber(absolute, maximumFractionDigits: 2))"
    }

    // 状态栏金额：默认用元，达到 10 万后切万；不带正负号，由颜色表示方向
    static func compactStatusBarAmount(_ value: Double?) -> String {
        guard let value else { return "--" }
        let absolute = abs(value)

        if absolute >= 100_000 {
            return "\(String(format: "%.2f", absolute / 10_000))万"
        }

        return "\(fixedTwoDecimalNumber(absolute))元"
    }

    static func quantity(_ value: Double?) -> String {
        guard let value else { return "--" }
        return quantityFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    static func quantity(_ value: Double?, for assetKind: AssetKind) -> String {
        guard let value else { return "--" }
        let prefersInteger = assetKind == .stock && value.rounded() == value
        let formatter = prefersInteger ? integerQuantityFormatter : quantityFormatter
        let fallback = prefersInteger ? "%.0f" : "%.2f"
        return formatter.string(from: NSNumber(value: value)) ?? String(format: fallback, value)
    }

    static func nav(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.4f", value)
    }

    static func displayValue(_ value: Double?, for assetKind: AssetKind) -> String {
        guard let value else { return "--" }
        switch assetKind {
        case .fund:
            return String(format: "%.4f", value)
        case .stock:
            return String(format: "%.2f", value)
        }
    }

    static func time(_ value: Date?) -> String {
        guard let value else { return "--" }
        return timeFormatter.string(from: value)
    }

    static func statusBarTitle(primaryFund: FundViewData?) -> String {
        guard let primaryFund else {
            return "添加自选项"
        }
        guard primaryFund.displayChangePct != nil else {
            return "\(primaryFund.assetKind.title) \(primaryFund.code) 刷新中"
        }

        let percent = signedPercent(primaryFund.displayChangePct)
        if shouldShowProfitAmount(for: primaryFund) {
            return "\(primaryFund.assetKind.title) \(primaryFund.code) \(percent) \(compactMoney(primaryFund.estimatedProfitAmount))"
        }
        return "\(primaryFund.assetKind.title) \(primaryFund.code) \(percent)"
    }

    static func statusBarVisibleSummary(primaryFund: FundViewData?) -> String {
        guard let primaryFund, primaryFund.displayChangePct != nil else {
            return "--"
        }

        let percent = compactStatusBarPercent(primaryFund.displayChangePct)
        if shouldShowProfitAmount(for: primaryFund) {
            return "\(compactStatusBarAmount(primaryFund.estimatedProfitAmount)) \(percent)"
        }
        return percent
    }

    static func shouldShowProfitAmount(for fund: FundViewData) -> Bool {
        fund.shares > 0 && fund.estimatedProfitAmount != nil
    }

    static func profitTitle(for fund: FundViewData) -> String {
        if let dated = datedProfitLabel(for: fund) {
            return "\(dated)盈亏"
        }
        return "当日盈亏"
    }

    static func totalProfitTitle(primaryFund: FundViewData?) -> String {
        guard let primaryFund, let dated = datedProfitLabel(for: primaryFund) else {
            return "今日总盈亏"
        }
        return "\(dated)总盈亏"
    }

    static func datedProfitLabel(for fund: FundViewData) -> String? {
        guard shouldUseDatedProfitTitle(for: fund),
              let referenceDate = fund.referenceDate,
              let date = dateParser.date(from: referenceDate) else {
            return nil
        }
        return monthDayFormatter.string(from: date)
    }

    private static func shouldUseDatedProfitTitle(for fund: FundViewData) -> Bool {
        switch fund.sourceMode {
        case .official, .estimatedClosed:
            return true
        case .estimated, .preOpenEstimated, .realtime, nil:
            return false
        }
    }

    private static func trimmedNumber(_ value: Double, maximumFractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(maximumFractionDigits)f", value)
    }

    private static func fixedTwoDecimalNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}
