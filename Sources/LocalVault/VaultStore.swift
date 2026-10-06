import Foundation
import SwiftUI
import AppKit
import Combine

@MainActor
public final class VaultStore: ObservableObject {
    // 基础状态
    @Published public var isVaultCreated: Bool = false
    @Published public var isUnlocked: Bool = false
    @Published public var errorMessage: String? = nil

    // 核心数据
    @Published public var items: [AccountItem] = []
    @Published public var selectedItemId: UUID? = nil
    @Published public var currentFilter: SidebarFilter = .all
    @Published public var searchQuery: String = ""

    // 2FA 实时刷新
    @Published public var remainingSeconds2FA: Int = 30
    @Published public var progress2FA: Double = 1.0
    @Published public var cachedCodes2FA: [UUID: String] = [:]

    // 用户设置 (持久化存储于本地 UserDefaults 并通知 UI 响应)
    // 默认值设为 0 (仅在系统睡眠/锁屏或手动 Command+L 时上锁，避免正常使用途中莫名自动上锁)
    @Published public var autoLockMinutes: Int = {
        if let val = UserDefaults.standard.object(forKey: "vaultAutoLockMinutes_v2") as? Int {
            return val
        }
        return 0
    }() {
        didSet {
            UserDefaults.standard.set(autoLockMinutes, forKey: "vaultAutoLockMinutes_v2")
            resetIdleTimer()
        }
    }
    @Published public var clipboardClearSeconds: Int = (UserDefaults.standard.object(forKey: "clipboardClearSeconds") as? Int) ?? 30 {
        didSet {
            UserDefaults.standard.set(clipboardClearSeconds, forKey: "clipboardClearSeconds")
        }
    }
    @Published public var touchIDEnabled: Bool = UserDefaults.standard.bool(forKey: "touchIDEnabled") {
        didSet {
            UserDefaults.standard.set(touchIDEnabled, forKey: "touchIDEnabled")
        }
    }
    @Published public var groupByCategory: Bool = (UserDefaults.standard.object(forKey: "groupByCategory") as? Bool) ?? true {
        didSet {
            UserDefaults.standard.set(groupByCategory, forKey: "groupByCategory")
        }
    }

    // 提示信息
    @Published public var clipboardStatusMessage: String? = nil

    // 内部私有属性
    private var masterPasswordCache: String? = nil
    private var timerCancellable: AnyCancellable?
    private var idleTimer: Timer?
    private var lastUserActivity: Date = Date()
    private var clipboardClearWorkItem: DispatchWorkItem?
    private var eventMonitor: Any?

    public init() {
        checkVaultExistence()
        setupNotificationObservers()
        setupActivityMonitor()
        start2FATimer()
    }

