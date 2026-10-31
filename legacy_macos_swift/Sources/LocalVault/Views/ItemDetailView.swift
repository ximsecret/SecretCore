import SwiftUI
import AppKit

@MainActor
public final class ItemDetailViewModel: ObservableObject {
    @Published public var showDeleteConfirm: Bool = false
    @Published public var isQuickAddExpanded: Bool = false
    @Published public var quickAddRawInput: String = ""
    @Published public var lockedPasswordForQuickAdd: String? = nil
    @Published public var lastCopiedKey: String? = nil

    // 账号与 2FA 实时搜索关键词
    @Published public var accountSearchText: String = ""

    // 密码组折叠状态：存储已折叠的 groupKey
    @Published public var collapsedGroupKeys: Set<String> = []

    // 内联编辑某个密码组的密码（保留备用）
    @Published public var editingGroupPasswordOriginal: String? = nil
    @Published public var editingGroupPasswordNew: String = ""

    private var copyFeedbackTask: Task<Void, Never>? = nil

    public init() {}

    public func resetForNewItem() {
        showDeleteConfirm = false
        isQuickAddExpanded = false
        quickAddRawInput = ""
        lockedPasswordForQuickAdd = nil
        editingGroupPasswordOriginal = nil
        editingGroupPasswordNew = ""
        accountSearchText = ""
        collapsedGroupKeys.removeAll()
    }

    public func triggerCopyFeedback(key: String) {
        lastCopiedKey = key
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if !Task.isCancelled && self.lastCopiedKey == key {
                self.lastCopiedKey = nil
            }
        }
    }

    public func activateQuickAdd(lockedPassword: String? = nil) {
        self.lockedPasswordForQuickAdd = lockedPassword
        self.isQuickAddExpanded = true
    }

    public func toggleGroupCollapsed(key: String) {
        if collapsedGroupKeys.contains(key) {
            collapsedGroupKeys.remove(key)
        } else {
            collapsedGroupKeys.insert(key)
        }
    }

    public func isGroupCollapsed(key: String) -> Bool {
        collapsedGroupKeys.contains(key)
    }

    public func toggleAllGroups(groups: [PasswordCredentialGroup]) {
        let allKeys = groups.enumerated().map { i, g in
            g.password.isEmpty ? "empty_group_\(i)" : g.password
        }
        if collapsedGroupKeys.count >= allKeys.count {
            collapsedGroupKeys.removeAll()
        } else {
            collapsedGroupKeys = Set(allKeys)
        }
    }
}

public struct ItemDetailView: View {
    @EnvironmentObject private var store: VaultStore
    @StateObject private var vm = ItemDetailViewModel()
    public let item: AccountItem
    public var onEdit: (AccountItem) -> Void

    public init(item: AccountItem, onEdit: @escaping (AccountItem) -> Void) {
        self.item = item
        self.onEdit = onEdit
    }

    // 根据账号搜索词动态过滤密码组与下辖账号
    private var filteredPasswordGroups: [PasswordCredentialGroup] {
        let query = vm.accountSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return item.passwordGroups
        }

