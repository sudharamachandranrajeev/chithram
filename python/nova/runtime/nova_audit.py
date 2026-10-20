"""Extra layer: a Python audit hook that refuses network, process, ctypes and
filesystem-write events. Audit hooks cannot be removed once installed, but they
are NOT a sandbox on their own (the kernel/job layer is): they matter most on
Android's same-UID fallback and as defence in depth."""
import os
import sys

_BLOCK_PREFIXES = (
    "socket.", "subprocess.", "os.exec", "os.spawn", "os.posix_spawn", "os.fork",
    "os.system", "os.startfile", "os.kill", "os.killpg", "ctypes.", "shutil.",
    "os.remove", "os.rename", "os.mkdir", "os.rmdir", "os.symlink", "os.link",
    "os.chmod", "os.chown", "os.lchown", "os.truncate", "os.mkfifo", "os.mknod",
    "os.utime", "os.setxattr", "os.removexattr", "os.chroot", "os.putenv",
    "os.unsetenv", "pty.", "webbrowser.", "winreg.", "resource.setrlimit",
    "mmap.", "fcntl.", "ftplib.", "smtplib.", "telnetlib.", "urllib.Request",
    "http.client.connect", "sqlite3.connect", "tempfile.", "glob.glob",
    "msvcrt.", "multiprocessing.", "pickle.find_class",
)
# glob/mmap are blocked as a precaution: engines have no use for them.
_BLOCK_IMPORTS = {"ctypes", "_ctypes", "_posixsubprocess", "pty", "winreg"}
_WRITE = 0
for _n in ("O_WRONLY", "O_RDWR", "O_CREAT", "O_TRUNC", "O_APPEND", "O_EXCL"):
    _WRITE |= getattr(os, _n, 0)


def _norm(p):
    return os.path.normcase(os.path.abspath(p))


def install(read_roots):
    roots = tuple(_norm(r) for r in read_roots if r)

    def readable(p):
        if isinstance(p, int):
            return True
        try:
            p = _norm(os.fsdecode(p))
        except Exception:
            return False
        for r in roots:
            if p == r or p.startswith(r + os.sep):
                return True
        return False

    def hook(event, args):
        if event == "open":
            path, _mode, flags = args
            if isinstance(flags, int) and flags & _WRITE:
                raise PermissionError("nova sandbox: write open denied")
            if not readable(path):
                raise PermissionError("nova sandbox: read outside allowed roots denied")
            return
        if event in ("os.listdir", "os.scandir"):
            if args and args[0] is not None and not readable(args[0]):
                raise PermissionError("nova sandbox: listing denied")
            return
        if event == "import":
            if args[0] in _BLOCK_IMPORTS:
                raise ImportError("nova sandbox: import of %s denied" % args[0])
            return
        for pre in _BLOCK_PREFIXES:
            if event.startswith(pre):
                raise PermissionError("nova sandbox: %s denied" % event)

    sys.addaudithook(hook)
