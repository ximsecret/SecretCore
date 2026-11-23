import Flutter
import Security
import UIKit

class SceneDelegate: FlutterSceneDelegate {

  private static let channelName = "vault.keychain"
  private static let keychainService = "com.secretcore.app"
  private static let keychainAccount = "master_password_v1"

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    if let windowScene = scene as? UIWindowScene {
      let controller = windowScene.rootViewController as? FlutterViewController
        ?? window?.rootViewController as? FlutterViewController
      if let controller = controller {
        setupKeychainChannel(controller: controller)
      }
    }
  }

  private func setupKeychainChannel(controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: SceneDelegate.channelName,
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { (call, result) in
      SceneDelegate.handleKeychainCall(call, result: result)
    }
  }

  // MARK: - Keychain 桥接

  private static func handleKeychainCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "hasMasterPassword":
      result(hasMasterPassword())
    case "storeMasterPassword":
      guard let args = call.arguments as? [String: Any],
            let password = args["password"] as? String else {
        result(FlutterError(code: "badArgs", message: "缺少 password 参数", details: nil))
        return
      }
      do {
        result(try storeMasterPassword(password))
      } catch let error as NSError {
        result(FlutterError(code: "keychain", message: error.localizedDescription, details: nil))
      }
    case "readMasterPassword":
      do {
        result(try readMasterPassword())
      } catch let error as NSError {
        let code = (error.domain == NSOSStatusErrorDomain && error.code == errSecUserCanceled)
          ? "authFailed" : "keychain"
        result(FlutterError(code: code, message: error.localizedDescription, details: nil))
      }
    case "deleteMasterPassword":
      result(deleteMasterPassword())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func keychainQuery() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: keychainAccount,
    ]
  }

  private static func hasMasterPassword() -> Bool {
    var query = keychainQuery()
    query[kSecReturnAttributes as String] = false
    let status = SecItemCopyMatching(query as CFDictionary, nil)
    return status == errSecSuccess
  }

  /// 写入主密码：绑定 Face ID / Touch ID 访问控制，仅本设备解锁后可读
  private static func storeMasterPassword(_ password: String) throws -> Bool {
    let access = SecAccessControlCreateWithFlags(
      kCFAllocatorDefault,
      kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
      .biometryCurrentSet,
      nil
    )

    // 先删除旧值，避免 errSecDuplicateItem
    deleteMasterPassword()

    var query = keychainQuery()
    query[kSecValueData as String] = Data(password.utf8)
    query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    if let access = access {
      query[kSecAttrAccessControl as String] = access
    }

    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
    return true
  }

  /// 读取主密码：访问控制自动触发 Face ID / Touch ID
  private static func readMasterPassword() throws -> String? {
    var query = keychainQuery()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
    guard let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  private static func deleteMasterPassword() -> Bool {
    let status = SecItemDelete(keychainQuery() as CFDictionary)
    return status == errSecSuccess
  }
}
