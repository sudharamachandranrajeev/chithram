"""Runner-side broker: every network request from a plugin becomes an NDJSON
message to the host. The sandboxed process itself has no network."""
import base64
import io
import itertools
import json
import threading
import urllib.error
import urllib.parse
import urllib.request
import http.client
import email.message

MAX_LINE = 64 * 1024            # bytes per line the runner may write
MAX_STDOUT = 4 * 1024 * 1024    # bytes in total the runner may write
MAX_IN_LINE = 8 * 1024 * 1024   # bytes per line the host may send
MAX_BODY = 5 * 1024 * 1024

_transport = None
_ids = itertools.count(1)
_lock = threading.Lock()
requests_made = 0


class BrokerDenied(OSError):
    pass


def set_transport(t):
    global _transport
    _transport = t


class StdioTransport:
    """NDJSON over a private copy of fd 1 (out) and fd 0 (in)."""

    def __init__(self, in_fd, out_fd):
        self._in = open(in_fd, "rb", buffering=1 << 16, closefd=False)
        self._out = open(out_fd, "wb", buffering=0, closefd=False)
        self.written = 0

    def send(self, obj):
        data = json.dumps(obj, separators=(",", ":"), ensure_ascii=True).encode() + b"\n"
        if len(data) > MAX_LINE:
            raise ValueError("line over %d bytes" % MAX_LINE)
        if self.written + len(data) > MAX_STDOUT:
            raise ValueError("stdout budget (%d bytes) exhausted" % MAX_STDOUT)
        self.written += len(data)
        self._out.write(data)

    def recv(self):
        line = self._in.readline(MAX_IN_LINE + 1)
        if not line:
            return None
        if len(line) > MAX_IN_LINE:
            raise ValueError("input line too long")
        return json.loads(line)


def _b64(b):
    return base64.b64encode(b).decode("ascii")


class Response(io.BytesIO):
    """Minimal urllib/http.client response look-alike."""

    def __init__(self, status, headers, body, url, reason=""):
        super().__init__(body)
        self.status = self.code = status
        self.reason = self.msg = reason
        self.url = url
        self.headers = email.message.Message()
        for k, v in headers.items():
            self.headers[k] = v
        self.version = 11

    def getcode(self):
        return self.status

    def geturl(self):
        return self.url

    def info(self):
        return self.headers

    def getheader(self, name, default=None):
        v = self.headers.get(name)
        return default if v is None else v

    def getheaders(self):
        return list(self.headers.items())


def fetch(method, url, headers=None, data=None, timeout=None):
    """Ask the host. Returns Response. Raises BrokerDenied on host refusal."""
    global requests_made
    if isinstance(data, str):
        data = data.encode()
    if isinstance(data, dict):
        data = urllib.parse.urlencode(data).encode()
    with _lock:
        requests_made += 1
        rid = next(_ids)
        _transport.send({
            "op": "http", "id": rid, "method": method, "url": url,
            "headers": {str(k): str(v) for k, v in (headers or {}).items()},
            "body_b64": _b64(data) if data else None,
        })
        while True:
            msg = _transport.recv()
            if msg is None or msg.get("op") == "cancel":
                raise SystemExit(3)
            if msg.get("op") == "http_resp" and msg.get("id") == rid:
                break
    if msg.get("error"):
        raise BrokerDenied(msg["error"])
    body = base64.b64decode(msg.get("body_b64") or "")
    return Response(msg["status"], msg.get("headers") or {}, body, msg.get("url") or url,
                    msg.get("reason") or "")


# ---- shims that replace urllib.request / http.client ----------------------

def _do(req, data=None, timeout=None):
    if isinstance(req, str):
        req = urllib.request.Request(req)
    if data is None:
        data = req.data
    hdrs = dict(req.header_items())
    method = req.get_method() if data is None else "POST"
    try:
        resp = fetch(method, req.full_url, hdrs, data, timeout)
    except BrokerDenied as e:
        raise urllib.error.URLError(str(e))
    if resp.status >= 400:
        raise urllib.error.HTTPError(req.full_url, resp.status, resp.reason, resp.headers, resp)
    return resp


class _Opener:
    def __init__(self, *handlers):
        self.addheaders = [("User-agent", "Python-urllib")]

    def open(self, fullurl, data=None, timeout=None):
        req = fullurl if isinstance(fullurl, urllib.request.Request) else urllib.request.Request(fullurl, data)
        for k, v in self.addheaders:
            if not req.has_header(k):
                req.add_header(k, v)
        return _do(req, data, timeout)


def _urlretrieve(*a, **k):
    raise PermissionError("urlretrieve: writing files is not allowed in the nova sandbox")


class _Conn:
    scheme = "http"
    default_port = 80

    def __init__(self, host, port=None, timeout=None, **kw):
        self.host, self.port = host, port
        self._resp = None

    def set_debuglevel(self, n):
        pass

    def request(self, method, url, body=None, headers=None, **kw):
        netloc = self.host if not self.port or self.port == self.default_port else "%s:%s" % (self.host, self.port)
        full = url if "://" in url else "%s://%s%s" % (self.scheme, netloc, url)
        try:
            self._resp = fetch(method, full, headers or {}, body)
        except BrokerDenied as e:
            raise ConnectionRefusedError(str(e))

    def getresponse(self):
        return self._resp

    def close(self):
        pass


class _HTTPConn(_Conn):
    pass


class _HTTPSConn(_Conn):
    scheme = "https"
    default_port = 443

    def __init__(self, host, port=None, key_file=None, cert_file=None, timeout=None, context=None, **kw):
        super().__init__(host, port, timeout)


def install_shims():
    urllib.request.urlopen = lambda url, data=None, timeout=None, **kw: _do(url, data, timeout)
    urllib.request.build_opener = lambda *h: _Opener(*h)
    urllib.request.install_opener = lambda o: None
    urllib.request.urlretrieve = _urlretrieve
    http.client.HTTPConnection = _HTTPConn
    http.client.HTTPSConnection = _HTTPSConn
