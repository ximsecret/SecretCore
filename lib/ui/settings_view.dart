import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'vault_store.dart';

/// 应用版本信息（与 pubspec.yaml version 保持同步）
const String kAppVersion = '1.0.0+1';
const String kRepoUrl = 'github.com/ximsecret/SecretCore';

/// 设置与关于页 — 对齐 Mac 版 SettingsView：
/// 安全策略说明（仅手动锁定）、纯本地数据说明、剪贴板策略、版本与开源信息。
class SettingsView extends StatelessWidget {
  const SettingsView({super.key, required this.store});

  final VaultStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgIceMid,
      appBar: AppBar(title: const Text('设置')),
      body: AppTheme.cyberBackground(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSecurityCard(context),
            const SizedBox(height: 14),
            _buildDataCard(context),
            const SizedBox(height: 14),
            _buildAboutCard(context),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── 安全 ──

  Widget _buildSecurityCard(BuildContext context) {
    return _SettingsCard(
      title: '安全',
      icon: Icons.shield_outlined,
      tint: AppTheme.primaryBlue,
      children: [
        _SettingsRow(
          icon: Icons.lock_outline_rounded,
          iconColor: AppTheme.primaryBlue,
          title: '立即锁定',
          subtitle: '返回锁屏界面，需主密码或 Face ID 重新解锁',
          trailing: const Icon(Icons.chevron_right_rounded,
              color: AppTheme.textFaint),
          onTap: () {
            Navigator.of(context).pop();
            store.lockNow(message: '已手动锁定保险箱');
          },
        ),
        const Divider(height: 1),
        const _SettingsRow(
          icon: Icons.info_outline_rounded,
          iconColor: AppTheme.tealTag,
          title: '仅手动锁定',
          subtitle: '应用不启用后台自动锁定：切到后台、息屏均不会锁定，'
              '仅在主动点击「立即锁定」或系统重启后回到锁屏。请养成随手锁定的习惯。',
        ),
        const Divider(height: 1),
        const _SettingsRow(
          icon: Icons.content_paste_off_rounded,
          iconColor: AppTheme.warnOrange,
          title: '剪贴板保护',
          subtitle: '复制账号、密码或 2FA 动态码后 30 秒自动清空剪贴板，'
              '避免敏感信息残留在系统剪贴板中。',
        ),
      ],
    );
  }

  // ── 数据 ──

  Widget _buildDataCard(BuildContext context) {
    return _SettingsCard(
      title: '数据',
      icon: Icons.storage_rounded,
      tint: AppTheme.tealTag,
      children: [
        const _SettingsRow(
          icon: Icons.wifi_off_rounded,
          iconColor: AppTheme.successGreen,
          title: '纯本地离线 · 零联网',
          subtitle: '应用不接入任何云端服务，不发起任何网络请求。'
              '所有数据仅保存在本机。',
        ),
        const Divider(height: 1),
        const _SettingsRow(
          icon: Icons.enhanced_encryption_rounded,
          iconColor: AppTheme.primaryBlueDeep,
          title: '加密存储',
          subtitle: '保险箱使用主密码派生密钥（Argon2/PBKDF2）做 AES 加密，'
              '磁盘上只有一份密文文件，主密码不落盘、不可找回。',
        ),
        const Divider(height: 1),
        AnimatedBuilder(
          animation: store,
          builder: (context, _) {
            final items = store.items.length;
            var entries = 0;
            var totp = 0;
            for (final item in store.items) {
              entries += item.entries.length;
              for (final e in item.entries) {
                if (e.totpSecret.trim().isNotEmpty) totp++;
              }
            }
            return _SettingsRow(
              icon: Icons.inventory_2_outlined,
              iconColor: AppTheme.actionBlue,
              title: '当前保险箱',
              subtitle: '$items 个条目 · $entries 组账号 · $totp 个 2FA 动态码密钥',
            );
          },
        ),
      ],
    );
  }

  // ── 关于 ──

  Widget _buildAboutCard(BuildContext context) {
    return _SettingsCard(
      title: '关于',
      icon: Icons.info_outline_rounded,
      tint: AppTheme.primaryBlueDeep,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: AppTheme.brandGradient,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.28),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.shield_outlined,
                    color: Colors.white, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Text(
                          'SecretCore',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        SizedBox(width: 6),
                        _PillBadge(text: '极光秘核'),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '版本 $kAppVersion · 纯本地离线密码与 2FA 管理工具',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        const _SettingsRow(
          icon: Icons.code_rounded,
          iconColor: AppTheme.textSecondary,
          title: '开源仓库',
          subtitle: kRepoUrl,
        ),
        const Divider(height: 1),
        const _SettingsRow(
          icon: Icons.article_outlined,
          iconColor: AppTheme.textSecondary,
          title: '技术栈',
          subtitle: 'Flutter 跨平台 · 核心加密逻辑复用 SecretCore Dart 实现，'
              '与 Mac 版同一套算法与数据格式。',
        ),
      ],
    );
  }
}

// ────────────────────────── 通用小组件 ──────────────────────────

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.icon,
    required this.tint,
    required this.children,
  });

  final String title;
  final IconData icon;
  final Color tint;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.glassCard(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Icon(icon, size: 15, color: tint),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: tint,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppTheme.strokeDim),
          ...children,
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 6),
            trailing!,
          ],
        ],
      ),
    );

    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

class _PillBadge extends StatelessWidget {
  const _PillBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.primaryBlue.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppTheme.actionBlue,
        ),
      ),
    );
  }
}
