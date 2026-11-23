import Foundation
import Security

/// 读取主 App 写入共享 Keychain 的快速填充镜像（只读）。
/// 镜像结构：[{"title":..., "url":..., "username":..., "password":...}]
enum SharedMirrorReader {

  struct QuickTypeEntry {
    let title: String
    let url: String
    let username: String
    let password: String

    var displayTitle: String {
      let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
      return t.isEmpty ? (url.isEmpty ? username : url) : t
    }
  }

  private static let service = "com.secretcore.quicktype"
  private static let account = "quick_type_mirror_v1"

  /// 读取全部快速填充条目；镜像不存在或解析失败时返回空数组
  static func loadEntries() -> [QuickTypeEntry] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    if let accessGroup = Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String {
      query[kSecAttrAccessGroup as String] = accessGroup
    }

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data,
          let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
      return []
    }

    return array.map { dict in
      QuickTypeEntry(
        title: dict["title"] as? String ?? "",
        url: dict["url"] as? String ?? "",
        username: dict["username"] as? String ?? "",
        password: dict["password"] as? String ?? ""
      )
    }
  }

  /// 按域名 / 标题 / 账号模糊过滤
  static func filter(_ entries: [QuickTypeEntry], query: String) -> [QuickTypeEntry] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !q.isEmpty else { return entries }
    return entries.filter {
      $0.title.lowercased().contains(q) ||
        $0.url.lowercased().contains(q) ||
        $0.username.lowercased().contains(q)
    }
  }
}
