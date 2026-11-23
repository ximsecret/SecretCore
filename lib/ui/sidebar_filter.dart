import 'package:flutter/material.dart';

import '../core/models/account_category.dart';

/// 侧边栏/胶囊筛选器 — 对齐 Mac 版 SidebarFilter（全部/收藏/含2FA/分类/#标签）
class SidebarFilter {
  const SidebarFilter._(this.kind, [this.category, this.tag]);

  final String kind; // all | favorites | has2FA | category | tag
  final AccountCategory? category;
  final String? tag;

  static const SidebarFilter all = SidebarFilter._('all');
  static const SidebarFilter favorites = SidebarFilter._('favorites');
  static const SidebarFilter has2FA = SidebarFilter._('has2FA');
  static SidebarFilter forCategory(AccountCategory cat) =>
      SidebarFilter._('category', cat);
  static SidebarFilter forTag(String t) => SidebarFilter._('tag', null, t);

  String get title {
    switch (kind) {
      case 'all':
        return '全部账号';
      case 'favorites':
        return '星标收藏';
      case 'has2FA':
        return '2FA 动态码';
      case 'category':
        return category?.title ?? '分类';
      case 'tag':
        return '#${tag ?? ''}';
    }
    return '全部账号';
  }

  String? get subtitle {
    if (kind == 'category') return category?.description;
    if (kind == 'has2FA') return '含实时动态验证码的账号';
    return null;
  }

  Color get tintColor {
    switch (kind) {
      case 'all':
        return const Color(0xFF0D85FA);
      case 'favorites':
        return const Color(0xFFF59E0B);
      case 'has2FA':
        return const Color(0xFF10B981);
      case 'category':
        return category?.themeColor ?? const Color(0xFF0D85FA);
      case 'tag':
        return const Color(0xFF0D9488);
    }
    return const Color(0xFF0D85FA);
  }

  IconData get iconName {
    switch (kind) {
      case 'all':
        return Icons.square_rounded;
      case 'favorites':
        return Icons.star_rounded;
      case 'has2FA':
        return Icons.shield_outlined;
      case 'category':
        return Icons.grid_view_rounded;
      case 'tag':
        return Icons.tag_rounded;
    }
    return Icons.square_rounded;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SidebarFilter) return false;
    return kind == other.kind &&
        category == other.category &&
        tag == other.tag;
  }

  @override
  int get hashCode => Object.hash(kind, category, tag);
}
