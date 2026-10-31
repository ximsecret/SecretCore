import 'package:uuid/uuid.dart';

class LabeledPassword {
  final String id;
  String label;
  String value;
  DateTime createdAt;

  LabeledPassword({
    String? id,
    this.label = '密码',
    this.value = '',
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  String get effectiveLabel {
    final trimmed = label.trim();
    return trimmed.isEmpty ? '密码' : trimmed;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'value': value,
        'createdAt': createdAt.toIso8601String(),
      };

  factory LabeledPassword.fromJson(Map<String, dynamic> json) => LabeledPassword(
        id: json['id'] as String?,
        label: (json['label'] as String?) ?? '密码',
        value: (json['value'] as String?) ?? '',
        createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
      );
}
