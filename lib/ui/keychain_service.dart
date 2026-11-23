import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

class BiometricsNotAvailableException implements Exception {
  final String message;
  BiometricsNotAvailableException(this.message);
  @override
  String toString() => message;
}

class BiometricsAuthFailedException implements Exception {
  final String message;
  BiometricsAuthFailedException(this.message);
  @override
  String toString() => message;
}

/// iOS Keychain 托管服务。
///
/// 主密码通过自定义 MethodChannel (`vault.keychain`) 存入 iOS Keychain，
/// 条目属性为 kSecAttrAccessibleWhenUnlockedThisDeviceOnly +
/// kSecAttrAccessControl(biometryCurrentSet)，读取自动触发 Face ID / Touch ID。
/// 在未实现该通道的平台（macOS/Windows 桌面）上所有方法安全降级。
class KeychainService {
  static const MethodChannel _channel = MethodChannel('vault.keychain');

  final LocalAuthentication _localAuth = LocalAuthentication();

  /// 设备是否配置了 Face ID / Touch ID
  Future<bool> canCheckBiometrics() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      return supported && canCheck;
    } catch (_) {
      return false;
    }
  }

  /// 发起一次生物识别验证
  Future<bool> authenticate() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: '验证身份以访问密码保险箱',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException catch (e) {
      switch (e.code) {
        case LocalAuthExceptionCode.noCredentialsSet:
        case LocalAuthExceptionCode.noBiometricsEnrolled:
        case LocalAuthExceptionCode.noBiometricHardware:
        case LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable:
          throw BiometricsNotAvailableException('设备未配置生物识别');
        default:
          throw BiometricsAuthFailedException('验证失败：${e.code.name}');
      }
    } catch (_) {
      return false;
    }
  }

  /// 是否已托管主密码
  Future<bool> hasMasterPassword() async {
    try {
      final result = await _channel.invokeMethod<bool>('hasMasterPassword');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 将主密码写入 Keychain（写入前要求一次生物识别确认身份）
  Future<bool> storeMasterPassword(String password) async {
    if (!await canCheckBiometrics()) {
      throw BiometricsNotAvailableException('设备未配置 Face ID / Touch ID');
    }
    final authed = await authenticate();
    if (!authed) return false;

    try {
      final result = await _channel
          .invokeMethod<bool>('storeMasterPassword', {'password': password});
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 读取托管的主密码（Keychain 访问控制自动触发 Face ID）
  Future<String?> readMasterPassword() async {
    try {
      final result = await _channel.invokeMethod<String>('readMasterPassword');
      return result;
    } on PlatformException catch (e) {
      if (e.code == 'authFailed') {
        throw BiometricsAuthFailedException('生物识别未通过');
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 删除托管的密码
  Future<bool> deleteMasterPassword() async {
    try {
      final result = await _channel.invokeMethod<bool>('deleteMasterPassword');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }
}
