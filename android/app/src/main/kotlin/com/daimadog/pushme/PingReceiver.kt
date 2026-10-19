package com.daimadog.pushme

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Log

/**
 * 唤醒闹钟的接收器（在 AndroidManifest 里注册）。
 *
 * 这个类很小，但它承担三件事，顺序不能变：
 *
 * 1. **先无条件续上下一次唤醒**。放在最前面、且不依赖后面任何一步成功。
 *    上一版的教训：Paho 在 ping 超时路径上不会再 `schedule()`，只要漏一次，
 *    整条保活链就永久断掉（真机上是「锁屏断开 → 解锁也不恢复」）。
 * 2. **把 CPU 叫醒足够久**。`setExactAndAllowWhileIdle` 只保证「到点唤醒」，
 *    唤醒后系统很快就会再次挂起。真机实测：只持 3 秒锁时，从 suspend 醒来后
 *    网络还没恢复，PINGRESP 回来时 CPU 已经又睡了，于是 5 分钟后被误判为超时断开。
 * 3. **驱动业务**：服务活着就自检/重连，服务已经被杀就把它拉起来。
 *
 * 因为它是清单注册的，系统持有闹钟 → 进程被杀也能被重新拉起，这是推送服务能
 * 「自愈」的根本原因。动态注册的接收器做不到这一点。
 */
class PingReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        val app = context.applicationContext

        // 用户主动关掉了服务：连闹钟一起收掉，别再叫醒设备
        if (!Prefs(app).serviceEnabled) {
            PushAlarm.cancel(app)
            return
        }

        // ① 无条件续命（必须在最前面）
        val connected = MqttService.isConnectedNow
        PushAlarm.schedule(
            app,
            if (connected) PushAlarm.INTERVAL_CONNECTED else PushAlarm.INTERVAL_RETRY
        )

        // ② 唤醒窗口：覆盖「网络从低功耗恢复 + 一次往返」
        val wl = newWakeLock(app)
        try {
            wl?.acquire(HOLD_MS)
        } catch (_: Exception) {
        }

        // ③ 驱动
        try {
            MqttService.onWake(app)
        } catch (e: Exception) {
            Log.w(TAG, "wake service failed: ${e.javaClass.simpleName}")
        }

        RELEASE.postDelayed({
            try {
                if (wl?.isHeld == true) wl.release()
            } catch (_: Exception) {
            }
        }, HOLD_MS + 1_000L)
    }

    private fun newWakeLock(ctx: Context): PowerManager.WakeLock? = try {
        (ctx.getSystemService(Context.POWER_SERVICE) as? PowerManager)
            ?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "PushMe:Wake")
    } catch (_: Exception) {
        null
    }

    companion object {
        private const val TAG = "PushMeService"

        /**
         * 醒来后至少保持清醒的时长。
         *
         * 3 秒（上一版）不够：熄屏时 WiFi 芯片处于省电态，被唤醒后要几秒才恢到能收发；
         * 12 秒足够覆盖这个恢复过程 + 一次 RTT，按 240 秒一次算，占空比约 5%，
         * 一晚上多耗的电远小于「连不上要重连」的代价。
         */
        private const val HOLD_MS = 12_000L

        private val RELEASE = Handler(Looper.getMainLooper())
    }
}
