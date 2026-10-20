import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/native_api.dart';
import '../widgets/common.dart';
import '../widgets/message_tile.dart';
import 'message_detail_page.dart';

class MessageListPage extends StatefulWidget {
  const MessageListPage({super.key});

  @override
  State<MessageListPage> createState() => _MessageListPageState();
}

sealed class _Row {
  const _Row();
}

class _HeaderRow extends _Row {
  const _HeaderRow(this.label, this.count);
  final String label;
  final int count;
}

class _MsgRow extends _Row {
  const _MsgRow(this.msg, {this.indent = false});
  final MessageItem msg;

  /// 是否是「组卡片展开后」的子行 —— 缩进一点，视觉上从属于上面的组
  final bool indent;
}

/// 「折叠」模式下，同一分组（消息的 user 字段）收成的一条
class _GroupRow extends _Row {
  const _GroupRow({
    required this.key,
    required this.user,
    required this.msgs,
    required this.expanded,
  });

  final String key;
  final String user;
  final List<MessageItem> msgs;
  final bool expanded;
}

class _MessageListPageState extends State<MessageListPage> {
  static const int _pageSize = 40;

  final ScrollController _scroll = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  final List<MessageItem> _items = <MessageItem>[];
  List<_Row> _rows = const <_Row>[];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _searchOpen = false;

  String _query = '';
  String _status = '全部';
  String _theme = '全部';
  String _sortBy = '时间';
  String _sort = 'desc';

  Timer? _debounce;
  int _seenVersion = -1;
  int _seenSeq = 0;

  /// 消息分组的显示方式：「展开」/「折叠」，见设置页
  String _groupMode = '展开';

  /// 已展开的组（key = 日期|分组名）。默认全部收起
  final Set<String> _expandedGroups = <String>{};

  /// 折叠模式：同一分组的多条消息收成一条
  bool get _collapsed => _groupMode == '折叠';

