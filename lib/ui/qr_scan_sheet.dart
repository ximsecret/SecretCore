import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/totp/totp_engine.dart';
import 'app_theme.dart';

/// 扫码结果：解析 otpauth:// 后用于回填编辑器的字段值
class OtpAuthFill {
  const OtpAuthFill({
    required this.secret,
    this.issuer = '',
    this.account = '',
    this.digits = 6,
    this.period = 30,
    this.algorithm = TOTPAlgorithm.sha1,
  });

  final String secret;
  final String issuer;
  final String account;
  final int digits;
  final int period;
  final TOTPAlgorithm algorithm;

  factory OtpAuthFill.fromParsed(ParsedOTPAuth p) => OtpAuthFill(
        secret: p.secret,
        issuer: p.issuer,
        account: p.account,
        digits: p.digits,
        period: p.period,
        algorithm: p.algorithm,
      );
}

/// 从二维码内容提取 otpauth 填充值；非 otpauth 内容返回 null
OtpAuthFill? parseQrPayload(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final parsed = TOTPEngine.parseOTPAuthURI(raw.trim());
  if (parsed == null) return null;
  return OtpAuthFill.fromParsed(parsed);
}

/// 打开相机扫码页，返回解析后的 otpauth 填充值；取消 / 无法识别返回 null。
/// 仅移动端调用（Web 端相机能力受限，编辑器内不展示扫码入口）。
Future<OtpAuthFill?> openQrScanSheet(BuildContext context) {
  return Navigator.of(context).push<OtpAuthFill>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const QrScanPage(),
    ),
  );
}

class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key});

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;
  String? _error;
  final TextEditingController _manualC = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    _manualC.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final fill = parseQrPayload(barcode.rawValue);
      if (fill != null) {
        _handled = true;
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(fill);
        return;
      }
    }
  }

  void _manualApply() {
    final fill = parseQrPayload(_manualC.text);
    if (fill == null) {
      setState(() => _error = '内容不是有效的 otpauth:// 链接');
      return;
    }
    Navigator.of(context).pop(fill);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('扫码导入 2FA'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: '切换闪光灯',
            icon: const Icon(Icons.flash_on_rounded),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              return _FallbackPanel(
                manualC: _manualC,
                error: _error,
                onApply: _manualApply,
                message: '相机不可用（权限或模拟器），可粘贴 otpauth:// 链接导入',
              );
            },
          ),
          // 取景框
          IgnorePointer(
            child: Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.9),
                    width: 2.5,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 28,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '将 2FA 二维码对准取景框，识别后自动返回并填入密钥',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 12.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 相机不可用时的手动粘贴回退面板
class _FallbackPanel extends StatelessWidget {
  const _FallbackPanel({
    required this.manualC,
    required this.error,
    required this.onApply,
    required this.message,
  });

  final TextEditingController manualC;
  final String? error;
  final VoidCallback onApply;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined,
                color: Colors.white54, size: 42),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: manualC,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'otpauth://totp/...?secret=...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                errorText: error,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onApply,
              icon: const Icon(Icons.download_rounded, size: 16),
              label: const Text('导入'),
            ),
          ],
        ),
      ),
    );
  }
}
