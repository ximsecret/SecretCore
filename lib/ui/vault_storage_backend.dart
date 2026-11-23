import '../core/models/account_item.dart';
import '../core/storage/vault_storage.dart';

/// 保险箱存储后端抽象：VaultStore 通过它读写加密数据。
/// 生产环境使用 [LocalVaultStorageBackend]（磁盘 + AES-256-GCM），
/// 测试注入内存实现以获得确定性。
abstract class VaultStorageBackend {
  Future<bool> hasExistingVault();
  Future<void> save({
    required List<AccountItem> items,
    required String masterPassword,
  });
  Future<List<AccountItem>> load({required String masterPassword});
}

/// 默认后端：委托给 VaultStorage 落盘加密文件
class LocalVaultStorageBackend implements VaultStorageBackend {
  const LocalVaultStorageBackend();

  @override
  Future<bool> hasExistingVault() => VaultStorage.hasExistingVault();

  @override
  Future<void> save({
    required List<AccountItem> items,
    required String masterPassword,
  }) =>
      VaultStorage.saveVault(items: items, masterPassword: masterPassword);

  @override
  Future<List<AccountItem>> load({required String masterPassword}) =>
      VaultStorage.loadVault(masterPassword: masterPassword);
}
