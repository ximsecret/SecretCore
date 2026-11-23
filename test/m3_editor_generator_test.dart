import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secret_core/core/models/account_item.dart';
import 'package:secret_core/core/models/credential_entry.dart';
import 'package:secret_core/core/models/note_entry.dart';
import 'package:secret_core/ui/app_theme.dart';
import 'package:secret_core/ui/item_editor_sheet.dart';
import 'package:secret_core/ui/password_generator_sheet.dart';
import 'package:secret_core/ui/settings_view.dart';
import 'package:secret_core/ui/vault_store.dart';

import 'vault_list_test.dart' show InMemoryVaultBackend, FakeKeychainService;

const _demoSecret = 'JBSWY3DPEHPK3PXP';

/// 已解锁保险箱（空数据），可直接挂载编辑器 / 生成器 / 设置页
Future<VaultStore> _makeUnlockedStore(WidgetTester tester) async {
  final backend = InMemoryVaultBackend();
  backend.exists = true;
  backend.password = 'CorrectHorse1';
  backend.savedItems = [];

  final store = VaultStore(
    keychain: FakeKeychainService(),
    backend: backend,
  );
  addTearDown(store.dispose);

  await store.bootstrap();
  final ok = await store.unlockWithPassword('CorrectHorse1');
  expect(ok, isTrue);
  return store;
}

