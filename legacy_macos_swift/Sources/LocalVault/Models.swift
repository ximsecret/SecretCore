import Foundation
import SwiftUI
import AppKit

public enum TOTPAlgorithm: String, Codable, CaseIterable, Identifiable {
    case sha1 = "SHA1"
    case sha256 = "SHA256"
    case sha512 = "SHA512"

    public var id: String { rawValue }
}

public enum AccountCategory: String, Codable, CaseIterable, Identifiable {
    case crypto = "加密与交易"
    case work = "开发与工作"
    case ai = "AI与云服务"
    case finance = "金融与支付"
    case social = "社交与邮箱"
    case general = "常规网站"
    case other = "其他记录"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .crypto: return "bitcoinsign.circle.fill"
        case .work: return "chevron.left.forwardslash.chevron.right"
        case .ai: return "sparkles"
        case .finance: return "creditcard.fill"
        case .social: return "bubble.left.and.bubble.right.fill"
        case .general: return "safari.fill"
        case .other: return "key.radiowaves.forward.fill"
        }
    }

    public var tintColor: Color {
        switch self {
        case .crypto: return Color(red: 0.96, green: 0.58, blue: 0.11)   // 琥珀金
        case .work: return Color(red: 0.36, green: 0.44, blue: 0.96)     // 靛蓝紫
        case .ai: return Color(red: 0.68, green: 0.32, blue: 0.96)       // 霓虹紫
        case .finance: return Color(red: 0.06, green: 0.74, blue: 0.52)  // 翡翠绿
        case .social: return Color(red: 0.94, green: 0.30, blue: 0.58)   // 珊瑚粉
        case .general: return Color(red: 0.14, green: 0.58, blue: 0.96)  // 科技蓝
        case .other: return Color(red: 0.46, green: 0.54, blue: 0.64)    // 钛金灰
        }
    }

    public var secondaryColor: Color {
        switch self {
        case .crypto: return Color(red: 0.92, green: 0.34, blue: 0.08)
        case .work: return Color(red: 0.22, green: 0.28, blue: 0.78)
        case .ai: return Color(red: 0.42, green: 0.18, blue: 0.82)
        case .finance: return Color(red: 0.04, green: 0.48, blue: 0.38)
        case .social: return Color(red: 0.76, green: 0.18, blue: 0.46)
        case .general: return Color(red: 0.18, green: 0.36, blue: 0.84)
        case .other: return Color(red: 0.28, green: 0.34, blue: 0.44)
        }
    }

    public var subtitle: String {
        switch self {
        case .crypto: return "交易所、Web3 钱包、行情平台"
        case .work: return "GitHub、服务器、代码仓库、工作台"
        case .ai: return "OpenAI、Claude、云算力与 API"
        case .finance: return "银行卡、券商、支付与账单"
        case .social: return "邮箱、Apple ID、社交媒体"
        case .general: return "日常网站、论坛、通用账号"
        case .other: return "软件激活码、安全备忘与其它"
        }
    }

    // 兼容旧版存档分类名称
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self)) ?? "常规网站"
        if let exact = AccountCategory(rawValue: raw) {
            self = exact
            return
        }
        switch raw {
        case "常规登录": self = .general
        case "金融与加密": self = .crypto
        default: self = .other
        }
    }
}

public enum SidebarFilter: Hashable, Identifiable {
    case all
    case favorites
    case has2FA
    case category(AccountCategory)
    case tag(String)

    public var id: String {
        switch self {
        case .all: return "all"
        case .favorites: return "favorites"
        case .has2FA: return "has2FA"
        case .category(let cat): return "cat_\(cat.rawValue)"
        case .tag(let tag): return "tag_\(tag)"
        }
    }

    public var title: String {
        switch self {
        case .all: return "全部账号"
        case .favorites: return "星标收藏"
        case .has2FA: return "2FA 动态码"
        case .category(let cat): return cat.rawValue
        case .tag(let tag): return "# \(tag)"
        }
    }

    public var iconName: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .favorites: return "star.fill"
        case .has2FA: return "timer"
        case .category(let cat): return cat.iconName
        case .tag: return "tag.fill"
        }
    }

    public var tintColor: Color {
        switch self {
        case .all: return Color(red: 0.20, green: 0.56, blue: 0.98)
        case .favorites: return Color(red: 0.98, green: 0.68, blue: 0.12)
        case .has2FA: return Color(red: 0.10, green: 0.78, blue: 0.58)
        case .category(let cat): return cat.tintColor
        case .tag: return .teal
        }
    }
}

public struct CustomField: Codable, Identifiable, Equatable, Hashable {
    public var id: UUID = UUID()
    public var label: String
    public var value: String
    public var isSecret: Bool

    public init(id: UUID = UUID(), label: String, value: String, isSecret: Bool = false) {
        self.id = id
        self.label = label
        self.value = value
        self.isSecret = isSecret
    }
}

