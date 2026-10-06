import Foundation

public struct PasswordGeneratorOptions {
    public var length: Int = 18
    public var useUppercase: Bool = true
    public var useLowercase: Bool = true
    public var useDigits: Bool = true
    public var useSymbols: Bool = true
    public var avoidAmbiguous: Bool = true

    public init(
        length: Int = 18,
        useUppercase: Bool = true,
        useLowercase: Bool = true,
        useDigits: Bool = true,
        useSymbols: Bool = true,
        avoidAmbiguous: Bool = true
    ) {
        self.length = length
        self.useUppercase = useUppercase
        self.useLowercase = useLowercase
        self.useDigits = useDigits
        self.useSymbols = useSymbols
        self.avoidAmbiguous = avoidAmbiguous
    }
}

public enum PasswordStrength: Int {
    case empty = 0
    case weak = 1
    case fair = 2
    case strong = 3
    case veryStrong = 4

    public var label: String {
        switch self {
        case .empty: return "未设置"
        case .weak: return "弱 (易被猜测)"
        case .fair: return "中等"
        case .strong: return "强"
        case .veryStrong: return "极强"
        }
    }
}

public final class PasswordGenerator {
    private static let uppercaseAll = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    private static let lowercaseAll = "abcdefghijklmnopqrstuvwxyz"
    private static let digitsAll = "0123456789"
    private static let symbolsAll = "!@#$%^&*()-_=+[]{}?"
    private static let ambiguousChars = Set("0O1lI")

    public static func generate(options: PasswordGeneratorOptions = PasswordGeneratorOptions()) -> String {
        let filter: (String) -> [Character] = { str in
            if options.avoidAmbiguous {
                return str.filter { !ambiguousChars.contains($0) }
            }
            return Array(str)
        }

        var pools = [[Character]]()
        if options.useUppercase { pools.append(filter(uppercaseAll)) }
        if options.useLowercase { pools.append(filter(lowercaseAll)) }
        if options.useDigits { pools.append(filter(digitsAll)) }
        if options.useSymbols { pools.append(filter(symbolsAll)) }

        if pools.isEmpty {
            pools.append(filter(lowercaseAll))
        }

        let combinedPool = pools.flatMap { $0 }
        guard !combinedPool.isEmpty else { return "" }

        let targetLength = max(4, min(64, options.length))
        var rng = SystemRandomNumberGenerator()
        var passwordChars = [Character]()

        // 确保每个勾选的字符集至少包含一个字符
        for pool in pools where !pool.isEmpty && passwordChars.count < targetLength {
            if let char = pool.randomElement(using: &rng) {
                passwordChars.append(char)
            }
        }

        while passwordChars.count < targetLength {
            if let char = combinedPool.randomElement(using: &rng) {
                passwordChars.append(char)
            }
        }

        // 打乱顺序
        passwordChars.shuffle(using: &rng)
        return String(passwordChars)
    }

    public static func evaluateStrength(_ password: String) -> (strength: PasswordStrength, entropyBits: Int) {
        guard !password.isEmpty else { return (.empty, 0) }

        var charsetSize = 0
        if password.rangeOfCharacter(from: .lowercaseLetters) != nil { charsetSize += 26 }
        if password.rangeOfCharacter(from: .uppercaseLetters) != nil { charsetSize += 26 }
        if password.rangeOfCharacter(from: .decimalDigits) != nil { charsetSize += 10 }
        let symbolsSet = CharacterSet.alphanumerics.inverted
        if password.rangeOfCharacter(from: symbolsSet) != nil { charsetSize += 32 }

        guard charsetSize > 0 else { return (.weak, 10) }

        let entropy = Double(password.count) * log2(Double(charsetSize))
        let bits = Int(entropy.rounded())

        let strength: PasswordStrength
        switch bits {
        case ..<40:
            strength = .weak
        case 40..<65:
            strength = .fair
        case 65..<95:
            strength = .strong
        default:
            strength = .veryStrong
        }

        return (strength, bits)
    }
}
