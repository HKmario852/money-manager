package hk.mario.money_manager

import android.app.Notification
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * 收集付款通知，等 App 下次開嘅時候交俾 Gemini 讀。
 *
 * 私隱：只有用戶喺 App 揀咗嘅 App（銀行、信用卡、錢包…）嘅通知內容會存低；
 * 其他 App 只記低套件名，方便用戶喺清單度揀，內容唔會存。
 */
class NotificationCaptureService : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val n = sbn.notification ?: return
        if (sbn.isOngoing || n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        if (sbn.packageName == packageName) return
        val store = NotificationStore(this)
        store.markSeen(sbn.packageName)
        if (sbn.packageName !in store.allowedPackages()) return

        val extras = n.extras
        val parts = listOfNotNull(
            extras.getCharSequence(Notification.EXTRA_TITLE),
            extras.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: extras.getCharSequence(Notification.EXTRA_TEXT),
            extras.getCharSequence(Notification.EXTRA_SUB_TEXT),
        ).map { it.toString().trim() }.filter { it.isNotEmpty() }
        if (parts.isEmpty()) return

        store.append(
            JSONObject()
                .put("key", "${sbn.key}|${sbn.postTime}")
                .put("package", sbn.packageName)
                .put("app", appLabel(this, sbn.packageName))
                .put("text", parts.joinToString("\n"))
                .put("postedAt", sbn.postTime)
        )
    }
}

fun appLabel(context: Context, pkg: String): String = try {
    val pm = context.packageManager
    pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
} catch (e: PackageManager.NameNotFoundException) {
    pkg
}

/** 通知佇列：一個 JSON lines 檔 + SharedPreferences，Service 同 Flutter 兩邊共用。 */
class NotificationStore(private val context: Context) {
    private val prefs = context.getSharedPreferences("notification_capture", Context.MODE_PRIVATE)
    private val queue = File(context.filesDir, "captured_notifications.jsonl")

    fun allowedPackages(): Set<String> = prefs.getStringSet("allowed", emptySet()) ?: emptySet()

    fun setAllowedPackages(packages: List<String>) = prefs.edit().putStringSet("allowed", packages.toSet()).apply()

    fun markSeen(pkg: String) {
        val seen = prefs.getStringSet("seen", emptySet()) ?: emptySet()
        if (pkg !in seen) prefs.edit().putStringSet("seen", seen + pkg).apply()
    }

    fun seenPackages(): Set<String> = prefs.getStringSet("seen", emptySet()) ?: emptySet()

    /** 有桌面圖示嘅 App（俾用戶揀邊啲通知要讀）。 */
    fun launchableApps(): List<Map<String, String>> {
        val pm = context.packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        @Suppress("DEPRECATION")
        val pkgs = pm.queryIntentActivities(intent, 0).map { it.activityInfo.packageName }.toSet() + seenPackages()
        return pkgs.filter { it != context.packageName }
            .map { mapOf("package" to it, "label" to appLabel(context, it)) }
            .sortedBy { it["label"] }
    }

    fun append(item: JSONObject) = synchronized(lock) {
        queue.appendText(item.toString() + "\n")
        // 唔好無限增長：只留最近 500 條
        val lines = queue.readLines()
        if (lines.size > 500) queue.writeText(lines.takeLast(500).joinToString("\n", postfix = "\n"))
    }

    fun drain(): JSONArray = synchronized(lock) {
        val result = JSONArray()
        if (queue.exists()) {
            queue.readLines().filter { it.isNotBlank() }.forEach {
                try {
                    result.put(JSONObject(it))
                } catch (_: Exception) {
                }
            }
            queue.delete()
        }
        result
    }

    companion object {
        private val lock = Any()

        fun isAccessGranted(context: Context): Boolean {
            val enabled = Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners") ?: ""
            val me = ComponentName(context, NotificationCaptureService::class.java)
            return enabled.split(":").any { ComponentName.unflattenFromString(it) == me }
        }

        fun openAccessSettings(context: Context) {
            context.startActivity(
                Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }
    }
}
