import 'package:flutter/material.dart';

import '../core/models/account_category.dart';
import '../core/models/account_item.dart';
import 'app_theme.dart';
import 'item_detail_view.dart';
import 'item_editor_sheet.dart';
import 'password_generator_sheet.dart';
import 'settings_view.dart';
import 'sidebar_filter.dart';
import 'totp_ring.dart';
import 'vault_store.dart';

/// 主保险箱视图 — 对齐 Mac 版 MainVaultView：
/// 顶部搜索/分组开关/粘贴即存/智能添加 + 快捷胶囊栏 + 分组列表 + 选中态 + Toast
class MainVaultView extends StatelessWidget {
  const MainVaultView({super.key, required this.store});

  final VaultStore store;

  void _openDetail(BuildContext context, AccountItem item) {
    store.selectItem(item.id);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ItemDetailView(store: store, itemId: item.id),
      ),
    );
  }

  void _pasteAdd(BuildContext context) {
    final cat = store.currentFilter.kind == 'category'
        ? store.currentFilter.category!
        : AccountCategory.general;
    store.smartAddFromClipboard(defaultCategory: cat);
  }

  void _smartAdd(BuildContext context) {
    final cat = store.currentFilter.kind == 'category'
        ? store.currentFilter.category!
        : AccountCategory.general;
    openItemEditor(context, store: store, defaultCategory: cat);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final filtered = store.filteredItems;
        final groups = store.itemsGroupedByCategory;

        return Column(
          children: [
            _HeaderBar(
              store: store,
              onPasteAdd: () => _pasteAdd(context),
              onSmartAdd: () => _smartAdd(context),
            ),
            _QuickFilterChips(store: store),
            const Divider(height: 1),
            Expanded(
              child: filtered.isEmpty
                  ? _EmptyStateView(
                      store: store,
                      onPasteAdd: () => _pasteAdd(context),
                      onSmartAdd: () => _smartAdd(context),
                    )
                  : _ItemsList(
                      store: store,
                      filtered: filtered,
                      groups: groups,
                      onOpen: (item) => _openDetail(context, item),
                    ),
            ),
          ],
        );
      },
    );
  }
}

// ────────────────────────── 顶部搜索与操作栏 ──────────────────────────

class _HeaderBar extends StatefulWidget {
  const _HeaderBar({
    required this.store,
    required this.onPasteAdd,
    required this.onSmartAdd,
  });

  final VaultStore store;
  final VoidCallback onPasteAdd;
  final VoidCallback onSmartAdd;

  @override
  State<_HeaderBar> createState() => _HeaderBarState();
}

class _HeaderBarState extends State<_HeaderBar> {
  late final TextEditingController _searchController;

  VaultStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: store.searchQuery);
    store.addListener(_syncFromStore);
  }

  /// 外部清空搜索（锁屏重置 / 空态「查看全部账号」）时同步输入框
  void _syncFromStore() {
    if (store.searchQuery != _searchController.text) {
      _searchController.value = TextEditingValue(
        text: store.searchQuery,
        selection: TextSelection.collapsed(offset: store.searchQuery.length),
      );
    }
  }

  @override
  void dispose() {
    store.removeListener(_syncFromStore);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white.withValues(alpha: 0.55),
      padding: const EdgeInsets.fromLTRB(8, 10, 12, 8),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                key: const Key('drawer_open_button'),
                tooltip: '导航侧栏',
                icon: const Icon(Icons.menu_rounded,
                    size: 22, color: AppTheme.textSecondary),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search_rounded,
                          size: 16, color: AppTheme.textSecondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          key: const Key('vault_search_field'),
                          controller: _searchController,
                          onChanged: store.setSearchQuery,
                          style: const TextStyle(
                              color: AppTheme.textPrimary, fontSize: 13),
                          decoration: const InputDecoration(
                            hintText: '搜索标题、账号、网址、分类或 #标签...',
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding:
                                EdgeInsets.symmetric(vertical: 9),
                          ),
                        ),
                      ),
                      if (store.searchQuery.isNotEmpty)
                        GestureDetector(
                          onTap: () => store.setSearchQuery(''),
                          child: const Icon(Icons.cancel_rounded,
                              size: 15, color: AppTheme.textSecondary),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _IconButton(
                key: const Key('group_toggle_button'),
                tooltip: store.groupByCategory
                    ? '当前：按类型分组显示（点击切换为平铺列表）'
                    : '当前：平铺列表显示（点击切换为按类型分组）',
                icon: store.groupByCategory
                    ? Icons.grid_view_rounded
                    : Icons.list_rounded,
                color: store.groupByCategory
                    ? AppTheme.primaryBlue
                    : AppTheme.textSecondary,
                onTap: store.toggleGroupByCategory,
              ),
              const SizedBox(width: 8),
              _PasteAddButton(onTap: widget.onPasteAdd),
              const SizedBox(width: 8),
              _SmartAddButton(onTap: widget.onSmartAdd),
            ],
          ),
        ],
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}

