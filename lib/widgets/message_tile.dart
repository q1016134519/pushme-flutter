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
