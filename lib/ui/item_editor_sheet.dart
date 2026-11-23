import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/crypto/password_generator.dart';
import '../core/models/account_category.dart';
import '../core/models/account_item.dart';
import '../core/models/credential_entry.dart';
import '../core/models/labeled_password.dart';
import '../core/models/note_entry.dart';
import '../core/models/notes_layout_mode.dart';
import '../core/parser/smart_credential_parser.dart';
import '../core/totp/totp_engine.dart';
import 'app_theme.dart';
import 'password_generator_sheet.dart';
import 'qr_scan_sheet.dart';
import 'vault_store.dart';

/// 打开条目编辑器（对齐 Mac 版 ItemEditorSheet）。
/// [editingItem] 为空时是「智能识别添加」新建模式，否则是编辑更新模式。
Future<void> openItemEditor(
  BuildContext context, {
  required VaultStore store,
  AccountItem? editingItem,
  AccountCategory defaultCategory = AccountCategory.general,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ItemEditorPage(
        store: store,
        editingItem: editingItem,
        defaultCategory: defaultCategory,
      ),
    ),
  );
}

class ItemEditorPage extends StatefulWidget {
  const ItemEditorPage({
    super.key,
    required this.store,
    this.editingItem,
    this.defaultCategory = AccountCategory.general,
  });

  final VaultStore store;
  final AccountItem? editingItem;
  final AccountCategory defaultCategory;

  @override
  State<ItemEditorPage> createState() => _ItemEditorPageState();
}

class _ItemEditorPageState extends State<ItemEditorPage> {
  // 智能识别与基础信息（控制器在 State 生命周期持有，避免重建打断输入）
  final TextEditingController _rawC = TextEditingController();
  final TextEditingController _titleC = TextEditingController();
  final TextEditingController _urlC = TextEditingController();
  final TextEditingController _freeNoteC = TextEditingController();

  // 当前子账号绑定字段
  final TextEditingController _accLabelC = TextEditingController();
  final TextEditingController _userC = TextEditingController();
  final TextEditingController _pwdLabelC = TextEditingController();
  final TextEditingController _pwdC = TextEditingController();
  final TextEditingController _totpC = TextEditingController();

  List<CredentialEntry> _entries = [];
  int _sel = 0;
  List<TextEditingController> _extraLabelCs = [];
  List<TextEditingController> _extraValueCs = [];

  List<NoteEntry> _noteEntries = [];
  List<TextEditingController> _noteLabelCs = [];
  List<TextEditingController> _noteContentCs = [];

  AccountCategory _category = AccountCategory.general;
  List<String> _badges = [];
  List<ParsedCredential> _batch = [];
  String? _hint;
  String? _error;

  VaultStore get store => widget.store;
  bool get _isEditing => widget.editingItem != null;

  @override
  void initState() {
    super.initState();
    final item = widget.editingItem;
    if (item != null) {
      _titleC.text = item.title;
      _urlC.text = item.url;
      _category = item.category;
      _noteEntries = [
        for (final n in item.effectiveNoteEntries)
          NoteEntry(label: n.label, content: n.content),
      ];
      _entries = [
        for (final e in item.entries) CredentialEntry.fromJson(e.toJson()),
      ];
    } else {
      _category = widget.defaultCategory;
      _entries = [CredentialEntry()];
    }
    _rebuildNoteControllers();
    _loadCurrent();
  }

  @override
  void dispose() {
    _rawC.dispose();
    _titleC.dispose();
    _urlC.dispose();
    _freeNoteC.dispose();
    _accLabelC.dispose();
    _userC.dispose();
    _pwdLabelC.dispose();
    _pwdC.dispose();
    _totpC.dispose();
    _disposeList(_extraLabelCs);
    _disposeList(_extraValueCs);
    _disposeList(_noteLabelCs);
    _disposeList(_noteContentCs);
    super.dispose();
  }

  void _disposeList(List<TextEditingController> list) {
    for (final c in list) {
      c.dispose();
    }
  }

