package com.daimadog.pushme

import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
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

    /**
     * 是否已挂上前台服务。
     *
     * 只在「用户主动停止服务」时才会被置回 false —— 平时无论哪个通知档位都保持 true。
     * 见 [applyStateNotification]：一旦中途掉出前台，Android 12+ 就不让再进来了。
     */
    @Volatile
    private var foreground = false

    /** 正在停止：阻止 setState 把通知又贴回去 */
    @Volatile
    private var stopping = false

    /**
     * 本实例是否仍然有效。onDestroy 置 false 后，残留线程（例如卡在 TCP 上的连接线程）
     * 即使随后抛异常也不会再回来改状态、改通知。
     */
    @Volatile
    private var alive = false

    /**
     * 连接尝试的序号。每次发起连接 +1，[disconnect] 也会 +1。
     * 线程回到主流程时若发现序号已变，说明它属于一次已经作废的尝试，直接丢弃结果。
     */
    @Volatile
    private var attempt = 0

    /** 本次连接尝试的开始时间，用于判断「是不是卡死了」 */
    @Volatile
    private var connectingSince = 0L

    /** 等待 CONNACK 的上限。超过就判定失败，避免通知栏永远停在「正在连接…」 */
    private val connectTimeoutMs = 20_000L

    /** 上一次真正发布出去的状态，用于判断「状态是否发生跃变」以决定要不要响铃 */
    private var lastPostedState: String = ""

    override fun onCreate() {
        super.onCreate()
        AppContextHolder.context = applicationContext
        prefs = Prefs(this)
        notifier = Notifier(this)
        db = MessageDb.get(this)
        alive = true
        stopping = false
        MqttService.state = "Connecting"
        running = true
        notifier.ensureChannels(prefs)
        enterForeground(
            notifier.buildStateNotification("Connecting", "正在连接…", stateChannel())
        )
        registerNetworkCallback()
        broadcastStatus("Connecting")
        connect()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action

        // 任何「重新开始」的动作都必须复位停止标记。
        // stopSelf() 之后如果很快又来一个 start，系统可能复用同一个实例而不重跑 onCreate，
        // 于是 stopping 会一直停在 true —— applyStateNotification 被永久拦死，
        // 表现就是「界面已经显示断开，通知栏却一直停在旧文案」。
        if (action != ACTION_STOP) {
            stopping = false
            alive = true
            if (!foreground) {
                // 实例被复用（stopSelf 之后很快又来一次 start，onCreate 不会再跑）：
                // 必须重新挂回前台，否则 startForegroundService 会在 5 秒后
                // 判定「没有调用 startForeground」而直接崩溃。
                enterForeground(
                    notifier.buildStateNotification(state, lastDetail, stateChannel())
                )
            }
        }

        when (action) {
            ACTION_STOP -> {
                prefs.serviceEnabled = false
                // 先正常收尾：此时 stopping 仍为 false，通知能更新成「Closed」，
                // 紧接着就被 stopForeground 移除，用户看到的是完整的一次退出而不是半截状态。
                disconnect()
                stopping = true
                alive = false
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
        alive = false
        stopping = true
        running = false
        attempt++          // 让所有在途连接线程的结果作废
        connecting = false
        handler.removeCallbacksAndMessages(null)
        disconnectQuiet()
        foreground = false
        MqttService.state = "Closed"
        unregisterNetworkCallback()
        broadcastStatus("Closed")
        super.onDestroy()
    }

    // ---------------- 连接管理 ----------------

    private fun connect() {
        if (!alive || stopping) return

        val now = System.currentTimeMillis()
        // 上一次尝试还没回来：除非它已经明显超过超时时间（底层卡死），否则不叠加新连接
        if (connecting && now - connectingSince < connectTimeoutMs) return

        val t = prefs.activeTarget()
        target = t
        if (t.key.isBlank() || t.host.isBlank()) {
            setState("未配置", "请先在设置中填写服务地址与 key")
            return
        }
        connecting = true
        connectingSince = now
        val my = ++attempt
        // 只有从「没在连」的状态进入时才显示「正在连接」。
        // 失败重连的循环里保持在「已断开」，否则文案会在 Connecting/Disconnected 之间来回跳，
        // 每跳一次状态就算一次跃变，会把「断开提醒」变成连环响铃。
        if (MqttService.state != "Disconnected") setState("Connecting", "正在连接…")
        Thread { doConnect(t, my) }.start()
    }

    private fun doConnect(t: Prefs.Target, my: Int) {
        var pending: MqttClient? = null
        try {
            disconnectQuiet()
            val uri = "${if (t.tls) "ssl" else "tcp"}://${formatHost(t.host)}:${t.port}"
            val cli = MqttClient(uri, "me_${t.key}", MemoryPersistence())
            pending = cli
            cli.setCallback(this)
            val opt = MqttConnectOptions().apply {
                isAutomaticReconnect = false
                isCleanSession = true
                connectionTimeout = 20
                // 心跳间隔。原来取 300s，正好和运营商 NAT 的空闲回收时间撞在一起：
                // NAT 先把映射表项丢掉，我们的 PINGREQ 发进黑洞，要到 1.5×300=450s
                // 之后 Paho 才判定超时，中间最长 7 分半是「假死」。
                // 改成 120s：每两分钟一次心跳能持续刷新 NAT 映射，最长失联窗口压到 3 分钟。
                keepAliveInterval = 120
                maxInflight = 100
                if (t.tls) {
                    val sf = buildSocketFactory(t)
                    if (sf != null) socketFactory = sf
                }
            }
            // 必须用「带超时的等待」而不是同步 connect()：
            // Paho 的阻塞式 connect() 内部是 Token.waitForCompletion()（无超时），
            // 一旦 broker 接受 TCP 却不回 CONNACK（端口填错、被墙、TLS 端口写成明文），
            // 这个线程会永久挂住，通知栏就永远停在「正在连接…」。
            cli.connectWithResult(opt).waitForCompletion(connectTimeoutMs)
            if (my != attempt || !alive) {
                try {
                    cli.close(true)
                } catch (_: Exception) {
                }
                return
            }
            client = cli
            cli.subscribe(t.topic, 1)
            Log.i(TAG, "subscribed ${t.topic} on $uri")
        } catch (e: Exception) {
            try {
                pending?.close(true)
            } catch (_: Exception) {
            }
            if (my != attempt || !alive) return
            Log.w(TAG, "connect failed: ${e.message}")
            setState("Disconnected", friendlyError(e))
            scheduleRetry()
        } finally {
            if (my == attempt) connecting = false
        }
    }

    /** 把 Paho / 网络异常翻译成用户看得懂的文案（会直接显示在通知栏正文里） */
    private fun friendlyError(e: Exception): String {
        // Paho 会把底层异常包一层再抛，reasonCode 常常退化成 0，
        // 所以先沿 cause 链找真正的根因（超时/拒绝连接），再看 reasonCode。
        var cur: Throwable? = e
        var depth = 0
        while (cur != null && depth < 8) {
            when (cur) {
                is java.net.SocketTimeoutException -> return "连接超时"
                is java.net.UnknownHostException -> return "地址解析失败"
                is java.net.ConnectException -> return "服务器不可达"
                is java.net.NoRouteToHostException -> return "网络不可用"
            }
            cur = cur.cause
            depth++
        }
        val me = e as? org.eclipse.paho.client.mqttv3.MqttException
        if (me != null) {
            return when (me.reasonCode) {
                32000 -> "连接超时"
                32103 -> "服务器不可达"
                32104 -> "服务器无响应"
                32105, 32106, 32107, 32108 -> "服务器拒绝连接"
                32109, 32110 -> "连接被中断"
                else -> {
                    val m = me.message
                    when {
                        !m.isNullOrBlank() && m != "MqttException" -> m
                        me.reasonCode > 0 -> "连接失败（${me.reasonCode}）"
                        else -> "连接失败"
                    }
                }
            }
        }
        return e.message?.takeIf { it.isNotBlank() } ?: "连接失败"
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
        attempt++          // 作废在途的连接线程，避免它稍后把状态改回 Disconnected
        connecting = false
        handler.removeCallbacksAndMessages(null)
        disconnectQuiet()
        setState("Closed", "服务已停止")
    }

    // ---------------- Paho 回调 ----------------

    override fun connectComplete(reconnect: Boolean, serverURI: String?) {
        if (!alive) return
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
        if (!alive) return
        if (cause is org.eclipse.paho.client.mqttv3.MqttException && cause.reasonCode == 32111) {
            // 主动断开，不重连
            return
        }
        setState("Disconnected", cause?.message ?: "连接断开")
        scheduleRetry()
    }

    override fun messageArrived(topic: String?, message: MqttMessage?) {
        if (!alive) return
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
     * 注意：这里只管「用哪个通道、响不响」，**不管显不显示**——
     * 前台服务的那条通知必须一直挂着（见 [applyStateNotification] 的说明）。
     * 想让它从通知栏消失，唯一合法的办法是用户自己在系统设置里把该通道关掉。
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
        "关闭" -> Notifier.CH_STATE_QUIET
        // 静音：不出声，但保留状态栏图标
        "静音" -> Notifier.CH_STATE_LOW
        // 限静：仅静音时段内不打扰
        "限静" -> if (inQuietHours()) Notifier.CH_STATE_LOW else Notifier.CH_STATE
        else -> Notifier.CH_STATE
    }

    /**
     * 挂上前台服务。
     *
     * ⚠️ Android 14+ 起 `startForeground` 必须带服务类型，否则抛
     * `MissingForegroundServiceTypeException`；类型取 manifest 声明的 `specialUse`
     * （不能用 `dataSync`：API 35 起 dataSync 前台服务累计跑满 6 小时会被系统强制停止）。
     */
    private fun enterForeground(n: android.app.Notification): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    Notifier.STATE_NOTIFICATION_ID,
                    n,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                )
            } else {
                startForeground(Notifier.STATE_NOTIFICATION_ID, n)
            }
            foreground = true
            true
        } catch (e: Exception) {
            Log.w(TAG, "startForeground failed: ${e.javaClass.simpleName}")
            false
        }
    }

    /**
     * 按当前设置重发状态通知。
     *
     * ⚠️⚠️ 这里**绝对不能** `stopForeground` —— 这是上一版最大的坑。
     *
     * 「限断」档曾经在连接正常时用 `stopForeground(STOP_FOREGROUND_REMOVE)` 把通知撤掉，
     * 服务于是退回普通后台优先级。之后一旦断线要重连，Android 12+ **禁止后台进程再进入前台**，
     * `startForeground` 抛 `ForegroundServiceStartNotAllowedException`，只能退化成普通 notify，
     * 于是永远回不到前台 → 被系统冻结/限流 → keepalive 停止 → broker 断开 → 重连又失败，死循环。
     * 这正是「给了电池白名单、锁了后台，切后台一会儿还是断」的原因：
     * 电池白名单只豁免 Doze 与省电策略，**不豁免后台启动前台服务的限制**。
     *
     * 正确做法：前台服务自始至终挂着，靠「换成不响的通道」来降低打扰；
     * 要让通知栏彻底一条都不留，由用户到系统设置里把该通知通道关掉——
     * 那时前台服务仍在运行（进程仍受保护），只是通知不再显示。
     */
    private fun applyStateNotification() {
        if (stopping || !alive) return

        val ch = stateChannel()
        // 状态发生跃变才允许响铃；同一状态反复重连失败只更新文案，避免连环响
        val changed = state != lastPostedState
        lastPostedState = state
        val alert = changed && ch == Notifier.CH_STATE
        Log.i(TAG, "post state=$state ch=$ch fg=$foreground alert=$alert")
        val n = notifier.buildStateNotification(state, lastDetail, ch, alertOnlyOnce = !alert)

        if (enterForeground(n)) return

        // 极少见：从后台被拒（如刚被系统 thaw 时）。退化成普通通知，等下次状态变化再试。
        try {
            androidx.core.app.NotificationManagerCompat.from(this)
                .notify(Notifier.STATE_NOTIFICATION_ID, n)
        } catch (_: Exception) {
        }
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
        if (!alive) return
        MqttService.state = state
        MqttService.lastDetail = detail
        notifier.ensureChannels(prefs)
        applyStateNotification()
        broadcastStatus(state)
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
