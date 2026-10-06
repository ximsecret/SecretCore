<p align="center">
  <img src="Resources/AppIcon-Preview.png" width="128" height="128" alt="SecretCore Icon" />
</p>

<p align="center">
  <h1 align="center">SecretCore · 极光秘核</h1>
  <b>纯本地离线 macOS 密码与 2FA (TOTP) 一体化管理工具</b><br>
  Swift + SwiftUI 原生架构 · 零网络权限 · 军工级 AES-256-GCM 强加密 · RFC 6238 TOTP
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2013%2B-blue?logo=apple" alt="Platform" />
  <img src="https://img.shields.io/badge/Language-Swift%205.9-orange?logo=swift" alt="Language" />
  <img src="https://img.shields.io/badge/Network-100%25%20Offline-success" alt="Offline" />
  <img src="https://img.shields.io/badge/License-MIT-green" alt="License" />
</p>

---


`SecretCore (极光秘核) (LocalVault)` 是一款采用 **Swift + SwiftUI 原生架构** 构建的纯本地、零网络依赖的 macOS 密码管理与 2FA（TOTP 动态验证码）一体化软件。无任何第三方依赖包，完全调用 macOS 系统底层安全框架（`CryptoKit`、`CommonCrypto`、`LocalAuthentication`、`CoreImage`）。

---

## 核心特性

### 1. 纯本地强加密架构（零网络权限）
- **密钥派生**：采用 `CommonCrypto` 的 `CCKeyDerivationPBKDF`（`PBKDF2-HMAC-SHA256`，默认 **150,000 轮**迭代 + 32 字节随机高强度盐值）从主密码派生 256 位对称密钥。
- **认证加密**：采用 Apple `CryptoKit` 的 **AES-256-GCM**（12 字节随机 Nonce + 16 字节完整性认证 Tag）加密整个保险箱数据。任何字节篡改或密码错误均在解密阶段被直接拒绝。
- **纯离线存储**：加密文件默认保存在本地 `~/Library/Application Support/LocalVault/vault.enc`，软件不申请任何网络权限，杜绝云端泄漏风险。

### 2. 密码 + 2FA (TOTP) 同屏一体管理
- **标准 RFC 6238 动态码**：内置零依赖 `RFC 4648 Base32` 解码器与 `RFC 6238 TOTP` 引擎，支持 `SHA1` / `SHA256` / `SHA512` 算法、6 位 / 8 位动态码、30 秒 / 60 秒周期。
- **多种 2FA 导入方式**：
  - 直接输入或粘贴 `Base32 Secret` 密钥；
  - 一键粘贴解析 `otpauth://totp/...` 标准协议链接（自动填充发行方、账号名、密钥与算法参数）；
  - **离线二维码识别**：直接选择本地二维码图片（PNG/JPG 截图），通过 macOS 原生 `CIDetector` 离线识别并导入 2FA 密钥。
- **实时倒计时环与一键复制**：列表与详情页实时展示 30 秒进度圆环（最后 5 秒变红预警），点击即可复制密码或 6 位动态码。

### 3. 多维分类体系与视觉美化
- **7 大业务分类与专属色彩图标**：
  - 🪙 **加密与交易**（琥珀金）：交易所、Web3 钱包、行情平台
  - 💻 **开发与工作**（靛蓝紫）：GitHub、服务器、代码仓库、工作台
  - 🪄 **AI与云服务**（霓虹紫）：OpenAI、Claude、云算力与 API
  - 💳 **金融与支付**（翡翠绿）：银行卡、券商、支付与账单
  - 💬 **社交与邮箱**（珊瑚粉）：邮箱、Apple ID、社交媒体
  - 🌐 **常规网站**（科技蓝）：日常网站、论坛、通用账号
  - 📁 **其他记录**（岩石灰）：软件激活码、安全备忘与其它
- **按类型分组（Grouped）与平铺列表一键切换**：在列表栏顶部可一键切换“按分类分组展示”（带彩色标识条与分类卡片）与“平铺列表展示”。
- **多维度筛选体系**：
  - **左侧侧边栏**：快捷概览（全部、星标收藏、2FA 动态码）、分类目录（带各分类数量统计角标）与自定义子标签栏；
  - **顶部水平滚动胶囊栏**：单手快速在各个分类之间横跳筛选；
  - **详情页一键换类**：在详情 Hero 面板可直接通过分类下拉菜单 1 键将账号调整到新类型；
  - **自定义子标签**：支持为账号附加任意子标签（如 `#交易所`、`#主力号`、`#AWS`），并在全库中汇总检索。
