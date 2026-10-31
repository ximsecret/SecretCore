import 'package:flutter/material.dart';

enum AccountCategory {
  crypto('crypto', '加密与交易', '🪙', Color(0xFFF59E0B), '交易所、Web3 钱包、行情平台'),
  work('work', '开发与工作', '💻', Color(0xFF6366F1), 'GitHub、服务器、代码仓库、工作台'),
  ai('ai', 'AI与云服务', '🪄', Color(0xFFA855F7), 'OpenAI、Claude、云算力与 API'),
  finance('finance', '金融与支付', '💳', Color(0xFF10B981), '银行卡、券商、支付与账单'),
  social('social', '社交与邮箱', '💬', Color(0xFFEC4899), '邮箱、Apple ID、社交媒体'),
  general('general', '常规网站', '🌐', Color(0xFF0EA5E9), '日常网站、论坛、通用账号'),
  other('other', '其他记录', '📁', Color(0xFF64748B), '软件激活码、安全备忘与其它');

  final String id;
  final String title;
  final String iconEmoji;
  final Color themeColor;
  final String description;

  const AccountCategory(
    this.id,
    this.title,
    this.iconEmoji,
    this.themeColor,
    this.description,
  );

  static AccountCategory fromString(String? str) {
    if (str == null) return AccountCategory.general;
    final lower = str.toLowerCase().trim();
    for (final cat in AccountCategory.values) {
      if (cat.id == lower || cat.title == str) {
        return cat;
      }
    }
    return AccountCategory.general;
  }
}
