package com.daimadog.pushme

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/** 原生 -> Flutter 的事件通道（新消息、连接状态、通知点击） */
object PushEvents {

    private var sink: EventChannel.EventSink? = null
    private val main = Handler(Looper.getMainLooper())

    fun attach(s: EventChannel.EventSink?) {
        sink = s
    }

    private fun post(map: Map<String, Any?>) {
        main.post {
            try {
                sink?.success(map)
            } catch (_: Exception) {
            }
        }
    }

    fun emitMessage(id: Long, opened: Boolean = false) {
        post(mapOf("type" to if (opened) "openMessage" else "message", "id" to id))
    }

    fun emitStatus(state: String, since: String) {
        post(mapOf("type" to "status", "state" to state, "since" to since))
    }

    fun emitRefresh() {
        post(mapOf("type" to "refresh"))
    }
}
