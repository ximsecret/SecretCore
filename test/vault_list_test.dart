import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secret_core/core/crypto/crypto_engine.dart';
import 'package:secret_core/core/models/account_category.dart';
import 'package:secret_core/core/models/account_item.dart';
import 'package:secret_core/core/models/credential_entry.dart';
import 'package:secret_core/core/models/labeled_password.dart';
import 'package:secret_core/core/models/note_entry.dart';
import 'package:secret_core/core/models/notes_layout_mode.dart';
import 'package:secret_core/ui/app_theme.dart';
import 'package:secret_core/ui/home_shell.dart';
import 'package:secret_core/ui/item_detail_view.dart';
import 'package:secret_core/ui/keychain_service.dart';
import 'package:secret_core/ui/sidebar_filter.dart';
import 'package:secret_core/ui/status_toast.dart';
import 'package:secret_core/ui/vault_store.dart';
import 'package:secret_core/ui/vault_storage_backend.dart';

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
  @override
  Future<bool> canCheckBiometrics() async => false;
}

AccountItem _simpleItem({
  required String title,
  AccountCategory category = AccountCategory.general,
  bool favorite = false,
  String username = 'user@demo.io',
  String password = 'Pass#12345',
  String url = '',
  String tag = '',
}) {
  return AccountItem(
    title: title,
    url: url,
    category: category,
    customTag: tag,
    isFavorite: favorite,
    entries: [CredentialEntry(username: username, password: password)],
  );
}

