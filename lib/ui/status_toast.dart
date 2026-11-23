import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'vault_store.dart';

/// 全局状态 Toast 层 — 挂载于 MaterialApp.builder，覆盖所有路由
/// 对齐 Mac 版窗口级 clipboardStatusMessage 绿胶囊（复制成功 → 定时自动清空提示）
class StatusToastLayer extends StatelessWidget {
  const StatusToastLayer({super.key, required this.store});

  final VaultStore store;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final message = store.clipboardStatusMessage;
        final insets = MediaQuery.of(context);
        final bottom = (insets.viewInsets.bottom > insets.padding.bottom
                ? insets.viewInsets.bottom
                : insets.padding.bottom) +
            18;
        return IgnorePointer(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: bottom),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                transitionBuilder: (child, anim) => SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.4),
                    end: Offset.zero,
                  ).animate(anim),
                  child: FadeTransition(opacity: anim, child: child),
                ),
                child: message == null
                    ? const SizedBox.shrink(key: ValueKey('toast-empty'))
                    : StatusToast(
                        key: ValueKey(message),
                        message: message,
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 绿色玻璃胶囊 Toast 本体
class StatusToast extends StatelessWidget {
  const StatusToast({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final icon = message.startsWith('安全防护')
        ? Icons.verified_user_rounded
        : Icons.check_circle_rounded;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppTheme.successGreen.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppTheme.successGreen),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
