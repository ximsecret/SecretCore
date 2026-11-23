import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secret_core/core/crypto/crypto_engine.dart';
import 'package:secret_core/core/models/account_item.dart';
import 'package:secret_core/ui/app_theme.dart';
import 'package:secret_core/ui/keychain_service.dart';
import 'package:secret_core/ui/lock_screen.dart';
import 'package:secret_core/ui/vault_store.dart';
import 'package:secret_core/ui/vault_storage_backend.dart';

/// 内存存储后端：模拟"已存在/不存在保险箱"与密码校验
class InMemoryVaultBackend extends VaultStorageBackend {
  bool exists = false;
  String? password;
  List<AccountItem> savedItems = [];

  @override
  Future<bool> hasExistingVault() async => exists;

  @override
  Future<void> save({
    required List<AccountItem> items,
    required String masterPassword,
  }) async {
    exists = true;
    password = masterPassword;
    savedItems = List.of(items);
  }

  @override
  Future<List<AccountItem>> load({required String masterPassword}) async {
    if (!exists) {
      throw Exception('保险箱数据文件不存在');
    }
    if (masterPassword != password) {
      throw InvalidMasterPasswordException();
    }
    return List.of(savedItems);
  }
}

class FakeKeychainService extends KeychainService {
  bool _hasPassword = false;
  String? stored;

  @override
  Future<bool> canCheckBiometrics() async => false;

  @override
  Future<bool> hasMasterPassword() async => _hasPassword;

  @override
  Future<bool> storeMasterPassword(String password) async {
    _hasPassword = true;
    stored = password;
    return true;
  }

  @override
  Future<String?> readMasterPassword() async => stored;

  @override
  Future<bool> deleteMasterPassword() async {
    _hasPassword = false;
    stored = null;
    return true;
  }
}

VaultStore _newStore({required InMemoryVaultBackend backend}) {
  final store = VaultStore(
    keychain: FakeKeychainService(),
    backend: backend,
  );
  addTearDown(store.dispose);
  return store;
}

Widget _phaseRouter(VaultStore store) {
  return AnimatedBuilder(
    animation: store,
    builder: (context, _) {
      switch (store.phase) {
        case VaultPhase.unlocked:
          return const Scaffold(body: Text('HOME'));
        case VaultPhase.locked:
        case VaultPhase.needsSetup:
          return LockScreen(store: store, animate: false);
      }
    },
  );
}

void main() {
  test('锁定策略默认不自动锁（对齐 Mac：autoLockMinutes = 0）', () {
    final backend = InMemoryVaultBackend();
    final store = VaultStore(
      keychain: FakeKeychainService(),
      backend: backend,
    );
    addTearDown(store.dispose);
    expect(store.autoLockMinutes, 0);
  });

  group('VaultStore 阶段机', () {
    testWidgets('首次启动进入创建阶段，空表单校验阻止提交', (tester) async {
      final backend = InMemoryVaultBackend();
      final store = _newStore(backend: backend);
      await store.bootstrap();
      expect(store.phase, VaultPhase.needsSetup);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: _phaseRouter(store),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('创建保险箱'));
      await tester.pumpAndSettle();

      expect(store.phase, VaultPhase.needsSetup);
      expect(find.text('主密码至少需要 8 位，建议 12 位以上'), findsOneWidget);
    });

    testWidgets('填写有效主密码后成功创建并解锁（预置演示数据）', (tester) async {
      final backend = InMemoryVaultBackend();
      final store = _newStore(backend: backend);
      await store.bootstrap();

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: _phaseRouter(store),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('setup_password_field')),
        'MyMaster#2026',
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('setup_confirm_field')),
        'MyMaster#2026',
      );
      await tester.pump();
      await tester.tap(find.text('创建保险箱'));
      await tester.pumpAndSettle();

      expect(store.phase, VaultPhase.unlocked);
      expect(backend.exists, isTrue);
      expect(store.items, isNotEmpty, reason: '创建保险箱应预置演示数据');
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('两次密码不一致时阻止创建', (tester) async {
      final backend = InMemoryVaultBackend();
      final store = _newStore(backend: backend);
      await store.bootstrap();

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: _phaseRouter(store),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('setup_password_field')),
        'MyMaster#2026',
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('setup_confirm_field')),
        'DifferentPass1',
      );
      await tester.pump();
      await tester.tap(find.text('创建保险箱'));
      await tester.pumpAndSettle();

      expect(store.phase, VaultPhase.needsSetup);
      expect(backend.exists, isFalse);
      expect(find.text('两次输入的主密码不一致'), findsOneWidget);
    });

    testWidgets('主密码错误展示错误横幅', (tester) async {
      final backend = InMemoryVaultBackend();
      final store = _newStore(backend: backend);
      await store.bootstrap();
      await store.createVault('CorrectHorse1', 'CorrectHorse1');
      store.lockNow();
      expect(store.phase, VaultPhase.locked);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: _phaseRouter(store),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('unlock_password_field')),
        'WrongPassword',
      );
      await tester.pump();
      await tester.tap(find.text('解锁'));
      await tester.pumpAndSettle();

      expect(store.phase, VaultPhase.locked);
      expect(store.lastError, contains('主密码错误'));
    });

    testWidgets('切后台保持解锁且不锁定（对齐 Mac 行为）', (tester) async {
      final backend = InMemoryVaultBackend();
      final store = _newStore(backend: backend);
      await store.bootstrap();
      await store.createVault('CorrectHorse1', 'CorrectHorse1');
      expect(store.phase, VaultPhase.unlocked);

      store.handleAppPaused();

      expect(store.phase, VaultPhase.unlocked,
          reason: '对齐 Mac 版：切后台不自动锁定');
      expect(store.items, isNotEmpty);

      store.handleAppResumed();
      expect(store.phase, VaultPhase.unlocked);
    });

    testWidgets('手动 lockNow 立即清空内存明文', (tester) async {
      final backend = InMemoryVaultBackend();
      final store = _newStore(backend: backend);
      await store.bootstrap();
      await store.createVault('CorrectHorse1', 'CorrectHorse1');

      store.lockNow();

      expect(store.phase, VaultPhase.locked);
      expect(store.items, isEmpty);
      expect(store.selectedItemId, isNull);
      expect(store.cachedCodes2FA, isEmpty);
    });
  });
}
