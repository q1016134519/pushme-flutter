import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../core/theme.dart';
import 'common.dart';

/// 消息列表项
class MessageTile extends StatelessWidget {
  const MessageTile({
    super.key,
    required this.msg,
    required this.onTap,
    this.onLongPress,
    this.onStar,
  });

  final MessageItem msg;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onStar;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = themeAccent(msg.theme, scheme);
    final unread = !msg.read;

    return SoftCard(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      padding: const EdgeInsets.fromLTRB(13, 13, 10, 12),
      radius: 18,
      onTap: onTap,
      onLongPress: onLongPress,
      color: unread
          ? Color.alphaBlend(
              accent.withValues(alpha: 0.035),
              scheme.surfaceContainerLowest,
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Avatar(msg: msg, accent: accent, unread: unread),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (unread) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                    ],
                    Expanded(
                      child: Text(
                        msg.title.isEmpty ? '（无标题）' : msg.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.25,
                          fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        formatMsgTime(msg.date),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  msg.preview.isEmpty ? '（无内容）' : msg.preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.8,
                    height: 1.5,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.95),
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    if (msg.theme.isNotEmpty) ...[
                      Pill(
                        themeLabel(msg.theme),
                        color: accent,
                        icon: themeIcon(msg.theme),
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (msg.user.isNotEmpty)
                      Flexible(
                        child: Pill(
                          msg.user,
                          icon: Icons.folder_rounded,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    if (msg.type.isNotEmpty && msg.type != 'text') ...[
                      const SizedBox(width: 6),
                      Pill(msg.type.toUpperCase(), color: scheme.primary),
                    ],
                    const Spacer(),
                    if (msg.starred)
                      Icon(
                        Icons.star_rounded,
                        size: 16,
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.9),
                      )
                    else if (msg.type == 'url')
                      Icon(
                        Icons.link_rounded,
                        size: 15,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (onStar != null)
            SizedBox(
              width: 26,
              child: IconButton(
                onPressed: onStar,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  msg.starred ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 18,
                  color: msg.starred
                      ? const Color(0xFFF59E0B)
                      : scheme.onSurfaceVariant.withValues(alpha: 0.35),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 折叠模式下，同一分组的多条消息收成的「组卡片」。
///
/// 只负责画这一张卡；展开后的子消息由列表页插入普通 [MessageTile]，
/// 这样每条消息的点击 / 长按 / 收藏行为都和自己单独显示时完全一致。
class MessageGroupTile extends StatelessWidget {
  const MessageGroupTile({
    super.key,
    required this.user,
    required this.msgs,
    required this.expanded,
    required this.onTap,
    this.onLongPress,
  });

  /// 分组名（消息的 user 字段）
  final String user;
  final List<MessageItem> msgs;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 列表按时间倒序，第一条就是最新的
    final latest = msgs.first;
    final unread = msgs.where((e) => !e.read).length;
    final accent = themeAccent(latest.theme, scheme);

    return SoftCard(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      padding: const EdgeInsets.fromLTRB(13, 13, 10, 12),
      radius: 18,
      onTap: onTap,
      onLongPress: onLongPress,
      color: unread > 0
          ? Color.alphaBlend(
              accent.withValues(alpha: 0.035),
              scheme.surfaceContainerLowest,
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _GroupAvatar(
            user: user,
            accent: accent,
            count: msgs.length,
            unread: unread,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        user,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.25,
                          fontWeight:
                              unread > 0 ? FontWeight.w800 : FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        formatMsgTime(latest.date),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  latest.preview.isEmpty
                      ? '（无内容）'
                      : '${latest.title.isEmpty ? '' : '${latest.title} · '}${latest.preview}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.8,
                    height: 1.5,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.95),
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Pill(
                      '${msgs.length} 条',
                      color: accent,
                      icon: Icons.layers_rounded,
                    ),
                    if (unread > 0) ...[
                      const SizedBox(width: 6),
                      Pill(
                        '$unread 条未读',
                        color: const Color(0xFFEF4444),
                        icon: Icons.fiber_manual_record_rounded,
                      ),
                    ],
                    const Spacer(),
                    Text(
                      expanded ? '收起' : '展开',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: scheme.primary.withValues(alpha: 0.9),
                      ),
                    ),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: scheme.primary.withValues(alpha: 0.9),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 组卡片头像：圆形色块 + 首字，右下角挂一个条数角标
class _GroupAvatar extends StatelessWidget {
  const _GroupAvatar({
    required this.user,
    required this.accent,
    required this.count,
    required this.unread,
  });

  final String user;
  final Color accent;
  final int count;
  final int unread;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.13),
                shape: BoxShape.circle,
              ),
              child: Text(
                user.isEmpty ? '#' : user.characters.first,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ),
          ),
          Positioned(
            right: -3,
            bottom: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              constraints: const BoxConstraints(minWidth: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: unread > 0 ? const Color(0xFFEF4444) : accent,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: scheme.surfaceContainerLowest,
                  width: 2,
                ),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontSize: 9.5,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.msg, required this.accent, required this.unread});
  final MessageItem msg;
  final Color accent;
  final bool unread;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.13),
        shape: BoxShape.circle,
      ),
      child: msg.user.isEmpty
          ? Icon(themeIcon(msg.theme), size: 19, color: accent)
          : Text(
              msg.user.characters.first,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: accent,
              ),
            ),
    );

    Widget inner;
    if (msg.face.isNotEmpty) {
      inner = ClipOval(
        child: Image.network(
          msg.face,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : fallback,
        ),
      );
    } else {
      inner = fallback;
    }

    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: inner),
          if (unread)
            Positioned(
              right: -1,
              top: -1,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: scheme.surfaceContainerLowest,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
