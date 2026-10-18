import 'dart:async';

import 'package:flutter/material.dart';

import 'models.dart';
import 'native_api.dart';
import 'theme.dart';

/// 全局应用状态：设置、连接状态、统计、原生事件。
class AppState extends ChangeNotifier {
  AppState._();

  static final AppState instance = AppState._();

  bool ready = false;
  Map<String, dynamic> settings = <String, dynamic>{};
  MqttStatus status = const MqttStatus();
  Counts counts = const Counts();
  PermStatus perms = const PermStatus();
  AppInfo info = const AppInfo();

  /// 消息列表需要重新加载的信号
  int listVersion = 0;

  /// 待打开的消（来自通知点击）
  int? pendingOpenId;

  StreamSubscription<dynamic>? _sub;
  Timer? _ticker;
  int _msgSeq = 0;

  /// 收到新消息的自增序号，用于列表页提示
  int get messageSeq => _msgSeq;

  Future<void> init() async {
    await reloadSettings();
    _listen();
    await refreshAll();
    if (ready) return;
    ready = true;
    notifyListeners();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) async {
      await refreshStatus();
    });
  }

  void _listen() {
    _sub?.cancel();
    try {
      _sub = NativeApi.events().listen(_onEvent, onError: (_) {});
    } catch (_) {
      // 非 Android 环境忽略
    }
  }

  void _onEvent(dynamic event) {
    final map = asMap(event);
    final type = asStr(map['type']);
    switch (type) {
      case 'message':
        _msgSeq++;
        listVersion++;
        refreshCounts();
        notifyListeners();
        break;
      case 'openMessage':
        pendingOpenId = asInt(map['id']);
        notifyListeners();
        break;
      case 'status':
        status = MqttStatus(
          state: asStr(map['state'], status.state),
          since: asStr(map['since'], status.since),
          self: status.self,
          host: status.host,
          port: status.port,
          enabled: status.enabled,
        );
        notifyListeners();
        break;
      case 'refresh':
        listVersion++;
        notifyListeners();
        break;
    }
  }

  int? consumePendingOpenId() {
    final id = pendingOpenId;
    pendingOpenId = null;
    return id;
  }

  // ---------------- 读取 ----------------

  Future<void> reloadSettings() async {
    try {
      settings = await NativeApi.settingsAll();
    } catch (_) {
      settings = <String, dynamic>{};
    }
    notifyListeners();
  }

  Future<void> refreshStatus() async {
    try {
      status = await NativeApi.mqttStatus();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> refreshCounts() async {
    try {
      counts = await NativeApi.counts();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> refreshPerms() async {
    try {
      perms = await NativeApi.permStatus();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> refreshAll() async {
    await Future.wait([
      refreshStatus(),
      refreshCounts(),
      refreshPerms(),
    ]);
    try {
      info = await NativeApi.appInfo();
    } catch (_) {}
    notifyListeners();
  }

  // ---------------- 设置 ----------------

  Future<void> set(String key, Object? value) async {
    settings[key] = value;
    notifyListeners();
    try {
      await NativeApi.settingsSet(key, value);
    } catch (_) {}
    await reloadSettings();
  }

  String str(String key, [String fallback = '']) =>
      settings[key] == null ? fallback : settings[key].toString();

  int integer(String key, int fallback) {
    final v = settings[key];
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  bool flag(String key, [bool fallback = false]) {
    final v = settings[key];
    if (v is bool) return v;
    if (v is num) return v != 0;
    return fallback;
  }

  double get fontScale {
    final v = settings['font_scale'];
    if (v is num) return v.toDouble().clamp(0.8, 1.4);
    return 1.0;
  }

  ThemeMode get themeMode {
    switch (str('app_theme', '系统')) {
      case '深色':
        return ThemeMode.dark;
      case '亮色':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }

  Color get seedColor => parseSeedColor(str('app_color', ''));

  bool get serviceEnabled => flag('service_enabled', true);

  bool get selfEnabled =>
      str('self_state', '关闭') == '开启' && str('self_host').isNotEmpty;

  String get activeKey => selfEnabled ? str('self_key') : str('push_key');

  String get activeHost => selfEnabled ? str('self_host') : str('mqtt_host');

  int get activePort => selfEnabled ? integer('self_port', 3100) : integer('mqtt_port', 9009);

  @override
  void dispose() {
    _sub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }
}
