import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/native_api.dart';
import '../widgets/common.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  Stats? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final s = await NativeApi.stats();
      await AppState.instance.refreshCounts();
      if (!mounted) return;
      setState(() {
        _stats = s;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  int get _today {
    final s = _stats;
    if (s == null || s.byDay.isEmpty) return 0;
    return s.byDay.last.count;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final counts = AppState.instance.counts;
    final s = _stats;

    return Scaffold(
      // 内容区限定在状态栏下方，滚动时不会压到状态栏的时间/电量上
      body: SafeArea(
        top: true,
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.only(bottom: 90),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '数据概览',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '本地消息统计 · 实时更新',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
            if (_loading && s == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
              )
            else if (s == null)
              EmptyState(
                icon: Icons.insights_rounded,
                title: '暂无统计数据',
                subtitle: '下拉刷新试试',
                action: FilledButton.tonal(
                  onPressed: _load,
                  child: const Text('重新加载'),
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            label: '消息总数',
                            value: counts.total,
                            icon: Icons.inbox_rounded,
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _StatCard(
                            label: '今日收到',
                            value: _today,
                            icon: Icons.bolt_rounded,
                            color: const Color(0xFF06B6D4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            label: '未读',
                            value: counts.unread,
                            icon: Icons.mark_email_unread_rounded,
                            color: const Color(0xFFF59E0B),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _StatCard(
                            label: '收藏',
                            value: counts.starred,
                            icon: Icons.star_rounded,
                            color: const Color(0xFFF43F5E),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SectionHeader('近 14 天接收趋势'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SoftCard(
                  padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
                  child: _TrendChart(days: s.byDay),
                ),
              ),
              const SectionHeader('主题分布'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SoftCard(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                  child: Column(
                    children: [
                      _themeRow(context, '信息', s.info, s, const Color(0xFF3B82F6)),
                      _themeRow(context, '成功', s.success, s, const Color(0xFF10B981)),
                      _themeRow(context, '警告', s.warning, s, const Color(0xFFF59E0B)),
                      _themeRow(context, '失败', s.failure, s, const Color(0xFFEF4444)),
                      _themeRow(
                        context,
                        '普通',
                        s.plain,
                        s,
                        Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
              const SectionHeader('消息类型'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SoftCard(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 10,
                    children: s.byType
                        .map(
                          (e) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHigh
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  typeLabel(e.name),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  '${e.count}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    color: scheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
              const SectionHeader('消息分组 TOP'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SoftCard(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                  child: Column(
                    children: s.byUser
                        .map((e) => _userRow(context, e, s.byUser))
                        .toList(),
                  ),
                ),
              ),
            ],
          ],
          ),
        ),
      ),
    );
  }

  Widget _themeRow(
    BuildContext context,
    String label,
    int value,
    Stats s,
    Color color,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final total = math.max(1, s.info + s.success + s.warning + s.failure + s.plain);
    final ratio = value / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 7,
                backgroundColor: scheme.surfaceContainerHigh.withValues(alpha: 0.6),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 38,
            child: Text(
              '$value',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _userRow(BuildContext context, NameCount e, List<NameCount> all) {
    final scheme = Theme.of(context).colorScheme;
    final maxV = all.isEmpty ? 1 : math.max(1, all.first.count);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              e.name.isEmpty ? '#' : e.name.characters.first,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: scheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: e.count / maxV,
                    minHeight: 4,
                    backgroundColor:
                        scheme.surfaceContainerHigh.withValues(alpha: 0.55),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      scheme.primary.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${e.count}',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SoftCard(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 15, color: color),
              ),
              const Spacer(),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$value',
                style: const TextStyle(
                  fontSize: 26,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '条',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.days});

  final List<DayCount> days;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (days.isEmpty) {
      return SizedBox(
        height: 80,
        child: Center(
          child: Text(
            '暂无数据',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }
    // 真实峰值（可能为 0）；maxV 仅作除数，最小为 1，避免 0/0 得到 NaN
    final peak = days.map((e) => e.count).fold<int>(0, (a, b) => math.max(a, b));
    final maxV = peak == 0 ? 1 : peak;
    const chartH = 88.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              peak == 0 ? '近 14 天暂无接收' : '峰值 $peak 条 / 天',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: chartH + 30,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < days.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // 固定高度：无论是否显示数值都占位，避免柱状图区高度溢出
                        SizedBox(
                          height: 11,
                          child: days[i].count > 0
                              ? FittedBox(
                                  child: Text(
                                    '${days[i].count}',
                                    style: TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w700,
                                      color: scheme.onSurfaceVariant
                                          .withValues(alpha: 0.8),
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          height: days[i].count == 0
                              ? 4
                              : math.max(
                                  5,
                                  (days[i].count / maxV) * chartH,
                                ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                scheme.primary,
                                scheme.primary.withValues(alpha: 0.45),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 5),
                        SizedBox(
                          height: 12,
                          child: (i % 3 == 0 || i == days.length - 1)
                              ? FittedBox(
                                  child: Text(
                                    shortDay(days[i].date),
                                    style: TextStyle(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurfaceVariant
                                          .withValues(alpha: 0.65),
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