public struct PresetAccountIcon: Identifiable, Hashable {
    public let id: String
    public let symbol: String
    public let label: String

    public static let all: [PresetAccountIcon] = [
        PresetAccountIcon(id: "", symbol: "wand.and.stars", label: "智能匹配"),
        PresetAccountIcon(id: "bitcoinsign.circle.fill", symbol: "bitcoinsign.circle.fill", label: "加密货币"),
        PresetAccountIcon(id: "chart.line.uptrend.xyaxis", symbol: "chart.line.uptrend.xyaxis", label: "交易行情"),
        PresetAccountIcon(id: "wallet.pass.fill", symbol: "wallet.pass.fill", label: "Web3钱包"),
        PresetAccountIcon(id: "chevron.left.forwardslash.chevron.right", symbol: "chevron.left.forwardslash.chevron.right", label: "代码仓库"),
        PresetAccountIcon(id: "terminal.fill", symbol: "terminal.fill", label: "终端命令行"),
        PresetAccountIcon(id: "server.rack", symbol: "server.rack", label: "云服务器"),
        PresetAccountIcon(id: "cpu.fill", symbol: "cpu.fill", label: "算力与芯片"),
        PresetAccountIcon(id: "sparkles", symbol: "sparkles", label: "AI 大模型"),
        PresetAccountIcon(id: "brain.head.profile", symbol: "brain.head.profile", label: "智能助手"),
        PresetAccountIcon(id: "creditcard.fill", symbol: "creditcard.fill", label: "银行卡/支付"),
        PresetAccountIcon(id: "building.columns.fill", symbol: "building.columns.fill", label: "银行/券商"),
        PresetAccountIcon(id: "envelope.fill", symbol: "envelope.fill", label: "电子邮箱"),
        PresetAccountIcon(id: "paperplane.fill", symbol: "paperplane.fill", label: "即时通讯"),
        PresetAccountIcon(id: "bubble.left.and.bubble.right.fill", symbol: "bubble.left.and.bubble.right.fill", label: "社交社区"),
        PresetAccountIcon(id: "apple.logo", symbol: "apple.logo", label: "Apple 账户"),
        PresetAccountIcon(id: "globe", symbol: "globe", label: "全球网站"),
        PresetAccountIcon(id: "gamecontroller.fill", symbol: "gamecontroller.fill", label: "游戏娱乐"),
        PresetAccountIcon(id: "cart.fill", symbol: "cart.fill", label: "电商购物"),
        PresetAccountIcon(id: "key.radiowaves.forward.fill", symbol: "key.radiowaves.forward.fill", label: "硬件密钥"),
        PresetAccountIcon(id: "lock.shield.fill", symbol: "lock.shield.fill", label: "安全护盾")
    ]
}

// MARK: - 单账号下多密码模型（支持一个账号拥有主密码、资金密码、支付密码、API Key 等多个不同密码）
public struct LabeledPassword: Codable, Identifiable, Equatable, Hashable {
    public var id: UUID
    public var label: String
    public var value: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        label: String = "密码",
        value: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.label = label
        self.value = value
        self.createdAt = createdAt
    }

    public var effectiveLabel: String {
        var trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("：") || trimmed.hasSuffix(":") {
            trimmed = String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed.isEmpty ? "密码" : trimmed
    }
}

// MARK: - 多行安全备注模型（一行一条，支持自定义标签如 备注1、备注+8、密保问题）
public struct NoteEntry: Codable, Identifiable, Equatable, Hashable {
    public var id: UUID
    public var label: String
    public var content: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        label: String = "备注",
        content: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.label = label
        self.content = content
        self.createdAt = createdAt
    }

    public var effectiveLabel: String {
        var trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("：") || trimmed.hasSuffix(":") {
            trimmed = String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed.isEmpty ? "备注" : trimmed
    }
}

// MARK: - 常用预设标签词库
public enum CredentialLabelPresets {
    public static let accountPresets = ["账号", "用途", "域名", "接码平台", "邮箱", "手机号", "用户名", "UID"]
    public static let passwordPresets = ["密码", "登录密码", "资金密码", "支付密码", "交易密码", "API Key", "二级密码", "PIN码"]
    public static let notePresets = ["备注", "备注1", "备注2", "备注+8", "密保问题", "安全提示", "恢复助记词", "防钓鱼码"]
}

