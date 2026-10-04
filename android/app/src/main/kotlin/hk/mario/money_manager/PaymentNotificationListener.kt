package hk.mario.money_manager

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONObject

/**
 * 讀取用戶揀咗嘅付款 App 嘅通知，放入隊列等 App 開嗰陣處理。
 * 只記錄用戶允許嘅 App；其他 App 淨係記低套件名，俾用戶喺設定揀。
 */
class PaymentNotificationListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val pkg = sbn.packageName ?: return
        if (pkg == packageName) return
        val n = sbn.notification ?: return
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        CaptureStore.markSeen(this, pkg)
        if (pkg !in CaptureStore.allowed(this)) return

        val extras = n.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
        val big = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
        val text = big ?: extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
        if (text.isNullOrBlank() && title.isNullOrBlank()) return

        CaptureStore.enqueue(
            this,
            JSONObject()
                .put("id", "$pkg:${sbn.key}:${(title + "|" + text).hashCode()}")
                .put("package", pkg)
                .put("title", title)
                .put("text", text)
                .put("postTime", sbn.postTime),
        )
    }
}
