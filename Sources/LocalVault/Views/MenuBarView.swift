import SwiftUI
import AppKit

public final class MenuBarViewModel: ObservableObject {
    @Published public var quickSearch: String = ""
    @Published public var selectedCategory: AccountCategory? = nil

    public init() {}
}

public struct MenuBarView: View {
    @EnvironmentObject private var store: VaultStore
    @StateObject private var vm = MenuBarViewModel()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // 顶部标题栏与全局 2FA 进度
            HStack(spacing: 8) {
                VaultBrandEmblemView(size: 22)

                Text("SecretCore · 极光秘核")
                    .font(.system(size: 12.5, weight: .bold))

                Spacer()

                if store.isUnlocked {
                    HStack(spacing: 4) {
                        Circle()
                            .trim(from: 0, to: store.progress2FA)
                            .stroke(
                                store.remainingSeconds2FA <= 5 ? Color.red : Color.blue,
                                style: StrokeStyle(lineWidth: 2, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 14, height: 14)

                        Text("\(store.remainingSeconds2FA)s")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(store.remainingSeconds2FA <= 5 ? .red : .secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if !store.isUnlocked {
                lockedQuickView
            } else {
                unlockedQuickView
            }

            Divider()

            // 底部快捷操作
            HStack {
                Button("打开主窗口") {
                    NSApp.activate(ignoringOtherApps: true)
                    for window in NSApp.windows where window.canBecomeMain {
                        window.makeKeyAndOrderFront(nil)
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.blue)

                Spacer()

                if store.isUnlocked {
                    Button("锁定") {
                        store.lock()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(.orange)

                    Text("·").foregroundColor(.secondary.opacity(0.5))
                }

                Button("退出") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        }
        .frame(width: 340)
    }

    private var lockedQuickView: some View {
        VStack(spacing: 12) {
            VaultBrandEmblemView(size: 54)
                .padding(.top, 14)

            Text("保险箱已锁定，请先解锁以查看密码与 2FA")
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)

            if store.touchIDEnabled && KeychainTouchIDHelper.isTouchIDAvailable() {
                Button(action: {
                    Task {
                        await store.unlockWithTouchID()
                    }
                }) {
                    Label("Touch ID 快捷解锁", systemImage: "touchid")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Button("打开主窗口输入主密码") {
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
    }

    private var unlockedQuickView: some View {
        let filtered = store.items.filter { item in
            if let targetCat = vm.selectedCategory, item.category != targetCat {
                return false
            }
            let q = vm.quickSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if q.isEmpty { return true }
            return item.title.lowercased().contains(q) ||
                   item.username.lowercased().contains(q) ||
                   item.category.rawValue.lowercased().contains(q) ||
                   item.normalizedCustomTag.lowercased().contains(q)
        }

        return VStack(spacing: 0) {
            // 搜索框
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                TextField("按标题、分类、账号或标签搜索...", text: $vm.quickSearch)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))

                if !vm.quickSearch.isEmpty {
                    Button(action: { vm.quickSearch = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.secondary.opacity(0.08))

            // 水平分类筛选条
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    categoryChip(nil, label: "全部 (\(store.items.count))")

                    ForEach(AccountCategory.allCases) { cat in
                        let cnt = store.items.filter { $0.category == cat }.count
                        if cnt > 0 {
                            categoryChip(cat, label: "\(cat.rawValue) (\(cnt))")
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))

            Divider()

            if let toast = store.clipboardStatusMessage {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                    Text(toast)
                        .font(.system(size: 10.5, weight: .medium))
                }
                .foregroundColor(.green)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(Color.green.opacity(0.12))
            }

            if filtered.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("无匹配账号")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { item in
                            menuBarItemRow(item: item)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
    }

    private func categoryChip(_ cat: AccountCategory?, label: String) -> some View {
        let isSelected = (vm.selectedCategory == cat)
        let tint = cat?.tintColor ?? .blue

        return Button(action: {
            vm.selectedCategory = cat
        }) {
            HStack(spacing: 3) {
                if let cat = cat {
                    Image(systemName: cat.iconName)
                        .font(.system(size: 9))
                }
                Text(label)
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium))
            }
            .foregroundColor(isSelected ? .white : .primary.opacity(0.85))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(isSelected ? tint : Color.secondary.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }

    private func menuBarItemRow(item: AccountItem) -> some View {
        HStack(spacing: 8) {
            // 3D 玻璃质感账号图标
            AccountAvatarView(item: item, size: 26, showFavoriteBadge: false)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)

                    Text(item.category.rawValue)
                        .font(.system(size: 8.5))
                        .foregroundColor(item.category.tintColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(item.category.tintColor.opacity(0.12)))
                }

                if !item.username.isEmpty {
                    Text(item.username)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if !item.password.isEmpty {
                Button(action: {
                    store.copyToClipboard(text: item.password, label: "密码：\(item.password)")
                }) {
                    Text("密码")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("复制 密码：\(item.password)")
            }

            if item.hasTOTP {
                Button(action: {
                    store.copyToClipboard(text: store.code(for: item), label: "2FA：\(store.code(for: item))")
                }) {
                    Text(store.code(for: item))
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .help("复制 2FA：\(store.code(for: item))")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}
