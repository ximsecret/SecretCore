import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/crypto/password_generator.dart';
import '../core/models/account_category.dart';
import '../core/models/account_item.dart';
import '../core/models/credential_entry.dart';
import '../core/models/labeled_password.dart';
import '../core/models/note_entry.dart';
import '../core/models/notes_layout_mode.dart';
import '../core/models/password_credential_group.dart';
import '../core/parser/smart_credential_parser.dart';
import 'app_theme.dart';
import 'item_editor_sheet.dart';
import 'vault_store.dart';

/// 条目详情页 — 对齐 Mac 版 ItemDetailView：
/// Hero 卡 + 内联快速追加 + 详情内账号搜索 + 按密码折叠分组 + 自定义字段 + 备注
class ItemDetailView extends StatefulWidget {
  const ItemDetailView({
    super.key,
    required this.store,
    required this.itemId,
  });

  final VaultStore store;
  final String itemId;

  @override
  State<ItemDetailView> createState() => _ItemDetailViewState();
}

class _ItemDetailViewState extends State<ItemDetailView> {
  String _accountSearch = '';
  final Set<String> _collapsedGroups = {};
  bool _quickAddExpanded = false;
  final TextEditingController _quickAddController = TextEditingController();

  // 点击即复制的方框反馈（对齐 Mac lastCopiedKey / triggerCopyFeedback）
  String? _lastCopiedKey;
  Timer? _copyFeedbackTimer;

  VaultStore get store => widget.store;

  @override
  void dispose() {
    _quickAddController.dispose();
    _copyFeedbackTimer?.cancel();
    super.dispose();
  }

