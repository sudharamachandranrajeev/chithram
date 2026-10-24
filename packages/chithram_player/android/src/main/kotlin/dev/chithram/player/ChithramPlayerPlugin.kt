package dev.chithram.player

import android.app.Activity
import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Method channel front for [PlayerHost]; also registers the SurfaceView platform view. */
class ChithramPlayerPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var messenger: BinaryMessenger
    private lateinit var context: Context
    private var activity: Activity? = null
    private var nextId = 1
    private val hosts = HashMap<Int, PlayerHost>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        messenger = binding.binaryMessenger
        context = binding.applicationContext
        channel = MethodChannel(messenger, "chithram_player/methods")
        channel.setMethodCallHandler(this)
        binding.platformViewRegistry.registerViewFactory(
            "chithram_player/surface",
            SurfaceViewFactory { id -> hosts[id] },
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        hosts.values.toList().forEach { it.release() }
        hosts.clear()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivity() { activity = null }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "create" -> {
                    val id = nextId++
                    hosts[id] = PlayerHost(context, id, messenger)
                    result.success(id)
                }
                "capabilities" -> result.success(Capabilities.query(activity ?: context))
                "launchArgs" -> {
                    val extras = activity?.intent?.extras
                    val out = HashMap<String, String>()
                    extras?.keySet()?.forEach { k -> extras.getString(k)?.let { out[k] = it } }
                    result.success(out)
                }
                else -> {
                    val host = hosts[call.argument<Int>("id") ?: -1]
                    if (host == null) {
                        result.error("no_player", "unknown player id", null)
                        return
                    }
                    when (call.method) {
                        "open" -> {
                            host.open(
                                videoUrl = call.argument<String>("videoUrl")!!,
                                audioUrl = call.argument<String>("audioUrl"),
                                headers = call.argument<Map<String, String>>("headers") ?: emptyMap(),
                                isLive = call.argument<Boolean>("isLive") ?: false,
                                startMs = (call.argument<Number>("startMs") ?: 0).toLong(),
                            )
                            result.success(null)
                        }
                        "selectTrack" -> {
                            host.selectTrack(call.argument<String>("kind") ?: "audio", call.argument<String>("trackId"))
                            result.success(null)
                        }
                        "trackPreferences" -> {
                            host.setPreferences(
                                audioLanguage = call.argument<String>("audioLanguage"),
                                textLanguage = call.argument<String>("textLanguage"),
                                text = call.argument<Boolean>("text") ?: false,
                            )
                            result.success(null)
                        }
                        "play" -> { host.play(); result.success(null) }
                        "pause" -> { host.pause(); result.success(null) }
                        "seek" -> {
                            host.seek((call.argument<Number>("positionMs") ?: 0).toLong())
                            result.success(null)
                        }
                        "dispose" -> {
                            hosts.remove(host.id)
                            host.release()
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }
            }
        } catch (e: Exception) {
            result.error("player_error", e.message, null)
        }
    }
}
