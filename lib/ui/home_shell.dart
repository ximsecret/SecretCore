import 'package:flutter/material.dart';

import 'main_vault_view.dart';
import 'vault_store.dart';

/// 已解锁后的应用主外壳：抽屉侧栏 + 主列表
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.store});

  final VaultStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: VaultDrawer(store: store),
      body: MainVaultView(store: store),
    );
  }
}