  /// 复制内容并点亮对应方框的「已复制」状态
  void _copyWithFeedback(String text, String label, String key) {
    store.copyToClipboard(text, label: label);
    _copyFeedbackTimer?.cancel();
    setState(() => _lastCopiedKey = key);
    _copyFeedbackTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted && _lastCopiedKey == key) {
        setState(() => _lastCopiedKey = null);
      }
    });
  }

  AccountItem? _findItem() {
    for (final item in store.items) {
      if (item.id == widget.itemId) return item;
    }
    return null;
  }

  /// 按账号搜索词过滤密码组（对齐 Mac filteredPasswordGroups）
  List<PasswordCredentialGroup> _filteredGroups(AccountItem item) {
    final query = _accountSearch.trim().toLowerCase();
    if (query.isEmpty) return item.passwordGroups;

    final result = <PasswordCredentialGroup>[];
    for (final group in item.passwordGroups) {
      final pwdMatches = group.password.toLowerCase().contains(query);
      final matchingEntries = group.entries.where((entry) {
        return entry.username.toLowerCase().contains(query) ||
            entry.notes.toLowerCase().contains(query) ||
            entry.totpSecret.toLowerCase().contains(query) ||
            store.codeForEntry(entry).contains(query);
      }).toList();

      if (pwdMatches) {
        result.add(group);
      } else if (matchingEntries.isNotEmpty) {
        result.add(PasswordCredentialGroup(
          password: group.password,
          passwordLabel: group.passwordLabel,
          entries: matchingEntries,
        ));
      }
    }
    return result;
  }

  void _toggleGroup(String key) {
    setState(() {
      if (_collapsedGroups.contains(key)) {
        _collapsedGroups.remove(key);
      } else {
        _collapsedGroups.add(key);
      }
    });
  }

  String _groupKey(PasswordCredentialGroup g, int i) =>
      g.password.isEmpty ? 'empty_group_$i' : g.password;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final item = _findItem();
        if (item == null) {
          return const Scaffold(
            body: Center(
              child: Text('条目不存在',
                  style: TextStyle(color: AppTheme.textSecondary)),
            ),
          );
        }

        return Scaffold(
          backgroundColor: AppTheme.bgIceMid,
          appBar: AppBar(
            title: Text(item.title),
            actions: [
              IconButton(
                key: const Key('detail_edit_button'),
                tooltip: '编辑条目',
                icon: const Icon(Icons.edit_outlined,
                    color: AppTheme.textSecondary, size: 21),
                onPressed: () =>
                    openItemEditor(context, store: store, editingItem: item),
              ),
              IconButton(
                tooltip: item.isFavorite ? '取消收藏' : '收藏',
                icon: Icon(
                  item.isFavorite
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  color: item.isFavorite
                      ? AppTheme.starYellow
                      : AppTheme.textSecondary,
                ),
                onPressed: () => store.toggleFavorite(item.id),
              ),
            ],
          ),
          body: AppTheme.cyberBackground(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildHeroCard(item),
                const SizedBox(height: 14),
                _buildQuickAddPanel(item),
                const SizedBox(height: 14),
                _buildPasswordGroupsSection(item),
                if (item.customFields.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _buildCustomFields(item),
                ],
                if (item.effectiveNoteEntries.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _buildNotes(item),
                ],
                const SizedBox(height: 18),
                _buildFooter(item),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Hero 卡（Cyber Mission Control）──

  Widget _buildHeroCard(AccountItem item) {
    final cat = item.category;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.glassCard(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      cat.themeColor.withValues(alpha: 0.85),
                      cat.themeColor.withValues(alpha: 0.55),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(15),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.5)),
                ),
                child: Center(
                  child: Text(item.customIcon.isNotEmpty
                      ? item.customIcon
                      : cat.iconEmoji, style: const TextStyle(fontSize: 26)),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        if (item.isFavorite) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.star_rounded,
                              size: 16, color: AppTheme.starYellow),
                        ],
                      ],
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: AppTheme.actionBlue.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${item.passwordGroups.length} 套密码 · ${item.entries.length} 个账号',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.actionBlue,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 分类切换
                        PopupMenuButton<AccountCategory>(
                          tooltip: '切换所属分类',
                          onSelected: (cat) =>
                              store.updateCategory(item.id, cat),
                          itemBuilder: (_) => [
                            for (final c in AccountCategory.values)
                              PopupMenuItem(
                                value: c,
                                child: Row(
                                  children: [
                                    Text(c.iconEmoji,
                                        style:
                                            const TextStyle(fontSize: 15)),
                                    const SizedBox(width: 8),
                                    Text(
                                      c.title,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    if (c == item.category) ...[
                                      const Spacer(),
                                      const Icon(Icons.check,
                                          size: 16,
                                          color: AppTheme.primaryBlue),
                                    ],
                                  ],
                                ),
                              ),
                          ],
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3.5),
                            decoration: BoxDecoration(
                              color:
                                  cat.themeColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(cat.iconEmoji,
                                    style: const TextStyle(fontSize: 10)),
                                const SizedBox(width: 4),
                                Text(
                                  cat.title,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: cat.themeColor,
                                  ),
                                ),
                                const Icon(Icons.expand_more_rounded,
                                    size: 12, color: AppTheme.textSecondary),
                              ],
                            ),
                          ),
                        ),
                        if (item.normalizedCustomTag.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: AppTheme.tealTag.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '#${item.normalizedCustomTag}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.tealTag,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (item.url.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: () => store.copyToClipboard(item.url, label: '网址'),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.link_rounded,
                        size: 15, color: AppTheme.primaryBlue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.actionBlue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Icon(Icons.copy_rounded,
                        size: 13, color: AppTheme.primaryBlue),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── 内联快速追加（对齐 Mac quickAddCredentialPanel）──

  Widget _buildQuickAddPanel(AccountItem item) {
    return Container(
      decoration: AppTheme.glassCard(radius: 14),
      child: Column(
        children: [
          InkWell(
            key: const Key('quick_add_toggle'),
            onTap: () => setState(() => _quickAddExpanded = !_quickAddExpanded),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      gradient: AppTheme.brandGradient,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.add_rounded,
                        size: 17, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '快速追加账号 / 新密码',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  Icon(
                    _quickAddExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: AppTheme.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_quickAddExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '粘贴或输入如「user@mail.com pass123 2fa(JBSWY3DP)」，将智能解析并追加到「${item.title}」名下',
                    style: const TextStyle(
                        fontSize: 11.5, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('quick_add_field'),
                          controller: _quickAddController,
                          maxLines: 2,
                          minLines: 1,
                          style: const TextStyle(fontSize: 12.5),
                          decoration: const InputDecoration(
                            hintText: '账号 密码 2fa(密钥)，可多行',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 9),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        key: const Key('quick_add_submit'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primaryBlue,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          minimumSize: Size.zero,
                        ),
                        onPressed: () => _submitQuickAdd(item),
                        child: const Text('解析追加',
                            style: TextStyle(fontSize: 12.5)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _submitQuickAdd(AccountItem item) {
    final raw = _quickAddController.text.trim();
    if (raw.isEmpty) {
      store.showStatusToast('请先输入或粘贴账号信息');
      return;
    }

    var appended = 0;
    for (final line in raw.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final parsed = SmartParseBridge.parseLine(trimmed);
      if (parsed == null) continue;
      store.appendEntry(item.id, parsed);
      appended++;
    }

    if (appended > 0) {
      _quickAddController.clear();
      setState(() => _quickAddExpanded = false);
      store.showStatusToast('✨ 已解析并追加 $appended 条账号到「${item.title}」');
    } else {
      store.showStatusToast('未识别到有效账号信息');
    }
  }

  // ── 密码组区 ──

  Widget _buildPasswordGroupsSection(AccountItem item) {
    final groups = _filteredGroups(item);
    final searching = _accountSearch.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '凭据矩阵',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const Spacer(),
            SizedBox(
              width: 170,
              height: 32,
              child: TextField(
                key: const Key('detail_search_field'),
                onChanged: (v) => setState(() => _accountSearch = v),
                style:
                    const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
                decoration: InputDecoration(
                  hintText: '搜索账号 / 密码 / 2FA...',
                  prefixIcon: const Icon(Icons.search_rounded,
                      size: 14, color: AppTheme.textSecondary),
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  fillColor: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: _collapsedGroups.length >= groups.length && groups.isNotEmpty
                  ? '展开全部密码组'
                  : '折叠全部密码组',
              child: InkWell(
                onTap: () {
                  setState(() {
                    if (_collapsedGroups.length >= groups.length &&
                        groups.isNotEmpty) {
                      _collapsedGroups.clear();
                    } else {
                      _collapsedGroups.addAll(
                        [for (var i = 0; i < groups.length; i++) _groupKey(groups[i], i)],
                      );
                    }
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _collapsedGroups.length >= groups.length && groups.isNotEmpty
                        ? Icons.unfold_more_rounded
                        : Icons.unfold_less_rounded,
                    size: 16,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (searching)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '匹配 ${groups.fold<int>(0, (sum, g) => sum + g.entries.length)} 个账号',
              style:
                  const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ),
        const SizedBox(height: 8),
        if (groups.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: AppTheme.glassCard(),
            child: const Center(
              child: Text('未匹配到账号',
                  style:
                      TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
            ),
          )
        else
          for (var i = 0; i < groups.length; i++) ...[
            _PasswordGroupCard(
              group: groups[i],
              groupIndex: i,
              totalGroups: groups.length,
              collapsed: _collapsedGroups.contains(_groupKey(groups[i], i)),
              onToggle: () => _toggleGroup(_groupKey(groups[i], i)),
              store: store,
              category: item.category,
              lastCopiedKey: _lastCopiedKey,
              onCopy: _copyWithFeedback,
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  // ── 自定义字段 ──

  Widget _buildCustomFields(AccountItem item) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.glassCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '自定义字段',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          for (final field in item.customFields.entries)
            InkWell(
              onTap: () => store.copyToClipboard(field.value, label: field.key),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
                child: Row(
                  children: [
                    SizedBox(
                      width: 100,
                      child: Text(
                        field.key,
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        field.value,
                        style: const TextStyle(
                            fontSize: 13, color: AppTheme.textPrimary),
                      ),
                    ),
                    const Icon(Icons.copy_rounded,
                        size: 13, color: AppTheme.textSecondary),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── 安全备注（对齐 Mac notesSection：一行单条 / 一行两条切换，卡片点击复制，内容支持多行）──

  Widget _buildNotes(AccountItem item) {
    final entries = item.effectiveNoteEntries;
    if (entries.isEmpty) return const SizedBox.shrink();
    final accent = item.category.themeColor;
    final isDouble = item.notesLayout == NotesLayoutMode.double;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.glassCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sticky_note_2_rounded, size: 15, color: accent),
              const SizedBox(width: 6),
              const Text(
                '安全备注',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '点击卡片直接复制',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: AppTheme.textSecondary.withValues(alpha: 0.9),
                  ),
                ),
              ),
              const Spacer(),
              _NotesLayoutSwitcher(
                layout: item.notesLayout,
                accent: accent,
                onSelect: (mode) => store.updateNotesLayout(item.id, mode),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (isDouble)
            // 一行两条：LazyVGrid 双列对齐
            for (var i = 0; i < entries.length; i += 2) ...[
              if (i > 0) const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _noteCard(item, entries[i])),
                  if (i + 1 < entries.length) ...[
                    const SizedBox(width: 10),
                    Expanded(child: _noteCard(item, entries[i + 1])),
                  ] else
                    const Spacer(),
                ],
              ),
            ]
          else
            // 一行单条：全宽通栏，内容多行展开
            Column(
              children: [
                for (var i = 0; i < entries.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _noteCard(item, entries[i]),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _noteCard(AccountItem item, NoteEntry note) {
    final copied = _lastCopiedKey == 'note_${note.id}';
    return InkWell(
      onTap: () => _copyWithFeedback(
        note.content,
        '${note.effectiveLabel}：${note.content}',
        'note_${note.id}',
      ),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: copied
              ? AppTheme.successGreen.withValues(alpha: 0.07)
              : Colors.white.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: copied
                ? AppTheme.successGreen.withValues(alpha: 0.4)
                : AppTheme.strokeDim,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${note.effectiveLabel}：',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: item.category.themeColor,
              ),
            ),
            Expanded(
              child: Text(
                note.content,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 6),
            _CopyCapsule(copied: copied),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(AccountItem item) {
    final fmt = DateFormat('yyyy-MM-dd HH:mm');
    return Center(
      child: Text(
        '创建于 ${fmt.format(item.createdAt)} · 更新于 ${fmt.format(item.updatedAt)}',
        style: TextStyle(
          fontSize: 11,
          color: AppTheme.textSecondary.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

// ────────────────────────── 密码组卡片（对齐 Mac passwordGroupCard）──────────────────────────

class _PasswordGroupCard extends StatelessWidget {
  const _PasswordGroupCard({
    required this.group,
    required this.groupIndex,
    required this.totalGroups,
    required this.collapsed,
    required this.onToggle,
    required this.store,
    required this.category,
    required this.lastCopiedKey,
    required this.onCopy,
  });

  final PasswordCredentialGroup group;
  final int groupIndex;
  final int totalGroups;
  final bool collapsed;
  final VoidCallback onToggle;
  final VaultStore store;
  final AccountCategory category;
  final String? lastCopiedKey;
  final void Function(String text, String label, String key) onCopy;

  String get _pwdKey => 'pwd_group_$groupIndex';

  @override
  Widget build(BuildContext context) {
    final eval = (
      strength: PasswordGenerator.evaluateStrength(group.password),
      entropyBits: PasswordGenerator.calculateEntropy(group.password).round(),
    );

    return Container(
      decoration: AppTheme.glassCard(radius: 16),
      child: Column(
        children: [
          _buildHeader(),
          // 密码行：左列密码主框（点击复制）+ 右列 260pt 安全评级卡
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: _sideBySide(
              context,
              left: _CredBox(
                label: '${group.effectivePasswordLabel}：',
                value: group.password,
                emptyHint: '（未设置密码）',
                color: const Color(0xFFF28C1F),
                icon: Icons.key_rounded,
                copied: lastCopiedKey == _pwdKey,
                onCopy: () => onCopy(
                  group.password,
                  '${group.effectivePasswordLabel}：${group.password}',
                  _pwdKey,
                ),
              ),
              right: _StrengthCard(eval: eval),
            ),
          ),
          if (!collapsed) ...[
            const Divider(height: 1),
            for (var i = 0; i < group.entries.length; i++) ...[
              _AccountAndTotpRow(
                entry: group.entries[i],
                store: store,
                category: category,
                lastCopiedKey: lastCopiedKey,
                onCopy: onCopy,
              ),
              if (i < group.entries.length - 1)
                Divider(height: 1, indent: 14, endIndent: 14),
            ],
          ],
        ],
      ),
    );
  }

  // ── 组头：展开/收起 + 密码组徽章 + 下辖账号数 ──
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(
        children: [
          // 展开 / 收起胶囊
          InkWell(
            key: Key('group_toggle_$groupIndex'),
            onTap: onToggle,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: collapsed
                    ? AppTheme.primaryBlue.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    collapsed
                        ? Icons.chevron_right_rounded
                        : Icons.expand_more_rounded,
                    size: 12,
                    color: collapsed
                        ? AppTheme.primaryBlue
                        : AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    collapsed ? '展开' : '收起',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: collapsed
                          ? AppTheme.primaryBlue
                          : AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 密码组徽章
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              gradient: AppTheme.brandGradient,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.key_rounded,
                    size: 10, color: Colors.white),
                const SizedBox(width: 4),
                Text(
                  totalGroups > 1 ? '密码组 #${groupIndex + 1}' : '登录密码',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 下辖账号数量
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '下辖 ${group.accountCount} 个账号',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.actionBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 宽屏左右两列（右列 260pt 与 Mac 版对齐），窄屏（iOS 竖屏）上下堆叠
Widget _sideBySide(
  BuildContext context, {
  required Widget left,
  required Widget right,
}) {
  final wide = MediaQuery.sizeOf(context).width >= 620;
  if (wide) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        right,
      ],
    );
  }
  return Column(
    children: [
      left,
      const SizedBox(height: 8),
      SizedBox(width: double.infinity, child: right),
    ],
  );
}

// ────────────────────────── 凭据方框（点击即复制）──────────────────────────

/// 通用凭据主框：32 图标胶囊 + 标签：值 + 复制胶囊，整块点击复制（对齐 Mac passwordMainBox / accountMainBox）
class _CredBox extends StatelessWidget {
  const _CredBox({
    required this.label,
    required this.value,
    required this.emptyHint,
    required this.color,
    required this.icon,
    required this.copied,
    required this.onCopy,
    this.trailing,
  });

  final String label;
  final String value;
  final String emptyHint;
  final Color color;
  final IconData icon;
  final bool copied;
  final VoidCallback onCopy;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final hasValue = value.isNotEmpty;
    return InkWell(
      onTap: hasValue ? onCopy : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: copied
              ? AppTheme.successGreen.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: copied
                ? AppTheme.successGreen.withValues(alpha: 0.45)
                : AppTheme.primaryBlue.withValues(alpha: 0.20),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: copied
                    ? AppTheme.successGreen.withValues(alpha: 0.16)
                    : color.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(
                copied ? Icons.check_rounded : icon,
                size: 15,
                color: copied ? AppTheme.successGreen : color,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                hasValue ? value : emptyHint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  color: hasValue ? AppTheme.textPrimary : AppTheme.textFaint,
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 4),
              trailing!,
            ],
            if (hasValue) ...[
              const SizedBox(width: 6),
              _CopyCapsule(copied: copied),
            ],
          ],
        ),
      ),
    );
  }
}

/// 「复制 / 已复制」小胶囊
class _CopyCapsule extends StatelessWidget {
  const _CopyCapsule({required this.copied});

  final bool copied;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: copied
            ? AppTheme.successGreen.withValues(alpha: 0.14)
            : Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            copied ? Icons.check_rounded : Icons.copy_rounded,
            size: 10,
            color: copied ? AppTheme.successGreen : AppTheme.textSecondary,
          ),
          const SizedBox(width: 3),
          Text(
            copied ? '已复制' : '复制',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: copied ? AppTheme.successGreen : AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────── 密码行右列：安全评级卡 ──────────────────────────

class _StrengthCard extends StatelessWidget {
  const _StrengthCard({required this.eval});

  final ({PasswordStrength strength, int entropyBits}) eval;

  static (Color, String, int) _meta(PasswordStrength strength) => switch (strength) {
        PasswordStrength.weak => (AppTheme.dangerRed, '弱', 1),
        PasswordStrength.medium => (AppTheme.warnOrange, '中', 2),
        PasswordStrength.strong => (AppTheme.successGreen, '强', 3),
        PasswordStrength.veryStrong => (const Color(0xFF0DBFF2), '极强', 4),
      };

  @override
  Widget build(BuildContext context) {
    final (color, label, level) = _meta(eval.strength);
    return Container(
      width: 260,
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: AppTheme.primaryBlue.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Icon(Icons.shield_rounded, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '安全评级：',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${eval.entropyBits} bit 熵值 · 内存沙箱加密',
                  style: const TextStyle(
                    fontSize: 9.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: 3),
                Container(
                  width: 8,
                  height: 12,
                  decoration: BoxDecoration(
                    color: i < level
                        ? color
                        : AppTheme.textSecondary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ────────────────────────── 单个子账号 + 2FA 行（对齐 Mac subAccountAnd2FARow）──────────────────────────

class _AccountAndTotpRow extends StatelessWidget {
  const _AccountAndTotpRow({
    required this.entry,
    required this.store,
    required this.category,
    required this.lastCopiedKey,
    required this.onCopy,
  });

  final CredentialEntry entry;
  final VaultStore store;
  final AccountCategory category;
  final String? lastCopiedKey;
  final void Function(String text, String label, String key) onCopy;

  @override
  Widget build(BuildContext context) {
    final userCopied = lastCopiedKey == 'user_${entry.id}';
    final tfaCopied = lastCopiedKey == 'tfa_${entry.id}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          _sideBySide(
            context,
            left: _CredBox(
              label: '${entry.effectiveAccountLabel}：',
              value: entry.username,
              emptyHint: '（未填写账号）',
              color: category.themeColor,
              icon: Icons.person_rounded,
              copied: userCopied,
              onCopy: () => onCopy(
                entry.username,
                '${entry.effectiveAccountLabel}：${entry.username}',
                'user_${entry.id}',
              ),
              trailing: entry.notes.trim().isEmpty
                  ? null
                  : _TealNotesBadge(text: entry.notes.trim()),
            ),
            right: _TOTPCard(
              entry: entry,
              store: store,
              copied: tfaCopied,
              onCopy: () {
                final raw = store.codeForEntry(entry);
                final valid = raw != '密钥错误' && raw != '------';
                final copyValue = valid ? raw : entry.totpSecret;
                onCopy(copyValue, '2FA：${store.formattedCode(copyValue)}',
                    'tfa_${entry.id}');
              },
            ),
          ),
          // 从属额外密码（资金密码 / API Key 等，明文点击复制）
          for (final extra in entry.extraPasswords)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _sideBySide(
                context,
                left: _ExtraPasswordBox(
                  extra: extra,
                  copied: lastCopiedKey == 'extra_${extra.id}',
                  onCopy: () => onCopy(
                    extra.value,
                    '${extra.effectiveLabel}：${extra.value}',
                    'extra_${extra.id}',
                  ),
                ),
                right: const _SecondaryVaultCard(),
              ),
            ),
        ],
      ),
    );
  }
}

/// 账号框内的备注小胶囊（对齐 Mac teal capsule）
class _TealNotesBadge extends StatelessWidget {
  const _TealNotesBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      constraints: const BoxConstraints(maxWidth: 120),
      decoration: BoxDecoration(
        color: AppTheme.tealTag.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          color: AppTheme.tealTag,
        ),
      ),
    );
  }
}

/// 2FA 动态码卡片：全高进度条填充 + 秒数徽章 + 复制胶囊（对齐 Mac accountTOTPCard）
class _TOTPCard extends StatelessWidget {
  const _TOTPCard({
    required this.entry,
    required this.store,
    required this.copied,
    required this.onCopy,
  });

  final CredentialEntry entry;
  final VaultStore store;
  final bool copied;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    if (!entry.hasTOTP) {
      // 未配置 2FA 的守恒占位卡（保证左右列宽对齐）
      return Container(
        width: MediaQuery.sizeOf(context).width >= 620 ? 260 : null,
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: AppTheme.primaryBlue.withValues(alpha: 0.20)),
        ),
        child: Row(
          children: [
            Icon(Icons.shield_outlined,
                size: 13,
                color: AppTheme.textSecondary.withValues(alpha: 0.6)),
            const SizedBox(width: 6),
            const Text(
              '2FA：未配置动态口令',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppTheme.textFaint,
              ),
            ),
          ],
        ),
      );
    }

    final raw = store.codeForEntry(entry);
    final valid = raw != '密钥错误' && raw != '------';
    final urgent = valid && store.remainingSeconds2FA <= 5;
    final progress = store.progress2FA.clamp(0.0, 1.0);

    return InkWell(
      onTap: onCopy,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 50,
        width: MediaQuery.sizeOf(context).width >= 620 ? 260 : null,
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: copied
                ? AppTheme.successGreen.withValues(alpha: 0.55)
                : urgent
                    ? AppTheme.dangerRed.withValues(alpha: 0.40)
                    : AppTheme.primaryBlue.withValues(alpha: 0.20),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final fillWidth =
                  valid ? constraints.maxWidth * progress : constraints.maxWidth;
              return Stack(
                children: [
                  Positioned.fill(
                    child: ColoredBox(
                      color: copied
                          ? AppTheme.successGreen.withValues(alpha: 0.10)
                          : urgent
                              ? AppTheme.dangerRed.withValues(alpha: 0.06)
                              : Colors.white.withValues(alpha: 0.88),
                    ),
                  ),
                  if (valid)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: fillWidth,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: copied
                                ? [
                                    AppTheme.successGreen.withValues(alpha: 0.24),
                                    AppTheme.successGreen.withValues(alpha: 0.32),
                                  ]
                                : urgent
                                    ? [
                                        AppTheme.warnOrange.withValues(alpha: 0.32),
                                        AppTheme.dangerRed.withValues(alpha: 0.40),
                                      ]
                                    : [
                                        const Color(0xFF0DB885).withValues(alpha: 0.22),
                                        AppTheme.primaryBlue.withValues(alpha: 0.28),
                                      ],
                          ),
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.verified_user_rounded,
                            size: 14,
                            color: copied
                                ? AppTheme.successGreen
                                : urgent
                                    ? AppTheme.dangerRed
                                    : const Color(0xFF0DA67A),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '2FA：',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: urgent
                                  ? AppTheme.dangerRed
                                  : const Color(0xFF0C8C61),
                            ),
                          ),
                          Flexible(
                            child: Text(
                              valid
                                  ? store.formattedCode(raw)
                                  : entry.totpSecret,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: valid ? 14.5 : 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: valid ? 1.5 : 0,
                                color: copied
                                    ? AppTheme.successGreen
                                    : urgent
                                        ? AppTheme.dangerRed
                                        : AppTheme.primaryBlue,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          if (valid) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: (urgent
                                        ? AppTheme.dangerRed
                                        : AppTheme.primaryBlue)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${store.remainingSeconds2FA}s',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: urgent
                                      ? AppTheme.dangerRed
                                      : AppTheme.actionBlue,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: copied
                                  ? AppTheme.successGreen
                                  : urgent
                                      ? AppTheme.dangerRed.withValues(alpha: 0.12)
                                      : AppTheme.primaryBlue
                                          .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  copied
                                      ? Icons.check_rounded
                                      : Icons.copy_rounded,
                                  size: 10,
                                  color: copied
                                      ? Colors.white
                                      : urgent
                                          ? AppTheme.dangerRed
                                          : AppTheme.primaryBlue,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  copied ? '已复制' : '复制',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: copied
                                        ? Colors.white
                                        : urgent
                                            ? AppTheme.dangerRed
                                            : AppTheme.primaryBlue,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ────────────────────────── 从属额外密码行 ──────────────────────────

class _ExtraPasswordBox extends StatelessWidget {
  const _ExtraPasswordBox({
    required this.extra,
    required this.copied,
    required this.onCopy,
  });

  final LabeledPassword extra;
  final bool copied;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return _CredBox(
      label: '${extra.effectiveLabel}：',
      value: extra.value,
      emptyHint: '（未设置）',
      color: const Color(0xFF9333EA),
      icon: Icons.vpn_key_rounded,
      copied: copied,
      onCopy: onCopy,
    );
  }
}

/// 右列 260pt 守恒占位卡（对齐 Mac「从属二级凭据 · 独立密级」）
class _SecondaryVaultCard extends StatelessWidget {
  const _SecondaryVaultCard();

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 620;
    return Container(
      width: wide ? 260 : null,
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: AppTheme.textSecondary.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(Icons.shield_outlined,
              size: 13, color: AppTheme.textSecondary.withValues(alpha: 0.7)),
          const SizedBox(width: 6),
          const Text(
            '从属二级凭据 · 独立密级',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────── 备注排版切换器（一行单条 / 一行两条）──────────────────────────

class _NotesLayoutSwitcher extends StatelessWidget {
  const _NotesLayoutSwitcher({
    required this.layout,
    required this.accent,
    required this.onSelect,
  });

  final NotesLayoutMode layout;
  final Color accent;
  final ValueChanged<NotesLayoutMode> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.strokeDim),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final mode in NotesLayoutMode.values) ...[
            if (mode != NotesLayoutMode.single) const SizedBox(width: 2),
            InkWell(
              key: Key('notes_layout_${mode.name}'),
              onTap: () => onSelect(mode),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                decoration: BoxDecoration(
                  color: layout == mode
                      ? accent.withValues(alpha: 0.18)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      mode == NotesLayoutMode.single
                          ? Icons.view_stream_rounded
                          : Icons.grid_view_rounded,
                      size: 10,
                      color: layout == mode ? accent : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      mode.displayName,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color:
                            layout == mode ? accent : AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 解析桥接：详情页快速追加把单行文本解析为凭据
class SmartParseBridge {
  SmartParseBridge._();

  static CredentialEntry? parseLine(String line) {
    final parsed = SmartCredentialParser.parse(line);
    if (parsed.username.isEmpty &&
        parsed.password.isEmpty &&
        parsed.totpSecret.isEmpty) {
      return null;
    }
    return parsed.toCredentialEntry();
  }
}
