import 'package:uuid/uuid.dart';
import 'account_category.dart';
import 'credential_entry.dart';
import 'note_entry.dart';
import 'notes_layout_mode.dart';
import 'password_credential_group.dart';

class AccountItem {
  final String id;
  String title;
  String url;
  AccountCategory category;
  String customTag;
  String customIcon;
  bool isFavorite;
  List<CredentialEntry> entries;
  List<NoteEntry> noteEntries;
  NotesLayoutMode notesLayout;
  Map<String, String> customFields;
  DateTime createdAt;
  DateTime updatedAt;

  AccountItem({
    String? id,
    this.title = '',
    this.url = '',
    this.category = AccountCategory.general,
    this.customTag = '',
    this.customIcon = '',
    this.isFavorite = false,
    List<CredentialEntry>? entries,
    List<NoteEntry>? noteEntries,
    this.notesLayout = NotesLayoutMode.single,
    Map<String, String>? customFields,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        entries = entries ?? [CredentialEntry()],
        noteEntries = noteEntries ?? [],
        customFields = customFields ?? {},
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  bool get hasTOTP => entries.any((e) => e.hasTOTP);

  String get firstTOTPSecret => entries.firstWhere((e) => e.hasTOTP, orElse: () => entries.first).totpSecret;

  String get primaryUsername => entries.firstOrNull?.username ?? '';
  String get primaryPassword => entries.firstOrNull?.password ?? '';

  List<NoteEntry> get effectiveNoteEntries {
    return noteEntries;
  }

  /// 按密码归组（同密码下挂载多个账号）
  List<PasswordCredentialGroup> get passwordGroups {
    final Map<String, List<CredentialEntry>> grouped = {};
    for (final entry in entries) {
      final pwd = entry.password;
      grouped.putIfAbsent(pwd, () => []).add(entry);
    }

    final groups = <PasswordCredentialGroup>[];
    grouped.forEach((pwd, entryList) {
      final label = entryList.firstOrNull?.effectivePasswordLabel ?? '密码';
      groups.add(PasswordCredentialGroup(
        password: pwd,
        passwordLabel: label,
        entries: entryList,
      ));
    });
    return groups;
  }

  void clearEntryTOTP(String entryId) {
    for (final entry in entries) {
      if (entry.id == entryId) {
        entry.clearTOTP();
      }
    }
    updatedAt = DateTime.now();
  }

  void removeEntry(String entryId) {
    entries.removeWhere((e) => e.id == entryId);
    if (entries.isEmpty) {
      entries.add(CredentialEntry());
    }
    updatedAt = DateTime.now();
  }

  void addOrUpdateEntry(CredentialEntry entry) {
    final index = entries.indexWhere((e) => e.id == entry.id);
    if (index >= 0) {
      entries[index] = entry;
    } else {
      entries.add(entry);
    }
    updatedAt = DateTime.now();
  }

  void updateNotesLayout(NotesLayoutMode layout) {
    notesLayout = layout;
    updatedAt = DateTime.now();
  }

  void updateNoteEntries(List<NoteEntry> list) {
    noteEntries = list;
    updatedAt = DateTime.now();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'url': url,
        'category': category.id,
        'customTag': customTag,
        'customIcon': customIcon,
        'isFavorite': isFavorite,
        'entries': entries.map((e) => e.toJson()).toList(),
        'noteEntries': noteEntries.map((n) => n.toJson()).toList(),
        'notesLayout': notesLayout.name,
        'customFields': customFields,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory AccountItem.fromJson(Map<String, dynamic> json) {
    final entriesRaw = json['entries'] as List<dynamic>?;
    final entries = entriesRaw != null
        ? entriesRaw.map((e) => CredentialEntry.fromJson(e as Map<String, dynamic>)).toList()
        : <CredentialEntry>[
            CredentialEntry(
              username: (json['username'] as String?) ?? '',
              password: (json['password'] as String?) ?? '',
              totpSecret: (json['totpSecret'] as String?) ?? '',
            )
          ];

    final notesRaw = json['noteEntries'] as List<dynamic>?;
    final noteEntries = notesRaw != null
        ? notesRaw.map((n) => NoteEntry.fromJson(n as Map<String, dynamic>)).toList()
        : <NoteEntry>[];

    // 如果旧版只有 notes 字符串，转换为 noteEntries
    if (noteEntries.isEmpty && json['notes'] != null) {
      final oldNotes = (json['notes'] as String).trim();
      if (oldNotes.isNotEmpty) {
        final lines = oldNotes.split('\n');
        for (final line in lines) {
          final trimmedLine = line.trim();
          if (trimmedLine.isEmpty) continue;
          if (trimmedLine.contains('：') || trimmedLine.contains(':')) {
            final parts = trimmedLine.split(RegExp(r'[:：]'));
            noteEntries.add(NoteEntry(
              label: parts[0].trim().isEmpty ? '备注' : parts[0].trim(),
              content: parts.sublist(1).join(':').trim(),
            ));
          } else {
            noteEntries.add(NoteEntry(label: '备注', content: trimmedLine));
          }
        }
      }
    }

    return AccountItem(
      id: json['id'] as String?,
      title: (json['title'] as String?) ?? '',
      url: (json['url'] as String?) ?? '',
      category: AccountCategory.fromString(json['category'] as String?),
      customTag: (json['customTag'] as String?) ?? '',
      customIcon: (json['customIcon'] as String?) ?? '',
      isFavorite: (json['isFavorite'] as bool?) ?? false,
      entries: entries.isEmpty ? [CredentialEntry()] : entries,
      noteEntries: noteEntries,
      notesLayout: NotesLayoutMode.fromString(json['notesLayout'] as String?),
      customFields: (json['customFields'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, v.toString()),
          ) ??
          {},
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
      updatedAt: json['updatedAt'] != null ? DateTime.tryParse(json['updatedAt'] as String) : null,
    );
  }
}