class _PasteAddButton extends StatelessWidget {
  const _PasteAddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '一键读取剪贴板如「xxxx.com xxx账号 xxx密码 2fa(xxxx)」直接识别入库',
      child: InkWell(
        key: const Key('paste_add_button'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: AppTheme.actionBlue.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.content_paste_rounded,
                  size: 14, color: AppTheme.actionBlue),
              SizedBox(width: 4),
              Text(
                '粘贴即存',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.actionBlue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmartAddButton extends StatelessWidget {
  const _SmartAddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '打开智能识别添加面板，支持任意文本一键自动拆解入库',
      child: InkWell(
        key: const Key('smart_add_button'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            gradient: AppTheme.brandGradient,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome_rounded, size: 14, color: Colors.white),
              SizedBox(width: 4),
              Text(
                '智能添加',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────── 快捷筛选胶囊栏 ──────────────────────────

class _QuickFilterChips extends StatelessWidget {
  const _QuickFilterChips({required this.store});

  final VaultStore store;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        children: [
          _chip(SidebarFilter.all, '全部'),
          _chip(SidebarFilter.has2FA, '2FA 动态码'),
          _chip(SidebarFilter.favorites, '收藏'),
          VerticalDivider(
              width: 16, indent: 8, endIndent: 8, color: AppTheme.strokeDim),
          for (final cat in AccountCategory.values)
            _chip(SidebarFilter.forCategory(cat), cat.title),
        ],
      ),
    );
  }

  Widget _chip(SidebarFilter filter, String label) {
    final isSelected = store.currentFilter == filter;
    final tint = filter.tintColor;
    final count = store.countFor(filter);

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: () => store.setFilter(filter),
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(
                    colors: [tint, tint.withValues(alpha: 0.82)])
                : null,
            color: isSelected ? null : Colors.black.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isSelected
                  ? tint.withValues(alpha: 0.4)
                  : Colors.black.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(filter.iconName,
                  size: 12, color: isSelected ? Colors.white : tint),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? Colors.white
                      : AppTheme.textPrimary.withValues(alpha: 0.85),
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 3),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.9)
                        : AppTheme.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────── 列表主体 ──────────────────────────

class _ItemsList extends StatelessWidget {
  const _ItemsList({
    required this.store,
    required this.filtered,
    required this.groups,
    required this.onOpen,
  });

  final VaultStore store;
  final List<AccountItem> filtered;
  final List<(AccountCategory, List<AccountItem>)> groups;
  final void Function(AccountItem) onOpen;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (store.groupByCategory)
          for (final (cat, items) in groups) ...[
            _CategorySectionHeader(category: cat, count: items.length),
            for (final item in items)
              _AccountCard(
                item: item,
                selected: store.selectedItem?.id == item.id,
                store: store,
                onOpen: () => onOpen(item),
              ),
            const SizedBox(height: 6),
          ]
        else
          for (final item in filtered)
            _AccountCard(
              item: item,
              selected: store.selectedItem?.id == item.id,
              store: store,
              onOpen: () => onOpen(item),
            ),
      ],
    );
  }
}

class _CategorySectionHeader extends StatelessWidget {
  const _CategorySectionHeader({required this.category, required this.count});

  final AccountCategory category;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 14,
            decoration: BoxDecoration(
              color: category.themeColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(category.iconEmoji, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          Text(
            category.title,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              category.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 10, color: AppTheme.textSecondary),
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: category.themeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count 项',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: category.themeColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 极简账号卡片 — 对齐 Mac：头像 + 标题/星标 + 分类/密数/标签徽章 + 箭头
class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.item,
    required this.selected,
    required this.store,
    required this.onOpen,
  });

