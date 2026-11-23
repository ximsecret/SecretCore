import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/account_item.dart';
import '../core/storage/vault_storage.dart';
import 'vault_storage_backend.dart';

/// Web 预览后端：.scvault 加密字节流以 Base64 存入 SharedPreferences(localStorage)。
/// 与桌面/iOS 文件后端共用同一加密格式，仅用于 Flutter Web 构建（Chrome 预览）。
class WebVaultStorageBackend implements VaultStorageBackend {
  static const String _storageKey = 'secretcore.webvault.v1';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _getPrefs() async =>
      _prefs ??= await SharedPreferences.getInstance();

  @override
  Future<bool> hasExistingVault() async {
    try {
      final prefs = await _getPrefs();
      return prefs.getString(_storageKey) != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> save({
    required List<AccountItem> items,
    required String masterPassword,
  }) async {
    final prefs = await _getPrefs();
    final bytes = await VaultStorage.encryptItems(items, masterPassword);
    await prefs.setString(_storageKey, base64Encode(bytes));
  }

  @override
  Future<List<AccountItem>> load({required String masterPassword}) async {
    final prefs = await _getPrefs();
    final stored = prefs.getString(_storageKey);
    if (stored == null) {
      throw FileNotFoundException('保险箱数据文件不存在');
    }
    final bytes = Uint8List.fromList(base64Decode(stored));
    return VaultStorage.decryptItems(bytes, masterPassword);
  }
}
