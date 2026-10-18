package com.daimadog.pushme

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import android.widget.Toast
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.BufferedReader
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.daimadog.pushme/native"
        private const val EVENTS = "com.daimadog.pushme/events"
        private const val REQ_NOTIFICATION = 1001
    }

    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pendingMessageId: Long = 0L
    private var sinkReady = false
    private var methodChannel: MethodChannel? = null
    private var pendingNotifResult: MethodChannel.Result? = null

    private lateinit var prefs: Prefs

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        AppContextHolder.context = applicationContext
        prefs = Prefs(this)
        // 启动常驻服务
        if (prefs.serviceEnabled && prefs.activeTarget().key.isNotBlank()) {
            startPushService()
        }
        consumeIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        consumeIntent(intent)
    }

    private fun consumeIntent(i: Intent?) {
        if (i == null) return
        val id = i.getLongExtra("messageId", 0L)
        if (id <= 0L) return
        // 立即消费掉，避免 Activity 因配置变更重建时用同一个 Intent 再次打开详情页
        i.removeExtra("messageId")
        Log.i("PushMe", "consumeIntent messageId=$id sinkReady=$sinkReady")
        if (sinkReady) {
            PushEvents.emitMessage(id, opened = true)
        } else {
            pendingMessageId = id
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENTS).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    PushEvents.attach(events)
                    sinkReady = true
                    if (pendingMessageId > 0L) {
                        PushEvents.emitMessage(pendingMessageId, opened = true)
                        pendingMessageId = 0L
                    }
                }

                override fun onCancel(arguments: Any?) {
                    PushEvents.attach(null)
                    sinkReady = false
                }
            }
        )

        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = ch
        ch.setMethodCallHandler { call, result -> handle(call, result) }
    }

    // ---------------- 方法分发 ----------------

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        val db = MessageDb.get(this)
        when (call.method) {
            "settings.getAll" -> result.success(prefs.asMap())

            "settings.set" -> {
                val key = call.argument<String>("key") ?: return result.success(false)
                val value = call.argument<Any>("value")
                prefs.set(key, value)
                when (key) {
                    Prefs.SELF_HOST, Prefs.SELF_PORT, Prefs.SELF_TLS, Prefs.SELF_CERT,
                    Prefs.SELF_KEY, Prefs.SELF_STATE, Prefs.MQTT_HOST, Prefs.MQTT_PORT,
                    Prefs.MQTT_TLS, Prefs.MQTT_CERT, Prefs.PUSH_KEY -> {
                        if (prefs.serviceEnabled) MqttService.reconnect(this)
                    }
                    Prefs.CHANNEL, Prefs.CHANNEL_START, Prefs.CHANNEL_END -> {
                        // 通道要重建；同时让前台服务按新策略立刻重发状态通知，
                        // 否则用户改完设置通知栏毫无变化（挂到下次状态跃变才生效）
                        Notifier(this).ensureChannels(prefs)
                        MqttService.refreshNotification(this)
                    }
                }
                result.success(true)
            }

            "mqtt.status" -> result.success(
                mapOf(
                    "state" to MqttService.state,
                    "since" to MqttService.sinceText,
                    "self" to prefs.selfEnabled(),
                    "host" to prefs.activeTarget().host,
                    "port" to prefs.activeTarget().port,
                    "enabled" to prefs.serviceEnabled
                )
            )

            "mqtt.reconnect" -> {
                prefs.serviceEnabled = true
                startPushService()
                MqttService.reconnect(this)
                result.success(true)
            }

            "mqtt.stop" -> {
                MqttService.stop(this)
                result.success(true)
            }

            "messages.list" -> async(result) {
                db.list(
                    offset = call.argument<Int>("offset") ?: 0,
                    limit = call.argument<Int>("limit") ?: 40,
                    query = call.argument<String>("query") ?: "",
                    field = call.argument<String>("field") ?: "标题+内容",
                    theme = call.argument<String>("theme") ?: "全部",
                    status = call.argument<String>("status") ?: "全部",
                    sortBy = call.argument<String>("sortBy") ?: "时间",
                    sort = call.argument<String>("sort") ?: "desc"
                ).toMap()
            }

            "messages.get" -> async(result) {
                db.get(call.argument<Int>("id")?.toLong() ?: 0L)?.toMap()
            }

            "messages.mark" -> async(result) {
                val ids = call.argument<List<Int>>("ids")?.map { it.toLong() } ?: emptyList()
                db.markRead(ids, call.argument<Boolean>("read") ?: true)
                true
            }

            "messages.star" -> async(result) {
                val ids = call.argument<List<Int>>("ids")?.map { it.toLong() } ?: emptyList()
                db.star(ids, call.argument<Boolean>("star") ?: true)
                true
            }

            "messages.delete" -> async(result) {
                val ids = call.argument<List<Int>>("ids")?.map { it.toLong() } ?: emptyList()
                db.delete(ids)
                val notifier = Notifier(this)
                ids.forEach { notifier.cancelMessage(it) }
                true
            }

            "messages.clearAll" -> async(result) {
                db.clearAll()
                Notifier(this).cancelAll()
                true
            }

            "messages.markAllRead" -> async(result) {
                db.markAllRead()
                Notifier(this).cancelAll()
                true
            }

            "messages.counts" -> async(result) { db.counts().toMap() }

            "messages.stats" -> async(result) { db.stats().toMap() }

            "notify.permission" -> {
                NotificationManagerCompat.from(this).areNotificationsEnabled()
            }

            "notify.request" -> {
                if (Build.VERSION.SDK_INT >= 33) {
                    pendingNotifResult = result
                    requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIFICATION)
                } else {
                    result.success(true)
                }
            }

            "perm.status" -> result.success(
                mapOf(
                    "notifications" to NotificationManagerCompat.from(this).areNotificationsEnabled(),
                    "battery" to isIgnoringBattery(),
                    "exactAlarm" to if (Build.VERSION.SDK_INT >= 31) {
                        (getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager).canScheduleExactAlarms()
                    } else true,
                    "phoneState" to (ContextCompat.checkSelfPermission(
                        this, Manifest.permission.READ_PHONE_STATE
                    ) == PackageManager.PERMISSION_GRANTED)
                )
            )

            "perm.requestPhone" -> {
                if (Build.VERSION.SDK_INT >= 23) {
                    requestPermissions(arrayOf(Manifest.permission.READ_PHONE_STATE), 1002)
                }
                result.success(true)
            }

            "open" -> {
                openTarget(call.argument<String>("target") ?: "")
                result.success(true)
            }

            "toast" -> {
                Toast.makeText(this, call.argument<String>("text") ?: "", Toast.LENGTH_SHORT).show()
                result.success(true)
            }

            "app.info" -> result.success(
                mapOf(
                    "version" to (packageManager.getPackageInfo(packageName, 0).versionName ?: "1.0.0"),
                    "model" to "${Build.BRAND} ${Build.MODEL}",
                    "android" to Build.VERSION.RELEASE
                )
            )

            "send.push" -> async(result) {
                sendPush(
                    call.argument<String>("title") ?: "",
                    call.argument<String>("content") ?: "",
                    call.argument<String>("type") ?: ""
                )
            }

            "seed.imported" -> result.success(java.io.File(filesDir, "seed_imported.flag").exists())

            else -> result.notImplemented()
        }
    }

    private fun async(result: MethodChannel.Result, block: () -> Any?) {
        executor.execute {
            try {
                val r = block()
                main.post { result.success(r) }
            } catch (e: Exception) {
                main.post { result.error("native_error", e.message, null) }
            }
        }
    }

    private fun startPushService() {
        try {
            MqttService.start(this)
        } catch (e: Exception) {
            android.util.Log.w("PushMe", "start service failed: ${e.message}")
        }
    }

    private fun isIgnoringBattery(): Boolean {
        if (Build.VERSION.SDK_INT < 23) return true
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun openTarget(target: String) {
        val i = when (target) {
            "notification" -> Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            }
            // 直达「状态通知」那条通道的设置页。
            // 这是唯一能把状态栏条目真正去掉的入口——而且去掉之后前台服务照旧运行，
            // 进程保护一点不减，只是通知不再显示（见 MqttService.applyStateNotification）。
            "channel" -> {
                val chId = when (prefs.channel) {
                    "静音" -> Notifier.CH_STATE_LOW
                    "限断", "仅断开时提醒", "关闭" -> Notifier.CH_STATE_QUIET
                    else -> Notifier.CH_STATE
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
                        putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        putExtra(Settings.EXTRA_CHANNEL_ID, chId)
                    }
                } else {
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                }
            }
            "app" -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
            "battery" -> Intent(
                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                Uri.parse("package:$packageName")
            )
            "batteryList" -> Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
            "alarm" -> if (Build.VERSION.SDK_INT >= 31) {
                Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:$packageName"))
            } else Intent(Settings.ACTION_SETTINGS)
            "home" -> Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
            "samsungAutoStart" -> Intent().setClassName(
                "com.samsung.android.lool",
                "com.samsung.android.sm.ui.battery.BatteryActivity"
            )
            "samsungBg" -> Intent().setClassName(
                "com.samsung.android.lool",
                "com.samsung.android.sm.ui.ram.AutoRunActivity"
            )
            else -> Intent(Settings.ACTION_SETTINGS)
        }
        try {
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(i)
        } catch (e: Exception) {
            Toast.makeText(this, "无法打开该设置页", Toast.LENGTH_SHORT).show()
        }
    }

    /** 调用自建/官方接口发送一条测试消息 */
    private fun sendPush(title: String, content: String, type: String): String {
        val t = prefs.activeTarget()
        val key = t.key
        if (key.isBlank()) return "未配置 push_key"
        val api = t.api.ifBlank { "https://push.i-i.me" }
        val url = URL(api.trimEnd('/') + "/")
        val conn = url.openConnection() as HttpURLConnection
        return try {
            conn.requestMethod = "POST"
            conn.doOutput = true
            conn.connectTimeout = 15000
            conn.readTimeout = 15000
            conn.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
            val body = buildString {
                append("push_key=").append(URLEncoder.encode(key, "UTF-8"))
                append("&title=").append(URLEncoder.encode(title, "UTF-8"))
                append("&content=").append(URLEncoder.encode(content, "UTF-8"))
                if (type.isNotBlank()) append("&type=").append(URLEncoder.encode(type, "UTF-8"))
            }
            conn.outputStream.use { it.write(body.toByteArray()) }
            val code = conn.responseCode
            val text = (if (code in 200..299) conn.inputStream else conn.errorStream)
                ?.bufferedReader()?.use(BufferedReader::readText) ?: ""
            if (code in 200..299) "success:$text" else "fail:$code $text"
        } catch (e: Exception) {
            "fail:${e.message}"
        } finally {
            conn.disconnect()
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_NOTIFICATION) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingNotifResult?.success(granted)
            pendingNotifResult = null
        }
    }
}

/** org.json.JSONObject -> Map（供 MethodChannel 传输） */
fun JSONObject.toMap(): Map<String, Any?> {
    val map = HashMap<String, Any?>()
    keys().forEach { k ->
        val v = opt(k)
        map[k] = when (v) {
            is JSONObject -> v.toMap()
            is org.json.JSONArray -> v.toList()
            JSONObject.NULL -> null
            else -> v
        }
    }
    return map
}

fun org.json.JSONArray.toList(): List<Any?> {
    val list = ArrayList<Any?>()
    for (i in 0 until length()) {
        val v = opt(i)
        list.add(
            when (v) {
                is JSONObject -> v.toMap()
                is org.json.JSONArray -> v.toList()
                JSONObject.NULL -> null
                else -> v
            }
        )
    }
    return list
}
