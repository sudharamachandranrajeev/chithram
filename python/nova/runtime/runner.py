"""Chithram nova runner.

Reads NDJSON commands from the host on stdin, runs ONE qBittorrent-style search
plugin (nova3 API: class <id> with url/name/supported_categories and
search(what, cat)) and writes NDJSON to the host on a private copy of fd 1.
All HTTP goes through the host broker (nova_broker); the process is expected to
run inside the native sandbox (seccomp/Landlock, AppContainer, :nova service).

Host -> runner:  {"op":"search","id":"x","src":"<py source>","query":"..","cat":"all"}
                 {"op":"http_resp","id":N,"status":200,"headers":{},"body_b64":"..","error":null}
                 {"op":"quit"}
Runner -> host:  {"op":"meta",...} {"op":"http",...} {"op":"result","r":{..}}
                 {"op":"log","msg":".."} {"op":"error","msg":".."}
                 {"op":"done","count":n,"rejected":m,"truncated":bool}
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


MAX_RESULTS = 500
MAX_STR = 2048
_SCHEMES = ("http://", "https://", "magnet:")


class _Discard:
    """Replacement for sys.stdout/sys.stderr inside plugins."""
    encoding = "utf-8"
    errors = "replace"

    def __init__(self):
        self.count = 0
        self.head = []

    def write(self, s):
        n = len(s)
        self.count += n
        if self.count <= 4096:
            self.head.append(s if isinstance(s, str) else repr(s))
        return n

    def flush(self):
        pass

    def isatty(self):
        return False

    def fileno(self):
        raise OSError("no fileno")


class Runner:
    def __init__(self, transport, audit_roots=None):
        self.t = transport
        self.count = 0
        self.rejected = 0
        self.truncated = False
        self.audit_roots = audit_roots
        self.sizeToBytes = None

    # -- result validation ---------------------------------------------------
    def _s(self, v, limit=MAX_STR):
        if not isinstance(v, str):
            raise ValueError("not a string")
        if len(v) > limit:
            raise ValueError("string too long")
        return v

    def validate(self, d):
        if not isinstance(d, dict):
            raise ValueError("result is not a dict")
        out = {}
        out["link"] = self._s(d["link"])
        if not out["link"].lower().startswith(_SCHEMES):
            raise ValueError("link scheme not allowed")
        out["name"] = self._s(d["name"], 1024)
        out["size"] = int(self.sizeToBytes(d["size"])) if isinstance(d["size"], (int, float, str)) else -1
        for k in ("seeds", "leech"):
            v = d[k]
            if isinstance(v, str) and v.strip().lstrip("-").isdigit():
                v = int(v)
            out[k] = v if isinstance(v, int) and not isinstance(v, bool) else -1
        out["engine_url"] = self._s(d["engine_url"])
        if d.get("desc_link"):
            out["desc_link"] = self._s(d["desc_link"])
            if not out["desc_link"].lower().startswith(_SCHEMES):
                del out["desc_link"]
        if isinstance(d.get("pub_date"), int):
            out["pub_date"] = d["pub_date"]
        return out

    def sink(self, d):
        if self.count >= MAX_RESULTS:
            self.truncated = True
            return
        try:
            r = self.validate(d)
        except Exception:
            self.rejected += 1
            return
        self.count += 1
        self.t.send({"op": "result", "r": r})

    # -- setup -----------------------------------------------------------------
    def prepare(self):
        sys.path.insert(0, HERE)
        import nova_broker
        nova_broker.set_transport(self.t)
        nova_broker.install_shims()
        # preload so audit-blocked imports are not needed later
        import json, re, html, gzip, io, base64, datetime, urllib.parse, urllib.error, xml.etree.ElementTree  # noqa
        import subprocess, threading, tempfile, shutil, random, time, hashlib, ssl, http.cookiejar, collections  # noqa
        import socket  # noqa  (importing is allowed; using it is not)
        import importlib
        for m in ("socks", "novaprinter", "helpers"):  # vendored (patched) copies answer `import helpers` etc.
            sys.modules[m] = importlib.import_module("vendor." + m)
        import novaprinter, helpers
        novaprinter._sink = self.sink
        self.sizeToBytes = novaprinter.anySizeToBytes
        self.helpers = helpers
        roots = self.audit_roots
        if roots is None:
            roots = {sys.prefix, sys.base_prefix, sys.exec_prefix, sys.base_exec_prefix, HERE}
            for p in sys.path:
                if p:
                    roots.add(p)
            if hasattr(sys, "getandroidapilevel"):  # Chaquopy: code and stdlib live under files/chaquopy
                roots.update(["/system", "/apex", "/vendor"])
            if os.name == "posix":
                roots.update(["/usr/share/zoneinfo", "/usr/lib", "/lib", "/lib64", "/usr/lib64"])
        if os.environ.get("NOVA_AUDIT", "1") != "0":  # "0" only for kernel-layer-only CI runs
            import nova_audit
            nova_audit.install(roots)

    # -- commands --------------------------------------------------------------
    def search(self, msg):
        name = msg.get("module") or msg.get("engine") or "engine"
        src = msg["src"]
        ns = {"__name__": "engines." + name, "__builtins__": __builtins__}
        exec(compile(src, "<engine:%s>" % name, "exec"), ns)
        cls = ns.get(name)
        if cls is None:
            for v in ns.values():
                if isinstance(v, type) and hasattr(v, "search") and v.__module__ == ns["__name__"]:
                    cls = v
                    break
        if cls is None:
            raise RuntimeError("no engine class %r in plugin" % name)
        eng = cls()
        self.t.send({"op": "meta", "name": str(getattr(eng, "name", name))[:128],
                     "url": str(getattr(eng, "url", ""))[:512],
                     "categories": sorted(map(str, getattr(eng, "supported_categories", {}) or {}))[:32]})
        cat = msg.get("cat") or "all"
        eng.search(msg["query"], cat)

    def download(self, msg):
        name = msg.get("module") or "engine"
        ns = {"__name__": "engines." + name, "__builtins__": __builtins__}
        exec(compile(msg["src"], "<engine:%s>" % name, "exec"), ns)
        eng = ns[name]()
        eng.download_torrent(msg["url"])
        dl = self.helpers._downloads
        self.t.send({"op": "downloaded", "keys": sorted(dl), "sizes": [len(v) for v in dl.values()]})

    def serve(self):
        out_err = _Discard()
        out_std = _Discard()
        sys.stdout = sys.__stdout__ = out_std
        sys.stderr = sys.__stderr__ = out_err
        while True:
            msg = self.t.recv()
            if msg is None or msg.get("op") == "quit":
                return 0
            op = msg.get("op")
            try:
                if op == "search":
                    self.count = self.rejected = 0
                    self.truncated = False
                    self.search(msg)
                    self.t.send({"op": "done", "count": self.count, "rejected": self.rejected,
                                 "truncated": self.truncated, "stdout_bytes": out_std.count})
                elif op == "download":
                    self.download(msg)
                    self.t.send({"op": "done", "count": 0})
                elif op == "ping":
                    self.t.send({"op": "pong", "py": sys.version.split()[0]})
                else:
                    self.t.send({"op": "error", "msg": "unknown op"})
            except SystemExit:
                return 3
            except BaseException as e:  # noqa
                try:
                    self.t.send({"op": "error", "msg": ("%s: %s" % (type(e).__name__, e))[:2000],
                                 "stderr": "".join(out_err.head)[:1000]})
                except Exception:
                    return 4


def main():
    sys.path.insert(0, HERE)
    import nova_broker
    # Private protocol fds: stdin as-is, a dup of stdout. Plugin writes to fd 1
    # then land on stderr (host drains and caps it), never on the protocol.
    proto_out = os.dup(1)
    os.dup2(2, 1)
    t = nova_broker.StdioTransport(0, proto_out)
    r = Runner(t)
    try:
        r.prepare()
    except BaseException as e:  # noqa
        t.send({"op": "error", "msg": "runner setup failed: %s: %s" % (type(e).__name__, e)})
        return 5
    return r.serve()


if __name__ == "__main__":
    sys.exit(main())
