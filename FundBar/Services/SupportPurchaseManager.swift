import AppKit
import SwiftUI

struct DonationMethod: Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let qrImageName: String
    let iconName: String
    let brandColor: (red: Double, green: Double, blue: Double)
}

@MainActor
final class SupportPurchaseManager: ObservableObject {

    static let donationMethods: [DonationMethod] = [
        DonationMethod(
            id: "wechat",
            title: "微信打赏",
            subtitle: "扫一扫二维码",
            qrImageName: "wechat_pay_qr",
            iconName: "message.fill",
            brandColor: (0.07, 0.73, 0.37)
        ),
        DonationMethod(
            id: "alipay",
            title: "支付宝打赏",
            subtitle: "扫一扫二维码",
            qrImageName: "alipay_qr",
            iconName: "creditcard.fill",
            brandColor: (0.22, 0.47, 0.96)
        )
    ]

    @Published var activeQRMethod: DonationMethod?

    func showQR(for method: DonationMethod) {
        activeQRMethod = method
    }

    func dismissQR() {
        activeQRMethod = nil
    }

    func qrImage(for method: DonationMethod) -> NSImage? {
        if let url = Bundle.main.url(forResource: method.qrImageName, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return nil
    }
}
