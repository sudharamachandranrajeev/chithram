// JNI glue: embeds CPython (python.org Android build) in the isolated service
// process. No Context, SharedPreferences or app files are touched: the stdlib and
// the runner are zip files in the native library directory, extension modules are
// libpymod_<name>.so files found by a small meta-path finder.
#include <jni.h>
#include <android/log.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <Python.h>

#define TAG "NovaJni"

static void throw_rt(JNIEnv *env, const char *msg) {
    (*env)->ThrowNew(env, (*env)->FindClass(env, "java/lang/RuntimeException"), msg);
}

JNIEXPORT jintArray JNICALL Java_dev_chithram_nova_1host_NovaNative_createPipes(JNIEnv *env, jclass cls) {
    int in_p[2], out_p[2];
    if (pipe(in_p) || pipe(out_p)) {
        throw_rt(env, strerror(errno));
        return NULL;
    }
    // [python reads, service writes, service reads, python writes]
    jint fds[4] = {in_p[0], in_p[1], out_p[0], out_p[1]};
    jintArray r = (*env)->NewIntArray(env, 4);
    (*env)->SetIntArrayRegion(env, r, 0, 4, fds);
    return r;
}

static wchar_t *wide(const char *s) {
    size_t n = strlen(s);
    wchar_t *w = malloc((n + 1) * sizeof(wchar_t));
    for (size_t i = 0; i <= n; i++) w[i] = (unsigned char)s[i];  // paths are ASCII
    return w;
}

static const char *BOOT =
    "import sys, os, importlib.machinery as _m, importlib.util as _u\n"
    "_lib = os.environ['NOVA_LIBDIR']\n"
    "class _ExtFinder:\n"
    "    @staticmethod\n"
    "    def find_spec(name, path=None, target=None):\n"
    "        if '.' in name: return None\n"
    "        p = _lib + '/libpymod_' + name + '.so'\n"
    "        if os.path.exists(p):\n"
    "            return _u.spec_from_file_location(name, p, loader=_m.ExtensionFileLoader(name, p))\n"
    "sys.meta_path.append(_ExtFinder)\n"
    "import nova_android\n"
    "_rc = nova_android.main()\n"
    "sys.stdout = sys.__stdout__\n";

// Runs the interpreter until the runner quits. Returns 0 on a clean end.
JNIEXPORT jint JNICALL Java_dev_chithram_nova_1host_NovaNative_runPython(
    JNIEnv *env, jclass cls, jstring jlib, jint inFd, jint outFd, jboolean audit) {
    const char *lib = (*env)->GetStringUTFChars(env, jlib, NULL);
    char stdlib[1024], runtime[1024], fdbuf[32];
    snprintf(stdlib, sizeof stdlib, "%s/libnova_stdlib.so", lib);
    snprintf(runtime, sizeof runtime, "%s/libnova_runtime.so", lib);
    setenv("NOVA_LIBDIR", lib, 1);
    snprintf(fdbuf, sizeof fdbuf, "%d", inFd);
    setenv("NOVA_IN_FD", fdbuf, 1);
    snprintf(fdbuf, sizeof fdbuf, "%d", outFd);
    setenv("NOVA_OUT_FD", fdbuf, 1);
    setenv("NOVA_AUDIT", audit ? "1" : "0", 1);
    setenv("TMPDIR", "/nonexistent", 1);

    PyConfig config;
    PyConfig_InitIsolatedConfig(&config);
    config.module_search_paths_set = 1;
    PyWideStringList_Append(&config.module_search_paths, wide(stdlib));
    PyWideStringList_Append(&config.module_search_paths, wide(runtime));
    config.write_bytecode = 0;
    config.install_signal_handlers = 0;
    config.site_import = 0;
    config.pathconfig_warnings = 0;
    PyConfig_SetBytesString(&config, &config.program_name, "nova");
    PyStatus st = Py_InitializeFromConfig(&config);
    PyConfig_Clear(&config);
    if (PyStatus_Exception(st)) {
        __android_log_print(ANDROID_LOG_ERROR, TAG, "Py_InitializeFromConfig failed: %s", st.err_msg ? st.err_msg : "?");
        throw_rt(env, st.err_msg ? st.err_msg : "Py_InitializeFromConfig failed");
        (*env)->ReleaseStringUTFChars(env, jlib, lib);
        return 1;
    }
    int rc = PyRun_SimpleString(BOOT);
    __android_log_print(ANDROID_LOG_INFO, TAG, "runner finished rc=%d", rc);
    (*env)->ReleaseStringUTFChars(env, jlib, lib);
    return rc;
}
