import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/crypto/crypto_engine.dart';
import '../core/models/account_category.dart';
import '../core/models/account_item.dart';
import '../core/models/credential_entry.dart';
import '../core/models/note_entry.dart';
import '../core/models/notes_layout_mode.dart';
import '../core/parser/smart_credential_parser.dart';
import '../core/storage/vault_storage.dart' show FileNotFoundException;
import '../core/totp/totp_engine.dart';
import 'keychain_service.dart';
import 'quick_type_mirror.dart';
import 'sidebar_filter.dart';
import 'vault_storage_backend.dart';
import 'web_vault_storage_backend.dart';

/// 应用生命周期阶段
enum VaultPhase {
  /// 尚未探测到本地保险箱，等待首次创建
  needsSetup,

  /// 存在保险箱但处于锁定状态
  locked,

  /// 已解锁，明文数据驻留内存
  unlocked,
}

/// 全局状态总线 — 对齐 Mac 版 VaultStore 的处理逻辑：
/// 选中态驱动详情、筛选器体系、全局 2FA 缓存、剪贴板安全 Toast、
/// 粘贴即存智能归并、按类型分组、闲置锁定（默认 0 = 不自动锁）。
class VaultStore extends ChangeNotifier {
  VaultPhase _phase = VaultPhase.needsSetup;

  final List<AccountItem> _items = [];
  String _masterPassword = '';
  bool _unlocking = false;
  bool _authenticating = false;
  String? _lastError;

  // ── 选中态与筛选 ──
  String? selectedItemId;
  SidebarFilter currentFilter = SidebarFilter.all;
  String searchQuery = '';
  bool groupByCategory = true;

  // ── 全局 2FA 实时状态 ──
  int remainingSeconds2FA = 30;
  double progress2FA = 1.0;
  final Map<String, String> cachedCodes2FA = {};

  // ── 用户设置（M4 接入持久化）──
  int autoLockMinutes = 0; // 对齐 Mac 默认值：0 = 仅手动/系统事件锁定
  int clipboardClearSeconds = 30;

  // ── 剪贴板安全 Toast ──
  String? clipboardStatusMessage;
  Timer? _clipboardClearTimer;
  Timer? _clipboardToastTimer;
  Timer? _statusToastTimer;

  // ── 内部计时器 ──
  Timer? _totpTicker;
  Timer? _idleLockTimer;
  DateTime _lastUserActivity = DateTime.now();

  VaultPhase get phase => _phase;
  bool get hasVault => _phase != VaultPhase.needsSetup;
  bool get isUnlocked => _phase == VaultPhase.unlocked;
  bool get unlocking => _unlocking;
  bool get authenticating => _authenticating;
  String? get lastError => _lastError;
  List<AccountItem> get items => List.unmodifiable(_items);

  final KeychainService keychain;
  final VaultStorageBackend backend;

  VaultStore({
    KeychainService? keychain,
    VaultStorageBackend? backend,
  })  : keychain = keychain ?? KeychainService(),
        backend = backend ??
            (kIsWeb
                ? WebVaultStorageBackend()
                : const LocalVaultStorageBackend());

