package hk.mario.money_manager

import android.content.Context
import org.json.JSONObject
import java.io.File

/** 通知捕捉嘅本地儲存：見過嘅 App、用戶揀咗嘅 App，同未處理嘅通知隊列。 */
object CaptureStore {
    private const val PREFS = "mm_capture"
    private const val SEEN = "seen_packages"
    private const val ALLOWED = "allowed_packages"
    private const val QUEUE = "capture_queue.jsonl"
    private const val MAX_QUEUE_BYTES = 2_000_000L
    private val lock = Any()

    fun markSeen(context: Context, pkg: String) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val seen = prefs.getStringSet(SEEN, emptySet()) ?: emptySet()
        if (pkg !in seen) prefs.edit().putStringSet(SEEN, seen + pkg).apply()
    }

    fun seen(context: Context): Set<String> =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getStringSet(SEEN, emptySet()) ?: emptySet()

    fun allowed(context: Context): Set<String> =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getStringSet(ALLOWED, emptySet()) ?: emptySet()

    fun setAllowed(context: Context, packages: Collection<String>) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putStringSet(ALLOWED, packages.toSet()).apply()
    }

    fun enqueue(context: Context, item: JSONObject) {
        synchronized(lock) {
            val file = File(context.filesDir, QUEUE)
            if (file.exists() && file.length() > MAX_QUEUE_BYTES) return
            file.appendText(item.toString() + "\n")
        }
    }

    fun drain(context: Context): List<Map<String, Any?>> {
        synchronized(lock) {
            val file = File(context.filesDir, QUEUE)
            if (!file.exists()) return emptyList()
            val lines = file.readLines()
            file.delete()
            return lines.filter { it.isNotBlank() }.mapNotNull { line ->
                try {
                    val o = JSONObject(line)
                    o.keys().asSequence().associateWith { k -> o.opt(k).takeUnless { it == JSONObject.NULL } }
                } catch (e: Exception) {
                    null
                }
            }
        }
    }
}
