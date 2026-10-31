enum NotesLayoutMode {
  single, // 一行单条 (全宽通栏)
  double; // 一行两条 (双列并排)

  String get displayName {
    switch (this) {
      case NotesLayoutMode.single:
        return '一行单条';
      case NotesLayoutMode.double:
        return '一行两条';
    }
  }

  static NotesLayoutMode fromString(String? str) {
    if (str?.toLowerCase() == 'double') {
      return NotesLayoutMode.double;
    }
    return NotesLayoutMode.single;
  }
}
