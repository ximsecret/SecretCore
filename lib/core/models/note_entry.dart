import 'package:uuid/uuid.dart';

class NoteEntry {
  final String id;
  String label;
  String content;
  DateTime createdAt;

  NoteEntry({
    String? id,
    this.label = '备注',
    this.content = '',
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  String get effectiveLabel {
    final trimmed = label.trim();
    return trimmed.isEmpty ? '备注' : trimmed;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
      };

  factory NoteEntry.fromJson(Map<String, dynamic> json) => NoteEntry(
        id: json['id'] as String?,
        label: (json['label'] as String?) ?? '备注',
        content: (json['content'] as String?) ?? '',
        createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
      );
}
