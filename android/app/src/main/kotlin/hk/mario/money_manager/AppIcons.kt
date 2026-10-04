package hk.mario.money_manager

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/** 「App 課金」畫面：按 Google Play 嘅 App 名搵電話上裝咗嘅 App 圖示。 */
object AppIcons {
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    fun find(context: Context, names: List<String>, result: MethodChannel.Result) {
        executor.execute {
            val out = try {
                lookup(context, names)
            } catch (e: Exception) {
                emptyMap()
            }
            main.post { result.success(out) }
        }
    }

    private fun key(s: String) = s.lowercase().filter { it.isLetterOrDigit() }

    private fun lookup(context: Context, names: List<String>): Map<String, ByteArray> {
        val pm = context.packageManager
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val apps = pm.queryIntentActivities(launcher, 0)
            .map { it.activityInfo.applicationInfo }
            .distinctBy { it.packageName }
            .map { key(pm.getApplicationLabel(it).toString()) to it }
            .filter { it.first.length >= 3 }
        val out = mutableMapOf<String, ByteArray>()
        for (name in names) {
            val k = key(name)
            if (k.isEmpty()) continue
            // 名一樣最好；否則 Play 名包含裝咗嘅 App 名（例如「Garena 傳說對決 - …」），揀最長嗰個
            val app = apps.firstOrNull { it.first == k }?.second
                ?: apps.filter { k.contains(it.first) }.maxByOrNull { it.first.length }?.second
                ?: continue
            out[name] = png(pm.getApplicationIcon(app))
        }
        return out
    }

    private fun png(drawable: android.graphics.drawable.Drawable): ByteArray {
        val size = 96
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        drawable.setBounds(0, 0, size, size)
        drawable.draw(Canvas(bitmap))
        return ByteArrayOutputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
            it.toByteArray()
        }
    }
}