  CredentialEntry get _current {
    if (_entries.isEmpty) _entries.add(CredentialEntry());
    if (_sel >= _entries.length) _sel = _entries.length - 1;
    return _entries[_sel];
  }

  // ── 子账号字段载入 / 冲刷（对齐 Mac loadCurrent / flushCurrent）──

  void _loadCurrent() {
    final e = _current;
    _accLabelC.text = e.accountLabel.trim().isEmpty ? '账号' : e.accountLabel;
    _userC.text = e.username;
    _pwdLabelC.text = e.passwordLabel.trim().isEmpty ? '密码' : e.passwordLabel;
    _pwdC.text = e.password;
    _totpC.text = e.totpSecret;
    _disposeList(_extraLabelCs);
    _disposeList(_extraValueCs);
    _extraLabelCs = [
      for (final p in e.extraPasswords)
        TextEditingController(text: p.label),
    ];
    _extraValueCs = [
      for (final p in e.extraPasswords) TextEditingController(text: p.value),
    ];
  }

  void _flushCurrent() {
    final e = _current;
    e.accountLabel = _accLabelC.text.trim().isEmpty ? '账号' : _accLabelC.text;
    e.username = _userC.text;
    e.passwordLabel =
        _pwdLabelC.text.trim().isEmpty ? '密码' : _pwdLabelC.text;
    e.password = _pwdC.text;
    e.totpSecret = _totpC.text.replaceAll(' ', '').replaceAll('-', '').trim();
    e.updatedAt = DateTime.now();
    // 从属密码与结构化备注的控制器内容必须写回模型，否则保存时丢失
    for (var i = 0;
        i < e.extraPasswords.length && i < _extraLabelCs.length;
        i++) {
      e.extraPasswords[i].label = _extraLabelCs[i].text;
      e.extraPasswords[i].value = _extraValueCs[i].text;
    }
    for (var i = 0;
        i < _noteEntries.length && i < _noteLabelCs.length;
        i++) {
      _noteEntries[i].label = _noteLabelCs[i].text;
      _noteEntries[i].content = _noteContentCs[i].text;
    }
  }

  void _selectEntry(int index) {
    if (index == _sel || !(_entries.length > index)) return;
    _flushCurrent();
    setState(() {
      _sel = index;
      _loadCurrent();
    });
  }

  void _addSubAccount() {
    _flushCurrent();
    setState(() {
      _entries.add(CredentialEntry(password: _pwdC.text));
      _sel = _entries.length - 1;
      _loadCurrent();
      _hint = '已添加子账号 #${_entries.length}';
    });
  }

  void _removeSubAccount() {
    if (_entries.length <= 1) return;
    _flushCurrent();
    setState(() {
      _entries.removeAt(_sel);
      _sel = _sel >= _entries.length ? _entries.length - 1 : _sel;
      _loadCurrent();
      _hint = '已删除子账号';
    });
  }

  // ── 从属密码 ──

  void _addExtraPassword() {
    setState(() {
      _current.extraPasswords.add(LabeledPassword(label: '资金密码', value: ''));
      _loadCurrent();
    });
  }

  void _removeExtraPassword(int index) {
    setState(() {
      _current.extraPasswords.removeAt(index);
      _loadCurrent();
    });
  }

  // ── 安全备注 ──

  void _rebuildNoteControllers() {
    _disposeList(_noteLabelCs);
    _disposeList(_noteContentCs);
    _noteLabelCs = [
      for (final n in _noteEntries) TextEditingController(text: n.label),
    ];
    _noteContentCs = [
      for (final n in _noteEntries) TextEditingController(text: n.content),
    ];
  }

  void _addNoteEntry() {
    setState(() {
      if (_noteEntries.isEmpty && _freeNoteC.text.trim().isNotEmpty) {
        // 自由备注升级为第一条结构化备注（对齐 Mac 行为）
        _noteEntries
            .add(NoteEntry(label: '备注1', content: _freeNoteC.text.trim()));
        _freeNoteC.clear();
        _noteEntries.add(NoteEntry(label: '备注2', content: ''));
      } else {
        _noteEntries.add(NoteEntry(label: '备注${_noteEntries.length + 1}'));
      }
      _rebuildNoteControllers();
    });
  }

