import Foundation
import CryptoKit
import CoreImage
import AppKit

public enum TOTPError: LocalizedError {
    case invalidBase32
    case secretKeyEmpty
    case calculationFailed
    case qrCodeNotFound
    case unsupportedImage

    public var errorDescription: String? {
        switch self {
        case .invalidBase32:
            return "Base32 密钥格式不正确（只能包含 A-Z 和 2-7）"
        case .secretKeyEmpty:
            return "2FA 密钥不能为空"
        case .calculationFailed:
            return "动态验证码计算失败"
        case .qrCodeNotFound:
            return "图片中未检测到有效的 2FA 二维码"
        case .unsupportedImage:
            return "不支持的图片格式"
        }
    }
}

public struct ParsedOTPAuth {
    public var label: String
    public var issuer: String?
    public var account: String?
    public var secret: String
    public var algorithm: TOTPAlgorithm
    public var digits: Int
    public var period: Int

    public init(
        label: String,
        issuer: String? = nil,
        account: String? = nil,
        secret: String,
        algorithm: TOTPAlgorithm = .sha1,
        digits: Int = 6,
        period: Int = 30
    ) {
        self.label = label
        self.issuer = issuer
        self.account = account
        self.secret = secret
        self.algorithm = algorithm
        self.digits = digits
        self.period = period
    }
}

public final class TOTPEngine {

    // MARK: - RFC 4648 Base32 解码
    public static func decodeBase32(_ string: String) throws -> Data {
        let cleaned = string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .uppercased()

        guard !cleaned.isEmpty else {
            throw TOTPError.secretKeyEmpty
        }

        let base32Chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var charMap = [Character: UInt8]()
        for (i, char) in base32Chars.enumerated() {
            charMap[char] = UInt8(i)
        }

        var buffer: UInt64 = 0
        var bitsLeft: Int = 0
        var result = [UInt8]()

        for char in cleaned {
            if char == "=" {
                break // 遇到 padding 结束
            }
            guard let val = charMap[char] else {
                throw TOTPError.invalidBase32
            }
            buffer = (buffer << 5) | UInt64(val)
            bitsLeft += 5

            if bitsLeft >= 8 {
                let byte = UInt8((buffer >> (bitsLeft - 8)) & 0xFF)
                result.append(byte)
                bitsLeft -= 8
            }
        }

        return Data(result)
    }

    // MARK: - RFC 6238 TOTP 动态码计算
    public static func generateCode(
        secret: String,
        date: Date = Date(),
        period: Int = 30,
        digits: Int = 6,
        algorithm: TOTPAlgorithm = .sha1
    ) throws -> String {
        let secretData = try decodeBase32(secret)
        guard !secretData.isEmpty else {
            throw TOTPError.secretKeyEmpty
        }

        let timeInterval = date.timeIntervalSince1970
        let counter = UInt64(floor(timeInterval / Double(period)))
        var counterBigEndian = counter.bigEndian
        let counterData = Data(bytes: &counterBigEndian, count: MemoryLayout<UInt64>.size)

        let symmetricKey = SymmetricKey(data: secretData)
        let hashData: Data

        switch algorithm {
        case .sha1:
            let hmac = HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: symmetricKey)
            hashData = Data(hmac)
        case .sha256:
            let hmac = HMAC<SHA256>.authenticationCode(for: counterData, using: symmetricKey)
            hashData = Data(hmac)
        case .sha512:
            let hmac = HMAC<SHA512>.authenticationCode(for: counterData, using: symmetricKey)
            hashData = Data(hmac)
        }

        guard let lastByte = hashData.last else {
            throw TOTPError.calculationFailed
        }

        let offset = Int(lastByte & 0x0F)
        guard offset + 4 <= hashData.count else {
            throw TOTPError.calculationFailed
        }

        let b0 = UInt32(hashData[offset] & 0x7F) << 24
        let b1 = UInt32(hashData[offset + 1] & 0xFF) << 16
        let b2 = UInt32(hashData[offset + 2] & 0xFF) << 8
        let b3 = UInt32(hashData[offset + 3] & 0xFF)
        let binaryCode = b0 | b1 | b2 | b3

        let modulus = UInt32(pow(10.0, Double(digits)))
        let token = binaryCode % modulus

        let format = "%0\(digits)u"
        return String(format: format, token)
    }

    // MARK: - 计算倒计时与周期进度
    public static func timeStatus(date: Date = Date(), period: Int = 30) -> (remainingSeconds: Int, progress: Double) {
        let currentSeconds = Int(date.timeIntervalSince1970)
        let elapsed = currentSeconds % period
        let remaining = period - elapsed
        let progress = Double(remaining) / Double(period)
        return (remaining, progress)
    }

    // MARK: - otpauth://totp/... 链接解析
    public static func parseOTPAuthURI(_ urlString: String) -> ParsedOTPAuth? {
        guard let url = URL(string: urlString),
              url.scheme?.lowercased() == "otpauth",
              url.host?.lowercased() == "totp" else {
            return nil
        }

        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let rawLabel = path.removingPercentEncoding ?? path

        var issuerFromLabel: String?
        var accountFromLabel: String?

        if rawLabel.contains(":") {
            let parts = rawLabel.split(separator: ":", maxSplits: 1).map(String.init)
            issuerFromLabel = parts[0].trimmingCharacters(in: .whitespaces)
            accountFromLabel = parts[1].trimmingCharacters(in: .whitespaces)
        } else {
            accountFromLabel = rawLabel
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return nil
        }

        var secret = ""
        var issuer = issuerFromLabel
        var digits = 6
        var period = 30
        var algorithm: TOTPAlgorithm = .sha1

        for item in queryItems {
            guard let value = item.value else { continue }
            switch item.name.lowercased() {
            case "secret":
                secret = value
            case "issuer":
                issuer = value
            case "digits":
                if let d = Int(value), d >= 6 && d <= 8 {
                    digits = d
                }
            case "period":
                if let p = Int(value), p > 0 {
                    period = p
                }
            case "algorithm":
                switch value.uppercased() {
                case "SHA256": algorithm = .sha256
                case "SHA512": algorithm = .sha512
                default: algorithm = .sha1
                }
            default:
                break
            }
        }

        guard !secret.isEmpty else { return nil }

        return ParsedOTPAuth(
            label: rawLabel,
            issuer: issuer,
            account: accountFromLabel,
            secret: secret,
            algorithm: algorithm,
            digits: digits,
            period: period
        )
    }

    // MARK: - 离线图片二维码识别 (CoreImage)
    public static func scanQRCode(from image: NSImage) throws -> String {
        guard let tiffData = image.tiffRepresentation,
              let ciImage = CIImage(data: tiffData) else {
            throw TOTPError.unsupportedImage
        }

        let detectorOptions = [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        guard let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: detectorOptions) else {
            throw TOTPError.qrCodeNotFound
        }

        let features = detector.features(in: ciImage)
        for feature in features {
            if let qrFeature = feature as? CIQRCodeFeature, let message = qrFeature.messageString, !message.isEmpty {
                return message
            }
        }

        throw TOTPError.qrCodeNotFound
    }

    public static func scanQRCode(from fileURL: URL) throws -> String {
        guard let image = NSImage(contentsOf: fileURL) else {
            throw TOTPError.unsupportedImage
        }
        return try scanQRCode(from: image)
    }
}
