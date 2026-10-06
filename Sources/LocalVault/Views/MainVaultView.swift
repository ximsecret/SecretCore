import SwiftUI

public final class MainVaultViewModel: ObservableObject {
    @Published public var showingAddSheet: Bool = false
    @Published public var itemToEdit: AccountItem? = nil
    @Published public var showingSettingsSheet: Bool = false
    @Published public var showingGeneratorSheet: Bool = false

    public init() {}
}

public struct MainVaultView: View {
    @EnvironmentObject private var store: VaultStore
    @StateObject private var vm = MainVaultViewModel()

    public init() {}

    private var activeDefaultCategory: AccountCategory {
        if case .category(let cat) = store.currentFilter {
            return cat
        }
        return .crypto
    }

    public var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 215, ideal: 235, max: 280)
        } content: {
            itemListView
                .navigationSplitViewColumnWidth(min: 310, ideal: 350, max: 440)
        } detail: {
            detailContentView
        }
        .sheet(isPresented: $vm.showingAddSheet) {
            ItemEditorSheet(editingItem: nil, defaultCategory: activeDefaultCategory)
        }
        .sheet(item: $vm.itemToEdit) { item in
            ItemEditorSheet(editingItem: item)
        }
        .sheet(isPresented: $vm.showingSettingsSheet) {
            SettingsSheet()
        }
        .sheet(isPresented: $vm.showingGeneratorSheet) {
            StandaloneGeneratorSheet()
        }
        .overlay(alignment: .bottom) {
            if let toast = store.clipboardStatusMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.green)
                    Text(toast)
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color.green.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 5)
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: store.clipboardStatusMessage)
    }

    // MARK: - 左侧导航侧边栏
    private var sidebarContent: some View {
        VStack(spacing: 0) {
            // 顶部品牌与全局 2FA 状态栏
            HStack(spacing: 10) {
                VaultBrandEmblemView(size: 36)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text("SecretCore")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        Text("极光秘核")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.cyan.opacity(0.15))
                            .foregroundColor(Color(red: 0.0, green: 0.52, blue: 0.90))
                            .cornerRadius(4)
                    }
                    Text("纯本地加密 · 零联网")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // 全局 2FA 刷新进度环
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.16), lineWidth: 2.5)
                        .frame(width: 28, height: 28)
                    Circle()
                        .trim(from: 0, to: store.progress2FA)
                        .stroke(
                            store.remainingSeconds2FA <= 5 ? Color.red : Color.blue,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 28, height: 28)
                        .animation(.linear(duration: 0.3), value: store.progress2FA)
                    Text("\(store.remainingSeconds2FA)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(store.remainingSeconds2FA <= 5 ? .red : .secondary)
                }
                .help("2FA 动态验证码全局倒计时 (\(store.remainingSeconds2FA) 秒)")
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider()
                .opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // 常用视图
                    VStack(alignment: .leading, spacing: 4) {
                        sidebarSectionHeader("快捷概览")
                        sidebarButton(filter: .all, subtitle: nil)
                        sidebarButton(filter: .favorites, subtitle: nil)
                        sidebarButton(filter: .has2FA, subtitle: nil)
                    }

                    // 分类目录
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            sidebarSectionHeader("按类型分类")
                            Spacer()
                            Text("\(AccountCategory.allCases.count) 类")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.7))
                                .padding(.trailing, 8)
                        }

                        ForEach(AccountCategory.allCases) { cat in
                            sidebarButton(filter: .category(cat), subtitle: cat.subtitle)
                        }
                    }

                    // 自定义标签
                    let tags = store.allCustomTags
                    if !tags.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            sidebarSectionHeader("自定义子标签")
                            ForEach(tags, id: \.self) { tag in
                                sidebarButton(filter: .tag(tag), subtitle: nil)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }

            Divider()
                .opacity(0.6)

            // 侧边栏底部工具栏
            HStack(spacing: 8) {
                Button(action: {
                    vm.showingGeneratorSheet = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 12, weight: .semibold))
                        Text("密码器")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(7)
                }
                .buttonStyle(.plain)
                .help("打开独立强密码生成器")

                Button(action: {
                    vm.showingSettingsSheet = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 12))
                        Text("设置")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(7)
                }
                .buttonStyle(.plain)
                .help("安全策略与加密备份设置")

                Spacer()

                Button(action: {
                    store.lock()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11))
                        Text("锁定")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(7)
                }
                .buttonStyle(.plain)
                .help("立即锁定保险箱并清空内存密钥")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func sidebarSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.secondary.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.bottom, 2)
    }

    private func sidebarButton(filter: SidebarFilter, subtitle: String?) -> some View {
        let isSelected = store.currentFilter == filter
        let count = store.count(for: filter)
        let tint = filter.tintColor

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                store.currentFilter = filter
                if let first = store.filteredItems.first {
                    store.selectedItemId = first.id
                }
            }
        }) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            isSelected
                                ? LinearGradient(colors: [tint, tint.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [tint.opacity(0.20), tint.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 26, height: 26)

                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.white.opacity(0.35) : tint.opacity(0.20),
                            lineWidth: 0.8
                        )
                        .frame(width: 26, height: 26)

                    Image(systemName: filter.iconName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isSelected ? .white : tint)
                        .shadow(color: isSelected ? Color.black.opacity(0.2) : Color.clear, radius: 1, x: 0, y: 1)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(filter.title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? .primary : .primary.opacity(0.88))
                        .lineLimit(1)

                    if let sub = subtitle, isSelected {
                        Text(sub)
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if count > 0 || isSelected {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(isSelected ? tint : .secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isSelected ? tint.opacity(0.18) : Color.secondary.opacity(0.1))
                        )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        isSelected
                            ? tint.opacity(0.14)
                            : Color.clear
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isSelected ? tint.opacity(0.35) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 中间账号列表栏
    private var itemListView: some View {
        VStack(spacing: 0) {
            // 顶部搜索与操作栏
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12, weight: .medium))

                        TextField("搜索标题、账号、网址、分类或 #标签...", text: $store.searchQuery)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))

                        if !store.searchQuery.isEmpty {
                            Button(action: {
                                store.searchQuery = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.secondary.opacity(0.1))
                    )

                    // 按类型分组展示开关
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            store.groupByCategory.toggle()
                        }
                    }) {
                        Image(systemName: store.groupByCategory ? "rectangle.grid.1x2.fill" : "list.bullet")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(store.groupByCategory ? .blue : .secondary)
                            .frame(width: 30, height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(store.groupByCategory ? Color.blue.opacity(0.14) : Color.secondary.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                    .help(store.groupByCategory ? "当前：按类型分组显示（点击切换为平铺列表）" : "当前：平铺列表显示（点击切换为按类型分组）")

                    // 粘贴即存按钮 (直接读取剪贴板智能解析入库)
                    Button(action: {
                        if !store.smartAddFromClipboard(defaultCategory: activeDefaultCategory) {
                            vm.showingAddSheet = true
                        }
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 11, weight: .bold))
                            Text("粘贴即存")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .foregroundColor(Color(red: 0.06, green: 0.44, blue: 0.88))
                        .padding(.horizontal, 8)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.blue.opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                    .help("一键读取剪贴板如「xxxx.com xxx账号 xxx密码 2fa(xxxx)」直接识别入库")

                    // 智能识别添加按钮
                    Button(action: {
                        vm.showingAddSheet = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .bold))
                            Text("智能添加")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.05, green: 0.52, blue: 0.98), Color(red: 0.22, green: 0.35, blue: 0.95)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("打开智能识别添加面板，支持任意文本一键自动拆解入库")
                }

                // 顶部水平快速类型筛选胶囊栏
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        quickFilterChip(filter: .all, label: "全部")
                        quickFilterChip(filter: .has2FA, label: "2FA 动态码")
                        quickFilterChip(filter: .favorites, label: "收藏")

                        Divider()
                            .frame(height: 14)
                            .padding(.horizontal, 2)

                        ForEach(AccountCategory.allCases) { cat in
                            quickFilterChip(filter: .category(cat), label: cat.rawValue)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

            Divider()

            // 列表主体
            let items = store.filteredItems
            if items.isEmpty {
                emptyListView
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if store.groupByCategory {
                            ForEach(store.itemsGroupedByCategory, id: \.category.id) { group in
                                categoryGroupSection(category: group.category, groupItems: group.items)
                            }
                        } else {
                            ForEach(items) { item in
                                accountCardRow(item: item)
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func quickFilterChip(filter: SidebarFilter, label: String) -> some View {
        let isSelected = store.currentFilter == filter
        let tint = filter.tintColor
        let count = store.count(for: filter)

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                store.currentFilter = filter
                if let first = store.filteredItems.first {
                    store.selectedItemId = first.id
                }
            }
        }) {
            HStack(spacing: 5) {
                Image(systemName: filter.iconName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isSelected ? .white : tint)

                Text(label)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .white : .primary.opacity(0.85))

                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(
                        isSelected
                            ? LinearGradient(colors: [tint, tint.opacity(0.82)], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [Color.secondary.opacity(0.1), Color.secondary.opacity(0.1)], startPoint: .leading, endPoint: .trailing)
                    )
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? tint.opacity(0.4) : Color.secondary.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func categoryGroupSection(category: AccountCategory, groupItems: [AccountItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // 分组标题栏
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(category.tintColor)
                    .frame(width: 4, height: 14)

                Image(systemName: category.iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(category.tintColor)

                Text(category.rawValue)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary.opacity(0.9))

                Text(category.subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()

                Text("\(groupItems.count) 项")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(category.tintColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(category.tintColor.opacity(0.12))
                    )
            }
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .padding(.bottom, 2)

            ForEach(groupItems) { item in
                accountCardRow(item: item)
            }
        }
        .padding(.bottom, 6)
    }

    private func accountCardRow(item: AccountItem) -> some View {
        let isSelected = (store.selectedItem?.id == item.id)
        let cat = item.category

        return Button(action: {
            store.selectedItemId = item.id
            store.recordActivity()
        }) {
            HStack(spacing: 11) {
                // 左侧 3D 玻璃质感智能图标
                AccountAvatarView(item: item, size: 38)

                // 中间标题与分类/数量胶囊（不显示 2FA 与账号文本，保持列表极简大气与完整标题呈现）
                VStack(alignment: .leading, spacing: 3.5) {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        if item.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.yellow)
                        }
                    }

                    HStack(spacing: 5) {
                        // 类型小徽章
                        Text(cat.rawValue)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(cat.tintColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule()
                                    .fill(cat.tintColor.opacity(0.14))
                            )

                        if item.entries.count > 1 || item.passwordGroups.count > 1 {
                            Text("\(item.passwordGroups.count)密 · \(item.entries.count)号")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundColor(Color(red: 0.05, green: 0.48, blue: 0.92))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(
                                    Capsule()
                                        .fill(Color(red: 0.05, green: 0.48, blue: 0.92).opacity(0.12))
                                )
                        }

                        if !item.normalizedCustomTag.isEmpty {
                            Text("#\(item.normalizedCustomTag)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.teal)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(
                                    Capsule()
                                        .fill(Color.teal.opacity(0.12))
                                )
                        }
                    }
                }

                Spacer(minLength: 4)

                // 右侧微交互指示箭头
                Image(systemName: "chevron.right")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(isSelected ? cat.tintColor : Color.secondary.opacity(0.28))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isSelected
                            ? cat.tintColor.opacity(0.14)
                            : Color(NSColor.controlBackgroundColor).opacity(0.65)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? cat.tintColor.opacity(0.55) : Color.primary.opacity(0.06),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if item.hasTOTP {
                let totpEntries = item.entries.filter { $0.hasTOTP }
                if totpEntries.count > 1 {
                    Menu("复制 2FA 验证码...") {
                        ForEach(totpEntries) { entry in
                            Button {
                                store.copyToClipboard(text: store.code(for: entry), label: "2FA：\(store.formattedCode(for: entry))")
                            } label: {
                                Label("2FA：\(store.formattedCode(for: entry)) (\(entry.username.isEmpty ? "默认" : entry.username))", systemImage: "clock.badge.checkmark")
                            }
                        }
                    }
                } else {
                    Button {
                        store.copyToClipboard(text: store.code(for: item), label: "2FA：\(store.formattedCode(for: item))")
                    } label: {
                        Label("复制 2FA：\(store.formattedCode(for: item))", systemImage: "clock.badge.checkmark")
                    }
                }
            }

            if item.passwordGroups.count > 1 {
                Menu("复制密码...") {
                    ForEach(Array(item.passwordGroups.enumerated()), id: \.element.id) { idx, grp in
                        Button {
                            store.copyToClipboard(text: grp.password, label: "密码：\(grp.password)")
                        } label: {
                            Label("密码：\(grp.password) (#\(idx + 1) · \(grp.entries.count)账号)", systemImage: "key.fill")
                        }
                    }
                }
            } else if !item.password.isEmpty {
                Button {
                    store.copyToClipboard(text: item.password, label: "密码：\(item.password)")
                } label: {
                    Label("复制 密码：\(item.password)", systemImage: "key.fill")
                }
            }

            if item.entries.count > 1 {
                Menu("复制用户名...") {
                    ForEach(item.entries) { entry in
                        Button {
                            store.copyToClipboard(text: entry.username, label: "账号：\(entry.username)")
                        } label: {
                            Label(entry.username.isEmpty ? "（未填写账号）" : "账号：\(entry.username)", systemImage: "person.fill")
                        }
                    }
                }
            } else if !item.username.isEmpty {
                Button {
                    store.copyToClipboard(text: item.username, label: "账号：\(item.username)")
                } label: {
                    Label("复制 账号：\(item.username)", systemImage: "person.fill")
                }
            }

            Divider()

            Menu("更改所属分类...") {
                ForEach(AccountCategory.allCases) { targetCat in
                    Button {
                        store.updateCategory(id: item.id, category: targetCat)
                    } label: {
                        Label(
                            targetCat == item.category ? "✓ \(targetCat.rawValue)" : targetCat.rawValue,
                            systemImage: targetCat.iconName
                        )
                    }
                }
            }

            Button {
                store.toggleFavorite(id: item.id)
            } label: {
                Label(item.isFavorite ? "取消星标收藏" : "设为星标收藏", systemImage: item.isFavorite ? "star.slash" : "star")
            }

            Button {
                vm.itemToEdit = item
            } label: {
                Label("编辑记录", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                store.deleteItem(id: item.id)
            } label: {
                Label("删除记录", systemImage: "trash")
            }
        }
    }

    private var emptyListView: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(store.currentFilter.tintColor.opacity(0.12))
                    .frame(width: 68, height: 68)
                Image(systemName: store.currentFilter.iconName)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(store.currentFilter.tintColor)
            }

            Text(store.searchQuery.isEmpty ? "「\(store.currentFilter.title)」下暂无记录" : "未找到匹配的账号记录")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary.opacity(0.85))

            Text(store.searchQuery.isEmpty ? "可以点击下方按钮在此分类下创建第一条账号，或切换其他分类查看。" : "请尝试更换搜索关键词或切换到「全部账号」。")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            HStack(spacing: 10) {
                if store.currentFilter != .all || !store.searchQuery.isEmpty {
                    Button("查看全部账号") {
                        store.currentFilter = .all
                        store.searchQuery = ""
                    }
                    .buttonStyle(.bordered)
                }

                Button(action: {
                    if !store.smartAddFromClipboard(defaultCategory: activeDefaultCategory) {
                        vm.showingAddSheet = true
                    }
                }) {
                    Label("粘贴剪贴板即存", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)

                Button(action: {
                    vm.showingAddSheet = true
                }) {
                    Label("智能识别添加", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 右侧详情面板
    private var detailContentView: some View {
        Group {
            if let selected = store.selectedItem {
                ItemDetailView(item: selected) { editTarget in
                    vm.itemToEdit = editTarget
                }
            } else {
                VStack(spacing: 16) {
                    VaultBrandEmblemView(size: 78)
                    Text("选择记录或使用「智能识别」添加账号")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.85))
                    Text("直接复制如「xxxx.com   xxx账号   xxx密码    2fa（xxxx）」，即可全自动拆解网址、账号、密码与 2FA 入库")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)

                    HStack(spacing: 12) {
                        Button(action: {
                            if !store.smartAddFromClipboard(defaultCategory: activeDefaultCategory) {
                                vm.showingAddSheet = true
                            }
                        }) {
                            Label("读取剪贴板直接添加", systemImage: "doc.on.clipboard")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                        Button(action: {
                            vm.showingAddSheet = true
                        }) {
                            Label("打开智能识别添加", systemImage: "sparkles")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - 独立快捷密码生成器窗口
public final class StandaloneGeneratorViewModel: ObservableObject {
    @Published public var options = PasswordGeneratorOptions()
    @Published public var generatedPassword: String = ""

    public init() {
        regenerate()
    }

    public func regenerate() {
        generatedPassword = PasswordGenerator.generate(options: options)
    }
}

struct StandaloneGeneratorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: VaultStore
    @StateObject private var vm = StandaloneGeneratorViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // 生成出的密码显示区
                VStack(spacing: 10) {
                    Text(vm.generatedPassword)
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.blue.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.blue.opacity(0.25), lineWidth: 1)
                        )

                    let strength = PasswordGenerator.evaluateStrength(vm.generatedPassword)
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 12))
                        Text("强度: \(strength.strength.label) · 信息熵: \(strength.entropyBits) bits")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }

                // 参数控制
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("密码长度: \(vm.options.length) 位")
                            .font(.system(size: 13, weight: .semibold))
                        Slider(value: Binding(
                            get: { Double(vm.options.length) },
                            set: { vm.options.length = Int($0); vm.regenerate() }
                        ), in: 8...48, step: 1)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("包含大写字母 (A-Z)", isOn: $vm.options.useUppercase).onChange(of: vm.options.useUppercase) { _ in vm.regenerate() }
                        Toggle("包含小写字母 (a-z)", isOn: $vm.options.useLowercase).onChange(of: vm.options.useLowercase) { _ in vm.regenerate() }
                        Toggle("包含数字 (0-9)", isOn: $vm.options.useDigits).onChange(of: vm.options.useDigits) { _ in vm.regenerate() }
                        Toggle("包含特殊符号 (!@#$...)", isOn: $vm.options.useSymbols).onChange(of: vm.options.useSymbols) { _ in vm.regenerate() }
                        Toggle("排除易混淆字符 (0/O, 1/l/I)", isOn: $vm.options.avoidAmbiguous).onChange(of: vm.options.avoidAmbiguous) { _ in vm.regenerate() }
                    }
                    .toggleStyle(.checkbox)
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)

                HStack(spacing: 14) {
                    Button(action: {
                        vm.regenerate()
                    }) {
                        Label("重新生成", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.large)

                    Button(action: {
                        store.copyToClipboard(text: vm.generatedPassword, label: "密码：\(vm.generatedPassword)")
                        dismiss()
                    }) {
                        Label("复制并关闭", systemImage: "doc.on.doc.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle("强密码生成工具")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 440, minHeight: 460)
    }
}
