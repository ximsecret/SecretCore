import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import '../crypto/crypto_engine.dart';
import '../models/account_item.dart';

class VaultStorage {
  static const String defaultVaultFileName = 'vault.scvault';

  /// 获取默认保险箱存储目录
  static Future<Directory> getDefaultStorageDir() async {
    final appSupport = await getApplicationSupportDirectory();
    final vaultDir = Directory('${appSupport.path}/SecretCore');
    if (!await vaultDir.exists()) {
      await vaultDir.create(recursive: true);
    }
    return vaultDir;
  }

  /// 默认保险箱文件完整路径
  static Future<File> getDefaultVaultFile() async {
    final dir = await getDefaultStorageDir();
    return File('${dir.path}/$defaultVaultFileName');
  }

  /// 检查本地是否已存在初始化过的保险箱
  static Future<bool> hasExistingVault() async {
    try {
      final file = await getDefaultVaultFile();
      return await file.exists();
    } catch (_) {
      return false;
    }
  }

  /// 加密并保存所有账号至指定或默认保险箱
  static Future<void> saveVault({
    required List<AccountItem> items,
    required String masterPassword,
    File? customFile,
  }) async {
    final file = customFile ?? await getDefaultVaultFile();

    final payload = {
      'version': '1.0.0',
      'updatedAt': DateTime.now().toIso8601String(),
      'items': items.map((e) => e.toJson()).toList(),
    };

    final jsonString = jsonEncode(payload);
    final encryptedBytes = await CryptoEngine.encryptVault(jsonString, masterPassword);

    await file.writeAsBytes(encryptedBytes, flush: true);
  }

  /// 从指定或默认保险箱解密读取数据
  static Future<List<AccountItem>> loadVault({
    required String masterPassword,
    File? customFile,
  }) async {
    final file = customFile ?? await getDefaultVaultFile();
    if (!await file.exists()) {
      throw FileNotFoundException('保险箱数据文件不存在');
    }

    final encryptedBytes = await file.readAsBytes();
    final jsonString = await CryptoEngine.decryptVault(encryptedBytes, masterPassword);

    final dynamic decoded = jsonDecode(jsonString);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('保险箱数据结构解析失败');
    }

    final itemsRaw = decoded['items'] as List<dynamic>?;
    if (itemsRaw == null) return [];

    return itemsRaw
        .map((e) => AccountItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 导出加密的 .scvault 文件至指定路径（用于跨端 AirDrop / 备份）
  static Future<File> exportVaultFile({
    required List<AccountItem> items,
    required String masterPassword,
    required String destinationPath,
  }) async {
    final destFile = File(destinationPath);
    await saveVault(
      items: items,
      masterPassword: masterPassword,
      customFile: destFile,
    );
    return destFile;
  }

  /// 从导入的 .scvault 文件中读取条目
  static Future<List<AccountItem>> importVaultFile({
    required File importedFile,
    required String masterPassword,
  }) async {
    return await loadVault(
      masterPassword: masterPassword,
      customFile: importedFile,
    );
  }
}

class FileNotFoundException implements Exception {
  final String message;
  FileNotFoundException(this.message);
  @override
  String toString() => message;
}
