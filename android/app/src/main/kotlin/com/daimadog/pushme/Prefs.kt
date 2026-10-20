package com.daimadog.pushme

import android.content.Context
import android.content.SharedPreferences

/**
 * 设置项：字段名与旧版 PushMe 的 DataStore key 保持一致，
 * 便于用户从旧版迁移配置。
 */
class Prefs(context: Context) {

    private val sp: SharedPreferences =
        context.getSharedPreferences("pushme_prefs", Context.MODE_PRIVATE)

    companion object {
        const val APP_THEME = "app_theme"          // 系统 / 暗色 / 亮色
        const val APP_COLOR = "app_color"          // PushMe / 系统 / 自定义
        const val FONT_SCALE = "font_scale"
        const val MSG_READ_INIT = "msg_read_init"  // 已读 / 未读
        const val MSG_USER_TOP = "msg_user_top"
        const val LINK_CLICK = "link_click"        // 系统 / 内置
        const val CHANNEL = "channel"              // 通知/限静/静音/限断/关闭
        const val CHANNEL_START = "channel_start_time"
        const val CHANNEL_END = "channel_end_time"
        const val MQTT_HOST = "mqtt_host"
        const val MQTT_PORT = "mqtt_port"
        const val MQTT_TLS = "mqtt_tls"
        const val MQTT_CERT = "mqtt_cert"
        const val PUSH_ID = "push_id"
        const val PUSH_KEY = "push_key"
        const val SELF_HOST = "self_host"
        const val SELF_PORT = "self_port"
        const val SELF_TLS = "self_tls"
        const val SELF_CERT = "self_cert"
        const val SELF_KEY = "self_key"
        const val SELF_STATE = "self_state"
        const val SELF_API = "self_api"
        const val SERVICE_ENABLED = "service_enabled"

        /** 通知分组方式：「展开」= 每条消息单独铺开；「折叠」= 同一分组收进一张卡片 */
        const val NOTIF_GROUP = "notif_group"
    }

    private fun put(key: String, value: Any?) {
        sp.edit().apply {
            when (value) {
                null -> remove(key)
                is Boolean -> putBoolean(key, value)
                is Int -> putInt(key, value)
                is Long -> putLong(key, value)
                is Float -> putFloat(key, value)
                is Double -> putFloat(key, value.toFloat())
                else -> putString(key, value.toString())
            }
        }.apply()
    }

    /** 数值型读取容错：历史数据可能被写成字符串 */
    private fun safeInt(key: String, def: Int): Int = try {
        sp.getInt(key, def)
    } catch (e: ClassCastException) {
        sp.getString(key, null)?.trim()?.toIntOrNull() ?: def
    }

    private fun safeFloat(key: String, def: Float): Float = try {
        sp.getFloat(key, def)
    } catch (e: ClassCastException) {
        sp.getString(key, null)?.trim()?.toFloatOrNull() ?: def
    }

    var appTheme: String
        get() = sp.getString(APP_THEME, "系统") ?: "系统"
        set(v) = put(APP_THEME, v)

    var appColor: String
        get() = sp.getString(APP_COLOR, "PushMe") ?: "PushMe"
        set(v) = put(APP_COLOR, v)

    var fontScale: Float
        get() = safeFloat(FONT_SCALE, 1.0f)
        set(v) = put(FONT_SCALE, v)

    var msgReadInit: String
        get() = sp.getString(MSG_READ_INIT, "未读") ?: "未读"
        set(v) = put(MSG_READ_INIT, v)

    var msgUserTop: String
        get() = sp.getString(MSG_USER_TOP, "关闭") ?: "关闭"
        set(v) = put(MSG_USER_TOP, v)

    var linkClick: String
        get() = sp.getString(LINK_CLICK, "系统") ?: "系统"
        set(v) = put(LINK_CLICK, v)

    var channel: String
        get() = sp.getString(CHANNEL, "限断") ?: "限断"
        set(v) = put(CHANNEL, v)

    /**
     * 这个档位是否需要**常驻通知**（也就是是否需要前台服务）。
     *
     * 「限断」「关闭」要的是通知栏干净：连上之后一条都不留，只有断开才提醒。
     * 这两个档位一律不挂前台服务，退回原版那种普通后台服务 + 闹钟心跳。
     * 其余三档本来就要显示状态，用前台服务换更强的进程保护。
     */
    val needsForeground: Boolean
        get() = when (channel) {
            "限断", "仅断开时提醒", "关闭" -> false
            else -> true
        }

    var channelStart: Int
        get() = safeInt(CHANNEL_START, 23)
        set(v) = put(CHANNEL_START, v)

    var channelEnd: Int
        get() = safeInt(CHANNEL_END, 7)
        set(v) = put(CHANNEL_END, v)

