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
    rm -rf "$TARGET_APP"
    mkdir -p "$TARGET_APP/Contents/MacOS"
    mkdir -p "$TARGET_APP/Contents/Resources"

    cp "$DIR/.build/release/LocalVault" "$TARGET_APP/Contents/MacOS/LocalVault"
    chmod +x "$TARGET_APP/Contents/MacOS/LocalVault"

    local RES_DIR="$DIR/Resources"
    if [ ! -d "$RES_DIR" ] && [ -d "$DIR/../Resources" ]; then
        RES_DIR="$DIR/../Resources"
    fi

    if [ -f "$RES_DIR/AppIcon.icns" ]; then
        cp "$RES_DIR/AppIcon.icns" "$TARGET_APP/Contents/Resources/AppIcon.icns"
    fi
    if [ -f "$RES_DIR/BrandHero.png" ]; then
        cp "$RES_DIR/BrandHero.png" "$TARGET_APP/Contents/Resources/BrandHero.png"
    fi
    if [ -f "$RES_DIR/SourceBrandIcon.png" ]; then
        cp "$RES_DIR/SourceBrandIcon.png" "$TARGET_APP/Contents/Resources/SourceBrandIcon.png"
    fi
    if [ -f "$RES_DIR/AppIcon-Preview.png" ]; then
        cp "$RES_DIR/AppIcon-Preview.png" "$TARGET_APP/Contents/Resources/AppIcon-Preview.png"
    fi
    if [ -f "$RES_DIR/LoginScreen-Preview.png" ]; then
        cp "$RES_DIR/LoginScreen-Preview.png" "$TARGET_APP/Contents/Resources/LoginScreen-Preview.png"
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

echo "==> 4. 安装部署至 /Applications/SecretCore.app 与 ~/Desktop/SecretCore.app..."
rm -rf /Applications/SecretCore.app
cp -R "$APP_DIR" /Applications/SecretCore.app
rm -f ~/Desktop/SecretCore.app
ln -s /Applications/SecretCore.app ~/Desktop/SecretCore.app

# 注册 LaunchServices 图标缓存
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f /Applications/SecretCore.app || true
touch /Applications/SecretCore.app

echo "✅ 打包与部署完成:"
echo "   本地构建包: $APP_DIR"
echo "   系统程序包: /Applications/SecretCore.app"
echo "   桌面快捷方式: ~/Desktop/SecretCore.app"
