package com.daimadog.pushme

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** 通知上的「已读 / 删除」按钮 */
class NotificationActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        AppContextHolder.context = context.applicationContext
        val id = intent.getLongExtra("messageId", 0L)
        if (id <= 0L) return
        val db = MessageDb.get(context)
        val notifier = Notifier(context)
        when (intent.action) {
            Notifier.ACTION_MARK_READ -> {
                db.markRead(listOf(id), true)
                notifier.cancelMessage(id)
                PushEvents.emitRefresh()
            }
            Notifier.ACTION_DELETE -> {
                db.delete(listOf(id))
                notifier.cancelMessage(id)
                PushEvents.emitRefresh()
            }
        }
    }
}
