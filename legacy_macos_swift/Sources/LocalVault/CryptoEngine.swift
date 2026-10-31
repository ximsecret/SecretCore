import Foundation
import CryptoKit
import CommonCrypto
import Security
import LocalAuthentication

public enum CryptoError: LocalizedError {
    case invalidMasterPassword
    case keyDerivationFailed
    case encryptionFailed(String)
    case decryptionFailed(String)
    case invalidEnvelope
    case touchIDNotAvailable
    case touchIDFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidMasterPassword:
            return "主密码错误，无法解密保险箱"
        case .keyDerivationFailed:
            return "密钥派生计算失败"
        case .encryptionFailed(let msg):
            return "数据加密失败: \(msg)"
        case .decryptionFailed(let msg):
            return "主密码错误或数据文件已损坏 (\(msg))"
        case .invalidEnvelope:
            return "无效的保险箱加密文件格式"
        case .touchIDNotAvailable:
            return "当前设备不支持或未配置 Touch ID"
        case .touchIDFailed(let msg):
            return "Touch ID 验证未通过: \(msg)"
        }
    }
}

public final class CryptoEngine {
    public static let defaultRounds: UInt32 = 150_000
    public static let saltByteCount: Int = 16
    public static let keyByteCount: Int = 32 // 256 bits for AES-256

    /// 派生加密密钥 (PBKDF2-HMAC-SHA256)
    public static func deriveKey(password: String, salt: Data, rounds: UInt32 = defaultRounds) throws -> SymmetricKey {
        guard let passwordData = password.data(using: .utf8), !passwordData.isEmpty else {
            throw CryptoError.invalidMasterPassword
        }

        var derivedKey = Data(count: keyByteCount)
        let status = derivedKey.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        rounds,
                        derivedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyByteCount
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw CryptoError.keyDerivationFailed
        }

        return SymmetricKey(data: derivedKey)
    }

    /// 生成高强度随机 Salt
    public static func generateRandomSalt(count: Int = saltByteCount) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    /// 加密原始数据 -> EncryptedEnvelope
    public static func encrypt(data: Data, masterPassword: String, rounds: UInt32 = defaultRounds) throws -> EncryptedEnvelope {
        let salt = generateRandomSalt()
        let key = try deriveKey(password: masterPassword, salt: salt, rounds: rounds)

        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            guard let combined = sealedBox.combined else {
                throw CryptoError.encryptionFailed("无法打包 AES-GCM SealedBox")
            }

            return EncryptedEnvelope(
                magic: EncryptedEnvelope.currentMagic,
                version: 1,
                kdf: "PBKDF2-HMAC-SHA256",
                cipher: "AES-256-GCM",
                rounds: rounds,
                saltBase64: salt.base64EncodedString(),
                sealedBoxBase64: combined.base64EncodedString(),
                updatedAt: Date()
            )
        } catch {
            throw CryptoError.encryptionFailed(error.localizedDescription)
        }
    }

    /// 解密 EncryptedEnvelope -> 原始数据
    public static func decrypt(envelope: EncryptedEnvelope, masterPassword: String) throws -> Data {
        guard envelope.magic == EncryptedEnvelope.currentMagic else {
            throw CryptoError.invalidEnvelope
        }

        guard let salt = Data(base64Encoded: envelope.saltBase64),
              let combined = Data(base64Encoded: envelope.sealedBoxBase64) else {
            throw CryptoError.invalidEnvelope
        }

        let key = try deriveKey(password: masterPassword, salt: salt, rounds: envelope.rounds)

        do {
            let sealedBox = try AES.GCM.SealedBox(combined: combined)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            return decryptedData
        } catch {
            throw CryptoError.decryptionFailed("密钥验证不匹配")
        }
    }
}

// MARK: - Keychain & Touch ID 辅助管理器 (兼容本地 Ad-hoc 签名)
public final class KeychainTouchIDHelper {
    private static let serviceName = "com.localvault.macos.biometrics"
    private static let masterPasswordAccount = "vault_master_secret"

    /// 检查设备是否支持 Touch ID 生物识别
    public static func isTouchIDAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// 保存主密码到系统钥匙串（供 Touch ID 通过后读取）
    public static func saveMasterPasswordForBiometrics(password: String) throws {
        guard let data = password.data(using: .utf8) else { return }

        deleteSavedMasterPassword()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: masterPasswordAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CryptoError.touchIDFailed("写入本地钥匙串失败 (状态码: \(status))")
        }
    }

    /// 触发系统 Touch ID 指纹验证并读取主密码
    public static func retrieveMasterPasswordWithBiometrics(prompt: String = "使用 Touch ID 解锁本地密码保险箱") async throws -> String {
        let context = LAContext()
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
            throw CryptoError.touchIDNotAvailable
        }

        let authenticated: Bool = try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: prompt) { success, error in
                if success {
                    continuation.resume(returning: true)
                } else {
                    let msg = error?.localizedDescription ?? "验证已取消"
                    continuation.resume(throwing: CryptoError.touchIDFailed(msg))
                }
            }
        }

        guard authenticated else {
            throw CryptoError.touchIDFailed("未通过 Touch ID 验证")
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: masterPasswordAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess,
           let data = item as? Data,
           let password = String(data: data, encoding: .utf8) {
            return password
        } else {
            throw CryptoError.touchIDFailed("未找到已保存的解锁凭据，请先用主密码登录并重新开启 Touch ID")
        }
    }

    /// 删除已保存的 Touch ID 凭据
    public static func deleteSavedMasterPassword() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: masterPasswordAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// 检查是否已保存凭据
    public static func hasSavedBiometricsCredential() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: masterPasswordAccount,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
}
