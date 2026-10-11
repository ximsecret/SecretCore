import Foundation

public struct ParsedCredential: Equatable, Identifiable {
    public var id: UUID = UUID()
    public var title: String
    public var url: String
    public var accountLabel: String = "账号"
    public var username: String
    public var passwordLabel: String = "密码"
    public var password: String
    public var extraPasswords: [LabeledPassword] = []
    public var totpSecret: String
    public var totpDigits: Int
    public var totpPeriod: Int
    public var totpAlgorithm: TOTPAlgorithm
    public var category: AccountCategory
    public var notes: String
    public var noteEntries: [NoteEntry] = []
    public var recognizedFields: [String]

    public init(
        id: UUID = UUID(),
        title: String = "",
        url: String = "",
        accountLabel: String = "账号",
        username: String = "",
        passwordLabel: String = "密码",
        password: String = "",
        extraPasswords: [LabeledPassword] = [],
        totpSecret: String = "",
        totpDigits: Int = 6,
        totpPeriod: Int = 30,
        totpAlgorithm: TOTPAlgorithm = .sha1,
        category: AccountCategory = .general,
        notes: String = "",
        noteEntries: [NoteEntry] = [],
        recognizedFields: [String] = []
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.accountLabel = accountLabel
        self.username = username
        self.passwordLabel = passwordLabel
        self.password = password
        self.extraPasswords = extraPasswords
        self.totpSecret = totpSecret
        self.totpDigits = totpDigits
        self.totpPeriod = totpPeriod
        self.totpAlgorithm = totpAlgorithm
        self.category = category
        self.notes = notes
        self.noteEntries = noteEntries
        self.recognizedFields = recognizedFields
    }

    public var hasAnyContent: Bool {
        !title.isEmpty || !url.isEmpty || !username.isEmpty || !password.isEmpty || !totpSecret.isEmpty || !extraPasswords.isEmpty || !noteEntries.isEmpty
    }