  /// 应用启动后调用：探测本地保险箱决定初始阶段，并启动全局 2FA 心跳
  Future<void> bootstrap() async {
    final exists = await backend.hasExistingVault();
    _phase = exists ? VaultPhase.locked : VaultPhase.needsSetup;
    _lastError = null;
    _start2FATicker();
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // 创建与解锁
  // ------------------------------------------------------------------

  /// 首次创建保险箱（预置演示数据，对齐 Mac 版 createVault 行为）
  Future<bool> createVault(String password, String confirmation) async {
    if (_phase != VaultPhase.needsSetup) {
      _fail('本地已存在保险箱，无法重复创建');
      return false;
    }
    if (password.length < 8) {
      _fail('主密码至少需要 8 位，建议 12 位以上');
      return false;
    }
    if (password != confirmation) {
      _fail('两次输入的主密码不一致');
      return false;
    }
    if (password.contains(' ')) {
      _fail('主密码不能包含空格');
      return false;
    }

    _unlocking = true;
    notifyListeners();
    try {
      final demoItems = _demoSeedItems();
      await backend.save(items: demoItems, masterPassword: password);
      _masterPassword = password;
      _items
        ..clear()
        ..addAll(demoItems);
      selectedItemId = _items.isNotEmpty ? _items.first.id : null;
      _enterUnlocked();
      return true;
    } catch (e) {
      _fail('保险箱创建失败：$e');
      return false;
    } finally {
      _unlocking = false;
      notifyListeners();
    }
  }

  /// 使用主密码解锁
  Future<bool> unlockWithPassword(String password) async {
    _unlocking = true;
    _lastError = null;
    notifyListeners();
    try {
      final loaded = await backend.load(masterPassword: password);
      _masterPassword = password;
      _items
        ..clear()
        ..addAll(loaded);
      selectedItemId = _items.isNotEmpty ? _items.first.id : null;
      _enterUnlocked();
      return true;
    } on InvalidMasterPasswordException {
      _fail('主密码错误，或保险箱数据已被篡改');
      return false;
    } on FileNotFoundException {
      _fail('保险箱文件不存在');
      return false;
    } catch (e) {
      _fail('解锁失败：$e');
      return false;
    } finally {
      _unlocking = false;
      notifyListeners();
    }
  }

  /// 判断 Face ID / Touch ID 是否可用（含 Keychain 托管前提）
  Future<bool> canUseBiometrics() async {
    if (_phase != VaultPhase.locked) return false;
    final hasStored = await keychain.hasMasterPassword();
    return hasStored && await keychain.canCheckBiometrics();
  }

  /// Face ID / Touch ID 解锁
  Future<bool> unlockWithBiometrics() async {
    if (_phase != VaultPhase.locked) return false;
    final hasStored = await keychain.hasMasterPassword();
    if (!hasStored) return false;
    if (!await keychain.canCheckBiometrics()) return false;

    _authenticating = true;
    _lastError = null;
    notifyListeners();
    try {
      final password = await keychain.readMasterPassword();
      if (password == null || password.isEmpty) {
        _fail('生物识别数据已失效，请使用主密码解锁');
        return false;
      }
      return await unlockWithPassword(password);
    } on BiometricsNotAvailableException {
      _fail('设备未配置 Face ID / Touch ID');
      return false;
    } on BiometricsAuthFailedException {
      _fail('生物识别未通过，请使用主密码解锁');
      return false;
    } finally {
      _authenticating = false;
      notifyListeners();
    }
  }

  /// 开关生物识别托管
  Future<bool> setBiometricsEnabled(bool enabled) async {
    if (!isUnlocked) return false;
    if (enabled) {
      return await keychain.storeMasterPassword(_masterPassword);
    }
    return await keychain.deleteMasterPassword();
  }

  /// 当前 Keychain 是否已托管主密码
  Future<bool> isBiometricsEnabled() => keychain.hasMasterPassword();

  /// 修改主密码（需已解锁）
  Future<bool> changeMasterPassword(
      String oldPassword, String newPassword) async {
    if (!isUnlocked) {
      _fail('保险箱处于锁定状态');
      return false;
    }
    if (oldPassword != _masterPassword) {
      _fail('原主密码不正确');
      return false;
    }
    if (newPassword.length < 8) {
      _fail('新主密码至少需要 8 位');
      return false;
    }
    _unlocking = true;
    notifyListeners();
    try {
      await backend.save(items: _items, masterPassword: newPassword);
      _masterPassword = newPassword;
      if (await keychain.hasMasterPassword()) {
        await keychain.storeMasterPassword(newPassword);
      }
      return true;
    } catch (e) {
      _fail('主密码修改失败：$e');
      return false;
    } finally {
      _unlocking = false;
      notifyListeners();
    }
  }

  // ------------------------------------------------------------------
  // 账号增删改（对齐 Mac 版操作集）
  // ------------------------------------------------------------------

  /// 持久化当前条目
  Future<void> persist() async {
    if (!isUnlocked) return;
    await backend.save(items: _items, masterPassword: _masterPassword);
    // AutoFill 镜像 best-effort：不阻塞持久化链路（测试环境无平台通道实现）
    unawaited(QuickTypeMirror.sync(_items));
    recordActivity();
  }

  /// 新增或更新条目：新条目插到队首并选中（对齐 Mac upsertItem）
  Future<void> upsertItem(AccountItem item) async {
    if (!isUnlocked) return;
    final index = _items.indexWhere((e) => e.id == item.id);
    if (index >= 0) {
      _items[index] = item;
    } else {
      _items.insert(0, item);
    }
    selectedItemId = item.id;
    _refresh2FACodes();
    notifyListeners();
    await persist();
  }

  /// 批量写入条目
  Future<void> addItems(List<AccountItem> newItems) async {
    if (!isUnlocked) return;
    for (final item in newItems) {
      final index = _items.indexWhere((e) => e.id == item.id);
      if (index >= 0) {
        _items[index] = item;
      } else {
        _items.add(item);
      }
    }
    _refresh2FACodes();
    notifyListeners();
    await persist();
  }

  /// 删除条目：选中态回退到过滤列表首项（对齐 Mac deleteItem）
  Future<void> deleteItem(String itemId) async {
    if (!isUnlocked) return;
    _items.removeWhere((e) => e.id == itemId);
    cachedCodes2FA.remove(itemId);
    if (selectedItemId == itemId) {
      selectedItemId = filteredItems.isNotEmpty ? filteredItems.first.id : null;
    }
    notifyListeners();
    await persist();
    showStatusToast('已彻底删除该记录（不保留）');
  }

  /// 切换收藏
  Future<void> toggleFavorite(String itemId) async {
    if (!isUnlocked) return;
    for (final item in _items) {
      if (item.id == itemId) {
        item.isFavorite = !item.isFavorite;
        item.updatedAt = DateTime.now();
        break;
      }
    }
    notifyListeners();
    await persist();
  }

  /// 更改所属分类
  Future<void> updateCategory(String itemId, AccountCategory category) async {
    if (!isUnlocked) return;
    for (final item in _items) {
      if (item.id == itemId) {
        item.category = category;
        item.updatedAt = DateTime.now();
        break;
      }
    }
    notifyListeners();
    await persist();
  }

  /// 同名称下追加/更新账号（详情页快速追加）
  Future<void> appendEntry(String itemId, CredentialEntry entry) async {
    if (!isUnlocked) return;
    final index = _items.indexWhere((e) => e.id == itemId);
    if (index < 0) return;
    _items[index].addOrUpdateEntry(entry);
    _refresh2FACodes();
    notifyListeners();
    await persist();
  }

  /// 切换安全备注排版（一行单条 / 一行两条，对齐 Mac updateNotesLayout）
  Future<void> updateNotesLayout(String itemId, NotesLayoutMode layout) async {
    if (!isUnlocked) return;
    final index = _items.indexWhere((e) => e.id == itemId);
    if (index < 0) return;
    _items[index].updateNotesLayout(layout);
    notifyListeners();
    await persist();
  }

  // ------------------------------------------------------------------
  // 智能识别：粘贴即存与归并（对齐 Mac smartAddFromClipboard / merge）
  // ------------------------------------------------------------------

  /// 从剪贴板（或显式文本）批量解析并入桶，返回是否成功入库
  bool smartAddFromClipboard({
    String? clipText,
    AccountCategory defaultCategory = AccountCategory.general,
  }) {
    final text = clipText?.trim();
    if (text == null || text.isEmpty) {
      showStatusToast('剪贴板当前为空，请先复制「网址 账号 密码 2fa(...)」');
      return false;
    }

    final parsedList = <ParsedCredential>[];
    for (final line in text.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      parsedList.add(
        SmartCredentialParser.parse(trimmed, defaultCategory: defaultCategory),
      );
    }

    final validItems = parsedList
        .where((p) =>
            p.username.isNotEmpty ||
            p.password.isNotEmpty ||
            p.totpSecret.isNotEmpty ||
            p.url.isNotEmpty)
        .toList();

    if (validItems.isEmpty) {
      showStatusToast('未识别到有效账号信息，请使用「智能添加」粘贴调整');
      return false;
    }

    mergeOrInsertParsedCredentials(validItems, defaultCategory: defaultCategory);
    return true;
  }

  /// 按域名/标题匹配既有条目（对齐 Mac findExistingItem）
  AccountItem? findExistingItem(String title, String url) {
    final cleanTitle = title.trim().toLowerCase();
    final cleanURL = url.trim().toLowerCase();

    if (cleanURL.isNotEmpty) {
      final h2 = _domainOf(cleanURL);
      for (final item in _items) {
        final itemURL = item.url.trim().toLowerCase();
        if (itemURL.isEmpty) continue;
        if (itemURL == cleanURL) return item;
        final h1 = _domainOf(itemURL);
        if (h1.isNotEmpty && h2.isNotEmpty && h1 == h2) return item;
      }
    }

    if (cleanTitle.isNotEmpty) {
      for (final item in _items) {
        final itemTitle = item.title.trim().toLowerCase();
        if (itemTitle == cleanTitle) return item;
        final baseItemTitle = _baseTitle(itemTitle);
        final baseCleanTitle = _baseTitle(cleanTitle);
        if (baseItemTitle.isNotEmpty && baseItemTitle == baseCleanTitle) {
          return item;
        }
      }
    }
    return null;
  }

  /// 归并或新建条目并给出 Toast 反馈（对齐 Mac mergeOrInsertParsedCredentials）
  Future<void> mergeOrInsertParsedCredentials(
    List<ParsedCredential> parsedList, {
    AccountCategory defaultCategory = AccountCategory.general,
  }) async {
    if (!isUnlocked) return;
    final mergedTitles = <String>[];
    var createdCount = 0;
    String? lastTargetId;

    for (final parsed in parsedList) {
      final entry = parsed.toCredentialEntry();
      final existing = findExistingItem(parsed.title, parsed.url);
      if (existing != null) {
        final idx = _items.indexWhere((e) => e.id == existing.id);
        _items[idx].addOrUpdateEntry(entry);
        if (_items[idx].url.isEmpty && parsed.url.isNotEmpty) {
          _items[idx].url = parsed.url;
        }
        for (final n in parsed.noteEntries) {
          if (!_items[idx].effectiveNoteEntries
              .any((e) => e.content == n.content)) {
            _items[idx].noteEntries.add(n);
          }
        }
        lastTargetId = _items[idx].id;
        if (!mergedTitles.contains(_items[idx].title)) {
          mergedTitles.add(_items[idx].title);
        }
      } else {
        final newItem = parsed.toAccountItem();
        if (newItem.category == AccountCategory.general && defaultCategory != AccountCategory.general) {
          newItem.category = defaultCategory;
        }
        _items.insert(0, newItem);
        lastTargetId = newItem.id;
        createdCount += 1;
      }
    }

    if (lastTargetId != null) {
      selectedItemId = lastTargetId;
    }
    _refresh2FACodes();
    notifyListeners();
    await persist();

    if (mergedTitles.isNotEmpty && createdCount == 0) {
      showStatusToast('✨ 已自动归并到「${mergedTitles.join('、')}」名下');
    } else if (mergedTitles.isNotEmpty && createdCount > 0) {
      showStatusToast('✨ 已归并至「${mergedTitles.join('、')}」并新建 $createdCount 项');
    } else if (createdCount > 1) {
      showStatusToast('✨ 已智能识别并批量入库 $createdCount 条记录');
    } else if (createdCount == 1 && _items.isNotEmpty) {
      showStatusToast('✨ 已自动识别并入库：${_items.first.title}');
    }
  }

  // ------------------------------------------------------------------
  // 筛选、分组与统计（对齐 Mac filteredItems / itemsGroupedByCategory / count）
  // ------------------------------------------------------------------

  List<AccountItem> get filteredItems {
    List<AccountItem> baseItems;
    switch (currentFilter.kind) {
      case 'favorites':
        baseItems = _items.where((e) => e.isFavorite).toList();
        break;
      case 'has2FA':
        baseItems = _items.where((e) => e.hasTOTP).toList();
        break;
      case 'category':
        baseItems =
            _items.where((e) => e.category == currentFilter.category).toList();
        break;
      case 'tag':
        baseItems = _items
            .where((e) =>
                _normalizeTag(e.customTag).toLowerCase() ==
                (currentFilter.tag ?? '').toLowerCase())
            .toList();
        break;
      default:
        baseItems = List.of(_items);
    }

    final query = searchQuery.trim().toLowerCase();
    if (query.isEmpty) return baseItems;

    return baseItems.where((item) {
      if (item.title.toLowerCase().contains(query)) return true;
      if (item.url.toLowerCase().contains(query)) return true;
      if (item.notesText.toLowerCase().contains(query)) return true;
      if (item.category.title.toLowerCase().contains(query)) return true;
      if (_normalizeTag(item.customTag).toLowerCase().contains(query)) {
        return true;
      }
      for (final note in item.effectiveNoteEntries) {
        if (note.effectiveLabel.toLowerCase().contains(query) ||
            note.content.toLowerCase().contains(query)) {
          return true;
        }
      }
      for (final entry in item.entries) {
        if (entry.username.toLowerCase().contains(query)) return true;
        if (entry.effectiveAccountLabel.toLowerCase().contains(query)) {
          return true;
        }
        if (entry.password.toLowerCase().contains(query)) return true;
        if (entry.notes.toLowerCase().contains(query)) return true;
        for (final extra in entry.extraPasswords) {
          if (extra.effectiveLabel.toLowerCase().contains(query) ||
              extra.value.toLowerCase().contains(query)) {
            return true;
          }
        }
      }
      return false;
    }).toList();
  }

  List<(AccountCategory, List<AccountItem>)> get itemsGroupedByCategory {
    final current = filteredItems;
    final result = <(AccountCategory, List<AccountItem>)>[];
    for (final cat in AccountCategory.values) {
      final matches = current.where((e) => e.category == cat).toList();
      if (matches.isNotEmpty) result.add((cat, matches));
    }
    return result;
  }

  AccountItem? get selectedItem {
    if (selectedItemId != null) {
      for (final item in _items) {
        if (item.id == selectedItemId) return item;
      }
    }
    return filteredItems.isNotEmpty ? filteredItems.first : null;
  }

  void selectItem(String? itemId) {
    selectedItemId = itemId;
    recordActivity();
    notifyListeners();
  }

  void setFilter(SidebarFilter filter) {
    currentFilter = filter;
    final first = filteredItems.isNotEmpty ? filteredItems.first.id : null;
    selectedItemId = first;
    recordActivity();
    notifyListeners();
  }

  void setSearchQuery(String value) {
    searchQuery = value;
    recordActivity();
    notifyListeners();
  }

  void toggleGroupByCategory() {
    groupByCategory = !groupByCategory;
    notifyListeners();
  }

  int countFor(SidebarFilter filter) {
    switch (filter.kind) {
      case 'all':
        return _items.length;
      case 'favorites':
        return _items.where((e) => e.isFavorite).length;
      case 'has2FA':
        return _items.where((e) => e.hasTOTP).length;
      case 'category':
        return _items.where((e) => e.category == filter.category).length;
      case 'tag':
        return _items
            .where((e) =>
                _normalizeTag(e.customTag).toLowerCase() ==
                (filter.tag ?? '').toLowerCase())
            .length;
    }
    return 0;
  }

  List<String> get allCustomTags {
    final seen = <String>{};
    final result = <String>[];
    for (final item in _items) {
      final tag = _normalizeTag(item.customTag);
      if (tag.isNotEmpty && !seen.contains(tag)) {
        seen.add(tag);
        result.add(tag);
      }
    }
    result.sort();
    return result;
  }

  // ------------------------------------------------------------------
  // 全局 2FA 实时计算（对齐 Mac cachedCodes2FA / 单时钟设计）
  // ------------------------------------------------------------------

  void _start2FATicker() {
    _totpTicker?.cancel();
    _update2FATime();
    _totpTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      _update2FATime();
      if (isUnlocked) _refresh2FACodes();
    });
  }

  void _update2FATime() {
    final remaining = TOTPEngine.getRemainingSeconds(period: 30);
    remainingSeconds2FA = remaining;
    progress2FA = remaining / 30.0;
  }

  void _refresh2FACodes() {
    for (final item in _items) {
      if (item.hasTOTP) {
        cachedCodes2FA[item.id] = _safeCode(
          item.firstTOTPSecret,
          digits: item.entries.firstWhere((e) => e.hasTOTP).totpDigits,
          period: item.entries.firstWhere((e) => e.hasTOTP).totpPeriod,
          algorithm: item.entries.firstWhere((e) => e.hasTOTP).totpAlgorithm,
        );
      }
      for (final entry in item.entries) {
        if (entry.hasTOTP) {
          cachedCodes2FA[entry.id] = _safeCode(
            entry.totpSecret,
            digits: entry.totpDigits,
            period: entry.totpPeriod,
            algorithm: entry.totpAlgorithm,
          );
        }
      }
    }
    notifyListeners();
  }

  String _safeCode(String secret,
      {required int digits, required int period, required dynamic algorithm}) {
    try {
      return TOTPEngine.generateCode(
        secret: secret,
        digits: digits,
        period: period,
        algorithm: algorithm,
      );
    } catch (_) {
      return '密钥错误';
    }
  }

  String codeForItem(AccountItem item) {
    final totpEntry = item.entries.firstWhere((e) => e.hasTOTP,
        orElse: () => item.entries.first);
    if (!item.hasTOTP) return cachedCodes2FA[item.id] ?? '------';
    return cachedCodes2FA[totpEntry.id] ??
        cachedCodes2FA[item.id] ??
        '------';
  }

  String codeForEntry(CredentialEntry entry) {
    if (cachedCodes2FA.containsKey(entry.id)) return cachedCodes2FA[entry.id]!;
    return _safeCode(
      entry.totpSecret,
      digits: entry.totpDigits,
      period: entry.totpPeriod,
      algorithm: entry.totpAlgorithm,
    );
  }

  String formattedCode(String raw) {
    if (raw.length == 6) {
      return '${raw.substring(0, 3)} ${raw.substring(3)}';
    } else if (raw.length == 8) {
      return '${raw.substring(0, 4)} ${raw.substring(4)}';
    }
    return raw;
  }

  // ------------------------------------------------------------------
  // 剪贴板安全（对齐 Mac copyToClipboard 两阶段 Toast）
  // ------------------------------------------------------------------

  /// 复制内容：入剪贴板 + 定时清空 + Toast 反馈
  void copyToClipboard(String text, {String label = '内容'}) {
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    recordActivity();

    final trimmedLabel = label.trim().isEmpty ? '内容' : label.trim();
    final seconds = clipboardClearSeconds;

    if (seconds > 0) {
      clipboardStatusMessage = '已复制 $trimmedLabel · $seconds秒后自动清空剪贴板';
      _clipboardClearTimer?.cancel();
      _clipboardClearTimer = Timer(Duration(seconds: seconds), () async {
        final current = await Clipboard.getData('text/plain');
        if (current?.text == text) {
          await Clipboard.setData(const ClipboardData(text: ''));
          clipboardStatusMessage = '安全防护：剪贴板已自动清空';
          notifyListeners();
          _statusToastTimer?.cancel();
          _statusToastTimer = Timer(const Duration(seconds: 2), () {
            if (clipboardStatusMessage == '安全防护：剪贴板已自动清空') {
              clipboardStatusMessage = null;
              notifyListeners();
            }
          });
        }
      });
    } else {
      clipboardStatusMessage = '已复制 $trimmedLabel';
    }

    _clipboardToastTimer?.cancel();
    _clipboardToastTimer = Timer(const Duration(seconds: 3), () {
      if (clipboardStatusMessage?.startsWith('已复制') == true) {
        clipboardStatusMessage = null;
        notifyListeners();
      }
    });
    notifyListeners();
  }

  /// 通用状态 Toast
  void showStatusToast(String message) {
    clipboardStatusMessage = message;
    _statusToastTimer?.cancel();
    _statusToastTimer = Timer(const Duration(milliseconds: 3200), () {
      if (clipboardStatusMessage == message) {
        clipboardStatusMessage = null;
        notifyListeners();
      }
    });
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // 锁定与闲置（对齐 Mac：autoLockMinutes=0 时不自动锁）
  // ------------------------------------------------------------------

  /// 立即锁定：清空内存明文与密钥
  void lockNow({String? message}) {
    _idleLockTimer?.cancel();
    _idleLockTimer = null;
    if (_phase == VaultPhase.unlocked) {
      _masterPassword = '';
      _items.clear();
      cachedCodes2FA.clear();
      selectedItemId = null;
      searchQuery = '';
      currentFilter = SidebarFilter.all;
      clipboardStatusMessage = null;
      _phase = VaultPhase.locked;
    }
    _lastError = message;
    notifyListeners();
  }

  /// 记录用户活跃（重置闲置计时基准）
  void recordActivity() {
    _lastUserActivity = DateTime.now();
  }

  void _resetIdleTimer() {
    _idleLockTimer?.cancel();
    _idleLockTimer = null;
    recordActivity();

    if (autoLockMinutes <= 0) return;
    final interval = Duration(minutes: autoLockMinutes);
    _idleLockTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!isUnlocked) return;
      if (DateTime.now().difference(_lastUserActivity) >= interval) {
        lockNow(message: '长时间未操作，已自动锁定');
      }
    });
  }

  void handleAppResumed() {
    if (isUnlocked) {
      _resetIdleTimer();
      _refresh2FACodes();
    }
  }

  void handleAppPaused() {
    // 对齐 Mac 版：切后台不锁定（iOS 可在设置中开启后台锁定，M4 提供）
    recordActivity();
  }

  @override
  void dispose() {
    _totpTicker?.cancel();
    _idleLockTimer?.cancel();
    _clipboardClearTimer?.cancel();
    _clipboardToastTimer?.cancel();
    _statusToastTimer?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // 私有区
  // ------------------------------------------------------------------

  void _enterUnlocked() {
    _phase = VaultPhase.unlocked;
    _lastError = null;
    _refresh2FACodes();
    _resetIdleTimer();
  }

  void _fail(String message) {
    _lastError = message;
    notifyListeners();
  }

  String _domainOf(String url) {
    return url
        .replaceAll('https://', '')
        .replaceAll('http://', '')
        .replaceAll('www.', '')
        .split('/')
        .first;
  }

  String _baseTitle(String title) {
    return title
        .split(' (')
        .first
        .split('（')
        .first
        .trim();
  }

  String _normalizeTag(String tag) {
    final t = tag.trim();
    if (t.startsWith('#')) return t.substring(1).trim();
    return t;
  }

  /// 创建保险箱时预置演示数据（对齐 Mac 版内置示例）
  static List<AccountItem> _demoSeedItems() {
    const sharedPass1 = 'AlphaQuant_2026!#9';
    const sharedPass2 = 'SubVault_9988\$Xz';

    return [
      AccountItem(
        title: 'Binance (示例加密账户)',
        url: 'https://www.binance.com',
        category: AccountCategory.crypto,
        customTag: '交易所',
        isFavorite: true,
        noteEntries: [
          NoteEntry(label: '备注', content: '演示安全备注：客服绝不会索要 2FA 动态验证码'),
          NoteEntry(label: '密保问题', content: ' 出生地城市？'),
          NoteEntry(label: '恢复助记词', content: 'aurora vault quantum pulse harbor'),
        ],
        entries: [
          CredentialEntry(
            username: 'trader_main@example.com',
            password: sharedPass1,
            totpSecret: 'JBSWY3DPEHPK3PXP',
            notes: '主现货交易号',
          ),
          CredentialEntry(
            username: 'quant_bot01@example.com',
            password: sharedPass1,
            totpSecret: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ',
            notes: '同密码下的网格量化子号',
          ),
          CredentialEntry(
            username: 'hedge_sub02@binance.vip',
            password: sharedPass2,
            totpSecret: 'JBSWY3DPEHPK3PXP',
            notes: '另一套独立密码下的合约对冲子号',
          ),
        ],
      ),
      AccountItem(
        title: 'GitHub (示例开发仓库)',
        url: 'https://github.com',
        category: AccountCategory.work,
        customTag: '代码库',
        isFavorite: true,
        entries: [
          CredentialEntry(
            username: 'developer@example.com',
            password: 'Gh#Demo-2026!x',
            totpSecret: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ',
            notes: '示例开发平台账号，含 RFC 6238 标准 2FA 动态码。',
          ),
        ],
      ),
      AccountItem(
        title: 'OpenAI API (示例 AI 服务)',
        url: 'https://platform.openai.com',
        category: AccountCategory.ai,
        customTag: '大模型',
        isFavorite: false,
        entries: [
          CredentialEntry(
            username: 'ai-builder@example.com',
            password: 'Oa#Demo-2026!k',
            notes: '示例 AI 与云服务分类账号，可在侧栏或顶部按类型一键筛选。',
          ),
        ],
      ),
    ];
  }
}