- **现代化视觉打磨**：
  - 沉浸式微光深色锁定屏、毛玻璃卡片质感、3D 渐变盾牌 Emblem；
  - 密码强度动态彩色指示条与信息熵实时评估；
  - 32pt 大字号等宽 2FA 动态码、动态脉冲倒计时进度环；
  - 复制成功绿色安全胶囊 Toast 与安全清空倒计时提示。

### 4. macOS 原生安全防护与便捷交互
- **Touch ID 指纹快捷解锁**：开启后将主密码加密托管于 macOS 硬件级 `Keychain`（绑定生物识别上下文），支持指纹一键解锁。
- **剪贴板自动清空**：复制密码或 2FA 验证码后，默认 **30 秒自动清空系统剪贴板**（仅当剪贴板内容仍为刚才复制的凭据时才清除，不误删后续复制的其它文本）。
- **自动上锁防护**：支持闲置超时自动锁定（1 / 5 / 15 / 30 分钟），并在 Mac **息屏或休眠瞬间自动上锁**并清空内存中的明文与密钥。
- **菜单栏常驻小助手 (`MenuBarExtra`)**：常驻系统右上角状态栏，无需切出浏览器即可快速搜索并一键复制密码与当前 2FA 验证码。
- **内置高熵密码生成器**：使用硬件级 `SystemRandomNumberGenerator` 生成密码，实时评估信息熵（bits）与抗暴力破解强度。
- **加密备份与 JSON 迁移**：支持导出 `.vault` 加密备份包或导入/导出明文 JSON 以便离线冷备。

---

## 目录结构

```text
LocalVault/
├── Package.swift                           # Swift Package 配置 (macOS 13+, 零第三方依赖)
├── Resources/
│   └── AppIcon.icns                        # 原生高清应用图标
├── Sources/LocalVault/
│   ├── Models.swift                        # 账号、分类、2FA 配置及加密信封数据模型
│   ├── CryptoEngine.swift                  # PBKDF2-HMAC-SHA256 + AES-256-GCM + Touch ID Keychain
│   ├── TOTPEngine.swift                    # Base32 解码、RFC 6238 TOTP、otpauth 解析、二维码识别
│   ├── PasswordGenerator.swift             # 强随机数密码生成与熵值评估
│   ├── VaultStore.swift                    # 核心状态总线、定时刷新、剪贴板自动清理、休眠上锁
│   ├── LocalVaultApp.swift                 # 应用主入口、菜单栏扩展与 --self-test 自检套件
│   └── Views/
│       ├── LockView.swift                  # 首次创建与解锁/Touch ID 界面
│       ├── MainVaultView.swift             # 三栏主视图与独立密码生成器弹窗
│       ├── ItemDetailView.swift            # 账号详情与 2FA 实时倒计时面板
│       ├── ItemEditorSheet.swift           # 新增/编辑账号及离线二维码扫描表单
│       ├── SettingsSheet.swift             # 安全策略、修改主密码、加密备份与恢复
│       └── MenuBarView.swift               # 菜单栏常驻快速检索面板
├── scripts/
│   └── build_app.sh                        # 一键编译、自检、打包并签名 .app 脚本
└── build/
    └── SecretCore.app                      # 打包生成的独立双击可运行 macOS 应用
```

---

## 快速构建与运行

### 1. 一键编译并打包 `.app`
```bash
cd LocalVault
./scripts/build_app.sh
```

### 2. 运行内置加密与 RFC 6238 算法自检
```bash
.build/release/LocalVault --self-test
```

### 3. 启动应用
```bash
open "build/SecretCore.app"
```
也可以将 `build/SecretCore.app` 直接拖入 `/Applications`（应用程序）文件夹或固定到 Dock 栏日常使用。


---

## 📄 开源许可证

本项目基于 [MIT License](LICENSE) 协议开源。
