package dev.chithram.nova_host

/** JNI into libnova_jni.so, which embeds CPython. */
object NovaNative {
    /** [python stdin read, service write, service read, python stdout write] */
    @JvmStatic external fun createPipes(): IntArray

    /** Blocks until the runner quits. */
    @JvmStatic external fun runPython(libDir: String, inFd: Int, outFd: Int, audit: Boolean): Int
}