/// 预置后端数据并直接解锁（绕过 createVault 的演示种子），泵出主界面
Future<VaultStore> _pumpUnlockedHome(
  WidgetTester tester,
  List<AccountItem> items,
) async {
  final backend = InMemoryVaultBackend();
  backend.exists = true;
  backend.password = 'CorrectHorse1';
  backend.savedItems = List.of(items);

  final store = VaultStore(
    keychain: FakeKeychainService(),
    backend: backend,
  );
  addTearDown(store.dispose);

  await store.bootstrap();
  final ok = await store.unlockWithPassword('CorrectHorse1');
  expect(ok, isTrue);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      // 与生产入口一致：全局 Toast 层挂载于 MaterialApp.builder
      builder: (context, child) => Stack(
        children: [
          if (child != null) child,
          Positioned.fill(child: StatusToastLayer(store: store)),
        ],
      ),
      home: HomeShell(store: store),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

void main() {
  group('VaultStore 筛选与统计（对齐 Mac filteredItems / countFor）', () {
    test('全部/收藏/含2FA/分类/标签 五种筛选器', () async {
      final backend = InMemoryVaultBackend();
      final store = VaultStore(
        keychain: FakeKeychainService(),
        backend: backend,
      );
      addTearDown(store.dispose);
      await store.bootstrap();
      await store.createVault('CorrectHorse1', 'CorrectHorse1');
      // createVault 自带 3 条演示数据，再补 1 条无 2FA 的常规项
      final plain = _simpleItem(title: 'Plain');
      await store.addItems([plain]);

      expect(store.countFor(SidebarFilter.all), 4);
      expect(store.countFor(SidebarFilter.favorites), 2);
      expect(store.countFor(SidebarFilter.has2FA), 2);
      expect(store.countFor(SidebarFilter.forCategory(AccountCategory.crypto)), 1);

      store.setFilter(SidebarFilter.favorites);
      expect(store.filteredItems.every((e) => e.isFavorite), isTrue);
      expect(store.selectedItemId, store.filteredItems.first.id);

      store.setFilter(SidebarFilter.has2FA);
      expect(store.filteredItems.every((e) => e.hasTOTP), isTrue);

      store.setFilter(SidebarFilter.all);
      expect(store.filteredItems.length, 4);

      expect(store.allCustomTags, containsAll(<String>['交易所', '代码库', '大模型']));
    });

    test('全局搜索覆盖标题/账号/网址/备注/自定义字段', () async {
      final backend = InMemoryVaultBackend();
      final store = VaultStore(
        keychain: FakeKeychainService(),
        backend: backend,
      );
      addTearDown(store.dispose);
      await store.bootstrap();
      await store.createVault('CorrectHorse1', 'CorrectHorse1');
      await store.addItems([
        AccountItem(
          title: 'OpsPanel',
          url: 'https://ops.internal.io',
          customFields: {'恢复邮箱': 'recover@demo.io'},
          noteEntries: [NoteEntry(label: '密保', content: '青色配备')],
          entries: [CredentialEntry(username: 'oncall@demo.io', password: 'Op#999')],
        ),
      ]);

      for (final keyword in ['opspanel', 'ops.internal', 'oncall', '青色配备']) {
        store.setSearchQuery(keyword);
        expect(
          store.filteredItems.any((e) => e.title == 'OpsPanel'),
          isTrue,
          reason: '关键词「$keyword」应命中 OpsPanel',
        );
      }
      store.setSearchQuery('zzz');
      expect(store.filteredItems, isEmpty);
    });

    test('删除后选中态回退到过滤列表首项', () async {
      final backend = InMemoryVaultBackend();
      final store = VaultStore(
        keychain: FakeKeychainService(),
        backend: backend,
      );
      addTearDown(store.dispose);
      await store.bootstrap();
      await store.createVault('CorrectHorse1', 'CorrectHorse1');
      final a = _simpleItem(title: 'AAA');
      final b = _simpleItem(title: 'BBB');
      await store.addItems([a, b]);

      store.selectItem(b.id);
      await store.deleteItem(b.id);

      expect(store.items.any((e) => e.id == b.id), isFalse);
      expect(store.selectedItemId, isNot(equals(b.id)));
      expect(store.selectedItem, isNotNull);
    });

    test('粘贴即存：同域名归并既有条目，不同域名新建', () async {
      final backend = InMemoryVaultBackend();
      final store = VaultStore(
        keychain: FakeKeychainService(),
        backend: backend,
      );
      addTearDown(store.dispose);
      await store.bootstrap();
      await store.createVault('CorrectHorse1', 'CorrectHorse1');
      final before = store.items.length;

      // 同域名（github.com）→ 归并到演示条目「GitHub (示例开发仓库)」
      final merged = store.smartAddFromClipboard(
        clipText: 'github.com merger@demo.io MergePass1',
      );
      expect(merged, isTrue);
      expect(store.items.length, before, reason: '同域名不应新建条目');
      final github = store.items
          .singleWhere((e) => e.title.startsWith('GitHub'));
      expect(github.entries.length, 2);
      expect(
        github.entries.any((e) => e.username == 'merger@demo.io'),
        isTrue,
      );

      // 新域名（gitlab.com）→ 新建 GitLab 条目
      final created = store.smartAddFromClipboard(
        clipText: 'gitlab.com labber@demo.io LabPass2',
      );
      expect(created, isTrue);
      expect(store.items.length, before + 1);
      final gitlab = store.items.first;
      expect(gitlab.title, 'GitLab');
      expect(gitlab.category, AccountCategory.work);
    });
  });

  group('主列表', () {
    testWidgets('渲染条目、分类分区头与数量徽章', (tester) async {
      await _pumpUnlockedHome(tester, [
        _simpleItem(title: 'Binance', category: AccountCategory.crypto),
        _simpleItem(title: 'GitHub', category: AccountCategory.work),
      ]);

      expect(find.text('Binance'), findsOneWidget);
      expect(find.text('GitHub'), findsOneWidget);
      // 分组头：分区计数徽章
      expect(find.text('1 项'), findsNWidgets(2));
      // 快捷胶囊 chip / 分组分区头 / 抽屉侧栏按钮共用同一标题，共 3 处
      expect(find.text('加密与交易'), findsNWidgets(3));
    });

    testWidgets('点击分类胶囊过滤列表', (tester) async {
      await _pumpUnlockedHome(tester, [
        _simpleItem(title: 'Binance', category: AccountCategory.crypto),
        _simpleItem(title: 'GitHub', category: AccountCategory.work),
      ]);

      await tester.tap(find.text('开发与工作').first);
      await tester.pumpAndSettle();

      expect(find.text('GitHub'), findsOneWidget);
      expect(find.text('Binance'), findsNothing);
      expect(find.text('1 项'), findsOneWidget);
    });

    testWidgets('收藏胶囊仅显示星标项，长按菜单可设星标', (tester) async {
      final store = await _pumpUnlockedHome(tester, [
        _simpleItem(title: 'Plain'),
        _simpleItem(title: 'Starred', favorite: true),
      ]);

      await tester.tap(find.text('收藏').first);
      await tester.pumpAndSettle();
      expect(find.text('Starred'), findsOneWidget);
      expect(find.text('Plain'), findsNothing);

      await tester.tap(find.text('全部').first);
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Plain'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('设为星标收藏'));
      await tester.pumpAndSettle();

      final plain = store.items.firstWhere((e) => e.title == 'Plain');
      expect(plain.isFavorite, isTrue);

      await tester.tap(find.text('收藏').first);
      await tester.pumpAndSettle();
      expect(find.text('Starred'), findsOneWidget);
      expect(find.text('Plain'), findsOneWidget);
    });

    testWidgets('搜索命中账号/标题，空结果展示空态并可一键还原', (tester) async {
      await _pumpUnlockedHome(tester, [
        _simpleItem(title: 'Binance', username: 'trader@demo.io'),
        _simpleItem(title: 'GitHub', username: 'dev@demo.io'),
      ]);

      await tester.enterText(
          find.byKey(const Key('vault_search_field')), 'trader');
      await tester.pumpAndSettle();
      expect(find.text('Binance'), findsOneWidget);
      expect(find.text('GitHub'), findsNothing);

      await tester.enterText(
          find.byKey(const Key('vault_search_field')), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('未找到匹配的账号记录'), findsOneWidget);

      await tester.tap(find.byKey(const Key('empty_view_all_button')));
      await tester.pumpAndSettle();
      expect(find.text('Binance'), findsOneWidget);
      expect(find.text('GitHub'), findsOneWidget);
    });

    testWidgets('分组开关切换平铺与分组视图', (tester) async {
      await _pumpUnlockedHome(tester, [
        _simpleItem(title: 'Binance', category: AccountCategory.crypto),
        _simpleItem(title: 'GitHub', category: AccountCategory.work),
      ]);

      // 分组态：显示常规网站的分区描述
      expect(find.text('交易所、Web3 钱包、行情平台'), findsOneWidget);

      await tester.tap(find.byKey(const Key('group_toggle_button')));
      await tester.pumpAndSettle();

      expect(find.text('交易所、Web3 钱包、行情平台'), findsNothing);
      expect(find.text('Binance'), findsOneWidget);
      expect(find.text('GitHub'), findsOneWidget);
    });

    testWidgets('长按删除：确认对话框后彻底移除并弹 Toast', (tester) async {
      final store = await _pumpUnlockedHome(tester, [
        _simpleItem(title: 'Doomed'),
      ]);

      await tester.longPress(find.text('Doomed'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除记录'));
      await tester.pumpAndSettle();

      expect(find.text('确认删除该服务及其下属全部账号？'), findsOneWidget);
      await tester.tap(find.text('永久删除'));
      await tester.pumpAndSettle();

      expect(store.items, isEmpty);
      expect(find.text('已彻底删除该记录（不保留）'), findsOneWidget);
      expect(find.text('「全部账号」下暂无记录'), findsOneWidget);
    });

    testWidgets('长按复制密码弹绿胶囊 Toast', (tester) async {
      await _pumpUnlockedHome(tester, [
        _simpleItem(title: 'Vault'),
      ]);

      await tester.longPress(find.text('Vault'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('复制 密码：Pass#12345'));
      await tester.pumpAndSettle();

      expect(find.textContaining('已复制 密码'), findsOneWidget);
      expect(find.textContaining('秒后自动清空剪贴板'), findsOneWidget);
    });

    testWidgets('打开抽屉侧栏并一键锁定', (tester) async {
      final store = await _pumpUnlockedHome(tester, [
        _simpleItem(title: 'Binance', category: AccountCategory.crypto),
      ]);

      await tester.tap(find.byKey(const Key('drawer_open_button')));
      await tester.pumpAndSettle();

      expect(find.text('SecretCore'), findsOneWidget);
      expect(find.text('极光秘核'), findsOneWidget);
      expect(find.text('快捷概览'), findsOneWidget);
      expect(find.text('按类型分类'), findsOneWidget);
      expect(find.text('纯本地加密 · 零联网'), findsOneWidget);

      await tester.tap(find.byKey(const Key('drawer_lock_button')));
      await tester.pumpAndSettle();

      expect(store.phase, VaultPhase.locked);
    });
  });

  group('详情页', () {
    Future<VaultStore> openDetail(
      WidgetTester tester, {
      required AccountItem item,
    }) async {
      final store = await _pumpUnlockedHome(tester, [item]);
      await tester.tap(find.text(item.title));
      await tester.pumpAndSettle();
      expect(find.byType(ItemDetailView), findsOneWidget);
      return store;
    }

    testWidgets('Hero 卡与按密码归组展示', (tester) async {
      await openDetail(
        tester,
        item: AccountItem(
          title: 'GitHub',
          url: 'https://github.com',
          category: AccountCategory.work,
          customTag: '代码库',
          customFields: {'恢复邮箱': 'recovery@demo.io'},
          noteEntries: [NoteEntry(label: '套餐', content: 'Team Plan')],
          entries: [
            CredentialEntry(
              accountLabel: '主邮箱',
              username: 'aurora@demo.io',
              password: 'Gh#Shared-2026',
              extraPasswords: [
                LabeledPassword(label: '访问令牌', value: 'ghp_demoToken'),
              ],
            ),
            CredentialEntry(
              accountLabel: '备用邮箱',
              username: 'backup@demo.io',
              password: 'Gh#Shared-2026',
            ),
            CredentialEntry(
              username: 'solo@demo.io',
              password: 'Gh#Solo-2026',
            ),
          ],
        ),
      );

      expect(find.text('2 套密码 · 3 个账号'), findsOneWidget);
      // 主列表卡片在底层路由同样显示标签徽章，因此用 findsWidgets
      expect(find.text('#代码库'), findsWidgets);
      expect(find.text('Gh#Shared-2026'), findsOneWidget);
      expect(find.text('下辖 2 个账号'), findsOneWidget);
      expect(find.text('主邮箱：'), findsOneWidget);
      expect(find.text('aurora@demo.io'), findsOneWidget);
      expect(find.text('访问令牌：'), findsOneWidget);
      expect(find.text('Gh#Solo-2026'), findsOneWidget);

      // 折叠第一个密码组后，组内账号隐藏（密码行保持可见）
      await tester.tap(find.byKey(const Key('group_toggle_0')));
      await tester.pumpAndSettle();
      expect(find.text('aurora@demo.io'), findsNothing);
      expect(find.text('Gh#Shared-2026'), findsOneWidget);
    });

    testWidgets('自定义字段与安全备注展示', (tester) async {
      final store = await openDetail(
        tester,
        item: AccountItem(
          title: 'GitHub',
          customFields: {'恢复邮箱': 'recovery@demo.io'},
          noteEntries: [
            NoteEntry(label: '套餐', content: 'Team Plan'),
            NoteEntry(label: '密保问题', content: '出生城市？'),
          ],
          entries: [
            CredentialEntry(username: 'aurora@demo.io', password: 'P#1'),
          ],
        ),
      );

      expect(find.text('自定义字段'), findsOneWidget);
      expect(find.text('恢复邮箱'), findsOneWidget);
      expect(find.text('安全备注'), findsOneWidget);
      expect(find.text('Team Plan'), findsOneWidget);
      expect(find.text('出生城市？'), findsOneWidget);

      // 切换一行两条：双列并排展示，且排版写回条目
      await tester.ensureVisible(find.byKey(const Key('notes_layout_double')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notes_layout_double')));
      await tester.pumpAndSettle();
      expect(store.items.single.notesLayout, NotesLayoutMode.double);
      expect(find.text('Team Plan'), findsOneWidget);
      expect(find.text('出生城市？'), findsOneWidget);

      // 点击备注卡片直接复制内容
      await tester.ensureVisible(find.text('Team Plan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Team Plan'));
      await tester.pumpAndSettle();
      expect(find.textContaining('已复制 套餐：Team Plan'), findsOneWidget);
    });

    testWidgets('账号/密码/2FA 方框点击即复制（对齐 Mac 点击复制）', (tester) async {
      await openDetail(
        tester,
        item: AccountItem(
          title: 'Binance',
          category: AccountCategory.crypto,
          entries: [
            CredentialEntry(
              username: 'trader@demo.io',
              password: 'Bnc#Aurora-2026',
              totpSecret: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ',
            ),
          ],
        ),
      );

      // 点击账号方框 → 复制账号 + 方框点亮已复制
      await tester.ensureVisible(find.text('trader@demo.io'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('trader@demo.io'));
      await tester.pumpAndSettle();
      expect(find.textContaining('已复制 账号：trader@demo.io'), findsOneWidget);
      expect(find.text('已复制'), findsWidgets);

      // 点击密码方框 → 复制密码
      await tester.tap(find.text('Bnc#Aurora-2026'));
      await tester.pumpAndSettle();
      expect(find.textContaining('已复制 密码：Bnc#Aurora-2026'), findsOneWidget);

      // 点击 2FA 卡片 → 复制动态码
      await tester.tap(find.textContaining(RegExp(r'^\d{3} \d{3}$')));
      await tester.pumpAndSettle();
      expect(find.textContaining('已复制 2FA：'), findsOneWidget);
    });

    testWidgets('详情内账号搜索过滤密码组', (tester) async {
      await openDetail(
        tester,
        item: AccountItem(
          title: 'GitHub',
          entries: [
            CredentialEntry(username: 'aurora@demo.io', password: 'Gh#Shared'),
            CredentialEntry(username: 'backup@demo.io', password: 'Gh#Shared'),
          ],
        ),
      );

      await tester.enterText(
          find.byKey(const Key('detail_search_field')), 'aurora');
      await tester.pumpAndSettle();

      expect(find.text('匹配 1 个账号'), findsOneWidget);
      expect(find.text('aurora@demo.io'), findsOneWidget);
      expect(find.text('backup@demo.io'), findsNothing);
    });

    testWidgets('2FA 面板展示实时动态码与倒计时环', (tester) async {
      await openDetail(
        tester,
        item: AccountItem(
          title: 'Binance',
          category: AccountCategory.crypto,
          entries: [
            CredentialEntry(
              username: 'trader@demo.io',
              password: 'Bnc#Aurora-2026',
              totpSecret: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ',
            ),
          ],
        ),
      );

      expect(find.text('Bnc#Aurora-2026'), findsOneWidget);
      expect(find.textContaining(RegExp(r'\d{3} \d{3}')), findsOneWidget);
    });

    testWidgets('快速追加账号解析入库并弹 Toast', (tester) async {
      final store = await openDetail(
        tester,
        item: AccountItem(
          title: 'GitHub',
          entries: [
            CredentialEntry(username: 'aurora@demo.io', password: 'Gh#Old'),
          ],
        ),
      );
      final itemId = store.selectedItem!.id;

      await tester.tap(find.byKey(const Key('quick_add_toggle')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('quick_add_field')),
        'newbie@demo.io FreshPass9',
      );
      await tester.tap(find.byKey(const Key('quick_add_submit')));
      await tester.pumpAndSettle();

      final item = store.items.firstWhere((e) => e.id == itemId);
      expect(item.entries.length, 2);
      expect(item.entries.last.username, 'newbie@demo.io');
      expect(item.entries.last.password, 'FreshPass9');
      expect(find.textContaining('已解析并追加 1 条账号'), findsOneWidget);
    });

    testWidgets('收藏按钮切换并回写主列表', (tester) async {
      final store = await openDetail(
        tester,
        item: _simpleItem(title: 'GitHub'),
      );

      await tester.tap(find.byTooltip('收藏'));
      await tester.pumpAndSettle();
      expect(store.items.single.isFavorite, isTrue);
    });
  });

  group('全局 2FA 单时钟与 Toast', () {
    testWidgets('copyToClipboard 进入两阶段 Toast 流程', (tester) async {
      final backend = InMemoryVaultBackend();
      backend.exists = true;
      backend.password = 'CorrectHorse1';
      final store = VaultStore(
        keychain: FakeKeychainService(),
        backend: backend,
      );
      addTearDown(store.dispose);
      await store.bootstrap();
      await store.unlockWithPassword('CorrectHorse1');

      var clipContent = '';
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (message) async {
          if (message.method == 'Clipboard.setData') {
            clipContent =
                (message.arguments as Map<dynamic, dynamic>)['text'] as String? ?? '';
            return null;
          }
          if (message.method == 'Clipboard.getData') {
            return {'text': clipContent};
          }
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      store.copyToClipboard('Pass#12345', label: '密码：Pass#12345');
      expect(
        store.clipboardStatusMessage,
        contains('已复制 密码：Pass#12345'),
      );
      expect(store.clipboardStatusMessage, contains('秒后自动清空剪贴板'));

      await tester.pump(const Duration(seconds: 31));
      expect(store.clipboardStatusMessage, '安全防护：剪贴板已自动清空');

      await tester.pump(const Duration(seconds: 2, milliseconds: 100));
      expect(store.clipboardStatusMessage, isNull);
    });
  });
}
