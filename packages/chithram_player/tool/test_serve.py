"""Tests for serve.py: `python3 -m unittest packages/chithram_player/tool/test_serve.py`."""
import hashlib
import json
import os
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import serve  # noqa: E402


class ServeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.TemporaryDirectory()
        root = cls.dir.name
        os.makedirs(os.path.join(root, "3", "movie"))
        cls.write("3/movie/popular", '{"results":[1]}')
        cls.write("3/movie/popular@language=en-US&page=2", '{"results":[2]}')
        cls.write("plain.txt", "hello")
        cls.write("big.bin", "x" * (serve.ETAG_MAX + 1))
        cls.server = serve.make_server(root, 0)
        cls.base = "http://127.0.0.1:%d" % cls.server.server_address[1]
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.dir.cleanup()

    @classmethod
    def write(cls, rel, text):
        with open(os.path.join(cls.dir.name, rel), "w") as f:
            f.write(text)

    def get(self, path, headers=None, method="GET"):
        req = urllib.request.Request(self.base + path, headers=headers or {}, method=method)
        try:
            with urllib.request.urlopen(req) as r:
                return r.status, dict(r.headers), r.read()
        except urllib.error.HTTPError as e:
            return e.code, dict(e.headers), e.read()

    def hits(self):
        return json.loads(self.get("/__hits")[2])

    def setUp(self):
        self.get("/__hits/reset", method="POST")

    def test_plain_path_and_unknown_query_fall_back_to_the_plain_file(self):
        self.assertEqual(self.get("/3/movie/popular")[2], b'{"results":[1]}')
        self.assertEqual(self.get("/3/movie/popular?page=1")[2], b'{"results":[1]}')

    def test_query_maps_to_sorted_urlencoded_variant(self):
        # Parameter order in the request does not matter.
        self.assertEqual(self.get("/3/movie/popular?page=2&language=en-US")[2], b'{"results":[2]}')
        self.assertEqual(self.get("/3/movie/popular?language=en-US&page=2")[2], b'{"results":[2]}')

    def test_missing_is_404_and_traversal_is_refused(self):
        self.assertEqual(self.get("/nope")[0], 404)
        self.assertEqual(self.get("/../etc/passwd")[0], 404)
        self.assertEqual(self.get("/3/movie/popular?x=../../secret")[2], b'{"results":[1]}')

    def test_etag_and_304(self):
        status, headers, body = self.get("/plain.txt")
        etag = '"%s"' % hashlib.sha1(b"hello").hexdigest()
        self.assertEqual((status, headers["ETag"], body), (200, etag, b"hello"))
        status, headers, body = self.get("/plain.txt", {"If-None-Match": etag})
        self.assertEqual((status, body), (304, b""))
        self.assertEqual(headers["ETag"], etag)
        self.assertEqual(self.get("/plain.txt", {"If-None-Match": '"other"'})[0], 200)
        # The variant has its own ETag.
        self.assertNotEqual(self.get("/3/movie/popular?language=en-US&page=2")[1]["ETag"],
                            self.get("/3/movie/popular")[1]["ETag"])

    def test_big_files_have_no_etag_and_still_serve_ranges(self):
        status, headers, body = self.get("/big.bin", {"Range": "bytes=0-3"})
        self.assertEqual((status, body), (206, b"xxxx"))
        self.assertNotIn("ETag", headers)

    def test_hits_counts_requests_but_not_itself(self):
        self.assertEqual(self.hits(), {"total": 0, "paths": {}})
        self.get("/plain.txt")
        self.get("/plain.txt", {"If-None-Match": '"x"'})
        self.get("/3/movie/popular?page=2")
        self.get("/missing")
        h = self.hits()
        self.assertEqual(h["total"], 4)
        self.assertEqual(h["paths"]["/plain.txt"], 2)
        self.assertEqual(h["paths"]["/3/movie/popular"], 1)
        self.assertEqual(self.hits()["total"], 4)  # reading did not count

    def test_servers_do_not_share_counters(self):
        other = serve.make_server(self.dir.name, 0)
        threading.Thread(target=other.serve_forever, daemon=True).start()
        self.addCleanup(other.shutdown)
        self.get("/plain.txt")
        with urllib.request.urlopen("http://127.0.0.1:%d/__hits" % other.server_address[1]) as r:
            self.assertEqual(json.loads(r.read())["total"], 0)


if __name__ == "__main__":
    unittest.main()
