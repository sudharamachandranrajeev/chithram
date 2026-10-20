package dev.chithram.nova_host

/** Messenger message ids shared by the plugin and the services. */
object NovaProtocol {
    const val MSG_START = 1   // client -> service (replyTo = client)
    const val MSG_FEED = 2    // client -> service, data "line"
    const val MSG_STOP = 3    // client -> service: end the process
    const val MSG_STARTED = 10 // service -> client, arg1 = 1 ok / 0 failed, data "detail"
    const val MSG_LINE = 11    // service -> client, data "line"
}

/** Handed to Python (nova_android.init); Python calls line() with NDJSON lines. */
class LineSink(private val out: (String) -> Unit) {
    fun line(s: String) {
        out(s)
    }
}