    // MARK: - 文件路径
    public var vaultDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("LocalVault", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public var vaultFileURL: URL {
        vaultDirectoryURL.appendingPathComponent("vault.enc")
    }

    public func checkVaultExistence() {
        isVaultCreated = FileManager.default.fileExists(atPath: vaultFileURL.path)
    }

    // MARK: - 创建与解锁
    public func createVault(masterPassword: String) throws {
        guard !masterPassword.isEmpty else {
            throw CryptoError.invalidMasterPassword
        }

        let sharedPass1 = "AlphaQuant_2026!#9"
        let sharedPass2 = "SubVault_9988$Xz"
        let initialPayload = VaultPayload(
            schemaVersion: 1,
            items: [
                AccountItem(
                    title: "Binance (示例加密账户)",
                    url: "https://www.binance.com",
                    category: .crypto,
                    customTag: "交易所",
                    isFavorite: true,
                    notes: "演示：同一名称下包含多个密码与多个账号，自动按密码分组展示，点击任意密码/账号/2FA即可一键复制。",
                    entries: [
                        CredentialEntry(
                            username: "trader_main@example.com",
                            password: sharedPass1,
                            totpSecret: "JBSWY3DPEHPK3PXP",
                            notes: "主现货交易号"
                        ),
                        CredentialEntry(
                            username: "quant_bot01@example.com",
                            password: sharedPass1,
                            totpSecret: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ",
                            notes: "同密码下的网格量化子号"
                        ),
                        CredentialEntry(
                            username: "hedge_sub02@binance.vip",
                            password: sharedPass2,
                            totpSecret: "JBSWY3DPEHPK3PXP",
                            notes: "另一套独立密码下的合约对冲子号"
                        )
                    ]
                ),
                AccountItem(
                    title: "GitHub (示例开发仓库)",
                    username: "developer@example.com",
                    password: PasswordGenerator.generate(),
                    url: "https://github.com",
                    category: .work,
                    customTag: "代码库",
                    isFavorite: true,
                    totpSecret: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ",
                    notes: "示例开发平台账号，含 RFC 6238 标准 2FA 动态码。"
                ),
                AccountItem(
                    title: "OpenAI API (示例 AI 服务)",
                    username: "ai-builder@example.com",
                    password: PasswordGenerator.generate(),
                    url: "https://platform.openai.com",
                    category: .ai,
                    customTag: "大模型",
                    isFavorite: false,
                    totpSecret: "",
                    notes: "示例 AI 与云服务分类账号，可在左侧或顶部按类型一键筛选。"
                )
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let plaintextData = try encoder.encode(initialPayload)

        let envelope = try CryptoEngine.encrypt(data: plaintextData, masterPassword: masterPassword)
        let envelopeData = try JSONEncoder().encode(envelope)
        try envelopeData.write(to: vaultFileURL, options: .atomic)

        self.masterPasswordCache = masterPassword
        self.items = initialPayload.items
        self.selectedItemId = initialPayload.items.first?.id
        self.isVaultCreated = true
        self.isUnlocked = true
        self.errorMessage = nil

        if touchIDEnabled && KeychainTouchIDHelper.isTouchIDAvailable() {
            try? KeychainTouchIDHelper.saveMasterPasswordForBiometrics(password: masterPassword)
        }

        update2FACodes()
        resetIdleTimer()
    }

    public func unlock(masterPassword: String) throws {
        guard FileManager.default.fileExists(atPath: vaultFileURL.path) else {
            throw CryptoError.invalidEnvelope
        }

        let envelopeData = try Data(contentsOf: vaultFileURL)
        let envelope = try JSONDecoder().decode(EncryptedEnvelope.self, from: envelopeData)
        let decryptedData = try CryptoEngine.decrypt(envelope: envelope, masterPassword: masterPassword)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(VaultPayload.self, from: decryptedData)

        self.masterPasswordCache = masterPassword
        self.items = payload.items
        self.selectedItemId = items.first?.id
        self.isUnlocked = true
        self.errorMessage = nil

        if touchIDEnabled && KeychainTouchIDHelper.isTouchIDAvailable() {
            try? KeychainTouchIDHelper.saveMasterPasswordForBiometrics(password: masterPassword)
        }

        update2FACodes()
        resetIdleTimer()
    }

    public func unlockWithTouchID() async {
        do {
            let password = try await KeychainTouchIDHelper.retrieveMasterPasswordWithBiometrics()
            try unlock(masterPassword: password)
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    /// 校验现有主密码并更新为新主密码（支持在登录锁屏页或已解锁设置页调用，100% 保留全部加密数据）
    public func changeMasterPassword(currentPassword: String, newPassword: String) throws {
        guard !currentPassword.isEmpty, newPassword.count >= 6 else {
            throw CryptoError.invalidMasterPassword
        }

        if isUnlocked {
            guard masterPasswordCache == currentPassword else {
                throw CryptoError.invalidMasterPassword
            }
            self.masterPasswordCache = newPassword
            try saveVault()
        } else {
            guard FileManager.default.fileExists(atPath: vaultFileURL.path) else {
                throw CryptoError.invalidEnvelope
            }
            let envelopeData = try Data(contentsOf: vaultFileURL)
            let envelope = try JSONDecoder().decode(EncryptedEnvelope.self, from: envelopeData)
            let decryptedData = try CryptoEngine.decrypt(envelope: envelope, masterPassword: currentPassword)

            let newEnvelope = try CryptoEngine.encrypt(data: decryptedData, masterPassword: newPassword)
            let newEnvelopeData = try JSONEncoder().encode(newEnvelope)
            try newEnvelopeData.write(to: vaultFileURL, options: .atomic)
        }

        if touchIDEnabled && KeychainTouchIDHelper.isTouchIDAvailable() {
            try? KeychainTouchIDHelper.saveMasterPasswordForBiometrics(password: newPassword)
        }
    }

    /// 在已解锁状态下直接重置主密码（无需输入旧主密码，保留全部现有账号数据）
    public func resetMasterPasswordDirectly(newPassword: String) throws {
        guard isUnlocked else {
            throw CryptoError.invalidMasterPassword
        }
        guard newPassword.count >= 6 else {
            throw CryptoError.invalidMasterPassword
        }

        self.masterPasswordCache = newPassword
        try saveVault()

        if touchIDEnabled && KeychainTouchIDHelper.isTouchIDAvailable() {
            try? KeychainTouchIDHelper.saveMasterPasswordForBiometrics(password: newPassword)
        }
    }

    /// 在锁屏状态下通过 Touch ID 验证读取旧密钥，并在保留全部数据的前提下重置为新主密码
    public func resetMasterPasswordWithTouchID(newPassword: String) async throws {
        guard newPassword.count >= 6 else {
            throw CryptoError.invalidMasterPassword
        }
        let savedPassword = try await KeychainTouchIDHelper.retrieveMasterPasswordWithBiometrics(
            prompt: "验证 Touch ID 指纹以重置 SecretCore 极光秘核主密码"
        )
        try unlock(masterPassword: savedPassword)
        try resetMasterPasswordDirectly(newPassword: newPassword)
    }

    /// 彻底清空并重新初始化本地密码库（删除加密文件与钥匙串缓存，回到首次设密状态）
    public func resetEntireVault() {
        lock()
        KeychainTouchIDHelper.deleteSavedMasterPassword()
        if FileManager.default.fileExists(atPath: vaultFileURL.path) {
            try? FileManager.default.removeItem(at: vaultFileURL)
        }
        self.isVaultCreated = false
        self.isUnlocked = false
        self.errorMessage = nil
    }

    /// 一键重置密码库并立即使用新主密码初始化解锁（专为忘记原密码后直接重设新密码设计）
    public func resetVaultAndCreateNew(newPassword: String) throws {
        guard newPassword.count >= 6 else {
            throw CryptoError.invalidMasterPassword
        }
        resetEntireVault()
        try createVault(masterPassword: newPassword)
    }

    public func syncTouchIDSetting(enabled: Bool) {
        touchIDEnabled = enabled
        if enabled, let masterPassword = masterPasswordCache {
            try? KeychainTouchIDHelper.saveMasterPasswordForBiometrics(password: masterPassword)
        } else if !enabled {
            KeychainTouchIDHelper.deleteSavedMasterPassword()
        }
    }

    public func lock() {
        isUnlocked = false
        masterPasswordCache = nil
        items = []
        selectedItemId = nil
        cachedCodes2FA.removeAll()
        idleTimer?.invalidate()
        idleTimer = nil
    }

    // MARK: - 保存数据
    public func saveVault() throws {
        guard isUnlocked, let masterPassword = masterPasswordCache else { return }

        let payload = VaultPayload(
            schemaVersion: 1,
            items: items,
            updatedAt: Date()
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let plaintextData = try encoder.encode(payload)

        let envelope = try CryptoEngine.encrypt(data: plaintextData, masterPassword: masterPassword)
        let envelopeData = try JSONEncoder().encode(envelope)
        try envelopeData.write(to: vaultFileURL, options: .atomic)
    }

    // MARK: - 账号增删改
    public func upsertItem(_ item: AccountItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.insert(item, at: 0)
        }
        selectedItemId = item.id
        try? saveVault()
        update2FACodes()
        recordActivity()
    }

    public func deleteItem(id: UUID) {
        items.removeAll { $0.id == id }
        if selectedItemId == id {
            selectedItemId = filteredItems.first?.id
        }
        try? saveVault()
        cachedCodes2FA.removeValue(forKey: id)
        recordActivity()
    }

    public func toggleFavorite(id: UUID) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].isFavorite.toggle()
            items[idx].updatedAt = Date()
            try? saveVault()
            recordActivity()
        }
    }

    public func updateCategory(id: UUID, category: AccountCategory) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].category = category
            items[idx].updatedAt = Date()
            try? saveVault()
            recordActivity()
        }
    }

    // MARK: - 同名称下多密码/多账号操作与智能归并
    public func appendEntry(toItemId id: UUID, entry: CredentialEntry) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].addOrUpdateEntry(entry)
        try? saveVault()
        update2FACodes()
        recordActivity()
    }

    public func removeEntry(fromItemId id: UUID, entryId: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].removeEntry(id: entryId)
        cachedCodes2FA.removeValue(forKey: entryId)
        try? saveVault()
        update2FACodes()
        recordActivity()
    }

    public func removePasswordGroup(fromItemId id: UUID, password: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].removePasswordGroup(password: password)
        try? saveVault()
        update2FACodes()
        recordActivity()
    }

    public func updateGroupPassword(inItemId id: UUID, oldPassword: String, newPassword: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].updateGroupPassword(oldPassword: oldPassword, newPassword: newPassword)
        try? saveVault()
        recordActivity()
    }

    public func findExistingItem(matchingTitle title: String, url: String) -> AccountItem? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // 1. 优先按域名/网址匹配
        if !cleanURL.isEmpty {
            let h2 = cleanURL
                .replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
                .replacingOccurrences(of: "www.", with: "")
                .components(separatedBy: "/").first ?? ""
            for item in items {
                let itemURL = item.url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !itemURL.isEmpty {
                    if itemURL == cleanURL { return item }
                    let h1 = itemURL
                        .replacingOccurrences(of: "https://", with: "")
                        .replacingOccurrences(of: "http://", with: "")
                        .replacingOccurrences(of: "www.", with: "")
                        .components(separatedBy: "/").first ?? ""
                    if !h1.isEmpty && !h2.isEmpty && h1 == h2 {
                        return item
                    }
                }
            }
        }

        // 2. 按服务名称匹配（如已有 "Binance" 或 "Binance (示例加密账户)"）
        if !cleanTitle.isEmpty {
            for item in items {
                let itemTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if itemTitle == cleanTitle {
                    return item
                }
                // 兼容带括号副标题的情况，如 "binance (示例加密账户)" 匹配 "binance"
                let baseItemTitle = itemTitle.components(separatedBy: " (").first?.components(separatedBy: "（").first?.trimmingCharacters(in: .whitespaces) ?? itemTitle
                let baseCleanTitle = cleanTitle.components(separatedBy: " (").first?.components(separatedBy: "（").first?.trimmingCharacters(in: .whitespaces) ?? cleanTitle
                if !baseItemTitle.isEmpty && baseItemTitle == baseCleanTitle {
                    return item
                }
            }
        }

        return nil
    }

    public func mergeOrInsertParsedCredentials(_ parsedList: [ParsedCredential], defaultCategory: AccountCategory = .general) {
        var mergedTitles: [String] = []
        var createdCount = 0
        var lastTargetId: UUID? = nil

        for parsed in parsedList {
            let entry = parsed.toCredentialEntry()
            if let existing = findExistingItem(matchingTitle: parsed.title, url: parsed.url),
               let idx = items.firstIndex(where: { $0.id == existing.id }) {
                items[idx].addOrUpdateEntry(entry)
                if items[idx].url.isEmpty && !parsed.url.isEmpty {
                    items[idx].url = parsed.url
                }
                lastTargetId = items[idx].id
                if !mergedTitles.contains(items[idx].title) {
                    mergedTitles.append(items[idx].title)
                }
            } else {
                let newItem = parsed.toAccountItem()
                items.insert(newItem, at: 0)
                lastTargetId = newItem.id
                createdCount += 1
            }
        }

        if let targetId = lastTargetId {
            selectedItemId = targetId
        }
        try? saveVault()
        update2FACodes()
        recordActivity()

        if !mergedTitles.isEmpty && createdCount == 0 {
            showStatusToast("✨ 已自动归并到「\(mergedTitles.joined(separator: "、"))」名下")
        } else if !mergedTitles.isEmpty && createdCount > 0 {
            showStatusToast("✨ 已归并至「\(mergedTitles.joined(separator: "、"))」并新建 \(createdCount) 项")
        } else if createdCount > 1 {
            showStatusToast("✨ 已智能识别并批量入库 \(createdCount) 条记录")
        } else if createdCount == 1, let first = items.first {
            showStatusToast("✨ 已自动识别并入库：\(first.title)")
        }
    }

    public var allCustomTags: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for item in items {
            let tag = item.normalizedCustomTag
            if !tag.isEmpty && !seen.contains(tag) {
                seen.insert(tag)
                result.append(tag)
            }
        }
        return result.sorted()
    }

    public func count(for filter: SidebarFilter) -> Int {
        switch filter {
        case .all:
            return items.count
        case .favorites:
            return items.filter { $0.isFavorite }.count
        case .has2FA:
            return items.filter { $0.hasTOTP }.count
        case .category(let cat):
            return items.filter { $0.category == cat }.count
        case .tag(let tag):
            return items.filter { $0.normalizedCustomTag.lowercased() == tag.lowercased() }.count
        }
    }

    // MARK: - 过滤项与按类型分组
    public var filteredItems: [AccountItem] {
        let baseItems: [AccountItem]
        switch currentFilter {
        case .all:
            baseItems = items
        case .favorites:
            baseItems = items.filter { $0.isFavorite }
        case .has2FA:
            baseItems = items.filter { $0.hasTOTP }
        case .category(let cat):
            baseItems = items.filter { $0.category == cat }
        case .tag(let tag):
            baseItems = items.filter { $0.normalizedCustomTag.lowercased() == tag.lowercased() }
        }

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            return baseItems
        }

        return baseItems.filter { item in
            item.title.lowercased().contains(query) ||
            item.username.lowercased().contains(query) ||
            item.url.lowercased().contains(query) ||
            item.notes.lowercased().contains(query) ||
            item.category.rawValue.lowercased().contains(query) ||
            item.normalizedCustomTag.lowercased().contains(query) ||
            item.entries.contains(where: {
                $0.username.lowercased().contains(query) ||
                $0.password.lowercased().contains(query) ||
                $0.notes.lowercased().contains(query)
            })
        }
    }

    public var itemsGroupedByCategory: [(category: AccountCategory, items: [AccountItem])] {
        let current = filteredItems
        return AccountCategory.allCases.compactMap { cat in
            let matches = current.filter { $0.category == cat }
            return matches.isEmpty ? nil : (category: cat, items: matches)
        }
    }

    public var selectedItem: AccountItem? {
        if let id = selectedItemId {
            return items.first { $0.id == id }
        }
        return filteredItems.first
    }

    // MARK: - 2FA 实时计算与定时器
    private func start2FATimer() {
        update2FATime()
        timerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.update2FATime()
                if self.isUnlocked {
                    self.update2FACodes()
                }
            }
    }

    private func update2FATime() {
        let status = TOTPEngine.timeStatus(period: 30)
        self.remainingSeconds2FA = status.remainingSeconds
        self.progress2FA = status.progress
    }

    public func update2FACodes() {
        for item in items {
            if item.hasTOTP {
                if let code = try? TOTPEngine.generateCode(
                    secret: item.totpSecret,
                    period: item.totpPeriod,
                    digits: item.totpDigits,
                    algorithm: item.totpAlgorithm
                ) {
                    cachedCodes2FA[item.id] = code
                } else {
                    cachedCodes2FA[item.id] = "密钥错误"
                }
            }

            for entry in item.entries where entry.hasTOTP {
                if let code = try? TOTPEngine.generateCode(
                    secret: entry.totpSecret,
                    period: entry.totpPeriod,
                    digits: entry.totpDigits,
                    algorithm: entry.totpAlgorithm
                ) {
                    cachedCodes2FA[entry.id] = code
                } else {
                    cachedCodes2FA[entry.id] = "密钥错误"
                }
            }
        }
    }

    public func code(for item: AccountItem) -> String {
        return cachedCodes2FA[item.id] ?? "------"
    }

    public func formattedCode(for item: AccountItem) -> String {
        return formatRaw2FACode(code(for: item))
    }

    public func code(for entry: CredentialEntry) -> String {
        if let cached = cachedCodes2FA[entry.id] {
            return cached
        }
        if let generated = try? TOTPEngine.generateCode(
            secret: entry.totpSecret,
            period: entry.totpPeriod,
            digits: entry.totpDigits,
            algorithm: entry.totpAlgorithm
        ) {
            return generated
        }
        return "密钥错误"
    }

    public func formattedCode(for entry: CredentialEntry) -> String {
        return formatRaw2FACode(code(for: entry))
    }

    private func formatRaw2FACode(_ raw: String) -> String {
        if raw.count == 6 {
            let prefix = raw.prefix(3)
            let suffix = raw.suffix(3)
            return "\(prefix) \(suffix)"
        } else if raw.count == 8 {
            let prefix = raw.prefix(4)
            let suffix = raw.suffix(4)
            return "\(prefix) \(suffix)"
        }
        return raw
    }

    // MARK: - 剪贴板安全管理（自动定时清空）
    public func copyToClipboard(text: String, label: String = "内容") {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        recordActivity()

        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayLabel = trimmed.isEmpty ? "内容" : trimmed

        let seconds = clipboardClearSeconds
        if seconds > 0 {
            clipboardStatusMessage = "已复制 \(displayLabel) · \(seconds)秒后自动清空剪贴板"

            clipboardClearWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    guard let self = self else { return }
                    if let current = NSPasteboard.general.string(forType: .string), current == text {
                        NSPasteboard.general.clearContents()
                        self.clipboardStatusMessage = "安全防护：剪贴板已自动清空"
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        if self.clipboardStatusMessage == "安全防护：剪贴板已自动清空" {
                            self.clipboardStatusMessage = nil
                        }
                    }
                }
            }
            clipboardClearWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds), execute: workItem)
        } else {
            clipboardStatusMessage = "已复制 \(displayLabel)"
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if self.clipboardStatusMessage?.starts(with: "已复制") == true {
                self.clipboardStatusMessage = nil
            }
        }
    }

    public func showStatusToast(_ message: String) {
        clipboardStatusMessage = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            if self.clipboardStatusMessage == message {
                self.clipboardStatusMessage = nil
            }
        }
    }

    /// 从系统剪贴板读取文本，并调用 SmartCredentialParser 智能识别直接入库
    @discardableResult
    public func smartAddFromClipboard(defaultCategory: AccountCategory = .general) -> Bool {
        guard let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !clip.isEmpty else {
            showStatusToast("剪贴板当前为空，请先复制「网址 账号 密码 2fa(...)」")
            return false
        }

        let batch = SmartCredentialParser.parseBatch(clip, defaultCategory: defaultCategory)
        let validItems = batch.filter {
            !$0.username.isEmpty || !$0.password.isEmpty || !$0.totpSecret.isEmpty || !$0.url.isEmpty
        }

        guard !validItems.isEmpty else {
            showStatusToast("未识别到有效账号信息，请点击「✨ 智能添加」粘贴调整")
            return false
        }

        mergeOrInsertParsedCredentials(validItems, defaultCategory: defaultCategory)
        return true
    }

    // MARK: - 闲置自动上锁 & 锁屏监听
    public func recordActivity() {
        lastUserActivity = Date()
    }

    private func setupActivityMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .keyDown, .scrollWheel
        ]) { [weak self] event in
            Task { @MainActor in
                self?.recordActivity()
            }
            return event
        }
    }

    private func resetIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = nil
        recordActivity() // 每次解锁或重置计时器时立即刷新活跃时间，杜绝刚解锁 15 秒就被误判超时锁屏的 Bug

        guard autoLockMinutes > 0 else { return }

        let interval = TimeInterval(autoLockMinutes * 60)
        idleTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isUnlocked else { return }
                if Date().timeIntervalSince(self.lastUserActivity) >= interval {
                    self.lock()
                }
            }
        }
    }

    private func setupNotificationObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.lock()
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.lock()
            }
        }
    }

    // MARK: - 导出与导入
    public func exportEncryptedBackup(to destinationURL: URL) throws {
        guard FileManager.default.fileExists(atPath: vaultFileURL.path) else {
            throw CryptoError.invalidEnvelope
        }
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: vaultFileURL, to: destinationURL)
    }

    public func exportPlaintextJSON(to destinationURL: URL) throws {
        guard isUnlocked else { throw CryptoError.invalidMasterPassword }
        let payload = VaultPayload(schemaVersion: 1, items: items, updatedAt: Date())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try data.write(to: destinationURL, options: .atomic)
    }

    public func importFromPlaintextJSON(from sourceURL: URL) throws -> Int {
        guard isUnlocked else { throw CryptoError.invalidMasterPassword }
        let data = try Data(contentsOf: sourceURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(VaultPayload.self, from: data)

        var count = 0
        for item in payload.items {
            if !items.contains(where: { $0.id == item.id || ($0.title == item.title && $0.username == item.username) }) {
                items.append(item)
                count += 1
            }
        }
        try saveVault()
        update2FACodes()
        return count
    }
}
