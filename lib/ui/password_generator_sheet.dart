import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/crypto/password_generator.dart';
import 'app_theme.dart';
import 'vault_store.dart';

/// 打开密码生成器面板；传入 [store] 时复制走全局绿胶囊 Toast。
/// 「使用此密码」返回生成的密码字符串，取消返回 null。
Future<String?> showPasswordGeneratorSheet(
  BuildContext context, {
  VaultStore? store,
  int initialLength = 18,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => PasswordGeneratorSheet(
      store: store,
      initialLength: initialLength,
    ),
  );
}

class PasswordGeneratorSheet extends StatefulWidget {
  const PasswordGeneratorSheet({
    super.key,
    this.store,
    this.initialLength = 18,
  });

  final VaultStore? store;
  final int initialLength;

  @override
  State<PasswordGeneratorSheet> createState() => _PasswordGeneratorSheetState();
}

class _PasswordGeneratorSheetState extends State<PasswordGeneratorSheet> {
  late double _length;
  bool _upper = true;
  bool _lower = true;
  bool _digits = true;
  bool _symbols = true;
  bool _avoidAmbiguous = true;
  String _password = '';

  @override
  void initState() {
    super.initState();
    _length = widget.initialLength.clamp(8, 64).toDouble();
    _regenerate();
  }

  void _regenerate() {
    setState(() {
      _password = PasswordGenerator.generate(
        length: _length.round(),
        includeUppercase: _upper,
        includeLowercase: _lower,
        includeDigits: _digits,
        includeSymbols: _symbols,
        avoidAmbiguous: _avoidAmbiguous,
      );
    });
  }

  (String, Color) _strengthInfo(String pwd) {
    if (pwd.isEmpty) return ('未设置', AppTheme.textSecondary);
    final bits = PasswordGenerator.calculateEntropy(pwd).round();
    switch (PasswordGenerator.evaluateStrength(pwd)) {
      case PasswordStrength.weak:
        return ('弱 · $bits bits', AppTheme.dangerRed);
      case PasswordStrength.medium:
        return ('中等 · $bits bits', AppTheme.warnOrange);
      case PasswordStrength.strong:
        return ('强 · $bits bits', const Color(0xFF0C8C61));
      case PasswordStrength.veryStrong:
        return ('极强 · $bits bits', AppTheme.primaryBlue);
    }
  }

  void _copyGenerated() {
    if (widget.store != null) {
      widget.store!.copyToClipboard(_password, label: '密码：$_password');
    } else {
      Clipboard.setData(ClipboardData(text: _password));
    }
  }

  @override
  Widget build(BuildContext context) {
    final (strengthLabel, strengthColor) = _strengthInfo(_password);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF5F9FF),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 标题栏 ──
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: AppTheme.brandGradient,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(Icons.casino_rounded,
                        color: Colors.white, size: 19),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '密码生成器',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        size: 20, color: AppTheme.textSecondary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── 生成结果展示 ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: AppTheme.glassCard(radius: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      _password,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: strengthColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        strengthLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: strengthColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ── 长度滑杆 ──
              Row(
                children: [
                  const Text('长度',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary)),
                  Expanded(
                    child: Slider(
                      value: _length,
                      min: 8,
                      max: 64,
                      divisions: 56,
                      activeColor: AppTheme.primaryBlue,
                      label: '${_length.round()}',
                      onChanged: (v) {
                        _length = v;
                        _regenerate();
                      },
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${_length.round()} 位',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primaryBlue)),
                  ),
                ],
              ),

              // ── 字符集开关 ──
              _switchTile('大写字母 A-Z', _upper, (v) {
                _upper = v;
                _regenerate();
              }),
              _switchTile('小写字母 a-z', _lower, (v) {
                _lower = v;
                _regenerate();
              }),
              _switchTile('数字 0-9', _digits, (v) {
                _digits = v;
                _regenerate();
              }),
              _switchTile('符号 !@#\$…', _symbols, (v) {
                _symbols = v;
                _regenerate();
              }),
              _switchTile('排除易混淆字符（0O1lI）', _avoidAmbiguous, (v) {
                _avoidAmbiguous = v;
                _regenerate();
              }),
              const SizedBox(height: 14),

              // ── 操作按钮 ──
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      key: const Key('gen_refresh_button'),
                      onTap: _regenerate,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.refresh_rounded,
                                size: 16, color: AppTheme.textSecondary),
                            SizedBox(width: 5),
                            Text('重新生成',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textSecondary)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      key: const Key('gen_copy_button'),
                      onTap: _copyGenerated,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppTheme.actionBlue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.copy_rounded,
                                size: 15, color: AppTheme.actionBlue),
                            SizedBox(width: 5),
                            Text('复制',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.actionBlue)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      key: const Key('gen_use_button'),
                      onTap: () => Navigator.pop(context, _password),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: AppTheme.brandGradient,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text('使用此密码',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _switchTile(String label, bool value, ValueChanged<bool> onChanged) {
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary)),
          ),
          SizedBox(
            height: 26,
            child: Switch(
              value: value,
              activeThumbColor: AppTheme.primaryBlue,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
