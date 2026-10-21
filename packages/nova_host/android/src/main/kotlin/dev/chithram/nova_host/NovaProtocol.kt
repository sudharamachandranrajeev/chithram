package dev.chithram.nova_host

import android.os.Bundle
import android.os.Message

/** Messenger message ids shared by the plugin and the isolated service. */
object NovaProtocol {
    const val MSG_START = 1    // client -> service (replyTo = client), data "audit"
    const val MSG_FEED = 2     // client -> service, chunked line
    const val MSG_STOP = 3     // client -> service: end the process
    const val MSG_STARTED = 10 // service -> client, arg1 = 1 ok / 0 failed, data "line" = detail
    const val MSG_LINE = 11    // service -> client, chunked line

    /** Binder transactions are limited to about 1 MB, so long lines travel in pieces. */
    const val CHUNK_CHARS = 100_000

    fun chunks(line: String, what: Int): List<Message> {
        val out = ArrayList<Message>()
        var i = 0
        do {
            val end = minOf(line.length, i + CHUNK_CHARS)
            val m = Message.obtain(null, what)
            m.data = Bundle().apply {
                putString("line", line.substring(i, end))
                putBoolean("more", end < line.length)
            }
            out.add(m)
            i = end
        } while (i < line.length)
        return out
    }
}

/** Reassembles chunked lines. */
class LineAssembler {
    private val sb = StringBuilder()

    /** Returns the full line once the last chunk arrived, else null. */
    fun add(m: Message): String? {
        sb.append(m.data.getString("line") ?: "")
        if (m.data.getBoolean("more")) return null
        val s = sb.toString()
        sb.setLength(0)
        return s
    }
}
