import SwiftUI
import AppKit
import LocalAuthentication

@MainActor
public final class LockViewModel: ObservableObject {
    // 登录与首次创建状态
    @Published public var password: String = ""
    @Published public var confirmPassword: String = ""
    @Published public var showPassword: Bool = false
    @Published public var enableTouchIDOnCreate: Bool = true
    @Published public var isProcessing: Bool = false
    @Published public var localError: String? = nil
    @Published public var successMessage: String? = nil

    // 角落入口：安全弹窗状态 (0: 更换密码 - 需现有密码; 1: 重置密码 - 忘记密码向导)
    @Published public var showSecurityModal: Bool = false
    @Published public var securityModalTab: Int = 0

    // 模态弹窗字段
    @Published public var currentPasswordInput: String = ""
    @Published public var newPasswordInput: String = ""
    @Published public var confirmNewPasswordInput: String = ""
    @Published public var showModalSecrets: Bool = false
    @Published public var modalError: String? = nil
    @Published public var modalSuccess: String? = nil

    // 内联重置确认模式 (彻底杜绝 macOS Alert 模态被拦截失效的问题)
    @Published public var showInlineWipeConfirm: Bool = false

    public init() {}

    public func openChangePasswordTab() {
        securityModalTab = 0
        resetModalFields()
        showSecurityModal = true
    }

    public func openResetPasswordTab() {
        securityModalTab = 1
        resetModalFields()
        showSecurityModal = true
    }

    public func resetModalFields() {
        currentPasswordInput = ""
        newPasswordInput = ""
        confirmNewPasswordInput = ""
        modalError = nil
        modalSuccess = nil
        showInlineWipeConfirm = false
    }

    public func closeModal() {
        showSecurityModal = false
        resetModalFields()
    }
}

public struct LockView: View {
    @EnvironmentObject private var store: VaultStore
    @StateObject private var vm = LockViewModel()

    private var hasTouchID: Bool {
        KeychainTouchIDHelper.isTouchIDAvailable()
    }

    private static let cachedBackdropImage: NSImage? = {
        if let bundleURL = Bundle.main.url(forResource: "SourceBrandIcon", withExtension: "png"),
           let img = NSImage(contentsOf: bundleURL) {
            return img
        }
        let candidates: [String?] = [
            Bundle.main.resourceURL?.appendingPathComponent("SourceBrandIcon.png").path,
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/SourceBrandIcon.png").path,
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // Views/
                .deletingLastPathComponent() // LocalVault/
                .deletingLastPathComponent() // Sources/
                .deletingLastPathComponent() // legacy_macos_swift/
                .appendingPathComponent("Resources/SourceBrandIcon.png").path,
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent() // root
                .appendingPathComponent("Resources/SourceBrandIcon.png").path,
            "/Users/mac/Desktop/AI/misc/SecretCore/legacy_macos_swift/Resources/SourceBrandIcon.png",
            "/Users/mac/Desktop/AI/misc/SecretCore/Resources/SourceBrandIcon.png",
            "/Applications/SecretCore.app/Contents/Resources/SourceBrandIcon.png"
        ]
        for p in candidates.compactMap({ $0 }) {
            if FileManager.default.fileExists(atPath: p),
               let img = NSImage(contentsOfFile: p) {
                return img
            }
        }
        return nil
    }()

    public init() {}

