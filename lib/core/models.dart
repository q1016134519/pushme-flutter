/// 与原生层（Kotlin）对齐的数据模型
library;

Map<String, dynamic> asMap(dynamic v) {
  if (v is Map) {
    return v.map((k, value) => MapEntry(k.toString(), value));
  }
  return <String, dynamic>{};
}

List<dynamic> asList(dynamic v) => v is List ? v : const <dynamic>[];

int asInt(dynamic v, [int fallback = 0]) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

String asStr(dynamic v, [String fallback = '']) =>
    v == null ? fallback : v.toString();

bool asBool(dynamic v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  return fallback;
}

class MessageItem {
  final int id;
  final String title;
  final String content;
  final String date;
  final String type;
  final bool read;
  final bool starred;
  final String user;
  final String face;
  final String theme;
  final String preview;

  const MessageItem({
    required this.id,
    required this.title,
    required this.content,
    required this.date,
    required this.type,
    required this.read,
    required this.starred,
    required this.user,
    required this.face,
    required this.theme,
    required this.preview,
  });

  factory MessageItem.fromMap(Map<dynamic, dynamic> m) => MessageItem(
        id: asInt(m['id']),
        title: asStr(m['title']),
        content: asStr(m['content']),
        date: asStr(m['date']),
        type: asStr(m['type']),
        read: asBool(m['read'], true),
        starred: asBool(m['star']),
        user: asStr(m['user']),
        face: asStr(m['face']),
        theme: asStr(m['theme']),
        preview: asStr(m['preview']),
      );

  MessageItem copyWith({bool? read, bool? starred}) => MessageItem(
        id: id,
        title: title,
        content: content,
        date: date,
        type: type,
        read: read ?? this.read,
        starred: starred ?? this.starred,
        user: user,
        face: face,
        theme: theme,
        preview: preview,
      );

  /// 用于列表比较：同一 id + 已读/收藏状态一致则视为同一项
  bool sameContentAs(MessageItem o) =>
      id == o.id && read == o.read && starred == o.starred;
}

class Counts {
  final int total;
  final int unread;
  final int starred;

  const Counts({this.total = 0, this.unread = 0, this.starred = 0});

  factory Counts.fromMap(Map<dynamic, dynamic> m) => Counts(
        total: asInt(m['total']),
        unread: asInt(m['unread']),
        starred: asInt(m['starred']),
      );
}

class NameCount {
  final String name;
  final int count;

  const NameCount(this.name, this.count);

  factory NameCount.fromMap(Map<dynamic, dynamic> m) =>
      NameCount(asStr(m['name']), asInt(m['count']));
}

class DayCount {
  final String date;
  final int count;

  const DayCount(this.date, this.count);

  factory DayCount.fromMap(Map<dynamic, dynamic> m) =>
      DayCount(asStr(m['date']), asInt(m['count']));
}

class Stats {
  final int info;
  final int success;
  final int warning;
  final int failure;
  final int plain;
  final List<NameCount> byType;
  final List<NameCount> byUser;
  final List<DayCount> byDay;

  const Stats({
    this.info = 0,
    this.success = 0,
    this.warning = 0,
    this.failure = 0,
    this.plain = 0,
    this.byType = const [],
    this.byUser = const [],
    this.byDay = const [],
  });

  int get themed => info + success + warning + failure;

  factory Stats.fromMap(Map<dynamic, dynamic> m) {
    final theme = asMap(m['byTheme']);
    return Stats(
      info: asInt(theme['i']),
      success: asInt(theme['s']),
      warning: asInt(theme['w']),
      failure: asInt(theme['f']),
      plain: asInt(theme['none']),
      byType: asList(m['byType'])
          .map((e) => NameCount.fromMap(asMap(e)))
          .toList(growable: false),
      byUser: asList(m['byUser'])
          .map((e) => NameCount.fromMap(asMap(e)))
          .toList(growable: false),
      byDay: asList(m['byDay'])
          .map((e) => DayCount.fromMap(asMap(e)))
          .toList(growable: false),
    );
  }
}

class MqttStatus {
  final String state;
  final String since;
  final bool self;
  final String host;
  final int port;
  final bool enabled;

  const MqttStatus({
    this.state = 'Closed',
    this.since = '--:--:--',
    this.self = false,
    this.host = '',
    this.port = 0,
    this.enabled = false,
  });

  factory MqttStatus.fromMap(Map<dynamic, dynamic> m) => MqttStatus(
        state: asStr(m['state'], 'Closed'),
        since: asStr(m['since'], '--:--:--'),
        self: asBool(m['self']),
        host: asStr(m['host']),
        port: asInt(m['port']),
        enabled: asBool(m['enabled']),
      );

  bool get isConnected => state == 'Connected';

  String get label {
    switch (state) {
      case 'Connected':
        return '已连接';
      case 'Connecting':
        return '连接中';
      case 'Disconnected':
        return '已断开';
      case 'Closed':
        return '已停止';
      case '未配置':
        return '未配置';
      default:
        return state;
    }
  }
}

class PermStatus {
  final bool notifications;
  final bool battery;
  final bool exactAlarm;
  final bool phoneState;

  const PermStatus({
    this.notifications = false,
    this.battery = false,
    this.exactAlarm = false,
    this.phoneState = false,
  });

  factory PermStatus.fromMap(Map<dynamic, dynamic> m) => PermStatus(
        notifications: asBool(m['notifications']),
        battery: asBool(m['battery']),
        exactAlarm: asBool(m['exactAlarm']),
        phoneState: asBool(m['phoneState']),
      );
}

class AppInfo {
  final String version;
  final String model;
  final String android;

  const AppInfo({
    this.version = '1.0.0',
    this.model = '',
    this.android = '',
  });

  factory AppInfo.fromMap(Map<dynamic, dynamic> m) => AppInfo(
        version: asStr(m['version'], '1.0.0'),
        model: asStr(m['model']),
        android: asStr(m['android']),
      );
}

/// 消息类型的中文说明
String typeLabel(String type) {
  switch (type) {
    case 'text':
    case '':
      return '文本';
    case 'markdown':
      return 'Markdown';
    case 'html':
      return 'HTML';
    case 'url':
      return '链接';
    case 'data':
      return '数据';
    case 'chart':
      return '图表';
    case 'echarts':
      return 'ECharts';
    case 'svg':
      return 'SVG';
    default:
      return type;
  }
}