        var result: [PasswordCredentialGroup] = []
        for group in item.passwordGroups {
            let pwdMatches = group.password.lowercased().contains(query)
            let matchingEntries = group.entries.filter { entry in
                entry.username.lowercased().contains(query) ||
                entry.notes.lowercased().contains(query) ||
                entry.totpSecret.lowercased().contains(query) ||
                store.code(for: entry).contains(query)
            }

            if pwdMatches {
                result.append(group)
            } else if !matchingEntries.isEmpty {
                result.append(PasswordCredentialGroup(password: group.password, entries: matchingEntries))
            }
        }
        return result
    }

    private var matchingAccountsCount: Int {
        filteredPasswordGroups.reduce(0) { $0 + $1.accountCount }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 1. 顶部服务品牌卡片（Cyber Mission Control · 极光仪表盘，集成放大版官网卡片与账号搜索）
                headerHeroCard

                // 2. 内联快速追加子账号/新密码面板（支持同名称下随时追加）
                quickAddCredentialPanel

                // 3. 按密码聚合分组的核心凭据矩阵（密码框与账号框像素级对齐，单行折叠无多余横条）
                passwordGroupsSection

                // 4. 扩展自定义字段（全明文 + 点击即复制）
                if !item.customFields.isEmpty {
                    customFieldsSection
                }

                // 5. 安全备注与说明
                if !item.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !item.noteEntries.isEmpty {
                    notesSection
                }

                // 6. 底部时间戳
                footerSection
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onChange(of: item.id) { _ in
            vm.resetForNewItem()
        }
        .alert("确认删除该服务及其下属全部账号？", isPresented: $vm.showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("永久删除", role: .destructive) {
                store.deleteItem(id: item.id)
            }
        } message: {
            Text("删除「\(item.title)」后，其包含的 \(item.passwordGroups.count) 套密码与 \(item.entries.count) 个账号记录将从本地彻底移除。")
        }
    }

    // MARK: - 1. 顶部 Hero 卡片（Cyber Mission Control · 极光仪表盘）
    private var headerHeroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // ── 第一行：服务头像、标题、安全态势微标、分类及操作按钮 ──
            HStack(spacing: 16) {
                AccountAvatarView(item: item, size: 58, showFavoriteBadge: false)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(item.title)
                            .font(.system(size: 23, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)

                        if item.isFavorite {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                                .font(.system(size: 14))
                        }

                        // 密码组数与子账号数统计徽章
                        HStack(spacing: 4) {
                            Image(systemName: "square.stack.3d.up.fill")
                                .font(.system(size: 10))
                            Text("\(item.passwordGroups.count) 套密码 · \(item.entries.count) 个账号")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(Color(red: 0.05, green: 0.48, blue: 0.92))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3.5)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.05, green: 0.48, blue: 0.92).opacity(0.12))
                        )

                    }

                    // 所属分类切换菜单与安全态势
                    HStack(spacing: 8) {
                        Menu {
                            Text("切换所属分类")
                            Divider()
                            ForEach(AccountCategory.allCases) { cat in
                                Button(action: {
                                    store.updateCategory(id: item.id, category: cat)
                                }) {
                                    Label(cat.rawValue, systemImage: cat.iconName)
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: item.category.iconName)
                                    .font(.system(size: 10, weight: .semibold))
                                Text(item.category.rawValue)
                                    .font(.system(size: 11, weight: .semibold))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .foregroundColor(item.category.tintColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(item.category.tintColor.opacity(0.14))
                            .cornerRadius(8)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()

                        // 科技安全态势指示徽章（发光绿点 + 本地隔离）
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                                .shadow(color: Color.green.opacity(0.8), radius: 3, x: 0, y: 0)
                            Text("本地物理沙箱 · AES-256 GCM 隔离保护")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(Capsule().fill(Color.green.opacity(0.08)))
                        .overlay(Capsule().strokeBorder(Color.green.opacity(0.20), lineWidth: 0.8))
                    }
                }

                Spacer()

                // 右侧快捷操作按钮组
                HStack(spacing: 8) {
                    Button(action: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                            if vm.isQuickAddExpanded && vm.lockedPasswordForQuickAdd == nil {
                                vm.isQuickAddExpanded = false
                            } else {
                                vm.activateQuickAdd(lockedPassword: nil)
                            }
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text("追加账号/密码")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.05, green: 0.52, blue: 0.98), Color(red: 0.22, green: 0.36, blue: 0.95)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("在「\(item.title)」下快速追加新密码或新账号")

                    Button(action: {
                        store.toggleFavorite(id: item.id)
                    }) {
                        Image(systemName: item.isFavorite ? "star.fill" : "star")
                            .foregroundColor(item.isFavorite ? .yellow : .secondary)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.bordered)
                    .help(item.isFavorite ? "取消收藏" : "加入收藏")

                    Button(action: {
                        onEdit(item)
                    }) {
                        Label("管理", systemImage: "slider.horizontal.3")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive, action: {
                        vm.showDeleteConfirm = true
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.bordered)
                    .help("删除整个服务记录")
                }
            }

            // ── 第二行：放大版官方网址卡片（若未配置则不显示） ──
            let cleanUrl = item.url.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanUrl.isEmpty {
                enlargedWebsiteBar(cleanUrl: cleanUrl)
            }

            // ── 第三行：当前条目账号与 2FA 实时搜索栏 ──
            accountSearchBar
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            item.category.tintColor.opacity(0.12),
                            Color.blue.opacity(0.04),
                            Color(NSColor.controlBackgroundColor)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            item.category.tintColor.opacity(0.35),
                            Color.blue.opacity(0.20),
                            Color.cyan.opacity(0.30)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: item.category.tintColor.opacity(0.05), radius: 10, x: 0, y: 3)
    }

    // MARK: - 放大版关联网站中枢卡片（15pt 等宽主域名 + 复制网址 + 直达官网）
    private func enlargedWebsiteBar(cleanUrl: String) -> some View {
        let isUrlCopied = (vm.lastCopiedKey == "header_url")

        return HStack(spacing: 12) {
            // 网站地球微光图标
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.05, green: 0.52, blue: 0.98).opacity(isUrlCopied ? 0.25 : 0.15),
                                Color(red: 0.12, green: 0.75, blue: 0.92).opacity(isUrlCopied ? 0.35 : 0.20)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)

                Image(systemName: isUrlCopied ? "checkmark.circle.fill" : "globe.asia.australia.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(isUrlCopied ? .green : Color(red: 0.05, green: 0.52, blue: 0.98))
            }

            // 放大版域名与说明
            VStack(alignment: .leading, spacing: 2) {
                Text(cleanUrl)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(isUrlCopied ? .green : .primary)
                    .lineLimit(1)

                Text("官方关联服务站点 · 点击右侧直接复制或直达")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary.opacity(0.85))
            }

            Spacer(minLength: 8)

            // 复制网址胶囊按钮
            Button(action: {
                copyWithFeedback(text: cleanUrl, label: "网址：\(cleanUrl)", key: "header_url")
            }) {
                HStack(spacing: 5) {
                    Image(systemName: isUrlCopied ? "checkmark" : "doc.on.doc.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(isUrlCopied ? "已复制" : "复制网址")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(isUrlCopied ? .white : Color(red: 0.05, green: 0.48, blue: 0.95))
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isUrlCopied ? Color.green : Color.blue.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
            .help("点击直接复制网址：\(cleanUrl)")

            // 直达官网按钮
            if let validURL = normalizedWebURL(from: cleanUrl) {
                Button(action: {
                    NSWorkspace.shared.open(validURL)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "safari.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("直达官网")
                            .font(.system(size: 12, weight: .bold))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.08, green: 0.56, blue: 0.98),
                                Color(red: 0.18, green: 0.38, blue: 0.94)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("在默认浏览器中打开：\(cleanUrl)")
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(NSColor.textBackgroundColor).opacity(0.90),
                            Color.blue.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isUrlCopied ? Color.green.opacity(0.4) : Color.blue.opacity(0.20),
                    lineWidth: 1
                )
        )
    }

    // MARK: - 账号与 2FA 实时搜索栏
    private var accountSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(vm.accountSearchText.isEmpty ? .secondary : Color(red: 0.05, green: 0.52, blue: 0.98))

            TextField("搜索当前条目的账号、备注或 2FA...", text: $vm.accountSearchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, weight: .medium, design: .rounded))

            if !vm.accountSearchText.isEmpty {
                // 实时匹配统计徽章
                Text("\(matchingAccountsCount)/\(item.entries.count) 匹配")
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.05, green: 0.50, blue: 0.95))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(Color.blue.opacity(0.12)))

                Button(action: {
                    vm.accountSearchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(NSColor.textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    vm.accountSearchText.isEmpty
                        ? Color.primary.opacity(0.10)
                        : Color.blue.opacity(0.45),
                    lineWidth: 1
                )
        )
    }

    // MARK: - 2. 内联快速追加子账号/新密码面板
    private var quickAddCredentialPanel: some View {
        Group {
            if vm.isQuickAddExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .foregroundColor(.blue)
                            .font(.system(size: 13, weight: .bold))

                        if let lockedPass = vm.lockedPasswordForQuickAdd {
                            Text("在密码「\(lockedPass.isEmpty ? "无密码" : lockedPass)」下追加：账号：xxx   2FA：xxxx")
                                .font(.system(size: 12.5, weight: .bold))
                                .foregroundColor(Color(red: 0.05, green: 0.45, blue: 0.90))

                            Button("切换为新密码模式") {
                                vm.lockedPasswordForQuickAdd = nil
                            }
                            .font(.system(size: 11))
                            .buttonStyle(.link)
                        } else {
                            Text("在「\(item.title)」下快速追加：密码：xxx   账号：xxx   2FA：xxxx")
                                .font(.system(size: 12.5, weight: .bold))
                        }

                        Spacer()

                        Button(action: handlePasteAndQuickAdd) {
                            Label("粘贴剪贴板直接追加", systemImage: "doc.on.clipboard")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                vm.isQuickAddExpanded = false
                                vm.lockedPasswordForQuickAdd = nil
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 10) {
                        TextField(
                            vm.lockedPasswordForQuickAdd != nil
                                ? "提示格式：账号：xxx   2FA：xxxx   （密码已自动关联当前组）"
                                : "提示格式：密码：xxx   账号：xxx   2FA：xxxx   （自动按密码归组）",
                            text: $vm.quickAddRawInput
                        )
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(NSColor.textBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.blue.opacity(0.35), lineWidth: 1.2)
                        )
                        .onSubmit {
                            handleQuickAddSubmit()
                        }

                        Button(action: {
                            handleQuickAddSubmit()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 12, weight: .bold))
                                Text("立即追加")
                                    .font(.system(size: 12.5, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 0.05, green: 0.52, blue: 0.98), Color(red: 0.22, green: 0.36, blue: 0.95)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(vm.quickAddRawInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    Text("提示：可一次性粘贴多行。系统自动识别每行中的账号、密码、2FA 密钥或动态码，按相同密码智能归并到同一卡片。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.blue.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.blue.opacity(0.25), lineWidth: 1)
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - 3. 按密码聚合的核心组视图（支持密码组展开与关闭，彻底删除原折叠横条）
    private var passwordGroupsSection: some View {
        let groups = filteredPasswordGroups
        let isSearching = !vm.accountSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return VStack(alignment: .leading, spacing: 14) {
            // 当存在多个密码组或处于搜索状态时，提供说明与一键全部展开/全部收起
            if groups.count > 1 || isSearching {
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "square.stack.3d.down.right.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.blue)
                        if isSearching {
                            Text("搜索过滤：匹配到 \(matchingAccountsCount) 个账号（分布在 \(groups.count) 个密码组）")
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundColor(.primary)
                        } else {
                            Text("共 \(groups.count) 个密码组")
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    if !groups.isEmpty {
                        let allCollapsed = groups.enumerated().allSatisfy { i, g in
                            vm.isGroupCollapsed(key: g.password.isEmpty ? "empty_group_\(i)" : g.password)
                        }

                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                vm.toggleAllGroups(groups: groups)
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: allCollapsed ? "chevron.down" : "chevron.up")
                                    .font(.system(size: 10, weight: .bold))
                                Text(allCollapsed ? "全部展开" : "全部收起")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(Color(red: 0.05, green: 0.48, blue: 0.94))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.blue.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }

            if groups.isEmpty && isSearching {
                // 搜索无结果科技占位
                VStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("未匹配到包含「\(vm.accountSearchText)」的账号或 2FA")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                    Button("清空搜索条件") {
                        vm.accountSearchText = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
            } else {
                ForEach(Array(groups.enumerated()), id: \.element.id) { groupIndex, group in
                    passwordGroupCard(group: group, groupIndex: groupIndex, totalGroups: groups.count)
                }
            }
        }
    }

    private func passwordGroupCard(group: PasswordCredentialGroup, groupIndex: Int, totalGroups: Int) -> some View {
        let groupKey = group.password.isEmpty ? "empty_group_\(groupIndex)" : group.password
        let isCollapsed = vm.isGroupCollapsed(key: groupKey)
        let pwdCopyKey = "pwd_group_\(groupIndex)"
        let isPwdCopied = (vm.lastCopiedKey == pwdCopyKey)
        let eval = group.strength

        return VStack(alignment: .leading, spacing: 0) {
            // ── A. 顶部密码组状态微型控制台 ──
            passwordGroupHeader(
                group: group,
                groupIndex: groupIndex,
                groupKey: groupKey,
                isCollapsed: isCollapsed,
                totalGroups: totalGroups
            )

            // ── B. 密码行（与账号行左右列完全对齐：左列密码主框，右列 260pt 密码安全评级卡片） ──
            passwordMainRow(
                group: group,
                pwdCopyKey: pwdCopyKey,
                isPwdCopied: isPwdCopied,
                eval: eval
            )

            // ── C. 该密码下挂载的所有账号与对应 2FA 列表（支持展开与折叠；收起时干净利落，无多余占位条） ──
            if !isCollapsed {
                Divider()
                    .opacity(0.5)

                VStack(spacing: 0) {
                    ForEach(Array(group.entries.enumerated()), id: \.element.id) { entryIndex, entry in
                        subAccountAnd2FARow(
                            entry: entry,
                            entryIndex: entryIndex,
                            totalEntriesInItem: item.entries.count
                        )

                        if entryIndex < group.entries.count - 1 {
                            Divider()
                                .padding(.horizontal, 14)
                                .opacity(0.4)
                        }
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.65))
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.30),
                            Color.cyan.opacity(0.20),
                            Color.blue.opacity(0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
    }

    // MARK: - 密码组顶部控制条
    private func passwordGroupHeader(
        group: PasswordCredentialGroup,
        groupIndex: Int,
        groupKey: String,
        isCollapsed: Bool,
        totalGroups: Int
    ) -> some View {
        HStack(spacing: 8) {
            // 展开 / 折叠密码组按钮（置于密码组最左侧）
            Button(action: {
                withAnimation(.easeInOut(duration: 0.22)) {
                    vm.toggleGroupCollapsed(key: groupKey)
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                    Text(isCollapsed ? "展开" : "收起")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(isCollapsed ? Color(red: 0.05, green: 0.48, blue: 0.94) : .secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(isCollapsed ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.10))
                )
            }
            .buttonStyle(.plain)
            .help(isCollapsed ? "展开此密码组下的全部账号与 2FA" : "收起此密码组下的全部账号与 2FA")

            // 密码组序号徽章
            HStack(spacing: 4) {
                Image(systemName: "key.fill")
                    .font(.system(size: 10, weight: .bold))
                Text(totalGroups > 1 ? "密码组 #\(groupIndex + 1)" : "登录密码")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 3.5)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.05, green: 0.50, blue: 0.96),
                                Color(red: 0.20, green: 0.36, blue: 0.92)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )

            // 包含账号数量
            Text("下辖 \(group.accountCount) 个账号")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(red: 0.15, green: 0.45, blue: 0.85))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.blue.opacity(0.10))
                )

            Spacer()

            // 在当前密码组下快速追加账号按钮（位于右侧操作区）
            Button(action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                    vm.activateQuickAdd(lockedPassword: group.password)
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text("同密码加账号")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(Color(red: 0.05, green: 0.48, blue: 0.94))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.blue.opacity(0.10))
                )
            }
            .buttonStyle(.plain)
            .help("使用当前相同密码，快速新增一个关联账号与 2FA")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - 密码完整行（左列密码主框，右列 260pt 密码安全评级卡片）
    private func passwordMainRow(
        group: PasswordCredentialGroup,
        pwdCopyKey: String,
        isPwdCopied: Bool,
        eval: (strength: PasswordStrength, entropyBits: Int)
    ) -> some View {
        HStack(spacing: 12) {
            // 左列：密码凭据主框 (Flex 宽度，与账号主框完全等宽等高对齐)
            passwordMainBox(group: group, pwdCopyKey: pwdCopyKey, isPwdCopied: isPwdCopied)

            // 右列：密码安全评级与熵值卡片 (固定宽度 260pt，高度 50pt，与 2FA 动态码卡片完全对称)
            passwordStrengthCard(eval: eval)

        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    // MARK: - 密码凭据主框
    private func passwordMainBox(
        group: PasswordCredentialGroup,
        pwdCopyKey: String,
        isPwdCopied: Bool
    ) -> some View {
        Button(action: {
            guard !group.password.isEmpty else { return }
            copyWithFeedback(
                text: group.password,
                label: "\(group.effectivePasswordLabel)：\(group.password)",
                key: pwdCopyKey
            )
        }) {
            HStack(spacing: 10) {
                // 32×32 图标胶囊
                ZStack {
                    Circle()
                        .fill(isPwdCopied ? Color.green.opacity(0.16) : Color(red: 0.95, green: 0.55, blue: 0.12).opacity(0.14))
                        .frame(width: 32, height: 32)
                    Image(systemName: isPwdCopied ? "checkmark" : "key.fill")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(isPwdCopied ? .green : Color(red: 0.95, green: 0.55, blue: 0.12))
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text("\(group.effectivePasswordLabel)：")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(red: 0.90, green: 0.50, blue: 0.10))

                        Text(group.password.isEmpty ? "（未设置密码）" : group.password)
                            .font(.system(size: 13.5, weight: .bold, design: .monospaced))
                            .foregroundColor(group.password.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 6)

                if !group.password.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: isPwdCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9.5, weight: .bold))
                        Text(isPwdCopied ? "已复制" : "复制")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .foregroundColor(isPwdCopied ? .green : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(isPwdCopied ? Color.green.opacity(0.14) : Color.secondary.opacity(0.10))
                    )
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isPwdCopied
                            ? Color.green.opacity(0.08)
                            : Color(NSColor.textBackgroundColor)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isPwdCopied ? Color.green.opacity(0.45) : Color.blue.opacity(0.20),
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("点击直接复制\(group.effectivePasswordLabel)：\(group.password)")
        .contextMenu {
            Button("复制\(group.effectivePasswordLabel)") {
                copyWithFeedback(
                    text: group.password,
                    label: "\(group.effectivePasswordLabel)：\(group.password)",
                    key: pwdCopyKey
                )
            }
        }
    }

    // MARK: - 密码安全评级卡片
    private func passwordStrengthCard(eval: (strength: PasswordStrength, entropyBits: Int)) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 13.5, weight: .bold))
                .foregroundColor(strengthColor(eval.strength))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("安全评级：")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(eval.strength.label)
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundColor(strengthColor(eval.strength))
                }

                Text("\(eval.entropyBits) bit 熵值 · 内存沙箱加密")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.85))
            }

            Spacer(minLength: 4)

            // 4 格强度进度指示条
            HStack(spacing: 3) {
                ForEach(0..<4) { idx in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(idx < strengthLevel(eval.strength) ? strengthColor(eval.strength) : Color.secondary.opacity(0.2))
                        .frame(width: 8, height: 12)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(width: 260, height: 50, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(NSColor.textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.blue.opacity(0.20), lineWidth: 1)
        )
    }

    // MARK: - 单个子账号 + 对应 2FA 行（统一提示格式：账号：xxx / 2FA：xxx，与密码行严格对齐）
    private func subAccountAnd2FARow(entry: CredentialEntry, entryIndex: Int, totalEntriesInItem: Int) -> some View {
        let userCopyKey = "user_\(entry.id.uuidString)"
        let tfaCopyKey = "tfa_\(entry.id.uuidString)"
        let isUserCopied = (vm.lastCopiedKey == userCopyKey)
        let isTFACopied = (vm.lastCopiedKey == tfaCopyKey)

        return VStack(spacing: 8) {
            HStack(spacing: 12) {
                // 1. 左列：账号区块（统一提示：账号：xxx，整块点击直接复制账号，与密码框严格等宽等高）
                accountMainBox(entry: entry, userCopyKey: userCopyKey, isUserCopied: isUserCopied, totalEntriesInItem: totalEntriesInItem)

                // 2. 右列：对应的 2FA 动态码区块（统一提示：2FA：xxx，固定宽度 260pt，高度 50pt，背景全高充满进度条）
                accountTOTPCard(entry: entry, tfaCopyKey: tfaCopyKey, isTFACopied: isTFACopied)
            }

            // 3. 从属额外密码（如资金密码、支付密码、API Key 等，明文显示，点击直接复制，右列保持 260pt 对齐）
            ForEach(entry.extraPasswords) { extra in
                extraPasswordRow(entry: entry, extra: extra)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - 账号凭据主框
    private func accountMainBox(
        entry: CredentialEntry,
        userCopyKey: String,
        isUserCopied: Bool,
        totalEntriesInItem: Int
    ) -> some View {
        Button(action: {
            guard !entry.username.isEmpty else { return }
            copyWithFeedback(
                text: entry.username,
                label: "\(entry.effectiveAccountLabel)：\(entry.username)",
                key: userCopyKey
            )
        }) {
            HStack(spacing: 10) {
                // 32×32 图标胶囊
                ZStack {
                    Circle()
                        .fill(isUserCopied ? Color.green.opacity(0.16) : item.category.tintColor.opacity(0.14))
                        .frame(width: 32, height: 32)
                    Image(systemName: isUserCopied ? "checkmark" : "person.fill")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(isUserCopied ? .green : item.category.tintColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text("\(entry.effectiveAccountLabel)：")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(item.category.tintColor)

                        Text(entry.username.isEmpty ? "（未填写账号）" : entry.username)
                            .font(.system(size: 13.5, weight: .bold, design: .monospaced))
                            .foregroundColor(entry.username.isEmpty ? .secondary : .primary)
                            .lineLimit(1)

                        if !entry.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(entry.notes)
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundColor(.teal)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.teal.opacity(0.12)))
                        }
                    }
                }

                Spacer(minLength: 6)

                if !entry.username.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: isUserCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9.5, weight: .bold))
                        Text(isUserCopied ? "已复制" : "复制")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .foregroundColor(isUserCopied ? .green : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(isUserCopied ? Color.green.opacity(0.14) : Color.secondary.opacity(0.10))
                    )
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isUserCopied
                            ? Color.green.opacity(0.08)
                            : Color(NSColor.textBackgroundColor)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isUserCopied ? Color.green.opacity(0.45) : Color.blue.opacity(0.20),
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("点击直接复制\(entry.effectiveAccountLabel)：\(entry.username)")
        .contextMenu {
            Button("复制\(entry.effectiveAccountLabel)") {
                copyWithFeedback(
                    text: entry.username,
                    label: "\(entry.effectiveAccountLabel)：\(entry.username)",
                    key: userCopyKey
                )
            }
            if totalEntriesInItem > 1 {
                Divider()
                Button(role: .destructive) {
                    store.removeEntry(fromItemId: item.id, entryId: entry.id)
                } label: {
                    Label("彻底删除此账号（不保留）", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - 账号对应 2FA 卡片
    private func accountTOTPCard(entry: CredentialEntry, tfaCopyKey: String, isTFACopied: Bool) -> some View {
        Group {
            if entry.hasTOTP {
                let rawCode = store.code(for: entry)
                let isStandardTOTP = (rawCode != "密钥错误" && rawCode != "------")
                let copyValue = isStandardTOTP ? rawCode : entry.totpSecret
                let isUrgent = isStandardTOTP && (store.remainingSeconds2FA <= 5)

                Button(action: {
                    copyWithFeedback(
                        text: copyValue,
                        label: "2FA：\(copyValue)",
                        key: tfaCopyKey
                    )
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: isTFACopied ? "checkmark.shield.fill" : "shield.lefthalf.filled.badge.checkmark")
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundColor(isTFACopied ? .green : (isUrgent ? .red : Color(red: 0.05, green: 0.65, blue: 0.48)))

                        HStack(spacing: 3) {
                            Text("2FA：")
                                .font(.system(size: 12.5, weight: .bold))
                                .foregroundColor(isUrgent ? .red : Color(red: 0.04, green: 0.55, blue: 0.38))

                            Text(isStandardTOTP ? store.formattedCode(for: entry) : entry.totpSecret)
                                .font(.system(size: isStandardTOTP ? 14.5 : 12, weight: .bold, design: .monospaced))
                                .foregroundColor(
                                    isTFACopied
                                        ? .green
                                        : (isUrgent ? .red : Color(red: 0.04, green: 0.48, blue: 0.92))
                                )
                                .lineLimit(1)
                        }

                        Spacer(minLength: 4)

                        // 倒计时秒数徽章
                        if isStandardTOTP {
                            Text("\(store.remainingSeconds2FA)s")
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .foregroundColor(isUrgent ? .red : Color(red: 0.12, green: 0.50, blue: 0.85))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2.5)
                                .background(
                                    Capsule()
                                        .fill((isUrgent ? Color.red : Color.blue).opacity(0.12))
                                )
                        }

                        // 复制胶囊按钮
                        HStack(spacing: 3) {
                            Image(systemName: isTFACopied ? "checkmark" : "doc.on.doc.fill")
                                .font(.system(size: 9.5, weight: .bold))
                            Text(isTFACopied ? "已复制" : "复制")
                                .font(.system(size: 10.5, weight: .bold))
                        }
                        .foregroundColor(isTFACopied ? .white : (isUrgent ? .red : Color(red: 0.04, green: 0.48, blue: 0.92)))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(isTFACopied ? Color.green : (isUrgent ? Color.red.opacity(0.12) : Color.blue.opacity(0.12)))
                        )
                    }
                    .padding(.horizontal, 12)
                    .frame(width: 260, height: 50)
                    .background(
                        GeometryReader { geo in
                            let progressRatio = isStandardTOTP ? max(0.0, min(1.0, CGFloat(store.progress2FA))) : 1.0
                            let progressWidth = geo.size.width * progressRatio

                            ZStack(alignment: .leading) {
                                // 1. 底层背景容器
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(
                                        isTFACopied
                                            ? Color.green.opacity(0.10)
                                            : (isUrgent
                                                ? Color.red.opacity(0.06)
                                                : Color(NSColor.textBackgroundColor))
                                    )

                                // 2. 整个进度条将 2FA 标签页填满（全高充满 100%，宽度随倒计时平滑推进）
                                if isStandardTOTP {
                                    Rectangle()
                                        .fill(
                                            isTFACopied
                                                ? LinearGradient(
                                                    colors: [Color.green.opacity(0.24), Color.green.opacity(0.32)],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                                : (isUrgent
                                                    ? LinearGradient(
                                                        colors: [
                                                            Color(red: 1.0, green: 0.55, blue: 0.15).opacity(0.32),
                                                            Color(red: 0.95, green: 0.22, blue: 0.22).opacity(0.40)
                                                        ],
                                                        startPoint: .leading,
                                                        endPoint: .trailing
                                                    )
                                                    : LinearGradient(
                                                        colors: [
                                                            Color(red: 0.04, green: 0.72, blue: 0.52).opacity(0.22),
                                                            Color(red: 0.05, green: 0.52, blue: 0.95).opacity(0.28)
                                                        ],
                                                        startPoint: .leading,
                                                        endPoint: .trailing
                                                    ))
                                        )
                                        .frame(width: progressWidth, height: geo.size.height)
                                        .animation(.linear(duration: 0.25), value: store.progress2FA)
                                }
                            }
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                isTFACopied
                                    ? Color.green.opacity(0.55)
                                    : (isUrgent ? Color.red.opacity(0.40) : Color.blue.opacity(0.20)),
                                lineWidth: 1
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("点击直接复制 2FA：\(copyValue)")
                .contextMenu {
                    Button("复制 2FA 动态码") {
                        copyWithFeedback(
                            text: copyValue,
                            label: "2FA：\(copyValue)",
                            key: tfaCopyKey
                        )
                    }
                    Divider()
                    Button(role: .destructive) {
                        store.clearEntryTOTP(itemId: item.id, entryId: entry.id)
                    } label: {
                        Label("彻底删除并清空此 2FA（不保留）", systemImage: "trash")
                    }
                }

            } else {
                // 未配置 2FA 时的统一 260pt 轻量占位卡片 (保证宽度绝对守恒与对齐！)
                HStack(spacing: 6) {
                    Image(systemName: "shield.slash")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("2FA：未配置动态口令")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.65))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(width: 260, height: 50, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(NSColor.textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.blue.opacity(0.20), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - 4. 扩展自定义字段（全明文 + 点击即复制）
    private var customFieldsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.rectangle.portrait.fill")
                    .foregroundColor(item.category.tintColor)
                Text("扩展自定义字段（明文直显 · 点击即复制）")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(Array(item.customFields.enumerated()), id: \.element.id) { index, field in
                    let fKey = "custom_\(field.id.uuidString)"
                    let isCopied = (vm.lastCopiedKey == fKey)

                    Button(action: {
                        copyWithFeedback(text: field.value, label: "\(field.label)：\(field.value)", key: fKey)
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(field.label)：")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Text(field.value)
                                    .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.primary)
                            }
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 11))
                                Text(isCopied ? "已复制" : "点击复制")
                                    .font(.system(size: 11.5, weight: .semibold))
                            }
                            .foregroundColor(isCopied ? .green : .secondary)
                        }
                        .padding(14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < item.customFields.count - 1 {
                        Divider()
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
            )
        }
    }

    // MARK: - 从属额外密码行（资金密码、支付密码、API Key 等，明文展示，点击复制，右列 260pt 对齐）
    private func extraPasswordRow(entry: CredentialEntry, extra: LabeledPassword) -> some View {
        let copyKey = "extra_\(extra.id.uuidString)"
        let isCopied = (vm.lastCopiedKey == copyKey)

        return HStack(spacing: 12) {
            // 左列：额外密码主框（与账号框/密码框严格等宽等高）
            Button(action: {
                guard !extra.value.isEmpty else { return }
                copyWithFeedback(
                    text: extra.value,
                    label: "\(extra.effectiveLabel)：\(extra.value)",
                    key: copyKey
                )
            }) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(isCopied ? Color.green.opacity(0.16) : Color.purple.opacity(0.14))
                            .frame(width: 32, height: 32)
                        Image(systemName: isCopied ? "checkmark" : "key.badge.ellipsis")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(isCopied ? .green : .purple)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Text("\(extra.effectiveLabel)：")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.purple)

                            Text(extra.value.isEmpty ? "（未设置）" : extra.value)
                                .font(.system(size: 13.5, weight: .bold, design: .monospaced))
                                .foregroundColor(extra.value.isEmpty ? .secondary : .primary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 6)

                    if !extra.value.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10.5))
                            Text(isCopied ? "已复制" : "复制")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(isCopied ? .green : .secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(
                            Capsule()
                                .fill(isCopied ? Color.green.opacity(0.12) : Color.secondary.opacity(0.08))
                        )
                    }
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 50)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isCopied ? Color.green.opacity(0.4) : Color.purple.opacity(0.25), lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("点击直接复制\(extra.effectiveLabel)：\(extra.value)")
            .contextMenu {
                Button("复制\(extra.effectiveLabel)") {
                    copyWithFeedback(
                        text: extra.value,
                        label: "\(extra.effectiveLabel)：\(extra.value)",
                        key: copyKey
                    )
                }
                Divider()
                Button(role: .destructive) {
                    store.removeExtraPassword(fromItemId: item.id, entryId: entry.id, extraId: extra.id)
                } label: {
                    Label("彻底删除此\(extra.effectiveLabel)（不保留）", systemImage: "trash")
                }
            }

            // 右列：保持 260pt 对齐的占位说明卡片
            HStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.7))
                Text("从属二级凭据 · 独立密级")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(width: 260, height: 50)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.45))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundColor(Color.secondary.opacity(0.18))
            )
        }
    }


    // MARK: - 5. 安全多备注（支持一行一条/一行两条自由切换，点击复制）
    private var notesSection: some View {
        let noteEntries = item.effectiveNoteEntries
        guard !noteEntries.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.fill")
                        .foregroundColor(item.category.tintColor)
                    Text("安全备注 / 备用信息（点击直接复制）")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)

                    Spacer()

                    // 排版切换器：一行单条 vs 一行两条
                    HStack(spacing: 2) {
                        Button(action: {
                            store.updateNotesLayout(itemId: item.id, layout: .single)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "rectangle.grid.1x2.fill")
                                    .font(.system(size: 10))
                                Text("一行单条")
                                    .font(.system(size: 10.5, weight: .medium))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(
                                Capsule()
                                    .fill(item.effectiveNotesLayout == .single ? item.category.tintColor.opacity(0.18) : Color.clear)
                            )
                            .foregroundColor(item.effectiveNotesLayout == .single ? item.category.tintColor : .secondary)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            store.updateNotesLayout(itemId: item.id, layout: .double)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "square.grid.2x2.fill")
                                    .font(.system(size: 10))
                                Text("一行两条")
                                    .font(.system(size: 10.5, weight: .medium))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(
                                Capsule()
                                    .fill(item.effectiveNotesLayout == .double ? item.category.tintColor.opacity(0.18) : Color.clear)
                            )
                            .foregroundColor(item.effectiveNotesLayout == .double ? item.category.tintColor : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(2)
                    .background(Capsule().fill(Color(NSColor.controlBackgroundColor)))
                    .overlay(Capsule().stroke(Color.secondary.opacity(0.18), lineWidth: 0.8))
                }

                if item.effectiveNotesLayout == .double {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(noteEntries) { entry in
                            singleNoteCard(entry: entry)
                        }
                    }
                } else {
                    VStack(spacing: 8) {
                        ForEach(noteEntries) { entry in
                            singleNoteCard(entry: entry)
                        }
                    }
                }
            }
        )
    }

    private func singleNoteCard(entry: NoteEntry) -> some View {
        let copyKey = "note_\(entry.id.uuidString)"
        let isCopied = (vm.lastCopiedKey == copyKey)

        return Button(action: {
            copyWithFeedback(
                text: entry.content,
                label: "\(entry.effectiveLabel)：\(entry.content)",
                key: copyKey
            )
        }) {
            HStack(alignment: .top, spacing: 8) {
                Text("\(entry.effectiveLabel)：")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(item.category.tintColor)

                Text(entry.content)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .lineSpacing(3)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 6)

                HStack(spacing: 3) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                    Text(isCopied ? "已复制" : "复制")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .foregroundColor(isCopied ? .green : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(isCopied ? Color.green.opacity(0.12) : Color.secondary.opacity(0.08))
                )
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isCopied ? Color.green.opacity(0.4) : Color.secondary.opacity(0.16), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("复制\(entry.effectiveLabel)") {
                copyWithFeedback(
                    text: entry.content,
                    label: "\(entry.effectiveLabel)：\(entry.content)",
                    key: copyKey
                )
            }
            Divider()
            Button(role: .destructive) {
                store.removeNoteEntry(fromItemId: item.id, noteId: entry.id)
            } label: {
                Label("彻底删除此备注（不保留）", systemImage: "trash")
            }
        }
    }


    // MARK: - 6. 底部元数据
    private var footerSection: some View {
        HStack {
            Label("创建于 \(item.createdAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "calendar")
            Spacer()
            Label("更新于 \(item.updatedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock.arrow.circlepath")
        }
        .font(.system(size: 11))
        .foregroundColor(.secondary.opacity(0.8))
        .padding(.top, 6)
    }

    // MARK: - 内部辅助方法
    private func copyWithFeedback(text: String, label: String, key: String) {
        store.copyToClipboard(text: text, label: label)
        vm.triggerCopyFeedback(key: key)
    }

    private func handlePasteAndQuickAdd() {
        guard let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !clip.isEmpty else { return }
        vm.quickAddRawInput = clip
        handleQuickAddSubmit()
    }

    private func handleQuickAddSubmit() {
        let trimmed = vm.quickAddRawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let lines = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines {
            let newEntry = SmartCredentialParser.parseSubAccount(
                line,
                lockedPassword: vm.lockedPasswordForQuickAdd
            )
            store.appendEntry(toItemId: item.id, entry: newEntry)
        }

        vm.quickAddRawInput = ""
        store.showStatusToast("✨ 已在「\(item.title)」下追加 \(lines.count) 个账号并按密码自动归组")
    }

    private func normalizedWebURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return URL(string: trimmed)
        }
        return URL(string: "https://\(trimmed)")
    }

    private func strengthColor(_ strength: PasswordStrength) -> Color {
        switch strength {
        case .empty: return .gray
        case .weak: return .red
        case .fair: return .orange
        case .strong: return .green
        case .veryStrong: return Color(red: 0.05, green: 0.75, blue: 0.95)
        }
    }

    private func strengthLevel(_ strength: PasswordStrength) -> Int {
        switch strength {
        case .empty: return 0
        case .weak: return 1
        case .fair: return 2
        case .strong: return 3
        case .veryStrong: return 4
        }
    }
}
