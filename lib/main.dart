import 'dart:async';

import 'package:flutter/material.dart';

import 'ui/app_theme.dart';
import 'ui/home_shell.dart';
import 'ui/lock_screen.dart';
import 'ui/status_toast.dart';
import 'ui/vault_store.dart';

void main() {
  runApp(const SecretCoreApp());
}

class SecretCoreApp extends StatefulWidget {
  const SecretCoreApp({super.key});

  @override
  State<SecretCoreApp> createState() => _SecretCoreAppState();
}

class _SecretCoreAppState extends State<SecretCoreApp>
    with WidgetsBindingObserver {
  final VaultStore _store = VaultStore();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_store.bootstrap());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _store.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _store.handleAppPaused();
        break;
      case AppLifecycleState.resumed:
        _store.handleAppResumed();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SecretCore · 极光秘核',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      // 全局绿胶囊 Toast：覆盖所有路由（对齐 Mac 窗口级 clipboardStatusMessage）
      builder: (context, child) => Stack(
        children: [
          if (child != null) child,
          Positioned.fill(
            child: StatusToastLayer(store: _store),
          ),
        ],
      ),
      home: AnimatedBuilder(
        animation: _store,
        builder: (context, _) {
          switch (_store.phase) {
            case VaultPhase.unlocked:
              return HomeShell(store: _store);
            case VaultPhase.locked:
            case VaultPhase.needsSetup:
              return LockScreen(store: _store);
          }
        },
      ),
    );
  }
}