// MARK: - 单条子账号凭据（支持同一名称下挂载多个不同密码、多个账号及各自独立的 2FA）
public struct CredentialEntry: Codable, Identifiable, Equatable, Hashable {
    public var id: UUID
    public var accountLabel: String
    public var username: String
    public var passwordLabel: String
    public var password: String
    public var extraPasswords: [LabeledPassword]
    public var totpSecret: String
    public var totpDigits: Int
    public var totpPeriod: Int
    public var totpAlgorithm: TOTPAlgorithm
    public var notes: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        accountLabel: String = "账号",
        username: String = "",
        passwordLabel: String = "密码",
        password: String = "",
        extraPasswords: [LabeledPassword] = [],
        totpSecret: String = "",
        totpDigits: Int = 6,
        totpPeriod: Int = 30,
        totpAlgorithm: TOTPAlgorithm = .sha1,
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.accountLabel = accountLabel
        self.username = username
        self.passwordLabel = passwordLabel
        self.password = password
        self.extraPasswords = extraPasswords
        self.totpSecret = totpSecret
        self.totpDigits = totpDigits
        self.totpPeriod = totpPeriod
        self.totpAlgorithm = totpAlgorithm
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var effectiveAccountLabel: String {
        var trimmed = accountLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("：") || trimmed.hasSuffix(":") {
            trimmed = String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed.isEmpty ? "账号" : trimmed
    }

    public var effectivePasswordLabel: String {
        var trimmed = passwordLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("：") || trimmed.hasSuffix(":") {
            trimmed = String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed.isEmpty ? "密码" : trimmed
    }

    public var hasTOTP: Bool {
        !totpSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var hasPassword: Bool {
        !password.isEmpty || !extraPasswords.isEmpty
    }

    public mutating func clearTOTP() {
        totpSecret = ""
        updatedAt = Date()
    }

    public mutating func addExtraPassword(label: String = "密码", value: String = "") {
        extraPasswords.append(LabeledPassword(label: label, value: value))
        updatedAt = Date()
    }

    public mutating func removeExtraPassword(id: UUID) {
        extraPasswords.removeAll { $0.id == id }
        updatedAt = Date()
    }

    enum CodingKeys: String, CodingKey {
        case id, accountLabel, username, passwordLabel, password, extraPasswords
        case totpSecret, totpDigits, totpPeriod, totpAlgorithm
        case notes, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        accountLabel = (try? c.decode(String.self, forKey: .accountLabel)) ?? "账号"
        username = (try? c.decode(String.self, forKey: .username)) ?? ""
        passwordLabel = (try? c.decode(String.self, forKey: .passwordLabel)) ?? "密码"
        password = (try? c.decode(String.self, forKey: .password)) ?? ""
        extraPasswords = (try? c.decode([LabeledPassword].self, forKey: .extraPasswords)) ?? []
        totpSecret = (try? c.decode(String.self, forKey: .totpSecret)) ?? ""
        totpDigits = (try? c.decode(Int.self, forKey: .totpDigits)) ?? 6
        totpPeriod = (try? c.decode(Int.self, forKey: .totpPeriod)) ?? 30
        totpAlgorithm = (try? c.decode(TOTPAlgorithm.self, forKey: .totpAlgorithm)) ?? .sha1
        notes = (try? c.decode(String.self, forKey: .notes)) ?? ""
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? Date()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(accountLabel, forKey: .accountLabel)
        try c.encode(username, forKey: .username)
        try c.encode(passwordLabel, forKey: .passwordLabel)
        try c.encode(password, forKey: .password)
        try c.encode(extraPasswords, forKey: .extraPasswords)
        try c.encode(totpSecret, forKey: .totpSecret)
        try c.encode(totpDigits, forKey: .totpDigits)
        try c.encode(totpPeriod, forKey: .totpPeriod)
        try c.encode(totpAlgorithm, forKey: .totpAlgorithm)
        try c.encode(notes, forKey: .notes)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

// MARK: - 备注排版模式（一行单条 vs 一行两条自由切换）
public enum NotesLayoutMode: String, Codable, CaseIterable, Identifiable {
    case single = "single" // 一行单条（全宽）
    case double = "double" // 一行两条（双列并排）

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .single: return "一行单条"
        case .double: return "一行两条"
        }
    }

    public var iconName: String {
        switch self {
        case .single: return "rectangle.grid.1x2"
        case .double: return "rectangle.grid.2x2"
        }
    }
}

// MARK: - 按密码聚合分组模型（同一密码下包含多个账号及对应 2FA，另一密码下包含其他账号）
public struct PasswordCredentialGroup: Identifiable, Equatable {
    public var id: String { password.isEmpty ? "__EMPTY_PASSWORD__" : password }
    public var password: String
    public var entries: [CredentialEntry]

    public init(password: String, entries: [CredentialEntry]) {
        self.password = password
        self.entries = entries
    }

    public var accountCount: Int {
        entries.count
    }

    public var strength: (strength: PasswordStrength, entropyBits: Int) {
        PasswordGenerator.evaluateStrength(password)
    }

    public var effectivePasswordLabel: String {
        if let first = entries.first(where: { !$0.passwordLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return first.effectivePasswordLabel
        }
        return "密码"
    }
}

public struct AccountItem: Codable, Identifiable, Equatable, Hashable {
    public var id: UUID
    public var title: String
    public var url: String
    public var category: AccountCategory
    public var customTag: String
    public var customIcon: String
    public var isFavorite: Bool

    // 同一个名称下的多账号多密码列表
    public var entries: [CredentialEntry]

    public var notes: String
    public var noteEntries: [NoteEntry]
    public var notesLayout: NotesLayoutMode
    public var customFields: [CustomField]
    public var createdAt: Date
    public var updatedAt: Date

    // 兼容主凭据属性（映射到 entries[0]）
    public var username: String {
        get { entries.first?.username ?? "" }
        set {
            ensureAtLeastOneEntry()
            entries[0].username = newValue
            entries[0].updatedAt = Date()
        }
    }

    public var password: String {
        get { entries.first?.password ?? "" }
        set {
            ensureAtLeastOneEntry()
            entries[0].password = newValue
            entries[0].updatedAt = Date()
        }
    }

    public var totpSecret: String {
        get { entries.first(where: { $0.hasTOTP })?.totpSecret ?? (entries.first?.totpSecret ?? "") }
        set {
            ensureAtLeastOneEntry()
            entries[0].totpSecret = newValue
            entries[0].updatedAt = Date()
        }
    }

    public var totpDigits: Int {
        get { entries.first?.totpDigits ?? 6 }
        set {
            ensureAtLeastOneEntry()
            entries[0].totpDigits = newValue
        }
    }

    public var totpPeriod: Int {
        get { entries.first?.totpPeriod ?? 30 }
        set {
            ensureAtLeastOneEntry()
            entries[0].totpPeriod = newValue
        }
    }

    public var totpAlgorithm: TOTPAlgorithm {
        get { entries.first?.totpAlgorithm ?? .sha1 }
        set {
            ensureAtLeastOneEntry()
            entries[0].totpAlgorithm = newValue
        }
    }

    private mutating func ensureAtLeastOneEntry() {
        if entries.isEmpty {
            entries.append(CredentialEntry())
        }
    }

    public init(
        id: UUID = UUID(),
        title: String,
        username: String = "",
        password: String = "",
        url: String = "",
        category: AccountCategory = .general,
        customTag: String = "",
        customIcon: String = "",
        isFavorite: Bool = false,
        totpSecret: String = "",
        totpDigits: Int = 6,
        totpPeriod: Int = 30,
        totpAlgorithm: TOTPAlgorithm = .sha1,
        notes: String = "",
        noteEntries: [NoteEntry]? = nil,
        notesLayout: NotesLayoutMode = .single,
        customFields: [CustomField] = [],
        entries: [CredentialEntry]? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.category = category
        self.customTag = customTag
        self.customIcon = customIcon
        self.isFavorite = isFavorite
        self.notes = notes
        self.customFields = customFields
        self.notesLayout = notesLayout
        self.createdAt = createdAt
        self.updatedAt = updatedAt

        if let explicitNotes = noteEntries, !explicitNotes.isEmpty {
            self.noteEntries = explicitNotes
        } else if !notes.isEmpty {
            let lines = notes.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            var list: [NoteEntry] = []
            for line in lines {
                if let colon = line.firstIndex(of: "：") ?? line.firstIndex(of: ":") {
                    let lbl = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                    let cnt = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                    list.append(NoteEntry(label: lbl.isEmpty ? "备注" : lbl, content: cnt))
                } else {
                    list.append(NoteEntry(label: "备注", content: line))
                }
            }
            self.noteEntries = list.isEmpty ? [NoteEntry(label: "备注", content: notes)] : list
        } else {
            self.noteEntries = []
        }

        if let explicitEntries = entries, !explicitEntries.isEmpty {
            self.entries = explicitEntries
        } else {
            self.entries = [
                CredentialEntry(
                    username: username,
                    password: password,
                    totpSecret: totpSecret,
                    totpDigits: totpDigits,
                    totpPeriod: totpPeriod,
                    totpAlgorithm: totpAlgorithm,
                    createdAt: createdAt,
                    updatedAt: updatedAt
                )
            ]
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, username, password, url, category, customTag, customIcon, isFavorite
        case totpSecret, totpDigits, totpPeriod, totpAlgorithm
        case notes, noteEntries, notesLayout, customFields, createdAt, updatedAt
        case entries
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        url = (try? c.decode(String.self, forKey: .url)) ?? ""
        category = (try? c.decode(AccountCategory.self, forKey: .category)) ?? .general
        customTag = (try? c.decode(String.self, forKey: .customTag)) ?? ""
        customIcon = (try? c.decode(String.self, forKey: .customIcon)) ?? ""
        isFavorite = (try? c.decode(Bool.self, forKey: .isFavorite)) ?? false
        notes = (try? c.decode(String.self, forKey: .notes)) ?? ""
        if let decodedNoteEntries = try? c.decode([NoteEntry].self, forKey: .noteEntries),
           !decodedNoteEntries.isEmpty {
            noteEntries = decodedNoteEntries
        } else if !notes.isEmpty {
            let lines = notes.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            var list: [NoteEntry] = []
            for line in lines {
                if let colon = line.firstIndex(of: "：") ?? line.firstIndex(of: ":") {
                    let lbl = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                    let cnt = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                    list.append(NoteEntry(label: lbl.isEmpty ? "备注" : lbl, content: cnt))
                } else {
                    list.append(NoteEntry(label: "备注", content: line))
                }
            }
            noteEntries = list.isEmpty ? [NoteEntry(label: "备注", content: notes)] : list
        } else {
            noteEntries = []
        }
        notesLayout = (try? c.decode(NotesLayoutMode.self, forKey: .notesLayout)) ?? .single
        customFields = (try? c.decode([CustomField].self, forKey: .customFields)) ?? []
        let decodedCreatedAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        let decodedUpdatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? Date()
        createdAt = decodedCreatedAt
        updatedAt = decodedUpdatedAt

        if let decodedEntries = try? c.decode([CredentialEntry].self, forKey: .entries),
           !decodedEntries.isEmpty {
            entries = decodedEntries
        } else {
            let legacyUser = (try? c.decode(String.self, forKey: .username)) ?? ""
            let legacyPass = (try? c.decode(String.self, forKey: .password)) ?? ""
            let legacySecret = (try? c.decode(String.self, forKey: .totpSecret)) ?? ""
            let legacyDigits = (try? c.decode(Int.self, forKey: .totpDigits)) ?? 6
            let legacyPeriod = (try? c.decode(Int.self, forKey: .totpPeriod)) ?? 30
            let legacyAlgo = (try? c.decode(TOTPAlgorithm.self, forKey: .totpAlgorithm)) ?? .sha1
            entries = [
                CredentialEntry(
                    username: legacyUser,
                    password: legacyPass,
                    totpSecret: legacySecret,
                    totpDigits: legacyDigits,
                    totpPeriod: legacyPeriod,
                    totpAlgorithm: legacyAlgo,
                    createdAt: decodedCreatedAt,
                    updatedAt: decodedUpdatedAt
                )
            ]
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(username, forKey: .username)
        try c.encode(password, forKey: .password)
        try c.encode(url, forKey: .url)
        try c.encode(category, forKey: .category)
        try c.encode(customTag, forKey: .customTag)
        try c.encode(customIcon, forKey: .customIcon)
        try c.encode(isFavorite, forKey: .isFavorite)
        try c.encode(totpSecret, forKey: .totpSecret)
        try c.encode(totpDigits, forKey: .totpDigits)
        try c.encode(totpPeriod, forKey: .totpPeriod)
        try c.encode(totpAlgorithm, forKey: .totpAlgorithm)
        try c.encode(notes, forKey: .notes)
        try c.encode(noteEntries, forKey: .noteEntries)
        try c.encode(notesLayout, forKey: .notesLayout)
        try c.encode(customFields, forKey: .customFields)
        try c.encode(entries, forKey: .entries)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }

    public var hasTOTP: Bool {
        entries.contains { $0.hasTOTP }
    }

    public var hasPassword: Bool {
        entries.contains { $0.hasPassword }
    }

    /// 按密码聚合分组排序：同一个密码下排列多个账号与对应的 2FA，另外一个密码下排列其他账号与 2FA
    public var passwordGroups: [PasswordCredentialGroup] {
        var groups: [PasswordCredentialGroup] = []
        var groupIndexMap: [String: Int] = [:]

        for entry in entries {
            let key = entry.password
            if let idx = groupIndexMap[key] {
                groups[idx].entries.append(entry)
            } else {
                groupIndexMap[key] = groups.count
                groups.append(PasswordCredentialGroup(password: key, entries: [entry]))
            }
        }

        // 保持非空密码组在前、空密码组在后的顺序，各组内部保持账号录入顺序
        let nonEmptyGroups = groups.filter { !$0.password.isEmpty }
        let emptyGroups = groups.filter { $0.password.isEmpty }
        return nonEmptyGroups + emptyGroups
    }

    /// 所有非空子账号名称摘要（用于列表卡片展示，统一格式为：账号：xxx）
    public var accountsSummaryText: String {
        let validEntries = entries.filter { !$0.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if validEntries.isEmpty {
            return url.isEmpty ? "（未填写账号）" : "网址：\(url)"
        }
        let list = validEntries.map { "\($0.effectiveAccountLabel)：\($0.username.trimmingCharacters(in: .whitespacesAndNewlines))" }
        return list.joined(separator: "  ·  ")
    }

    /// 向当前名称下追加或更新一条子凭据
    public mutating func addOrUpdateEntry(_ newEntry: CredentialEntry) {
        // 若当前仅有一个完全空白的占位条目，直接替换
        if entries.count == 1 &&
           entries[0].username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
           entries[0].password.isEmpty &&
           !entries[0].hasTOTP {
            entries[0] = newEntry
            updatedAt = Date()
            return
        }

        // 若 ID 完全一致则原位更新
        if let idx = entries.firstIndex(where: { $0.id == newEntry.id }) {
            entries[idx] = newEntry
            updatedAt = Date()
            return
        }

        // 若存在相同账号名 + 相同密码，则合并补充其 2FA 或备注
        let cleanNewUser = newEntry.username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !cleanNewUser.isEmpty,
           let idx = entries.firstIndex(where: {
               $0.username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == cleanNewUser &&
               $0.password == newEntry.password
           }) {
            if !newEntry.totpSecret.isEmpty {
                entries[idx].totpSecret = newEntry.totpSecret
            }
            if !newEntry.notes.isEmpty {
                entries[idx].notes = newEntry.notes
            }
            if newEntry.accountLabel != "账号" && !newEntry.accountLabel.isEmpty {
                entries[idx].accountLabel = newEntry.accountLabel
            }
            if newEntry.passwordLabel != "密码" && !newEntry.passwordLabel.isEmpty {
                entries[idx].passwordLabel = newEntry.passwordLabel
            }
            for extra in newEntry.extraPasswords {
                if !entries[idx].extraPasswords.contains(where: { $0.label == extra.label && $0.value == extra.value }) {
                    entries[idx].extraPasswords.append(extra)
                }
            }
            entries[idx].updatedAt = Date()
            updatedAt = Date()
            return
        }

        entries.append(newEntry)
        updatedAt = Date()
    }

    public var effectiveNotesLayout: NotesLayoutMode {
        notesLayout
    }

    public var effectiveNoteEntries: [NoteEntry] {
        if !noteEntries.isEmpty {
            return noteEntries
        }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let lines = trimmed.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var list: [NoteEntry] = []
        for line in lines {
            if let colon = line.firstIndex(of: "：") ?? line.firstIndex(of: ":") {
                let lbl = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                let cnt = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                list.append(NoteEntry(label: lbl.isEmpty ? "备注" : lbl, content: cnt))
            } else {
                list.append(NoteEntry(label: "备注", content: line))
            }
        }
        return list.isEmpty ? [NoteEntry(label: "备注", content: trimmed)] : list
    }

    public mutating func clearEntryTOTP(entryId: UUID) {
        if let idx = entries.firstIndex(where: { $0.id == entryId }) {
            entries[idx].clearTOTP()
            if entries[idx].id == entries.first?.id || !hasTOTP {
                totpSecret = entries.first?.totpSecret ?? ""
            }
            updatedAt = Date()
        }
    }

    public mutating func updateNotesLayout(_ layout: NotesLayoutMode) {
        notesLayout = layout
        updatedAt = Date()
    }

    public mutating func updateNoteEntries(_ list: [NoteEntry]) {
        noteEntries = list
        syncNotesFromEntries()
        updatedAt = Date()
    }

    public mutating func syncNotesFromEntries() {
        if !noteEntries.isEmpty {
            notes = noteEntries.map { "\($0.effectiveLabel)：\($0.content)" }.joined(separator: "\n")
        } else {
            notes = ""
        }
    }

    public mutating func removeNoteEntry(id: UUID) {
        if noteEntries.isEmpty {
            noteEntries = effectiveNoteEntries
        }
        noteEntries.removeAll { $0.id == id }
        syncNotesFromEntries()
        updatedAt = Date()
    }

    public mutating func removeExtraPassword(entryId: UUID, extraId: UUID) {
        if let idx = entries.firstIndex(where: { $0.id == entryId }) {
            entries[idx].removeExtraPassword(id: extraId)
            updatedAt = Date()
        }
    }

    public mutating func addExtraPassword(entryId: UUID, label: String = "密码", value: String = "") {
        if let idx = entries.firstIndex(where: { $0.id == entryId }) {
            entries[idx].addExtraPassword(label: label, value: value)
            updatedAt = Date()
        }
    }

    public mutating func removeEntry(id: UUID) {
        entries.removeAll { $0.id == id }
        if entries.isEmpty {
            entries.append(CredentialEntry())
        }
        username = entries.first?.username ?? ""
        password = entries.first?.password ?? ""
        totpSecret = entries.first?.totpSecret ?? ""
        updatedAt = Date()
    }

    public mutating func removePasswordGroup(password: String) {
        entries.removeAll { $0.password == password }
        if entries.isEmpty {
            entries.append(CredentialEntry())
        }
        updatedAt = Date()
    }

    public mutating func updateGroupPassword(oldPassword: String, newPassword: String) {
        for idx in entries.indices where entries[idx].password == oldPassword {
            entries[idx].password = newPassword
            entries[idx].updatedAt = Date()
        }
        updatedAt = Date()
    }

    public var normalizedCustomTag: String {
        customTag.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 智能解析最佳显示图标：优先使用用户指定的 customIcon，其次根据标题/网址智能匹配品牌符号，最后回退到分类图标
    public var resolvedIconName: String {
        let trimmedIcon = customIcon.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedIcon.isEmpty {
            return trimmedIcon
        }

        let hay = "\(title) \(url) \(customTag)".lowercased()
        if hay.contains("github") || hay.contains("gitlab") || hay.contains("gitee") || hay.contains("代码") {
            return "chevron.left.forwardslash.chevron.right"
        }
        if hay.contains("binance") || hay.contains("币安") || hay.contains("okx") || hay.contains("bybit") || hay.contains("coinbase") || hay.contains("bitget") || hay.contains("gate") {
            return "bitcoinsign.circle.fill"
        }
        if hay.contains("metamask") || hay.contains("phantom") || hay.contains("ledger") || hay.contains("trezor") || hay.contains("wallet") || hay.contains("钱包") {
            return "wallet.pass.fill"
        }
        if hay.contains("tradingview") || hay.contains("coinglass") || hay.contains("行情") || hay.contains("期权") {
            return "chart.line.uptrend.xyaxis"
        }
        if hay.contains("openai") || hay.contains("chatgpt") || hay.contains("claude") || hay.contains("anthropic") || hay.contains("gemini") || hay.contains("deepseek") || hay.contains("大模型") {
            return "sparkles"
        }
        if hay.contains("aws") || hay.contains("cloudflare") || hay.contains("aliyun") || hay.contains("阿里云") || hay.contains("腾讯云") || hay.contains("server") || hay.contains("服务器") || hay.contains("docker") || hay.contains("ssh") {
            return "server.rack"
        }
        if hay.contains("apple") || hay.contains("icloud") {
            return "apple.logo"
        }
        if hay.contains("gmail") || hay.contains("outlook") || hay.contains("proton") || hay.contains("mail") || hay.contains("邮箱") || hay.contains("163") || hay.contains("qq邮箱") {
            return "envelope.fill"
        }
        if hay.contains("telegram") || hay.contains("tg") {
            return "paperplane.fill"
        }
        let isXCom = url.lowercased() == "x.com" || url.lowercased().contains("://x.com") || url.lowercased().contains("/x.com")
        if hay.contains("discord") || hay.contains("twitter") || isXCom || hay.contains("wechat") || hay.contains("微信") {
            return "bubble.left.and.bubble.right.fill"
        }
        if hay.contains("steam") || hay.contains("epic") || hay.contains("playstation") || hay.contains("nintendo") || hay.contains("游戏") {
            return "gamecontroller.fill"
        }
        if hay.contains("bank") || hay.contains("银行") || hay.contains("券商") || hay.contains("ibkr") || hay.contains("富途") {
            return "building.columns.fill"
        }
        if hay.contains("alipay") || hay.contains("支付宝") || hay.contains("paypal") || hay.contains("stripe") || hay.contains("wise") {
            return "creditcard.fill"
        }
        return category.iconName
    }
}

// MARK: - 统一精修 3D 玻璃质感图标组件 (用于列表、详情、侧边栏与锁定屏)
public struct AccountAvatarView: View {
    public let item: AccountItem
    public var size: CGFloat = 42
    public var showFavoriteBadge: Bool = true

    public init(item: AccountItem, size: CGFloat = 42, showFavoriteBadge: Bool = true) {
        self.item = item
        self.size = size
        self.showFavoriteBadge = showFavoriteBadge
    }

    public var body: some View {
        let cat = item.category
        let corner = size * 0.27

        ZStack(alignment: .bottomTrailing) {
            ZStack {
                // 1. 底层双色饱和渐变
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [cat.tintColor, cat.secondaryColor],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // 2. 左上角玻璃高光折射层
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.38), Color.white.opacity(0.0)],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: size * 0.85
                        )
                    )

                // 3. 顶部高光金属内描边
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.55), Color.white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: max(1.0, size * 0.03)
                    )

                // 4. 中心精修符号 (带微投影)
                Image(systemName: item.resolvedIconName)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundColor(.white)
                    .shadow(color: Color.black.opacity(0.28), radius: 2, x: 0, y: 1)
            }
            .frame(width: size, height: size)
            .shadow(color: cat.tintColor.opacity(0.28), radius: size * 0.14, x: 0, y: size * 0.07)

            // 5. 星标角标
            if showFavoriteBadge && item.isFavorite {
                ZStack {
                    Circle()
                        .fill(Color(NSColor.windowBackgroundColor))
                        .frame(width: max(14, size * 0.36), height: max(14, size * 0.36))
                    Image(systemName: "star.fill")
                        .font(.system(size: max(8, size * 0.22), weight: .bold))
                        .foregroundColor(.yellow)
                }
                .offset(x: size * 0.08, y: size * 0.08)
            }
        }
    }
}

// MARK: - 品牌主徽标组件 (加载精修放大版全息 3D 护盾图标 BrandHero.png，并提供双层全息星环与矢量后备)
public struct VaultBrandEmblemView: View {
    public var size: CGFloat = 88
    public var showAura: Bool = false

    public init(size: CGFloat = 88, showAura: Bool = false) {
        self.size = size
        self.showAura = showAura
    }

    private static let cachedHeroImage: NSImage? = {
        if let bundleURL = Bundle.main.url(forResource: "BrandHero", withExtension: "png"),
           let img = NSImage(contentsOf: bundleURL) {
            return img
        }
        let candidates: [String?] = [
            Bundle.main.resourceURL?.appendingPathComponent("BrandHero.png").path,
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/BrandHero.png").path,
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // LocalVault/
                .deletingLastPathComponent() // Sources/
                .deletingLastPathComponent() // legacy_macos_swift/
                .appendingPathComponent("Resources/BrandHero.png").path,
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent() // root
                .appendingPathComponent("Resources/BrandHero.png").path,
            "/Users/mac/Desktop/AI/misc/SecretCore/legacy_macos_swift/Resources/BrandHero.png",
            "/Users/mac/Desktop/AI/misc/SecretCore/Resources/BrandHero.png",
            "/Applications/SecretCore.app/Contents/Resources/BrandHero.png"
        ]
        for p in candidates.compactMap({ $0 }) {
            if FileManager.default.fileExists(atPath: p),
               let img = NSImage(contentsOfFile: p) {
                return img
            }
        }
        return nil
    }()

    public var body: some View {
        let corner = size * 0.24
        ZStack {
            if showAura {
                // 1. 远景全息极光能量场 (电光青 + 琥珀金双色辉光)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.0, green: 0.72, blue: 1.0).opacity(0.38),
                                Color(red: 1.0, green: 0.65, blue: 0.18).opacity(0.20),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: size * 0.12,
                            endRadius: size * 0.82
                        )
                    )
                    .frame(width: size * 1.56, height: size * 1.56)

                // 2. 外层量子虚线星轨环 (呼应图标中的金色/青色加速环)
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color(red: 0.0, green: 0.68, blue: 1.0).opacity(0.55),
                                Color(red: 1.0, green: 0.64, blue: 0.15).opacity(0.50),
                                Color(red: 0.0, green: 0.75, blue: 1.0).opacity(0.20),
                                Color(red: 0.0, green: 0.68, blue: 1.0).opacity(0.55)
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 1.6, dash: [14, 6, 3, 6])
                    )
                    .frame(width: size * 1.24, height: size * 1.24)

                // 3. 内层精密锁定环
                Circle()
                    .stroke(
                        Color(red: 0.0, green: 0.58, blue: 0.96).opacity(0.32),
                        lineWidth: 1.0
                    )
                    .frame(width: size * 1.10, height: size * 1.10)

                // 4. 轨道卫星能量节点 (青色粒子 + 琥珀金粒子)
                Circle()
                    .fill(Color(red: 0.0, green: 0.72, blue: 1.0))
                    .frame(width: max(6, size * 0.055), height: max(6, size * 0.055))
                    .shadow(color: Color(red: 0.0, green: 0.72, blue: 1.0), radius: 5)
                    .offset(x: size * 0.62 * 0.866, y: -size * 0.62 * 0.5)

                Circle()
                    .fill(Color(red: 1.0, green: 0.65, blue: 0.16))
                    .frame(width: max(5, size * 0.048), height: max(5, size * 0.048))
                    .shadow(color: Color(red: 1.0, green: 0.65, blue: 0.16), radius: 5)
                    .offset(x: -size * 0.62 * 0.866, y: size * 0.62 * 0.5)
            }

