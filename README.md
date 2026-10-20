# PushMe

自建推送服务的 Android 客户端 —— **Flutter 重构版**。

原版（`com.android.pushme`）用原生 Java 写成，功能完整但界面陈旧。这个版本把 UI 整体用 Flutter 重写，
交互与视觉全面对齐 Material 3，功能一项不少：MQTT over TCP 直连、消息本地落库、三类内容渲染、统计看板、深浅色主题。

> 本项目是**客户端**，不含服务端。推送服务需要你自己部署并配合其 HTTP 推送接口使用。
> 服务端与 Windows 桌面端见下方 [相关项目](#相关项目与致谢)。

---

## 下载

前往 [**Releases**](https://github.com/q1016134519/pushme-flutter/releases/latest) 下载 APK：

| 文件 | 大小 | 适用设备 |
| --- | --- | --- |
| `PushMe-5.1.0-arm64-v8a.apk` | 22 MB | **绝大多数手机（推荐）** |
| `PushMe-5.1.0-armeabi-v7a.apk` | 20 MB | 老 32 位设备 |
| `PushMe-5.1.0-x86_64.apk` | 23 MB | 模拟器 / 平板 / ChromeOS |
| `PushMe-5.1.0-universal.apk` | 59 MB | 不确定架构时用，三合一 |

不确定就选 `universal`。

### 安装

```bash
adb install -r PushMe-5.1.0-arm64-v8a.apk
```

或直接把 APK 拷进手机点击安装。包名 `com.daimadog.pushme`，与原版并存，可随时回退。

**首次使用**：设置页填写服务器地址与 Push Key，打开顶部推送服务开关。

### ⚠️ 关于版本号

Flutter 的 `--split-per-abi` 会给每个 ABI 加版本号偏移：

| 变体 | versionCode |
| --- | --- |
| armeabi-v7a | 1054 |
| arm64-v8a | 2054 |
| x86_64 | 4054 |
| universal | 54 |

Android 不允许降级安装。**已在用 arm64 包就不要换 universal**（会报
`INSTALL_FAILED_VERSION_DOWNGRADE`），反过来 universal → arm64 是升级，可以直接装。
四个包签名一致，可以互相覆盖。

---

## 功能

| 模块 | 说明 |
| --- | --- |
| 消息列表 | 按日期分组、类型标签、未读徽标、下拉刷新、长按操作 |
| 消息详情 | text / markdown / html 三种格式渲染，收藏、复制、删除 |
| 数据概览 | 消息总数 / 今日收到 / 未读 / 收藏，14 天趋势柱状图，主题分布 |
| 设置 | 自建服务器 / 官方服务双模式、Push Key、端口、TLS、通道、消息分组、主题、导入导出 |
| 后台服务 | MQTT over TCP 长连接；「通知/限静/静音」用前台服务常驻（`specialUse`），「限断/关闭」用闹钟心跳的普通后台服务；断线自动重连 |
| 主题 | 跟随系统 / 浅色 / 深色，Material 3 配色 |

### 消息分组：折叠 / 展开

「设置 → 通知 → 消息分组」，两档，**默认展开**：

| 档位 | 行为 |
| --- | --- |
| 展开 | 每条消息各自一条通知，互不归档（与原版 PushMe 一致） |
| 折叠 | 同组消息收进一张「N 条新消息」卡片，点开才逐条显示 |

实现上，所有消息通知都带同一个 group key（`pushme`）；**决定是否归档的是那张
group summary 卡片**——它在就收进一张，不在就平铺。所以切换设置不需要把已有通知
重发一遍，只要贴/撤这张卡片（`Notifier.applyGroupMode`）。

注意：卡片本身设了 `GROUP_ALERT_CHILDREN`，**只让组内子通知响铃**，避免来一条消息响两遍。

### 状态通知的行为

「状态通知频道」的五个档位：

| 选项 | 连接正常 | 断开时 |
| --- | --- | --- |
| 通知 | 显示，响铃 | 显示，响铃 |
| 限静 | 显示，静音时段内静默 | 显示，静音时段内静默 |
| 静音 | 显示，不出声、不亮屏 | 显示，不出声、不亮屏 |
| **限断** | **不显示（0 条）** | 显示，响铃 |
| **关闭** | **不显示（0 条）** | 不显示，不提醒 |

#### 两种运行方式：前台服务 vs 普通后台服务

五个档位走的是两条完全不同的路径（判据见 `Prefs.needsForeground`）：

**「通知 / 限静 / 静音」—— 前台服务常驻。** 这三档本来就要显示状态，挂前台服务换更强的进程保护。

**「限断 / 关闭」—— 普通后台服务，通知栏干净。** 这两档的原意就是「别占通知栏」，
所以压根不用 `startForegroundService`，改走普通 `startService`，连上之后一条通知都不留；
「限断」只在真的断开时发一条普通通知（会响），「关闭」连这条都不发。

> 注意：不能「先进前台、再摘掉」。Android 12+ 禁止后台进程重新进入前台，
> 一旦 `stopForeground` 掉出前台，之后 `startForeground()` 会抛
> `ForegroundServiceStartNotAllowedException`，永远回不去。所以这两档是**从一开始就不进前台**。

#### 锁屏不掉线的第一层：心跳用闹钟，不用定时器

早期版本（以及 Paho 的默认行为）用 `TimerPingSender`，它本质上是一个 `java.util.Timer` 线程。
**锁屏后设备进入 suspend，所有用户态线程一起停摆**，定时器自然到点不执行 —— 一个 `PINGREQ`
都发不出去。broker（Aedes）按 `keepalive × 1.5` 判超时，到点没收到报文就 `close('keepalive timeout')`。

现在心跳由 `PushAlarm` + `PingReceiver` 驱动：

- `AlarmManager.setExactAndAllowWhileIdle(RTC_WAKEUP, ...)` 排下一次唤醒 —— 这是唯一能把 CPU
  从 suspend 里精确叫醒、并且能穿透 Doze 的机制（原版 `com.android.pushme` 用的是同一套：
  反编译可见 `AlarmPingSender` 的 type 0 + `PUSHME[AlarmPingSender]` 日志）。
- `PingReceiver` 在 `onReceive` 里先持 `PARTIAL_WAKE_LOCK` 12 秒。**12 秒不是拍脑袋**：从 suspend
  醒来后 WiFi 芯片要几秒才恢复到能收发，只持 3 秒会在 `PINGRESP` 回来之前就被重新挂起，
  下一次心跳直接判定超时断开（真机上就是这么坏的，见下）。
- `onReceive` 跑在主线程，**不能等 ping 的结果**（最长 10s 会 ANR），只调 `checkForActivity()` 就返回。
- `MqttClient` 的构造器不接受自定义 `MqttPingSender`，所以用 `MqttAsyncClient`。

#### 第二层：闹钟链必须无条件续命，且不能被 MQTT 客户端关掉

这一层踩过两个坑，都是「进程活着但永远不再醒」：

1. **`pingSender.stop()` 里不能 `alarmManager.cancel()`。** Paho 在 ping 超时、broker 断开、
   手动 disconnect 时都会调 `stop()`；旧实现顺手把闹钟取消掉，唯一的唤醒源被自己关了。
2. **不能依赖 Paho 在失败路径上 `schedule()`。** ping 超时那一次它不会再排下一次。

现在闹钟归 `PushAlarm` 管，生命周期只跟「服务是否启用」绑定；`PingReceiver` 里
**第一件事就是无条件续上下一次唤醒**，然后再去干活。

真机实测（旧版本，SM-S9310）：
```
20:26:08 / 20:26:59 / 20:31:59  闹钟响了 3 次
之后 45 分钟              dumpsys alarm 里 0 次唤醒，CPU 时间几乎不增长
```

#### 第三层：三星的 Freecess 会把后台进程冻住（这是真机上最关键的一条）

三星 One UI 的 `FreecessController` 会在应用退到后台后 **6~22 秒**把整个进程冻结（cgroup freezer），
和 Doze、电池白名单都无关：

```
21:31:24  FZ  : com.daimadog.pushme reason: Bg          ← 切后台就被冻
21:34:52  UFZ : com.daimadog.pushme reason: Alarm       ← 闹钟到点才解冻
21:34:58  FZ  : com.daimadog.pushme reason: Bg          ← 6 秒后又冻回去
21:34:58  disable frozen app (com.daimadog.pushme) wakelock.  ← 顺带收走唤醒锁
```

冻结期间进程一行日志都不出、Handler 不跑、socket 读线程停摆。**这不是我们代码的问题
—— 同一台机器上的原版 `com.android.pushme` 被冻得一模一样**（`FZ : com.android.pushme reason: Bg`），
它“看起来没掉线”是因为：

- **TCP 连接在冻结期间一直保持 `ESTABLISHED`**，内核替它守着 socket，报文堆在接收缓冲区；
- 每次闹钟解冻时把缓冲的报文读走、把 `PINGREQ` 发出去；
- **三星在收到网络包时会主动解冻**（`UFZ ... reason: Packet`），所以只要连接还活着，消息投递是即时的。

对应的实现：

- `PingReceiver` **必须在 AndroidManifest 里注册**。闹钟由系统持有，进程被杀后闹钟照样会响；
  动态注册的接收器会随进程一起消失，广播没人收，进程也就再也起不来了。清单注册之后，
  这一次广播能把进程（连同 `MqttService`）重新拉起来。
- 每次唤醒都走一次 `MqttService.onTick()`：**要么确认链路真的活着，要么立刻重连**，不留任何
  「什么都不做」的分支（判活方式见第五层）。实测：检测到连接失效后 **10 秒**自动重连成功。
- 亮屏 / 解锁（`ACTION_SCREEN_ON` / `ACTION_USER_PRESENT`）也触发一次 `onTick()`，
  这是「解锁后不恢复」的直接对症药 —— 即使闹钟链意外断了，用户一解锁也能马上接回来。
- 网络恢复回调（`registerDefaultNetworkCallback`）同样兜一层。

#### 第四层：断线提醒要有宽限期

因为上面的冻结机制，连接会周期性地「假死 → 判超时 → 重连」，一次只要几百毫秒。
如果「限断」档一断就弹通知，用户会每隔几分钟被响一次。所以断开后 **45 秒内不提醒**，
真正长时间连不上才弹；同一次断线只提醒一次（用户划掉后不会反复冒出来）。

#### 第五层：永远不要相信 `isConnected`（僵尸连接）

这一条是 5.3.0 才查出来的，也是最隐蔽的一条。

`MqttAsyncClient.isConnected` 只是 Paho 自己的一个布尔标志。进程被冻结、broker 早已把会话
踢掉之后，它**依然是 `true`**，socket 也依然挂着 `ESTABLISHED`。真机上实测到的现象是：

```
21:51:55  FZ : com.daimadog.pushme reason: LEV          ← 熄屏后被冻
21:56:53  发布一条测试消息 →  手机无任何反应（无 UFZ reason: Packet，通知栏也没有）
21:57:50  UFZ reason: Alarm → "tick: connected, keepalive check"   ← 仍认为连着
21:58:24  亮屏 → "tick: connected, keepalive check"                ← 仍认为连着
```

根因是 **Paho 判断「该发 PINGREQ 了没 / ping 超时了没」用的是 `System.nanoTime()`**
（Linux 上对应 `CLOCK_MONOTONIC`），而**设备 suspend（熄屏、Doze）期间这个时钟是不走的**：

1. 进程被 Freecess 冻住、设备进 suspend，Paho 醒来后认为「才过了一瞬间」；
2. 于是它永远不满足发 `PINGREQ` 的条件，一个心跳都不发；
3. broker 按**真实时间** `keepAlive × 1.5 = 450 秒` 判定会话超时，把客户端踢掉；
4. 客户端毫无察觉 —— 连接变成一条「僵尸」，收不到任何消息，也不会重连。

所以判活改为**协议层面的真实往返**：每次巡检往 `<topic>/hb` 发一条空的 **QoS1** 消息，
等 broker 回 `PUBACK`（实测 10~30 毫秒）。QoS1 的回执不依赖任何本地时钟：

- 收到 `PUBACK` → 链路确实活着；
- 12 秒内没等到 → 立刻 `disconnectForcibly()` + 重建客户端重连。

这条 `PUBLISH` 本身就是出站流量，会刷新 broker 的 keepalive 计时器，所以 240 秒的巡检
节拍同时也是心跳，不再额外发 `PINGREQ`。原版 `com.android.pushme` 的
`[MQTTAlarmReconnect]` 闹钟做的正是「定期推倒重连」这件事，这里用协议回执代替它。

顺带修掉一个副作用：`AlarmMqttPingSender.schedule()` 现在**故意什么都不做**。
Paho 每次算「下次什么时候发 ping」都会调它，但同样因为 `nanoTime` 不走，它算出的间隔是错的
——真机实测把稳定的 240 秒节拍打成了 `121s / 71s` 乱跳，多叫醒 CPU 却发不出真正的 ping。

> 代价：连接在冻结期间死掉是必然的，消息在「死掉 → 下次巡检」这段窗口内会丢。
> 实测这段窗口最长约等于一个巡检周期（240 秒）。在「限断」档（无前台服务）下，
> 这是 Android + 三星冻结机制下的物理下限；要彻底不丢，需要 broker 侧持久会话
> （`cleanSession=false` + 服务端 QoS≥1），属于服务端配置。

#### 其他保活措施

- 服务类型用 `specialUse`（`PROPERTY_SPECIAL_USE_FGS_SUBTYPE=persistent_mqtt_push_connection`）。
  不能用 `dataSync`：Android 15 起 `dataSync` 前台服务累计跑满 6 小时会被系统强制停止。
- `keepAliveInterval = 300s`，由闹钟驱动。原版实测也是 300s（`dumpsys alarm` 里两次
  `[AlarmPingSender]` 的间隔正好 305 秒），所以这是经过验证的取值。
  别为了「更快发现断线」压到 60~120s：每次心跳都要把 CPU 从 suspend 里叫醒一次。
- `PushAlarm.INTERVAL_CONNECTED = 240s`：巡检间隔必须小于 keepAlive，给唤醒抖动留 60 秒余量。
- `AlarmManager` 用 `RTC_WAKEUP` 精确闹钟，manifest 声明 `USE_EXACT_ALARM`（普通权限、装完即生效）。
  若系统仍拒绝精确闹钟，代码会退化成 `setAndAllowWhileIdle`（Doze 下约 9 分钟一次），比「不发」好得多。
  启动日志会打印 `exactAlarm=true/false`，方便排查。
- `START_STICKY` + `stopWithTask="false"`：划掉最近任务不清服务。
- `BootReceiver` 开机自启。

#### 关于电池优化白名单

Android 8+ 有一条**与 Doze 无关**的规则：app 进入后台数分钟后，系统会以
`Stopping service due to app idle` 停掉它的后台服务（模拟器 Android 11 实测约 4 分钟触发）。
`dumpsys deviceidle whitelist +<pkg>` 加白名单后就不再停。

但要注意：**白名单挡不住三星的 Freecess**。真机上两者都在白名单里（`user,com.daimadog.pushme`），
照样被冻。所以白名单是必要条件，不是充分条件 —— 真正兜底的是上面那套闹钟自愈。
设置页仍会提示用户授予「忽略电池优化」，三星建议把电池模式设为「不受限制」。

---

## 从源码构建

```bash
flutter pub get
flutter build apk --release --split-per-abi \
  --target-platform android-arm,android-arm64,android-x64
```

产物在 `build/app/outputs/flutter-apk/`。

### 云端构建

推送到 `main` 自动触发 [`.github/workflows/build-apk.yml`](.github/workflows/build-apk.yml)：
JDK 21 + Flutter stable，先按 ABI 分别打包，再打一个全 ABI 并存版，四个 APK 一起上传为 artifact。

### 环境

- Flutter 3.x（stable 通道；CI 上会自动选最新 stable，`pubspec.yaml` 里 SDK 约束放宽到 `>=3.5.0`）
- JDK 17+（CI 用 temurin 21）
- Android SDK：compileSdk 36 / targetSdk 36 / minSdk 24
- Kotlin 2.4.0、AGP 9.2.1、Gradle 9.5.1（Android Gradle Plugin 版本在 `android/settings.gradle.kts`）

---

## 隐私

本仓库**不含任何个人信息**：

- 无服务器地址、无域名、无 Push Key（首次启动为空，由用户自行填写）
- 无历史消息数据（早期开发用的种子库已从仓库移除）
- 应用不会向第三方上报任何数据，消息只存在本机 SQLite

仓库里的 `android/app/debug.keystore` 是 Android SDK 默认调试密钥（口令 `android`），
仅用于保证「本地构建」与「云端 CI 构建」签名一致、可以互相覆盖安装。
**它不是发布密钥** —— 若要正式分发，请换成自己的 release keystore 并移除此文件。

---

## 相关项目与致谢

本项目是 **PushMe 生态里的 Android 客户端**。同一生态下还有其他作者维护的项目：

| 项目 | 说明 | 协议 |
| --- | --- | --- |
| **[yafoo/pushme-client](https://github.com/yafoo/pushme-client)** | **Windows 桌面客户端**（Wails v3 + Go + Vue），在电脑上实时接收手机推送的消息，支持图表消息与插件扩展 | MIT |
| [yafoo/pushme-server](https://github.com/yafoo/pushme-server) | 自建推送服务端（Node.js），接口参数与官方一致；Web 管理走 `3010`，MQTT/WebSocket 走 `3100` | MIT |
| [PushMe 官网](https://push.i-i.me/) | 官方服务、App 下载与接口文档 | — |

### 致谢

- **重构基准**：原 Android 应用 `com.android.pushme`（闭源）。消息类型、字段命名、SQLite 表结构、
  MQTT 主题与 clientId 规则，均按其实际行为对齐，以保证新版本能直接接住旧数据。
- **[yafoo/pushme-client](https://github.com/yafoo/pushme-client)**：PushMe 生态的 Windows 桌面客户端（MIT）。
  本项目的消息类型清单（text / markdown / html / data / chart 等）与它保持同一套生态约定，
  手机上收到的消息可以在两个客户端上呈现一致的效果。
- **[yafoo/pushme-server](https://github.com/yafoo/pushme-server)**：自建服务端（MIT）。
  它的端口约定 —— `3010` HTTP API、`3100` MQTT —— 与本项目客户端侧默认配置一致，可直接对接。

> 本项目代码为独立实现，未复制上述项目的源码；上述项目版权归各自作者所有。
> 如有引用遗漏或描述不当，欢迎提 Issue 指出。

---

## 目录结构

仓库根目录即 Flutter 工程根：

```
.
├── lib/
│   ├── main.dart                  入口
│   ├── core/                      状态管理、模型、主题、原生桥、格式化
│   │   ├── app_state.dart
│   │   ├── models.dart
│   │   ├── theme.dart
│   │   ├── native_api.dart
│   │   └── format.dart
│   ├── pages/                     页面
│   │   ├── home_page.dart         底部导航容器
│   │   ├── message_list_page.dart
│   │   ├── message_detail_page.dart
│   │   ├── stats_page.dart
│   │   └── settings_page.dart
│   └── widgets/                   复用组件
│       ├── common.dart
│       └── message_tile.dart
├── android/app/src/main/kotlin/com/daimadog/pushme/
│   ├── MainActivity.kt            Flutter 宿主、Intent 分发
│   ├── MqttService.kt             MQTT 前台服务
│   ├── MessageDb.kt               SQLite 读写
│   ├── Prefs.kt                   配置存储
│   ├── Notifier.kt                通知
│   ├── TitleParser.kt             标题/内容解析
│   ├── PushEvents.kt              事件桥
│   ├── BootReceiver.kt            开机自启
│   └── NotificationActionReceiver.kt
└── .github/workflows/build-apk.yml
```

---

## 推送接口

客户端从服务端接收消息，服务端向外提供 HTTP 推送接口：

```bash
curl -d "push_key=YOUR_KEY&title=标题&content=正文&type=text" http://你的服务器:3010
```

- 表单字段：`push_key`、`title`、`content`、`type`
- `type` 支持 `text` / `markdown` / `html` / `data` / `chart` 等
- 客户端通过 MQTT（默认 `3100`）接收，HTTP 接口只负责投递

具体参数以你所用服务端的文档为准，兼容官方接口格式的实现都可以对接。
