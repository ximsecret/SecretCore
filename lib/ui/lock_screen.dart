import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/crypto/password_generator.dart';
import 'app_theme.dart';
import 'vault_store.dart';

/// 锁屏 — 浅色全息赛博实验室风格（对齐 Mac 版 LockView）
/// 首次创建保险箱 / 主密码解锁 / Face ID 快捷解锁
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.store, this.animate = true});

  final VaultStore store;

  /// 关闭呼吸动画（测试中传 false 以便 pumpAndSettle 收敛）
  final bool animate;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _confirmFocus = FocusNode();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _obscure = true;
  bool _biometricsAvailable = false;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    if (widget.animate) {
      _pulseController.repeat(reverse: true);
    }
    unawaited(_probeBiometrics());
  }

  Future<void> _probeBiometrics() async {
    final available = await widget.store.canUseBiometrics();
    if (!mounted) return;
    setState(() => _biometricsAvailable = available);
    if (available) {
      unawaited(_tryBiometrics());
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  bool get _isSetup => widget.store.phase == VaultPhase.needsSetup;

  Future<void> _tryBiometrics() async {
    final ok = await widget.store.unlockWithBiometrics();
    if (ok && mounted) HapticFeedback.lightImpact();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final password = _passwordController.text;

    final ok = _isSetup
        ? await widget.store.createVault(password, _confirmController.text)
        : await widget.store.unlockWithPassword(password);

    if (ok && mounted) {
      HapticFeedback.lightImpact();
      _passwordController.clear();
      _confirmController.clear();
    }
  }

  String? _validatePassword(String? value) {
    final text = value ?? '';
    if (_isSetup) {
      if (text.length < 8) return '主密码至少需要 8 位，建议 12 位以上';
      if (text.contains(' ')) return '主密码不能包含空格';
    } else {
      if (text.isEmpty) return '请输入主密码';
    }
    return null;
  }

  String? _validateConfirmation(String? value) {
    if ((value ?? '') != _passwordController.text) {
      return '两次输入的主密码不一致';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: AppTheme.cyberBackground(
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 40),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildEmblem(),
                    const SizedBox(height: 24),
                    Text(
                      _isSetup ? '创建你的密码保险箱' : '保险箱已锁定',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isSetup
                          ? '设置一个强主密码。它将用于加密你的所有数据，\n无法找回，请务必牢记。'
                          : '输入主密码或使用 Face ID 解锁保险箱',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: AppTheme.glassCard(radius: 20),
                      child: Column(
                        children: [
                          if (_isSetup) ...[
                            _buildPasswordField(
                              key: const Key('setup_password_field'),
                              controller: _passwordController,
                              focusNode: _passwordFocus,
                              label: '设置主密码',
                              hint: '至少 8 位，建议 12 位以上',
                              validator: _validatePassword,
                              textInputAction: TextInputAction.next,
                              onFieldSubmitted: (_) =>
                                  _confirmFocus.requestFocus(),
                            ),
                            const SizedBox(height: 16),
                            _buildPasswordField(
                              key: const Key('setup_confirm_field'),
                              controller: _confirmController,
                              focusNode: _confirmFocus,
                              label: '确认主密码',
                              hint: '再次输入相同的主密码',
                              validator: _validateConfirmation,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _submit(),
                            ),
                            const SizedBox(height: 18),
                            PasswordStrengthMeter(
                                password: _passwordController.text),
                          ] else
                            _buildPasswordField(
                              key: const Key('unlock_password_field'),
                              controller: _passwordController,
                              focusNode: _passwordFocus,
                              label: '主密码',
                              hint: '输入主密码解锁',
                              validator: _validatePassword,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _submit(),
                            ),
                          if (store.lastError != null) ...[
                            const SizedBox(height: 16),
                            _buildErrorBanner(store.lastError!),
                          ],
                          const SizedBox(height: 20),
                          _buildPrimaryButton(store),
                          if (!_isSetup && _biometricsAvailable) ...[
                            const SizedBox(height: 12),
                            _buildFaceIdButton(),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (!_isSetup)
                      Text(
                        '主密码无法找回 · 忘记即永久失去全部数据',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.textSecondary.withValues(alpha: 0.8),
                          fontSize: 12,
                        ),
                      ),
                    const SizedBox(height: 18),
                    Text(
                      'SecretCore · 极光秘核\n纯本地离线密码与 2FA (TOTP) 一体化管理工具 · 零网络权限',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.textSecondary.withValues(alpha: 0.65),
                        fontSize: 11,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmblem() {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.85, end: 1.0).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
      ),
      child: const _HoloCrystalEmblem(),
    );
  }

  Widget _buildPasswordField({
    required Key key,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required String hint,
    required FormFieldValidator<String> validator,
    required TextInputAction textInputAction,
    required ValueChanged<String> onFieldSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          key: key,
          controller: controller,
          focusNode: focusNode,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: _isSetup ? null : const [AutofillHints.password],
          textInputAction: textInputAction,
          onFieldSubmitted: onFieldSubmitted,
          onChanged: (_) => setState(() {}),
          validator: validator,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
          decoration: InputDecoration(
            hintText: hint,
            suffixIcon: IconButton(
              icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: AppTheme.textSecondary,
                size: 22,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.dangerRed.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: AppTheme.dangerRed.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppTheme.dangerRed, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppTheme.dangerRed, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryButton(VaultStore store) {
    final busy = store.unlocking;
    return FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        backgroundColor: AppTheme.primaryBlue,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
      onPressed: busy ? null : _submit,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: busy
            ? const SizedBox(
                key: ValueKey('loading'),
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                ),
              )
            : Text(
                _isSetup ? '创建保险箱' : '解锁',
                key: const ValueKey('label'),
                style: const TextStyle(
                    fontSize: 15.5, fontWeight: FontWeight.w700),
              ),
      ),
    );
  }

  Widget _buildFaceIdButton() {
    return OutlinedButton.icon(
      onPressed: widget.store.authenticating ? null : _tryBiometrics,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.primaryBlue,
        side: const BorderSide(color: AppTheme.strokeDim),
        backgroundColor: Colors.white.withValues(alpha: 0.6),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
      icon: const Icon(Icons.face_outlined, size: 22),
      label: Text(widget.store.authenticating ? '验证中…' : '使用 Face ID 解锁'),
    );
  }
}

/// 密码强度指示条
class PasswordStrengthMeter extends StatelessWidget {
  const PasswordStrengthMeter({super.key, required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final strength = PasswordGenerator.evaluateStrength(password);
    final entropy = PasswordGenerator.calculateEntropy(password);
    final (color, label) = switch (strength) {
      PasswordStrength.weak => (AppTheme.dangerRed, '弱'),
      PasswordStrength.medium => (AppTheme.warnOrange, '中'),
      PasswordStrength.strong => (AppTheme.successGreen, '强'),
      PasswordStrength.veryStrong => (AppTheme.primaryBlue, '极强'),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (entropy / 128).clamp(0.0, 1.0),
            minHeight: 5,
            backgroundColor: AppTheme.surfaceRaised,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          password.isEmpty
              ? '熵值评估将在此实时显示'
              : '强度：$label · ${entropy.toStringAsFixed(0)} bits',
          style: TextStyle(
            color: password.isEmpty ? AppTheme.textSecondary : color,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

/// 全息白水晶徽标 — 使用 GitHub 仓库 Resources/AppIcon.iconset 真实应用图标
class _HoloCrystalEmblem extends StatelessWidget {
  const _HoloCrystalEmblem();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 96,
        height: 96,
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.65), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryBlue.withValues(alpha: 0.30),
              blurRadius: 34,
              spreadRadius: 1,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Image.asset(
            'assets/brand/app_icon.png',
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    );
  }
}
