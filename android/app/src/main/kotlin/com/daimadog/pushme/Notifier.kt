package com.daimadog.pushme

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * 通知：消息通知（每个频道一个 NotificationChannel）+ 常驻服务状态通知。
 */
class Notifier(private val ctx: Context) {

    companion object {
        const val CH_MAIN = "MainChannel"

        /**
         * 状态通道：会响铃，用于「断开时提醒」。
         *
         * ⚠️ 坑：NotificationChannel 的 **importance / sound / vibration 在创建那一刻就被系统固化**，
         * 之后应用再怎么 createNotificationChannel 改都不会生效（只有用户能在系统设置里改）。
         * `dumpsys notification` 里体现为 `mOriginalImp` 永远是首次声明的值。
         * 所以这个 id 必须是「从未以低重要性创建过」的新名字 —— 历史上叫 StateChannel 的那个
         * 已经被以 IMPORTANCE_MIN 建过（mOriginalImp=1），永久停在 LOW（无声），只能弃用。
         * 若以后要再调重要性，请再换新 id，而不是改这里的常量值。
         */
        const val CH_STATE = "StateAlertChannel"

        /** 低打扰通道：无声、不亮屏，状态栏保留图标（本来就是 LOW，不受地板规则影响） */
        const val CH_STATE_LOW = "StateLowChannel"

        /**
         * 静默通道：声明为 IMPORTANCE_MIN，无声、不亮屏、排在下拉栏底部。
         *
         * ⚠️ 重要：Android 对前台服务通知有一条「重要性地板」——
         * NotificationManagerService 在入队时执行：
         *   if (notification.isFgsOrUij()
         *       && (channel.getUserLockedFields() & USER_LOCKED_IMPORTANCE) == 0
         *       && r.getImportance() <= IMPORTANCE_MIN) {
         *       channel.setImportance(IMPORTANCE_LOW)   // 强制抬到 LOW
         *   }
         * 也就是说，前台服务挂 MIN 通道会被系统自动抬到 LOW，**状态栏图标删不掉**。
         * 这里仍按 MIN 声明，是因为一旦用户在系统设置里把该通道重要性锁定为
         * 「无」，地板条件不成立，MIN 就会被真正尊重（那时状态栏图标才会消失）。
         */
        const val CH_STATE_QUIET = "StateQuietChannel"

        const val STATE_NOTIFICATION_ID = 1

        /**
         * 消息通知 id 的偏移量。
         *
         * 消息通知原先直接用数据库自增 id（从 1 开始），第一条消息的 id 正好等于
         * [STATE_NOTIFICATION_ID]：状态通知和消息通知会互相覆盖 ——
         * 「限断」档在断开时重贴提醒，会顺手把用户还没看的第一条消息顶掉；
         * 反过来消息到达又会把状态通知顶掉。加个固定偏移把两个命名空间分开。
         */
        private const val MESSAGE_ID_BASE = 100000

        const val ACTION_MARK_READ = "com.daimadog.pushme.MARK_READ"
        const val ACTION_DELETE = "com.daimadog.pushme.DELETE_MESSAGE"
        const val ACTION_REPEAT = "com.daimadog.pushme.REPEAT_MESSAGE"
    }

    private val nm: NotificationManager =
        ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    fun ensureChannels(prefs: Prefs) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val main = NotificationChannel(CH_MAIN, "消息通知", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "接收到的推送消息"
            enableVibration(true)
            enableLights(true)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        nm.createNotificationChannel(main)

        // 状态通道：重要性在 channel 创建后「应用侧完全改不动」，所以不能靠改重要性来
        // 切换打扰级别 —— 必须用不同的 channelId。三个通道各固定一个重要性，
        // 运行时按设置「换通道」，而不是「改通道」。
        //
        // 这里显式 setSound：IMPORTANCE_DEFAULT 若不写 sound，层里可能落成 null（无声），
        // 那就又变成「说好会响其实不响」。
        val state = NotificationChannel(
            CH_STATE, "状态通知", NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = "推送服务连接状态（断开时响铃提醒）"
            setShowBadge(false)
            setSound(
                android.provider.Settings.System.DEFAULT_NOTIFICATION_URI,
                Notification.AUDIO_ATTRIBUTES_DEFAULT
            )
            enableVibration(true)
        }
        nm.createNotificationChannel(state)

        val stateLow = NotificationChannel(
            CH_STATE_LOW, "状态通知（无声）", NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "推送服务连接状态，不发声但保留状态栏图标"
            setShowBadge(false)
            enableVibration(false)
            enableLights(false)
            setSound(null, null)
        }
        nm.createNotificationChannel(stateLow)

        // 静默通道。声明 IMPORTANCE_MIN；但前台服务会被系统抬到 LOW（见 CH_STATE_QUIET 注释）。
        // 用户若在系统设置中把本通道重要性锁为「无」，则 MIN 生效、状态栏图标消失。
        val stateQuiet = NotificationChannel(
            CH_STATE_QUIET, "状态通知（静默）", NotificationManager.IMPORTANCE_MIN
        ).apply {
            description = "推送服务运行中，尽量不打扰（可在系统通知设置里进一步调低）"
            setShowBadge(false)
            enableVibration(false)
            enableLights(false)
            setSound(null, null)
        }
        nm.createNotificationChannel(stateQuiet)

        // 清掉历史遗留通道：旧版的 "StateChannel" 当初以 IMPORTANCE_MIN 创建，
        // 已被系统抬到 LOW 且改不回来，留着只会在系统设置里多出一个永远不响的「状态通知」。
        runCatching { nm.deleteNotificationChannel("StateChannel") }
    }

