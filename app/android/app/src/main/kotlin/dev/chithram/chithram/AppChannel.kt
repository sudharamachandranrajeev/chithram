package dev.chithram.chithram

import android.app.ActivityManager
import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Channel `dev.chithram/app`: what Dart asks the platform about the device.
 *
 *  - `formFactor` -> "tv" | "phone" (integration tests build the app directly)
 *  - `reportFullyDrawn` -> null; marks the first frame of Home for the cold-start
 *    measurement ("Fully drawn" in logcat and `am start -W`)
 *  - `memoryInfo` -> {totalMem: Long bytes, lowRam: Boolean}, which sizes the
 *    image cache
 */
object AppChannel {
    const val NAME = "dev.chithram/app"

    fun register(activity: MainActivity, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, NAME).setMethodCallHandler { call, result ->
            when (call.method) {
                "formFactor" -> result.success(FormFactor.detect(activity))
                "reportFullyDrawn" -> {
                    activity.reportFullyDrawn()
                    result.success(null)
                }
                "memoryInfo" -> {
                    val am = activity.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                    val info = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
                    result.success(mapOf("totalMem" to info.totalMem, "lowRam" to am.isLowRamDevice))
                }
                else -> result.notImplemented()
            }
        }
    }
}
