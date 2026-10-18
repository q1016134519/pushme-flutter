# PushMe

自建推送服务的 Android 客户端 —— **Flutter 重构版**。

原版（`com.android.pushme`）用原生 Java 写成，功能完整但界面陈旧。这个版本把 UI 整体用 Flutter 重写，
交互与视觉全面对齐 Material 3，功能一项不少：MQTT over TCP 直连、消息本地落库、三类内容渲染、统计看板、深浅色主题。

> 本项目是**客户端**，不含服务端。推送服务需要你自己部署并配合其 HTTP 推送接口使用。

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
| armeabi-v7a | 1051 |
| arm64-v8a | 2051 |
| x86_64 | 4051 |
| universal | 51 |

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
| 设置 | 自建服务器 / 官方服务双模式、Push Key、端口、TLS、通道、主题、导入导出 |
| 后台服务 | MQTT over TCP 长连接 + 前台服务常驻，断线重连 |
| 主题 | 跟随系统 / 浅色 / 深色，Material 3 配色 |

---

## 从源码构建

```bash
cd app
flutter pub get
flutter build apk --release --split-per-abi \
  --target-platform android-arm,android-arm64,android-x64
```

产物在 `app/build/app/outputs/flutter-apk/`。

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

## 目录结构

```
app/
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

## 参考

- 原版应用 `com.android.pushme`（Java + 原生 View）
- 服务端推送接口：`POST /`，表单字段 `push_key`、`title`、`content`、`type`