    var mqttHost: String
        // 开源/云端构建版不预置私有服务器地址，由用户在设置页填写
        get() = sp.getString(MQTT_HOST, "") ?: ""
        set(v) = put(MQTT_HOST, v)

    var mqttPort: Int
        get() = safeInt(MQTT_PORT, 9009)
        set(v) = put(MQTT_PORT, v)

    var mqttTls: String
        get() = sp.getString(MQTT_TLS, "开启") ?: "开启"
        set(v) = put(MQTT_TLS, v)

    var mqttCert: String
        get() = sp.getString(MQTT_CERT, "") ?: ""
        set(v) = put(MQTT_CERT, v)

    var pushId: Int
        get() = safeInt(PUSH_ID, 0)
        set(v) = put(PUSH_ID, v)

    var pushKey: String
        get() = sp.getString(PUSH_KEY, "") ?: ""
        set(v) = put(PUSH_KEY, v)

    var selfHost: String
        get() = sp.getString(SELF_HOST, "") ?: ""
        set(v) = put(SELF_HOST, v)

    var selfPort: Int
        get() = safeInt(SELF_PORT, 3100)
        set(v) = put(SELF_PORT, v)

    var selfTls: String
        get() = sp.getString(SELF_TLS, "无证书") ?: "无证书"
        set(v) = put(SELF_TLS, v)

    var selfCert: String
        get() = sp.getString(SELF_CERT, "") ?: ""
        set(v) = put(SELF_CERT, v)

    var selfKey: String
        get() = sp.getString(SELF_KEY, "") ?: ""
        set(v) = put(SELF_KEY, v)

    var selfState: String
        get() = sp.getString(SELF_STATE, "关闭") ?: "关闭"
        set(v) = put(SELF_STATE, v)

    var selfApi: String
        get() = sp.getString(SELF_API, "") ?: ""
        set(v) = put(SELF_API, v)

    var serviceEnabled: Boolean
        get() = sp.getBoolean(SERVICE_ENABLED, true)
        set(v) = put(SERVICE_ENABLED, v)

    /**
     * 分组方式，取值只有「展开」「折叠」。
     *
     * 默认「展开」—— 与原版 PushMe 一致：每条消息各自一条通知，互不归档。
     */
    var notifGroup: String
        get() = sp.getString(NOTIF_GROUP, "展开") ?: "展开"
        set(v) = put(NOTIF_GROUP, v)

    /** 是否折叠。折叠 = 同组消息收进一张「N 条新消息」卡片，点开才看到每条 */
    val notifGroupCollapsed: Boolean
        get() = notifGroup == "折叠"

    fun selfEnabled(): Boolean = selfState == "开启" && selfHost.isNotBlank()

    /** 当前生效的连接参数 */
    fun activeTarget(): Target {
        return if (selfEnabled()) {
            Target(
                host = selfHost,
                port = selfPort,
                tls = selfTls != "无证书",
                cert = selfCert,
                key = selfKey,
                topic = selfKey,
                api = selfApi,
                selfHosted = true
            )
        } else {
            Target(
                host = mqttHost,
                port = mqttPort,
                tls = mqttTls == "开启",
                cert = mqttCert,
                key = pushKey,
                topic = pushKey,
                api = if (selfApi.isNotBlank()) selfApi else "https://push.i-i.me",
                selfHosted = false
            )
        }
    }

    data class Target(
        val host: String,
        val port: Int,
        val tls: Boolean,
        val cert: String,
        val key: String,
        val topic: String,
        val api: String,
        val selfHosted: Boolean
    )

    fun asMap(): Map<String, Any?> = mapOf(
        APP_THEME to appTheme,
        APP_COLOR to appColor,
        FONT_SCALE to fontScale,
        MSG_READ_INIT to msgReadInit,
        MSG_USER_TOP to msgUserTop,
        LINK_CLICK to linkClick,
        CHANNEL to channel,
        CHANNEL_START to channelStart,
        CHANNEL_END to channelEnd,
        MQTT_HOST to mqttHost,
        MQTT_PORT to mqttPort,
        MQTT_TLS to mqttTls,
        MQTT_CERT to mqttCert,
        PUSH_ID to pushId,
        PUSH_KEY to pushKey,
        SELF_HOST to selfHost,
        SELF_PORT to selfPort,
        SELF_TLS to selfTls,
        SELF_CERT to selfCert,
        SELF_KEY to selfKey,
        SELF_STATE to selfState,
        SELF_API to selfApi,
        SERVICE_ENABLED to serviceEnabled,
        NOTIF_GROUP to notifGroup
    )

    fun set(key: String, value: Any?) = put(key, value)
}
