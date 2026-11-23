import AuthenticationServices
import UIKit

/// AutoFill 凭据提供扩展主控制器。
///
/// 流程：从共享 Keychain 读取主 App 维护的快速填充镜像 →
/// 列出全部账号（支持搜索）→ 用户点选 → completeRequest 返回
/// ASPasswordCredential 给系统，由系统填入 Safari / App 登录框。
///
/// 隐私约定：扩展不解密保险箱文件，只读镜像；
/// 镜像只存于本机 Keychain（WhenUnlockedThisDeviceOnly），完全离线。
class CredentialProviderViewController: UIViewController {

  private var allEntries: [SharedMirrorReader.QuickTypeEntry] = []
  private var visibleEntries: [SharedMirrorReader.QuickTypeEntry] = []

  private let tableView = UITableView(frame: .zero, style: .insetGrouped)
  private let searchController = UISearchController(searchResultsController: nil)
  private let emptyLabel = UILabel()
  private let brandHeader = UIView()

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = UIColor(red: 0.94, green: 0.97, blue: 1.0, alpha: 1.0)
    setupUI()
    reloadMirror()
  }

  // MARK: - 系统入口

  /// Safari / App 点击账号框选择「极光秘核」时进入
  override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
    guard let primary = serviceIdentifiers.first else { return }
    var hint = primary.identifier.lowercased()
    if primary.type == .URL,
       let url = URL(string: primary.identifier),
       let host = url.host {
      hint = host
    }
    // 域名 / 标题命中时优先排序（不做强制过滤，保留手动搜索能力）
    reloadMirror(preferHint: hint)
  }

  /// 系统直接请求某个具体凭据（iOS 17+ 快速路径）
  override func prepareInterfaceToProvideCredential(for credentialRequest: ASCredentialRequest) {
    // 统一走列表选择；选中后按请求身份 complete
    reloadMirror()
  }

  /// 用户在系统设置里把本 App 设为 AutoFill 来源时的一次性引导
  override func prepareInterfaceForExtensionConfiguration() {
    reloadMirror()
    title = "启用完成 · 选择任意账号以验证"
  }

  // MARK: - UI 构建

  private func setupUI() {
    title = "极光秘核 · 选择账号"

    navigationItem.searchController = searchController
    searchController.searchResultsUpdater = self
    searchController.obscuresBackgroundDuringPresentation = false
    searchController.searchBar.placeholder = "搜索标题 / 账号 / 网址"

    navigationItem.leftBarButtonItem = UIBarButtonItem(
      barButtonSystemItem: .cancel,
      target: self,
      action: #selector(cancelTapped)
    )

    tableView.dataSource = self
    tableView.delegate = self
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "entry")
    tableView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(tableView)

    emptyLabel.text = "镜像为空\n请先在极光秘核 App 中添加账号，\n任意保存一次后回到此处。"
    emptyLabel.numberOfLines = 0
    emptyLabel.textAlignment = .center
    emptyLabel.textColor = UIColor(red: 0.36, green: 0.44, blue: 0.54, alpha: 1.0)
    emptyLabel.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(emptyLabel)

    NSLayoutConstraint.activate([
      tableView.topAnchor.constraint(equalTo: view.topAnchor),
      tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])
  }

  private func reloadMirror(preferHint: String? = nil) {
    allEntries = SharedMirrorReader.loadEntries()
    if let hint = preferHint, !hint.isEmpty {
      let matched = SharedMirrorReader.filter(allEntries, query: hint)
      let rest = allEntries.filter { entry in !matched.contains(where: { $0.username == entry.username && $0.title == entry.title }) }
      allEntries = matched + rest
    }
    visibleEntries = allEntries
    let empty = allEntries.isEmpty
    emptyLabel.isHidden = !empty
    tableView.isHidden = empty
    tableView.reloadData()
  }

  @objc private func cancelTapped() {
    extensionContext.cancelRequest(withError: NSError(
      domain: ASExtensionErrorDomain,
      code: ASExtensionError.userCanceled.rawValue
    ))
  }

  private func complete(with entry: SharedMirrorReader.QuickTypeEntry) {
    let credential = ASPasswordCredential(user: entry.username, password: entry.password)
    extensionContext.completeRequest(
      withCredentials: [credential],
      completion: nil
    )
  }
}

// MARK: - 搜索

extension CredentialProviderViewController: UISearchResultsUpdating {
  func updateSearchResults(for searchController: UISearchController) {
    visibleEntries = SharedMirrorReader.filter(allEntries, query: searchController.searchBar.text ?? "")
    tableView.reloadData()
  }
}

// MARK: - 列表

extension CredentialProviderViewController: UITableViewDataSource, UITableViewDelegate {

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    visibleEntries.count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "entry", for: indexPath)
    let entry = visibleEntries[indexPath.row]
    var config = cell.defaultContentConfiguration()
    config.text = entry.displayTitle
    config.secondaryText = entry.username
    config.textProperties.font = .systemFont(ofSize: 15, weight: .semibold)
    config.secondaryTextProperties.font = .systemFont(ofSize: 12.5)
    config.secondaryTextProperties.color = UIColor(red: 0.36, green: 0.44, blue: 0.54, alpha: 1.0)
    cell.contentConfiguration = config
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    complete(with: visibleEntries[indexPath.row])
  }
}
