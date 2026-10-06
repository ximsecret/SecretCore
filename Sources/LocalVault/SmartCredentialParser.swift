import Foundation

public struct ParsedCredential: Equatable, Identifiable {
    public var id: UUID = UUID()
    public var title: String
    public var url: String
    public var username: String
    public var password: String
    public var totpSecret: String
    public var totpDigits: Int
    public var totpPeriod: Int
    public var totpAlgorithm: TOTPAlgorithm
    public var category: AccountCategory
    public var notes: String
    public var recognizedFields: [String]

    public var hasAnyContent: Bool {
        !title.isEmpty || !url.isEmpty || !username.isEmpty || !password.isEmpty || !totpSecret.isEmpty
    }

    public var hasValidBase32TOTP: Bool {
        let cleaned = totpSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return false }
        return (try? TOTPEngine.decodeBase32(cleaned)) != nil
    }

    public func toCredentialEntry() -> CredentialEntry {
        CredentialEntry(
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password,
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

        return AccountItem(
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
            entries: [entry],
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

public enum SmartCredentialParser {

    /// 智能解析单条文本（支持单行空格/Tab分隔、带括号2FA、带标签键值对或多行分段）
    /// 例如: "xxxx.com   xxx账号   xxx密码    2fa（xxxx）"
    public static func parse(_ rawInput: String, defaultCategory: AccountCategory = .general) -> ParsedCredential {
        var working = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if working.isEmpty {
            return ParsedCredential(
                title: "",
                url: "",
                username: "",
                password: "",
                totpSecret: "",
                totpDigits: 6,
                totpPeriod: 30,
                totpAlgorithm: .sha1,
                category: defaultCategory,
                notes: "",
                recognizedFields: []
            )
        }

        var title = ""
        var url = ""
        var username = ""
        var password = ""
        var totpSecret = ""
        var totpDigits = 6
        var totpPeriod = 30
        var totpAlgorithm: TOTPAlgorithm = .sha1
        var notes = ""
        var badges: [String] = []

        // 0. 检查是否包含 otpauth:// 协议链接
        if let otpRange = working.range(of: #"otpauth:\/\/[^\s\t\n]+"#, options: [.regularExpression, .caseInsensitive]) {
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
            let colon2FAPattern = #"(?:2fa|totp|双重认证|动态码|验证码|谷歌验证|otp)\s*(?:[:：=]\s*|\s+)([A-Za-z0-9=\s-]{3,64}?)(?=$|\n|\r|\t|  |\s+(?:网址|账号|密码|备注|http))"#
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

        // 3. 提取显式标签字段 (如 "网址: xxx", "账号: xxx", "密码: xxx", "标题: xxx", "备注: xxx")
        if let m = firstMatch(pattern: #"(?:网址|网站|链接|域名|url|link|domain|site)\s*[:：=]\s*([^\s\t\n]+)"#, in: working) {
            url = m.group1.trimmingCharacters(in: .whitespacesAndNewlines)
            working.replaceSubrange(m.fullRange, with: " ")
        }
        if let m = firstMatch(pattern: #"(?:账号|账户|用户名|登录名|用户|邮箱|user(?:name)?|acc(?:ount)?|email|uid)\s*[:：=]\s*([^\s\t\n]+)"#, in: working) {
            username = m.group1.trimmingCharacters(in: .whitespacesAndNewlines)
            working.replaceSubrange(m.fullRange, with: " ")
        }
        if let m = firstMatch(pattern: #"(?:密码|口令|登录密码|pass(?:word)?|pwd)\s*[:：=]\s*([^\s\t\n]+)"#, in: working) {
            password = m.group1.trimmingCharacters(in: .whitespacesAndNewlines)
            working.replaceSubrange(m.fullRange, with: " ")
        }
        if let m = firstMatch(pattern: #"(?:标题|服务|平台|名称|title|service)\s*[:：=]\s*([^\s\t\n]+)"#, in: working) {
            title = m.group1.trimmingCharacters(in: .whitespacesAndNewlines)
            working.replaceSubrange(m.fullRange, with: " ")
        }
        if let m = firstMatch(pattern: #"(?:备注|说明|notes?|memo)\s*[:：=]\s*([^\n\r]+)"#, in: working) {
            notes = m.group1.trimmingCharacters(in: .whitespacesAndNewlines)
            working.replaceSubrange(m.fullRange, with: " ")
        }

        // 4. 将剩余内容按空白、Tab、换行、竖线或逗号切分为词元 (Tokens)
        var tokens = splitIntoTokens(working)

        // 5. 若尚未提取 URL，在 tokens 中寻找域名或网址 (排除包含 @ 的邮箱)
        if url.isEmpty {
            if let idx = tokens.firstIndex(where: { isLikelyURLOrDomain($0) }) {
                url = tokens.remove(at: idx)
            }
        }

        // 6. 若尚未提取 2FA，检查 tokens 中是否有标准 16~64 位 Base32 密钥串
        if totpSecret.isEmpty {
            if let idx = tokens.firstIndex(where: { isLikelyStandaloneBase32($0) }) {
                totpSecret = tokens.remove(at: idx).uppercased()
            }
        }

        // 7. 若尚未提取账号，优先在 tokens 中寻找邮箱或手机号
        if username.isEmpty {
            if let idx = tokens.firstIndex(where: { isLikelyEmailOrPhone($0) }) {
                username = tokens.remove(at: idx)
            }
        }

        // 8. 按位置智能分配剩余词元
        // 典型输入: "xxxx.com   xxx账号   xxx密码    2fa（xxxx）"
        // 此时 url="xxxx.com", totpSecret="xxxx", 剩余 tokens=["xxx账号", "xxx密码"]
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
            // 如果没有域名/URL 且也没有标题，第一个词元通常是服务名称（例如："币安主号  my_user  my_pass  2fa(xxx)"）
            if url.isEmpty && title.isEmpty {
                title = tokens.removeFirst()
            } else if !url.isEmpty && title.isEmpty && !username.isEmpty {
                // 如果已经有 URL 和邮箱账号，第一个可能是标题
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

        // 9. 根据 URL 智能推导服务名称 (Title)
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

        // 规范化 URL (如 xxxx.com 保持或补全)
        let normalizedURL = normalizeURL(url)

        // 10. 智能分类识别
        let inferredCategory = inferCategory(
            title: title,
            url: normalizedURL,
            username: username,
            notes: notes,
            fallback: defaultCategory
        )

        // 11. 汇总已识别标签
        if !normalizedURL.isEmpty {
            badges.append("网址/域名")
        } else if !title.isEmpty {
            badges.append("服务名称")
        }
        if !username.isEmpty {
            badges.append("登录账号")
        }
        if !password.isEmpty {
            badges.append("登录密码")
        }
        if !totpSecret.isEmpty {
            badges.append("2FA 密钥")
        }
        if !notes.isEmpty {
            badges.append("备注信息")
        }

        return ParsedCredential(
            title: title,
            url: normalizedURL,
            username: username,
            password: password,
            totpSecret: totpSecret,
            totpDigits: totpDigits,
            totpPeriod: totpPeriod,
            totpAlgorithm: totpAlgorithm,
            category: inferredCategory,
            notes: notes,
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

        // 判断是否每一行都是一条独立的完整记录（例如每行都包含 >= 3 个词元，或每行都有账号+密码）
        let lineParsed = lines.map { parse($0, defaultCategory: defaultCategory) }
        let allLinesAreCompleteRecords = lineParsed.allSatisfy { item in
            let fieldCount = (!item.url.isEmpty ? 1 : 0) +
                             (!item.username.isEmpty ? 1 : 0) +
                             (!item.password.isEmpty ? 1 : 0) +
                             (!item.totpSecret.isEmpty ? 1 : 0)
            return fieldCount >= 2 && (!item.username.isEmpty || !item.password.isEmpty)
        }

        if allLinesAreCompleteRecords {
            var results = lineParsed
            // 如果第一行包含明确的域名或服务名称，而后续行省略了域名（仅写了 账号 密码 2fa），则自动归属到同一服务名下
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
            // 锁定同密码模式：若用户输入了 2 个词（没有识别为 2FA），且没写密码标签，第一词为账号，若第二词不是密码而是备注或未提取 2FA
            let finalUser: String
            if !parsed.username.isEmpty {
                finalUser = parsed.username
            } else if !parsed.title.isEmpty {
                finalUser = parsed.title
            } else {
                finalUser = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return CredentialEntry(
                username: finalUser,
                password: locked,
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

    private static func splitIntoTokens(_ text: String) -> [String] {
        // 将全角空格替换为普通空格，并按空白/Tab/换行/逗号/竖线切分
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
        // 匹配常见域名格式，如 xxxx.com / binance.com / sub.domain.org/login
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
        // 标准 TOTP Base32 密钥通常为 16~64 位仅含 A-Z 和 2-7 的大写字符串
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

        // 精确知名品牌映射
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

        // 常规域名提取主干名，如 xxxx.com -> xxxx.com
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
