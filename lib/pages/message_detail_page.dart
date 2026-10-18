import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../core/app_state.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/native_api.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

class MessageDetailPage extends StatefulWidget {
  const MessageDetailPage({super.key, required this.initial});

  final MessageItem initial;

  @override
  State<MessageDetailPage> createState() => _MessageDetailPageState();
}

class _MessageDetailPageState extends State<MessageDetailPage> {
  late MessageItem _msg = widget.initial;

  @override
  void initState() {
    super.initState();
    _markRead();
  }

  Future<void> _markRead() async {
    if (_msg.read) return;
    setState(() => _msg = _msg.copyWith(read: true));
    try {
      await NativeApi.markRead([_msg.id], true);
    } catch (_) {}
    AppState.instance.refreshCounts();
  }

  Future<void> _toggleStar() async {
    final next = !_msg.starred;
    setState(() => _msg = _msg.copyWith(starred: next));
    try {
      await NativeApi.star([_msg.id], next);
    } catch (_) {}
    if (!mounted) return;
    showToast(context, next ? '已收藏' : '已取消收藏');
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _msg.content));
    if (!mounted) return;
    showToast(context, '内容已复制');
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条消息？'),
        content: const Text('删除后无法恢复。'),
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
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await NativeApi.delete([_msg.id]);
    AppState.instance.refreshCounts();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _openUrl(String url) async {
    var target = url.trim();
    if (target.startsWith('//')) target = 'https:$target';
    if (!target.contains('://')) {
      if (target.startsWith('www.')) {
        target = 'https://$target';
      } else {
        target = 'https://$target';
      }
    }
    final uri = Uri.tryParse(target);
    if (uri == null) {
      if (mounted) showToast(context, '链接格式不正确');
      return;
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) showToast(context, '没有可用的浏览器');
    } catch (_) {
      if (mounted) showToast(context, '无法打开链接');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = themeAccent(_msg.theme, scheme);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: scheme.surface,
            surfaceTintColor: Colors.transparent,
            titleSpacing: 4,
            title: Text(
              typeLabel(_msg.type),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            actions: [
              IconButton(
                tooltip: _msg.starred ? '取消收藏' : '收藏',
                onPressed: _toggleStar,
                icon: Icon(
                  _msg.starred ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: _msg.starred ? const Color(0xFFF59E0B) : null,
                ),
              ),
              IconButton(
                tooltip: '复制',
                onPressed: _copy,
                icon: const Icon(Icons.copy_rounded, size: 20),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onSelected: (v) {
                  if (v == 'delete') _delete();
                  if (v == 'open') _openUrl(_msg.content);
                },
                itemBuilder: (ctx) => [
                  if (_msg.type == 'url')
                    const PopupMenuItem(
                      value: 'open',
                      child: Text('在浏览器打开'),
                    ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('删除消息'),
                  ),
                ],
              ),
              const SizedBox(width: 4),
            ],
          ),
          SliverToBoxAdapter(
            child: SelectionArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (_msg.theme.isNotEmpty)
                          Pill(
                            themeLabel(_msg.theme),
                            color: accent,
                            icon: themeIcon(_msg.theme),
                            filled: true,
                          ),
                        if (_msg.theme.isNotEmpty) const SizedBox(width: 7),
                        if (_msg.type.isNotEmpty)
                          Pill(_msg.type.toUpperCase(), color: scheme.primary),
                        const Spacer(),
                        if (_msg.starred)
                          const Icon(
                            Icons.star_rounded,
                            size: 18,
                            color: Color(0xFFF59E0B),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _msg.title.isEmpty ? '（无标题）' : _msg.title,
                      style: const TextStyle(
                        fontSize: 21,
                        height: 1.35,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 14,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _meta(
                          context,
                          Icons.folder_outlined,
                          _msg.user.isEmpty ? '未分组' : _msg.user,
                        ),
                        _meta(
                          context,
                          Icons.schedule_rounded,
                          formatFullTime(_msg.date),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.5),
                          width: 0.8,
                        ),
                      ),
                      child: _body(context),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        '消息 ID ${_msg.id} · 本地保存',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _meta(BuildContext context, IconData icon, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.9),
          ),
        ),
      ],
    );
  }

  Widget _body(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textStyle = TextStyle(
      fontSize: 15,
      height: 1.75,
      color: scheme.onSurface,
    );
    final content = _msg.content;

    switch (_msg.type) {
      case 'markdown':
        return _rich(
          md.markdownToHtml(content, extensionSet: md.ExtensionSet.gitHubFlavored),
          textStyle,
        );
      case 'html':
        return _rich(content, textStyle);
      case 'url':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              content,
              style: textStyle.copyWith(fontSize: 13.5, height: 1.6),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _openUrl(content),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('在浏览器打开'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        );
      case 'data':
        return _codeBlock(context, _prettyJson(content), 'JSON 数据');
      case 'chart':
      case 'echarts':
      case 'svg':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 15, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${typeLabel(_msg.type)} 源码，可在浏览器中渲染查看',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _codeBlock(context, content, _msg.type.toUpperCase()),
          ],
        );
      default:
        return SelectableText(content, style: textStyle);
    }
  }

  /// 转成 CSS 颜色：#RRGGBB（该包不认 8 位 ARGB，会当成 RRGGBBAA 导致颜色发淡）
  String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  /// 统一的富文本渲染：收紧默认段间距，避免每行都被渲染成一个大段
  Widget _rich(String html, TextStyle textStyle) {
    final scheme = Theme.of(context).colorScheme;
    return HtmlWidget(
      html,
      textStyle: textStyle,
      onTapUrl: (url) {
        _openUrl(url);
        return true;
      },
      customStylesBuilder: (el) {
        switch (el.localName) {
          case 'p':
            return {'margin': '0 0 7px 0'};
          case 'h1':
          case 'h2':
          case 'h3':
          case 'h4':
          case 'h5':
          case 'h6':
            return {
              'margin': '14px 0 6px 0',
              'font-weight': '700',
              'line-height': '1.45',
            };
          case 'ul':
          case 'ol':
            return {'margin': '2px 0 7px 0', 'padding-left': '20px'};
          case 'li':
            return {'margin': '0 0 3px 0'};
          case 'blockquote':
            return {
              'margin': '6px 0',
              'padding-left': '10px',
              'color': _hex(scheme.onSurfaceVariant),
            };
          case 'pre':
            return {
              'margin': '4px 0 8px 0',
              'padding': '10px',
              'font-size': '12.5px',
              'background-color': _hex(scheme.surfaceContainerHigh),
            };
          case 'code':
            return {'font-size': '12.5px'};
          case 'hr':
            return {'margin': '12px 0'};
          case 'table':
            return {'margin': '4px 0 8px 0', 'font-size': '13px'};
          case 'img':
            return {'max-width': '100%'};
          default:
            return null;
        }
      },
    );
  }

  Widget _codeBlock(BuildContext context, String code, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 2),
            child: Row(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    if (!context.mounted) return;
                    showToast(context, '源码已复制');
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: SelectableText(
              code,
              style: TextStyle(
                fontSize: 12.2,
                height: 1.55,
                fontFamily: 'monospace',
                color: scheme.onSurface.withValues(alpha: 0.92),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _prettyJson(String raw) {
    // 轻量格式化：仅处理单行 JSON，避免额外依赖
    final trimmed = raw.trim();
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return raw;
    if (trimmed.contains('\n')) return raw;
    try {
      return _indentJson(trimmed);
    } catch (_) {
      return raw;
    }
  }

  String _pad(int depth) => List<String>.filled(depth, '  ').join();

  String _indentJson(String s) {
    final buf = StringBuffer();
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      if (inString) {
        buf.write(ch);
        if (escaped) {
          escaped = false;
        } else if (ch == '\\') {
          escaped = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }
      switch (ch) {
        case '"':
          inString = true;
          buf.write(ch);
          break;
        case '{':
        case '[':
          depth++;
          buf.write(ch);
          buf.write('\n');
          buf.write(_pad(depth));
          break;
        case '}':
        case ']':
          depth--;
          buf.write('\n');
          buf.write(_pad(depth < 0 ? 0 : depth));
          buf.write(ch);
          break;
        case ',':
          buf.write(ch);
          buf.write('\n');
          buf.write(_pad(depth));
          break;
        case ':':
          buf.write(': ');
          break;
        default:
          buf.write(ch);
      }
    }
    return buf.toString();
  }
}
