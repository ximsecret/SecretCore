import 'package:flutter/material.dart';

/// 浅色赛博实验室主题 — 对齐 Mac 版「Cyber Mission Control · 极光仪表盘」视觉语言
class AppTheme {
  // ── 背景冰川蓝银渐变 ──
  static const Color bgIceTop = Color(0xFFDEEDFC);
  static const Color bgIceMid = Color(0xFFF0F7FF);
  static const Color bgIceBottom = Color(0xFFE0EEFC);

  // ── 品牌蓝 ──
  static const Color primaryBlue = Color(0xFF0D85FA); // (0.05,0.52,0.98)
  static const Color primaryBlueDeep = Color(0xFF3859F2); // (0.22,0.35,0.95)
  static const Color actionBlue = Color(0xFF0F70E0); // (0.06,0.44,0.88)
  static const Color blueGradientEnd = Color(0xFF3859F2);

  // ── 文本 ──
  static const Color textPrimary = Color(0xFF16283E);
  static const Color textSecondary = Color(0xFF5B7089);
  static const Color textFaint = Color(0xFF8CA0B8);

  // ── 表面与描边 ──
  static const Color surfaceCard = Color(0xCCFFFFFF); // 白玻璃
  static const Color surfaceRaised = Color(0xFFF3F8FE);
  static const Color strokeDim = Color(0x14000000); // black 8%
  static const Color strokeSoft = Color(0x0F16283E);

  // ── 语义色 ──
  static const Color successGreen = Color(0xFF16A34A);
  static const Color warnOrange = Color(0xFFF59E0B);
  static const Color dangerRed = Color(0xFFDC2626);
  static const Color starYellow = Color(0xFFFACC15);
  static const Color tealTag = Color(0xFF0D9488);

  static LinearGradient get bgGradient => const LinearGradient(
        colors: [bgIceTop, bgIceMid, bgIceBottom],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static LinearGradient get brandGradient => const LinearGradient(
        colors: [primaryBlue, primaryBlueDeep],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static ThemeData dark() => buildTheme();

  static ThemeData buildTheme() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        brightness: Brightness.light,
      ).copyWith(
        primary: primaryBlue,
        secondary: primaryBlueDeep,
        surface: bgIceMid,
        error: dangerRed,
      ),
      scaffoldBackgroundColor: bgIceMid,
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
      dividerTheme: DividerThemeData(color: strokeDim.withValues(alpha: 1)),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: textPrimary,
        contentTextStyle: TextStyle(color: Colors.white, fontSize: 13),
        behavior: SnackBarBehavior.floating,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.75),
        hintStyle: const TextStyle(color: textFaint, fontSize: 13),
        labelStyle: const TextStyle(color: textSecondary, fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: strokeDim),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: strokeDim),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: primaryBlue, width: 1.4),
        ),
      ),
    );
  }

  /// 白玻璃卡片容器装饰
  static BoxDecoration glassCard({double radius = 14, Color? border}) =>
      BoxDecoration(
        color: surfaceCard,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border ?? strokeDim),
      );

  /// 透视网格背景（对齐 Mac 版浅色赛博实验室）
  static Widget cyberBackground({required Widget child}) {
    return Container(
      decoration: BoxDecoration(gradient: bgGradient),
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.05,
              child: CustomPaint(painter: _GridPainter()),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.primaryBlue
      ..strokeWidth = 0.6;
    const step = 34.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
