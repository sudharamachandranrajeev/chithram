package dev.chithram.chithram

import android.app.ActivityManager
import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
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
 *  - `sfxLoad` {name: path} -> null; `sfxPlay` name -> null: short UI sounds
 *    through a SoundPool (low latency; a name not loaded yet plays nothing)
 */
object AppChannel {
    const val NAME = "dev.chithram/app"

    private var sounds: SoundPool? = null
    private val soundIds = mutableMapOf<String, Int>()

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
                "sfxLoad" -> {
                    val pool = sounds ?: SoundPool.Builder()
                        .setMaxStreams(4)
                        .setAudioAttributes(
                            AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                .build(),
                        )
                        .build()
                        .also { sounds = it }
                    val paths = call.arguments as Map<*, *>
                    for ((name, path) in paths) {
                        if (name is String && path is String && name !in soundIds) soundIds[name] = pool.load(path, 1)
                    }
                    result.success(null)
                }
                "sfxPlay" -> {
                    val id = soundIds[call.arguments as? String]
                    if (id != null) sounds?.play(id, 1f, 1f, 1, 0, 1f)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
