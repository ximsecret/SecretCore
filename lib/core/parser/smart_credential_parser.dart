import '../models/account_category.dart';
import '../models/account_item.dart';
import '../models/credential_entry.dart';
import '../models/labeled_password.dart';
import '../models/note_entry.dart';
import '../totp/base32.dart';
import '../totp/totp_engine.dart';

class ParsedCredential {
  String title;
  String url;
  String accountLabel;
  String username;
  String passwordLabel;
  String password;
  List<LabeledPassword> extraPasswords;
  String totpSecret;
  int totpDigits;
  int totpPeriod;
  TOTPAlgorithm totpAlgorithm;
  AccountCategory category;
  List<NoteEntry> noteEntries;
  List<String> recognizedBadges;

  ParsedCredential({
    this.title = '',
    this.url = '',
    this.accountLabel = '账号',
    this.username = '',
    this.passwordLabel = '密码',
    this.password = '',
    List<LabeledPassword>? extraPasswords,
    this.totpSecret = '',
    this.totpDigits = 6,
    this.totpPeriod = 30,
    this.totpAlgorithm = TOTPAlgorithm.sha1,
    this.category = AccountCategory.general,
    List<NoteEntry>? noteEntries,
    List<String>? recognizedBadges,
  })  : extraPasswords = extraPasswords ?? [],
        noteEntries = noteEntries ?? [],
        recognizedBadges = recognizedBadges ?? [];

  bool get hasContent =>
      title.isNotEmpty ||
      url.isNotEmpty ||
      username.isNotEmpty ||
      password.isNotEmpty ||
      totpSecret.isNotEmpty;

  CredentialEntry toCredentialEntry() {
    return CredentialEntry(
      accountLabel: accountLabel,
      username: username,
      passwordLabel: passwordLabel,
      password: password,
      extraPasswords: extraPasswords,
      totpSecret: totpSecret,
      totpDigits: totpDigits,
      totpPeriod: totpPeriod,
      totpAlgorithm: totpAlgorithm,
    );
  }

  AccountItem toAccountItem() {
    final finalTitle = title.trim().isNotEmpty
        ? title.trim()
        : (url.trim().isNotEmpty ? deriveServiceTitle(url) : (username.trim().isNotEmpty ? username.trim() : '未命名账号'));

    final entry = toCredentialEntry();

    return AccountItem(
      title: finalTitle,
      url: url.trim(),
      category: category,
      entries: [entry],
      noteEntries: noteEntries,
    );
  }

  static String deriveServiceTitle(String rawUrl) {
    var clean = rawUrl.trim();
    if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
      clean = 'https://$clean';
    }
    final uri = Uri.tryParse(clean);
    final host = uri?.host.toLowerCase() ?? rawUrl.toLowerCase();

    final brands = <String, String>{
      'binance.': 'Binance',
      'okx.': 'OKX',
      'bybit.': 'Bybit',
      'gate.': 'Gate.io',
      'bitget.': 'Bitget',
      'coinbase.': 'Coinbase',
      'github.': 'GitHub',
      'gitlab.': 'GitLab',
      'openai.': 'OpenAI',
      'chatgpt.': 'ChatGPT',
      'claude.': 'Claude',
      'anthropic.': 'Anthropic',
      'deepseek.': 'DeepSeek',
      'google.': 'Google',
      'gmail.': 'Gmail',
      'apple.': 'Apple ID',
      'telegram.': 'Telegram',
      'twitter.': 'X (Twitter)',
      'x.com': 'X (Twitter)',
      'discord.': 'Discord',
      'paypal.': 'PayPal',
      'stripe.': 'Stripe',
      'alipay.': '支付宝',
    };

    for (final entry in brands.entries) {
      if (host.contains(entry.key)) {
        return entry.value;
      }
    }

    var stripped = host;
    if (stripped.startsWith('www.')) {
      stripped = stripped.substring(4);
    }
    return stripped;
  }
}

