import 'credential_entry.dart';

class PasswordCredentialGroup {
  final String password;
  final String passwordLabel;
  final List<CredentialEntry> entries;

  PasswordCredentialGroup({
    required this.password,
    this.passwordLabel = '密码',
    required this.entries,
  });

  int get accountCount => entries.length;

  String get effectivePasswordLabel {
    final entryLabel = entries.firstOrNull?.effectivePasswordLabel;
    if (entryLabel != null && entryLabel.isNotEmpty) {
      return entryLabel;
    }
    final trimmed = passwordLabel.trim();
    return trimmed.isEmpty ? '密码' : trimmed;
  }
}
