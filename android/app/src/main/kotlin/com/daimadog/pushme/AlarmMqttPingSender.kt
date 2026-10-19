package com.daimadog.pushme

import android.content.Context
import android.util.Log
import org.eclipse.paho.client.mqttv3.MqttPingSender
import org.eclipse.paho.client.mqttv3.internal.ClientComms

/**
 * Paho 的心跳排程接口适配器 —— 只做「把 Paho 的排程意图翻译成闹钟」，不再自己管广播接收器。
 *
 * Paho 会在三个时机调用它：
 *  - 连接成功后 `start()`
 *  - 每次 `checkForActivity()` 算好「下次该什么时候发」时 `schedule(delay)`
 *  - 连接关闭 / 断线时 `stop()`
 *
 * **`stop()` 里绝对不能取消闹钟。** Paho 在 ping 超时、broker 主动断开、手动 disconnect
 * 时都会调 `stop()`；上一版就在这里 `alarmManager.cancel()`，于是唯一的唤醒源被自己关掉，
 * 进程还活着却再也不会醒 —— 真机实测 45 分钟零唤醒、CPU 时间几乎为零，
 * 表现就是「解锁后也不恢复」。
 *
 * 现在闹钟归 [PushAlarm] 管，生命周期只跟「服务是否启用」绑定。
 */
class AlarmMqttPingSender(
    private val ctx: Context,
    private val clientId: String
) : MqttPingSender {

    /** 本客户端自己的通道，用于在 stop() 时判断「全局引用还是不是我的」 */
    private var myComms: ClientComms? = null

    override fun init(comms: ClientComms) {
        myComms = comms
        PingLink.comms = comms
    }

    override fun start() {
        Log.i(TAG, "ping alarm started ($clientId)")
        PushAlarm.schedule(ctx, PushAlarm.INTERVAL_CONNECTED)
    }

    /**
     * **故意什么都不做。**
     *
     * Paho 每次算「下次该什么时候发 ping」都会调这里，但它算延迟用的是
     * `System.nanoTime()`（CLOCK_MONOTONIC）—— 设备 suspend 期间这个时钟不走，
     * 于是它算出来的间隔是错的：真机实测把我们的 240 秒节拍打成了 121s / 71s 乱跳，
     * 白白多叫醒几次 CPU，而且那些唤醒又不会真正发出 PINGREQ。
     *
     * 链路是否活着现在完全由 [MqttService.probe] 的 QoS1 PUBACK 往返来判定，
     * 巡检节拍只由 `PushAlarm` 的 240 秒定时器驱动，所以这里保持静默。
     */
    override fun schedule(delayInMilliseconds: Long) {
        // no-op，见上面的说明
    }

    override fun stop() {
        // 只解除关联，不取消闹钟（见类注释）。加身份判断：新客户端的 init() 可能已经先跑了。
        if (PingLink.comms === myComms) PingLink.comms = null
        Log.i(TAG, "ping alarm detached ($clientId)")
    }

    companion object {
        private const val TAG = "PushMeService"
    }
}

/**
 * 当前活着的 MQTT 客户端的内部通道。
 *
 * `ClientComms` 在 Paho 的 internal 包里，只能靠 [MqttPingSender.init] 拿到。
 * 现在链路活性由 QoS1 PUBACK 往返判定（见 `MqttService.probe`），不再需要
 * 借它调 `checkForActivity()`；保留它只是为了在重连时能干净地断开与旧客户端的关联。
 */
object PingLink {
    @Volatile
    var comms: ClientComms? = null
}
