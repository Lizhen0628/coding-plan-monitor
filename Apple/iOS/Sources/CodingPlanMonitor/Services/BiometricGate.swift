import Foundation
import LocalAuthentication

/// 敏感操作前的机主验证（Face ID / Touch ID / 设备密码）。
/// 设备未设置生物识别或密码时不阻塞操作。
enum BiometricGate {
    static func unlock(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return true }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}
