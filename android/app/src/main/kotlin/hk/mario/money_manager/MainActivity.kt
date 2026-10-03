package hk.mario.money_manager

import android.content.ComponentName
import android.content.Intent
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// local_auth 需要 FragmentActivity
class MainActivity : FlutterFragmentActivity() {
    private val octopus by lazy { OctopusReader(this) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // 開咗私隱鎖：唔俾截圖，「最近使用」畫面唔顯示內容
        MethodChannel(messenger, "hk.mario.money_manager/secure")
            .setMethodCallHandler { call, result ->
                if (call.method == "setSecure") {
                    if (call.arguments == true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }

        // 自動記錄：通知讀取同八達通 NFC
        MethodChannel(messenger, "hk.mario.money_manager/capture")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isNotificationAccessGranted" -> result.success(notificationAccessGranted())
                    "openNotificationAccessSettings" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(null)
                    }
                    "getSeenApps" -> result.success(
                        CaptureStore.seen(this).map { mapOf("package" to it, "label" to appLabel(it)) },
                    )
                    "getAllowedApps" -> result.success(CaptureStore.allowed(this).toList())
                    "setAllowedApps" -> {
                        @Suppress("UNCHECKED_CAST")
                        CaptureStore.setAllowed(this, (call.arguments as? List<String>) ?: emptyList())
                        result.success(null)
                    }
                    "drainNotifications" -> result.success(
                        CaptureStore.drain(this).map { it + ("label" to appLabel(it["package"] as? String ?: "")) },
                    )
                    "hasNfc" -> result.success(android.nfc.NfcAdapter.getDefaultAdapter(this) != null)
                    "readOctopus" -> octopus.start(result)
                    "cancelOctopus" -> {
                        octopus.stop()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun notificationAccessGranted(): Boolean {
        val enabled = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: return false
        val me = ComponentName(this, PaymentNotificationListener::class.java).flattenToString()
        return enabled.split(":").any { it == me }
    }

    @Suppress("DEPRECATION")
    private fun appLabel(pkg: String): String? = try {
        val info = packageManager.getApplicationInfo(pkg, 0)
        packageManager.getApplicationLabel(info).toString()
    } catch (e: Exception) {
        null
    }
}
