import SwiftUI
import AppKit

// MARK: - 可手输自定义标签，同时带下拉预设词库选择的通用标签组件
public struct EditableTagField: View {
    @Binding public var text: String
    public var presets: [String]
    public var placeholder: String
    public var accentColor: Color

    public init(
        text: Binding<String>,
        presets: [String],
        placeholder: String = "标签",
        accentColor: Color = .blue
    ) {
        self._text = text
        self.presets = presets
        self.placeholder = placeholder
        self.accentColor = accentColor
    }

    public var body: some View {
        HStack(spacing: 2) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundColor(accentColor)
                .lineLimit(1)

            Menu {
                Text("常用标签预设").font(.caption)
                Divider()
                ForEach(presets, id: \.self) { preset in
                    Button(preset) {
                        text = preset
                    }
                }
            } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(accentColor.opacity(0.85))
                    .frame(width: 14, height: 18)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .frame(width: 80)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(accentColor.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(accentColor.opacity(0.28), lineWidth: 0.8)
        )
    }
}

@MainActor
public final class ItemEditorViewModel: ObservableObject {
    // 智能识别原始输入文本
    @Published public var rawSmartInput: String = ""

    // 批量识别结果（当用户一次性粘贴多行独立账号时自动激活）
    @Published public var batchItems: [ParsedCredential] = []

    // 单条服务基础信息
    @Published public var title: String = ""
    @Published public var url: String = ""
    @Published public var category: AccountCategory = .general
    @Published public var isFavorite: Bool = false
    @Published public var recognizedBadges: [String] = []

    // 子账号列表管理 (entries，支持 3 个或更多任意数量子账号)
    @Published public var entries: [CredentialEntry] = []
    @Published public var selectedEntryIndex: Int = 0

    // 当前正在编辑的子账号双向绑定字段
    @Published public var currentAccountLabel: String = "账号"
    @Published public var currentUsername: String = ""
    @Published public var currentPasswordLabel: String = "密码"
    @Published public var currentPassword: String = ""
    @Published public var currentExtraPasswords: [LabeledPassword] = []
    @Published public var currentTotpSecret: String = ""
    @Published public var currentEntryNotes: String = ""

    // 全局安全备注与多条结构化备注
    @Published public var notes: String = ""
    @Published public var noteEntries: [NoteEntry] = []

    @Published public var errorMessage: String? = nil
    @Published public var statusHint: String? = nil

    public let editingItem: AccountItem?
    public let defaultCategory: AccountCategory

    public init(editingItem: AccountItem? = nil, defaultCategory: AccountCategory = .general) {
        self.editingItem = editingItem
        self.defaultCategory = defaultCategory

        if let item = editingItem {
            self.title = item.title
            self.url = item.url
            self.category = item.category
            self.isFavorite = item.isFavorite
            self.notes = item.notes
            self.noteEntries = item.effectiveNoteEntries

            if !item.entries.isEmpty {
                self.entries = item.entries
            } else {
                self.entries = [
                    CredentialEntry(
                        username: item.username,
                        password: item.password,
                        totpSecret: item.totpSecret,
                        notes: item.notes
                    )
                ]
            }
            self.selectedEntryIndex = 0
            loadCurrentEntryFields()
        } else {
            self.category = defaultCategory
            self.entries = [CredentialEntry()]
            self.selectedEntryIndex = 0
            loadCurrentEntryFields()
        }
    }

    // 兼容旧属性访问
    public var username: String {
        get { currentUsername }
        set { currentUsername = newValue }
    }
    public var password: String {
        get { currentPassword }
        set { currentPassword = newValue }
    }
    public var totpSecret: String {
        get { currentTotpSecret }
        set { currentTotpSecret = newValue }
    }

    public var effectiveAccountLabel: String {
        let trimmed = currentAccountLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "账号" : trimmed
    }

    public var effectivePasswordLabel: String {
        let trimmed = currentPasswordLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "密码" : trimmed
    }

    /// 载入当前选中子账号的数据至表单输入框
    public func loadCurrentEntryFields() {
        guard entries.indices.contains(selectedEntryIndex) else {
            if entries.isEmpty {
                entries.append(CredentialEntry())
            }
            selectedEntryIndex = 0
            loadCurrentEntryFields()
            return
        }
        let e = entries[selectedEntryIndex]
        currentAccountLabel = e.accountLabel.isEmpty ? "账号" : e.accountLabel
        currentUsername = e.username
        currentPasswordLabel = e.passwordLabel.isEmpty ? "密码" : e.passwordLabel
        currentPassword = e.password
        currentExtraPasswords = e.extraPasswords
        currentTotpSecret = e.totpSecret
        currentEntryNotes = e.notes
    }

