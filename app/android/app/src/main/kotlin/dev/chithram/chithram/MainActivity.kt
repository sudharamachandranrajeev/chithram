package dev.chithram.chithram

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
