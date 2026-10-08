import Foundation
import StoreKit

/// 中国大陆合规判定（Guideline 5 - Legal）：
/// OpenAI 未取得 MIIT 生成式 AI 服务许可，设备地区或 App Store 店面为
/// 中国大陆时停用相关供应商。先用设备地区做初始判定，启动后由店面校正。
@MainActor
enum RegionPolicy {
    private static var chinaMainland: Bool = Locale.current.region?.identifier == "CN"

    static var isChinaMainland: Bool {
        chinaMainland
    }

    /// App Store 店面比设备地区更准确；仅在有店面信息时覆盖初始判定
    static func refreshFromStorefront() async {
        if let code = await Storefront.current?.countryCode {
            chinaMainland = (code == "CN")
        }
    }
}