  void _removeNoteEntry(int index) {
    setState(() {
      _noteEntries.removeAt(index);
      _rebuildNoteControllers();
    });
  }

  // ── 智能识别（对齐 Mac parseSmartInput / applyParsed）──

  void _parseSmartInput(String text) {
    final t = text.trim();
    if (t.isEmpty) {
      _batch = const [];
      _badges = const [];
      if (!_isEditing) {
        _titleC.clear();
        _urlC.clear();
        setState(() {
          _entries = [CredentialEntry()];
          _sel = 0;
          _category = widget.defaultCategory;
          _noteEntries = [];
          _rebuildNoteControllers();
          _freeNoteC.clear();
          _loadCurrent();
        });
      }
      setState(() {});
      return;
    }

    final parsedList = <ParsedCredential>[];
    for (final line in t.split(RegExp(r'\r?\n'))) {
      final lt = line.trim();
      if (lt.isEmpty) continue;
      final p = SmartCredentialParser.parse(
        lt,
        defaultCategory: widget.defaultCategory,
      );
      if (p.title.isNotEmpty ||
          p.url.isNotEmpty ||
          p.username.isNotEmpty ||
          p.password.isNotEmpty ||
          p.totpSecret.isNotEmpty) {
        parsedList.add(p);
      }
    }

    setState(() {
      if (parsedList.length > 1) {
        _batch = parsedList;
        _applyParsed(parsedList.first);
      } else {
        _batch = const [];
        _applyParsed(
          SmartCredentialParser.parse(
            t,
            defaultCategory: widget.defaultCategory,
          ),
        );
      }
    });
  }

  void _applyParsed(ParsedCredential p) {
    if (p.title.isNotEmpty) _titleC.text = p.title;
    if (p.url.isNotEmpty) _urlC.text = p.url;
    if (p.category != AccountCategory.general ||
        _category == AccountCategory.general) {
      _category = p.category;
    }
    _badges = List.of(p.recognizedBadges);
    if (p.accountLabel.isNotEmpty) _accLabelC.text = p.accountLabel;
    if (p.username.isNotEmpty) _userC.text = p.username;
    if (p.passwordLabel.isNotEmpty) _pwdLabelC.text = p.passwordLabel;
    if (p.password.isNotEmpty) _pwdC.text = p.password;
    if (p.totpSecret.isNotEmpty) _totpC.text = p.totpSecret;
    if (p.extraPasswords.isNotEmpty) {
      _current.extraPasswords = [
        for (final x in p.extraPasswords)
          LabeledPassword(label: x.label, value: x.value),
      ];
    }
    if (p.noteEntries.isNotEmpty) {
      _noteEntries = [
        for (final n in p.noteEntries)
          NoteEntry(label: n.label, content: n.content),
      ];
      _rebuildNoteControllers();
    }
    _flushCurrent();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final clip = data?.text?.trim() ?? '';
    if (clip.isEmpty) {
      setState(() => _hint = '剪贴板当前为空');
      return;
    }
    _rawC.text = clip;
    _parseSmartInput(clip);
    setState(() => _hint = '已从剪贴板读取并完成自动识别');
  }

  void _fillExample() {
    const sample = 'xxxx.com   密码：xxx密码   账号：xxx账号   2FA：JBSWY3DPEHPK3PXP';
    _rawC.text = sample;
    _parseSmartInput(sample);
    setState(() => _hint = '已填入统一格式示例：密码：xxx   账号：xxx   2FA：xxx');
  }

  void _clearAll() {
    _rawC.clear();
    _parseSmartInput('');
    setState(() {
      _hint = null;
      _error = null;
    });
  }

  Future<void> _generatePassword() async {
    _flushCurrent();
    final generated = PasswordGenerator.generate(length: 18);
    setState(() => _pwdC.text = generated);
    _flushCurrent();
  }

