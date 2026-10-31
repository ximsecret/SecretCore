import AppKit
import CoreGraphics
import CoreImage
import Foundation

let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let baseDir = scriptDir.deletingLastPathComponent()
let sourceImagePath = baseDir.appendingPathComponent("Resources/SourceBrandIcon.png").path

guard let sourceImage = NSImage(contentsOfFile: sourceImagePath) else {
    print("❌ Failed to load SourceBrandIcon.png at: \(sourceImagePath)")
    exit(1)
}

/// 生成 macOS 图标或应用内主视觉大徽标
/// - Parameters:
///   - size: 输出画布尺寸
///   - source: 原始高清 3D 护盾图
///   - isHeroEmblem: 若为 true，则采用超窄边距饱满构图，专为登录页/应用内大尺寸主图标设计
func createMacAppIcon(size: CGFloat, source: NSImage, isHeroEmblem: Bool = false) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let s = size / 1024.0

    // 大幅放大主图标占画布比例：
    // AppIcon 采用 896x896 (留白仅 64px，比之前 824 明显放大)；
    // 登录页 Hero 徽标采用 968x968 (留白仅 28px，饱满度拉满)
    let pad = (isHeroEmblem ? 28.0 : 64.0) * s
    let boxSize = 1024.0 * s - pad * 2.0
    let baseRect = CGRect(x: pad, y: pad, width: boxSize, height: boxSize)
    let cornerRadius = boxSize * 0.225
    let squirclePath = NSBezierPath(roundedRect: baseRect, xRadius: cornerRadius, yRadius: cornerRadius)

    // 1. 底层立体投影 (深海电光蓝立体悬浮阴影)
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -8.0 * s),
        blur: (isHeroEmblem ? 14.0 : 18.0) * s,
        color: NSColor(calibratedRed: 0.02, green: 0.14, blue: 0.35, alpha: 0.32).cgColor
    )
    NSColor(calibratedWhite: 0.96, alpha: 1.0).setFill()
    squirclePath.fill()
    ctx.restoreGState()

    if !isHeroEmblem {
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -22.0 * s),
            blur: 36.0 * s,
            color: NSColor(calibratedRed: 0.0, green: 0.28, blue: 0.62, alpha: 0.30).cgColor
        )
        NSColor(calibratedWhite: 0.96, alpha: 1.0).setFill()
        squirclePath.fill()
        ctx.restoreGState()
    }

    // 2. 裁剪到连续圆角内部并大幅放大核心 3D 护盾与 secret 铭牌
    ctx.saveGState()
    squirclePath.addClip()

    // 原图 1254x1254：向内深度裁剪 122px，使 3D 蓝盾、挂锁与 secret 胶囊显著放大并占据绝对视觉中心
    // 同时微调纵向偏移 (+14px)，让盾牌尖顶到全息底座完美居中
    let cropInset: CGFloat = isHeroEmblem ? 132.0 : 118.0
    let srcW = source.size.width
    let srcH = source.size.height
    let srcRect = CGRect(
        x: cropInset,
        y: cropInset + 10.0,
        width: srcW - cropInset * 2.0,
        height: srcH - cropInset * 2.0
    )

    if let tiffData = source.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiffData),
       let cgImage = bitmap.cgImage {
        if let croppedCG = cgImage.cropping(to: srcRect) {
            ctx.draw(croppedCG, in: baseRect)
        } else {
            ctx.draw(cgImage, in: baseRect)
        }
    }

    // 3. 顶部全息冷白/电光冰蓝折射高光
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let highlightColors = [
        NSColor(calibratedWhite: 1.0, alpha: 0.28).cgColor,
        NSColor(calibratedRed: 0.65, green: 0.90, blue: 1.0, alpha: 0.10).cgColor,
        NSColor(calibratedWhite: 1.0, alpha: 0.0).cgColor
    ] as CFArray
    if let grad = CGGradient(colorsSpace: colorSpace, colors: highlightColors, locations: [0.0, 0.32, 1.0]) {
        ctx.drawLinearGradient(
            grad,
            start: CGPoint(x: baseRect.midX, y: baseRect.maxY),
            end: CGPoint(x: baseRect.midX, y: baseRect.midY + 60.0 * s),
            options: []
        )
    }

    // 4. 物理级水晶双层内描边 (高光白 + 赛博电光蓝护边)
    let innerBorderRect = baseRect.insetBy(dx: 2.0 * s, dy: 2.0 * s)
    let innerPath = NSBezierPath(roundedRect: innerBorderRect, xRadius: cornerRadius - 2.0 * s, yRadius: cornerRadius - 2.0 * s)
    innerPath.lineWidth = 3.5 * s
    NSColor(calibratedWhite: 1.0, alpha: 0.65).setStroke()
    innerPath.stroke()

    let outerRimRect = baseRect.insetBy(dx: 0.75 * s, dy: 0.75 * s)
    let outerRimPath = NSBezierPath(roundedRect: outerRimRect, xRadius: cornerRadius, yRadius: cornerRadius)
    outerRimPath.lineWidth = 1.5 * s
    NSColor(calibratedRed: 0.0, green: 0.58, blue: 0.98, alpha: 0.38).setStroke()
    outerRimPath.stroke()

    ctx.restoreGState()

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to url: URL, pixelSize: Int) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return }

    rep.size = NSSize(width: pixelSize, height: pixelSize)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(
        in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
        from: .zero,
        operation: .copy,
        fraction: 1.0
    )
    NSGraphicsContext.restoreGraphicsState()

    if let data = rep.representation(using: .png, properties: [:]) {
        try data.write(to: url)
    }
}

let fm = FileManager.default
// baseDir already defined above
let resourcesDir = baseDir.appendingPathComponent("Resources", isDirectory: true)
let iconsetDir = resourcesDir.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try? fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

print("🎨 正在生成放大版 macOS 原生全息 Squircle 图标...")
let masterImage = createMacAppIcon(size: 1024, source: sourceImage, isHeroEmblem: false)
let previewURL = resourcesDir.appendingPathComponent("AppIcon-Preview.png")
try savePNG(masterImage, to: previewURL, pixelSize: 1024)

// 生成专门用于登录页与主界面的超饱满放大版 BrandHero.png (768x768 高清)
let heroImage = createMacAppIcon(size: 1024, source: sourceImage, isHeroEmblem: true)
let heroURL = resourcesDir.appendingPathComponent("BrandHero.png")
try savePNG(heroImage, to: heroURL, pixelSize: 768)

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (filename, px) in specs {
    let img = createMacAppIcon(size: CGFloat(px), source: sourceImage, isHeroEmblem: false)
    try savePNG(img, to: iconsetDir.appendingPathComponent(filename), pixelSize: px)
}

print("✅ 图标切片生成完成，正在调用 iconutil 打包 AppIcon.icns...")
let icnsURL = resourcesDir.appendingPathComponent("AppIcon.icns")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsURL.path]
try p.run()
p.waitUntilExit()

if p.terminationStatus == 0 {
    print("🎉 成功生成放大版原生 AppIcon.icns 与 BrandHero.png!")
} else {
    print("❌ iconutil 执行失败，返回码: \(p.terminationStatus)")
}
