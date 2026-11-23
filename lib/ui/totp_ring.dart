import 'package:flutter/material.dart';

import 'app_theme.dart';

/// TOTP 倒计时环 — 数值由 VaultStore 全局单时钟驱动（对齐 Mac 版设计）
class TOTPRing extends StatelessWidget {
  const TOTPRing({
    super.key,
    required this.remaining,
    required this.period,
    this.size = 28,
    this.lineWidth = 2.5,
    this.showSecondsText = true,
  });

  final int remaining;
  final int period;
  final double size;
  final double lineWidth;
  final bool showSecondsText;

  Color get _ringColor {
    if (remaining <= 5) return AppTheme.dangerRed;
    if (remaining / period <= 0.17) return AppTheme.warnOrange;
    return AppTheme.primaryBlue;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: period > 0 ? remaining / period : 0,
              strokeWidth: lineWidth,
              strokeCap: StrokeCap.round,
              color: _ringColor,
              backgroundColor: Colors.grey.withValues(alpha: 0.16),
            ),
          ),
          if (showSecondsText)
            Text(
              '$remaining',
              style: TextStyle(
                color: remaining <= 5 ? AppTheme.dangerRed : AppTheme.textSecondary,
                fontSize: size * 0.32,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}
