package dev.chithram.chithram

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null

    // The form factor reaches Dart before the first frame as an entrypoint
    // argument, after whatever the launcher passed (the release smoke test's
    // --smoke).
    override fun getDartEntrypointArgs(): List<String>? =
        (super.getDartEntrypointArgs() ?: emptyList()) + "--form-factor=${FormFactor.detect(this)}"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Integration tests build the app directly, so they ask.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.chithram/app")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "formFactor" -> result.success(FormFactor.detect(this))
                    else -> result.notImplemented()
                }
            }
        // Receiving LocalSend discovery packets needs the multicast lock; the
        // Receive screen holds it only while it is open.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.chithram/net")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "multicastLock" -> {
                        setMulticastLock(call.arguments as? Boolean ?: false)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun setMulticastLock(on: Boolean) {
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager ?: return
        if (on) {
            if (multicastLock == null) {
                multicastLock = wifi.createMulticastLock("chithram-localsend").apply {
                    setReferenceCounted(false)
                }
            }
            multicastLock?.acquire()
        } else {
            multicastLock?.let { if (it.isHeld) it.release() }
        }
    }

    override fun onDestroy() {
        setMulticastLock(false)
        super.onDestroy()
    }
}