  final AccountItem item;
  final bool selected;
  final VaultStore store;
  final VoidCallback onOpen;

  void _showContextMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetCtx) => _ItemContextMenu(store: store, item: item),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cat = item.category;
    final groupCount = item.passwordGroups.length;
    final entryCount = item.entries.length;
    final tag = item.normalizedCustomTag;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: InkWell(
        key: Key('account_card_${item.id}'),
        onTap: onOpen,
        onLongPress: () => _showContextMenu(context),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? cat.themeColor.withValues(alpha: 0.14)
                : Colors.white.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? cat.themeColor.withValues(alpha: 0.55)
                  : AppTheme.strokeDim,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              _AvatarTile(item: item, size: 38),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        if (item.isFavorite) ...[
                          const SizedBox(width: 5),
                          const Icon(Icons.star_rounded,
                              size: 13, color: AppTheme.starYellow),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _MiniBadge(
                          text: cat.title,
                          color: cat.themeColor,
                        ),
                        if (entryCount > 1 || groupCount > 1) ...[
                          const SizedBox(width: 5),
                          _MiniBadge(
                            text: '$groupCount密 · $entryCount号',
                            color: AppTheme.actionBlue,
                            bold: true,
                          ),
                        ],
                        if (tag.isNotEmpty) ...[
                          const SizedBox(width: 5),
                          _MiniBadge(
                            text: '#$tag',
                            color: AppTheme.tealTag,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded,
                  size: 14,
                  color: selected
                      ? cat.themeColor
                      : AppTheme.textSecondary.withValues(alpha: 0.4)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 智能头像块（对齐 Mac AccountAvatarView 的 3D 玻璃质感）
class _AvatarTile extends StatelessWidget {
  const _AvatarTile({required this.item, required this.size});

  final AccountItem item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tint = item.category.themeColor;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [tint.withValues(alpha: 0.85), tint.withValues(alpha: 0.55)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: tint.withValues(alpha: 0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          item.customIcon.isNotEmpty ? item.customIcon : item.category.iconEmoji,
          style: TextStyle(fontSize: size * 0.48),
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({
    required this.text,
    required this.color,
    this.bold = false,
  });

  final String text;
  final Color color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ────────────────────────── 长按上下文菜单（对齐 Mac contextMenu）──────────────────────────

class _ItemContextMenu extends StatelessWidget {
  const _ItemContextMenu({required this.store, required this.item});

  final VaultStore store;
  final AccountItem item;

  @override
  Widget build(BuildContext context) {
    final totpEntries = item.entries.where((e) => e.hasTOTP).toList();
    final groups = item.passwordGroups;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          if (totpEntries.isNotEmpty)
            for (final entry in totpEntries)
              _MenuRow(
                icon: Icons.shield_outlined,
                label:
                    '复制 2FA：${store.formattedCode(store.codeForEntry(entry))}${totpEntries.length > 1 ? '（${entry.username.isEmpty ? '默认' : entry.username}）' : ''}',
                onTap: () {
                  Navigator.pop(context);
                  store.copyToClipboard(
                    store.codeForEntry(entry),
                    label: '2FA：${store.formattedCode(store.codeForEntry(entry))}',
                  );
                },
              ),
          if (groups.length > 1)
            for (var i = 0; i < groups.length; i++)
              _MenuRow(
                icon: Icons.key_rounded,
                label:
                    '复制密码：${groups[i].password}（#$i+1 · ${groups[i].entries.length}账号）',
                onTap: () {
                  Navigator.pop(context);
                  store.copyToClipboard(groups[i].password,
                      label: '密码：${groups[i].password}');
                },
              )
          else if (item.primaryPassword.isNotEmpty)
            _MenuRow(
              icon: Icons.key_rounded,
              label: '复制 密码：${item.primaryPassword}',
              onTap: () {
                Navigator.pop(context);
                store.copyToClipboard(item.primaryPassword,
                    label: '密码：${item.primaryPassword}');
              },
            ),
          if (item.entries.length > 1)
            for (final entry in item.entries)
              _MenuRow(
                icon: Icons.person_rounded,
                label: entry.username.isEmpty
                    ? '（未填写账号）'
                    : '账号：${entry.username}',
                onTap: () {
                  Navigator.pop(context);
                  store.copyToClipboard(entry.username,
                      label: '账号：${entry.username}');
                },
              )
          else if (item.primaryUsername.isNotEmpty)
            _MenuRow(
              icon: Icons.person_rounded,
              label: '复制 账号：${item.primaryUsername}',
              onTap: () {
                Navigator.pop(context);
                store.copyToClipboard(item.primaryUsername,
                    label: '账号：${item.primaryUsername}');
              },
            ),
          const Divider(height: 14),
          _MenuRow(
            icon: Icons.category_rounded,
            label: '更改所属分类...',
            onTap: () {
              Navigator.pop(context);
              _showCategoryPicker(context);
            },
          ),
          _MenuRow(
            icon: item.isFavorite ? Icons.star_outline_rounded : Icons.star_rounded,
            label: item.isFavorite ? '取消星标收藏' : '设为星标收藏',
            onTap: () {
              Navigator.pop(context);
              store.toggleFavorite(item.id);
            },
          ),
          _MenuRow(
            icon: Icons.edit_rounded,
            label: '编辑记录',
            onTap: () {
              Navigator.pop(context);
              store.showStatusToast('条目编辑器将在 M3 里程碑提供');
            },
          ),
          const Divider(height: 14),
          _MenuRow(
            icon: Icons.delete_outline_rounded,
            label: '删除记录',
            danger: true,
            onTap: () {
              Navigator.pop(context);
              _confirmDelete(context);
            },
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  void _showCategoryPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                '更改所属分类',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
            for (final cat in AccountCategory.values)
              ListTile(
                dense: true,
                leading: Text(cat.iconEmoji, style: const TextStyle(fontSize: 18)),
                title: Text(
                  cat.title,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: cat == item.category
                        ? cat.themeColor
                        : AppTheme.textPrimary,
                    fontWeight:
                        cat == item.category ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                trailing:
                    cat == item.category ? const Icon(Icons.check, size: 18) : null,
                onTap: () {
                  Navigator.pop(sheetCtx);
                  store.updateCategory(item.id, cat);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('确认删除该服务及其下属全部账号？', style: TextStyle(fontSize: 16)),
        content: Text(
          '删除「${item.title}」后，其包含的 ${item.passwordGroups.length} 套密码与 ${item.entries.length} 个账号记录将从本地彻底移除。',
          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              store.deleteItem(item.id);
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.dangerRed),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppTheme.dangerRed : AppTheme.textPrimary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        child: Row(
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────── 空态 ──────────────────────────

class _EmptyStateView extends StatelessWidget {
  const _EmptyStateView({
    required this.store,
    required this.onPasteAdd,
    required this.onSmartAdd,
  });

  final VaultStore store;
  final VoidCallback onPasteAdd;
  final VoidCallback onSmartAdd;

  @override
  Widget build(BuildContext context) {
    final tint = store.currentFilter.tintColor;
    final searching = store.searchQuery.isNotEmpty;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              searching ? Icons.search_off_rounded : Icons.folder_off_outlined,
              size: 30,
              color: tint,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            searching ? '未找到匹配的账号记录' : '「${store.currentFilter.title}」下暂无记录',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            searching
                ? '请尝试更换搜索关键词或切换到「全部账号」。'
                : '可以在此分类下创建第一条账号，或切换其他分类查看。',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              if (store.currentFilter != SidebarFilter.all || searching)
                OutlinedButton(
                  key: const Key('empty_view_all_button'),
                  onPressed: () {
                    store.setFilter(SidebarFilter.all);
                    store.setSearchQuery('');
                  },
                  child: const Text('查看全部账号', style: TextStyle(fontSize: 12.5)),
                ),
              OutlinedButton.icon(
                key: const Key('empty_paste_button'),
                onPressed: onPasteAdd,
                icon: const Icon(Icons.content_paste_rounded, size: 15),
                label: const Text('粘贴剪贴板即存', style: TextStyle(fontSize: 12.5)),
              ),
              FilledButton.icon(
                key: const Key('empty_smart_button'),
                onPressed: onSmartAdd,
                icon: const Icon(Icons.auto_awesome_rounded, size: 15),
                label: const Text('智能识别添加', style: TextStyle(fontSize: 12.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ────────────────────────── 状态 Toast ──────────────────────────
// 已迁移至 status_toast.dart 的全局 StatusToastLayer（MaterialApp.builder 级）

// ────────────────────────── 抽屉侧栏（对齐 Mac sidebarContent）──────────────────────────

class VaultDrawer extends StatelessWidget {
  const VaultDrawer({super.key, required this.store});

  final VaultStore store;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFFF5F9FF),
      child: AnimatedBuilder(
        animation: store,
        builder: (context, _) => SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _brandHeader(),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 12),
                  children: [
                    _sectionHeader('快捷概览'),
                    _filterButton(SidebarFilter.all),
                    _filterButton(SidebarFilter.favorites),
                    _filterButton(SidebarFilter.has2FA),
                    const SizedBox(height: 14),
                    _sectionHeader('按类型分类'),
                    for (final cat in AccountCategory.values)
                      _filterButton(
                        SidebarFilter.forCategory(cat),
                        subtitle: cat.description,
                        emoji: cat.iconEmoji,
                      ),
                    if (store.allCustomTags.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _sectionHeader('自定义子标签'),
                      for (final tag in store.allCustomTags)
                        _filterButton(
                          SidebarFilter.forTag(tag),
                          emoji: '#',
                        ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              _bottomToolbar(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _brandHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: AppTheme.brandGradient,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
            ),
            child: const Icon(Icons.shield_outlined,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'SecretCore',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '极光秘核',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.actionBlue,
                        ),
                      ),
                    ),
                  ],
                ),
                const Text(
                  '纯本地加密 · 零联网',
                  style: TextStyle(
                      fontSize: 10, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          TOTPRing(
            remaining: store.remainingSeconds2FA,
            period: 30,
            size: 28,
            lineWidth: 2.5,
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppTheme.textSecondary.withValues(alpha: 0.85),
        ),
      ),
    );
  }

  Widget _filterButton(SidebarFilter filter,
      {String? subtitle, String? emoji}) {
    final isSelected = store.currentFilter == filter;
    final count = store.countFor(filter);
    final tint = filter.tintColor;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        key: Key('drawer_filter_${filter.kind}_${filter.category?.id ?? filter.tag ?? ''}'),
        onTap: () => store.setFilter(filter),
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? tint.withValues(alpha: 0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: isSelected ? tint.withValues(alpha: 0.35) : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isSelected
                        ? [tint, tint.withValues(alpha: 0.85)]
                        : [tint.withValues(alpha: 0.20), tint.withValues(alpha: 0.10)],
                  ),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Center(
                  child: emoji != null
                      ? Text(emoji,
                          style: TextStyle(
                            fontSize: 12,
                            color: isSelected ? Colors.white : tint,
                          ))
                      : Icon(filter.iconName,
                          size: 13,
                          color: isSelected ? Colors.white : tint),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      filter.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    if (subtitle != null && isSelected)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 9.5, color: AppTheme.textSecondary),
                      ),
                  ],
                ),
              ),
              if (count > 0 || isSelected)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? tint.withValues(alpha: 0.18)
                        : Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? tint : AppTheme.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomToolbar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          _toolButton(
            icon: Icons.auto_fix_high_rounded,
            label: '密码器',
            onTap: () {
              Navigator.pop(context);
              showPasswordGeneratorSheet(context, store: store);
            },
          ),
          const SizedBox(width: 8),
          _toolButton(
            icon: Icons.settings_rounded,
            label: '设置',
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SettingsView(store: store),
                ),
              );
            },
          ),
          const Spacer(),
          InkWell(
            key: const Key('drawer_lock_button'),
            onTap: () {
              Navigator.pop(context);
              store.lockNow();
            },
            borderRadius: BorderRadius.circular(7),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.warnOrange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock_rounded, size: 12, color: AppTheme.warnOrange),
                  SizedBox(width: 4),
                  Text(
                    '锁定',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.warnOrange,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          children: [
            Icon(icon, size: 13, color: AppTheme.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
