package hk.mario.money_manager

import android.app.Activity
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.tech.NfcF
import io.flutter.plugin.common.MethodChannel

/**
 * 經 NFC 讀八達通（FeliCa）餘額。只讀公開、唔加密嘅餘額區（service 0x0117），讀唔到行程。
 */
class OctopusReader(private val activity: Activity) {
    private var pending: MethodChannel.Result? = null

    fun start(result: MethodChannel.Result) {
        val adapter = NfcAdapter.getDefaultAdapter(activity)
        if (adapter == null) {
            result.error("no_nfc", "呢部機冇 NFC", null)
            return
        }
        if (!adapter.isEnabled) {
            result.error("nfc_off", "請先喺系統設定開啟 NFC", null)
            return
        }
        pending?.error("cancelled", "已取消", null)
        pending = result
        adapter.enableReaderMode(
            activity,
            { tag -> onTag(tag) },
            NfcAdapter.FLAG_READER_NFC_F or NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK or NfcAdapter.FLAG_READER_NO_PLATFORM_SOUNDS,
            null,
        )
    }

    fun stop() {
        NfcAdapter.getDefaultAdapter(activity)?.disableReaderMode(activity)
        pending?.error("cancelled", "已取消", null)
        pending = null
    }

    private fun onTag(tag: Tag) {
        val result = pending ?: return
        val outcome: Pair<Long?, String?> = try {
            Pair(readRawBalance(tag), null)
        } catch (e: Exception) {
            Pair(null, e.message ?: "讀唔到張卡")
        }
        activity.runOnUiThread {
            NfcAdapter.getDefaultAdapter(activity)?.disableReaderMode(activity)
            pending = null
            val (raw, error) = outcome
            if (raw != null) result.success(raw) else result.error("read_failed", error, null)
        }
    }

    /** 返回卡入面嘅原始數值（0.1 港元為單位，包含按金偏移）。 */
    private fun readRawBalance(tag: Tag): Long {
        val nfcF = NfcF.get(tag) ?: throw IllegalStateException("呢張唔係八達通")
        nfcF.use { f ->
            f.connect()
            val idm = tag.id
            // Read Without Encryption：1 個 service (0x0117，little endian)、1 個 block (block 0)
            val body = byteArrayOf(0x06) + idm + byteArrayOf(0x01, 0x17, 0x01, 0x01, 0x80.toByte(), 0x00)
            val cmd = byteArrayOf((body.size + 1).toByte()) + body
            val res = f.transceive(cmd)
            if (res.size < 29 || res[1] != 0x07.toByte() || res[10] != 0.toByte()) {
                throw IllegalStateException("讀唔到餘額，請貼穩張卡再試")
            }
            var raw = 0L
            for (i in 13 until 17) raw = (raw shl 8) or (res[i].toLong() and 0xff)
            return raw
        }
    }
}
