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
        const val CH_STATE = "StateChannel"
        const val STATE_NOTIFICATION_ID = 1
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

        val importance = when (prefs.channel) {
            "静音" -> NotificationManager.IMPORTANCE_LOW
            "关闭" -> NotificationManager.IMPORTANCE_MIN
            else -> NotificationManager.IMPORTANCE_DEFAULT
        }
        val state = NotificationChannel(CH_STATE, "状态通知", importance).apply {
            description = "推送服务连接状态"
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
        }
        nm.createNotificationChannel(state)
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
            .setGroup("pushme")
            .addAction(R.drawable.ic_stat_read, "已读", readPi)
            .addAction(R.drawable.ic_stat_delete, "删除", delPi)

        try {
            NotificationManagerCompat.from(ctx).notify(id.toInt(), builder.build())
        } catch (e: SecurityException) {
            android.util.Log.w("PushMeNotifier", "notify failed: ${e.message}")
        }
    }

    fun cancelMessage(id: Long) {
        try {
            NotificationManagerCompat.from(ctx).cancel(id.toInt())
        } catch (_: Exception) {
        }
    }

    fun cancelAll() {
        nm.cancelAll()
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

    /** 常驻状态通知 */
    fun buildStateNotification(state: String, detail: String, prefs: Prefs): Notification {
        val openIntent = Intent(ctx, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openPi = PendingIntent.getActivity(
            ctx, 0, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val icon = if (state == "Connected") "🟢" else "🔴"
        val builder = NotificationCompat.Builder(ctx, CH_STATE)
            .setSmallIcon(R.drawable.ic_stat_push)
            .setContentTitle("$icon PushMe $state")
            .setContentText(detail)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setContentIntent(openPi)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)

        // 点击可打开设置（长按通知时系统提供）
        return builder.build()
    }

    fun notifyState(state: String, detail: String, prefs: Prefs) {
        try {
            NotificationManagerCompat.from(ctx)
                .notify(STATE_NOTIFICATION_ID, buildStateNotification(state, detail, prefs))
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