    public var hasValidBase32TOTP: Bool {
        let cleaned = totpSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return false }
        return (try? TOTPEngine.decodeBase32(cleaned)) != nil
    }

    public func toCredentialEntry() -> CredentialEntry {
        let effAccLabel = accountLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let effPwdLabel = passwordLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return CredentialEntry(
            accountLabel: effAccLabel.isEmpty ? "账号" : effAccLabel,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            passwordLabel: effPwdLabel.isEmpty ? "密码" : effPwdLabel,
            password: password,
            extraPasswords: extraPasswords,
            totpSecret: totpSecret.trimmingCharacters(in: .whitespacesAndNewlines),
            totpDigits: totpDigits,
            totpPeriod: totpPeriod,
            totpAlgorithm: totpAlgorithm,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    public func toAccountItem() -> AccountItem {
        let finalTitle: String = {
            let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
            let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
            if !u.isEmpty { return u }
            let acc = username.trimmingCharacters(in: .whitespacesAndNewlines)
            if !acc.isEmpty { return acc }
            return "未命名账号"
        }()

        let entry = toCredentialEntry()

        var item = AccountItem(
            title: finalTitle,
            username: entry.username,
            password: entry.password,
            url: url.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            customTag: "",
            customIcon: "",
            isFavorite: false,
            totpSecret: entry.totpSecret,
            totpDigits: entry.totpDigits,
            totpPeriod: entry.totpPeriod,
            totpAlgorithm: entry.totpAlgorithm,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            noteEntries: noteEntries,
            notesLayout: .single,
            entries: [entry],
            createdAt: Date(),
            updatedAt: Date()
        )
        item.syncNotesFromEntries()
        return item
    }
}

public enum SmartCredentialParser {

    /// 智能解析单条文本（支持单行空格/Tab分隔、带括号2FA、带标签键值对或多行分段）
    /// 例如: "xxxx.com   密码：xxx   账号：xxx   2fa（xxxx）   资金密码：yyy   备注1：zzz"
    public static func parse(_ rawInput: String, defaultCategory: AccountCategory = .general) -> ParsedCredential {
        var working = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if working.isEmpty {
            return ParsedCredential(
                title: "",
                url: "",
                accountLabel: "账号",
                username: "",
                passwordLabel: "密码",
                password: "",
                extraPasswords: [],
                totpSecret: "",
                totpDigits: 6,
                totpPeriod: 30,
                totpAlgorithm: .sha1,
                category: defaultCategory,
                notes: "",
                noteEntries: [],
                recognizedFields: []
            )
        }

        var title = ""
        var url = ""
        var accountLabel = "账号"
        var username = ""
        var passwordLabel = "密码"
        var password = ""
        var extraPasswords: [LabeledPassword] = []
        var noteEntries: [NoteEntry] = []
        var totpSecret = ""
        var totpDigits = 6
        var totpPeriod = 30
        var totpAlgorithm: TOTPAlgorithm = .sha1
        var notes = ""
        var badges: [String] = []

        // 0. 检查是否包含 otpauth:// 协议链接
        if let otpRange = working.range(of: #"otpauth:\/\/[^\s\t\r\n]+"#, options: [.regularExpression, .caseInsensitive]) {
            let uriString = String(working[otpRange])
            if let parsedOTP = TOTPEngine.parseOTPAuthURI(uriString) {
                totpSecret = parsedOTP.secret
                totpDigits = parsedOTP.digits
                totpPeriod = parsedOTP.period
                totpAlgorithm = parsedOTP.algorithm
                if let issuer = parsedOTP.issuer, !issuer.isEmpty {
                    title = issuer
                } else if !parsedOTP.label.isEmpty {
                    title = parsedOTP.label
                }
                if let acc = parsedOTP.account, !acc.isEmpty {
                    username = acc
                }
            }
            working.replaceSubrange(otpRange, with: " ")
        }

        // 1. 提取带括号的 2FA 标记，如：2fa(xxxx) / 2fa（xxxx） / 动态码（xxxx） / [2FA: xxxx] / 2fa【xxxx】
        let bracket2FAPattern = #"(?:2fa|totp|双重认证|动态码|验证码|谷歌验证|otp)\s*[:：=]?\s*[（(\[【]([^）)\]】]+)[）)\]】]"#
        if let match = firstMatch(pattern: bracket2FAPattern, in: working) {
            let captured = match.group1
            let cleaned = captured
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "-", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                totpSecret = cleaned
            }
            working.replaceSubrange(match.fullRange, with: " ")
        } else {
            // 2. 提取冒号或空格跟随的 2FA 标记，如：2fa: xxxx / 2FA：xxxx / 2fa=xxxx / 2fa xxxx
            let colon2FAPattern = #"(?:2fa|totp|双重认证|动态码|验证码|谷歌验证|otp)\s*(?:[:：=]\s*|\s+)([A-Za-z0-9=\s-]{3,64}?)(?=$|\r|\n|\t|  |\s+(?:网址|网站|账号|账户|密码|口令|备注|http|用途|域名|资金密码|支付密码))"#
            if let match = firstMatch(pattern: colon2FAPattern, in: working) {
                let captured = match.group1
                let cleaned = captured
                    .replacingOccurrences(of: " ", with: "")
                    .replacingOccurrences(of: "-", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    totpSecret = cleaned
                }
                working.replaceSubrange(match.fullRange, with: " ")
            }
        }

        // 3. 循环提取从属密码（如 资金密码: xxx, 支付密码: xxx, 交易密码: xxx, API Key: xxx, 二级密码: xxx, PIN码: xxx, 安全密码: xxx）
        let extraPasswordPattern = #"(资金密码|支付密码|交易密码|API\s*Key|二级密码|PIN\s*码?|安全密码)\s*[:：=]\s*([^\s\t\r\n]+)"#
        while let match = matchTwoGroups(pattern: extraPasswordPattern, in: working) {
            let lbl = match.group1.trimmingCharacters(in: .whitespacesAndNewlines)
            let val = match.group2.trimmingCharacters(in: .whitespacesAndNewlines)
            if !val.isEmpty {
                extraPasswords.append(LabeledPassword(label: lbl, value: val))
                if !badges.contains(lbl) {
                    badges.append(lbl)
                }
            }
            working.replaceSubrange(match.fullRange, with: " ")
        }

        // 4. 循环提取多行独立备注（如 备注1: xxx, 备注+8: xxx, 密保问题: xxx, 安全提示: xxx, 恢复助记词: xxx, 防钓鱼码: xxx）
        let noteEntryPattern = #"(备注\+?\d*|密保问题|安全提示|恢复助记词|防钓鱼码)\s*[:：=]\s*([^\r\n\t]+?)(?=(?:\s+(?:网址|网站|账号|账户|密码|口令|资金密码|支付密码|用途|域名|接码平台|邮箱|手机号|UID|2fa|totp|备注\+?\d*|密保问题|安全提示|恢复助记词|防钓鱼码)\s*[:：=])|$|\r|\n)"#
        while let match = matchTwoGroups(pattern: noteEntryPattern, in: working) {
            let lbl = match.group1.trimmingCharacters(in: .whitespacesAndNewlines)
            let cnt = match.group2.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cnt.isEmpty {
                noteEntries.append(NoteEntry(label: lbl, content: cnt))
                if !badges.contains(lbl) {
                    badges.append(lbl)
                }
            }
            working.replaceSubrange(match.fullRange, with: " ")
        }

        // 5. 提取自定义账号标签与账号（如 用途: xxx, 域名: xxx, 接码平台: xxx, 邮箱: xxx, 手机号: xxx, 用户名: xxx, 账号: xxx, 账户: xxx, UID: xxx）
        let accountPattern = #"(用途|域名|接码平台|邮箱|手机号|用户名|登录名|账号|账户|UID|user(?:name)?|acc(?:ount)?|email)\s*[:：=]\s*([^\s\t\r\n]+)"#
        if let match = matchTwoGroups(pattern: accountPattern, in: working) {
            accountLabel = match.group1.trimmingCharacters(in: .whitespacesAndNewlines)
            username = match.group2.trimmingCharacters(in: .whitespacesAndNewlines)
            if !badges.contains(accountLabel) {
                badges.append(accountLabel)
            }
            working.replaceSubrange(match.fullRange, with: " ")
        }

        // 6. 提取主密码标签与密码（如 登录密码: xxx, 口令: xxx, 密码: xxx, pass(?:word)?|pwd）
        let passwordPattern = #"(登录密码|口令|密码|pass(?:word)?|pwd)\s*[:：=]\s*([^\s\t\r\n]+)"#
        if let match = matchTwoGroups(pattern: passwordPattern, in: working) {
            passwordLabel = match.group1.trimmingCharacters(in: .whitespacesAndNewlines)
            password = match.group2.trimmingCharacters(in: .whitespacesAndNewlines)
            if !badges.contains(passwordLabel) {
                badges.append(passwordLabel)
            }
            working.replaceSubrange(match.fullRange, with: " ")
        }

        // 7. 提取显式网址与标题
        let urlPattern = #"(?:网址|网站|链接|url|link|site)\s*[:：=]\s*([^\s\t\r\n]+)"#
        if let m = firstMatch(pattern: urlPattern, in: working) {
            url = m.group1.trimmingCharacters(in: .whitespacesAndNewlines)
            if !badges.contains("网址/域名") { badges.append("网址/域名") }
            working.replaceSubrange(m.fullRange, with: " ")
        }
        let titlePattern = #"(?:标题|服务|平台|名称|title|service)\s*[:：=]\s*([^\s\t\r\n]+)"#
        if let m = firstMatch(pattern: titlePattern, in: working) {
            title = m.group1.trimmingCharacters(in: .whitespacesAndNewlines)
            if !badges.contains("服务名称") { badges.append("服务名称") }
            working.replaceSubrange(m.fullRange, with: " ")
        }

        // 8. 提取通用备注（若尚未被 noteEntryPattern 匹配）
        let genNotePattern = #"(?:备注|说明|notes?|memo)\s*[:：=]\s*([^\r\n]+)"#
        if let m = firstMatch(pattern: genNotePattern, in: working) {
            let genNote = m.group1.trimmingCharacters(in: .whitespacesAndNewlines)
            if !genNote.isEmpty {
                if !noteEntries.contains(where: { $0.content == genNote }) {
                    noteEntries.append(NoteEntry(label: "备注", content: genNote))
                }
                if notes.isEmpty {
                    notes = genNote
                } else {
                    notes = "\(notes)\n\(genNote)"
                }
                if !badges.contains("备注") { badges.append("备注") }
            }
            working.replaceSubrange(m.fullRange, with: " ")
        }

        // 9. 将剩余内容按空白、Tab、换行、竖线或逗号切分为词元 (Tokens)
        var tokens = splitIntoTokens(working)

        // 10. 若尚未提取 URL，在 tokens 中寻找域名或网址 (排除包含 @ 的邮箱)
        if url.isEmpty {
            if let idx = tokens.firstIndex(where: { isLikelyURLOrDomain($0) }) {
                url = tokens.remove(at: idx)
            }
        }

        // 11. 若尚未提取 2FA，检查 tokens 中是否有标准 16~64 位 Base32 密钥串
        if totpSecret.isEmpty {
            if let idx = tokens.firstIndex(where: { isLikelyStandaloneBase32($0) }) {
                totpSecret = tokens.remove(at: idx).uppercased()
            }
        }

        // 12. 若尚未提取账号，优先在 tokens 中寻找邮箱或手机号
        if username.isEmpty {
            if let idx = tokens.firstIndex(where: { isLikelyEmailOrPhone($0) }) {
                username = tokens.remove(at: idx)
            }
        }

        // 13. 按位置智能分配剩余词元
        if tokens.count == 1 {
            let tok = tokens.removeFirst()
            if username.isEmpty {
                username = tok
            } else if password.isEmpty {
                password = tok
            } else if title.isEmpty && url.isEmpty {
                title = tok
            } else {
                notes = notes.isEmpty ? tok : "\(notes) \(tok)"
            }
        } else if tokens.count == 2 {
            let first = tokens.removeFirst()
            let second = tokens.removeFirst()
            if username.isEmpty && password.isEmpty {
                username = first
                password = second
            } else if username.isEmpty {
                if title.isEmpty && url.isEmpty {
                    title = first
                    username = second
                } else {
                    username = first
                    notes = notes.isEmpty ? second : "\(notes) \(second)"
                }
            } else if password.isEmpty {
                if title.isEmpty && url.isEmpty {
                    title = first
                    password = second
                } else {
                    password = first
                    notes = notes.isEmpty ? second : "\(notes) \(second)"
                }
            } else {
                let joined = "\(first) \(second)"
                notes = notes.isEmpty ? joined : "\(notes) \(joined)"
            }
        } else if tokens.count >= 3 {
            if url.isEmpty && title.isEmpty {
                title = tokens.removeFirst()
            } else if !url.isEmpty && title.isEmpty && !username.isEmpty {
                title = tokens.removeFirst()
            }
            if username.isEmpty && !tokens.isEmpty {
                username = tokens.removeFirst()
            }
            if password.isEmpty && !tokens.isEmpty {
                password = tokens.removeFirst()
            }
            if !tokens.isEmpty {
                let extra = tokens.joined(separator: " ")
                notes = notes.isEmpty ? extra : "\(notes) \(extra)"
            }
        }

        // 14. 根据 URL 智能推导服务名称 (Title)
        if title.isEmpty && !url.isEmpty {
            title = deriveServiceTitle(from: url)
        }
        if title.isEmpty {
            if !username.isEmpty {
                title = username
            } else if !totpSecret.isEmpty {
                title = "2FA 动态码密钥"
            }
        }

        let normalizedURL = normalizeURL(url)

        // 15. 备注与 noteEntries 同步
        if notes.isEmpty && !noteEntries.isEmpty {
            notes = noteEntries.map { "\($0.effectiveLabel)：\($0.content)" }.joined(separator: "\n")
        } else if !notes.isEmpty && noteEntries.isEmpty {
            noteEntries = [NoteEntry(label: "备注", content: notes)]
        }

        // 16. 智能分类识别
        let inferredCategory = inferCategory(
            title: title,
            url: normalizedURL,
            username: username,
            notes: notes,
            fallback: defaultCategory
        )

        // 17. 汇总已识别标签
        if !normalizedURL.isEmpty && !badges.contains("网址/域名") {
            badges.append("网址/域名")
        } else if !title.isEmpty && !badges.contains("服务名称") {
            badges.append("服务名称")
        }
        if !username.isEmpty && !badges.contains(accountLabel) {
            badges.append(accountLabel)
        }
        if !password.isEmpty && !badges.contains(passwordLabel) {
            badges.append(passwordLabel)
        }
        if !totpSecret.isEmpty && !badges.contains("2FA 密钥") {
            badges.append("2FA 密钥")
        }
        if !notes.isEmpty && !badges.contains("备注") && noteEntries.isEmpty {
            badges.append("备注")
        }

        return ParsedCredential(
            title: title,
            url: normalizedURL,
            accountLabel: accountLabel,
            username: username,
            passwordLabel: passwordLabel,
            password: password,
            extraPasswords: extraPasswords,
            totpSecret: totpSecret,
            totpDigits: totpDigits,
            totpPeriod: totpPeriod,
            totpAlgorithm: totpAlgorithm,
            category: inferredCategory,
            notes: notes,
            noteEntries: noteEntries,
            recognizedFields: badges
        )
    }

    /// 支持批量多行识别（当用户一次性粘贴多行完整记录时，自动拆分为多条；若多行仅是同一条记录的不同字段则合并为单条）
    public static func parseBatch(_ rawInput: String, defaultCategory: AccountCategory = .general) -> [ParsedCredential] {
        let lines = rawInput
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard lines.count >= 2 else {
            let single = parse(rawInput, defaultCategory: defaultCategory)
            return single.hasAnyContent ? [single] : []
        }

        let lineParsed = lines.map { parse($0, defaultCategory: defaultCategory) }
        let allLinesAreCompleteRecords = lineParsed.allSatisfy { item in
            let fieldCount = (!item.url.isEmpty ? 1 : 0) +
                             (!item.username.isEmpty ? 1 : 0) +
                             (!item.password.isEmpty ? 1 : 0) +
                             (!item.totpSecret.isEmpty ? 1 : 0) +
                             (!item.extraPasswords.isEmpty ? 1 : 0)
            return fieldCount >= 2 && (!item.username.isEmpty || !item.password.isEmpty || !item.extraPasswords.isEmpty)
        }

        if allLinesAreCompleteRecords {
            var results = lineParsed
            if let first = results.first, (!first.url.isEmpty || (!first.title.isEmpty && first.title != first.username)) {
                for idx in 1..<results.count {
                    if results[idx].url.isEmpty && (results[idx].title.isEmpty || results[idx].title == results[idx].username) {
                        results[idx].url = first.url
                        results[idx].title = first.title
                        results[idx].category = first.category
                    }
                }
            }
            return results
        } else {
            let single = parse(rawInput, defaultCategory: defaultCategory)
            return single.hasAnyContent ? [single] : []
        }
    }

    /// 针对已有服务下快速追加子账号/密码/2FA 的解析（可选锁定使用同一密码）
    public static func parseSubAccount(_ rawInput: String, lockedPassword: String? = nil) -> CredentialEntry {
        let parsed = parse(rawInput)
        if let locked = lockedPassword {
            let finalUser: String
            if !parsed.username.isEmpty {
                finalUser = parsed.username
            } else if !parsed.title.isEmpty {
                finalUser = parsed.title
            } else {
                finalUser = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return CredentialEntry(
                accountLabel: parsed.accountLabel,
                username: finalUser,
                passwordLabel: parsed.passwordLabel,
                password: locked,
                extraPasswords: parsed.extraPasswords,
                totpSecret: parsed.totpSecret,
                totpDigits: parsed.totpDigits,
                totpPeriod: parsed.totpPeriod,
                totpAlgorithm: parsed.totpAlgorithm,
                notes: parsed.notes
            )
        } else {
            return parsed.toCredentialEntry()
        }
    }

    // MARK: - 内部正则与启发式工具

    private struct RegexMatchResult {
        let fullRange: Range<String.Index>
        let group1: String
    }

    private struct TwoGroupMatchResult {
        let fullRange: Range<String.Index>
        let group1: String
        let group2: String
    }

    private static func firstMatch(pattern: String, in text: String) -> RegexMatchResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange),
              match.numberOfRanges >= 2,
              let fullRange = Range(match.range(at: 0), in: text),
              let group1Range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return RegexMatchResult(fullRange: fullRange, group1: String(text[group1Range]))
    }

    private static func matchTwoGroups(pattern: String, in text: String) -> TwoGroupMatchResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange),
              match.numberOfRanges >= 3,
              let fullRange = Range(match.range(at: 0), in: text),
              let g1Range = Range(match.range(at: 1), in: text),
              let g2Range = Range(match.range(at: 2), in: text) else {
            return nil
        }
        return TwoGroupMatchResult(
            fullRange: fullRange,
            group1: String(text[g1Range]),
            group2: String(text[g2Range])
        )
    }

    private static func splitIntoTokens(_ text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "　", with: " ")
        let parts = normalized.components(separatedBy: CharacterSet(charactersIn: " \t\n\r|,;；"))
        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func isLikelyURLOrDomain(_ token: String) -> Bool {
        let lower = token.lowercased()
        if lower.contains("@") { return false }
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return true
        }
        let domainPattern = #"^[a-zA-Z0-9][-a-zA-Z0-9]{0,62}(?:\.[a-zA-Z0-9][-a-zA-Z0-9]{0,62})*\.[a-zA-Z]{2,12}(?::\d+)?(?:\/[^\s]*)?$"#
        return lower.range(of: domainPattern, options: .regularExpression) != nil
    }

    private static func isLikelyEmailOrPhone(_ token: String) -> Bool {
        let emailPattern = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        if token.range(of: emailPattern, options: .regularExpression) != nil {
            return true
        }
        let phonePattern = #"^\+?1?[3-9]\d{9,10}$"#
        if token.range(of: phonePattern, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private static func isLikelyStandaloneBase32(_ token: String) -> Bool {
        let upper = token.uppercased()
        guard upper.count >= 16 && upper.count <= 64 else { return false }
        let pattern = #"^[A-Z2-7]+=*$"#
        guard upper.range(of: pattern, options: .regularExpression) != nil else { return false }
        return (try? TOTPEngine.decodeBase32(upper)) != nil
    }

    private static func normalizeURL(_ rawURL: String) -> String {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed
    }

    private static func deriveServiceTitle(from rawURL: String) -> String {
        var clean = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.lowercased().hasPrefix("http://") && !clean.lowercased().hasPrefix("https://") {
            clean = "https://" + clean
        }
        let host: String = {
            if let urlObj = URL(string: clean), let h = urlObj.host {
                return h.lowercased()
            }
            return rawURL.lowercased()
        }()

        let exactHostBrands: [(String, String)] = [
            ("binance.", "Binance"),
            ("okx.", "OKX"),
            ("bybit.", "Bybit"),
            ("gate.", "Gate.io"),
            ("bitget.", "Bitget"),
            ("coinbase.", "Coinbase"),
            ("kraken.", "Kraken"),
            ("metamask.", "MetaMask"),
            ("github.", "GitHub"),
            ("gitlab.", "GitLab"),
            ("gitee.", "Gitee"),
            ("openai.", "OpenAI"),
            ("chatgpt.", "ChatGPT"),
            ("claude.", "Anthropic Claude"),
            ("anthropic.", "Anthropic"),
            ("deepseek.", "DeepSeek"),
            ("google.", "Google"),
            ("gmail.", "Gmail"),
            ("apple.", "Apple ID"),
            ("icloud.", "iCloud"),
            ("telegram.", "Telegram"),
            ("twitter.", "X (Twitter)"),
            ("discord.", "Discord"),
            ("paypal.", "PayPal"),
            ("stripe.", "Stripe"),
            ("alipay.", "支付宝"),
            ("qq.", "腾讯 QQ"),
            ("163.", "网易邮箱"),
            ("aliyun.", "阿里云"),
            ("cloudflare.", "Cloudflare"),
            ("amazonaws.", "AWS")
        ]

        if host == "x.com" || host.hasSuffix(".x.com") {
            return "X (Twitter)"
        }

        for (prefix, brand) in exactHostBrands {
            if host.hasPrefix(prefix) || host.contains(".\(prefix)") {
                return brand
            }
        }

        var strippedHost = host
        if strippedHost.hasPrefix("www.") {
            strippedHost = String(strippedHost.dropFirst(4))
        }
        return strippedHost
    }

    public static func inferCategory(
        title: String,
        url: String,
        username: String,
        notes: String,
        fallback: AccountCategory = .general
    ) -> AccountCategory {
        let hay = "\(title) \(url) \(username) \(notes)".lowercased()

        let cryptoKeywords = ["binance", "币安", "okx", "欧易", "bybit", "gate.io", "bitget", "coinbase", "kraken", "kucoin", "metamask", "phantom", "ledger", "trezor", "uniswap", "hyperliquid", "tradingview", "coinglass", "crypto", "web3", "交易所", "钱包"]
        if cryptoKeywords.contains(where: { hay.contains($0) }) {
            return .crypto
        }

        let aiKeywords = ["openai", "chatgpt", "claude", "anthropic", "deepseek", "midjourney", "gemini", "huggingface", "cursor", "perplexity", "大模型", "算力"]
        if aiKeywords.contains(where: { hay.contains($0) }) {
            return .ai
        }

        let workKeywords = ["github", "gitlab", "gitee", "aws", "aliyun", "阿里云", "腾讯云", "cloudflare", "docker", "vercel", "supabase", "server", "服务器", "ssh", "vps", "代码"]
        if workKeywords.contains(where: { hay.contains($0) }) {
            return .work
        }

        let financeKeywords = ["paypal", "stripe", "alipay", "支付宝", "wise", "ibkr", "盈透", "富途", "bank", "银行", "券商", "信用卡"]
        if financeKeywords.contains(where: { hay.contains($0) }) {
            return .finance
        }

        let socialKeywords = ["google", "gmail", "outlook", "proton", "qq.com", "163.com", "apple", "icloud", "telegram", "discord", "twitter", "wechat", "微信", "微博", "邮箱"]
        if socialKeywords.contains(where: { hay.contains($0) }) || url.lowercased() == "x.com" || url.lowercased().hasSuffix(".x.com") {
            return .social
        }

        return fallback
    }
}