    /// 将当前表单输入框的字段冲刷保存到 entries 列表中对应项
    public func flushCurrentEntryFields() {
        guard entries.indices.contains(selectedEntryIndex) else { return }
        entries[selectedEntryIndex].accountLabel = currentAccountLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "账号" : currentAccountLabel
        entries[selectedEntryIndex].username = currentUsername
        entries[selectedEntryIndex].passwordLabel = currentPasswordLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "密码" : currentPasswordLabel
        entries[selectedEntryIndex].password = currentPassword
        entries[selectedEntryIndex].extraPasswords = currentExtraPasswords
        entries[selectedEntryIndex].totpSecret = currentTotpSecret
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        entries[selectedEntryIndex].notes = currentEntryNotes
        entries[selectedEntryIndex].updatedAt = Date()
    }

    /// 切换选中的子账号
    public func selectEntry(at index: Int) {
        guard index != selectedEntryIndex, entries.indices.contains(index) else { return }
        flushCurrentEntryFields()
        selectedEntryIndex = index
        loadCurrentEntryFields()
    }

    /// 获取任意下标子账号的实时摘要（用于下拉菜单与胶囊标签实时显示）
    public func entrySummary(at index: Int) -> (label: String, username: String) {
        if index == selectedEntryIndex {
            let lbl = currentAccountLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            return (lbl.isEmpty ? "账号" : lbl, currentUsername.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard entries.indices.contains(index) else {
            return ("账号", "")
        }
        let e = entries[index]
        let lbl = e.accountLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return (lbl.isEmpty ? "账号" : lbl, e.username.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// 随时添加第 3、第 4、第 N 个子账号（继承当前密码，可自定义标签与账号）
    public func addNewSubAccount() {
        flushCurrentEntryFields()
        let newIdx = entries.count + 1
        let inheritedPassword = currentPassword
        let newEntry = CredentialEntry(
            accountLabel: "账号",
            username: "",
            passwordLabel: "密码",
            password: inheritedPassword,
            extraPasswords: [],
            totpSecret: "",
            notes: ""
        )
        entries.append(newEntry)
        selectedEntryIndex = entries.count - 1
        loadCurrentEntryFields()
        statusHint = "已添加子账号 #\(newIdx)"
    }

    /// 删除指定下标的子账号（总数需大于 1）
    public func removeSubAccount(at index: Int) {
        guard entries.count > 1, entries.indices.contains(index) else { return }
        flushCurrentEntryFields()
        entries.remove(at: index)
        if selectedEntryIndex >= entries.count {
            selectedEntryIndex = max(0, entries.count - 1)
        }
        loadCurrentEntryFields()
        statusHint = "已删除子账号"
    }

    /// 添加从属额外密码
    public func addExtraPassword(label: String = "资金密码", value: String = "") {
        currentExtraPasswords.append(LabeledPassword(label: label, value: value))
    }

    /// 删除从属额外密码
    public func removeExtraPassword(at index: Int) {
        guard currentExtraPasswords.indices.contains(index) else { return }
        currentExtraPasswords.remove(at: index)
    }

    /// 添加自定义备注条目
    public func addNoteEntry(label: String = "备注", content: String = "") {
        if noteEntries.isEmpty && !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            noteEntries.append(NoteEntry(label: "备注1", content: notes.trimmingCharacters(in: .whitespacesAndNewlines)))
            notes = ""
            let nextLbl = label == "备注" ? "备注2" : label
            noteEntries.append(NoteEntry(label: nextLbl, content: content))
        } else {
            noteEntries.append(NoteEntry(label: label, content: content))
        }
    }

    /// 删除自定义备注条目
    public func removeNoteEntry(at index: Int) {
        guard noteEntries.indices.contains(index) else { return }
        noteEntries.remove(at: index)
    }

    /// 当用户在智能识别框输入或粘贴文本时，实时解析
    public func parseSmartInput(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            batchItems = []
            if editingItem == nil {
                title = ""
                url = ""
                entries = [CredentialEntry()]
                selectedEntryIndex = 0
                loadCurrentEntryFields()
                noteEntries = []
                notes = ""
                recognizedBadges = []
                category = defaultCategory
            }
            return
        }

        let batch = SmartCredentialParser.parseBatch(trimmed, defaultCategory: defaultCategory)
        if batch.count > 1 {
            batchItems = batch
            if let first = batch.first {
                applyParsed(first)
            }
        } else {
            batchItems = []
            let parsed = SmartCredentialParser.parse(trimmed, defaultCategory: defaultCategory)
            applyParsed(parsed)
        }
    }

    private func applyParsed(_ parsed: ParsedCredential) {
        if !parsed.title.isEmpty { self.title = parsed.title }
        if !parsed.url.isEmpty { self.url = parsed.url }
        if parsed.category != .general || self.category == .general { self.category = parsed.category }
        self.recognizedBadges = parsed.recognizedFields

        if !parsed.accountLabel.isEmpty { self.currentAccountLabel = parsed.accountLabel }
        if !parsed.username.isEmpty { self.currentUsername = parsed.username }
        if !parsed.passwordLabel.isEmpty { self.currentPasswordLabel = parsed.passwordLabel }
        if !parsed.password.isEmpty { self.currentPassword = parsed.password }
        if !parsed.totpSecret.isEmpty { self.currentTotpSecret = parsed.totpSecret }
        if !parsed.extraPasswords.isEmpty { self.currentExtraPasswords = parsed.extraPasswords }
        if !parsed.notes.isEmpty {
            if self.notes.isEmpty {
                self.notes = parsed.notes
            } else if !self.notes.contains(parsed.notes) {
                self.notes += "\n" + parsed.notes
            }
        }
        if !parsed.noteEntries.isEmpty {
            self.noteEntries = parsed.noteEntries
        }
        flushCurrentEntryFields()
    }

    /// 从系统剪贴板一键读取并智能识别
    public func pasteAndRecognizeFromClipboard() {
        if let clip = NSPasteboard.general.string(forType: .string),
           !clip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rawSmartInput = clip
            parseSmartInput(clip)
            statusHint = "已从剪贴板读取并完成自动识别"
        } else {
            statusHint = "剪贴板当前为空"
        }
    }

    /// 填入演示示例
    public func fillExample() {
        let sample = "xxxx.com   密码：xxx密码   账号：xxx账号   2FA：JBSWY3DPEHPK3PXP"
        rawSmartInput = sample
        parseSmartInput(sample)
        statusHint = "已填入统一格式示例：密码：xxx   账号：xxx   2FA：xxx"
    }

    public func clearAll() {
        rawSmartInput = ""
        parseSmartInput("")
        statusHint = nil
        errorMessage = nil
    }

    public var hasValidContentToSave: Bool {
        if batchItems.count > 1 {
            return true
        }
        let hasIdentity = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          !currentUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          entries.contains { !$0.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let hasSecret = !currentPassword.isEmpty ||
                        !currentTotpSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        !currentUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        entries.contains { !$0.password.isEmpty || !$0.username.isEmpty }
        return hasIdentity && hasSecret
    }

    /// 实时预览 2FA 验证码（若密钥为合法 Base32 则返回 6 位动态码）
    public var liveTOTPPreviewCode: String? {
        let cleaned = currentTotpSecret
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return try? TOTPEngine.generateCode(secret: cleaned, date: Date())
    }
}

public struct ItemEditorSheet: View {
    @EnvironmentObject private var store: VaultStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: ItemEditorViewModel

    public init(editingItem: AccountItem? = nil, defaultCategory: AccountCategory = .general) {
        _vm = StateObject(wrappedValue: ItemEditorViewModel(editingItem: editingItem, defaultCategory: defaultCategory))
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 1. 顶部科技感标题栏
            headerBar

            Divider().opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // 2. 智能识别粘贴区
                    smartInputSection

                    // 3. 实时解析结果预览与微调卡片
                    if vm.batchItems.count > 1 {
                        batchPreviewSection
                    } else {
                        singlePreviewAndAdjustSection
                    }
                }
                .padding(22)
            }

            Divider().opacity(0.5)

            // 4. 底部操作栏
            bottomActionBar
        }
        .frame(width: 610, height: 625)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.98, blue: 1.0),
                    Color(red: 0.93, green: 0.96, blue: 0.99)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    // MARK: - 1. 顶部栏
    private var headerBar: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.05, green: 0.52, blue: 0.98),
                                Color(red: 0.25, green: 0.35, blue: 0.95)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .shadow(color: Color.blue.opacity(0.25), radius: 6, x: 0, y: 3)

                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(vm.editingItem == nil ? "智能识别添加" : "智能管理与更新记录")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.08, green: 0.13, blue: 0.24))

                    Text("MULTI-ACCOUNT SUPPORT")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundColor(Color(red: 0.04, green: 0.48, blue: 0.92))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.04, green: 0.48, blue: 0.92).opacity(0.12))
                        )
                }

                Text("支持管理 3 个以上任意子账号，账号、密码与备注均可自定义命名")
                    .font(.system(size: 11.5))
                    .foregroundColor(Color(red: 0.38, green: 0.46, blue: 0.58))
            }

            Spacer()

            Button(action: {
                dismiss()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Color.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.75))
    }

    // MARK: - 2. 智能识别输入区
    private var smartInputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("一键粘贴原始文本", systemImage: "text.viewfinder")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(Color(red: 0.12, green: 0.20, blue: 0.34))

                Spacer()

                // 快捷操作按钮组
                HStack(spacing: 8) {
                    Button(action: {
                        vm.pasteAndRecognizeFromClipboard()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.clipboard.fill")
                                .font(.system(size: 10.5))
                            Text("粘贴剪贴板并识别")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.05, green: 0.52, blue: 0.98), Color(red: 0.22, green: 0.38, blue: 0.95)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        vm.fillExample()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 10.5))
                            Text("填入示例")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(Color(red: 0.06, green: 0.46, blue: 0.88))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.06, green: 0.46, blue: 0.88).opacity(0.10))
                        )
                    }
                    .buttonStyle(.plain)

                    Button(action: handlePickQRImage) {
                        HStack(spacing: 4) {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.system(size: 10.5))
                            Text("识别二维码图")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(Color(red: 0.25, green: 0.35, blue: 0.50))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.05))
                        )
                    }
                    .buttonStyle(.plain)

                    if !vm.rawSmartInput.isEmpty {
                        Button(action: {
                            vm.clearAll()
                        }) {
                            Text("清空")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.red.opacity(0.8))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.red.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: Binding(
                    get: { vm.rawSmartInput },
                    set: { newVal in
                        vm.rawSmartInput = newVal
                        vm.parseSmartInput(newVal)
                    }
                ))
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(height: 82)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            !vm.rawSmartInput.isEmpty
                                ? Color(red: 0.05, green: 0.55, blue: 0.98).opacity(0.55)
                                : Color(red: 0.72, green: 0.80, blue: 0.90).opacity(0.65),
                            lineWidth: 1.4
                        )
                )

                if vm.rawSmartInput.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("在此直接粘贴（支持单行/空格/Tab分隔、统一格式或多行批量）：")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(Color.secondary.opacity(0.75))
                        Text("统一格式：xxxx.com   密码：xxx   账号：xxx   2FA：xxxx")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundColor(Color(red: 0.15, green: 0.48, blue: 0.88).opacity(0.75))
                        Text("兼容格式：binance.com   Pass123!   user@gmail.com   2fa(JBSWY3DPEHPK3PXP)")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundColor(Color.secondary.opacity(0.65))
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
                }
            }

            // 识别状态胶囊条
            if !vm.recognizedBadges.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 0.04, green: 0.68, blue: 0.45))

                    Text("已自动提取：")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(red: 0.15, green: 0.25, blue: 0.38))

                    ForEach(vm.recognizedBadges, id: \.self) { badge in
                        Text(badge)
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(Color(red: 0.04, green: 0.54, blue: 0.40))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color(red: 0.04, green: 0.68, blue: 0.45).opacity(0.12))
                            )
                    }

                    Spacer()
                }
            }
        }
    }

    // MARK: - 3A. 单条实时解析与微调卡片
    private var singlePreviewAndAdjustSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 顶部：自动匹配图标 + 网站/服务名 + 网址 + 分类选择
            HStack(spacing: 12) {
                let previewItem = AccountItem(
                    title: vm.title.isEmpty ? (vm.url.isEmpty ? "待识别" : vm.url) : vm.title,
                    url: vm.url,
                    category: vm.category
                )
                AccountAvatarView(item: previewItem, size: 44, showFavoriteBadge: false)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("名称：")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 44, alignment: .leading)

                        TextField("服务名称 (如 Binance / xxxx.com)", text: $vm.title)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13.5, weight: .bold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Color(red: 0.95, green: 0.97, blue: 1.0)))
                    }

                    HStack(spacing: 8) {
                        Text("网址：")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 44, alignment: .leading)

                        TextField("域名或网址 (如 xxxx.com)", text: $vm.url)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5, design: .monospaced))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Color(red: 0.95, green: 0.97, blue: 1.0)))
                    }
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 6) {
                    Text("所属分类:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Picker("", selection: $vm.category) {
                        ForEach(AccountCategory.allCases) { cat in
                            Text(cat.rawValue).tag(cat)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(red: 0.05, green: 0.52, blue: 0.98).opacity(0.15), lineWidth: 1)
            )

            // 核心：子账号多账号管理与凭据编辑卡片
            VStack(spacing: 12) {
                // 子账号下拉选择与管理栏
                subAccountsSelectorSection

                Divider().opacity(0.5)

                // 账号行（支持手输自定义标签 + 词库预设）
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Color(red: 0.12, green: 0.52, blue: 0.96))
                        .frame(width: 22)

                    EditableTagField(
                        text: $vm.currentAccountLabel,
                        presets: CredentialLabelPresets.accountPresets,
                        placeholder: "账号",
                        accentColor: Color(red: 0.12, green: 0.52, blue: 0.96)
                    )

                    TextField("\(vm.effectiveAccountLabel)：xxx（输入或修改账号/用户名/邮箱）", text: $vm.currentUsername)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(red: 0.95, green: 0.97, blue: 1.0))
                        )
                }

                // 密码行（支持手输自定义标签 + 词库预设 + 随机生成）
                HStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Color(red: 0.95, green: 0.55, blue: 0.12))
                        .frame(width: 22)

                    EditableTagField(
                        text: $vm.currentPasswordLabel,
                        presets: CredentialLabelPresets.passwordPresets,
                        placeholder: "密码",
                        accentColor: Color(red: 0.95, green: 0.55, blue: 0.12)
                    )

                    HStack(spacing: 6) {
                        TextField("\(vm.effectivePasswordLabel)：xxx（输入或修改密码）", text: $vm.currentPassword)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))

                        Button(action: {
                            vm.currentPassword = PasswordGenerator.generate(options: PasswordGeneratorOptions(length: 18))
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "dice.fill")
                                    .font(.system(size: 10))
                                Text("随机生成")
                                    .font(.system(size: 10.5, weight: .medium))
                            }
                            .foregroundColor(Color(red: 0.25, green: 0.38, blue: 0.58))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(Capsule().fill(Color.black.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                        .help("随机生成 18 位高强度密码")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(red: 0.95, green: 0.97, blue: 1.0))
                    )
                }

                // 从属额外密码（如资金密码、支付密码、API Key 等）
                ForEach(Array(vm.currentExtraPasswords.enumerated()), id: \.element.id) { extraIdx, extra in
                    HStack(spacing: 8) {
                        Image(systemName: "key.badge.ellipsis")
                            .font(.system(size: 12))
                            .foregroundColor(.purple)
                            .frame(width: 22)

                        EditableTagField(
                            text: Binding(
                                get: { vm.currentExtraPasswords[extraIdx].label },
                                set: { vm.currentExtraPasswords[extraIdx].label = $0 }
                            ),
                            presets: CredentialLabelPresets.passwordPresets,
                            placeholder: "资金密码",
                            accentColor: .purple
                        )

                        HStack(spacing: 6) {
                            TextField("从属密码值", text: Binding(
                                get: { vm.currentExtraPasswords[extraIdx].value },
                                set: { vm.currentExtraPasswords[extraIdx].value = $0 }
                            ))
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))

                            Button(action: {
                                vm.removeExtraPassword(at: extraIdx)
                            }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .foregroundColor(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            .help("删除此项从属密码")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.purple.opacity(0.05))
                        )
                    }
                }

                // 添加从属额外密码按钮
                HStack {
                    Button(action: {
                        vm.addExtraPassword(label: "资金密码", value: "")
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 11))
                            Text("➕ 添加从属密码（如资金密码/支付密码/API Key）")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.purple)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 30)

                    Spacer()
                }

                // 2FA 密钥行 + 动态码即时演算预览
                HStack(spacing: 8) {
                    Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                        .font(.system(size: 13))
                        .foregroundColor(Color(red: 0.06, green: 0.70, blue: 0.48))
                        .frame(width: 22)

                    HStack(spacing: 3) {
                        Text("2FA 验证：")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundColor(Color(red: 0.06, green: 0.70, blue: 0.48))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .frame(width: 80, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(red: 0.06, green: 0.70, blue: 0.48).opacity(0.09))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color(red: 0.06, green: 0.70, blue: 0.48).opacity(0.28), lineWidth: 0.8)
                    )

                    HStack(spacing: 6) {
                        TextField("2FA：xxxx（Base32 密钥或 2fa(xxxx)）", text: $vm.currentTotpSecret)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))

                        if let code = vm.liveTOTPPreviewCode {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                                Text("动态码: \(code)")
                                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(red: 0.04, green: 0.55, blue: 0.38))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Capsule().fill(Color.green.opacity(0.12)))
                        } else if !vm.currentTotpSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("已记录密钥")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2.5)
                                .background(Capsule().fill(Color.orange.opacity(0.12)))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(red: 0.95, green: 0.97, blue: 1.0))
                    )
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(red: 0.05, green: 0.52, blue: 0.98).opacity(0.18), lineWidth: 1)
            )

            // 安全备注卡片（支持自定义标签与多条备注）
            notesSection
        }
    }

    // MARK: - 子账号多账号管理与下拉切换器
    private var subAccountsSelectorSection: some View {
        HStack(spacing: 10) {
            // 子账号下拉选择器 Menu
            Menu {
                ForEach(Array(vm.entries.enumerated()), id: \.element.id) { idx, entry in
                    let isSelected = (idx == vm.selectedEntryIndex)
                    let summary = vm.entrySummary(at: idx)
                    let userText = summary.username.isEmpty ? "未填写" : summary.username
                    let labelPart = (summary.label.isEmpty || summary.label == "账号") ? "" : " [\(summary.label)]"
                    let checkPrefix = isSelected ? "✓ " : "    "
                    let itemTitle = "\(checkPrefix)子账号 #\(idx + 1)\(labelPart)：\(userText)"

                    Button(action: {
                        vm.selectEntry(at: idx)
                    }) {
                        Text(itemTitle)
                    }
                }

                Divider()

                Button(action: {
                    vm.addNewSubAccount()
                }) {
                    Label("添加新子账号（第 \(vm.entries.count + 1) 个）", systemImage: "plus.circle")
                }

                if vm.entries.count > 1 {
                    Button(role: .destructive, action: {
                        vm.removeSubAccount(at: vm.selectedEntryIndex)
                    }) {
                        Label("删除当前子账号", systemImage: "trash")
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .foregroundColor(Color.blue)
                        .font(.system(size: 13, weight: .bold))

                    let summary = vm.entrySummary(at: vm.selectedEntryIndex)
                    let userText = summary.username.isEmpty ? "未填写" : summary.username
                    let labelPart = (summary.label.isEmpty || summary.label == "账号") ? "" : " [\(summary.label)]"
                    Text("当前：子账号 #\(vm.selectedEntryIndex + 1)\(labelPart)：\(userText) [\(vm.selectedEntryIndex + 1)/\(vm.entries.count)]")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.blue.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.blue.opacity(0.25), lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            // 右侧快捷操作按钮：➕ 添加子账号
            Button(action: {
                vm.addNewSubAccount()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("添加子账号")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.05, green: 0.52, blue: 0.98), Color(red: 0.22, green: 0.38, blue: 0.95)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("随时添加第 3、第 4、第 N 个子账号，无数量限制")

            // 当子账号大于 1 个时，提供删除当前子账号按钮
            if vm.entries.count > 1 {
                Button(action: {
                    vm.removeSubAccount(at: vm.selectedEntryIndex)
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "trash")
                            .font(.system(size: 10.5))
                        Text("删除此号")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.red.opacity(0.85))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4.5)
                    .background(Capsule().fill(Color.red.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help("删除当前正在查看的子账号")
            }
        }
    }

    // MARK: - 安全备注与说明卡片（支持自定义标签与多条备注）
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "note.text")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 20)

                Text("安全备注与附加说明（支持自定义标签）：")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(red: 0.22, green: 0.30, blue: 0.42))

                Spacer()

                Button(action: {
                    let nextNum = vm.noteEntries.count + 1
                    vm.addNoteEntry(label: "备注\(nextNum)", content: "")
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 10.5))
                        Text("添加自定义备注条目")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(Color.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(Capsule().fill(Color.blue.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }

            if vm.noteEntries.isEmpty {
                // 自由单文本备注框
                HStack(spacing: 8) {
                    EditableTagField(
                        text: .constant("备注"),
                        presets: CredentialLabelPresets.notePresets,
                        placeholder: "备注",
                        accentColor: .secondary
                    )

                    TextField("可选补充说明（自由备注、密保问题或恢复码）", text: $vm.notes)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(red: 0.95, green: 0.97, blue: 1.0))
                        )
                }
            } else {
                // 多条结构化自定义备注行
                VStack(spacing: 8) {
                    ForEach(Array(vm.noteEntries.enumerated()), id: \.element.id) { noteIdx, note in
                        HStack(spacing: 8) {
                            EditableTagField(
                                text: Binding(
                                    get: { vm.noteEntries[noteIdx].label },
                                    set: { vm.noteEntries[noteIdx].label = $0 }
                                ),
                                presets: CredentialLabelPresets.notePresets,
                                placeholder: "备注",
                                accentColor: .secondary
                            )

                            HStack(spacing: 6) {
                                TextField("备注内容（如 备注+8、密保答案等）", text: Binding(
                                    get: { vm.noteEntries[noteIdx].content },
                                    set: { vm.noteEntries[noteIdx].content = $0 }
                                ))
                                .textFieldStyle(.plain)
                                .font(.system(size: 12.5))

                                Button(action: {
                                    vm.removeNoteEntry(at: noteIdx)
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundColor(.red.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                                .help("删除此项备注")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(red: 0.95, green: 0.97, blue: 1.0))
                            )
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - 3B. 多行批量识别预览
    private var batchPreviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundColor(.blue)
                Text("已自动识别出 \(vm.batchItems.count) 条独立账号记录（点击右下角可一次性全部入库）")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(Color(red: 0.12, green: 0.20, blue: 0.34))
                Spacer()
            }

            VStack(spacing: 8) {
                ForEach(vm.batchItems) { item in
                    HStack(spacing: 12) {
                        AccountAvatarView(item: item.toAccountItem(), size: 34, showFavoriteBadge: false)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(item.title)
                                    .font(.system(size: 13, weight: .bold))
                                Text(item.category.rawValue)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(item.category.tintColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(item.category.tintColor.opacity(0.12)))
                            }

                            HStack(spacing: 12) {
                                if !item.password.isEmpty {
                                    Text("\(item.passwordLabel)：\(item.password)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                if !item.username.isEmpty {
                                    Text("\(item.accountLabel)：\(item.username)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                if !item.totpSecret.isEmpty {
                                    Text("2FA：\(item.totpSecret)")
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundColor(Color(red: 0.04, green: 0.58, blue: 0.42))
                                }
                            }
                        }

                        Spacer()
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.blue.opacity(0.15), lineWidth: 1)
                    )
                }
            }
        }
    }

    // MARK: - 4. 底部保存操作栏
    private var bottomActionBar: some View {
        HStack(spacing: 12) {
            if let err = vm.errorMessage {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(err)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.red)
                }
            } else if let hint = vm.statusHint {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.blue)
                    Text(hint)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(Color(red: 0.15, green: 0.42, blue: 0.78))
                }
            } else {
                Text("提示：支持管理 3 个以上任意子账号，按 ⌘ ⏎ 快捷保存")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("取消") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button(action: handleSave) {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.shield.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text(vm.batchItems.count > 1 ? "批量自动添加 (\(vm.batchItems.count) 条)" : (vm.editingItem == nil ? "一键自动添加" : "保存更新"))
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: vm.hasValidContentToSave
                            ? [Color(red: 0.04, green: 0.50, blue: 0.98), Color(red: 0.22, green: 0.34, blue: 0.95)]
                            : [Color.gray.opacity(0.4), Color.gray.opacity(0.4)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!vm.hasValidContentToSave)
            .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.85))
    }

    // MARK: - 选择图片识别 2FA 二维码
    private func handlePickQRImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .png, .jpeg]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.message = "选择包含 2FA 动态码二维码的图片文件"

        if panel.runModal() == .OK, let selectedURL = panel.url {
            do {
                let qrContent = try TOTPEngine.scanQRCode(from: selectedURL)
                if vm.rawSmartInput.isEmpty {
                    vm.rawSmartInput = qrContent
                } else {
                    vm.rawSmartInput += " " + qrContent
                }
                vm.parseSmartInput(vm.rawSmartInput)
                vm.statusHint = "二维码识别成功"
            } catch {
                vm.errorMessage = "未能识别二维码: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - 保存入库
    private func handleSave() {
        vm.errorMessage = nil
        vm.flushCurrentEntryFields()

        // 若为多行批量识别模式
        if vm.batchItems.count > 1 && vm.editingItem == nil {
            store.mergeOrInsertParsedCredentials(vm.batchItems, defaultCategory: vm.defaultCategory)
            dismiss()
            return
        }

        // 单条模式：决定最终标题
        let finalTitle: String = {
            let t = vm.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
            let u = vm.url.trimmingCharacters(in: .whitespacesAndNewlines)
            if !u.isEmpty { return u }
            let acc = vm.currentUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            if !acc.isEmpty { return acc }
            if let firstUser = vm.entries.first(where: { !$0.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.username {
                return firstUser
            }
            return "未命名账号"
        }()

        // 清理并提取所有有效 entries
        var cleanedEntries: [CredentialEntry] = []
        for var e in vm.entries {
            let user = e.username.trimmingCharacters(in: .whitespacesAndNewlines)
            let pwd = e.password
            let sec = e.totpSecret
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "-", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            e.username = user
            e.password = pwd
            e.totpSecret = sec
            if e.accountLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                e.accountLabel = "账号"
            }
            if e.passwordLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                e.passwordLabel = "密码"
            }
            cleanedEntries.append(e)
        }

        if cleanedEntries.isEmpty {
            cleanedEntries = [
                CredentialEntry(
                    accountLabel: vm.currentAccountLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "账号" : vm.currentAccountLabel,
                    username: vm.currentUsername.trimmingCharacters(in: .whitespacesAndNewlines),
                    passwordLabel: vm.currentPasswordLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "密码" : vm.currentPasswordLabel,
                    password: vm.currentPassword,
                    extraPasswords: vm.currentExtraPasswords,
                    totpSecret: vm.currentTotpSecret
                        .replacingOccurrences(of: " ", with: "")
                        .replacingOccurrences(of: "-", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                )
            ]
        }

        let finalNoteEntries = vm.noteEntries
        let finalNotes: String = {
            if !finalNoteEntries.isEmpty {
                return finalNoteEntries.map { "\($0.effectiveLabel)：\($0.content)" }.joined(separator: "\n")
            }
            return vm.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        }()

        if let existing = vm.editingItem {
            var item = existing
            item.title = finalTitle
            item.url = vm.url.trimmingCharacters(in: .whitespacesAndNewlines)
            item.category = vm.category
            item.isFavorite = vm.isFavorite
            item.entries = cleanedEntries
            item.noteEntries = finalNoteEntries
            item.notes = finalNotes
            item.updatedAt = Date()
            store.upsertItem(item)
        } else {
            // 新建条目：若已有同名/同网址服务，则合并追加 entries；若无则新建 AccountItem
            if let existing = store.findExistingItem(matchingTitle: finalTitle, url: vm.url.trimmingCharacters(in: .whitespacesAndNewlines)),
               let idx = store.items.firstIndex(where: { $0.id == existing.id }) {
                for e in cleanedEntries {
                    store.items[idx].addOrUpdateEntry(e)
                }
                for n in finalNoteEntries {
                    if !store.items[idx].effectiveNoteEntries.contains(where: { $0.content == n.content }) {
                        store.items[idx].noteEntries.append(n)
                    }
                }
                store.items[idx].syncNotesFromEntries()
                store.selectedItemId = store.items[idx].id
                try? store.saveVault()
                store.update2FACodes()
                store.recordActivity()
                store.showStatusToast("已将账号合并追加至「\(store.items[idx].title)」")
            } else {
                let item = AccountItem(
                    title: finalTitle,
                    url: vm.url.trimmingCharacters(in: .whitespacesAndNewlines),
                    category: vm.category,
                    customTag: "",
                    customIcon: "",
                    isFavorite: vm.isFavorite,
                    notes: finalNotes,
                    noteEntries: finalNoteEntries,
                    notesLayout: .single,
                    entries: cleanedEntries,
                    createdAt: Date(),
                    updatedAt: Date()
                )
                store.upsertItem(item)
            }
        }
        dismiss()
    }
}
