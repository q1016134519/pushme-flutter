package com.daimadog.pushme

import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.Network
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import org.eclipse.paho.client.mqttv3.IMqttDeliveryToken
import org.eclipse.paho.client.mqttv3.MqttCallbackExtended
import org.eclipse.paho.client.mqttv3.MqttClient
import org.eclipse.paho.client.mqttv3.MqttConnectOptions
import org.eclipse.paho.client.mqttv3.MqttMessage
import org.eclipse.paho.client.mqttv3.persist.MemoryPersistence
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.security.KeyStore
import java.security.cert.CertificateFactory
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocketFactory
import javax.net.ssl.TrustManagerFactory

/**
 * 常驻 MQTT 推送服务。
 * 使用 Paho MQTT 客户端，主进程内运行；前台服务保证进程不被回收。
 */
class MqttService : Service(), MqttCallbackExtended {

    companion object {
        private const val TAG = "PushMeService"
        const val ACTION_START = "com.daimadog.pushme.START"
        const val ACTION_STOP = "com.daimadog.pushme.STOP"
        const val ACTION_RECONNECT = "com.daimadog.pushme.RECONNECT"
        const val ACTION_REFRESH = "com.daimadog.pushme.REFRESH_NOTIFICATION"

        @Volatile
        var state: String = "Closed"
            private set

        /** 最近一次的详情文案，供「改设置后立即刷新通知」使用 */
        @Volatile
        var lastDetail: String = "正在连接…"
            private set

        @Volatile
        var sinceText: String = "--:--:--"
            private set

        @Volatile
        var connectedAt: Long = 0L
            private set

        /** 服务实例是否已存在（避免改设置时用 startService 把没跑的服务拉起来） */
        @Volatile
        var running: Boolean = false
            private set

        fun start(ctx: Context) {
            val i = Intent(ctx, MqttService::class.java).setAction(ACTION_START)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) ctx.startForegroundService(i)
            else ctx.startService(i)
        }

        fun stop(ctx: Context) {
            ctx.startService(Intent(ctx, MqttService::class.java).setAction(ACTION_STOP))
        }

        fun reconnect(ctx: Context) {
            ctx.startService(Intent(ctx, MqttService::class.java).setAction(ACTION_RECONNECT))
        }

