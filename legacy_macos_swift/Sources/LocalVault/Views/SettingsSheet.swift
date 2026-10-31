import SwiftUI
import AppKit
import UniformTypeIdentifiers

public final class SettingsViewModel: ObservableObject {
    @Published public var currentPassword: String = ""
    @Published public var newPassword: String = ""
    @Published public var confirmNewPassword: String = ""
    @Published public var skipOldPassword: Bool = false
    @Published public var showWipeConfirm: Bool = false
    @Published public var statusBanner: String? = nil
    @Published public var isErrorBanner: Bool = false

    public init() {}
}

public struct SettingsSheet: View {
    @EnvironmentObject private var store: VaultStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = SettingsViewModel()

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                if let banner = vm.statusBanner {
                    Section {
                        HStack {
                            Image(systemName: vm.isErrorBanner ? "xmark.octagon.fill" : "checkmark.circle.fill")
                                .foregroundColor(vm.isErrorBanner ? .red : .green)
                            Text(banner)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(vm.isErrorBanner ? .red : .green)
                        }
                    }
                }

                // 1. 安全策略设置
                Section("安全与隐私防护") {
                    if KeychainTouchIDHelper.isTouchIDAvailable() {
                        Toggle(
                            "启用 Touch ID 指纹快捷解锁",
                            isOn: Binding(
                                get: { store.touchIDEnabled },
                                set: { store.syncTouchIDSetting(enabled: $0) }
                            )
                        )
                    }

                    Picker("自动上锁策略", selection: $store.autoLockMinutes) {
                        Text("仅在系统锁屏/睡眠或手动时上锁 (推荐)").tag(0)
                        Text("无操作 5 分钟后自动上锁").tag(5)
                        Text("无操作 15 分钟后自动上锁").tag(15)
                        Text("无操作 30 分钟后自动上锁").tag(30)
                        Text("无操作 1 分钟后自动上锁").tag(1)
                    }

                    Picker("复制密码/2FA 后清空剪贴板", selection: $store.clipboardClearSeconds) {
                        Text("15 秒").tag(15)
                        Text("30 秒 (推荐)").tag(30)
                        Text("60 秒").tag(60)
                        Text("不自动清空").tag(0)
                    }
                }

                // 2. 修改或重置主密码
                Section("修改 / 重置主密码 (保留全部现有数据)") {
                    Toggle("忘记旧密码（当前已解锁，免输旧密码直接重置）", isOn: $vm.skipOldPassword)
                        .font(.system(size: 12))

                    if !vm.skipOldPassword {
                        SecureField("当前主密码", text: $vm.currentPassword)
                    }
                    SecureField("新主密码 (至少 6 位)", text: $vm.newPassword)
                    SecureField("确认新主密码", text: $vm.confirmNewPassword)

                    Button(vm.skipOldPassword ? "直接重置为新主密码" : "更新主加密密码") {
                        handleChangeMasterPassword()
                    }
                    .disabled((!vm.skipOldPassword && vm.currentPassword.isEmpty) || vm.newPassword.isEmpty || vm.confirmNewPassword.isEmpty)
                }

                // 3. 本地数据文件与备份
                Section("本地加密数据与备份") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("本地加密存储路径:")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text(store.vaultFileURL.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)

                        HStack(spacing: 10) {
                            Button(action: {
                                NSWorkspace.shared.activateFileViewerSelecting([store.vaultFileURL])
                            }) {
                                Label("在 Finder 中定位", systemImage: "folder")
                            }
                            .controlSize(.small)

                            Button(action: handleExportEncrypted) {
                                Label("导出加密备份 (.enc)", systemImage: "lock.doc")
                            }
                            .controlSize(.small)

                            Button(action: handleExportJSON) {
                                Label("导出 JSON 明文", systemImage: "square.and.arrow.up")
                            }
                            .controlSize(.small)

                            Button(action: handleImportJSON) {
                                Label("导入 JSON", systemImage: "square.and.arrow.down")
                            }
                            .controlSize(.small)
                        }
                        .padding(.top, 4)
                    }
                }

                // 4. 彻底初始化重置
                Section("彻底重置") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("清空并重新初始化密码箱")
                                    .font(.system(size: 12.5, weight: .semibold))
                                Text("删除所有本地账号记录并回到首次设置新主密码状态")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if !vm.showWipeConfirm {
                                Button(role: .destructive) {
                                    vm.showWipeConfirm = true
                                } label: {
                                    Label("清空重置密码库", systemImage: "trash")
                                }
                                .controlSize(.small)
                            }
                        }

                        if vm.showWipeConfirm {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("⚠️ 确认清空本地所有加密账号数据，并返回初始设密界面？")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.red)
                                HStack(spacing: 10) {
                                    Button("取消") {
                                        vm.showWipeConfirm = false
                                    }
                                    .controlSize(.small)

                                    Button(role: .destructive) {
                                        store.resetEntireVault()
                                        dismiss()
                                    } label: {
                                        Text("确认清空并重新设置主密码")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.red)
                                    .controlSize(.small)
                                }
                            }
                            .padding(10)
                            .background(Color.red.opacity(0.08))
                            .cornerRadius(8)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .alert("确认彻底清空并重置密码箱？", isPresented: $vm.showWipeConfirm) {
                Button("取消", role: .cancel) {}
                Button("清空并重新设置主密码", role: .destructive) {
                    store.resetEntireVault()
                    dismiss()
                }
            } message: {
                Text("此操作将清空本地加密库中的所有账号与 2FA 数据，并立即返回初始界面让您设置全新的主密码。")
            }
            .navigationTitle("安全与备份设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 500)
    }

    private func handleChangeMasterPassword() {
        guard vm.newPassword == vm.confirmNewPassword else {
            showBanner("两次输入的新密码不一致", isError: true)
            return
        }
        guard vm.newPassword.count >= 6 else {
            showBanner("新密码长度不能少于 6 位", isError: true)
            return
        }

        do {
            if vm.skipOldPassword {
                try store.resetMasterPasswordDirectly(newPassword: vm.newPassword)
            } else {
                try store.changeMasterPassword(currentPassword: vm.currentPassword, newPassword: vm.newPassword)
            }
            vm.currentPassword = ""
            vm.newPassword = ""
            vm.confirmNewPassword = ""
            showBanner("主密码已重置并重新加密保存成功！", isError: false)
        } catch {
            showBanner(error.localizedDescription, isError: true)
        }
    }

    private func handleExportEncrypted() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "SecretCore_Backup_\(formattedDate()).enc"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try store.exportEncryptedBackup(to: url)
                showBanner("加密备份已导出至: \(url.lastPathComponent)", isError: false)
            } catch {
                showBanner("导出失败: \(error.localizedDescription)", isError: true)
            }
        }
    }

    private func handleExportJSON() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "SecretCore_Export_\(formattedDate()).json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try store.exportPlaintextJSON(to: url)
                showBanner("明文 JSON 已导出，请注意妥善保管该文件", isError: false)
            } catch {
                showBanner("导出失败: \(error.localizedDescription)", isError: true)
            }
        }
    }

    private func handleImportJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let count = try store.importFromPlaintextJSON(from: url)
                showBanner("成功导入 \(count) 条新账号记录", isError: false)
            } catch {
                showBanner("导入失败: \(error.localizedDescription)", isError: true)
            }
        }
    }

    private func showBanner(_ text: String, isError: Bool) {
        vm.statusBanner = text
        vm.isErrorBanner = isError
    }

    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmm"
        return formatter.string(from: Date())
    }
}
