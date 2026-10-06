import SwiftUI
import AppKit

@MainActor
public final class ItemEditorViewModel: ObservableObject {
    // 智能识别原始输入文本
    @Published public var rawSmartInput: String = ""

    // 批量识别结果（当用户一次性粘贴多行独立账号时自动激活）
    @Published public var batchItems: [ParsedCredential] = []

    // 单条识别/微调字段
    @Published public var title: String = ""
    @Published public var url: String = ""
    @Published public var username: String = ""
    @Published public var password: String = ""
    @Published public var totpSecret: String = ""
    @Published public var category: AccountCategory = .general
    @Published public var notes: String = ""
    @Published public var isFavorite: Bool = false
    @Published public var recognizedBadges: [String] = []

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
            self.username = item.username
            self.password = item.password
            self.totpSecret = item.totpSecret
            self.category = item.category
            self.notes = item.notes
            self.isFavorite = item.isFavorite
        } else {
            self.category = defaultCategory
        }
    }

    /// 当用户在智能识别框输入或粘贴文本时，实时解析
    public func parseSmartInput(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            batchItems = []
            if editingItem == nil {
                title = ""
                url = ""
                username = ""
                password = ""
                totpSecret = ""
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
        self.title = parsed.title
        self.url = parsed.url
        self.username = parsed.username
        self.password = parsed.password
        self.totpSecret = parsed.totpSecret
        self.category = parsed.category
        self.notes = parsed.notes
        self.recognizedBadges = parsed.recognizedFields
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
                          !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasSecret = !password.isEmpty ||
                        !totpSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasIdentity && hasSecret
    }

    /// 实时预览 2FA 验证码（若密钥为合法 Base32 则返回 6 位动态码）
    public var liveTOTPPreviewCode: String? {
        let cleaned = totpSecret
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
        .frame(width: 600, height: 610)
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
                    Text(vm.editingItem == nil ? "智能识别添加" : "智能更新记录")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.08, green: 0.13, blue: 0.24))

                    Text("AUTO-PARSE ENGINE")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundColor(Color(red: 0.04, green: 0.48, blue: 0.92))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.04, green: 0.48, blue: 0.92).opacity(0.12))
                        )
                }

                Text("直接粘贴如：xxxx.com   密码：xxx   账号：xxx   2FA：xxxx，自动识别拆解入库")
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
                .frame(height: 88)
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

    // MARK: - 3A. 单条实时解析卡片（自动填充 + 可直接微调）
    private var singlePreviewAndAdjustSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("智能拆解结果预览（点击任意栏可直接微调）", systemImage: "cpu.fill")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(Color(red: 0.12, green: 0.20, blue: 0.34))

                Spacer()

                // 分类自动归属与快速切换胶囊
                HStack(spacing: 4) {
                    Text("自动归类:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Picker("", selection: $vm.category) {
                        ForEach(AccountCategory.allCases) { cat in
                            Text(cat.rawValue).tag(cat)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 125)
                }
            }

            // 核心预览卡片
            VStack(spacing: 10) {
                // 顶部：自动匹配图标 + 网站/服务名 + 网址
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

                            TextField("自动识别服务名称 (如 xxxx.com / Binance)", text: $vm.title)
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

                            TextField("自动提取域名或网址 (如 xxxx.com)", text: $vm.url)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12.5, design: .monospaced))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 7).fill(Color(red: 0.95, green: 0.97, blue: 1.0)))
                        }
                    }
                }

                Divider().opacity(0.45)

                // 账号行（统一提示格式：账号：xxx）
                parsedFieldRow(
                    icon: "person.crop.circle.fill",
                    iconColor: Color(red: 0.12, green: 0.52, blue: 0.96),
                    label: "账号：",
                    placeholder: "账号：xxx（自动提取或输入登录账号/邮箱）",
                    text: $vm.username,
                    monospaced: true
                )

                // 密码行（统一提示格式：密码：xxx，输入主框与账号主框完全等宽等高对齐）
                HStack(spacing: 10) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Color(red: 0.95, green: 0.55, blue: 0.12))
                        .frame(width: 22)

                    Text("密码：")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(red: 0.22, green: 0.30, blue: 0.42))
                        .frame(width: 48, alignment: .leading)

                    HStack(spacing: 6) {
                        TextField("密码：xxx（自动提取或输入登录密码）", text: $vm.password)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))

                        Button(action: {
                            vm.password = PasswordGenerator.generate(options: PasswordGeneratorOptions(length: 18))
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

                // 2FA 密钥行 + 实时动态码即时演算预览（统一提示格式：2FA：xxx，输入主框与账号/密码完全等宽等高对齐）
                HStack(spacing: 10) {
                    Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                        .font(.system(size: 13))
                        .foregroundColor(Color(red: 0.06, green: 0.70, blue: 0.48))
                        .frame(width: 22)

                    Text("2FA：")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(red: 0.22, green: 0.30, blue: 0.42))
                        .frame(width: 48, alignment: .leading)

                    HStack(spacing: 6) {
                        TextField("2FA：xxxx（密钥或 2fa(xxxx)）", text: $vm.totpSecret)
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
                        } else if !vm.totpSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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

                // 备注行（仅在识别出额外信息或编辑时展示，保持极简）
                parsedFieldRow(
                    icon: "note.text",
                    iconColor: .secondary,
                    label: "备注：",
                    placeholder: "可选补充说明（多余未分类文本会自动归入此处）",
                    text: $vm.notes,
                    monospaced: false
                )
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(red: 0.05, green: 0.52, blue: 0.98).opacity(0.18), lineWidth: 1)
            )
        }
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
                                    Text("密码：\(item.password)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                if !item.username.isEmpty {
                                    Text("账号：\(item.username)")
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

    private func parsedFieldRow(
        icon: String,
        iconColor: Color,
        label: String,
        placeholder: String,
        text: Binding<String>,
        monospaced: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(iconColor)
                .frame(width: 22)

            Text(label)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Color(red: 0.22, green: 0.30, blue: 0.42))
                .frame(width: 48, alignment: .leading)

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium, design: monospaced ? .monospaced : .default))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(red: 0.95, green: 0.97, blue: 1.0))
                )
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
                Text("提示：支持直接粘贴「网址  密码：xxx  账号：xxx  2FA：xxx」，按 ⌘ ⏎ 一键入库")
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

        // 若为多行批量模式
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
            let acc = vm.username.trimmingCharacters(in: .whitespacesAndNewlines)
            if !acc.isEmpty { return acc }
            return "未命名账号"
        }()

        let cleanedSecret = vm.totpSecret
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing = vm.editingItem {
            var item = existing
            item.title = finalTitle
            item.url = vm.url.trimmingCharacters(in: .whitespacesAndNewlines)
            item.username = vm.username.trimmingCharacters(in: .whitespacesAndNewlines)
            item.password = vm.password
            item.category = vm.category
            item.isFavorite = vm.isFavorite
            item.totpSecret = cleanedSecret
            item.notes = vm.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            item.updatedAt = Date()
            store.upsertItem(item)
        } else {
            // 新建单条：若已有同名/同域名服务则自动挂载至该服务下（支持同密码聚合或新密码分组）
            let parsed = ParsedCredential(
                title: finalTitle,
                url: vm.url.trimmingCharacters(in: .whitespacesAndNewlines),
                username: vm.username.trimmingCharacters(in: .whitespacesAndNewlines),
                password: vm.password,
                totpSecret: cleanedSecret,
                totpDigits: 6,
                totpPeriod: 30,
                totpAlgorithm: .sha1,
                category: vm.category,
                notes: vm.notes.trimmingCharacters(in: .whitespacesAndNewlines),
                recognizedFields: vm.recognizedBadges
            )
            store.mergeOrInsertParsedCredentials([parsed], defaultCategory: vm.defaultCategory)
        }
        dismiss()
    }
}