class SmartCredentialParser {
  /// 智能解析单条或多行文本
  /// 支持: xxxx.com   xxx账号   xxx密码    2fa（xxxx）
  /// 支持: 用途: xxx, 资金密码: xxx, 备注1: xxx
  static ParsedCredential parse(String rawInput, {AccountCategory defaultCategory = AccountCategory.general}) {
    var working = rawInput.trim();
    if (working.isEmpty) {
      return ParsedCredential(category: defaultCategory);
    }

    var title = '';
    var url = '';
    var accountLabel = '账号';
    var username = '';
    var passwordLabel = '密码';
    var password = '';
    final extraPasswords = <LabeledPassword>[];
    var totpSecret = '';
    var totpDigits = 6;
    var totpPeriod = 30;
    var totpAlgorithm = TOTPAlgorithm.sha1;
    final noteEntries = <NoteEntry>[];
    final badges = <String>[];

    // 0. 检查是否包含 otpauth:// 协议链接
    final otpMatch = RegExp(r'otpauth:\/\/[^\s\t\n]+', caseSensitive: false).firstMatch(working);
    if (otpMatch != null) {
      final uriString = otpMatch.group(0)!;
      final parsed = TOTPEngine.parseOTPAuthURI(uriString);
      if (parsed != null) {
        totpSecret = parsed.secret;
        totpDigits = parsed.digits;
        totpPeriod = parsed.period;
        totpAlgorithm = parsed.algorithm;
        if (parsed.issuer.isNotEmpty) title = parsed.issuer;
        if (parsed.account.isNotEmpty) username = parsed.account;
        badges.add('OTPAuth');
      }
      working = working.replaceRange(otpMatch.start, otpMatch.end, ' ');
    }

    // 1. 提取带括号的 2FA 标记: 2fa(xxxx), 2fa（xxxx）, 动态码（xxxx）, [2FA: xxxx], 2fa【xxxx】
    final bracket2FARegex = RegExp(
      r'(?:2fa|totp|双重认证|动态码|验证码|谷歌验证|otp)\s*[:：=]?\s*[（(\[【]([^）)\]】]+)[）)\]】]',
      caseSensitive: false,
    );
    final bracketMatch = bracket2FARegex.firstMatch(working);
    if (bracketMatch != null) {
      totpSecret = bracketMatch.group(1)!
          .replaceAll(' ', '')
          .replaceAll('-', '')
          .trim();
      badges.add('2FA密钥');
      working = working.replaceRange(bracketMatch.start, bracketMatch.end, ' ');
    } else {
      // 2. 提取冒号跟随的 2FA
      final colon2FARegex = RegExp(
        r'(?:2fa|totp|双重认证|动态码|验证码|谷歌验证|otp)\s*(?:[:：=]\s*|\s+)([A-Za-z0-9=\s-]{3,64}?)(?=$|\n|\r|\t|  |\s+(?:网址|账号|密码|备注|http))',
        caseSensitive: false,
      );
      final colonMatch = colon2FARegex.firstMatch(working);
      if (colonMatch != null) {
        totpSecret = colonMatch.group(1)!
            .replaceAll(' ', '')
            .replaceAll('-', '')
            .trim();
        badges.add('2FA密钥');
        working = working.replaceRange(colonMatch.start, colonMatch.end, ' ');
      }
    }

    // 3. 提取额外密码 (如: 资金密码: xxx, 支付密码: xxx, API Key: xxx)
    final extraPwdRegex = RegExp(
      r'(资金密码|支付密码|交易密码|API\s*Key|二级密码|PIN码|安全密码)\s*[:：=]\s*([^\s\t\n]+)',
      caseSensitive: false,
    );
    final extraMatches = extraPwdRegex.allMatches(working).toList();
    for (final m in extraMatches) {
      final lbl = m.group(1)!.trim();
      final val = m.group(2)!.trim();
      extraPasswords.add(LabeledPassword(label: lbl, value: val));
      badges.add(lbl);
      working = working.replaceRange(m.start, m.end, ' ');
    }

    // 4. 提取显式标签字段
    // 网址
    final urlRegex = RegExp(r'(?:网址|网站|链接|域名|url|link|domain|site)\s*[:：=]\s*([^\s\t\n]+)', caseSensitive: false);
    final urlMatch = urlRegex.firstMatch(working);
    if (urlMatch != null) {
      url = urlMatch.group(1)!.trim();
      badges.add('网址');
      working = working.replaceRange(urlMatch.start, urlMatch.end, ' ');
    }

    // 账号（包含 用途、域名、接码平台、邮箱等自定义标签）
    final accRegex = RegExp(
      r'(?:(账号|账户|用户名|登录名|用户|用途|接码平台|邮箱|user(?:name)?|acc(?:ount)?|email|uid))\s*[:：=]\s*([^\s\t\n]+)',
      caseSensitive: false,
    );
    final accMatch = accRegex.firstMatch(working);
    if (accMatch != null) {
      accountLabel = accMatch.group(1)!.trim();
      username = accMatch.group(2)!.trim();
      badges.add(accountLabel);
      working = working.replaceRange(accMatch.start, accMatch.end, ' ');
    }

    // 登录密码
    final pwdRegex = RegExp(r'(?:(密码|口令|登录密码|pass(?:word)?|pwd))\s*[:：=]\s*([^\s\t\n]+)', caseSensitive: false);
    final pwdMatch = pwdRegex.firstMatch(working);
    if (pwdMatch != null) {
      passwordLabel = pwdMatch.group(1)!.trim();
      password = pwdMatch.group(2)!.trim();
      badges.add(passwordLabel);
      working = working.replaceRange(pwdMatch.start, pwdMatch.end, ' ');
    }

    // 标题
    final titleRegex = RegExp(r'(?:标题|服务|平台|名称|title|service)\s*[:：=]\s*([^\s\t\n]+)', caseSensitive: false);
    final titleMatch = titleRegex.firstMatch(working);
    if (titleMatch != null) {
      title = titleMatch.group(1)!.trim();
      badges.add('服务');
      working = working.replaceRange(titleMatch.start, titleMatch.end, ' ');
    }

    // 备注 (如 备注: xxx, 备注1: xxx, 备注+8: xxx)
    final noteRegex = RegExp(r'(?:(备注(?:\+?\d+)?|说明|密保问题|安全提示|notes?|memo))\s*[:：=]\s*([^\n\r]+)', caseSensitive: false);
    final noteMatches = noteRegex.allMatches(working).toList();
    for (final m in noteMatches) {
      final lbl = m.group(1)!.trim();
      final cnt = m.group(2)!.trim();
      noteEntries.add(NoteEntry(label: lbl, content: cnt));
      badges.add(lbl);
      working = working.replaceRange(m.start, m.end, ' ');
    }

    // 5. 将剩余内容切分为词元 (Tokens)
    var tokens = working
        .split(RegExp(r'[\s\t\n|;,]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    // 6. 若尚未提取 URL，寻找域名或网址
    if (url.isEmpty) {
      final urlIndex = tokens.indexWhere((t) => isLikelyUrl(t));
      if (urlIndex != -1) {
        url = tokens.removeAt(urlIndex);
        badges.add('域名');
      }
    }

    // 7. 若尚未提取 2FA，检查是否有标准 Base32 密钥
    if (totpSecret.isEmpty) {
      final b32Index = tokens.indexWhere((t) => isLikelyBase32(t));
      if (b32Index != -1) {
        totpSecret = tokens.removeAt(b32Index).toUpperCase();
        badges.add('Base32');
      }
    }

    // 8. 若尚未提取账号，优先在 tokens 中寻找邮箱或手机号
    if (username.isEmpty) {
      final emailIndex = tokens.indexWhere((t) => isLikelyEmail(t));
      if (emailIndex != -1) {
        username = tokens.removeAt(emailIndex);
        badges.add('邮箱');
      }
    }

    // 9. 智能按序分配剩余词元
    // 典型输入: "xxxx.com   xxx账号   xxx密码    2fa（xxxx）"
    if (tokens.length == 1) {
      final tok = tokens.removeAt(0);
      if (username.isEmpty) {
        username = tok;
      } else if (password.isEmpty) {
        password = tok;
      } else if (title.isEmpty && url.isEmpty) {
        title = tok;
      } else {
        noteEntries.add(NoteEntry(label: '备注', content: tok));
      }
    } else if (tokens.length >= 2) {
      final first = tokens.removeAt(0);
      final second = tokens.removeAt(0);
      if (username.isEmpty && password.isEmpty) {
        username = first;
        password = second;
      } else if (username.isEmpty) {
        username = first;
        if (password.isEmpty) password = second;
      } else if (password.isEmpty) {
        password = first;
        noteEntries.add(NoteEntry(label: '备注', content: second));
      }
      for (final rem in tokens) {
        noteEntries.add(NoteEntry(label: '备注', content: rem));
      }
    }

    final category = inferCategory(title: title, url: url, username: username, fallback: defaultCategory);

    return ParsedCredential(
      title: title,
      url: url,
      accountLabel: accountLabel,
      username: username,
      passwordLabel: passwordLabel,
      password: password,
      extraPasswords: extraPasswords,
      totpSecret: totpSecret,
      totpDigits: totpDigits,
      totpPeriod: totpPeriod,
      totpAlgorithm: totpAlgorithm,
      category: category,
      noteEntries: noteEntries,
      recognizedBadges: badges,
    );
  }

  static bool isLikelyUrl(String token) {
    if (token.contains('@')) return false;
    final lower = token.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) return true;
    final domainRegex = RegExp(r'^[a-zA-Z0-9][-a-zA-Z0-9]*\.[a-zA-Z]{2,}(?::\d+)?(?:\/.*)?$');
    return domainRegex.hasMatch(token);
  }

  static bool isLikelyBase32(String token) {
    final upper = token.toUpperCase();
    if (upper.length < 16 || upper.length > 64) return false;
    final b32Regex = RegExp(r'^[A-Z2-7]+=*$');
    if (!b32Regex.hasMatch(upper)) return false;
    try {
      final decoded = Base32.decode(upper);
      return decoded.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static bool isLikelyEmail(String token) {
    return RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(token);
  }

  static AccountCategory inferCategory({
    required String title,
    required String url,
    required String username,
    AccountCategory fallback = AccountCategory.general,
  }) {
    final hay = '$title $url $username'.toLowerCase();

    if (hay.contains('binance') ||
        hay.contains('okx') ||
        hay.contains('bybit') ||
        hay.contains('gate.io') ||
        hay.contains('bitget') ||
        hay.contains('coinbase') ||
        hay.contains('metamask') ||
        hay.contains('crypto') ||
        hay.contains('web3') ||
        hay.contains('交易所') ||
        hay.contains('钱包')) {
      return AccountCategory.crypto;
    }

    if (hay.contains('openai') ||
        hay.contains('chatgpt') ||
        hay.contains('claude') ||
        hay.contains('anthropic') ||
        hay.contains('deepseek') ||
        hay.contains('midjourney') ||
        hay.contains('大模型') ||
        hay.contains('算力')) {
      return AccountCategory.ai;
    }

    if (hay.contains('github') ||
        hay.contains('gitlab') ||
        hay.contains('gitee') ||
        hay.contains('aws') ||
        hay.contains('aliyun') ||
        hay.contains('阿里云') ||
        hay.contains('cloudflare') ||
        hay.contains('docker') ||
        hay.contains('server') ||
        hay.contains('服务器') ||
        hay.contains('vps')) {
      return AccountCategory.work;
    }

    if (hay.contains('paypal') ||
        hay.contains('stripe') ||
        hay.contains('alipay') ||
        hay.contains('支付宝') ||
        hay.contains('bank') ||
        hay.contains('银行') ||
        hay.contains('券商') ||
        hay.contains('信用卡')) {
      return AccountCategory.finance;
    }

    if (hay.contains('google') ||
        hay.contains('gmail') ||
        hay.contains('apple') ||
        hay.contains('telegram') ||
        hay.contains('twitter') ||
        hay.contains('discord') ||
        hay.contains('微信') ||
        hay.contains('微博') ||
        url.contains('x.com')) {
      return AccountCategory.social;
    }

    return fallback;
  }
}
