import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/format.dart';
import '../core/native_api.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  AppState get _s => AppState.instance;

  @override
  void initState() {
    super.initState();
    _s.refreshAll();
  }

  // ---------------- 编辑辅助 ----------------

  Future<void> _editText({
    required String title,
    required String key,
    String? initial,
    String? hint,
    String? helper,
    bool numeric = false,
    int maxLines = 1,
  }) async {
    final ctrl = TextEditingController(text: initial ?? _s.str(key));
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: maxLines,
              keyboardType: numeric ? TextInputType.number : TextInputType.text,
              decoration: InputDecoration(hintText: hint),
            ),
            if (helper != null) ...[
              const SizedBox(height: 10),
              Text(
                helper,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.5,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null) return;
    if (numeric) {
      final v = int.tryParse(result);
      if (v == null) {
        if (mounted) showToast(context, '请输入有效的数字');
        return;
      }
      await _s.set(key, v);
    } else {
      await _s.set(key, result);
    }
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _pickChannel() async {
    const options = <String, String>{
      '通知': '常驻状态通知，断开时响铃提醒',
      '限静': '静音时段内不响铃，状态栏仍显示',
      '静音': '状态通知不出声，状态栏仍显示',
      '限断': '连接正常时收起，仅在断开时提醒',
      '关闭': '尽力隐藏，仅通知栏下拉后可见',
    };
    final current = _s.str('channel', '限断');
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            const Text(
              '状态通知频道',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (final e in options.entries)
              RadioListTile<String>(
                value: e.key,
                groupValue: current,
                onChanged: (v) => Navigator.pop(ctx, v),
                title: Text(
                  e.key,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  e.value,
                  style: const TextStyle(fontSize: 11.5),
                ),
                dense: true,
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await _s.set('channel', picked);
    if (!mounted) return;
    setState(() {});
    showToast(context, '已切换为「$picked」');
  }

  Future<void> _sendTest() async {
    final titleCtrl = TextEditingController(text: '测试推送');
    final contentCtrl = TextEditingController(text: '来自 PushMe 重构版的一条测试消息 🎉');
    String type = 'text';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('发送测试推送'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: '标题'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentCtrl,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '内容'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(labelText: '类型'),
                items: const [
                  DropdownMenuItem(value: 'text', child: Text('文本')),
                  DropdownMenuItem(value: 'markdown', child: Text('Markdown')),
                  DropdownMenuItem(value: 'html', child: Text('HTML')),
                ],
                onChanged: (v) => setLocal(() => type = v ?? 'text'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('发送'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    showToast(context, '正在发送…');
    final res = await NativeApi.sendPush(
      title: titleCtrl.text,
      content: contentCtrl.text,
      type: type,
    );
    if (!mounted) return;
    if (res.startsWith('success')) {
      showToast(context, '发送成功，稍候即可收到');
    } else {
      showToast(context, '发送失败：${res.replaceFirst('fail:', '')}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _s,
      builder: (context, _) {
        return Scaffold(
          // 内容区限定在状态栏下方，滚动时不会压到状态栏的时间/电量上
          body: SafeArea(
            top: true,
            bottom: false,
            child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 100),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '设置',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '连接、通知与外观',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _ServiceCard(
                  onReconnect: () async {
                    await NativeApi.mqttReconnect();
                    await _s.refreshStatus();
                    if (!mounted) return;
                    showToast(context, '已请求重新连接');
                  },
                  onStop: () async {
                    await NativeApi.mqttStop();
                    await _s.refreshStatus();
                    if (!mounted) return;
                    showToast(context, '服务已停止');
                  },
                  onToggle: (v) async {
                    await _s.set('service_enabled', v);
                    if (v) {
                      await NativeApi.mqttReconnect();
                    } else {
                      await NativeApi.mqttStop();
                    }
                    await _s.refreshStatus();
                  },
                ),
              ),
              SectionHeader('推送服务'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SoftCard(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      _sourceSwitch(context),
                      if (_s.selfEnabled || _s.str('self_state') == '开启') ...[
                        const Divider(height: 1),
                        SettingTile(
                          icon: Icons.dns_rounded,
                          title: '服务器地址',
                          subtitle: _s.str('self_host').isEmpty
                              ? '未填写'
                              : _s.str('self_host'),
                          onTap: () => _editText(
                            title: '自建服务器地址',
                            key: 'self_host',
                            hint: '例如 push.example.com',
                          ),
                        ),
                        const Divider(height: 1),
                        SettingTile(
                          icon: Icons.settings_ethernet_rounded,
                          title: '端口',
                          subtitle: '${_s.integer('self_port', 3100)}',
                          onTap: () => _editText(
                            title: '自建服务器 MQTT 端口',
                            key: 'self_port',
                            numeric: true,
                            hint: '3100',
                          ),
                        ),
                        const Divider(height: 1),
                        SettingTile(
                          icon: Icons.lock_rounded,
                          title: 'TLS 加密',
                          subtitle: _s.str('self_tls', '无证书'),
                          onTap: () => _pickSelfTls(),
                        ),
                        const Divider(height: 1),
                        SettingTile(
                          icon: Icons.vpn_key_rounded,
                          title: 'Push Key',
                          subtitle: maskKey(_s.str('self_key')),
                          trailing: IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: _s.str('self_key')),
                              );
                              if (!mounted) return;
                              showToast(context, '已复制');
                            },
                          ),
                          onTap: () => _editText(
                            title: '自建 Push Key',
                            key: 'self_key',
                            hint: '与服务端 config.pushKeys 中一致',
                          ),
                        ),
                        const Divider(height: 1),
                        SettingTile(
                          icon: Icons.api_rounded,
                          title: '推送接口',
                          subtitle: _s.str('self_api').isEmpty
                              ? '未填写（发送测试需要）'
                              : _s.str('self_api'),
                          onTap: () => _editText(
                            title: '推送 HTTP 接口',
                            key: 'self_api',
                            hint: 'https://push.example.com',
                          ),
                        ),
                      ] else ...[
                        const Divider(height: 1),
                        SettingTile(
                          icon: Icons.dns_rounded,
                          title: '服务器地址',
                          subtitle: _s.str('mqtt_host').isEmpty
                              ? '未填写'
                              : _s.str('mqtt_host'),
                          onTap: () => _editText(
                            title: '服务器地址',
                            key: 'mqtt_host',
                            hint: '例如 192.168.1.10',
                          ),
                        ),
                        const Divider(height: 1),
                        SettingTile(
                          icon: Icons.settings_ethernet_rounded,
                          title: '端口',
                          subtitle: '${_s.integer('mqtt_port', 9009)}',
                          onTap: () => _editText(
                            title: 'MQTT 端口',
                            key: 'mqtt_port',
                            numeric: true,
                            hint: '9009',
                          ),
                        ),
                        const Divider(height: 1),
                        SettingTile(
                          icon: Icons.lock_rounded,
                          title: 'TLS 加密',
                          subtitle: _s.str('mqtt_tls', '开启'),
                          trailing: Switch(
                            value: _s.str('mqtt_tls', '开启') == '开启',
                            onChanged: (v) =>
                                _s.set('mqtt_tls', v ? '开启' : '关闭'),
                          ),
                          onTap: () => _s.set(
                            'mqtt_tls',
                            _s.str('mqtt_tls', '开启') == '开启' ? '关闭' : '开启',
                          ),
                        ),
                        const Divider(height: 1),
                        SettingTile(
                          icon: Icons.vpn_key_rounded,
                          title: 'Push Key',
                          subtitle: maskKey(_s.str('push_key')),
                          trailing: IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: _s.str('push_key')),
                              );
                              if (!mounted) return;
                              showToast(context, '已复制');
                            },
                          ),
                          onTap: () => _editText(
                            title: 'Push Key',
                            key: 'push_key',
                            hint: '推送服务分配的 key',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              SectionHeader('通知'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SoftCard(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      SettingTile(
                        icon: Icons.tune_rounded,
                        title: '状态通知频道',
                        subtitle: _s.str('channel', '限断'),
                        onTap: _pickChannel,
                      ),
                      const Divider(height: 1),
                      SettingTile(
                        icon: Icons.notifications_active_rounded,
                        title: '通知权限',
                        subtitle: _s.perms.notifications ? '已允许' : '未开启，收不到提醒',
                        trailing: _permBadge(_s.perms.notifications),
                        onTap: () => NativeApi.open('notification'),
                      ),
                      const Divider(height: 1),
                      SettingTile(
                        icon: Icons.battery_saver_rounded,
                        title: '电池优化',
                        subtitle: _s.perms.battery ? '已忽略限制（推荐）' : '未加入白名单',
                        trailing: _permBadge(_s.perms.battery),
                        onTap: () => NativeApi.open('battery'),
                      ),
                      if (_s.info.model.toUpperCase().contains('SAMSUNG')) ...[
                        const Divider(height: 1),
                        SettingTile(
                          icon: Icons.bolt_rounded,
                          title: '三星：自启动管理',
                          subtitle: '保持后台连接不被清理',
                          onTap: () => NativeApi.open('samsungAutoStart'),
                        ),
                      ],
                      const Divider(height: 1),
                      SettingTile(
                        icon: Icons.settings_suggest_rounded,
                        title: '应用设置页',
                        subtitle: '权限、后台运行等系统设置',
                        onTap: () => NativeApi.open('app'),
                      ),
                    ],
                  ),
                ),
              ),
              SectionHeader('外观'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SoftCard(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '主题模式',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<String>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                              value: '系统',
                              label: Text('跟随系统'),
                              icon: Icon(Icons.brightness_auto_rounded, size: 16),
                            ),
                            ButtonSegment(
                              value: '亮色',
                              label: Text('浅色'),
                              icon: Icon(Icons.light_mode_rounded, size: 16),
                            ),
                            ButtonSegment(
                              value: '深色',
                              label: Text('深色'),
                              icon: Icon(Icons.dark_mode_rounded, size: 16),
                            ),
                          ],
                          selected: {_s.str('app_theme', '系统')},
                          onSelectionChanged: (v) =>
                              _s.set('app_theme', v.first),
                          style: ButtonStyle(
                            textStyle: WidgetStatePropertyAll(
                              TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '主题色',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: kColorPresets.map((p) {
                          final selected = _s.seedColor.toARGB32() ==
                              p.color.toARGB32();
                          return GestureDetector(
                            onTap: () => _s.set('app_color', colorToHex(p.color)),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: p.color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: selected
                                      ? scheme.onSurface
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: selected
                                  ? const Icon(
                                      Icons.check_rounded,
                                      color: Colors.white,
                                      size: 19,
                                    )
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Text(
                            '字号',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${(_s.fontScale * 100).round()}%',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: scheme.primary,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _s.fontScale,
                        min: 0.85,
                        max: 1.3,
                        divisions: 9,
                        label: '${(_s.fontScale * 100).round()}%',
                        onChanged: (v) => _s.set('font_scale', v),
                      ),
                      Center(
                        child: Text(
                          '推送消息默认按「${_s.str('msg_read_init', '未读')}」保存',
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                  ),
                ),
              ),
              SectionHeader('其他'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SoftCard(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      SettingTile(
                        icon: Icons.send_rounded,
                        title: '发送测试推送',
                        subtitle: '通过当前配置的推送接口发一条',
                        onTap: _sendTest,
                      ),
                      const Divider(height: 1),
                      SettingTile(
                        icon: Icons.history_rounded,
                        title: '历史数据',
                        subtitle: '已导入旧版 ${_s.counts.total} 条消息',
                        onTap: () => showToast(
                          context,
                          '旧版消息已随安装包导入，删除后不可恢复',
                        ),
                      ),
                      const Divider(height: 1),
                      SettingTile(
                        icon: Icons.info_outline_rounded,
                        title: '关于',
                        subtitle:
                            'v${_s.info.version} · ${_s.info.model} · Android ${_s.info.android}',
                        onTap: () => _showAbout(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: Text(
                  'PushMe · Flutter 重构版\n数据全部保存在本机',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.6,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ],
            ),
          ),
        );
      },
    );
  }

  Widget _permBadge(bool ok) {
    return Pill(
      ok ? '正常' : '待处理',
      color: ok ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
      filled: true,
    );
  }

  Widget _sourceSwitch(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final self = _s.str('self_state', '关闭') == '开启';
    Widget item(String label, IconData icon, bool selected, VoidCallback tap) {
      return Expanded(
        child: GestureDetector(
          onTap: tap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? scheme.primary.withValues(alpha: 0.35)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        item('官方服务', Icons.cloud_rounded, !self, () async {
          await _s.set('self_state', '关闭');
          if (!mounted) return;
          setState(() {});
        }),
        item('自建服务器', Icons.dns_rounded, self, () async {
          await _s.set('self_state', '开启');
          if (!mounted) return;
          setState(() {});
        }),
      ],
    );
  }

  Future<void> _pickSelfTls() async {
    final current = _s.str('self_tls', '无证书');
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            const Text(
              'TLS 加密方式',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            for (final e in const {
              '无证书': '明文连接，适合内网或反代已终止 TLS',
              '公共证书': '使用系统信任链校验（Let\'s Encrypt 等）',
              '自签证书': '使用下方填写的自签名 PEM 证书',
            }.entries)
              RadioListTile<String>(
                value: e.key,
                groupValue: current,
                onChanged: (v) => Navigator.pop(ctx, v),
                title: Text(
                  e.key,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(e.value, style: const TextStyle(fontSize: 11.5)),
                dense: true,
              ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.description_outlined, size: 20),
              title: const Text(
                '编辑自签证书',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                _s.str('self_cert').isEmpty ? '未填写' : '已填写 PEM',
                style: const TextStyle(fontSize: 11.5),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _editText(
                  title: '自签证书（PEM）',
                  key: 'self_cert',
                  maxLines: 8,
                  hint: '-----BEGIN CERTIFICATE-----',
                );
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await _s.set('self_tls', picked);
    if (!mounted) return;
    setState(() {});
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('关于 PushMe'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'PushMe · Flutter 重构版',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            _aboutRow('版本', 'v${_s.info.version}'),
            _aboutRow('设备', _s.info.model),
            _aboutRow('系统', 'Android ${_s.info.android}'),
            _aboutRow('消息', '${_s.counts.total} 条 / 未读 ${_s.counts.unread}'),
            _aboutRow('连接', '${_s.status.label} · ${_s.activeHost}:${_s.activePort}'),
            const SizedBox(height: 12),
            Text(
              '基于 MQTT 的私有推送客户端。消息仅保存在本机数据库，不上传任何第三方服务器。',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.6,
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Widget _aboutRow(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Text(
              k,
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.onReconnect,
    required this.onStop,
    required this.onToggle,
  });

  final Future<void> Function() onReconnect;
  final Future<void> Function() onStop;
  final Future<void> Function(bool) onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = AppState.instance.status;
    final connected = s.isConnected;
    final seed = AppState.instance.seedColor;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(seed.withValues(alpha: 0.92), scheme.primary),
            Color.alphaBlend(
              Color.lerp(seed, const Color(0xFF7C3AED), 0.45)!,
              scheme.primary,
            ),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: seed.withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      connected ? '推送服务运行中' : '推送服务${s.label}',
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppState.instance.serviceEnabled
                          ? '${s.host}:${s.port}'
                          : '服务已手动关闭',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              Transform.scale(
                scale: 0.86,
                child: Switch(
                  value: AppState.instance.serviceEnabled,
                  onChanged: onToggle,
                  thumbColor: const WidgetStatePropertyAll(Colors.white),
                  trackColor: WidgetStatePropertyAll(
                    Colors.white.withValues(alpha: 0.35),
                  ),
                  trackOutlineColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _metric(
                connected ? '连接于' : '状态',
                connected ? s.since : s.label,
              ),
              const SizedBox(width: 18),
              _metric('分组', AppState.instance.str('push_key').isEmpty ? '—' : '已配置'),
              const Spacer(),
              _action(Icons.refresh_rounded, '重连', onReconnect),
              const SizedBox(width: 8),
              _action(Icons.stop_rounded, '停止', onStop),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _action(IconData icon, String label, Future<void> Function() tap) {
    return GestureDetector(
      onTap: () => tap(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
