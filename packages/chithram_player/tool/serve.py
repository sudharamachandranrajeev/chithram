#!/usr/bin/env python3
"""Tiny static file server with HTTP Range support (python's http.server has none).

Usage: serve.py DIR [PORT]  (listens on 127.0.0.1, default port 8000)

Also, for the API fixtures of the e2e and perf runs:
  - A request `<path>?<q>` is answered from the file `<path>@<q>` when it
    exists (q = the query parameters sorted by name and urlencoded, e.g.
    `3/search/movie@language=en-US&query=fixture`), otherwise from `<path>`.
  - Files up to 4 MiB carry an ETag (sha1 of the body); If-None-Match gets 304.
  - `GET /__hits` returns {"total": N, "paths": {path: N}}: the requests served
    since start (not counting /__hits). `POST /__hits/reset` zeroes it.
"""
import hashlib
import json
import mimetypes
import os
import re
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qsl, urlencode

ETAG_MAX = 4 * 1024 * 1024
TYPES = {
    ".m3u8": "application/vnd.apple.mpegurl",
    ".ts": "video/mp2t",
    ".m4a": "audio/mp4",
    ".mp4": "video/mp4",
}


def lookup(root, request_path):
    """The file answering `request_path` (with its query), or None."""
    raw, _, query = request_path.partition("?")
    base = os.path.abspath(os.path.join(root, raw.lstrip("/")))
    candidates = []
    if query:
        q = urlencode(sorted(parse_qsl(query, keep_blank_values=True)))
        candidates.append(base + "@" + q)
    candidates.append(base)
    for path in candidates:
        if path.startswith(root + os.sep) and os.path.isfile(path):
            return path
    return None


class Hits:
    def __init__(self):
        self.lock = threading.Lock()
        self.total = 0
        self.paths = {}

    def add(self, route):
        with self.lock:
            self.total += 1
            self.paths[route] = self.paths.get(route, 0) + 1

    def reset(self):
        with self.lock:
            self.total = 0
            self.paths = {}

    def snapshot(self):
        with self.lock:
            return {"total": self.total, "paths": dict(self.paths)}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    root = os.path.abspath(".")
    hits = None  # a Hits, set per server by make_server

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))

    def _json(self, status, obj):
        body = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _etag(self, path, size):
        if size > ETAG_MAX:
            return None
        with open(path, "rb") as f:
            return '"%s"' % hashlib.sha1(f.read()).hexdigest()

    def _serve(self, head):
        route = self.path.split("?", 1)[0]
        if route == "/__hits":
            self._json(200, self.hits.snapshot())
            return
        self.hits.add(route)
        path = lookup(self.root, self.path)
        if path is None:
            self.send_error(404)
            return
        size = os.path.getsize(path)
        etag = self._etag(path, size)
        if etag and etag in [t.strip() for t in self.headers.get("If-None-Match", "").split(",")]:
            self.send_response(304)
            self.send_header("ETag", etag)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        ext = os.path.splitext(path)[1].lower()
        ctype = TYPES.get(ext) or mimetypes.guess_type(path)[0] or "application/octet-stream"
        start, end, status = 0, size - 1, 200
        m = re.match(r"bytes=(\d*)-(\d*)$", self.headers.get("Range", ""))
        if m and (m.group(1) or m.group(2)):
            if m.group(1):
                start = int(m.group(1))
                end = int(m.group(2)) if m.group(2) else size - 1
            else:
                start = max(0, size - int(m.group(2)))
            end = min(end, size - 1)
            if start > end:
                self.send_response(416)
                self.send_header("Content-Range", "bytes */%d" % size)
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            status = 206
        length = end - start + 1
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Accept-Ranges", "bytes")
        if etag:
            self.send_header("ETag", etag)
        self.send_header("Content-Length", str(length))
        if status == 206:
            self.send_header("Content-Range", "bytes %d-%d/%d" % (start, end, size))
        self.end_headers()
        if head:
            return
        try:
            with open(path, "rb") as f:
                f.seek(start)
                left = length
                while left > 0:
                    chunk = f.read(min(65536, left))
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    left -= len(chunk)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_GET(self):
        self._serve(False)

    def do_HEAD(self):
        self._serve(True)

    def do_POST(self):
        if self.path == "/__hits/reset":
            self.hits.reset()
            self._json(200, self.hits.snapshot())
        else:
            self.send_error(404)


def make_server(root, port=8000):
    """A server for `root` on 127.0.0.1 (port 0 picks a free one)."""
    handler = type("RootHandler", (Handler,), {"root": os.path.abspath(root), "hits": Hits()})
    return ThreadingHTTPServer(("127.0.0.1", port), handler)


if __name__ == "__main__":
    make_server(sys.argv[1] if len(sys.argv) > 1 else ".", int(sys.argv[2]) if len(sys.argv) > 2 else 8000).serve_forever()