Future<void> _pumpEditor(
  WidgetTester tester, {
  required VaultStore store,
  AccountItem? editingItem,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => openItemEditor(
            context,
            store: store,
            editingItem: editingItem,
          ),
          child: const Text('open-editor'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open-editor'));
  await tester.pumpAndSettle();
}

Future<void> _saveAndSettle(WidgetTester tester) async {
  // 编辑器是懒加载 ListView，底栏初始未构建，需滚动直至可见
  final saveButton = find.byKey(const Key('editor_save_button'));
  await tester.scrollUntilVisible(
    saveButton,
    160,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(saveButton);
  await tester.pumpAndSettle();
}

void main() {
  group('M3 条目编辑器（对齐 Mac ItemEditorSheet）', () {
    testWidgets('智能识别新建：解析文本后保存入库', (tester) async {
      final store = await _makeUnlockedStore(tester);
      await _pumpEditor(tester, store: store);

      await tester.enterText(
        find.byKey(const Key('editor_smart_field')),
        'github.com user@a.com Pwd#8888 2fa($_demoSecret)',
      );
      await tester.pumpAndSettle();
      await _saveAndSettle(tester);

      expect(store.items.length, 1);
      final item = store.items.first;
      expect(item.entries.first.username, 'user@a.com');
      expect(item.entries.first.password, 'Pwd#8888');
      expect(item.entries.first.totpSecret, _demoSecret);
      expect(store.phase, VaultPhase.unlocked);
    });

    testWidgets('编辑模式：修改标题与账号后保存更新原条目', (tester) async {
      final store = await _makeUnlockedStore(tester);
      final existing = AccountItem(
        title: '旧标题',
        entries: [
          CredentialEntry(username: 'old@a.com', password: 'OldPass1'),
        ],
        noteEntries: [NoteEntry(label: '备注1', content: '旧备注')],
      );
      await store.upsertItem(existing);

      await _pumpEditor(tester, store: store, editingItem: existing);
      await tester.enterText(
        find.byKey(const Key('editor_title_field')),
        '新标题',
      );
      await tester.enterText(
        find.byKey(const Key('editor_username_field')),
        'new@a.com',
      );
      await _saveAndSettle(tester);

      expect(store.items.length, 1);
      expect(store.items.first.title, '新标题');
      expect(store.items.first.entries.first.username, 'new@a.com');
      // 未改动的结构化备注保留
      expect(store.items.first.noteEntries.first.content, '旧备注');
    });

    testWidgets('同名归并：新建保存时追加至既有条目而非重复创建', (tester) async {
      final store = await _makeUnlockedStore(tester);
      await store.upsertItem(AccountItem(
        title: 'GitHub',
        entries: [CredentialEntry(username: 'first@a.com')],
      ));

      await _pumpEditor(tester, store: store);
      await tester.enterText(
        find.byKey(const Key('editor_smart_field')),
        'github.com second@a.com Pwd#7777',
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('editor_title_field')),
        'GitHub',
      );
      await _saveAndSettle(tester);

      expect(store.items.length, 1);
      final usernames =
          store.items.first.entries.map((e) => e.username).toList();
      expect(usernames, containsAll(['first@a.com', 'second@a.com']));
    });

    testWidgets('从属密码与结构化备注：新增后保存写回模型', (tester) async {
      final store = await _makeUnlockedStore(tester);
      await _pumpEditor(tester, store: store);

      await tester.enterText(find.byKey(const Key('editor_title_field')),
          '交易所');
      await tester.enterText(
          find.byKey(const Key('editor_username_field')), 'trader@x.com');
      await tester.enterText(
          find.byKey(const Key('editor_password_field')), 'Main#0000');

      await tester.ensureVisible(
          find.byKey(const Key('editor_add_extra_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editor_add_extra_button')));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('editor_free_note_field')), '资金密码：Zi#9999');
      await _saveAndSettle(tester);

      final item = store.items.first;
      expect(item.title, '交易所');
      // 自由备注升级为结构化备注
      expect(item.noteEntries, isNotEmpty);
      expect(item.noteEntries.first.content, contains('资金密码'));
    });
  });

  group('M3 密码生成器面板', () {
    testWidgets('展示密码且「使用此密码」返回生成值', (tester) async {
      Future<String?>? resultFuture;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  resultFuture = showPasswordGeneratorSheet(context),
              child: const Text('open-generator'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open-generator'));
      await tester.pumpAndSettle();

      // 已自动生成一个非空密码
      final selectable = tester.widget<SelectableText>(
        find.byType(SelectableText).first,
      );
      expect(selectable.data, isNotEmpty);

      await tester.tap(find.byKey(const Key('gen_use_button')));
      await tester.pumpAndSettle();

      final used = await resultFuture;
      expect(used, isNotEmpty);
    });

    testWidgets('关闭按钮返回 null 且不保留面板', (tester) async {
      Future<String?>? resultFuture;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  resultFuture = showPasswordGeneratorSheet(context),
              child: const Text('open-generator'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open-generator'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(await resultFuture, isNull);
      expect(find.byType(PasswordGeneratorSheet), findsNothing);
    });

    testWidgets('刷新按钮生成全新密码', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPasswordGeneratorSheet(context),
              child: const Text('open-generator'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open-generator'));
      await tester.pumpAndSettle();

      String current() => tester
          .widget<SelectableText>(find.byType(SelectableText).first)
          .data!;

      final before = current();
      await tester.tap(find.byKey(const Key('gen_refresh_button')));
      await tester.pumpAndSettle();
      final after = current();

      expect(after, isNotEmpty);
      expect(after, isNot(equals(before)));
    });
  });

  group('M3 设置与关于页', () {
    testWidgets('展示手动锁定说明 / 数据说明 / 版本信息与统计', (tester) async {
      final store = await _makeUnlockedStore(tester);
      await store.upsertItem(AccountItem(
        title: 'GitHub',
        entries: [
          CredentialEntry(username: 'a@x.com', password: 'P1', totpSecret: _demoSecret),
        ],
      ));

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark(), home: SettingsView(store: store)),
      );
      await tester.pumpAndSettle();

      expect(find.text('仅手动锁定'), findsOneWidget);
      expect(find.text('剪贴板保护'), findsOneWidget);
      expect(find.text('纯本地离线 · 零联网'), findsOneWidget);
      expect(find.textContaining('版本 1.0.0'), findsOneWidget);
      expect(find.textContaining('1 个条目'), findsOneWidget);
      expect(find.textContaining('1 个 2FA'), findsOneWidget);
    });

    testWidgets('立即锁定：返回上一页并回到锁屏阶段', (tester) async {
      final store = await _makeUnlockedStore(tester);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => SettingsView(store: store)),
              ),
              child: const Text('open-settings'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open-settings'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('立即锁定'));
      await tester.pumpAndSettle();

      expect(store.phase, VaultPhase.locked);
    });
  });
}