  @override
  void initState() {
    super.initState();
    _seenVersion = AppState.instance.listVersion;
    _seenSeq = AppState.instance.messageSeq;
    _groupMode = AppState.instance.str('msg_group', '展开');
    AppState.instance.addListener(_onState);
    _scroll.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onState);
    _scroll.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onState() {
    final state = AppState.instance;
    if (!mounted) return;
    // 设置里切换「折叠 / 展开」后立刻重排，不用退出重进
    final mode = state.str('msg_group', '展开');
    if (mode != _groupMode) {
      setState(() {
        _groupMode = mode;
        _rows = _buildRows(_items);
      });
    }
    if (state.listVersion != _seenVersion) {
      _seenVersion = state.listVersion;
      // 有新消息：静默刷新列表首屏
      _load(reset: true, silent: true);
    }
    if (state.messageSeq != _seenSeq) {
      _seenSeq = state.messageSeq;
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _load({bool reset = false, bool silent = false}) async {
    if (reset) {
      if (!silent) setState(() => _loading = true);
    } else {
      if (_loadingMore || _items.length >= _total) return;
      setState(() => _loadingMore = true);
    }
    try {
      final r = await NativeApi.messagesList(
        offset: reset ? 0 : _items.length,
        limit: _pageSize,
        query: _query,
        status: _status,
        theme: _theme,
        sortBy: _sortBy,
        sort: _sort,
      );
      if (!mounted) return;
      setState(() {
        _total = r.total;
        if (reset) {
          _items
            ..clear()
            ..addAll(r.items);
        } else {
          _items.addAll(r.items);
        }
        _rows = _buildRows(_items);
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _items.length >= _total) return;
    await _load();
  }

  List<_Row> _buildRows(List<MessageItem> items) {
    final rows = <_Row>[];

    // 先按天切段：日期标题始终保留，分组只在同一天内部发生
    final dayKeys = <String>[];
    final days = <String, List<MessageItem>>{};
    for (final m in items) {
      final k = groupKey(m.date);
      final bucket = days.putIfAbsent(k, () {
        dayKeys.add(k);
        return <MessageItem>[];
      });
      bucket.add(m);
    }

    for (final k in dayKeys) {
      final day = days[k]!;
      rows.add(_HeaderRow(groupLabel(day.first.date), day.length));

      if (!_collapsed) {
        rows.addAll(day.map((m) => _MsgRow(m)));
        continue;
      }

      // 折叠：同一天内、同名分组的多条消息收成一条，位置放在该组最新一条处。
      // 只有一条的分组不折叠 —— 收成「1 条」反而多一次点击。
      final emitted = <String>{};
      for (final m in day) {
        final user = m.user.trim();
        if (user.isEmpty) {
          rows.add(_MsgRow(m));
          continue;
        }
        if (!emitted.add(user)) continue;
        final members = day.where((e) => e.user.trim() == user).toList();
        if (members.length < 2) {
          rows.add(_MsgRow(m));
          continue;
        }
        final key = '$k|$user';
        final expanded = _expandedGroups.contains(key);
        rows.add(_GroupRow(
          key: key,
          user: user,
          msgs: members,
          expanded: expanded,
        ));
        if (expanded) {
          rows.addAll(members.map((e) => _MsgRow(e, indent: true)));
        }
      }
    }
    return rows;
  }

  void _toggleGroup(String key) {
    setState(() {
      if (!_expandedGroups.remove(key)) _expandedGroups.add(key);
      _rows = _buildRows(_items);
    });
  }

  void _patch(int id, MessageItem Function(MessageItem) update) {
    for (var i = 0; i < _items.length; i++) {
      if (_items[i].id == id) {
        _items[i] = update(_items[i]);
        break;
      }
    }
    setState(() => _rows = _buildRows(_items));
  }

  Future<void> _open(MessageItem m) async {
    if (!m.read) {
      _patch(m.id, (e) => e.copyWith(read: true));
      AppState.instance.refreshCounts();
      try {
        await NativeApi.markRead([m.id], true);
      } catch (_) {}
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MessageDetailPage(initial: m)),
    );
    if (!mounted) return;
    AppState.instance.refreshCounts();
    _load(reset: true, silent: true);
  }

  void _toggleStar(MessageItem m) {
    final next = !m.starred;
    _patch(m.id, (e) => e.copyWith(starred: next));
    NativeApi.star([m.id], next);
    AppState.instance.refreshCounts();
    showToast(context, next ? '已收藏' : '已取消收藏');
  }

  Future<void> _longPress(MessageItem m) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetCtx) {
        final scheme = Theme.of(sheetCtx).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        m.title.isEmpty ? '（无标题）' : m.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _sheetAction(
                sheetCtx,
                m.read ? Icons.mark_email_unread_rounded : Icons.done_all_rounded,
                m.read ? '标为未读' : '标为已读',
                () async {
                  Navigator.pop(sheetCtx);
                  final next = !m.read;
                  _patch(m.id, (e) => e.copyWith(read: next));
                  await NativeApi.markRead([m.id], next);
                  AppState.instance.refreshCounts();
                },
              ),
              _sheetAction(
                sheetCtx,
                m.starred ? Icons.star_outline_rounded : Icons.star_rounded,
                m.starred ? '取消收藏' : '收藏',
                () {
                  Navigator.pop(sheetCtx);
                  _toggleStar(m);
                },
              ),
              _sheetAction(
                sheetCtx,
                Icons.copy_rounded,
                '复制内容',
                () async {
                  Navigator.pop(sheetCtx);
                  await Clipboard.setData(ClipboardData(text: m.content));
                  if (!mounted) return;
                  showToast(context, '内容已复制');
                },
              ),
              _sheetAction(
                sheetCtx,
                Icons.delete_outline_rounded,
                '删除消息',
                () async {
                  Navigator.pop(sheetCtx);
                  await NativeApi.delete([m.id]);
                  if (!mounted) return;
                  setState(() {
                    _items.removeWhere((e) => e.id == m.id);
                    _rows = _buildRows(_items);
                    _total = _total > 0 ? _total - 1 : 0;
                  });
                  AppState.instance.refreshCounts();
                  if (mounted) showToast(context, '已删除');
                },
                danger: true,
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _sheetAction(
    BuildContext ctx,
    IconData icon,
    String text,
    VoidCallback onTap, {
    bool danger = false,
  }) {
    final scheme = Theme.of(ctx).colorScheme;
    final color = danger ? const Color(0xFFEF4444) : scheme.onSurface;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 14),
            Text(
              text,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      setState(() => _query = v.trim());
      _load(reset: true);
    });
  }

  Future<void> _openFilter() async {
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      builder: (ctx) => _FilterSheet(
        theme: _theme,
        sortBy: _sortBy,
        sort: _sort,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _theme = result[0];
      _sortBy = result[1];
      _sort = result[2];
    });
    _load(reset: true);
  }

  Future<void> _markAllRead() async {
    await NativeApi.markAllRead();
    AppState.instance.refreshCounts();
    if (!mounted) return;
    showToast(context, '已全部标为已读');
    _load(reset: true, silent: true);
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空全部消息'),
        content: const Text('将删除本机保存的所有推送记录，且不可恢复。确定继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await NativeApi.clearAll();
    AppState.instance.refreshCounts();
    if (!mounted) return;
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = AppState.instance;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverAppBar(
              pinned: true,
              toolbarHeight: 66,
              backgroundColor: scheme.surface,
              surfaceTintColor: Colors.transparent,
              titleSpacing: 20,
              title: AnimatedBuilder(
                animation: state,
                builder: (context, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'PushMe',
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const StatusPill(),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _subtitle(state),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  );
                },
              ),
              actions: [
                IconButton(
                  tooltip: '搜索',
                  onPressed: () {
                    setState(() => _searchOpen = !_searchOpen);
                    if (_searchOpen) {
                      Future.delayed(
                        const Duration(milliseconds: 120),
                        () => _searchFocus.requestFocus(),
                      );
                    } else {
                      _searchCtrl.clear();
                      _searchFocus.unfocus();
                      if (_query.isNotEmpty) {
                        setState(() => _query = '');
                        _load(reset: true);
                      }
                    }
                  },
                  icon: Icon(
                    _searchOpen ? Icons.close_rounded : Icons.search_rounded,
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz_rounded),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  onSelected: (v) {
                    switch (v) {
                      case 'read':
                        _markAllRead();
                        break;
                      case 'refresh':
                        _load(reset: true);
                        break;
                      case 'clear':
                        _clearAll();
                        break;
                    }
                  },
                  itemBuilder: (ctx) => const [
                    PopupMenuItem(
                      value: 'read',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.done_all_rounded, size: 20),
                        title: Text('全部标为已读'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'refresh',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.refresh_rounded, size: 20),
                        title: Text('刷新'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'clear',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.delete_sweep_rounded, size: 20),
                        title: Text('清空消息'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 6),
              ],
            ),
            SliverToBoxAdapter(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                child: _searchOpen
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                        child: TextField(
                          controller: _searchCtrl,
                          focusNode: _searchFocus,
                          onChanged: _onSearchChanged,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: '搜索标题或内容…',
                            prefixIcon: const Icon(Icons.search_rounded, size: 20),
                            suffixIcon: _searchCtrl.text.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.cancel_rounded, size: 18),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      _onSearchChanged('');
                                    },
                                  ),
                          ),
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ),
            SliverToBoxAdapter(child: _filterBar(scheme)),
            SliverToBoxAdapter(
              child: _loading ? const _TopLoading() : const SizedBox(height: 2),
            ),
            SliverList.builder(
              itemCount: _rows.length,
              itemBuilder: (context, index) {
                final row = _rows[index];
                if (row is _HeaderRow) {
                  return _dateHeader(context, row.label, row.count);
                }
                if (row is _GroupRow) {
                  return MessageGroupTile(
                    user: row.user,
                    msgs: row.msgs,
                    expanded: row.expanded,
                    onTap: () => _toggleGroup(row.key),
                  );
                }
                final msgRow = row as _MsgRow;
                final msg = msgRow.msg;
                final tile = MessageTile(
                  msg: msg,
                  onTap: () => _open(msg),
                  onLongPress: () => _longPress(msg),
                  onStar: () => _toggleStar(msg),
                );
                if (!msgRow.indent) return tile;
                // 组内子消息往右缩一点，视觉上挂在组卡片下面
                return Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: tile,
                );
              },
            ),
            SliverToBoxAdapter(child: _footer(scheme)),
            const SliverToBoxAdapter(child: SizedBox(height: 90)),
          ],
        ),
      ),
    );
  }

  String _subtitle(AppState state) {
    if (_query.isNotEmpty) {
      return '搜索「$_query」 · $_total 条结果';
    }
    final unread = state.counts.unread;
    final base = '共 $_total 条';
    return unread > 0 ? '$base · $unread 条未读' : '$base · 全部已读';
  }

  Widget _filterBar(ColorScheme scheme) {
    Widget chip(String label, IconData? icon, bool selected, VoidCallback onTap) {
      return _FilterChip(
        label: label,
        icon: icon,
        selected: selected,
        onTap: onTap,
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  chip('全部', Icons.inbox_rounded, _status == '全部', () {
                    setState(() => _status = '全部');
                    _load(reset: true);
                  }),
                  const SizedBox(width: 8),
                  chip('未读', Icons.fiber_manual_record_rounded,
                      _status == '未读', () {
                    setState(() => _status = '未读');
                    _load(reset: true);
                  }),
                  const SizedBox(width: 8),
                  chip('收藏', Icons.star_rounded, _status == '收藏', () {
                    setState(() => _status = '收藏');
                    _load(reset: true);
                  }),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: '筛选与排序',
            onPressed: _openFilter,
            icon: Badge(
              isLabelVisible: _theme != '全部' || _sortBy != '时间' || _sort != 'desc',
              smallSize: 7,
              backgroundColor: scheme.primary,
              child: const Icon(Icons.tune_rounded, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateHeader(BuildContext context, String label, int count) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer(ColorScheme scheme) {
    if (_loading) return const SizedBox.shrink();
    if (_items.isEmpty) {
      return EmptyState(
        icon: Icons.notifications_off_rounded,
        title: _query.isNotEmpty ? '没有匹配的消息' : '还没有收到推送',
        subtitle: _query.isNotEmpty
            ? '换个关键词试试，或清除搜索条件'
            : '服务运行后，向你的 push_key 发送一条消息即可在这里看到。',
      );
    }
    if (_loadingMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.primary,
            ),
          ),
        ),
      );
    }
    if (_items.length >= _total) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            '已经到底了 · 共 $_total 条',
            style: TextStyle(
              fontSize: 11.5,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ),
      );
    }
    return const SizedBox(height: 20);
  }
}

