package dev.chithram.nova_host

import android.app.Service
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.util.Log
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform

/** Runs the nova runner (Python) behind a Messenger. Subclasses only differ in manifest flags. */
abstract class NovaServiceBase : Service() {
    private var client: Messenger? = null

    private val handler = object : Handler(Looper.getMainLooper()) {
        override fun handleMessage(msg: Message) {
            when (msg.what) {
                NovaProtocol.MSG_START -> {
                    client = msg.replyTo
                    Thread({ startPython() }, "nova-python").start()
                }
                NovaProtocol.MSG_FEED -> {
                    val line = msg.data.getString("line") ?: return
                    try {
                        Python.getInstance().getModule("nova_android").callAttr("feed", line)
                    } catch (t: Throwable) {
                        Log.e(TAG, "feed failed", t)
                    }
                }
                NovaProtocol.MSG_STOP -> {
                    Log.i(TAG, "stop requested, ending process ${android.os.Process.myPid()}")
                    android.os.Process.killProcess(android.os.Process.myPid())
                }
            }
        }
    }

    private val messenger = Messenger(handler)

    override fun onBind(intent: Intent?): IBinder = messenger.binder

    private fun reply(what: Int, ok: Boolean, text: String) {
        val m = Message.obtain(null, what, if (ok) 1 else 0, 0)
        m.data = Bundle().apply { putString("line", text) }
        try {
            client?.send(m)
        } catch (t: Throwable) {
            Log.e(TAG, "reply failed", t)
        }
    }

    private fun startPython() {
        val tag = "uid=${android.os.Process.myUid()} pid=${android.os.Process.myPid()} " +
            "isolated=${android.os.Process.isIsolated()}"
        try {
            if (!Python.isStarted()) Python.start(AndroidPlatform(this))
            val mod = Python.getInstance().getModule("nova_android")
            mod.callAttr("init", LineSink { line ->
                val m = Message.obtain(null, NovaProtocol.MSG_LINE)
                m.data = Bundle().apply { putString("line", line) }
                try {
                    client?.send(m)
                } catch (t: Throwable) {
                    Log.e(TAG, "send failed", t)
                }
            })
            val py = mod.callAttr("version").toString()
            Log.i(TAG, "python $py started ($tag)")
            reply(NovaProtocol.MSG_STARTED, true, "python=$py $tag")
            mod.callAttr("run")
        } catch (t: Throwable) {
            Log.e(TAG, "python failed to start ($tag)", t)
            reply(NovaProtocol.MSG_STARTED, false, "$tag error=${t.javaClass.simpleName}: ${t.message}")
        }
    }

    companion object {
        const val TAG = "NovaService"
    }
}

class NovaService : NovaServiceBase()

class NovaIsolatedService : NovaServiceBase()
