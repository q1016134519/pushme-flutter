package com.daimadog.pushme

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * 应用级「唤醒闹钟」的唯一管理者。
 *
 * ## 为什么要从 MQTT 客户端里独立出来
 *
 * 上一版把闹钟放在 [AlarmMqttPingSender] 里，生命周期跟着**某一次连接**走，于是踩了两个坑：
 *
 * 1. Paho 在 ping 超时 / 连接关闭时会调 `pingSender.stop()`。旧实现顺手
 *    `alarmManager.cancel()`，唯一的唤醒源被自己关掉 —— **唤醒链当场死亡**。
 *    真机实测：19:26~20:31 之间醒了 3 次，之后 45 分钟一次都没再醒。
 * 2. PendingIntent 指向动态注册的广播接收器。进程被系统杀掉后闹钟照样会响，
 *    但接收器随进程一起没了，广播无人接收 → 闹钟白响，进程也起不来。
 *
 * 现在：闹钟归应用管，生命周期只跟「服务是否启用」绑定；PendingIntent 显式指向
 * 清单里注册的 [PingReceiver]，即使进程被杀，闹钟也能把进程连同服务一起拉起来。
 */
object PushAlarm {

    private const val TAG = "PushMeService"

    const val ACTION_PING = "com.daimadog.pushme.PING"

    /** 连接正常时的巡检间隔。必须明显小于 keepAliveInterval，给唤醒抖动留余量 */
    const val INTERVAL_CONNECTED = 240_000L

    /** 断线时的巡检间隔：恢复要快 */
    const val INTERVAL_RETRY = 30_000L

    /** requestCode 固定，保证「同一个 PendingIntent」被复用、不会堆出多个 */
    private const val REQ_CODE = 0x504D

    /**
     * 排下一次唤醒。
     *
     * 用 `setExactAndAllowWhileIdle(RTC_WAKEUP, ...)`：这是唯一能把 CPU 从 suspend
     * 里精确叫醒、并且能穿透 Doze 的机制，也是原版 `com.android.pushme` 的做法。
     */
    fun schedule(ctx: Context, delayMs: Long) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val at = System.currentTimeMillis() + delayMs.coerceAtLeast(5_000L)
        val pi = pending(ctx)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
            } else {
                am.setExact(AlarmManager.RTC_WAKEUP, at, pi)
            }
        } catch (e: SecurityException) {
            // Android 14+ 若精确闹钟权限被回收，退化成非精确：Doze 里约 9 分钟一次，
            // 虽然慢，但比「完全不醒」好得多。
            Log.w(TAG, "exact alarm denied, fallback to inexact")
            try {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
            } catch (_: Exception) {
            }
        } catch (e: Exception) {
            Log.w(TAG, "schedule alarm failed: ${e.javaClass.simpleName}")
        }
    }

    /** 只在用户主动停止服务时调用 */
    fun cancel(ctx: Context) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        try {
            am.cancel(pending(ctx))
            Log.i(TAG, "wake alarm cancelled")
        } catch (_: Exception) {
        }
    }

    /** 精确闹钟权限是否还在（Android 12+ 可被用户/系统回收，出问题时方便排查） */
    fun canExact(ctx: Context): Boolean = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager).canScheduleExactAlarms()
        } else {
            true
        }
    } catch (_: Exception) {
        false
    }

    private fun pending(ctx: Context): PendingIntent {
        // 显式组件：不靠 action 匹配，进程死了系统也能把目标拉起来
        val i = Intent(ctx, PingReceiver::class.java).setAction(ACTION_PING)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        return PendingIntent.getBroadcast(ctx, REQ_CODE, i, flags)
    }
}