class _TopLoading extends StatelessWidget {
  const _TopLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 30),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary
              : scheme.surfaceContainerHigh.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 13,
                color: selected ? Colors.white : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? Colors.white : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.theme,
    required this.sortBy,
    required this.sort,
  });

  final String theme;
  final String sortBy;
  final String sort;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String _theme = widget.theme;
  late String _sortBy = widget.sortBy;
  late String _sort = widget.sort;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '筛选与排序',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            Text(
              '主题',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['全部', '信息', '成功', '警告', '失败'].map((t) {
                return _FilterChip(
                  label: t,
                  selected: _theme == t,
                  onTap: () => setState(() => _theme = t),
                );
              }).toList(),
            ),
            const SizedBox(height: 18),
            Text(
              '排序',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final by in ['时间', '主题', '标题', '类型'])
                  _FilterChip(
                    label: by,
                    selected: _sortBy == by,
                    onTap: () => setState(() => _sortBy = by),
                  ),
                for (final dir in ['desc', 'asc'])
                  _FilterChip(
                    label: dir == 'desc' ? '降序' : '升序',
                    icon: dir == 'desc'
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded,
                    selected: _sort == dir,
                    onTap: () => setState(() => _sort = dir),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _theme = '全部';
                        _sortBy = '时间';
                        _sort = 'desc';
                      });
                    },
                    child: const Text('重置'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, [_theme, _sortBy, _sort]),
                    child: const Text('应用'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
