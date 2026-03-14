import AppKit

enum HapticManager {
    /// 产生通用对齐或选择的震动反馈
    static func generateFeedback(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .generic) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .default)
    }
}