    public var body: some View {
        ZStack {
            // 1. 浅色高能全息赛博实验室背景矩阵 (融合 3D 科技底图 + 透视网格 + 量子星盘 + 机甲 HUD)
            lightCyberBackground

            // 2. 四角全息 HUD 遥测铭牌与侧翼刻度尺
            cyberCornerHUD

            // 3. 主体内容层
            VStack(spacing: 0) {
                Spacer(minLength: 10)

                // 主全息白水晶战术控制舱卡片 (内含大幅放大的 154pt 3D 全息主图标)
                mainGlassCard

                Spacer(minLength: 10)

                // 底部状态栏与低调角落改密入口
                bottomCornerBar
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
        }
        .environment(\.colorScheme, .light)
        .sheet(isPresented: $vm.showSecurityModal) {
            securityModalSheet
                .environment(\.colorScheme, .light)
        }
    }

    // MARK: - 浅色高能全息科技背景 (彻底告别单调，多维赛博蓝图 HUD 空间)
    private var lightCyberBackground: some View {
        ZStack {
            // 层 1：浅色冰川蓝银科技底座渐变
            LinearGradient(
                colors: [
                    Color(red: 0.87, green: 0.93, blue: 0.99),
                    Color(red: 0.93, green: 0.965, blue: 1.0),
                    Color(red: 0.88, green: 0.935, blue: 0.99)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // 层 2：原图 3D 未来城市场景与琥珀/电光青全息光影投射层
            GeometryReader { geo in
                if let bgImg = Self.cachedBackdropImage {
                    Image(nsImage: bgImg)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: 16)
                        .opacity(0.38)
                        .clipped()
                }
            }
            .ignoresSafeArea()

            // 层 3：浅色科技柔光滤镜层 (保证高对比度浅色质感，同时透出底层青金双色光晕)
            LinearGradient(
                colors: [
                    Color(red: 0.90, green: 0.95, blue: 1.0).opacity(0.58),
                    Color(red: 0.95, green: 0.98, blue: 1.0).opacity(0.45),
                    Color(red: 0.91, green: 0.95, blue: 0.99).opacity(0.60)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // 层 4：高饱和极光等离子能量场 (左上电光青 + 右下琥珀金 + 右上深海蓝)
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.0, green: 0.72, blue: 1.0).opacity(0.30),
                                Color(red: 0.0, green: 0.52, blue: 0.98).opacity(0.10),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 340
                        )
                    )
                    .frame(width: 680, height: 680)
                    .offset(x: -290, y: -190)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 1.0, green: 0.64, blue: 0.14).opacity(0.25),
                                Color(red: 1.0, green: 0.78, blue: 0.32).opacity(0.08),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 320
                        )
                    )
                    .frame(width: 640, height: 640)
                    .offset(x: 300, y: 200)
            }
            .ignoresSafeArea()

            // 层 5：3D 赛博透视地平线网格 + 蓝图矩阵 + 量子星盘雷达 + 折线电路
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let cx = w * 0.5
                let cy = h * 0.46

                ZStack {
                    // 5A. 全局精密工程蓝图正交网格
                    Path { path in
                        let step: CGFloat = 56
                        var x: CGFloat = 0
                        while x <= w {
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: h))
                            x += step
                        }
                        var y: CGFloat = 0
                        while y <= h {
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: w, y: y))
                            y += step
                        }
                    }
                    .stroke(Color(red: 0.02, green: 0.45, blue: 0.88).opacity(0.13), lineWidth: 0.85)

                    // 5B. 底部 3D 赛博空间透视地平面网格 (Perspective Horizon Floor)
                    Path { path in
                        let horizonY = h * 0.57
                        let rayCount = 20
                        for i in 0...rayCount {
                            let frac = CGFloat(i) / CGFloat(rayCount)
                            let topX = w * (0.15 + frac * 0.70)
                            let bottomX = w * (-0.35 + frac * 1.70)
                            path.move(to: CGPoint(x: topX, y: horizonY))
                            path.addLine(to: CGPoint(x: bottomX, y: h))
                        }

                        let depthSteps = 8
                        for j in 0...depthSteps {
                            let t = CGFloat(j) / CGFloat(depthSteps)
                            let y = horizonY + pow(t, 1.55) * (h - horizonY)
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: w, y: y))
                        }
                    }
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 0.0, green: 0.58, blue: 0.98).opacity(0.08),
                                Color(red: 0.0, green: 0.50, blue: 0.95).opacity(0.32),
                                Color(red: 0.95, green: 0.58, blue: 0.12).opacity(0.28)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.1
                    )

                    // 5C. 顶部 3D 赛博穹顶透视网格 (Perspective Ceiling)
                    Path { path in
                        let ceilingY = h * 0.27
                        let rayCount = 14
                        for i in 0...rayCount {
                            let frac = CGFloat(i) / CGFloat(rayCount)
                            let bottomX = w * (0.20 + frac * 0.60)
                            let topX = w * (-0.20 + frac * 1.40)
                            path.move(to: CGPoint(x: bottomX, y: ceilingY))
                            path.addLine(to: CGPoint(x: topX, y: 0))
                        }

                        let steps = 5
                        for j in 0...steps {
                            let t = CGFloat(j) / CGFloat(steps)
                            let y = ceilingY - pow(t, 1.5) * ceilingY
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: w, y: y))
                        }
                    }
                    .stroke(Color(red: 0.0, green: 0.55, blue: 0.95).opacity(0.13), lineWidth: 0.9)

                    // 5D. 中心巨型全息量子星盘与 72 刻度雷达环
                    // 外层主雷达环 (760pt)
                    Circle()
                        .stroke(Color(red: 0.0, green: 0.52, blue: 0.92).opacity(0.24), lineWidth: 1.3)
                        .frame(width: 760, height: 760)
                        .position(x: cx, y: cy)

                    // 72 刻度线环形标尺 (每 5 度一刻度，每 30 度加长主刻度)
                    Path { path in
                        let radius: CGFloat = 380
                        for deg in stride(from: 0, to: 360, by: 5) {
                            let rad = CGFloat(deg) * .pi / 180.0
                            let isMajor = (deg % 30 == 0)
                            let innerR = radius - (isMajor ? 14 : 6)
                            let p1 = CGPoint(x: cx + cos(rad) * innerR, y: cy + sin(rad) * innerR)
                            let p2 = CGPoint(x: cx + cos(rad) * radius, y: cy + sin(rad) * radius)
                            path.move(to: p1)
                            path.addLine(to: p2)
                        }
                    }
                    .stroke(Color(red: 0.0, green: 0.48, blue: 0.90).opacity(0.32), lineWidth: 1.1)

                    // 中层琥珀金加速星轨环 (640pt，呼应图标金色光环)
                    Circle()
                        .stroke(
                            Color(red: 0.96, green: 0.56, blue: 0.08).opacity(0.36),
                            style: StrokeStyle(lineWidth: 1.8, dash: [24, 10, 4, 10])
                        )
                        .frame(width: 640, height: 640)
                        .position(x: cx, y: cy)

                    // 内层电光青战术锁定环 (520pt)
                    Circle()
                        .stroke(
                            Color(red: 0.0, green: 0.62, blue: 0.98).opacity(0.38),
                            style: StrokeStyle(lineWidth: 1.6, dash: [42, 14, 8, 14])
                        )
                        .frame(width: 520, height: 520)
                        .position(x: cx, y: cy)

                    // 斜向激光扫描基准轴线 (±26°)
                    Path { path in
                        let angle1: CGFloat = 26.0 * .pi / 180.0
                        let r: CGFloat = 430
                        path.move(to: CGPoint(x: cx - cos(angle1) * r, y: cy - sin(angle1) * r))
                        path.addLine(to: CGPoint(x: cx + cos(angle1) * r, y: cy + sin(angle1) * r))

                        path.move(to: CGPoint(x: cx - cos(angle1) * r, y: cy + sin(angle1) * r))
                        path.addLine(to: CGPoint(x: cx + cos(angle1) * r, y: cy - sin(angle1) * r))
                    }
                    .stroke(
                        Color(red: 0.0, green: 0.55, blue: 0.95).opacity(0.18),
                        style: StrokeStyle(lineWidth: 1.0, dash: [8, 8])
                    )

                    // 5E. 左右两翼 45° 赛博芯片折线电路 (Cyber Circuit Traces)
                    Path { path in
                        // 左侧电路支路 1
                        path.move(to: CGPoint(x: 0, y: cy - 90))
                        path.addLine(to: CGPoint(x: w * 0.14, y: cy - 90))
                        path.addLine(to: CGPoint(x: w * 0.19, y: cy - 40))
                        path.addLine(to: CGPoint(x: w * 0.25, y: cy - 40))

                        // 左侧电路支路 2
                        path.move(to: CGPoint(x: 0, y: cy + 75))
                        path.addLine(to: CGPoint(x: w * 0.12, y: cy + 75))
                        path.addLine(to: CGPoint(x: w * 0.17, y: cy + 25))
                        path.addLine(to: CGPoint(x: w * 0.24, y: cy + 25))

                        // 右侧电路支路 1
                        path.move(to: CGPoint(x: w, y: cy - 85))
                        path.addLine(to: CGPoint(x: w * 0.86, y: cy - 85))
                        path.addLine(to: CGPoint(x: w * 0.81, y: cy - 35))
                        path.addLine(to: CGPoint(x: w * 0.75, y: cy - 35))

                        // 右侧电路支路 2
                        path.move(to: CGPoint(x: w, y: cy + 80))
                        path.addLine(to: CGPoint(x: w * 0.88, y: cy + 80))
                        path.addLine(to: CGPoint(x: w * 0.83, y: cy + 30))
                        path.addLine(to: CGPoint(x: w * 0.76, y: cy + 30))
                    }
                    .stroke(Color(red: 0.0, green: 0.56, blue: 0.96).opacity(0.30), lineWidth: 1.4)

                    // 电路端点发光焊盘节点 + 精密十字准星 (+)
                    Path { path in
                        let crossPoints = [
                            CGPoint(x: w * 0.16, y: h * 0.22),
                            CGPoint(x: w * 0.84, y: h * 0.22),
                            CGPoint(x: w * 0.16, y: h * 0.74),
                            CGPoint(x: w * 0.84, y: h * 0.74),
                            CGPoint(x: w * 0.26, y: cy - 150),
                            CGPoint(x: w * 0.74, y: cy - 150),
                            CGPoint(x: w * 0.26, y: cy + 150),
                            CGPoint(x: w * 0.74, y: cy + 150)
                        ]
                        for pt in crossPoints {
                            path.move(to: CGPoint(x: pt.x - 6, y: pt.y))
                            path.addLine(to: CGPoint(x: pt.x + 6, y: pt.y))
                            path.move(to: CGPoint(x: pt.x, y: pt.y - 6))
                            path.addLine(to: CGPoint(x: pt.x, y: pt.y + 6))
                        }
                    }
                    .stroke(Color(red: 0.0, green: 0.48, blue: 0.90).opacity(0.42), lineWidth: 1.2)

                    // 星轨发光卫星节点
                    Circle()
                        .fill(Color(red: 0.0, green: 0.68, blue: 1.0))
                        .frame(width: 8, height: 8)
                        .shadow(color: Color(red: 0.0, green: 0.68, blue: 1.0), radius: 6)
                        .position(x: cx - 260, y: cy - 12)

                    Circle()
                        .fill(Color(red: 0.98, green: 0.58, blue: 0.10))
                        .frame(width: 8, height: 8)
                        .shadow(color: Color(red: 0.98, green: 0.58, blue: 0.10), radius: 6)
                        .position(x: cx + 318, y: cy + 36)
                }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - 四角全息机甲取景框与实时遥测 HUD (呼应原图顶角折线与 /// 能量条)
    private var cyberCornerHUD: some View {
        VStack {
            // 顶部左右遥测 HUD
            HStack(alignment: .top) {
                // 左上角 HUD 模块
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        // 琥珀金 + 电光青战术指示块
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(red: 0.98, green: 0.56, blue: 0.10))
                            .frame(width: 4, height: 14)

                        Text("SYS.CORE // SECRETCORE QUANTUM-OS v1.2")
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 0.08, green: 0.28, blue: 0.56))

                        // 呼应图标右上角的 /// 三道斜向科技条
                        HStack(spacing: 3) {
                            ForEach(0..<3, id: \.self) { _ in
                                Capsule()
                                    .fill(Color(red: 0.98, green: 0.58, blue: 0.12).opacity(0.85))
                                    .frame(width: 6, height: 3)
                            }
                        }
                    }

                    Text("ENCLAVE  // LOCAL AIR-GAP · HARDWARE ISOLATED [ONLINE]")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(red: 0.22, green: 0.42, blue: 0.66).opacity(0.85))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.58))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(red: 0.0, green: 0.58, blue: 0.96).opacity(0.28), lineWidth: 1)
                )
                .cornerRadius(8)

                Spacer()

                // 右上角 HUD 模块
                VStack(alignment: .trailing, spacing: 5) {
                    HStack(spacing: 6) {
                        HStack(spacing: 3) {
                            ForEach(0..<3, id: \.self) { _ in
                                Capsule()
                                    .fill(Color(red: 0.0, green: 0.65, blue: 0.98).opacity(0.85))
                                    .frame(width: 6, height: 3)
                            }
                        }

                        Text("CIPHER // AES-256-GCM · PBKDF2-100K")
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 0.08, green: 0.28, blue: 0.56))

                        Circle()
                            .fill(Color(red: 0.05, green: 0.78, blue: 0.48))
                            .frame(width: 7, height: 7)
                            .shadow(color: Color(red: 0.05, green: 0.78, blue: 0.48), radius: 4)
                    }

                    Text("NET.LINK // 0.0.0.0 · ZERO-OUTBOUND ENFORCED")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(red: 0.22, green: 0.42, blue: 0.66).opacity(0.85))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.58))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(red: 0.0, green: 0.58, blue: 0.96).opacity(0.28), lineWidth: 1)
                )
                .cornerRadius(8)
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)

            Spacer()

            // 中部两侧竖向高度标尺 (Cockpit Elevation Scale)
            HStack {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(["100", "080", "060", "040", "020"], id: \.self) { mark in
                        HStack(spacing: 4) {
                            Rectangle()
                                .fill(Color(red: 0.0, green: 0.55, blue: 0.95).opacity(0.45))
                                .frame(width: 10, height: 1.5)
                            Text(mark)
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(red: 0.15, green: 0.42, blue: 0.72).opacity(0.65))
                        }
                    }
                }
                .padding(.leading, 18)

                Spacer()

                VStack(alignment: .trailing, spacing: 10) {
                    ForEach(["SEC-A", "TOTP", "SHA256", "GCM", "LOCAL"], id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag)
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(red: 0.15, green: 0.42, blue: 0.72).opacity(0.65))
                            Rectangle()
                                .fill(Color(red: 0.96, green: 0.58, blue: 0.12).opacity(0.45))
                                .frame(width: 10, height: 1.5)
                        }
                    }
                }
                .padding(.trailing, 18)
            }

            Spacer()
        }
        .allowsHitTesting(false)
    }

    // MARK: - 主全息白水晶战术控制舱卡片 (含大幅放大的 154pt 3D 全息主图标)
    private var mainGlassCard: some View {
        VStack(spacing: 16) {
            // 0. 卡片顶部全息遥测铭牌条
            HStack {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color(red: 0.0, green: 0.68, blue: 1.0))
                        .frame(width: 6, height: 6)
                    Text("QUANTUM SECURITY TERMINAL")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 0.12, green: 0.38, blue: 0.68))
                }

                Spacer()

                HStack(spacing: 3) {
                    Text("AIR-GAP // 01")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 0.85, green: 0.48, blue: 0.08))
                }
            }
            .padding(.horizontal, 4)

            // 1. 大幅放大的 3D 全息护盾主图标 (从 96 大幅放大至 154，外圈带全息星轨达 200pt!)
            ZStack(alignment: .bottom) {
                // 底部全息能量投影底座光盘
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.0, green: 0.68, blue: 1.0).opacity(0.32),
                                Color(red: 1.0, green: 0.65, blue: 0.18).opacity(0.16),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 8,
                            endRadius: 95
                        )
                    )
                    .frame(width: 228, height: 30)
                    .offset(y: 6)

                VaultBrandEmblemView(size: 176, showAura: true)
            }
            .padding(.top, -4)
            .padding(.bottom, -2)

            // 2. 软件名称与科技副标
            VStack(spacing: 7) {
                HStack(spacing: 8) {
                    Text("SecretCore")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.04, green: 0.14, blue: 0.32),
                                    Color(red: 0.02, green: 0.36, blue: 0.76)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    Text("极光秘核")
                        .font(.system(size: 11.5, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.0, green: 0.72, blue: 1.0).opacity(0.18),
                                    Color(red: 1.0, green: 0.65, blue: 0.16).opacity(0.14)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(Color(red: 0.02, green: 0.42, blue: 0.86))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color(red: 0.0, green: 0.60, blue: 1.0).opacity(0.35), lineWidth: 1)
                        )
                        .cornerRadius(6)
                }

                Text(store.isVaultCreated
                     ? "端到端纯本地硬件级加密 · 请输入主密钥解锁秘核"
                     : "首次运行初始化：请设置您的本地唯一主加密密钥")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(Color(red: 0.28, green: 0.38, blue: 0.52))

                // 科技参数微型徽章
                HStack(spacing: 8) {
                    specPill(icon: "network.slash", text: "零网络物理隔离")
                    specPill(icon: "bolt.shield.fill", text: "PBKDF2 10万次")
                    specPill(icon: "lock.shield.fill", text: "AES-256-GCM")
                }
                .padding(.top, 2)
            }

            // 成功提示横幅 (重置完成或修改成功)
            if let succ = vm.successMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(Color(red: 0.05, green: 0.72, blue: 0.45))
                    Text(succ)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(red: 0.05, green: 0.60, blue: 0.35))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color(red: 0.92, green: 0.98, blue: 0.94))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(red: 0.05, green: 0.72, blue: 0.45).opacity(0.30), lineWidth: 1)
                )
            }

            // 错误/警告信息横幅
            if let err = vm.localError ?? store.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundColor(Color(red: 0.92, green: 0.24, blue: 0.24))
                    Text(err)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(red: 0.78, green: 0.18, blue: 0.18))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color(red: 1.0, green: 0.92, blue: 0.92))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(red: 0.92, green: 0.24, blue: 0.24).opacity(0.28), lineWidth: 1)
                )
            }

            // 表单区域
            if !store.isVaultCreated {
                creationForm
            } else {
                unlockForm
            }
        }
        .frame(width: 440)
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.86))

                // 顶部电光青+琥珀金激光能量灯带
                VStack {
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color(red: 0.0, green: 0.68, blue: 1.0).opacity(0.85),
                            Color(red: 1.0, green: 0.64, blue: 0.16).opacity(0.75),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(height: 3)
                    Spacer()
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        )
        .overlay(
            ZStack {
                // 全息流光双层高光边框
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color(red: 0.0, green: 0.68, blue: 1.0).opacity(0.50),
                                Color.white.opacity(0.95),
                                Color(red: 1.0, green: 0.65, blue: 0.18).opacity(0.42),
                                Color(red: 0.0, green: 0.58, blue: 0.96).opacity(0.45)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.6
                    )

                // 四角赛博金属护角 (Tactical HUD Corner Brackets)
                cardCornerBrackets
            }
        )
        .shadow(color: Color(red: 0.02, green: 0.22, blue: 0.52).opacity(0.15), radius: 36, x: 0, y: 16)
        .shadow(color: Color(red: 0.0, green: 0.50, blue: 0.95).opacity(0.08), radius: 10, x: 0, y: 3)
    }

    // MARK: - 卡片四角机甲护角线
    private var cardCornerBrackets: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let len: CGFloat = 22
            let inset: CGFloat = 6

            Path { path in
                // 左上护角
                path.move(to: CGPoint(x: inset, y: inset + len))
                path.addLine(to: CGPoint(x: inset, y: inset + 8))
                path.addQuadCurve(to: CGPoint(x: inset + 8, y: inset), control: CGPoint(x: inset, y: inset))
                path.addLine(to: CGPoint(x: inset + len, y: inset))

                // 右上护角
                path.move(to: CGPoint(x: w - inset - len, y: inset))
                path.addLine(to: CGPoint(x: w - inset - 8, y: inset))
                path.addQuadCurve(to: CGPoint(x: w - inset, y: inset + 8), control: CGPoint(x: w - inset, y: inset))
                path.addLine(to: CGPoint(x: w - inset, y: inset + len))

                // 左下护角
                path.move(to: CGPoint(x: inset, y: h - inset - len))
                path.addLine(to: CGPoint(x: inset, y: h - inset - 8))
                path.addQuadCurve(to: CGPoint(x: inset + 8, y: h - inset), control: CGPoint(x: inset, y: h - inset))
                path.addLine(to: CGPoint(x: inset + len, y: h - inset))

                // 右下护角
                path.move(to: CGPoint(x: w - inset - len, y: h - inset))
                path.addLine(to: CGPoint(x: w - inset - 8, y: h - inset))
                path.addQuadCurve(to: CGPoint(x: w - inset, y: h - inset - 8), control: CGPoint(x: w - inset, y: h - inset))
                path.addLine(to: CGPoint(x: w - inset, y: h - inset - len))
            }
            .stroke(
                LinearGradient(
                    colors: [
                        Color(red: 0.0, green: 0.62, blue: 1.0).opacity(0.75),
                        Color(red: 0.98, green: 0.58, blue: 0.12).opacity(0.75)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
            )
        }
        .allowsHitTesting(false)
    }

    // MARK: - 规格胶囊
    private func specPill(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(Color(red: 0.0, green: 0.52, blue: 0.95))
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color(red: 0.16, green: 0.32, blue: 0.52))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(Color(red: 0.90, green: 0.95, blue: 1.0))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(red: 0.0, green: 0.55, blue: 0.95).opacity(0.22), lineWidth: 0.8)
        )
        .cornerRadius(6)
    }

    // MARK: - 解锁表单
    private var unlockForm: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("主加密密钥 // MASTER KEY")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 0.16, green: 0.30, blue: 0.48))
                    Spacer()
                    Text("AES-256")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 0.0, green: 0.56, blue: 0.94))
                }

                lightCyberPasswordField(
                    placeholder: "输入您的本地主密码解锁...",
                    text: $vm.password,
                    showSecret: $vm.showPassword
                ) {
                    handleUnlock()
                }
            }

            // 立即解锁按钮 (高能电光青蓝激光渐变)
            Button(action: handleUnlock) {
                HStack(spacing: 8) {
                    if vm.isProcessing {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "key.horizontal.fill")
                            .font(.system(size: 12.5, weight: .bold))
                        Text("立即解锁秘核 // UNLOCK")
                            .font(.system(size: 13.5, weight: .bold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.02, green: 0.48, blue: 0.96),
                            Color(red: 0.00, green: 0.70, blue: 0.96)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Color.white.opacity(0.45), lineWidth: 1)
                )
                .cornerRadius(11)
                .shadow(color: Color(red: 0.0, green: 0.56, blue: 0.98).opacity(0.32), radius: 12, x: 0, y: 5)
            }
            .buttonStyle(.plain)
            .disabled(vm.password.isEmpty || vm.isProcessing)
            .opacity(vm.password.isEmpty ? 0.55 : 1.0)

            // Touch ID 快捷生物识别按钮
            if store.touchIDEnabled && hasTouchID {
                Button {
                    Task {
                        await store.unlockWithTouchID()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "touchid")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color(red: 0.92, green: 0.18, blue: 0.42))
                        Text("使用 Touch ID 生物识别快速解锁")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(Color(red: 0.16, green: 0.28, blue: 0.44))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.93, green: 0.96, blue: 1.0))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(red: 0.0, green: 0.55, blue: 0.95).opacity(0.24), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 首次创建密码库表单
    private var creationForm: some View {
        VStack(spacing: 13) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("设置主加密密钥 (至少 6 位)")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundColor(Color(red: 0.16, green: 0.30, blue: 0.48))
                    Spacer()
                    if !vm.password.isEmpty {
                        let info = strengthInfo(for: vm.password)
                        Text("强度: \(info.0)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(info.1)
                    }
                }

                lightCyberPasswordField(
                    placeholder: "请输入强主密码...",
                    text: $vm.password,
                    showSecret: $vm.showPassword
                ) {}
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("确认主加密密钥")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundColor(Color(red: 0.16, green: 0.30, blue: 0.48))

                lightCyberPasswordField(
                    placeholder: "请再次输入相同的主密码...",
                    text: $vm.confirmPassword,
                    showSecret: $vm.showPassword
                ) {
                    handleCreateVault()
                }
            }

            if hasTouchID {
                Toggle(isOn: $vm.enableTouchIDOnCreate) {
                    HStack(spacing: 6) {
                        Image(systemName: "touchid")
                            .foregroundColor(.pink)
                        Text("启用 Touch ID 生物识别辅助解锁与安全恢复")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(red: 0.22, green: 0.32, blue: 0.45))
                    }
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: handleCreateVault) {
                HStack(spacing: 8) {
                    Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                    Text("创建并加密初始化 SecretCore")
                        .font(.system(size: 13.5, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.02, green: 0.48, blue: 0.96),
                            Color(red: 0.00, green: 0.70, blue: 0.96)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(11)
                .shadow(color: Color(red: 0.0, green: 0.56, blue: 0.98).opacity(0.30), radius: 12, x: 0, y: 5)
            }
            .buttonStyle(.plain)
            .disabled(vm.password.count < 6 || vm.password != vm.confirmPassword || vm.isProcessing)
            .opacity((vm.password.count < 6 || vm.password != vm.confirmPassword) ? 0.55 : 1.0)
        }
    }

    // MARK: - 浅色赛博科技终端风格密码框
    private func lightCyberPasswordField(
        placeholder: String,
        text: Binding<String>,
        showSecret: Binding<Bool>,
        onSubmit: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text("KEY //")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(Color(red: 0.0, green: 0.52, blue: 0.94))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(red: 0.0, green: 0.60, blue: 1.0).opacity(0.12))
                .cornerRadius(5)

            Group {
                if showSecret.wrappedValue {
                    TextField(placeholder, text: text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(Color(red: 0.08, green: 0.14, blue: 0.24))
                        .onSubmit(onSubmit)
                } else {
                    SecureField(placeholder, text: text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(Color(red: 0.08, green: 0.14, blue: 0.24))
                        .onSubmit(onSubmit)
                }
            }

            Button {
                showSecret.wrappedValue.toggle()
            } label: {
                Image(systemName: showSecret.wrappedValue ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 12.5))
                    .foregroundColor(Color(red: 0.35, green: 0.48, blue: 0.64))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(Color(red: 0.95, green: 0.975, blue: 1.0))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.0, green: 0.62, blue: 0.98).opacity(0.42),
                            Color(red: 0.98, green: 0.62, blue: 0.15).opacity(0.28)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 1.2
                )
        )
    }

    // MARK: - 底部状态栏与不起眼的右下角“更换密码 / 重置密码”双入口
    private var bottomCornerBar: some View {
        HStack(alignment: .center) {
            // 左下角：极简本地加密存储状态标识
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(red: 0.05, green: 0.76, blue: 0.46))
                    .frame(width: 6, height: 6)
                Text("LOCAL VAULT // AES-256-GCM 离线密文仓已就绪")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(red: 0.24, green: 0.38, blue: 0.56).opacity(0.85))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.48))
            .cornerRadius(6)

            Spacer()

            // 右下角不起眼的角落：提供“更换密码 (需原密码)”与“重置密码 (忘记密码)”独立入口
            if store.isVaultCreated {
                HStack(spacing: 8) {
                    Button {
                        vm.openChangePasswordTab()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "key.horizontal")
                                .font(.system(size: 10.5, weight: .semibold))
                            Text("更换密码")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(Color(red: 0.24, green: 0.38, blue: 0.54))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.56))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(red: 0.0, green: 0.52, blue: 0.92).opacity(0.22), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("记得当前密码：输入现有密码以安全更换新主密码")

                    Button {
                        vm.openResetPasswordTab()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise.circle")
                                .font(.system(size: 10.5, weight: .semibold))
                            Text("重置密码")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(Color(red: 0.72, green: 0.24, blue: 0.24))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.56))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(red: 0.85, green: 0.25, blue: 0.25).opacity(0.22), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("忘记了现有主密码：通过 Touch ID 或重新初始化直接重设新密码")
                }
            }
        }
    }

    // MARK: - 安全更换密码 & 重置密码 双模弹窗 (内置内联确认，彻底规避 macOS 弹窗遮挡 Bug)
    private var securityModalSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // 顶部模式分段切换栏
                Picker("", selection: $vm.securityModalTab) {
                    Text("更换密码 (需验证现有密码)").tag(0)
                    Text("重置密码 (忘记现有密码)").tag(1)
                }
                .pickerStyle(.segmented)
                .onChange(of: vm.securityModalTab) { _ in
                    vm.modalError = nil
                    vm.modalSuccess = nil
                    vm.showInlineWipeConfirm = false
                }

                // 反馈横幅 (错误或成功)
                if let err = vm.modalError {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.octagon.fill")
                            .foregroundColor(.red)
                        Text(err)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.red)
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(8)
                }

                if let ok = vm.modalSuccess {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(ok)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.green)
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.green.opacity(0.08))
                    .cornerRadius(8)
                }

                if vm.securityModalTab == 0 {
                    changePasswordTabContent
                } else {
                    resetPasswordTabContent
                }

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(width: 500, height: 570)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        vm.closeModal()
                    }
                }
            }
        }
    }

    // MARK: - 模式 0：安全更换主密码 (必须验证现有密码)
    private var changePasswordTabContent: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.0, green: 0.65, blue: 1.0).opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color(red: 0.0, green: 0.52, blue: 0.95))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("验证现有密码并安全更换")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color(red: 0.10, green: 0.16, blue: 0.28))
                    Text("校验现有主密码正确后，将使用新密钥无损重新加密全部本地数据")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("第一步：输入现有主密码 (必填校验)", systemImage: "1.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(red: 0.15, green: 0.28, blue: 0.45))

                    lightCyberPasswordField(
                        placeholder: "请输入当前正在使用的主密码...",
                        text: $vm.currentPasswordInput,
                        showSecret: $vm.showModalSecrets
                    ) {}
                }

                Divider()

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Label("第二步：输入新主密码 (至少 6 位)", systemImage: "2.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(red: 0.15, green: 0.28, blue: 0.45))
                        Spacer()
                        if !vm.newPasswordInput.isEmpty {
                            let info = strengthInfo(for: vm.newPasswordInput)
                            Text("强度: \(info.0)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(info.1)
                        }
                    }

                    lightCyberPasswordField(
                        placeholder: "请输入新的主密码...",
                        text: $vm.newPasswordInput,
                        showSecret: $vm.showModalSecrets
                    ) {}
                }

                VStack(alignment: .leading, spacing: 5) {
                    Label("第三步：确认新主密码", systemImage: "3.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(red: 0.15, green: 0.28, blue: 0.45))

                    lightCyberPasswordField(
                        placeholder: "请再次输入新的主密码...",
                        text: $vm.confirmNewPasswordInput,
                        showSecret: $vm.showModalSecrets
                    ) {
                        handleVerifyAndChangePassword()
                    }
                }
            }
            .padding(15)
            .background(Color(red: 0.96, green: 0.98, blue: 1.0))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(red: 0.0, green: 0.55, blue: 0.95).opacity(0.18), lineWidth: 1)
            )

            Button(action: handleVerifyAndChangePassword) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                    Text("验证现有密码并更新为新密码")
                        .font(.system(size: 13.5, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.02, green: 0.52, blue: 0.96),
                            Color(red: 0.00, green: 0.68, blue: 0.92)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .disabled(vm.currentPasswordInput.isEmpty || vm.newPasswordInput.count < 6 || vm.isProcessing)
            .opacity((vm.currentPasswordInput.isEmpty || vm.newPasswordInput.count < 6) ? 0.5 : 1.0)

            Button {
                vm.securityModalTab = 1
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "questionmark.circle")
                    Text("忘记了当前主密码？点此切换至【重置密码】无需旧密码直接重设")
                        .font(.system(size: 11.5, weight: .medium))
                        .underline()
                }
                .foregroundColor(Color(red: 0.02, green: 0.48, blue: 0.90))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
    }

    // MARK: - 模式 1：重置主密码 (忘记现有密码时无需旧密码直接重置)
    private var resetPasswordTabContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.14))
                        .frame(width: 42, height: 42)
                    Image(systemName: "arrow.counterclockwise.shield.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.orange)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("忘记密码 · 直接重置主密码")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color(red: 0.10, green: 0.16, blue: 0.28))
                    Text("无需输入旧密码：请在下方设置您的新主密码，并选择重置方式")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            // 1. 直接输入要设置的新密码
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Label("设置新的主密码 (至少 6 位)", systemImage: "key.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(red: 0.15, green: 0.28, blue: 0.45))
                        Spacer()
                        if !vm.newPasswordInput.isEmpty {
                            let info = strengthInfo(for: vm.newPasswordInput)
                            Text("新密码强度: \(info.0)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(info.1)
                        }
                    }

                    lightCyberPasswordField(
                        placeholder: "请输入您要重设的新主密码...",
                        text: $vm.newPasswordInput,
                        showSecret: $vm.showModalSecrets
                    ) {}
                }

                VStack(alignment: .leading, spacing: 5) {
                    Label("确认新的主密码", systemImage: "checkmark.shield.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(red: 0.15, green: 0.28, blue: 0.45))

                    lightCyberPasswordField(
                        placeholder: "请再次输入相同的新主密码...",
                        text: $vm.confirmNewPasswordInput,
                        showSecret: $vm.showModalSecrets
                    ) {}
                }
            }
            .padding(14)
            .background(Color(red: 0.96, green: 0.98, blue: 1.0))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(red: 0.0, green: 0.55, blue: 0.95).opacity(0.18), lineWidth: 1)
            )

            // 2. 重置执行方式 A：Touch ID 无损重置 (若可用)
            if store.touchIDEnabled && hasTouchID && KeychainTouchIDHelper.hasSavedBiometricsCredential() {
                Button(action: handleResetWithTouchID) {
                    HStack(spacing: 8) {
                        Image(systemName: "touchid")
                            .font(.system(size: 15))
                        Text("方式 A：通过 Touch ID 指纹核验并重设新密码 (保留全部旧数据)")
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [Color.pink, Color.purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }

            // 3. 重置执行方式 B：直接重置密码箱并启用新密码 (内联二次确认，100% 响应不失败)
            if !vm.showInlineWipeConfirm {
                VStack(spacing: 8) {
                    Button {
                        if vm.newPasswordInput.isEmpty && vm.confirmNewPasswordInput.isEmpty {
                            // 允许直接触发清空确认
                            vm.modalError = nil
                            vm.showInlineWipeConfirm = true
                        } else if vm.newPasswordInput.count < 6 {
                            vm.modalError = "新主密码长度不能少于 6 位"
                        } else if vm.newPasswordInput != vm.confirmNewPasswordInput {
                            vm.modalError = "两次输入的新主密码不一致，请核对"
                        } else {
                            vm.modalError = nil
                            vm.showInlineWipeConfirm = true
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            Text(vm.newPasswordInput.count >= 6 && vm.newPasswordInput == vm.confirmNewPasswordInput
                                 ? "立即重置密码库并启用上方新密码"
                                 : "清空旧密文并重新初始化密码库")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.90, green: 0.26, blue: 0.24),
                                    Color(red: 0.96, green: 0.45, blue: 0.18)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)

                    Text("说明：纯本地离线加密无云端后门，无旧密码与指纹时重置将抹除旧密文并启用新密码。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            } else {
                // 内联二次确认面板 (不依赖外部 Alert，杜绝 macOS Sheet 遮挡导致的点击无效)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(vm.newPasswordInput.count >= 6 && vm.newPasswordInput == vm.confirmNewPasswordInput
                             ? "确认抹除旧密文，并立即使用新密码解锁进入？"
                             : "确认抹除本地旧密文，并返回首次设密界面？")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundColor(.red)
                    }

                    Text("由于采用纯本地零知识加密，旧密文在无原密码时无法解密。点击“确认重置”后将立即为您完成重置。")
                        .font(.system(size: 11.5))
                        .foregroundColor(Color(red: 0.35, green: 0.15, blue: 0.15))

                    HStack(spacing: 12) {
                        Button {
                            vm.showInlineWipeConfirm = false
                        } label: {
                            Text("取消")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.white)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)

                        Button {
                            handleExecuteDirectReset()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark.circle.fill")
                                Text(vm.newPasswordInput.count >= 6 && vm.newPasswordInput == vm.confirmNewPasswordInput
                                     ? "确认重置并直接解锁"
                                     : "确认清空并重设密码")
                                    .font(.system(size: 12.5, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.red)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
                .background(Color.red.opacity(0.08))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.red.opacity(0.35), lineWidth: 1.2)
                )
            }
        }
    }

    // MARK: - 逻辑处理
    private func handleUnlock() {
        vm.localError = nil
        vm.successMessage = nil
        vm.isProcessing = true
        do {
            try store.unlock(masterPassword: vm.password)
            vm.password = ""
        } catch {
            vm.localError = "主密码校验错误，请重新输入（如忘记密码请点击右下角“重置密码”）"
        }
        vm.isProcessing = false
    }

    private func handleCreateVault() {
        vm.localError = nil
        vm.successMessage = nil
        guard vm.password == vm.confirmPassword else {
            vm.localError = "两次输入的密码不一致"
            return
        }
        guard vm.password.count >= 6 else {
            vm.localError = "为了安全，主密码长度不能少于 6 位"
            return
        }

        vm.isProcessing = true
        store.touchIDEnabled = vm.enableTouchIDOnCreate
        do {
            try store.createVault(masterPassword: vm.password)
            vm.password = ""
            vm.confirmPassword = ""
        } catch {
            vm.localError = error.localizedDescription
        }
        vm.isProcessing = false
    }

    private func handleVerifyAndChangePassword() {
        vm.modalError = nil
        vm.modalSuccess = nil

        guard !vm.currentPasswordInput.isEmpty else {
            vm.modalError = "请输入现有主密码进行校验（若已忘记现有密码，请切换到顶部“重置密码”标签）"
            return
        }
        guard vm.newPasswordInput == vm.confirmNewPasswordInput else {
            vm.modalError = "两次输入的新密码不一致，请核对"
            return
        }
        guard vm.newPasswordInput.count >= 6 else {
            vm.modalError = "新密码长度不能少于 6 位"
            return
        }

        vm.isProcessing = true
        do {
            try store.changeMasterPassword(currentPassword: vm.currentPasswordInput, newPassword: vm.newPasswordInput)
            vm.modalSuccess = "现有密码验证通过！主密码已成功更新。"
            vm.successMessage = "主密码已成功更新，请使用新密码解锁"
            Task {
                try? await Task.sleep(nanoseconds: 900_000_000)
                await MainActor.run {
                    vm.closeModal()
                }
            }
        } catch {
            vm.modalError = "现有密码校验失败：原密码不正确（若忘记原密码请切换至顶部“重置密码”）"
        }
        vm.isProcessing = false
    }

    private func handleResetWithTouchID() {
        vm.modalError = nil
        vm.modalSuccess = nil

        guard !vm.newPasswordInput.isEmpty, vm.newPasswordInput == vm.confirmNewPasswordInput, vm.newPasswordInput.count >= 6 else {
            vm.modalError = "请先在上方输入合法且两次一致的新主密码 (至少 6 位)"
            return
        }

        vm.isProcessing = true
        Task {
            do {
                try await store.resetMasterPasswordWithTouchID(newPassword: vm.newPasswordInput)
                await MainActor.run {
                    vm.modalSuccess = "Touch ID 验证通过！主密码已成功重置并保留全部数据。"
                    vm.closeModal()
                }
            } catch {
                await MainActor.run {
                    vm.modalError = "Touch ID 验证未通过: \(error.localizedDescription)"
                }
            }
            await MainActor.run {
                vm.isProcessing = false
            }
        }
    }

    private func handleExecuteDirectReset() {
        vm.modalError = nil
        vm.modalSuccess = nil

        // 如果用户已经填写了合法的新密码，直接一步到位完成“清空旧密文 + 创建新密码库 + 自动解锁进入主界面”
        if vm.newPasswordInput.count >= 6 && vm.newPasswordInput == vm.confirmNewPasswordInput {
            let newPass = vm.newPasswordInput
            do {
                try store.resetVaultAndCreateNew(newPassword: newPass)
                vm.password = ""
                vm.confirmPassword = ""
                vm.localError = nil
                vm.closeModal()
            } catch {
                vm.modalError = "重置初始化失败: \(error.localizedDescription)"
            }
        } else {
            // 如果用户未填写新密码，则清空旧密文并回到首次设密主界面
            store.resetEntireVault()
            vm.password = ""
            vm.confirmPassword = ""
            vm.localError = nil
            vm.successMessage = "本地密码库已成功重置清空，请在下方设置您的全新主密码"
            vm.closeModal()
        }
    }

    private func strengthInfo(for pwd: String) -> (String, Color) {
        let eval = PasswordGenerator.evaluateStrength(pwd)
        switch eval.strength {
        case .empty: return ("未设置", .secondary)
        case .weak: return ("弱", .red)
        case .fair: return ("中等", .orange)
        case .strong: return ("强", Color(red: 0.0, green: 0.55, blue: 0.95))
        case .veryStrong: return ("极强", Color(red: 0.05, green: 0.72, blue: 0.45))
        }
    }
}