        /**
         * 设置页改了通知频道后调用：按新策略重发状态通知，不重连、不打断连接。
         *
         * 只在服务已运行时才发：否则 startService 会把一个本已停止的服务重新拉起来，
         * 用户会看到「只是改了个通知设置，服务却自己启动了」。
         */
        fun refreshNotification(ctx: Context) {
            if (!running) return
            try {
                ctx.startService(Intent(ctx, MqttService::class.java).setAction(ACTION_REFRESH))
            } catch (_: Exception) {
            }
        }
    }

    private lateinit var prefs: Prefs
    private lateinit var notifier: Notifier
    private var db: MessageDb? = null

    private var client: MqttClient? = null
    private var target: Prefs.Target? = null

    private val handler = Handler(Looper.getMainLooper())
    private var retry = 0
    private var connecting = false

    private var netCallback: ConnectivityManager.NetworkCallback? = null
    private var cfgReceiver: BroadcastReceiver? = null

    /** 是否还挂在前台（stopForeground 之后不再重发通知） */
    @Volatile
    private var foreground = false

    /** 正在停止：阻止 setState 把通知又贴回去 */
    @Volatile
    private var stopping = false

    /** 上一次真正发布出去的状态，用于判断「状态是否发生跃变」以决定要不要响铃 */
    private var lastPostedState: String = ""

    override fun onCreate() {
        super.onCreate()
        AppContextHolder.context = applicationContext
        prefs = Prefs(this)
        notifier = Notifier(this)
        db = MessageDb.get(this)
        MqttService.state = "Connecting"
        running = true
        notifier.ensureChannels(prefs)
        startForeground(
            Notifier.STATE_NOTIFICATION_ID,
            notifier.buildStateNotification("Connecting", "正在连接…", stateChannel())
        )
        foreground = true
        registerNetworkCallback()
        broadcastStatus("Connecting")
        connect()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                prefs.serviceEnabled = false
                stopping = true
                disconnect()
                foreground = false
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_RECONNECT -> {
                prefs.serviceEnabled = true
                retry = 0
                connect()
            }
            ACTION_REFRESH -> {
                // 频道设置变了：重建通道并按新策略重发，不打断连接
                notifier.ensureChannels(prefs)
                applyStateNotification()
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopping = true
        running = false
        disconnect()
        foreground = false
        unregisterNetworkCallback()
        broadcastStatus("Closed")
        super.onDestroy()
    }

    // ---------------- 连接管理 ----------------

    private fun connect() {
        if (connecting) return
        val t = prefs.activeTarget()
        target = t
        if (t.key.isBlank() || t.host.isBlank()) {
            setState("未配置", "请先在设置中填写服务地址与 key")
            return
        }
        connecting = true
        Thread {
            try {
                disconnectQuiet()
                val uri = "${if (t.tls) "ssl" else "tcp"}://${formatHost(t.host)}:${t.port}"
                val c = MqttClient(uri, "me_${t.key}", MemoryPersistence())
                c.setCallback(this)
                val opt = MqttConnectOptions().apply {
                    isAutomaticReconnect = false
                    isCleanSession = true
                    connectionTimeout = 20
                    keepAliveInterval = 300
                    maxInflight = 100
                    if (t.tls) {
                        val sf = buildSocketFactory(t)
                        if (sf != null) socketFactory = sf
                    }
                }
                c.connect(opt)
                client = c
                c.subscribe(t.topic, 1)
                Log.i(TAG, "subscribed ${t.topic} on $uri")
            } catch (e: Exception) {
                Log.w(TAG, "connect failed: ${e.message}")
                setState("Disconnected", e.message ?: "连接失败")
                scheduleRetry()
            } finally {
                connecting = false
            }
        }.start()
    }

    private fun formatHost(host: String): String {
        return if (host.contains(":") && !host.startsWith("[")) "[$host]" else host
    }

    private fun buildSocketFactory(t: Prefs.Target): SSLSocketFactory? {
        return try {
            when (t.cert) {
                "", "公共证书" -> {
                    val tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())
                    tmf.init(null as KeyStore?)
                    SSLContext.getInstance("TLSv1.2").apply {
                        init(null, tmf.trustManagers, null)
                    }.socketFactory
                }
                else -> {
                    val cf = CertificateFactory.getInstance("X.509")
                    val cert = ByteArrayInputStream(t.cert.toByteArray()).use { cf.generateCertificate(it) }
                    val ks = KeyStore.getInstance(KeyStore.getDefaultType()).apply { load(null, null) }
                    ks.setCertificateEntry("broker", cert)
                    val tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())
                    tmf.init(ks)
                    SSLContext.getInstance("TLS").apply { init(null, tmf.trustManagers, null) }.socketFactory
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "ssl factory failed: ${e.message}")
            null
        }
    }

    private fun scheduleRetry() {
        retry++
        val delay = when {
            retry <= 1 -> 5_000L
            retry <= 3 -> 15_000L
            retry <= 6 -> 30_000L
            else -> 60_000L
        }
        handler.removeCallbacksAndMessages(null)
        handler.postDelayed({ connect() }, delay)
    }

    private fun disconnectQuiet() {
        try {
            client?.let {
                if (it.isConnected) it.disconnect(500)
                it.close(true)
            }
        } catch (_: Exception) {
        }
        client = null
    }

    private fun disconnect() {
        handler.removeCallbacksAndMessages(null)
        disconnectQuiet()
        setState("Closed", "服务已停止")
    }

    // ---------------- Paho 回调 ----------------

    override fun connectComplete(reconnect: Boolean, serverURI: String?) {
        retry = 0
        connectedAt = System.currentTimeMillis()
        sinceText = SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date())
        setState("Connected", "已连接 · $serverURI")
        target?.let {
            try {
                client?.subscribe(it.topic, 1)
            } catch (_: Exception) {
            }
        }
    }

    override fun connectionLost(cause: Throwable?) {
        if (cause is org.eclipse.paho.client.mqttv3.MqttException && cause.reasonCode == 32111) {
            // 主动断开，不重连
            return
        }
        setState("Disconnected", cause?.message ?: "连接断开")
        scheduleRetry()
    }

    override fun messageArrived(topic: String?, message: MqttMessage?) {
        val payload = message?.payload?.toString(Charsets.UTF_8) ?: return
        try {
            handlePayload(payload)
        } catch (e: Exception) {
            Log.w(TAG, "handle payload failed: ${e.message}")
        }
    }

    override fun deliveryComplete(token: IMqttDeliveryToken?) {}

    // ---------------- 消息处理 ----------------

    private fun handlePayload(payload: String) {
        val json = try {
            JSONObject(payload)
        } catch (e: Exception) {
            JSONObject().put("title", payload.take(50)).put("content", payload).put("type", "")
        }
        val rawTitle = json.optString("title", "")
        var content = json.optString("content", "")
        if (content.isEmpty()) content = json.optString("msg", "")
        val type = json.optString("type", "")
        val date = json.optString("date", "").ifBlank {
            SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date())
        }
        val parsed = TitleParser.parse(rawTitle)
        val title = parsed.title.ifBlank { "新消息" }
        val unread = prefs.msgReadInit == "未读"
        val id = db?.insert(title, content, date, type, parsed.user, parsed.face, parsed.theme, unread) ?: 0
        if (id <= 0) return

        val preview = TitleParser.preview(content, type, 300)
        notifier.showMessage(
            id, title, preview, parsed.channel, type, content, prefs
        )
        broadcastNewMessage(id)
        updateStateText()
    }

    // ---------------- 状态 ----------------

    /**
     * 按当前「状态通知频道」设置，选出这条通知该走哪个 channel。
     *
     * 系统硬限制：这是前台服务，Android 强制要求挂一个通知，**无法真正隐藏**。
     * 而且 NotificationManagerService 有一条「重要性地板」：
     *   isFgsOrUij() && 通道重要性未被用户锁定 && importance <= MIN
     *     → 强制 channel.setImportance(LOW)
     * 所以 MIN 通道挂在 FGS 上会被抬到 LOW，状态栏图标照旧。
     *
     * 结论：应用侧能做的只有「不响铃、不亮屏、不弹横幅」，图标是否消失取决于用户
     * 在系统通知设置里把该通道调成「无」。设置页提供了直达入口。
     *
     *  - [Notifier.CH_STATE]       会响铃（断开时提醒）
     *  - [Notifier.CH_STATE_LOW]   无声、不亮屏，状态栏留图标
     *  - [Notifier.CH_STATE_QUIET] 静默通道，尽量低调
     */
    private fun stateChannel(): String = when (prefs.channel) {
        // 仅断开时提醒：只有「真的断了」才回到会响铃的通道；
        // 连接中 / 已连接 / 未配置 全部静默，避免开机后先响一声
        "限断", "仅断开时提醒" ->
            if (state == "Disconnected") Notifier.CH_STATE else Notifier.CH_STATE_QUIET
        // 不显示状态通知：前台服务无法真正隐藏，退化为静默常驻
        "关闭" -> Notifier.CH_STATE_QUIET
        // 静音：不出声，但保留状态栏图标
        "静音" -> Notifier.CH_STATE_LOW
        // 限静：仅静音时段内不打扰
        "限静" -> if (inQuietHours()) Notifier.CH_STATE_LOW else Notifier.CH_STATE
        else -> Notifier.CH_STATE
    }

    /** 是否处于静音时段（start~end，跨零点也成立） */
    private fun inQuietHours(): Boolean {
        val start = prefs.channelStart
        val end = prefs.channelEnd
        if (start == end) return false
        val h = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
        return if (start < end) h in start until end else (h >= start || h < end)
    }

    private fun setState(state: String, detail: String) {
        MqttService.state = state
        MqttService.lastDetail = detail
        notifier.ensureChannels(prefs)
        applyStateNotification()
        broadcastStatus(state)
    }

    /**
     * 按当前设置重发状态通知。
     *
     * 走 startForeground 而不是 notify：只有 startForeground 才能保证前台服务
     * 自己挂的那条通知换了 channel（Android 12+ 上对已发布的前台通知，
     * 单独 notify 同一个 id 有概率不生效，表现就是「设置改了但通知栏没变」）。
     */
    private fun applyStateNotification() {
        if (stopping) return
        val ch = stateChannel()
        // 状态发生跃变才允许响铃；同一状态反复重连失败只更新文案，避免连环响
        val changed = state != lastPostedState
        lastPostedState = state
        val alert = changed && ch == Notifier.CH_STATE
        val n = notifier.buildStateNotification(state, lastDetail, ch, alertOnlyOnce = !alert)
        if (foreground) {
            try {
                startForeground(Notifier.STATE_NOTIFICATION_ID, n)
                return
            } catch (_: Exception) {
                // 前台状态被系统回收过，退化为普通 notify
            }
        }
        try {
            androidx.core.app.NotificationManagerCompat.from(this)
                .notify(Notifier.STATE_NOTIFICATION_ID, n)
        } catch (_: Exception) {
        }
    }

    private fun updateStateText() {
        val count = db?.todayCount() ?: 0
        MqttService.lastDetail = "今日已收 $count 条 · $sinceText 连接"
        applyStateNotification()
    }

    private fun broadcastStatus(state: String) {
        PushEvents.emitStatus(state, sinceText)
    }

    private fun broadcastNewMessage(id: Long) {
        PushEvents.emitMessage(id)
    }

    // ---------------- 网络变化 ----------------

    private fun registerNetworkCallback() {
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val cb = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    handler.postDelayed({
                        if (client?.isConnected != true) {
                            retry = 0
                            connect()
                        }
                    }, 1200)
                }
            }
            cm.registerDefaultNetworkCallback(cb)
            netCallback = cb
        } catch (_: Exception) {
        }
    }

    private fun unregisterNetworkCallback() {
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            netCallback?.let { cm.unregisterNetworkCallback(it) }
        } catch (_: Exception) {
        }
        netCallback = null
    }
}
