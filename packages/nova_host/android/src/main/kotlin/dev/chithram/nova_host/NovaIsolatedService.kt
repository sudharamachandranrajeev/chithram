package dev.chithram.nova_host

import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.concurrent.Executors

/**
 * Runs CPython in an isolated process (android:isolatedProcess="true": own uid in
 * 99000-99999, no INTERNET, no access to the app's data). No Context-dependent
 * Python start-up is used (that is what made Chaquopy fail here).
 */
class NovaIsolatedService : Service() {
    private var client: Messenger? = null
    private var toPython: FileOutputStream? = null
    private val feeder = LineAssembler()
    private val writer = Executors.newSingleThreadExecutor()
    @Volatile private var started = false

    private val handler = object : Handler(Looper.getMainLooper()) {
        override fun handleMessage(msg: Message) {
            when (msg.what) {
                NovaProtocol.MSG_START -> {
                    client = msg.replyTo
                    val audit = msg.data.getBoolean("audit", true)
                    Thread({ boot(audit) }, "nova-boot").start()
                }
                NovaProtocol.MSG_FEED -> {
                    val line = feeder.add(msg) ?: return
                    writer.execute {
                        try {
                            toPython?.write((line + "\n").toByteArray(Charsets.UTF_8))
                            toPython?.flush()
                        } catch (t: Throwable) {
                            Log.w(TAG, "write to python failed: $t")
                        }
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

    private fun send(what: Int, ok: Boolean, text: String) {
        try {
            if (what == NovaProtocol.MSG_STARTED) {
                val m = Message.obtain(null, what, if (ok) 1 else 0, 0)
                m.data = android.os.Bundle().apply { putString("line", text) }
                client?.send(m)
            } else {
                for (m in NovaProtocol.chunks(text, what)) client?.send(m)
            }
        } catch (t: Throwable) {
            Log.e(TAG, "send failed", t)
        }
    }

    private fun boot(audit: Boolean) {
        val id = "uid=${android.os.Process.myUid()} pid=${android.os.Process.myPid()} " +
            "isolated=${android.os.Process.isIsolated()} abi=${Build.SUPPORTED_ABIS.firstOrNull()}"
        try {
            val abi = Build.SUPPORTED_ABIS.firstOrNull()
            if (abi != "arm64-v8a" && abi != "x86_64") {
                send(NovaProtocol.MSG_STARTED, false, "python.org publishes CPython for Android only for arm64-v8a and x86_64, not $abi ($id)")
                return
            }
            val lib = applicationInfo.nativeLibraryDir
            for (f in listOf("libpython3.14.so", "libnova_stdlib.so", "libnova_runtime.so", "libnova_jni.so")) {
                if (!File(lib, f).exists()) {
                    send(NovaProtocol.MSG_STARTED, false,
                        "$f missing in $lib (native libs not extracted?) files=${File(lib).list()?.take(8)} ($id)")
                    return
                }
            }
            System.loadLibrary("python3.14")
            System.loadLibrary("nova_jni")
            val fds = NovaNative.createPipes()
            toPython = FileOutputStream(ParcelFileDescriptor.adoptFd(fds[1]).fileDescriptor)
            val fromPython = FileInputStream(ParcelFileDescriptor.adoptFd(fds[2]).fileDescriptor)

            Thread({
                try {
                    val rc = NovaNative.runPython(lib, fds[0], fds[3], audit)
                    if (!started) send(NovaProtocol.MSG_STARTED, false, "python exited rc=$rc before ready ($id)")
                } catch (t: Throwable) {
                    Log.e(TAG, "runPython failed", t)
                    if (!started) send(NovaProtocol.MSG_STARTED, false, "runPython: ${t.message} ($id)")
                }
            }, "nova-python").start()

            val reader = fromPython.bufferedReader(Charsets.UTF_8)
            while (true) {
                val line = reader.readLine() ?: break
                if (!started) {
                    started = true
                    if (line.contains("\"op\":\"ready\"")) {
                        send(NovaProtocol.MSG_STARTED, true, "$line $id")
                    } else {
                        send(NovaProtocol.MSG_STARTED, false, "runner said: $line ($id)")
                    }
                    continue
                }
                send(NovaProtocol.MSG_LINE, true, line)
            }
        } catch (t: Throwable) {
            Log.e(TAG, "boot failed ($id)", t)
            if (!started) send(NovaProtocol.MSG_STARTED, false, "${t.javaClass.simpleName}: ${t.message} ($id)")
        }
    }

    companion object {
        const val TAG = "NovaService"
    }
}
