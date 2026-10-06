#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$DIR/build"
APP_DIR="$BUILD_DIR/SecretCore.app"

echo "==> 1. 编译 SecretCore (极光秘核) Release 原生二进制..."
swift build -c release --package-path "$DIR"

echo "==> 2. 运行加密、密码更换校验与 TOTP 算法自检..."
"$DIR/.build/release/LocalVault" --self-test

package_bundle() {
    local TARGET_APP="$1"
    mkdir -p "$TARGET_APP/Contents/MacOS"
    mkdir -p "$TARGET_APP/Contents/Resources"

    cp "$DIR/.build/release/LocalVault" "$TARGET_APP/Contents/MacOS/LocalVault"
    chmod +x "$TARGET_APP/Contents/MacOS/LocalVault"

    if [ -f "$DIR/Resources/AppIcon.icns" ]; then
        cp "$DIR/Resources/AppIcon.icns" "$TARGET_APP/Contents/Resources/AppIcon.icns"
    fi
    if [ -f "$DIR/Resources/BrandHero.png" ]; then
        cp "$DIR/Resources/BrandHero.png" "$TARGET_APP/Contents/Resources/BrandHero.png"
    fi
    if [ -f "$DIR/Resources/SourceBrandIcon.png" ]; then
        cp "$DIR/Resources/SourceBrandIcon.png" "$TARGET_APP/Contents/Resources/SourceBrandIcon.png"
    fi

    cat << 'PLIST' > "$TARGET_APP/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleDisplayName</key>
    <string>SecretCore · 极光秘核</string>
    <key>CFBundleExecutable</key>
    <string>LocalVault</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.localvault.offline.macos</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>SecretCore</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.2.0</string>
    <key>CFBundleVersion</key>
    <string>1.2.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

    touch "$TARGET_APP"
    codesign --force --deep --sign - "$TARGET_APP"
}

echo "==> 3. 封装 macOS 独立应用包 (SecretCore.app)..."
package_bundle "$APP_DIR"

echo "✅ 打包与签名完成:"
echo "   主应用包: $APP_DIR"
