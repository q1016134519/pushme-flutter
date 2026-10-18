import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/native_api.dart';
import 'message_detail_page.dart';
import 'message_list_page.dart';
import 'settings_page.dart';
import 'stats_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;
  int _statsEpoch = 0;

  @override
  void initState() {
    super.initState();
    AppState.instance.addListener(_onState);
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    final id = AppState.instance.consumePendingOpenId();
    if (id == null) return;
    // 忽略构建期的同步通知，等一帧结束后再导航，避免在 build 中 push 路由
    WidgetsBinding.instance.addPostFrameCallback((_) => _openById(id));
  }

  Future<void> _openById(int id) async {
    try {
      final msg = await NativeApi.messageGet(id);
      if (msg == null || !mounted) return;
      await NativeApi.markRead([id], true);
      AppState.instance.refreshCounts();
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MessageDetailPage(initial: msg.copyWith(read: true)),
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const MessageListPage(),
          StatsPage(key: ValueKey('stats-$_statsEpoch')),
          const SettingsPage(),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.4),
              width: 0.8,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) {
            setState(() {
              if (i == 1 && _index != 1) _statsEpoch++;
              _index = i;
            });
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.forum_outlined),
              selectedIcon: Icon(Icons.forum_rounded),
              label: '消息',
            ),
            NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights_rounded),
              label: '数据',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: '设置',
            ),
          ],
        ),
      ),
    );
  }
}