            if let hero = Self.cachedHeroImage {
                Image(nsImage: hero)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size * 1.04, height: size * 1.04)
                    .shadow(
                        color: Color(red: 0.0, green: 0.38, blue: 0.85).opacity(showAura ? 0.30 : 0.16),
                        radius: showAura ? size * 0.12 : size * 0.06,
                        x: 0,
                        y: showAura ? size * 0.05 : 2
                    )
            } else {
                // 矢量降级后备
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.85, green: 0.93, blue: 1.0),
                                Color(red: 0.65, green: 0.82, blue: 0.98)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.05, green: 0.52, blue: 0.98),
                                Color(red: 0.02, green: 0.32, blue: 0.78)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
        .frame(width: showAura ? size * 1.30 : size, height: showAura ? size * 1.26 : size)
    }
}

public struct VaultPayload: Codable {
    public var schemaVersion: Int
    public var items: [AccountItem]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        schemaVersion: Int = 1,
        items: [AccountItem] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.items = items
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct EncryptedEnvelope: Codable {
    public var magic: String
    public var version: Int
    public var kdf: String
    public var cipher: String
    public var rounds: UInt32
    public var saltBase64: String
    public var sealedBoxBase64: String
    public var updatedAt: Date

    public static let currentMagic = "LOCALVAULT_ENC_V1"
}