  /// 扫码导入 2FA（M5-2）：解析 otpauth:// 后回填密钥并提示归属
  Future<void> _scan2faQr() async {
    _flushCurrent();
    final fill = await openQrScanSheet(context);
    if (fill == null || !mounted) return;
    setState(() {
      _totpC.text = fill.secret;
      _flushCurrent();
      final who = [
        if (fill.issuer.isNotEmpty) fill.issuer,
        if (fill.account.isNotEmpty) fill.account,
      ].join(' · ');
      _hint = who.isEmpty ? '已从二维码导入 2FA 密钥' : '已导入 2FA：$who';
    });
  }

  Future<void> _openGeneratorSheet() async {
    _flushCurrent();
    final used = await showPasswordGeneratorSheet(
      context,
      store: store,
      initialLength: _pwdC.text.length >= 8 ? _pwdC.text.length : 18,
    );
    if (used != null && used.isNotEmpty && mounted) {
      setState(() => _pwdC.text = used);
      _flushCurrent();
    }
  }

  // ── 2FA 实时预览（对齐 Mac liveTOTPPreviewCode）──

  String? get _liveTotpPreview {
    final cleaned =
        _totpC.text.replaceAll(' ', '').replaceAll('-', '').trim();
    if (cleaned.isEmpty) return null;
    try {
      final code = TOTPEngine.generateCode(secret: cleaned);
      return code == '------' ? null : code;
    } catch (_) {
      return null;
    }
  }

  // ── 校验与保存（对齐 Mac handleSave）──

  bool get _hasValidContent {
    if (_batch.length > 1) return true;
    final hasIdentity = _titleC.text.trim().isNotEmpty ||
        _urlC.text.trim().isNotEmpty ||
        _userC.text.trim().isNotEmpty ||
        _entries.any((e) => e.username.trim().isNotEmpty);
    final hasSecret = _pwdC.text.isNotEmpty ||
        _totpC.text.trim().isNotEmpty ||
        _entries.any((e) => e.password.isNotEmpty);
    return hasIdentity && hasSecret;
  }

  Future<void> _save() async {
    _flushCurrent();
    setState(() {
      _error = null;
    });

    // 多行批量识别：一次性全部入库
    if (_batch.length > 1 && !_isEditing) {
      await store.mergeOrInsertParsedCredentials(
        List.of(_batch),
        defaultCategory: widget.defaultCategory,
      );
      if (mounted) Navigator.pop(context);
      return;
    }

    final title = _titleC.text.trim();
    final url = _urlC.text.trim();
    final finalTitle = title.isNotEmpty
        ? title
        : url.isNotEmpty
            ? url
            : _userC.text.trim().isNotEmpty
                ? _userC.text.trim()
                : '未命名账号';

    final cleaned = <CredentialEntry>[];
    for (final e in _entries) {
      e.username = e.username.trim();
      e.totpSecret = e.totpSecret.replaceAll(' ', '').replaceAll('-', '').trim();
      if (e.accountLabel.trim().isEmpty) e.accountLabel = '账号';
      if (e.passwordLabel.trim().isEmpty) e.passwordLabel = '密码';
      cleaned.add(e);
    }
    if (cleaned.isEmpty) {
      cleaned.add(CredentialEntry(username: _userC.text.trim()));
    }

    final effectiveNotes = List.of(_noteEntries);
    if (effectiveNotes.isEmpty && _freeNoteC.text.trim().isNotEmpty) {
      effectiveNotes.add(
          NoteEntry(label: '备注1', content: _freeNoteC.text.trim()));
    }

    final existing = widget.editingItem;
    if (existing != null) {
      existing
        ..title = finalTitle
        ..url = url
        ..category = _category
        ..entries = cleaned
        ..noteEntries = effectiveNotes
        ..updatedAt = DateTime.now();
      await store.upsertItem(existing);
      store.showStatusToast('已保存更新「${existing.title}」');
    } else {
      final dup = store.findExistingItem(finalTitle, url);
      if (dup != null) {
        for (final e in cleaned) {
          dup.addOrUpdateEntry(e);
        }
        for (final n in effectiveNotes) {
          if (!dup.effectiveNoteEntries.any((x) => x.content == n.content)) {
            dup.noteEntries.add(n);
          }
        }
        if (dup.url.isEmpty && url.isNotEmpty) dup.url = url;
        dup.updatedAt = DateTime.now();
        await store.upsertItem(dup);
        store.showStatusToast('已将账号合并追加至「${dup.title}」');
      } else {
        final item = AccountItem(
          title: finalTitle,
          url: url,
          category: _category,
          isFavorite: false,
          noteEntries: effectiveNotes,
          notesLayout: NotesLayoutMode.single,
          entries: cleaned,
        );
        await store.upsertItem(item);
        store.showStatusToast('已自动识别并入库「${item.title}」');
      }
    }
    if (mounted) Navigator.pop(context);
  }

