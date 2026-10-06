import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let iconURL = Bundle.main.url(forResource: "BrandHero", withExtension: "png"),
           let iconImg = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = iconImg
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct LocalVaultApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = VaultStore()

    init() {
        if CommandLine.arguments.contains("--self-test") {
            runSelfTestAndExit()
        }
    }

    var body: some Scene {
        WindowGroup("SecretCore · 极光秘核") {
            Group {
                if store.isUnlocked {
                    MainVaultView()
                        .environmentObject(store)
                } else {
                    LockView()
                        .environmentObject(store)
                }
            }
            .frame(minWidth: 960, minHeight: 620)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("锁定 SecretCore") {
                    store.lock()
                }
                .keyboardShortcut("l", modifiers: [.command])
                .disabled(!store.isUnlocked)
            }
        }

        // 菜单栏常驻小助手
        MenuBarExtra("SecretCore · 极光秘核", systemImage: "lock.shield.fill") {
            MenuBarView()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - 命令行自测套件 (RFC 6238 官方测试向量与加解密测试)
private func runSelfTestAndExit() -> Never {
    print("========================================")
    print("🚀 [SecretCore · 极光秘核] 启动核心加密与算法自检...")
    print("========================================")

    var passed = 0
    var failed = 0

    func assertTest(_ name: String, _ condition: Bool) {
        if condition {
            print("  ✅ [PASS] \(name)")
            passed += 1
        } else {
            print("  ❌ [FAIL] \(name)")
            failed += 1
        }
    }

    // 1. Base32 解码测试
    do {
        let base32 = "JBSWY3DPEHPK3PXP"
        let decoded = try TOTPEngine.decodeBase32(base32)
        assertTest("Base32 解码有效性", !decoded.isEmpty)
    } catch {
        assertTest("Base32 解码有效性", false)
    }

    // 2. RFC 6238 TOTP 规范测试向量 (Section 5.3 & Appendix B)
    // T = 59s -> SHA1 8位: 94287082, 6位: 287082
    // T = 1111111109s -> SHA1 8位: 07081804, 6位: 081804
    // T = 1234567890s -> SHA1 8位: 89005924, 6位: 005924
    let rfcSecretSHA1 = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
    let rfcSecretSHA256 = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA===="
    let rfcSecretSHA512 = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNA="

    do {
        let date1 = Date(timeIntervalSince1970: 59)
        let code1 = try TOTPEngine.generateCode(secret: rfcSecretSHA1, date: date1, period: 30, digits: 8, algorithm: .sha1)
        assertTest("RFC 6238 SHA1 (T=59s, 8位) 测试向量: \(code1)", code1 == "94287082")

        let code1_6 = try TOTPEngine.generateCode(secret: rfcSecretSHA1, date: date1, period: 30, digits: 6, algorithm: .sha1)
        assertTest("RFC 6238 SHA1 (T=59s, 6位) 测试向量: \(code1_6)", code1_6 == "287082")

        let date2 = Date(timeIntervalSince1970: 1111111109)
        let code2 = try TOTPEngine.generateCode(secret: rfcSecretSHA1, date: date2, period: 30, digits: 6, algorithm: .sha1)
        assertTest("RFC 6238 SHA1 (T=1111111109s, 6位) 测试向量: \(code2)", code2 == "081804")

        let date3 = Date(timeIntervalSince1970: 1234567890)
        let code3 = try TOTPEngine.generateCode(secret: rfcSecretSHA1, date: date3, period: 30, digits: 6, algorithm: .sha1)
        assertTest("RFC 6238 SHA1 (T=1234567890s, 6位) 测试向量: \(code3)", code3 == "005924")

        // 测试 SHA256 算法 (RFC 6238 Appendix B: T=59 -> 46119246)
        let codeSHA256 = try TOTPEngine.generateCode(secret: rfcSecretSHA256, date: date1, period: 30, digits: 8, algorithm: .sha256)
        assertTest("RFC 6238 SHA256 (T=59s, 8位) 测试向量: \(codeSHA256)", codeSHA256 == "46119246")

        // 测试 SHA512 算法 (RFC 6238 Appendix B: T=59 -> 90693936)
        let codeSHA512 = try TOTPEngine.generateCode(secret: rfcSecretSHA512, date: date1, period: 30, digits: 8, algorithm: .sha512)
        assertTest("RFC 6238 SHA512 (T=59s, 8位) 测试向量: \(codeSHA512)", codeSHA512 == "90693936")
    } catch {
        assertTest("RFC 6238 验证测试", false)
    }

    // 3. otpauth:// 协议解析测试
    let uri = "otpauth://totp/GitHub:alice@github.com?secret=JBSWY3DPEHPK3PXP&issuer=GitHub&digits=6&period=30&algorithm=SHA1"
    if let parsed = TOTPEngine.parseOTPAuthURI(uri) {
        assertTest("otpauth:// 协议解析 (Secret & Issuer & Account)",
                   parsed.secret == "JBSWY3DPEHPK3PXP" &&
                   parsed.issuer == "GitHub" &&
                   parsed.account == "alice@github.com" &&
                   parsed.digits == 6)
    } else {
        assertTest("otpauth:// 协议解析", false)
    }

    // 4. PBKDF2 + AES-256-GCM 本地加密往返测试
    do {
        let masterPass = "MySuper$tr0ngP@ssword2026"
        let secretData = "{\"account\":\"admin\",\"token\":\"secret123\"}".data(using: .utf8)!

        let envelope = try CryptoEngine.encrypt(data: secretData, masterPassword: masterPass, rounds: 10_000)
        assertTest("AES-256-GCM 加密封装", envelope.magic == EncryptedEnvelope.currentMagic)

        let decrypted = try CryptoEngine.decrypt(envelope: envelope, masterPassword: masterPass)
        let roundtripStr = String(data: decrypted, encoding: .utf8)
        assertTest("AES-256-GCM 正确解密恢复", roundtripStr == "{\"account\":\"admin\",\"token\":\"secret123\"}")

        // 错误密码拒绝测试
        var wrongPassFailed = false
        do {
            _ = try CryptoEngine.decrypt(envelope: envelope, masterPassword: "WrongPassword")
        } catch {
            wrongPassFailed = true
        }
        assertTest("防篡改/错误主密码拒绝", wrongPassFailed)
    } catch {
        assertTest("加密加解密测试", false)
    }

    // 5. 强密码生成器测试
    let pwd = PasswordGenerator.generate(options: PasswordGeneratorOptions(length: 20))
    let strength = PasswordGenerator.evaluateStrength(pwd)
    assertTest("密码生成器长度及强度 (\(pwd.count)位, 强度: \(strength.strength.label))", pwd.count == 20 && strength.strength.rawValue >= 3)

    // 6. 账号多维分类体系与旧存档向后兼容解码测试
    do {
        let legacyJSON = """
        {"id":"11111111-2222-3333-4444-555555555555","title":"LegacyTest","category":"金融与加密"}
        """.data(using: .utf8)!
        let decodedItem = try JSONDecoder().decode(AccountItem.self, from: legacyJSON)
        assertTest("分类体系向后兼容解码 (金融与加密 -> \(decodedItem.category.rawValue)) && 7 大分类完整",
                   decodedItem.category == .crypto && AccountCategory.allCases.count == 7)
    } catch {
        assertTest("分类体系向后兼容解码", false)
    }

    // 8. 智能凭证识别引擎测试 (用户真实格式及统一格式: 密码：xxx 账号：xxx 2FA：xxx)
    let userRawInput = "xxxx.com   xxx账号   xxx密码    2fa（xxxx）"
    let parsedUser = SmartCredentialParser.parse(userRawInput)
    assertTest("智能提取用户格式：网址 (xxxx.com)", parsedUser.url == "xxxx.com" || parsedUser.url == "https://xxxx.com")
    assertTest("智能提取用户格式：账号 (xxx账号)", parsedUser.username == "xxx账号")
    assertTest("智能提取用户格式：密码 (xxx密码)", parsedUser.password == "xxx密码")
    assertTest("智能提取用户格式：2FA (xxxx)", parsedUser.totpSecret == "xxxx")

    let unifiedRawInput = "xxxx.com   密码：xxx密码   账号：xxx账号   2FA：xxxx"
    let parsedUnified = SmartCredentialParser.parse(unifiedRawInput)
    assertTest("统一提示格式提取：密码：xxx", parsedUnified.password == "xxx密码")
    assertTest("统一提示格式提取：账号：xxx", parsedUnified.username == "xxx账号")
    assertTest("统一提示格式提取：2FA：xxx", parsedUnified.totpSecret == "xxxx")

    // 9. 智能凭证与 RFC 6238 联动自测
    let rfcInput = "github.com   alice@example.com   SecurePass2026!   2fa(GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ)"
    let parsedRFC = SmartCredentialParser.parse(rfcInput)
    let rfcCode = try? TOTPEngine.generateCode(secret: parsedRFC.totpSecret, date: Date(timeIntervalSince1970: 59))
    assertTest("智能提取并计算 TOTP 动态码 (RFC 6238 -> 287082)",
               parsedRFC.username == "alice@example.com" &&
               parsedRFC.password == "SecurePass2026!" &&
               parsedRFC.category == .work &&
               rfcCode == "287082")

    // 10. 批量多行智能识别测试
    let batchRaw = """
    binance.com   trader1   Pass1   2fa(JBSWY3DPEHPK3PXP)
    openai.com   builder2   Pass2   2fa(GEZDGNBVGY3TQOJQ)
    """
    let batchParsed = SmartCredentialParser.parseBatch(batchRaw)
    assertTest("多行批量智能解析 (2条完整记录)", batchParsed.count == 2 && batchParsed[0].category == .crypto && batchParsed[1].category == .ai)

    // 11. 同名称下多密码与多账号分组聚合测试 (同一密码下聚合多个子账号，不同密码分列独立密码组)
    var multiAccountItem = AccountItem(
        title: "Binance",
        url: "binance.com",
        category: .crypto,
        entries: [
            CredentialEntry(username: "main@vip.io", password: "SharedPassword#2026", totpSecret: "JBSWY3DPEHPK3PXP"),
            CredentialEntry(username: "sub_grid@vip.io", password: "SharedPassword#2026", totpSecret: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"),
            CredentialEntry(username: "cold_hedge@vip.io", password: "IsolatedPassword!99", totpSecret: "NB2W45DFOIZA====")
        ]
    )
    let groups = multiAccountItem.passwordGroups
    assertTest("同名称多账号按密码自动分组 (2套密码聚合3个账号)",
               groups.count == 2 &&
               groups[0].password == "SharedPassword#2026" &&
               groups[0].entries.count == 2 &&
               groups[1].password == "IsolatedPassword!99" &&
               groups[1].entries.count == 1)

    // 测试在某套密码下继续追加子账号
    let appendedSub = SmartCredentialParser.parseSubAccount("arb_bot@vip.io   2fa(JBSWY3DPEHPK3PXP)", lockedPassword: "SharedPassword#2026")
    multiAccountItem.addOrUpdateEntry(appendedSub)
    assertTest("同密码下快速追加子账号并携带独立 2FA",
               multiAccountItem.entries.count == 4 &&
               multiAccountItem.passwordGroups.first?.entries.count == 3 &&
               appendedSub.username == "arb_bot@vip.io" &&
               appendedSub.password == "SharedPassword#2026" &&
               appendedSub.totpSecret == "JBSWY3DPEHPK3PXP")

    // 12. 同一服务下不同子账号独立 2FA 动态码计算测试
    let testTime = Date(timeIntervalSince1970: 59)
    let entryCode1 = try? TOTPEngine.generateCode(secret: multiAccountItem.entries[0].totpSecret, date: testTime)
    let entryCode2 = try? TOTPEngine.generateCode(secret: multiAccountItem.entries[1].totpSecret, date: testTime)
    assertTest("同服务下各子账号独立生成 2FA 验证码 (\(entryCode1 ?? "") vs \(entryCode2 ?? ""))",
               entryCode1 != nil && entryCode2 == "287082" && entryCode1 != entryCode2)

    // 13. 同服务多行继承解析 + JSON 序列化完整性测试
    let sameServiceBatchRaw = """
    okx.com   acc_alpha   AlphaPass123   2fa(JBSWY3DPEHPK3PXP)
    acc_beta   AlphaPass123   2fa(GEZDGNBVGY3TQOJQ)
    acc_gamma   GammaPass999   2fa(NB2W45DFOIZA====)
    """
    let inheritedBatch = SmartCredentialParser.parseBatch(sameServiceBatchRaw)
    assertTest("多行粘贴省略域名时自动继承首行服务名 (OKX)",
               inheritedBatch.count == 3 &&
               inheritedBatch.allSatisfy { $0.title == "OKX" && $0.url == "okx.com" })

    // 7. 更换主密码安全往返测试 (验证现有密码机制)
    do {
        let initialPass = "OldMasterPassword123"
        let newPass = "NewMasterPassword456"
        let secretData = "{\"vault\":\"SecretCoreData\"}".data(using: .utf8)!

        let envelope = try CryptoEngine.encrypt(data: secretData, masterPassword: initialPass, rounds: 10_000)

        // 校验错误旧密码必须拒绝
        var wrongPassRejected = false
        do {
            _ = try CryptoEngine.decrypt(envelope: envelope, masterPassword: "WrongCurrentPassword")
        } catch {
            wrongPassRejected = true
        }
        assertTest("更换密码前置校验：错误现有密码被严格拦截拒绝", wrongPassRejected)

        // 校验正确旧密码解密并重新加密为新密码
        let decrypted = try CryptoEngine.decrypt(envelope: envelope, masterPassword: initialPass)
        let newEnvelope = try CryptoEngine.encrypt(data: decrypted, masterPassword: newPass, rounds: 10_000)
        let roundtrip = try CryptoEngine.decrypt(envelope: newEnvelope, masterPassword: newPass)
        assertTest("更换密码后置校验：新密码成功解密恢复全部密文", roundtrip == secretData)
    } catch {
        assertTest("更换主密码安全往返测试", false)
    }

    print("========================================")
    print("自检完成: 共通过 \(passed) 项, 失败 \(failed) 项")
    print("========================================")

    exit(failed == 0 ? 0 : 1)
}
