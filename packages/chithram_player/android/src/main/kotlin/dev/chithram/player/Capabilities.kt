package dev.chithram.player

import android.content.Context
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.os.Build
import android.view.Display
import android.view.WindowManager

/** What this device can decode in hardware and show, for picking a stream format. */
object Capabilities {
    // Best first.
    private val codecs = listOf(
        "av1" to "video/av01",
        "vp9" to "video/x-vnd.on2.vp9",
        "h265" to "video/hevc",
        "h264" to "video/avc",
    )

    fun query(context: Context): Map<String, Any> {
        val infos = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.filter { !it.isEncoder }
        val supported = codecs.filter { (_, mime) -> infos.any { isHardware(it) && handles(it, mime) } }
            .map { it.first }
        val display = display(context)
        return mapOf(
            "videoCodecs" to supported.ifEmpty { listOf("h264") },
            // The short side: the height of a landscape picture.
            "maxHeight" to (display?.mode?.let { minOf(it.physicalWidth, it.physicalHeight) } ?: 1080),
            "hdr" to hdr(display),
        )
    }

    private fun handles(info: MediaCodecInfo, mime: String) =
        info.supportedTypes.any { it.equals(mime, ignoreCase = true) }

    private fun isHardware(info: MediaCodecInfo): Boolean =
        if (Build.VERSION.SDK_INT >= 29) info.isHardwareAccelerated
        else !info.name.startsWith("OMX.google.") && !info.name.startsWith("c2.android.")

    @Suppress("DEPRECATION")
    private fun display(context: Context): Display? =
        (context.getSystemService(Context.WINDOW_SERVICE) as? WindowManager)?.defaultDisplay

    @Suppress("DEPRECATION")
    private fun hdr(display: Display?): Boolean =
        display?.hdrCapabilities?.supportedHdrTypes?.isNotEmpty() == true
}
