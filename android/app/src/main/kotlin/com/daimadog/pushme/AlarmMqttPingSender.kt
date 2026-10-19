package com.daimadog.pushme

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.PowerManager
import android.util.Log
import androidx.core.content.ContextCompat
import org.eclipse.paho.client.mqttv3.MqttPingSender
import org.eclipse.paho.client.mqttv3.internal.ClientComms

/**
 * 闹钟式心跳：用 AlarmManager 唤醒 CPU 去发 PINGREQ，而不是靠后台线程的定时器。
 *
 * ## 为什么必须这么做
 *
 * Paho 的 `MqttClient` 默认用 [org.eclipse.paho.client.mqttv3.TimerPingSender]，
 * 它本质上是一个 `java.util.Timer` 线程。锁屏后设备进入 suspend，**所有用户态线程一起停摆**，
 * 定时器自然不会到点执行 —— 于是我们一个 PINGREQ 都发不出去。
 *
 * broker（Aedes）按 `keepalive × 1.5` 判定超时：到点没收到任何报文就 `close('keepalive timeout')`。
 * 表现就是「锁屏一会儿就断开，解锁后重连」。
 *
 * 原版 `com.android.pushme` 不受影响，正是因为它在反编译代码里用的是
 * `[AlarmPingSender].Schedule next alarm at ...` + `AlarmManager.setExactAndAllowWhileIdle(RTC_WAKEUP, ...)`，
 * 闹钟能把 CPU 从 suspend 里叫醒，`onReceive` 里再短暂持有 PARTIAL_WAKE_LOCK 把 ping 发出去。
 *
 * 本类就是那套机制的重写版：不常驻 wakelock（那样整晚不睡、耗电），
 * 每次只醒几百毫秒。
 */
class AlarmMqttPingSender(
    private val ctx: Context,
    private val clientId: String
) : MqttPingSender {

    private var comms: ClientComms? = null
    private var alarmManager: AlarmManager? = null
    private var pendingIntent: PendingIntent? = null
    private var receiver: BroadcastReceiver? = null
    private var started = false

    /** 由 Paho 在构造客户端时回调，拿到内部通信对象 */
    override fun init(comms: ClientComms) {
        this.comms = comms
    }

    override fun start() {
        if (started) stop()
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        alarmManager = am

        val action = "com.daimadog.pushme.PING.$clientId"
        val r = object : BroadcastReceiver() {
            override fun onReceive(c: Context?, intent: Intent?) {
                // onReceive 跑在主线程，这里**绝不能等** ping 的结果（最多 10s 会 ANR）。
                // 只负责把 CPU 叫醒：setExactAndAllowWhileIdle 只保证「到点唤醒」，
                // 唤醒后系统还会很快重新挂起，所以短暂持锁把发包的几百毫秒兜住，
                // 3 秒后（那时 CPU 一定还醒着）再释放。
                val pm = c?.getSystemService(Context.POWER_SERVICE) as? PowerManager
                val wl = try {
                    pm?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "PushMe:MqttPing")
                } catch (_: Exception) {
                    null
                }
                try {
                    wl?.acquire(20_000L)
                } catch (_: Exception) {
                }
                try {
                    comms?.checkForActivity()
                } catch (e: Exception) {
                    Log.w(TAG, "ping failed: ${e.javaClass.simpleName}")
                }
                RELEASE_HANDLER.postDelayed({
                    try {
                        if (wl?.isHeld == true) wl.release()
                    } catch (_: Exception) {
                    }
                }, 3_000L)
            }
        }
        receiver = r
        try {
            // API 33+ 注册非导出广播必须显式给 flag，否则抛 SecurityException
            ContextCompat.registerReceiver(
                ctx, r, IntentFilter(action), ContextCompat.RECEIVER_NOT_EXPORTED
            )
        } catch (e: Exception) {
            Log.w(TAG, "register ping receiver failed: ${e.message}")
            return
        }

        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        pendingIntent = PendingIntent.getBroadcast(
            ctx, clientId.hashCode(), Intent(action).setPackage(ctx.packageName), flags
        )
        started = true
        // 首次排程交给 Paho：它连上后会立刻调 schedule(keepAlive)
        schedule(KEEPALIVE_HINT_MS)
        Log.i(TAG, "ping alarm started ($clientId)")
    }

    override fun stop() {
        if (!started) return
        started = false
        try {
            pendingIntent?.let { alarmManager?.cancel(it) }
        } catch (_: Exception) {
        }
        try {
            receiver?.let { ctx.unregisterReceiver(it) }
        } catch (_: Exception) {
        }
        Log.i(TAG, "ping alarm stopped ($clientId)")
    }

    override fun schedule(delayInMilliseconds: Long) {
        val am = alarmManager ?: return
        val pi = pendingIntent ?: return
        val at = System.currentTimeMillis() + delayInMilliseconds.coerceAtLeast(1_000L)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                // 精确闹钟能穿透 Doze，是锁屏保活的关键
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
            } else {
                am.setExact(AlarmManager.RTC_WAKEUP, at, pi)
            }
        } catch (e: SecurityException) {
            // Android 14 起 SCHEDULE_EXACT_ALARM 默认不授予，精确闹钟会抛 SecurityException。
            // 退化成非精确闹钟：Doze 里约 9 分钟一次，仍比「完全不发」好得多。
            Log.w(TAG, "exact alarm denied, fallback to inexact")
            try {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
            } catch (_: Exception) {
            }
        } catch (e: Exception) {
            Log.w(TAG, "schedule alarm failed: ${e.message}")
        }
    }

    companion object {
        private const val TAG = "PushMeService"

        /** 首次排程用；Paho 连上后会用自己的 keepAlive 重新 schedule */
        private const val KEEPALIVE_HINT_MS = 300_000L

        /** 放锁用，不依赖任何 Service 生命周期 */
        private val RELEASE_HANDLER = android.os.Handler(android.os.Looper.getMainLooper())
    }
}
