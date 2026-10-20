"""Runs runner.py as a child, plays the host with a canned broker. No network."""
import base64, json, os, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
RUNNER = os.path.join(ROOT, "runtime", "runner.py")
FIX = os.path.join(ROOT, "dev", "fixtures")
PAGE = ('<a class="r" href="magnet:?xt=urn:btih:' + "a" * 40 + '" data-size="1.5 GB" data-s="10" data-l="2">Fixture item 1</a>'
        '<a class="r" href="http://example.test/t2.torrent" data-size="700 MB" data-s="3" data-l="1">Fixture item 2</a>')


def run(name, audit=True, limit_requests=20, timeout=60):
    src = open(os.path.join(FIX, name + ".py")).read()
    for k, v in {"__BASE__": "http://example.test:9", "__PORT__": "9", "__HOME__": os.path.expanduser("~"),
                 "__TMP__": tempfile.gettempdir(), "__SECRET__": os.path.join(os.path.expanduser("~"), ".fake_secret_nova_test")}.items():
        src = src.replace(k, v)
    env = dict(os.environ, NOVA_AUDIT="1" if audit else "0", PYTHONDONTWRITEBYTECODE="1")
    p = subprocess.Popen([sys.executable, "-I", RUNNER], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, env=env)
    p.stdin.write(json.dumps({"op": "search", "module": name, "src": src, "query": "sintel", "cat": "all"}).encode() + b"\n")
    p.stdin.flush()
    out = {"results": [], "http": [], "done": None, "error": None}
    n = 0
    while True:
        line = p.stdout.readline()
        if not line:
            break
        m = json.loads(line)
        if m["op"] == "result":
            out["results"].append(m["r"])
        elif m["op"] == "http":
            out["http"].append(m["url"])
            n += 1
            if n > limit_requests or "other.test" in m["url"] or "127.0.0.1" in m["url"] or m["url"].startswith("file:") or "redirect-foreign" in m["url"]:
                resp = {"op": "http_resp", "id": m["id"], "error": "blocked by host"}
            else:
                body = PAGE if "/search" in m["url"] else "hello"
                resp = {"op": "http_resp", "id": m["id"], "status": 200, "headers": {"Content-Type": "text/html"},
                        "body_b64": base64.b64encode(body.encode()).decode()}
            p.stdin.write(json.dumps(resp).encode() + b"\n")
            p.stdin.flush()
        elif m["op"] == "done":
            out["done"] = m
            break
        elif m["op"] == "error":
            out["error"] = m
            break
    p.stdin.close()
    p.wait(timeout=timeout)
    return out


class T(unittest.TestCase):
    def test_good(self):
        o = run("fx_good")
        self.assertEqual([r["name"] for r in o["results"]], ["Fixture item 1", "Fixture item 2"])
        self.assertEqual(o["results"][0]["size"], int(1.5 * 2**30))
        self.assertEqual(o["done"]["count"], 2)

    def test_urllib(self):
        o = run("fx_urllib")
        self.assertEqual([r["name"] for r in o["results"]], ["urllib:hello", "httpclient:200:hello"])

    def _no_escape(self, name):
        o = run(name)
        names = [r["name"] for r in o["results"]]
        self.assertTrue(names, name)
        self.assertFalse([n for n in names if n.startswith("ESCAPED")], names)

    def test_write(self):
        self._no_escape("fx_write_home")

    def test_socket(self):
        self._no_escape("fx_socket")

    def test_subprocess(self):
        self._no_escape("fx_subprocess")

    def test_foreign(self):
        self._no_escape("fx_foreign")

    def test_secret(self):
        p = os.path.join(os.path.expanduser("~"), ".fake_secret_nova_test")
        open(p, "w").write("TOPSECRET")
        try:
            self._no_escape("fx_read_secret")
        finally:
            os.remove(p)

    def test_flood(self):
        o = run("fx_flood")
        self.assertEqual(o["results"][0]["name"], "ok=20")
        self.assertEqual(len(o["results"]), 500)
        self.assertTrue(o["done"]["truncated"])

    def test_bigprint_runner_survives_discard(self):
        # print() is discarded by the runner; the raw os.write(1) flood goes to
        # stderr (DEVNULL here); the host-side kill is tested in Dart.
        o = run("fx_bigprint")
        self.assertIsNotNone(o["done"])


if __name__ == "__main__":
    unittest.main()
