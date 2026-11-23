import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/models/account_item.dart';

/// AutoFill 快速填充镜像（M5-1）。
///
/// 主 App 在每次数据持久化后，把「标题 / 网址 / 账号 / 密码」最小集合序列化为
/// JSON，经 MethodChannel 写入 App 与 AutoFill 扩展共享的 Keychain 条目。
/// 扩展只读镜像、不解密保险箱，数据始终仅存本机 Keychain（完全离线）。
///
/// 未实现该通道的平台（Web / 桌面 / 测试）全部静默降级为 no-op。
class QuickTypeMirror {
  QuickTypeMirror._();

  static const MethodChannel _channel = MethodChannel('vault.quicktype');

  /// 将当前条目同步到 AutoFill 共享镜像；失败不影响主流程
  static Future<void> sync(List<AccountItem> items) async {
    if (kIsWeb) return;
    final payload = [
      for (final item in items)
        for (final entry in item.entries)
          if (entry.username.trim().isNotEmpty || entry.password.isNotEmpty)
            {
              'title': item.title,
              'url': item.url,
              'username': entry.username,
              'password': entry.password,
            },
    ];
    try {
      await _channel
          .invokeMethod('updateMirror', {'itemsJson': jsonEncode(payload)});
    } catch (_) {
      // 通道未注册（桌面 / 测试）或 Keychain 写入失败：静默忽略
    }
  }

  /// 清空镜像（删除保险箱或显式关闭 AutoFill 时调用）
  static Future<void> clear() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('clearMirror');
    } catch (_) {}
  }
}
