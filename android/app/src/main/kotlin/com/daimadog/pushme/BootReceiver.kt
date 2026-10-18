package com.daimadog.pushme

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** 开机自启：拉起常驻推送服务 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != Intent.ACTION_MY_PACKAGE_REPLACED &&
            intent.action != "android.intent.action.QUICKBOOT_POWERON"
        ) return
        AppContextHolder.context = context.applicationContext
        val prefs = Prefs(context)
        if (!prefs.serviceEnabled) return
        if (prefs.activeTarget().key.isBlank()) return
        try {
            MqttService.start(context)
        } catch (e: Exception) {
            android.util.Log.w("PushMeBoot", "start service failed: ${e.message}")
        }
    }
}
