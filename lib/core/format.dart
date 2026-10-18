import 'package:intl/intl.dart';

DateTime? parseMsgDate(String raw) {
  if (raw.isEmpty) return null;
  final normalized = raw.contains('T') ? raw : raw.replaceFirst(' ', 'T');
  return DateTime.tryParse(normalized);
}

String two(int n) => n.toString().padLeft(2, '0');

/// 列表里的时间：今天 14:03 / 昨天 / 10-12 / 2025-08-01
String formatMsgTime(String raw) {
  final d = parseMsgDate(raw);
  if (d == null) return raw;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return '${two(d.hour)}:${two(d.minute)}';
  if (diff == 1) return '昨天';
  if (d.year == now.year) return '${two(d.month)}-${two(d.day)}';
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

/// 详情页完整时间
String formatFullTime(String raw) {
  final d = parseMsgDate(raw);
  if (d == null) return raw;
  return DateFormat('yyyy年M月d日 HH:mm:ss').format(d);
}

/// 日期分组标题
String groupLabel(String raw) {
  final d = parseMsgDate(raw);
  if (d == null) return raw;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return '今天';
  if (diff == 1) return '昨天';
  if (diff < 7) return '$diff 天前';
  if (d.year == now.year) return '${d.month} 月 ${d.day} 日';
  return '${d.year} 年 ${d.month} 月 ${d.day} 日';
}

/// 分组用的 key（yyyy-MM-dd）
String groupKey(String raw) {
  if (raw.length >= 10) return raw.substring(0, 10);
  return raw;
}

String maskKey(String key) {
  if (key.isEmpty) return '未填写';
  if (key.length <= 8) return key;
  return '${key.substring(0, 4)}••••${key.substring(key.length - 4)}';
}

/// 14 天图表的短标签
String shortDay(String date) {
  if (date.length >= 10) {
    final m = int.tryParse(date.substring(5, 7));
    final d = int.tryParse(date.substring(8, 10));
    if (m != null && d != null) return '$m/$d';
  }
  return date;
}
