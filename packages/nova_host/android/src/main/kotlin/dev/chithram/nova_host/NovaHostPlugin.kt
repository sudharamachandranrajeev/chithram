package dev.chithram.nova_host

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges Dart to the :novaiso isolated Python service.
 * Dart -> start{audit}, send{line}, stop. Native -> Dart: line(String), ended().
 */
class NovaHostPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private val main = Handler(Looper.getMainLooper())

    private var conn: ServiceConnection? = null
    private var service: Messenger? = null
    private var pendingStart: MethodChannel.Result? = null
    private var timeout: Runnable? = null

    private val assembler = LineAssembler()

    private val inbound = Messenger(object : Handler(Looper.getMainLooper()) {
        override fun handleMessage(msg: Message) {
            when (msg.what) {
                NovaProtocol.MSG_STARTED -> finishStart(msg.arg1 == 1, msg.data.getString("line") ?: "")
                NovaProtocol.MSG_LINE -> {
                    val line = assembler.add(msg)
                    if (!line.isNullOrEmpty()) channel.invokeMethod("line", line)
                }
            }
        }
    })

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "dev.chithram/nova_host")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        stop()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> start(call.argument<Boolean>("audit") != false, result)
            "send" -> {
                try {
                    for (m in NovaProtocol.chunks(call.argument<String>("line") ?: "", NovaProtocol.MSG_FEED)) service?.send(m)
                    result.success(true)
                } catch (t: Throwable) {
                    result.success(false)
                }
            }
            "stop" -> {
                stop()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun finishStart(ok: Boolean, detail: String) {
        timeout?.let { main.removeCallbacks(it) }
        val r = pendingStart ?: return
        pendingStart = null
        r.success(mapOf("started" to ok, "detail" to detail))
        if (!ok) stop()
    }

    private fun start(audit: Boolean, result: MethodChannel.Result) {
        stop()
        pendingStart = result
        // Only the isolated service exists: there is no same-UID fallback.
        val cls = NovaIsolatedService::class.java
        val c = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName, binder: IBinder) {
                val s = Messenger(binder)
                service = s
                val m = Message.obtain(null, NovaProtocol.MSG_START)
                m.data = Bundle().apply { putBoolean("audit", audit) }
                m.replyTo = inbound
                try {
                    s.send(m)
                } catch (t: Throwable) {
                    finishStart(false, "send START failed: $t")
                }
            }

            override fun onServiceDisconnected(name: ComponentName) {
                Log.w(TAG, "service disconnected: $name")
                service = null
                if (pendingStart != null) finishStart(false, "service process died while starting")
                else channel.invokeMethod("ended", null)
            }

            override fun onBindingDied(name: ComponentName) {
                if (pendingStart != null) finishStart(false, "binding died")
            }
        }
        conn = c
        val ok = try {
            context.bindService(Intent(context, cls), c, Context.BIND_AUTO_CREATE)
        } catch (t: Throwable) {
            Log.e(TAG, "bindService threw", t)
            false
        }
        if (!ok) {
            finishStart(false, "bindService returned false for ${cls.simpleName}")
            return
        }
        val t = Runnable { finishStart(false, "timeout waiting for the isolated Python service (30 s)") }
        timeout = t
        main.postDelayed(t, 30_000)
    }

    private fun stop() {
        try {
            service?.send(Message.obtain(null, NovaProtocol.MSG_STOP))
        } catch (_: Throwable) {
        }
        conn?.let {
            try {
                context.unbindService(it)
            } catch (_: Throwable) {
            }
        }
        conn = null
        service = null
    }

    companion object {
        const val TAG = "NovaHostPlugin"
    }
}