    private fun channelFor(name: String, prefs: Prefs): String {
        if (name.isBlank() || name == CH_MAIN) return CH_MAIN
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel("~$name", "~$name", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "频道：$name"
                enableVibration(true)
            }
            nm.createNotificationChannel(ch)
        }
        return "~$name"
    }

    /** 消息通知 */
    fun showMessage(
        id: Long,
        title: String,
        body: String,
        channel: String,
        type: String,
        content: String,
        prefs: Prefs
    ) {
        if (!NotificationManagerCompat.from(ctx).areNotificationsEnabled()) return

        val openIntent = Intent(ctx, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("messageId", id)
            putExtra("messageType", type)
            putExtra("messageContent", if (type == "url") content else "")
        }
        val openPi = PendingIntent.getActivity(
            ctx, id.toInt(), openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val readPi = broadcast(id, ACTION_MARK_READ, id.toInt() + 100000)
        val delPi = broadcast(id, ACTION_DELETE, id.toInt() + 200000)

        val builder = NotificationCompat.Builder(ctx, channelFor(channel, prefs))
            .setSmallIcon(R.drawable.ic_stat_push)
            .setContentTitle(title.ifBlank { "新消息" })
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setWhen(System.currentTimeMillis())
            .setShowWhen(true)
            .setContentIntent(openPi)
            .addAction(R.drawable.ic_stat_read, "已读", readPi)
            .addAction(R.drawable.ic_stat_delete, "删除", delPi)

        try {
            // 一条消息一张通知，**不做任何分组归档** —— 与原始 PushMe 行为一致。
            // 「消息分组折叠/展开」是应用内消息列表页的显示设置，不涉及通知栏。
            NotificationManagerCompat.from(ctx)
                .notify(MESSAGE_ID_BASE + id.toInt(), builder.build())
        } catch (e: SecurityException) {
            android.util.Log.w("PushMeNotifier", "notify failed: ${e.message}")
        }
    }

    fun cancelMessage(id: Long) {
        try {
            NotificationManagerCompat.from(ctx).cancel(MESSAGE_ID_BASE + id.toInt())
        } catch (_: Exception) {
        }
    }

    fun cancelAll() {
        nm.cancelAll()
        // cancelAll() 会把「状态通知」一起清掉。如果服务还在跑而这条通知没了，
        // 在「通知 / 静音 / 限静」档下用户就再也看不到连接状态（只能等下次状态跃变）。
        // 让服务按当前策略重发一次；服务没在跑就什么都不做。
        if (!MqttService.running) return
        try {
            ctx.startService(
                Intent(ctx, MqttService::class.java).setAction(MqttService.ACTION_REFRESH)
            )
        } catch (_: Exception) {
        }
    }

    private fun broadcast(id: Long, action: String, reqCode: Int): PendingIntent {
        val i = Intent(ctx, NotificationActionReceiver::class.java).apply {
            this.action = action
            putExtra("messageId", id)
        }
        return PendingIntent.getBroadcast(
            ctx, reqCode, i,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /**
     * 常驻状态通知。
     *
     * @param channelId 三选一：[CH_STATE] 正常提醒 / [CH_STATE_LOW] 无声 / [CH_STATE_QUIET] 静默
     * @param alertOnlyOnce true 时同一条通知的更新不再重复响铃（用于反复重连失败时防轰炸）
     */
    fun buildStateNotification(
        state: String,
        detail: String,
        channelId: String = CH_STATE,
        alertOnlyOnce: Boolean = true
    ): Notification {
        // 通知自身的 priority 必须与所选通道的重要性一致，否则会「就高」——
        // 例如静默通道(IMPORTANCE_MIN)配 PRIORITY_LOW，系统会把实际重要性抬到 LOW，
        // 结果静默通道照样在状态栏留图标。
        val priority = when (channelId) {
            CH_STATE_QUIET -> NotificationCompat.PRIORITY_MIN
            CH_STATE_LOW -> NotificationCompat.PRIORITY_LOW
            else -> NotificationCompat.PRIORITY_DEFAULT
        }
        val silent = channelId != CH_STATE

        val openIntent = Intent(ctx, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openPi = PendingIntent.getActivity(
            ctx, 0, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val icon = if (state == "Connected") "🟢" else "🔴"
        val builder = NotificationCompat.Builder(ctx, channelId)
            .setSmallIcon(R.drawable.ic_stat_push)
            .setContentTitle("$icon PushMe $state")
            .setContentText(detail)
            .setOngoing(true)
            .setOnlyAlertOnce(alertOnlyOnce)
            .setShowWhen(false)
            .setSilent(silent)
            .setPriority(priority)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setContentIntent(openPi)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // 前台服务通知立即展示，避免「已运行但通知迟到」的割裂感
            builder.setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
        }

        return builder.build()
    }

    fun notifyState(state: String, detail: String, channelId: String = CH_STATE) {
        try {
            NotificationManagerCompat.from(ctx)
                .notify(STATE_NOTIFICATION_ID, buildStateNotification(state, detail, channelId))
        } catch (_: Exception) {
        }
    }

    fun openNotificationSettings() {
        val i = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
            putExtra(Settings.EXTRA_APP_PACKAGE, ctx.packageName)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        ctx.startActivity(i)
    }

    fun openAppSettings() {
        val i = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${ctx.packageName}")).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        ctx.startActivity(i)
    }
}
