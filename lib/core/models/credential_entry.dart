import 'package:uuid/uuid.dart';
import '../totp/totp_engine.dart';
import 'labeled_password.dart';

class CredentialEntry {
  final String id;
  String accountLabel;
  String username;
  String passwordLabel;
  String password;
  List<LabeledPassword> extraPasswords;
  String totpSecret;
  int totpDigits;
  int totpPeriod;
  TOTPAlgorithm totpAlgorithm;
  String notes;
  DateTime createdAt;
  DateTime updatedAt;

  CredentialEntry({
    String? id,
    this.accountLabel = '账号',
    this.username = '',
    this.passwordLabel = '密码',
    this.password = '',
    List<LabeledPassword>? extraPasswords,
    this.totpSecret = '',
    this.totpDigits = 6,
    this.totpPeriod = 30,
    this.totpAlgorithm = TOTPAlgorithm.sha1,
    this.notes = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        extraPasswords = extraPasswords ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  String get effectiveAccountLabel {
    final trimmed = accountLabel.trim();
    return trimmed.isEmpty ? '账号' : trimmed;
  }

  String get effectivePasswordLabel {
    final trimmed = passwordLabel.trim();
    return trimmed.isEmpty ? '密码' : trimmed;
  }

  bool get hasTOTP => totpSecret.trim().isNotEmpty;
  bool get hasPassword => password.isNotEmpty || extraPasswords.isNotEmpty;

  List<LabeledPassword> get allPasswords {
    final list = <LabeledPassword>[];
    if (password.isNotEmpty || extraPasswords.isEmpty) {
      list.add(LabeledPassword(
        id: '${id}_main_pwd',
        label: effectivePasswordLabel,
        value: password,
        createdAt: createdAt,
      ));
    }
    list.addAll(extraPasswords);
    return list;
  }

  void clearTOTP() {
    totpSecret = '';
    updatedAt = DateTime.now();
  }

  void addExtraPassword({String label = '密码', String value = ''}) {
    extraPasswords.add(LabeledPassword(label: label, value: value));
    updatedAt = DateTime.now();
  }

  void removeExtraPassword(String passwordId) {
    extraPasswords.removeWhere((p) => p.id == passwordId);
    updatedAt = DateTime.now();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'accountLabel': accountLabel,
        'username': username,
        'passwordLabel': passwordLabel,
        'password': password,
        'extraPasswords': extraPasswords.map((p) => p.toJson()).toList(),
        'totpSecret': totpSecret,
        'totpDigits': totpDigits,
        'totpPeriod': totpPeriod,
        'totpAlgorithm': totpAlgorithm.name,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory CredentialEntry.fromJson(Map<String, dynamic> json) {
    return CredentialEntry(
      id: json['id'] as String?,
      accountLabel: (json['accountLabel'] as String?) ?? '账号',
      username: (json['username'] as String?) ?? '',
      passwordLabel: (json['passwordLabel'] as String?) ?? '密码',
      password: (json['password'] as String?) ?? '',
      extraPasswords: (json['extraPasswords'] as List<dynamic>?)
              ?.map((e) => LabeledPassword.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      totpSecret: (json['totpSecret'] as String?) ?? '',
      totpDigits: (json['totpDigits'] as int?) ?? 6,
      totpPeriod: (json['totpPeriod'] as int?) ?? 30,
      totpAlgorithm: TOTPAlgorithm.fromString(json['totpAlgorithm'] as String? ?? 'sha1'),
      notes: (json['notes'] as String?) ?? '',
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
      updatedAt: json['updatedAt'] != null ? DateTime.tryParse(json['updatedAt'] as String) : null,
    );
  }
}