  // ═══════════════════════════ UI ═══════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgIceMid,
      appBar: AppBar(
        title: Row(
          children: [
            Text(_isEditing ? '智能管理与更新记录' : '智能识别添加'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'MULTI-ACCOUNT',
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: AppTheme.primaryBlue,
                ),
              ),
            ),
          ],
        ),
      ),
      body: AppTheme.cyberBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 660),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSmartInputSection(),
                const SizedBox(height: 14),
                if (_batch.length > 1)
                  _buildBatchPreviewSection()
                else ...[
                  _buildAdjustSection(),
                  const SizedBox(height: 14),
                  _buildNotesSection(),
                ],
                const SizedBox(height: 16),
                _buildBottomBar(),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 智能识别粘贴区 ──

  Widget _buildSmartInputSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.glassCard(radius: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.text_fields_rounded,
                  size: 15, color: AppTheme.textSecondary),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('一键粘贴原始文本',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary)),
              ),
              _pillButton(
                key: const Key('editor_paste_button'),
                label: '粘贴剪贴板并识别',
                icon: Icons.content_paste_rounded,
                filled: true,
                onTap: _pasteFromClipboard,
              ),
              const SizedBox(width: 6),
              _pillButton(
                label: '填入示例',
                icon: Icons.auto_fix_high_rounded,
                onTap: _fillExample,
              ),
              if (_rawC.text.isNotEmpty) ...[
                const SizedBox(width: 6),
                _pillButton(
                  label: '清空',
                  onTap: _clearAll,
                  danger: true,
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('editor_smart_field'),
            controller: _rawC,
            onChanged: _parseSmartInput,
            minLines: 3,
            maxLines: 5,
            style: const TextStyle(
                fontSize: 12.5, fontFamily: 'monospace', height: 1.5),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.85),
              hintText: '统一格式：xxxx.com   密码：xxx   账号：xxx   2FA：xxxx\n'
                  '兼容格式：binance.com   Pass123!   user@gmail.com   2fa(xxxx)\n'
                  '支持单行 / 空格 / Tab 分隔或多行批量粘贴',
              hintStyle: TextStyle(
                fontSize: 11,
                height: 1.6,
                color: AppTheme.textSecondary.withValues(alpha: 0.8),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: BorderSide(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.25),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: BorderSide(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.25),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: const BorderSide(
                    color: AppTheme.primaryBlue, width: 1.4),
              ),
            ),
          ),
          if (_badges.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Icon(Icons.verified_rounded,
                    size: 13, color: Color(0xFF0C8C61)),
                const Text('已自动提取：',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary)),
                for (final b in _badges)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0C8C61).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(b,
                        style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0C8C61))),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── 单条微调卡 ──

  Widget _buildAdjustSection() {
    final e = _current;
    final code = _liveTotpPreview;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.glassCard(radius: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 名称 / 网址 / 分类
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: AppTheme.brandGradient,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(_category.iconEmoji,
                    style: const TextStyle(fontSize: 18)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  children: [
                    _labeledField(
                      label: '名称',
                      key: const Key('editor_title_field'),
                      controller: _titleC,
                      hint: '服务名称（如 Binance / xxxx.com）',
                      bold: true,
                    ),
                    const SizedBox(height: 6),
                    _labeledField(
                      label: '网址',
                      key: const Key('editor_url_field'),
                      controller: _urlC,
                      hint: '域名或网址（如 xxxx.com）',
                      mono: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 分类选择
          SizedBox(
            height: 36,
            child: Row(
              children: [
                const Text('所属分类',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: _category.themeColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<AccountCategory>(
                      key: const Key('editor_category_dropdown'),
                      value: _category,
                      isDense: true,
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary),
                      items: [
                        for (final cat in AccountCategory.values)
                          DropdownMenuItem(
                            value: cat,
                            child:
                                Text('${cat.iconEmoji} ${cat.title}'),
                          ),
                      ],
                      onChanged: (v) =>
                          setState(() => _category = v ?? _category),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 20),

          // 子账号选择与管理
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: PopupMenuButton<int>(
                  key: const Key('editor_entry_selector'),
                  tooltip: '切换子账号',
                  onSelected: _selectEntry,
                  itemBuilder: (_) => [
                    for (var i = 0; i < _entries.length; i++)
                      PopupMenuItem(
                        value: i,
                        child: Text(
                          '${i == _sel ? '✓ ' : ''}子账号 #${i + 1}：${_entries[i].username.isEmpty ? '未填写' : _entries[i].username} [${i + 1}/${_entries.length}]',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                  ],
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.person_pin_rounded,
                          size: 14, color: AppTheme.primaryBlue),
                      const SizedBox(width: 5),
                      Text(
                        '子账号 #${_sel + 1}/${_entries.length}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary),
                      ),
                      const SizedBox(width: 3),
                      const Icon(Icons.expand_more_rounded,
                          size: 13, color: AppTheme.textSecondary),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              _pillButton(
                key: const Key('editor_add_entry_button'),
                label: '添加子账号',
                icon: Icons.add_circle_outline_rounded,
                filled: true,
                onTap: _addSubAccount,
              ),
              if (_entries.length > 1) ...[
                const SizedBox(width: 6),
                _pillButton(
                  key: const Key('editor_remove_entry_button'),
                  label: '删除此号',
                  onTap: _removeSubAccount,
                  danger: true,
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),

          // 账号行
          Row(
            children: [
              _tagCapsule(
                key: const Key('editor_account_label'),
                controller: _accLabelC,
                color: const Color(0xFF1285F5),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  key: const Key('editor_username_field'),
                  controller: _userC,
                  onChanged: (_) => _flushCurrent(),
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace'),
                  decoration: _boxDecoration(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 密码行（含随机生成 + 生成器）
          Row(
            children: [
              _tagCapsule(
                key: const Key('editor_password_label'),
                controller: _pwdLabelC,
                color: const Color(0xFFF28C1F),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  key: const Key('editor_password_field'),
                  controller: _pwdC,
                  onChanged: (_) => _flushCurrent(),
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace'),
                  decoration: _boxDecoration().copyWith(
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Tooltip(
                          message: '打开密码生成器（可调长度与字符集）',
                          child: InkWell(
                            key: const Key('editor_generator_button'),
                            onTap: _openGeneratorSheet,
                            borderRadius: BorderRadius.circular(999),
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(Icons.tune_rounded,
                                  size: 15, color: AppTheme.textSecondary),
                            ),
                          ),
                        ),
                        Tooltip(
                          message: '随机生成 18 位高强度密码',
                          child: InkWell(
                            key: const Key('editor_dice_button'),
                            onTap: _generatePassword,
                            borderRadius: BorderRadius.circular(999),
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(Icons.casino_rounded,
                                  size: 15, color: AppTheme.actionBlue),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_pwdC.text.isNotEmpty) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 78),
              child: Text(
                _strengthText(_pwdC.text),
                style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary),
              ),
            ),
          ],
          const SizedBox(height: 10),

          // 从属额外密码
          for (var i = 0; i < e.extraPasswords.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  _tagCapsule(
                    controller: _extraLabelCs[i],
                    color: const Color(0xFF8E5CE6),
                    onChanged: (v) => e.extraPasswords[i].label = v,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _extraValueCs[i],
                      onChanged: (v) => e.extraPasswords[i].value = v,
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace'),
                      decoration: _boxDecoration(
                        fill: const Color(0xFF8E5CE6).withValues(alpha: 0.05),
                      ).copyWith(
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 16, color: AppTheme.dangerRed),
                          onPressed: () => _removeExtraPassword(i),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: _pillButton(
              key: const Key('editor_add_extra_button'),
              label: '添加从属密码（资金密码 / 支付密码 / API Key）',
              icon: Icons.add_circle_outline_rounded,
              onTap: _addExtraPassword,
              color: const Color(0xFF8E5CE6),
            ),
          ),
          const SizedBox(height: 12),

          // 2FA 行 + 实时动态码预览
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                width: 78,
                decoration: BoxDecoration(
                  color: const Color(0xFF0C8C61).withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('2FA 验证',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0C8C61))),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  key: const Key('editor_totp_field'),
                  controller: _totpC,
                  onChanged: (_) => setState(() => _flushCurrent()),
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace'),
                  decoration: _boxDecoration(),
                ),
              ),
              if (code != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('动态码 $code',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                          color: Color(0xFF0C8C61))),
                ),
              ] else if (_totpC.text.trim().isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.warnOrange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text('已记录密钥',
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.warnOrange)),
                ),
              ],
              // 相机扫码导入（M5-2，仅移动端；Web 相机受限不显示）
              if (!kIsWeb) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: '扫描 2FA 二维码自动填入密钥',
                  child: InkWell(
                    key: const Key('editor_scan_button'),
                    onTap: _scan2faQr,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0C8C61).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.qr_code_scanner_rounded,
                          size: 17, color: Color(0xFF0C8C61)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── 安全备注卡 ──

  Widget _buildNotesSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.glassCard(radius: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sticky_note_2_rounded,
                  size: 15, color: AppTheme.textSecondary),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('安全备注与附加说明',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary)),
              ),
              _pillButton(
                key: const Key('editor_add_note_button'),
                label: '添加自定义备注条目',
                icon: Icons.add_circle_outline_rounded,
                onTap: _addNoteEntry,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_noteEntries.isEmpty)
            Row(
              children: [
                const _FixedTagCapsule(text: '备注'),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    key: const Key('editor_free_note_field'),
                    controller: _freeNoteC,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: _boxDecoration()
                        .copyWith(hintText: '可选补充说明（密保问题 / 恢复码等）'),
                  ),
                ),
              ],
            )
          else
            for (var i = 0; i < _noteEntries.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    _tagCapsule(
                      controller: _noteLabelCs[i],
                      color: AppTheme.textSecondary,
                      onChanged: (v) => _noteEntries[i].label = v,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        key: Key('editor_note_content_$i'),
                        controller: _noteContentCs[i],
                        onChanged: (v) => _noteEntries[i].content = v,
                        style: const TextStyle(fontSize: 12.5),
                        decoration: _boxDecoration().copyWith(
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.delete_outline_rounded,
                                size: 16, color: AppTheme.dangerRed),
                            onPressed: () => _removeNoteEntry(i),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  // ── 批量识别预览 ──

  Widget _buildBatchPreviewSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.glassCard(radius: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.layers_rounded,
                  size: 15, color: AppTheme.primaryBlue),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '已自动识别出 ${_batch.length} 条独立账号记录，保存后将一次性全部入库',
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final p in _batch)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Text(p.category.iconEmoji,
                      style: const TextStyle(fontSize: 17)),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.title.isEmpty
                              ? (p.url.isEmpty ? '待命名' : p.url)
                              : p.title,
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (p.username.isNotEmpty) '账号 ${p.username}',
                            if (p.password.isNotEmpty) '密码 ${p.password}',
                            if (p.totpSecret.isNotEmpty) '2FA ${p.totpSecret}',
                          ].join('  ·  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 10.5,
                              fontFamily: 'monospace',
                              color: AppTheme.textSecondary
                                  .withValues(alpha: 0.9)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── 底部操作栏 ──

  Widget _buildBottomBar() {
    final valid = _hasValidContent;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.glassCard(radius: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _error ??
                  _hint ??
                  '支持任意数量子账号；账号、密码与备注均可自定义命名',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _error != null
                    ? AppTheme.dangerRed
                    : AppTheme.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消',
                style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 4),
          InkWell(
            key: const Key('editor_save_button'),
            onTap: valid ? _save : null,
            borderRadius: BorderRadius.circular(10),
            child: Opacity(
              opacity: valid ? 1 : 0.45,
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: AppTheme.brandGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _batch.length > 1
                      ? '批量添加（${_batch.length} 条）'
                      : (_isEditing ? '保存更新' : '一键自动添加'),
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 通用小组件 ──

  String _strengthText(String pwd) {
    if (pwd.isEmpty) return '';
    final bits = PasswordGenerator.calculateEntropy(pwd).round();
    final label = switch (PasswordGenerator.evaluateStrength(pwd)) {
      PasswordStrength.weak => '弱',
      PasswordStrength.medium => '中等',
      PasswordStrength.strong => '强',
      PasswordStrength.veryStrong => '极强',
    };
    return '强度 $label · $bits bits';
  }

  InputDecoration _boxDecoration({Color? fill}) {
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: fill ?? Colors.white.withValues(alpha: 0.85),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide(
            color: AppTheme.primaryBlue.withValues(alpha: 0.18)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide(
            color: AppTheme.primaryBlue.withValues(alpha: 0.18)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide:
            const BorderSide(color: AppTheme.primaryBlue, width: 1.3),
      ),
    );
  }

  Widget _labeledField({
    required String label,
    Key? key,
    required TextEditingController controller,
    required String hint,
    bool bold = false,
    bool mono = false,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 38,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary)),
        ),
        Expanded(
          child: TextField(
            key: key,
            controller: controller,
            style: TextStyle(
              fontSize: bold ? 13 : 12,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              fontFamily: mono ? 'monospace' : null,
            ),
            decoration:
                _boxDecoration().copyWith(hintText: hint, hintStyle: const TextStyle(fontSize: 11)),
          ),
        ),
      ],
    );
  }

  Widget _tagCapsule({
    Key? key,
    required TextEditingController controller,
    required Color color,
    ValueChanged<String>? onChanged,
  }) {
    return Container(
      key: key,
      width: 72,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        maxLength: 8,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w800, color: color),
        decoration: const InputDecoration(
          isDense: true,
          counterText: '',
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 9),
        ),
      ),
    );
  }

  Widget _pillButton({
    Key? key,
    required String label,
    required VoidCallback onTap,
    IconData? icon,
    bool filled = false,
    bool danger = false,
    Color color = AppTheme.primaryBlue,
  }) {
    final fg = danger ? AppTheme.dangerRed : color;
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: danger
              ? AppTheme.dangerRed.withValues(alpha: 0.08)
              : filled
                  ? null
                  : color.withValues(alpha: 0.10),
          gradient: filled && !danger ? AppTheme.brandGradient : null,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: filled && !danger ? Colors.white : fg),
              const SizedBox(width: 3),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: filled && !danger ? Colors.white : fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 固定文本标签胶囊（自由备注行的「备注」标签）
class _FixedTagCapsule extends StatelessWidget {
  const _FixedTagCapsule({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      padding: const EdgeInsets.symmetric(vertical: 9),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.textSecondary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(7),
        border:
            Border.all(color: AppTheme.textSecondary.withValues(alpha: 0.25)),
      ),
      child: Text(text,
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppTheme.textSecondary)),
    );
  }
}
