import 'package:flutter/services.dart';

import 'models.dart';

/// 原生能力桥接。
/// 通道名与 MainActivity.kt 中保持一致。
class NativeApi {
  static const MethodChannel _ch = MethodChannel('com.daimadog.pushme/native');
  static const EventChannel _ev = EventChannel('com.daimadog.pushme/events');

  /// 原生事件流：消息、连接状态、通知点击
  static Stream<dynamic> events() => _ev.receiveBroadcastStream();

  // ---------------- 设置 ----------------

  static Future<Map<String, dynamic>> settingsAll() async {
    final r = await _ch.invokeMethod<dynamic>('settings.getAll');
    return asMap(r);
  }

  static Future<bool> settingsSet(String key, Object? value) async {
    final r = await _ch.invokeMethod<bool>('settings.set', {
      'key': key,
      'value': value,
    });
    return r ?? false;
  }

  // ---------------- 连接 ----------------

  static Future<MqttStatus> mqttStatus() async =>
      MqttStatus.fromMap(asMap(await _ch.invokeMethod<dynamic>('mqtt.status')));

  static Future<bool> mqttReconnect() async =>
      await _ch.invokeMethod<bool>('mqtt.reconnect') ?? false;

  static Future<bool> mqttStop() async =>
      await _ch.invokeMethod<bool>('mqtt.stop') ?? false;

  // ---------------- 消息 ----------------

  static Future<({int total, List<MessageItem> items})> messagesList({
    int offset = 0,
    int limit = 40,
    String query = '',
    String field = '标题+内容',
    String theme = '全部',
    String status = '全部',
    String sortBy = '时间',
    String sort = 'desc',
  }) async {
    final r = asMap(await _ch.invokeMethod<dynamic>('messages.list', {
      'offset': offset,
      'limit': limit,
      'query': query,
      'field': field,
      'theme': theme,
      'status': status,
      'sortBy': sortBy,
      'sort': sort,
    }));
    final items = asList(r['items'])
        .map((e) => MessageItem.fromMap(asMap(e)))
        .toList(growable: false);
    return (total: asInt(r['total']), items: items);
  }

  static Future<MessageItem?> messageGet(int id) async {
    final r = await _ch.invokeMethod<dynamic>('messages.get', {'id': id});
    if (r == null) return null;
    return MessageItem.fromMap(asMap(r));
  }

  static Future<void> markRead(List<int> ids, bool read) =>
      _ch.invokeMethod('messages.mark', {'ids': ids, 'read': read});

  static Future<void> star(List<int> ids, bool star) =>
      _ch.invokeMethod('messages.star', {'ids': ids, 'star': star});

  static Future<void> delete(List<int> ids) =>
      _ch.invokeMethod('messages.delete', {'ids': ids});

  static Future<void> clearAll() => _ch.invokeMethod('messages.clearAll');

  static Future<void> markAllRead() =>
      _ch.invokeMethod('messages.markAllRead');

  static Future<Counts> counts() async =>
      Counts.fromMap(asMap(await _ch.invokeMethod<dynamic>('messages.counts')));

  static Future<Stats> stats() async =>
      Stats.fromMap(asMap(await _ch.invokeMethod<dynamic>('messages.stats')));

  // ---------------- 权限 ----------------

  static Future<bool> notificationsEnabled() async =>
      await _ch.invokeMethod<bool>('notify.permission') ?? false;

  static Future<bool> requestNotification() async =>
      await _ch.invokeMethod<bool>('notify.request') ?? false;

  static Future<PermStatus> permStatus() async =>
      PermStatus.fromMap(asMap(await _ch.invokeMethod<dynamic>('perm.status')));

  static Future<void> requestPhoneState() =>
      _ch.invokeMethod('perm.requestPhone');

  // ---------------- 其他 ----------------

  /// target: notification / app / battery / batteryList / alarm / home /
  ///         samsungAutoStart / samsungBg
  static Future<void> open(String target) =>
      _ch.invokeMethod('open', {'target': target});

  static Future<void> toast(String text) =>
      _ch.invokeMethod('toast', {'text': text});

  static Future<AppInfo> appInfo() async =>
      AppInfo.fromMap(asMap(await _ch.invokeMethod<dynamic>('app.info')));

  /// 通过 HTTP 接口发送一条测试推送，返回 success:... / fail:...
  static Future<String> sendPush({
    required String title,
    required String content,
    String type = '',
  }) async {
    final r = await _ch.invokeMethod<String>('send.push', {
      'title': title,
      'content': content,
      'type': type,
    });
    return r ?? 'fail:unknown';
  }

  static Future<bool> seedImported() async =>
      await _ch.invokeMethod<bool>('seed.imported') ?? false;
}
