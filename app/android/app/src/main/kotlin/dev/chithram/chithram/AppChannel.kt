package dev.chithram.chithram

import android.app.ActivityManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File
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
 *  - `installApk` {path} -> "started" | "permission": hands a downloaded APK
 *    (under the cache's updates/) to the system installer; "permission" when
 *    installing apps isn't allowed yet, after opening that setting
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
                "installApk" -> result.success(installApk(activity, call.argument<String>("path")!!))
                else -> result.notImplemented()
            }
        }
    }

    private fun installApk(activity: MainActivity, path: String): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !activity.packageManager.canRequestPackageInstalls()) {
            val ask = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}"))
            try {
                activity.startActivity(ask)
            } catch (e: ActivityNotFoundException) {
                // Some TVs have no per-app screen; the general one then.
                activity.startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS))
            }
            return "permission"
        }
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", File(path))
        activity.startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION),
        )
        return "started"
    }
}
