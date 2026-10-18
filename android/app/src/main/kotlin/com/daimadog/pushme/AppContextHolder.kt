package com.daimadog.pushme

import android.content.Context

/**
 * 进程级 Application Context 持有者。
 * 后台线程（MqttService / Receiver）需要访问 Context 时使用。
 */
object AppContextHolder {
    @Volatile
    var context: Context? = null
        set(value) {
            field = value?.applicationContext ?: value
        }

    fun require(): Context =
        context ?: throw IllegalStateException("AppContextHolder 未初始化")
}
